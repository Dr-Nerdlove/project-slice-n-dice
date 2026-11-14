class_name ToyFigure
extends Node3D
## One toy figure, built in code from shared primitive meshes (ToyKit) and animated from ToyMotion's pose.
## The node stands on the floor at the player's drawn position, turned to its facing and scaled by the player
## radius: every size below is in player radii (the body's footprint has radius ~1 = the hit circle), +z is the
## front, +y is up. Structure: self (position, yaw, scale) -> "Pose" (lift, lean, roll, squash) -> pieces
## ("Body", "Head", "ArmL", "ArmR", "FootL", "FootR" and the extras of the kind). On a death the pieces fly apart.
##
## To add a figure: a new ToyPose.Kind (and its CYCLE and gait flavour), a _build_* function below that creates at
## least the six standard pieces, its accent colour in ACCENTS and its name in NAMES.

const NAMES: Array[String] = ["Gummi-Dino", "Aufzieh-Roboter", "Plüschhase", "Quietsche-Ente"]
## The second colour of each toy (spikes, metal and dials, muzzle, beak). None of them is a player colour.
const ACCENTS: Array[Color] = [Color("ffe14d"), Color("c9d2dc"), Color("fff4ea"), Color("ffd21f")]
const WHITE := Color("fbfbf7")
const INK := Color("1d1638")
const DEBRIS_TIME := 1.15          # how long the pieces of a popped toy fly and bounce
const DEBRIS_SHRINK := 0.3         # ... of which the last part they shrink away
const DEBRIS_GRAVITY := 46.0       # radii / s^2
const GHOSTS := 3

var kind := 0
var color := Color.WHITE
var motion: ToyMotion
var body_mat: StandardMaterial3D
var pose_node: Node3D
var pieces: Array[Node3D] = []
var _home: Array[Transform3D] = []
var _twisted: Array[bool] = []      # pieces that turn with the upper body
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _foot_l: Node3D
var _foot_r: Node3D
var _floppy: Array[Node3D] = []     # ears / tail: swing with the EARS channel
var _key: Node3D
var _stars: Node3D
var _shadow: MeshInstance3D
var _ghosts: Array[MeshInstance3D] = []
var _ghost_mat: StandardMaterial3D
var _confetti: CPUParticles3D
var _debris_t := -1.0
var _debris_v: Array[Vector3] = []
var _debris_w: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _pr := 0.5


func _init(figure_kind: int, body_color: Color) -> void:
	kind = figure_kind
	color = body_color
	name = "Toy%d" % figure_kind
	motion = ToyMotion.new(figure_kind)
	_rng.seed = 1234 + figure_kind
	body_mat = ToyKit.new_plastic(color)
	if kind == ToyPose.Kind.BUNNY:
		body_mat.roughness = 1.0
		body_mat.metallic_specular = 0.15
		body_mat.clearcoat_enabled = false
		body_mat.rim = 0.7
		body_mat.rim_tint = 0.85
	pose_node = Node3D.new()
	pose_node.name = "Pose"
	add_child(pose_node)
	match kind:
		ToyPose.Kind.DINO:
			_build_dino()
		ToyPose.Kind.ROBOT:
			_build_robot()
		ToyPose.Kind.BUNNY:
			_build_bunny()
		_:
			_build_duck()
	for pc in pieces:
		_home.append(pc.transform)
		_debris_v.append(Vector3.ZERO)
		_debris_w.append(Vector3.ZERO)
	_shadow = ToyKit.shadow(2.7)
	_shadow.position.y = 0.03
	add_child(_shadow)
	_build_stars()
	_build_ghosts()
	_build_confetti()


# ------------------------------------------------------------------ building

func _piece(piece_name: String, pos: Vector3, twisted := false) -> Node3D:
	var n := Node3D.new()
	n.name = piece_name
	n.position = pos
	pose_node.add_child(n)
	pieces.append(n)
	_twisted.append(twisted)
	return n


