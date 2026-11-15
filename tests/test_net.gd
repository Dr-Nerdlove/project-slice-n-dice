extends SceneTree
## Netcode tests (headless). Run through tests/run.sh. Everything but the last section runs over the
## in-memory loopback with a fake clock, so it is fast and fully deterministic.

var fails := 0
## Moves the localhost ports (and the user:// file) so several test runs can go on at once (tests/run.sh).
var PORT_OFFSET := int(OS.get_environment("TEST_PORT_OFFSET"))
const Y := SimPlayer.Yo
const DT_MS := 1000.0 / 60.0


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  [" + info + "]" if info != "" else ""))
	if not ok:
		fails += 1


func inp(move := Vector2.ZERO, aim := Vector2.ZERO, held := false, dash := false) -> SimInput:
	var i := SimInput.new()
	i.move = move
	i.aim = aim
	i.aim_held = held
	i.dash = dash
	return i


# ---------------------------------------------------------------- rig

## Loopback hub + server + n clients. delay_ms is per direction.
## The train is off unless `with_train` (it has its own checks; the clock of the world it runs on is the server's, so
## a client is never "equal to a purely local sim" while it runs).
func make_rig(delay_ms: float, loss: float, n_clients: int, seed := 1, with_bots := false, with_train := false) -> Dictionary:
	var hub := LoopbackHub.new(seed)
	hub.delay_ms = delay_ms
	hub.loss_pct = loss
	var cfg := Config.new()
	cfg.max_range = 8.0      # the scenarios are set up for the old 8 m throw range and 9 m string
	cfg.string_length = 9.0
	if not with_train:
		cfg.train_speed = 0.0
	var server := ServerCore.new(cfg, hub.server, 7, with_bots)
	var clients: Array[ClientCore] = []
	for i in n_clients:
		clients.append(ClientCore.new(hub.connect_client()))
	return {"hub": hub, "server": server, "clients": clients}


## One 60 Hz frame of everything. `f` is Callable(client index) -> SimInput.
func step_rig(rig: Dictionary, f: Callable) -> void:
	var hub: LoopbackHub = rig["hub"]
	hub.advance(DT_MS)
	var cs: Array = rig["clients"]
	for k in cs.size():
		var c: ClientCore = cs[k]
		c.poll(DT_MS / 1000.0)
		c.tick(f.call(k))
	(rig["server"] as ServerCore).tick()


func warm_up(rig: Dictionary, max_ticks := 240) -> bool:
	for _t in max_ticks:
		step_rig(rig, func(_k: int) -> SimInput: return SimInput.new())
		var all := true
		for c: ClientCore in rig["clients"]:
			if c.state != ClientCore.State.ONLINE:
				all = false
		if all:
			return true
	return false


## A looping 5 s routine: walk, charge, throw, tap (retract), walk, charge, throw, hold (pull), dash.
## Player k mirrors player k - 1.
func scripted(k: int, t: int) -> SimInput:
	var dx := 1.0 if k % 2 == 0 else -1.0
	var ph := t % 300
	if ph < 60:
		return inp(Vector2(dx, 0.0))
	if ph < 90:
		return inp(Vector2.ZERO, Vector2(dx, 0.0), true)                 # charge, released at 90: thrown
	if ph < 125:
		return inp()
	if ph < 128:
		return inp(Vector2.ZERO, Vector2.ZERO, true)                     # tap while out: retract
	if ph < 160:
		return inp(Vector2(0.0, dx * 0.7))
	if ph < 190:
		return inp(Vector2.ZERO, Vector2(dx, 0.0), true)                 # charge, thrown at 190
	if ph < 225:
		return inp()
	if ph < 275:
		return inp(Vector2.ZERO, Vector2.ZERO, true)                     # held while out: pull
	if ph == 280:
		return inp(Vector2(dx, 0.0), Vector2.ZERO, false, true)          # dash
	return inp(Vector2(-dx, 0.3).limit_length(1.0))


## Two players go to the bottom edge (clear of the obstacles), walk towards each other, throw at each
## other, retract and walk back a little.
func duel(k: int, t: int) -> SimInput:
	var dx := 1.0 if k % 2 == 0 else -1.0
	var ph := t % 260
	if ph < 47:
		return inp(Vector2(0.0, 1.0))
	if ph < 137:
		return inp(Vector2(dx, 0.0))
	if ph < 179:
		return inp(Vector2.ZERO, Vector2(dx, 0.0), true)
	if ph < 215:
		return inp()
	if ph < 218:
		return inp(Vector2.ZERO, Vector2.ZERO, true)
	return inp(Vector2(-dx, 0.0))


func state_without_tick(s: Sim) -> PackedByteArray:
	var d := s.save_state()
	d.erase("tick")
	return var_to_bytes(d)


# ---------------------------------------------------------------- snapshot

func random_mods(r: RandomNumberGenerator) -> Dictionary:
	var m := {}
	for id in Mods.ORDER:
		m[id] = r.randi_range(0, 3)
	return m


func has_object(v: Variant) -> bool:
	match typeof(v):
		TYPE_OBJECT:
			return true
		TYPE_ARRAY:
			for e: Variant in v:
				if has_object(e):
					return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if has_object(k) or has_object(v[k]):
					return true
	return false


func test_snapshot() -> void:
	var worst := 0
	var runs := 0
	var all_ok := true
	var no_objects := true
	var kills_seen := 0
	var info := ""
	for seed_v in [3, 11, 42]:
		var cfg := Config.new()
		var a := Sim.new(cfg, seed_v)
		var bots: Array[Bot] = []
		for i in 4:
			bots.append(Bot.new(i, cfg, 100 + seed_v + i))
		var r := RandomNumberGenerator.new()
		r.seed = seed_v
		var points := [150, 400, 900]
		var t := 0
		for point: int in points:
			while t < point:
				if t % 120 == 0:
					for i in 4:
						a.apply_mods(i, random_mods(r))
				var ins: Array = []
				for b in bots:
					ins.append(b.think(a, 1.0 / 60.0))
				a.step(ins)
				for e: Dictionary in a.events:
					if e["type"] == "kill":
						kills_seen += 1
				t += 1
			var st := a.save_state()
			var bytes := var_to_bytes(st)
			no_objects = no_objects and not has_object(st)
			var b_sim := Sim.new(Config.new(), 999)
			b_sim.load_state(bytes_to_var(bytes))
			if var_to_bytes(b_sim.save_state()) != bytes:
				all_ok = false
				info = "load/save differs at seed %d tick %d" % [seed_v, t]
			# Copies of the bots (their own rng and phase are not sim state): only the inputs matter, so
			# record them once and feed both sims the same ones.
			var rec: Array = []
			for k in 400:
				var ins2: Array = []
				for b in bots:
					ins2.append(b.think(a, 1.0 / 60.0))
				rec.append(ins2)
				a.step(ins2)
				b_sim.step(ins2)
				if var_to_bytes(a.save_state()) != var_to_bytes(b_sim.save_state()):
					all_ok = false
					info = "diverged %d ticks after the snapshot (seed %d, tick %d)" % [k + 1, seed_v, t]
					break
				for e: Dictionary in a.events:
					if e["type"] == "kill":
						kills_seen += 1
			t += 400
			runs += 1
	check("snapshot: round trip through var_to_bytes, then identical for 400 ticks (%d runs)" % runs, all_ok, info)
	check("snapshot: contains no Objects", no_objects)
	check("snapshot: the runs include kills (so respawn rng is exercised)", kills_seen >= 3, "kills=%d" % kills_seen)

	# load_state keeps the existing objects, also when the head count changes
	var s1 := Sim.new(Config.new(), 5)
	var s2 := Sim.new(Config.new(), 6)
	s2.apply_mods(0, {"twin": 3})
	s2.players[0].heads.append(SimHead.new())
	var p0 := s1.players[0]
	var h0 := s1.players[0].heads[0]
	var p3 := s1.players[3]
	s1.load_state(s2.save_state())
	check("snapshot: load keeps SimPlayer and SimHead objects", s1.players[0] == p0 and s1.players[0].heads[0] == h0 and s1.players[3] == p3 and s1.players.size() == 4)
	check("snapshot: load adapts the head count", s1.players[0].heads.size() == 2)
	check("snapshot: events are not part of it", not s2.save_state().has("events") and not s2.save_state().has("cfg"))
	# the same snapshot twice gives identical bytes; a copy is independent of the live sim
	var st1 := s2.save_state()
	s2.players[0].pos = Vector2(1, 1)
	check("snapshot: dump is a deep copy", st1["players"][0]["pos"] != Vector2(1, 1))


# ---------------------------------------------------------------- train

func test_train() -> void:
	var rig := make_rig(60.0, 0.0, 1, 5, false, true)
	check("train: client joins", warm_up(rig))
	var cl: ClientCore = rig["clients"][0]
	var server: ServerCore = rig["server"]
	var idle := func(_k: int) -> SimInput: return SimInput.new()
	check("train: the client got the train speed with the server config", is_equal_approx(cl.cfg.train_speed, Config.DEFAULTS["train_speed"]))
	for _t in 60:
		step_rig(rig, idle)
	var step_m: float = Config.DEFAULTS["train_speed"] / 60.0
	var ahead := cl.sim.tick - server.sim.tick
	var expect := fposmod(server.sim.train_s + ahead * step_m, TrainTrack.LENGTH)
	var diff := minf(absf(cl.sim.train_s - expect), TrainTrack.LENGTH - absf(cl.sim.train_s - expect))
	check("train: the predicted train is where the server's would be at the client's tick (%d ticks ahead, off by %.4f m)" % [ahead, diff], diff < 0.01 and ahead >= 0 and ahead < 30)
	check("train: the client's step is one step of the server's speed", is_equal_approx(cl.sim.train_s - cl.sim.prev_train_s, step_m) or cl.sim.train_s < step_m)
	# the player is put on the rails in front of the locomotive; the kill must arrive as an event on the client
	var me := server.sim.players[cl.slot]
	me.pos = TrainTrack.point(server.sim.train_s + 3.5); me.prev_pos = me.pos
	var seen := []
	var errors_free := true
	for _t in 150:
		step_rig(rig, idle)
		for e: Dictionary in cl.events:
			if e["type"] == "kill":
				seen.append(e)
				errors_free = errors_free and e.has("pos") and e.has("victim") and e.has("killer")
	check("train: the server ran the player over (a death, no kill for anybody)", me.deaths == 1 and server.sim.players.all(func(p: SimPlayer) -> bool: return p.kills == 0))
	check("train: the kill arrives at the client as an event with killer -1 and cause train", seen.size() == 1 and seen[0]["killer"] == -1 and seen[0]["cause"] == "train" and seen[0]["victim"] == cl.slot and errors_free, str(seen))
	check("train: the client's own copy counts the death too", cl.sim.players[cl.slot].deaths == 1 and cl.sim.players[cl.slot].kills == 0)


# ---------------------------------------------------------------- prediction

func test_prediction() -> void:
	var rig := make_rig(100.0, 2.0, 1, 5)
	check("net: client joins over 100 ms / 2 % loss", warm_up(rig))
	var cl: ClientCore = rig["clients"][0]
	var server: ServerCore = rig["server"]
	check("net: gets slot 0 and the server config", cl.slot == 0 and cl.cfg != null and is_equal_approx(cl.cfg.player_speed, 6.0))
	var ref := Sim.new(cl.cfg, 1)
	ref.load_state(cl.sim.save_state())
	ref.apply_mods(0, Mods.empty_levels())
	var slot := cl.slot
	# This tests the prediction itself, not the server's adaptive input buffer (which starts small and may run dry
	# for a moment while it learns, see test_input_buffer): give the player a buffer that stays at 3.
	server.slots[slot].target = 3
	server.slots[slot].shrink_wait = 1 << 30
	var pred := {}
	var srv := {}
	var same_as_ref := true
	var first_diff := -1
	var diff_key := ""
	var max_corr := 0.0
	var reacted_move := false
	var reacted_throw := false
	var reacted_pull := false
	var server_lagged_throw := false
	var prev_consumed := 0
	var yo_seen := {}
	var total := 600
	for t in total:
		var input := scripted(0, t)
		var pos_before := cl.sim.players[slot].pos
		var hand_before := cl.sim.players[slot].hand_index()
		step_rig(rig, func(_k: int) -> SimInput: return input)
		ref.step([input, SimInput.new(), SimInput.new(), SimInput.new()])
		var me := cl.sim.players[slot]
		# (a) reaction on the same local tick
		if t % 300 == 5:
			reacted_move = me.pos != pos_before
		if t % 300 == 90:
			reacted_throw = hand_before >= 0 and me.hand_index() < 0 and me.ystate == Y.FLIGHT
			server_lagged_throw = server.sim.players[slot].hand_index() >= 0
		yo_seen[me.ystate] = true
		if t % 300 == 225 + int(cl.cfg.tap_threshold * 60.0) + 3:
			reacted_pull = reacted_pull or me.ystate == Y.PULL
		if state_without_tick(cl.sim) != state_without_tick(ref):
			same_as_ref = false
			if first_diff < 0:
				first_diff = t
				var a := cl.sim.save_state()
				var b := ref.save_state()
				for key: String in a:
					if var_to_bytes(a[key]) != var_to_bytes(b[key]) and key != "tick":
						diff_key = key
						if key == "players":
							for pi in 4:
								for f: String in a[key][pi]:
									if var_to_bytes(a[key][pi][f]) != var_to_bytes(b[key][pi][f]):
										diff_key += " p%d.%s %s vs %s" % [pi, f, str(a[key][pi][f]).left(60), str(b[key][pi][f]).left(60)]
		max_corr = maxf(max_corr, cl.correction)
		pred[cl.seq] = me.pos
		var lc: int = server.slots[slot].last_consumed
		if lc != prev_consumed:
			prev_consumed = lc
			srv[lc] = server.sim.players[slot].pos
	check("predict (a): own character moves on the very tick of the input", reacted_move)
	check("predict (a): the throw leaves the hand on the very tick of the release, the server does not know yet", reacted_throw and server_lagged_throw)
	check("predict (a): the pull starts on the tick the hold becomes a pull", yo_seen.has(Y.PULL) and reacted_pull)
	check("predict (a): the routine covers charge, flight, out, pull and retract", yo_seen.has(Y.CHARGING) and yo_seen.has(Y.FLIGHT) and yo_seen.has(Y.OUT) and yo_seen.has(Y.RETRACT), str(yo_seen.keys()))
	check("predict (a): client state equals a purely local sim on every tick (first diff tick %d %s)" % [first_diff, diff_key], same_as_ref)
	var compared := 0
	var mismatches := 0
	for s: int in srv:
		if pred.has(s):
			compared += 1
			if pred[s] != srv[s]:
				mismatches += 1
	check("predict (b): predicted position of input N equals the server's after N (%d compared)" % compared, compared > total * 0.9 and mismatches == 0, "mismatches=%d" % mismatches)
	check("predict (b): zero corrections without other players", max_corr == 0.0 and cl.snapshots_applied > 100, "max=%.4f applied=%d" % [max_corr, cl.snapshots_applied])
	check("predict: server never ran dry and the client has few unacknowledged inputs", server.underruns == 0 and cl.pending_inputs() > 0 and cl.pending_inputs() < 30, "underruns=%d pending=%d" % [server.underruns, cl.pending_inputs()])
	check("predict: ping estimate is about the round trip (200 ms + buffering)", cl.ping_ms > 190.0 and cl.ping_ms < 260.0, "ping=%.1f" % cl.ping_ms)


func test_two_clients() -> void:
	var rig := make_rig(100.0, 2.0, 2, 9)
	check("net: two clients join", warm_up(rig))
	var cs: Array = rig["clients"]
	var server: ServerCore = rig["server"]
	check("net: they get different slots", cs[0].slot != cs[1].slot and server.players_online() == 2)
	var sum_corr := 0.0
	var max_corr := 0.0
	var n := 0
	var max_pending := 0
	var kills := 0
	for t in 1500:
		step_rig(rig, func(k: int) -> SimInput: return duel(k, t))
		for k in 2:
			var c: ClientCore = cs[k]
			sum_corr += c.correction
			max_corr = maxf(max_corr, c.correction)
			n += 1
			max_pending = maxi(max_pending, c.pending_inputs())
			for e: Dictionary in c.events:
				if e["type"] == "kill":
					kills += 1
	for _t in 180:
		step_rig(rig, func(_k: int) -> SimInput: return SimInput.new())
	var conv := true
	var worst := 0.0
	for k in 2:
		var c: ClientCore = cs[k]
		for i in 4:
			var d := c.sim.players[i].pos.distance_to(server.sim.players[i].pos)
			worst = maxf(worst, d)
			if d > 0.001 or c.sim.players[i].alive != server.sim.players[i].alive or c.sim.players[i].enabled != server.sim.players[i].enabled:
				conv = false
	check("2 clients: they really interact (kills seen by the clients)", kills > 0, "kills=%d" % kills)
	check("2 clients: corrections stay bounded (avg %.3f m, max %.2f m)" % [sum_corr / n, max_corr], sum_corr / n < 0.1 and max_corr < 3.0)
	check("2 clients: unacknowledged inputs stay bounded", max_pending < 40, "max=%d" % max_pending)
	check("2 clients: after the inputs stop, both clients converge to the server (worst %.4f m)" % worst, conv)
	check("2 clients: server buffers stay bounded", server.stale_inputs == 0 and server.slots[0].buffer.size() <= ServerCore.MAX_BUFFER)


## Player B walks with direction changes, dashes several times and throws; player A stands and watches.
func other_script(t: int) -> SimInput:
	var ph := t % 240
	if ph < 40:
		return inp(Vector2(1.0, 0.0))
	if ph < 41:
		return inp(Vector2(1.0, 0.0), Vector2.ZERO, false, true)         # dash
	if ph < 70:
		return inp(Vector2(0.7, 0.7))
	if ph < 71:
		return inp(Vector2(0.7, 0.7), Vector2.ZERO, false, true)
	if ph < 100:
		return inp(Vector2(-0.6, -0.8))
	if ph < 125:
		return inp(Vector2.ZERO, Vector2(1.0, 0.0), true)                # charge, thrown at 125
	if ph < 150:
		return inp(Vector2(0.0, 1.0))
	if ph < 153:
		return inp(Vector2.ZERO, Vector2.ZERO, true)                     # tap: retract
	if ph < 190:
		return inp(Vector2(-1.0, 0.0))
	if ph < 191:
		return inp(Vector2(-1.0, 0.0), Vector2.ZERO, false, true)
	if ph < 215:
		return inp(Vector2(0.0, -1.0))
	return inp()


## What A's screen shows of B against B's true movement on the server. Returns the figures of the run.
func measure_other(delay_ms: float, loss: float, smooth: bool, ticks := 720, seed := 21) -> Dictionary:
	var rig := make_rig(delay_ms, loss, 2, seed)
	warm_up(rig)
	var a: ClientCore = rig["clients"][0]
	var b_slot: int = (rig["clients"][1] as ClientCore).slot
	var server: ServerCore = rig["server"]
	if a.get("smooth_others") != null:
		a.set("smooth_others", smooth)
	# Where B starts matters for the time matching below: wherever the scripted path doubles back on itself in the
	# open (the diagonal out, the diagonal back) or in a corner, the nearest true sample is ambiguous and a correct
	# picture can count as "back in time". In the 28 x 12.6 arena B spawned 2 m above the bottom wall and its loop
	# slid along that wall and a block; this start gives the same kind of loop in the 32 x 14.4 arena (along the
	# bottom wall, stopped by the box), clear of the corners.
	var bp: SimPlayer = server.sim.players[b_slot]
	bp.pos = Vector2(6.0, Config.ARENA_SIZE.y - 2.0)
	bp.prev_pos = bp.pos
	var shown_prev := Vector2.INF
	var true_prev := server.sim.players[b_slot].pos
	var d_prev := Vector2.ZERO
	var history: Array[Vector2] = []
	var matched := -1
	var max_jump := 0.0
	var max_true := 0.0
	var back := 0
	var jit_sum := 0.0
	var true_jit_sum := 0.0
	var n := 0
	var td_prev := Vector2.ZERO
	for t in ticks:
		step_rig(rig, func(k: int) -> SimInput: return inp() if k == 0 else other_script(t))
		var tp := server.sim.players[b_slot].pos
		var td := tp - true_prev
		true_prev = tp
		var shown: Vector2 = a.displayed_pos(b_slot, 0.5)
		if t < 120:
			shown_prev = shown
			continue
		var d := shown - shown_prev
		shown_prev = shown
		history.append(tp)
		max_jump = maxf(max_jump, d.length())
		max_true = maxf(max_true, td.length())
		# Which moment of B's true path does the picture show? (the sample nearest to the displayed spot, the
		# one closest to the previous match among equals). Going back in time by more than 2 ticks is a backward jump.
		var lo := maxi(0, matched - 40)
		var best := INF
		for k in range(lo, history.size()):
			best = minf(best, history[k].distance_to(shown))
		var pick := -1
		for k in range(lo, history.size()):
			if history[k].distance_to(shown) <= best + 0.001 and (pick < 0 or absi(k - matched) < absi(pick - matched)):
				pick = k
		if matched >= 0 and pick < matched - 2:
			back += 1
		matched = maxi(matched, 0) if pick < 0 else pick
		jit_sum += (d - d_prev).length()
		true_jit_sum += (td - td_prev).length()
		d_prev = d
		td_prev = td
		n += 1
	return {"max_jump": max_jump, "max_true": max_true, "ratio": max_jump / max_true, "back": back,
			"jitter": jit_sum / n, "true_jitter": true_jit_sum / n}


func test_other_display() -> void:
	var worst_ratio := 0.0
	var worst_back := 0
	var worst_jit := 0.0
	var line := ""
	for delay in [0.0, 20.0, 50.0]:
		for loss in [0.0, 2.0]:
			var m := measure_other(delay, loss, true)
			worst_ratio = maxf(worst_ratio, m["ratio"])
			worst_back = maxi(worst_back, m["back"])
			worst_jit = maxf(worst_jit, m["jitter"] / m["true_jitter"])
			line += " %d/%d:%.2f" % [delay, loss, m["ratio"]]
	check("other display: no jump bigger than the true movement (worst ratio %.2f; delay/loss:%s)" % [worst_ratio, line], worst_ratio < 1.3)
	check("other display: never goes back in time (0, 20, 50 ms, 0 and 2 % loss)", worst_back == 0, "back=%d" % worst_back)
	check("other display: as smooth as the true path (worst jitter %.2fx the true one)" % worst_jit, worst_jit < 1.5)
	# the old display (switch off) is what the owner saw: it must fail the same measures
	var old := measure_other(20.0, 0.0, false)
	check("other display: switch off gives the old, jumpy picture (ratio %.2f, jitter %.1fx)" % [old["ratio"], old["jitter"] / old["true_jitter"]], old["ratio"] > 2.0 and old["jitter"] / old["true_jitter"] > 3.0)
	print("INFO  old display 20 ms: jump %.2f m (true %.2f), jitter %.4f (true %.4f)" % [old["max_jump"], old["max_true"], old["jitter"], old["true_jitter"]])


