class_name ToyMotion
extends RefCounted
## Follows one player for its figure, frame by frame: reads the sim state the view draws the player from (the
## predicted sim, or online for the other players the interpolated display sim), measures the drawn movement,
## notices the moments (throw, catch, end of a dash, death, respawn) and moves the pose with ToyPose's springs.
## Node-free: tests drive it directly. Only reads the sim.

const SPEED_SMOOTH := 18.0       # 1/s: low-pass of the measured velocity
const TELEPORT := 2.5            # metres in one frame: a respawn or a correction, not movement
const TURN_RATE := 20.0          # 1/s: easing of the facing
const FAST_TURN_RATE := 45.0     # while dashing or flying
## A drawn speed above this many player speeds counts as a dash (online, the dash_t of the others can fall
## between two snapshots; the drawn movement cannot).
const DASH_SPEED_FACTOR := 2.0
const SPIN_IDLE := 2.0           # rad/s of the top's base standing still
const SPIN_RUN := 10.0           # extra rad/s at full running speed
const SPIN_DASH := 30.0          # rad/s in a dash or a pull
## The die: side length of its cube in player radii (ToyFigure builds the cube from it), how fast a rolled cube
## eases back to face the front, the hop height of that settling at a half turn still to go.
const DIE_SIDE := 1.84
const TUMBLE_SETTLE := 12.0      # 1/s
const TUMBLE_SNAP := 0.02        # rad: closer than this to upright it snaps
const SETTLE_HOP := 0.35

var kind := 0
var facts := ToyPose.Facts.new()
var target: Array[float] = ToyPose.new_pose()
var shown: Array[float] = ToyPose.new_pose()
var vel: Array[float] = []
var act: int = ToyPose.Act.DEAD
var yaw := 0.0
var velocity := Vector2.ZERO     # smoothed drawn velocity, m/s
var spin := 0.0                  # angle of the spinning top's base: slow idle, faster running, fastest in a dash
var wind := 0.0                  # angle of the wind-up key (robot)
## The die only: orientation of its cube in the figure's frame (identity = face to the front). Walking rolls it over
## its edges, one side length = a quarter turn; standing, stunned or spawning it eases back to the identity.
var tumble := Basis.IDENTITY
var settling := false            # the die is easing back to upright (it hops a little while it does)
var popped := false              # true on the frame the player died: the figure pops
var spawned := false             # true on the frame the player (re)appeared: the figure drops in
var _last := Vector2.INF
var _alive := false
var _hand := -1
var _dashing := false


func _init(figure_kind := 0) -> void:
	kind = figure_kind
	facts.kind = figure_kind
	for _c in ToyPose.CHANNELS:
		vel.append(0.0)


## One frame. `p` is the player as `src` has it, `drawn` its drawn (interpolated) ground position.
func update(p: SimPlayer, src: Sim, drawn: Vector2, dt: float) -> void:
	popped = false
	spawned = false
	dt = clampf(dt, 0.0, 0.1)
	var alive := p.enabled and p.alive
	if alive and not _alive:
		_appear(p, drawn)
	elif _alive and not alive and p.enabled:
		popped = true
	_alive = alive
	facts.alive = alive
	facts.time += dt
	if not alive:
		act = ToyPose.targets(facts, target)
		return
	var cfg := src.cfg
	var ps := maxf(cfg.player_speed, 0.1)
	# Movement as drawn (works the same for the predicted sim and the interpolated display sim).
	if drawn.distance_to(_last) > TELEPORT:
		_last = drawn
		velocity = Vector2.ZERO
	var step := drawn - _last
	var moved := step.length()
	if dt > 0.0:
		velocity = velocity.lerp((drawn - _last) / dt, 1.0 - exp(-SPEED_SMOOTH * dt))
	_last = drawn
	var face := (p.aim_dir if p.charging else p.facing)
	face = face.normalized() if face.length() > 0.001 else Vector2.DOWN
	var side := Vector2(face.y, -face.x)
	facts.fwd_speed = velocity.dot(face) / ps
	facts.side_speed = velocity.dot(side) / ps
	facts.gait = fmod(facts.gait + moved / (ToyPose.CYCLE[kind] * cfg.player_radius) * TAU, TAU)
	# Timers first, then the moments that restart them.
	facts.since_throw += dt
	facts.since_catch += dt
	facts.since_dash += dt
	facts.since_spawn += dt
	facts.charging = p.charging
	facts.charge = clampf(p.charge_t / maxf(cfg.charge_time, 0.001), 0.0, 1.0)
	facts.pulling = p.pulling or p.fling_left > 0.0
	facts.stunned = p.stun_t > 0.0
	facts.out = p.any_out()
	var dashing := p.dash_t > 0.0 or (velocity.length() > ps * DASH_SPEED_FACTOR and not facts.pulling)
	if _dashing and not dashing:
		facts.since_dash = 0.0
	_dashing = dashing
	facts.dashing = dashing
	var hand := p.count_state(SimHead.S.HAND)
	if _hand >= 0 and hand < _hand:
		facts.since_throw = 0.0
	elif _hand >= 0 and hand > _hand:
		facts.since_catch = 0.0
	_hand = hand
	act = ToyPose.targets(facts, target)
	ToyPose.spring_step(shown, vel, target, dt, act == ToyPose.Act.SPAWN and facts.since_spawn < ToyPose.DROP_TIME + ToyPose.LAND_TIME)
	var rate := FAST_TURN_RATE if dashing or facts.pulling else TURN_RATE
	yaw += angle_difference(yaw, atan2(face.x, face.y)) * (1.0 - exp(-rate * dt))
	# The key turns while the toy runs and is wound back hard while charging.
	var walk := clampf(velocity.length() / ps, 0.0, 1.0)
	spin += dt * (SPIN_DASH if dashing or facts.pulling else SPIN_IDLE + SPIN_RUN * walk)
	wind += dt * (-12.0 * facts.charge if facts.charging else 1.5 + 9.0 * walk)
	if kind == ToyPose.Kind.DIE:
		_roll_die(step, velocity.length() / ps, cfg.player_radius, dt)


