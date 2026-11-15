class_name FigurePreview
extends SubViewportContainer
## A small live picture of one toy figure for the menu: it turns slowly, walks on the spot for a while, then
## stands. It drives a real ToyFigure with a player of its own, so it shows exactly what the game shows.

const WALK_TIME := 3.0
const STAND_TIME := 1.6
const TURN_SPEED := 0.7

var figure: ToyFigure
var _viewport: SubViewport
var _player := SimPlayer.new()
var _sim: Sim
var _time := 0.0
var _walked := 0.0


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff1e0")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	_viewport.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 3.9, 5.6)
	cam.rotation_degrees = Vector3(-27.0, 0.0, 0.0)
	_viewport.add_child(cam)


## Shows figure `kind` in colour `col`. `cfg` gives the sizes the figure reads (player radius and speed).
func show_figure(kind: int, col: Color, cfg: Config) -> void:
	if figure != null:
		_viewport.remove_child(figure)
		figure.queue_free()
	if _sim == null or _sim.cfg != cfg:
		_sim = Sim.new(cfg, 1)
	figure = ToyFigure.new(kind, col)
	_viewport.add_child(figure)
	_player = SimPlayer.new()
	_time = 0.0
	_walked = 0.0


func _process(delta: float) -> void:
	if figure == null or not is_visible_in_tree():
		return
	_time += delta
	var yaw := sin(_time * TURN_SPEED) * 0.9
	var face := Vector2(sin(yaw), cos(yaw))
	_player.facing = face
	_player.aim_dir = face
	if fmod(_time, WALK_TIME + STAND_TIME) < WALK_TIME:
		_walked += _sim.cfg.player_speed * delta
	# Walking on the spot: the drawn position runs ahead and the camera never sees it leave (the figure node is
	# moved back to the middle after the pose has been taken from the movement).
	figure.sync(_player, _sim, face * _walked, delta)
	figure.position = Vector3.ZERO
	figure.scale = Vector3.ONE
