# Arquitetura da Reconexão — Cyber Resistance

---

## 1. Contexto: duas camadas de rede

O jogo tem **duas conexões ENet independentes** (enums, autoloads e sinais não
se cruzam):

- **Layer 1 — Lobby / Servidor central.** Um servidor fixo na porta `42069`.
  É a **fonte da verdade** sobre quem está em cada sala. Estável por hipótese.
- **Layer 2 — Jogo (host da sala ↔ jogadores).** Cada sala tem um **host** (que
  é um cliente comum, escolhido por `my_id % 4 == 0`) que abre um `ENetConnection`
  próprio numa porta sorteada (`room_port`). Os demais jogadores (*joiners*)
  conectam nesse host. É o **link frágil** — o alvo da reconexão.

> A reconexão implementada trata **só a Layer 2** (joiner ↔ host). O vínculo com
> o servidor central (Layer 1) **não** tem reconexão; sua queda é tratada como
> saída definitiva (limpeza no servidor).

`my_id` (0–3, atribuído pelo servidor central) é a **identidade estável** do
jogador nas duas camadas.

---

## 2. Componentes

### Cliente joiner (o que cai e reconecta)
| Componente (autoload/script) | Papel na reconexão |
|---|---|
| `ProtNetworkHandler` | Conexão **Layer 1** com o servidor central (fica viva no blip). |
| `ClientPacketHandler` | Handler da Layer 1. Cacheia ip/porta do host; trata `QUIT_ROOM`; dispara resync no host. |
| `GamePacketHandler` | Conexão **Layer 2**. **Detecta a queda e roda o loop de reconexão.** |
| `PlayerHostPacketHandler` | Demux dos pacotes Layer 2 (roteia para sinais). |
| `MinigameSession` | Cena do minigame; aplica assign/progress na volta. |
| `ReconnectOverlay` | Overlay global "reconectando…" (autoload CanvasLayer). |

### Cliente host da sala 
| Componente | Papel |
|---|---|
| `GamePacketHandler` (is_host) | Aceita conexões Layer 2; detecta peer que caiu. |
| `PlayerHostPacketHandler` (host) | Mantém `peer_by_id` e `disconnected_ids`; emite `player_reconnected`. |
| `ClientPacketHandler` (host) | Ao reconectar um peer, reenvia a **cena** (`SceneForcePacket`). |
| `MinigameSession` (host) | Ao reconectar, reenvia **assign + progress** da dupla. |

### Servidor central
| Componente | Papel |
|---|---|
| `ProtNetworkHandler` (server) | Conexão Layer 1; detecta `EVENT_DISCONNECT` de peers. |
| `ServerPacketHandler` | `handle_peer_drop`: dissolve sala (se host) ou remove membro. |
| `RoomStorage` | Estado de cada sala (host_peer, jogadores, ids, nomes). |

---

## 3. Estado / dados 

**No host (`PlayerHostPacketHandler`):**
- `peer_by_id: Dictionary` — `my_id → ENetPacketPeer` (atualizado pelo `PLAYER_HELLO`).
- `disconnected_ids: Array[int]` — ids que caíram na Layer 2 aguardando voltar.
- `signal player_reconnected(player_id)` — disparado quando um id caído reaparece.

**No joiner (`GamePacketHandler`):**
- `reconnecting: bool`, `_reconnect_timer: Timer`, `_reconnect_start_msec: int`
- `_reconnect_ip/_reconnect_port` — destino do host (cópia do cache).

**No joiner (`ClientPacketHandler`):**
- `reconnect_host_ip / reconnect_host_port` — **cache** do host, gravado no join.
- `pending_minigame_assign` — buffer da atribuição do minigame.
- `pending_minigame_progress_by_team: Dictionary` — `team → progress` (por dupla,
  para não haver corrida entre times durante o resync).

**No host (`MinigameSession`):**
- `host_team_state: Array` — estado autoritativo das 2 duplas (membros, quem é
  QUIZ agora, pergunta atual, terminou).

**Parâmetros (constantes):**
- `RECONNECT_WINDOW_S = 30.0` — janela total de tentativas.
- `RECONNECT_INTERVAL_S = 2.0` — intervalo entre tentativas.
- Timeout ENet Layer 2: `set_timeout(0, 10000, 10000)` → detecção em ~10 s.

---

## 4. Fluxos

### Fluxo A — Conexão inicial (base da reconexão)
Lifelines: **Joiner.GamePacketHandler**, **Host.PlayerHostPacketHandler**

1. Joiner conecta na Layer 2 (`EVENT_CONNECT`) → `player_connection()`.
2. Joiner envia **`PLAYER_HELLO(my_id)`** ao host.
3. Host recebe → `_handle_player_hello`: grava `peer_by_id[my_id] = peer` e
   `peer.set_meta("game_id", my_id)`.
4. Como o id **não** está em `disconnected_ids` → é "primeira conexão" (só loga).

