# Map rework: walls, themes, hiding, crushers

A plan that is built step by step, one pull request per step, by different sessions. Each step is written so
that a session can pick it up without the conversation it came from. Tick a step off in "Progress" (at the end)
in the same pull request that builds it, and write down there what turned out differently.

Decided by the owners on 2026-11-16. The current maps are described in `docs/maps.md`; that file is updated by
every step that changes a map (sketch, numbers).

## Why

Played on the phone, the six maps feel the same in spite of their twists:

- Every map is one open room with four or five blocks. Everybody sees everybody from the first second, is
  attacked at once, and a round is over far too quickly.
- The spawn points are few and close to each other.
- Every map has the same purple carpet, the same lettered blocks and the same wooden frame. Nothing tells
  which room you are in, and nothing but the twist object belongs to the map.

## Goals

1. **Floor plans.** Every map has its own floor plan with clearly more walls, so that players start out of
   sight of each other and have to come looking. The floor plan supports the map's twist.
2. **Themes.** Every map is a different room of the house with its own floor, its own walls, its own objects
   and its own surroundings outside the arena, fitting the twist.
3. **Tall carpet** to hide in (on some maps).
4. **Switches that move an object which crushes players** (on some maps).

The reference the owners named is the map variety of party arena brawlers (mazes, a room cut into quarters,
choke points, tall grass, moving walls). Take the principles only. Do not copy a floor plan, an object or the
look of another game.

## Rules for every step

- The architecture rule holds: rules in `game/sim` (pure, deterministic, in the snapshot), look in
  `game/view`. Numbers of a map live in `game/sim/map_def.gd`.
- Play never sees tuned values: nothing here becomes a `Config` tuning variable.
- Obstacles stay axis-aligned `Rect2` entries of `MapDef.OBSTACLES` (map 0: `Config.OBSTACLES`). A wall is a
  thin obstacle, at least 0.8 m thick (thinner ones were never tested against fast yo-yo heads).
- The four final zone areas of a map (`ZONE_SPOTS`, each 8.0 x 3.6 m) stay free of obstacles, hazards, the
  chest and the present, as today. They are the four "clearings" of a floor plan; the walls stand between them.
- No UI during a round. Everything announces itself in the world.
- Every new behaviour gets a test and a sabotage entry (`tests/sabotage.py`, the live list at the END of the
  file), and the sabotage check is really run for the new entries.
- A changed layout or new snapshot state makes old and new clients incompatible: `NetProto.VERSION` goes up in
  the first pull request after a release that changes either. Check which protocol version the last release
  had (`git show <tag>:game/net/net_proto.gd`); raise it once, not once per pull request.
- Every step adds its user-visible change to the section of the next version in `CHANGELOG.md` and updates
  "Project knowledge" in `AGENTS.md` (the entries "Maps" and "Look").
- The look cannot be seen on the owner's machine directly. Still pictures can be rendered in a container with
  `tools/render-preview.sh` (needs Docker; it runs `tools/character_preview.gd`, so a map picture needs its
  own small script next to it). Every theme step renders one top-down still per changed map, looks at it, and
  puts it into the pull request (not into the repository). Motion and the feel on a phone stay unchecked: say
  so in the pull request.
- Performance on a phone: share materials (`ToyKit`), use `MultiMeshInstance3D` for anything repeated, keep the
  decoration of one map below roughly 250 mesh instances, no real-time lights or shadows beyond what exists.

## Step F: foundations (first, before any map)

Everything the new floor plans need and all maps share. No map changes its layout in this step.

