class_name LoopbackHub
extends RefCounted
## In-memory network for tests: one server endpoint, any number of client endpoints, a fixed one-way delay
## and random loss of unreliable packets. Time only moves when the test calls advance().

var now_ms := 0.0
var delay_ms := 0.0
var loss_pct := 0.0
var rng := RandomNumberGenerator.new()
var server: LoopbackEndpoint
var _clients: Dictionary = {}   # client peer id (as the server sees it) -> LoopbackEndpoint
var _next_id := 1


func _init(seed_value := 1) -> void:
	rng.seed = seed_value
	server = LoopbackEndpoint.new(self, 0)


func advance(ms: float) -> void:
	now_ms += ms


## A new client; the connect event reaches both sides after the delay.
func connect_client() -> LoopbackEndpoint:
	var c := LoopbackEndpoint.new(self, _next_id)
	_clients[_next_id] = c
	_next_id += 1
	var at := now_ms + delay_ms
	c._inbox.append({"at": at, "ev": NetEndpoint.event(NetEndpoint.Kind.CONNECT, 1)})
	server._inbox.append({"at": at, "ev": NetEndpoint.event(NetEndpoint.Kind.CONNECT, c.id)})
	return c


func _route(from: LoopbackEndpoint, peer: int, data: PackedByteArray, reliable: bool) -> void:
	if not reliable and rng.randf() * 100.0 < loss_pct:
		return
	var at := now_ms + delay_ms
	if from == server:
		var c: LoopbackEndpoint = _clients.get(peer)
		if c != null:
			c._inbox.append({"at": at, "ev": NetEndpoint.event(NetEndpoint.Kind.PACKET, 1, data, reliable)})
	elif _clients.has(from.id):
		server._inbox.append({"at": at, "ev": NetEndpoint.event(NetEndpoint.Kind.PACKET, from.id, data, reliable)})


func _hang_up(from: LoopbackEndpoint, peer: int) -> void:
	var at := now_ms + delay_ms
	if from == server:
		var c: LoopbackEndpoint = _clients.get(peer)
		if c == null:
			return
		c._inbox.append({"at": at, "ev": NetEndpoint.event(NetEndpoint.Kind.DISCONNECT, 1)})
		server._inbox.append({"at": at, "ev": NetEndpoint.event(NetEndpoint.Kind.DISCONNECT, peer)})
		_clients.erase(peer)
	else:
		server._inbox.append({"at": at, "ev": NetEndpoint.event(NetEndpoint.Kind.DISCONNECT, from.id)})
		_clients.erase(from.id)


class LoopbackEndpoint extends NetEndpoint:
	var id: int
	var _hub_ref: WeakRef   # weak: the hub owns its endpoints, a strong link back would be a leaking cycle
	var hub: LoopbackHub:
		get:
			return _hub_ref.get_ref()
	var _inbox: Array = []

	func _init(h: LoopbackHub, endpoint_id: int) -> void:
		_hub_ref = weakref(h)
		id = endpoint_id

	func poll() -> Array:
		var out: Array = []
		var rest: Array = []
		for item: Dictionary in _inbox:
			if item["at"] <= hub.now_ms:
				out.append(item["ev"])
			else:
				rest.append(item)
		_inbox = rest
		return out

	func send(peer: int, data: PackedByteArray, reliable: bool) -> void:
		hub._route(self, peer, data, reliable)

	func disconnect_peer(peer: int) -> void:
		hub._hang_up(self, peer)

	func close() -> void:
		if self != hub.server:
			hub._hang_up(self, 1)