func _p(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return ToyKit.part(parent, mesh, mat, pos, size, rot)


## A painted eye on a surface whose outward direction is `dir`: white, pupil, highlight.
func _eye(parent: Node3D, pos: Vector3, dir: Vector3, size: float, tall := 1.15) -> void:
	dir = dir.normalized()
	var b := Basis.looking_at(-dir, Vector3.UP)
	var white := MeshInstance3D.new()
	white.mesh = ToyKit.sphere()
	white.material_override = ToyKit.plastic(WHITE)
	white.transform = Transform3D(b.scaled_local(Vector3(size, size * tall, size * 0.45)), pos)
	parent.add_child(white)
	var pupil := MeshInstance3D.new()
	pupil.mesh = ToyKit.sphere()
	pupil.material_override = ToyKit.plastic(INK)
	pupil.transform = Transform3D(b.scaled_local(Vector3(size * 0.58, size * 0.68, size * 0.3)), pos + dir * size * 0.13)
	parent.add_child(pupil)
	var shine := MeshInstance3D.new()
	shine.mesh = ToyKit.sphere()
	shine.material_override = ToyKit.unshaded(Color.WHITE)
	var up := b.y
	var right := b.x
	shine.transform = Transform3D(Basis().scaled(Vector3.ONE * size * 0.2), pos + dir * size * 0.24 + up * size * 0.18 - right * size * 0.12)
	parent.add_child(shine)


func _arm(piece: Node3D, mat: Material, length: float, thick: float, paw_mat: Material = null) -> void:
	# The arm hangs down from the shoulder (the piece's origin); rotating the piece swings it.
	_p(piece, ToyKit.sphere(), mat, Vector3(0, -length * 0.45, 0), Vector3(thick, length, thick))
	if paw_mat != null:
		_p(piece, ToyKit.sphere(), paw_mat, Vector3(0, -length * 0.88, 0.02), Vector3.ONE * thick * 1.15)


func _build_dino() -> void:
	var acc := ToyKit.plastic(ACCENTS[kind])
	var belly := ToyKit.plastic(Color("fff1c9"))
	var body := _piece("Body", Vector3(0, 0.95, -0.05), true)
	_p(body, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.9, 1.55, 2.0))
	_p(body, ToyKit.sphere(), belly, Vector3(0, -0.05, 0.42), Vector3(1.25, 1.15, 1.1))
	var head := _piece("Head", Vector3(0, 1.95, 0.25))
	_head = head
	_p(head, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.75, 1.45, 1.75))
	_p(head, ToyKit.sphere(), body_mat, Vector3(0, -0.22, 0.78), Vector3(1.15, 0.8, 1.05))   # snout
	_p(head, ToyKit.sphere(), ToyKit.plastic(INK), Vector3(0.2, -0.05, 1.28), Vector3(0.11, 0.08, 0.06))
	_p(head, ToyKit.sphere(), ToyKit.plastic(INK), Vector3(-0.2, -0.05, 1.28), Vector3(0.11, 0.08, 0.06))
	_p(head, ToyKit.sphere(), ToyKit.plastic(Color("e8506a")), Vector3(0, -0.45, 1.1), Vector3(0.5, 0.12, 0.25))  # mouth
	_eye(head, Vector3(0.42, 0.3, 0.62), Vector3(0.45, 0.25, 1.0), 0.48)
	_eye(head, Vector3(-0.42, 0.3, 0.62), Vector3(-0.45, 0.25, 1.0), 0.48)
	# Spikes along the middle, from the forehead down the back to the tail: a line that points where it looks.
	for s in [[Vector3(0, 0.72, 0.15), 0.42, -0.35], [Vector3(0, 0.62, -0.42), 0.48, -0.75]]:
		_p(head, ToyKit.cone(), acc, s[0], Vector3(0.36, s[1], 0.36), Vector3(s[2], 0, 0))
	for s in [[Vector3(0, 0.62, -0.55), 0.5, -0.9], [Vector3(0, 0.25, -0.95), 0.45, -1.25]]:
		_p(body, ToyKit.cone(), acc, s[0], Vector3(0.38, s[1], 0.38), Vector3(s[2], 0, 0))
	var tail := _piece("Tail", Vector3(0, 0.6, -0.95), true)
	_p(tail, ToyKit.cone(), body_mat, Vector3(0, -0.05, -0.55), Vector3(0.75, 1.25, 0.6), Vector3(-1.75, 0, 0))
	_p(tail, ToyKit.cone(), acc, Vector3(0, 0.22, -0.55), Vector3(0.26, 0.36, 0.26), Vector3(-1.2, 0, 0))
	_floppy.append(tail)
	_arm_l = _piece("ArmL", Vector3(-0.85, 1.25, 0.4), true)
	_arm(_arm_l, body_mat, 0.75, 0.38, body_mat)
	_arm_r = _piece("ArmR", Vector3(0.85, 1.25, 0.4), true)
	_arm(_arm_r, body_mat, 0.75, 0.38, body_mat)
	_foot_l = _piece("FootL", Vector3(-0.5, 0.2, 0.1))
	_p(_foot_l, ToyKit.sphere(), body_mat, Vector3(0, 0, 0.12), Vector3(0.7, 0.45, 0.95))
	_p(_foot_l, ToyKit.sphere(), acc, Vector3(0, -0.05, 0.55), Vector3(0.5, 0.2, 0.22))
	_foot_r = _piece("FootR", Vector3(0.5, 0.2, 0.1))
	_p(_foot_r, ToyKit.sphere(), body_mat, Vector3(0, 0, 0.12), Vector3(0.7, 0.45, 0.95))
	_p(_foot_r, ToyKit.sphere(), acc, Vector3(0, -0.05, 0.55), Vector3(0.5, 0.2, 0.22))