1. **Bots find their way.** Today a bot steers straight at its target and only pushes away from blocks
   (`game/input/bot.gd`, `_wander` and the chase code); between many walls it gets stuck. Add a pure
   `NavGrid` (`game/sim/nav_grid.gd`): a grid of about 0.8 m cells over the arena, built from a sim's
   `statics` grown by the player radius, with a breadth-first search (8 neighbours, no cutting of corners) and
   a line-of-sight test (segment against the statics). It is derived data: cache it per map id, never put it
   into the snapshot (`STATE_SKIP` if a state object ever holds it). The bot walks towards its target directly
   when it has a clear walking line and otherwise towards the next waypoint of the path. The chest is ignored
   by the grid (it moves; bots push it). Everything stays deterministic: no randomness outside the bot's own
   rng. Tests: a path around a wall exists and is free; a bot placed behind a long wall reaches a target on
   the other side within a time limit; the existing bot and determinism tests still pass on all maps.
2. **Bots do not throw at walls.** A bot only throws at an enemy it has a clear line to, or one bounce away if
   that is cheap to compute; otherwise it walks. (Check what the code does today first; keep it if it already
   tests the line.)
3. **Spread-out starts.** `Sim._start_round` shuffles the eight spawn points and gives the first ones to the
   players, so two players often start next to each other. Change it to: the first spawn point is drawn with
   the sim's rng, every further player gets the free spawn point farthest from all points already given
   (ties: lowest index). `reset_round`-style free play and `_respawn` keep their rules. Test: with 2, 3 and 4
   players and many seeds, the smallest distance between two starts is the best possible for that first point;
   sabotage entry.
4. **Floor-plan rules as tests** (`tests/test_sim.gd`, in `_map_geometry`, for every map). They pass for the
   current maps where possible; a rule that an old layout cannot meet is switched on per map with a list
   `REWORKED` (map ids already rebuilt), which the map steps extend:
   - every spawn point, zone area centre, the chest start and the present are reachable from each other on the
     `NavGrid` (belts, trampolines and lava do not count as walls);
   - every passage is at least 2.0 m wide (the chest is 1.4 m): no two obstacles, and no obstacle and outer
     wall, are closer than 2.0 m unless they touch or overlap in a way that closes the gap completely
     (obstacles that touch to form an L or T are allowed; the old "do not overlap each other" check becomes
     "do not overlap except by touching edges");
   - reworked maps: 10 to 18 obstacles; any two spawn points are at least 6 m apart; no two spawn points
     closer than 14 m see each other (the segment between them hits an obstacle); every spawn point has at
     least 1.5 m of free floor around it.
5. **A map as text.** `tools/map_ascii.gd` (run with `godot --headless --path game -s ../tools/map_ascii.gd --
   [id]`) prints a map as characters, one per 0.8 x 0.8 m cell: `#` obstacle, `1`-`8` spawn points, `z` zone
   areas, `C` chest, `P` present, and the map's own things (belt arrows, pads, magnets, pig, track, later rugs
   and crushers). Layout steps paste this print into `docs/maps.md` and the pull request, so a floor plan can
   be reviewed without a picture.
6. **Walls that do not look stretched.** `Playroom._build_block` stretches one lettered cube over the whole
   rectangle, which looks wrong for a long wall. Until the themes exist: an obstacle whose long side is more
   than 1.5 times its short side is drawn as a row of equal blocks (near-square footprints, alternating colours
   and letters). View test: the row covers exactly the rectangle.

## Step A: floor plans

One pull request per map, or two maps together when small. For every map: new `OBSTACLES`, `SPAWNS`,
`ZONE_SPOTS`, chest and present places, the map id added to `REWORKED`, the twist's own numbers moved where
the plan below says so, bots checked (the per-map bot tests: map deaths stay rare, a bot match round ends),
`docs/maps.md` updated with the `map_ascii` print. The layouts below are the idea and the constraints; the
exact rectangles are the builder's job, checked by the tests of step F and reviewed on the ASCII print. Keep
every layout point-symmetric or mirror-symmetric so that no start is better than another.

Lengths in metres; the arena is 32 x 14.4, x to the right, y down from the top wall.

### 0 Train Set: the ring road

- The track (`TrainTrack`: a rounded rectangle x 10.5..21.5, y 3.6..10.8) stays. It becomes the main road.
- **Inside the loop:** the big centre block stays; add two short walls so that the inside is a small yard with
  two entrances across the rails (top left, bottom right). Whoever hides inside must cross the rails.
