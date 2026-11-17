# Changelog

One section per release, newest first. The heading is `## MAJOR.MINOR.PATCH` (no `v`); the release workflow
(`.github/workflows/release.yml`) publishes the section of the tagged version as the release notes and fails if
there is none. Write it for testers, in plain words.

## 0.16.0

Draft, not released yet.

- **Friendlier wording**: the game no longer talks about killing or dying. Texts now say "knock out" and "KOs" (score line, coin breakdown, modifier cards and descriptions). The main menu's Play button no longer shows "Last Standing", because Play now has three modes.
- **Throw arrow instead of the aim line**: while you charge a throw, the exact flight path and landing mark are gone. A small arrow in your colour lies on the floor just outside the ring around your figure and points the way you will throw; the longer you charge, the slightly further out it sits. It does not tell you how far the yo-yo will fly.

## 0.15.0

Draft, not released yet. Players on different versions can no longer play together.

- **Teams mode**: pick "Teams" in the Match screen (the Mode card), then 2v2, 3v3 or 4v4. Two teams, Red and Blue, fight; you cannot hurt your own team, and when a round ends every member of the winning team scores a point. The floor ring under every figure shows its team colour. Playing together, each player sees both teams in the lobby and can press "Switch team"; the host can start only when the teams are even. Solo puts you on Red and fills both teams with bots.
- **Hot Potato mode**: pick "Hot Potato". One player carries a bomb with a fuse; hit someone to pass it on, and when the fuse runs out the carrier is out. The last one standing wins the round. The round result says who survived the bombs. The bomb carrier's markers (YOU tag, modifier icons) now sit above the bomb.
- **Mode choice**: "Free-for-all", "Teams" and "Hot Potato" are buttons in the Mode card. The points to win (10, 15 or 20) work in every mode. Games found on the Wi-Fi show their mode, e.g. "Teams 3v3". While you host or have joined a game, the mode, players and points cannot be changed; a joiner sees the host's settings.
- **Teams scoreboard**: between rounds the scoreboard has two columns, Red and Blue, with the team's points and its players.
- **Bigger figures in the lobby**: the figure in the Play lobby is about twice as big and still shown completely.

## 0.14.0

Easier to read in a match, and two fixes for how yo-yos and figures are drawn.

- **Yo-yo in the hand**: a yo-yo you hold is always drawn at normal size, so Big Chunk no longer hides your figure; it grows to its real size when thrown and shrinks back when caught. With Twin, one yo-yo is held in each hand, for every figure (the Snapping Dino's arms moved a little apart for this).
- **Markers above the figures**: at the start of a round everybody sees the modifiers the others bought (small icons over their heads), and your own figure gets a "YOU" tag with an arrow. A player outside the shrinking zone now gets a big red countdown number (3, 2, 1) above the head instead of the ring on the floor.
- **Play lobby**: the figure picture now shows every figure completely (the top of some was cut off); the camera
  is framed from the figure's real size and the shape of the picture.

## 0.13.0

Four more maps have a new floor plan, the same way Train Set and Assembly Line got one earlier. Every plan is
symmetrical, so no start is better than another, and nobody starts in sight of another player. Players on
different versions can no longer play together.

- **Piggy Bank**: the pig stands in an open square in the middle, inside a ring of shelves with an entrance in the
  middle of each side. From outside, the pig can only be hit through an entrance, so taking the coins means
  showing yourself. Two long walls make the ends of the room into aisles, and a short wall in each aisle splits
  it. Bots only throw at the pig when no shelf is in the way.
- **Magnet Lab**: each magnet stands in a broken square of short walls (open at the corners), so a straight throw
  into it is blocked and only a throw bent by the magnet gets round. A long middle wall with a door at each end
  splits the room in two, and a cross wall near each short side makes the two end rooms.
- **Bounce House**: three long walls divide the room into four strips side by side, each wall with only one walking
  door (top, bottom, top), so walking across is a long zigzag. Every strip has one trampoline that throws you over
  a wall into another strip, and bots take a trampoline when it saves them a long walk. Short walls inside the
  strips give cover.
- **Lava Mats**: a windmill of walls around a small courtyard in the middle, and a small room with a way out in
  every corner. The walls give cover, and a mat that is about to burn is still never more than a short walk from a
  safe one. Bots walk around the walls when they flee from the lava.

## 0.12.0

- **Assembly Line has a new floor plan**: two long walls divide the room into a left, a middle and a right part.
  The conveyor belt runs through an opening in each wall (the quick way into the next part), and there is a
  separate walking door at the far end. Short walls along the belt give cover and places to step off. (Players on
  different versions can no longer play together.)

## 0.11.0

- **Bots walk around walls** instead of pushing against them, and only throw at a player they can actually see
  (no wall in between).
- **Players start farther apart** at the beginning of every round.
- **Train Set has a new floor plan**: walls divide the room into corner rooms and side rooms that are connected
  along the toy train's rails, and the block in the middle has two walls that make a small yard. (Players on
  different versions can no longer play together.)