# ---------------------------------------------------------------- chosen figure

func test_skin() -> void:
	var rig := make_rig(0.0, 0.0, 2, 3)
	var a: ClientCore = rig["clients"][0]
	var b: ClientCore = rig["clients"][1]
	var pick := Config.SKIN_COUNT - 1
	a.set_skin(pick)
	warm_up(rig)
	for _t in 30:
		step_rig(rig, func(_k: int) -> SimInput: return SimInput.new())
	var server: ServerCore = rig["server"]
	check("figure: the choice reaches the server's slot", server.sim.players[a.slot].skin == pick)
	check("figure: the chooser sees it on their own predicted player", a.sim.players[a.slot].skin == pick)
	check("figure: the other client sees it through the snapshot", b.sim.players[a.slot].skin == pick)
	check("figure: a client that never chose keeps the default (slot)", server.sim.players[b.slot].skin == b.slot % Config.SKIN_COUNT and b.sim.players[b.slot].skin == b.slot % Config.SKIN_COUNT)
	a.set_skin(2)
	for _t in 30:
		step_rig(rig, func(_k: int) -> SimInput: return SimInput.new())
	check("figure: a change travels again", server.sim.players[a.slot].skin == 2 and b.sim.players[a.slot].skin == 2)
	check("figure: out-of-range choices on the client wrap into range", (func() -> bool:
		a.set_skin(Config.SKIN_COUNT * 4 + 3)
		return a._wanted_skin == 3).call())


func test_skin_delayed() -> void:
	# with a slow link the own choice must show at once and survive snapshots that still carry the old one
	var rig := make_rig(200.0, 0.0, 1, 3)
	var a: ClientCore = rig["clients"][0]
	warm_up(rig)
	for _t in 30:
		step_rig(rig, func(_k: int) -> SimInput: return SimInput.new())
	var pick := (a.slot + 1) % Config.SKIN_COUNT
	a.set_skin(pick)
	step_rig(rig, func(_k: int) -> SimInput: return SimInput.new())
	check("figure: the own choice shows on the predicted player at once", a.sim.players[a.slot].skin == pick)
	var server: ServerCore = rig["server"]
	var kept := true
	for _t in 8:
		step_rig(rig, func(_k: int) -> SimInput: return SimInput.new())
		kept = kept and a.sim.players[a.slot].skin == pick
	check("figure: old snapshots do not flip it back before the server knows", kept and server.sim.players[a.slot].skin != pick)


# ---------------------------------------------------------------- repeated one-shot inputs

func test_one_shot_inputs() -> void:
	var i := inp(Vector2(0.5, 0.2), Vector2(0.0, 1.0), true, true)
	var r := i.repeated()
	check("repeated input: sticks are kept, the dash is not", r.move == i.move and r.aim == i.aim and r.aim_held and not r.dash and i.dash)
	# server: the last dash input is consumed, then the client falls silent and the server repeats the input
	var rig := make_rig(0.0, 0.0, 1, 3)
	var c: ClientCore = rig["clients"][0]
	c.set_mods({"extradash": 1})
	warm_up(rig)
	for _t in 20:
		step_rig(rig, func(_k: int) -> SimInput: return SimInput.new())
	var server: ServerCore = rig["server"]
	var me := server.sim.players[c.slot]
	var charges_before := me.dash_charges
	step_rig(rig, func(_k: int) -> SimInput: return inp(Vector2.RIGHT, Vector2.ZERO, false, true))
	for _t in 40:                                  # the client stops sending
		(rig["hub"] as LoopbackHub).advance(DT_MS)
		server.tick()
	check("server: a dash input repeated on an underrun does not dash again (charges %d -> %d)" % [charges_before, me.dash_charges], charges_before == 2 and me.dash_charges == 1 and server.underruns > 20, "underruns=%d" % server.underruns)
	# client: the snapshot carries a dash of player 1; the extrapolation must not dash again
	var fs := fake_server_setup()
	var cl: ClientCore = fs["client"]
	var s := Sim.new(fs["cfg"], 1)
	for k in 4:
		s.set_player_enabled(k, k < 2)
		s.players[k].alive = true
	s.crate_pos = Vector2(-50, -50)
	s.box_active = false
	s.box_timer = 9999.0
	s.apply_mods(1, {"extradash": 1})
	s.players[1].pos = Vector2(8.0, 6.3)
	s.players[1].prev_pos = s.players[1].pos
	var dash := inp(Vector2.RIGHT, Vector2.ZERO, false, true)
	s.step([SimInput.new(), dash, SimInput.new(), SimInput.new()])
	check("client test setup: the dash started and one of two charges is spent", s.players[1].dash_t > 0.0 and s.players[1].dash_charges == 1)
	s.tick = 100
	var enc: Array = []
	for k in 4:
		enc.append(NetProto.encode_input(dash if k == 1 else SimInput.new()))
	var body := NetProto.snapshot_body(enc, s.save_state())
	(fs["hub"] as LoopbackHub).server.send(1, NetProto.snapshot_packet(100, 0, body), false)
	(fs["hub"] as LoopbackHub).advance(1.0)
	cl.poll()
	for _t in 25:
		cl.tick(SimInput.new())
	check("client: the dash of another player is not repeated while extrapolating (charges left %d)" % cl.sim.players[1].dash_charges, cl.sim.players[1].dash_charges == 1)


# ---------------------------------------------------------------- interpolated display

const IP_V := 0.1          # metres per tick of player 1 in the interpolation tests

func interp_world(s: Sim, tick_no: int) -> void:
	var d := float(tick_no - 100)
	var p := s.players[1]
	p.pos = Vector2(5.0 + IP_V * d, 6.3)
	p.prev_pos = Vector2(p.pos.x - IP_V, p.pos.y)
	var h := p.heads[0]
	h.state = SimHead.S.FLIGHT
	h.pos = Vector2(5.0 + 3.0 * IP_V * d, 7.3)
	h.prev_pos = Vector2(h.pos.x - 3.0 * IP_V, h.pos.y)
	s.shards.clear()
	var sh := SimShard.new()
	sh.owner_id = 1
	sh.pos = Vector2(3.0 + 2.0 * IP_V * d, 9.0)
	sh.prev_pos = Vector2(sh.pos.x - 2.0 * IP_V, sh.pos.y)
	s.shards.append(sh)
	s.tick = tick_no


func interp_setup() -> Dictionary:
	var fs := fake_server_setup()
	var s := Sim.new(fs["cfg"], 1)
	for k in 4:
		s.set_player_enabled(k, k < 2)
		s.players[k].alive = true
	s.crate_pos = Vector2(-50, -50)
	s.box_active = false
	s.box_timer = 9999.0
	fs["sim"] = s
	return fs


## Server tick `tick_no` arrives at the client.
func feed(fs: Dictionary, tick_no: int) -> void:
	interp_world(fs["sim"], tick_no)
	send_snapshot(fs, fs["sim"], tick_no, 0)


func test_interpolation() -> void:
	var fs := interp_setup()
	var cl: ClientCore = fs["client"]
	cl.predict_heads = false     # this tests the interpolation itself; the fake server's yo-yos are not what the client predicts
	feed(fs, 100)
	check("interp: before the first snapshot is used, a single snapshot is held", cl.displayed_pos(1, 0.5).x == 5.0 and cl.display_sim != null)
	var px: Array[float] = []
	var hx: Array[float] = []
	var sx: Array[float] = []
	var lag_ok := true
	var clock: Array[float] = []
	var tick_no := 100
	for n in 120:
		tick_no += 2
		feed(fs, tick_no)
		for _k in 2:
			cl.tick(SimInput.new())
			clock.append(cl._render_t)
			if n > 20:
				px.append(cl.displayed_pos(1, 0.5).x)
				hx.append(cl.display_sim.players[1].heads[0].prev_pos.lerp(cl.display_sim.players[1].heads[0].pos, cl.display_alpha).x)
				var sh := cl.display_sim.shards[0]
				sx.append(sh.prev_pos.lerp(sh.pos, cl.display_alpha).x)
				var behind: float = (5.0 + IP_V * (tick_no - 100) - px.back()) / IP_V
				lag_ok = lag_ok and behind > 2.0 and behind < 7.0
	var worst_p := 0.0
	var worst_h := 0.0
	var worst_s := 0.0
	for k in range(1, px.size()):
		worst_p = maxf(worst_p, absf(px[k] - px[k - 1] - IP_V))
		worst_h = maxf(worst_h, absf(hx[k] - hx[k - 1] - 3.0 * IP_V))
		worst_s = maxf(worst_s, absf(sx[k] - sx[k - 1] - 2.0 * IP_V))
	check("interp: the other player moves evenly every tick (worst deviation %.4f m of %.2f)" % [worst_p, IP_V], worst_p < 0.02)
	check("interp: their yo-yo head moves evenly (worst deviation %.4f m)" % worst_h, worst_h < 0.06)
	check("interp: their shards move evenly (worst deviation %.4f m)" % worst_s, worst_s < 0.04)
	check("interp: the picture runs about 2 snapshot intervals behind", lag_ok)
	var step_ok := true
	for k in range(1, clock.size()):
		var d := clock[k] - clock[k - 1]
		step_ok = step_ok and d > 0.74 and d < 1.26
	check("interp: the render clock only runs 0.75x to 1.25x, it never jumps or goes back", step_ok)
	check("interp: the own player is drawn from the predicted sim", cl.displayed_pos(0, 0.5) == cl.sim.players[0].prev_pos.lerp(cl.sim.players[0].pos, 0.5))
	cl.smooth_others = false
	check("interp: switched off there is no display sim and the predicted sim is used", cl.displayed_pos(1, 1.0) == cl.sim.players[1].pos and cl.display_sim == null)
	cl.smooth_others = true

	# buffer runs dry: hold at the newest state, never past it and never back
	var newest_x := 5.0 + IP_V * (tick_no - 100)
	var last := cl.displayed_pos(1, 0.5).x
	var dry_ok := true
	for _t in 14:
		cl.tick(SimInput.new())
		var x := cl.displayed_pos(1, 0.5).x
		dry_ok = dry_ok and x >= last - 0.0001 and x <= newest_x + 0.0001
		last = x
	check("interp: when snapshots stop the picture holds the newest state (x %.2f of %.2f)" % [last, newest_x], dry_ok and is_equal_approx(last, newest_x))
	# they come back (7 server ticks of them at once): no step back
	var back_ok := true
	var jump := 0.0
	for _k in 7:
		tick_no += 2
		feed(fs, tick_no)
		var x := cl.displayed_pos(1, 0.5).x
		back_ok = back_ok and x >= last - 0.0001
		jump = maxf(jump, x - last)
		last = x
	check("interp: when snapshots resume the picture does not step back", back_ok, "max step %.2f" % jump)

	# a teleport (respawn) is shown as one jump, not as a slide across the arena
	var fs3 := interp_setup()
	var c3: ClientCore = fs3["client"]
	var t3 := 100
	var shift := 0.0
	var xs3: Array[float] = []
	feed(fs3, t3)
	for n in 60:
		t3 += 2
		if n == 30:
			shift = 12.0
		interp_world(fs3["sim"], t3)
		var pl: SimPlayer = (fs3["sim"] as Sim).players[1]
		pl.pos.x += shift
		pl.prev_pos.x += shift
		send_snapshot(fs3, fs3["sim"], t3, 0)
		for _k in 2:
			c3.tick(SimInput.new())
			xs3.append(c3.displayed_pos(1, 0.5).x)
	var big := 0
	var between := 0
	var before_x := 5.0 + IP_V * 60.0          # about where the player is when the teleport happens
	for k in range(1, xs3.size()):
		if xs3[k] - xs3[k - 1] > 2.0:
			big += 1
		if xs3[k] > before_x + 1.5 and xs3[k] < before_x + shift - 1.5:
			between += 1
	check("interp: a teleport is one jump and nothing is drawn in between (jumps %d, in between %d)" % [big, between], big == 1 and between == 0)

	# late snapshots make the delay grow, then it shrinks back slowly; the clock never jumps meanwhile
	var fs4 := interp_setup()
	var c4: ClientCore = fs4["client"]
	var t4 := 100
	feed(fs4, t4)
	var base := c4.interp_delay_ms()
	var clk: Array[float] = []
	for n in 30:
		t4 += 2
		feed(fs4, t4)
		for _k in 2:
			c4.tick(SimInput.new())
			clk.append(c4._render_t)
	var steady := c4.interp_delay_ms()
	for _k in 8:                                    # a stall of 8 ticks, then 4 snapshots at once
		c4.tick(SimInput.new())
		clk.append(c4._render_t)
	for _k in 4:
		t4 += 2
		feed(fs4, t4)
	var grown := c4.interp_delay_ms()
	var clk_ok := true
	for k in range(1, clk.size()):
		clk_ok = clk_ok and clk[k] - clk[k - 1] > 0.74 and clk[k] - clk[k - 1] < 1.26
	for n in 40:
		t4 += 2
		feed(fs4, t4)
		for _k in 2:
			c4.tick(SimInput.new())
			clk.append(c4._render_t)
			clk_ok = clk_ok and clk[-1] - clk[-2] > 0.74 and clk[-1] - clk[-2] < 1.26
	var after_80 := c4.interp_delay_ms()
	c4._extra = ClientCore.INTERP_EXTRA_MAX            # without snapshots (cheap): it must find its way back
	for _n in 2000:
		c4.tick(SimInput.new())
	var settled := c4.interp_delay_ms()
	check("interp: base delay is 4 ticks (%.1f ms)" % base, absf(base - 4.0 * 1000.0 / 60.0) < 0.1 and absf(steady - base) < 0.1)
	check("interp: late snapshots grow the delay (%.0f -> %.0f ms)" % [steady, grown], grown > steady + 50.0)
	check("interp: it shrinks back slowly, not at once (%.0f ms after 80 ticks, %.0f from the maximum after 2000)" % [after_80, settled], after_80 > steady + 25.0 and absf(settled - steady) < 20.0)
	check("interp: the clock keeps its pace while the delay changes", clk_ok)
	# a client clock 1 % faster than the server's must not make the delay creep up
	var fs6 := interp_setup()
	var c6: ClientCore = fs6["client"]
	feed(fs6, 100)
	var st6: Dictionary = (fs6["sim"] as Sim).save_state()
	var sv := 100.0
	var next_snap := 102
	for _n in 3000:
		c6.tick(SimInput.new())
		sv += 0.99
		while sv >= float(next_snap):
			c6._buffer_snapshot(next_snap, st6)
			next_snap += 2
	check("interp: a client clock 1 %% fast does not make the delay creep up (%.0f ms)" % c6.interp_delay_ms(), c6.interp_delay_ms() < base + 40.0)
	# lost snapshots (a gap) grow it as well
	var fs5 := interp_setup()
	var c5: ClientCore = fs5["client"]
	var t5 := 100
	feed(fs5, t5)
	for n in 20:
		t5 += 2
		feed(fs5, t5)
		for _k in 2:
			c5.tick(SimInput.new())
	var before5 := c5.interp_delay_ms()
	t5 += 8                                         # three snapshots lost: the next one is 8 ticks after the last
	for _k in 6:
		c5.tick(SimInput.new())
	feed(fs5, t5)
	check("interp: lost snapshots grow the delay (%.0f -> %.0f ms)" % [before5, c5.interp_delay_ms()], c5.interp_delay_ms() > before5 + 30.0)


# ---------------------------------------------------------------- the victim sees the head arrive

## What the others do in the "hit" scenarios. A (client 0) always stands still; B (client 1) aims at -x.
## "flight": the thrown head flies through A. "retract": the head lands, B walks diagonally and calls it back, the
## way home leads through A (who stands beside the way out). "shard": the head lands, B calls it back with the
## shards mod, one of the shards flies at A.
func hit_script(scn: String, t: int) -> SimInput:
	var aim := Vector2(-1.0, 0.0)
	if t >= 10 and t < 100:
		return inp(Vector2.ZERO, aim, true)                                  # charge, thrown at 100
	if scn == "retract":
		if t >= 140 and t < 162:
			return inp(Vector2(-0.447, -0.894))
		if t >= 170 and t < 173:
			return inp(Vector2.ZERO, Vector2.ZERO, true)                     # tap: retract
	if scn == "shard" and t >= 150 and t < 153:
		return inp(Vector2.ZERO, Vector2.ZERO, true)
	return inp()


## Positions in the lower right part of the arena, clear of the blocks (written for the 28 x 12.6 arena and moved
## along with its lower right corner when it grew to 32 x 14.4).
const HIT_SHIFT := Vector2(4.0, 1.8)
const HIT_SCENARIOS := {
	"flight": [Vector2(19.0, 11.0) + HIT_SHIFT, Vector2(25.0, 11.0) + HIT_SHIFT],
	"retract": [Vector2(21.0, 4.86) + HIT_SHIFT, Vector2(25.0, 6.0) + HIT_SHIFT],
	"shard": [Vector2(18.5, 8.6) + HIT_SHIFT, Vector2(25.0, 6.0) + HIT_SHIFT],
}


## B throws at the standing A. The gap is, on A's screen, the distance between the drawn enemy head (or shard) and
## the drawn A, minus the hit distance: 0 = touching, positive = the killer has not arrived yet. Measured on the
## local tick on which A's client learns of its death ("learn"), and on the tick of A's own time that the server
## was at when it killed A ("server": the input number the server had consumed, which is A's local tick).
func measure_hit(scn: String, delay_ms: float, loss: float, predict := true, seed := 31) -> Dictionary:
	var rig := make_rig(delay_ms, loss, 2, seed)
	warm_up(rig)
	var a: ClientCore = rig["clients"][0]
	var b: ClientCore = rig["clients"][1]
	var server: ServerCore = rig["server"]
	if not predict:
		a.set("predict_heads", false)       # (on is the default)
	var sa := a.slot
	var sb := b.slot
	for k in 2:
		var p: SimPlayer = server.sim.players[[sa, sb][k]]
		p.pos = (HIT_SCENARIOS[scn][k] as Vector2)
		p.prev_pos = p.pos
	if scn == "shard":
		var m := Mods.empty_levels()
		m["shards"] = 1
		b.set_mods(m)
	for _t in 60:
		step_rig(rig, func(_k: int) -> SimInput: return inp())    # let the clients take the new positions
	var gaps := {}                 # A's local tick (input number) -> gap
	var learn_gap := INF
	var server_gap := INF
	var server_seq := -1
	var kill_state := -1
	var pr := a.cfg.player_radius
	var first_local := 0
	for t in 330:
		if learn_gap != INF and server_seq >= 0:
			break
		step_rig(rig, func(k: int) -> SimInput: return hit_script(scn, t) if k == 1 else inp())
		var mine: Vector2 = a.sim.players[sa].prev_pos.lerp(a.sim.players[sa].pos, 0.5)
		var gap := INF
		for k in a.sim.players[sb].heads.size():
			var h := a.displayed_head_pos(sb, k, 0.5)
			gap = minf(gap, h.distance_to(mine) - (a.cfg.head_radius + pr))
		for sh: Dictionary in a.displayed_other_shards(0.5):
			gap = minf(gap, (sh["pos"] as Vector2).distance_to(mine) - ((sh["radius"] as float) + pr))
		gaps[a.seq] = gap
		if learn_gap == INF and not a.sim.players[sa].alive:
			learn_gap = gap
			first_local = t
		if server_seq < 0 and not server.sim.players[sa].alive:
			server_seq = server.slots[sa].last_consumed
			for h in server.sim.players[sb].heads:
				kill_state = h.state
			if server.sim.events.size() > 0 and kill_state != SimHead.S.HAND:
				pass
	if server_seq >= 0:
		server_gap = gaps.get(server_seq, INF)
	return {"killed": learn_gap != INF and server_seq >= 0, "learn": learn_gap, "server": server_gap, "state": kill_state,
			"learn_tick": first_local}


func test_victim_sees_arrival() -> void:
	var worst_near := -INF       # 0 and 20 ms per direction
	var worst_far := -INF        # 50 ms per direction
	var best_old := INF
	var min_gap := INF
	var line := ""
	var all_killed := true
	var info_old := ""
	var states := {}
	for scn in ["flight", "retract", "shard"]:
		for delay in [0.0, 20.0, 50.0]:
			for loss in [0.0, 2.0]:
				var m := measure_hit(scn, delay, loss)
				var o := measure_hit(scn, delay, loss, false) if loss == 0.0 else m
				all_killed = all_killed and m["killed"] and o["killed"]
				var worst := maxf(m["learn"], m["server"] if scn != "shard" else -INF)   # a shard's origin (the tap) is not known earlier
				if delay <= 20.0:
					worst_near = maxf(worst_near, maxf(m["learn"], m["server"]))
				else:
					worst_far = maxf(worst_far, worst)
				min_gap = minf(min_gap, m["learn"])
				if loss == 0.0:
					best_old = minf(best_old, maxf(o["learn"], o["server"]))
				if scn != "shard":
					states[scn] = m["state"]
				line += " %s %d/%d:%.2f|%.2f" % [scn.left(2), delay, loss, m["learn"], m["server"]]
				if loss == 0.0:
					info_old += " %s %d/%d:%.2f|%.2f" % [scn.left(2), delay, loss, o["learn"], o["server"]]
	print("INFO  hit gap new (learn|server, m):" + line)
	print("INFO  hit gap old (learn|server, m):" + info_old)
	check("hit scenarios: A is killed in every scenario and setting", all_killed)
	check("hit scenarios: the retract scenario kills with a retracting head, the flight one with a flying head", states["retract"] == SimHead.S.RETRACT and states["flight"] == SimHead.S.FLIGHT, str(states))
	check("victim sees the arrival: at 0 and 20 ms per direction the killer is within %.2f m of touching when the death is learned / was decided" % worst_near, worst_near < 0.5)
	check("victim sees the arrival: at 50 ms per direction within %.2f m (the head is thrown less than a ping before it hits; old display at least %.1f m)" % [worst_far, best_old], worst_far < 2.0)
	check("victim sees the arrival: the killer is never drawn far past the victim (%.2f m)" % min_gap, min_gap > -0.6)


# ---------------------------------------------------------------- predicted enemy heads: no pops

func send_snapshot_inputs(fs: Dictionary, state: Sim, tick_no: int, acked: int, inputs: Array) -> void:
	var enc: Array = []
	for i in 4:
		enc.append(NetProto.encode_input(inputs[i]))
	var body := NetProto.snapshot_body(enc, state.save_state())
	(fs["hub"] as LoopbackHub).server.send(1, NetProto.snapshot_packet(tick_no, acked, body), false)
	(fs["hub"] as LoopbackHub).advance(1.0)
	(fs["client"] as ClientCore).poll()


