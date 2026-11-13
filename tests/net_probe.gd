extends SceneTree
## Scripted headless client for checking a running server by hand (no display needed):
##   godot --headless --path game -s tests/net_probe.gd -- 127.0.0.1[:port] [--seconds N] [--lag MS] [--loss PERCENT]
## Walks, charges, throws, retracts and pulls in a loop, prints one line per second and exits with 0 when
## it was online and kept receiving snapshots, otherwise with 1.

var _cl: ClientCore
var _lag: LagEndpoint
var _t := 0
var _acc := 0.0
var _seconds := 6.0
var _started_ms := 0
var _last_print := -1
var _was_online := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var address := ""
	var lag_ms := 0.0
	var loss := 0.0
	var i := 0
	while i < args.size():
		match args[i]:
			"--seconds":
				i += 1
				_seconds = float(args[i])
			"--lag":
				i += 1
				lag_ms = float(args[i])
			"--loss":
				i += 1
				loss = float(args[i])
			_:
				address = args[i]
		i += 1
	var a := NetStore.parse_address(address)
	if a["host"] == "":
		printerr("usage: -- HOST[:PORT] [--seconds N] [--lag MS] [--loss PERCENT]")
		quit(2)
		return
	var ep := ENetEndpoint.new()
	if ep.connect_to(a["host"], a["port"]) != OK:
		printerr("cannot open a client socket")
		quit(1)
		return
	_lag = LagEndpoint.new(ep)
	_lag.delay_ms = lag_ms
	_lag.loss_pct = loss
	_cl = ClientCore.new(_lag)
	_started_ms = Time.get_ticks_msec()
	print("connecting to %s:%d (lag %d ms per direction, loss %d %%)" % [a["host"], a["port"], lag_ms, loss])


func _routine(t: int) -> SimInput:
	var i := SimInput.new()
	var ph := t % 300
	if ph < 60:
		i.move = Vector2.RIGHT
	elif ph < 90:
		i.aim = Vector2.RIGHT
		i.aim_held = true
	elif ph >= 125 and ph < 128:
		i.aim_held = true
	elif ph >= 190 and ph < 240:
		i.aim_held = true
	return i


func _process(delta: float) -> bool:
	_cl.poll(delta)
	if _cl.state == ClientCore.State.FAILED or _cl.state == ClientCore.State.CLOSED:
		print("ended: %s" % _cl.fail_reason)
		quit(0 if _was_online else 1)
		return true
	if _cl.state == ClientCore.State.ONLINE:
		if not _was_online:
			_was_online = true
			print("online as player %d" % (_cl.slot + 1))
		_acc = minf(_acc + delta, 0.25)
		while _acc >= 1.0 / 60.0:
			_acc -= 1.0 / 60.0
			_cl.tick(_routine(_t))
			_t += 1
			_cl.poll()
	var sec := (Time.get_ticks_msec() - _started_ms) / 1000
	if sec != _last_print:
		_last_print = sec
		print("t=%ds state=%d ping=%.0f ms correction=%.3f m pending=%d snapshots=%d (dropped %d)" % [
				sec, _cl.state, _cl.ping_ms, _cl.correction, _cl.pending_inputs(), _cl.snapshots_applied, _cl.snapshots_dropped])
	if (Time.get_ticks_msec() - _started_ms) / 1000.0 > _seconds:
		var ok := _was_online and _cl.snapshots_applied > 30
		print("result: %s" % ("OK" if ok else "FAILED"))
		_cl.close()
		quit(0 if ok else 1)
		return true
	return false
