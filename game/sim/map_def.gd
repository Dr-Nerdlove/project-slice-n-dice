class_name MapDef
extends RefCounted
## The maps: layout data and every number of their twists, with the pure geometry that the simulation, the bots and
## the view share. No state lives here (the state of a twist is in `Sim`). Design and reasons: docs/maps.md.
## Every map is the same room (Config.ARENA_SIZE); map 0 is the original playroom with the toy train, whose data
## stays in `Config` and `TrainTrack`. Units: metres, seconds. y = 0 is the top wall (the top of the screen).

enum Id { TRAIN, BELTS, LAVA, BOUNCE, MAGNETS, PIGGY }

const NAMES: Array[String] = ["Train Set", "Assembly Line", "Lava Mats", "Bounce House", "Magnet Lab", "Piggy Bank"]
## One line for a map picker.
const HINTS: Array[String] = [
	"A toy train circles the centre.",
	"Conveyor belts carry you along, then reverse.",
	"The floor is lava: glowing mats burn.",
	"Trampolines fling you over the wall.",
	"Magnets bend every throw.",
	"Hit the pig to take its coins.",
]

## Maps whose floor plan has been rebuilt (docs/map-rework.md). The stricter floor-plan rules of the tests (10 to
## 18 obstacles, spawn points far apart and out of sight, the 2.0 m passage rule) apply only to these.
const REWORKED: Array[int] = [0, 1, 2, 3, 4]

