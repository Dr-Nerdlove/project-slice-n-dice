class_name PlayLobby
extends CanvasLayer
## "Match": set up a real game. The mode card (Last Standing for now), the figure choice with a live 3D picture,
## and two ways to play: Solo against bots, or Together on the same Wi-Fi / hotspot (host a game or join one by
## the list of found games or by code). The real game always uses the fixed default values; nothing here reads
## the Training tuning. The only thing the lobby edits is the chosen figure of the SAVED config (`cfg.character`).
## No logic of its own: it reports presses; `main.gd` starts the games.

signal back_pressed
signal solo_requested
signal host_requested(with_bots: bool)
signal join_local_requested(ip: String, port: int)
signal join_code_requested(code: String)
signal stop_requested
signal figure_chosen(index: int)
signal color_chosen(index: int)
signal target_chosen(points: int)
signal start_match_requested
signal rejoin_requested

## Games listed at most (the page has no room to scroll).
const MAX_FOUND := 2

var cfg: Config                 # the saved config; only `character`, `player_color` and the game settings are touched
## How the figure choice is persisted (a test replaces this so it never writes the real settings file).
var save_fn: Callable = TuningStore.save
var back_btn: Button
var solo_btn: Button
var mode_card: PanelContainer
var figure_buttons: Array[Button] = []
var color_buttons: Array[Button] = []    # the eight palette swatches
var target_buttons: Array[Button] = []   # First to 10 / 15 / 20
var player_buttons: Array[Button] = []   # 2 .. 8 players
var start_btn: Button           # host only: begins the match for everybody in the lobby
var wait_label: Label           # joiner only: waits for the host
var cols: HBoxContainer         # the three columns of the page (a test measures them)
var figure_preview: FigurePreview   # live 3D picture of the chosen figure

var _preview_cfg := Config.new()   # the picture is drawn with the standard sizes, as in a real game

var _bots_check: CheckButton
var _host_btn: Button
var _stop_btn: Button
var _join_btn: Button
var rejoin_btn: Button         # shown while a Play game with a running match is stored and this device is not in a session
var _has_rejoin := false
var _code_edit: LineEdit
var _status: Label
var _hosting_box: Control
var _code_label: Label
var _players_label: Label
var _hint: Label                 # how to connect: hidden while hosting or connected
var _join_box: VBoxContainer     # games found and the code field: hidden while hosting or connected
var _found_box: VBoxContainer
var _empty_label: Label
var _found_buttons := {}        # "ip:port" -> Button
var _hosting := false
var _connected := false
var _shown := ""                # what the hosting box shows now (to touch the labels only on a change)
## Looking for games: the listener runs only while the lobby is open and the player is neither hosting nor connected.
var discovery_port := LanBeacon.PORT
var clock: Callable = Time.get_ticks_msec   # a test replaces this with a fake clock
var _listener: LanBeacon


func setup(c: Config) -> void:
	cfg = c
	layer = 10
	visible = false
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(UiKit.backdrop())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(page)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	page.add_child(bar)
	back_btn = UiKit.button("Back", "quiet")
	back_btn.custom_minimum_size.x = 140.0
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	bar.add_child(back_btn)
	bar.add_child(UiKit.title("Match", 44))

	# Three columns, no scrolling: the base screen is 1280 x 576 and every other screen is at least that big
	# (stretch aspect "expand"), so everything below has to fit in about 470 px of height.
	cols = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 20)
	page.add_child(cols)
	var first := VBoxContainer.new()
	first.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first.size_flags_stretch_ratio = 1.0
	first.add_theme_constant_override("separation", 14)
	cols.add_child(first)
	var second := VBoxContainer.new()
	second.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second.size_flags_stretch_ratio = 0.85
	cols.add_child(second)
	var third := VBoxContainer.new()
	third.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	third.size_flags_stretch_ratio = 1.35
	cols.add_child(third)

	first.add_child(_build_mode_card())
	first.add_child(_build_solo())
	second.add_child(_build_figures())
	third.add_child(_build_together())
	_mark_figure()
	_mark_target()
	_mark_players()


