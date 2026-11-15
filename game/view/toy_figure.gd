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

const NAMES: Array[String] = [
	"Schnapp-Dino", "Aufzieh-Roboter", "Plüschhase", "Quietsche-Ente", "Springteufel", "Würfel", "Stehauf-Püppchen",
	"Kreisel"]
## The second colour of each toy (spikes, metal and dials, muzzle, beak, horns and ruff, pips, face, band). None
## of them is a player colour.
const ACCENTS: Array[Color] = [
	Color("ffe14d"), Color("c9d2dc"), Color("fff4ea"), Color("ffd21f"), Color("fff1c9"), Color("fbfbf7"),
	Color("ffe9d2"), Color("ffe14d")]
const BLUSH := Color("ff8fa8")
## Where the yo-yo hand goes, in the figure's units: holding the yo-yo in front of the belly, wound up behind the
## shoulder, and how far it reaches along the string. The arm only points there; the yo-yo sits in the real hand.
const HAND_HOLD := Vector3(0.3, 0.85, 1.25)
const HAND_WOUND := Vector3(1.15, 2.4, -0.95)
const HAND_REACH := 1.3
const BLINK_TIME := 0.11
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
var _spin: Node3D                   # spinning top: the part that turns
var _jaw: Node3D                    # snapper dino: the hinged lower jaw
var _tail: Node3D                   # snapper dino: the tail that swings sideways
var _wheels: Array[Node3D] = []     # pull-along duck: the four wheels
var _base: Node3D                   # spinning top: the base (cone and skirt) that turns at its own speed
var _coils: Array[Node3D] = []      # imp: the rings of its spring
var _paw: Node3D                    # the end of the yo-yo arm: where the yo-yo and its string are held
var _eyes: Array[Node3D] = []
var _blink := 2.0
## World direction from the player to where its string leads (the first bounce point or the yo-yo); ZERO while
## no yo-yo is out. Set by the view before `sync`: the yo-yo arm points along it.
var string_dir := Vector2.ZERO
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
	if kind == ToyPose.Kind.DUCK or kind == ToyPose.Kind.DOLL:     # painted wood: matte
		body_mat.roughness = 0.8
		body_mat.metallic_specular = 0.25
		body_mat.clearcoat_enabled = false
		body_mat.rim = 0.4
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
		ToyPose.Kind.DUCK:
			_build_duck()
		ToyPose.Kind.IMP:
			_build_imp()
		ToyPose.Kind.DIE:
			_build_die()
		ToyPose.Kind.DOLL:
			_build_doll()
		_:
			_build_top()
	_blink = _rng.randf_range(0.6, 3.5)
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


## A painted eye on a surface whose outward direction is `dir`: white, pupil, highlight. It blinks.
func _eye(parent: Node3D, pos: Vector3, dir: Vector3, size: float, tall := 1.15, pupil := 0.58) -> void:
	dir = dir.normalized()
	var eye := Node3D.new()
	eye.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)
	eye.set_meta("open", eye.basis)
	parent.add_child(eye)
	_eyes.append(eye)
	_p(eye, ToyKit.sphere(), ToyKit.plastic(WHITE), Vector3.ZERO, Vector3(size, size * tall, size * 0.45))
	_p(eye, ToyKit.sphere(), ToyKit.plastic(INK), Vector3(0, 0, size * 0.13), Vector3(size * pupil, size * (pupil + 0.1), size * 0.3))
	_p(eye, ToyKit.sphere(), ToyKit.unshaded(Color.WHITE), Vector3(-size * 0.12, size * 0.18, size * 0.24), Vector3.ONE * size * 0.2)


## A soft pink cheek.
func _blush(parent: Node3D, pos: Vector3, size: float) -> void:
	_p(parent, ToyKit.sphere(), ToyKit.plush(BLUSH), pos, Vector3(size, size * 0.6, size * 0.35))


## Marks the end of the yo-yo arm (`length` below its shoulder).
func _set_paw(length: float) -> void:
	_paw = Node3D.new()
	_paw.name = "Paw"
	_paw.position = Vector3(0, -length, 0.05)
	_arm_r.add_child(_paw)


## A floating glove as a hand (figures without arms).
func _glove(piece: Node3D, mat: Material, size: float) -> void:
	_p(piece, ToyKit.sphere(), mat, Vector3(0, -0.5, 0), Vector3.ONE * size)
	_p(piece, ToyKit.sphere(), mat, Vector3(0.0, -0.42, 0.14), Vector3.ONE * size * 0.5)


func _arm(piece: Node3D, mat: Material, length: float, thick: float, paw_mat: Material = null) -> void:
	# The arm hangs down from the shoulder (the piece's origin); rotating the piece swings it.
	_p(piece, ToyKit.sphere(), mat, Vector3(0, -length * 0.45, 0), Vector3(thick, length, thick))
	if paw_mat != null:
		_p(piece, ToyKit.sphere(), paw_mat, Vector3(0, -length * 0.88, 0.02), Vector3.ONE * thick * 1.15)


