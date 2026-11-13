class_name InputRouter
extends Control
## Turns touch / gamepad / keyboard+mouse into a SimInput for the local player and draws the touch UI.

signal menu_requested

var blocked := false:                      # true while the tuning menu is open
	set(v):
		blocked = v
		if v:
			_release_all()
var exclude_rects: Array[Rect2] = []       # screen areas owned by other UI (gear button)
var mouse_to_world: Callable               # (Vector2 screen) -> Vector2 sim position, or Vector2.INF
var dash_ready_ratio := 1.0                # progress of the next dash charge, 0..1 (for drawing)
var dash_charges := 1                      # dashes available now (for drawing)
var dash_charges_max := 1

var _move_idx := -1
var _move_c := Vector2.ZERO
var _move_p := Vector2.ZERO
var _aim_idx := -1
var _aim_c := Vector2.ZERO
var _aim_p := Vector2.ZERO
var _dash_idx := -1
var _held_latch := false
var _dash_latch := false
var _lmb := false
var _mouse_pos := Vector2.ZERO
var _pad_held := false
var _pad_last_aim := Vector2.ZERO
var _pad_dash_prev := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _screen_size() -> Vector2:
	return get_viewport_rect().size


func _dash_center() -> Vector2:
	return _screen_size() - Config.DASH_BUTTON_OFFSET


func _move_rest() -> Vector2:
	return Vector2(Config.STICK_REST_OFFSET_LEFT.x, _screen_size().y - Config.STICK_REST_OFFSET_LEFT.y)


func _aim_rest() -> Vector2:
	return _screen_size() - Config.STICK_REST_OFFSET_RIGHT


func _notification(what: int) -> void:
	# A finger can vanish without an "up" event (app switch, system gesture): never keep a stale touch.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			menu_requested.emit()
		return
	if blocked:
		_release_all()
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_move(d.index, d.position)
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		# Mouse events synthesised from touches are ignored; touches are handled directly.
		if m.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if m.button_index == MOUSE_BUTTON_LEFT:
			if m.pressed:
				for r in exclude_rects:
					if r.has_point(m.position):
						return
				_held_latch = true
			_lmb = m.pressed
		_mouse_pos = m.position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.device != InputEvent.DEVICE_ID_EMULATION:
			_mouse_pos = mm.position


func _release_all() -> void:
	_move_idx = -1
	_aim_idx = -1
	_dash_idx = -1
	_lmb = false


func _touch_down(idx: int, pos: Vector2) -> void:
	# A "down" for an index we still hold means its "up" was lost: drop the stale touch first.
	_touch_up(idx)
	for r in exclude_rects:
		if r.has_point(pos):
			return
	if pos.distance_to(_dash_center()) <= Config.DASH_BUTTON_RADIUS + 4.0:
		if _dash_idx == -1:
			_dash_idx = idx
			_dash_latch = true
		return
	var w := _screen_size().x
	var to_move := pos.x < w * 0.5
	# Near the middle a thumb may land on the "wrong" side: use the other stick if this one is busy.
	if to_move and _move_idx != -1 and _aim_idx == -1 and pos.x > w * 0.35:
		to_move = false
	elif not to_move and _aim_idx != -1 and _move_idx == -1 and pos.x < w * 0.65:
		to_move = true
	if to_move:
		if _move_idx == -1:
			_move_idx = idx
			_move_c = pos
			_move_p = pos
	elif _aim_idx == -1:
		_aim_idx = idx
		_aim_c = pos
		_aim_p = pos
		_held_latch = true


func _touch_up(idx: int) -> void:
	if idx == _move_idx:
		_move_idx = -1
	if idx == _aim_idx:
		_aim_idx = -1
	if idx == _dash_idx:
		_dash_idx = -1


func _touch_move(idx: int, pos: Vector2) -> void:
	if idx == _move_idx:
		_move_p = pos
		_move_c = _follow(_move_c, pos)
	elif idx == _aim_idx:
		_aim_p = pos
		_aim_c = _follow(_aim_c, pos)


## Floating stick: the base follows the finger when it is dragged beyond the radius.
func _follow(c: Vector2, p: Vector2) -> Vector2:
	var off := p - c
	if off.length() > Config.STICK_RADIUS:
		return p - off.normalized() * Config.STICK_RADIUS
	return c


func _stick(c: Vector2, p: Vector2) -> Vector2:
	return ((p - c) / Config.STICK_RADIUS).limit_length(1.0)


