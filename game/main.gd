extends Node
## Wires sim, view, input, bots, HUD and the menus together and runs the fixed 60 Hz tick loop.
## The app starts on the main menu (over the dimmed arena; the sim does not tick). "Play" opens the lobby: a real game
## (solo against bots, or hosting / joining a local match) always uses the DEFAULT values (`play_cfg`: a fresh `Config`
## with only the chosen figure copied from the saved one, no modifier levels). "Training" starts a game with the tuned,
## saved values (`train_cfg`) and the tuning menu. Tuned values never reach a Play game.
## Offline the local sim runs here. Online (menu page "Online") the tick source is a ClientCore that
## predicts the own player and follows the server; the view and HUD then read its sim instead.
## Started with "-- --server" it becomes a headless dedicated server and builds none of this.

const SIM_SEED := 20260101
const UPDATE_CHECK_DELAY := 3.0
const UPDATE_TIMEOUT := 10.0

enum Screen { MENU, LOBBY, GAME }

var cfg: Config                # the config of the game that runs: `train_cfg` (Training) or `play_cfg` (Play)
var train_cfg: Config          # the tuned values, loaded from and saved to user:// (edited by the tuning menu)
var play_cfg: Config           # the fixed values of a real game (see `_make_play_cfg`)
var screen := Screen.MENU
var training := false          # the running (or shown) game is Training
var sim: Sim
var view: ArenaView
var router: InputRouter
var hud: Hud
var menu: TuningMenu           # the Training tuning menu
var main_menu: MainMenu
var lobby: PlayLobby
var pause: PauseMenu
var bots: Array[Bot] = []
var client: ClientCore         # set while connecting / online
var lag: LagEndpoint           # the lag tool between the client and the network
var local_host: LocalHost      # set while this device hosts a local match (Play lobby)
## Ports of the local play; a test changes them so it never touches the real ones.
var local_port := NetProto.DEFAULT_PORT
var beacon_port := LanBeacon.PORT
var beacon_targets: Array = []

var _online := false           # the predicted sim of `client` is what the view shows
var _lag_ms := 0.0
var _loss_pct := 0.0
var _from_local := false       # the current / last connection was started from the Play lobby
var _smooth := true            # draw the other players interpolated (menu switch "Smooth others")

var _acc := 0.0
var _hitstop := 0.0
var _applied_bot_mode := -1
var _update: Dictionary = {}   # {"version", "url"} of a newer release; empty: none known
var _update_dismissed := false
var _update_http: HTTPRequest
var update_url := UpdateCheck.API_URL   # a test points this at a local server
var open_url: Callable = OS.shell_open    # a test replaces this so no browser starts
var quit_hook: Callable                   # a test sets this so Android back in the main menu does not end the test run


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--server"):
		var server := ServerMain.new()
		add_child(server)
		if not server.start(OS.get_cmdline_user_args()):
			get_tree().quit(1)
		return
	train_cfg = Config.new()
	TuningStore.load_into(train_cfg)
	play_cfg = _make_play_cfg()
	cfg = play_cfg
	sim = Sim.new(cfg, SIM_SEED)

	view = ArenaView.new()
	add_child(view)
	view.setup(sim)

	var ui := CanvasLayer.new()
	ui.layer = 4
	add_child(ui)
	router = InputRouter.new()
	router.mouse_to_world = view.screen_to_ground
	router.menu_requested.connect(_on_pause_pressed)
	ui.add_child(router)

	hud = Hud.new()
	add_child(hud)
	hud.setup(sim)
	hud.gear_pressed.connect(_on_pause_pressed)

	menu = TuningMenu.new()
	add_child(menu)
	menu.setup(train_cfg)
	menu.update_requested.connect(_download_update)
	menu.closed.connect(_update_blocked)
	menu.main_menu_requested.connect(_show_main_menu)
	menu.connect_requested.connect(_connect)
	menu.disconnect_requested.connect(func() -> void: _leave_online("closed"))
	menu.lag_changed.connect(func(ms: float, loss: float) -> void:
		_lag_ms = ms
		_loss_pct = loss
		if lag != null:
			lag.delay_ms = ms
			lag.loss_pct = loss)
	menu.smoothing_changed.connect(func(on: bool) -> void:
		_smooth = on
		if client != null:
			client.smooth_others = on)

	main_menu = MainMenu.new()
	add_child(main_menu)
	main_menu.setup()
	main_menu.play_pressed.connect(_show_lobby)
	main_menu.training_pressed.connect(start_training)
	main_menu.update_requested.connect(_download_update)
	main_menu.update_dismissed.connect(func() -> void: _update_dismissed = true)

	lobby = PlayLobby.new()
	add_child(lobby)
	lobby.setup(train_cfg)
	lobby.back_pressed.connect(_show_main_menu)
	lobby.solo_requested.connect(start_solo)
	lobby.host_requested.connect(_host_local)
	lobby.join_local_requested.connect(_join_local)
	lobby.join_code_requested.connect(_join_code)
	lobby.stop_requested.connect(func() -> void: _leave_online("closed"))

	pause = PauseMenu.new()
	add_child(pause)
	pause.setup()
	pause.resume_pressed.connect(_on_pause_pressed)
	pause.main_menu_pressed.connect(_show_main_menu)

	bots = _make_bots()
	_apply_bot_mode()
	_set_screen(Screen.MENU)
	# Headless runs (tests) never go to the network; they feed `offer_update` directly.
	if DisplayServer.get_name() != "headless":
		get_tree().create_timer(UPDATE_CHECK_DELAY).timeout.connect(_start_update_check)