func _build_mode_card() -> Control:
	mode_card = UiKit.panel("paper")
	var sb := UiKit.theme().get_stylebox("panel", "PaperPanel").duplicate() as StyleBoxFlat
	sb.set_border_width_all(4)   # the selected card: a tomato outline
	sb.border_color = UiKit.TOMATO
	sb.set_content_margin_all(16.0)
	mode_card.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	mode_card.add_child(box)
	box.add_child(UiKit.eyebrow("Mode"))
	box.add_child(UiKit.heading("Last Standing", 24))
	box.add_child(UiKit.eyebrow("Points to win"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for i in MatchMode.TARGETS.size():
		var pts: int = MatchMode.TARGETS[i]
		var b := UiKit.compact(UiKit.button(str(pts), "paper"))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _choose_target(pts))
		row.add_child(b)
		target_buttons.append(b)
	box.add_child(UiKit.eyebrow("Players"))
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 4)
	box.add_child(prow)
	for n in range(Config.MIN_PLAYERS, Config.NUM_PLAYERS + 1):
		var b := UiKit.compact(UiKit.button(str(n), "paper"))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _choose_players(n))
		prow.add_child(b)
		player_buttons.append(b)
	return mode_card


func _build_figures() -> Control:
	var panel := UiKit.tighten(UiKit.panel("paper"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	box.add_child(UiKit.eyebrow("Your figure"))
	figure_preview = FigurePreview.new()
	figure_preview.custom_minimum_size = Vector2(0, 100)
	figure_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL   # takes all the height the column has left
	figure_preview.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(figure_preview)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for i in Config.SKIN_COUNT:
		var b := UiKit.compact(UiKit.button(ToyFigure.NAMES[i], "paper"), 32.0, 18)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _choose_figure(i))
		grid.add_child(b)
		figure_buttons.append(b)
	var swatches := HBoxContainer.new()
	swatches.name = "Colours"
	swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	swatches.add_theme_constant_override("separation", 6)
	box.add_child(swatches)
	for k in Config.COLOR_COUNT:
		var s := _swatch(ArenaView.PLAYER_COLORS[k])
		s.name = "Colour%d" % k
		s.pressed.connect(func() -> void: _choose_color(k))
		swatches.add_child(s)
		color_buttons.append(s)
	return panel


## A round colour swatch toggle: thin dark edge, a thick ink edge when it is the chosen one.
func _swatch(col: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(26, 26)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(13)
		var on: bool = state.contains("pressed")
		sb.set_border_width_all(5 if on else 1)
		sb.border_color = UiKit.INK if on else UiKit.INK.lerp(col, 0.4)
		b.add_theme_stylebox_override(state, sb)
	return b


func _build_solo() -> Control:
	var panel := UiKit.tighten(UiKit.panel("paper"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	row.add_child(texts)
	texts.add_child(UiKit.eyebrow("On this device"))
	texts.add_child(UiKit.heading("Solo vs bots", 22))
	solo_btn = UiKit.button("Go", "main")
	solo_btn.custom_minimum_size.x = 110.0
	solo_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	solo_btn.pressed.connect(func() -> void: solo_requested.emit())
	row.add_child(solo_btn)
	return panel


## Play on the same network: one device hosts, the others pick the game from a list or type its code. While this
## device hosts or is connected the joining half is hidden (it could not be used anyway), which keeps the card short.
func _build_together() -> Control:
	var panel := UiKit.tighten(UiKit.panel("paper"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(UiKit.heading("Together on one Wi-Fi", 22))
	_hint = UiKit.body("Everyone joins the same Wi-Fi, or the hotspot of one phone (switch it on in the phone's settings). The game ends when the host leaves the app.")
	col.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_bots_check = CheckButton.new()
	_bots_check.text = "Fill with bots"
	_bots_check.button_pressed = true
	_bots_check.custom_minimum_size = Vector2(0, 44)
	_bots_check.add_theme_font_override("font", UiKit.font(false, 500))
	_bots_check.add_theme_font_size_override("font_size", UiKit.SMALL_SIZE)
	_bots_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bots_check)
	_host_btn = UiKit.compact(UiKit.button("Host a game", "main"), 48.0)
	_host_btn.pressed.connect(func() -> void: host_requested.emit(_bots_check.button_pressed))
	row.add_child(_host_btn)
	_stop_btn = UiKit.compact(UiKit.button("Stop", "dark"), 48.0)
	_stop_btn.disabled = true
	_stop_btn.pressed.connect(func() -> void: stop_requested.emit())
	row.add_child(_stop_btn)
	# Shown while hosting: the code in big letters and the player count.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.visible = false
	col.add_child(box)
	_hosting_box = box
	box.add_child(UiKit.body("Your game is open. The others type this code:"))
	_code_label = UiKit.heading("", 56)
	box.add_child(_code_label)
	_players_label = UiKit.label("", 22, UiKit.INK, true)
	_players_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_players_label)
	# Shown while this device neither hosts nor is connected: the games found and the code field.
	_join_box = VBoxContainer.new()
	_join_box.add_theme_constant_override("separation", 8)
	col.add_child(_join_box)
	_found_box = VBoxContainer.new()
	_found_box.add_theme_constant_override("separation", 6)
	_join_box.add_child(_found_box)
	_empty_label = UiKit.body("No game found yet")
	_found_box.add_child(_empty_label)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_join_box.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.custom_minimum_size = Vector2(120, 48)
	_code_edit.max_length = 16
	_code_edit.placeholder_text = "Or enter a code"
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_code_edit)
	_join_btn = UiKit.compact(UiKit.button("Join", "dark"), 48.0)
	_join_btn.pressed.connect(func() -> void: join_code_requested.emit(_code_edit.text))
	join_row.add_child(_join_btn)
	rejoin_btn = UiKit.compact(UiKit.button("Rejoin", "main"), 48.0)
	rejoin_btn.visible = false
	rejoin_btn.pressed.connect(func() -> void: rejoin_requested.emit())
	join_row.add_child(rejoin_btn)
	_status = UiKit.label("Not connected", 20, UiKit.INK, true)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	start_btn = UiKit.compact(UiKit.button("Start match", "main"), 48.0)
	start_btn.visible = false
	start_btn.pressed.connect(func() -> void: start_match_requested.emit())
	col.add_child(start_btn)
	wait_label = UiKit.heading("Waiting for the host to start", 20)
	wait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wait_label.visible = false
	col.add_child(wait_label)
	return panel


# ---------------------------------------------------------------- figure

func _choose_figure(i: int) -> void:
	cfg.character = i
	_mark_figure()
	save_fn.call(cfg)
	figure_chosen.emit(i)


func _choose_color(k: int) -> void:
	cfg.player_color = k
	_mark_figure()
	save_fn.call(cfg)
	color_chosen.emit(k)


func _choose_target(points: int) -> void:
	cfg.target_score = points
	_mark_target()
	save_fn.call(cfg)
	target_chosen.emit(points)


## How many play in a Play match: you plus bots in Solo, the room size when hosting.
func _choose_players(n: int) -> void:
	cfg.player_count = clampi(n, Config.MIN_PLAYERS, Config.NUM_PLAYERS)
	_mark_players()
	save_fn.call(cfg)


func _mark_players() -> void:
	for i in player_buttons.size():
		player_buttons[i].set_pressed_no_signal(Config.MIN_PLAYERS + i == cfg.player_count)


func _mark_target() -> void:
	for i in target_buttons.size():
		target_buttons[i].set_pressed_no_signal(MatchMode.TARGETS[i] == cfg.target_score)


func _mark_figure() -> void:
	for i in figure_buttons.size():
		figure_buttons[i].set_pressed_no_signal(i == cfg.character)
	for k in color_buttons.size():
		color_buttons[k].set_pressed_no_signal(k == cfg.player_color)
	var col: Color = ArenaView.PLAYER_COLORS[cfg.player_color]
	if figure_preview.figure == null or figure_preview.figure.kind != cfg.character or figure_preview.figure.player_color != col:
		figure_preview.show_figure(cfg.character, col, _preview_cfg)


## Shows the lobby (the figure shown follows the saved choice) / hides it.
func open() -> void:
	_mark_figure()
	_mark_target()
	_mark_players()
	visible = true


func close() -> void:
	visible = false
	_stop_listener()


# ---------------------------------------------------------------- local play

## Status line of the lobby (results of connections started here).
func set_status(text: String) -> void:
	_status.text = text


## What the lobby shows about the running session: hosting (with the code, "" = no usable address) and/or connected
## (connecting counts). Called often; it touches the widgets only when something changed.
func set_session(hosting: bool, connected: bool, code: String, players: int) -> void:
	_hosting = hosting
	_connected = connected
	_host_btn.disabled = hosting or connected
	_join_btn.disabled = hosting or connected
	_stop_btn.disabled = not (hosting or connected)
	_refresh_rejoin()
	_hosting_box.visible = hosting
	_join_box.visible = not (hosting or connected)
	_hint.visible = not (hosting or connected)
	var shown := "%s|%d" % [code, players]
	if hosting and shown != _shown:
		_shown = shown
		if code == "":
			_code_label.text = ""
			_players_label.text = "No network address: join a Wi-Fi or switch on the hotspot."
			_players_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			_code_label.text = LanCode.grouped(code)
			_players_label.text = "Players: %d of %d" % [players, cfg.player_count]
	if not hosting:
		_shown = ""


## Whether a game to rejoin is stored (the button also needs this device to be neither hosting nor connected).
func set_rejoin(has_game: bool) -> void:
	_has_rejoin = has_game
	_refresh_rejoin()


func _refresh_rejoin() -> void:
	rejoin_btn.visible = _has_rejoin and not _hosting and not _connected


## The start controls of a connected lobby: the host sees "Start match" (enabled when `can_start`), a joiner sees
## that the host has to start. Not connected: neither.
func set_start(hosting: bool, connected: bool, can_start: bool) -> void:
	start_btn.visible = hosting and connected
	start_btn.disabled = not can_start
	wait_label.visible = connected and not hosting


## Looks for games while it makes sense; closes the listener otherwise.
func _process(_delta: float) -> void:
	var want := visible and not _hosting and not _connected
	if want and _listener == null:
		_listener = LanBeacon.new()
		if _listener.start_listening(discovery_port) != OK:
			_listener = null   # no list, the code still works
			want = false
	elif not want:
		_stop_listener()
	if _listener != null:
		_show_found(_listener.poll(int(clock.call())))


func _stop_listener() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
		_show_found([])


func _exit_tree() -> void:
	if _listener != null:
		_listener.close()
		_listener = null


## Makes the list buttons match `games` (a button is created or removed only when its game appears or vanishes).
func _show_found(games: Array) -> void:
	var seen := {}
	for g: Dictionary in games.slice(0, MAX_FOUND):   # more would not fit the page (no scrolling)
		var key := "%s:%d" % [g["ip"], g["port"]]
		seen[key] = true
		var text := "Game %s – %d/%d players" % [LanCode.grouped(g["code"]), g["players"], g["max"]]
		var b: Button = _found_buttons.get(key)
		if b == null:
			b = UiKit.compact(UiKit.button(text, "dark"), 44.0)
			var ip: String = g["ip"]
			var port: int = g["port"]
			b.pressed.connect(func() -> void: join_local_requested.emit(ip, port))
			_found_box.add_child(b)
			_found_buttons[key] = b
		b.text = text
	for key: String in _found_buttons.keys():
		if not seen.has(key):
			(_found_buttons[key] as Button).queue_free()
			_found_buttons.erase(key)
	_empty_label.visible = games.is_empty()
