# Changelog

One section per release, newest first. The heading is `## MAJOR.MINOR.PATCH` (no `v`); the release workflow
(`.github/workflows/release.yml`) publishes the section of the tagged version as the release notes and fails if
there is none. Write it for testers, in plain words.

## 0.4.2

Two figures redesigned.

- **The Schnapp-Dino** is now a round T-Rex with a fat tail, back plates and tiny arms. Its head is a snapper toy:
  the upper part with the eyes swings up, so you see the pink mouth and teeth from above. It snaps while walking, opens
  wider while charging, shuts on the throw, hangs open a little when dizzy and snaps once when it catches the yo-yo.
- **The Würfel** really rolls over its edges in the direction it moves. It has one face (eyes, smile, cheeks) and pips on
  the other sides, and when it stops it hops a little and lands with the face to the front.

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