- **Outside the loop:** four walls run from the outer wall towards the track and stop 2 m before it (two from
  the top wall, two from the bottom wall, at about x = 9 and x = 23), plus one short wall at each short side at
  mid height. That makes four corner rooms and two side rooms, all connected only along the track.
- Spawn points: one in each corner room, one in each side room, two between the top/bottom walls next to the
  track but outside it. Zone areas: the two side rooms and two corner rooms (keep them free).
- The train geometry checks at the end of `_train_tests` must still hold (clearance of every obstacle to the
  track).

### 1 Assembly Line: the belt is the fast way through

- The S-shaped belt stays where it is.
- Two long walls divide the room into three parts, left, middle and right, roughly along x = 9.5 and x = 22.5.
  Each wall has a walking door (2.4 m) far from the belt, and the belt runs **through** a second opening in
  it: riding the belt is the quick way into the next part, but only in the direction it currently runs.
- Short walls stand along parts of the belt's edges (never both sides at the same x), so the belt is a channel
  with places to step off.
- Spawn points: three in the left part, two in the middle (off the belt), three in the right part. Zone areas:
  as today where still free, otherwise moved off the belt.
- Trap: the chest starts on the belt and pushes things; keep that (`map_sim(..., far_crate)` in the tests).

### 2 Lava Mats: the pillow fort

- The mats are a grid of 8 x 4 cells of 4.0 x 3.6 m. Walls stand **on the seams** between mats (centred on
  the seam, 0.8 m thick), never across a mat.
- The lava rule guarantees that of every mat pair (columns 0-1, 2-3, 4-5, 6-7 of a row) one mat stays safe. A
  wall must therefore never close the seam inside a pair (x = 4, 12, 20, 28) completely: at most half of that
  seam's length. Seams between pairs (x = 8, 16, 24) and between rows (y = 3.6, 7.2, 10.8) carry the walls,
  each wall segment with a door of at least 2.0 m per mat edge it runs along or ending before the next
  crossing.
- Shape: a pinwheel. From the centre crossing (16, 7.2) four walls run out, each turning once (a swastika-free
  pinwheel: use L shapes of different arm lengths, mirrored in pairs, so it reads as a pillow fort and not as
  a symbol; check the ASCII print for that). The current centre block goes; the corner blocks become wall
  ends.
- Spawn points: one per quarter near the outer wall, one per quarter near the centre, never two in the same
  mat. Zone areas: one mat pair each, free of walls inside (walls on their outer seams are fine).
- New test: for every wave and many seeds, every player-reachable mat has a safe mat reachable without
  crossing a burning one within the warning time at walking speed. If that cannot be guaranteed by layout
  alone, lower the walls' coverage until it can; do not change the lava numbers.

### 3 Bounce House: over the fence

- The trampolines are shortcuts over walls, so the walls must be worth jumping. Three long walls divide the
  room into four strips side by side (about x = 8, 16, 24), each wall with ONE walking door, alternating top
  and bottom, so that walking from the far left to the far right is a long zigzag.
- Every trampoline stands in one strip and lands in the next one or the one after: jumping is the fast and
  loud way. Keep four pads; move them and their landing spots (`MapDef.PADS`) so that each strip has one pad
  and one landing spot, a landing spot never lies in a doorway, and a pad never lies within 2 m of a spawn
  point.
- Two or three short walls inside the strips give cover from the doors.
- Spawn points: two per strip, far from the doors. Zone areas: one per strip.
- The bot rule "do not step on a pad whose landing spot is outside the zone" stays; add: a bot whose path is
  long and whose strip has a pad leading closer may use it.

### 4 Magnet Lab: shots around the corner

- The two magnets stay at (11, 7.2) and (21, 7.2). A bent throw should reach somebody behind cover.
- Around each magnet, between 2.5 m and 5 m from it, stand four short walls like the sides of a broken square
  (each about 3 m long, open corners): a straight throw is blocked, a throw bent by the pulling magnet goes
  round. The two squares must not touch; between them the centre wall stays, a little longer (0.8 x 4.4).
