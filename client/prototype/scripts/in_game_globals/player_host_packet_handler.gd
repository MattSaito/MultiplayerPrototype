extends Node

# player signal
signal player_movement_signal(data: PackedByteArray)
signal player_text_signal(data: PackedByteArray)
signal player_change_scene_signal(peer: ENetPacketPeer, data: PackedByteArray)
signal player_minigame_answer_signal(data: PackedByteArray)

# host signal
signal host_movement_signal(data: PackedByteArray)
signal host_text_signal(data: PackedByteArray)
signal host_change_scene_signal(data: PackedByteArray)
signal host_force_scene_signal(data: PackedByteArray)
signal host_minigame_assign_signal(data: PackedByteArray)
signal host_minigame_progress_signal(data: PackedByteArray)
signal host_minigame_grade_signal(data: PackedByteArray)

var is_host: bool

# Reconexão (host): mapa peer -> my_id alimentado pelo PLAYER_HELLO, e lista
# de ids que caíram na Layer 2 aguardando volta.
var peer_by_id: Dictionary = {}
var disconnected_ids: Array[int] = []
signal player_reconnected(player_id: int)

# Conecta APENAS um lado por instância: host OU player, nunca os dois.
# Se conectasse ambos, cada pacote dispararia o handler duas vezes
# (host_packet_handler entende SCENE_FORCE_PACKET, player_packet_handler não).
func setup_packet_handler() -> void:
	peer_by_id.clear()
	disconnected_ids.clear()
	is_host = GamePacketHandler.is_host
	if is_host:
		GamePacketHandler.from_player_packet.connect(player_packet_handler)
	else :
		GamePacketHandler.from_host_packet.connect(host_packet_handler)

func player_packet_handler(_peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var packet_type = data.decode_u8(0)
	match packet_type:
		InGameTypeClass.PACKET_TYPE.PLAYER_PACKET:
			player_movement_signal.emit(data)
		InGameTypeClass.PACKET_TYPE.PLAYER_HELLO:
			_handle_player_hello(_peer, data)
		InGameTypeClass.PACKET_TYPE.TEXT_PACKET:
			player_text_signal.emit(data)
		InGameTypeClass.PACKET_TYPE.SCENE_SYNC_PACKET:
			player_change_scene_signal.emit(_peer, data)
		InGameTypeClass.PACKET_TYPE.MINIGAME_ANSWER:
			player_minigame_answer_signal.emit(data)

func _handle_player_hello(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var hello: PlayerHelloPkt = PlayerHelloPkt.create_from_data(data)
	peer.set_meta("game_id", hello.player_id)
	peer_by_id[hello.player_id] = peer
	if hello.player_id in disconnected_ids:
		disconnected_ids.erase(hello.player_id)
		print("(Host) RECONEXÃO de player ", hello.player_id)
		player_reconnected.emit(hello.player_id)
	else:
		print("(Host) PLAYER_HELLO (primeira conexão) de ", hello.player_id)

func host_packet_handler(data: PackedByteArray) -> void:
	var packet_type = data.decode_u8(0)
	match packet_type:
		InGameTypeClass.PACKET_TYPE.PLAYER_PACKET:
			host_movement_signal.emit(data)
		InGameTypeClass.PACKET_TYPE.TEXT_PACKET:
			host_text_signal.emit(data)
		InGameTypeClass.PACKET_TYPE.SCENE_SYNC_PACKET:
			host_change_scene_signal.emit(data)
		InGameTypeClass.PACKET_TYPE.SCENE_FORCE_PACKET:
			host_force_scene_signal.emit(data)
		InGameTypeClass.PACKET_TYPE.MINIGAME_ASSIGN:
			host_minigame_assign_signal.emit(data)
		InGameTypeClass.PACKET_TYPE.MINIGAME_PROGRESS:
			host_minigame_progress_signal.emit(data)
		InGameTypeClass.PACKET_TYPE.MINIGAME_GRADE_RESULT:
			host_minigame_grade_signal.emit(data)