## B (slot 1) of a scripted server charges and throws (tick 20), taps to retract (tick 80). `event` is Callable(n, sim)
## and may meddle with the server sim before the tick's snapshot (a wrong prediction, a teleport, a kill).
## Returns the per-tick series of how the head of B is drawn on A's screen against the predicted sim.
const HEAD_LAT := 6   # ticks (100 ms) between the server and the client in the scripted server


func run_head_script(event: Callable, ticks := 190, predict := true, charge_until := 40) -> Dictionary:
	var fs := interp_setup()
	var cl: ClientCore = fs["client"]
	if not predict:
		cl.predict_heads = false      # (on is the default and is what the other runs use)
	var s: Sim = fs["sim"]
	s.players[0].pos = Vector2(3.0, 11.0)
	s.players[1].pos = Vector2(8.0, 11.0)
	for k in 2:
		s.players[k].prev_pos = s.players[k].pos
		s.players[k].facing = Vector2.RIGHT
	var disp: Array[Vector2] = []
	var pred: Array[Vector2] = []
	var hand: Array[bool] = []
	var body_hand: Array[Vector2] = []   # where the hand of B's drawn body is
	var first := true
	var hist := {}                 # server tick -> [state, inputs]: the snapshots reach the client LAT ticks late
	for n in ticks:
		var b := inp()
		if n >= 4 and n < charge_until:
			b = inp(Vector2.ZERO, Vector2(1.0, 0.0), true)
		elif n >= 100 and n < 103:
			b = inp(Vector2.ZERO, Vector2.ZERO, true)
		var ins := [inp(), b, inp(), inp()]
		s.step(ins)
		event.call(n, s)
		hist[s.tick] = [s.save_state(), ins]
		if s.tick % 2 == 0 and hist.has(s.tick - HEAD_LAT):
			var old := Sim.new(cl.cfg, 1)
			old.load_state(hist[s.tick - HEAD_LAT][0])
			send_snapshot_inputs(fs, old, old.tick, cl.seq - HEAD_LAT if not first else 0, hist[s.tick - HEAD_LAT][1])
			if first:
				first = false
				continue
		if first:
			continue
		cl.tick(inp())
		var ph := cl.sim.players[1].heads[0]
		disp.append(cl.displayed_head_pos(1, 0, 0.5))
		pred.append(ph.prev_pos.lerp(ph.pos, 0.5) if ph.state != SimHead.S.HAND else ClientCore._hand_pos(cl.sim, cl.sim.players[1], cl.sim.players[1].prev_pos.lerp(cl.sim.players[1].pos, 0.5)))
		hand.append(ph.state == SimHead.S.HAND)
		var dp := cl.display_sim.players[1]
		body_hand.append(ClientCore._hand_pos(cl.display_sim, dp, dp.prev_pos.lerp(dp.pos, cl.display_alpha)))
	return {"disp": disp, "pred": pred, "hand": hand, "body_hand": body_hand, "cl": cl, "server": s}


func test_predicted_heads() -> void:
	var catch_up := ClientCore.HEAD_CATCHUP_TICKS
	check("predicted heads: drawing the enemy heads from the predicted sim is the default", fake_server_setup()["client"].predict_heads)
	var normal := func(_n: int, _s: Sim) -> void: pass
	var r := run_head_script(normal)
	var disp: Array[Vector2] = r["disp"]
	var pred: Array[Vector2] = r["pred"]
	var hand: Array[bool] = r["hand"]
	# (1) the throw: the head first appears where the (interpolated) hand is and slides to the predicted path
	var thrown := -1
	for k in hand.size():
		if not hand[k]:
			thrown = k
			break
	var off0 := disp[thrown].distance_to(pred[thrown]) if thrown >= 0 else 0.0
	var mono := true
	for k in range(thrown + 1, thrown + catch_up):
		mono = mono and disp[k].distance_to(pred[k]) <= disp[k - 1].distance_to(pred[k - 1]) + 0.001
	check("predicted heads: the thrown head is first drawn at the hand and not at the predicted place (offset %.2f m)" % off0, thrown > 0 and off0 > 0.3)
	check("predicted heads: the offset shrinks every tick and is gone after %d ticks (then %.4f m)" % [catch_up, disp[thrown + catch_up].distance_to(pred[thrown + catch_up])], mono and disp[thrown + catch_up].distance_to(pred[thrown + catch_up]) < 0.001)
	var worst_step := 0.0
	var plain_step := 0.0
	for k in range(1, disp.size()):
		if hand[k] or hand[k - 1]:
			continue
		worst_step = maxf(worst_step, disp[k].distance_to(disp[k - 1]))
	check("predicted heads: the head never jumps (largest one-tick step %.2f m, flight speed %.2f m)" % [worst_step, r["cl"].cfg.flight_speed / 60.0], worst_step < r["cl"].cfg.flight_speed / 60.0 + off0 / catch_up + 0.05)
	# (2) after the first few ticks the head is exactly on the predicted path; on its way home and in the hand again too
	var exact := true
	var back_in_hand := -1
	for k in range(thrown + catch_up + 1, disp.size()):
		if hand[k]:
			back_in_hand = k
			break
		exact = exact and (disp[k].distance_to(pred[k]) < 0.001 or k >= 96)   # (the tap at 100 reaches the client late: the retract is predicted wrong for a moment)
	check("predicted heads: flight and landing are drawn exactly where the predicted sim has them", exact and back_in_hand > 0, "back in hand at %d" % back_in_hand)
	var after_ok := true
	for k in range(back_in_hand + catch_up + 1, disp.size()):
		after_ok = after_ok and disp[k].distance_to(pred[k]) < 0.001
	check("predicted heads: back in the hand the head is drawn at the hand again after the catch-up", after_ok and back_in_hand > 0)

	# (3) a snapshot corrects the predicted head by 1 m: the drawn head slides instead of popping
	var shift := func(n: int, sv: Sim) -> void:
		if n == 50:
			var h := sv.players[1].heads[0]
			h.pos.x += 1.0
			h.prev_pos.x += 1.0
	var cfg_step: float = r["cl"].cfg.flight_speed / 60.0
	var c := run_head_script(shift)
	var cd: Array[Vector2] = c["disp"]
	var cp: Array[Vector2] = c["pred"]
	var jump := 0.0
	var gap_max := 0.0
	var k_gap := -1
	var k_c := -1
	for k in range(thrown + catch_up + 2, 90):
		if k_c < 0 and absf((cp[k] - cp[k - 1]).length() - cfg_step) > 0.5:
			k_c = k
		if k_c < 0 or k > k_c + 8:
			continue
		jump = maxf(jump, ((cd[k] - disp[k]) - (cd[k - 1] - disp[k - 1])).length())   # against the run without the correction
		if cd[k].distance_to(cp[k]) > gap_max:
			gap_max = cd[k].distance_to(cp[k])
			k_gap = k
	var settle := -1
	for k in range(maxi(k_gap, 0), 90):
		if cd[k].distance_to(cp[k]) < 0.001:
			settle = k
			break
	check("predicted heads: a 1 m correction of the head slides (largest one-tick shift against the run without the correction %.2f m, drawn at most %.2f m from the predicted place)" % [jump, gap_max], gap_max > 0.5 and gap_max <= 1.001 and jump < 1.0 / catch_up + 0.03)
	check("predicted heads: ... and is settled %d ticks after the correction" % (settle - k_gap), settle > 0 and settle - k_gap <= catch_up + 1)
	# (4) a teleport (more than HEAD_MAX_OFFSET) is not slid over
	var tele := func(n: int, sv: Sim) -> void:
		if n == 50:
			var h := sv.players[1].heads[0]
			h.pos.x += ClientCore.HEAD_MAX_OFFSET + 3.0
			h.prev_pos.x += ClientCore.HEAD_MAX_OFFSET + 3.0
	var tp := run_head_script(tele)
	var td: Array[Vector2] = tp["disp"]
	var tpd: Array[Vector2] = tp["pred"]
	var k_t := -1
	for k in range(thrown + catch_up + 2, tpd.size()):
		if tpd[k].distance_to(tpd[k - 1]) > 4.0:
			k_t = k
			break
	check("predicted heads: a teleport of the head is drawn at once (%.4f m off in the frame it happens)" % (td[k_t].distance_to(tpd[k_t]) if k_t > 0 else -1.0), k_t > 0 and td[k_t].distance_to(tpd[k_t]) < 0.001)
	# (5) a kill and a respawn: the head of the respawned player is in the hand, nothing slides over from before
	var kill := func(n: int, sv: Sim) -> void:
		if n == 60:
			sv._kill(sv.players[1], sv.players[0])
		if n == 70:
			sv._respawn(sv.players[1])
			sv.players[1].pos = Vector2(8.0, 11.0)
			sv.players[1].prev_pos = Vector2(8.0, 11.0)
	var kr := run_head_script(kill, 190, true, 24)     # a short throw: the head dies within the 6 m a slide may cover
	var kd: Array[Vector2] = kr["disp"]
	var kp: Array[Vector2] = kr["pred"]
	var respawn_off := 0.0
	var kh: Array[Vector2] = kr["body_hand"]
	for k in range(68, 110):
		respawn_off = maxf(respawn_off, kd[k].distance_to(kh[k]))
	check("predicted heads: after a kill and a respawn the head is drawn in the hand of the drawn body, nothing slides over from before (%.4f m off)" % respawn_off, respawn_off < 0.001 and kr["hand"][100])
	# (5b) the string bends where the predicted head bounced: the pins of the predicted head are drawn
	var pinned := run_head_script(normal, 56)
	var pcl: ClientCore = pinned["cl"]
	var pin_head := pcl.sim.players[1].heads[0]
	pin_head.pins = PackedVector2Array([Vector2(10.0, 11.0), Vector2(11.0, 9.0)])
	pcl.prepare_display(0.5)
	var shown_pins := pcl.display_sim.players[1].heads[0].pins
	check("predicted heads: the drawn string goes through the pins of the predicted head", pin_head.state != SimHead.S.HAND and shown_pins == pin_head.pins, str(shown_pins))
	# (6) the switch off gives the old picture: the head is on the interpolated path, the predicted sim is not used
	var old := run_head_script(normal, 190, false)
	var od: Array[Vector2] = old["disp"]
	var op: Array[Vector2] = old["pred"]
	var far := 0.0
	for k in range(thrown, thrown + 20):
		far = maxf(far, od[k].distance_to(op[k]))
	check("predicted heads: predict_heads off draws the heads from the interpolation, in the past (%.2f m behind the predicted head)" % far, far > 1.0)
	var raw := run_head_script(normal)
	var rcl: ClientCore = raw["cl"]
	rcl.smooth_others = false
	var sim_head := rcl.sim.players[1].heads[0]
	check("predicted heads: 'Smooth others' off draws the raw predicted path", rcl.displayed_head_pos(1, 0, 1.0) == (sim_head.pos if sim_head.state != SimHead.S.HAND else ClientCore._hand_pos(rcl.sim, rcl.sim.players[1], rcl.sim.players[1].pos)) and rcl.display_sim == null)


# ---------------------------------------------------------------- server input buffer

## Two clients duel; returns how far the snapshots moved the predicted own position and how long the inputs waited.
func measure_buffer(delay_ms: float, loss: float, ticks := 1500, seed := 9) -> Dictionary:
	var rig := make_rig(delay_ms, loss, 2, seed)
	warm_up(rig)
	var cs: Array = rig["clients"]
	var server: ServerCore = rig["server"]
	var sum_corr := 0.0
	var big := 0
	var n := 0
	for t in ticks:
		step_rig(rig, func(k: int) -> SimInput: return duel(k, t))
		for k in 2:
			var c: ClientCore = cs[k]
			sum_corr += c.correction
			if c.correction > 0.01:
				big += 1
			n += 1
	return {"corr_avg": sum_corr / n, "corr_n": big, "delay": float(server.get("delay_sum")) / maxf(float(server.get("delay_count")), 1.0),
			"underruns": server.underruns, "stale": server.stale_inputs}


## One raw player on a server without clients; `send_n` inputs per tick are fed by the caller.
func raw_player() -> Dictionary:
	var rig := make_rig(0.0, 0.0, 0)
	var raw := join_raw(rig)
	var hub: LoopbackHub = rig["hub"]
	var server: ServerCore = rig["server"]
	var slot: ServerCore.Slot = server.slots[0]
	return {"hub": hub, "server": server, "raw": raw, "slot": slot, "seq": 0}


## A tick of the raw player: sends the next `n` inputs (numbered on), then the server ticks.
func raw_tick(rp: Dictionary, n := 1, dash_first := false) -> void:
	var raw: LoopbackHub.LoopbackEndpoint = rp["raw"]
	for k in n:
		rp["seq"] += 1
		raw.send(1, NetProto.pack([NetProto.T_INPUT, rp["seq"], [NetProto.encode_input(inp(Vector2.RIGHT, Vector2.ZERO, false, dash_first and k == 0))]]), false)
	(rp["hub"] as LoopbackHub).advance(DT_MS)
	(rp["server"] as ServerCore).tick()


func measure_single(delay_ms: float, loss: float, ticks := 1200) -> Dictionary:
	var rig := make_rig(delay_ms, loss, 1, 5)
	warm_up(rig)
	var cl: ClientCore = rig["clients"][0]
	var server: ServerCore = rig["server"]
	var n := 0
	var mx := 0.0
	var last := cl.snapshots_applied
	for t in ticks:
		step_rig(rig, func(_k: int) -> SimInput: return scripted(0, t))
		if cl.snapshots_applied != last:
			last = cl.snapshots_applied
			if cl.correction > 0.001:
				n += 1
				mx = maxf(mx, cl.correction)
	return {"corr": n, "max": mx, "underruns": server.underruns, "delay": float(server.delay_sum) / maxf(float(server.delay_count), 1.0)}


func test_input_buffer() -> void:
	# --- one client alone (the prediction test's routine, but with the adaptive buffer): it runs dry while it learns,
	# which costs a few corrections of one tick of input (the fixed buffer of 3 had none)
	var one := measure_single(100.0, 2.0)
	print("INFO  one client, 100 ms / 2 %%: %d corrections (largest %.2f m) in 1200 ticks, %d underruns, inputs wait %.2f ticks" % [one["corr"], one["max"], one["underruns"], one["delay"]])
	check("buffer: alone at 100 ms / 2 %% loss only a few small corrections while the buffer learns (%d, largest %.2f m; fixed buffer: 0)" % [one["corr"], one["max"]], one["corr"] <= 4 and one["max"] <= 0.25)
	# --- the adaptive buffer of one player
	var rp := raw_player()
	var server: ServerCore = rp["server"]
	var slot: ServerCore.Slot = rp["slot"]
	check("buffer: a new player's target starts small (%d)" % slot.target, slot.target == ServerCore.JITTER_START and ServerCore.JITTER_START == 1)
	for _t in 200:
		raw_tick(rp)
	check("buffer: with even arrivals nothing waits, nothing runs dry, the target stays", server.underruns == 0 and slot.target == ServerCore.JITTER_START and server.delay_sum == 0, "underruns=%d target=%d delay=%d" % [server.underruns, slot.target, server.delay_sum])
	raw_tick(rp, 0)    # one input is late: the buffer runs dry
	check("buffer: running dry repeats the last input and grows the target by one", server.underruns == 1 and slot.target == ServerCore.JITTER_START + 1 and slot.last_input.move == Vector2.RIGHT)
	var wait_after_one := slot.shrink_wait
	raw_tick(rp, 2)    # the late one arrives together with the next
	check("buffer: ... the late input is used afterwards, no input is lost", server.skipped_inputs == 0 and slot.buffer.size() == 1, "skipped=%d buffer=%d" % [server.skipped_inputs, slot.buffer.size()])
	for _t in 3:
		raw_tick(rp, 0)
		raw_tick(rp, 1)
	for _t in 3:
		raw_tick(rp, 0)
	raw_tick(rp, 4)    # a burst of four
	check("buffer: a burst of inputs grows the target too", slot.target > ServerCore.JITTER_START + 1, "target=%d" % slot.target)
	var rb := raw_player()
	for _t in 100:
		raw_tick(rb)
	raw_tick(rb, 4)    # four at once, though nothing ran dry before
	check("buffer: a burst alone (nothing ran dry) grows the target by one", (rb["server"] as ServerCore).underruns == 0 and (rb["slot"] as ServerCore.Slot).target == ServerCore.JITTER_START + 1, "target=%d" % (rb["slot"] as ServerCore.Slot).target)
	var cap_ok := true
	for _t in 40:
		raw_tick(rp, 0)
		raw_tick(rp, 5)
		cap_ok = cap_ok and slot.target <= ServerCore.JITTER_MAX
	check("buffer: the target never grows beyond JITTER_MAX (%d)" % slot.target, cap_ok and slot.target == ServerCore.JITTER_MAX)
	check("buffer: every growth doubles the quiet time needed to shrink again (%d -> %d ticks)" % [wait_after_one, slot.shrink_wait], slot.shrink_wait > wait_after_one and slot.shrink_wait <= ServerCore.SHRINK_MAX)
	# quiet: the surplus is trimmed, then the target shrinks, slowly
	var target_before := slot.target
	var trimmed_before := server.trimmed_inputs
	var skipped_before := server.skipped_inputs
	for _t in ServerCore.TRIM_AFTER * 12:
		raw_tick(rp)
	check("buffer: a buffer that stays above its target is trimmed back (%d dropped, now %d waiting)" % [server.trimmed_inputs - trimmed_before, slot.buffer.size()], server.trimmed_inputs > trimmed_before and slot.buffer.size() <= slot.target)
	check("buffer: trimmed inputs are no lost inputs (acknowledged, no gap counted)", server.skipped_inputs == skipped_before)
	var shrink_wait := slot.shrink_wait
	for _t in shrink_wait + 20:
		raw_tick(rp)
	check("buffer: after the quiet time the target shrinks by one (%d -> %d)" % [target_before, slot.target], slot.target == target_before - 1)
	check("buffer: ... and the next shrink comes sooner (wait %d -> %d)" % [shrink_wait, slot.shrink_wait], slot.shrink_wait < shrink_wait or shrink_wait == ServerCore.SHRINK_AFTER)
	slot.shrink_wait = ServerCore.SHRINK_AFTER
	for _t in ServerCore.SHRINK_AFTER * (ServerCore.JITTER_MAX + 1):
		raw_tick(rp)
	check("buffer: in the end it is back at the start size (%d)" % slot.target, slot.target == ServerCore.JITTER_START)
	# a dash in a dropped input is handed on
	var s2 := ServerCore.Slot.new()
	var d := SimInput.new()
	d.dash = true
	s2.buffer[7] = d
	s2.buffer[8] = SimInput.new()
	s2.arrived[7] = 0
	s2.arrived[8] = 0
	server._drop_oldest(s2, true)
	check("buffer: when an input is dropped its dash goes to the next one, and it counts as used", (s2.buffer[8] as SimInput).dash and s2.last_consumed == 7 and s2.buffer.size() == 1)
	# a player's slot starts fresh for the next one
	slot.target = 4
	slot.reset()
	check("buffer: a freed slot forgets the target", slot.target == ServerCore.JITTER_START and slot.shrink_wait == ServerCore.SHRINK_AFTER)

	# --- against two clients: how long the inputs wait on the server, and what it costs in corrections
	# (the fixed 3-input buffer before: wait 2.0 / 2.6 ticks at 0 / 50 ms and no loss, 16 corrections in 3000
	# client-ticks at every setting, 100 ms / 2 %: wait 1.55)
	var worst_wait := 0.0
	var worst_corr := 0
	var line := ""
	for cond in [[0.0, 0.0], [50.0, 0.0], [100.0, 2.0]]:
		var m := measure_buffer(cond[0], cond[1])
		line += " %d/%d:%d corrections, wait %.2f;" % [cond[0], cond[1], m["corr_n"], m["delay"]]
		if cond[1] == 0.0:
			worst_wait = maxf(worst_wait, m["delay"])
		worst_corr = maxi(worst_corr, m["corr_n"])
	print("INFO  server input buffer (of 3000 ticks):" + line)
	check("buffer: without loss the inputs wait clearly less than the 2 to 2.6 ticks of the fixed buffer (worst %.2f ticks)" % worst_wait, worst_wait < 1.0)
	check("buffer: no real rise in corrections (worst %d of 3000 ticks; fixed buffer: 16)" % worst_corr, worst_corr <= 26)


# ---------------------------------------------------------------- the view draws the others from the display sim

func test_view_others() -> void:
	var cfg := Config.new()
	var pred := Sim.new(cfg, 1)
	var disp := Sim.new(cfg, 1)
	for s in [pred, disp]:
		for k in 4:
			s.set_player_enabled(k, k < 2)
			s.players[k].alive = true
	pred.players[0].pos = Vector2(3.0, 6.0)
	pred.players[0].prev_pos = Vector2(3.0, 6.0)
	pred.players[1].pos = Vector2(10.0, 6.0)
	pred.players[1].prev_pos = Vector2(10.0, 6.0)
	disp.players[0].pos = Vector2(20.0, 6.0)
	disp.players[0].prev_pos = Vector2(20.0, 6.0)
	disp.players[1].prev_pos = Vector2(6.0, 8.0)
	disp.players[1].pos = Vector2(8.0, 8.0)
	var view := ArenaView.new()
	root.add_child(view)
	view.setup(pred)
	view.use_sim(pred, 0)
	view.render(0.5, 0.016)
	check("view: without a display sim all players come from the predicted sim", view._bodies[1].position.x == 10.0 and view._bodies[0].position.x == 3.0)
	view.set_others(disp, 0.25)
	view.render(0.5, 0.016)
	check("view: the others come from the display sim with its own alpha (x %.2f)" % view._bodies[1].position.x, is_equal_approx(view._bodies[1].position.x, 6.5) and is_equal_approx(view._bodies[1].position.z, 8.0))
	check("view: the own player stays on the predicted sim", view._bodies[0].position.x == 3.0)
	# shards and wires: the own ones from the predicted sim, the others' from the display sim
	var mk := func(owner: int, x: float) -> SimShard:
		var sh := SimShard.new()
		sh.owner_id = owner
		sh.pos = Vector2(x, 5.0)
		sh.prev_pos = Vector2(x, 5.0)
		return sh
	pred.shards.append(mk.call(0, 1.0))
	pred.shards.append(mk.call(1, 2.0))
	disp.shards.append(mk.call(0, 3.0))
	disp.shards.append(mk.call(1, 4.0))
	var wire := func(owner: int, n: int) -> SimWire:
		var w := SimWire.new()
		w.owner_id = owner
		for k in n:
			w.pts.append(Vector2(float(k) * 2.0, 1.0))
		return w
	pred.wires.append(wire.call(0, 2))
	pred.wires.append(wire.call(1, 4))
	disp.wires.append(wire.call(0, 5))
	disp.wires.append(wire.call(1, 3))
	view.render(0.5, 0.016)
	var xs: Array[float] = []
	for n in view._shard_nodes:
		if n.visible:
			xs.append(n.position.x)
	xs.sort()
	var segs := 0
	for n in view._wire_core:
		if n.visible:
			segs += 1
	check("view: own shards from the predicted sim, the others' from the display sim", xs == [1.0, 4.0], str(xs))
	check("view: own wires from the predicted sim, the others' from the display sim (%d segments)" % segs, segs == 1 + 2)
	view.set_others(null, 1.0)
	view.render(0.5, 0.016)
	xs.clear()
	for n in view._shard_nodes:
		if n.visible:
			xs.append(n.position.x)
	xs.sort()
	segs = 0
	for n in view._wire_core:
		if n.visible:
			segs += 1
	check("view: without a display sim every shard and wire comes from the predicted sim", xs == [1.0, 2.0] and segs == 1 + 3, "%s %d" % [str(xs), segs])
	view.set_others(disp, 0.5)
	view.use_sim(pred, 0)
	check("view: use_sim drops the display sim", view.others_sim == null)
	view.queue_free()


