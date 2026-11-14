class_name TuningMenu
extends CanvasLayer
## Overlay with two pages: "Werte" (sliders for the main tuning values) and "Modifikatoren"
## (sandbox: modifier levels for the player and the bots). German labels, big touch targets.

signal closed
signal connect_requested(address: String)
signal disconnect_requested
signal lag_changed(delay_ms: float, loss_pct: float)
signal smoothing_changed(on: bool)
signal update_requested

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
	["train_speed", "Eisenbahn-Tempo", 0.0, 10.0, 0.1, "m/s"],
]
const VARIANT_NAMES: Array[String] = [
	"A – Jojo wird hinterhergezogen",
	"B – Leine (Spieler gebunden)",
	"C – Starr (Jojo läuft mit)",
]
const BOT_NAMES: Array[String] = ["Aus", "Übungspuppen", "Aktiv"]
const SLIDER_HEIGHT := 56.0
const FONT_SIZE := 22
const LEVEL_BUTTON_SIZE := Vector2(76, 56)
const DESC_FONT_SIZE := 18

var cfg: Config
var _rows := {}  # name -> {slider, label}
var _variant_opt: OptionButton
var _bot_opt: OptionButton
var _save_timer: Timer
var _grabber: ImageTexture
var _suppress := false
var _values_page: ScrollContainer
var _mods_page: ScrollContainer
var _tab_values: Button
var _tab_mods: Button
var _tab_online: Button
var _tab_figure: Button
var _figure_page: ScrollContainer
var _figure_buttons: Array[Button] = []
var _figure_preview: FigurePreview   # live 3D picture of the chosen figure
var _online_page: ScrollContainer
var _address_edit: LineEdit
var _connect_btn: Button
var _disconnect_btn: Button
var _online_status: Label
var _smooth_check: CheckButton
var _lag_slider: HSlider
var _loss_slider: HSlider
var _lag_label: Label
var _loss_label: Label
var _level_buttons := {}   # "you:<id>" / "bots:<id>" -> Array[Button]
var _desc_labels := {}     # id -> Label
var _syn_label: Label
var _export_panel: Control
var _export_status: Label
var _export_text: TextEdit
var _version_label: Label
var _update_btn: Button


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
	top.add_child(title)
	_version_label = Label.new()
	_version_label.text = "Version %s" % UpdateCheck.running_version()
	_version_label.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	_version_label.modulate = Color(1, 1, 1, 0.7)
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_label.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(_version_label)
	_update_btn = _button("Herunterladen")
	_update_btn.visible = false
	_update_btn.pressed.connect(func() -> void: update_requested.emit())
	top.add_child(_update_btn)
	var reset := _button("Zurücksetzen")
	reset.pressed.connect(_on_reset)
	top.add_child(reset)
	var export_btn := _button("Werte kopieren")
	export_btn.pressed.connect(_on_export)
	top.add_child(export_btn)
	var close := _button("Schließen")
	close.pressed.connect(close_menu)
	top.add_child(close)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	_tab_values = _button("Werte")
	_tab_values.toggle_mode = true
	_tab_values.pressed.connect(func() -> void: _show_page(0))
	tabs.add_child(_tab_values)
	_tab_mods = _button("Modifikatoren")
	_tab_mods.toggle_mode = true
	_tab_mods.custom_minimum_size = Vector2(260, 56)
	_tab_mods.pressed.connect(func() -> void: _show_page(1))
	tabs.add_child(_tab_mods)
	_tab_online = _button("Online")
	_tab_online.toggle_mode = true
	_tab_online.pressed.connect(func() -> void: _show_page(2))
	tabs.add_child(_tab_online)
	_tab_figure = _button("Figur")
	_tab_figure.toggle_mode = true
	_tab_figure.pressed.connect(func() -> void: _show_page(3))
	tabs.add_child(_tab_figure)

	var scroll := _make_scroll()
	_values_page = scroll
	root.add_child(scroll)
	_mods_page = _make_scroll()
	root.add_child(_mods_page)
	_build_mods_page(_mods_page)
	_online_page = _make_scroll()
	root.add_child(_online_page)
	_build_online_page(_online_page)
	_figure_page = _make_scroll()
	root.add_child(_figure_page)
	_build_figure_page(_figure_page)
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

	_build_export_panel()
	_show_page(0)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(func() -> void: TuningStore.save(cfg))
	add_child(_save_timer)
	refresh()