## The die's cube: rolls over the edge in the direction of this frame's drawn movement `step` (in the figure's frame:
## local +z is the facing, local +x the `side` vector of `update`), or eases back to upright while the figure
## stands (`speed`: smoothed, in player speeds), is stunned or is spawning.
func _roll_die(step: Vector2, speed: float, radius: float, dt: float) -> void:
	settling = speed < ToyPose.WALK_MIN or act == ToyPose.Act.STUN or act == ToyPose.Act.SPAWN
	if settling:
		var q := tumble.get_rotation_quaternion().normalized()
		if q.angle_to(Quaternion.IDENTITY) < TUMBLE_SNAP:
			tumble = Basis.IDENTITY
		else:
			tumble = Basis(q.slerp(Quaternion.IDENTITY, 1.0 - exp(-TUMBLE_SETTLE * dt)))
		return
	var local := Vector3(step.dot(Vector2(cos(yaw), -sin(yaw))), 0.0, step.dot(Vector2(sin(yaw), cos(yaw))))
	var dist := local.length()
	if dist < 0.00001:
		return
	var axis := Vector3.UP.cross(local / dist)            # the top tips towards the movement
	tumble = (Basis(axis.normalized(), (PI * 0.5) * dist / (DIE_SIDE * radius)) * tumble).orthonormalized()


## Height of the die's cube centre above the floor (player radii): half the side times the sum of the absolute
## vertical components of its three axes, so a cube standing on an edge is higher than one lying flat.
func die_height() -> float:
	return DIE_SIDE * 0.5 * (absf(tumble.x.y) + absf(tumble.y.y) + absf(tumble.z.y))


## The extra hop while the die settles: grows with the angle still to go (SETTLE_HOP at a half turn).
func die_hop() -> float:
	if not settling:
		return 0.0
	return SETTLE_HOP * tumble.get_rotation_quaternion().normalized().angle_to(Quaternion.IDENTITY) / PI


func _appear(p: SimPlayer, drawn: Vector2) -> void:
	spawned = true
	tumble = Basis.IDENTITY
	settling = false
	_last = drawn
	velocity = Vector2.ZERO
	var face := p.facing if p.facing.length() > 0.001 else Vector2.DOWN
	yaw = atan2(face.x, face.y)
	facts.since_spawn = 0.0
	facts.since_throw = 99.0
	facts.since_catch = 99.0
	facts.since_dash = 99.0
	_dashing = false
	_hand = p.count_state(SimHead.S.HAND)
	for c in ToyPose.CHANNELS:
		shown[c] = ToyPose.REST[c]
		vel[c] = 0.0


## How far the yo-yo hand is wound up behind the shoulder (0..1).
func wind_up() -> float:
	return clampf(-shown[ToyPose.ARM], 0.0, 1.0)
