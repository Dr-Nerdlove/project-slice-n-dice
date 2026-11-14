# Project Plan: Yo-Yo Arena Brawler (working title)

This document is the binding basis for implementation. It collects all decisions made by the project owner. Anyone continuing the work needs no prior knowledge from earlier conversations.

## 1. Context and way of working

- **What:** A top-down arena brawler for Android with online multiplayer for 2-8 players.
- **Inspired by the genre only:** Fast rounds, one hit kills, party feel. Name, characters, graphics, levels and sound must be entirely original. No existing game is being rebuilt.
- **Project owner:** Has little experience with game engines. The AI assistants build most of it; the owner tests on the device and sets the direction. The owner works alone with AI assistants; a partner may join.
- **Language:** Communication in German.
- **Priorities in this order:** smooth multiplayer, clear skill expression, then content and looks.
- **Goal:** First an MVP for friends (APK distributed directly), then polish, possibly a Play Store release later.
- **Repository:** Dr-Nerdlove/project-slice-n-dice (working title of the repo: "Slice n Dice"). The Godot project lives in `game/`. Development happens on Linux, with Godot 4.7.2.

## 2. Core gameplay

- **Perspective:** Top-down, high-quality 3D presentation.
- **Round:** 20-40 seconds, last man standing, one hit kills.
- **Match:** Points for placement and kills. The shop opens between rounds. The first to reach the target score wins. Target match length 8-12 minutes.
- **Player count:** 2-8.
- **Modes:** Free-for-all up to 8 players, and teams (2v2, 3v3, 4v4). Arena size scales with the player count.
- **Controls** (decided by the owner on 2026-11-13): Two virtual sticks (left moves, right aims and throws) plus controller support. Holding the right stick charges the throw: the longer the hold, the further the throw, and a visible aim line shows direction and landing distance. Releasing throws. While the yo-yo is out, a short tap on the right stick retracts it, and holding the right stick pulls the character to the yo-yo.
- **Theme and name:** Still open. Placeholder characters are used until decided.

### Playroom arena and the toy train

The prototype arena is a playroom. A toy train runs a closed loop around the middle of the arena and is a moving hazard (rules in `game/sim/sim.gd`, `_step_train`):

- The locomotive and two cars follow the rails at a constant speed. Each car is a circle for the game.
- A car runs over any living player whose centre is closer than the car radius plus a forgiving share of the player radius. That counts as a death for the victim and a kill for nobody (kill event with `killer: -1` and `cause: "train"`).
- A car shoves the crate completely out of its way; the train itself never leaves its track. Players are not pushed, only killed.
- Yo-yo heads, strings, wires and shards pass over the train unharmed. Making yo-yos interact with the train (blocking, riding or derailing it) is an open idea, not decided.
- A player never respawns inside a car's hit distance; bots steer away from the cars and do not dash towards them.
- Numbers: the track and the car size live in `TrainTrack` (`game/sim/train_track.gd`), the speed in `Config.train_speed` (default 5 m/s, 0 = no train, a slider in the tuning menu), the hit share in `Config.TRAIN_HIT_SHARE`. The rails keep a car radius clear of walls and obstacles and all spawn points lie farther from the rails than the hit distance plus the spawn noise (tests check both).

## 3. The core weapon: the yo-yo

### States

| State | Behaviour |
|---|---|
| Ready | Yo-yo in hand, throw possible. |
| Charging | Right stick held. The aim line shows direction and landing distance; the longer the hold, the further the throw. |
| Flight | After release, flies in the aimed direction to the charged distance. Lethal. A yo-yo that hits a wall simply stops and lies there. |
| Out | Stays where it landed and keeps spinning. Lethal, blocks space. No new throw is possible while it is out. |
| Retract | A short tap on the right stick pulls it back. Lethal on the way back, interacts with the environment (dragging objects along, triggering switches, hitting destructibles). Walls and obstacles stop it: the head then lies there again (Out) and can be tapped or pulled to again. |
| Pull | Holding the right stick while the yo-yo is out pulls the character to the yo-yo. This works wherever the yo-yo lies, not only when it is anchored in terrain. |