## Wind-up snapper: an angular, chunky dino with a big hinged jaw that snaps in step with its walk, a stiff segmented
## tail that swings from side to side, spikes down the back and stompy feet.
func _build_dino() -> void:
	var acc := ToyKit.plastic(ACCENTS[kind])
	var belly := ToyKit.plastic(Color("fff1c9"))
	var tooth := ToyKit.plastic(WHITE)
	var rbox := ToyKit.rounded_box(0.22)
	var body := _piece("Body", Vector3(0, 0.95, -0.05), true)
	_p(body, rbox, body_mat, Vector3.ZERO, Vector3(1.9, 1.5, 2.1))
	_p(body, rbox, belly, Vector3(0, -0.12, 0.5), Vector3(1.3, 1.0, 1.2))
	var head := _piece("Head", Vector3(0, 1.95, -0.05))
	_head = head
	_p(head, rbox, body_mat, Vector3(0, 0.05, 0.0), Vector3(1.75, 1.2, 1.5))
	_p(head, rbox, body_mat, Vector3(0, -0.02, 0.7), Vector3(1.35, 0.62, 0.95))               # upper jaw / snout
	_eye(head, Vector3(0.45, 0.4, 0.55), Vector3(0.45, 0.25, 1.0), 0.48)
	_eye(head, Vector3(-0.45, 0.4, 0.55), Vector3(-0.45, 0.25, 1.0), 0.48)
	for sx in [-1.0, 1.0]:
		_p(head, rbox, body_mat, Vector3(sx * 0.46, 0.7, 0.45), Vector3(0.6, 0.18, 0.45), Vector3(-0.25, 0, sx * -0.2))   # brow ridge
		for k in 2:
			_p(head, ToyKit.cone(), tooth, Vector3(sx * 0.5, -0.38, 0.5 + 0.4 * k), Vector3(0.14, 0.2, 0.14), Vector3(PI, 0, 0))   # upper teeth
	# The lower jaw hangs on a hinge under the head and swings open with the JAW channel.
	_jaw = Node3D.new()
	_jaw.name = "Jaw"
	_jaw.position = Vector3(0, -0.34, 0.1)
	head.add_child(_jaw)
	_p(_jaw, rbox, acc, Vector3(0, -0.1, 0.5), Vector3(1.25, 0.28, 1.15))
	_p(_jaw, ToyKit.sphere(), ToyKit.plastic(Color("e8506a")), Vector3(0, 0.03, 0.5), Vector3(0.8, 0.1, 0.8))   # tongue
	for sx in [-1.0, 1.0]:
		for k in 2:
			_p(_jaw, ToyKit.cone(), tooth, Vector3(sx * 0.46, 0.12, 0.45 + 0.4 * k), Vector3(0.14, 0.2, 0.14))      # lower teeth
	# Spikes along the middle: a line that points where it looks.
	for s in [[Vector3(0, 0.62, -0.25), 0.4, -0.35], [Vector3(0, 0.55, -0.6), 0.44, -0.6]]:
		_p(head, ToyKit.cone(), acc, s[0], Vector3(0.34, s[1], 0.34), Vector3(s[2], 0, 0))
	for s in [[Vector3(0, 0.78, -0.45), 0.5, -0.8], [Vector3(0, 0.42, -1.0), 0.45, -1.2]]:
		_p(body, ToyKit.cone(), acc, s[0], Vector3(0.38, s[1], 0.38), Vector3(s[2], 0, 0))
	# Tail: three stiff blocks in a row, a spiky tip. The whole piece swings sideways.
	var tail := _piece("Tail", Vector3(0, 0.75, -1.05), true)
	_p(tail, rbox, body_mat, Vector3(0, 0, -0.35), Vector3(0.9, 0.7, 0.8))
	_p(tail, rbox, body_mat, Vector3(0, -0.04, -0.95), Vector3(0.62, 0.5, 0.7))
	_p(tail, ToyKit.cone(), acc, Vector3(0, -0.08, -1.55), Vector3(0.42, 0.7, 0.42), Vector3(-PI * 0.5, 0, 0))
	_tail = tail
	_arm_l = _piece("ArmL", Vector3(-0.95, 1.25, 0.45), true)
	_arm(_arm_l, body_mat, 0.7, 0.34, body_mat)
	_arm_r = _piece("ArmR", Vector3(0.95, 1.25, 0.45), true)
	_arm(_arm_r, body_mat, 0.7, 0.34, body_mat)
	_set_paw(0.65)
	for sx in [-1.0, 1.0]:
		var foot := _piece("FootL" if sx < 0.0 else "FootR", Vector3(sx * 0.5, 0.2, 0.1))
		_p(foot, rbox, body_mat, Vector3(0, 0, 0.12), Vector3(0.7, 0.45, 0.95))
		_p(foot, rbox, acc, Vector3(0, -0.05, 0.55), Vector3(0.5, 0.2, 0.22))
		if sx < 0.0:
			_foot_l = foot
		else:
			_foot_r = foot


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
	_p(body, ToyKit.cylinder(), ToyKit.plastic(Color("58e07a")), Vector3(0, 0.08, 0.82), Vector3(0.2, 0.08, 0.2), Vector3(PI * 0.5, 0, 0))
	for sx in [-1.0, 1.0]:
		_p(body, ToyKit.sphere(), metal, Vector3(sx * 0.98, 0.35, 0.05), Vector3.ONE * 0.42)       # shoulder joints
		_p(body, ToyKit.sphere(), metal, Vector3(sx * 0.72, 0.38, 0.74), Vector3.ONE * 0.13)       # rivets
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
	_set_paw(0.85)
	_foot_l = _piece("FootL", Vector3(-0.42, 0.2, 0.08))
	_p(_foot_l, rbox, dark, Vector3(0, 0, 0.1), Vector3(0.6, 0.4, 1.0))
	_foot_r = _piece("FootR", Vector3(0.42, 0.2, 0.08))
	_p(_foot_r, rbox, dark, Vector3(0, 0, 0.1), Vector3(0.6, 0.4, 1.0))


