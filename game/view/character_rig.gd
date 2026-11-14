class_name CharacterRig
extends Node3D
## One player figure, built from primitives and animated in code. Presentation only: every kind has the same
## footprint (the player radius) and the same parts (body, two feet, two hands, eyes), so the choice of figure
## never changes the game. What differs is the look and the way it moves (its gait numbers and `_extras`).
##
## Unit space: the figure is modelled for a player radius of 1 (about 2.5 high) and scaled by the real radius.
## +Z is forward. The hand on +X holds the yo-yo; the foot and hand on -X lead the walk cycle.

enum Kind { ROBOT, IMP, DINO, DUCK, DIE, DOLL, TOP, TEDDY }
const KIND_COUNT := 8
## German names shown in the menu (the prototype UI is German).
const NAMES: Array[String] = [
	"Blechroboter", "Springteufel", "Plüschdino", "Quietscheente", "Würfel", "Stehauf-Püppchen", "Kreisel", "Teddy"]

const CREAM := Color(1.0, 0.94, 0.8)
const METAL := Color(0.74, 0.77, 0.82)
const INK := Color(0.07, 0.07, 0.1)
const WHITE := Color(1, 1, 1)
const ORANGE := Color(1.0, 0.58, 0.16)
const STAR := Color(1.0, 0.92, 0.3)
const HOLD_POS := Vector3(0.5, 1.2, 0.9)      # the yo-yo hand at rest
const WIND_POS := Vector3(1.0, 1.95, -0.55)   # ... wound back at full charge
const OUT_RADIUS := 1.05                      # ... pointing along the string while the yo-yo is out
const OUT_Y := 1.25
const THROW_TIME := 0.2
const POP_TIME := 0.3
const WOBBLE_SPEED := 45.0
const WOBBLE_ANGLE := 0.25
const FLASH_PERIOD := 0.08

var kind := -1
var color := Color.WHITE

# Gait: what makes each figure walk in character. Distances in unit space, angles in radians.
var cadence := 0.4      # walk cycles per metre (one cycle = two steps, or two hops)
var swing := 0.4        # how far a foot reaches forward and back
var lift := 0.3         # how high a foot is lifted
var bob := 0.06         # body moving up at each step
var roll_amp := 0.1     # body rocking sideways over the standing foot
var twist := 0.1        # shoulders turning with the steps
var lean := 0.08        # leaning into the walk
var arm := 0.3          # free hand swinging
var snap := 1.0         # < 1: the motion holds at its extremes (stiff, mechanical)
var hop_h := 0.0        # > 0: hops with both feet instead of stepping
var stretch := 0.0      # squash and stretch of a hop
var follow := 1.0       # how much of the hop the feet follow (the rest stretches the body)
var rock := 0.0         # rocking in a circle while moving (roly-poly)
var idle_rock := 0.0    # ... and while standing
var idle_rate := 1.7

var _pivot: Node3D      # scaled by the player radius
var _tilt: Node3D       # body, head and hands: bobs, leans, squashes
var _legs: Node3D       # the feet: turned into the walking direction
var _shadow: MeshInstance3D
var _stars: Node3D
var _feet: Array[Node3D] = []
var _hands: Array[Node3D] = []
var _foot_rest := Vector3(0.42, 0.16, 0.05)
var _hand_rest := Vector3(1.0, 1.0, 0.1)
var _eyes: Array[Node3D] = []
var _mats: Array = []   # [material, base colour]
var _head: Node3D
var _tail: Node3D
var _key: Node3D
var _antenna: Node3D
var _spin: Node3D
var _ball: Node3D
var _rings: Array[Node3D] = []
var _head_rest := Vector3.ZERO

var _t := 0.0
var _phase := 0.0
var _walk := 0.0
var _zip := 0.0
var _throw := 0.0
var _pop := 1.0
var _legs_yaw := 0.0
var _hold := HOLD_POS
var _blink := 2.0
var _blink_left := 0.0
var _flashing := false
var _rng := RandomNumberGenerator.new()


