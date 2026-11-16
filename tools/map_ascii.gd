extends SceneTree
## Prints a map as text, one character per 0.8 x 0.8 m cell (40 x 18 for the 32 x 14.4 m arena), so a floor plan
## can be reviewed without a picture:
##   godot --headless --path game -s ../tools/map_ascii.gd -- [id]      (no id: every map)
## Legend (the first that applies wins):
##   1-8 spawn point   C chest start   P present   # obstacle   M magnet   G pig
##   > < ^ v belt (direction while it runs forwards)   o trampoline   x its landing spot   t train track
##   z zone area (one of the four final spots)   . floor
## Later steps add rugs and crushers here.

const CELL := 0.8


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var id := int(args[0])
		if not args[0].is_valid_int() or id < 0 or id >= MapDef.NAMES.size():
			printerr("map id must be 0..%d" % (MapDef.NAMES.size() - 1))
			quit(2)
			return
		print(render(id))
	else:
		for id in MapDef.NAMES.size():
			print(render(id))
	quit()


static func render(id: int) -> String:
	var cols := int(ceil(Config.ARENA_SIZE.x / CELL))
	var rows := int(ceil(Config.ARENA_SIZE.y / CELL))
	var grid: Array = []
	for r in rows:
		var line: Array = []
		line.resize(cols)
		line.fill(".")
		grid.append(line)
	# lowest priority first, later layers overwrite
	for z: Rect2 in MapDef.zone_spots(id):
		_fill(grid, z, "z")
	if id == MapDef.Id.TRAIN:
		var n := int(TrainTrack.LENGTH / 0.2)
		for k in n:
			_put(grid, TrainTrack.point(TrainTrack.LENGTH * k / n), "t")
	if id == MapDef.Id.BELTS:
		for b: Array in MapDef.BELTS:
			var d: Vector2 = b[1]
			_fill(grid, b[0], ">" if d.x > 0.5 else "<" if d.x < -0.5 else "v" if d.y > 0.5 else "^")
	if id == MapDef.Id.BOUNCE:
		for pad: Array in MapDef.PADS:
			_put_disc(grid, pad[0], MapDef.PAD_RADIUS, "o")
			_put(grid, pad[1], "x")
	var obs: Array = MapDef.obstacles(id)
	var special: int = MapDef.SPECIAL_OBSTACLES[id]
	for k in obs.size():
		var ch := "#"
		if k < special:
			ch = "G" if id == MapDef.Id.PIGGY else "M"
		_fill(grid, obs[k], ch)
	var crate := MapDef.crate_start(id)
	_fill(grid, Rect2(crate - Vector2(Config.CRATE_HALF, Config.CRATE_HALF), Vector2(Config.CRATE_HALF, Config.CRATE_HALF) * 2.0), "C")
	var box := MapDef.box_pos(id)
	_fill(grid, Rect2(box - Vector2(Config.BOX_HALF, Config.BOX_HALF), Vector2(Config.BOX_HALF, Config.BOX_HALF) * 2.0), "P")
	var spawns: Array = MapDef.spawns(id)
	for k in spawns.size():
		_put(grid, spawns[k], str(k + 1))
	var out := "Map %d: %s  (%d x %d cells of %.1f m, %d obstacles)\n" % [id, MapDef.NAMES[id], cols, rows, CELL, obs.size()]
	for line: Array in grid:
		out += "".join(PackedStringArray(line)) + "\n"
	return out


static func _put(grid: Array, pos: Vector2, ch: String) -> void:
	var c := int(floor(pos.x / CELL))
	var r := int(floor(pos.y / CELL))
	if r >= 0 and r < grid.size() and c >= 0 and c < (grid[0] as Array).size():
		grid[r][c] = ch


## Cells whose centre lies inside the rectangle (every rectangle covers at least the cell of its centre).
static func _fill(grid: Array, rect: Rect2, ch: String) -> void:
	var any := false
	for r in grid.size():
		for c in (grid[r] as Array).size():
			if rect.has_point(Vector2((c + 0.5) * CELL, (r + 0.5) * CELL)):
				grid[r][c] = ch
				any = true
	if not any:
		_put(grid, rect.get_center(), ch)


static func _put_disc(grid: Array, centre: Vector2, radius: float, ch: String) -> void:
	for r in grid.size():
		for c in (grid[r] as Array).size():
			if Vector2((c + 0.5) * CELL, (r + 0.5) * CELL).distance_to(centre) <= radius:
				grid[r][c] = ch
