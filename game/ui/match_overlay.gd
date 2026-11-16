class_name MatchOverlay
extends CanvasLayer
## The screens of a Play match over the arena: the 3-2-1-GO countdown, the round result with the scoreboard, the
## shop (`ShopPanel`) and the match-over panel. It only READS the match state of the sim it is given each frame (`update`) and reports
## button presses; `main.gd` owns the flow. Nothing is shown during PLAY (no UI during a round) and in Training.

signal rematch_pressed
signal main_menu_pressed
signal shop_buy(k: int)
signal shop_reroll
signal shop_done
signal shop_sell(n: int)
signal shop_lock(k: int)

const GO_TIME := 0.6        # how long "GO!" stays after the countdown
const PANEL_DELAY := 0.8    # the result / match-over panel appears this long after the last hit

var countdown_label: Label
var panel: PanelContainer
var heading_label: Label
var scorer_label: Label
var rows_box: VBoxContainer
var coins_label: Label
var target_label: Label
var rematch_btn: Button
var wait_label: Label
var main_menu_btn: Button
var shop: ShopPanel

## Set by main.gd every frame: the connection broke and the game is trying to come back.
var reconnecting := false
var reconnect_panel: PanelContainer

var _shown_key := ""
var _go_t := -1.0
var _pop_round := -1   # the round whose new pip already pulsed
var _last_phase := MatchMode.Phase.OFF


func setup() -> void:
	layer = 6
	visible = false
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	countdown_label = UiKit.title("3", 220)
	countdown_label.visible = false
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(countdown_label)

	panel = UiKit.panel("paper")
	panel.custom_minimum_size.x = 640.0
	panel.visible = false
	center.add_child(panel)
	shop = ShopPanel.new()
	shop.visible = false
	shop.buy_pressed.connect(func(k: int) -> void: shop_buy.emit(k))
	shop.reroll_pressed.connect(func() -> void: shop_reroll.emit())
	shop.done_pressed.connect(func() -> void: shop_done.emit())
	shop.sell_pressed.connect(func(n: int) -> void: shop_sell.emit(n))
	shop.lock_pressed.connect(func(k: int) -> void: shop_lock.emit(k))
	center.add_child(shop)
	reconnect_panel = UiKit.panel("paper")
	reconnect_panel.visible = false
	reconnect_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(reconnect_panel)
	reconnect_panel.add_child(UiKit.heading("Reconnecting …", 30))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	heading_label = UiKit.heading("", 30)
	box.add_child(heading_label)
	scorer_label = UiKit.label("", 24, UiKit.TOMATO, true)
	box.add_child(scorer_label)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 2)
	box.add_child(rows_box)
	coins_label = UiKit.label("", UiKit.SMALL_SIZE, UiKit.MUTE)
	coins_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(coins_label)
	target_label = UiKit.eyebrow("")
	box.add_child(target_label)
	rematch_btn = UiKit.compact(UiKit.button("Rematch", "main"), 48.0, 24)
	rematch_btn.pressed.connect(func() -> void: rematch_pressed.emit())
	box.add_child(rematch_btn)
	wait_label = UiKit.heading("Waiting for the host", 22)
	box.add_child(wait_label)
	# Only at match over, and "dark": a "quiet" button (translucent, paper text) is invisible on the paper panel,
	# and between rounds an invisible Main menu button at the bottom ended matches by accident.
	main_menu_btn = UiKit.compact(UiKit.button("Main menu", "dark"), 48.0, 24)
	main_menu_btn.pressed.connect(func() -> void: main_menu_pressed.emit())
	box.add_child(main_menu_btn)


## "3", "2", "1" for the countdown phase.
static func countdown_text(phase_t: float) -> String:
	return str(clampi(ceili(MatchMode.COUNTDOWN_TIME - phase_t), 1, 3))


## Name of a slot for the scoreboard: "You" for the own slot, else the figure name (offline bots get " (bot)").
## The own coin line under the scoreboard, e.g. "+6 coins: round 3, kills 1, survivor 2". Empty outside the roster.
static func coin_text(m: MatchMode, slot: int) -> String:
	if slot < 0 or slot >= m.roster.size() or not m.roster[slot]:
		return ""
	var parts := m.coin_parts(slot, m.last_scorer)
	var bits: Array[String] = []
	for k: String in ["base", "kills", "survivor", "underdog", "leader"]:
		if parts[k] > 0:
			bits.append("%s %d" % [{"base": "round", "kills": "kills", "survivor": "survivor", "underdog": "underdog", "leader": "leader kill"}[k], parts[k]])
	return "+%d coins: %s" % [m.earned[slot], ", ".join(bits)]


static func player_name(sim: Sim, slot: int, own: int, bots_offline: bool) -> String:
	if slot == own:
		return "You"
	var n: String = ToyFigure.NAMES[posmod(sim.players[slot].skin, ToyFigure.NAMES.size())]
	return n + " (bot)" if bots_offline else n


