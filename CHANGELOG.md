# Changelog

One section per release, newest first. The heading is `## MAJOR.MINOR.PATCH` (no `v`); the release workflow
(`.github/workflows/release.yml`) publishes the section of the tagged version as the release notes and fails if
there is none. Write it for testers, in plain words.

## 0.3.0

Netcode experiment, third test build.

- **Eight toy figures instead of capsules:** tin robot, jack-in-the-box imp, plush dinosaur, rubber duck, die,
  roly-poly doll, spinning top and teddy. Each walks in its own way (march, hop, stomp, pitter-patter ...). They
  differ only in looks; size and speed are the same for all. Choose yours in the settings on the new tab "Figur";
  other players see it online. The body colour stays the player colour.
- **The yo-yo throw has a real animation:** the figure holds the yo-yo in its hand, winds up while the throw is
  charged, flicks it out, and the string runs from the hand. The yo-yo flies out in a flat arc and climbs back
  into the hand.
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
