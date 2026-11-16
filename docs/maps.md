# Maps

Six maps: the playroom with the toy train (map 0, new floor plan since 0.11.0) and five new ones. Every map is the same
room (32 x 14.4 m, same walls, same camera) with other toys on the carpet, and every map has ONE twist of a
different kind. All rules below live in the pure simulation (`game/sim`), are part of the snapshot and are
deterministic; the view only reads them.

| Id | Name          | Kind of twist                         | In one sentence                                                        |
| -- | ------------- | ------------------------------------- | ---------------------------------------------------------------------- |
| 0  | Train Set     | moving hazard                         | A toy train circles the centre and runs players over.                  |
| 1  | Assembly Line | terrain that moves you                | Conveyor belts carry players, the chest and lying yo-yos, then reverse. |
| 2  | Lava Mats     | map-wide event on a timer             | "The floor is lava": more and more foam mats glow, then burn.          |
| 3  | Bounce House  | launch / teleport                     | Trampolines fling you over the wall; land on somebody to squash them.  |
| 4  | Magnet Lab    | bends the yo-yo itself                | Two magnets pull and push flying and lying yo-yos, and swap roles.     |
| 5  | Piggy Bank    | risk / reward                         | The pig in the open centre saves up coins; a yo-yo hit takes them all. |

Where things live: `game/sim/map_def.gd` (`MapDef`: all layout data and every number of the twists, pure
functions), the section "maps" at the end of `game/sim/sim.gd` (the rules), `game/input/bot.gd` (what bots do
about them), `game/view/playroom.gd` and `game/view/map_props.gd` (the look).

Sketches: one character is 1 m wide and 1.8 m tall, so they are 32 x 8 and only rough (exact numbers:
`MapDef`). `#` block, `C` toy chest (the movable crate), `P` present (the breakable box), `1`-`8` spawn points.
On Lava Mats the lines are the borders of the mat pairs. Where the shrinking zone can end: `MapDef.ZONE_SPOTS`.

## Common rules

- Size, outer walls, the chest, the present, eight spawn points and four final zone areas exist on every map.
  The zone areas are always free of blocks, of the chest's and the present's start and of anything that kills
  or throws a player out (belts, trampolines).
- A death by a map counts like the train: a death for the victim, a kill for nobody (`killer: -1`,
  `cause: "lava"`). The squash of the Bounce House is a real kill with credit and coins.
- The twist clock (`Sim.map_t`) only runs while a round is played. It starts at zero with every round, so
  every round opens the same way and the first seconds are calm.
- Nothing is shown as UI. Every twist announces itself in the world: belts stop before they turn, mats blink
  before they burn, the landing spot of a trampoline is painted on the floor, the magnets change colour, the
  coins lie on the pig's back.

## 0. Train Set

```
...........#................#zzzzzzzzzz.
...........#....3...........#zzzzzzzzzz.
..5........#.......CC.......#zzzzzzzz8z.
...........#.......CC.......#zzzzzzzzzz.
...........#..tttttttttttt..#zzzzzzzzzz.
########.....t............t.....########
.............t............t.............
.zzzzzzzzzz..t....#######.t..zzzzzzzzzz.
.zzzz1zzzzz..t....####....t..zzzzz2zzzz.
.zzzzzzzzzz..t....####....t..zzzzzzzzzz.
.zzzzzzzzzz..t.#######....t..zzzzzzzzzz.
.............t............t.............
########.....t............t.....########
.zzzzzzzzzz#.tttttttttttttt.#...........
.zzzzzzzzzz#.......PP.......#...........
.zzzzzzzzzz#.......PP.......#...........
.z7zzzzzzzz#...........4....#........6..
...........#................#...........
```
(`#` wall or block, `t` the rails, `z` the four final zone areas, `C` chest, `P` present, `1`-`8` spawn points; one
character is 0.8 m.)

**Twist.** The toy train circles the centre on its loop of rails (x 10.5 to 21.5, y 3.6 to 10.8) and runs over
anyone on it (a death, no kill for anyone). The floor plan (step A0 of `docs/map-rework.md`) makes the rails the
main road: four walls grow from the top and bottom walls towards the track and four more close the left and right
side rooms off from the four corner rooms, so the rooms are connected along the track. Inside the loop the centre
block has a wall on each side (a pinwheel): the yard behind it is a hiding place that has to be reached across the
rails.

