class_name FigurePreview
extends SubViewportContainer
## A small live picture of one figure for the menu: it turns slowly, walks on the spot for a while, then stands.

const WALK_TIME := 3.0
const STAND_TIME := 1.6
const TURN_SPEED := 0.7
const WALK_SPEED := 6.0

var rig: CharacterRig
var _viewport: SubViewport
var _time := 0.0


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
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 0.9
	_viewport.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 4.4, 6.6)
	cam.rotation_degrees = Vector3(-27.0, 0.0, 0.0)
	_viewport.add_child(cam)
	rig = CharacterRig.new()
	_viewport.add_child(rig)


func show_figure(kind: int, col: Color) -> void:
	rig.setup(kind, col)
	rig.pop()
	_time = 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree() or rig.kind < 0:
		return
	_time += delta
	rig.rotation.y = sin(_time * TURN_SPEED) * 0.9
	var walking := fmod(_time, WALK_TIME + STAND_TIME) < WALK_TIME
	var fwd := Vector2(sin(rig.rotation.y), cos(rig.rotation.y))
	rig.animate(delta, 1.0, fwd * WALK_SPEED if walking else Vector2.ZERO, WALK_SPEED, false, 0.0, false, Vector2.ZERO)
