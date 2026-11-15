class_name ToyPose
extends RefCounted
## The body language of the toy figures as pure functions: which pose the state of one player asks for
## (`targets`), and the springs that move the shown pose towards it (`spring_step`). No nodes and no clock of its
## own: everything is a function of the arguments, so it is testable headless and the same at every frame rate.
## ToyMotion feeds it from the sim, ToyFigure turns the pose into node transforms.

enum Kind { DINO, ROBOT, BUNNY, DUCK, IMP, DIE, DOLL, TOP }
enum Act { IDLE, WALK, CHARGE, THROW, OUT, CATCH, DASH, DASH_STOP, PULL, STUN, DEAD, SPAWN }

## Pose channels (indices into a pose array). Units: radians, player radii, scale factors.
enum {
	LEAN,      # forward pitch (+ = leaning forward)
	ROLL,      # sideways tilt
	SQUASH,    # height scale (the width follows so the volume stays)
	STRETCH,   # scale along the facing
	LIFT,      # whole body up (hop, drop, flight)
	ARM,       # yo-yo arm: -1 wound up behind the shoulder, 0 hanging, 1 reaching forward
	TWIST,     # upper body turned (wind-up, waddle)
	HEAD,      # head pitch (+ = nodding forward)
	STEP,      # how far the feet swing (0 = standing)
	TREMBLE,   # shake amplitude (full charge)
	DIZZY,     # stun 0..1 (stars, wobble)
	EARS,      # extra swing of floppy parts (bunny ears, duck tail)
	JAW,       # snapper dino: how far the lower jaw is open (0 shut, 1 wide)
	TILT_F,    # roly-poly doll: forward tilt on its round bottom (springs back with a decaying swing)
	TILT_S,    # roly-poly doll: sideways tilt (same kind of spring)
	CHANNELS,
}

const REST: Array[float] = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## Spring per channel: angular frequency (1/s) and damping ratio (< 1 overshoots: the jelly of squash and stretch).
const OMEGA: Array[float] = [15.0, 13.0, 24.0, 22.0, 26.0, 17.0, 13.0, 13.0, 11.0, 20.0, 9.0, 10.0, 34.0, 11.0, 11.0]
const ZETA: Array[float] = [0.7, 0.6, 0.36, 0.42, 0.55, 0.8, 0.75, 0.5, 1.0, 1.0, 1.0, 0.28, 0.5, 0.13, 0.13]
const SUBSTEP := 1.0 / 240.0       # the springs integrate in fixed small steps: same result at 30, 60 or 120 fps

const THROW_TIME := 0.3            # lunge and follow-through after a throw
const CATCH_TIME := 0.26           # recoil when a yo-yo lands in the hand
const DASH_STOP_TIME := 0.16       # squash at the end of a dash
const DROP_TIME := 0.24            # respawn: falling from DROP_HEIGHT
const SPAWN_TIME := 0.5            # the drop and the bounce after it
const DROP_HEIGHT := 3.4
const LAND_TIME := 0.07            # how long the landing squash is held
const WALK_MIN := 0.12             # below this speed (in player speeds) the figure stands
const BREATH_SPEED := 2.4
## Actions in which the feet keep walking.
const GAIT_ACTS: Array[int] = [Act.IDLE, Act.WALK, Act.CHARGE, Act.THROW, Act.OUT, Act.CATCH]
## Walk cycle length (two steps, or one hop) per kind, in player radii.
const CYCLE: Array[float] = [4.0, 3.2, 4.6, 2.14, 4.2, 4.4, 2.6, 2.8]


