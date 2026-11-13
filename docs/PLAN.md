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

1. **Tripwire** (Stolperdraht): the string stays on the ground as a wire when a retract starts; enemies touching it stumble (level 3: the wire is lethal).
2. **Big head** (Dicker Brocken): the yo-yo head is much bigger, without slowdown.
3. **Elastic** (Gummiband): faster pull, and the player is flung onward after catching the head; from level 2 the body is lethal while pulling and flung.
4. **Extra dash** (Extra-Dash): more dash charges, shorter cooldown, longer dash at level 3.
5. **Bounce** (Abpraller): the flying head reflects off walls and obstacles, gaining distance with every bounce.
6. **Arc return** (Bogenwurf): the retract comes home on a curve (side chosen with the move stick); level 3 circles the player first.
7. **Pierce** (Durchschlag): the head passes through obstacle blocks (retract and crate from level 2); level 3 knocks enemy heads away in duels.
8. **Shards** (Splitter): lethal shards fly out from the head when a retract starts; at level 3 they bounce once.
9. **Warhead** (Sprengkopf): the head explodes where it lands; from level 2 also where a retract starts.
10. **Twin** (Zwilling): 2 / 3 / 5 yo-yos, controls see section 3.

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
  - Evaluate the netfox addon for prediction and rollback before building something custom.
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

Finish and tune the M1 prototype on the phone.