func _make_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.scroll_deadzone = 10
	scroll.get_v_scroll_bar().custom_minimum_size.x = 26.0  # wide, always visible: also a scroll handle for thumbs
	return scroll


## 0 = values, 1 = modifiers, 2 = online, 3 = figure.
func _show_page(page: int) -> void:
	_values_page.visible = page == 0
	_mods_page.visible = page == 1
	_online_page.visible = page == 2
	_figure_page.visible = page == 3
	_tab_values.set_pressed_no_signal(page == 0)
	_tab_mods.set_pressed_no_signal(page == 1)
	_tab_online.set_pressed_no_signal(page == 2)
	_tab_figure.set_pressed_no_signal(page == 3)


## The choice of the player's figure: a preview area on top, then one toggle button per figure.
func _build_figure_page(scroll: ScrollContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)
	_figure_preview = FigurePreview.new()
	_figure_preview.custom_minimum_size = Vector2(0, 200)
	_figure_preview.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_figure_preview)
	var cap := Label.new()
	cap.text = "Deine Figur"
	cap.add_theme_font_size_override("font_size", FONT_SIZE)
	cap.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(cap)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for i in Config.SKIN_COUNT:
		var b := _button(CharacterRig.NAMES[i])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _choose_figure(i))
		grid.add_child(b)
		_figure_buttons.append(b)
	_mark_figure()


func _choose_figure(i: int) -> void:
	cfg.character = i
	_mark_figure()
	_queue_save()


func _mark_figure() -> void:
	for i in _figure_buttons.size():
		_figure_buttons[i].set_pressed_no_signal(i == cfg.character)
	if _figure_preview.rig.kind != cfg.character:
		_figure_preview.show_figure(cfg.character, ArenaView.PLAYER_COLORS[0])


## Connection to a game server plus the artificial lag tool. The lag applies to what this phone sends and
## receives, so it works against any server.
func _build_online_page(scroll: ScrollContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)
	var info := Label.new()
	info.text = "Online spielst du mit den Werten des Servers. Deine Modifikatoren („Du“ auf der Seite Modifikatoren) werden übernommen."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	info.modulate = Color(1, 1, 1, 0.85)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(info)
	var cap := Label.new()
	cap.text = "Server-Adresse (Name oder IP, optional mit :Port)"
	cap.add_theme_font_size_override("font_size", FONT_SIZE)
	cap.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(cap)
	_address_edit = LineEdit.new()
	_address_edit.custom_minimum_size = Vector2(0, SLIDER_HEIGHT)
	_address_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_address_edit.max_length = 255
	_address_edit.text = NetStore.load_address()
	col.add_child(_address_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_connect_btn = _button("Verbinden")
	_connect_btn.pressed.connect(func() -> void: connect_requested.emit(_address_edit.text))
	row.add_child(_connect_btn)
	_disconnect_btn = _button("Trennen")
	_disconnect_btn.pressed.connect(func() -> void: disconnect_requested.emit())
	_disconnect_btn.disabled = true
	row.add_child(_disconnect_btn)
	_online_status = Label.new()
	_online_status.text = "Nicht verbunden"
	_online_status.add_theme_font_size_override("font_size", 26)
	_online_status.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_online_status)
	_smooth_check = CheckButton.new()
	_smooth_check.text = "Gegner glätten"
	_smooth_check.button_pressed = true
	_smooth_check.custom_minimum_size = Vector2(0, SLIDER_HEIGHT)
	_smooth_check.add_theme_font_size_override("font_size", FONT_SIZE)
	_smooth_check.toggled.connect(func(on: bool) -> void: smoothing_changed.emit(on))
	col.add_child(_smooth_check)
	var smooth_info := Label.new()
	smooth_info.text = "An: die anderen Spieler werden flüssig, aber etwas in der Vergangenheit gezeigt. Aus: rohe Vorhersage (ruckelt)."
	smooth_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	smooth_info.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	smooth_info.modulate = Color(1, 1, 1, 0.85)
	smooth_info.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(smooth_info)
	var lag_title := Label.new()
	lag_title.text = "Netz-Test"
	lag_title.add_theme_font_size_override("font_size", 26)
	lag_title.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(lag_title)
	_lag_label = Label.new()
	_lag_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_lag_label.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_lag_label)
	_lag_slider = _plain_slider(0.0, 300.0, 5.0)
	_lag_slider.value_changed.connect(func(_v: float) -> void: _on_lag_changed())
	col.add_child(_lag_slider)
	_loss_label = Label.new()
	_loss_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_loss_label.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_loss_label)
	_loss_slider = _plain_slider(0.0, 20.0, 1.0)
	_loss_slider.value_changed.connect(func(_v: float) -> void: _on_lag_changed())
	col.add_child(_loss_slider)
	_update_lag_labels()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 80)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(pad)