### Proposals by the planner, not yet explicitly confirmed by the owner

- **Defence:** When two yo-yos meet, they bounce off each other.
- **String:** Harmless in the base state; only modifiers make it dangerous.
- **Dash:** A short evasive step with a cooldown as a second movement option. The player has dash charges (tuning menu value, modifiers can add more); charges refill one at a time, each taking the cooldown.

### Several yo-yos (twin modifier)

A player has a list of yo-yos; each has its own state, charging and pulling belong to the player. Controls (decided by the owner on 2026-11-13):

- While at least one yo-yo is in hand: holding the right stick charges, releasing throws the next one, as with one yo-yo.
- A short tap (shorter than the tap threshold and without stick deflection) while at least one yo-yo is out retracts all yo-yos that are out, also when another one is still in hand. With a yo-yo in hand, an aimed quick flick still throws.
- When all yo-yos are out, holding pulls the player to the yo-yo that lies most in the direction the player is moving (without move input: the nearest). The target is fixed when the pull starts; catching it puts that yo-yo back in hand and ends the pull.
- With a single yo-yo the behaviour is exactly as described in the table above.

Make these three points playable in milestone 1 and have the owner confirm them.

## 4. Modifiers

Modifiers change how the game is played, not just numbers. They act on three areas:

| Category | Examples |
|---|---|
| Yo-yo head | Splits on retract, magnetic, bigger but slower, explodes at the end point |
| Behaviour | Bounces off walls, flies in a curve, second yo-yo, retract faster than throw |
| String | Longer, cuts enemies, elastic (flings the player further), stays behind as a tripwire |

Rules:

- One hit always kills, even fully upgraded players. A player's own effects never hurt themselves.
- Fixed number of slots per player (proposal: five). This caps maximum strength and lets trailing players catch up.
- Modifiers must be visible on the yo-yo or the string so that opponents can read them.
- Goal for the MVP: 10-15 modifiers.

Decisions of 2026-11-13:

- **Modifiers are pure upsides**, there are no drawbacks.
- **Levels by copies:** buying the same modifier 3 times makes it level 2, 6 times level 3 (very hard to reach). One modifier occupies one slot regardless of its copies.
- **Higher levels must be dramatically stronger**, so that a player really feels that collecting was worth it.
- **The shop will have rerolls for coins**, so skilled players reach their builds more often.
- **Sandbox:** the prototype has a menu page "Modifikatoren" where the owner sets the level (0-3) of every modifier for the player and, separately, for all bots. Prices (three tiers, placeholder values) exist in the data but are not used yet.

First batch of ten modifiers. All definitions, German texts and every number live in `game/sim/mods.gd`.

1. **Tripwire** (Stolperdraht): the string stays on the ground as a wire when a retract or a pull starts, along the current string path; enemies touching it stumble (level 3: the wire is lethal).
2. **Big head** (Dicker Brocken): the yo-yo head is much bigger, without slowdown.
3. **Elastic** (Gummiband): faster pull, and the player is flung onward after catching the head; from level 2 the body is lethal while pulling and flung.
4. **Extra dash** (Extra-Dash): more dash charges, shorter cooldown, longer dash at level 3.
5. **Bounce** (Abpraller): the flying head reflects off walls and obstacles (1 / 3 / 5 times), gaining flight distance with every bounce (+1.5 / +3 / +5 m).
6. **Arc** (Bogenwurf): the throw flies on a curve (side chosen with the move stick, default left; a throw still lands at the aimed point and the aim line shows the curve) and the string lies on that curve; level 2 bulges more and retracts 1.3x faster; level 3 adds one lethal circle around the player on the way back (see below).
7. **Pierce** (Durchschlag): the head passes through obstacle blocks (retract and crate from level 2); level 3 knocks enemy heads away in duels.
8. **Shards** (Splitter): lethal shards fly out from the head when a retract starts; at level 3 they bounce once.
9. **Warhead** (Sprengkopf): the head explodes where it lands; from level 2 also where a retract starts.
10. **Twin** (Zwilling): always exactly 2 yo-yos, controls see section 3. Level 2 ("Kreuzfeuer"): when retracting with both out, the heads first fly to the midpoint between them (lethal) and return together. Level 3: retract 1.5x faster, and an undeflected hold pulls to a lying yo-yo even while the other one is still in hand.