**Numbers.** 11 obstacles (`Config.OBSTACLES`, point-symmetric about the arena centre), walls 0.8 m thick,
every passage at least 2.0 m, spawn points at least 6 m apart and out of sight of each other below 14 m, four
free zone areas (left middle, right middle, bottom left, top right).

## 1. Assembly Line

```
...........#...............##zzzzzzzzzz.
...........#...............##zzzzzzzz6z.
..3........#.................zzzzzzzzzz.
....>>>>>>>>>>>>>>>vv........zzzzzzzzzz.
....>>>C>>>>>>>>>>>vv........zzzzzzzzzz.
....>>>>>>>>>>>>>>>vv......##....#######
########...#.......vv......##zzzzzzzzzz.
.zzzzzzzzzz#......#vv......##zzzzzzzzzz.
.zzzzzzzzzz#...7..#vv#..8..##zzzzz2zzzz.
.zzzz1zzzzz#......#vv#.....##zzzzzzzzzz.
.zzzzzzzzzz#.......vv#.....##zzzzzzzzzz.
.zzzzzzzzzz#.......vv......##...########
#######............>>>>>>>>>>>>>>>>>....
.zzzzzzzzzz........>>>>>>>>>>>>>>>>>....
.zzzzzzzzzz........>>>>>>>>>>>>>>>>>....
.zzzzzzzzzz#...............##...........
.z5zzzzzzzz#...............##...P....4..
...........#...............##...........
```
(`#` wall, `>` `v` the belt and its direction, `z` the four final zone areas, `C` chest, `P` present, `1`-`8` spawn points; one character is 0.8 m.)

**Twist.** A building-set conveyor runs through the room in an S: along the top to the middle, down the
middle, along the bottom to the right. It carries everything that stands or lies on it: players, the toy
chest and yo-yos that lie out (they stay deadly while they ride). Every 9 s the belt stops for 1.5 s and
then runs the other way.

**Floor plan (step A1 of `docs/map-rework.md`).** Two dividing walls (x 9 to 10 and 22 to 23, 1.0 m thick) split the
room into a left, a middle and a right part. Each has a belt opening 2.6 m high (the belt runs through it, so riding
it is the quick way into the next part, in the direction it currently runs) and a walking door 2.4 m high at the far
end from the belt. Short walls lie along the belt's edges (under the top run, over the bottom run, and on both sides of
the vertical run at different heights, never both sides at the same x) and double as cover. Spawn points: three in the
left part, two in the middle (off the belt), three in the right part. 12 obstacles, point-symmetric about the arena centre.

**Why it is fun.** The belt is a fast lane and a trap at once. With it you move at 10 m/s instead of 6;
against it only at 2, and while you charge a throw (slower walking) it drags you backwards. A yo-yo thrown
onto the belt becomes a travelling mine that sweeps along the lane until the string is taut. The chest
starts on the belt and wanders through the map, so cover is never where it was last round. The reversal
turns an escape route into a dead end.

**Counterplay.** Step off: the belt is 2.2 m wide and never touches a final zone area. The stop before the
reversal is the warning. A riding yo-yo is predictable: it only moves along the lane.

**Bots.** The belt kills nobody, so bots need no avoidance. They keep steering at their target, which makes
them fight the current like a player would.

**Numbers** (`MapDef`): `BELT_SPEED` 4.0 m/s, `BELT_RUN` 9.0 s, `BELT_STOP` 1.5 s, width 2.2 m. Belt
pieces in `BELTS` (rectangle, direction forwards, direction backwards: the two corner pieces turn the flow).

## 2. Lava Mats

```
...##...|.5.....|.8..##.|.......
...##...|.......|.......|.......
--------+-------+-------+-------
..3.....|...C..##.......|.....2.
--------+------##-------+-------
..1.....|.......|...P...|.....4.
--------+-------+-------+-------
........|#....7.|.....6.|..##...
```

**Twist.** The carpet is a puzzle mat of 8 x 4 foam tiles (4 x 3.6 m each). "The floor is lava" comes in
waves: 3 s of calm, then some mats blink for 1.5 s, then they burn for 2 s and kill whoever stands on them.
The first wave takes 6 mats, every later one 2 more, up to 16: half the floor.

**Why it is fun.** Everybody has to move at the same moment, and everybody sees where everybody else has to
go. A wave herds players onto the same safe mats, which is exactly when a yo-yo is most dangerous. Late in
a round, with half the floor burning and the zone closing, a 2 s stumble from a trip wire is a death
sentence. Because the waves grow, a round has a clear rhythm from calm to frantic.