### Fluxo B — Queda da Layer 2 + loop de reconexão (caminho feliz)
Lifelines: **Joiner.GamePacketHandler**, **ReconnectOverlay**, **Host**

1. Link Layer 2 cai. Após ~10 s o ENet emite `EVENT_DISCONNECT`.
2. **Host:** `peer_disconnected` → adiciona `game_id` a `disconnected_ids`
   (marca "caído, aguardando volta"). *(A Layer 1 do host segue viva.)*
3. **Joiner:** `host_disconnection()` → `_start_reconnect()`:
   - lê `reconnect_host_ip/port` do cache;
   - `ReconnectOverlay.show_message("Conexão perdida — reconectando…")`;
   - arma `Timer` (a cada `RECONNECT_INTERVAL_S`) e marca `reconnecting = true`.
4. A cada tick, `_attempt_reconnect()`:
   - se passou de `RECONNECT_WINDOW_S` → **desiste** (Fluxo D);
   - senão, se não há conexão em andamento → `reconnect_to_host(ip, port)`
     (recria o `ENetConnection`, sem re-rodar setup).
5. Ao ter sucesso (`EVENT_CONNECT`) → `player_connection()`:
   - reenvia **`PLAYER_HELLO(my_id)`**;
   - `_finish_reconnect()` → esconde overlay, para o timer, `reconnecting = false`.
6. **Host:** recebe `PLAYER_HELLO`; agora o id **está** em `disconnected_ids` →
   é **reconexão**: remove da lista e emite **`player_reconnected(my_id)`**.
7. → dispara o Fluxo C (resync).

### Fluxo C — Resync de cena e minigame na volta
Lifelines: **Host.ClientPacketHandler**, **Host.MinigameSession**, **Joiner**

Disparado por `player_reconnected(player_id)` no host (dois ouvintes):

1. `ClientPacketHandler.on_player_reconnected` → envia **`SceneForcePacket(cena)`**
   dirigido ao peer (usa `players_scenes[player_id]`).
2. `MinigameSession._on_host_player_reconnected` (só se em minigame) → acha a
   dupla em `host_team_state` e envia ao peer:
   - **`MinigameAssignPkt`** (dupla, papel inicial, parceiro);
   - **`MinigameProgressPkt`** (pergunta atual, quem é QUIZ agora, terminou).
3. **Joiner:** `SceneForcePacket` → recarrega a cena (deferido). Ao montar, a
   `MinigameSession` lê `pending_minigame_assign` + `pending_minigame_progress_by_team`
   e cai direto na pergunta/papel **correntes** (não volta à pergunta 0).

> Ordem garantida: os pacotes vão pelo mesmo canal confiável, `SceneForce` antes
> de `Assign`/`Progress`. O buffer por-dupla evita corrida com o outro time.

### Fluxo D — Desistência (estourou 30 s)
Lifelines: **Joiner.GamePacketHandler**, **Servidor**, **Joiner.ClientPacketHandler**

1. `_attempt_reconnect` detecta janela esgotada → `_give_up_reconnect()`:
   - esconde overlay, para o timer, `reconnecting = false`;
   - envia **`QuitRequestClass(room_id)`** ao servidor central (Layer 1).
2. Servidor → `quit_room_request` → responde **`QUIT_ROOM`** ao joiner.
3. Joiner: `packet_handler(QUIT_ROOM)` → `cancel_reconnect()` (no-op), limpa
   estado e **volta ao lobby** (`multiplayer.tscn`).

### Fluxo E — Host cai (dissolução pela Layer 1)
Lifelines: **Servidor.ProtNetworkHandler**, **Servidor.ServerPacketHandler**, **Joiners**

1. Host some (fecha/crash). O servidor central detecta `EVENT_DISCONNECT`.
2. `network_handler.peer_disconnected` → `ServerPacketHandler.handle_peer_drop(peer)`.
3. `handle_peer_drop` vê que o peer é `host_peer` de uma sala → **dissolve**:
   - envia **`QUIT_ROOM`** a todos os membros;
   - apaga a sala e libera o id.
4. Cada joiner: `packet_handler(QUIT_ROOM)` → `cancel_reconnect()` **cancela o
   loop** (se estava tentando) e volta ao lobby.

> **Desambiguação (chave da arquitetura):** o joiner não distingue "host caiu"
> de "só a Layer 2 piscou" apenas pela Layer 2. Quem resolve é a **Layer 1**: se
> o host caiu de verdade, o servidor manda `QUIT_ROOM` e a reconexão é cancelada;
> se foi só um blip, nenhum `QUIT_ROOM` chega e a reconexão conclui.

### Fluxo F — Membro cai (não é host)
1. Servidor detecta `EVENT_DISCONNECT` do membro → `handle_peer_drop`.
2. Peer não é host → remove da sala e envia **`HAS_QUITTED`** aos demais.
3. A sala continua; os outros despawnam o avatar do que saiu.