func _build_bunny() -> void:
	var fluff := ToyKit.plush(ACCENTS[kind])
	var pink := ToyKit.plush(Color("ffb3c8"))
	var body := _piece("Body", Vector3(0, 0.9, -0.05), true)
	_p(body, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.95, 1.6, 1.9))
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
		var eye := Node3D.new()      # the button eye blinks like the painted ones
		eye.position = p
		eye.set_meta("open", eye.basis)
		head.add_child(eye)
		_eyes.append(eye)
		_p(eye, ToyKit.sphere(), ToyKit.plastic(INK), Vector3.ZERO, Vector3(0.3, 0.32, 0.18))
		_p(eye, ToyKit.sphere(), ToyKit.unshaded(Color.WHITE), dir * 0.09 + Vector3(-sx * 0.04, 0.07, 0), Vector3.ONE * 0.08)
	for sx in [-1.0, 1.0]:
		_blush(head, Vector3(sx * 0.66, -0.12, 0.6), 0.3)
		_p(head, rbox_teeth(), ToyKit.plastic(WHITE), Vector3(sx * 0.08, -0.5, 0.9), Vector3(0.14, 0.2, 0.08))   # front teeth
	# A bow at the neck.
	var bow := ToyKit.plastic(Color("7b5cff"))
	_p(body, ToyKit.sphere(), bow, Vector3(0.24, 0.62, 0.72), Vector3(0.42, 0.3, 0.2), Vector3(0, 0, 0.4))
	_p(body, ToyKit.sphere(), bow, Vector3(-0.24, 0.62, 0.72), Vector3(0.42, 0.3, 0.2), Vector3(0, 0, -0.4))
	_p(body, ToyKit.sphere(), bow, Vector3(0, 0.62, 0.78), Vector3.ONE * 0.18)
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
	_set_paw(0.65)
	_foot_l = _piece("FootL", Vector3(-0.45, 0.18, 0.15))
	_p(_foot_l, ToyKit.sphere(), body_mat, Vector3(0, 0, 0.15), Vector3(0.62, 0.4, 1.1))
	_p(_foot_l, ToyKit.sphere(), pink, Vector3(0, -0.12, 0.15), Vector3(0.45, 0.2, 0.8))
	_foot_r = _piece("FootR", Vector3(0.45, 0.18, 0.15))
	_p(_foot_r, ToyKit.sphere(), body_mat, Vector3(0, 0, 0.15), Vector3(0.62, 0.4, 1.1))
	_p(_foot_r, ToyKit.sphere(), pink, Vector3(0, -0.12, 0.15), Vector3(0.45, 0.2, 0.8))


