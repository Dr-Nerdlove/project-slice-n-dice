class_name NetProto
extends RefCounted
## Wire format shared by ServerCore and ClientCore. Messages are Arrays whose first element is the type,
## packed with var_to_bytes (never the _with_objects variants: nothing from the network may create Objects).
## Every packet starts with one byte, the packet kind. Snapshots are binary because they are big and
## compressed; everything else is a plain var_to_bytes Array.
##
## client -> server
##   [T_HELLO, version, token]               reliable, first message after connecting (token: the install's identity, 8..64 chars of 0-9a-f)
##   [T_INPUT, seq, [input, ...]]            unreliable, newest first (seq, seq-1, ...)
##   [T_MODS, {modifier id: level}]          reliable, whenever the chosen modifier levels change
##   [T_COLOR, colour]                       reliable, whenever the chosen colour changes (int 0..COLOR_COUNT-1); the server may pick another one when it is taken
##   [T_TEAM]                                reliable, "move me to the other team" (Teams mode, only before a match / after one; refused when every seat there is a human)
##   [T_SKIN, figure]                        reliable, whenever the chosen figure changes (int 0..SKIN_COUNT-1)
##   [T_PING, time]                          unreliable
##   [T_SHOP, action, arg, seq]              reliable, a shop action (SHOP_BUY offer index / SHOP_REROLL / SHOP_DONE /
##                                           SHOP_SELL index in Mods.ORDER / SHOP_LOCK offer index);
##                                           seq is the slot's `MatchMode.shop_seq` the client saw (repeats are refused)
## server -> client
##   [T_WELCOME, version, slot, config]      reliable
##   [T_REJECT, reason]                      reliable, then the server hangs up
##   [T_PONG, time]                          unreliable
##   snapshot packet (see snapshot_packet)  unreliable
## input = [move.x, move.y, aim.x, aim.y, flags]   flags: bit 0 aim_held, bit 1 dash

const VERSION := 19
const DEFAULT_PORT := 24565

const T_HELLO := 1
const T_INPUT := 2
const T_MODS := 3
const T_PING := 4
const T_SKIN := 5
const T_SHOP := 6
const T_COLOR := 7
const T_TEAM := 8
const SHOP_BUY := 0
const SHOP_REROLL := 1
const SHOP_DONE := 2
const SHOP_SELL := 3   # arg: index of the modifier in Mods.ORDER
const SHOP_LOCK := 4   # arg: offer index; toggles the lock
const T_WELCOME := 10
const T_REJECT := 11
const T_PONG := 12

const K_PLAIN := 0
const K_SNAPSHOT := 1

const MAX_CLIENT_PACKET := 1024      # bytes; anything bigger is dropped unread
const MAX_SERVER_PACKET := 16384
const MAX_STATE_BYTES := 262144      # cap for a decompressed snapshot
const REDUNDANCY := 4                # inputs per packet: the newest plus the previous ones
const MAX_INPUTS_PER_PACKET := 8
const MAX_SEQ := 2147483647
const SNAPSHOT_HEADER := 9           # kind byte + u32 acked input seq + u32 server tick


## True for a well-formed client token: a String of 8..64 characters of 0-9a-f.
static func valid_token(t: Variant) -> bool:
	if not (t is String):
		return false
	var str: String = t
	if str.length() < 8 or str.length() > 64:
		return false
	for c in str:
		if not "0123456789abcdef".contains(c):
			return false
	return true


static func pack(msg: Array) -> PackedByteArray:
	var out := PackedByteArray([K_PLAIN])
	out.append_array(var_to_bytes(msg))
	return out


## Decodes a plain packet. Returns [] for anything that is not a well-formed message Array with an int type.
static func unpack(data: PackedByteArray, max_size: int) -> Array:
	if data.size() < 5 or data.size() > max_size or data[0] != K_PLAIN:
		return []
	var body := data.slice(1)
	# Only an Array header is decoded: bytes_to_var prints an engine error for every malformed input.
	if body.decode_u32(0) != TYPE_ARRAY:
		return []
	var v: Variant = bytes_to_var(body)
	if not (v is Array) or (v as Array).is_empty() or not ((v as Array)[0] is int):
		return []
	return v


static func encode_input(i: SimInput) -> Array:
	var c := clamp_input(i)
	return [c.move.x, c.move.y, c.aim.x, c.aim.y, (1 if c.aim_held else 0) | (2 if c.dash else 0)]


## A copy with the sticks limited to length 1 (the same rule on both sides keeps prediction exact).
static func clamp_input(i: SimInput) -> SimInput:
	var c := SimInput.new()
	c.move = i.move.limit_length(1.0)
	c.aim = i.aim.limit_length(1.0)
	c.aim_held = i.aim_held
	c.dash = i.dash
	return c


## Honest clients send sticks of length <= 1. Anything bigger is refused: a huge value turns into inf as a float32
## Vector2 and limit_length makes NaN of it, which would poison the sim for every player.
const MAX_STICK := 2.0


static func _num(v: Variant) -> bool:
	return (v is float and is_finite(v)) or v is int


## Null when `a` is not a well-formed input; sticks are clamped to length <= 1.
static func decode_input(a: Variant) -> SimInput:
	if not (a is Array) or (a as Array).size() != 5:
		return null
	for k in 4:
		if not _num(a[k]) or absf(float(a[k])) > MAX_STICK:
			return null
	if not (a[4] is int):
		return null
	var i := SimInput.new()
	i.move = Vector2(a[0], a[1])
	i.aim = Vector2(a[2], a[3])
	i.aim_held = (int(a[4]) & 1) != 0
	i.dash = (int(a[4]) & 2) != 0
	return clamp_input(i)


## Compressed body shared by all peers: the current input of every slot and the sim state.
static func snapshot_body(inputs: Array, state: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes([inputs, state])
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())   # zstd needs the size of the decompressed data
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func snapshot_packet(server_tick: int, acked_seq: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([K_SNAPSHOT])
	out.resize(SNAPSHOT_HEADER)
	out.encode_u32(1, acked_seq)
	out.encode_u32(5, server_tick)
	out.append_array(body)
	return out


## {"tick", "acked", "inputs", "state"} or {} when the packet is not a snapshot.
static func read_snapshot(data: PackedByteArray) -> Dictionary:
	if data.size() <= SNAPSHOT_HEADER + 4 or data.size() > MAX_SERVER_PACKET or data[0] != K_SNAPSHOT:
		return {}
	var raw_size := data.decode_u32(SNAPSHOT_HEADER)
	if data.size() <= SNAPSHOT_HEADER + 4 or raw_size < 5 or raw_size > MAX_STATE_BYTES:
		return {}
	var raw := data.slice(SNAPSHOT_HEADER + 4).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() < 5 or raw.decode_u32(0) != TYPE_ARRAY:
		return {}
	var v: Variant = bytes_to_var(raw)
	if not (v is Array) or (v as Array).size() != 2 or not (v[0] is Array) or not (v[1] is Dictionary):
		return {}
	return {"tick": data.decode_u32(5), "acked": data.decode_u32(1), "inputs": v[0], "state": v[1]}
