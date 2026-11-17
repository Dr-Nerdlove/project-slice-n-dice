class_name FigurePreview
extends SubViewportContainer
## A small live picture of one toy figure for the menu: it turns slowly, walks on the spot for a while, then
## stands. It drives a real ToyFigure with a player of its own, so it shows exactly what the game shows.

const WALK_TIME := 3.0
const STAND_TIME := 1.6
const TURN_SPEED := 0.7
const TURN_PERIOD := TAU / TURN_SPEED   # the turning repeats after this long
const FOV := 30.0
const PITCH_DEG := -27.0
const FILL := 0.97     # the framed box fills at most this much of the picture each way
const MARGIN := 1.05   # room round the measured box

var figure: ToyFigure
var camera: Camera3D
var bounds := AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))   # the box round everything the figure does in its show
var points: Array[Vector3] = []   # the corners of every mesh in every pose of the show (what the camera frames)
var _framed_for := Vector2.ZERO
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
	camera = Camera3D.new()
	camera.fov = FOV
	camera.position = Vector3(0.0, 3.9, 5.6)
	camera.rotation_degrees = Vector3(PITCH_DEG, 0.0, 0.0)
	_viewport.add_child(camera)


## The corners of every visible mesh of `fig` (without its blob shadow) in the figure's own frame.
static func figure_points(fig: Node3D) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	_collect(fig, Transform3D.IDENTITY, true, pts, fig.get("_shadow"))
	return pts


## The box a figure occupies, from points taken in its poses in the preview's frame (turned as it turns, so the
## box is as wide as the figure really gets and not as a full turn would make it): symmetric round the vertical
## axis and grown by MARGIN round its centre.
static func box_of(pts: Array[Vector3]) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var rx := 0.0
	var rz := 0.0
	for v in pts:
		lo = lo.min(v)
		hi = hi.max(v)
		rx = maxf(rx, absf(v.x))
		rz = maxf(rz, absf(v.z))
	var c := Vector3(0.0, (lo.y + hi.y) * 0.5, 0.0)
	var half := Vector3(rx, (hi.y - lo.y) * 0.5, rz) * MARGIN
	return AABB(c - half, half * 2.0)


## What the figure really occupies: a scratch copy plays the whole walk-and-stand cycle once and every pose's
## meshes count (arms, jaw, ears, hops). Needs the preview to be in the tree.
func _measure(kind: int, col: Color, cfg: Config) -> AABB:
	var pts: Array[Vector3] = []
	for dt in [1.0 / 60.0, 1.0 / 30.0]:   # (the springs move a little differently at other frame rates)
		var fig := ToyFigure.new(kind, col)
		_viewport.add_child(fig)
		var p := SimPlayer.new()
		var sim := Sim.new(cfg, 1)
		_settle(fig, p, sim)
		var t := 0.0
		var walked := 0.0
		while t < TURN_PERIOD + WALK_TIME + STAND_TIME:   # (the turning and the walk-and-stand cycle are out of step)
			t += dt
			if fmod(t, WALK_TIME + STAND_TIME) < WALK_TIME:
				walked += cfg.player_speed * dt
			_pose(fig, p, sim, t, walked, dt)
			for v in figure_points(fig):
				pts.append(fig.transform * v)   # (turned as the figure is at this moment)
		_viewport.remove_child(fig)
		fig.free()
	var seen := {}
	points = []
	for v in pts:   # (a point per 2 cm is plenty)
		var key := Vector3i((v * 50.0).round())
		if not seen.has(key):
			seen[key] = true
			points.append(v)
	return box_of(pts)


## A new figure first "drops in" as at a respawn; the picture lets that pass unseen (and unmeasured), so the
## figure just stands there when it is shown.
static func _settle(fig: ToyFigure, p: SimPlayer, sim: Sim) -> void:
	for _i in 45:
		_pose(fig, p, sim, 0.0, 0.0, 1.0 / 30.0)


## Poses `fig` for time `t` of the preview's little show (turning, walking on the spot, standing).
static func _pose(fig: ToyFigure, p: SimPlayer, sim: Sim, t: float, walked: float, dt: float) -> void:
	var yaw := sin(t * TURN_SPEED) * 0.9
	var face := Vector2(sin(yaw), cos(yaw))
	p.facing = face
	p.aim_dir = face
	# Walking on the spot: the drawn position runs ahead and the camera never sees it leave (the figure node is
	# moved back to the middle after the pose has been taken from the movement).
	fig.sync(p, sim, face * walked, dt)
	fig.position = Vector3.ZERO
	fig.scale = Vector3.ONE


