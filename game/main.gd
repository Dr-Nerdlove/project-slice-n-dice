extends Node
## Wires sim, view, input, bots, HUD and menu together and runs the fixed 60 Hz tick loop.
## Offline the local sim runs here. Online (menu page "Online") the tick source is a ClientCore that
## predicts the own player and follows the server; the view and HUD then read its sim instead.
## Started with "-- --server" it becomes a headless dedicated server and builds none of this.

const SIM_SEED := 20260101

var cfg: Config
var sim: Sim
var view: ArenaView
var router: InputRouter
var hud: Hud
var menu: TuningMenu
var bots: Array[Bot] = []
var client: ClientCore         # set while connecting / online
var lag: LagEndpoint           # the lag tool between the client and the network

var _online := false           # the predicted sim of `client` is what the view shows
var _lag_ms := 0.0
var _loss_pct := 0.0

var _acc := 0.0
var _hitstop := 0.0
var _applied_bot_mode := -1


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--server"):
		var server := ServerMain.new()
		add_child(server)
		if not server.start(OS.get_cmdline_user_args()):
			get_tree().quit(1)
		return
	cfg = Config.new()
	TuningStore.load_into(cfg)
	sim = Sim.new(cfg, SIM_SEED)

	view = ArenaView.new()
	add_child(view)
	view.setup(sim)

	var ui := CanvasLayer.new()
	ui.layer = 4
	add_child(ui)
	router = InputRouter.new()
	router.mouse_to_world = view.screen_to_ground
	router.menu_requested.connect(_toggle_menu)
	ui.add_child(router)

	hud = Hud.new()
	add_child(hud)
	hud.setup(sim)
	hud.gear_pressed.connect(_toggle_menu)

	menu = TuningMenu.new()
	add_child(menu)
	menu.setup(cfg)
	menu.closed.connect(func() -> void: router.blocked = false)
	menu.connect_requested.connect(_connect)
	menu.disconnect_requested.connect(func() -> void: _leave_online("closed"))
	menu.lag_changed.connect(func(ms: float, loss: float) -> void:
		_lag_ms = ms
		_loss_pct = loss
		if lag != null:
			lag.delay_ms = ms
			lag.loss_pct = loss)

	for i in range(1, Config.NUM_PLAYERS):
		bots.append(Bot.new(i, cfg, SIM_SEED + i))
	_apply_bot_mode()


func _toggle_menu() -> void:
	if menu.visible:
		menu.close_menu()
	else:
		menu.open_menu()
		router.blocked = true


func _apply_bot_mode() -> void:
	_applied_bot_mode = cfg.bot_mode
	for i in range(1, Config.NUM_PLAYERS):
		sim.set_player_enabled(i, cfg.bot_mode != Config.BotMode.OFF)
	sim.set_player_enabled(0, true)


## Copies the sandbox modifier choice into the sim (takes effect on the next tick).
func _sync_mods() -> void:
	sim.apply_mods(0, cfg.mods_you)
	for i in range(1, Config.NUM_PLAYERS):
		sim.apply_mods(i, cfg.mods_bots)


func _process(delta: float) -> void:
	if sim == null:
		return   # server mode
	if client != null:
		_poll_client(delta)
	var dt := 1.0 / Config.TICK_RATE
	var shown := sim
	var slot := 0
	if _online:
		shown = client.sim
		slot = client.slot
		client.set_mods(cfg.mods_you)
		# Online the world does not wait: no hit-stop, and the sim keeps running while the menu is open.
		_acc = minf(_acc + delta, Config.MAX_ACCUMULATED_TIME)
		while _acc >= dt and _online:
			_acc -= dt
			_tick_online()
			_poll_client(0.0)
	else:
		_sync_mods()
		if cfg.bot_mode != _applied_bot_mode:
			_apply_bot_mode()
		if not menu.visible:
			if _hitstop > 0.0:
				_hitstop -= delta  # presentation-only freeze; the sim simply does not tick
			else:
				_acc = minf(_acc + delta, Config.MAX_ACCUMULATED_TIME)
				while _acc >= dt:
					_acc -= dt
					_tick(dt)
					if _hitstop > 0.0:
						break
	if _online:
		shown = client.sim
	var me := shown.players[slot]
	router.dash_charges = me.dash_charges
	router.dash_charges_max = shown.dash_max(me)
	router.dash_ready_ratio = 1.0 - clampf(me.dash_cd / maxf(shown.dash_cooldown_of(me), 0.001), 0.0, 1.0)
	hud.net_text = _net_text() if _online else ""
	hud.refresh()
	router.exclude_rects = [hud.gear_rect()]
	view.render(clampf(_acc / dt, 0.0, 1.0), delta)


