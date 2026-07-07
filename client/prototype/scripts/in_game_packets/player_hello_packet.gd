class_name PlayerHelloPkt extends InGameTypeClass

# Player -> Host. Enviado logo após o EVENT_CONNECT, tanto na primeira
# conexão quanto na reconexão. Dá ao host um mapa explícito peer -> my_id,
# que é a base da lógica de reconexão (detecção da volta + resync dirigido).

var player_id: int

static func create(_player_id: int) -> PlayerHelloPkt:
	var new_packet: PlayerHelloPkt = PlayerHelloPkt.new(PACKET_TYPE.PLAYER_HELLO, ENetPacketPeer.FLAG_RELIABLE)
	new_packet.player_id = _player_id
	return new_packet

static func create_from_data(data: PackedByteArray) -> PlayerHelloPkt:
	var new_packet: PlayerHelloPkt = PlayerHelloPkt.new(PACKET_TYPE.PLAYER_HELLO, ENetPacketPeer.FLAG_RELIABLE)
	new_packet.decode(data)
	return new_packet

func encode() -> PackedByteArray:
	var data: PackedByteArray = super.encode()
	data.append(player_id)
	return data

func decode(data: PackedByteArray) -> void:
	super.decode(data)
	player_id = data.decode_u8(1)