func test_redundancy() -> void:
	var skipped := {}
	for red in [4, 1]:
		var rig := make_rig(60.0, 10.0, 1, 21)
		warm_up(rig)
		var cl: ClientCore = rig["clients"][0]
		if red != 4:
			cl.redundancy = red
		for t in 1200:
			step_rig(rig, func(_k: int) -> SimInput: return scripted(0, t))
		skipped[red] = (rig["server"] as ServerCore).skipped_inputs
	check("redundancy: at 10 %% loss the previous inputs fill the holes (skipped %d with, %d without)" % [skipped[4], skipped[1]], skipped[1] > 40 and skipped[4] * 5 < skipped[1])


func test_jitter_buffer() -> void:
	var rig := make_rig(0.0, 0.0, 1, 2)
	warm_up(rig)
	var server: ServerCore = rig["server"]
	var cl: ClientCore = rig["clients"][0]
	# a burst of 60 inputs at once: the buffer must not grow, the oldest are dropped
	var raw := cl.net
	var base := cl.seq + 1000
	for k in 60:
		raw.send(1, NetProto.pack([NetProto.T_INPUT, base + k, [NetProto.encode_input(inp(Vector2.RIGHT))]]), false)
	(rig["hub"] as LoopbackHub).advance(DT_MS)
	server.tick()
	var s: ServerCore.Slot = server.slots[cl.slot]
	check("server: a burst of inputs does not make the buffer grow", s.buffer.size() <= ServerCore.MAX_BUFFER and server.stale_inputs > 0, "buffer=%d stale=%d" % [s.buffer.size(), server.stale_inputs])
	# a stalled client: the last input is repeated for a while, then the player stands still
	for _t in 400:
		(rig["hub"] as LoopbackHub).advance(DT_MS)
		server.tick()
	check("server: without input the player stops (no runaway repeat)", server.slots[cl.slot].last_input.move == Vector2.ZERO and server.underruns > 0)


# ---------------------------------------------------------------- server robustness

func join_raw(rig: Dictionary, version := NetProto.VERSION, token: Variant = "0123456789abcdef0123456789abcdef") -> LoopbackHub.LoopbackEndpoint:
	var hub: LoopbackHub = rig["hub"]
	var raw := hub.connect_client()
	hub.advance(1.0)
	(rig["server"] as ServerCore).pump()
	raw.poll()
	raw.send(1, NetProto.pack([NetProto.T_HELLO, version] if token == null else [NetProto.T_HELLO, version, token]), true)
	hub.advance(1.0)
	(rig["server"] as ServerCore).pump()
	return raw


func test_robustness() -> void:
	var rig := make_rig(0.0, 0.0, 0, 3)
	var server: ServerCore = rig["server"]
	var hub: LoopbackHub = rig["hub"]
	var raw := join_raw(rig)
	var welcome := false
	for ev: Dictionary in raw.poll():
		var m := NetProto.unpack(ev["data"], 65536) if ev["kind"] == NetEndpoint.Kind.PACKET else []
		if not m.is_empty() and m[0] == NetProto.T_WELCOME:
			welcome = true
	check("server: a valid hello gets a welcome with the slot", welcome and server.players_online() == 1)

	var garbage: Array[PackedByteArray] = []
	garbage.append(PackedByteArray())
	garbage.append(PackedByteArray([0]))
	garbage.append(PackedByteArray([1, 2, 3]))
	garbage.append(PackedByteArray([7, 7, 7, 7, 7, 7, 7, 7, 7]))
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	for _k in 20:
		var b := PackedByteArray()
		b.resize(rr.randi_range(5, 200))
		for j in b.size():
			b[j] = rr.randi() % 256
		b[0] = NetProto.K_PLAIN if rr.randf() < 0.7 else b[0]
		garbage.append(b)
	garbage.append(NetProto.pack([]))                                           # empty message
	garbage.append(NetProto.pack(["input", 1]))                                 # type is not an int
	garbage.append(NetProto.pack([NetProto.T_INPUT]))                           # too short
	garbage.append(NetProto.pack([NetProto.T_INPUT, "x", []]))                  # seq not an int
	garbage.append(NetProto.pack([NetProto.T_INPUT, 5, []]))                    # no inputs
	garbage.append(NetProto.pack([NetProto.T_INPUT, 5, [[1, 2, 3]]]))           # input too short
	garbage.append(NetProto.pack([NetProto.T_INPUT, 5, [["a", 0, 0, 0, 0]]]))   # field is a string
	garbage.append(NetProto.pack([NetProto.T_INPUT, 5, [[NAN, 0.0, 0.0, 0.0, 0]]]))
	garbage.append(NetProto.pack([NetProto.T_INPUT, 5, [[INF, 0.0, 0.0, 0.0, 0]]]))
	garbage.append(NetProto.pack([NetProto.T_INPUT, -4, [[0, 0, 0, 0, 0]]]))    # negative seq
	garbage.append(NetProto.pack([NetProto.T_INPUT, 1 << 40, [[0, 0, 0, 0, 0]]]))
	garbage.append(NetProto.pack([NetProto.T_MODS, 17]))
	garbage.append(NetProto.pack([NetProto.T_PING, "now"]))
	garbage.append(NetProto.pack([999, 1, 2, 3]))                               # unknown type
	var many: Array = []
	for _k in 40:
		many.append([0, 0, 0, 0, 0])
	garbage.append(NetProto.pack([NetProto.T_INPUT, 50, many]))                 # too many inputs
	var before_dropped := server.dropped_packets
	for g in garbage:
		raw.send(1, g, false)
	hub.advance(1.0)
	var tick_before := server.sim.tick
	for _t in 3:
		hub.advance(DT_MS)
		server.tick()
	check("server: garbage packets are ignored and counted (%d of %d)" % [server.dropped_packets - before_dropped, garbage.size()],
			server.dropped_packets - before_dropped >= garbage.size() - 1 and server.sim.tick == tick_before + 3 and server.players_online() == 1)

	# an oversized but otherwise valid packet
	var fat := {}
	for k in 300:
		fat["junk%d" % k] = 1
	var fat_packet := NetProto.pack([NetProto.T_MODS, fat])
	var d0 := server.dropped_packets
	raw.send(1, fat_packet, true)
	hub.advance(1.0)
	server.pump()
	check("server: an oversized packet (%d bytes) is dropped unread" % fat_packet.size(), fat_packet.size() > NetProto.MAX_CLIENT_PACKET and server.dropped_packets == d0 + 1)

	# out-of-range sticks are clamped to length 1
	var seq_base := 100
	for k in 6:
		raw.send(1, NetProto.pack([NetProto.T_INPUT, seq_base + k, [[100.0, 100.0, -50.0, 1e30, 3]]]), false)
	hub.advance(1.0)
	var slot_i: int = server.slots.find_custom(func(s: ServerCore.Slot) -> bool: return s.peer >= 0)
	var start := server.sim.players[slot_i].pos
	var max_len := 0.0
	for _t in 60:
		hub.advance(DT_MS)
		server.tick()
		max_len = maxf(max_len, maxf(server.current_inputs[slot_i].move.length(), server.current_inputs[slot_i].aim.length()))
	# keep feeding the same extreme input so the player keeps walking
	check("server: stick values are clamped to length <= 1 (max %.4f)" % max_len, max_len <= 1.0001)
	var moved := server.sim.players[slot_i].pos.distance_to(start)
	check("server: clamped input cannot move faster than the speed limit", moved <= 6.0 * 1.2, "moved %.2f m in 1 s" % moved)

	# input before hello is ignored; a second hello is ignored
	var raw2 := hub.connect_client()
	hub.advance(1.0)
	server.pump()
	var d1 := server.dropped_packets
	raw2.send(1, NetProto.pack([NetProto.T_INPUT, 1, [[1, 0, 0, 0, 0]]]), false)
	hub.advance(1.0)
	server.pump()
	check("server: input before the hello is ignored", server.dropped_packets == d1 + 1 and server.players_online() == 1)

	# modifier levels are validated
	raw.send(1, NetProto.pack([NetProto.T_MODS, {"twin": 99, "nonsense": 5, "bounce": -3, "pierce": 2.0}]), true)
	hub.advance(1.0)
	server.pump()
	var mods := server.sim.players[slot_i].mods
	check("server: modifier levels are clamped, unknown ids dropped", int(mods["twin"]) == Mods.MAX_LEVEL and int(mods["bounce"]) == 0 and int(mods["pierce"]) == 2 and not mods.has("nonsense"))

	# the chosen figure is validated
	var skin_pick := (server.sim.players[slot_i].skin + 1) % Config.SKIN_COUNT
	var skin_before := server.sim.players[slot_i].skin
	var d_skin := server.dropped_packets
	raw.send(1, NetProto.pack([NetProto.T_SKIN, skin_pick]), true)
	hub.advance(1.0)
	server.pump()
	check("server: a valid figure choice is applied", server.sim.players[slot_i].skin == skin_pick and server.dropped_packets == d_skin)
	var bad_skins: Array = [Config.SKIN_COUNT, -1, 1 << 40, 2.0, "3", null, [1], true]
	for bad: Variant in bad_skins:
		raw.send(1, NetProto.pack([NetProto.T_SKIN, bad]), true)
	raw.send(1, NetProto.pack([NetProto.T_SKIN]), true)
	raw.send(1, NetProto.pack([NetProto.T_SKIN, 1, 2]), true)
	hub.advance(1.0)
	server.pump()
	check("server: invalid figure choices are dropped and change nothing", server.sim.players[slot_i].skin == skin_pick and server.dropped_packets == d_skin + bad_skins.size() + 2 and skin_before != skin_pick)

	# a ping gets a pong
	raw.poll()
	raw.send(1, NetProto.pack([NetProto.T_PING, 1234]), false)
	hub.advance(1.0)
	server.pump()
	var pong := false
	for ev: Dictionary in raw.poll():
		var m := NetProto.unpack(ev["data"], 65536) if ev["kind"] == NetEndpoint.Kind.PACKET else []
		if not m.is_empty() and m[0] == NetProto.T_PONG and m[1] == 1234:
			pong = true
	check("server: ping is answered", pong)


func test_join_rules() -> void:
	# wrong protocol version
	var rig := make_rig(0.0, 0.0, 0, 4)
	var server: ServerCore = rig["server"]
	var raw := join_raw(rig, NetProto.VERSION + 1)
	var rejected := false
	for ev: Dictionary in raw.poll():
		if ev["kind"] == NetEndpoint.Kind.PACKET:
			var m := NetProto.unpack(ev["data"], 65536)
			rejected = rejected or (not m.is_empty() and m[0] == NetProto.T_REJECT and m[1] == "version")
	check("server: a wrong protocol version is refused", rejected and server.players_online() == 0)

	# a client core that gets refused ends in FAILED
	var rig2 := make_rig(0.0, 0.0, 0, 4)
	var hub2: LoopbackHub = rig2["hub"]
	# fill the server first, then a fifth client has to be refused
	var fillers: Array[ClientCore] = []
	for _k in 4:
		fillers.append(ClientCore.new(hub2.connect_client()))
	rig2["clients"] = fillers
	warm_up(rig2)
	var late := ClientCore.new(hub2.connect_client())
	for _t in 30:
		hub2.advance(DT_MS)
		late.poll(DT_MS / 1000.0)
		(rig2["server"] as ServerCore).tick()
		for f in fillers:
			f.poll()
			f.tick(SimInput.new())
	check("server: four players fit", (rig2["server"] as ServerCore).players_online() == 4 and fillers[0].state == ClientCore.State.ONLINE)
	check("server: a fifth client is refused with 'full'", late.state == ClientCore.State.FAILED and late.fail_reason == "full" and (rig2["server"] as ServerCore).players_online() == 4, "state=%d reason=%s" % [late.state, late.fail_reason])

	# leaving frees the slot, and a newcomer can take it
	var gone: ClientCore = fillers[1]
	var gone_slot := gone.slot
	gone.close()
	for _t in 10:
		hub2.advance(DT_MS)
		(rig2["server"] as ServerCore).tick()
	check("server: leaving frees the slot", (rig2["server"] as ServerCore).players_online() == 3 and (rig2["server"] as ServerCore).slots[gone_slot].peer < 0)
	var again := ClientCore.new(hub2.connect_client())
	for _t in 30:
		hub2.advance(DT_MS)
		again.poll(DT_MS / 1000.0)
		(rig2["server"] as ServerCore).tick()
	check("server: a newcomer gets the freed slot", again.slot == gone_slot, "slot=%d expected %d" % [again.slot, gone_slot])

	# a server with bots fills the free slots and hands them over
	var rig3 := make_rig(0.0, 0.0, 1, 4, true)
	check("bots: the server runs bots in the free slots", warm_up(rig3))
	var srv3: ServerCore = rig3["server"]
	for _t in 300:
		step_rig(rig3, func(_k: int) -> SimInput: return SimInput.new())
	var bots_enabled := 0
	for i in 4:
		if srv3.sim.players[i].enabled and i != rig3["clients"][0].slot:
			bots_enabled += 1
	check("bots: three bots plus the human", bots_enabled == 3 and srv3.bots.size() == 4)
	var bot_moved := false
	for i in 4:
		if i != rig3["clients"][0].slot and srv3.current_inputs[i].move != Vector2.ZERO:
			bot_moved = true
	check("bots: the bots produce input", bot_moved)


func hello_reason(rig: Dictionary, token: Variant = "0123456789abcdef0123456789abcdef") -> String:
	var raw := join_raw(rig, NetProto.VERSION, token)
	for ev: Dictionary in raw.poll():
		if ev["kind"] == NetEndpoint.Kind.PACKET:
			var m := NetProto.unpack(ev["data"], 65536)
			if not m.is_empty() and m[0] == NetProto.T_REJECT:
				return str(m[1])
			if not m.is_empty() and m[0] == NetProto.T_WELCOME:
				return "welcome"
	return ""


func test_match_lock() -> void:
	var M := MatchMode.Phase
	var rig := make_rig(0.0, 0.0, 2, 6)
	check("match lock: two clients join", warm_up(rig))
	var server: ServerCore = rig["server"]
	check("match lock: open in free play", not server.match_locked() and hello_reason(rig) == "welcome")
	var rig_b := make_rig(0.0, 0.0, 2, 6)
	warm_up(rig_b)
	var sb: ServerCore = rig_b["server"]
	check("match lock: server starts the match", sb.start_match(10) and sb.match_locked() and sb.sim.mode.phase == M.COUNTDOWN)
	check("match lock: hello refused with 'started' in COUNTDOWN", hello_reason(rig_b) == "started")
	for _t in 200:
		step_rig(rig_b, func(_k: int) -> SimInput: return SimInput.new())
	check("match lock: still refused in PLAY", sb.sim.mode.phase == M.PLAY and hello_reason(rig_b) == "started")
	sb.sim.mode.phase = M.RESULT
	check("match lock: refused in RESULT", hello_reason(rig_b) == "started")
	sb.sim.mode.phase = M.MATCH_OVER
	check("match lock: open again in MATCH_OVER", not sb.match_locked() and hello_reason(rig_b) == "welcome")
	# an empty server cannot start
	var rig_c := make_rig(0.0, 0.0, 1, 6)
	warm_up(rig_c)
	check("match lock: one player cannot start", not (rig_c["server"] as ServerCore).start_match(10))
	# a refused ClientCore ends FAILED with the reason
	var rig_d := make_rig(0.0, 0.0, 2, 7)
	warm_up(rig_d)
	(rig_d["server"] as ServerCore).start_match(10)
	var late := ClientCore.new((rig_d["hub"] as LoopbackHub).connect_client())
	for _t in 30:
		(rig_d["hub"] as LoopbackHub).advance(DT_MS)
		late.poll(DT_MS / 1000.0)
		(rig_d["server"] as ServerCore).tick()
		for c: ClientCore in rig_d["clients"]:
			c.poll(DT_MS / 1000.0)
			c.tick(SimInput.new())
	check("match lock: a client core fails with reason 'started'", late.state == ClientCore.State.FAILED and late.fail_reason == "started", "reason=%s" % late.fail_reason)

	# prediction stays consistent through countdown -> play
	var rig_e := make_rig(60.0, 0.0, 2, 8)
	warm_up(rig_e)
	var se: ServerCore = rig_e["server"]
	se.start_match(10)
	var cl: ClientCore = rig_e["clients"][0]
	var moved_early := false
	var max_gap := 0.0
	var play_seen := false
	for t in 330:
		var p0 := cl.sim.players[cl.slot].pos
		step_rig(rig_e, func(k: int) -> SimInput:
			var i := SimInput.new()
			if k == 0: i.move = Vector2.RIGHT
			return i)
		if cl.sim.mode.phase == M.COUNTDOWN and cl.sim.players[cl.slot].pos != p0 and t > 30:
			moved_early = true
		if cl.sim.mode.phase == M.PLAY:
			play_seen = true
		if t > 250:
			max_gap = maxf(max_gap, cl.sim.players[cl.slot].pos.distance_to(se.sim.players[cl.slot].pos))
	check("match lock: client prediction does not move in countdown", not moved_early)
	check("match lock: client reaches play and stays near the server", play_seen and se.sim.mode.phase == M.PLAY and max_gap < 1.5, "gap=%.2f phase=%d" % [max_gap, cl.sim.mode.phase])


# ---------------------------------------------------------------- rejoin

func idle_input(_k: int) -> SimInput:
	return SimInput.new()


## Two clients in a running match (phase PLAY). With bots the other two slots are driven by bots.
func play_phase_rig(with_bots := false) -> Dictionary:
	var rig := make_rig(0.0, 0.0, 2, 6, with_bots)
	warm_up(rig)
	(rig["server"] as ServerCore).start_match(10)
	for _t in 220:
		step_rig(rig, idle_input)
	return rig


## A client with `token` joins the rig (and is stepped with the others from now on).
func add_client(rig: Dictionary, token: String) -> ClientCore:
	var c := ClientCore.new((rig["hub"] as LoopbackHub).connect_client())
	c.token = token
	(rig["clients"] as Array).append(c)
	return c


func test_zone() -> void:
	var M := MatchMode.Phase
	var rig := play_phase_rig(false)
	var srv: ServerCore = rig["server"]
	var c0: ClientCore = rig["clients"][0]
	var c1: ClientCore = rig["clients"][1]
	check("zone net: a running match", srv.sim.mode.phase == M.PLAY and c0.sim.mode.phase == M.PLAY)
	# put the server into the shrunk state and one player outside, the other inside (server state; clients follow)
	var spot: Rect2 = Config.ZONE_SPOTS[1]
	srv.sim.mode.zone_spot = 1
	srv.sim.mode.zone_t = 20.0 + 12.0
	srv.sim.players[0].pos = Vector2(5.0, 7.2)
	srv.sim.players[0].prev_pos = srv.sim.players[0].pos
	srv.sim.players[1].pos = spot.get_center()
	srv.sim.players[1].prev_pos = srv.sim.players[1].pos
	for _t in 70:
		step_rig(rig, idle_input)
	var zs := srv.sim.zone_rect()
	var zc := c0.sim.zone_rect()
	check("zone net: the client sees the same zone rect as the server", c0.sim.mode.zone_spot == 1 and zs.position.distance_to(zc.position) < 0.2 and zs.end.distance_to(zc.end) < 0.2 and zs != Rect2(Vector2.ZERO, Config.ARENA_SIZE), "server %s client %s" % [zs, zc])
	check("zone net: the clock agrees within a few ticks", absf(srv.sim.mode.zone_t - c0.sim.mode.zone_t) < 0.15, "%f vs %f" % [srv.sim.mode.zone_t, c0.sim.mode.zone_t])
	var ts: float = srv.sim.players[0].zone_t
	check("zone net: the outside player's timer is running and the own client predicts it", ts > 0.5 and absf(c0.sim.players[0].zone_t - ts) < 0.15, "server %f client %f" % [ts, c0.sim.players[0].zone_t])
	check("zone net: the other client sees the same timers", absf(c1.sim.players[0].zone_t - ts) < 0.15 and c1.sim.players[1].zone_t == 0.0, "%f" % c1.sim.players[0].zone_t)
	c1.prepare_display(0.5)
	var disp: Sim = c1.display_sim
	check("zone net: the interpolated display sim carries the zone for the others", disp != null and disp.zone_active() and absf(disp.players[0].zone_t - ts) < 0.4, "%s" % disp)