func _build_robot() -> void:
	var metal := ToyKit.plastic(ACCENTS[kind])
	var dark := ToyKit.plastic(Color("39405a"))
	var yellow := ToyKit.plastic(Color("ffd21f"))
	var red := ToyKit.plastic(Color("ff4b3e"))
	var rbox := ToyKit.rounded_box(0.3)
	var body := _piece("Body", Vector3(0, 0.95, 0), true)
	_p(body, rbox, body_mat, Vector3.ZERO, Vector3(1.9, 1.1, 1.55))
	_p(body, rbox, ToyKit.plastic(WHITE), Vector3(0, 0.02, 0.74), Vector3(0.95, 0.6, 0.12))      # chest panel
	_p(body, ToyKit.cylinder(), red, Vector3(-0.22, 0.08, 0.82), Vector3(0.2, 0.08, 0.2), Vector3(PI * 0.5, 0, 0))
	_p(body, ToyKit.cylinder(), yellow, Vector3(0.22, 0.08, 0.82), Vector3(0.2, 0.08, 0.2), Vector3(PI * 0.5, 0, 0))
	_p(body, rbox, dark, Vector3(0, -0.15, 0.81), Vector3(0.6, 0.08, 0.05))
	_p(body, ToyKit.cylinder(), metal, Vector3(0, -0.6, 0), Vector3(1.4, 0.14, 1.2))             # waist ring
	var head := _piece("Head", Vector3(0, 2.05, 0.02))
	_head = head
	_p(head, rbox, body_mat, Vector3.ZERO, Vector3(1.75, 1.15, 1.45))
	_p(head, rbox, dark, Vector3(0, -0.02, 0.66), Vector3(1.35, 0.6, 0.2))                     # visor
	_eye(head, Vector3(0.32, 0.0, 0.77), Vector3(0, 0, 1), 0.36, 1.0)
	_eye(head, Vector3(-0.32, 0.0, 0.77), Vector3(0, 0, 1), 0.36, 1.0)
	_p(head, rbox, metal, Vector3(0, -0.42, 0.7), Vector3(0.5, 0.08, 0.08))                    # mouth grille
	_p(head, ToyKit.cylinder(), metal, Vector3(0.92, 0, 0), Vector3(0.36, 0.14, 0.36), Vector3(0, 0, PI * 0.5))
	_p(head, ToyKit.cylinder(), metal, Vector3(-0.92, 0, 0), Vector3(0.36, 0.14, 0.36), Vector3(0, 0, PI * 0.5))
	_p(head, rbox, metal, Vector3(0, 0.6, 0.25), Vector3(1.2, 0.08, 0.35))                     # brow stripe (front)
	_p(head, ToyKit.cylinder(), metal, Vector3(0, 0.85, -0.05), Vector3(0.07, 0.55, 0.07))     # antenna
	_p(head, ToyKit.sphere(), red, Vector3(0, 1.17, -0.05), Vector3.ONE * 0.26)
	# The wind-up key in the back: sticks out behind, so the back is obvious from above; it turns.
	var key := _piece("Key", Vector3(0, 1.05, -0.78), true)
	_key = Node3D.new()
	key.add_child(_key)
	_p(_key, ToyKit.cylinder(), metal, Vector3(0, 0, -0.25), Vector3(0.14, 0.5, 0.14), Vector3(PI * 0.5, 0, 0))
	_p(_key, ToyKit.torus(), yellow, Vector3(0.3, 0, -0.55), Vector3(0.62, 0.9, 0.62), Vector3(0, 0, PI * 0.5))
	_p(_key, ToyKit.torus(), yellow, Vector3(-0.3, 0, -0.55), Vector3(0.62, 0.9, 0.62), Vector3(0, 0, PI * 0.5))
	_arm_l = _piece("ArmL", Vector3(-1.12, 1.3, 0.05), true)
	_p(_arm_l, ToyKit.cylinder(), metal, Vector3(0, -0.38, 0), Vector3(0.24, 0.75, 0.24))
	_p(_arm_l, ToyKit.torus(), dark, Vector3(0, -0.85, 0.02), Vector3(0.46, 0.7, 0.46), Vector3(0, PI * 0.5, PI * 0.5))
	_arm_r = _piece("ArmR", Vector3(1.12, 1.3, 0.05), true)
	_p(_arm_r, ToyKit.cylinder(), metal, Vector3(0, -0.38, 0), Vector3(0.24, 0.75, 0.24))
	_p(_arm_r, ToyKit.torus(), dark, Vector3(0, -0.85, 0.02), Vector3(0.46, 0.7, 0.46), Vector3(0, PI * 0.5, PI * 0.5))
	_foot_l = _piece("FootL", Vector3(-0.42, 0.2, 0.08))
	_p(_foot_l, rbox, dark, Vector3(0, 0, 0.1), Vector3(0.6, 0.4, 1.0))
	_foot_r = _piece("FootR", Vector3(0.42, 0.2, 0.08))
	_p(_foot_r, rbox, dark, Vector3(0, 0, 0.1), Vector3(0.6, 0.4, 1.0))


