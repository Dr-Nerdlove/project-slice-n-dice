extends SceneTree
## Renders pictures of the toy figures and the arena to PNG files, for checking a visual change without a phone.
## Run it through tools/render-preview.sh OUT_DIR (a container with a virtual screen), or with a display:
##   godot --path game -s ../tools/character_preview.gd -- OUT_DIR
## Writes lineup_<n>.png (all figures walking towards the camera, in phases of their step), poses.png (charging,
## yo-yo out, dashing, stunned, walking away), arena.png (the real game after a few seconds of bots playing) and
## menu.png (the menu page "Figur").

var _out := "."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_run()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name))


## A stage: the real arena view with its players switched off, and a close camera on its lower middle.
func _stage(cfg: Config) -> Array:
	var sim := Sim.new(cfg, 3)
	for i in sim.players.size():
		sim.set_player_enabled(i, false)
	var view := ArenaView.new()
	root.add_child(view)
	view.setup(sim)
	view.render(1.0, 0.016)
	var c := Config.ARENA_SIZE * Vector2(0.5, 0.78)
	var pitch := deg_to_rad(Config.CAMERA_PITCH_DEG)
	view.camera.position = Vector3(c.x, 0.4 + 9.0 * sin(pitch), c.y + 9.0 * cos(pitch))
	return [sim, view, c]


func _run() -> void:
	var cfg := Config.new()
	cfg.train_speed = 0.0
	var st := _stage(cfg)
	var sim: Sim = st[0]
	var view: ArenaView = st[1]
	var c: Vector2 = st[2]
	var n := ToyFigure.NAMES.size()
	var figs: Array[ToyFigure] = []
	var players: Array[SimPlayer] = []
	for k in n:
		var fig := ToyFigure.new(k, ArenaView.PLAYER_COLORS[k % 4])
		view.add_child(fig)
		figs.append(fig)
		var p := SimPlayer.new()
		p.facing = Vector2(0, 1)
		p.aim_dir = Vector2(0, 1)
		players.append(p)
	var dt := 1.0 / 60.0
	var spot := func(k: int) -> Vector2:
		return c + Vector2(-3.9 + 2.6 * (k % 4), -1.5 + 2.6 * (k / 4))
	# Walking towards the camera (the figures walk on the spot: the drawn position moves and snaps back).
	var walked := 0.0
	for shot in 4:
		for step in 11:
			walked += cfg.player_speed * dt
			for k in n:
				figs[k].sync(players[k], sim, spot.call(k) + Vector2(0, fmod(walked, 0.6) - 0.3), dt)
		await _shot("lineup_%d.png" % shot)
	# Poses.
	for k in n:
		figs[k].queue_free()
	figs.clear()
	var kinds := [4, 5, 6, 7, 0, 1, 2, 3]
	for k in n:
		var fig := ToyFigure.new(kinds[k], ArenaView.PLAYER_COLORS[(k + 2) % 4])
		view.add_child(fig)
		figs.append(fig)
		players[k] = SimPlayer.new()
		players[k].facing = Vector2(0, 1)
		players[k].aim_dir = Vector2(0, 1)
	players[0].charging = true
	players[0].charge_t = cfg.charge_time
	players[1].heads[0].state = SimHead.S.OUT
	figs[1].string_dir = Vector2(1, 0.3).normalized()
	players[2].stun_t = 1.0
	players[3].facing = Vector2(0, -1)
	players[4].charging = true
	players[4].charge_t = cfg.charge_time * 0.6
	players[5].heads[0].state = SimHead.S.OUT
	figs[5].string_dir = Vector2(-1, 0.6).normalized()
	players[6].pulling = true
	players[7].stun_t = 1.0
	for step in 50:
		for k in n:
			figs[k].sync(players[k], sim, spot.call(k), dt)
	await _shot("poses.png")
	view.queue_free()
	await process_frame

	# The real game view after a few seconds of bots playing.
	cfg = Config.new()
	sim = Sim.new(cfg, 7)
	for i in sim.players.size():
		sim.set_skin(i, [4, 5, 6, 7][i % 4])
	view = ArenaView.new()
	root.add_child(view)
	view.setup(sim)
	var bots: Array[Bot] = []
	for i in Config.NUM_PLAYERS:
		bots.append(Bot.new(i, cfg, 100 + i))
	for tick in 150:
		var inputs: Array = []
		for b in bots:
			inputs.append(b.think(sim, 1.0 / Config.TICK_RATE))
		sim.step(inputs)
		for e: Dictionary in sim.events:
			view.handle_event(e)
		view.render(1.0, 1.0 / Config.TICK_RATE)
	await _shot("arena.png")

	# The menu page where the figure is chosen.
	cfg.character = 4
	var menu := TuningMenu.new()
	root.add_child(menu)
	menu.setup(cfg)
	menu.open_menu()
	menu._show_page(3)
	for frame in 50:
		await process_frame
	await _shot("menu.png")
	quit()