## The config of a real game: the defaults, whatever is tuned or saved for Training; only the chosen figure is
## taken from the saved config. No modifier levels (they come from the shop later), bots active.
func _make_play_cfg() -> Config:
	var c := Config.new()
	c.character = train_cfg.character
	c.bot_mode = Config.BotMode.ACTIVE
	return c


func _make_bots() -> Array[Bot]:
	var out: Array[Bot] = []
	for i in range(1, Config.NUM_PLAYERS):
		out.append(Bot.new(i, cfg, SIM_SEED + i))
	return out


# ---------------------------------------------------------------- screens

## Shows one of the three screens: the main menu and the lobby sit over the dimmed arena (the offline sim stands
## still), the game shows the HUD (Training: scoreboard and gear; Play: only the pause button).
func _set_screen(s: Screen) -> void:
	screen = s
	main_menu.visible = s == Screen.MENU
	if s == Screen.MENU:
		main_menu.show_main()
	if s == Screen.LOBBY:
		lobby.open()
	else:
		lobby.close()
	pause.visible = false
	if s != Screen.GAME and menu.visible:
		menu.close_menu()
	hud.visible = s == Screen.GAME
	hud.play_mode = s == Screen.GAME and not training
	_update_blocked()


func _update_blocked() -> void:
	var want := screen != Screen.GAME or menu.visible or pause.visible
	if router.blocked != want:
		router.blocked = want


## Replaces the offline sim (and the bots) by a fresh one built from `c`, and points view and HUD at it.
func _new_sim(c: Config) -> void:
	cfg = c
	sim = Sim.new(cfg, SIM_SEED)
	bots = _make_bots()
	_applied_bot_mode = -1
	_apply_bot_mode()
	_acc = 0.0
	_hitstop = 0.0
	view.use_sim(sim, 0)
	hud.use_sim(sim, 0)


func _show_main_menu() -> void:
	if client != null or local_host != null:
		_end_session("closed")   # the lobby status then says how it ended
	training = false
	play_cfg = _make_play_cfg()
	_new_sim(play_cfg)   # the backdrop: a fresh, default-valued arena that stands still
	_set_screen(Screen.MENU)


func _show_lobby() -> void:
	_set_screen(Screen.LOBBY)


## Solo against bots with the fixed values.
func start_solo() -> void:
	if client != null or local_host != null:
		_leave_online("closed", false)
	training = false
	play_cfg = _make_play_cfg()
	_new_sim(play_cfg)
	_set_screen(Screen.GAME)


## The sandbox: the tuned, saved values with the tuning menu.
func start_training() -> void:
	if client != null or local_host != null:
		_leave_online("closed", false)
	training = true
	_new_sim(train_cfg)
	_set_screen(Screen.GAME)


## The pause button, Escape, and Resume. Training opens / closes the tuning menu, Play the pause panel.
func _on_pause_pressed() -> void:
	if screen != Screen.GAME:
		return
	if training:
		if menu.visible:
			menu.close_menu()
		else:
			menu.open_menu()
	else:
		pause.visible = not pause.visible
	_update_blocked()


func _quit() -> void:
	if quit_hook.is_valid():
		quit_hook.call()
	else:
		get_tree().quit()


## Android back: pause / resume in a game, back to the main menu from the lobby, leave Settings, quit from the main menu.
func _on_back() -> void:
	match screen:
		Screen.GAME:
			_on_pause_pressed()
		Screen.LOBBY:
			_show_main_menu()
		Screen.MENU:
			if not main_menu.back():
				_quit()


