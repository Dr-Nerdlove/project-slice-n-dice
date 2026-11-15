class_name LocalHost
extends RefCounted
## A phone (or PC) hosting a match itself: an embedded server plus the announcement for the "found games" list.
## No nodes: the owner calls `process(delta)` every frame. The host's own game connects to it like everybody
## else, through 127.0.0.1.

const ADDRESS_REFRESH_MS := 2000   # the network may change while hosting (a hotspot is switched on)

var core: ServerCore
var port := NetProto.DEFAULT_PORT
## Where the announcement goes and to which extra addresses (tests change these before `start`).
var beacon_port := LanBeacon.PORT
var beacon_targets: Array = []

var _endpoint: ENetEndpoint
var _beacon: LanBeacon
var _address := ""
var _next_address_ms := 0


## Starts listening on UDP `port`. The match runs on a COPY of `cfg` (the owner passes the fixed Play values, never
## the tuned ones), later changes do not reach it; clients cannot change modifiers (`accept_client_mods`). Returns an Error code.
func start(cfg: Config, with_bots: bool, game_port := NetProto.DEFAULT_PORT, seed_value := 20260101) -> int:
	stop()
	var copy := Config.new()
	copy.from_dict(cfg.to_dict())
	# A probe first: a failing ENet listen prints an engine error, a failing plain bind does not.
	var probe := PacketPeerUDP.new()
	var taken := probe.bind(game_port, "*") != OK
	probe.close()
	if taken:
		return ERR_ALREADY_IN_USE
	var ep := ENetEndpoint.new()
	var err := ep.listen(game_port, ServerCore.MAX_PENDING)
	if err != OK:
		return err
	_endpoint = ep
	port = game_port
	core = ServerCore.new(copy, ep, seed_value, with_bots)
	core.accept_client_mods = false   # a local match is a real game: fixed values, no modifiers from the clients
	_beacon = LanBeacon.new()
	_beacon.start_announcing(beacon_port, beacon_targets)
	_address = LanCode.pick_local_address(IP.get_local_interfaces())
	_next_address_ms = Time.get_ticks_msec() + ADDRESS_REFRESH_MS
	return OK


func is_running() -> bool:
	return core != null


## One frame: network in, the fixed 60 Hz ticks, the announcement.
func process(delta: float) -> void:
	if core == null:
		return
	core.run(delta)
	var now := Time.get_ticks_msec()
	if now >= _next_address_ms:
		_next_address_ms = now + ADDRESS_REFRESH_MS
		_address = LanCode.pick_local_address(IP.get_local_interfaces())
	_beacon.announce(now, core.players_online(), Config.NUM_PLAYERS, port)


func players() -> int:
	return core.players_online() if core != null else 0


## The IPv4 address others can reach this host on; "" when the device is in no usable network.
func address() -> String:
	return _address


## The short code of `address()`; "" without an address.
func code() -> String:
	return LanCode.encode(_address)


## Closes everything; the port is free again.
func stop() -> void:
	if _beacon != null:
		_beacon.close()
	if _endpoint != null:
		_endpoint.close()
	_beacon = null
	_endpoint = null
	core = null