**Counterplay.** It is always fair: the mats come in pairs (left and right neighbour), and a wave never
takes both mats of a pair. So a safe mat is always right next to you (at most 4 m, 0.7 s of walking, with
1.5 s of warning), and the final zone areas are exactly such pairs, so the last fight always keeps half its
ground. The dash crosses a burning mat's edge in an instant.

**Bots.** On a blinking or burning mat they walk straight to the nearest safe mat; next to one they are
pushed away from its edge; they do not dash while mats are marked. They never respawn on a marked mat.

**Numbers:** `LAVA_CALM` 3.0 s, `LAVA_WARN` 1.5 s, `LAVA_HOT` 2.0 s, `LAVA_FIRST` 6, `LAVA_STEP` 2,
`LAVA_MAX` 16 mats, grid `LAVA_COLS` 8 x `LAVA_ROWS` 4. The pattern is drawn from the sim's seeded random
generator when the blinking starts (`Sim.lava_cells`), so server and clients see the same mats.

## 3. Bounce House

```
................C...............
..3.......#.......e.....6....E..
............A..##..a............
...............##....8..........
..1.......7....##............2..
............b..##..B............
..D..................#.......4..
........5....d..P...............
```
(`A`, `B`, `D`, `E` trampolines, `a`, `b`, `d`, `e` their landing spots.)

**Twist.** A wall of cushions splits the room; the only ways round are the two narrow gaps at the top and
bottom, one blocked by the chest and one by the present. Four trampolines are the shortcuts: step on one and
it flings you through the air to its painted landing spot (0.75 s). In the air nothing can hit you and you
can do nothing; your yo-yos snap back into your hand. Whoever stands where you come down is squashed: a
kill for you.

**Why it is fun.** A trampoline is an escape, an ambush and a gamble in one. It saves you from a yo-yo that
is about to connect, but everybody knows where and when you land, so a yo-yo can already lie there (you die
on arrival) or a player waits to throw. The squash turns that around: standing on a landing spot to camp it
is the most dangerous place in the room. A and B cross the wall in opposite directions; D and E fire from
the far corners into the two gaps, where the fights over the wall happen.

**Counterplay.** Do not stand on painted spots. Punish a landing: the jumper arrives with the yo-yo in hand
but needs a moment to charge. A jump is 0.75 s of doing nothing, and the squash circle (1.4 m) is small
enough to side-step if you watch the shadow.

**Bots.** They treat trampolines as floor and so jump now and then, like a curious player. They steer away
from a trampoline (and do not dash near it) when its landing spot is outside the zone or a deadly yo-yo lies
on it. Trampolines never lie in a final zone area.

**Numbers:** `PAD_RADIUS` 0.95 m, `AIR_TIME` 0.75 s, `AIR_HEIGHT` 3.2 m (view only), `STOMP_RADIUS` 1.4 m,
pads and landing spots in `PADS`.

## 4. Magnet Lab

```
............7...................
..3............##......P.....6..
................................
..........NN...#....SS..........
..1.......NN...#....SS.......2..
................................
..5.....C......##............4..
...................8............
```
(`N` / `S` the two magnets, `$` in the next sketch the pig.)

**Twist.** Two big horseshoe magnets stand left and right of the centre. One pulls yo-yos, the other pushes
them away; every 8 s they swap (the last second of each turn both are off and blink). Within 6 m a magnet
bends the flight of a thrown yo-yo: towards the red one, away from the blue one. A yo-yo that lies on the
floor creeps the same way, still deadly. Players are not metal and feel nothing.

**Why it is fun.** Hardly a throw is a straight line here, and that is a skill, not noise: the aim line shows the
real curve, so you can learn to throw round the centre wall and round the blocks, hit somebody behind cover,
or slingshot a yo-yo past the red magnet. The pulling magnet swallows careless throws (the yo-yo sticks to
it and has to be called back), the pushing one is a shield you can stand behind. The swap every 8 s turns
the safe side into the dangerous one. A lying yo-yo that slowly creeps towards a magnet is a slow moving
mine that both players have to keep an eye on.

**Counterplay.** Watch the colours and stand behind the pushing magnet. Throw short: a short flight bends
little. During the blink both magnets are off and throws fly straight.

**Bots.** Nothing here kills, so no avoidance. They aim straight and are therefore a bit worse on this map,
which is fine for a map about aiming.