func _apply_bot_mode() -> void:
	_applied_bot_mode = cfg.bot_mode
	for i in range(1, Config.NUM_PLAYERS):
		sim.set_player_enabled(i, cfg.bot_mode != Config.BotMode.OFF)
	sim.set_player_enabled(0, true)


## Copies the sandbox modifier choice into the sim (takes effect on the next tick).
func _sync_mods() -> void:
	sim.apply_mods(0, cfg.mods_you)
	sim.set_skin(0, cfg.character)
	for i in range(1, Config.NUM_PLAYERS):
		sim.apply_mods(i, cfg.mods_bots)
		sim.set_skin(i, cfg.character + i)


func _process(delta: float) -> void:
	if sim == null:
		return   # server mode
	if local_host != null:
		local_host.process(delta)
		lobby.set_session(true, client != null, local_host.code(), local_host.players())
	if client != null:
		_poll_client(delta)
	var dt := 1.0 / Config.TICK_RATE
	var shown := sim
	var slot := 0
	if _online:
		shown = client.sim
		slot = client.slot
		client.set_mods(cfg.mods_you)
		client.set_skin(cfg.character)
		# Online the world does not wait: no hit-stop, and the sim keeps running while a menu is open.
		_acc = minf(_acc + delta, Config.MAX_ACCUMULATED_TIME)
		while _acc >= dt and _online:
			_acc -= dt
			_tick_online()
			_poll_client(0.0)
	else:
		_sync_mods()
		if cfg.bot_mode != _applied_bot_mode:
			_apply_bot_mode()
		if screen == Screen.GAME and not menu.visible and not pause.visible:
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
	router.exclude_rects = hud.blocked_rects()
	var frac := clampf(_acc / dt, 0.0, 1.0)
	if _online:
		client.prepare_display(frac)
		view.set_others(client.display_sim, client.display_alpha)
	view.render(frac, delta)


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


# ---------------------------------------------------------------- update notice

## One request for the newest release in the public releases repository. Sends nothing about the user
## (no identifiers, no version); every failure is silent.
func _start_update_check() -> void:
	if _update_http != null:
		return
	_update_http = HTTPRequest.new()
	_update_http.timeout = UPDATE_TIMEOUT
	_update_http.body_size_limit = UpdateCheck.MAX_BODY_BYTES
	add_child(_update_http)
	_update_http.request_completed.connect(_on_update_response)
	var headers := PackedStringArray(["User-Agent: slice-n-dice", "Accept: application/vnd.github+json"])
	if _update_http.request(update_url, headers) != OK:
		_update_http.queue_free()


func _on_update_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		offer_update(UpdateCheck.parse_release(body, UpdateCheck.running_version()))
	_update_http.queue_free()


## Shows the notice for a release found by `UpdateCheck.parse_release` ({} = nothing newer).
func offer_update(info: Dictionary) -> void:
	_update = info
	menu.set_update(info.get("version", ""))
	main_menu.set_update(info.get("version", ""), _update_dismissed)


func _download_update() -> void:
	# The browser/Android download manager takes over; the link was checked by UpdateCheck.
	if not _update.is_empty() and UpdateCheck.is_allowed_url(_update["url"]):
		open_url.call(_update["url"])


# ---------------------------------------------------------------- online

## Texts of the connection status (shown on the Online page of Training and in the Play lobby).
const STATUS := {
	"bad_address": "Invalid address",
	"connect_failed": "Connection failed",
	"connecting": "Connecting …",
	"host_failed": "Could not open the game (port in use?)",
	"connected": "Connected as player %d",
	"ended": "Game ended",
	"full": "Server is full (%d players)",
	"version": "Wrong version: the app and the server do not match",
	"started": "The match has already started.",
	"disconnected": "Disconnected",
	"not_connected": "Not connected",
	"bad_code": "Invalid code",
}


## The Online page of the tuning menu (Training): a connection with the tuned values.
func _connect(address_text: String) -> void:
	_leave_online("closed", false)
	_from_local = false
	var a := NetStore.parse_address(address_text)
	if a["host"] == "":
		_set_status("bad_address", false)
		return
	NetStore.save_address(address_text.strip_edges())
	_use_config_for_session(train_cfg, true)
	_start_client(a["host"], a["port"])


## Which values a session uses: Training (Online page) the tuned ones with the modifier sandbox, a Play session
## (local hosting / joining) the fixed ones with no modifiers.
func _use_config_for_session(c: Config, is_training: bool) -> void:
	cfg = c
	training = is_training