## What a figure knows about its player in one frame.
class Facts:
	var kind := 0
	var alive := true
	var fwd_speed := 0.0      # drawn velocity along the facing, in player speeds
	var side_speed := 0.0     # drawn velocity sideways (+ = towards the figure's local +x), in player speeds
	var charging := false
	var charge := 0.0         # 0..1
	var dashing := false
	var pulling := false      # pulled to the yo-yo or flung by the Gummiband
	var stunned := false
	var out := false          # at least one yo-yo is out (the string is in the hand)
	var since_throw := 99.0   # seconds since a yo-yo left the hand
	var since_catch := 99.0   # seconds since a yo-yo came back into the hand
	var since_dash := 99.0    # seconds since the last dash ended
	var since_spawn := 99.0   # seconds since the figure (re)appeared
	var gait := 0.0           # walk cycle phase in radians, advanced by the distance walked
	var time := 0.0           # running clock for breathing, tremble and dizziness


static func new_pose() -> Array[float]:
	return REST.duplicate()


## The action that decides the pose (the most important one wins).
static func act_of(f: Facts) -> int:
	if not f.alive:
		return Act.DEAD
	if f.since_spawn < SPAWN_TIME:
		return Act.SPAWN
	if f.stunned:
		return Act.STUN
	if f.pulling:
		return Act.PULL
	if f.dashing:
		return Act.DASH
	if f.charging:
		return Act.CHARGE
	if f.since_throw < THROW_TIME:
		return Act.THROW
	if f.since_dash < DASH_STOP_TIME:
		return Act.DASH_STOP
	if f.since_catch < CATCH_TIME:
		return Act.CATCH
	if f.out:
		return Act.OUT
	if Vector2(f.fwd_speed, f.side_speed).length() > WALK_MIN:
		return Act.WALK
	return Act.IDLE