func _build_bunny() -> void:
	var fluff := ToyKit.plush(ACCENTS[kind])
	var pink := ToyKit.plush(Color("ffb3c8"))
	var body := _piece("Body", Vector3(0, 0.9, -0.05), true)
	_p(body, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.75, 1.55, 1.7))
	_p(body, ToyKit.sphere(), fluff, Vector3(0, -0.1, 0.42), Vector3(1.1, 1.0, 0.95))
	var tail := _piece("Tail", Vector3(0, 0.75, -0.85), true)
	_p(tail, ToyKit.sphere(), fluff, Vector3.ZERO, Vector3.ONE * 0.6)
	var head := _piece("Head", Vector3(0, 1.95, 0.12))
	_head = head
	_p(head, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.85, 1.6, 1.7))
	_p(head, ToyKit.sphere(), fluff, Vector3(0, -0.3, 0.68), Vector3(0.95, 0.65, 0.55))       # muzzle
	_p(head, ToyKit.sphere(), ToyKit.plastic(Color("e0457b")), Vector3(0, -0.1, 0.95), Vector3(0.28, 0.2, 0.18))
	# Button eyes: shiny black with a highlight.
	for sx in [-1.0, 1.0]:
		var dir := Vector3(sx * 0.5, 0.25, 1.0).normalized()
		var p := Vector3(sx * 0.4, 0.22, 0.72)
		_p(head, ToyKit.sphere(), ToyKit.plastic(INK), p, Vector3(0.3, 0.32, 0.18))
		_p(head, ToyKit.sphere(), ToyKit.unshaded(Color.WHITE), p + dir * 0.09 + Vector3(-sx * 0.04, 0.07, 0), Vector3.ONE * 0.08)
	# Long floppy ears lying back over the head: a V that points backwards, seen from above.
	for sx in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.name = "EarL" if sx < 0 else "EarR"
		ear.position = Vector3(sx * 0.38, 0.6, -0.1)
		ear.rotation = Vector3(-1.05, sx * 0.3, sx * -0.35)
		head.add_child(ear)
		_p(ear, ToyKit.sphere(), body_mat, Vector3(0, 0.65, 0), Vector3(0.5, 1.45, 0.24))
		_p(ear, ToyKit.sphere(), pink, Vector3(0, 0.65, 0.07), Vector3(0.3, 1.1, 0.14))
		_floppy.append(ear)
	_arm_l = _piece("ArmL", Vector3(-0.78, 1.25, 0.3), true)
	_arm(_arm_l, body_mat, 0.7, 0.42, body_mat)
	_arm_r = _piece("ArmR", Vector3(0.78, 1.25, 0.3), true)
	_arm(_arm_r, body_mat, 0.7, 0.42, body_mat)
	_foot_l = _piece("FootL", Vector3(-0.45, 0.18, 0.15))
	_p(_foot_l, ToyKit.sphere(), body_mat, Vector3(0, 0, 0.15), Vector3(0.62, 0.4, 1.1))
	_p(_foot_l, ToyKit.sphere(), pink, Vector3(0, -0.12, 0.15), Vector3(0.45, 0.2, 0.8))
	_foot_r = _piece("FootR", Vector3(0.45, 0.18, 0.15))
	_p(_foot_r, ToyKit.sphere(), body_mat, Vector3(0, 0, 0.15), Vector3(0.62, 0.4, 1.1))
	_p(_foot_r, ToyKit.sphere(), pink, Vector3(0, -0.12, 0.15), Vector3(0.45, 0.2, 0.8))