func test_rejoin() -> void:
	var M := MatchMode.Phase
	# a drop during PLAY keeps the place: enabled, roster, points; the figure stands (also with bots on)
	var rig := play_phase_rig(true)
	var srv: ServerCore = rig["server"]
	var c1: ClientCore = rig["clients"][1]
	var tok1 := c1.token
	check("rejoin: the match is in PLAY", srv.sim.mode.phase == M.PLAY and srv.sim.mode.roster[1])
	srv.sim.mode.points[1] = 3
	c1.close()
	var moved := false
	for _t in 120:
		step_rig(rig, idle_input)
		if srv.current_inputs[1].move != Vector2.ZERO or srv.current_inputs[1].aim_held or srv.current_inputs[1].dash:
			moved = true
	check("rejoin: a drop during PLAY keeps the slot enabled, in the roster, with its points", srv.sim.players[1].enabled and srv.sim.mode.roster[1] and srv.sim.mode.points[1] == 3 and srv.slots[1].away and srv.slots[1].token == tok1)
	check("rejoin: the absent figure gets empty input, no bot drives it", not moved and srv.away_slots() == [1] and srv.players_online() == 1)
	check("rejoin: a bot still drives the free slots", srv.slots[2].peer < 0 and not srv.slots[2].away and srv.sim.players[2].enabled)
	# the same token comes back to the same slot
	var re := add_client(rig, tok1)
	for _t in 60:
		step_rig(rig, idle_input)
	check("rejoin: the same token gets the same slot back during PLAY", re.state == ClientCore.State.ONLINE and re.slot == 1 and not srv.slots[1].away and srv.players_online() == 2, "state=%d slot=%d" % [re.state, re.slot])
	check("rejoin: the points are intact for the returning player", re.sim.mode.points[1] == 3 and srv.sim.mode.points[1] == 3 and srv.sim.mode.phase == M.PLAY)
	check("rejoin: a new token is still refused with 'started'", hello_reason(rig, "ffffffffffffffffffffffffffffffff") == "started")

	# a drop in free play (phase OFF) frees the slot as before
	var rig_o := make_rig(0.0, 0.0, 2, 6)
	warm_up(rig_o)
	var so: ServerCore = rig_o["server"]
	(rig_o["clients"][1] as ClientCore).close()
	for _t in 5:
		step_rig(rig_o, idle_input)
	check("rejoin: a drop in phase OFF frees the slot", not so.sim.players[1].enabled and not so.slots[1].away and so.slots[1].token == "" and so.away_slots().is_empty())

	# takeover: the same token while the old connection is still there
	var rig_t := play_phase_rig(false)
	var st: ServerCore = rig_t["server"]
	var old: ClientCore = rig_t["clients"][1]
	var old_peer: int = st.slots[1].peer
	var fresh := add_client(rig_t, old.token)
	for _t in 60:
		step_rig(rig_t, idle_input)
	check("rejoin: takeover gives the slot to the new connection", fresh.state == ClientCore.State.ONLINE and fresh.slot == 1 and st.slots[1].peer != old_peer and st.slots[1].peer >= 0 and not st.slots[1].away)
	check("rejoin: takeover disconnects the old connection and counts players right", old.state != ClientCore.State.ONLINE and st.players_online() == 2 and not st._peer_slot.has(old_peer), "online=%d" % st.players_online())
	check("rejoin: takeover keeps the figure in the match", st.sim.players[1].enabled and st.sim.mode.roster[1])

	# the idle timeout during a match reserves the slot too
	var rig_i := play_phase_rig(false)
	var si: ServerCore = rig_i["server"]
	var active: ClientCore = rig_i["clients"][0]
	var hi: LoopbackHub = rig_i["hub"]
	for _t in ServerCore.IDLE_TIMEOUT + 30:
		hi.advance(DT_MS)
		active.poll(DT_MS / 1000.0)
		active.tick(SimInput.new())
		si.tick()
		si.sim.mode.zone_t = 0.0   # keep the shrinking zone from ending the round while the idle players stand still
	check("rejoin: the idle timeout in a match keeps the slot reserved", si.sim.mode.phase == M.PLAY and si.slots[1].away and si.sim.players[1].enabled and si.players_online() == 1, "phase=%d" % si.sim.mode.phase)

	# the held places are freed when the match ends; a rematch works
	var rig_e := play_phase_rig(false)
	var se: ServerCore = rig_e["server"]
	var tok_e: String = (rig_e["clients"][1] as ClientCore).token
	(rig_e["clients"][1] as ClientCore).close()
	for _t in 5:
		step_rig(rig_e, idle_input)
	check("rejoin: held before the match ends", se.slots[1].away)
	se.sim.mode.phase = M.MATCH_OVER
	se.sim.mode.phase_t = 0.0
	for _t in 3:
		step_rig(rig_e, idle_input)
	check("rejoin: away slots are freed at MATCH_OVER", se.away_slots().is_empty() and not se.slots[1].away and se.slots[1].token == "" and not se.sim.players[1].enabled)
	var fresh_e := add_client(rig_e, "aaaaaaaaaaaaaaaa")
	for _t in 30:
		step_rig(rig_e, idle_input)
	check("rejoin: after MATCH_OVER a new player joins and the rematch starts", fresh_e.state == ClientCore.State.ONLINE and se.start_match(10) and se.sim.mode.phase == M.COUNTDOWN)
	check("rejoin: the old token no longer gets a held place after the match", tok_e != "" and not se.slots[1].away)
	# leaving the match (phase OFF) frees them as well
	var rig_f := play_phase_rig(false)
	var sf: ServerCore = rig_f["server"]
	(rig_f["clients"][1] as ClientCore).close()
	for _t in 5:
		step_rig(rig_f, idle_input)
	sf.sim.mode.phase = M.OFF
	step_rig(rig_f, idle_input)
	check("rejoin: away slots are freed when the match is left (phase OFF)", sf.away_slots().is_empty() and not sf.sim.players[1].enabled)

	# malformed tokens are dropped like any malformed hello
	var rig_m := make_rig(0.0, 0.0, 0, 3)
	var sm: ServerCore = rig_m["server"]
	var bad: Array = [5, "abc", "a".repeat(65), "ZZZZZZZZZZZZ", "0123456789abcdeg", ["x"], null]
	var all_dropped := true
	for t: Variant in bad:
		var before := sm.dropped_packets
		var raw := join_raw(rig_m, NetProto.VERSION, t)
		var welcomed := false
		for ev: Dictionary in raw.poll():
			if ev["kind"] == NetEndpoint.Kind.PACKET:
				welcomed = true
		if sm.dropped_packets != before + 1 or welcomed or sm.players_online() != 0:
			all_dropped = false
	check("rejoin: a hello with a malformed or missing token is dropped", all_dropped)
	check("rejoin: a valid token of 8 and of 64 characters is accepted", hello_reason(rig_m, "abcdef01") == "welcome" and hello_reason(rig_m, "0123456789abcdef".repeat(4)) == "welcome")

	# ClientCore: lost-connection detector
	var fs := fake_server_setup()
	var cl: ClientCore = fs["client"]
	var s := Sim.new(fs["cfg"], 1)
	send_snapshot(fs, s, 100, 0)
	cl.poll(ClientCore.LOST_TIMEOUT - 0.5)
	check("client lost: online while snapshots are recent", cl.state == ClientCore.State.ONLINE)
	s.tick = 102
	send_snapshot(fs, s, 102, 0)
	cl.poll(ClientCore.LOST_TIMEOUT - 0.5)
	check("client lost: a snapshot resets the silence", cl.state == ClientCore.State.ONLINE)
	cl.poll(1.0)
	check("client lost: no snapshot for LOST_TIMEOUT fails with 'lost'", cl.state == ClientCore.State.FAILED and cl.fail_reason == "lost", "%d %s" % [cl.state, cl.fail_reason])
	var fs2 := fake_server_setup()
	send_snapshot(fs2, Sim.new(fs2["cfg"], 1), 100, 0)
	(fs2["hub"] as LoopbackHub).server.disconnect_peer(1)
	(fs2["hub"] as LoopbackHub).advance(1.0)
	(fs2["client"] as ClientCore).poll()
	check("client lost: a disconnect while online is 'lost'", (fs2["client"] as ClientCore).fail_reason == "lost")
	var fs3 := fake_server_setup()
	(fs3["client"] as ClientCore).poll(10.0)
	check("client lost: the detector only runs while online", (fs3["client"] as ClientCore).fail_reason == "timeout")
	var fs4 := fake_server_setup()
	send_snapshot(fs4, Sim.new(fs4["cfg"], 1), 100, 0)
	(fs4["client"] as ClientCore).close()
	check("client lost: leaving on purpose stays 'closed'", (fs4["client"] as ClientCore).fail_reason == "closed")

	# the hello carries the token
	var fs5 := fake_server_setup()
	check("client: the token is a valid random one by default", NetProto.valid_token((fs5["client"] as ClientCore).token) and (fs5["client"] as ClientCore).token != cl.token)

	# NetStore token
	NetStore.path = "user://test_online%d.json" % PORT_OFFSET
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NetStore.path))
	check("netstore: no token before the first use", NetStore.load_token() == "")
	var t1 := NetStore.token()
	check("netstore: the token is created once and stable", NetProto.valid_token(t1) and t1.length() == 32 and NetStore.token() == t1 and NetStore.load_token() == t1)
	NetStore.save_address("host:1")
	check("netstore: saving the address keeps the token and the other way round", NetStore.token() == t1 and NetStore.load_address() == "host:1")
	NetStore.save_last_game("10.0.0.2", 24565)
	check("netstore: the last game round-trips and can be cleared", NetStore.load_last_game() == {"host": "10.0.0.2", "port": 24565} and NetStore.token() == t1)
	NetStore.clear_last_game()
	check("netstore: cleared last game is empty", NetStore.load_last_game().is_empty() and NetStore.load_address() == "host:1")
	var f := FileAccess.open(NetStore.path, FileAccess.WRITE)
	f.store_string('{"address": "old:5"}')
	f.close()
	var t2 := NetStore.token()
	check("netstore: an old file with only the address still reads, and gets a token", NetStore.load_address() == "old:5" and NetProto.valid_token(t2) and t2 != t1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NetStore.path))


func test_idle_and_sticks() -> void:
	# a joined player that sends no input is dropped after IDLE_TIMEOUT ticks; an active one stays
	var rig := make_rig(0.0, 0.0, 2, 5)
	var srv: ServerCore = rig["server"]
	var cs: Array = rig["clients"]
	check("idle: both join", warm_up(rig) and srv.players_online() == 2)
	var silent: ClientCore = cs[1]
	var active: ClientCore = cs[0]
	var h: LoopbackHub = rig["hub"]
	for _t in ServerCore.IDLE_TIMEOUT - 120:
		h.advance(DT_MS)
		active.poll(DT_MS / 1000.0)
		active.tick(SimInput.new())
		srv.tick()
	check("idle: before the timeout the silent player is still there", srv.players_online() == 2)
	for _t in 240:
		h.advance(DT_MS)
		active.poll(DT_MS / 1000.0)
		active.tick(SimInput.new())
		silent.poll(DT_MS / 1000.0)
		srv.tick()
	check("idle: the silent player's slot is freed, the active one is kept", srv.players_online() == 1 and active.state == ClientCore.State.ONLINE and silent.state != ClientCore.State.ONLINE, "online=%d silent=%d" % [srv.players_online(), silent.state])


func test_stick_range() -> void:
	for bad: Variant in [1e200, -1e200, 1e30, 2.5, -2.5]:
		check("proto: a stick value of %s is refused" % str(bad), NetProto.decode_input([bad, 0, 0, 0, 0]) == null and NetProto.decode_input([0, 0, 0, bad, 0]) == null)
	for good: Variant in [1.0, -1.0, 0, 0.0, 1, -1]:
		check("proto: a stick value of %s is accepted" % str(good), NetProto.decode_input([good, 0, good, 0, 0]) != null)
	# a hostile packet must not poison the sim
	var rig := make_rig(0.0, 0.0, 0, 3)
	var server: ServerCore = rig["server"]
	var hub: LoopbackHub = rig["hub"]
	var raw := join_raw(rig)
	for k in 30:
		raw.send(1, NetProto.pack([NetProto.T_INPUT, k + 1, [[1e200, -1e200, 1e30, 1e200, 0]]]), false)
		hub.advance(DT_MS)
		server.tick()
	var finite := true
	for p in server.sim.players:
		finite = finite and is_finite(p.pos.x) and is_finite(p.pos.y)
	check("server: out-of-range sticks leave all positions finite", finite and server.dropped_packets >= 30, "dropped=%d" % server.dropped_packets)


# ---------------------------------------------------------------- client against a scripted server

func fake_server_setup() -> Dictionary:
	var hub := LoopbackHub.new(1)
	var cl := ClientCore.new(hub.connect_client())
	hub.advance(1.0)
	cl.poll()                                   # sends the hello
	hub.server.poll()                           # connect event
	var cfg := Config.new()
	hub.server.send(1, NetProto.pack([NetProto.T_WELCOME, NetProto.VERSION, 0, cfg.to_dict()]), true)
	hub.advance(1.0)
	cl.poll()
	return {"hub": hub, "client": cl, "cfg": cfg}


func send_snapshot(fs: Dictionary, state: Sim, tick_no: int, acked: int) -> void:
	var enc: Array = []
	for i in 4:
		enc.append(NetProto.encode_input(SimInput.new()))
	var body := NetProto.snapshot_body(enc, state.save_state())
	(fs["hub"] as LoopbackHub).server.send(1, NetProto.snapshot_packet(tick_no, acked, body), false)
	(fs["hub"] as LoopbackHub).advance(1.0)
	(fs["client"] as ClientCore).poll()


func test_client_rules() -> void:
	var fs := fake_server_setup()
	var cl: ClientCore = fs["client"]
	var s := Sim.new(fs["cfg"], 1)
	for i in 4:
		s.set_player_enabled(i, i < 2)
		s.players[i].alive = true
	s.crate_pos = Vector2(-50, -50)
	s.box_active = false
	s.box_timer = 9999.0
	check("client: welcome gives slot and config but it is not online before the first snapshot", cl.slot == 0 and cl.sim != null and cl.state == ClientCore.State.CONNECTING)
	s.tick = 100
	send_snapshot(fs, s, 100, 0)
	check("client: the first snapshot puts it online", cl.state == ClientCore.State.ONLINE and cl.sim.tick == 100)
	s.tick = 90
	var older := Sim.new(fs["cfg"], 1)
	older.load_state(s.save_state())
	older.players[0].pos = Vector2(20, 3)
	send_snapshot(fs, older, 90, 0)
	check("client: an older snapshot is dropped", cl.snapshots_dropped == 1 and cl.sim.players[0].pos != Vector2(20, 3) and cl.sim.tick == 100)
	s.tick = 100
	var dup := Sim.new(fs["cfg"], 1)
	dup.load_state(s.save_state())
	dup.players[0].pos = Vector2(20, 3)
	send_snapshot(fs, dup, 100, 0)
	check("client: a snapshot with the same tick is dropped as well", cl.snapshots_dropped == 2)

	# events of re-simulated ticks do not reach the view
	var k := Sim.new(fs["cfg"], 1)
	k.load_state(s.save_state())
	k.players[1].pos = Vector2(8, 6.3)
	k.players[1].prev_pos = Vector2(8, 6.3)
	k.players[0].pos = Vector2(5, 6.3)
	k.players[0].prev_pos = Vector2(5, 6.3)
	var h := k.players[0].heads[0]
	h.state = SimHead.S.FLIGHT
	h.pos = Vector2(7.7, 6.3)
	h.prev_pos = Vector2(7.7, 6.3)
	h.throw_dir = Vector2.RIGHT
	h.flight_dist = 8.0
	var probe := Sim.new(fs["cfg"], 1)
	probe.load_state(k.save_state())
	probe.step([SimInput.new(), SimInput.new(), SimInput.new(), SimInput.new()])
	var probe_kill := false
	for e: Dictionary in probe.events:
		probe_kill = probe_kill or e["type"] == "kill"
	check("client test setup: the crafted state really produces a kill in one tick", probe_kill)
	k.tick = 110
	send_snapshot(fs, k, 110, 0)                   # reconcile onto the crafted state
	cl.tick(SimInput.new())                        # seq 1: predicted, produces the kill event
	var own_kill := false
	for e: Dictionary in cl.events:
		own_kill = own_kill or e["type"] == "kill"
	check("client: events of the newest local tick are handed on", own_kill)
	cl.events = []
	k.tick = 120
	send_snapshot(fs, k, 120, 0)                   # same crafted state, seq 1 still pending: it is replayed
	var replay_state_kill := not cl.sim.players[1].alive
	check("client: the replay really re-ran the kill", replay_state_kill)
	check("client: events of replayed ticks are not handed to the view", cl.events.is_empty(), str(cl.events))


# ---------------------------------------------------------------- lag tool

func test_lag_tool() -> void:
	var hub := LoopbackHub.new(1)
	var clock := [0.0]
	var raw := hub.connect_client()
	var lag := LagEndpoint.new(raw, 77)
	lag.clock = func() -> float: return clock[0]
	hub.advance(1.0)
	lag.poll()
	hub.server.poll()
	lag.delay_ms = 100.0
	lag.send(1, PackedByteArray([1, 2, 3]), false)
	lag.poll()
	hub.advance(1.0)
	var got_early := hub.server.poll().size()
	clock[0] = 99.0
	lag.poll()
	hub.advance(1.0)
	var got_99 := hub.server.poll().size()
	clock[0] = 100.0
	lag.poll()
	hub.advance(1.0)
	var got_100 := hub.server.poll().size()
	check("lag tool: outgoing packet is held for exactly the delay", got_early == 0 and got_99 == 0 and got_100 == 1)
	# incoming
	hub.server.send(1, PackedByteArray([9]), false)
	hub.advance(1.0)
	clock[0] = 150.0
	var in_early := lag.poll().size()
	clock[0] = 260.0
	var in_late := lag.poll().size()
	check("lag tool: incoming packet is held for the delay as well", in_early == 0 and in_late == 1)
	# loss: reliable never, unreliable about p
	lag.delay_ms = 0.0
	lag.loss_pct = 20.0
	clock[0] = 300.0
	for k in 1000:
		lag.send(1, PackedByteArray([k % 256]), false)
		lag.send(1, PackedByteArray([k % 256, 1]), true)
	lag.poll()
	var unrel := 0
	var rel := 0
	var order_ok := true
	var last_rel := -1
	for ev: Dictionary in hub.server.poll():
		if ev["kind"] != NetEndpoint.Kind.PACKET:
			continue
		if ev["reliable"]:
			rel += 1
		else:
			unrel += 1
	hub.advance(1.0)
	for ev: Dictionary in hub.server.poll():
		if ev["kind"] != NetEndpoint.Kind.PACKET:
			continue
		if ev["reliable"]:
			rel += 1
		else:
			unrel += 1
	check("lag tool: 20 %% loss drops about a fifth of the unreliable packets (%d of 1000 kept)" % unrel, unrel > 740 and unrel < 860)
	check("lag tool: reliable packets are never dropped (%d of 1000)" % rel, rel == 1000)
	# the same for the incoming direction
	clock[0] = 400.0
	for k in 1000:
		hub.server.send(1, PackedByteArray([k % 256]), false)
		hub.server.send(1, PackedByteArray([k % 256, 1]), true)
	hub.advance(1.0)
	var in_unrel := 0
	var in_rel := 0
	for ev: Dictionary in lag.poll():
		if ev["kind"] == NetEndpoint.Kind.PACKET:
			if ev["reliable"]:
				in_rel += 1
			else:
				in_unrel += 1
	check("lag tool: incoming loss hits only unreliable packets (%d of 1000 kept, %d of 1000 reliable)" % [in_unrel, in_rel], in_rel == 1000 and in_unrel > 740 and in_unrel < 860)
	# order is kept when the delay shrinks while packets are on the way
	lag.loss_pct = 0.0
	lag.delay_ms = 100.0
	clock[0] = 1000.0
	lag.send(1, PackedByteArray([1]), true)
	lag.delay_ms = 10.0
	clock[0] = 1001.0
	lag.send(1, PackedByteArray([2]), true)
	clock[0] = 1200.0
	lag.poll()
	hub.advance(1.0)
	var order: Array = []
	for ev: Dictionary in hub.server.poll():
		if ev["kind"] == NetEndpoint.Kind.PACKET:
			order.append(ev["data"][0])
	order_ok = order == [1, 2]
	check("lag tool: packets keep their order when the delay is lowered", order_ok, str(order))


func test_address_parse() -> void:
	check("address: host only gets the default port", NetStore.parse_address(" example.org ") == {"host": "example.org", "port": NetProto.DEFAULT_PORT})
	check("address: host and port", NetStore.parse_address("10.0.0.5:30000") == {"host": "10.0.0.5", "port": 30000})
	check("address: a bad port is refused", NetStore.parse_address("10.0.0.5:99999")["host"] == "" and NetStore.parse_address("10.0.0.5:abc")["host"] == "")
	check("address: empty or with spaces is refused", NetStore.parse_address("")["host"] == "" and NetStore.parse_address("a b")["host"] == "")


# ---------------------------------------------------------------- real ENet on localhost

func test_enet() -> void:
	var port := 0
	var server_ep := ENetEndpoint.new()
	for p in range(24610 + PORT_OFFSET, 24650 + PORT_OFFSET):
		if server_ep.listen(p, ServerCore.MAX_PENDING) == OK:
			port = p
			break
	check("enet: server socket opens on a free localhost port", port != 0)
	if port == 0:
		return
	var server := ServerCore.new(Config.new(), server_ep, 7, true)
	for i in 4:
		server.sim.apply_mods(i, Mods.sanitize({"splitter": 3, "twin": 3, "steer": 3, "shards": 3, "warhead": 3, "tripwire": 3, "bighead": 3, "bounce": 3, "pierce": 3, "elastic": 3, "extradash": 3}))
	var client_ep := ENetEndpoint.new()
	check("enet: client socket opens", client_ep.connect_to("127.0.0.1", port) == OK)
	var cl := ClientCore.new(client_ep)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var moved := false
	var start := Vector2.ZERO
	while Time.get_ticks_msec() - t0 < 2500 and frames < 400:
		cl.poll(1.0 / 60.0)
		server.tick()
		cl.tick(inp(Vector2.RIGHT) if cl.state == ClientCore.State.ONLINE else SimInput.new())
		if cl.state == ClientCore.State.ONLINE and start == Vector2.ZERO:
			start = cl.sim.players[cl.slot].pos
		frames += 1
		OS.delay_msec(8)
		if cl.snapshots_applied > 60 and cl.ping_ms > 0.0:
			break
	check("enet: the client joins and gets snapshots", cl.state == ClientCore.State.ONLINE and cl.snapshots_applied > 30 and cl.slot == 0, "state=%d applied=%d" % [cl.state, cl.snapshots_applied])
	check("enet: the server receives and consumes the inputs", server.slots[0].last_consumed > 20, "consumed=%d" % server.slots[0].last_consumed)
	var me := cl.sim.players[0]
	check("enet: input moves the player (prediction and server agree on direction)", me.pos.x > start.x + 0.5 and server.sim.players[0].pos.x > start.x, "client x=%.2f server x=%.2f" % [me.pos.x, server.sim.players[0].pos.x])
	check("enet: ping estimate exists", cl.ping_ms > 0.0, "ping=%.1f" % cl.ping_ms)
	# an unreliable packet bigger than one MTU must still arrive, and still count as unreliable
	var big := PackedByteArray()
	big.resize(3000)
	for i in big.size():
		big[i] = (i * 7) % 251
	server_ep.send(1, big, false)
	server_ep.flush()
	var got_big := false
	var big_reliable := true
	for _i in 100:
		for ev: Dictionary in client_ep.poll():
			if ev["kind"] == NetEndpoint.Kind.PACKET and ev["data"].size() == 3000:
				got_big = ev["data"] == big
				big_reliable = ev["reliable"]
		if got_big:
			break
		OS.delay_msec(5)
	check("enet: a 3000 byte unreliable packet arrives whole and stays unreliable", got_big and not big_reliable)
	cl.close()
	for _i in 60:
		server.tick()
		OS.delay_msec(5)
		if server.players_online() == 0:
			break
	check("enet: the server notices that the client left", server.players_online() == 0)
	server_ep.close()