# --- layout per map (index = map id) ---
const OBSTACLES: Array = [
	[],  # map 0: Config.OBSTACLES
	# Assembly Line: two dividing walls (x 9..10 and 22..23) make a left, a middle and a right part. Each has a belt
	# opening (2.6 m, the belt runs through) and a walking door (2.4 m) at the far end. Short walls lie along the
	# belt's edges, never on both sides at the same x. Point-symmetric about the arena centre.
	[Rect2(9.0, 0.0, 1.0, 2.4), Rect2(9.0, 5.0, 1.0, 5.0), Rect2(9.0, 12.4, 1.0, 2.0),
			Rect2(22.0, 12.0, 1.0, 2.4), Rect2(22.0, 4.4, 1.0, 5.0), Rect2(22.0, 0.0, 1.0, 2.0),
			Rect2(0.0, 4.8, 6.4, 0.8), Rect2(25.6, 8.8, 6.4, 0.8), Rect2(0.0, 9.5, 5.6, 0.8), Rect2(26.4, 4.1, 5.6, 0.8),
			Rect2(14.1, 5.4, 0.8, 2.4), Rect2(17.1, 6.6, 0.8, 2.4)],
	# Lava Mats: a pillow fort. A windmill of four bars (1.0 m thick so that they meet exactly in float32; two long,
	# two short, so it does not read as a symbol) around a 2 m courtyard at the centre, and in each corner a small
	# room with a 2 m way out (0.8 m walls). Walls stand on mat seams; where a seam borders a final zone area the
	# wall sits flush against the area (0.4 m off the seam) so the area stays free. No wall closes the seam inside
	# a mat pair (x = 4, 12, 20, 28). Point-symmetric about the arena centre.
	[Rect2(17.0, 5.2, 5.0, 1.0), Rect2(17.0, 6.2, 1.0, 3.8), Rect2(10.0, 8.2, 5.0, 1.0), Rect2(14.0, 4.4, 1.0, 3.8),
			Rect2(0.0, 3.2, 5.6, 0.8), Rect2(7.6, 0.0, 0.8, 4.4), Rect2(26.4, 10.4, 5.6, 0.8), Rect2(23.6, 10.0, 0.8, 4.4),
			Rect2(24.0, 0.0, 0.8, 3.6), Rect2(26.8, 2.8, 5.2, 0.8), Rect2(7.2, 10.8, 0.8, 3.6), Rect2(0.0, 10.8, 5.2, 0.8)],
	# Bounce House: three long walls (1.0 m thick) divide the room into four strips side by side, each with ONE walking
	# door: left wall at the top, middle wall at the bottom, right wall at the top (a zigzag from one end to the other;
	# the doors are 4.0 m tall so that a zone area fits across the top ones). Covers inside the strips hide the two
	# starts of a strip from each other. Mirror-symmetric about x = 16 (the strips are 8.5, 6.0, 6.0 and 8.5 m wide).
	[Rect2(8.5, 4.0, 1.0, 10.4), Rect2(15.5, 0.0, 1.0, 10.4), Rect2(22.5, 4.0, 1.0, 10.4),
			Rect2(0.0, 6.5, 6.0, 1.0), Rect2(26.0, 6.5, 6.0, 1.0), Rect2(11.5, 6.5, 2.0, 1.0), Rect2(18.5, 6.5, 2.0, 1.0),
			Rect2(12.5, 11.9, 1.0, 2.5), Rect2(18.5, 11.9, 1.0, 2.5), Rect2(3.0, 2.0, 1.0, 1.0), Rect2(28.0, 2.0, 1.0, 1.0)],
	# Magnet Lab: the two magnets first (MAGNETS holds their centres). Around each magnet a broken square: an outer
	# wall (3.0 m), a wall above and one below (3.0 m, open corners) and, on the inner side, the long middle wall. A
	# straight throw into a square is blocked, a throw bent by the magnet goes round. The middle wall is extended to
	# the top and bottom wall with a 2.0 m door on each side of its centre piece. The walls above and below a square
	# end in a stem to the outer wall, a cross wall near each short side makes the end rooms. Point-symmetric about
	# the arena centre. The 2.0 m passage rule keeps every wall 2.0 m from a magnet block, so the plan's inner walls
	# at 2.5 to 5 m would not fit between the magnets and the middle wall.
	[Rect2(10.2, 6.4, 1.6, 1.6), Rect2(20.2, 6.4, 1.6, 1.6), Rect2(15.6, 5.0, 0.8, 4.4),
			Rect2(7.3, 5.7, 0.8, 3.0), Rect2(23.9, 5.7, 0.8, 3.0),
			Rect2(8.6, 2.8, 3.0, 0.8), Rect2(8.6, 10.8, 3.0, 0.8), Rect2(20.4, 2.8, 3.0, 0.8), Rect2(20.4, 10.8, 3.0, 0.8),
			Rect2(3.6, 4.7, 0.8, 5.0), Rect2(27.6, 4.7, 0.8, 5.0),
			# (the bottom stems are 2.799999 tall: 11.6 + 2.8 would end one float step beyond the outer wall)
			Rect2(8.6, 0.0, 0.8, 2.8), Rect2(8.6, 11.6, 0.8, 2.799999), Rect2(22.6, 0.0, 0.8, 2.8), Rect2(22.6, 11.6, 0.8, 2.799999),
			Rect2(15.6, 0.0, 0.8, 3.0), Rect2(15.6, 11.4, 0.8, 3.0)],
	# Piggy Bank: the pig first (PIG_RECT), then four blocks around it.
	[Rect2(15.0, 6.2, 2.0, 2.0), Rect2(10.2, 3.2, 1.6, 1.6), Rect2(20.2, 3.2, 1.6, 1.6), Rect2(10.2, 9.6, 1.6, 1.6),
			Rect2(20.2, 9.6, 1.6, 1.6)],
]
## How many of a map's first obstacles the view dresses itself (magnets, the pig) instead of as building blocks.
const SPECIAL_OBSTACLES: Array[int] = [0, 0, 0, 0, 2, 1]
const SPAWNS: Array = [
	[],  # map 0: Config.SPAWNS
	[Vector2(4.5, 7.8), Vector2(27.5, 6.6), Vector2(1.6, 1.6), Vector2(30.4, 12.8),
			Vector2(1.6, 13.2), Vector2(30.4, 1.2), Vector2(12.4, 7.2), Vector2(19.6, 7.2)],
	[Vector2(3.0, 1.6), Vector2(29.0, 12.8), Vector2(29.0, 1.2), Vector2(3.0, 13.2),
			Vector2(10.0, 5.6), Vector2(22.0, 8.8), Vector2(20.0, 3.0), Vector2(12.0, 11.4)],
	[Vector2(2.0, 4.8), Vector2(30.0, 4.8), Vector2(2.0, 12.4), Vector2(30.0, 12.4),
			Vector2(12.5, 4.6), Vector2(19.5, 4.6), Vector2(11.0, 12.9), Vector2(21.0, 12.9)],
	# Magnet Lab: four on each side of the middle wall, all out of sight of each other (the squares, the stems and
	# the cross walls hide them); one is in each end room.
	[Vector2(1.4, 5.2), Vector2(5.2, 12.4), Vector2(13.2, 10.6), Vector2(11.0, 1.2),
			Vector2(30.6, 9.2), Vector2(26.8, 2.0), Vector2(18.8, 3.8), Vector2(21.0, 13.2)],
	[Vector2(2.8, 7.2), Vector2(29.2, 7.2), Vector2(2.8, 2.2), Vector2(29.2, 12.2),
			Vector2(2.8, 12.2), Vector2(29.2, 2.2), Vector2(12.0, 13.0), Vector2(20.0, 1.4)],
]
## Where the shrinking zone can end (each ARENA_SIZE / 4, free of blocks, chest, present, belts and trampolines).
const ZONE_SPOTS: Array = [
	[],  # map 0: Config.ZONE_SPOTS
	[Rect2(0.8, 5.8, 8.0, 3.6), Rect2(23.2, 5.0, 8.0, 3.6), Rect2(0.8, 10.4, 8.0, 3.6), Rect2(23.2, 0.4, 8.0, 3.6)],
	# Lava Mats: each is one mat pair, so a wave never takes more than half of it.
	[Rect2(16.0, 0.0, 8.0, 3.6), Rect2(8.0, 10.8, 8.0, 3.6), Rect2(0.0, 7.2, 8.0, 3.6), Rect2(24.0, 3.6, 8.0, 3.6)],
	# Bounce House: the bottom of the two outer strips, and the top across the two upper doors.
	[Rect2(0.25, 10.2, 8.0, 3.6), Rect2(23.75, 10.2, 8.0, 3.6), Rect2(4.75, 0.25, 8.0, 3.6), Rect2(19.25, 0.25, 8.0, 3.6)],
	# Magnet Lab: the four corners of the two end rooms.
	[Rect2(0.4, 0.4, 8.0, 3.6), Rect2(0.4, 10.4, 8.0, 3.6), Rect2(23.6, 0.4, 8.0, 3.6), Rect2(23.6, 10.4, 8.0, 3.6)],
	# Piggy Bank: the four corners, never the pig.
	[Rect2(0.8, 0.4, 8.0, 3.6), Rect2(23.2, 0.4, 8.0, 3.6), Rect2(0.8, 10.4, 8.0, 3.6), Rect2(23.2, 10.4, 8.0, 3.6)],
]
const CRATE_STARTS: Array[Vector2] = [
	Vector2.ZERO, Vector2(6.0, 3.7), Vector2(12.0, 5.4), Vector2(16.0, 12.4), Vector2(17.2, 4.6), Vector2(16.0, 2.4)]
