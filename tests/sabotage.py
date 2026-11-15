# Deliberately breaks the game code, one change at a time, and checks that the tests notice.
# Usage: python3 tests/sabotage.py [-j N] [--full] [name-prefix ...]
#   Every change is made in a temporary COPY of game/ (outside the repository); the working tree is never touched.
#   Each entry runs only the suite(s) that cover it: by default the one named by its first character
#   (1-7 sim, 8 net, 9 update, 0 view), or the explicit list in the optional fifth field of the entry (see SUITES_OVERRIDE).
#   --full runs all suites for every entry. -j N: number of parallel workers (default: half of the CPU cores).
import subprocess, os, sys, shutil, tempfile, threading, queue, time, argparse
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME=os.path.join(ROOT,'game')
RUN=os.path.join(ROOT,'tests','run.sh')
PREFIX_SUITE={'1':'sim','2':'sim','3':'sim','4':'sim','5':'sim','6':'sim','7':'sim','8':'net','9':'update','0':'view'}
# Entries that the suite of their prefix does not catch: name -> suites.
SUITES_OVERRIDE={}
PORT_STEP=100   # distance of the localhost port ranges of two workers (each test uses a range of 40)
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
 ("9 compare as text","update/update_check.gd","\t\tif a[i] != b[i]:\n\t\t\treturn a[i] > b[i]","\t\tif a[i] != b[i]:\n\t\t\treturn str(a[i]) > str(b[i])"),
 ("9 same version counts as newer","update/update_check.gd","\t\t\treturn a[i] > b[i]\n\treturn false","\t\t\treturn a[i] > b[i]\n\treturn true"),
 ("9 leading v not tolerated","update/update_check.gd",'if s.begins_with("v") or s.begins_with("V"):','if false:'),
 ("9 dev suffix not ignored","update/update_check.gd",'for sep in ["-", "+"]:','for sep in []:'),
 ("9 url prefix not checked","update/update_check.gd","if url.length() > MAX_URL_LENGTH or not url.begins_with(DOWNLOAD_PREFIX):","if url.length() > MAX_URL_LENGTH:"),
 ("9 url dot-dot allowed","update/update_check.gd",'rest.contains("..") or ',''),
 ("9 url http allowed","update/update_check.gd",'const DOWNLOAD_PREFIX := "https://github.com/','const DOWNLOAD_PREFIX := "http://github.com/'),
 ("9 size cap off","update/update_check.gd","body.is_empty() or body.size() > MAX_BODY_BYTES","body.is_empty()"),
 ("9 non-apk asset taken",'update/update_check.gd','.to_lower().ends_with(".apk") and','.to_lower().ends_with("") and'),
 ("9 prerelease offered","update/update_check.gd",'or rel.get("prerelease", false) == true','or false'),
 ("9 assets not an array not rejected","update/update_check.gd","\tif not assets is Array:\n\t\treturn {}\n","\tpass\n"),
 ("9 version code formula","update/update_check.gd","v[0] * 10000 + v[1] * 100 + v[2]","v[0] * 1000 + v[1] * 100 + v[2]"),
 ("9 main: banner never shown","main.gd",'\t\thud.show_update(info["version"])','\t\tpass'),
 ("9 main: Später forgotten","main.gd","hud.update_dismissed.connect(func() -> void: _update_dismissed = true)","hud.update_dismissed.connect(func() -> void: pass)"),
 ("9 main: banner touches steer the player","main.gd","router.exclude_rects = hud.blocked_rects()","router.exclude_rects = [hud.gear_rect()]"),
 ("9 main: download opens any link","main.gd",' and UpdateCheck.is_allowed_url(_update["url"])',''),
 ("9 main: menu button not connected","main.gd","menu.update_requested.connect(_download_update)","pass"),
 ("9 main: no timeout on the request","main.gd","_update_http.timeout = UPDATE_TIMEOUT\n","\n"),
 ("9 main: check also in server mode","main.gd","\t\t\tget_tree().quit(1)\n\t\treturn\n","\t\t\tget_tree().quit(1)\n\t\tget_tree().create_timer(UPDATE_CHECK_DELAY).timeout.connect(_start_update_check)\n\t\treturn\n"),
 ("9 main: request fails -> parsed even on error code","main.gd","if result == HTTPRequest.RESULT_SUCCESS and code == 200:","if true:"),
 ("9 hud: Später does not hide","view/hud.gd","\t\tupdate_banner.visible = false\n\t\tupdate_dismissed.emit())","\t\tupdate_dismissed.emit())"),
 ("9 hud: banner text","view/hud.gd",'"Neue Version %s verfügbar"','"Update %s"'),
 ("9 hud: hidden banner still blocks","view/hud.gd","\tif update_banner.visible:\n\t\trects.append","\tif true:\n\t\trects.append"),
 ("9 menu: version not shown","view/tuning_menu.gd",'_version_label.text = "Version %s" % UpdateCheck.running_version()','_version_label.text = ""'),
 ("9 menu: update button never shown","view/tuning_menu.gd","_update_btn.visible = version != \"\"","_update_btn.visible = false"),
]
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
 ("7 figure: not saved","sim/config.gd",'\td["character"] = character\n','\n'),
 ("7 figure: not sanitised","sim/config.gd","posmod(int(ch), SKIN_COUNT)","int(ch)"),
 ("7 figure: garbage not zero","sim/config.gd","if (ch is int or (ch is float and is_finite(ch))) else 0","if true else 0"),
 ("7 figure: reset clears it","sim/config.gd","\tfor k: String in DEFAULTS:\n\t\tset(k, DEFAULTS[k])\n","\tfor k: String in DEFAULTS:\n\t\tset(k, DEFAULTS[k])\n\tcharacter = 0\n"),
 ("7 figure: set_skin does not wrap","sim/sim.gd","players[i].skin = posmod(k, Config.SKIN_COUNT)","players[i].skin = k"),
 ("7 figure: set_skin ignored","sim/sim.gd","players[i].skin = posmod(k, Config.SKIN_COUNT)","pass"),
 ("7 figure: skin changes the simulation","sim/sim.gd","\tplayers[i].skin = posmod(k, Config.SKIN_COUNT)\n","\tplayers[i].skin = posmod(k, Config.SKIN_COUNT)\n\tplayers[i].pos.x += 0.001 * players[i].skin\n"),
 ("7 figure: menu button does not set it","view/tuning_menu.gd","\tcfg.character = i\n","\tpass\n"),
 ("7 figure: menu shows wrong button pressed","view/tuning_menu.gd","set_pressed_no_signal(i == cfg.character)","set_pressed_no_signal(i == 0)"),
 ("7 figure: menu tab does not show page","view/tuning_menu.gd","\t_figure_page.visible = page == 3\n","\t_figure_page.visible = false\n"),
 ("7 figure: menu button label","view/tuning_menu.gd","_button(ToyFigure.NAMES[i])","_button(str(i))"),
 ("8 figure: client never sends it","net/client_core.gd","\t\tnet.send(1, NetProto.pack([NetProto.T_SKIN, _wanted_skin]), true)\n","\t\tpass\n"),
 ("8 figure: snapshot overwrites own choice","net/client_core.gd","\tif _wanted_skin >= 0:\n\t\tsim.set_skin(slot, _wanted_skin)\n","\tpass\n"),
 ("8 figure: client sends wrong value","net/client_core.gd","NetProto.pack([NetProto.T_SKIN, _wanted_skin])","NetProto.pack([NetProto.T_SKIN, 0])"),
 ("8 figure: server ignores it","net/server_core.gd","\t\t\t\tsim.set_skin(i, msg[1])\n","\t\t\t\tpass\n"),
 ("8 figure: server accepts any int","net/server_core.gd"," and msg[1] >= 0 and msg[1] < Config.SKIN_COUNT:",":"),
 ("8 figure: server accepts floats","net/server_core.gd","msg[1] is int and msg[1] >= 0","(msg[1] is int or msg[1] is float) and msg[1] >= 0"),
 ("8 figure: skin missing from snapshot","sim/sim_player.gd",'const STATE_SKIP := ["head", "prev_head", "ystate"]','const STATE_SKIP := ["head", "prev_head", "ystate", "skin"]'),
 ("8 figure: main offline bots look like the player","main.gd","sim.set_skin(i, cfg.character + i)","sim.set_skin(i, cfg.character)"),
 ("8 figure: main offline player ignores the choice","main.gd","\tsim.set_skin(0, cfg.character)\n","\tpass\n"),
 ("8 figure: main does not send it","main.gd","\t\tclient.set_skin(cfg.character)\n\t\t# Online","\t\t# Online"),
 ("1 train: does not advance","sim/sim.gd","\ttrain_s += cfg.train_speed * dt\n","\tpass\n"),
 ("1 train: wrap leaves prev behind","sim/sim.gd","\t\tprev_train_s -= TrainTrack.LENGTH\n","\t\tpass\n"),
 ("1 train: speed 0 still runs","sim/sim.gd","\tif cfg.train_speed <= 0.0:\n\t\tprev_train_s = train_s\n\t\treturn\n","\tpass\n"),
 ("1 train: kills nobody","sim/sim.gd","\t\t\tif v.enabled and v.alive and v.pos.distance_to(c) < reach:","\t\t\tif false:"),
 ("1 train: hit distance too small","sim/sim.gd","\tvar reach := TrainTrack.CAR_RADIUS + cfg.player_radius * Config.TRAIN_HIT_SHARE\n\tfor k in TrainTrack.CARS:\n\t\tvar c","\tvar reach := TrainTrack.CAR_RADIUS * 0.5\n\tfor k in TrainTrack.CARS:\n\t\tvar c"),
 ("1 train: hit distance too large","sim/sim.gd","\tvar reach := TrainTrack.CAR_RADIUS + cfg.player_radius * Config.TRAIN_HIT_SHARE\n\tfor k in TrainTrack.CARS:\n\t\tvar c","\tvar reach := TrainTrack.CAR_RADIUS + cfg.player_radius * 2.0\n\tfor k in TrainTrack.CARS:\n\t\tvar c"),
 ("1 train: only the locomotive kills","sim/sim.gd","\tfor k in TrainTrack.CARS:\n\t\tvar c := TrainTrack.point","\tfor k in 1:\n\t\tvar c := TrainTrack.point"),
 ("1 train: kill credited to somebody","sim/sim.gd","\tif killer != null:\n\t\tkiller.kills += 1","\tif true:\n\t\tvictim.kills += 1"),
 ("1 train: victim's death not counted","sim/sim.gd","\tvictim.deaths += 1\n\tif killer != null:","\tif killer != null:"),
 ("1 train: kill event without cause","sim/sim.gd","\t\te[\"cause\"] = \"train\"","\t\tpass"),
 ("1 train: kill event names a killer","sim/sim.gd","\"killer\": -1 if killer == null else killer.id}","\"killer\": 0 if killer == null else killer.id}"),
 ("1 train: crate not pushed","sim/sim.gd","\t\t_crate_vs_circle(c, TrainTrack.CAR_RADIUS, 1.0)\n","\t\tpass\n"),
 ("1 train: crate only half pushed","sim/sim.gd","\t\t_crate_vs_circle(c, TrainTrack.CAR_RADIUS, 1.0)\n","\t\t_crate_vs_circle(c, TrainTrack.CAR_RADIUS, 0.5)\n"),
 ("1 train: heads are removed","sim/sim.gd","\t\tfor v in players:\n\t\t\tif v.enabled and v.alive and v.pos.distance_to(c) < reach:","\t\tfor v in players:\n\t\t\tfor hh in v.heads:\n\t\t\t\tif hh.state == SimHead.S.OUT and hh.pos.distance_to(c) < reach:\n\t\t\t\t\thh.state = SimHead.S.HAND\n\t\t\tif v.enabled and v.alive and v.pos.distance_to(c) < reach:"),
 ("1 train: respawn ignores cars","sim/sim.gd","\t\tif train_unsafe(s):\n\t\t\tscore -= 1000.0\n","\t\tpass\n"),
 ("1 train: not in the snapshot","sim/sim.gd",'const STATE_SKIP := ["cfg", "rng", "statics", "wall_count", "events"]','const STATE_SKIP := ["cfg", "rng", "statics", "wall_count", "events", "train_s"]'),
 ("1 train: track too close to an obstacle","sim/train_track.gd","const CENTER := Vector2(16.0, 7.2)","const CENTER := Vector2(16.0, 6.4)"),
 ("1 train: spawn on the rails","sim/config.gd","Vector2(10.9, 1.5), Vector2(21.1, 12.9),","Vector2(12.2, 3.6), Vector2(21.1, 12.9),"),
 ("1 train: slider missing","view/tuning_menu.gd",'	["train_speed", "Eisenbahn-Tempo", 0.0, 10.0, 0.1, "m/s"],\n',''),
 ("1 train: bot ignores cars","input/bot.gd","\tif sim.cfg.train_speed > 0.0:\n\t\tfor k in TrainTrack.CARS:\n\t\t\tvar cs","\tif false:\n\t\tfor k in TrainTrack.CARS:\n\t\t\tvar cs"),
 ("1 train: bot dashes into cars","input/bot.gd"," and not _train_near(sim, me, cfg.dash_distance):",":"),
 ("8 train: server config lacks the speed","sim/config.gd",'\t"train_speed": 5.7,\n','\t"train_speed": 0.0,\n'),
 ("8 train: client does not predict it","sim/sim.gd","\t_step_train(dt)\n\t_collide_heads()","\tif cfg.train_speed > 100.0:\n\t\t_step_train(dt)\n\t_collide_heads()"),
 ("9 compare as text","update/update_check.gd","\t\tif a[i] != b[i]:\n\t\t\treturn a[i] > b[i]","\t\tif a[i] != b[i]:\n\t\t\treturn str(a[i]) > str(b[i])"),
 ("9 same version counts as newer","update/update_check.gd","\t\t\treturn a[i] > b[i]\n\treturn false","\t\t\treturn a[i] > b[i]\n\treturn true"),
 ("9 leading v not tolerated","update/update_check.gd",'if s.begins_with("v") or s.begins_with("V"):','if false:'),
 ("9 dev suffix not ignored","update/update_check.gd",'for sep in ["-", "+"]:','for sep in []:'),
 ("9 url prefix not checked","update/update_check.gd","if url.length() > MAX_URL_LENGTH or not url.begins_with(DOWNLOAD_PREFIX):","if url.length() > MAX_URL_LENGTH:"),
 ("9 url dot-dot allowed","update/update_check.gd",'rest.contains("..") or ',''),
 ("9 url http allowed","update/update_check.gd",'const DOWNLOAD_PREFIX := "https://github.com/','const DOWNLOAD_PREFIX := "http://github.com/'),
 ("9 size cap off","update/update_check.gd","body.is_empty() or body.size() > MAX_BODY_BYTES","body.is_empty()"),
 ("9 non-apk asset taken",'update/update_check.gd','.to_lower().ends_with(".apk") and','.to_lower().ends_with("") and'),
 ("9 prerelease offered","update/update_check.gd",'or rel.get("prerelease", false) == true','or false'),
 ("9 assets not an array not rejected","update/update_check.gd","\tif not assets is Array:\n\t\treturn {}\n","\tpass\n"),
 ("9 version code formula","update/update_check.gd","v[0] * 10000 + v[1] * 100 + v[2]","v[0] * 1000 + v[1] * 100 + v[2]"),
 ("9 main: banner never shown","main.gd",'\t\thud.show_update(info["version"])','\t\tpass'),
 ("9 main: Später forgotten","main.gd","hud.update_dismissed.connect(func() -> void: _update_dismissed = true)","hud.update_dismissed.connect(func() -> void: pass)"),
 ("9 main: banner touches steer the player","main.gd","router.exclude_rects = hud.blocked_rects()","router.exclude_rects = [hud.gear_rect()]"),
 ("9 main: download opens any link","main.gd",' and UpdateCheck.is_allowed_url(_update["url"])',''),
 ("9 main: menu button not connected","main.gd","menu.update_requested.connect(_download_update)","pass"),
 ("9 main: no timeout on the request","main.gd","_update_http.timeout = UPDATE_TIMEOUT\n","\n"),
 ("9 main: check also in server mode","main.gd","\t\t\tget_tree().quit(1)\n\t\treturn\n","\t\t\tget_tree().quit(1)\n\t\tget_tree().create_timer(UPDATE_CHECK_DELAY).timeout.connect(_start_update_check)\n\t\treturn\n"),
 ("9 main: request fails -> parsed even on error code","main.gd","if result == HTTPRequest.RESULT_SUCCESS and code == 200:","if true:"),
 ("9 hud: Später does not hide","view/hud.gd","\t\tupdate_banner.visible = false\n\t\tupdate_dismissed.emit())","\t\tupdate_dismissed.emit())"),
 ("9 hud: banner text","view/hud.gd",'"Neue Version %s verfügbar"','"Update %s"'),
 ("9 hud: hidden banner still blocks","view/hud.gd","\tif update_banner.visible:\n\t\trects.append","\tif true:\n\t\trects.append"),
 ("9 menu: version not shown","view/tuning_menu.gd",'_version_label.text = "Version %s" % UpdateCheck.running_version()','_version_label.text = ""'),
 ("9 menu: update button never shown","view/tuning_menu.gd","_update_btn.visible = version != \"\"","_update_btn.visible = false"),
 ("0 pose: charge does not lean back","view/toy_pose.gd","out[LEAN] = 0.04 * clampf(f.fwd_speed, -1.0, 1.0) - 0.34 * c","out[LEAN] = 0.04 * clampf(f.fwd_speed, -1.0, 1.0)"),
 ("0 pose: charge does not wind the arm up","view/toy_pose.gd","out[ARM] = lerpf(0.3, -1.0, c)","out[ARM] = 0.3"),
 ("0 pose: no tremble at full charge","view/toy_pose.gd","out[TREMBLE] = 0.08 * smoothstep(0.85, 1.0, c)","out[TREMBLE] = 0.0"),
 ("0 pose: dash not stretched","view/toy_pose.gd","out[STRETCH] = 1.5","out[STRETCH] = 1.0"),
 ("0 pose: stun not dizzy","view/toy_pose.gd","out[DIZZY] = 1.0","out[DIZZY] = 0.0"),
 ("0 pose: pull does not fly","view/toy_pose.gd","out[LIFT] = 0.4","out[LIFT] = 0.0"),
 ("0 pose: the bunny does not hop","view/toy_pose.gd","out[LIFT] += 0.6 * w * hop","out[LIFT] += 0.07 * w * hop"),
 ("0 pose: dash wins over charging","view/toy_pose.gd","\tif f.dashing:\n\t\treturn Act.DASH\n\tif f.charging:\n\t\treturn Act.CHARGE","\tif f.charging:\n\t\treturn Act.CHARGE\n\tif f.dashing:\n\t\treturn Act.DASH"),
 ("0 springs depend on the frame rate","view/toy_pose.gd","var n := maxi(1, ceili(dt / SUBSTEP - 0.001))","var n := 1"),
 ("0 motion: throw not noticed","view/toy_motion.gd","\t\tfacts.since_throw = 0.0\n\telif","\t\tpass\n\telif"),
 ("0 motion: catch not noticed","view/toy_motion.gd","\t\tfacts.since_catch = 0.0\n\t_hand = hand","\t\tpass\n\t_hand = hand"),
 ("0 motion: dash only from dash_t","view/toy_motion.gd","var dashing := p.dash_t > 0.0 or (velocity.length() > ps * DASH_SPEED_FACTOR and not facts.pulling)","var dashing := p.dash_t > 0.0"),
 ("0 motion: a teleport counts as movement","view/toy_motion.gd","\tif drawn.distance_to(_last) > TELEPORT:\n\t\t_last = drawn","\tif false:\n\t\t_last = drawn"),
 ("0 motion: death does not pop","view/toy_motion.gd","\t\tpopped = true","\t\tpass"),
 ("0 motion: no drop on respawn","view/toy_motion.gd","\tfacts.since_spawn = 0.0\n\tfacts.since_throw = 99.0","\tfacts.since_spawn = 99.0\n\tfacts.since_throw = 99.0"),
 ("0 motion: turns snap","view/toy_motion.gd","yaw += angle_difference(yaw, atan2(face.x, face.y)) * (1.0 - exp(-rate * dt))","yaw += angle_difference(yaw, atan2(face.x, face.y))"),
 ("0 figure: robot has no key","view/toy_figure.gd",'var key := _piece("Key"','var key := _piece("Crank"'),
 ("0 figure: pieces do not fly","view/toy_figure.gd","\t\tpc.position = p\n","\n"),
 ("0 figure: body too small for the hit circle","view/toy_figure.gd","_p(body, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.75, 1.55, 1.7))","_p(body, ToyKit.sphere(), body_mat, Vector3.ZERO, Vector3(1.25, 1.55, 1.2))"),
 ("0 view: figures drawn from the predicted sim","view/arena_view.gd","fig.sync(p, src, pos, delta)","fig.sync(sim.players[i], sim, pos, delta)"),
 ("0 view: players start with the same toy","sim/sim.gd","p.skin = i % Config.SKIN_COUNT","p.skin = 0"),
 ("0 arena: a spawn inside a block","sim/config.gd","Vector2(2.8, 7.2), Vector2(29.2, 7.2), Vector2(10.9, 1.5)","Vector2(2.8, 7.2), Vector2(16.0, 7.2), Vector2(10.9, 1.5)"),
 ("0 arena: box on the crate","sim/config.gd","const BOX_POS := Vector2(16.0, 12.1)","const BOX_POS := Vector2(16.0, 3.0)"),
 ("0 pose: the imp does not bounce","view/toy_pose.gd","out[LIFT] += 0.8 * w * hop","out[LIFT] += 0.05 * w * hop"),
 ("0 pose: the die barely rolls","view/toy_pose.gd","out[ROLL] += 0.3 * w * q","out[ROLL] += 0.05 * w * q"),
 ("0 pose: the doll's roll is in phase with its lean","view/toy_pose.gd","out[ROLL] += 0.24 * w * cos(f.gait)","out[ROLL] += 0.24 * w * sin(f.gait)"),
 ("0 pose: the doll does not sway at rest","view/toy_pose.gd","out[ROLL] += 0.07 * sin(f.time * 1.7) * (1.0 - walk)","out[ROLL] += 0.0"),
 ("0 pose: the top does not wobble at rest","view/toy_pose.gd","out[ROLL] += 0.05 * sin(f.time * 3.1)","out[ROLL] += 0.0"),
 ("0 pose: the top does not lean into its walk","view/toy_pose.gd","out[LEAN] += 0.14 * w\n","out[LEAN] += 0.0 * w\n"),
 ("0 pose: a kind without walk cycle","view/toy_pose.gd",", 4.4, 2.6, 2.8]",", 4.4, 2.6]"),
 ("0 figure: the eyes never close","view/toy_figure.gd","var open := 0.12 if _blink < 0.0","var open := 1.0 if _blink < 0.0"),
 ("0 figure: the eyes never open again","view/toy_figure.gd","\tif _blink < -BLINK_TIME:\n","\tif false:\n"),
 ("0 figure: the bunny's button eyes do not blink","view/toy_figure.gd","\t\t_eyes.append(eye)\n\t\t_p(eye, ToyKit.sphere(), ToyKit.plastic(INK), Vector3.ZERO, Vector3(0.3,","\t\t_p(eye, ToyKit.sphere(), ToyKit.plastic(INK), Vector3.ZERO, Vector3(0.3,"),
 ("0 figure: the spring coils lift with the hop","view/toy_figure.gd","0.24 * k - lift * (1.0 - k / 3.0)","0.24 * k"),
 ("0 figure: the top's part does not turn","view/toy_figure.gd","_spin.rotation.y = -motion.wind * 1.6","_spin.rotation.y = 0.0"),
 ("0 figure: hand_point ignores the paw","view/toy_figure.gd","if _paw != null and is_inside_tree() and visible:","if false:"),
 ("0 figure: the arm ignores the string direction","view/toy_figure.gd","\tif string_dir != Vector2.ZERO:\n\t\tvar loc","\tif false:\n\t\tvar loc"),
 ("0 figure: the wound-up hand is not behind the shoulder","view/toy_figure.gd","var tgt := HAND_WOUND.lerp(HAND_HOLD, clampf((arm + 1.0) / 1.3, 0.0, 1.0))","var tgt := HAND_HOLD"),
 ("0 view: a changed skin keeps the old figure","view/arena_view.gd","\t\tif fig.kind != posmod(p.skin, ToyFigure.NAMES.size()):","\t\tif false:"),
 ("0 view: a swapped figure loses the local ring","view/arena_view.gd","\t\told.remove_child(_ring)\n\t\tfig.add_child(_ring)","\t\told.remove_child(_ring)"),
 ("0 view: the arm is not told the string direction","view/arena_view.gd","\t\t\t\t\tfig.string_dir = to.normalized()","\t\t\t\t\tpass"),
 ("0 view: the string starts at the body","view/arena_view.gd","var prev3 := hand3","var prev3 := Vector3(pos.x, STRING_Y, pos.y)"),
 ("0 view: a flying yo-yo has no arc","view/arena_view.gd"," + sin(t * PI) * FLIGHT_ARC",""),
 ("0 view: a retracting yo-yo stays low","view/arena_view.gd","\t\t\treturn lerpf(HEAD_Y, hand_y, t * t)","\t\t\treturn HEAD_Y"),
 ("0 playroom: no track","view/playroom.gd","\t_build_track()\n\t_build_train()","\t_build_train()"),
 ("0 playroom: one car missing","view/playroom.gd","\tfor k in TrainTrack.CARS:\n\t\tvar car := Node3D.new()","\tfor k in TrainTrack.CARS - 1:\n\t\tvar car := Node3D.new()"),
 ("0 playroom: the cars ignore the sim","view/playroom.gd","var s := lerpf(sim.prev_train_s, sim.train_s, alpha)","var s := 0.0"),
 ("0 playroom: the cars are not interpolated","view/playroom.gd","var s := lerpf(sim.prev_train_s, sim.train_s, alpha)","var s := sim.train_s"),
 ("0 playroom: all cars at one place","view/playroom.gd","var cs := TrainTrack.car_s(s, k)","var cs := s"),
 ("0 playroom: the cars stay when the train is off","view/playroom.gd","car.visible = sim.cfg.train_speed > 0.0","car.visible = true"),
 ("0 playroom: the present does not burst","view/playroom.gd","\tdbg.visible = true\n","\tdbg.visible = false\n"),
 ("0 playroom: the debris does not fly","view/playroom.gd","\t\tpt.position = p\n","\t\tpass\n"),
 ("0 playroom: the debris never goes away","view/playroom.gd","\t\t_debris_t = -1.0\n\t\tdbg.visible = false\n\t\treturn","\t\t_debris_t = -1.0\n\t\treturn"),
 ("0 look: rounded_box wound the wrong way","view/toy_kit.gd","\t\t\tst.add_index(a)\n\t\t\tst.add_index(b)\n\t\t\tst.add_index(a + 1)\n\t\t\tst.add_index(a + 1)\n\t\t\tst.add_index(b)\n\t\t\tst.add_index(b + 1)\n","\t\t\tst.add_index(a)\n\t\t\tst.add_index(a + 1)\n\t\t\tst.add_index(b)\n\t\t\tst.add_index(a + 1)\n\t\t\tst.add_index(b + 1)\n\t\t\tst.add_index(b)\n"),
 ("0 look: the imp has feet again","view/toy_figure.gd","Vector3(sx * 0.3, 0.14, 0.12))\n","Vector3(sx * 0.3, 0.14, 0.12))\n\t\t_p(foot, ToyKit.sphere(), body_mat, Vector3(0, 0, 0.12), Vector3(0.46, 0.28, 0.85))\n"),
 ("0 look: the top has feet again","view/toy_figure.gd","\t_foot_l = _piece(\"FootL\", Vector3(-0.3, 0.12, 0.1))\n","\t_foot_l = _piece(\"FootL\", Vector3(-0.3, 0.12, 0.1))\n\t_p(_foot_l, ToyKit.sphere(), dark, Vector3(0, 0, 0.08), Vector3(0.42, 0.26, 0.6))\n"),
 ("0 look: the doll has feet again","view/toy_figure.gd","\t_foot_l = _piece(\"FootL\", Vector3(-0.3, 0.1, 0.4))\n","\t_foot_l = _piece(\"FootL\", Vector3(-0.3, 0.1, 0.4))\n\t_p(_foot_l, ToyKit.sphere(), paint, Vector3(0, 0, 0.1), Vector3(0.42, 0.24, 0.62))\n"),
 ("0 look: the top's base spin ignores running","view/toy_motion.gd","SPIN_IDLE + SPIN_RUN * walk)","SPIN_IDLE)"),
 ("0 look: the top's base spin ignores the dash","view/toy_motion.gd","(SPIN_DASH if dashing or facts.pulling else SPIN_IDLE + SPIN_RUN * walk)","(SPIN_IDLE + SPIN_RUN * walk)"),
 ("0 look: the top's base node does not turn","view/toy_figure.gd","\t\t_base.rotation.y = motion.spin\n","\t\tpass\n"),
 ("0 look: the dino's jaw does not open with the charge","view/toy_pose.gd","out[JAW] = 0.3 + 0.7 * c if f.kind","out[JAW] = 0.3 if f.kind"),
 ("0 look: the dino's jaw does not snap in step","view/toy_pose.gd","out[JAW] = w * 0.75 * smoothstep(-0.15, 0.15, sin(f.gait * 2.0))","out[JAW] = w * 0.75 * 0.5"),
 ("0 look: the duck's wheels do not turn","view/toy_figure.gd","\t\tw.rotation.x = f.gait\n","\t\tw.rotation.x = 0.0\n"),
 ("0 look: the doll does not tip into its run","view/toy_pose.gd","out[TILT_F] = 0.55 * clampf(f.fwd_speed, -1.0, 1.3)","out[TILT_F] = 0.0"),
 ("0 look: the doll's swing never dies down","view/toy_pose.gd","1.0, 1.0, 0.28, 0.5, 0.13, 0.13]","1.0, 1.0, 0.28, 0.5, 0.0, 0.0]"),
 ("0 look: the doll does not swing back","view/toy_pose.gd","1.0, 1.0, 0.28, 0.5, 0.13, 0.13]","1.0, 1.0, 0.28, 0.5, 1.2, 1.2]"),
 ("0 look: the bunny is too small for its hit circle","view/toy_figure.gd","Vector3(1.95, 1.6, 1.9))","Vector3(1.4, 1.2, 1.4))"),
 ("7 menu: the preview ignores the choice","view/tuning_menu.gd","_figure_preview.show_figure(cfg.character,","_figure_preview.show_figure(0,"),
 ("7 menu: the preview is not refreshed","view/tuning_menu.gd","if _figure_preview.figure == null or _figure_preview.figure.kind != cfg.character:","if _figure_preview.figure == null:"),
]