## Pull-along duck: a painted wooden duck on a little cart with four wheels that turn with the distance travelled.
func _build_duck() -> void:
	var beak := ToyKit.matte(ACCENTS[kind])
	var wood := ToyKit.matte(Color("b9824f"))
	var dark := ToyKit.matte(Color("6b3f2a"))
	var rbox := ToyKit.rounded_box(0.22)
	var body := _piece("Body", Vector3(0, 1.0, -0.05), true)
	_p(body, ToyKit.sphere(), body_mat, Vector3(0, 0.1, 0), Vector3(1.9, 1.4, 2.1))
	_p(body, rbox, wood, Vector3(0, -0.72, 0.05), Vector3(1.7, 0.26, 2.3))                        # the cart's board
	var tail := _piece("Tail", Vector3(0, 1.25, -1.0), true)
	_p(tail, ToyKit.cone(), body_mat, Vector3(0, 0.15, -0.2), Vector3(0.8, 0.9, 0.5), Vector3(-0.9, 0, 0))
	_floppy.append(tail)
	var head := _piece("Head", Vector3(0, 2.1, 0.15))
	_head = head
	_p(head, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.4, 1.35, 1.4))
	# The bill sticks out in front: an arrow from above.
	_p(head, rbox, beak, Vector3(0, -0.2, 0.65), Vector3(0.9, 0.22, 0.8))
	_p(head, rbox, beak, Vector3(0, -0.4, 0.6), Vector3(0.75, 0.16, 0.65))
	_eye(head, Vector3(0.34, 0.2, 0.52), Vector3(0.5, 0.2, 1.0), 0.34)
	_eye(head, Vector3(-0.34, 0.2, 0.52), Vector3(-0.5, 0.2, 1.0), 0.34)
	for sx in [-1.0, 1.0]:
		_blush(head, Vector3(sx * 0.5, -0.1, 0.46), 0.24)
	_p(head, ToyKit.cone(), body_mat, Vector3(0.05, 0.72, -0.05), Vector3(0.2, 0.36, 0.2), Vector3(-0.5, 0, 0.3))   # tuft
	# Wings are the arms: they flap up when it throws or dashes.
	_arm_l = _piece("ArmL", Vector3(-0.92, 1.35, 0.0), true)
	_p(_arm_l, ToyKit.sphere(), body_mat, Vector3(-0.08, -0.25, -0.1), Vector3(0.3, 0.85, 1.2), Vector3(0.3, 0, 0))
	_arm_r = _piece("ArmR", Vector3(0.92, 1.35, 0.0), true)
	_p(_arm_r, ToyKit.sphere(), body_mat, Vector3(0.08, -0.25, -0.1), Vector3(0.3, 0.85, 1.2), Vector3(0.3, 0, 0))
	_set_paw(0.6)
	# Two wheels per side on the cart (hung on the empty feet pieces). A nub on each wheel shows it turning.
	for sx in [-1.0, 1.0]:
		var foot := _piece("FootL" if sx < 0.0 else "FootR", Vector3(sx * 0.98, 0.36, 0.0))
		for wz in [-0.7, 0.75]:
			var wheel := Node3D.new()
			wheel.position = Vector3(0, 0, wz)
			foot.add_child(wheel)
			_wheels.append(wheel)
			_p(wheel, ToyKit.cylinder(), dark, Vector3.ZERO, Vector3(0.7, 0.16, 0.7), Vector3(0, 0, PI * 0.5))
			_p(wheel, ToyKit.cylinder(), beak, Vector3(sx * 0.1, 0, 0), Vector3(0.18, 0.18, 0.18), Vector3(0, 0, PI * 0.5))     # hub
			_p(wheel, ToyKit.sphere(), beak, Vector3(sx * 0.1, 0.22, 0), Vector3(0.12, 0.12, 0.12))                              # nub
		if sx < 0.0:
			_foot_l = foot
		else:
			_foot_r = foot


func rbox_teeth() -> Mesh:
	return ToyKit.rounded_box(0.3)


## Jack-in-the-box imp: a cheeky ball of a head with horns on a coil spring, floating gloves, no feet.
func _build_imp() -> void:
	var acc := ToyKit.plastic(ACCENTS[kind])
	var metal := ToyKit.plastic(Color("c9d2dc"))
	var gold := ToyKit.plastic(Color("ffd21f"))
	var ink := ToyKit.plastic(INK)
	var body := _piece("Body", Vector3(0, 0.55, 0), true)
	_p(body, ToyKit.cylinder(), acc, Vector3(0, 0.52, 0), Vector3(1.9, 0.16, 1.9))            # ruff under the head
	for k in 4:
		_coils.append(_p(body, ToyKit.torus(), metal, Vector3(0, -0.36 + 0.24 * k, 0), Vector3(1.25, 1.5, 1.25)))
	for k in 6:
		var a := TAU * k / 6.0
		_p(body, ToyKit.sphere(), gold, Vector3(sin(a) * 0.88, 0.52, cos(a) * 0.88), Vector3.ONE * 0.24)
	var head := _piece("Head", Vector3(0, 1.85, 0.0))
	_head = head
	_p(head, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.8, 1.7, 1.8))
	_p(head, ToyKit.sphere(), ink, Vector3(0, -0.3, 0.76), Vector3(0.8, 0.34, 0.3))               # grin
	_p(head, ToyKit.rounded_box(0.3), ToyKit.plastic(WHITE), Vector3(0, -0.23, 0.86), Vector3(0.56, 0.15, 0.14))
	for sx in [-1.0, 1.0]:
		_eye(head, Vector3(sx * 0.34, 0.2, 0.72), Vector3(sx * 0.4, 0.3, 1.0), 0.48, 1.15, 0.5)
		_p(head, ToyKit.rounded_box(0.3), ink, Vector3(sx * 0.34, 0.56, 0.72), Vector3(0.46, 0.11, 0.14), Vector3(-0.35, 0, sx * 0.45))
		_p(head, ToyKit.cone(), acc, Vector3(sx * 0.52, 0.82, 0.02), Vector3(0.42, 0.85, 0.42), Vector3(0, 0, sx * -0.5))
		_blush(head, Vector3(sx * 0.68, -0.1, 0.52), 0.26)
	_arm_l = _piece("ArmL", Vector3(-1.02, 2.0, 0.1), true)
	_glove(_arm_l, ToyKit.plastic(WHITE), 0.44)
	_arm_r = _piece("ArmR", Vector3(1.02, 2.0, 0.1), true)
	_glove(_arm_r, ToyKit.plastic(WHITE), 0.44)
	_set_paw(0.5)
	for sx in [-1.0, 1.0]:
		# No visible feet: the spring and the hopping are the imp's way of getting around. The pieces stay (empty)
		# because the pose code and the burst of a death work on the six standard ones.
		var foot := _piece("FootL" if sx < 0.0 else "FootR", Vector3(sx * 0.3, 0.14, 0.12))
		if sx < 0.0:
			_foot_l = foot
		else:
			_foot_r = foot


