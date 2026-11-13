class_name ENetEndpoint
extends NetEndpoint
## The real network: UDP through Godot's ENet (low-level ENetConnection, no MultiplayerAPI / RPC).
## Channel 0 carries reliable packets, channel 1 unreliable ones.

const CH_RELIABLE := 0
const CH_UNRELIABLE := 1
const MAX_EVENTS_PER_POLL := 512   # a flood cannot keep one frame busy forever

var host := ENetConnection.new()
var _peers := {}                   # id -> ENetPacketPeer
var _next_id := 1


## Server: listen on UDP `port` on all interfaces. Returns an Error code.
func listen(port: int, max_peers: int) -> int:
	return host.create_host_bound("*", port, max_peers, 2)


## Client: connect to `address:port` (the result arrives as a CONNECT or DISCONNECT event). Returns an Error code.
func connect_to(address: String, port: int) -> int:
	var err := host.create_host(1, 2)
	if err != OK:
		return err
	var peer := host.connect_to_host(address, port, 2)
	if peer == null:
		return ERR_CANT_CONNECT
	_register(peer)
	return OK


func _register(peer: ENetPacketPeer) -> int:
	if peer.has_meta("nid"):
		return peer.get_meta("nid")
	var id := _next_id
	_next_id += 1
	peer.set_meta("nid", id)
	_peers[id] = peer
	return id


func poll() -> Array:
	var out: Array = []
	for _i in MAX_EVENTS_PER_POLL:
		var r: Array = host.service(0)
		var type: int = r[0]
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = r[1]
		if peer == null:
			continue
		match type:
			ENetConnection.EVENT_CONNECT:
				out.append(NetEndpoint.event(Kind.CONNECT, _register(peer)))
			ENetConnection.EVENT_DISCONNECT:
				var id: int = peer.get_meta("nid", -1)
				if id >= 0:
					_peers.erase(id)
					out.append(NetEndpoint.event(Kind.DISCONNECT, id))
			ENetConnection.EVENT_RECEIVE:
				var id: int = peer.get_meta("nid", -1)
				while peer.get_available_packet_count() > 0:
					var data := peer.get_packet()
					if id >= 0:
						out.append(NetEndpoint.event(Kind.PACKET, id, data, int(r[3]) == CH_RELIABLE))
	return out


func send(peer: int, data: PackedByteArray, reliable: bool) -> void:
	var p: ENetPacketPeer = _peers.get(peer)
	if p == null or p.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return
	if reliable:
		p.send(CH_RELIABLE, data, ENetPacketPeer.FLAG_RELIABLE)
	else:
		# Without the fragment flag ENet turns an unreliable packet bigger than the MTU into a reliable one.
		p.send(CH_UNRELIABLE, data, ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT)


func flush() -> void:
	host.flush()


func disconnect_peer(peer: int) -> void:
	var p: ENetPacketPeer = _peers.get(peer)
	if p != null:
		p.peer_disconnect_later()


func close() -> void:
	for id: int in _peers:
		(_peers[id] as ENetPacketPeer).peer_disconnect_now()
	host.flush()
	_peers.clear()
	host.destroy()