func test_menu_online() -> void:   # async: ranges only report changes once the frame after adding them has passed
	NetStore.path = "user://test_online%d.json" % PORT_OFFSET
	var menu := TuningMenu.new()
	root.add_child(menu)
	menu.setup(Config.new())
	await process_frame
	var got: Array = []
	menu.connect_requested.connect(func(a: String) -> void: got.append(["connect", a]))
	menu.disconnect_requested.connect(func() -> void: got.append(["disconnect"]))
	menu.lag_changed.connect(func(ms: float, loss: float) -> void: got.append(["lag", ms, loss]))
	menu.smoothing_changed.connect(func(on: bool) -> void: got.append(["smooth", on]))
	menu._show_page(2)
	check("menu online: the Online page can be shown", menu._online_page.visible and not menu._values_page.visible and not menu._mods_page.visible)
	check("menu online: button states at the start", not menu._connect_btn.disabled and menu._disconnect_btn.disabled)
	menu._address_edit.text = "example.org:1234"
	menu._connect_btn.pressed.emit()
	check("menu online: Connect sends the typed address", got == [["connect", "example.org:1234"]], str(got))
	menu.set_online_status("Connected as player 2", true)
	check("menu online: while connected only Disconnect is enabled", menu._connect_btn.disabled and not menu._disconnect_btn.disabled and menu._online_status.text == "Connected as player 2")
	menu._disconnect_btn.pressed.emit()
	check("menu online: Trennen is announced", got.back() == ["disconnect"])
	got.clear()
	menu._lag_slider.value = 100.0
	menu._loss_slider.value = 7.0
	check("menu online: sliders report delay and loss", got == [["lag", 100.0, 0.0], ["lag", 100.0, 7.0]], str(got))
	check("menu online: the label says per direction and what happens to the ping", menu._lag_label.text.contains("per direction") and menu._lag_label.text.contains("200 ms") and menu._loss_label.text.contains("7 %"), menu._lag_label.text)
	check("menu online: the switch Smooth others is on by default", menu._smooth_check.button_pressed and menu._smooth_check.text == "Smooth others")
	got.clear()
	menu._smooth_check.button_pressed = false
	menu._smooth_check.button_pressed = true
	check("menu online: the switch reports off and on", got == [["smooth", false], ["smooth", true]], str(got))
	menu._smooth_check.button_pressed = false
	menu._on_reset()
	check("menu online: reset on this page clears the lag tool and switches smoothing on", menu._lag_slider.value == 0.0 and menu._loss_slider.value == 0.0 and menu._smooth_check.button_pressed)
	menu.queue_free()


## The real main scene (view, HUD, menu, router) against a real ENet server on localhost.
func test_main_scene() -> void:
	NetStore.path = "user://test_online%d.json" % PORT_OFFSET
	var port := 0
	var server_ep := ENetEndpoint.new()
	for p in range(24650, 24690):
		if server_ep.listen(p, ServerCore.MAX_PENDING) == OK:
			port = p
			break
	var server := ServerCore.new(Config.new(), server_ep, 7, false)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_training()   # the app starts on the main menu; this test is about the Training game
	await process_frame
	check("main: offline at the start", not main._online and main.client == null and main.view.sim == main.sim and main.training and main.screen == main.Screen.GAME and main.hud.visible and not main.hud.play_mode)
	main.cfg.character = 2
	await process_frame
	check("main: offline the player shows the chosen figure and the bots the following ones", main.sim.players[0].skin == 2 and main.sim.players[1].skin == 3 % Config.SKIN_COUNT and main.sim.players[3].skin == 5 % Config.SKIN_COUNT)
	main.menu.set_online_status("x", false)
	main.menu.connect_requested.emit("a b")
	check("main: an unusable address is refused with a message", main.menu._online_status.text == "Invalid address" and main.client == null)
	main.menu.lag_changed.emit(40.0, 0.0)
	main.menu.connect_requested.emit("127.0.0.1:%d" % port)
	check("main: connecting shows a status and keeps the offline game", main.client != null and not main._online and main.menu._online_status.text == "Connecting …" and main.lag.delay_ms == 40.0)
	for _i in 300:
		server.tick()
		OS.delay_msec(10)
		await process_frame
		if main._online:
			break
	check("main: goes online, view and HUD read the predicted sim", main._online and main.view.sim == main.client.sim and main.hud._sim == main.client.sim and main.hud.online)
	check("main: status says which player you are", main.menu._online_status.text == "Connected as player 1", main.menu._online_status.text)
	check("main: the address was remembered (in the test location only)", NetStore.load_address() == "127.0.0.1:%d" % port)
	main.menu.lag_changed.emit(120.0, 5.0)
	check("main: the lag sliders reach the running connection", main.lag.delay_ms == 120.0 and main.lag.loss_pct == 5.0)
	main.cfg.mods_you["twin"] = 2
	for _i in 120:
		server.tick()
		OS.delay_msec(10)
		await process_frame
	check("main: own modifier choice reaches the server", int(server.sim.players[0].mods.get("twin", 0)) == 2 and int(main.client.sim.players[0].mods.get("twin", 0)) == 2)
	main.cfg.character = 3
	for _i in 60:
		server.tick()
		OS.delay_msec(10)
		await process_frame
	check("main: a changed figure choice reaches the server while online", server.sim.players[0].skin == 3 and main.client.sim.players[0].skin == 3)
	check("main: the HUD shows ping and correction", main.hud._net_label.visible and main.hud._net_label.text.begins_with("Ping "), main.hud._net_label.text)
	check("main: the HUD shows the interpolation delay", main.hud._net_label.text.contains("Others ") and main.hud._net_label.text.contains(" ms behind"), main.hud._net_label.text)
	check("main: smoothing is on and the view gets the display sim", main.client.smooth_others and main.view.others_sim != null and main.view.others_sim == main.client.display_sim)
	main.menu.smoothing_changed.emit(false)
	for _i in 3:
		server.tick()
		OS.delay_msec(10)
		await process_frame
	check("main: the switch turns the smoothing off (view back on the predicted sim, HUD says so)", not main.client.smooth_others and main.view.others_sim == null and main.hud._net_label.text.contains("Others raw"), main.hud._net_label.text)
	main.menu.smoothing_changed.emit(true)
	for _i in 3:
		server.tick()
		OS.delay_msec(10)
		await process_frame
	check("main: and on again", main.client.smooth_others and main.view.others_sim != null)
	main.menu.open_menu()
	var tick_open: int = main.client.sim.tick
	for _i in 30:
		server.tick()
		OS.delay_msec(10)
		await process_frame
	check("main: online the sim keeps running while the menu is open", main.client.sim.tick > tick_open + 10)
	main.menu.close_menu()
	main.menu.disconnect_requested.emit()
	check("main: disconnecting falls back to the offline game", not main._online and main.client == null and main.view.sim == main.sim and main.hud._sim == main.sim and not main.hud.online and main.menu._online_status.text == "Disconnected")
	for _i in 30:
		server.tick()
		await process_frame
	check("main: the server sees the player leave", server.players_online() == 0)
	# a server that drops the connection: the game falls back as well
	main.menu.smoothing_changed.emit(false)    # chosen while offline: the next connection starts with it
	main.menu.connect_requested.emit("127.0.0.1:%d" % port)
	for _i in 300:
		server.tick()
		OS.delay_msec(10)
		await process_frame
		if main._online:
			break
	check("main: second connect works", main._online)
	check("main: a smoothing choice made before connecting is kept", not main.client.smooth_others)
	server_ep.close()   # the server vanishes
	var ticks_before: int = main.sim.tick
	for _i in 600:
		OS.delay_msec(10)
		await process_frame
		if not main._online:
			break
	check("main: when the server vanishes the game falls back to offline", not main._online and main.view.sim == main.sim and main.menu._online_status.text == "Connection lost", main.menu._online_status.text)
	for _i in 20:
		await process_frame
	check("main: and the offline sim runs again", main.sim.tick > ticks_before)
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_online%d.json" % PORT_OFFSET))


# ---------------------------------------------------------------- local play: code, beacon, host, menu

const LAN_PORT_BASE := 24700   # + PORT_OFFSET; the discovery tests use their own ports, never the real 24566


## A port that is free for UDP and ENet on localhost, searched from `first` + PORT_OFFSET.
func lan_free_port(first: int) -> int:
	for p in range(first + PORT_OFFSET, first + PORT_OFFSET + 14):
		var u := PacketPeerUDP.new()
		var ok := u.bind(p, "127.0.0.1") == OK
		u.close()
		var e := ENetEndpoint.new()
		var ok2 := e.listen(p, 4) == OK
		e.close()
		if ok and ok2:
			return p
	return 0


func test_lan_code() -> void:
	var samples := ["192.168.0.0", "192.168.1.20", "192.168.43.1", "192.168.255.255", "172.16.0.0", "172.20.10.1", "172.31.255.255",
			"10.0.0.0", "10.1.2.3", "10.255.255.255", "8.8.8.8", "255.255.255.255", "0.0.0.0", "172.32.0.1", "172.15.255.255", "193.168.1.1", "127.0.0.1", "192.169.1.1"]
	var round_ok := true
	var bad := ""
	for ip: String in samples:
		if LanCode.decode(LanCode.encode(ip)) != ip:
			round_ok = false
			bad = ip
	check("lan code: round trip of every class and the edges", round_ok, bad)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rnd_ok := true
	for i in 3000:
		var ip := "%d.%d.%d.%d" % [rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255)]
		if i % 3 == 0:
			ip = "192.168.%d.%d" % [rng.randi_range(0, 255), rng.randi_range(0, 255)]
		elif i % 3 == 1:
			ip = "172.%d.%d.%d" % [rng.randi_range(16, 31), rng.randi_range(0, 255), rng.randi_range(0, 255)]
		if LanCode.decode(LanCode.encode(ip)) != ip:
			rnd_ok = false
			bad = ip
	check("lan code: random addresses survive the round trip", rnd_ok, bad)
	check("lan code: lengths 4 / 5 / 6 / 7 by class", LanCode.encode("192.168.1.20").length() == 4 and LanCode.encode("172.20.1.1").length() == 5
			and LanCode.encode("10.9.8.7").length() == 6 and LanCode.encode("8.8.8.8").length() == 7 and LanCode.encode("172.32.0.1").length() == 7)
	check("lan code: 32 distinct characters without the look-alikes 0 O 1 I", LanCode.ALPHABET.length() == 32 and LanCode.ALPHABET.find("O") < 0 and LanCode.ALPHABET.find("I") < 0
			and LanCode.ALPHABET.find("0") < 0 and LanCode.ALPHABET.find("1") < 0)
	var c := LanCode.encode("192.168.1.20")
	check("lan code: case, spaces and dashes are ignored", LanCode.decode(c.to_lower()) == "192.168.1.20" and LanCode.decode(" " + c.substr(0, 2) + "-" + c.substr(2) + " ") == "192.168.1.20"
			and LanCode.decode(LanCode.grouped(LanCode.encode("10.9.8.7"))) == "10.9.8.7")
	check("lan code: grouped shows 4 characters per group", LanCode.grouped("ABCDEFG") == "ABCD EFG" and LanCode.grouped("ABCD") == "ABCD")
	check("lan code: not an IPv4 address gives an empty code", LanCode.encode("") == "" and LanCode.encode("1.2.3") == "" and LanCode.encode("256.1.1.1") == "" and LanCode.encode("a.b.c.d") == ""
			and LanCode.encode("1.2.3.4.5") == "" and LanCode.encode("::1") == "" and LanCode.encode("01.2.3.4") == "" and LanCode.encode("1.2.3.-4") == "" and LanCode.encode("example.org") == "")
	check("lan code: wrong characters are refused", LanCode.decode("0ABC") == "" and LanCode.decode("OABC") == "" and LanCode.decode("1ABC") == "" and LanCode.decode("IABC") == "" and LanCode.decode("AB!D") == "")
	check("lan code: wrong lengths are refused", LanCode.decode("") == "" and LanCode.decode("ABC") == "" and LanCode.decode(c + "A") == "" and LanCode.decode("ABCDEFGH") == ""
			and LanCode.decode(LanCode.encode("10.9.8.7").substr(0, 5)) == "" and LanCode.decode(LanCode.encode("8.8.8.8") + "A") == "")
	var flipped := c.substr(0, 3) + LanCode.ALPHABET[LanCode.ALPHABET.find(c[3]) ^ 1]
	check("lan code: non-zero padding bits are refused", LanCode.decode(flipped) == "", flipped)
	var canon := true
	for i in 32:
		for j in 32:
			var cd := "A" + LanCode.ALPHABET[i] + LanCode.ALPHABET[j] + "A"
			var d := LanCode.decode(cd)
			if d != "" and LanCode.encode(d) != cd:
				canon = false
	check("lan code: a code that decodes is the canonical code of its address", canon)


func test_pick_address() -> void:
	var lo := {"name": "lo", "addresses": ["127.0.0.1", "::1"]}
	var wlan := {"name": "wlan0", "addresses": ["fe80::1", "192.168.1.5"]}
	var mobile := {"name": "rmnet_data0", "addresses": ["10.20.30.40"]}
	check("pick address: Wi-Fi 192.168 beats mobile data, loopback and IPv6 are never taken", LanCode.pick_local_address([lo, mobile, wlan]) == "192.168.1.5")
	check("pick address: only mobile data still gives its address", LanCode.pick_local_address([lo, mobile]) == "10.20.30.40")
	check("pick address: nothing usable gives an empty string", LanCode.pick_local_address([lo, {"name": "wlan0", "addresses": ["169.254.3.4", "fe80::2"]}]) == "" and LanCode.pick_local_address([]) == "")
	check("pick address: 192.168 beats 172.16/12 beats 10 beats the rest",
			LanCode.pick_local_address([{"name": "eth0", "addresses": ["8.8.4.4"]}, {"name": "eth1", "addresses": ["10.1.1.1"]}, {"name": "eth2", "addresses": ["172.20.0.9"]}]) == "172.20.0.9"
			and LanCode.pick_local_address([{"name": "eth1", "addresses": ["10.1.1.1"]}, {"name": "eth2", "addresses": ["172.20.0.9"]}, {"name": "eth3", "addresses": ["192.168.7.7"]}]) == "192.168.7.7"
			and LanCode.pick_local_address([{"name": "eth0", "addresses": ["8.8.4.4"]}, {"name": "eth1", "addresses": ["10.1.1.1"]}]) == "10.1.1.1")
	check("pick address: the address class counts before the interface name", LanCode.pick_local_address([{"name": "wlan0", "addresses": ["10.0.0.2"]}, {"name": "rmnet0", "addresses": ["192.168.9.9"]}]) == "192.168.9.9")
	check("pick address: among equal addresses Wi-Fi / hotspot names beat unknown, those beat mobile data",
			LanCode.pick_local_address([{"name": "rmnet0", "addresses": ["192.168.9.9"]}, {"name": "ap0", "addresses": ["192.168.43.1"]}]) == "192.168.43.1"
			and LanCode.pick_local_address([{"name": "ccmni1", "addresses": ["192.168.9.9"]}, {"name": "foo0", "addresses": ["192.168.8.8"]}]) == "192.168.8.8"
			and LanCode.pick_local_address([{"name": "foo0", "addresses": ["192.168.8.8"]}, {"name": "swlan0", "addresses": ["192.168.7.1"]}]) == "192.168.7.1"
			and LanCode.pick_local_address([{"name": "pdp0", "addresses": ["10.9.9.9"]}, {"name": "enp3s0", "addresses": ["10.1.1.1"]}]) == "10.1.1.1")
	check("pick address: a PackedStringArray of addresses works too (as the engine returns it)", LanCode.pick_local_address([{"name": "wlan0", "addresses": PackedStringArray(["192.168.2.2"])}]) == "192.168.2.2")


## Only the entries heard from 127.0.0.1 (a test announcer also reaches the machine's real network addresses).
func lan_local_only(games: Array) -> Array:
	return games.filter(func(e: Dictionary) -> bool: return e["ip"] == "127.0.0.1")


func lan_raw_send(port: int, data: PackedByteArray) -> void:
	var u := PacketPeerUDP.new()
	u.set_dest_address("127.0.0.1", port)
	u.put_packet(data)
	u.close()


func lan_wait(listener: LanBeacon, now: int, want: Callable, tries := 60) -> Array:
	var games: Array = []
	for _i in tries:
		games = listener.poll(now)
		if want.call(games):
			break
		OS.delay_msec(10)
	return games


func test_lan_beacon() -> void:
	var pk := LanBeacon.build(NetProto.VERSION, 24565, 2, 4)
	var g := LanBeacon.parse(pk)
	check("beacon: build and parse round trip", pk.size() == LanBeacon.PACKET_SIZE and g == {"version": NetProto.VERSION, "port": 24565, "players": 2, "max": 4}, str(g))
	var wrong_magic := pk.duplicate()
	wrong_magic[0] = 88
	var pl_over := LanBeacon.build(NetProto.VERSION, 24565, 5, 4)
	check("beacon: parse refuses a wrong magic, length, port 0 and more players than places",
			LanBeacon.parse(wrong_magic).is_empty() and LanBeacon.parse(pk.slice(0, 9)).is_empty() and LanBeacon.parse(pk + PackedByteArray([0])).is_empty()
			and LanBeacon.parse(PackedByteArray()).is_empty() and LanBeacon.parse(LanBeacon.build(NetProto.VERSION, 0, 1, 4)).is_empty() and LanBeacon.parse(pl_over).is_empty())
	check("beacon: garbage of any kind is refused without an engine error", LanBeacon.parse("hello world!".to_utf8_buffer()).is_empty() and LanBeacon.parse(var_to_bytes([1, 2])).is_empty())
	var targets := LanBeacon.broadcast_targets([{"name": "wlan0", "addresses": ["192.168.1.7", "fe80::1"]}, {"name": "lo", "addresses": ["127.0.0.1"]},
			{"name": "rmnet0", "addresses": ["10.4.5.6", "169.254.1.1"]}, {"name": "x", "addresses": ["192.168.1.9"]}], ["127.0.0.1"])
	check("beacon: broadcast targets are the global one, a.b.c.255 per network, then the extras", targets == ["255.255.255.255", "192.168.1.255", "10.4.5.255", "127.0.0.1"], str(targets))
	var port := lan_free_port(LAN_PORT_BASE)
	check("beacon: a test port is free", port != 0)
	if port == 0:
		return
	var listener := LanBeacon.new()
	check("beacon: the listener opens its socket", listener.start_listening(port) == OK)
	check("beacon: nothing heard at the start", listener.poll(0).is_empty())
	var ann := LanBeacon.new()
	ann.start_announcing(port, ["127.0.0.1"])
	ann.announce(0, 2, 4)
	var games := lan_local_only(lan_wait(listener, 100, func(a: Array) -> bool: return not lan_local_only(a).is_empty()))
	check("beacon: a real UDP round trip finds the game", games.size() == 1 and games[0]["ip"] == "127.0.0.1" and games[0]["port"] == NetProto.DEFAULT_PORT
			and games[0]["players"] == 2 and games[0]["max"] == 4 and games[0]["code"] == LanCode.encode("127.0.0.1"), str(games))
	check("beacon: an entry stays while it is heard recently and expires after EXPIRE_MS",
			listener.poll(100 + LanBeacon.EXPIRE_MS - 100).size() >= 1 and listener.poll(100 + LanBeacon.EXPIRE_MS + 1).is_empty())
	ann.close()
	# the announcement rate, counted on a raw socket
	var raw := PacketPeerUDP.new()
	var rport := lan_free_port(LAN_PORT_BASE + 14)
	raw.bind(rport, "127.0.0.1")
	var ann2 := LanBeacon.new()
	ann2.start_announcing(rport, ["127.0.0.1"])
	ann2.announce(5000, 1, 4)
	ann2.announce(5500, 1, 4)
	ann2.announce(5000 + LanBeacon.INTERVAL_MS - 1, 1, 4)
	OS.delay_msec(50)
	var first := raw.get_available_packet_count()
	ann2.announce(5000 + LanBeacon.INTERVAL_MS, 3, 4)
	OS.delay_msec(50)
	var second := raw.get_available_packet_count()
	check("beacon: at most one announcement per interval", first == 1 and second == 2, "first=%d second=%d" % [first, second])
	raw.close()
	ann2.close()
	# other protocol versions, garbage and floods
	listener.close()
	check("beacon: the listener restarts", listener.start_listening(port) == OK)
	lan_raw_send(port, LanBeacon.build(NetProto.VERSION + 1, 24565, 1, 4))
	lan_raw_send(port, "not a beacon".to_utf8_buffer())
	lan_raw_send(port, LanBeacon.build(NetProto.VERSION, 0, 1, 4))
	OS.delay_msec(50)
	check("beacon: another protocol version, garbage and an invalid packet are ignored", listener.poll(0).is_empty())
	for i in 40:
		lan_raw_send(port, LanBeacon.build(NetProto.VERSION, 1000 + i, 1, 4))
	OS.delay_msec(100)
	games = listener.poll(0)
	check("beacon: a flood of different games keeps at most MAX_GAMES", games.size() == LanBeacon.MAX_GAMES, str(games.size()))
	games = listener.poll(0)
	check("beacon: the remembered games stay at the cap", games.size() == LanBeacon.MAX_GAMES)
	listener.close()
	listener.start_listening(port)
	for _i in LanBeacon.MAX_PACKETS_PER_POLL + 6:
		lan_raw_send(port, LanBeacon.build(NetProto.VERSION, 5000, 1, 4))
	lan_raw_send(port, LanBeacon.build(NetProto.VERSION, 6000, 2, 4))
	OS.delay_msec(100)
	games = listener.poll(0)
	var ports1: Array = games.map(func(e: Dictionary) -> int: return e["port"])
	games = listener.poll(0)
	var ports2: Array = games.map(func(e: Dictionary) -> int: return e["port"])
	check("beacon: one poll reads only a capped number of packets", ports1 == [5000] and ports2 == [5000, 6000], "%s %s" % [ports1, ports2])
	listener.close()
	check("beacon: after close nothing is heard and the port can be bound again", listener.poll(0).is_empty() and listener.start_listening(port) == OK)
	listener.close()
	var busy := PacketPeerUDP.new()
	busy.bind(port, "0.0.0.0")
	check("beacon: a port that is taken gives an error and no crash", LanBeacon.new().start_listening(port) != OK)
	busy.close()


