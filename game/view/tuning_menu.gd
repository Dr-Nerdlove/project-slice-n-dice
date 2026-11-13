class_name TuningMenu
extends CanvasLayer
## Overlay with sliders for the main tuning values. German labels, big touch targets.

signal closed

# name, German label, min, max, step, unit
const SLIDERS: Array = [
	["player_speed", "Lauftempo", 2.0, 12.0, 0.1, "m/s"],
	["dash_distance", "Dash-Weite", 1.0, 8.0, 0.1, "m"],
	["dash_charges", "Dash-Ladungen", 1.0, 5.0, 1.0, ""],
	["dash_cooldown", "Dash-Abklingzeit (pro Ladung)", 0.2, 4.0, 0.05, "s"],
	["charge_time", "Aufladezeit", 0.1, 2.0, 0.05, "s"],
	["min_range", "Mindestreichweite", 1.0, 8.0, 0.1, "m"],
	["max_range", "Maximalreichweite", 3.0, 14.0, 0.1, "m"],
	["flight_speed", "Flugtempo", 8.0, 60.0, 1.0, "m/s"],
	["retract_speed", "Rückholtempo", 5.0, 50.0, 1.0, "m/s"],
	["pull_speed", "Zugtempo", 5.0, 50.0, 1.0, "m/s"],
	["tap_threshold", "Tipp-Schwelle", 0.08, 0.6, 0.01, "s"],
	["string_length", "Schnurlänge", 3.0, 16.0, 0.1, "m"],
	["head_radius", "Jojo-Radius", 0.15, 0.8, 0.01, "m"],
	["charge_speed_mult", "Tempo beim Aufladen", 0.1, 1.0, 0.05, "×"],
]
const VARIANT_NAMES: Array[String] = [
	"A – Jojo wird hinterhergezogen",
	"B – Leine (Spieler gebunden)",
	"C – Starr (Jojo läuft mit)",
]
const BOT_NAMES: Array[String] = ["Aus", "Übungspuppen", "Aktiv"]
const SLIDER_HEIGHT := 56.0
const FONT_SIZE := 22

var cfg: Config
var _rows := {}  # name -> {slider, label}
var _variant_opt: OptionButton
var _bot_opt: OptionButton
var _save_timer: Timer
var _grabber: ImageTexture
var _suppress := false


func setup(c: Config) -> void:
	cfg = c
	layer = 20
	visible = false
	_grabber = _make_grabber()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "Einstellungen"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var reset := _button("Zurücksetzen")
	reset.pressed.connect(_on_reset)
	top.add_child(reset)
	var close := _button("Schließen")
	close.pressed.connect(close_menu)
	top.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.scroll_deadzone = 10
	scroll.get_v_scroll_bar().custom_minimum_size.x = 26.0  # wide, always visible: also a scroll handle for thumbs
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS

	grid.add_child(_selector("Verhalten des Jojos, wenn er draußen liegt", VARIANT_NAMES, "out_variant"))
	grid.add_child(_selector("Übungsgegner", BOT_NAMES, "bot_mode"))
	for def: Array in SLIDERS:
		grid.add_child(_slider_row(def))
	# Bottom padding so the last row can be scrolled clear of the screen edge.
	for _i in 2:
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 80)
		pad.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(pad)

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(func() -> void: TuningStore.save(cfg))
	add_child(_save_timer)
	refresh()


func _make_grabber() -> ImageTexture:
	var n := 44
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(c.x - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.4, 0.8, 1.0, a))
	return ImageTexture.create_from_image(img)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 56)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	return b


func _selector(caption: String, names: Array[String], key: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = caption
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	box.add_child(l)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(0, SLIDER_HEIGHT)
	opt.add_theme_font_size_override("font_size", FONT_SIZE)
	opt.get_popup().add_theme_font_size_override("font_size", FONT_SIZE)
	opt.get_popup().add_theme_constant_override("v_separation", 18)
	for n in names:
		opt.add_item(n)
	opt.item_selected.connect(func(i: int) -> void:
		if _suppress:
			return
		cfg.set(key, i)
		_queue_save())
	box.add_child(opt)
	if key == "out_variant":
		_variant_opt = opt
	else:
		_bot_opt = opt
	return box


func _slider_row(def: Array) -> Control:
	var key: String = def[0]
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = def[2]
	s.max_value = def[3]
	s.step = def[4]
	s.custom_minimum_size = Vector2(0, SLIDER_HEIGHT)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_theme_icon_override("grabber", _grabber)
	s.add_theme_icon_override("grabber_highlight", _grabber)
	s.add_theme_icon_override("grabber_disabled", _grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.3, 0.33, 0.4)
	track.set_content_margin_all(6.0)
	track.set_corner_radius_all(6)
	s.add_theme_stylebox_override("slider", track)
	s.value_changed.connect(func(v: float) -> void:
		if _suppress:
			return
		cfg.set(key, int(roundf(v)) if typeof(Config.DEFAULTS[key]) == TYPE_INT else v)
		_update_label(key)
		_queue_save())
	box.add_child(s)
	_rows[key] = {"slider": s, "label": l, "def": def}
	return box


func _update_label(key: String) -> void:
	var row: Dictionary = _rows[key]
	var def: Array = row["def"]
	var decimals := 2 if (def[4] as float) < 0.1 else (1 if (def[4] as float) < 1.0 else 0)
	var v: float = cfg.get(key)
	(row["label"] as Label).text = ("%s: %s %s" % [def[1], String.num(v, decimals), def[5]]).strip_edges()


func refresh() -> void:
	_suppress = true
	for key: String in _rows:
		(_rows[key]["slider"] as HSlider).value = cfg.get(key)
		_update_label(key)
	_variant_opt.select(cfg.out_variant)
	_bot_opt.select(cfg.bot_mode)
	_suppress = false


func _queue_save() -> void:
	_save_timer.start()


func _on_reset() -> void:
	cfg.reset()
	refresh()
	TuningStore.save(cfg)


func open_menu() -> void:
	refresh()
	visible = true


func close_menu() -> void:
	visible = false
	TuningStore.save(cfg)
	closed.emit()