def suites_for(name, full):
    if full: return ['sim','net','update','view']
    return SUITES_OVERRIDE.get(name) or [PREFIX_SUITE[name[0]]]

def game_snapshot():
    # What the working tree looks like under game/ (the only place a sabotage could end up in): path -> content.
    snap={}
    for d,dirs,files in os.walk(GAME):
        dirs[:]=[x for x in dirs if x!='.godot']
        for fn in files:
            p=os.path.join(d,fn)
            snap[p]=open(p,'rb').read()
    return snap

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('-j',type=int,default=max(1,(os.cpu_count() or 2)//2))
    ap.add_argument('--full',action='store_true')
    ap.add_argument('prefix',nargs='*')
    a=ap.parse_args()
    todo=[e for e in SB if not a.prefix or any(e[0].startswith(o) for o in a.prefix)]
    before=game_snapshot()
    t0=time.time()
    res=[]
    runnable=[]
    for e in todo:
        name,f,old,new=e[:4]
        n=open(os.path.join(GAME,f),encoding='utf-8').read().count(old)
        if n!=1:
            print("!! pattern count",n,name); res.append((name,'PATTERN')); continue
        runnable.append(e)
    tmp=tempfile.mkdtemp(prefix='sabotage-')
    try:
        if runnable:
            base=os.path.join(tmp,'base')
            shutil.copytree(GAME,base,ignore=shutil.ignore_patterns('.godot'))
            # One import pass (class names, resources); every worker gets a copy of the result.
            subprocess.run([os.environ.get('GODOT','godot'),'--headless','--path',base,'--import'],capture_output=True)
            nworkers=max(1,min(a.j,len(runnable)))
            q=queue.Queue()
            for e in runnable: q.put(e)
            lock=threading.Lock()
            def worker(w):
                d=os.path.join(tmp,'w%d'%w)
                shutil.copytree(base,d)
                env=dict(os.environ,GAME_DIR=d,TEST_PORT_OFFSET=str(w*PORT_STEP),TEST_STOP_ON_FAIL='' if a.full else '1')
                while True:
                    try: e=q.get_nowait()
                    except queue.Empty: return
                    name,f,old,new=e[:4]
                    path=os.path.join(d,f)
                    orig=open(path,'rb').read()
                    open(path,'wb').write(orig.decode().replace(old,new).encode())
                    suites=suites_for(name,a.full)
                    try:
                        out=subprocess.run([RUN]+suites,capture_output=True,text=True,env=env,timeout=900).stdout
                    except subprocess.TimeoutExpired:
                        out='TIMEOUT'
                    finally:
                        open(path,'wb').write(orig)
                    fails=[l[6:90] for l in out.splitlines() if l.startswith('FAIL')]
                    err='SCRIPT ERROR' in out or 'Parse Error' in out
                    caught=bool(fails or err) and out!='TIMEOUT'
                    with lock:
                        print(("OK   " if caught else "NOT CAUGHT"),name,"| suites:",",".join(suites),"| fails:",len(fails),"| script err:",err,"|",fails[:2] if out!='TIMEOUT' else 'TIMEOUT',flush=True)
                        res.append((name,caught))
            ts=[threading.Thread(target=worker,args=(w,)) for w in range(nworkers)]
            for t in ts: t.start()
            for t in ts: t.join()
    finally:
        shutil.rmtree(tmp,ignore_errors=True)
    untouched=game_snapshot()==before
    print("working tree untouched (game/ identical before and after):",untouched)
    ok=untouched and all(r[1] is True for r in res)
    print("ALL CAUGHT" if ok else "PROBLEMS",len(res),"entries in %.0f s"%(time.time()-t0), "(full suite per entry)" if a.full else "")
    sys.exit(0 if ok else 1)

main()
