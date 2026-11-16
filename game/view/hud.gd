class_name Hud
extends CanvasLayer
## Training: scoreboard, modifier chips, net text and the gear button. Play (`play_mode`): only a small quiet pause
## button (no UI during a round). English on-screen text.

signal gear_pressed

var gear_btn: Button
var _labels: Array[Label] = []
var _chip_box: HBoxContainer
var _chip_key := ""
var _sim: Sim
var _local := 0
var _net_label: Label
## Network figures shown while online (empty: hidden).
var net_text := ""
## True while playing online: the other players are people, not bots.
var online := false
var _score_box: HBoxContainer
## True in a real game: only the pause button is shown (drawn as two bars instead of the gear).
var play_mode := false:
	set(v):
		play_mode = v
		if _score_box != null:
			_score_box.visible = not v
			_chip_box.visible = not v
			_net_label.visible = false
			gear_btn.queue_redraw()


func setup(s: Sim) -> void:
	_sim = s
	layer = 5
	var box := HBoxContainer.new()
	# Top left, so it can never run into the gear button in the top right corner.
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(16.0, 8.0)
	box.add_theme_constant_override("separation", 20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_score_box = box
	var legend := Label.new()
	legend.text = "Kills : Deaths"
	legend.add_theme_font_size_override("font_size", 16)
	legend.modulate = Color(1, 1, 1, 0.6)
	box.add_child(legend)
	for i in s.players.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", ArenaView.PLAYER_COLORS[i])
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		box.add_child(l)
		_labels.append(l)

	# Chips with the human player's active modifiers, e.g. "Shards II".
	_chip_box = HBoxContainer.new()
	_chip_box.position = Vector2(16.0, 44.0)
	_chip_box.add_theme_constant_override("separation", 8)
	_chip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chip_box)

	_net_label = Label.new()
	_net_label.position = Vector2(16.0, 84.0)
	_net_label.add_theme_font_size_override("font_size", 16)
	_net_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_net_label.add_theme_constant_override("outline_size", 5)
	_net_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_label.visible = false
	add_child(_net_label)

	gear_btn = Button.new()
	gear_btn.flat = true
	gear_btn.custom_minimum_size = Vector2(Config.GEAR_SIZE, Config.GEAR_SIZE)
	gear_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gear_btn.position = Vector2(-Config.GEAR_SIZE - 12.0, 12.0)
	gear_btn.size = Vector2(Config.GEAR_SIZE, Config.GEAR_SIZE)
	gear_btn.focus_mode = Control.FOCUS_NONE
	gear_btn.draw.connect(_draw_gear)
	gear_btn.pressed.connect(func() -> void: gear_pressed.emit())
	add_child(gear_btn)


## Shows another sim (the predicted one while online) with `local_slot` as "You".
func use_sim(s: Sim, local_slot: int) -> void:
	_sim = s
	_local = local_slot
	_chip_key = ""


func _draw_gear() -> void:
	var c := gear_btn.size * 0.5
	if play_mode:
		# Quiet pause button: a translucent disc with two bars.
		gear_btn.draw_circle(c, Config.GEAR_SIZE * 0.5, Color(1, 1, 1, 0.1))
		for dx in [-7.0, 7.0]:
			gear_btn.draw_line(c + Vector2(dx, -10.0), c + Vector2(dx, 10.0), Color(1, 1, 1, 0.6), 5.0)
		return
	var col := Color(1, 1, 1, 0.75)
	gear_btn.draw_circle(c, Config.GEAR_SIZE * 0.5, Color(0, 0, 0, 0.35))
	gear_btn.draw_arc(c, 12.0, 0.0, TAU, 24, col, 4.0)
	for k in 8:
		var dir := Vector2.from_angle(TAU * k / 8.0)
		gear_btn.draw_line(c + dir * 12.0, c + dir * 19.0, col, 5.0)


## Screen areas of the HUD that must not steer the player.
func blocked_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [gear_rect()]
	return rects


func gear_rect() -> Rect2:
	return gear_btn.get_global_rect()


func refresh() -> void:
	if play_mode:
		return
	for i in _labels.size():
		var p := _sim.players[i]
		_labels[i].visible = p.enabled
		_labels[i].add_theme_color_override("font_color", ArenaView.color_of(p))
		var who := "You" if i == _local else ("Player %d" % (i + 1) if online else "Bot %d" % i)
		_labels[i].text = "%s %d : %d" % [who, p.kills, p.deaths]

	_net_label.visible = net_text != ""
	_net_label.text = net_text
	_refresh_chips()


func _refresh_chips() -> void:
	var mods := _sim.players[_local].mods
	var key := ""
	for id in Mods.ORDER:
		key += "%s%d," % [id, mods.get(id, 0)]
	if key == _chip_key:
		return
	_chip_key = key
	for c in _chip_box.get_children():
		c.queue_free()
	for id in Mods.ORDER:
		var level: int = mods.get(id, 0)
		if level <= 0:
			continue
		var l := Label.new()
		l.text = "%s %s" % [Mods.mod_name(id), Mods.ROMAN[level]]
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.12, 0.18, 0.75).lerp(Color(0.9, 0.7, 0.2, 0.75), (level - 1) / 2.0 * 0.6)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		sb.content_margin_top = 2.0
		sb.content_margin_bottom = 2.0
		l.add_theme_stylebox_override("normal", sb)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chip_box.add_child(l)