func _build_duck() -> void:
	var beak := ToyKit.plastic(ACCENTS[kind])
	var body := _piece("Body", Vector3(0, 0.82, -0.05), true)
	_p(body, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(2.0, 1.55, 2.25))
	var tail := _piece("Tail", Vector3(0, 1.05, -0.95), true)
	_p(tail, ToyKit.cone(), body_mat, Vector3(0, 0.12, -0.15), Vector3(0.9, 0.85, 0.55), Vector3(-0.85, 0, 0))
	_floppy.append(tail)
	var head := _piece("Head", Vector3(0, 1.95, 0.38))
	_head = head
	_p(head, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.55, 1.5, 1.5))
	# The big beak sticks out in front: an arrow from above.
	_p(head, ToyKit.sphere(), beak, Vector3(0, -0.2, 0.82), Vector3(0.95, 0.32, 0.95))
	_p(head, ToyKit.sphere(), beak, Vector3(0, -0.36, 0.72), Vector3(0.7, 0.2, 0.7))
	_p(head, ToyKit.cone(), body_mat, Vector3(0.05, 0.78, -0.05), Vector3(0.22, 0.4, 0.22), Vector3(-0.5, 0, 0.3))  # tuft
	_eye(head, Vector3(0.36, 0.22, 0.58), Vector3(0.5, 0.2, 1.0), 0.36)
	_eye(head, Vector3(-0.36, 0.22, 0.58), Vector3(-0.5, 0.2, 1.0), 0.36)
	# Wings are the arms.
	_arm_l = _piece("ArmL", Vector3(-0.95, 1.15, 0.0), true)
	_p(_arm_l, ToyKit.sphere(), body_mat, Vector3(0, -0.25, -0.1), Vector3(0.32, 0.8, 1.1), Vector3(0.3, 0, 0))
	_arm_r = _piece("ArmR", Vector3(0.95, 1.15, 0.0), true)
	_p(_arm_r, ToyKit.sphere(), body_mat, Vector3(0, -0.25, -0.1), Vector3(0.32, 0.8, 1.1), Vector3(0.3, 0, 0))
	_foot_l = _piece("FootL", Vector3(-0.42, 0.08, 0.35))
	_p(_foot_l, ToyKit.sphere(), beak, Vector3(0, 0, 0.15), Vector3(0.65, 0.16, 0.8))
	_foot_r = _piece("FootR", Vector3(0.42, 0.08, 0.35))
	_p(_foot_r, ToyKit.sphere(), beak, Vector3(0, 0, 0.15), Vector3(0.65, 0.16, 0.8))