**Numbers:** `MAGNET_RADIUS` 6.0 m, `MAGNET_TURN` 300 degrees/s at the magnet, falling linearly to 0 at the
radius, `MAGNET_DRIFT` 2.5 m/s (same fall-off), `MAGNET_PERIOD` 8.0 s, `MAGNET_OFF` 1.0 s.

## 5. Piggy Bank

```
....................8...........
..3.............C............6..
..........##........##..........
...............$$...............
..1............$$............2..
..........##........##..........
..5.............P............4..
............7...................
```

**Twist.** A big piggy bank stands in the open centre. Every 5 s a coin appears on its back (at most 3).
A thrown yo-yo that touches the pig shakes them all out for the thrower. They are paid with the round's
coins ("piggy bank" in the coin line), also if the thrower dies afterwards.

**Why it is fun.** It gives the shop economy a place on the map. Coins buy modifiers, so the pig is worth a
detour, but hitting it means a yo-yo that is out and not defending you, in the one place with no cover that
everybody watches. Waiting makes the pot bigger and the race for it sharper: with three coins on its back
somebody will throw. The final zone always ends in a corner, never on the pig, so late coins mean leaving
the zone on purpose with the death timer running. The player who is behind can catch up here; the leader
has to decide whether to guard the pig or the zone.

**Counterplay.** Punish the throw: whoever just hit the pig has no yo-yo in hand. Or deny it: one coin
taken early is two coins the others do not get later.

**Bots.** With a yo-yo in hand, the pig holding coins and in range, and no enemy close, a bot throws at the
pig. Otherwise the pig is just a block for them.

**Numbers:** `PIG_FILL` 5.0 s per coin, `PIG_MAX` 3 coins, pig 2 x 2 m. For comparison: a round pays 3
coins to everybody and 2 to the survivor (`Economy`).

## For the implementer

What is built on `feature/new-maps`: the design above, `MapDef`, the rules in `Sim`, bot behaviour, the look,
and the minimal plumbing (`Config.map`, saved and sent like `target_score`; `Sim.map_id`; a "Map" selector on
the values page of the Training menu, which Play uses too until the lobby has its own picker: remove that
caption and decide whether Training keeps its own selector when the lobby picker exists). What is NOT
built: tests, sabotage entries, the lobby picker, "Random", the protocol version bump, the entry in
`AGENTS.md`. The look was checked on still pictures only (rendered in the `godot-render` container that
`tools/render-preview.sh` uses, with a scratch script that is not in the repository): every map builds and
reads well in a still; motion, timing and the feel on a phone are unchecked. Existing suites: `sim`, `view`
and `net` were run and pass with these changes.

### How the map id should travel

- `Config.map` (0..`Config.MAP_COUNT` - 1) is in `to_dict` / `from_dict` (clamped; not a tuning value, `reset`
  leaves it). `main._make_play_cfg` copies it from the saved config, so `LocalHost` gets it with the fixed
  Play values and joiners get it in `T_WELCOME` (the config dictionary), where `ClientCore` builds its sims
  from it. Nothing else has to be sent.
- **Bump `NetProto.VERSION`**: an older client ignores the key and simulates map 0, and the snapshot has new
  fields. (Another branch bumps 7 -> 8 as well: whichever merges second takes the next number.)
- `Sim.map_id` is state (in the snapshot). `Sim.set_map(id)` switches the map of a running sim (layout, chest,
  twist state); `load_state` rebuilds the layout when a snapshot carries another map, and `ArenaView.render`
  rebuilds the playroom when the drawn sim's `map_id` changes. So a map change between rounds already works
  down to the view.
- Lobby: a row "Map" in the mode card (host and Solo), the six names from `MapDef.NAMES` plus "Random". It
  must stay compact (`test_lobby_fits`): one cycling button "Map: Lava Mats" is enough.
- "Random" is not built. Proposal, matching the rotation decided in `docs/PLAN.md` ("Maps and map rotation"):
  `Config.map = -1` means rotation; `Sim.start_match` shuffles the map ids with the sim's `rng` into a state
  array and `_start_round` calls `set_map` with the next one (reshuffle when empty). `from_dict` must then
  accept -1, and `Sim._init` must map -1 to some map for free play.

### What must be tested

For every map (loop over `Config.MAP_COUNT`), geometry like `_train_tests`:

- Obstacles lie fully inside the arena and do not overlap each other, the chest's start or the present.
- Eight spawn points; each at least player radius + `SPAWN_NOISE` away from every block, the chest, the
  present, and from each other; not on a belt, a trampoline or a landing spot.
