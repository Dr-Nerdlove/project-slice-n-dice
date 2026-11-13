extends SceneTree
const A := Vector2(28.0, 12.6)

func run_soak(label: String, mode: String, seed_v: int, variant := 0) -> void:
	var cfg := Config.new()
	cfg.out_variant = variant
	var s := Sim.new(cfg, seed_v)
	var r := RandomNumberGenerator.new(); r.seed = seed_v * 7 + 1
	var bots: Array[Bot] = []
	for i in 4: bots.append(Bot.new(i, cfg, 100 + i))
	var bad := []
	var max_pull := 0; var pull_t := [0, 0, 0, 0]; var max_pins := 0; var max_path := 0.0
	var max_flight := 0; var max_retract := 0; var max_stun := 0.0; var max_dead := 0
	var flight_t := {}; var retract_t := {}; var dead_t := [0, 0, 0, 0]
	var step_us := 0; var think_us := 0
	var events := {}
	var max_shards := 0; var max_wires := 0
	var ticks := 60 * 300
	for t in ticks:
		if t % 600 == 0:   # random levels re-rolled every 10 s (also exercises changing mods mid-game)
			for i in 4:
				var m := {}
				for id in Mods.ORDER:
					m[id] = 3 if mode == "all3" else r.randi_range(0, 3)
				s.apply_mods(i, m)
		var t0 := Time.get_ticks_usec()
		var ins: Array = []
		for b in bots: ins.append(b.think(s, 1.0 / 60.0))
		var t1 := Time.get_ticks_usec()
		s.step(ins)
		var t2 := Time.get_ticks_usec()
		think_us += t1 - t0; step_us += t2 - t1
		for e in s.events: events[e["type"]] = events.get(e["type"], 0) + 1
		max_shards = maxi(max_shards, s.shards.size()); max_wires = maxi(max_wires, s.wires.size())
		for p in s.players:
			var pts := [p.pos]
			for h in p.heads: pts.append(h.pos)
			for q in pts:
				if is_nan(q.x) or is_nan(q.y) or q.x < -0.01 or q.x > A.x + 0.01 or q.y < -0.01 or q.y > A.y + 0.01:
					bad.append("t=%d p%d outside/NaN %s" % [t, p.id, q])
			pull_t[p.id] = pull_t[p.id] + 1 if p.pulling else 0
			max_pull = maxi(max_pull, pull_t[p.id])
			for hh in p.heads:
				max_pins = maxi(max_pins, hh.pins.size())
				if hh.state == SimHead.S.OUT: max_path = maxf(max_path, Sim.path_length(s.string_path(p, hh)))
			max_stun = maxf(max_stun, p.stun_t)
			dead_t[p.id] = 0 if p.alive else dead_t[p.id] + 1
			max_dead = maxi(max_dead, dead_t[p.id])
			for k in p.heads.size():
				var key := p.id * 10 + k
				var h := p.heads[k]
				flight_t[key] = flight_t.get(key, 0) + 1 if h.state == SimHead.S.FLIGHT else 0
				retract_t[key] = retract_t.get(key, 0) + 1 if h.state == SimHead.S.RETRACT else 0
				max_flight = maxi(max_flight, flight_t[key]); max_retract = maxi(max_retract, retract_t[key])
		for sh in s.shards:
			if is_nan(sh.pos.x): bad.append("shard nan")
	var heads_state := []
	for p in s.players: heads_state.append(p.heads.map(func(h): return h.state))
	var k := []
	for p in s.players: k.append("%d/%d" % [p.kills, p.deaths])
	print("%s: kills/deaths %s | bad=%d %s | max flight %.1fs retract %.1fs stun %.2fs dead %.1fs | max shards %d wires %d | max pull %.1fs max pins %d max out-path %.1f" % [label, k, bad.size(), bad.slice(0, 3), max_flight / 60.0, max_retract / 60.0, max_stun, max_dead / 60.0, max_shards, max_wires, max_pull / 60.0, max_pins, max_path])
	print("   events: ", events)
	print("   avg sim.step %.1f us/tick, bots.think %.1f us/tick (all 4 bots), heads at end %s" % [float(step_us) / ticks, float(think_us) / ticks, heads_state])

func _init() -> void:
	run_soak("ALL LEVEL 3", "all3", 5)
	run_soak("RANDOM LEVELS", "rand", 9)
	run_soak("RANDOM LEVELS 2", "rand", 21)
	run_soak("ALL LEVEL 3 LEASH", "all3", 6, 1)
	run_soak("ALL LEVEL 3 RIGID", "all3", 7, 2)
	run_soak("RANDOM LEASH", "rand", 33, 1)
	run_soak("RANDOM RIGID", "rand", 34, 2)
	quit()