## The die: a big rounded cube with pips, its face on the front, gloves and little shoes.
func _build_die() -> void:
	var pip := ToyKit.plastic(ACCENTS[kind])
	var dark := ToyKit.plastic(Color("39405a"))
	var body := _piece("Body", Vector3(0, 1.2, 0), true)
	_p(body, ToyKit.rounded_box(0.22), body_mat, Vector3.ZERO, Vector3(1.85, 1.85, 1.85))
	for v: Vector2 in [Vector2(0, 0), Vector2(0.46, 0.46), Vector2(-0.46, 0.46), Vector2(0.46, -0.46), Vector2(-0.46, -0.46)]:
		_p(body, ToyKit.sphere(), pip, Vector3(v.x, 0.86, v.y), Vector3(0.32, 0.1, 0.32))
	for k in 3:
		_p(body, ToyKit.sphere(), pip, Vector3(0.86, 0.45 - 0.45 * k, -0.45 + 0.45 * k), Vector3(0.1, 0.3, 0.3))
	for v: Vector2 in [Vector2(0.42, 0.42), Vector2(-0.42, 0.42), Vector2(0.42, -0.42), Vector2(-0.42, -0.42)]:
		_p(body, ToyKit.sphere(), pip, Vector3(-0.86, v.x, v.y), Vector3(0.1, 0.3, 0.3))
	_p(body, ToyKit.sphere(), pip, Vector3(0.4, 0.4, -0.86), Vector3(0.3, 0.3, 0.1))
	_p(body, ToyKit.sphere(), pip, Vector3(-0.4, -0.4, -0.86), Vector3(0.3, 0.3, 0.1))
	# The face is painted on the front of the cube; the "head" is only a little cap on top.
	_p(body, ToyKit.sphere(), ToyKit.plastic(INK), Vector3(0, -0.34, 0.87), Vector3(0.42, 0.16, 0.08))  # smile
	for sx in [-1.0, 1.0]:
		_eye(body, Vector3(sx * 0.38, 0.22, 0.87), Vector3(sx * 0.1, 0.25, 1.0), 0.56, 1.15, 0.5)
		_blush(body, Vector3(sx * 0.62, -0.2, 0.86), 0.26)
	var head := _piece("Head", Vector3(0, 2.1, 0.0), true)
	_head = head
	_p(head, ToyKit.sphere(), dark, Vector3(0, 0.0, 0), Vector3(0.5, 0.2, 0.5))
	_p(head, ToyKit.sphere(), pip, Vector3(0, 0.12, 0), Vector3.ONE * 0.22)
	_arm_l = _piece("ArmL", Vector3(-1.05, 1.6, 0.1), true)
	_glove(_arm_l, ToyKit.plastic(WHITE), 0.42)
	_arm_r = _piece("ArmR", Vector3(1.05, 1.6, 0.1), true)
	_glove(_arm_r, ToyKit.plastic(WHITE), 0.42)
	_set_paw(0.5)
	_foot_l = _piece("FootL", Vector3(-0.45, 0.18, 0.1))
	_p(_foot_l, ToyKit.sphere(), dark, Vector3(0, 0, 0.1), Vector3(0.58, 0.38, 0.9))
	_foot_r = _piece("FootR", Vector3(0.45, 0.18, 0.1))
	_p(_foot_r, ToyKit.sphere(), dark, Vector3(0, 0, 0.1), Vector3(0.58, 0.38, 0.9))


