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