func _tick(dt: float) -> void:
	var inputs: Array = []
	inputs.append(router.poll(sim.players[0].pos))
	for b in bots:
		if cfg.bot_mode == Config.BotMode.ACTIVE:
			inputs.append(b.think(sim, dt))
		else:
			inputs.append(SimInput.new())
	sim.step(inputs)
	for e: Dictionary in sim.events:
		view.handle_event(e)
		if e["type"] == "kill":
			_hitstop = Config.HITSTOP_TIME
			if e["victim"] == 0 or e["killer"] == 0:
				Input.vibrate_handheld(Config.VIBRATE_MS)


# ---------------------------------------------------------------- online

func _connect(address_text: String) -> void:
	_leave_online("closed", false)
	var a := NetStore.parse_address(address_text)
	if a["host"] == "":
		menu.set_online_status("Ungültige Adresse", false)
		return
	NetStore.save_address(address_text.strip_edges())
	var endpoint := ENetEndpoint.new()
	if endpoint.connect_to(a["host"], a["port"]) != OK:
		menu.set_online_status("Verbindung fehlgeschlagen", false)
		return
	lag = LagEndpoint.new(endpoint)
	lag.delay_ms = _lag_ms
	lag.loss_pct = _loss_pct
	client = ClientCore.new(lag)
	client.set_mods(cfg.mods_you)
	menu.set_online_status("Verbinde …", true)


func _poll_client(delta: float) -> void:
	if client == null:
		return
	client.poll(delta)
	match client.state:
		ClientCore.State.ONLINE:
			if not _online:
				_enter_online()
		ClientCore.State.FAILED, ClientCore.State.CLOSED:
			_leave_online(client.fail_reason)


func _enter_online() -> void:
	_online = true
	_acc = 0.0
	view.use_sim(client.sim, client.slot)
	hud.use_sim(client.sim, client.slot)
	hud.online = true
	menu.set_online_status("Verbunden als Spieler %d" % (client.slot + 1), true)


func _tick_online() -> void:
	client.tick(router.poll(client.sim.players[client.slot].pos))
	for e: Dictionary in client.events:
		view.handle_event(e)
		if e["type"] == "kill" and (e["victim"] == client.slot or e["killer"] == client.slot):
			Input.vibrate_handheld(Config.VIBRATE_MS)


## Back to the offline game (which was paused while online and simply continues).
func _leave_online(reason: String, show_status := true) -> void:
	var was_online := _online
	if client != null:
		client.close()
	client = null
	lag = null
	_online = false
	_acc = 0.0
	view.use_sim(sim, 0)
	hud.use_sim(sim, 0)
	hud.online = false
	if show_status:
		menu.set_online_status(_reason_text(reason, was_online), false)


func _reason_text(reason: String, was_online: bool) -> String:
	match reason:
		"full":
			return "Server ist voll (4 Spieler)"
		"version":
			return "Falsche Version: App und Server passen nicht zusammen"
		"timeout", "unreachable":
			return "Verbindung fehlgeschlagen"
	return "Getrennt" if was_online else "Nicht verbunden"


func _net_text() -> String:
	return "Ping %d ms   Korrektur %s m   offene Eingaben %d" % [
			roundi(client.ping_ms), String.num(client.correction, 2).replace(".", ","), client.pending_inputs()]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and client != null:
		client.close()   # tells the server at once instead of letting the slot time out
