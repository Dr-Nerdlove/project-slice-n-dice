class_name LagEndpoint
extends NetEndpoint
## Test tool: wraps a client endpoint and holds every packet (in both directions) for `delay_ms` and drops
## `loss_pct` percent of the unreliable ones. Reliable packets and connect / disconnect events are only
## delayed, never dropped. Order is kept even when the delay is changed while packets are on the way.

var inner: NetEndpoint
var delay_ms := 0.0       # one way: the round trip grows by twice this value
var loss_pct := 0.0       # per direction
var rng := RandomNumberGenerator.new()
var clock: Callable       # () -> float, milliseconds; real time unless a test injects its own

var _out: Array = []      # {"at", "peer", "data", "reliable"}
var _in: Array = []       # {"at", "ev"}
var _last_out_at := 0.0
var _last_in_at := 0.0


func _init(wrapped: NetEndpoint, seed_value := 4242) -> void:
	inner = wrapped
	rng.seed = seed_value
	clock = func() -> float: return float(Time.get_ticks_msec())


func send(peer: int, data: PackedByteArray, reliable: bool) -> void:
	if not reliable and rng.randf() * 100.0 < loss_pct:
		return
	_last_out_at = maxf(float(clock.call()) + delay_ms, _last_out_at)
	_out.append({"at": _last_out_at, "peer": peer, "data": data, "reliable": reliable})


func poll() -> Array:
	var now: float = clock.call()
	while not _out.is_empty() and _out[0]["at"] <= now:
		var o: Dictionary = _out.pop_front()
		inner.send(o["peer"], o["data"], o["reliable"])
	for ev: Dictionary in inner.poll():
		if ev["kind"] == Kind.PACKET and not ev["reliable"] and rng.randf() * 100.0 < loss_pct:
			continue
		_last_in_at = maxf(now + delay_ms, _last_in_at)
		_in.append({"at": _last_in_at, "ev": ev})
	var out: Array = []
	while not _in.is_empty() and _in[0]["at"] <= now:
		out.append(_in.pop_front()["ev"])
	return out


func flush() -> void:
	inner.flush()


func disconnect_peer(peer: int) -> void:
	inner.disconnect_peer(peer)


func close() -> void:
	inner.close()