func _plain_slider(lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
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
	return s


func _update_lag_labels() -> void:
	var ms := int(_lag_slider.value)
	_lag_label.text = "Künstliche Verzögerung pro Richtung: %d ms (der Ping steigt um %d ms)" % [ms, 2 * ms]
	_loss_label.text = "Paketverlust pro Richtung: %d %%" % int(_loss_slider.value)


func _on_lag_changed() -> void:
	_update_lag_labels()
	lag_changed.emit(_lag_slider.value, _loss_slider.value)


## Status line of the Online page; `busy` is true while connecting or connected (the button states follow).
func set_online_status(text: String, busy: bool) -> void:
	_online_status.text = text
	_connect_btn.disabled = busy
	_disconnect_btn.disabled = not busy


func _build_mods_page(scroll: ScrollContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)
	# Column buttons: all off / all level 3, for "Du" and for "Bots".
	for who in ["you", "bots"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var cap := Label.new()
		cap.text = "Du:" if who == "you" else "Bots:"
		cap.custom_minimum_size = Vector2(90, 0)
		cap.add_theme_font_size_override("font_size", FONT_SIZE)
		cap.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(cap)
		var off := _button("Alle aus")
		off.pressed.connect(func() -> void: _set_all(who, 0))
		row.add_child(off)
		var max3 := _button("Alle Stufe 3")
		max3.pressed.connect(func() -> void: _set_all(who, Mods.MAX_LEVEL))
		row.add_child(max3)
	col.add_child(_synergy_panel())
	for id in Mods.ORDER:
		col.add_child(_mod_row(id))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 80)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(pad)


## "Aktive Kombinationen": the synergies that are active for "Du".
func _synergy_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.16, 0.08, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(box)
	var head := Label.new()
	head.text = "Aktive Kombinationen"
	head.add_theme_font_size_override("font_size", 26)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(head)
	_syn_label = Label.new()
	_syn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_syn_label.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	_syn_label.modulate = Color(1, 1, 1, 0.9)
	_syn_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_syn_label)
	return panel