func _build_stars() -> void:
	_stars = Node3D.new()
	_stars.name = "Stars"
	_stars.position = Vector3(0, 3.3, 0)
	_stars.visible = false
	add_child(_stars)
	for k in 3:
		var a := TAU * k / 3.0
		_p(_stars, ToyKit.diamond(), ToyKit.unshaded(Color("ffe14d")), Vector3(cos(a), 0, sin(a)) * 0.85, Vector3(0.32, 0.45, 0.32))


## Short trail of see-through copies behind a dash or a pull (three spheres that follow each other with a lag).
func _build_ghosts() -> void:
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
	for k in GHOSTS:
		var g := MeshInstance3D.new()
		g.mesh = ToyKit.sphere()
		g.material_override = _ghost_mat
		g.top_level = true
		g.visible = false
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.name = "Ghost%d" % k
		add_child(g)
		_ghosts.append(g)


func _build_confetti() -> void:
	var c := CPUParticles3D.new()
	c.name = "Confetti"
	c.top_level = true
	c.emitting = false
	c.one_shot = true
	c.explosiveness = 1.0
	c.amount = 40
	c.lifetime = 1.1
	c.direction = Vector3.UP
	c.spread = 70.0
	c.initial_velocity_min = 3.0
	c.initial_velocity_max = 7.0
	c.gravity = Vector3(0, -9.0, 0)
	c.damping_min = 1.5
	c.damping_max = 3.0
	c.angular_velocity_min = -540.0
	c.angular_velocity_max = 540.0
	c.angle_min = 0.0
	c.angle_max = 360.0
	c.scale_amount_min = 0.7
	c.scale_amount_max = 1.3
	c.particle_flag_rotate_y = true
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.09)
	c.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	c.material_override = m
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color.WHITE)
	g.add_point(0.6, color.lightened(0.35))
	c.color_initial_ramp = g
	add_child(c)
	_confetti = c


# ------------------------------------------------------------------ per frame

## One frame: reads player `p` from `src` (the sim the view draws it from), drawn at ground position `drawn`.
func sync(p: SimPlayer, src: Sim, drawn: Vector2, dt: float) -> void:
	motion.update(p, src, drawn, dt)
	_pr = src.cfg.player_radius
	scale = Vector3.ONE * _pr
	if motion.spawned:
		_reset_pieces()
	if motion.popped:
		_pop()
	if not p.enabled:
		visible = false
		_hide_ghosts()
		return
	if not p.alive:
		_step_debris(dt)
		_hide_ghosts()
		return
	visible = true
	position = Vector3(drawn.x, 0.0, drawn.y)
	rotation = Vector3(0.0, motion.yaw, 0.0)
	_apply_pose()
	_step_ghosts(dt)