## Roly-poly toy: a painted wooden pear with a heavy round bottom and no legs. It tips into the movement and rocks
## back and forth with a decaying swing (TILT channels).
func _build_doll() -> void:
	var face := ToyKit.matte(ACCENTS[kind])
	var paint := ToyKit.matte(color.darkened(0.45))
	var gold := ToyKit.matte(Color("ffd21f"))
	var body := _piece("Body", Vector3(0, 0.95, 0), true)
	_p(body, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(2.1, 1.9, 2.1))                         # the heavy bottom
	_p(body, ToyKit.sphere(), body_mat, Vector3(0, 0.85, 0), Vector3(1.45, 1.3, 1.45))              # the narrower belly
	_p(body, ToyKit.torus(), paint, Vector3(0, 0.05, 0), Vector3(2.15, 1.2, 2.15))                  # painted bands
	_p(body, ToyKit.torus(), gold, Vector3(0, -0.5, 0), Vector3(1.95, 1.1, 1.95))
	_p(body, ToyKit.sphere(), face, Vector3(0, 0.25, 0.6), Vector3(1.15, 1.2, 0.8))                 # apron
	_p(body, ToyKit.sphere(), gold, Vector3(0, 0.3, 0.98), Vector3(0.22, 0.22, 0.1))                # flower
	for k in 5:
		var a := TAU * k / 5.0
		_p(body, ToyKit.sphere(), ToyKit.matte(Color("ff6f91")), Vector3(sin(a) * 0.23, 0.3 + cos(a) * 0.23, 0.96), Vector3(0.22, 0.22, 0.09))
	for sx in [-1.0, 1.0]:
		_p(body, ToyKit.sphere(), paint, Vector3(sx * 0.5, -0.1, 0.9), Vector3(0.2, 0.2, 0.1))     # painted dots
	_p(body, ToyKit.torus(), paint, Vector3(0, 1.28, 0), Vector3(1.05, 1.0, 1.05))                 # band at the neck
	var head := _piece("Head", Vector3(0, 2.55, 0.05))
	_head = head
	_p(head, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.4, 1.35, 1.4))
	_p(head, ToyKit.sphere(), face, Vector3(0, 0.0, 0.3), Vector3(1.05, 1.0, 0.95))
	_p(head, ToyKit.sphere(), ToyKit.matte(Color("6b3f2a")), Vector3(0, 0.42, 0.45), Vector3(0.65, 0.3, 0.4))   # hair
	_p(head, ToyKit.sphere(), ToyKit.matte(Color("e0457b")), Vector3(0, -0.26, 0.74), Vector3(0.2, 0.1, 0.1))  # mouth
	_p(head, ToyKit.sphere(), paint, Vector3(0.14, -0.62, 0.45), Vector3(0.32, 0.24, 0.2), Vector3(0, 0, 0.5))   # kerchief knot
	_p(head, ToyKit.sphere(), paint, Vector3(-0.14, -0.62, 0.45), Vector3(0.32, 0.24, 0.2), Vector3(0, 0, -0.5))
	for sx in [-1.0, 1.0]:
		_eye(head, Vector3(sx * 0.24, 0.08, 0.7), Vector3(sx * 0.25, 0.3, 1.0), 0.3, 1.2, 0.66)
		_blush(head, Vector3(sx * 0.4, -0.14, 0.62), 0.22)
	_arm_l = _piece("ArmL", Vector3(-1.0, 1.7, 0.3), true)
	_glove(_arm_l, face, 0.36)
	_arm_r = _piece("ArmR", Vector3(1.0, 1.7, 0.3), true)
	_glove(_arm_r, face, 0.36)
	_set_paw(0.5)
	# No legs: it rolls on its round bottom (the pieces exist, empty).
	_foot_l = _piece("FootL", Vector3(-0.3, 0.1, 0.4))
	_foot_r = _piece("FootR", Vector3(0.3, 0.1, 0.4))