- Four zone areas, each `ARENA_SIZE / 4`, inside the arena, with no block, chest start, present, belt,
  trampoline (pad circle) in them. Lava Mats: each zone area is exactly one mat pair. Piggy Bank: the pig is
  in none of them.
- A sim built for the map has the map's statics; `set_map` and `load_state` of another map's snapshot
  rebuild them; map 0 is unchanged (all existing tests pass with `Config.map` 0).
- `Config.map` survives `to_dict` / `from_dict`, garbage becomes 0, `reset` leaves it.

State and determinism, per map: two sims with the same seed and inputs stay identical for 20+ s with bots;
`save_state` -> `var_to_bytes` -> `load_state` into a fresh sim of the same config gives the same next ticks
(mind `map_t`, `lava_cells`, `lava_wave`, `pig_coins`, `pig_t`, `SimPlayer.air_*`, `MatchMode.bonus`); in the
`test_net` rig client and server agree on those fields (the twist clock runs with the sim, unlike the train
there is no world clock to diverge, but check it).

Core effect, per twist (each is a candidate for a sabotage entry):

- **Assembly Line:** a standing player, the chest and a lying yo-yo on a belt move by `BELT_SPEED * dt` per
  tick in the belt's direction; off the belt nothing moves; during `BELT_STOP` nothing moves; after it the
  direction is reversed; the corner pieces turn the flow (an idle player placed at the start of the top belt
  ends up beyond the end of the bottom belt); a wall stops a carried player; a carried yo-yo kills.
- **Lava Mats:** no marked mats during the calm; `LAVA_FIRST` mats at the first warning, `LAVA_STEP` more per
  wave, never more than `LAVA_MAX`; never both mats of a pair (many seeds); a player on a blinking mat lives,
  on a burning one dies with `cause: "lava"` and no kill credit; an airborne player does not exist on this
  map, a player on a safe mat lives; the mats are cleared after the wave; `_respawn` avoids marked mats;
  a new round resets clock, wave count and mats.
- **Bounce House:** a player whose centre is inside a pad is launched (event `launch`), yo-yos are in hand,
  lands on the pad's spot after `AIR_TIME` (event `land`); in the air: input does nothing, a yo-yo, shard,
  wire and explosion do not kill, other players are not pushed; a player within `STOMP_RADIUS` of the landing
  dies with kill credit for the jumper (and coins in a match); one just outside lives; landing next to the
  chest pushes it or the player out of it (no overlap); a death in the air (zone) clears `air_t`.
- **Magnet Lab:** a throw past the pulling magnet ends closer to it than the straight line, past the pushing
  one farther; outside `MAGNET_RADIUS` and during `MAGNET_OFF` it flies straight; after `MAGNET_PERIOD` the
  two magnets have swapped; a lying yo-yo creeps towards / away and kills on the way; the string follows the
  bend (pins) and the retract comes back along it; `aim_path` equals the real flight of an unsteered throw
  (end points within a head radius); maps without magnets keep the two-point `aim_path`.
- **Piggy Bank:** coins grow by one per `PIG_FILL` up to `PIG_MAX`; a thrown yo-yo touching the pig empties
  it (event `pig` with the count) and, in a match, adds to `MatchMode.bonus` of the thrower; `coin_parts`
  has `bonus`, `award_coins` pays it, `MatchOverlay.coin_text` names it; a hit on an empty pig gives nothing;
  a lying or retracting yo-yo does not collect; a pierced yo-yo flying through the pig collects; in free
  play nothing is paid; a new round empties the pig and the bonus.

Bots, per map: four bots in free play (phase OFF) for 60 s and a full bot match round with the zone, several
seeds. Deaths caused by the map (`cause: "lava"`; on Bounce House zone deaths and deaths within a few ticks of
a `land`) must stay rare compared to yo-yo kills. Single checks: a bot on a blinking mat reaches a safe one
before it burns; a bot next to a trampoline whose landing spot is outside the zone does not step on it; a bot
alone with a full pig throws at it.

View (`tests/test_view.gd`): `Playroom.build` works for every map without script errors, `update` runs for
some frames in every twist phase, and `ArenaView` rebuilds the playroom when `map_id` changes.

### Things to try on the phone

Belt speed against walking speed; whether the blinking mats read early enough on a small screen; whether a
jumping figure and its landing are readable; whether the bent aim line is clear; whether the pig's coins are
noticed at all without UI. Performance with the lava overlays and the belt arrows (both are a handful of
draw calls, but unmeasured).