func _mod_row(id: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.2, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(box)
	var name_l := Label.new()
	name_l.text = Mods.mod_name(id)
	name_l.add_theme_font_size_override("font_size", 26)
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(name_l)
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	desc.modulate = Color(1, 1, 1, 0.85)
	desc.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(desc)
	_desc_labels[id] = desc
	var sel := HBoxContainer.new()
	sel.add_theme_constant_override("separation", 30)
	sel.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(sel)
	for who in ["you", "bots"]:
		var grp := ButtonGroup.new()
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		var l := Label.new()
		l.text = "Du" if who == "you" else "Bots"
		l.custom_minimum_size = Vector2(70, 0)
		l.add_theme_font_size_override("font_size", FONT_SIZE)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(l)
		var btns: Array[Button] = []
		for level in Mods.MAX_LEVEL + 1:
			var b := Button.new()
			b.text = "aus" if level == 0 else Mods.ROMAN[level]
			b.toggle_mode = true
			b.button_group = grp
			b.custom_minimum_size = LEVEL_BUTTON_SIZE
			b.add_theme_font_size_override("font_size", FONT_SIZE)
			b.pressed.connect(func() -> void: _set_level(who, id, level))
			h.add_child(b)
			btns.append(b)
		_level_buttons["%s:%s" % [who, id]] = btns
		sel.add_child(h)
	return panel


func _levels_of(who: String) -> Dictionary:
	return cfg.mods_you if who == "you" else cfg.mods_bots


func _set_level(who: String, id: String, level: int) -> void:
	if _suppress:
		return
	_levels_of(who)[id] = level
	_refresh_mods()
	_queue_save()


func _set_all(who: String, level: int) -> void:
	for id in Mods.ORDER:
		_levels_of(who)[id] = level
	_refresh_mods()
	_queue_save()


func _refresh_mods() -> void:
	_suppress = true
	var combos: Array[String] = []
	for key in Mods.active_synergies(cfg.mods_you):
		combos.append("• " + Mods.describe_synergy(key, cfg.mods_you))
	_syn_label.text = "\n".join(combos) if not combos.is_empty() \
			else "Keine. Kombiniere z. B. Splitter mit Sprengkopf, Dicker Brocken mit Stolperdraht."
	for id in Mods.ORDER:
		var lv_you: int = cfg.mods_you.get(id, 0)
		var lv_bots: int = cfg.mods_bots.get(id, 0)
		(_level_buttons["you:" + id] as Array)[lv_you].set_pressed_no_signal(true)
		(_level_buttons["bots:" + id] as Array)[lv_bots].set_pressed_no_signal(true)
		var text := ""
		if lv_you > 0:
			text += "Du (%s): %s" % [Mods.ROMAN[lv_you], Mods.describe(id, lv_you)]
		if lv_bots > 0:
			if text != "":
				text += "\n"
			text += "Bots (%s): %s" % [Mods.ROMAN[lv_bots], Mods.describe(id, lv_bots)]
		if text == "":
			text = "Stufe I: %s" % Mods.describe(id, 1)
		(_desc_labels[id] as Label).text = text
	_suppress = false


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
	_refresh_mods()
	_mark_figure()
	_variant_opt.select(cfg.out_variant)
	_bot_opt.select(cfg.bot_mode)
	_suppress = false


func _queue_save() -> void:
	_save_timer.start()


## Each page resets its own content: the values page the tuning values, the modifier page the levels,
## the online page the lag tool.
func _on_reset() -> void:
	if _online_page.visible:
		_lag_slider.value = 0.0
		_loss_slider.value = 0.0
		_smooth_check.button_pressed = true
		return
	if _mods_page.visible:
		_set_all("you", 0)
		_set_all("bots", 0)
	else:
		cfg.reset()
	refresh()
	TuningStore.save(cfg)


## Overlay with the settings as plain text, selectable, plus a short confirmation.
func _build_export_panel() -> void:
	_export_panel = Control.new()
	_export_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_export_panel.visible = false
	add_child(_export_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_export_panel.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	_export_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	_export_status = Label.new()
	_export_status.add_theme_font_size_override("font_size", 26)
	box.add_child(_export_status)
	_export_text = TextEdit.new()
	_export_text.editable = false
	_export_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_export_text.add_theme_font_size_override("font_size", 20)
	box.add_child(_export_text)
	var done := _button("Fertig")
	done.pressed.connect(func() -> void: _export_panel.visible = false)
	box.add_child(done)


func _on_export() -> void:
	var text := cfg.export_text()
	DisplayServer.clipboard_set(text)
	_export_text.text = text
	_export_status.text = "In die Zwischenablage kopiert"
	_export_panel.visible = true


## Shows the update button and the new version next to the running one; "" hides them.
func set_update(version: String) -> void:
	_update_btn.visible = version != ""
	var text := "Version %s" % UpdateCheck.running_version()
	_version_label.text = text + ("  (neu: %s)" % version if version != "" else "")


func open_menu() -> void:
	refresh()
	visible = true


func close_menu() -> void:
	visible = false
	_export_panel.visible = false
	TuningStore.save(cfg)
	closed.emit()
