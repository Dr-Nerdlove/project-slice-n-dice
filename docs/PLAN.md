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
- **Consequence, the next open point: lag compensation.** The others are now shown about 67 ms plus half the ping in
  the past, while the server still decides hits on the present positions. A player who aims at what he sees misses
  by that distance; the server would have to rewind the other players to what the shooter saw.
- Measured on the loopback with the fake clock (player B walks with direction changes, dashes and throws, A watches;
  largest single-tick jump of B's picture vs. B's largest true step of 0.42 m): old display 1.21 m at 0 ms, 2.31 m
  at 20 ms, 2.30 m at 50 ms per direction (2.9x to 5.5x), new display 0.42 m at all of them (1.0x), also with 2 %
  loss; position jitter 0.04 to 0.10 before, 0.010 after (the true path has 0.0104). The loopback has no jitter;
  the adaptive delay is tested separately.

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