## Spinning top: always turning under its face, no feet. The upper part and the base turn at different speeds; the
## base carries uneven marks (one big accent block, stripes on the cone) so the turning reads from above.
func _build_top() -> void:
	var acc := ToyKit.plastic(ACCENTS[kind])
	var dark := ToyKit.plastic(color.darkened(0.5))
	var white := ToyKit.plastic(WHITE)
	var body := _piece("Body", Vector3(0, 1.2, 0), true)
	_p(body, ToyKit.cylinder(), acc, Vector3.ZERO, Vector3(2.0, 0.36, 2.0))                       # band
	_base = Node3D.new()
	_base.name = "Base"
	body.add_child(_base)
	_p(_base, ToyKit.cone(), body_mat, Vector3(0, -0.62, 0), Vector3(1.9, 1.0, 1.9), Vector3(PI, 0, 0))
	_p(_base, ToyKit.cylinder(), body_mat, Vector3(0, -0.26, 0), Vector3(2.2, 0.1, 2.2))           # skirt, wider than the band
	for k in 6:
		var a := TAU * k / 6.0
		var big := k == 0
		_p(_base, ToyKit.rounded_box(0.3), acc if big else dark, Vector3(sin(a) * 1.0, -0.26, cos(a) * 1.0),
				Vector3(0.5 if big else 0.3, 0.14, 0.24 if big else 0.14), Vector3(0, a, 0))
	for k in 3:
		var pivot := Node3D.new()
		pivot.rotation.y = TAU * k / 3.0 + 0.4
		_base.add_child(pivot)
		_p(pivot, ToyKit.rounded_box(0.3), acc if k == 0 else white, Vector3(0, -0.62, 0.5), Vector3(0.16, 1.3, 0.05), Vector3(0.76, 0, 0))   # stripe down the cone
	_spin = Node3D.new()
	body.add_child(_spin)
	_p(_spin, ToyKit.sphere(), body_mat, Vector3(0, 0.16, 0), Vector3(1.8, 1.0, 1.8))
	for k in 3:
		var a := TAU * k / 3.0
		_p(_spin, ToyKit.sphere(), white, Vector3(sin(a) * 0.5, 0.58, cos(a) * 0.5), Vector3(0.6, 0.1, 0.24), Vector3(0, a + 0.9, 0))
	_p(_spin, ToyKit.cylinder(), ToyKit.plastic(Color("c9d2dc")), Vector3(0, 0.9, 0), Vector3(0.24, 0.6, 0.24))
	_p(_spin, ToyKit.sphere(), acc, Vector3(0, 1.26, 0), Vector3.ONE * 0.42)
	var head := _piece("Head", Vector3(0, 1.45, 0.0))
	_head = head
	_p(head, ToyKit.sphere(), ToyKit.plastic(INK), Vector3(0, -0.14, 0.9), Vector3(0.3, 0.12, 0.1))       # mouth
	for sx in [-1.0, 1.0]:
		_eye(head, Vector3(sx * 0.32, 0.16, 0.8), Vector3(sx * 0.2, 0.55, 1.0), 0.46, 1.15, 0.5)
	_arm_l = _piece("ArmL", Vector3(-1.2, 1.9, 0.0), true)
	_glove(_arm_l, white, 0.38)
	_arm_r = _piece("ArmR", Vector3(1.2, 1.9, 0.0), true)
	_glove(_arm_r, white, 0.38)
	_set_paw(0.5)
	# No visible feet (the pieces stay, empty: the pose code and the burst of a death work on the six standard ones).
	_foot_l = _piece("FootL", Vector3(-0.3, 0.12, 0.1))
	_foot_r = _piece("FootR", Vector3(0.3, 0.12, 0.1))


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
	_blink -= dt
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
	pose_node.basis = Basis.from_euler(Vector3(s[ToyPose.LEAN] + s[ToyPose.TILT_F], 0.0, s[ToyPose.ROLL] + s[ToyPose.TILT_S])).scaled_local(Vector3(sx, sy, sz))
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
	_aim_arm(arm, ang, twist)
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
	if _jaw != null:
		_jaw.rotation.x = s[ToyPose.JAW] * 0.9
	if _tail != null:
		_tail.rotate_object_local(Vector3.UP, 0.55 * s[ToyPose.STEP] * sin(f.gait) + 0.12 * sin(f.time * 2.3))
	for w in _wheels:
		w.rotation.x = f.gait
	if kind == ToyPose.Kind.DUCK:
		_flap_wings(s, f)
	for fl in _floppy:
		if fl.get_parent() == pose_node:
			fl.rotate_object_local(Vector3.RIGHT, -0.5 * s[ToyPose.EARS])   # tail (already placed with the twist)
		else:
			fl.basis = _ear_basis(fl, s[ToyPose.EARS])
	if _key != null:
		_key.rotation = Vector3(0.0, 0.0, motion.wind)
	if _spin != null:
		_spin.rotation.y = -motion.wind * 1.6
	if _base != null:
		_base.rotation.y = motion.spin
	# The imp's spring stays on the floor and stretches up to the hopping head.
	var lift := maxf(s[ToyPose.LIFT], 0.0)
	for k in _coils.size():
		_coils[k].position.y = -0.36 + 0.24 * k - lift * (1.0 - k / 3.0)
	if not _coils.is_empty():
		_foot_l.position.y -= lift * 0.55
		_foot_r.position.y -= lift * 0.55
	var dz := s[ToyPose.DIZZY]
	_stars.visible = dz > 0.05
	if _stars.visible:
		_stars.rotation.y = f.time * 6.0
		_stars.scale = Vector3.ONE * dz
	_shadow.scale = Vector3.ONE * 2.7 / (1.0 + maxf(s[ToyPose.LIFT], 0.0) * 0.35)
	if _blink < -BLINK_TIME:
		_blink = _rng.randf_range(1.6, 4.5)
	var open := 0.12 if _blink < 0.0 else (0.45 if dz > 0.5 else 1.0)
	for e in _eyes:
		e.basis = (e.get_meta("open") as Basis).scaled_local(Vector3(1.0, open, 1.0))