const BOX_POSITIONS: Array[Vector2] = [
	Vector2.ZERO, Vector2(26.0, 13.1), Vector2(20.0, 9.0), Vector2(3.0, 9.0), Vector2(14.8, 9.8), Vector2(16.0, 12.0)]

# --- 1 Assembly Line: conveyor belts ---
const BELT_SPEED := 4.0
const BELT_RUN := 9.0            # seconds the belt runs one way
const BELT_STOP := 1.5           # then it stands still this long and runs the other way
## [rectangle, direction while running forwards, direction while running backwards]. The first match counts. The
## two corner pieces turn the flow, so things ride the whole S instead of falling off at the bend.
const BELTS: Array = [
	[Rect2(3.0, 2.6, 11.9, 2.2), Vector2(1, 0), Vector2(-1, 0)],
	[Rect2(14.9, 2.6, 2.2, 2.2), Vector2(0, 1), Vector2(-1, 0)],
	[Rect2(14.9, 4.8, 2.2, 4.8), Vector2(0, 1), Vector2(0, -1)],
	[Rect2(14.9, 9.6, 2.2, 2.2), Vector2(1, 0), Vector2(0, -1)],
	[Rect2(17.1, 9.6, 11.9, 2.2), Vector2(1, 0), Vector2(-1, 0)],
]