## Fills `out` (CHANNELS floats) with the pose the facts ask for and returns the deciding action.
static func targets(f: Facts, out: Array[float]) -> int:
	for c in CHANNELS:
		out[c] = REST[c]
	var act := act_of(f)
	if act == Act.DEAD:
		return act
	var spd := clampf(Vector2(f.fwd_speed, f.side_speed).length(), 0.0, 1.3)
	var walk := clampf((spd - WALK_MIN) / (0.8 - WALK_MIN), 0.0, 1.0)
	out[SQUASH] = 1.0 + 0.03 * sin(f.time * BREATH_SPEED)   # breathing
	out[ARM] = 0.3                                           # holding the yo-yo in front of the belly
	# Lean into the movement: forward with speed, into the side the figure is drifting to.
	out[LEAN] = 0.16 * clampf(f.fwd_speed, -1.0, 1.2)
	out[ROLL] = -0.12 * clampf(f.side_speed, -1.0, 1.0)
	# Toys that never stand quite still: the roly-poly doll sways, the spinning top wobbles around its tip.
	if f.kind == Kind.DOLL:
		out[ROLL] += 0.07 * sin(f.time * 1.7) * (1.0 - walk)
		out[LEAN] += 0.07 * cos(f.time * 1.7) * (1.0 - walk)
	elif f.kind == Kind.TOP:
		out[ROLL] += 0.05 * sin(f.time * 3.1)
		out[LEAN] += 0.05 * cos(f.time * 3.1)
	if f.kind == Kind.DOLL:
		# Roly-poly: no stepping lean; it tips on its round bottom into the drift and swings back (TILT springs).
		out[LEAN] = 0.0
		out[ROLL] = 0.05 * sin(f.time * 1.7) * (1.0 - walk)
		out[TILT_F] = 0.55 * clampf(f.fwd_speed, -1.0, 1.3)
		out[TILT_S] = -0.5 * clampf(f.side_speed, -1.0, 1.0)
	if act in GAIT_ACTS:
		_gait(f, walk * (0.6 if act == Act.CHARGE else 1.0), out)
	match act:
		Act.CHARGE:
			# Wind-up that grows with the charge: lean back, crouch, turn away, yo-yo behind the shoulder.
			var c := clampf(f.charge, 0.0, 1.0)
			out[LEAN] = 0.04 * clampf(f.fwd_speed, -1.0, 1.0) - 0.34 * c
			out[SQUASH] -= 0.15 * c
			out[STRETCH] = 1.0 - 0.06 * c
			out[ARM] = lerpf(0.3, -1.0, c)
			out[TWIST] = -0.5 * c
			out[HEAD] = 0.14 * c
			out[TREMBLE] = 0.08 * smoothstep(0.85, 1.0, c)
			out[JAW] = 0.3 + 0.7 * c if f.kind == Kind.DINO else 0.0     # the snapper opens wider and wider
		Act.THROW:
			# Lunge after the release, then the follow-through.
			var k := 1.0 - clampf(f.since_throw / THROW_TIME, 0.0, 1.0)
			out[LEAN] = 0.12 + 0.5 * k
			out[STRETCH] = 1.0 + 0.28 * k
			out[SQUASH] = 1.0 - 0.1 * k
			out[ARM] = 1.0
			out[TWIST] = 0.4 * k
			out[HEAD] = 0.1
			out[JAW] = 0.0                                       # ... and snaps shut on the throw
		Act.OUT:
			out[ARM] = 0.85
			out[LEAN] += 0.08
			out[HEAD] = 0.05
		Act.CATCH:
			# The yo-yo smacks into the hand: the figure recoils and squashes.
			var k := 1.0 - clampf(f.since_catch / CATCH_TIME, 0.0, 1.0)
			out[SQUASH] = 1.0 - 0.24 * k
			out[STRETCH] = 1.0 - 0.08 * k
			out[LEAN] = -0.22 * k
			out[ARM] = 0.1
			out[HEAD] = -0.2 * k
		Act.DASH:
			out[LEAN] = 0.4
			out[STRETCH] = 1.5
			out[SQUASH] = 0.82
			out[LIFT] = 0.1
			out[ARM] = 0.1
			out[STEP] = 0.0
			out[TWIST] = 0.0
			out[EARS] = 1.0
		Act.DASH_STOP:
			var k := 1.0 - clampf(f.since_dash / DASH_STOP_TIME, 0.0, 1.0)
			out[STRETCH] = 1.0 - 0.26 * k
			out[SQUASH] = 1.0 - 0.18 * k
			out[LEAN] = -0.24 * k
			out[ARM] = 0.3
			out[EARS] = -0.6 * k
			if f.kind == Kind.DOLL:
				out[TILT_F] = -0.7 * k                           # the round bottom rocks back after a dash
		Act.PULL:
			# Flying to the yo-yo: stretched out, lifted off the ground, arm forward, feet trailing.
			out[LEAN] = 0.8
			out[STRETCH] = 1.38
			out[SQUASH] = 0.86
			out[LIFT] = 0.4
			out[ARM] = 1.0
			out[HEAD] = -0.35
			out[STEP] = 0.0
			out[EARS] = 1.0
		Act.STUN:
			var t := f.time * 7.5
			out[DIZZY] = 1.0
			out[ROLL] = 0.3 * sin(t)
			out[LEAN] = 0.22 * cos(t)
			out[HEAD] = 0.25 * sin(t * 0.7)
			out[SQUASH] = 0.92
			out[ARM] = 0.0
			out[STEP] = 0.0
			if f.kind == Kind.DOLL:
				out[TILT_F] = 0.45 * sin(t * 0.9)               # hit: rocks wildly, then settles by itself
				out[TILT_S] = 0.45 * cos(t * 0.9)
		Act.SPAWN:
			if f.since_spawn < DROP_TIME:
				var u := f.since_spawn / DROP_TIME
				out[LIFT] = DROP_HEIGHT * (1.0 - u * u)          # falls like a dropped toy
				out[SQUASH] = 1.12
				out[STRETCH] = 0.92
				out[EARS] = -1.0
			elif f.since_spawn < DROP_TIME + LAND_TIME:
				out[SQUASH] = 0.62                                # landing squash; the spring bounces back
				out[STRETCH] = 1.12
			out[ARM] = 0.3
	return act