## Called every frame. `sim` is the sim that is drawn, `own` the own slot, `can_rematch` whether this device may
## restart the match (Solo, the host), `bots_offline` marks slots > 0 as bots (solo).
func update(sim: Sim, own: int, show_it: bool, can_rematch: bool, bots_offline: bool, dt: float) -> void:
	var m := sim.mode
	if m.phase != _last_phase:
		if _last_phase == MatchMode.Phase.COUNTDOWN and m.phase == MatchMode.Phase.PLAY:
			_go_t = 0.0
		elif m.phase != MatchMode.Phase.PLAY:
			_go_t = -1.0
		_last_phase = m.phase
	if _go_t >= 0.0:
		_go_t += dt
		if _go_t >= GO_TIME:
			_go_t = -1.0
	var ctext := ""
	reconnect_panel.visible = show_it and reconnecting
	if show_it and not reconnecting:
		if m.phase == MatchMode.Phase.COUNTDOWN:
			ctext = countdown_text(m.phase_t)
		elif m.phase == MatchMode.Phase.PLAY and _go_t >= 0.0:
			ctext = "GO!"
	countdown_label.text = ctext
	countdown_label.visible = ctext != ""
	var panel_on := show_it and not reconnecting and m.phase_t >= PANEL_DELAY and (m.phase == MatchMode.Phase.RESULT or m.phase == MatchMode.Phase.MATCH_OVER)
	panel.visible = panel_on
	shop.visible = show_it and not reconnecting and m.phase == MatchMode.Phase.SHOP and own >= 0 and own < m.roster.size() and m.roster[own]
	if shop.visible:
		shop.refresh(sim, own)
	visible = show_it
	if not panel_on:
		_shown_key = ""
		if m.phase != MatchMode.Phase.RESULT:
			_pop_round = -1
		return
	var over := m.phase == MatchMode.Phase.MATCH_OVER
	var key := "%d|%d|%d|%s|%s|%s" % [m.phase, m.round, m.winner, str(m.points), str(m.roster) + str(m.coins), "%d%d" % [int(can_rematch), int(bots_offline)]]
	if key != _shown_key:
		_shown_key = key
		_fill(sim, own, over, bots_offline)
	rematch_btn.visible = over and can_rematch
	wait_label.visible = over and not can_rematch
	main_menu_btn.visible = over


func _fill(sim: Sim, own: int, over: bool, bots_offline: bool) -> void:
	var m := sim.mode
	if over:
		var w := player_name(sim, m.winner, own, bots_offline) if m.winner >= 0 else ""
		heading_label.text = "You win the match!" if m.winner == own else "%s wins the match!" % w
		scorer_label.text = ""
	else:
		heading_label.text = "Round %d" % m.round
		scorer_label.text = "Nobody scores" if m.last_scorer < 0 else ("You score!" if m.last_scorer == own else "%s scores!" % player_name(sim, m.last_scorer, own, bots_offline))
	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	var slots: Array = []
	for i in m.roster.size():
		if m.roster[i]:
			slots.append(i)
	slots.sort_custom(func(a: int, b: int) -> bool: return m.points[a] > m.points[b] or (m.points[a] == m.points[b] and a < b))
	var pop_now := not over and m.round != _pop_round
	if not over:
		_pop_round = m.round
	for i: int in slots:
		var skin: int = sim.players[i].skin
		rows_box.add_child(make_row(player_name(sim, i, own, bots_offline), ToyFigure.ACCENTS[posmod(skin, ToyFigure.ACCENTS.size())],
				m.points[i], m.target, i == own, pop_now and not over and i == m.last_scorer, m.coins[i], m.earned[i]))
	coins_label.text = coin_text(m, own)
	target_label.text = ("First to %d" % m.target).to_upper()


## One scoreboard row: colour dot, name, the score pips (the newest one pulses when `pop`) and the coin tag.
func make_row(pname: String, accent: Color, pts: int, target: int, is_own: bool, pop: bool, total: int, gained: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var dot := ColorRect.new()
	dot.color = accent
	dot.custom_minimum_size = Vector2(22, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var name_label := UiKit.label(pname, 22, UiKit.INK, is_own)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var pips := ScorePips.new()
	pips.name = "Pips"
	pips.setup(target, pts, accent)
	row.add_child(pips)
	row.add_child(_coin_tag(total, gained))
	if pop:
		pips.tree_entered.connect(pips.start_pop, CONNECT_ONE_SHOT)   # a tween needs the node in the tree
	return row


## A yellow price-tag chip with the player's coins and, small, what the last round gave.
func _coin_tag(total: int, gained: int) -> Control:
	var tag := UiKit.price_tag("%d ¢  +%d" % [total, gained])
	tag.custom_minimum_size.x = 96.0
	return tag