### Synergies

Modifiers influence each other. A synergy is a pair of modifiers that are both on; it is defined in the `SYNERGIES` table in `game/sim/mods.gd` (ids, German one-line text, numbers) and shown in the menu under "Aktive Kombinationen". Everything else combines per head without special rules (e.g. Bogenwurf + Splitter).

- Shards + Warhead: every shard explodes where it ends (radius 0.8 / 1.2 / 1.6 by warhead level).
- Shards + Pierce: shards pass through obstacle blocks (and the crate from pierce level 2).
- Shards + Bounce: shards bounce as often as the bounce level allows, in addition to the single bounce of Shards level 3.
- Shards + Big head: shard radius scales with the big-head factor.
- Big head + Warhead: explosion radius x1.15 / x1.3 / x1.5 by big-head level (also for shard explosions).
- Big head + Tripwire: the wire is wider (trigger half-width scales with the big-head factor).

### The string is the flight path

Rule: **the string always lies exactly on the path the yo-yo flew, and on a retract the yo-yo (and on a pull the player) always follows the string.** The string is a polyline: player, the path points ("pins", in order from the player outwards), head. Pins are the bounce points and, for a curved throw (Bogenwurf), a point about every 0.7 m flown along the curve. The path is real:

- Retract: the head travels back through the pins (each is removed as it passes), then to the player; lethal all the way. Pull: the player travels along the path through the pins to the head.
- String length is the path length. A head that is out: variant A (drag) drags the head along the path towards its nearest pin when the path gets too long; B (leash) limits how far the player may move away from the first pin; C (rigid) drops the pins as soon as the player moves.
- A step that reaches a pin carries its remaining distance on to the next segment in the same tick, so the speed along the path is constant.
- Pins are never removed because of a free line of sight (no rope physics). Pierce creates no pins. The Kreuzfeuer meeting flight is the one deliberate exception: the heads leave the string (dropped when the retract starts), meet at the midpoint and then return straight to the player.
- The tripwire follows the same polyline; trigger tests run against every segment.

### Bogenwurf level 3: the circle

On a retract the head first returns along the string until its straight distance to the player is at most the circle radius (at once if it already is), then flies one full 360 degree circle (about 1.1 s) around the player's current position (the centre follows the player), lethal and passing through blocks and the crate, then continues home along what is left of the string (pins passed before the circle are consumed). Radius: at most 4 m and at most the player's distance to the nearest outer wall minus the head radius, never below 1.5 m (only in that floor case the head may be clamped to the arena and slide along the wall). All numbers are in `game/sim/mods.gd`.

### Value export

The tuning menu has a "Werte kopieren" button. It copies one compact text block with every tuning value (config keys, values changed from the default marked with `*`), the out variant, the bot mode and the modifier levels for the player and the bots to the clipboard and shows it in a read-only text box, so it can be pasted to a developer. "Zurücksetzen" resets only the page it is on (values or modifier levels).

## 5. Shop, coins and catching up

- **System:** Shop with coins, saving and interest.
- **Income:** A base amount per round, plus kills, placement and bonuses.
- **Shop phase:** 15-20 seconds, all players at the same time, four random offers, reroll for coins, upgrades can be levelled up.
- **Interest:** Bonus on saved coins, capped.
- **Catching up (explicitly demanded by the owner):**
  - Bounty on the leaders: visibly marked, grows with their lead.
  - Bonuses for skill plays: double kill, bounce hit, kill while pulling in, ending an opponent's streak.