# --- 2 Lava Mats: the floor is lava ---
const LAVA_COLS := 8
const LAVA_ROWS := 4
const LAVA_TILE := Vector2(4.0, 3.6)
const LAVA_CALM := 3.0           # seconds without marked mats
const LAVA_WARN := 1.5           # the marked mats blink
const LAVA_HOT := 2.0            # they burn: standing on one is death
const LAVA_FIRST := 6            # mats of the first wave
const LAVA_STEP := 2             # more per later wave
const LAVA_MAX := 16             # never more: one mat of every pair
enum Lava { CALM, WARN, HOT }

# --- 3 Bounce House: trampolines ---
const PAD_RADIUS := 0.95
const AIR_TIME := 0.75           # seconds in the air
const AIR_HEIGHT := 3.2          # top of the arc (view only)
const STOMP_RADIUS := 1.4        # who is this close to the landing point is squashed
## [trampoline centre, landing spot]. Every strip (left to right: S1..S4) has one pad and one landing spot: the pad of S1
## lands in S2, the pad of S2 in S4, and the mirrored pair: S4 to S3, S3 to S1.
const PADS: Array = [
	[Vector2(7.0, 5.0), Vector2(11.6, 9.6)],
	[Vector2(25.0, 5.0), Vector2(20.4, 9.6)],
	[Vector2(14.2, 9.4), Vector2(27.2, 10.4)],
	[Vector2(17.8, 9.4), Vector2(4.8, 10.4)],
]

# --- 4 Magnet Lab ---
const MAGNETS: Array[Vector2] = [Vector2(11.0, 7.2), Vector2(21.0, 7.2)]
const MAGNET_RADIUS := 6.0
const MAGNET_TURN := 300.0       # degrees per second a flying yo-yo is turned right at the magnet (linear to 0 at the radius)
const MAGNET_DRIFT := 2.5        # m/s a lying yo-yo creeps right at the magnet (same fall-off)
const MAGNET_PERIOD := 8.0       # seconds until the magnets swap
const MAGNET_OFF := 1.0          # the last part of every period both are off

# --- 5 Piggy Bank ---
const PIG_RECT := Rect2(15.0, 6.2, 2.0, 2.0)
const PIG_FILL := 5.0            # seconds per coin
const PIG_MAX := 3
const PIG_TOUCH := 0.08          # a thrown yo-yo this close to the pig counts as a hit


static func valid(id: int) -> int:
	return id if id >= 0 and id < NAMES.size() else 0


static func obstacles(id: int) -> Array:
	return Config.OBSTACLES if id == Id.TRAIN else OBSTACLES[id]


static func spawns(id: int) -> Array:
	return Config.SPAWNS if id == Id.TRAIN else SPAWNS[id]


static func zone_spots(id: int) -> Array:
	return Config.ZONE_SPOTS if id == Id.TRAIN else ZONE_SPOTS[id]


static func crate_start(id: int) -> Vector2:
	return Config.CRATE_START if id == Id.TRAIN else CRATE_STARTS[id]


static func box_pos(id: int) -> Vector2:
	return Config.BOX_POS if id == Id.TRAIN else BOX_POSITIONS[id]


# ---------------------------------------------------------------- belts

## +1 while the belt runs forwards at time `t`, -1 backwards, 0 while it stands still before turning.
static func belt_factor(t: float) -> float:
	var cycle := BELT_RUN + BELT_STOP
	if fposmod(t, cycle) >= BELT_RUN:
		return 0.0
	return 1.0 if int(floor(t / cycle)) % 2 == 0 else -1.0


## Seconds until the belt stops next (0 while it stands).
static func belt_time_left(t: float) -> float:
	return maxf(0.0, BELT_RUN - fposmod(t, BELT_RUN + BELT_STOP))


## How far the belt surface has travelled forwards at time `t` (metres; for the view's moving arrows).
static func belt_travel(t: float) -> float:
	var cycle := BELT_RUN + BELT_STOP
	var k := int(floor(t / cycle))
	var part := minf(fposmod(t, cycle), BELT_RUN)
	# Forward and backward runs cancel in pairs.
	var total := BELT_RUN if k % 2 == 1 else 0.0
	total += part if k % 2 == 0 else -part
	return total * BELT_SPEED


## Index of the belt piece under `pos` (-1: none).
static func belt_at(pos: Vector2) -> int:
	for k in BELTS.size():
		if (BELTS[k][0] as Rect2).has_point(pos):
			return k
	return -1