## 0.10.0

- **Five new maps**, each with its own twist (plus the old playroom, now called Train Set):
  - **Assembly Line**: conveyor belts carry players, the toy chest and yo-yos lying on the floor, and stop and
    reverse every few seconds.
  - **Lava Mats**: the floor is lava. More and more mats blink, then burn; stand on a burning one and you are out.
  - **Bounce House**: trampolines fling you across the arena; land on somebody to squash them.
  - **Magnet Lab**: two magnets bend flying yo-yos and pull or push lying ones, and swap roles.
  - **Piggy Bank**: the pig in the middle saves up coins; hit it with a yo-yo to take them all (paid at the end
    of the round).
- **The map changes between rounds** in every Play game (Solo and together): the maps come in a shuffled order,
  each map once before any repeats.
- **Training**: the "Map" selector on the values page picks the map for Training only; Play ignores it.
- Bots know about the maps (they run from burning mats, avoid trampolines and go for a full pig).
- Update all phones: this version changes the network protocol (protocol 9), so older versions cannot join.
  (The look and feel of the new maps is not checked on a phone yet.)

## 0.9.0

- **Choose your colour**: the Play lobby has a row of eight colours under the figures. Your colour is used for
  your yo-yo, its string, your aim line, a ring on the floor around your figure and your dots in the scoreboard,
  so the scoreboard now matches what you see in the arena. Every figure keeps its own toy colour (before, all
  figures of a player were tinted in the player's colour, e.g. always pink). No two players share a colour: if
  yours is taken, you get the next free one. (Not looked at on a real screen yet.)
- **A clearer shop**:
  - All three offer cards keep the same width; buying no longer makes the shop change size, and modifier names
    are no longer cut off.
  - New short texts for every modifier and level, so you can tell what a modifier does (e.g. Rubber Band: "Zip to
    your yo-yo faster and fly past it"); a card shows the text of the level you get by buying it ("EVEN bigger
    explosions").
  - The Lock button looks like a button now and turns yellow when an offer is locked.
  - Your modifiers in the bottom row show their name and, top right, what you get for selling them ("+4 ¢").
- Hosting and joining needs the same version on every phone (network protocol 8): update all phones.

## 0.8.0

- **2 to 8 players in Play**: the lobby has a new **Players** row (2 to 8). Solo is you plus bots up to that
  number; when you host, the game holds at most that many players and **Fill with bots** fills the free places up
  to it (a friend who joins takes a bot's place). Training stays at 4. (Not tried on a phone with 8 figures yet.)
- **The lobby fits on one screen**: no more scrolling in the Play lobby or in Settings, on any screen size. The
  lobby is now laid out in three columns. (Not looked at on a real screen yet.)
- **Fixed: tapping the lower part of the round result ended the match.** An invisible **Main menu** button sat
  there. Between rounds it is gone (the pause button still leads to the main menu); at the end of a match it is
  shown clearly.
- **Points to win as dots**: the round result and the end of the match show a row of empty dots per player, in
  groups of five, one per point needed; every round won fills one in the figure's colour, and the newest one pops.
  (Not looked at on a real screen yet.)
- **Clearer shop**: your 5 modifier places are shown at the top, empty at the start. Each modifier you have shows
  its icon, its level (I, II, III) and dots for the copies still needed for the next level. Offers are cards with
  an icon, a short description and what buying gives you (new, next level or one more dot).
- **Sell modifiers**: tap one of your modifiers, then **Sell**: you get half of what you paid for all its copies
  back (rounded down), and the place is free again.
- **Lock offers**: the lock on an offer keeps it when you reroll and into the next shop, so you can buy it later
  when you have more coins. Locking is free; buying it unlocks it.
- Players with an older version cannot join a game of this version.

## 0.7.0

- **Shop between rounds in Play**: after the round result, everybody shops at the same time for up to 20 seconds
  (it closes early when everybody has pressed **Done**). You get three random modifiers with their price (3, 5 or
  8 coins); **Reroll** (1 coin) shows three new ones. Buying the same modifier again adds a copy: 3 copies make
  level II, 6 make level III. You can hold up to 5 different modifiers; with all 5 taken, only the ones you have
  are offered. Your modifiers stay for the whole match and are gone in the next match. Unspent coins are kept.
  Bots shop too, in Solo and in Together. There is no shop after the deciding round. Training is unchanged (its
  modifier levels never reach Play). Players with an older version cannot join a game of this version.
  (Not looked at on a real screen yet.)
- **Coins in Play**: after every round everybody gets coins, shown as a yellow tag next to each name on the round
  result (what you have and what this round gave), with your own breakdown below the scoreboard. Every round
  gives 3, each kill 1, winning the round 2, being in last place 2, and each kill of the player in first place 1
  more. Deaths by the train, the zone or your own explosion give nobody anything. Coins are kept from round to
  round and start at zero in every match; they will pay for the shop, which comes next. (Not looked at on a real
  screen yet.)
- **Shrinking zone in Play**: every round, the whole arena is safe for the first 20 seconds. Then a bright line
  closes in from all sides over 30 seconds and stops on a small area (a quarter of the arena's width and height)
  that is chosen at random each round. Outside the line the floor is darker. Anyone whose middle is outside the
  line gets a red ring on the floor under their figure that fills over 3 seconds; when it is full, they are out
  (no point for anybody). Back inside, the ring empties again. Bots stay inside the line. Training has no zone.
  (Not looked at on a real screen yet.)
- **Touch control settings** (Settings > Touch controls): choose **Floating** sticks (they appear where your thumb
  lands, as before) or **Fixed** sticks, pick the **size** and **opacity** of the controls, and turn on **Swap
  sides** for left-handed play (move stick on the right, aim stick on the left, Dash button on the left).
  **Place controls** lets you drag the sticks (Fixed) and the Dash button to where you want them, then Save,
  Reset to default or Cancel. The settings are kept on your device and apply to Play and Training.

## 0.6.0

The game has a new name and a new start screen: **Spinback Rumble**.

- **New main menu** with **Play**, **Training** and **Settings**. The app starts here, over the blurred playroom.
- **Play** is the real game: it always uses the fixed standard values. Your tuned values and test modifiers never
  reach a Play game. In **Play** you choose your figure (with a live 3D preview) and then start **Solo vs bots** or
  play **Together** on the same Wi-Fi.
- **Local play moved** from the old tab "Lokal" to **Play > Together**. It works as before (host with a code, join
  from the list or by code), now in English, and the host's tuned values are no longer used: everybody plays with
  the standard values and no modifiers.
- **Training** keeps everything the prototype had: sliders, modifiers, bots, the Online page and the lag tool. Open
  it from the main menu. The tabs "Lokal" and "Figur" are gone from it (the figure is chosen in Play, and Training
  uses the same figure).
- In a Play round the screen shows only the game and a small pause button in the top right (Resume / Main menu).
  Training keeps its scoreboard and the gear. The Android back button pauses a game, goes back from the lobby and
  quits from the main menu.
- The update notice now shows in the main menu (and in Settings), not during a game.
- All menus and texts are now in English.
- **Rounds and points in Play** (mode **Last Standing**): nobody respawns within a round, the last one standing gets
  a point, the first to 10, 15 or 20 points (your choice in the lobby) wins the match. Each round starts with a big
  3-2-1-GO. After a round you see who scored and the scoreboard; the next round starts by itself after a few
  seconds. When the match ends you can play a **Rematch** (Solo and the host) or go back to the main menu.
- **Solo** starts a match straight away. In **Together** the host presses **Start match** once at least two players
  (bots count) are in; the others wait in the lobby. Nobody can join while a match is running; joining is open
  again when it is over. Training is unchanged (it still respawns, no rounds).
- The app is now called **Spinback Rumble** (it installs over the old app as usual and keeps your saved settings).
- **Coming back after a dropped connection**: if your connection breaks during a match (Wi-Fi hiccup, app closed
  by accident), your figure stays standing in the arena with its points, and the game shows "Reconnecting …" and
  tries to get you back by itself for about 20 seconds. If that fails, or you restarted the app, press **Rejoin**
  in Play > Together. The place is held until the match ends.
- New fonts for the new screens (Unbounded and Rubik, free under the SIL Open Font License).

## 0.5.0

Play with friends without a server: one phone hosts, the others join.

- **New tab "Lokal"** in the settings. The host presses **Spiel eröffnen** (with the check box **Mit Bots auffüllen**,
  on by default) and sees a big code and the number of players. The match uses the host's settings.
- **Everyone must be in the same Wi-Fi, or in the hotspot of one of the phones.** The hotspot has to be switched on by
  hand in the phone's settings; the app cannot do that.
- **Joining:** the other phones open **Lokal** and press the game under **Gefundene Spiele**. If nothing shows up
  (some networks block this), type the code and press **Beitreten**.
- **The match ends when the host leaves** the game or closes the app; the others are then back in the offline game.
- The tab **Online** (join a server by address) works as before.
- The Android app now also asks for the permissions to read the Wi-Fi state and to receive broadcasts (needed for
  the list of found games). After installing, the update goes over the old app as usual.
- Your own explosions (Sprengkopf, and Splitter + Sprengkopf) now hurt you too. Such a death gives nobody a kill.
- Extra-Dash level 3 no longer dashes 1.3x as far; instead the dash goes through the obstacle blocks, the crate and
  the box (never through the outer walls).
- The default maximum throw range is now 10 m (was 8 m), and the string is 10 m long (was 9 m). Phones that kept
  their own tuned values keep them; "Zurücksetzen" in the tuning menu picks up the new defaults.
- **Lenkwurf replaces Bogenwurf.** While the yo-yo flies, pull the aim stick to steer it towards that direction (the
  string follows the bend). Level 2 steers harder and adds 25 % range. Level 3 is telekinesis: hold and pull the aim
  stick to move a lying or flying yo-yo freely (deadly, limited by the string length and by walls). Hold without
  pulling still drags you to the yo-yo and a tap still calls it back. Your saved Bogenwurf level is gone (the
  modifier has a new name); set Lenkwurf again in the menu.

## 0.4.2

A new Schnapp-Dino and a rolling Würfel, the toy train blocks yo-yos, and a lying yo-yo can be picked up by walking
over it.

- **The Schnapp-Dino** is now a round T-Rex with a fat tail, back plates and tiny arms. Its head is a snapper toy:
  the upper part with the eyes swings up, so you see the pink mouth and teeth from above. It snaps while walking, opens
  wider while charging, shuts on the throw, hangs open a little when dizzy and snaps once when it catches the yo-yo.
- **The Würfel** really rolls over its edges in the direction it moves. It has one face (eyes, smile, cheeks) and pips on
  the other sides, and when it stops it hops a little and lands with the face to the front.
- **The train blocks yo-yos:** a thrown yo-yo stops in front of a car (or bounces off it with the bounce modifier),
  a yo-yo coming back is stopped by it, and a yo-yo lying on the track is pushed aside by the arriving train. Yo-yos
  with the second pierce level still pass, like they pass the crate. Strings and shards still go over the train.
- **New:** walking over your own lying yo-yo picks it up again, no tap or hold needed. It works for every
  variant and for both yo-yos of the Zwilling. A stunned player does not pick it up.

## 0.4.1

Figures with more character, and a fix for see-through blocks.

- **Fixed:** the Würfel, the Aufzieh-Roboter and the building blocks no longer look see-through.
- **Springteufel and Kreisel** have no feet any more. The Kreisel's lower part now spins visibly too: slowly when
  standing, faster when running, fastest in a dash.
- **The dino is now the Schnapp-Dino**, a chunky wind-up snapper: its jaw snaps as it walks, opens wider and wider
  while charging and shuts on the throw.
- **The Quietsche-Ente** is a wooden pull-along duck on wheels that waddles and lifts its wings on a throw.
- **The Stehauf-Püppchen** is a real roly-poly: no legs, it tips into its run and rocks out when it stops or is hit.
- **All figures are about the same size now**, matching the hit area, which is the same for everyone as before.

## 0.4.0

A toy train, four more figures, and you pick your own.

- **A toy train** runs a loop around the middle of the room. It runs over anyone in its way (nobody gets the kill)
  and shoves the toy chest aside; yo-yos pass over it. Nobody respawns in front of it, and the bots dodge it. Its
  speed is a slider in the settings ("Eisenbahn-Tempo", 0 switches it off).
- **Eight figures** now: Gummi-Dino, Aufzieh-Roboter, Plüschhase and Quietsche-Ente are joined by Springteufel,
  Würfel, Stehauf-Püppchen and Kreisel.
- **Choose your figure** in the new settings tab "Figur", with a live picture of it. The choice is kept, also after
  "Zurücksetzen", and online the others see it too. Bots get the other figures.
- **The room got a makeover**: wooden floor, a chequered play carpet framed by wooden beams with crayons and marbles
  on them, building blocks with letters, a toy chest on wheels, and a wrapped present that bursts open when it
  breaks.
- Online, this version only plays with servers of the same version. Your tuned values are kept.

## 0.3.1

First look at the toy style: "toys from around the year 2000 come alive".

- **Four toy figures** instead of the placeholder shapes: Gummi-Dino, Aufzieh-Roboter (with a turning wind-up key),
  Plüschhase and Quietsche-Ente, each in its player's colour. From above you can see where each one looks.
- **Every action has its own movement**, so you can read what an opponent is about to do: charging winds up more
  and more and trembles when full, throwing lunges, catching recoils, a dash stretches and leaves a short trail,
  being pulled to the yo-yo looks like flying, a stunned toy wobbles with stars. A knocked-out toy pops into its
  parts with confetti, and it drops back in when it returns.
- **The yo-yos** are now toy yo-yos in the same shiny plastic.
- **The arena is a children's room** (play carpet, toy fence, wooden blocks, a cardboard box, a tower of blocks
  that tumbles when it breaks) and is a little bigger: 32 x 14.4 m instead of 28 x 12.6 m.
- Online, this version only plays with servers of the same version (the arena changed). Your tuned values are kept.
- **Server protection:** a player who sends nothing for 30 seconds is dropped, so a stuck or misbehaving connection
  can no longer block a slot forever, and nonsense stick values from a broken or hostile client are ignored instead of
  breaking the game for everyone.

## 0.3.0

Netcode experiment, third test build.

- **Update notice:** the app now checks once after the start whether a newer test version exists and shows
  "Neue Version ... verfügbar" with a download button. The settings show the running version.
- **Smooth opponents:** the other players move evenly instead of jumping.
- **Enemy yo-yos are drawn in the present**, at the same time as the player, not slightly behind.
- **Fixed test key:** test builds are signed with one fixed key, so a new version installs over the old one and
  keeps your tuned values. (Versions 0.2.0 and older have to be uninstalled once.)
- The server keeps a smaller input buffer, which makes online play react faster.

## 0.2.1

- Other players are drawn smoothly, a little in the past (about 70 ms), and move evenly between the positions
  the server sends. The switch "Gegner glätten" on the "Online" page compares this with the raw display.
- A dash of another player is no longer applied several times.
- First build signed with the fixed test key.

## 0.2.0

- **Online (experiment):** page "Online" in the settings: connect to a server on a PC in the same network, up to
  4 players. Artificial delay and packet loss sliders to try out bad connections.
- Your own character reacts at once; the server only corrects it when it sees things differently.
- Pierce level 1: the yo-yo also comes back through the block it flew through.

## 0.1.0

- First game-feel prototype, offline against practice bots: the yo-yo (charge, throw, retract, pull yourself to
  it), dash with charges, ten modifiers with three levels and their combinations, and a settings menu with
  sliders and a sandbox for the modifiers. "Werte kopieren" copies all settings as text for feedback.