## Kind-specific walk: dino stomps, robot steps stiffly, bunny hops, duck waddles, the imp bounces on its spring,
## the die tumbles from edge to edge, the doll rocks in circles, the top tiptoes leaning far in. `w` is 0..1.
static func _gait(f: Facts, w: float, out: Array[float]) -> void:
	if w <= 0.0:
		return
	var s := sin(f.gait)
	match f.kind:
		Kind.DINO:
			out[STEP] = w
			out[JAW] = w * 0.75 * smoothstep(-0.15, 0.15, sin(f.gait * 2.0))   # the jaw snaps open and shut with the steps
			out[LIFT] += 0.07 * w * absf(s)
			out[SQUASH] -= 0.09 * w * pow(1.0 - absf(s), 6.0)    # heavy footfall
			out[ROLL] += 0.07 * w * s
			out[LEAN] += 0.05 * w
		Kind.ROBOT:
			var q := clampf(s * 3.0, -1.0, 1.0)                  # stiff: snaps from one step to the next
			out[STEP] = w
			out[LIFT] += 0.03 * w * absf(q)
			out[LEAN] *= 0.35
			out[ROLL] *= 0.3
			out[TWIST] += 0.1 * w * q
		Kind.BUNNY:
			var hop := maxf(0.0, s)
			out[STEP] = w
			out[LIFT] += 0.6 * w * hop
			out[SQUASH] += w * (0.1 * hop - 0.14 * pow(1.0 - hop, 8.0) * float(s <= 0.0))
			out[LEAN] += 0.08 * w * cos(f.gait)
			out[EARS] += 0.8 * w * cos(f.gait)
		Kind.DUCK:
			out[STEP] = w                                        # wheels: the view turns them with the gait
			out[ROLL] += 0.16 * w * s                            # rocks on its wheels in step with them
			out[TWIST] += 0.1 * w * s
			out[EARS] += 0.6 * w * s
		Kind.IMP:
			var hop := maxf(0.0, s)
			out[STEP] = w
			out[LIFT] += 0.8 * w * hop
			out[SQUASH] += w * (0.16 * hop - 0.24 * pow(1.0 - hop, 6.0) * float(s <= 0.0))   # the spring loads
			out[LEAN] += 0.1 * w * cos(f.gait)
			out[EARS] += w * cos(f.gait)
		Kind.DIE:
			var q := clampf(s * 2.2, -1.0, 1.0)                  # tips over an edge, then catches itself
			out[STEP] = w
			out[ROLL] += 0.3 * w * q
			out[LIFT] += 0.16 * w * absf(q)
			out[TWIST] += 0.18 * w * q
			out[SQUASH] -= 0.08 * w * pow(1.0 - absf(s), 6.0)
			out[LEAN] *= 0.4
		Kind.DOLL:
			out[ROLL] += 0.05 * w * cos(f.gait)
		Kind.TOP:
			out[STEP] = 0.5 * w
			out[LEAN] += 0.14 * w
			out[LIFT] += 0.03 * w * absf(s)
			out[ROLL] += 0.06 * w * sin(f.gait * 2.0)


## Moves `shown` (with its velocities `vel`) towards `target` for `dt` seconds. Fixed sub-steps: independent of the
## frame rate. With `snap_lift` the lift jumps straight to its target (the fall of a respawn is exact).
static func spring_step(shown: Array[float], vel: Array[float], target: Array[float], dt: float, snap_lift := false) -> void:
	var n := maxi(1, ceili(dt / SUBSTEP - 0.001))
	var h := dt / float(n)
	for _k in n:
		for c in CHANNELS:
			var w := OMEGA[c]
			var a := w * w * (target[c] - shown[c]) - 2.0 * ZETA[c] * w * vel[c]
			vel[c] += a * h
			shown[c] += vel[c] * h
	if snap_lift:
		shown[LIFT] = target[LIFT]
		vel[LIFT] = 0.0