func setup(k: int, col: Color) -> void:
	for c in get_children():
		if c.name != "LocalRing":
			remove_child(c)
			c.queue_free()
	kind = posmod(k, KIND_COUNT)
	color = col
	_feet.clear()
	_hands.clear()
	_eyes.clear()
	_mats.clear()
	_rings.clear()
	_head = null
	_tail = null
	_key = null
	_antenna = null
	_spin = null
	_ball = null
	_flashing = false
	_rng.seed = kind * 7919 + 17
	_blink = _rng.randf_range(0.5, 3.0)

	_shadow = _part(self, _cyl(1.0, 1.0, 0.02), _flat(Color(0, 0, 0, 0.3)), Vector3(0, 0.02, 0))
	_shadow.name = "Shadow"
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_legs = Node3D.new()
	_pivot.add_child(_legs)
	_tilt = Node3D.new()
	_pivot.add_child(_tilt)
	for s in 2:
		var f := Node3D.new()
		_legs.add_child(f)
		_feet.append(f)
		var h := Node3D.new()
		_tilt.add_child(h)
		_hands.append(h)
	match kind:
		Kind.ROBOT: _build_robot()
		Kind.IMP: _build_imp()
		Kind.DINO: _build_dino()
		Kind.DUCK: _build_duck()
		Kind.DIE: _build_die()
		Kind.DOLL: _build_doll()
		Kind.TOP: _build_top()
		Kind.TEDDY: _build_teddy()
	if _head != null:
		_head_rest = _head.position
	_build_stars()
	_hold = HOLD_POS
	_place_limbs(0.0, 0.0, 0.0, 0.0, 0.0)


## Plays the pop-in of a figure that has just (re)appeared.
func pop() -> void:
	_pop = 0.0


## The yo-yo left the hand (`out` true) or came back to it.
func throw_flick(out: bool) -> void:
	_throw = 1.0 if out else -0.6


## World position of the hand that holds the yo-yo and its string.
func hand_world() -> Vector3:
	if _hands.size() < 2 or not is_inside_tree():
		return position + Vector3(0, 0.6, 0)
	return _hands[1].global_position


## Advances the animation. `vel` is the world velocity on the ground, `zip` a dash, pull or fling, `charge`
## the throw charge 0..1, `string_dir` the world direction of the string while the yo-yo is out (else ZERO).
func animate(delta: float, radius: float, vel: Vector2, max_speed: float, zip: bool, charge: float,
		stunned: bool, string_dir: Vector2) -> void:
	_t += delta
	var k := 1.0 - exp(-delta * 14.0)
	var speed := vel.length()
	_walk = lerpf(_walk, clampf(speed / maxf(max_speed, 0.01) * 1.4, 0.0, 1.0), k)
	_zip = lerpf(_zip, 1.0 if zip else 0.0, 1.0 - exp(-delta * 22.0))
	_throw = move_toward(_throw, 0.0, delta / THROW_TIME)
	_pop = minf(_pop + delta / POP_TIME, 1.0)

	# The feet turn into the walking direction; walking backwards runs the cycle in reverse instead.
	var dir := 1.0
	if speed > 0.3:
		var loc := Vector3(vel.x, 0.0, vel.y).rotated(Vector3.UP, -rotation.y)
		var ang := atan2(loc.x, loc.z)
		if absf(ang) > PI * 0.5:
			ang = wrapf(ang + PI, -PI, PI)
			dir = -1.0
		_legs_yaw = lerp_angle(_legs_yaw, ang, k)
	else:
		_legs_yaw = lerp_angle(_legs_yaw, 0.0, k)
	_legs.rotation.y = _legs_yaw
	_phase = fmod(_phase + dir * minf(speed, max_speed * 1.2) * delta * cadence * TAU, TAU * 64.0)

	var w := _walk * (1.0 - _zip)
	var sn := sin(_phase)
	var cs := cos(_phase)
	var air := absf(sn)
	var y := 0.0
	var roll := 0.0
	var yaw := twist * sn * w
	var pitch := lean * w
	var sq := 1.0 + 0.025 * sin(_t * 2.2 + kind) * (1.0 - w)   # breathing
	if hop_h > 0.0:
		y = hop_h * air * w
		sq += stretch * (air - 0.45) * w
		yaw = 0.0
	else:
		y = bob * absf(cs) * w
		roll = -roll_amp * _shape(cs) * w
	pitch += rock * sn * w + idle_rock * sin(_t * idle_rate) * (1.0 - w)
	roll += rock * 0.7 * cs * w + idle_rock * cos(_t * idle_rate) * (1.0 - w)

	# Winding up, the flick of the throw, and being dragged along.
	var ch := clampf(charge, 0.0, 1.0)
	sq *= 1.0 - 0.1 * ch
	pitch += -0.16 * ch + 0.28 * _throw + 0.4 * _zip
	yaw += 0.5 * ch - 0.55 * _throw
	var shake := sin(_t * 70.0) * 0.025 * ch * ch
	if stunned:
		roll += sin(_t * WOBBLE_SPEED) * WOBBLE_ANGLE
		pitch += cos(_t * WOBBLE_SPEED * 0.8) * WOBBLE_ANGLE * 0.6
	_set_flash(stunned and int(_t / FLASH_PERIOD) % 2 == 0)

	var wide := 1.0 / sqrt(maxf(sq, 0.2))
	_tilt.position = Vector3(shake, y, 0.0)
	_tilt.rotation = Vector3(pitch, yaw, roll)
	_tilt.scale = Vector3(wide * (1.0 - 0.12 * _zip), sq * (1.0 - 0.12 * _zip), wide * (1.0 + 0.3 * _zip))
	var t := _pop - 1.0
	_pivot.scale = Vector3.ONE * radius * (1.0 + 2.7 * t * t * t + 1.7 * t * t)
	var sh := radius * clampf(0.95 - 0.3 * y, 0.4, 1.0)
	_shadow.scale = Vector3(sh, 1.0, sh)

	_place_limbs(w, sn, cs, air, y)
	_place_hold(delta, ch, string_dir)
	_extras(delta, w, sn, air, y)
	_animate_eyes(delta, stunned)
	_stars.visible = stunned
	_stars.rotation.y = _t * 7.0


