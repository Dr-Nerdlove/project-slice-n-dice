class_name PauseMenu
extends CanvasLayer
## The small panel of the pause button in a real game (Play): Resume or back to the main menu. In Training the
## pause button opens the tuning menu instead. Offline the game is paused while this is open; online it keeps running.

signal resume_pressed
signal main_menu_pressed

var resume_btn: Button
var main_menu_btn: Button


func setup() -> void:
	layer = 12
	visible = false
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.08, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := UiKit.panel("ink")
	panel.custom_minimum_size.x = 420.0
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UiKit.heading("Paused", 30, UiKit.PAPER))
	resume_btn = UiKit.button("Resume", "main")
	resume_btn.pressed.connect(func() -> void: resume_pressed.emit())
	box.add_child(resume_btn)
	main_menu_btn = UiKit.button("Main menu", "quiet")
	main_menu_btn.pressed.connect(func() -> void: main_menu_pressed.emit())
	box.add_child(main_menu_btn)