- **Hard requirement:** The game must not snowball. A good play by a trailing player must noticeably bring them back into the match.
- **Known tension:** Interest tends to reward the leader. Bounty and skill bonuses must therefore pay clearly more than interest. Keep all values in one central, easily changed configuration.

## 6. Technology

- **Engine:** Godot 4.7.2, GDScript.
- **View and simulation separated:** The presentation is 3D, but the game logic runs on a flat 2D plane. From milestone 1 on, the simulation runs on a fixed 60 Hz tick, in pure code separated from the 3D view, so the feel does not change when the netcode arrives. Own movement and collision logic instead of the physics engine, so that steps can be re-simulated on the client.
- **Network model:** Authoritative server. The same server code runs headless on the server and embedded in the app for LAN rounds.
- **Netcode:**
  - Client prediction for the player's own character and yo-yo, corrected by the server.
  - Interpolation for other players.
  - Lag compensation for hits.
  - UDP (ENet), tick rate 30-60 Hz.
  - Evaluate the netfox addon for prediction and rollback before building something custom. **Decision (first
    experiment):** custom prediction by re-simulating the pure `Sim`, without netfox. netfox synchronises
    properties of nodes, while this game's whole state lives in one pure-code simulation without nodes; here
    prediction is just "load the server state, step the same code again with the unacknowledged inputs". netfox
    was **not tried in practice**; if the custom code turns out to be too much work, it can still be evaluated.
- **Biggest technical risk:** Pulling to the yo-yo must feel instant even at 60 ms ping. Test early with artificial lag and packet loss.
- **Graphics:** Placeholders and free asset packs until the MVP, own high-quality models in the polish phase. Mobile renderer; target devices are ordinary Android phones.
- **Readability:** With 8 players on a phone screen it gets crowded. Check in milestone 2 and limit FFA to 6 if necessary.

## 7. Hosting

- **Available:** A Proxmox server at the owner's home on the LAN, already running public applications. Domain via Cloudflare.
- **For the MVP:** A container or VM on the Proxmox with the headless server, UDP port forwarding on the router.
- **Constraints:**
  - The Cloudflare proxy and the free tunnel do not forward UDP. The game server needs a DNS record without proxy pointing directly at the home IP.
  - The home IP is therefore visible to other players. Acceptable among friends.
  - A public IPv4 address is needed. Whether the connection uses DS-Lite has not been checked yet.
- **Before a store release:** Put a small VPS in front or move to one. The server code stays the same.
- **Important:** Changes to router, DNS or Proxmox only after consulting the owner.

## 8. Lobby and matchmaking

- **MVP:** Private rooms with a room code, plus a LAN mode.
- **Later:** Public matchmaking. The architecture must not rule it out, but it is not built for the MVP.

## 9. Milestones

Every milestone ends with a build that the owner tests on the phone. Work continues only after the owner's approval.

### M1: Game feel offline
- Set up the Godot project and Git repository. The Android export is set up from the start; the owner tests on the phone via APK.
- The simulation runs on a fixed 60 Hz tick from the start, in pure code separated from the 3D view.
- A tuning menu with sliders in the prototype, so the owner can adjust values while playing.
- One arena with walls and a destructible or movable object.
- Placeholder character with movement and dash.
- Yo-yo with all six states (Ready, Charging, Flight, Out, Retract, Pull), including pulling to the yo-yo and two yo-yos bouncing off each other. The prototype offers three switchable variants for what the out yo-yo does when the player walks away (see open points).
- Touch controls with two sticks and controller support.
- Simple practice enemies.
- **Done when:** The owner says that throwing, charging, retracting and pulling feel good on the phone.

### M2: Netcode
- Separate server and client; the fixed-tick simulation from M1 is reused unchanged.
- Build the headless server and run it on the Proxmox.
- First 2, then 8 players.
- Test tool for artificial lag and packet loss.
- **Done when:** A match with 100 ms lag and 2 % packet loss plays smoothly and fairly.

