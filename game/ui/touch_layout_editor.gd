class_name TouchLayoutEditor
extends Control
## Full-screen editor for the touch control places: drag the move stick, the aim stick and the dash button, then Save,
## Reset to default or Cancel. Shown over the main menu from the Settings page. In Floating mode the sticks follow the
## thumb anyway, so only the dash button can be moved. Works on a copy; only Save writes to the settings and the file.

signal closed(saved: bool)

const TITLES := {"move": "Move", "aim": "Aim", "dash": "Dash"}

var save_btn: Button
var reset_btn: Button
var cancel_btn: Button

var _s: TouchSettings
var _places: Dictionary = {}    # key -> relative place of the working copy
var _drag := ""
var _grab_offset := Vector2.ZERO


func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y = 16.0
	add_child(bar)
	save_btn = UiKit.button("Save", "main")
	reset_btn = UiKit.button("Reset to default", "paper")
	cancel_btn = UiKit.button("Cancel", "quiet")
	for b in [save_btn, reset_btn, cancel_btn]:
		(b as Button).custom_minimum_size.x = 190.0
		bar.add_child(b)
	save_btn.pressed.connect(save)
	reset_btn.pressed.connect(reset_to_default)
	cancel_btn.pressed.connect(cancel)


func _screen() -> Vector2:
	return get_viewport_rect().size


## The controls that can be moved in the current mode.
func editable() -> Array[String]:
	if _s != null and _s.mode == TouchSettings.Mode.FIXED:
		return ["move", "aim", "dash"]
	return ["dash"]


func open(settings: TouchSettings) -> void:
	_s = settings
	_places = {}
	for k in TouchSettings.KEYS:
		_places[k] = settings.rel(k)
	_drag = ""
	visible = true
	queue_redraw()


## Pixel centre of a control in the working copy.
func center_of(key: String) -> Vector2:
	return TouchSettings.to_screen(_places[key], _screen(), _s.radius_of(key))


func place_of(key: String) -> Vector2:
	return _places[key]


func begin_drag(pos: Vector2) -> void:
	_drag = ""
	var best := INF
	for k in editable():
		var d := pos.distance_to(center_of(k))
		if d <= _s.radius_of(k) * 1.2 and d < best:
			best = d
			_drag = k
			_grab_offset = center_of(k) - pos


func drag_to(pos: Vector2) -> void:
	if _drag == "":
		return
	_places[_drag] = _s.rel_from_screen(_drag, pos + _grab_offset, _screen())
	queue_redraw()


func end_drag() -> void:
	_drag = ""


func reset_to_default() -> void:
	for k in TouchSettings.KEYS:
		_places[k] = _s.default_rel(k)
	queue_redraw()


func save() -> void:
	_s.set_positions(_places)
	_s.save()
	_close(true)


func cancel() -> void:
	_close(false)


func _close(saved: bool) -> void:
	visible = false
	_drag = ""
	closed.emit(saved)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			begin_drag((event as InputEventMouseButton).position)
		else:
			end_drag()
	elif event is InputEventMouseMotion and _drag != "":
		drag_to((event as InputEventMouseMotion).position)


func _draw() -> void:
	if _s == null:
		return
	draw_rect(Rect2(Vector2.ZERO, _screen()), Color(0.05, 0.06, 0.09, 0.82))
	var font := ThemeDB.fallback_font
	for k in TouchSettings.KEYS:
		var movable: bool = k in editable()
		var c := center_of(k)
		var r := _s.radius_of(k)
		var col := Color(0.3, 0.7, 1.0) if k == "dash" else (Color(1, 0.8, 0.4) if k == "aim" else Color.WHITE)
		var a := 0.55 if movable else 0.18
		draw_circle(c, r, Color(col.r, col.g, col.b, a * 0.5))
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, a + 0.2), 3.0 if k == _drag else 2.0)
		draw_string(font, c + Vector2(-60.0, 8.0), TITLES[k], HORIZONTAL_ALIGNMENT_CENTER, 120.0, 24,
				Color(1, 1, 1, 0.9 if movable else 0.4))
	var hint := "Drag the controls where you want them." if _s.mode == TouchSettings.Mode.FIXED \
			else "Floating sticks follow your thumb. Drag the Dash button where you want it."
	draw_string(font, Vector2(0.0, 112.0), hint, HORIZONTAL_ALIGNMENT_CENTER, _screen().x, 22, Color(1, 1, 1, 0.8))
