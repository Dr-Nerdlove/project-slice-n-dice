extends SceneTree
## Renders pictures of the player figures to PNG files, for checking a visual change without a phone.
## Needs a display and a GPU or software renderer (see "Pictures without a display" in AGENTS.md):
##   godot --path game -s ../tools/character_preview.gd -- OUT_DIR
## Writes lineup_<n>.png (all eight figures walking towards the camera, in four phases of their step),
## poses.png (standing, charging, dashing, stunned, seen from behind) and arena.png (the real game view).

const COLS: Array[Color] = [
	Color(0.25, 0.55, 1.0), Color(1.0, 0.35, 0.3), Color(0.35, 0.85, 0.4), Color(1.0, 0.8, 0.25)]

var _out := "."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_run()


func _stage(width: float) -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	sun.light_energy = 0.9
	stage.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 0.2, 30)
	floor_mi.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.22, 0.26)
	floor_mi.material_override = fm
	floor_mi.position.y = -0.1
	stage.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = Config.CAMERA_FOV
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	var pitch := deg_to_rad(Config.CAMERA_PITCH_DEG)
	var dist := width * 0.5 / tan(deg_to_rad(Config.CAMERA_FOV) * 0.5)
	cam.position = Vector3(0.0, 0.5 + dist * sin(pitch), dist * cos(pitch))
	cam.rotation = Vector3(-pitch, 0.0, 0.0)
	stage.add_child(cam)
	return stage


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name))


func _run() -> void:
	# All eight figures, two rows, walking towards the camera.
	var stage := _stage(11.0)
	var rigs: Array[CharacterRig] = []
	for k in CharacterRig.KIND_COUNT:
		var rig := CharacterRig.new()
		stage.add_child(rig)
		rig.setup(k, COLS[k % 4])
		rig.position = Vector3(-3.6 + 2.4 * (k % 4), 0.0, -1.6 + 2.6 * (k / 4))
		rigs.append(rig)
	for shot in 4:
		for step in 9:
			for rig in rigs:
				rig.animate(1.0 / 60.0, 0.8, Vector2(0, 6), 6.0, false, 0.0, false, Vector2.ZERO)
		await _shot("lineup_%d.png" % shot)
	# One row per pose: standing, winding up, dashing, stunned, walking away, yo-yo out to the side.
	for k in rigs.size():
		var rig := rigs[k]
		rig.setup([0, 1, 2, 3, 4, 5, 6, 7][k], COLS[(k + 1) % 4])
		rig.rotation.y = PI if k == 6 else 0.0
	for step in 40:
		rigs[0].animate(1.0 / 60.0, 0.8, Vector2.ZERO, 6.0, false, 0.0, false, Vector2.ZERO)
		rigs[1].animate(1.0 / 60.0, 0.8, Vector2.ZERO, 6.0, false, 1.0, false, Vector2.ZERO)
		rigs[2].animate(1.0 / 60.0, 0.8, Vector2(0, 30), 6.0, true, 0.0, false, Vector2.ZERO)
		rigs[3].animate(1.0 / 60.0, 0.8, Vector2.ZERO, 6.0, false, 0.0, true, Vector2.ZERO)
		rigs[4].animate(1.0 / 60.0, 0.8, Vector2(6, 0), 6.0, false, 0.0, false, Vector2.ZERO)
		rigs[5].animate(1.0 / 60.0, 0.8, Vector2.ZERO, 6.0, false, 0.0, false, Vector2(1, 0))
		rigs[6].animate(1.0 / 60.0, 0.8, Vector2(0, -6), 6.0, false, 0.0, false, Vector2.ZERO)
		rigs[7].animate(1.0 / 60.0, 0.8, Vector2(0, 6), 6.0, false, 0.6, false, Vector2.ZERO)
	await _shot("poses.png")
	stage.queue_free()
	await process_frame

	# The real game view after two seconds of bots playing.
	var cfg := Config.new()
	var sim := Sim.new(cfg, 7)
	var view := ArenaView.new()
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
	quit()