- Towards each short side of the room one wall stands across (about x = 4 and x = 28, 5 m long, centred), so
  that the two ends are rooms with two entrances.
- Spawn points: two in each end room, one above and one below each magnet square. Zone areas: the two end
  rooms and two of the four areas above/below the squares; move walls rather than give up a zone area.
- `aim_path` (the bent aim line) must still equal the real flight; its test runs unchanged.

### 5 Piggy Bank: the shop with the open counter

- The pig stays in the centre, and the centre stays an open square of about 8 x 6 m: taking the coins means
  showing yourself.
- Around the square a ring of shelves (walls) with four entrances, one in the middle of each side; the four
  blocks that stand around the pig today become the corners of that ring (L-shaped pairs).
- Outside the ring: two aisle walls on each long half (parallel to the short sides, at about x = 5 and
  x = 27, 6 m long, centred), so the ends of the room are aisles with entrances at the top and the bottom.
- Spawn points: two per end aisle (top and bottom), two above and two below the ring near the outer wall.
  Zone areas: the four corners as today (keep them free: the aisle walls stop before them, or the areas move
  towards the long walls).
- The pig rule (a thrown yo-yo that touches it takes the coins) is unchanged; from outside the ring the pig
  can be hit only through an entrance.

### After all six

Play rounds will last longer. If rounds drag on the phone, the zone times are the control
(`MatchMode.ZONE_FULL_TIME` 20 s, `ZONE_SHRINK_TIME` 30 s): ask the owners before changing them.

## Step B: themes

First one shared pull request, then one per map.

**B0, shared.** A `MapTheme` (`game/view/map_theme.gd`, view only, data per map id): floor (shader or colours
of the arena floor), frame (the beams around the arena), surround (the floor outside and what lies on it),
wall style (how an obstacle rectangle is dressed; replaces the lettered blocks per map), and a list of
decoration (props that collide with nothing: outside the arena, on top of walls, or flat on the floor).
`Playroom` builds from the theme of `sim.map_id`. The chest and the present may get a themed skin; their size
and the present's place do not change. Flat floor decoration must never look like a wall or a hazard, and
nothing may hide a player, a yo-yo or a twist's warning: twist objects keep their strong colours, decoration
stays calmer than they are. Tests (`tests/test_view.gd`): every map builds with its theme, wall dressing
covers exactly its rectangle, the mesh count stays under the budget, `ArenaView` rebuilds on a map change.

**Per map** (twist in brackets). The room, its floor, its walls, the things in it and around it:

| Map | Room | Floor | Walls are | In and around |
| --- | ---- | ----- | --------- | ------------- |
| 0 Train Set (train) | Child's bedroom | Play carpet with printed streets and houses | Building blocks (the lettered ones stay here), standing picture books, a wooden toy bridge | Outside: wooden floorboards, a bed edge with a hanging blanket, crayons, a ring tower, marbles, a teddy leaning on the frame. Track with a little station and a level crossing sign. |
| 1 Assembly Line (belts) | Workshop / garage | Concrete with yellow-black hazard stripes along the belt, oil stains | Toolboxes, stacked planks, paint cans in a row, a tyre | Outside: a workbench edge, screws and nuts, a spanner, a cable drum. Belt ends with rollers and a blinking lamp (exists). |
| 2 Lava Mats (lava) | Living room | The foam puzzle mats (exist), calmer colours | Sofa cushions and pillows (soft, rounded, with seams and buttons) | Outside: wooden floor, a sofa front, a side table leg, a rug corner, a remote control, slippers, a floor lamp base. |
| 3 Bounce House (trampolines) | Garden, birthday party | Lawn with mown stripes, daisies | Low hedges and a white picket fence, an inflatable wall in two colours | Outside: more lawn, flower beds, a garden hose, balloons tied to the frame, a bunting line, a ball. Frame: a wooden sandbox edge. |
| 4 Magnet Lab (magnets) | Desk with a science kit | Green cutting mat with a white grid | Rulers on edge, thick books, pencil cases, batteries, an eraser | Outside: the wooden desk top, sheets of paper with sketches, paper clips and iron filings near the magnets, pencils, a desk lamp foot. |
| 5 Piggy Bank (pig) | Play shop | Black-and-white checkered shop floor, a rug under the pig (exists) | Shelves with tiny groceries, fruit crates, a counter | Outside: a toy cash register, a shopping basket, play money, a price sign. The chest is a delivery crate. |