func test_local_host() -> void:
	var port := lan_free_port(LAN_PORT_BASE + 28)
	var bport := lan_free_port(LAN_PORT_BASE + 42)
	check("local host: test ports are free", port != 0 and bport != 0)
	if port == 0 or bport == 0:
		return
	var cfg := Config.new()
	cfg.player_speed = 7.5
	var host := LocalHost.new()
	host.beacon_port = bport
	host.beacon_targets = ["127.0.0.1"]
	check("local host: starts on a test port", host.start(cfg, true, port) == OK and host.is_running())
	cfg.player_speed = 9.5
	check("local host: the match runs on a copy of the host's values", host.core.cfg != cfg and is_equal_approx(host.core.cfg.player_speed, 7.5), str(host.core.cfg.player_speed))
	check("local host: with bots the free places are bots", host.core.sim.players[2].enabled)
	var listener := LanBeacon.new()
	check("local host: the discovery listener opens", listener.start_listening(bport) == OK)
	var ep := ENetEndpoint.new()
	check("local host: the own client socket opens", ep.connect_to("127.0.0.1", port) == OK)
	var cl := ClientCore.new(ep)
	cl.set_mods({"twin": 2})   # a client that tries to bring modifiers into the match
	var found: Array = []
	var t_before: int = host.core.sim.tick
	host.process(10.0)
	check("local host: after a long stall the host catches up by a few ticks only", host.core.sim.tick - t_before == ServerCore.MAX_TICKS_PER_FRAME, str(host.core.sim.tick - t_before))
	for _i in 300:
		host.process(1.0 / 60.0)
		cl.poll(1.0 / 60.0)
		cl.tick(SimInput.new() if cl.state != ClientCore.State.ONLINE else inp(Vector2.RIGHT))
		found = lan_local_only(listener.poll(0))
		OS.delay_msec(8)
		if cl.state == ClientCore.State.ONLINE and cl.snapshots_applied > 10 and found.size() > 0 and found[0]["players"] == 1:
			break
	check("local host: a client over real ENet to 127.0.0.1 gets online as player 1", cl.state == ClientCore.State.ONLINE and cl.slot == 0 and host.players() == 1, "state=%d" % cl.state)
	check("local host: the client plays with the host's values", is_equal_approx(cl.sim.cfg.player_speed, 7.5), str(cl.sim.cfg.player_speed))
	check("local host: the host's server ignores the modifiers a client sends", not host.core.accept_client_mods and int(host.core.sim.players[0].mods.get("twin", 0)) == 0 and int(cl.sim.players[0].mods.get("twin", 0)) == 2)
	check("local host: the server runs ticks and gets the client's inputs", host.core.sim.tick > 20 and host.core.slots[0].last_consumed > 5)
	check("local host: it announces itself with the player count and its port", found.size() == 1 and found[0]["players"] == 1 and found[0]["max"] == Config.NUM_PLAYERS and found[0]["port"] == port, str(found))
	check("local host: the code is the code of the address", host.code() == LanCode.encode(host.address()))
	cl.close()
	for _i in 30:
		host.process(1.0 / 60.0)
		OS.delay_msec(5)
	check("local host: it notices the client leaving", host.players() == 0)
	host.stop()
	check("local host: stop ends the match", not host.is_running() and host.players() == 0)
	listener.start_listening(bport)   # fresh: forgets what it heard before
	OS.delay_msec(1300)
	check("local host: nothing is announced after stop", lan_local_only(listener.poll(0)).is_empty())
	listener.close()
	var again := LocalHost.new()
	again.beacon_port = bport
	check("local host: after stop the port is free (a second start on it works), without bots the places stay empty", again.start(Config.new(), false, port) == OK and not again.core.sim.players[2].enabled)
	var third := LocalHost.new()
	check("local host: a port that is taken is reported", third.start(Config.new(), false, port) != OK and not third.is_running())
	again.stop()
	again.stop()
	check("local host: stopping twice is harmless", not again.is_running())


func test_menu_local() -> void:   # async
	var port := lan_free_port(LAN_PORT_BASE + 56)
	var menu := PlayLobby.new()
	root.add_child(menu)
	menu.setup(Config.new())
	await process_frame
	var got: Array = []
	menu.host_requested.connect(func(b: bool) -> void: got.append(["host", b]))
	menu.stop_requested.connect(func() -> void: got.append(["stop"]))
	menu.join_code_requested.connect(func(c: String) -> void: got.append(["code", c]))
	menu.join_local_requested.connect(func(ip: String, p: int) -> void: got.append(["join", ip, p]))
	var now := [1000]
	menu.clock = func() -> int: return now[0]
	menu.discovery_port = port
	await process_frame
	check("lobby local: no listener while the lobby is not shown", menu._listener == null)
	menu.open()
	await process_frame
	check("lobby local: the listener runs on the page and the list is empty", menu._listener != null and menu._empty_label.visible and menu._empty_label.text == "No game found yet" and menu._found_buttons.is_empty())
	check("lobby local: Fill with bots is on by default and the buttons start right", menu._bots_check.button_pressed and menu._bots_check.text == "Fill with bots"
			and menu._host_btn.text == "Host a game" and not menu._host_btn.disabled and menu._stop_btn.text == "Stop" and menu._stop_btn.disabled and not menu._hosting_box.visible)
	menu._host_btn.pressed.emit()
	menu._bots_check.button_pressed = false
	menu._host_btn.pressed.emit()
	menu._code_edit.text = "ab cd"
	menu._join_btn.pressed.emit()
	check("lobby local: Host a game reports the bot choice, Join the typed code", got == [["host", true], ["host", false], ["code", "ab cd"]], str(got))
	var ann := LanBeacon.new()
	ann.start_announcing(port, ["127.0.0.1"])
	ann.announce(0, 1, 4, 24999)
	for _i in 30:
		await process_frame
		OS.delay_msec(10)
		if not menu._found_buttons.is_empty():
			break
	var key := "127.0.0.1:24999"
	check("lobby local: a found game shows up as a button with code and players", menu._found_buttons.has(key) and not menu._empty_label.visible
			and (menu._found_buttons[key] as Button).text == "Game %s – 1/4 players" % LanCode.grouped(LanCode.encode("127.0.0.1")), str(menu._found_buttons.keys()))
	got.clear()
	(menu._found_buttons[key] as Button).pressed.emit()
	check("lobby local: pressing the game reports its address and port", got == [["join", "127.0.0.1", 24999]], str(got))
	now[0] += LanBeacon.EXPIRE_MS + 500
	await process_frame
	await process_frame
	check("lobby local: a game that is no longer heard disappears", menu._found_buttons.is_empty() and menu._empty_label.visible)
	menu.set_status("Invalid code")
	check("lobby local: the lobby has a status of its own", menu._status.text == "Invalid code")
	menu.set_session(true, true, "ABCDE", 2)
	await process_frame
	check("lobby local: while hosting the listener is closed, the code is shown grouped and big", menu._listener == null and menu._hosting_box.visible and menu._code_label.text == "ABCD E"
			and menu._code_label.get_theme_font_size("font_size") >= 60 and menu._players_label.text == "Players: 2 of %d" % Config.NUM_PLAYERS)
	check("lobby local: while hosting only Stop is enabled", menu._host_btn.disabled and menu._join_btn.disabled and not menu._stop_btn.disabled)
	menu._stop_btn.pressed.emit()
	check("lobby local: Stop is announced", got.back() == ["stop"])
	menu.set_session(true, true, "", 1)
	check("lobby local: without an address the page says so", menu._code_label.text == "" and menu._players_label.text.contains("No network address"))
	menu.set_session(false, true, "", 0)
	await process_frame
	check("lobby local: as a guest there is no listener either and Stop works", menu._listener == null and not menu._hosting_box.visible and not menu._stop_btn.disabled and menu._host_btn.disabled)
	menu.set_session(false, false, "", 0)
	await process_frame
	check("lobby local: back to nothing, the listener runs again", menu._listener != null and not menu._host_btn.disabled and menu._stop_btn.disabled)
	menu.close()
	await process_frame
	check("lobby local: closing the lobby closes the listener", menu._listener == null)
	ann.close()
	menu.queue_free()
	await process_frame


func test_main_local() -> void:   # async
	NetStore.path = "user://test_online%d.json" % PORT_OFFSET
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NetStore.path))
	var port := lan_free_port(LAN_PORT_BASE + 70)
	var bport := lan_free_port(LAN_PORT_BASE + 84)
	check("main local: test ports are free", port != 0 and bport != 0)
	if port == 0 or bport == 0:
		return
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.local_port = port
	main.beacon_port = bport
	main.beacon_targets = ["127.0.0.1"]
	main.lobby.discovery_port = bport
	await process_frame
	main.main_menu.play_btn.pressed.emit()
	check("main local: Play opens the lobby", main.screen == main.Screen.LOBBY and main.lobby.visible and not main.main_menu.visible)
	main.lobby.join_code_requested.emit("0000")
	check("main local: an invalid code shows a status and does not connect", main.lobby._status.text == "Invalid code" and main.client == null and not main._online)
	main.lobby.join_code_requested.emit("")
	check("main local: an empty code is invalid too", main.lobby._status.text == "Invalid code" and main.client == null)
	main.lobby.join_local_requested.emit("not an address", port)
	check("main local: a found game with a bad address is refused", main.lobby._status.text == "Invalid address" and main.client == null)
	# join by code: an ordinary server on the local port
	var server_ep := ENetEndpoint.new()
	check("main local: the test server listens", server_ep.listen(port, ServerCore.MAX_PENDING) == OK)
	var server := ServerCore.new(Config.new(), server_ep, 7, false)
	main.lobby.join_code_requested.emit(LanCode.grouped(LanCode.encode("127.0.0.1")).to_lower())
	check("main local: joining by code connects and shows the status in the lobby", main.client != null and main.lobby._status.text == "Connecting …")
	for _i in 300:
		server.tick()
		OS.delay_msec(10)
		await process_frame
		if main._online:
			break
	check("main local: joined by code (lower case, with a space)", main._online and main.local_host == null and main.lobby._status.text == "Connected as player 1", main.lobby._status.text)
	check("main local: the lobby knows it is connected", not main.lobby._stop_btn.disabled and main.lobby._host_btn.disabled)
	check("main local: a local join does not overwrite the saved Online address", NetStore.load_address() == "")
	check("main local: a joiner waits in the lobby while the server's phase is OFF (no game screen)", main.screen == main.Screen.LOBBY and main.lobby.visible and not main.training and not main.hud.visible and main.lobby.wait_label.visible and not main.lobby.start_btn.visible)
	server.sim.mode.phase = MatchMode.Phase.COUNTDOWN   # the server's match starts
	for _i in 300:
		server.tick()
		OS.delay_msec(10)
		await process_frame
		if main.screen == main.Screen.GAME:
			break
	check("main local: when the match starts the joiner goes to the game, no lobby, only the pause button", main.screen == main.Screen.GAME and not main.training and not main.lobby.visible and main.hud.visible and main.hud.play_mode)
	main.pause.main_menu_btn.pressed.emit()
	check("main local: Main menu leaves the game as a guest and shows the main menu", not main._online and main.client == null and main.lobby._status.text == "Disconnected" and main.view.sim == main.sim and main.screen == main.Screen.MENU and main.main_menu.visible)
	# joining a game from the list: its own port counts, not the local port
	var list_ep := ENetEndpoint.new()
	check("main local: a second test server listens", list_ep.listen(bport, ServerCore.MAX_PENDING) == OK)
	var list_server := ServerCore.new(Config.new(), list_ep, 7, false)
	main._show_lobby()
	list_server.sim.mode.phase = MatchMode.Phase.MATCH_OVER   # a match that has just ended: joining is open
	main.lobby.join_local_requested.emit("127.0.0.1", bport)
	for _i in 300:
		list_server.tick()
		OS.delay_msec(10)
		await process_frame
		if main._online:
			break
	for _i in 10:
		list_server.tick()
		await process_frame
	check("main local: a joiner who arrives at match over goes straight to the game", main.screen == main.Screen.GAME and main.client.sim.mode.phase == MatchMode.Phase.MATCH_OVER)
	check("main local: joining a found game connects to the port it announced", main._online and list_server.players_online() == 1 and main.lobby._status.text == "Connected as player 1")
	main.lobby.stop_requested.emit()
	check("main local: Stop leaves a joined game and goes to the main menu", not main._online and main.screen == main.Screen.MENU)
	list_ep.close()
	# hosting while the port is taken
	main._show_lobby()
	main.lobby.host_requested.emit(true)
	check("main local: hosting on a port that is taken says so", main.local_host == null and main.client == null and main.lobby._status.text.begins_with("Could not open the game"), main.lobby._status.text)
	server_ep.close()
	main.train_cfg.player_speed = 7.5
	main.train_cfg.mods_you["twin"] = 2   # tuned values and sandbox modifiers of Training
	main.lobby.host_requested.emit(true)
	check("main local: hosting starts a host and connects the own client", main.local_host != null and main.client != null and main.lobby._status.text == "Connecting …")
	for _i in 300:
		await process_frame
		OS.delay_msec(10)
		if main._online:
			break
	check("main local: the host goes online as a player through the real main scene", main._online and main.client.slot == 0 and main.local_host.players() == 1 and main.lobby._status.text == "Connected as player 1")
	check("main local: the match uses the fixed default values, not the tuned ones", is_equal_approx(main.client.sim.cfg.player_speed, Config.DEFAULTS["player_speed"]) and is_equal_approx(main.local_host.core.cfg.player_speed, Config.DEFAULTS["player_speed"]) and main.cfg == main.play_cfg and not main.training)
	check("main local: the page shows the code and the player count", main.lobby._hosting_box.visible and main.lobby._players_label.text.begins_with("Players: 1 of")
			and (main.local_host.code() == "" or main.lobby._code_label.text == LanCode.grouped(main.local_host.code())), main.lobby._players_label.text)
	check("main local: hosting did not touch the saved Online address", NetStore.load_address() == "")
	check("main local: the host waits in the lobby with Start match, enabled with the bots", main.screen == main.Screen.LOBBY and main.lobby.start_btn.visible and not main.lobby.start_btn.disabled and not main.lobby.wait_label.visible and main.local_host.core.sim.mode.phase == MatchMode.Phase.OFF)
	main.lobby.start_btn.pressed.emit()
	for _i in 300:
		await process_frame
		OS.delay_msec(10)
		if main.screen == main.Screen.GAME:
			break
	check("main local: Start match starts the match on the server and moves the host to the game", main.local_host.core.sim.mode.phase == MatchMode.Phase.COUNTDOWN and main.local_host.core.sim.mode.target == main.train_cfg.target_score and main.screen == main.Screen.GAME and main.client.sim.mode.phase != MatchMode.Phase.OFF)
	var hmode: MatchMode = main.local_host.core.sim.mode
	hmode.points[0] = 4
	hmode.phase = MatchMode.Phase.MATCH_OVER
	hmode.phase_t = 5.0
	main._rematch()
	check("main local: the host's Rematch restarts the match with the same target and zero points", hmode.phase == MatchMode.Phase.COUNTDOWN and hmode.points[0] == 0 and hmode.round == 1 and hmode.target == main.train_cfg.target_score)
	var tick0: int = main.local_host.core.sim.tick
	main.hud.gear_pressed.emit()
	for _i in 30:
		await process_frame
		OS.delay_msec(10)
	check("main local: the host keeps serving while the pause panel is open", main.pause.visible and main.local_host.core.sim.tick > tick0 + 10 and main.lobby._listener == null)
	check("main local: the host player has no modifiers (the Play client sends none)", main.local_host.core.sim.players[0].mods.values().all(func(v: int) -> bool: return v == 0) and main.client.sim.players[0].mods.values().all(func(v: int) -> bool: return v == 0))
	main.menu.lag_changed.emit(30.0, 0.0)
	check("main local: the lag tool works on the own client", main.lag.delay_ms == 30.0)
	var host: LocalHost = main.local_host
	main.pause.main_menu_btn.pressed.emit()
	check("main local: Main menu stops the host and leaves the session", main.local_host == null and not host.is_running() and not main._online and main.client == null
			and main.view.sim == main.sim and main.lobby._status.text == "Game ended" and not main.lobby._hosting_box.visible and main.screen == main.Screen.MENU and not main.pause.visible)
	var probe := ENetEndpoint.new()
	check("main local: the port is free again", probe.listen(port, 4) == OK)
	probe.close()
	main._show_lobby()
	main.lobby.host_requested.emit(false)
	for _i in 300:
		await process_frame
		OS.delay_msec(10)
		if main._online:
			break
	check("main local: hosting without bots", main._online and not main.local_host.core.sim.players[2].enabled)
	check("main local: Start match is disabled and refused with one player", main.lobby.start_btn.visible and main.lobby.start_btn.disabled and not main._start_hosted_match() and main.local_host.core.sim.mode.phase == MatchMode.Phase.OFF and main.screen == main.Screen.LOBBY)
	main.menu.disconnect_requested.emit()
	check("main local: leaving from the Online page stops the host as well (from the lobby it stays there)", main.local_host == null and not main._online and main.screen == main.Screen.LOBBY)
	main._show_lobby()
	main.lobby.host_requested.emit(true)
	for _i in 300:
		await process_frame
		OS.delay_msec(10)
		if main._online:
			break
	main.menu.connect_requested.emit("a b")
	check("main local: connecting elsewhere leaves and stops the host", main.local_host == null and main.client == null)
	main._show_lobby()
	main.lobby.host_requested.emit(true)
	var host2: LocalHost = main.local_host
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check("main local: closing the app stops the host", main.local_host == null and not host2.is_running())
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_online%d.json" % PORT_OFFSET))


## Ticks the server (if any) and waits one frame per round, until `until` is true (false: gave up after max_frames).
func spin(server: ServerCore, max_frames: int, until: Callable) -> bool:
	for _i in max_frames:
		if server != null:
			server.tick()
		OS.delay_msec(10)
		await process_frame
		if until.call():
			return true
	return false


## A Play joiner whose connection breaks in a match: it reconnects to the same slot, gives up after a while, and the
## Rejoin button of the lobby brings it back. Real ENet on localhost; "the connection breaks" = the server stops
## sending for a few seconds.
func test_main_rejoin() -> void:   # async
	NetStore.path = "user://test_online%d.json" % PORT_OFFSET
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NetStore.path))
	var port := lan_free_port(LAN_PORT_BASE + 100)
	check("main rejoin: test port is free", port != 0)
	if port == 0:
		return
	var M := MatchMode.Phase
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.local_port = port
	main.beacon_port = lan_free_port(LAN_PORT_BASE + 110)
	main.beacon_targets = ["127.0.0.1"]
	main.lobby.discovery_port = main.beacon_port
	await process_frame
	var ep := ENetEndpoint.new()
	ep.listen(port, ServerCore.MAX_PENDING)
	var server := ServerCore.new(Config.new(), ep, 7, true)
	main._show_lobby()
	check("main rejoin: no Rejoin button without a stored game", not main.lobby.rejoin_btn.visible)
	main.lobby.join_local_requested.emit("127.0.0.1", port)
	await spin(server, 300, func() -> bool: return main._online)
	var slot: int = main.client.slot
	check("main rejoin: joined", main._online and main.screen == main.Screen.LOBBY and NetStore.load_last_game().is_empty())
	server.start_match(10)
	await spin(server, 600, func() -> bool: return main.screen == main.Screen.GAME and main.client.sim.mode.phase == M.PLAY)
	server.sim.mode.points[slot] = 2
	await spin(server, 20, func() -> bool: return false)
	check("main rejoin: during a match the game is stored (memory and file)", main._last_game == {"host": "127.0.0.1", "port": port} and NetStore.load_last_game() == {"host": "127.0.0.1", "port": port})
	check("main rejoin: the token of the install is the one the server holds", server.slots[slot].token == NetStore.token() and NetStore.token() == main.client.token)
	# the connection breaks: the server goes quiet
	await spin(null, 600, func() -> bool: return main._reconnecting)
	check("main rejoin: a lost connection enters the reconnect state and stays on the game screen", main._reconnecting and main.screen == main.Screen.GAME and not main._online and main.lobby._status.text == "Reconnecting …", main.lobby._status.text)
	await process_frame
	var tick_frozen: int = main._frozen.tick
	var offline_tick: int = main.sim.tick
	await spin(null, 30, func() -> bool: return false)
	check("main rejoin: the offline sim stands still while reconnecting", main._reconnecting and main.sim.tick == offline_tick)
	check("main rejoin: the overlay shows Reconnecting and the game state stays drawn", main.overlay.reconnect_panel.visible and not main.overlay.countdown_label.visible and main.view.sim == main._frozen and main._frozen.tick == tick_frozen)
	# the server is reachable again: the old connection is taken over
	await spin(server, 900, func() -> bool: return main._online and not main._reconnecting)
	check("main rejoin: the player is back in the same slot with the points, still on the game screen", main._online and main.client.slot == slot and main.client.sim.mode.points[slot] == 2 and main.screen == main.Screen.GAME and server.players_online() == 1, "slot=%d" % main.client.slot)
	await process_frame
	check("main rejoin: the reconnect panel is gone", not main.overlay.reconnect_panel.visible and main.view.sim == main.client.sim)
	# lost again, and the server is gone for good: gives up into the main menu
	ep.close()
	await spin(null, 600, func() -> bool: return main._reconnecting)
	check("main rejoin: lost again enters reconnect", main._reconnecting)
	main._reconnect_left = 0.3
	await spin(null, 300, func() -> bool: return not main._reconnecting)
	check("main rejoin: giving up goes to the main menu with 'Connection lost'", not main._reconnecting and main.screen == main.Screen.MENU and main.lobby._status.text == "Connection lost" and main.client == null, main.lobby._status.text)
	check("main rejoin: the stored game stays for the Rejoin button", not main._last_game.is_empty() and NetStore.load_last_game() == {"host": "127.0.0.1", "port": port})
	main._show_lobby()
	await process_frame
	check("main rejoin: the lobby shows Rejoin", main.lobby.rejoin_btn.visible)
	# the server (a fresh one, free play) is back: Rejoin joins through the normal path
	var ep2 := ENetEndpoint.new()
	ep2.listen(port, ServerCore.MAX_PENDING)
	var server2 := ServerCore.new(Config.new(), ep2, 7, true)
	main.lobby.rejoin_btn.pressed.emit()
	await spin(server2, 300, func() -> bool: return main._online)
	check("main rejoin: the Rejoin button joins the stored game", main._online and server2.players_online() == 1 and not main.lobby.rejoin_btn.visible)
	# a match, a lost connection, and Main menu during the reconnect cancels it and forgets the game
	server2.start_match(10)
	await spin(server2, 600, func() -> bool: return main.screen == main.Screen.GAME and main.client.sim.mode.phase == M.PLAY)
	await spin(null, 600, func() -> bool: return main._reconnecting)
	check("main rejoin: second reconnect state", main._reconnecting)
	main.overlay.main_menu_pressed.emit()
	check("main rejoin: Main menu cancels the reconnect and forgets the game", not main._reconnecting and main.client == null and main.screen == main.Screen.MENU and main._last_game.is_empty() and NetStore.load_last_game().is_empty())
	for _i in 100:
		server2.tick()
		await process_frame
	check("main rejoin: no attempt goes on after cancelling", main.client == null and not main._online)
	# a refused rejoin shows the status and clears the stored game
	main._last_game = {"host": "127.0.0.1", "port": port}
	NetStore.save_last_game("127.0.0.1", port)
	for sl in server2.slots:
		if sl.away:
			sl.reset()   # nobody holds a place for this token any more
	main._show_lobby()
	main.lobby.rejoin_btn.pressed.emit()
	# the match on server2 is still running (PLAY) and the token has no place: refused with 'started'
	await spin(server2, 300, func() -> bool: return main.client == null)
	check("main rejoin: a refused rejoin shows the status and clears the stored game", main.lobby._status.text == "The match has already started." and main._last_game.is_empty() and NetStore.load_last_game().is_empty() and not main._online, main.lobby._status.text)
	ep2.close()
	# the host is gone for good: a Rejoin that cannot connect also clears the stored game (no button forever)
	main._last_game = {"host": "127.0.0.1", "port": port}
	NetStore.save_last_game("127.0.0.1", port)
	main._show_lobby()
	main.lobby.rejoin_btn.pressed.emit()
	await spin(null, 900, func() -> bool: return main.client == null)
	await process_frame
	check("main rejoin: a rejoin to a host that is gone clears the stored game and hides the button", main.client == null and not main._online and main._last_game.is_empty() and NetStore.load_last_game().is_empty() and not main.lobby.rejoin_btn.visible, main.lobby._status.text)
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_online%d.json" % PORT_OFFSET))