func _shape(x: float) -> float:
	return x if snap >= 1.0 else signf(x) * pow(absf(x), snap)


func _place_limbs(w: float, sn: float, cs: float, air: float, y: float) -> void:
	for s in 2:
		var sx := -1.0 if s == 0 else 1.0
		var fp := Vector3(_foot_rest.x * sx, _foot_rest.y, _foot_rest.z)
		var foot := _feet[s]
		if hop_h > 0.0:
			fp.y += y * follow
			foot.rotation.x = 0.5 * air * w
		else:
			var fs := _shape(sn) * -sx      # the -X foot leads
			var fc := cs * -sx
			fp.z += swing * fs * w
			fp.y += lift * maxf(fc, 0.0) * w
			foot.rotation.x = -0.5 * fc * w
		fp.z -= 0.45 * _zip
		fp.y += 0.12 * _zip
		foot.position = fp
		if s == 0:
			# The free hand swings against its foot; the other one holds the yo-yo (see _place_hold).
			var hp := Vector3(-_hand_rest.x, _hand_rest.y, _hand_rest.z)
			hp.z += arm * _shape(sn) * w - 0.7 * _zip + 0.25 * _throw
			hp.y += arm * 0.2 * absf(sn) * w + 0.12 * _zip
			if hop_h > 0.0:
				hp.y += 0.4 * air * w
			_hands[0].position = hp


func _place_hold(delta: float, ch: float, string_dir: Vector2) -> void:
	var target := HOLD_POS
	if string_dir != Vector2.ZERO:
		var loc := Vector3(string_dir.x, 0.0, string_dir.y).rotated(Vector3.UP, -rotation.y - _tilt.rotation.y)
		target = Vector3(loc.x * OUT_RADIUS, OUT_Y, loc.z * OUT_RADIUS)
	elif ch > 0.0:
		target = HOLD_POS.lerp(WIND_POS, pow(ch, 0.6))
	if _throw > 0.0:
		target += Vector3(-0.25, 0.1, 0.5) * _throw
	elif _throw < 0.0:
		target += Vector3(0.0, 0.0, 0.5) * _throw
	_hold = _hold.lerp(target, 1.0 - exp(-delta * 30.0))
	_hands[1].position = _hold


func _animate_eyes(delta: float, stunned: bool) -> void:
	_blink -= delta
	if _blink <= 0.0:
		_blink = _rng.randf_range(1.5, 4.5)
		_blink_left = 0.12
	_blink_left -= delta
	var open := 0.1 if _blink_left > 0.0 else 1.0
	if stunned:
		open = 0.35
	for e in _eyes:
		e.scale.y = open


func _extras(delta: float, w: float, sn: float, air: float, y: float) -> void:
	var idle := 1.0 - w
	match kind:
		Kind.ROBOT:
			_key.rotation.z += delta * (1.2 + 11.0 * w)
			_antenna.rotation.x = -0.4 * w + sin(_t * 11.0) * 0.1 * w
			_antenna.rotation.z = sin(_t * 2.3) * 0.08
			# Looks around in clicks while standing.
			_head.rotation.y = lerp_angle(_head.rotation.y, snappedf(sin(_t * 0.8) * 0.75, 0.5) * idle, 0.25)
		Kind.IMP:
			for i in _rings.size():
				_rings[i].position.y = 0.16 + 0.2 * i - y * (1.0 - follow) * (1.0 - i / 3.0)
			var sway := sin(_t * 2.4) * 0.07 * idle
			_ball.position.x = sway
			_ball.rotation.z = -sway * 1.5 + sn * 0.12 * w
		Kind.DINO:
			_tail.rotation.y = sn * 0.55 * w + sin(_t * 1.6) * 0.18 * idle
			_head.rotation.z = roll_amp * _shape(cos(_phase)) * w * 0.6
			_head.rotation.x = sin(_t * 1.1) * 0.05 * idle
		Kind.DUCK:
			var peck := sin(_phase * 2.0)
			_head.position = _head_rest + Vector3(0, 0, 0.12 * peck * w)
			_head.rotation.z = lerpf(_head.rotation.z, (0.3 if sin(_t * 0.9) > 0.55 else 0.0) * idle, 0.2)
			_tail.rotation.y = peck * 0.45 * w + sin(_t * 9.0) * 0.12 * idle
			var flap := (0.2 + 0.55 * absf(peck)) * w
			_hands[0].rotation.z = flap
			_hands[1].rotation.z = -flap if _hold.distance_to(HOLD_POS) < 0.2 else 0.0
		Kind.DIE:
			_head.rotation.y = sin(_t * 1.3) * 0.08 * idle
		Kind.DOLL:
			_head.rotation.y = sin(_t * idle_rate) * 0.12 * idle
		Kind.TOP:
			_spin.rotation.y -= delta * (5.0 + 16.0 * w)
			_hands[0].position.y += sin(_t * 3.0) * 0.12
		Kind.TEDDY:
			_head.rotation.z = sn * 0.14 * w + sin(_t * 1.2) * 0.04 * idle
			_head.rotation.y = -twist * sn * w * 0.6