## Builds the input for one sim tick. Edge events (press, dash) are latched until consumed here.
func poll(player_pos: Vector2) -> SimInput:
	var out := SimInput.new()
	if blocked:
		return out
	# --- touch ---
	var touch_move := Vector2.ZERO
	var touch_aim := Vector2.ZERO
	if _move_idx != -1:
		touch_move = _stick(_move_c, _move_p)
	if _aim_idx != -1:
		touch_aim = _stick(_aim_c, _aim_p)
	var held := _aim_idx != -1
	var aim := touch_aim

	# --- gamepad ---
	var pad_move := Vector2.ZERO
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var d: int = pads[0]
		pad_move = Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if pad_move.length() < 0.2:
			pad_move = Vector2.ZERO
		var rs := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		var rl := rs.length()
		var stick_held := rl > (0.25 if _pad_held else 0.5)
		if rl > 0.2:
			_pad_last_aim = rs.normalized()
		var shoulder := Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) \
				or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		var pad_now := stick_held or shoulder
		if pad_now and not _pad_held:
			_held_latch = true
		_pad_held = pad_now
		if pad_now and not held:
			held = true
			aim = rs.limit_length(1.0) if rl > 0.2 else _pad_last_aim
		var dash_now := Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) \
				or Input.is_joy_button_pressed(d, JOY_BUTTON_A)
		if dash_now and not _pad_dash_prev:
			_dash_latch = true
		_pad_dash_prev = dash_now
	else:
		_pad_held = false

	# --- keyboard + mouse ---
	var key_move := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if Input.is_physical_key_pressed(KEY_SPACE):
		if not _key_dash_prev:
			_dash_latch = true
		_key_dash_prev = true
	else:
		_key_dash_prev = false
	if _lmb and not held and mouse_to_world.is_valid():
		var w: Vector2 = mouse_to_world.call(_mouse_pos)
		if w != Vector2.INF:
			var dv := w - player_pos
			held = true
			aim = dv.normalized() if dv.length() > 0.01 else Vector2.ZERO

	out.move = touch_move
	if out.move == Vector2.ZERO:
		out.move = pad_move
	if out.move == Vector2.ZERO:
		out.move = key_move.limit_length(1.0)
	out.aim = aim
	out.aim_held = held or _held_latch
	out.dash = _dash_latch
	_held_latch = false
	_dash_latch = false
	return out


var _key_dash_prev := false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if blocked:
		return
	var white := Color(1, 1, 1, 0.22)
	var knob := Color(1, 1, 1, 0.45)
	# Sticks are always visible: at rest in the lower corners, floating to the finger while touched.
	if _move_idx != -1:
		_draw_stick(_move_c, _move_p, white, knob)
	else:
		var rest := _move_rest()
		_draw_stick(rest, rest, Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.28))
	if _aim_idx != -1:
		_draw_stick(_aim_c, _aim_p, Color(1, 0.8, 0.4, 0.25), Color(1, 0.8, 0.4, 0.5))
	else:
		var rest := _aim_rest()
		_draw_stick(rest, rest, Color(1, 0.8, 0.4, 0.14), Color(1, 0.8, 0.4, 0.3))
	var c := _dash_center()
	var pressed := _dash_idx != -1
	var usable := dash_charges > 0
	var a := 0.18 + (0.25 if usable else 0.0) + (0.2 if pressed else 0.0)
	draw_circle(c, Config.DASH_BUTTON_RADIUS, Color(0.3, 0.7, 1.0, a))
	draw_arc(c, Config.DASH_BUTTON_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
	if dash_charges < dash_charges_max:  # progress of the next charge
		draw_arc(c, Config.DASH_BUTTON_RADIUS - 5.0, -PI * 0.5, -PI * 0.5 + TAU * dash_ready_ratio, 40,
				Color(1, 1, 1, 0.9), 4.0)
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-40.0, 2.0), "Dash", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 22, Color(1, 1, 1, 0.9))
	# One pip per stored charge, filled while available.
	var pr := Config.DASH_PIP_RADIUS
	var step := pr * 2.0 + 5.0
	var x0 := c.x - step * (dash_charges_max - 1) * 0.5
	for i in dash_charges_max:
		var pc := Vector2(x0 + step * i, c.y + 20.0)
		if i < dash_charges:
			draw_circle(pc, pr, Color(1, 1, 1, 0.95))
		else:
			draw_arc(pc, pr - 1.0, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 2.0)


func _draw_stick(c: Vector2, p: Vector2, base_col: Color, knob_col: Color) -> void:
	draw_circle(c, Config.STICK_RADIUS, base_col)
	draw_arc(c, Config.STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.4), 2.0)
	var off := (p - c).limit_length(Config.STICK_RADIUS)
	draw_circle(c + off, Config.STICK_KNOB_RADIUS, knob_col)