A seventh map, the **bathroom** (wet tiles to slide on, a drain or a bath duck), was named by the owners and
is not planned yet: propose its twist to them when the six are done.

## Step C: tall carpet

- Data: `MapDef.RUGS`, per map a list of rectangles (empty for most maps). Planned: Train Set (a shaggy rug in
  each side room), Bounce House (tall grass in two strips), Piggy Bank none, others none at first.
- Rule (pure, in `Sim`): a player whose centre is in a rug is **hidden** unless revealed. Revealed for
  `RUG_REVEAL` (1.0 s) after: throwing, a yo-yo of theirs being out, dashing, being hit or stunned. Always
  visible to a player who stands within `RUG_NEAR` (2.5 m) or in the same rug. State: `SimPlayer.reveal_t`
  (in the snapshot). One pure function `Sim.visible_to(viewer, target)` is what the view and the bots both ask.
- View: a hidden player that the local player may not see is not drawn at all (figure, colour ring, aim
  line); the local player's own figure is drawn sunk into the rug so they know they are hidden; the rug
  moves a little where somebody walks only when that player is visible. Yo-yo heads, strings and shards are
  always drawn. Offline with several bots the viewer is player 0.
- Bots do not target, chase or flee a player that `visible_to` hides from them, and may wait in a rug.
- The hiding is honest only on the screen: every client receives every position. That is accepted (a game
  among friends); do not build server-side filtering.
- Zone areas may contain a rug; the zone kills hidden players like everybody else.
- Tests: the reveal rules one by one, `visible_to` both ways, bots ignore a hidden player, the view hides and
  shows the figure; sabotage entries. The rug itself is drawn by the map's theme (shag carpet, tall grass).

## Step D: switches and crushers

- Data: `MapDef.CRUSHERS`, per map a list of `[switch position, crush rectangle]`. Planned: Assembly Line (a
  press that stamps down on a piece of the belt, switch a few metres away next to the belt) and Piggy Bank
  (the drawer of the cash register that shoots out across one entrance of the shelf ring). Others later.
- Rule: a living player whose centre is within `SWITCH_RADIUS` (0.7 m) of a ready switch presses it. The
  crusher then warns for `CRUSH_WARN` (0.7 s: it must be readable), strikes for `CRUSH_HOLD` (0.4 s) and
  rests for `CRUSH_REST` (5 s) before the switch is ready again. While it strikes, every living player whose
  hit circle touches the rectangle dies: a real kill with credit and coins for the player who pressed
  (`cause: "crush"`), no credit when they crush themselves. A crusher is not a wall: nothing collides with it
  and yo-yos pass. State per crusher (phase clock, who pressed) in the snapshot.
- Zone areas and spawn points never overlap a crush rectangle or a switch. `_respawn` treats a warning or
  striking rectangle as unsafe.
- Bots: leave a rectangle that warns; press a switch when an enemy is in the rectangle and they are close to
  the switch; never stand in a rectangle while an enemy is close to its switch.
- View: the switch is a big floor button in the crusher's colour, down while not ready; the crusher shakes
  and its shadow grows while warning. No text.
- Tests: the phases and their times, kill with credit, self-crush without credit, no kill outside the
  rectangle or outside the strike, the bots' three rules, geometry (above); sabotage entries.

## Order

