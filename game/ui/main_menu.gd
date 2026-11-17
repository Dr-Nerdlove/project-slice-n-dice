class_name MainMenu
extends CanvasLayer
## The first screen: over the dimmed arena the title on the left and Play / Training / Settings on the right.
## Settings (version, update button) is a second page of the same layer. The update notice shows here, never during
## a game. No logic of its own: it only reports button presses.

signal play_pressed
signal training_pressed
signal update_requested
signal update_dismissed

var play_btn: Button
var training_btn: Button
var settings_btn: Button
var version_label: Label
var update_banner: PanelContainer
var settings_page: Control
var settings_update_btn: Button
var settings_version_label: Label
var touch: TouchSettings = TouchSettings.new()   # shared with the input router; edited here, saved at once
var mode_buttons: Array[Button] = []      # Floating / Fixed
var size_buttons: Array[Button] = []
var opacity_buttons: Array[Button] = []
var swap_btn: Button
var layout_btn: Button
var layout_editor: TouchLayoutEditor
var _main_page: Control
var _banner_label: Label


const SIZES := [["Small", 0.8], ["Normal", 1.0], ["Large", 1.25], ["Huge", 1.5]]
const OPACITIES := [["Faint", 0.5], ["Normal", 1.0], ["Strong", 1.6]]


## `touch_settings` is the instance the input router also reads, so a change shows in the game at once.
func setup(touch_settings: TouchSettings = null) -> void:
	if touch_settings != null:
		touch = touch_settings
	layer = 10
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(UiKit.backdrop())
	_main_page = Control.new()
	_main_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_main_page)
	_build_main(_main_page)
	settings_page = Control.new()
	settings_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_page.visible = false
	root.add_child(settings_page)
	_build_settings(settings_page)
	layout_editor = TouchLayoutEditor.new()
	root.add_child(layout_editor)
	layout_editor.setup()
	layout_editor.closed.connect(func(_saved: bool) -> void: _mark_touch())
	show_main()


func _build_main(page: Control) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 20)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var title := UiKit.title("Spinback Rumble", 84)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_constant_override("line_spacing", -6)
	left.add_child(title)
	var sub := UiKit.label("Yo-yo brawls in the playroom. 2 to 8 players.", 24, Color("d9dbe3"))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 430.0
	left.add_child(sub)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 360.0
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 16)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	play_btn = UiKit.button("Play", "main")
	play_btn.custom_minimum_size.y = 76.0
	play_btn.pressed.connect(func() -> void: play_pressed.emit())
	right.add_child(play_btn)
	training_btn = UiKit.button("Training", "paper", "Try out values")
	training_btn.custom_minimum_size.y = 76.0
	training_btn.pressed.connect(func() -> void: training_pressed.emit())
	right.add_child(training_btn)
	settings_btn = UiKit.button("Settings", "quiet")
	settings_btn.custom_minimum_size.y = 76.0
	settings_btn.pressed.connect(show_settings)
	right.add_child(settings_btn)

	version_label = UiKit.label("Version %s" % UpdateCheck.running_version(), 16, Color("b9bdc9"))
	version_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version_label.position = Vector2(80.0, 576.0 - 44.0)
	version_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	page.add_child(version_label)
	_build_banner(page)


## A small notice at the bottom centre: a newer version exists.
func _build_banner(page: Control) -> void:
	update_banner = UiKit.panel("ink")
	update_banner.visible = false
	update_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	update_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	update_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	update_banner.position.y = -16.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	update_banner.add_child(row)
	_banner_label = UiKit.label("", 22, UiKit.PAPER)
	_banner_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_banner_label)
	var get_btn := UiKit.button("Download", "main")
	get_btn.pressed.connect(func() -> void: update_requested.emit())
	row.add_child(get_btn)
	var later := UiKit.button("Later", "quiet")
	later.pressed.connect(func() -> void:
		update_banner.visible = false
		update_dismissed.emit())
	row.add_child(later)
	page.add_child(update_banner)


