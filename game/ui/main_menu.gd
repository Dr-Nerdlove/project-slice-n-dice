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
var _main_page: Control
var _banner_label: Label


func setup() -> void:
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
	play_btn = UiKit.button("Play", "main", "Last Standing")
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
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
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
	var panel := UiKit.panel("paper")
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size.x = 520.0
	col.add_child(panel)
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
	box.add_child(UiKit.body("More settings (touch controls) follow with the match update."))


func show_main() -> void:
	_main_page.visible = true
	settings_page.visible = false


func show_settings() -> void:
	_main_page.visible = false
	settings_page.visible = true


## Android back / Escape: leaves the settings page. False when there was nothing to leave (the caller quits).
func back() -> bool:
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