static func _collect(n: Node3D, to_fig: Transform3D, is_root: bool, out: Array[Vector3], skip: Node) -> void:
	var t := to_fig if is_root else to_fig * n.transform
	if not n.visible or n == skip or n.name == &"ColorRing":   # (the blob shadow and the floor ring are not the figure)
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var box := (n as MeshInstance3D).get_aabb()
		for i in 8:
			out.append(t * box.get_endpoint(i))
	for c in n.get_children():
		if c is Node3D:
			_collect(c, t, false, out, skip)


## The camera transform that looks along the preview's fixed downward angle from far enough, and shifted
## sideways and up so, that every point of `pts` is inside a picture of this aspect (width / height) with the
## vertical field `fov` (and a little room: FILL). Fits the points themselves, not a box round them, so the
## figure fills the picture as far as it can.
static func frame(pts: Array[Vector3], fov: float, aspect: float) -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(PITCH_DEG), 0.0, 0.0))
	var f := -basis.z
	var ty := tan(deg_to_rad(fov) * 0.5) * FILL
	var tx := ty * aspect
	if pts.is_empty():
		return Transform3D(basis, -f * 8.0)
	# Per axis: the camera at distance d and offset o needs |u - o| <= t * (d + depth) for every point; the
	# smallest d is (max(u / t - depth) + max(-u / t - depth)) / 2, at offset o = t * (max(u / t - depth) - max(-u / t - depth)) / 2.
	var up_x := -INF
	var dn_x := -INF
	var up_y := -INF
	var dn_y := -INF
	for v in pts:
		var depth := v.dot(f)
		var ux := v.dot(basis.x)
		var uy := v.dot(basis.y)
		up_x = maxf(up_x, ux / tx - depth)
		dn_x = maxf(dn_x, -ux / tx - depth)
		up_y = maxf(up_y, uy / ty - depth)
		dn_y = maxf(dn_y, -uy / ty - depth)
	var d := maxf(maxf((up_x + dn_x) * 0.5, (up_y + dn_y) * 0.5), 0.1)
	# With d fixed, any offset between the two limits works; take the middle of the allowed range.
	var ox := tx * (up_x - dn_x) * 0.5
	var oy := ty * (up_y - dn_y) * 0.5
	return Transform3D(basis, -f * d + basis.x * ox + basis.y * oy)


## True when every point of the figure's show is inside the picture with the camera as it is now.
func fits() -> bool:
	if size.x < 1.0 or size.y < 1.0 or points.is_empty():
		return false
	var inv := camera.transform.affine_inverse()
	var ty := tan(deg_to_rad(camera.fov) * 0.5)
	var tx := ty * size.x / size.y
	for p in points:
		var v := inv * p
		if v.z >= -0.01 or absf(v.x) > -v.z * tx or absf(v.y) > -v.z * ty:
			return false
	return true


## How much of the picture's height the figure (as posed now) fills with the camera as it is: 0..1.
func height_fraction() -> float:
	if figure == null or size.x < 1.0 or size.y < 1.0:
		return 0.0
	var inv := camera.transform.affine_inverse()
	var ty := tan(deg_to_rad(camera.fov) * 0.5)
	var lo := INF
	var hi := -INF
	for v in figure_points(figure):
		var q := inv * figure.global_transform * v
		if q.z < -0.01:
			var y := q.y / (-q.z * ty)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return (hi - lo) * 0.5


func _reframe() -> void:
	_framed_for = size
	if size.x >= 1.0 and size.y >= 1.0:
		camera.transform = frame(points, camera.fov, size.x / size.y)


## Shows figure `kind` in colour `col`. `cfg` gives the sizes the figure reads (player radius and speed).
func show_figure(kind: int, col: Color, cfg: Config) -> void:
	if figure != null:
		_viewport.remove_child(figure)
		figure.queue_free()
	if _sim == null or _sim.cfg != cfg:
		_sim = Sim.new(cfg, 1)
	figure = ToyFigure.new(kind, col)
	_viewport.add_child(figure)
	bounds = _measure(kind, col, cfg)
	_reframe()
	_player = SimPlayer.new()
	_settle(figure, _player, _sim)
	_time = 0.0
	_walked = 0.0


func _process(delta: float) -> void:
	if figure == null or not is_visible_in_tree():
		return
	if size != _framed_for:
		_reframe()
	_time += delta
	var walking := fmod(_time, WALK_TIME + STAND_TIME) < WALK_TIME
	if walking:
		_walked += _sim.cfg.player_speed * delta
	_pose(figure, _player, _sim, _time, _walked, delta)
