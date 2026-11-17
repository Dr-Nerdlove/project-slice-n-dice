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
const SETTLE_STEPS := 45
const DTS := [1.0 / 60.0, 1.0 / 30.0]
const WARM_BUDGET := 4000   # microseconds of measuring per frame while the lobby is idle
const SAMPLE_EVERY := 4   # `_measure` takes the corners of the figure's meshes every this many poses
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
var _job := {}   # the measuring in progress (see `_job_begin`)
var _warm: Array[int] = []   # kinds still to measure in idle frames
var _warm_cfg: Config
## What a figure's show occupies, per figure kind and sizes: {"points": Array[Vector3], "bounds": AABB}. It does not
## depend on the colour, and measuring is the expensive part (about 0.8 s on a PC), so it is done once per kind.
static var _measured := {}


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


## The cache key of a kind's measurement.
static func _key(kind: int, cfg: Config) -> String:
	return "%d:%f:%f" % [kind, cfg.player_radius, cfg.player_speed]


## True when the measurement of `kind` is done (shown at once, no work on a click).
static func is_measured(kind: int, cfg: Config) -> bool:
	return _measured.has(_key(kind, cfg))


## Starts measuring what a figure really occupies: a scratch copy (hidden) plays the whole walk-and-stand cycle
## and every pose's meshes count (arms, jaw, ears, hops). It is done in pieces (`_job_step`) so the lobby can do it
## in idle frames; `_measure` finishes it at once. Needs the preview to be in the tree.
func _job_begin(kind: int, cfg: Config) -> void:
	_job_end()
	var fig := ToyFigure.new(kind, Color.WHITE)
	fig.visible = false
	_viewport.add_child(fig)
	var p := SimPlayer.new()
	var sim := Sim.new(cfg, 1)
	_job = {"settled": 0, "key": _key(kind, cfg), "cfg": cfg, "fig": fig, "p": p, "sim": sim, "pass": 0, "t": 0.0, "walked": 0.0, "steps": 0, "pts": [] as Array[Vector3], "seen": {}}


func _job_end() -> void:
	if not _job.is_empty():
		var fig: ToyFigure = _job["fig"]
		_viewport.remove_child(fig)
		fig.free()
		_job = {}


## Works on the job for at most `budget_usec` microseconds (0 = until it is done). True when it is finished (the
## result is in the cache).
func _job_step(budget_usec: int) -> bool:
	if _job.is_empty():
		return true
	var started := Time.get_ticks_usec()
	var fig: ToyFigure = _job["fig"]
	var cfg: Config = _job["cfg"]
	var pts: Array[Vector3] = _job["pts"]
	var seen: Dictionary = _job["seen"]
	var dt: float = DTS[_job["pass"]]   # (the springs move a little differently at other frame rates)
	while true:
		if _job["t"] >= TURN_PERIOD + WALK_TIME + STAND_TIME:   # (the turning and the walk-and-stand cycle are out of step)
			_job["pass"] += 1
			if _job["pass"] >= DTS.size():
				break
			dt = DTS[_job["pass"]]
			_job["t"] = 0.0
			_job["walked"] = 0.0
			_job["steps"] = 0
			_job["settled"] = 0
		if _job["settled"] < SETTLE_STEPS:   # (the drop-in, a pose at a time like everything else)
			_pose(fig, _job["p"], _job["sim"], 0.0, 0.0, 1.0 / 30.0)
			_job["settled"] += 1
			if budget_usec > 0 and Time.get_ticks_usec() - started >= budget_usec:
				return false
			continue
		_job["t"] += dt
		if fmod(_job["t"], WALK_TIME + STAND_TIME) < WALK_TIME:
			_job["walked"] += cfg.player_speed * dt
		_pose(fig, _job["p"], _job["sim"], _job["t"], _job["walked"], dt)
		_job["steps"] += 1
		if _job["steps"] % SAMPLE_EVERY == 0:   # (every pose steps the springs, but the corners are taken every few steps)
			for v in figure_points(fig):
				var w: Vector3 = fig.transform * v   # (turned as the figure is at this moment)
				var key := Vector3i((w * 50.0).round())
				if not seen.has(key):   # (a point per 2 cm is plenty)
					seen[key] = true
					pts.append(w)
		if budget_usec > 0 and _job["steps"] % 8 == 0 and Time.get_ticks_usec() - started >= budget_usec:
			return false
	_measured[_job["key"]] = {"points": pts, "bounds": box_of(pts)}
	_job_end()
	return true


## The bounds of `kind`'s show (and `points`, what the camera frames), measured now unless already known.
func _measure(kind: int, cfg: Config) -> AABB:
	var k := _key(kind, cfg)
	if not _measured.has(k):
		if _job.is_empty() or _job["key"] != k:
			_job_begin(kind, cfg)
		_job_step(0)
	points = _measured[k]["points"]
	return _measured[k]["bounds"]


## A new figure first "drops in" as at a respawn; the picture lets that pass unseen (and unmeasured), so the
## figure just stands there when it is shown.
static func _settle(fig: ToyFigure, p: SimPlayer, sim: Sim) -> void:
	for _i in SETTLE_STEPS:
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
	if (not n.visible and not is_root) or n == skip or n.name == &"ColorRing":   # (the blob shadow and the floor ring are not the figure)
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
	if figure != null and figure.kind == kind and _sim != null and _sim.cfg == cfg:
		figure.recolor(col)   # only the colour changed: the same figure, measured, framed and posed already
		return
	if figure != null:
		_viewport.remove_child(figure)
		figure.queue_free()
	if _sim == null or _sim.cfg != cfg:
		_sim = Sim.new(cfg, 1)
	figure = ToyFigure.new(kind, col)
	_viewport.add_child(figure)
	bounds = _measure(kind, cfg)
	_reframe()
	_player = SimPlayer.new()
	_settle(figure, _player, _sim)
	_time = 0.0
	_walked = 0.0


## Measures the figures not measured yet in idle frames (a little each frame), so that choosing one later costs
## nothing. Called when the lobby opens.
func warm_up(cfg: Config) -> void:
	_warm_cfg = cfg
	_warm.clear()
	for k in Config.SKIN_COUNT:
		if not is_measured(k, cfg):
			_warm.append(k)


func _process(delta: float) -> void:
	if not _warm.is_empty() and is_visible_in_tree():
		var k: int = _warm[0]
		if is_measured(k, _warm_cfg):
			_warm.remove_at(0)
		else:
			if _job.is_empty():
				_job_begin(k, _warm_cfg)
			if _job_step(WARM_BUDGET):
				_warm.remove_at(0)
	if figure == null or not is_visible_in_tree():
		return
	if size != _framed_for:
		_reframe()
	_time += delta
	var walking := fmod(_time, WALK_TIME + STAND_TIME) < WALK_TIME
	if walking:
		_walked += _sim.cfg.player_speed * delta
	_pose(figure, _player, _sim, _time, _walked, delta)
