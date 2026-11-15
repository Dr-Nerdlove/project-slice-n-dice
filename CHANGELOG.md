# Changelog

One section per release, newest first. The heading is `## MAJOR.MINOR.PATCH` (no `v`); the release workflow
(`.github/workflows/release.yml`) publishes the section of the tagged version as the release notes and fails if
there is none. Write it for testers, in plain words.

## Unreleased

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
