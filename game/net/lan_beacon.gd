class_name LanBeacon
extends RefCounted
## Finding games on the local network. A hosting phone announces itself once a second with a small UDP
## broadcast; a phone that looks for games listens for those. This is an extra: joining by code (LanCode)
## works without it, and on iOS broadcast needs an Apple entitlement.
##
## Packet (10 bytes, big endian): "SND1", protocol version u16, game port u16, players u8, max players u8.
## Hand-rolled instead of var_to_bytes: a malformed packet from anyone on the network must not make the
## engine print errors.

const PORT := 24566
const INTERVAL_MS := 1000
const EXPIRE_MS := 3500
const MAGIC := "SND1"
const PACKET_SIZE := 10
const MAX_PACKETS_PER_POLL := 64
const MAX_GAMES := 16

var _sock: PacketPeerUDP
var _dest_port := PORT
var _extra_targets: Array = []
var _next_announce_ms := 0
var _announced := false
var _games := {}    # "ip:port" -> {"ip", "port", "players", "max", "seen"}


static func build(proto_version: int, game_port: int, players: int, max_players: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(PACKET_SIZE)
	var m := MAGIC.to_ascii_buffer()
	for i in 4:
		b[i] = m[i]
	b.encode_u16(4, clampi(proto_version, 0, 65535))
	b.encode_u16(6, clampi(game_port, 0, 65535))
	b[8] = clampi(players, 0, 255)
	b[9] = clampi(max_players, 0, 255)
	return b


## {"version", "port", "players", "max"}, or {} when the packet is not a valid announcement.
static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() != PACKET_SIZE or data.slice(0, 4) != MAGIC.to_ascii_buffer():
		return {}
	var port := data.decode_u16(6)
	var players := data[8]
	var max_players := data[9]
	if port == 0 or players > max_players:
		return {}
	return {"version": data.decode_u16(4), "port": port, "players": players, "max": max_players}


# ---------------------------------------------------------------- announcer (the host)

## `extra_targets`: further addresses to send to (tests pass "127.0.0.1").
func start_announcing(dest_port := PORT, extra_targets: Array = []) -> void:
	_dest_port = dest_port
	_extra_targets = extra_targets.duplicate()
	_sock = PacketPeerUDP.new()
	# On Android this is also what makes Godot take the Wi-Fi MulticastLock, without which the system drops broadcasts.
	_sock.set_broadcast_enabled(true)
	_announced = false


## Sends at most once per INTERVAL_MS: to the global broadcast address, to the directed broadcast of every
## local IPv4 network (assuming /24) and to the extra targets. Errors are ignored.
func announce(now_ms: int, players: int, max_players: int, game_port := NetProto.DEFAULT_PORT) -> void:
	if _sock == null or (_announced and now_ms < _next_announce_ms):
		return
	_announced = true
	_next_announce_ms = now_ms + INTERVAL_MS
	var packet := build(NetProto.VERSION, game_port, players, max_players)
	for target: String in broadcast_targets(IP.get_local_interfaces(), _extra_targets):
		if _sock.set_dest_address(target, _dest_port) == OK:
			_sock.put_packet(packet)


## "255.255.255.255", a.b.c.255 for every non-loopback, non-link-local local IPv4, then the extras (no duplicates).
static func broadcast_targets(interfaces: Array, extra: Array = []) -> Array:
	var out: Array = ["255.255.255.255"]
	for itf: Variant in interfaces:
		if not (itf is Dictionary):
			continue
		var addrs: Variant = (itf as Dictionary).get("addresses", [])
		if not (addrs is Array or addrs is PackedStringArray):
			continue
		for a: Variant in addrs:
			var o := LanCode.parse_ipv4(str(a))
			if o.is_empty() or o[0] == 127 or o[0] == 0 or o[0] >= 224 or (o[0] == 169 and o[1] == 254):
				continue
			var t := "%d.%d.%d.255" % [o[0], o[1], o[2]]
			if not out.has(t):
				out.append(t)
	for e: Variant in extra:
		if not out.has(str(e)):
			out.append(str(e))
	return out


# ---------------------------------------------------------------- listener (a phone looking for games)

## Returns the error; a failure only means there is no list (joining by code still works).
func start_listening(port := PORT) -> int:
	close()
	var s := PacketPeerUDP.new()
	s.set_broadcast_enabled(true)   # also makes Android take the MulticastLock, needed to receive broadcasts
	var err := s.bind(port, "0.0.0.0")
	if err != OK:
		return err
	_sock = s
	_games.clear()
	return OK


## The games heard so far, as [{"ip", "port", "players", "max", "code"}] sorted by address and port. Games of
## another protocol version are ignored, entries not heard for EXPIRE_MS vanish. `now_ms` is a parameter so a
## test can use a fake clock.
func poll(now_ms: int) -> Array:
	if _sock != null:
		for _i in MAX_PACKETS_PER_POLL:
			if _sock.get_available_packet_count() <= 0:
				break
			var data := _sock.get_packet()
			var ip := _sock.get_packet_ip()
			if _sock.get_packet_error() != OK:
				continue
			var g := parse(data)
			if g.is_empty() or g["version"] != NetProto.VERSION or ip == "":
				continue
			var key := "%s:%d" % [ip, g["port"]]
			if not _games.has(key) and _games.size() >= MAX_GAMES:
				continue
			_games[key] = {"ip": ip, "port": g["port"], "players": g["players"], "max": g["max"], "seen": now_ms}
	for key: String in _games.keys():
		if now_ms - int(_games[key]["seen"]) > EXPIRE_MS:
			_games.erase(key)
	var keys := _games.keys()
	keys.sort()
	var out: Array = []
	for key: String in keys:
		var e: Dictionary = _games[key]
		out.append({"ip": e["ip"], "port": e["port"], "players": e["players"], "max": e["max"], "code": LanCode.encode(e["ip"])})
	return out


func close() -> void:
	if _sock != null:
		_sock.close()
	_sock = null
	_games.clear()
