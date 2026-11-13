extends Node
## Wires sim, view, input, bots, HUD and menu together and runs the fixed 60 Hz tick loop.

const SIM_SEED := 20260101

var cfg: Config
var sim: Sim
var view: ArenaView
var router: InputRouter
var hud: Hud
var menu: TuningMenu
var bots: Array[Bot] = []

var _acc := 0.0
var _hitstop := 0.0
var _applied_bot_mode := -1


func _ready() -> void:
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
	_sync_mods()
	if cfg.bot_mode != _applied_bot_mode:
		_apply_bot_mode()
	var dt := 1.0 / Config.TICK_RATE
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
	var me := sim.players[0]
	router.dash_charges = me.dash_charges
	router.dash_charges_max = sim.dash_max(me)
	router.dash_ready_ratio = 1.0 - clampf(me.dash_cd / maxf(sim.dash_cooldown_of(me), 0.001), 0.0, 1.0)
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