F, then A for maps 0 to 5 in that order, then B0 and B for maps 0 to 5, then C, then D. A release for the
testers is the owners' call; a good moment is after A (the floor plans are what should change how it plays).

## Progress

- [x] F foundations (built as written. Notes: the bots already threw without looking for a wall, so point 2 added the
  line test; the 2.0 m passage rule fails on the old layouts of maps 0 to 4 (map 5 passes), so it is behind
  `REWORKED` with the other strict rules, only connectivity runs for every map; `NetProto.VERSION` stays 9 because
  neither a layout nor the snapshot changed. `REWORKED` lives in `MapDef`.)
- [x] A0 Train Set (built; 11 obstacles, `NetProto.VERSION` is now 10 for the whole step A. Changes against the idea:
  the "short wall at each short side at mid height" became four horizontal walls from the left and right walls
  (they make the corner rooms and side rooms the plan names); the inside of the loop got a pinwheel (a wall on
  each side of the centre block) instead of walls that close two entrances, because the rails are not an obstacle
  and a yard cannot be closed against them; the top walls are 4.2 m long and stop 2 m before the track's corner
  arcs, not before the straight. Old tests: `test_sim` already runs in an arena without obstacles (`mk()`), so
  they did not change; `test_net` clears the obstacles of its rigs with `open_arena()`. Later map steps: expect
  the same, keep the zone areas free, and fix stale sabotage patterns that quote the old layout.)
- [x] A1 Assembly Line (built; 12 obstacles, point-symmetric. Changes against the idea: the dividing walls are
  1.0 m thick at x 9..10 and 22..23, with a 2.6 m belt opening and a 2.4 m walking door each (the door at the end of the
  wall away from the belt, so the left wall's door is at the bottom and the right wall's at the top); the short walls
  along the belt are two long horizontal covers per side part (they also split each side part into three starting
  pockets, which the 14 m sight rule needs) and two short walls on opposite sides of the vertical run; zone areas moved
  down by 0.2 to 0.4 m to clear the new walls. Old tests: none had to change, the belt tests already run on
  stripped arenas.)
- [x] A2 Lava Mats (built; 12 obstacles, point-symmetric, `NetProto.VERSION` 12, version 0.13.0 because 0.12.0 was
  released with the old layout of map 2. Changes against the idea: the pinwheel is a windmill of four touching bars
  around an open 2 m courtyard (a plus-shaped hub is impossible: two bars separated by a third closer than 2.0 m break
  the passage rule), two long and two short bars so it does not read as a symbol; the bars are 1.0 m thick because
  touching 0.8 m bars overlap by a float32 rounding error; walls next to a zone area sit flush against it (0.4 m off
  the seam) because a wall centred on the seam would reach 0.4 m into the area; the zone areas moved to the
  top-middle-right, bottom-middle-left, left and right mat pairs; four corner rooms replace the corner blocks. The
  escape test checks the real walking distance on the NavGrid (limit speed x `LAVA_WARN` = 9 m), so layout alone
  guarantees it. Bot: `_lava_steer` now walks the NavGrid path. Old tests: only the position of the safe player in
  `_lava_tests` was moved off a new wall.)
- [x] A3 Bounce House (built; 11 obstacles, mirror-symmetric about x = 16 instead of point-symmetric because the zigzag of doors (top, bottom, top) is not point-symmetric; `NetProto.VERSION` 13. Changes against the idea: the strips are 8.5, 6, 6 and 8.5 m wide, doors are 4.0 m tall so a zone area fits across the top ones; pads S1->S2, S2->S4, S4->S3, S3->S1; the bot rule is `Bot._pad_goal` (walk to a pad when it saves 10 m of walking and is within 9 m on foot, via `NavGrid.path_length`). Old tests: the pad test in `_bounce_tests` was moved to the new pad positions.)
- [ ] A4 Magnet Lab
- [ ] A5 Piggy Bank
- [ ] B0 theme system
- [ ] B1..B6 themes of maps 0 to 5
- [ ] C tall carpet
- [ ] D switches and crushers