func _build_settings(page: Control) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	col.add_child(bar)
	var back := UiKit.button("Back", "quiet")
	back.custom_minimum_size.x = 140.0
	back.pressed.connect(show_main)
	bar.add_child(back)
	bar.add_child(UiKit.title("Settings", 44))
	var panels := HBoxContainer.new()   # no scrolling anywhere: the page has to fit the screen (checked by a test)
	panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panels.add_theme_constant_override("separation", 20)
	col.add_child(panels)
	var panel := UiKit.panel("paper")
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size.x = 340.0
	panels.add_child(panel)
	panels.add_child(_build_touch())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UiKit.eyebrow("About"))
	settings_version_label = UiKit.label("Version %s" % UpdateCheck.running_version(), 24, UiKit.INK, true)
	box.add_child(settings_version_label)
	settings_update_btn = UiKit.button("Download the new version", "main")
	settings_update_btn.visible = false
	settings_update_btn.pressed.connect(func() -> void: update_requested.emit())
	box.add_child(settings_update_btn)


## The "Touch controls" panel: stick mode, size, opacity, swap sides and the layout editor.
func _build_touch() -> Control:
	var panel := UiKit.panel("paper")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(UiKit.eyebrow("Touch controls"))
	mode_buttons = _option_row(box, "Sticks", [["Floating", TouchSettings.Mode.FLOATING], ["Fixed", TouchSettings.Mode.FIXED]],
			func(v: Variant) -> void: touch.mode = v)
	size_buttons = _option_row(box, "Size", SIZES, func(v: Variant) -> void: touch.scale = v)
	opacity_buttons = _option_row(box, "Opacity", OPACITIES, func(v: Variant) -> void: touch.opacity = v)
	var row := _row(box, "Left-handed")
	swap_btn = UiKit.button("Swap sides", "paper")
	swap_btn.toggle_mode = true
	swap_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swap_btn.custom_minimum_size.y = 44.0
	swap_btn.pressed.connect(func() -> void:
		touch.set_swap(not touch.swap)
		touch.save()
		_mark_touch())
	row.add_child(swap_btn)
	layout_btn = UiKit.button("Place controls", "paper")
	layout_btn.custom_minimum_size.y = 44.0
	layout_btn.pressed.connect(func() -> void: layout_editor.open(touch))
	box.add_child(layout_btn)
	box.add_child(UiKit.body("Floating: a stick appears where your thumb lands. Fixed: sticks stay where you put them. "
			+ "The Dash button can be placed in both."))
	_mark_touch()
	return panel


func _row(box: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var l := UiKit.label(title, 20, UiKit.INK, true)
	l.custom_minimum_size.x = 130.0
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


## A labelled row of toggle buttons; picking one calls `apply(value)`, saves the touch settings and marks the row.
func _option_row(box: VBoxContainer, title: String, options: Array, apply: Callable) -> Array[Button]:
	var row := _row(box, title)
	var out: Array[Button] = []
	for o in options:
		var value: Variant = o[1]
		var b := UiKit.button(o[0], "paper")
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 44.0
		b.pressed.connect(func() -> void:
			apply.call(value)
			touch.save()
			_mark_touch())
		row.add_child(b)
		out.append(b)
	return out


func _mark_touch() -> void:
	mode_buttons[0].set_pressed_no_signal(touch.mode == TouchSettings.Mode.FLOATING)
	mode_buttons[1].set_pressed_no_signal(touch.mode == TouchSettings.Mode.FIXED)
	for i in SIZES.size():
		size_buttons[i].set_pressed_no_signal(is_equal_approx(touch.scale, SIZES[i][1]))
	for i in OPACITIES.size():
		opacity_buttons[i].set_pressed_no_signal(is_equal_approx(touch.opacity, OPACITIES[i][1]))
	swap_btn.set_pressed_no_signal(touch.swap)


func show_main() -> void:
	_main_page.visible = true
	settings_page.visible = false


func show_settings() -> void:
	_main_page.visible = false
	settings_page.visible = true


## Android back / Escape: leaves the settings page. False when there was nothing to leave (the caller quits).
func back() -> bool:
	if layout_editor.visible:
		layout_editor.cancel()
		return true
	if settings_page.visible:
		show_main()
		return true
	return false


## Shows the update notice (banner and settings button) for `version`; "" hides both.
func set_update(version: String, dismissed := false) -> void:
	settings_update_btn.visible = version != ""
	settings_version_label.text = "Version %s" % UpdateCheck.running_version() + ("  (new: %s)" % version if version != "" else "")
	_banner_label.text = "New version %s available" % version
	update_banner.visible = version != "" and not dismissed
	update_banner.reset_size()