func _use_play_config() -> void:
	play_cfg = _make_play_cfg()
	_use_config_for_session(play_cfg, false)


## Connects the own client to a server (the shared part of every way to go online).
func _start_client(host: String, port: int) -> bool:
	var endpoint := ENetEndpoint.new()
	if endpoint.connect_to(host, port) != OK:
		_set_status("connect_failed", false)
		return false
	lag = LagEndpoint.new(endpoint)
	lag.delay_ms = _lag_ms
	lag.loss_pct = _loss_pct
	client = ClientCore.new(lag)
	client.smooth_others = _smooth
	client.set_mods(cfg.mods_you)
	client.set_skin(cfg.character)
	_set_status("connecting", true)
	return true


## Shows a connection status on the Online page and, for connections started in the Play lobby, there too.
func _set_status(key: String, busy: bool, arg := 0) -> void:
	var text: String = STATUS[key]
	if text.contains("%d"):
		text = text % arg
	menu.set_online_status(text, busy)
	if _from_local:
		lobby.set_status(text)
	_refresh_local_session()


## This device hosts a match on the fixed Play values (the own client joins through 127.0.0.1, like everybody else).
func _host_local(with_bots: bool) -> void:
	_leave_online("closed", false)
	_from_local = true
	_use_play_config()
	var host := LocalHost.new()
	host.beacon_port = beacon_port
	host.beacon_targets = beacon_targets
	if host.start(play_cfg, with_bots, local_port) != OK:
		_set_status("host_failed", false)
		return
	local_host = host
	if not _start_client("127.0.0.1", local_port):
		_leave_online("closed", false)


func _join_local(ip: String, port := -1) -> void:
	_leave_online("closed", false)
	_from_local = true
	_use_play_config()
	if LanCode.encode(ip) == "":
		_set_status("bad_address", false)
		return
	_start_client(ip, local_port if port < 1 else port)


func _join_code(code: String) -> void:
	var ip := LanCode.decode(code)
	_leave_online("closed", false)
	_from_local = true
	_use_play_config()
	if ip == "":
		_set_status("bad_code", false)
		return
	_start_client(ip, local_port)


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
	_set_screen(Screen.GAME)
	_set_status("connected", true, client.slot + 1)


func _tick_online() -> void:
	client.tick(router.poll(client.sim.players[client.slot].pos))
	for e: Dictionary in client.events:
		view.handle_event(e)
		if e["type"] == "kill" and (e["victim"] == client.slot or e["killer"] == client.slot):
			Input.vibrate_handheld(Config.VIBRATE_MS)


## Leaves the session. A Play match that ends this way (the host left, the connection broke) has nothing to go back
## to, so it returns to the main menu; Training falls back to its offline game. Silent (`show_status` false) when a
## new session or game replaces the old one right away.
func _leave_online(reason: String, show_status := true) -> void:
	_end_session(reason, show_status)
	if show_status and screen == Screen.GAME and not training:
		_show_main_menu()


## Back to the offline game (which was paused while online and simply continues).
func _end_session(reason: String, show_status := true) -> void:
	var was_online := _online
	var was_hosting := local_host != null
	if client != null:
		client.close()
	_stop_local_host()
	client = null
	lag = null
	_online = false
	_acc = 0.0
	view.use_sim(sim, 0)
	hud.use_sim(sim, 0)
	hud.online = false
	var key := "ended" if was_hosting and reason == "closed" else _reason_key(reason, was_online)
	if show_status:
		_set_status(key, false, Config.NUM_PLAYERS)
	else:
		_refresh_local_session()


func _stop_local_host() -> void:
	if local_host != null:
		local_host.stop()
		local_host = null


func _refresh_local_session() -> void:
	lobby.set_session(local_host != null, client != null, local_host.code() if local_host != null else "", local_host.players() if local_host != null else 0)


func _reason_key(reason: String, was_online: bool) -> String:
	match reason:
		"full":
			return "full"
		"version":
			return "version"
		"started":
			return "started"
		"timeout", "unreachable":
			return "connect_failed"
	return "disconnected" if was_online else "not_connected"


func _net_text() -> String:
	var others := "Others %d ms behind" % roundi(client.interp_delay_ms()) if client.smooth_others else "Others raw"
	return "Ping %d ms   Correction %s m   Pending inputs %d   %s" % [
			roundi(client.ping_ms), String.num(client.correction, 2), client.pending_inputs(), others]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if client != null:
			client.close()   # tells the server at once instead of letting the slot time out
		_stop_local_host()


func _exit_tree() -> void:
	_stop_local_host()
