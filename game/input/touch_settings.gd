class_name TouchSettings
extends RefCounted
## How the touch controls look and where they sit. Per device, saved in its own file (never part of the simulation
## `Config`, never touched by the tuning "Reset"). Applies to Play and Training alike. Pure data and geometry; the
## `InputRouter` draws and reads with it, the Settings page edits it and `TouchLayoutEditor` places the controls.
##
## Stick mode: FLOATING (default) puts a stick where the thumb lands, in its half of the screen; FIXED has the sticks
## at fixed places that can be moved in the layout editor. The dash button is placeable in both modes (one position
## for both). Positions are stored relative to the screen size (0..1) and clamped onto the screen when used, so they
## survive rotation and other resolutions. "Swap sides" mirrors the whole layout (move stick right, aim stick left,
## dash button on the left); turning it on or off mirrors custom positions too.

enum Mode { FLOATING, FIXED }

## Where the settings are kept (tests point this somewhere else).
static var path := "user://touch.json"

const SCALE_MIN := 0.6
const SCALE_MAX := 1.6
const OPACITY_MIN := 0.2
const OPACITY_MAX := 2.0
## The three controls that can be placed.
const KEYS: Array[String] = ["move", "aim", "dash"]
## The design size the default places (Config.STICK_REST_OFFSET_* and DASH_BUTTON_OFFSET) were made for.
const REFERENCE := Vector2(1280.0, 576.0)
## A fixed stick takes a touch this close to its centre, in stick radii.
const GRAB := 1.5

var mode: Mode = Mode.FLOATING
var scale := 1.0          # size of sticks and dash button
var opacity := 1.0        # multiplier on how strongly the controls are drawn
var swap := false         # left-handed: move stick right, aim stick left
var custom: Dictionary = {}   # key -> Vector2 relative (0..1), only for controls the player placed


## Loads the saved settings; a missing or damaged file gives the defaults.
static func load_saved() -> TouchSettings:
	var s := TouchSettings.new()
	if not FileAccess.file_exists(path):
		return s
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return s
	var json := JSON.new()   # parse() reports damage as a return code (parse_string prints an engine error)
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		s.from_dict(json.data)
	return s


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict()))


func to_dict() -> Dictionary:
	var pos := {}
	for k in custom:
		pos[k] = [(custom[k] as Vector2).x, (custom[k] as Vector2).y]
	return {"mode": "fixed" if mode == Mode.FIXED else "floating", "scale": scale, "opacity": opacity,
			"swap": swap, "pos": pos}


## Takes what makes sense and ignores the rest (wrong types are dropped, out-of-range numbers are clamped).
func from_dict(d: Dictionary) -> void:
	mode = Mode.FIXED if d.get("mode") is String and d["mode"] == "fixed" else Mode.FLOATING
	scale = _num(d.get("scale"), 1.0, SCALE_MIN, SCALE_MAX)
	opacity = _num(d.get("opacity"), 1.0, OPACITY_MIN, OPACITY_MAX)
	swap = d.get("swap") is bool and d["swap"]
	custom = {}
	var pos: Variant = d.get("pos")
	if pos is Dictionary:
		for k in KEYS:
			var v: Variant = (pos as Dictionary).get(k)
			if v is Array and (v as Array).size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
				var x := float(v[0])
				var y := float(v[1])
				if is_finite(x) and is_finite(y):
					custom[k] = Vector2(clampf(x, 0.0, 1.0), clampf(y, 0.0, 1.0))


static func _num(v: Variant, fallback: float, lo: float, hi: float) -> float:
	if (v is float or v is int) and is_finite(float(v)):
		return clampf(float(v), lo, hi)
	return fallback


# ---------------------------------------------------------------- geometry

## The default place of a control, relative; mirrored when `swap`.
func default_rel(key: String) -> Vector2:
	var p: Vector2
	match key:
		"move": p = Vector2(Config.STICK_REST_OFFSET_LEFT.x, REFERENCE.y - Config.STICK_REST_OFFSET_LEFT.y)
		"aim": p = REFERENCE - Config.STICK_REST_OFFSET_RIGHT
		_: p = REFERENCE - Config.DASH_BUTTON_OFFSET
	p /= REFERENCE
	return Vector2(1.0 - p.x, p.y) if swap else p


## The relative place of a control: the player's own, or the default.
func rel(key: String) -> Vector2:
	return custom.get(key, default_rel(key))


func stick_radius() -> float:
	return Config.STICK_RADIUS * scale


func knob_radius() -> float:
	return Config.STICK_KNOB_RADIUS * scale


func dash_radius() -> float:
	return Config.DASH_BUTTON_RADIUS * scale


func radius_of(key: String) -> float:
	return dash_radius() if key == "dash" else stick_radius()


## Puts a relative place onto the screen (pixels), keeping a whole control of radius `r` visible.
static func to_screen(rel_pos: Vector2, size: Vector2, r: float) -> Vector2:
	var m := minf(r, minf(size.x, size.y) * 0.5)
	return Vector2(clampf(rel_pos.x * size.x, m, size.x - m), clampf(rel_pos.y * size.y, m, size.y - m))


## The pixel centre of a control on a screen of `size`.
func center(key: String, size: Vector2) -> Vector2:
	return to_screen(rel(key), size, radius_of(key))


## Relative place for a pixel position (what the layout editor stores), clamped onto the screen.
func rel_from_screen(key: String, pos: Vector2, size: Vector2) -> Vector2:
	return to_screen(pos / size, size, radius_of(key)) / size


## Turns left-handed mode on or off; custom places are mirrored with it so the layout stays what the player built.
func set_swap(on: bool) -> void:
	if on == swap:
		return
	swap = on
	for k in custom:
		var v: Vector2 = custom[k]
		custom[k] = Vector2(1.0 - v.x, v.y)


## Forgets every custom place.
func reset_positions() -> void:
	custom = {}


## Stores the places of the editor; a place equal to its default is not kept as custom.
func set_positions(places: Dictionary) -> void:
	custom = {}
	for k in KEYS:
		if places.has(k) and not (places[k] as Vector2).is_equal_approx(default_rel(k)):
			custom[k] = places[k]
