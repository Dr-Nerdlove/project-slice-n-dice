class_name NavGrid
extends RefCounted
## Walking map of the arena for the bots and the floor-plan tests. Pure and derived: built from a sim's `statics`
## (outer walls and obstacles, grown by the player radius), never part of the snapshot. The chest is not in it (it
## moves; bots push it), and belts, trampolines and lava are floor, not walls. No randomness: a search always gives
## the same path for the same grid.

const CELL := 0.8
const COLS := 40   # ceil(Config.ARENA_SIZE.x / CELL)
const ROWS := 18   # ceil(Config.ARENA_SIZE.y / CELL)
const CLEAR_MARGIN := 0.05   # extra room a walking line keeps from a block

## Grids by map id; an entry is rebuilt when the statics or the radius differ (a test may add blocks to a sim).
static var _cache: Dictionary = {}

var radius := 0.5
var blocked := PackedByteArray()
var _rects: Array[Rect2] = []   # the statics this grid was built from


## The grid for the sim's current map and player radius (cached per map id).
static func for_sim(sim: Sim) -> NavGrid:
	var r := sim.cfg.player_radius
	var g: NavGrid = _cache.get(sim.map_id)
	if g != null and is_equal_approx(g.radius, r) and g._rects == sim.statics:
		return g
	g = NavGrid.new()
	g.build(sim.statics, r)
	_cache[sim.map_id] = g
	return g


func build(statics: Array[Rect2], player_radius: float) -> void:
	radius = player_radius
	_rects = statics.duplicate()
	blocked.resize(COLS * ROWS)
	blocked.fill(0)
	for row in ROWS:
		for col in COLS:
			var c := center(col, row)
			for s in statics:
				if _dist_to_rect(c, s) < radius:
					blocked[row * COLS + col] = 1
					break


static func center(col: int, row: int) -> Vector2:
	return Vector2((col + 0.5) * CELL, (row + 0.5) * CELL)


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(pos.x / CELL)), 0, COLS - 1), clampi(int(floor(pos.y / CELL)), 0, ROWS - 1))


static func _dist_to_rect(q: Vector2, r: Rect2) -> float:
	return q.distance_to(Vector2(clampf(q.x, r.position.x, r.end.x), clampf(q.y, r.position.y, r.end.y)))


func is_free(col: int, row: int) -> bool:
	return col >= 0 and row >= 0 and col < COLS and row < ROWS and blocked[row * COLS + col] == 0


## The free cell nearest to `pos` (the cell itself when free); Vector2i(-1, -1) when the whole grid is blocked.
func nearest_free(pos: Vector2) -> Vector2i:
	var c := cell_of(pos)
	if is_free(c.x, c.y):
		return c
	var best := Vector2i(-1, -1)
	var best_d := INF
	for row in ROWS:
		for col in COLS:
			if blocked[row * COLS + col] != 0:
				continue
			var d := center(col, row).distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = Vector2i(col, row)
	return best


## A point a walker can stand on that is close to `pos`: `pos` itself when its cell is free, else the centre of
## the nearest free cell.
func snap(pos: Vector2) -> Vector2:
	var c := cell_of(pos)
	if is_free(c.x, c.y):
		return pos
	var f := nearest_free(pos)
	return pos if f.x < 0 else center(f.x, f.y)


## True when the segment a-b passes every static at least `radius + margin` away (a walker of that radius fits).
## With `use_radius` >= 0 that radius is used instead (no margin): a yo-yo's line of flight is thinner than a walker.
func line_clear(a: Vector2, b: Vector2, use_radius := -1.0) -> bool:
	var r := (radius if use_radius < 0.0 else use_radius) + (CLEAR_MARGIN if use_radius < 0.0 else 0.0)
	for s in _rects:
		if segment_hits_rect(a, b, s.grow(r)):
			return false
	return true


## Segment against a rectangle (slab test); touching the border counts as a hit.
static func segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p: float = a[axis]
		var dd: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(dd) < 1e-9:
			if p < lo or p > hi:
				return false
		else:
			var ta := (lo - p) / dd
			var tb := (hi - p) / dd
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
	return true


## Waypoints (cell centres, then `to` itself) from `from` to `to`: breadth-first search over 8 neighbours, a
## diagonal step only when both cells beside it are free (no cutting of corners). Empty when there is no way.
## Start and goal are snapped to the nearest free cell. A single entry [to] when start and goal share a cell.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var s := nearest_free(from)
	var g := nearest_free(to)
	var out := PackedVector2Array()
	if s.x < 0 or g.x < 0:
		return out
	var start := s.y * COLS + s.x
	var goal := g.y * COLS + g.x
	if start == goal:
		out.append(to)
		return out
	var prev := PackedInt32Array()
	prev.resize(COLS * ROWS)
	prev.fill(-2)
	prev[start] = -1
	var queue := PackedInt32Array([start])
	var head := 0
	var found := false
	while head < queue.size() and not found:
		var cur := queue[head]
		head += 1
		var cx := cur % COLS
		var cy := cur / COLS
		for k in 8:
			var dx: int = NEIGHBOURS[k].x
			var dy: int = NEIGHBOURS[k].y
			var nx := cx + dx
			var ny := cy + dy
			if not is_free(nx, ny):
				continue
			if dx != 0 and dy != 0 and not (is_free(cx + dx, cy) and is_free(cx, cy + dy)):
				continue
			var n := ny * COLS + nx
			if prev[n] != -2:
				continue
			prev[n] = cur
			if n == goal:
				found = true
				break
			queue.append(n)
	if not found:
		return out
	var cells: Array[int] = []
	var at := goal
	while at != start:
		cells.append(at)
		at = prev[at]
	cells.reverse()
	for c in cells:
		out.append(center(c % COLS, c / COLS))
	out[out.size() - 1] = to
	return out


## True when a walker can get from `a` to `b` (both snapped to the nearest free cell).
func reachable(a: Vector2, b: Vector2) -> bool:
	return not find_path(a, b).is_empty()


## Where to walk from `from` to reach `to`: `to` itself with a clear walking line, otherwise the farthest of the
## first few waypoints that still has a clear line from `from` (the path with its corners cut). `to` itself when
## there is no way at all (the caller then walks straight and pushes against the wall, as before).
func next_point(from: Vector2, to: Vector2) -> Vector2:
	if line_clear(from, to):
		return to
	var path := find_path(from, to)
	if path.is_empty():
		return to
	var best := path[0]
	for i in mini(path.size(), LOOKAHEAD):
		if line_clear(from, path[i]):
			best = path[i]
	return best


const LOOKAHEAD := 12
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