**First experiment (done, to be played on phones):**
- `Sim.save_state()` / `load_state()` snapshot all mutable state by reflection (`game/sim/state_io.gd`).
- `game/net/`: `ServerCore` (authoritative sim, 60 Hz, 30 Hz snapshots, per-player input buffer), `ClientCore` (prediction
  of the own player and yo-yo by re-simulating, correction measure, ping), a lag/loss tool (`LagEndpoint`), an
  ENet transport and an in-memory transport for tests. Headless server: `godot --headless --path game -- --server`.
- Menu page "Online": server address, connect, artificial one-way delay (0-300 ms) and packet loss (0-20 %).
- What it does **not** do yet: lag compensation for hits (see below), hosting on the internet (the home server,
  router and DNS are untouched), 8 players (the sim has 4 slots), reconnecting, a lobby.
- The owner's question for the test: does pulling to the yo-yo feel instant at 60-100 ms (set 30-50 ms per direction
  in the menu, the ping shown in the HUD is the round trip)?

**Display of the other players (second experiment, to be played on phones):**
- Own player: prediction, unchanged. Other players: **snapshot interpolation**. The first experiment drew them
  from the predicted sim (extrapolated with their last input), so every change of their input made them snap, and
  a dash looked like a teleport. Now `ClientCore` buffers the received snapshots and draws the others (body, yo-yo
  heads, strings, aim line) from a separate display `Sim` loaded with the later of two snapshots around a render
  time, with its `prev_*` positions taken from the earlier one; the view lerps between them (`ArenaView.set_others`).
  Shared objects (crate, box) come from the predicted sim; wires and shards from the side of their owner (own:
  predicted, others': interpolated). The predicted sim still simulates the others for collisions, only the display
  source changed. Kill and hit effects are unchanged (they still come from the predicted sim).
- The render time runs `INTERP_DELAY` = 4 ticks (2 snapshot intervals, 67 ms) behind the newest snapshot. The delay
  grows (up to +8 ticks) when snapshots arrive late or are lost and shrinks back by 0.3 ticks per second. The render
  clock runs 0.75x to 1.25x to reach its target and only jumps over a stall longer than 30 ticks. A client clock that
  is a little fast or slow is absorbed by a slowly sinking server-time estimate. If the buffer runs dry the last
  state is held (no extrapolation); a move bigger than 6 m between two snapshots (respawn) is not interpolated.
- Menu page "Online": switch "Gegner glätten" (default on) to compare with the old display; the HUD line shows
  how far in the past the others are drawn ("Gegner 67 ms zurück").
- One-shot inputs: the dash is an edge event, so an input that is repeated (the client extrapolating the others, the
  server on an input underrun) is repeated without the dash (`SimInput.repeated()`). Before, a repeated dash could
  spend extra dash charges (only with the Extra-Dash modifier; with one charge the 1.2 s cooldown hid it).
  The aim release is an edge in the sim (`held_prev`), so repeating `aim_held` is harmless.
- **Consequence: the victim was killed before the head visibly arrived** (owner's test on two phones). The others
  were drawn about 67 ms plus half the ping in the past, while the own player is predicted (ahead of the server) and
  the server decides hits on the present. This is fixed for yo-yo heads and shards by the next section; what is left
  of lag compensation (the thrower aiming at what he sees) is still open.
- Measured on the loopback with the fake clock (player B walks with direction changes, dashes and throws, A watches;
  largest single-tick jump of B's picture vs. B's largest true step of 0.42 m): old display 1.21 m at 0 ms, 2.31 m
  at 20 ms, 2.30 m at 50 ms per direction (2.9x to 5.5x), new display 0.42 m at all of them (1.0x), also with 2 %
  loss; position jitter 0.04 to 0.10 before, 0.010 after (the true path has 0.0104). The loopback has no jitter;
  the adaptive delay is tested separately.

**Heads and shards of the others are drawn in the present (third experiment, to be played on phones):**
- Bodies stay interpolated (smooth, in the past). A yo-yo head of another player that is **not in the hand** in the
  predicted sim (FLIGHT, OUT, RETRACT) is drawn from the predicted sim (`client.sim`), and so are the shards of the
  others: a thrown head needs no further input to fly, so the prediction already has it where the server will have it
  when the victim's own inputs arrive there. Heads in the hand stay with the interpolated body. Done in
  `ClientCore._apply_predicted` (per frame, into `display_sim`; the view is unchanged). `predict_heads` switches it
  off; "Gegner glätten" off still draws everything raw from the predicted sim, as before.
- **How reliable the prediction is, per head state** (the others' input is their last known one, repeated):
  FLIGHT is exact (straight or curved path, bounces, speed are fixed at the throw); wrong only if a tap queued during
  flight (`queued_retract`) has not reached the client yet, or the thrower is hit/stunned (his heads keep flying, still
  fine). OUT is exact while the thrower stands still; if he walks, the head follows him by the string variant
  (drag, leash, rigid) using his repeated last input, wrong as soon as he changes direction; a tap or hold that has not
  reached the client yet (retract, pull) is also unknown. RETRACT homes to the thrower's position, so it follows his
  predicted body (wrong as much as that is) and a retract started by a tap the client has not seen is predicted as OUT
  for up to one ping. Shards are exact after they exist, but they only exist once the retract that spawns them is
  known, so a shard can appear late (it is drawn where it then is). The body that kills (own player) is predicted
  by the client itself.
- **No pops:** every displayed head has a visual offset (old drawn position minus new source position) that slides to
  zero over `HEAD_CATCHUP_TICKS` = 6 ticks (100 ms), linearly. It is set when the source changes (thrown: hand ->
  predicted path; back in the hand: predicted path -> hand, the head is drawn as a returning head while it slides) and
  when a snapshot corrects a predicted head (new predicted position differs from the old one). So the drawn head is
  never further from its true predicted place than the offset. An offset bigger than `HEAD_MAX_OFFSET` = 6 m
  (teleport) is dropped at once, and the offset of a player who is dead (respawn) does not exist. The string is drawn by
  the view from the interpolated body through the pins (taken from the predicted head, so bends and bounce points are
  right) to the drawn head: it stays continuous, only its first piece is longer for a moment because the body is
  further back than the head. Shards slide in without an offset (they appear where they are).
- Measured on the loopback with the fake clock (player A stands, B throws at A; "gap" = on A's screen the distance
  between the drawn head or shard and A, minus the hit distance, at the tick on which A's client learns of its death /
  at the server's kill tick mapped to A's time; 0 = touching, positive = the killer has not arrived yet). Three
  scenarios (flight through A, retracting head through A, shard at A), 0 / 20 / 50 ms per direction, 0 and 2 % loss:
  | gap in m, learn / server | 0 ms | 20 ms | 50 ms |
  |---|---|---|---|
  | flight, before (old display, fixed buffer) | 2.6 | 4.0 | 5.2 |
  | flight, display fix only | -0.2 | 0.2 | 2.3 |
  | flight, display fix + small buffer | -0.2 | -0.2 | 0.7 (1.5 with 2 % loss) |
  | retract, before | 2.0 | 3.1 | 3.3 |
  | retract, display fix only | -0.2 | 0.1 | 2.6 |
  | retract, display fix + small buffer | -0.2 | -0.2 (0.1 with 2 % loss) | 1.1 |
  | shard, before | 1.7 | 2.2 | 2.2 |
  | shard, display fix only | -0.1 | -0.1 | -0.1 (2.2 at the server's kill) |
  | shard, display fix + small buffer | -0.1 | -0.1 | -0.5 (2.2 at the server's kill) |

  (2 % loss changes little with the redundant inputs; "before" at 2 % loss was 0.5 to 1 m worse.) The negative
  values are the killer drawn up to 0.2 m inside the victim. The rest at 50 ms is the catch-up slide of a head that is
  thrown less than a ping before it hits: it appears at the hand and has to cover the distance within 100 ms.
- **Remaining limit:** a dodge in the last moment reaches the server about half a ping later, so the server may still
  count a hit the victim did not see (and the victim may see a head touch him that the server missed: the prediction
  of his own body is ahead of the server, the head is predicted in the present, but his input is not there yet).
  Whether to favour the thrower (as now: the server decides on its present) or the victim (rewind, or give a dodge
  that was started a ping ago the benefit) is an open design decision. A shard whose retract the victim has not heard
  of yet cannot be seen coming at all. At 50 ms per direction the throw reaches the victim less than a ping before the
  hit, so the victim sees the head appear and sweep in with the catch-up offset, still about 2 m from touching when he
  dies.
- **Smaller server input buffer:** `ServerCore.JITTER_TICKS` (fixed 3 ticks = 50 ms) is gone. Each player has a
  target (`Slot.target`): it starts at `JITTER_START`, grows by one when the buffer runs dry (underrun) or 3 inputs
  arrive in one tick (burst), up to `JITTER_MAX` = 5; every growth doubles the quiet time needed before it shrinks by
  one (300 ticks, up to 3600), so a link that needs the larger buffer does not run dry again every few seconds; a
  buffer that never ran down to its target for 30 ticks is trimmed by one input (a dash in the dropped input is handed
  to the next one; the dropped input counts as used).
  Measured on the loopback (two clients duelling, 3000 client-ticks): the average time an input waits in the buffer
  (server ticks) was 2.0 at 0 and 20 ms, 2.6 at 50 ms, 1.6 at 100 ms / 2 % loss with the fixed buffer; now 0.0, 0.0,
  0.2 and 1.4. Corrections (a snapshot moved the own predicted position by more than 1 cm): 16 with the fixed buffer
  at every setting; now 16 at 0 and 20 ms, 24 at 50 ms, 18 at 100 ms / 2 % (over 12000 ticks the totals were equal
  within noise: 66 to 90 against 86 to 92 at 100 ms / 2 %, 96 against 86 at 50 ms). One client alone at 100 ms / 2 %:
  2 corrections of 0.10 m (one tick of input) in 1200 ticks while the buffer learns; the fixed buffer had none.
  Starting at 2 or 3 and shrinking was tried and is no better, because the shrink probes the link. At 100 ms / 2 %
  loss the waiting time is no better than before (the target grows with every loss); the gain is on links
  without loss. The loopback has no jitter beyond the 1-tick rounding of its fixed delays, so how the buffer behaves
  on a real jittery link is not tested: that is for the phone test.


### M3: Match loop
- Rounds, points, target score, winner screen.
- Shop phase with coins, interest, reroll and upgrading.
- Bounty and skill bonuses.
- 10-15 modifiers across all three categories.
- **Done when:** A complete match runs through and a trailing player can realistically catch up in test games.

### M4: Lobby (MVP)
- Room codes, team selection, FFA and team modes.
- LAN mode with embedded server.
- Reconnecting after a dropped connection.
- **Done when:** Friends install the APK and start a match without help.

### M5: Polish
- Decide theme and name.
- Own models, animations, more arenas, sound, effects.

### M6: Optional
- Matchmaking, accounts, VPS, data protection, store presence.

## 10. Open points

- Theme, characters and name of the game.
- What the out yo-yo does when the player walks away. The prototype offers three switchable variants: A: it stays and is dragged along once the string is taut; B: leash, the player cannot move beyond the string length; C: it moves rigidly with the player. The owner decides by playing.
- Confirmation of defence, harmless string and dash (see section 3).
- Number of modifier slots (proposal: five).
- Target score and exact point scoring.
- Check for a public IPv4 address on the home connection.
- Product language(s) of the game UI (the prototype menu is German for now).

## 11. Next step

Finish and tune the M1 prototype on the phone, and play the first netcode experiment (M2) on the LAN with 2-4 phones.