## Rounds and points in Play: the target choice, Solo starting a match, the overlay texts, the rematch.
func test_match_flow() -> void:   # async
	NetStore.path = "user://test_online%d.json" % PORT_OFFSET
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	main.lobby.save_fn = func(_c: Config) -> void: pass   # never write the real settings
	var ov: MatchOverlay = main.overlay
	check("match: the target defaults to 10", main.train_cfg.target_score == 10 and main.lobby.target_buttons[0].button_pressed)
	main.main_menu.play_btn.pressed.emit()
	await process_frame
	main.lobby.target_buttons[1].pressed.emit()
	check("match: choosing First to 15 in the lobby is kept in the settings", main.train_cfg.target_score == 15 and main.train_cfg.to_dict()["target_score"] == 15 and main.lobby.target_buttons[1].button_pressed and not main.lobby.target_buttons[0].button_pressed)
	check("match: the target is copied into the Play config, not reset by Reset", main._make_play_cfg().target_score == 15 and (func() -> bool:
		var c := Config.new()
		c.from_dict(main.train_cfg.to_dict())
		c.reset()
		return c.target_score == 15).call())
	main.lobby.solo_btn.pressed.emit()
	for _i in 3:
		await process_frame
	var m: MatchMode = main.sim.mode
	check("match: Solo starts a match in the countdown with the chosen target and all players in it", m.phase == MatchMode.Phase.COUNTDOWN and m.target == 15 and m.round == 1 and m.roster[0] and m.roster[1] and main.play_cfg.target_score == 15 and main.screen == main.Screen.GAME)
	check("match: the countdown shows 3", ov.countdown_label.visible and ov.countdown_label.text == "3" and not ov.panel.visible)
	m.phase_t = 1.3
	await process_frame
	check("match: then 2", ov.countdown_label.text == "2")
	m.phase_t = 2.3
	await process_frame
	check("match: then 1", ov.countdown_label.text == "1")
	m.phase_t = 2.99
	for _i in 100:
		await process_frame
		if m.phase == MatchMode.Phase.PLAY:
			break
	check("match: GO! shows when play begins", m.phase == MatchMode.Phase.PLAY and ov.countdown_label.visible and ov.countdown_label.text == "GO!")
	ov.update(main.sim, 0, true, true, true, 1.0)
	check("match: GO! goes away and nothing is shown during play", m.phase == MatchMode.Phase.PLAY and not ov.countdown_label.visible and not ov.panel.visible)
	# result
	m.phase = MatchMode.Phase.RESULT
	m.phase_t = 0.2
	m.last_scorer = 2
	m.points[2] = 1
	await process_frame
	check("match: the result panel waits a moment after the last hit", not ov.panel.visible)
	m.phase_t = 1.0
	await process_frame
	var bot2: String = ToyFigure.NAMES[main.sim.players[2].skin] + " (bot)"
	var row0: Node = ov.rows_box.get_child(0)
	check("match: the result panel names the round and the scorer", ov.panel.visible and ov.heading_label.text == "Round 1" and ov.scorer_label.text == bot2 + " scores!" and not ov.rematch_btn.visible, ov.scorer_label.text)
	check("match: the scoreboard lists every player, the leader first with its point and the marker", ov.rows_box.get_child_count() == Config.NUM_PLAYERS and row0.get_child(1).text == bot2 and row0.get_child(2).text == "+1" and row0.get_child(3).text == "1" and ov.target_label.text == "FIRST TO 15",
			"%d %s %s %s %s" % [ov.rows_box.get_child_count(), row0.get_child(1).text, row0.get_child(2).text, row0.get_child(3).text, ov.target_label.text])
	m.last_scorer = -1
	ov._shown_key = ""
	await process_frame
	check("match: simultaneous deaths show Nobody scores", ov.scorer_label.text == "Nobody scores")
	m.last_scorer = 0
	ov._shown_key = ""
	await process_frame
	check("match: the own score says You", ov.scorer_label.text == "You score!")
	# match over and rematch
	m.points[0] = 15
	m.winner = 0
	m.phase = MatchMode.Phase.MATCH_OVER
	m.phase_t = 0.3
	await process_frame
	check("match: match over also waits a moment", not ov.panel.visible)
	m.phase_t = 1.0
	await process_frame
	check("match: match over names the winner and offers Rematch and Main menu", ov.panel.visible and ov.heading_label.text == "You win the match!" and ov.rematch_btn.visible and not ov.wait_label.visible and ov.main_menu_btn.visible)
	m.winner = 3
	m.points[3] = 15
	ov._shown_key = ""
	await process_frame
	check("match: another winner is named by figure", ov.heading_label.text == ToyFigure.NAMES[main.sim.players[3].skin] + " (bot) wins the match!")
	ov.update(main.sim, 0, true, false, false, 0.0)
	check("match: a joiner sees Waiting for the host instead of Rematch", not ov.rematch_btn.visible and ov.wait_label.visible and ov.heading_label.text == ToyFigure.NAMES[main.sim.players[3].skin] + " wins the match!")
	ov.rematch_btn.pressed.emit()
	ov.update(main.sim, 0, true, true, true, 0.0)
	ov.rematch_btn.pressed.emit()
	await process_frame
	check("match: Rematch starts again with zero points and the same target", m.phase == MatchMode.Phase.COUNTDOWN and m.round == 1 and m.points.all(func(v: int) -> bool: return v == 0) and m.target == 15 and m.winner == -1 and not ov.panel.visible)
	m.phase = MatchMode.Phase.MATCH_OVER
	m.phase_t = 1.0
	await process_frame
	ov.main_menu_btn.pressed.emit()
	await process_frame
	check("match: Main menu of the match-over panel leaves to the main menu", main.screen == main.Screen.MENU and not ov.visible)
	# Training has no match
	main.main_menu.training_btn.pressed.emit()
	for _i in 10:
		await process_frame
	check("match: Training starts no match and shows no overlay", main.training and main.sim.mode.phase == MatchMode.Phase.OFF and not ov.visible and not ov.countdown_label.visible)
	main.queue_free()
	await process_frame


## A default server takes the modifiers a client sends (`--server`, the Online tab); one with `accept_client_mods`
## off (the host of a Play match) does not.
func test_client_mods() -> void:
	var open_rig := make_rig(0.0, 0.0, 1, 3)
	var c: ClientCore = open_rig["clients"][0]
	c.set_mods({"twin": 2})
	warm_up(open_rig)
	for _t in 30:
		step_rig(open_rig, func(_k: int) -> SimInput: return SimInput.new())
	var server: ServerCore = open_rig["server"]
	check("client mods: a default server accepts them", server.accept_client_mods and int(server.sim.players[c.slot].mods.get("twin", 0)) == 2)
	var fixed_rig := make_rig(0.0, 0.0, 1, 3)
	(fixed_rig["server"] as ServerCore).accept_client_mods = false
	var c2: ClientCore = fixed_rig["clients"][0]
	c2.set_mods({"twin": 2})
	warm_up(fixed_rig)
	for _t in 30:
		step_rig(fixed_rig, func(_k: int) -> SimInput: return SimInput.new())
	var server2: ServerCore = fixed_rig["server"]
	check("client mods: a server with fixed values ignores them", int(server2.sim.players[c2.slot].mods.get("twin", 0)) == 0 and int(c2.sim.players[c2.slot].mods.get("twin", 0)) == 2)
	check("client mods: ... and nothing counts as a protocol error", server2.dropped_packets == 0 and server2.rejected == 0)


## The real main scene from the main menu: Play (fixed values) against Training (tuned values), pause, back.
func test_main_menu() -> void:   # async
	NetStore.path = "user://test_online%d.json" % PORT_OFFSET
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	check("menu: the app starts on the main menu over the arena", main.screen == main.Screen.MENU and main.main_menu.visible and not main.lobby.visible and not main.hud.visible and not main.pause.visible)
	check("menu: the sim does not tick while the main menu is open", main.sim.tick == 0)
	check("menu: the buttons are Play, Training and Settings (no Character button)", main.main_menu.play_btn.text == "Play" and main.main_menu.training_btn.text == "Training" and main.main_menu.settings_btn.text == "Settings"
			and not main.main_menu.find_children("*", "Button", true, false).any(func(b: Button) -> bool: return b.text.contains("Character")))
	check("menu: the title and the line are there, the version at the bottom", main.main_menu.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Spinback Rumble") and main.main_menu.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Yo-yo brawls in the playroom. 2 to 8 players.") and main.main_menu.version_label.text == "Version " + UpdateCheck.running_version())
	check("menu: the input is blocked behind the menu", main.router.blocked)
	# tuned values and sandbox modifiers in the saved config
	main.train_cfg.player_speed = 9.0
	main.train_cfg.dash_distance = 7.0
	main.train_cfg.mods_you["twin"] = 3
	main.train_cfg.mods_bots["pierce"] = 2
	main.train_cfg.bot_mode = Config.BotMode.DUMMY
	main.train_cfg.character = 3
	main.main_menu.play_btn.pressed.emit()
	await process_frame
	check("menu: Play opens the lobby, the sim still stands", main.screen == main.Screen.LOBBY and main.lobby.visible and not main.main_menu.visible and main.sim.tick == 0)
	main.lobby.solo_btn.pressed.emit()
	for _i in 30:
		await process_frame
	var pcfg: Config = main.sim.cfg
	check("play: a solo game runs on the default values, not the tuned ones", main.screen == main.Screen.GAME and not main.training and main.cfg == main.play_cfg and pcfg == main.play_cfg and main.play_cfg != main.train_cfg
			and pcfg.player_speed == Config.DEFAULTS["player_speed"] and pcfg.dash_distance == Config.DEFAULTS["dash_distance"] and main.sim.tick > 10, str(pcfg.player_speed))
	check("play: no modifier levels, for the player or the bots", Mods.ORDER.all(func(id: String) -> bool: return pcfg.mods_you[id] == 0 and pcfg.mods_bots[id] == 0 and main.sim.players[0].mods.get(id, 0) == 0 and main.sim.players[1].mods.get(id, 0) == 0))
	check("play: bots are active whatever the saved bot mode, and the chosen figure counts", pcfg.bot_mode == Config.BotMode.ACTIVE and main.sim.players[1].enabled and main.sim.players[0].skin == 3 and main.sim.players[1].skin == 4)
	check("play: the HUD shows only the pause button", main.hud.visible and main.hud.play_mode and not main.hud._score_box.visible and not main.hud._chip_box.visible and not main.hud._net_label.visible and not main.router.blocked)
	# pause
	var t0: int = main.sim.tick
	main.hud.gear_pressed.emit()
	for _i in 10:
		await process_frame
	check("pause: the pause panel opens, the offline sim stands and the input is blocked", main.pause.visible and main.sim.tick == t0 and main.router.blocked and not main.menu.visible)
	main.pause.resume_btn.pressed.emit()
	for _i in 10:
		await process_frame
	check("pause: Resume goes on", not main.pause.visible and main.sim.tick > t0 and not main.router.blocked)
	main.router.menu_requested.emit()
	check("pause: Escape opens it too", main.pause.visible)
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("pause: Android back closes it again", not main.pause.visible)
	main.hud.gear_pressed.emit()
	main.pause.main_menu_btn.pressed.emit()
	for _i in 3:
		await process_frame
	check("pause: Main menu stops the game and shows the menu over a fresh, standing arena", main.screen == main.Screen.MENU and main.main_menu.visible and not main.hud.visible and not main.pause.visible and main.sim.tick == 0 and main.router.blocked)
	# Training
	main.main_menu.training_btn.pressed.emit()
	for _i in 30:
		await process_frame
	check("training: runs on the tuned values and the sandbox modifiers", main.screen == main.Screen.GAME and main.training and main.cfg == main.train_cfg and main.sim.cfg.player_speed == 9.0 and main.sim.cfg.dash_distance == 7.0
			and main.sim.players[0].mods.get("twin", 0) == 3 and main.sim.players[1].mods.get("pierce", 0) == 2 and main.sim.tick > 10)
	check("training: keeps the saved bot mode, the figure and today's HUD", main.sim.players[1].enabled == (main.train_cfg.bot_mode != Config.BotMode.OFF) and not main.sim.cfg.bot_mode == Config.BotMode.ACTIVE and main.sim.players[0].skin == 3 and main.hud.visible and not main.hud.play_mode and main.hud._score_box.visible)
	main.hud.gear_pressed.emit()
	check("training: the pause button opens the tuning menu, not the pause panel", main.menu.visible and not main.pause.visible and main.router.blocked)
	var t1: int = main.sim.tick
	for _i in 5:
		await process_frame
	check("training: the offline sim stands while the tuning menu is open", main.sim.tick == t1)
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("training: Android back closes the tuning menu", not main.menu.visible and not main.router.blocked)
	main.hud.gear_pressed.emit()
	main.menu.main_menu_requested.emit()
	check("training: the Main menu button of the tuning menu goes back", main.screen == main.Screen.MENU and not main.menu.visible and main.main_menu.visible)
	check("training: and the tuned values are still the tuned ones for the next Training game", main.train_cfg.player_speed == 9.0)
	# lobby back, settings back
	main.main_menu.play_btn.pressed.emit()
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("back: Android back in the lobby goes to the main menu", main.screen == main.Screen.MENU and main.main_menu.visible and not main.lobby.visible)
	var quits: Array = []
	main.quit_hook = func() -> void: quits.append(true)
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("back: Android back in the main menu quits the app", quits.size() == 1)
	main.main_menu.settings_btn.pressed.emit()
	check("settings: the page shows the version and no update button yet", main.main_menu.settings_page.visible and main.main_menu.settings_version_label.text == "Version " + UpdateCheck.running_version() and not main.main_menu.settings_update_btn.visible)
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("back: Android back in Settings goes back to the main page (it does not quit)", quits.size() == 1 and main.screen == main.Screen.MENU and not main.main_menu.settings_page.visible and main.main_menu._main_page.visible)
	# the update notice is a main menu thing
	main.offer_update({"version": "9.9.9", "url": "https://github.com/Joni9993/slice-n-dice-releases/releases/download/v9.9.9/x.apk"})
	check("update: the banner shows in the main menu", main.main_menu.update_banner.visible and main.main_menu.settings_update_btn.visible)
	main.start_solo()
	check("update: not during a game", not main.main_menu.visible and main.screen == main.Screen.GAME)
	main.queue_free()
	await process_frame


## Settings page: the touch controls panel and the layout editor, in the real main scene.
func test_touch_menu() -> void:   # async
	NetStore.path = "user://test_online%d.json" % PORT_OFFSET
	TouchSettings.path = "user://test_touch%d.json" % PORT_OFFSET
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TouchSettings.path))
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	var mm: MainMenu = main.main_menu
	main.main_menu.settings_btn.pressed.emit()
	check("touch menu: defaults on the page - Floating, Normal size, Normal opacity, no swap", mm.mode_buttons[0].button_pressed and not mm.mode_buttons[1].button_pressed and mm.size_buttons[1].button_pressed and mm.opacity_buttons[1].button_pressed and not mm.swap_btn.button_pressed)
	check("touch menu: the router reads the same settings the page edits", main.router.touch == mm.touch and main.touch_settings == mm.touch)
	mm.mode_buttons[1].pressed.emit()
	mm.size_buttons[2].pressed.emit()
	mm.opacity_buttons[0].pressed.emit()
	mm.swap_btn.pressed.emit()
	var saved := TouchSettings.load_saved()
	check("touch menu: choices apply at once and are saved in their own file", main.router.touch.mode == TouchSettings.Mode.FIXED and is_equal_approx(main.router.touch.scale, 1.25) and is_equal_approx(main.router.touch.opacity, 0.5) and main.router.touch.swap
			and saved.mode == TouchSettings.Mode.FIXED and is_equal_approx(saved.scale, 1.25) and is_equal_approx(saved.opacity, 0.5) and saved.swap)
	check("touch menu: the buttons show the choice", mm.mode_buttons[1].button_pressed and not mm.mode_buttons[0].button_pressed and mm.size_buttons[2].button_pressed and mm.opacity_buttons[0].button_pressed and mm.swap_btn.button_pressed)

	# layout editor (Fixed): cancel keeps, save stores, reset + save forgets
	var ed: TouchLayoutEditor = mm.layout_editor
	mm.layout_btn.pressed.emit()
	check("touch editor: Place controls opens the editor, Fixed mode lets all three controls move", ed.visible and ed.editable() == ["move", "aim", "dash"])
	var dash_at: Vector2 = ed.center_of("dash")
	ed.begin_drag(dash_at + Vector2(5, 5))
	ed.drag_to(Vector2(300, 200))
	ed.end_drag()
	check("touch editor: dragging moves the control (the grab offset is kept)", ed.center_of("dash").distance_to(Vector2(300, 200) + Vector2(-5, -5)) < 1.0)
	ed.cancel()
	check("touch editor: Cancel closes and changes nothing", not ed.visible and main.router.touch.custom.is_empty() and TouchSettings.load_saved().custom.is_empty())
	mm.layout_btn.pressed.emit()
	ed.begin_drag(ed.center_of("move"))
	ed.drag_to(Vector2(600, 150))
	ed.end_drag()
	ed.begin_drag(ed.center_of("dash"))
	ed.drag_to(Vector2(10000, 10000))
	ed.end_drag()
	var screen_size: Vector2 = ed.get_viewport_rect().size
	check("touch editor: a control dragged off the screen is clamped onto it", ed.center_of("dash").is_equal_approx(screen_size - Vector2.ONE * main.router.touch.dash_radius()) and ed.place_of("dash").x < 1.0 and ed.place_of("dash").y < 1.0)
	ed.save_btn.pressed.emit()
	var after := TouchSettings.load_saved()
	check("touch editor: Save closes, keeps the places in the settings and in the file", not ed.visible and main.router.touch.custom.has("move") and main.router.touch.custom.has("dash") and after.custom.has("move") and after.custom.has("dash") and not after.custom.has("aim")
			and main.router._move_rest().distance_to(Vector2(600, 150)) < 1.0)
	mm.layout_btn.pressed.emit()
	ed.reset_btn.pressed.emit()
	check("touch editor: Reset to default puts the controls back in the editor, nothing is saved before Save", ed.place_of("move").is_equal_approx(main.router.touch.default_rel("move")) and TouchSettings.load_saved().custom.has("move"))
	ed.save_btn.pressed.emit()
	check("touch editor: Reset then Save forgets all placed controls", main.router.touch.custom.is_empty() and TouchSettings.load_saved().custom.is_empty())
	mm.mode_buttons[0].pressed.emit()
	mm.layout_btn.pressed.emit()
	check("touch editor: in Floating mode only the Dash button can be placed", ed.editable() == ["dash"])
	ed.begin_drag(ed.center_of("move"))
	ed.drag_to(Vector2(700, 300))
	ed.end_drag()
	check("touch editor: ... a stick cannot be dragged there", ed.place_of("move").is_equal_approx(main.router.touch.rel("move")))
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("touch editor: Android back closes the editor first, the page stays", not ed.visible and mm.settings_page.visible)

	# applies to Play and Training, survives a restart
	main.start_solo()
	check("touch menu: a Play game uses the saved settings", main.router.touch == main.touch_settings and main.router.touch.swap)
	main.start_training()
	check("touch menu: Training uses the same settings", main.router.touch == main.touch_settings and is_equal_approx(main.router.touch.scale, 1.25))
	main.queue_free()
	await process_frame
	var again: Node = load("res://main.tscn").instantiate()
	root.add_child(again)
	for _i in 3:
		await process_frame
	check("touch menu: after a restart the page shows the saved choices", again.main_menu.size_buttons[2].button_pressed and again.main_menu.swap_btn.button_pressed and again.main_menu.mode_buttons[0].button_pressed)
	again.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TouchSettings.path))


func _initialize() -> void:
	# TEST_STOP_ON_FAIL=1 (set by tests/sabotage.py): stop after the first test group that fails.
	var stop_early := OS.get_environment("TEST_STOP_ON_FAIL") == "1"
	var groups: Array[Callable] = [
		test_lan_code, test_pick_address, test_lan_beacon, test_local_host, test_menu_local, test_main_local,
		test_snapshot, test_train, test_prediction, test_one_shot_inputs, test_skin, test_skin_delayed, test_interpolation, test_view_others,
		test_other_display, test_victim_sees_arrival, test_predicted_heads, test_input_buffer, test_two_clients,
		test_redundancy, test_jitter_buffer, test_robustness, test_join_rules, test_match_lock, test_zone, test_rejoin, test_idle_and_sticks, test_stick_range, test_client_rules, test_lag_tool,
		test_address_parse, test_enet, test_menu_online, test_main_scene, test_client_mods, test_main_menu, test_touch_menu, test_match_flow, test_main_rejoin,
	]
	for g in groups:
		if stop_early and fails > 0:
			break
		await g.call()
	quit(fails)