## Velocity of the belt under `pos` at time `t` (zero off the belt or while it stands).
static func belt_velocity(pos: Vector2, t: float) -> Vector2:
	var f := belt_factor(t)
	if f == 0.0:
		return Vector2.ZERO
	var k := belt_at(pos)
	if k < 0:
		return Vector2.ZERO
	return (BELTS[k][1] if f > 0.0 else BELTS[k][2]) * BELT_SPEED


# ---------------------------------------------------------------- lava

static func lava_stage(t: float) -> int:
	var local := fposmod(t, LAVA_CALM + LAVA_WARN + LAVA_HOT)
	if local < LAVA_CALM:
		return Lava.CALM
	return Lava.WARN if local < LAVA_CALM + LAVA_WARN else Lava.HOT


## Mats of wave number `wave` (0 = the first).
static func lava_count(wave: int) -> int:
	return mini(LAVA_MAX, LAVA_FIRST + LAVA_STEP * maxi(wave, 0))


## The mat under `pos` (row * LAVA_COLS + column), clamped into the arena.
static func lava_cell(pos: Vector2) -> int:
	var c := clampi(int(floor(pos.x / LAVA_TILE.x)), 0, LAVA_COLS - 1)
	var r := clampi(int(floor(pos.y / LAVA_TILE.y)), 0, LAVA_ROWS - 1)
	return r * LAVA_COLS + c


static func lava_rect(cell: int) -> Rect2:
	return Rect2(Vector2(cell % LAVA_COLS, cell / LAVA_COLS) * LAVA_TILE, LAVA_TILE)


# ---------------------------------------------------------------- trampolines

## Index of the trampoline a player centre at `pos` stands on (-1: none).
static func pad_at(pos: Vector2) -> int:
	for k in PADS.size():
		if pos.distance_squared_to(PADS[k][0]) < PAD_RADIUS * PAD_RADIUS:
			return k
	return -1


## Height above the floor of a jump with `air_t` seconds left (a parabola; view only).
static func air_height(air_t: float) -> float:
	var k := clampf(1.0 - air_t / AIR_TIME, 0.0, 1.0)
	return 4.0 * AIR_HEIGHT * k * (1.0 - k)


# ---------------------------------------------------------------- magnets

## +1 while magnet `k` pulls at time `t`, -1 while it pushes, 0 while it is off (the end of every period).
static func magnet_sign(k: int, t: float) -> float:
	if fposmod(t, MAGNET_PERIOD) >= MAGNET_PERIOD - MAGNET_OFF:
		return 0.0
	return 1.0 if (int(floor(t / MAGNET_PERIOD)) + k) % 2 == 0 else -1.0


## Strength of magnet `k` at `pos`: 0 outside its radius, up to +-1 at the magnet (sign as `magnet_sign`).
static func magnet_force(k: int, pos: Vector2, t: float) -> float:
	var d := pos.distance_to(MAGNETS[k])
	if d >= MAGNET_RADIUS:
		return 0.0
	return magnet_sign(k, t) * (1.0 - d / MAGNET_RADIUS)


## The flight direction `dir` of a yo-yo at `pos` after `dt` seconds in the magnets' fields.
static func magnet_bend(pos: Vector2, dir: Vector2, t: float, dt: float) -> Vector2:
	for k in MAGNETS.size():
		var f := magnet_force(k, pos, t)
		if f == 0.0:
			continue
		var to: Vector2 = MAGNETS[k] - pos
		if to.length_squared() < 0.0001:
			continue
		var want := to.normalized() * signf(f)
		var max_turn := deg_to_rad(MAGNET_TURN) * absf(f) * dt
		dir = dir.rotated(clampf(dir.angle_to(want), -max_turn, max_turn))
	return dir


## Creep velocity of a yo-yo lying at `pos`.
static func magnet_drift(pos: Vector2, t: float) -> Vector2:
	var v := Vector2.ZERO
	for k in MAGNETS.size():
		var f := magnet_force(k, pos, t)
		var to: Vector2 = MAGNETS[k] - pos
		if f != 0.0 and to.length_squared() > 0.0001:
			v += to.normalized() * f * MAGNET_DRIFT
	return v
