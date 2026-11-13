# Deliberately breaks the game code, one change at a time, and checks that tests/run.sh notices.
# Usage: python3 tests/sabotage.py [name-prefix ...]
import subprocess, os, sys
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G=os.path.join(ROOT,'game')+os.sep
RUN=os.path.join(ROOT,'tests','run.sh')
SB=[
 ("1 bounce bonus values","sim/mods.gd",'"bonus_dist": [1.5, 3.0, 5.0]','"bonus_dist": [0.0, 2.0, 4.0]'),
 ("2 throw not curved","sim/sim.gd","h.throw_curved = bulge > 0.0","h.throw_curved = false"),
 ("2 aim line straight","sim/sim.gd","\tif bulge <= 0.0:\n\t\tpts.append(p.pos + p.aim_dir * aim_range(p))","\tif true:\n\t\tpts.append(p.pos + p.aim_dir * aim_range(p))"),
 ("2 circle blocked by blocks","sim/sim.gd","h.pos = _sweep_retract(h.pos, target - h.pos, r, 2)","h.pos = _sweep_retract(h.pos, target - h.pos, r, 0)"),
 ("3 twin heads 3/5","sim/mods.gd",'"heads": [2, 2, 2]','"heads": [2, 3, 5]'),
 ("3 no cross","sim/sim.gd",'mv(p, "twin", "cross", 0.0) > 0.0','mv(p, "twin", "cross", 0.0) > 5.0'),
 ("3 no retract x1.5","sim/sim.gd",' * mv(p, "twin", "retract_mult", 1.0)',''),
 ("3 no free pull","sim/sim.gd","func _can_free_pull(p: SimPlayer) -> bool:\n","func _can_free_pull(p: SimPlayer) -> bool:\n\tif true:\n\t\treturn false\n"),
 ("4 shards+warhead","sim/sim.gd","\t\t\tif s.blast > 0.0:","\t\t\tif false:"),
 ("7 pierce L1 retract blocked","sim/mods.gd",'"pass_retract": [1, 2, 2]','"pass_retract": [0, 2, 2]'),
 ("7 pierce L1 retract passes crate","sim/sim.gd","\t\tif pass_level < 2:\n\t\t\tpos = _crate_vs_circle(pos, r, 1.0)","\t\tif true:\n\t\t\tpass"),
 ("4 shards+pierce","sim/sim.gd","s.pass_level = _flight_pass(p)","s.pass_level = 0"),
 ("4 shards+bounce","sim/sim.gd",'s.bounces_left += int(Mods.n("bounce", "bounces", lv(p, "bounce")))','s.bounces_left += 0'),
 ("4 shards+bighead","sim/sim.gd",'* bighead_factor(p, "shards_bighead")','* 1.0'),
 ("4 bighead+warhead","sim/sim.gd","\treturn base * (f if f > 0.0 else 1.0)","\treturn base"),
 ("4 bighead+tripwire","sim/sim.gd",'* bighead_factor(p, "bighead_tripwire")','* 1.0'),
 ("4 synergy list menu","view/tuning_menu.gd","Mods.active_synergies(cfg.mods_you)","Mods.active_synergies(cfg.mods_bots)"),
 ("5 pins not recorded","sim/sim.gd","\t\t\t\th.pins.append(res)  # the string now bends here","\t\t\t\tpass"),
 ("5 retract ignores pins","sim/sim.gd","\t\tif budget <= 0.00001:\n\t\t\treturn\n\t\tvar has_pin := not h.pins.is_empty()\n","\t\tif budget <= 0.00001:\n\t\t\treturn\n\t\tvar has_pin := false\n"),
 ("5 pull ignores pins","sim/sim.gd","var goal := h.pins[0] if has_pin else h.pos","var goal := h.pos"),
 ("5 DRAG off","sim/sim.gd","\t\t\t_drag_head(p, h, r, length)","\t\t\tpass"),
 ("5 LEASH clamp off","sim/sim.gd","\tif d > max_off and d > 0.0001:","\tif false:"),
 ("5 RIGID keeps pins","sim/sim.gd","\t\t\t\th.pins.clear()  # the string is straight as soon as the player moves","\t\t\t\tpass"),
 ("6 no wire on pull","sim/sim.gd","\t\t_lay_wire(p, p.heads[target])","\t\tpass"),
 ("6 wire straight","sim/sim.gd","\tw.pts = pts\n","\tw.pts = PackedVector2Array([pts[0], pts[pts.size() - 1]])\n"),
 ("6 trigger first segment only","sim/sim.gd","\tfor i in range(1, pts.size()):\n\t\tvar c := Geometry2D","\tfor i in range(1, mini(pts.size(), 2)):\n\t\tvar c := Geometry2D"),
 ("7 export no * marker","sim/config.gd",'" *" if v != DEFAULTS[k] else ""','""'),
 ("7 export misses a key","sim/config.gd","\tfor k: String in DEFAULTS:\n\t\tvar v: Variant = get(k)\n\t\tvar shown","\tfor k: String in DEFAULTS.keys().slice(1):\n\t\tvar v: Variant = get(k)\n\t\tvar shown"),
 ("7 export no mod levels","sim/config.gd",'for group in ["mods_you", "mods_bots"]:','for group in ["mods_you"]:'),
 ("7 reset per page","view/tuning_menu.gd","\tif _mods_page.visible:\n\t\t_set_all","\tif false:\n\t\t_set_all"),
 ("7 export confirmation","view/tuning_menu.gd",'"In die Zwischenablage kopiert"','"Kopiert"'),
 ("8 snapshot leaves out player mods","sim/sim_player.gd",'const STATE_SKIP := ["head", "prev_head", "ystate"]','const STATE_SKIP := ["head", "prev_head", "ystate", "mods"]'),
 ("8 snapshot leaves out wires","sim/sim.gd",'const STATE_SKIP := ["cfg", "rng", "statics", "wall_count", "events"]','const STATE_SKIP := ["cfg", "rng", "statics", "wall_count", "events", "wires"]'),
 ("8 snapshot leaves out the head string pins","sim/sim_head.gd","var pins := PackedVector2Array()","const STATE_SKIP := [\"pins\"]\nvar pins := PackedVector2Array()"),
 ("8 snapshot does not restore the rng","sim/sim.gd",'\trng.state = d["rng_state"]','\tpass'),
 ("8 snapshot load replaces the objects","sim/state_io.gd","\t\t\tif arr[i] == null:\n\t\t\t\tarr[i] = script.new()","\t\t\tarr[i] = script.new()"),
 ("8 client does not replay pending inputs","net/client_core.gd",'\tfor p: Dictionary in pending:\n\t\tsim.step(_inputs_with(p["input"]))','\tfor p: Dictionary in []:\n\t\tsim.step(_inputs_with(p["input"]))'),
 ("8 client keeps acknowledged inputs","net/client_core.gd",'while not pending.is_empty() and pending[0]["seq"] <= acked:','while false:'),
 ("8 client does not predict (waits for the server)","net/client_core.gd","\tsim.step(_inputs_with(inp))\n\tevents = sim.events.duplicate()","\tevents = sim.events.duplicate()"),
 ("8 client hands out events of replays","net/client_core.gd",'\t\tsim.step(_inputs_with(p["input"]))\n','\t\tsim.step(_inputs_with(p["input"]))\n\t\tevents = sim.events.duplicate()\n'),
 ("8 client takes old snapshots","net/client_core.gd","\tif t <= last_snapshot_tick:","\tif false:"),
 ("8 no input redundancy","net/net_proto.gd","const REDUNDANCY := 4 ","const REDUNDANCY := 1 "),
 ("8 server does not clamp sticks","net/net_proto.gd","\treturn clamp_input(i)\n\n\n## Compressed","\treturn i\n\n\n## Compressed"),
 ("8 server accepts oversized packets","net/net_proto.gd","or data.size() > max_size or data[0] != K_PLAIN","or data[0] != K_PLAIN"),
 ("8 server skips the version check","net/server_core.gd","\tif msg[1] != NetProto.VERSION:","\tif false:"),
 ("8 server takes a fifth player","net/server_core.gd","\tif free < 0:\n\t\t_log(\"refused a client: server full\")","\tif free < 0 and false:\n\t\t_log(\"refused a client: server full\")"),
 ("8 server buffer grows without bound","net/server_core.gd","\twhile s.buffer.size() > MAX_BUFFER:","\twhile false:"),
 ("8 server trusts modifier levels","net/server_core.gd","sim.apply_mods(i, Mods.sanitize(msg[1]))","sim.apply_mods(i, msg[1])"),
 ("8 lag tool drops reliable packets","net/lag_endpoint.gd","if ev[\"kind\"] == Kind.PACKET and not ev[\"reliable\"] and rng","if ev[\"kind\"] == Kind.PACKET and rng"),
 ("8 lag tool does not delay","net/lag_endpoint.gd","\t_last_out_at = maxf(float(clock.call()) + delay_ms, _last_out_at)","\t_last_out_at = maxf(float(clock.call()), _last_out_at)"),
 ("8 menu lag label not per direction","view/tuning_menu.gd","Künstliche Verzögerung pro Richtung","Künstliche Verzögerung"),
 ("8 online: HUD keeps the offline sim","main.gd","\tview.use_sim(client.sim, client.slot)\n\thud.use_sim(client.sim, client.slot)","\tview.use_sim(client.sim, client.slot)"),
 ("8 online: leaving keeps the online view","main.gd","\tview.use_sim(sim, 0)\n\thud.use_sim(sim, 0)\n\thud.online = false","\thud.online = false"),
 ("8 client repeats the dash of the others","net/client_core.gd","_others[i] = inp.repeated()","_others[i] = inp"),
 ("8 server repeats a dash on an underrun","net/server_core.gd","return s.last_input.repeated()","return s.last_input"),
 ("8 display: no blending between snapshots","net/client_core.gd","display_alpha = clampf((rt - float(a_tick)) / float(b_tick - a_tick), 0.0, 1.0)","display_alpha = 1.0"),
 ("8 display: no interpolation delay","net/client_core.gd","const INTERP_DELAY := 4.0 ","const INTERP_DELAY := 0.0 "),
 ("8 display: render time ahead of the snapshots","net/client_core.gd","var rt := _render_t - 1.0 + clampf(frac, 0.0, 1.0)","var rt := _render_t + 6.0 + clampf(frac, 0.0, 1.0)"),
 ("8 display: teleports are interpolated","net/client_core.gd","const INTERP_MAX_STEP := 6.0 ","const INTERP_MAX_STEP := 1e9 "),
 ("8 display: render clock jumps","net/client_core.gd","_render_t += 1.0 + clampf(err * INTERP_NUDGE, -INTERP_NUDGE_MAX, INTERP_NUDGE_MAX)","_render_t += 1.0 + err"),
 ("8 display: delay does not grow on late snapshots","net/client_core.gd","\t\t_extra = maxf(_extra, minf(late, INTERP_EXTRA_MAX))","\t\tpass"),
 ("8 display: delay does not grow on lost snapshots","net/client_core.gd","\t\t_extra = maxf(_extra, minf(float(gap - ServerCore.SNAPSHOT_EVERY), INTERP_EXTRA_MAX))","\t\tpass"),
 ("8 display: delay never shrinks","net/client_core.gd","\t_extra = maxf(_extra - INTERP_EXTRA_DECAY, 0.0)","\tpass"),
 ("8 display: delay shrinks at once","net/client_core.gd","const INTERP_EXTRA_DECAY := 0.005 ","const INTERP_EXTRA_DECAY := 5.0 "),
 ("8 display: clock drift is not corrected","net/client_core.gd","\t\t_est -= minf(late, INTERP_EST_PULL)","\t\tpass"),
 ("8 display: other players not interpolated","net/client_core.gd","\t\t\tp.prev_pos = o[\"pos\"]","\t\t\tpass"),
 ("8 display: yo-yo heads not interpolated","net/client_core.gd","\t\t\t\tp.heads[k].prev_pos = oh[\"pos\"]","\t\t\t\tpass"),
 ("8 display: shards not interpolated","net/client_core.gd","\t\t\t\tsh.prev_pos = o[\"pos\"]","\t\t\t\tpass"),
 ("8 display: snapshots are not buffered","net/client_core.gd","\t_buffer_snapshot(t, snap[\"state\"])\n","\n"),
 ("8 heads: others' heads not drawn from the predicted sim","net/client_core.gd","var predict_heads := true ","var predict_heads := false "),
 ("8 heads: no catch-up offset when the source changes","net/client_core.gd","\t\t\t\t_set_offset(rec, Vector2.ZERO if off.length() > HEAD_MAX_OFFSET else off)\n\t\t\t\trec[\"kind\"] = kind","\t\t\t\t_set_offset(rec, Vector2.ZERO)\n\t\t\t\trec[\"kind\"] = kind"),
 ("8 heads: corrections of the predicted head pop","net/client_core.gd","\t\t_carry_head_corrections(heads_before)\n","\t\tpass\n"),
 ("8 heads: a teleport is slid over","net/client_core.gd","const HEAD_MAX_OFFSET := 6.0 ","const HEAD_MAX_OFFSET := 1e9 "),
 ("8 heads: the offset never decays","net/client_core.gd","\t_decay_offsets()\n\t_ticks += 1","\t_ticks += 1"),
 ("8 heads: the catch-up is one tick","net/client_core.gd","const HEAD_CATCHUP_TICKS := 6 ","const HEAD_CATCHUP_TICKS := 1 "),
 ("8 heads: the offset of a dead player stays","net/client_core.gd","\t\t\t\t_vis.erase(key)\n\t\t\t\tcontinue","\t\t\t\tcontinue"),
 ("8 heads: shards of the others stay interpolated","net/client_core.gd","\tif predict_heads:\n\t\tdisplay_sim.shards.clear()","\tif false:\n\t\tdisplay_sim.shards.clear()"),
 ("8 heads: the string loses the bounce points","net/client_core.gd","\t\t\t\th.pins = ph.pins\n","\t\t\t\th.pins = PackedVector2Array()\n"),
 ("8 heads: switch off still uses the predicted heads","net/client_core.gd","\tif not smooth_others or _snaps.is_empty() or sim == null:\n\t\tdisplay_sim = null\n\t\t_vis.clear()\n\t\treturn","\tif _snaps.is_empty() or sim == null:\n\t\tdisplay_sim = null\n\t\t_vis.clear()\n\t\treturn"),
 ("8 buffer: starts large","net/server_core.gd","const JITTER_START := 1 ","const JITTER_START := 3 "),
 ("8 buffer: does not grow on an underrun","net/server_core.gd","\t\tif s.starved == 1:\n\t\t\t_grow(s)","\t\tif s.starved == 1:\n\t\t\tpass"),
 ("8 buffer: does not grow on a burst","net/server_core.gd","\tif s.new_inputs >= BURST:\n\t\t_grow(s)","\tif s.new_inputs >= BURST:\n\t\tpass"),
 ("8 buffer: grows without a cap","net/server_core.gd","\ts.target = mini(s.target + 1, JITTER_MAX)","\ts.target += 1"),
 ("8 buffer: never shrinks","net/server_core.gd","\tif s.calm >= s.shrink_wait:","\tif false:"),
 ("8 buffer: growth does not slow the shrinking","net/server_core.gd","\ts.shrink_wait = mini(s.shrink_wait * 2, SHRINK_MAX)","\tpass"),
 ("8 buffer: surplus is never trimmed","net/server_core.gd","\t\tif s.excess >= TRIM_AFTER:","\t\tif false:"),
 ("8 buffer: trimmed inputs count as lost","net/server_core.gd","\tif acknowledge:\n\t\ts.last_consumed = old","\tif acknowledge:\n\t\tpass"),
 ("8 buffer: a trimmed dash is lost","net/server_core.gd","\tif inp.dash and not s.buffer.is_empty():","\tif false:"),
 ("8 buffer: a freed slot keeps its target","net/server_core.gd","\t\ttarget = JITTER_START\n\t\tcalm = 0","\t\tcalm = 0"),
 ("8 view: others drawn from the predicted sim","view/arena_view.gd","if others_sim != null and i != _local_slot:","if false:"),
 ("8 view: own player drawn from the display sim","view/arena_view.gd","if others_sim != null and i != _local_slot:","if others_sim != null:"),
 ("8 view: wires and shards of every owner from both sims","view/arena_view.gd","if (o.owner_id == _local_slot) == mine:","if true:"),
 ("8 menu: smoothing off by default","view/tuning_menu.gd","\t_smooth_check.button_pressed = true\n\t_smooth_check.custom_minimum_size","\t_smooth_check.button_pressed = false\n\t_smooth_check.custom_minimum_size"),
 ("8 menu: reset leaves smoothing as it is","view/tuning_menu.gd","\t\t_smooth_check.button_pressed = true\n\t\treturn","\t\treturn"),
 ("8 main: the switch does not reach the client","main.gd","\t\t\tclient.smooth_others = on)","\t\t\tpass)"),
 ("8 main: a new client ignores the switch","main.gd","\tclient.smooth_others = _smooth\n","\n"),
 ("8 main: view gets no display sim","main.gd","\t\tview.set_others(client.display_sim, client.display_alpha)\n","\t\tpass\n"),
 ("8 main: HUD hides the interpolation delay","main.gd",'"Gegner %d ms zurück" % roundi(client.interp_delay_ms()) if client.smooth_others','"Gegner roh" if client.smooth_others'),
]
only = sys.argv[1:]
res=[]
for name,f,old,new in SB:
    if only and not any(name.startswith(o) for o in only): continue
    path=G+f
    orig=open(path,'rb').read()
    src=orig.decode()
    if src.count(old)!=1:
        print("!! pattern count",src.count(old),name); res.append((name,'PATTERN',True)); continue
    try:
        open(path,'wb').write(src.replace(old,new).encode())
        out=subprocess.run([RUN],capture_output=True,text=True).stdout
    finally:
        open(path,'wb').write(orig)
    same=open(path,'rb').read()==orig
    fails=[l[6:90] for l in out.splitlines() if l.startswith('FAIL')]
    err='SCRIPT ERROR' in out or 'Parse Error' in out
    print(("OK   " if (fails or err) else "NOT CAUGHT"), name,"| restored identical:",same,"| fails:",len(fails),"| script err:",err, "|", fails[:2])
    res.append((name,bool(fails or err),same))
ok=all(r[1] is True and r[2] for r in res)
print("ALL CAUGHT" if ok else "PROBLEMS", len(res))
sys.exit(0 if ok else 1)
