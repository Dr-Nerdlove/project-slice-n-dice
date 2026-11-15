class_name ServerMain
extends Node
## Headless dedicated server: godot --headless --path game -- --server [--port N] [--bots]
## Creates no view, HUD or menu. Steps the sim at a fixed 60 Hz regardless of the frame rate and logs
## joins, leaves and a status line every 10 seconds.

const STATUS_EVERY_MS := 10000

var core: ServerCore
var endpoint: ENetEndpoint
var port := NetProto.DEFAULT_PORT

var _next_status_ms := 0
var _started_ms := 0


## Reads the arguments after "--". Returns false (after printing why) when the server cannot start.
func start(args: PackedStringArray) -> bool:
	var with_bots := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--server":
				pass
			"--bots":
				with_bots = true
			"--port":
				i += 1
				if i >= args.size() or not args[i].is_valid_int() or int(args[i]) < 1 or int(args[i]) > 65535:
					printerr("server: --port needs a number from 1 to 65535")
					return false
				port = int(args[i])
			_:
				printerr("server: unknown argument %s" % args[i])
				return false
		i += 1
	endpoint = ENetEndpoint.new()
	var err := endpoint.listen(port, ServerCore.MAX_PENDING)
	if err != OK:
		printerr("server: cannot listen on UDP port %d (error %d)" % [port, err])
		return false
	core = ServerCore.new(Config.new(), endpoint, 20260101, with_bots)
	core.log_fn = _log
	Engine.max_fps = 120   # headless would otherwise spin one core at 100 %
	_started_ms = Time.get_ticks_msec()
	_next_status_ms = _started_ms + STATUS_EVERY_MS
	_log("listening on UDP port %d, protocol %d, bots %s" % [port, NetProto.VERSION, "on" if with_bots else "off"])
	return true


func _log(text: String) -> void:
	print("[%7.1fs] %s" % [(Time.get_ticks_msec() - _started_ms) / 1000.0, text])


func _process(delta: float) -> void:
	if core == null:
		return
	core.run(delta)
	if Time.get_ticks_msec() >= _next_status_ms:
		_next_status_ms += STATUS_EVERY_MS
		_log("status: %d player(s), tick %d, dropped packets %d, underruns %d, stale inputs %d" % [
				core.players_online(), core.sim.tick, core.dropped_packets, core.underruns, core.stale_inputs])


func _exit_tree() -> void:
	if endpoint != null:
		endpoint.close()