func _apply_pose() -> void:
	var s := motion.shown
	var f := motion.facts
	var sy := maxf(s[ToyPose.SQUASH], 0.3)
	var sz := maxf(s[ToyPose.STRETCH], 0.3)
	var sx := 1.0 / sqrt(sy * sz)
	var tr := s[ToyPose.TREMBLE]
	pose_node.position = Vector3(sin(f.time * 83.0) * tr, maxf(s[ToyPose.LIFT], 0.0), cos(f.time * 71.0) * tr)
	pose_node.basis = Basis.from_euler(Vector3(s[ToyPose.LEAN], 0.0, s[ToyPose.ROLL])).scaled_local(Vector3(sx, sy, sz))
	var twist := s[ToyPose.TWIST]
	var tb := Basis(Vector3.UP, twist)
	for k in pieces.size():
		if _twisted[k]:
			pieces[k].transform = Transform3D(tb, Vector3.ZERO) * _home[k]
	# Head: nods with HEAD, keeps looking where the player aims (counter-twist), bobs a little while walking.
	var bob := sin(f.gait * 2.0) * 0.06 * s[ToyPose.STEP] if kind != ToyPose.Kind.ROBOT else 0.0
	_head.transform = _home[pieces.find(_head)]
	_head.rotation = Vector3(s[ToyPose.HEAD], 0.0, bob)
	# Arms: the yo-yo arm (right, +x) swings back over the shoulder (wind-up) or forward; the other swings with the gait.
	var arm := s[ToyPose.ARM]
	var ang := arm * (1.5 if arm >= 0.0 else 2.5)
	_arm_r.rotation = Vector3(ang, twist, -0.35 * clampf(arm, 0.0, 1.0) - 0.15)
	var swing := sin(f.gait) * 0.6 * s[ToyPose.STEP]
	var other := swing
	if motion.act == ToyPose.Act.DASH or motion.act == ToyPose.Act.PULL:
		other = 0.9 if motion.act == ToyPose.Act.PULL else -1.2
	elif motion.act == ToyPose.Act.STUN:
		other = sin(f.time * 9.0) * 0.8
	elif motion.act == ToyPose.Act.CHARGE:
		other = 0.6 * f.charge      # the free arm points at the target
	_arm_l.rotation = Vector3(other, twist, 0.15)
	_feet(s, f)
	for fl in _floppy:
		if fl.get_parent() == pose_node:
			fl.rotate_object_local(Vector3.RIGHT, -0.5 * s[ToyPose.EARS])   # tail (already placed with the twist)
		else:
			fl.basis = _ear_basis(fl, s[ToyPose.EARS])
	if _key != null:
		_key.rotation = Vector3(0.0, 0.0, motion.wind)
	var dz := s[ToyPose.DIZZY]
	_stars.visible = dz > 0.05
	if _stars.visible:
		_stars.rotation.y = f.time * 6.0
		_stars.scale = Vector3.ONE * dz
	_shadow.scale = Vector3.ONE * 2.7 / (1.0 + maxf(s[ToyPose.LIFT], 0.0) * 0.35)


## Ears lying back, swung by EARS (the base rotation is kept in the node's metadata).
func _ear_basis(ear: Node3D, swing: float) -> Basis:
	if not ear.has_meta("rest"):
		ear.set_meta("rest", ear.rotation)
	var r: Vector3 = ear.get_meta("rest")
	return Basis.from_euler(Vector3(r.x - 0.55 * swing, r.y, r.z))


func _feet(s: Array[float], f: ToyPose.Facts) -> void:
	var step := s[ToyPose.STEP]
	var kl := pieces.find(_foot_l)
	var kr := pieces.find(_foot_r)
	var hl := _home[kl].origin
	var hr := _home[kr].origin
	var a := sin(f.gait)
	var b := sin(f.gait + PI)
	if kind == ToyPose.Kind.ROBOT:
		a = clampf(a * 3.0, -1.0, 1.0)
		b = -a
	elif kind == ToyPose.Kind.BUNNY:
		b = a                          # both feet together: hops
	var stride := 0.38 * step
	var up := 0.22 * step
	_foot_l.position = hl + Vector3(0.0, maxf(0.0, cos(f.gait)) * up if kind != ToyPose.Kind.BUNNY else 0.0, a * stride)
	_foot_r.position = hr + Vector3(0.0, maxf(0.0, -cos(f.gait)) * up if kind != ToyPose.Kind.BUNNY else 0.0, b * stride)
	var tuck := 0.0
	if motion.act == ToyPose.Act.PULL or motion.act == ToyPose.Act.DASH:
		tuck = -0.7                    # feet trail behind
	_foot_l.rotation = Vector3(tuck - a * 0.3 * step, 0.0, 0.0)
	_foot_r.rotation = Vector3(tuck - b * 0.3 * step, 0.0, 0.0)


func _step_ghosts(dt: float) -> void:
	if not is_inside_tree():
		return
	var on := motion.act == ToyPose.Act.DASH or motion.act == ToyPose.Act.PULL or motion.act == ToyPose.Act.DASH_STOP
	var lead := global_position + Vector3(0, (1.0 + motion.shown[ToyPose.LIFT]) * _pr, 0)
	var k_follow := 1.0 - exp(-26.0 * dt)
	for k in _ghosts.size():
		var g := _ghosts[k]
		if not on:
			g.visible = false
			g.global_position = lead
			lead = g.global_position
			continue
		if not g.visible:
			g.global_position = lead
		g.global_position = g.global_position.lerp(lead, k_follow)
		var d := g.global_position.distance_to(global_position + Vector3(0, _pr, 0))
		g.visible = d > _pr * 0.8
		var r := _pr * (1.7 - 0.3 * k)
		g.scale = Vector3(r, r * 0.9, r)
		g.transparency = 0.25 + 0.2 * k
		lead = g.global_position