## The duck's wings: up on a throw, flapping in a dash or a pull.
func _flap_wings(s: Array[float], f: ToyPose.Facts) -> void:
	var up := 0.0
	var act := motion.act
	if act == ToyPose.Act.DASH or act == ToyPose.Act.PULL:
		up = 0.9 + 0.35 * sin(f.time * 38.0)
	elif f.since_throw < ToyPose.THROW_TIME:
		up = 1.3 * (1.0 - f.since_throw / ToyPose.THROW_TIME)
	if up <= 0.0:
		return
	_arm_l.rotation.z = 0.15 - up                 # the left wing goes up and out (-x)
	if act == ToyPose.Act.DASH or act == ToyPose.Act.PULL:
		_arm_r.basis = Basis(Vector3(0, 0, 1), up) * _arm_r.basis


## The yo-yo arm points at where the hand should be: in front of the belly, wound up behind the shoulder, or
## along the string while a yo-yo is out. The yo-yo itself is drawn in the real hand (`hand_point`).
func _aim_arm(arm: float, ang: float, twist: float) -> void:
	if _paw == null:
		_arm_r.rotation = Vector3(ang, twist, -0.35 * clampf(arm, 0.0, 1.0) - 0.15)
		return
	var sh := _arm_r.position
	var reach_dir := Vector3(0.0, -0.25, 1.0)
	if string_dir != Vector2.ZERO:
		var loc := Vector3(string_dir.x, 0.0, string_dir.y).rotated(Vector3.UP, -motion.yaw)
		reach_dir = Vector3(loc.x, -0.25, loc.z)
	var reach := sh + reach_dir.normalized() * HAND_REACH
	var tgt := HAND_WOUND.lerp(HAND_HOLD, clampf((arm + 1.0) / 1.3, 0.0, 1.0))
	if arm > 0.3:
		tgt = HAND_HOLD.lerp(reach, clampf((arm - 0.3) / 0.7, 0.0, 1.0))
	var y := -(tgt - sh).normalized()
	var x := y.cross(Vector3(0, 0, 1))
	x = x.normalized() if x.length() > 0.01 else Vector3.RIGHT
	_arm_r.basis = Basis(x, y, x.cross(y))


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
	if kind == ToyPose.Kind.DUCK or kind == ToyPose.Kind.DOLL:
		return                         # wheels / a round bottom: no stepping feet
	var hops := kind == ToyPose.Kind.BUNNY or kind == ToyPose.Kind.IMP
	if kind == ToyPose.Kind.ROBOT or kind == ToyPose.Kind.DIE:
		a = clampf(a * (3.0 if kind == ToyPose.Kind.ROBOT else 2.2), -1.0, 1.0)
		b = -a
	elif hops:
		b = a                          # both feet together: hops
	var stride := 0.38 * step
	var up := 0.22 * step
	_foot_l.position = hl + Vector3(0.0, maxf(0.0, cos(f.gait)) * up if not hops else 0.0, a * stride)
	_foot_r.position = hr + Vector3(0.0, maxf(0.0, -cos(f.gait)) * up if not hops else 0.0, b * stride)
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
	if _paw != null and is_inside_tree() and visible:
		return _paw.global_position + Vector3(0, hr * 0.3, 0)
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


## How far the solid parts of the body and head reach from the figure's centre in the horizontal plane, along x or z,
## in player radii: every mesh of the "Body" and "Head" pieces that is at least 0.6 wide both ways (no thin bits like
## horns, teeth or antennae). The figure must be in the scene tree.
func solid_reach() -> float:
	var inv := pose_node.global_transform.affine_inverse()
	var reach := 0.0
	for piece_name in ["Body", "Head"]:
		for mi: MeshInstance3D in pose_node.get_node(piece_name).find_children("*", "MeshInstance3D", true, false):
			var xf := inv * mi.global_transform
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for i in 8:
				var c := xf * mi.mesh.get_aabb().get_endpoint(i)
				lo = lo.min(c)
				hi = hi.max(c)
			if hi.x - lo.x >= 0.6 and hi.z - lo.z >= 0.6:
				reach = maxf(reach, maxf(maxf(absf(lo.x), absf(hi.x)), maxf(absf(lo.z), absf(hi.z))))
	return reach


## Footprint radius of the body shell (the first mesh of the "Body" piece), in player radii: half its larger
## horizontal size plus its offset. The hit circle has radius 1.
func body_footprint() -> float:
	var shell := (pose_node.get_node("Body") as Node3D).get_child(0) as MeshInstance3D
	var ext := shell.transform.basis.get_scale() * 0.5
	return maxf(absf(shell.position.x) + ext.x, absf(shell.position.z) + ext.z)