func _set_flash(on: bool) -> void:
	if on == _flashing:
		return
	_flashing = on
	for e: Array in _mats:
		(e[0] as StandardMaterial3D).albedo_color = WHITE if on else (e[1] as Color)


# ------------------------------------------------------------------ building blocks

func _mat(c: Color, rough := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mats.append([m, c])
	return m


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _sph(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 20
	m.rings = 1
	return m


func _tor(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 20
	m.ring_segments = 8
	return m


func _part(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, scl := Vector3.ONE,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## A round eye looking forward and a little up (towards the camera). `pupil` and `lid` as shares of the eye.
func _eye(parent: Node3D, pos: Vector3, r: float, pupil := 0.55, lid := 0.0, lid_mat: Material = null) -> void:
	var e := _node(parent, pos)
	e.rotation.x = -0.3
	_part(e, _sph(r), _mat(WHITE, 0.3), Vector3.ZERO, Vector3(1, 1, 0.65))
	_part(e, _sph(r * pupil), _mat(INK, 0.2), Vector3(0, 0, r * 0.5), Vector3(1, 1, 0.5))
	_part(e, _sph(r * 0.16), _flat(WHITE), Vector3(r * 0.2, r * 0.22, r * (0.5 + pupil * 0.3)))
	if lid > 0.0:
		_part(e, _sph(r * 1.12), lid_mat, Vector3(0, r * (1.25 - lid), 0.0), Vector3(1, 0.6, 0.8))
	_eyes.append(e)


func _both(cb: Callable) -> void:
	cb.call(-1.0, 0)
	cb.call(1.0, 1)


func _build_stars() -> void:
	_stars = _node(_pivot, Vector3(0, 2.9, 0))
	_stars.visible = false
	var m := _flat(STAR)
	for i in 3:
		var a := TAU * i / 3.0
		_part(_stars, _sph(0.16), m, Vector3(cos(a) * 0.7, 0.0, sin(a) * 0.7), Vector3(1, 0.6, 1))


# ------------------------------------------------------------------ the eight figures

## Wind-up tin robot: marches stiffly, each step clicking into place, the key in its back turning.
func _build_robot() -> void:
	cadence = 0.42; swing = 0.5; lift = 0.5; bob = 0.05; roll_amp = 0.14; twist = 0.0; lean = 0.0
	arm = 0.55; snap = 0.35
	_foot_rest = Vector3(0.42, 0.16, 0.05)
	_hand_rest = Vector3(1.0, 0.95, 0.1)
	var main := _mat(color, 0.35)
	var light := _mat(color.lightened(0.35), 0.35)
	var dark := _mat(color.darkened(0.45), 0.4)
	var metal := _mat(METAL, 0.3)
	_part(_tilt, _box(Vector3(1.45, 1.1, 1.2)), main, Vector3(0, 0.95, 0))
	_part(_tilt, _box(Vector3(0.85, 0.5, 0.08)), light, Vector3(0, 1.0, 0.6))
	var lamps: Array[Color] = [Color(1, 0.3, 0.3), Color(1, 0.9, 0.3), Color(0.4, 1, 0.5)]
	for i in 3:
		_part(_tilt, _sph(0.09), _flat(lamps[i]), Vector3(-0.24 + 0.24 * i, 1.0, 0.65))
	_part(_tilt, _cyl(0.26, 0.26, 0.2), metal, Vector3(0, 1.58, 0))
	_head = _node(_tilt, Vector3(0, 2.05, 0.05))
	_part(_head, _box(Vector3(1.2, 0.8, 1.0)), light)
	_part(_head, _box(Vector3(0.7, 0.05, 0.5)), main, Vector3(0, 0.41, -0.05))
	_part(_head, _box(Vector3(1.0, 0.44, 0.1)), _mat(INK, 0.2), Vector3(0, 0.02, 0.48))
	var glow := _flat(Color(0.6, 1.0, 1.0))
	_both(func(sx: float, _s: int) -> void:
		var e := _node(_head, Vector3(0.25 * sx, 0.02, 0.54))
		_part(e, _box(Vector3(0.27, 0.24, 0.06)), glow)
		_eyes.append(e)
		_part(_head, _cyl(0.17, 0.17, 0.14), metal, Vector3(0.67 * sx, 0, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
		_part(_feet[_s], _box(Vector3(0.55, 0.32, 0.82)), dark)
		_part(_hands[_s], _box(Vector3(0.36, 0.36, 0.36)), metal))
	_antenna = _node(_head, Vector3(0, 0.4, -0.1))
	_part(_antenna, _cyl(0.035, 0.035, 0.5), metal, Vector3(0, 0.25, 0))
	_part(_antenna, _sph(0.14), _flat(Color(1.0, 0.85, 0.3)), Vector3(0, 0.56, 0))
	var back := _node(_tilt, Vector3(0, 1.0, -0.6))
	_part(back, _cyl(0.07, 0.07, 0.45), metal, Vector3(0, 0, -0.2), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	_key = _node(back, Vector3(0, 0, -0.45))
	_both(func(sx: float, _s: int) -> void:
		_part(_key, _tor(0.11, 0.24), metal, Vector3(0.25 * sx, 0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)))


## Jack-in-the-box imp on a coil spring: hops with both feet, squashing and stretching, arms flying up.
func _build_imp() -> void:
	cadence = 0.27; hop_h = 0.75; stretch = 0.3; follow = 0.55; lean = 0.14; arm = 0.0
	_foot_rest = Vector3(0.22, 0.1, 0.12)
	_hand_rest = Vector3(1.02, 1.4, 0.1)
	var main := _mat(color, 0.4)
	var dark := _mat(color.darkened(0.45), 0.5)
	var cream := _mat(CREAM, 0.5)
	var metal := _mat(METAL, 0.3)
	var ink := _mat(INK, 0.3)
	for i in 4:
		var ring := _part(_tilt, _tor(0.3, 0.43), metal, Vector3(0, 0.16 + 0.2 * i, 0))
		_rings.append(ring)
	_ball = _node(_tilt, Vector3(0, 1.58, 0))
	_head = _ball
	_part(_ball, _sph(0.9), main)
	_part(_ball, _cyl(0.4, 0.82, 0.24), cream, Vector3(0, -0.74, 0))
	_part(_ball, _box(Vector3(0.64, 0.22, 0.1)), ink, Vector3(0, -0.24, 0.82))
	_part(_ball, _box(Vector3(0.52, 0.1, 0.1)), _mat(WHITE, 0.3), Vector3(0, -0.19, 0.85))
	_both(func(sx: float, s: int) -> void:
		_part(_ball, _cyl(0.0, 0.24, 0.75), cream, Vector3(0.5 * sx, 0.85, 0.05), Vector3.ONE, Vector3(0, 0, -0.5 * sx))
		_eye(_ball, Vector3(0.3 * sx, 0.24, 0.7), 0.25)
		_part(_ball, _box(Vector3(0.38, 0.09, 0.1)), ink, Vector3(0.3 * sx, 0.52, 0.74), Vector3.ONE, Vector3(-0.3, 0, 0.4 * sx))
		_part(_feet[s], _sph(0.22), dark, Vector3.ZERO, Vector3(1, 0.6, 1.6))
		_part(_hands[s], _sph(0.2), cream))


## Plush dinosaur: heavy, unhurried stomp, rolling from side to side with a swinging tail and sleepy eyes.
func _build_dino() -> void:
	cadence = 0.3; swing = 0.45; lift = 0.42; bob = 0.11; roll_amp = 0.2; twist = 0.15; lean = 0.08; arm = 0.12
	_foot_rest = Vector3(0.5, 0.18, 0.1)
	_hand_rest = Vector3(0.62, 1.05, 0.75)
	var main := _mat(color, 0.8)
	var light := _mat(color.lightened(0.3), 0.8)
	var dark := _mat(color.darkened(0.35), 0.8)
	var cream := _mat(CREAM, 0.8)
	var spike := _mat(ORANGE if color.r < 0.8 or color.g < 0.5 else Color(0.55, 0.3, 0.9), 0.7)
	_part(_tilt, _sph(1.0), main, Vector3(0, 0.95, 0), Vector3(1, 0.92, 1.05))
	_part(_tilt, _sph(0.72), cream, Vector3(0, 0.8, 0.62), Vector3(1, 1, 0.5))
	_part(_tilt, _box(Vector3(0.36, 0.05, 0.36)), light, Vector3(-0.5, 1.72, -0.35), Vector3.ONE, Vector3(-0.5, 0.3, 0.45))
	_head = _node(_tilt, Vector3(0, 1.8, 0.4))
	_part(_head, _sph(0.66), main)
	_part(_head, _sph(0.42), light, Vector3(0, -0.14, 0.5), Vector3(1.05, 0.75, 1.1))
	_both(func(sx: float, s: int) -> void:
		_part(_head, _sph(0.05), _mat(INK), Vector3(0.14 * sx, 0.02, 0.9))
		_eye(_head, Vector3(0.36 * sx, 0.2, 0.42), 0.21, 0.55, 0.55, main)
		_part(_feet[s], _sph(0.34), dark, Vector3.ZERO, Vector3(1.1, 0.6, 1.4))
		for i in 3:
			_part(_feet[s], _sph(0.085), cream, Vector3(-0.2 + 0.2 * i, -0.02, 0.44))
		_part(_hands[s], _sph(0.18), dark))
	var cone := _cyl(0.0, 0.2, 0.45)
	_part(_head, cone, spike, Vector3(0, 0.72, -0.1), Vector3.ONE, Vector3(-0.15, 0, 0))
	_part(_tilt, cone, spike, Vector3(0, 2.25, -0.3), Vector3.ONE, Vector3(-0.75, 0, 0))
	_part(_tilt, cone, spike, Vector3(0, 1.8, -0.72), Vector3.ONE, Vector3(-1.0, 0, 0))
	_part(_tilt, cone, spike, Vector3(0, 1.3, -1.0), Vector3.ONE, Vector3(-1.3, 0, 0))
	_tail = _node(_tilt, Vector3(0, 0.55, -0.8))
	_part(_tail, _cyl(0.0, 0.4, 1.2), main, Vector3(0, 0, -0.55), Vector3.ONE, Vector3(-PI * 0.5, 0, 0))
	_part(_tail, _cyl(0.0, 0.14, 0.32), spike, Vector3(0, 0.3, -0.5), Vector3.ONE, Vector3(-0.4, 0, 0))


## Rubber duck: frantic pitter-patter on flat feet, head pecking forward, wings flapping, tail wiggling.
func _build_duck() -> void:
	cadence = 0.8; swing = 0.28; lift = 0.22; bob = 0.06; roll_amp = 0.16; twist = 0.2; lean = 0.1; arm = 0.0
	_foot_rest = Vector3(0.4, 0.09, 0.15)
	_hand_rest = Vector3(0.95, 0.9, -0.05)
	var main := _mat(color, 0.25)
	var light := _mat(color.lightened(0.3), 0.25)
	var beak := _mat(ORANGE if color.r < 0.8 or color.g < 0.5 else Color(1.0, 0.4, 0.15), 0.3)
	_part(_tilt, _sph(0.92), main, Vector3(0, 0.82, 0), Vector3(1, 0.78, 1.15))
	_tail = _node(_tilt, Vector3(0, 0.95, -0.85))
	_part(_tail, _cyl(0.0, 0.3, 0.6), main, Vector3(0, 0.15, -0.15), Vector3.ONE, Vector3(-0.9, 0, 0))
	_head = _node(_tilt, Vector3(0, 1.78, 0.32))
	_part(_head, _sph(0.64), main)
	_part(_head, _sph(0.3), beak, Vector3(0, -0.1, 0.62), Vector3(1.25, 0.4, 1.3))
	_part(_head, _sph(0.3), beak, Vector3(0, -0.21, 0.55), Vector3(1.05, 0.3, 1.0))
	_part(_head, _cyl(0.0, 0.09, 0.36), light, Vector3(0, 0.68, -0.05), Vector3.ONE, Vector3(-0.4, 0, 0))
	_part(_head, _cyl(0.0, 0.08, 0.3), light, Vector3(0.1, 0.63, -0.16), Vector3.ONE, Vector3(-0.8, 0, -0.3))
	_both(func(sx: float, s: int) -> void:
		_eye(_head, Vector3(0.34 * sx, 0.16, 0.44), 0.19, 0.7)
		_part(_feet[s], _sph(0.3), beak, Vector3.ZERO, Vector3(1.2, 0.3, 1.5))
		_part(_hands[s], _sph(0.42), light, Vector3(0, 0, -0.1), Vector3(0.35, 0.8, 1.2)))


## The die: tumbles from edge to edge, rocking hard and catching itself at every step.
func _build_die() -> void:
	cadence = 0.34; swing = 0.36; lift = 0.3; bob = 0.18; roll_amp = 0.33; twist = 0.25; lean = 0.0
	arm = 0.3; snap = 0.5
	_foot_rest = Vector3(0.45, 0.16, 0.05)
	_hand_rest = Vector3(1.05, 1.0, 0.1)
	var main := _mat(color, 0.3)
	var dark := _mat(color.darkened(0.45), 0.5)
	var pip := _mat(WHITE, 0.3)
	_head = _node(_tilt, Vector3(0, 1.15, 0))
	_part(_head, _box(Vector3(1.5, 1.5, 1.5)), main)
	var dot := _sph(0.14)
	var flat_y := Vector3(1, 0.3, 1)
	for v: Vector2 in [Vector2(0, 0), Vector2(0.42, 0.42), Vector2(-0.42, 0.42), Vector2(0.42, -0.42), Vector2(-0.42, -0.42)]:
		_part(_head, dot, pip, Vector3(v.x, 0.75, v.y), flat_y)
	for i in 3:
		_part(_head, dot, pip, Vector3(0.75, 0.42 - 0.42 * i, -0.42 + 0.42 * i), Vector3(0.3, 1, 1))
	for v: Vector2 in [Vector2(0.4, 0.4), Vector2(-0.4, 0.4), Vector2(0.4, -0.4), Vector2(-0.4, -0.4)]:
		_part(_head, dot, pip, Vector3(-0.75, v.x, v.y), Vector3(0.3, 1, 1))
	_part(_head, dot, pip, Vector3(0.38, 0.38, -0.75), Vector3(1, 1, 0.3))
	_part(_head, dot, pip, Vector3(-0.38, -0.38, -0.75), Vector3(1, 1, 0.3))
	_part(_head, _box(Vector3(0.34, 0.09, 0.06)), _mat(INK), Vector3(0, -0.3, 0.75))
	_both(func(sx: float, s: int) -> void:
		_eye(_head, Vector3(0.34 * sx, 0.2, 0.74), 0.24, 0.5)
		_part(_feet[s], _sph(0.28), dark, Vector3.ZERO, Vector3(1, 0.6, 1.35))
		_part(_hands[s], _sph(0.2), pip))


## Roly-poly doll: never quite upright. Shuffles on tiny feet while its round body rocks in circles.
func _build_doll() -> void:
	cadence = 0.55; swing = 0.16; lift = 0.08; bob = 0.0; roll_amp = 0.0; twist = 0.0; lean = 0.04; arm = 0.1
	rock = 0.22; idle_rock = 0.07; idle_rate = 1.7
	_foot_rest = Vector3(0.3, 0.08, 0.25)
	_hand_rest = Vector3(0.98, 1.05, 0.2)
	var main := _mat(color, 0.3)
	var light := _mat(color.lightened(0.4), 0.3)
	var dark := _mat(color.darkened(0.4), 0.4)
	var cream := _mat(CREAM, 0.4)
	_part(_tilt, _sph(1.0), main, Vector3(0, 0.95, 0))
	_part(_tilt, _tor(0.66, 0.8), dark, Vector3(0, 1.5, 0))
	_part(_tilt, _sph(0.34), cream, Vector3(0, 0.85, 0.9), Vector3(1, 1, 0.3))
	_part(_tilt, _sph(0.15), _mat(ORANGE, 0.4), Vector3(0, 0.85, 0.99), Vector3(1, 1, 0.4))
	_head = _node(_tilt, Vector3(0, 1.95, 0))
	_part(_head, _sph(0.68), main)
	_part(_head, _sph(0.52), cream, Vector3(0, 0.08, 0.36), Vector3(1, 1, 0.75))
	_part(_head, _sph(0.2), light, Vector3(0, 0.62, 0.1), Vector3(1.4, 0.5, 1))
	_part(_head, _box(Vector3(0.16, 0.05, 0.05)), _mat(Color(0.8, 0.25, 0.3)), Vector3(0, -0.16, 0.74))
	var blush := _mat(Color(1.0, 0.55, 0.6), 0.6)
	_both(func(sx: float, s: int) -> void:
		_eye(_head, Vector3(0.2 * sx, 0.16, 0.7), 0.14, 0.75)
		_part(_head, _sph(0.1), blush, Vector3(0.34 * sx, -0.04, 0.64), Vector3(1, 0.7, 0.4))
		_part(_tilt, _sph(0.16), light, Vector3(0.15 * sx, 1.4, 0.74), Vector3(1.2, 0.8, 0.6))
		_part(_feet[s], _sph(0.2), dark, Vector3.ZERO, Vector3(1, 0.5, 1.3))
		_part(_hands[s], _sph(0.17), cream))


## Spinning top: always turning, tiptoes on tiny feet and leans far into wherever it is going.
func _build_top() -> void:
	cadence = 0.75; swing = 0.18; lift = 0.14; bob = 0.03; roll_amp = 0.0; twist = 0.0; lean = 0.24; arm = 0.0
	idle_rock = 0.06; idle_rate = 3.1; rock = 0.05
	_foot_rest = Vector3(0.3, 0.1, 0.1)
	_hand_rest = Vector3(1.15, 1.35, 0.0)
	var main := _mat(color, 0.25)
	var light := _mat(color.lightened(0.45), 0.25)
	var dark := _mat(color.darkened(0.45), 0.3)
	_spin = _node(_tilt, Vector3.ZERO)
	_part(_spin, _cyl(0.95, 0.08, 0.9), main, Vector3(0, 0.65, 0))
	_part(_spin, _cyl(1.0, 1.0, 0.3), light, Vector3(0, 1.25, 0))
	_part(_spin, _sph(0.95), main, Vector3(0, 1.4, 0), Vector3(1, 0.45, 1))
	for i in 6:
		var a := TAU * i / 6.0
		_part(_spin, _box(Vector3(0.26, 0.31, 0.1)), dark, Vector3(sin(a) * 0.97, 1.25, cos(a) * 0.97), Vector3.ONE, Vector3(0, a, 0))
	for i in 3:
		var a := TAU * i / 3.0
		_part(_spin, _sph(0.2), light, Vector3(sin(a) * 0.5, 1.74, cos(a) * 0.5), Vector3(1.6, 0.25, 0.8), Vector3(0, a + 0.9, 0))
	_part(_spin, _cyl(0.11, 0.14, 0.6), _mat(METAL, 0.3), Vector3(0, 2.05, 0))
	_part(_spin, _sph(0.2), _mat(CREAM, 0.3), Vector3(0, 2.4, 0))
	_head = _node(_tilt, Vector3(0, 1.3, 0))
	_both(func(sx: float, s: int) -> void:
		_eye(_head, Vector3(0.3 * sx, 0.36, 0.74), 0.22, 0.5)
		_part(_feet[s], _sph(0.2), dark, Vector3.ZERO, Vector3(1, 0.6, 1.3))
		_part(_hands[s], _sph(0.17), _mat(WHITE, 0.3)))


## Teddy bear: a soft, friendly amble with swinging arms and a head that sways along.
func _build_teddy() -> void:
	cadence = 0.36; swing = 0.42; lift = 0.28; bob = 0.09; roll_amp = 0.12; twist = 0.28; lean = 0.05; arm = 0.6
	_foot_rest = Vector3(0.48, 0.2, 0.12)
	_hand_rest = Vector3(0.98, 1.0, 0.15)
	var main := _mat(color, 0.9)
	var dark := _mat(color.darkened(0.3), 0.9)
	var cream := _mat(CREAM, 0.9)
	var ink := _mat(INK, 0.2)
	var bow := _mat(Color(0.95, 0.3, 0.4) if color.r < 0.8 or color.g > 0.5 else Color(0.3, 0.6, 1.0), 0.5)
	_part(_tilt, _sph(0.92), main, Vector3(0, 0.9, 0), Vector3(1, 1, 0.95))
	_part(_tilt, _sph(0.6), cream, Vector3(0, 0.82, 0.6), Vector3(1, 1, 0.45))
	_part(_tilt, _sph(0.09), bow, Vector3(0, 1.32, 0.78))
	_head = _node(_tilt, Vector3(0, 1.85, 0.15))
	_part(_head, _sph(0.72), main)
	_part(_head, _sph(0.32), cream, Vector3(0, -0.16, 0.6), Vector3(1.1, 0.8, 0.8))
	_part(_head, _sph(0.1), ink, Vector3(0, -0.06, 0.84), Vector3(1.3, 0.9, 1))
	_both(func(sx: float, s: int) -> void:
		_part(_head, _sph(0.28), main, Vector3(0.55 * sx, 0.52, 0), Vector3(1, 1, 0.6))
		_part(_head, _sph(0.16), cream, Vector3(0.55 * sx, 0.52, 0.12), Vector3(1, 1, 0.4))
		_eye(_head, Vector3(0.3 * sx, 0.14, 0.56), 0.15, 0.8)
		_part(_tilt, _sph(0.18), bow, Vector3(0.22 * sx, 1.32, 0.74), Vector3(1.3, 0.9, 0.5))
		_part(_feet[s], _sph(0.34), dark, Vector3.ZERO, Vector3(1, 0.65, 1.3))
		_part(_feet[s], _sph(0.2), cream, Vector3(0, 0.02, 0.36), Vector3(1, 1, 0.3))
		_part(_hands[s], _sph(0.26), dark))