func _hide_ghosts() -> void:
	for g in _ghosts:
		g.visible = false


# ------------------------------------------------------------------ death and respawn

## The toy pops into its pieces, which fly, bounce and vanish; confetti in the player colour.
func _pop() -> void:
	pose_node.transform = Transform3D.IDENTITY
	_stars.visible = false
	_shadow.visible = false
	for k in pieces.size():
		var pc := pieces[k]
		pc.transform = _home[k]
		var out := Vector3(pc.position.x, 0.0, pc.position.z)
		if out.length() < 0.2:
			out = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		out = out.normalized() * _rng.randf_range(3.0, 6.5)
		_debris_v[k] = out + Vector3(0, _rng.randf_range(8.0, 13.0), 0)
		_debris_w[k] = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-8, 8), _rng.randf_range(-12, 12))
	_debris_t = 0.0
	if is_inside_tree():
		_confetti.global_position = global_position + Vector3(0, _pr * 1.6, 0)
		_confetti.restart()


func _step_debris(dt: float) -> void:
	if _debris_t < 0.0:
		visible = false
		return
	_debris_t += dt
	if _debris_t >= DEBRIS_TIME:
		_debris_t = -1.0
		visible = false
		return
	visible = true
	var shrink := clampf((DEBRIS_TIME - _debris_t) / DEBRIS_SHRINK, 0.0, 1.0)
	for k in pieces.size():
		var pc := pieces[k]
		var v := _debris_v[k]
		v.y -= DEBRIS_GRAVITY * dt
		var p := pc.position + v * dt
		if p.y < 0.25 and v.y < 0.0:
			p.y = 0.25
			v = Vector3(v.x * 0.6, -v.y * 0.42, v.z * 0.6)
			_debris_w[k] *= 0.6
		_debris_v[k] = v
		pc.position = p
		var w := _debris_w[k] * dt
		pc.basis = (pc.basis * Basis.from_euler(w)).orthonormalized()
		pc.scale = Vector3.ONE * shrink


func _reset_pieces() -> void:
	_debris_t = -1.0
	_shadow.visible = true
	pose_node.transform = Transform3D.IDENTITY
	for k in pieces.size():
		pieces[k].transform = _home[k]


# ------------------------------------------------------------------ for the view and the tests

## Stun: the body flashes white.
func flash(on: bool) -> void:
	body_mat.albedo_color = Color(1, 1, 1) if on else color


## Where the yo-yo held in the hand is drawn (world position): in front of the belly at rest (the same spot
## ClientCore assumes for the other players), behind and above the shoulder when wound up for a throw.
func hand_point(pos: Vector2, face: Vector2, hr: float, rest_y: float) -> Vector3:
	var back := motion.wind_up()
	var side := Vector2(face.y, -face.x)
	var fwd := (_pr + hr * 0.4) * (1.0 - back) - (_pr * 1.1 + hr) * back
	var reach := maxf(motion.shown[ToyPose.ARM] - 0.3, 0.0) * _pr * 0.5
	var hp := pos + face * (fwd + reach) + side * back * _pr * 0.8
	var tr := motion.shown[ToyPose.TREMBLE] * _pr
	var t := motion.facts.time
	hp += Vector2(sin(t * 83.0), cos(t * 71.0)) * tr
	var y := lerpf(rest_y, _pr * 2.9, back) + maxf(motion.shown[ToyPose.LIFT], 0.0) * _pr
	return Vector3(hp.x, y, hp.y)


## Footprint radius of the body shell (the first mesh of the "Body" piece), in player radii: half its larger
## horizontal size plus its offset. The hit circle has radius 1.
func body_footprint() -> float:
	var shell := (pose_node.get_node("Body") as Node3D).get_child(0) as MeshInstance3D
	var ext := shell.transform.basis.get_scale() * 0.5
	return maxf(absf(shell.position.x) + ext.x, absf(shell.position.z) + ext.z)
