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

## Licence

GNU AGPL v3, see [LICENSE](LICENSE).
