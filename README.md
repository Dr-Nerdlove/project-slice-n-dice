# Slice n Dice

A top-down arena brawler for Android with online multiplayer for 2-8 players. Fast rounds where one hit kills, and the weapon is a yo-yo you throw, leave spinning, retract or pull yourself towards.

![Vision sketch](docs/vision.png)

The picture is the original German vision sketch.

## Status

Early prototype, milestone 1 (game feel offline). See [docs/PLAN.md](docs/PLAN.md) for the full plan.

## Working on it

- Engine: Godot 4.7.2. The Godot project is in `game/`.
- Run on PC:

  ```
  godot --path game
  ```

- Build an Android debug APK:

  ```
  godot --headless --path game --export-debug "Android" ../build/slice-n-dice-debug.apk
  ```

  This needs the Godot export templates, JDK 17 and the Android SDK, configured in Godot's editor settings.

- Run the automated tests (needs `godot` on the PATH; a few seconds):

  ```
  tests/run.sh
  ```

  `python3 tests/sabotage.py` checks that the tests really catch deliberate breakage. GitHub Actions runs the
  tests on every push and pull request and builds the debug APK (download it from the run's artifacts).

## Playing online (experiment)

The first netcode experiment: a headless server on a PC, 2-4 phones on the same network.

- Start the server (UDP port 24565 by default; `--bots` fills the free slots with bots):

  ```
  godot --headless --path game -- --server [--port 24565] [--bots]
  ```

  It prints joins and leaves and a status line every 10 seconds. Allow the port in the PC's firewall.
- On the phone: open the settings (gear), page **Online**, type the PC's address (`name` or `address:port`),
  **Verbinden**. The sliders on that page add artificial delay (per direction, so the ping grows by twice that value)
  and packet loss, and the switch **Gegner glätten** (on: the other players are drawn smoothly, a little in the past;
  off: the raw prediction, to compare); the HUD shows ping, correction, open inputs and the delay of the others.
- Check a running server without a display: `godot --headless --path game -s tests/net_probe.gd -- HOST[:PORT]`.

The Android build has the INTERNET permission enabled for this.

## Licence

GNU AGPL v3, see [LICENSE](LICENSE).
