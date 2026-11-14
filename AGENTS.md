# AGENTS.md

Instructions for every AI tool working on this repository.

<!-- owner-rules v16: general (AGENTS.md) - begin -->

## General rules

### People

- Unless "Project knowledge" says otherwise, assume that the people you work with **do not program**: they
  build their projects together with AI assistants and rely on you for the code, its quality and its
  explanation. "Project knowledge" lists who works on the project.
- Talk to them in **German**, in plain words, without jargon. Say what changes for them, not which file
  changed.
- When they ask for ideas or something is unclear, **offer choices and let them pick before building**, with
  a recommendation. Do not build a proposal nobody chose.
- **Report honestly**: a test that failed, a step that was skipped, a fix that turned out to be wrong. Say
  what was **really tested** and what was only built or compiled, and what it means for them.
- **Merge, release or publish only when the person asks for it.** Never merge or overwrite the work of
  someone else without their consent; propose it to them (pull request, comment) instead.

### Language

- **Everything in the repository is English**: files and documentation, code comments, commit messages,
  branch names, pull requests, issues and release notes. Only the conversation with the people is German.
- Text that the product itself shows to its users (an app's interface, a device's display, its store page)
  stays in the language or languages the product is made for. "Project knowledge" names them.
- **A product in several languages stays in all of them.** Every new or changed text goes into every
  language the product offers, in the same change; never leave one language behind, drop one, or fall back
  to another language silently. Write each language naturally (not word for word), with its proper
  characters (ä, ö, ü, ß in German). Check that no text is missing in any language before calling the change
  done.
- Where a project still has older content in another language, do not translate it on your own: offer it as
  a choice.

### Testing

- Where the project has automated tests, **every new behaviour that can be tested automatically gets a test,
  and a sabotage check**: break the behaviour on purpose (it must still compile, and it must break the
  behaviour, not just a selector or a text), run the test, see it fail, put the code back and confirm that
  the file is byte for byte what it was (`cmp`). A test that passes against broken code is worthless.
- **What cannot be tested automatically** (hardware, devices, displays, animations, things that need a real
  account or service) gets no test suite of its own. Check it as far as possible (build, compile, a preview),
  then on the real device or service, and say plainly which part is checked how.
- Where the project has no tests at all, do not set up a test suite on your own: when a change would be
  risky without one, offer it to the owner as a choice.
- Run the project's checks before pushing, as "Project knowledge" or the project's own instructions say.
  Where they say nothing: the checks that cover what changed, and the whole suite when the change could have
  effects elsewhere.

### Safety and data

- **Never put secrets into the repository**: passwords, API keys, tokens, private keys, keystores and `.env`
  files with values. Use the project's way of keeping them out (environment, settings, `.gitignore`); if there
  is none, ask.
- **Nor what tells others about the people or their machines**: addresses and host names in the home network,
  local paths with a user name (`C:\Users\<name>\…`, `/home/<name>/…`; use paths relative to the
  repository), and hidden metadata in files: images, PDFs and office documents can carry the path they were
  made from, an author's name or, in photos, the place (GPS). Remove it before committing such a file, and
  switch it off in the tool or script that makes the file, so it does not come back.
- **Never write a secret into a command**, not even for a quick test: tools remember commands word for word
  (Claude Code keeps every allowed one in `.claude/settings.local.json`), and the session's output is not
  private. Read secrets from the environment or a file that is not committed, or ask for them through the
  session's secure input where it has one. Never print one; show at most its first characters.
- **If a secret got out anyway** (pushed, or shown in a log, a pull request or an issue), tell the owner at
  once, without repeating the value. The secret counts as burnt: it must be **changed at the provider**, which
  makes the leaked copy worthless. Deleting it from the history alone is not enough (copies, caches, forks and
  logs keep it), and rewriting history happens only when the owner explicitly agrees.
- **Personal data** (of the people or of the product's users) is not sent anywhere new, logged or published
  without asking.
- **What users have stays usable after an update**: their settings, saved data, accounts. When a change
  would break or reset them, say so before building and offer a way to carry them over.
- **Never overwrite `main` with a force-push and never delete it.** Not even when asked in passing; the
  owner does that themselves if it is ever needed.
- **Ask before anything hard to undo**: deleting data or files that are not part of the change, rewriting
  history, changing a live service, publishing to a store.
- **New libraries or services** only with a reason, said in plain words; prefer what the project already
  uses.

### Changes

- **One topic per change** (branch, pull request): easier to check, to release and to undo.
- **One branch per task.** Create it from the latest default branch (usually `main`) with a name that says
  what the change is about: `type/short-topic`, lower case, English, words joined by hyphens - `feature/` for
  something new, `fix/` for a bug, `docs/` for documentation, `chore/` for tidying up (e.g.
  `feature/online-update`, `fix/ota-redirect-query`, `docs/ai-rules`). Not who or when, and nothing vague like
  `test` or `update2`. Push to that branch instead of the random branch name the environment gives the
  session; this is the owner's standing permission to push to such branches. A new task in the same session
  gets a new branch. Propose every change as a pull request into the default branch. It is merged when the person merges it on GitHub or asks for it ("übernehmen"); then merge it yourself (never squash away someone else's commits). Where the project has its own naming habits, follow
  them.
- **After a merge or release, the new version is not everywhere at once.** GitHub keeps copies for a while:
  GitHub Pages is usually live a minute or two after its run has finished, but browsers may show the old page
  for up to 10 minutes (raw files and download links up to about 5) unless reloaded without the cache;
  whatever a workflow builds or publishes only exists once its run has finished. Tell the person **how long to wait** (from the cache times
  and how long the project's last run took) and **how to check that the new version has arrived**: the run
  finished green under "Actions", the new version number in the app, on the release page or in the file, the
  new text on the page after a reload that bypasses the browser's cache. Where you can check it yourself, do
  so before calling it done, and say what you saw.
- **Commit messages and pull request titles** say in one line what changes, e.g. "Fix online update: keep
  the signed download URL"; more detail, and why, goes below.
- Changes that users notice go into the release notes or changelog in plain words (in English, like
  everything in the repository; texts shown to users inside the product or in a store, such as "what's new",
  in every language the product offers).

### Repository

Aim for what is common practice on GitHub, in proportion to the project: a small experiment needs less than
something others install. **Do not restructure an existing repository on your own**: point out what is
missing, with a recommendation, and let the people choose.

- **README**: what the project is (with a picture where it helps), how to install and use it, how to work on
  it (build, test, release), and its licence. Keep it up to date with every change that affects it.
- **Pull request descriptions**: what changes, why, how it was tested (and what was not), and anything the
  reviewer should know.
- **Automatic checks (CI)**: every push and pull request builds the project and runs its tests
  automatically; merge only when they pass. Where a project has none, offer to set it up. Where they do not
  look for secrets yet, offer a secret scan of every push (e.g. gitleaks); add it only when the owner chooses
  it.
- **Releases**: version numbers `vMAJOR.MINOR.PATCH` (e.g. `v1.4.2`: major for breaking changes, minor for
  new features, patch for fixes). Files that are published are built by CI, never by hand. Each release says
  in plain words what is new and how to install or update.
- **Basics**: a `.gitignore` for build output and local files, a **licence** file (without one, nobody may
  legally reuse the code, even in a public repository; the choice of licence is the people's), and a
  `CHANGELOG.md` where releases alone do not tell the story.

- **Protecting `main`**: when the rules are installed, check whether the repository is public or private.
  - **Public**: recommend to protect `main` against force-pushes and deletion, and give the steps below. The
    owner of the repository decides whether it makes sense for this project. You cannot set it up yourself,
    because you have no access to the repository settings.
  - **Private**: recommend nothing where the repository belongs to the rules' owner: they have no GitHub Pro,
    and in a free account branch protection and rulesets exist only for public repositories (source:
    `github/docs`, file `data/reusables/gated-features/protected-branches.md`). They can ignore GitHub's
    notes about missing protection there. Where the repository belongs to someone else, their plan decides
    and you cannot see it: mention once that protection on a private repository needs a paid plan (Pro or
    Team), and leave the decision to its owner.
  - **If you cannot tell** whether the repository is public or private (no way to look it up), ask instead of
    guessing.
  - **Whose repository it is matters**: only the repository's owner (or an admin) can open its settings. Where
    it belongs to someone else, say so and tell the person to pass the steps on to them.

  Steps for the owner (give them in German):

  1. Auf GitHub das Repository öffnen: **Settings → Rules → Rulesets → New ruleset → New branch ruleset**.
  2. Name: `main schützen`. **Enforcement status**: `Active`.
  3. **Target branches → Add target → Include default branch**.
  4. **Restrict deletions** und **Block force pushes** angehakt lassen.
  5. **Require status checks to pass** nur anhaken, wenn das Projekt CI hat; dann die CI-Prüfung auswählen.
     Achtung: Dann kann niemand mehr direkt auf `main` pushen, jede Änderung muss erst auf einem anderen
     Branch die Prüfung bestehen. Das passt nur, wenn ohnehin nichts direkt auf `main` geschrieben wird
     (auch kein Workflow). Bleibt ein Merge hängen, zuerst dort nachsehen: ob die Prüfung umbenannt wurde
     oder bei dieser Änderung gar nicht lief.
  6. **Nicht** "Require a pull request before merging" mit Approvals anhaken: Wer allein arbeitet, kann eigene
     Pull Requests nicht freigeben und würde sich selbst aussperren. Auch zu zweit ist es nicht nötig und
     bremst nur jeden Merge; der Schutz vor Force-Push und Löschen reicht.
  7. Auf **Create** klicken.

  Geklappt hat es, wenn das Ruleset in der Liste unter **Rulesets** als "Active" steht.
  Für weitere Projekte: das Ruleset dort über **Export ruleset** speichern und im nächsten Projekt über
  **Import a ruleset** übernehmen.

### Showing changes

- Show visual changes rather than describing them: **screenshots** where the result runs on a computer.
- Where no screenshot is possible (a device, a display, a phone app, print): build a **preview** (a mock-up
  page, a pixel preview), or ask for a **photo** of the real thing.

### Checking facts at the source

- Do not build on memory where the real thing can be checked: read the actual source of a library, look at
  the real answer of a server or service, read the real data. Behaviour that "should" be so is often not.
- When a cause is unclear, **ask for a log or an error message before guessing**, and say what it would show.

### Keeping knowledge in the repository

- Sessions end and are deleted; the repository stays. What a later session needs to know goes into the
  project's files ("Project knowledge", the README, other docs, commit messages), not only into the
  conversation: decisions and why, traps that cost time, how to build, test and release, and the limits of
  the environment (what a cloud session cannot do there).

<!-- owner-rules v16: general (AGENTS.md) - end -->

## Project knowledge

- **People:** Two people work on the project together with AI assistants; neither programs themselves. The
  repository owner (GitHub: Dr-Nerdlove) and a collaborator (GitHub: Joni9993), who has admin rights and whose
  machine the local sessions run on (`gh` is logged in as Joni9993 there: `gh repo create` creates under that
  account even when another owner is named). Agreed between them (2026-11-13): while the concept is being worked
  out, Joni9993 works ahead and decides about merging and test releases; Dr-Nerdlove builds on it afterwards.
- **What the project is:** "Slice n Dice", a top-down arena brawler for Android with online multiplayer
  (2-8 players) and a yo-yo as the weapon. Plan and decisions: `docs/PLAN.md`.
- **Product languages:** Not finally decided. The prototype UI is German for now.
- **Build and test:** Godot 4.7.2, project in `game/`. Run on PC: `godot --path game`. Android debug APK:
  `godot --headless --path game --export-debug "Android" ../build/slice-n-dice-debug.apk` (needs Godot export
  templates, JDK 17 and the Android SDK configured in Godot's editor settings). Tests: `tests/run.sh` (needs `godot` on the
  PATH; ~70 s, nearly all of it the netcode suite) runs the headless checks of the simulation and the menus in
  `tests/test_sim.gd`, of the netcode in `tests/test_net.gd` (loopback with fake clock, real ENet on localhost, the
  real main scene), of the update notice in `tests/test_update.gd` and of the toy figures, their poses and the
  arena geometry in `tests/test_view.gd`; `tests/run.sh sim|net|update|view ...` runs only
  the named suites; it prints only failures and a summary and exits non-zero on a failed check, an engine/script
  error or zero checks. `GAME_DIR=<copy of game/>` runs the tests against a copy and `TEST_PORT_OFFSET=N` shifts the
  localhost ports and the `user://` test file (parallel runs). `tests/run.sh soak` runs a longer bot soak run (~30 s,
  not in CI). `python3 tests/sabotage.py [-j N] [--full] [prefix ...]` breaks the game code on purpose, one change at
  a time, and checks that the tests notice. It works in temporary copies of `game/` outside the repository (the
  working tree is never modified; the script checks that `game/` is identical afterwards), runs only the suite that
  covers an entry (prefix 1-7 sim, 8 net, 9 update, 0 view; an entry that needs another suite goes into
  `SUITES_OVERRIDE`), stops the net suite after its first failing group, and runs `-j N` entries in parallel
  (default: half the CPU cores). All 146 entries take about 8 min with 6 workers (no gain beyond that on a 12-thread machine) (the old one-by-one run with the
  whole suite per entry: about 2.5 h); `--full` runs the whole suite for every entry. When game code is refactored,
  its patterns may go stale (the script reports "pattern count 0" and fails): update them. New testable behaviour
  gets a check in `tests/test_sim.gd` (netcode: `tests/test_net.gd`) and, if sensible, an entry in
  `tests/sabotage.py`. The tests live outside `game/` so the APK does not contain them. A new
  `class_name` file needs `godot --headless --path game --import` once before the tests see it.
- **Architecture rule:** `game/sim` is a pure fixed-tick simulation without nodes, physics or Input;
  `game/view` only reads it.
- **Netcode (experiment, M2):** `game/net/`, pure logic without nodes except `server_main.gd`. `ServerCore`
  (authoritative sim, 60 Hz), `ClientCore` (prediction by re-simulating the pure `Sim`), `NetProto` (wire format,
  validation), the `NetEndpoint` interface with `ENetEndpoint` (real UDP), `LoopbackHub` (in memory with delay and
  loss, for tests) and `LagEndpoint` (the artificial lag tool of the Online menu page). The own player is predicted; the OTHER players are
  drawn from `ClientCore.display_sim`, an interpolation between buffered snapshots about 4+ ticks in the past (switch
  "Gegner glätten"; `ArenaView.set_others`), except their yo-yo heads that are out and their shards: those are drawn
  from the predicted sim, in the present, with a decaying visual offset against pops (`ClientCore._apply_predicted`,
  `predict_heads`). Hits are decided on present positions and not lag-compensated (open design decision in
  `docs/PLAN.md`). The server's input buffer per player is adaptive (`ServerCore.Slot.target`). `Sim.save_state()` /
  `load_state()` snapshot every script variable by reflection (`game/sim/state_io.gd`): a variable that is not
  state (computed property, static data) must be listed in its class's `STATE_SKIP`, everything else is included
  automatically. Run the server: `godot --headless --path game -- --server [--port N] [--bots]` (default UDP
  24565; no hosting is set up); check a running one with
  `godot --headless --path game -s tests/net_probe.gd -- HOST[:PORT] [--lag MS] [--loss PCT]`. Decisions and what is
  not done yet: `docs/PLAN.md` (M2).
- **Look (toy figures, playroom):** all in `game/view`, view only. `toy_kit.gd`: the shared materials (glossy
  plastic with clearcoat and rim, plush, wood) and unit meshes; share them, do not create materials per figure.
  `toy_figure.gd`: builds the four figures (sizes in player radii, +z is the front) and applies the pose;
  `toy_pose.gd`: pure "sim state -> pose targets" plus the springs (fixed sub-steps); `toy_motion.gd`: follows one
  player in the sim the view draws it from (online the others come from the display sim) and notices throw,
  catch, dash end, death, respawn. `playroom.gd`: floor, fence, blocks, crate, box of the arena; arena geometry
  itself is in `game/sim/config.gd`. Which toy a slot gets: `ArenaView.FIGURE_KINDS`. To add a figure: a new
  `ToyPose.Kind` with its `CYCLE` entry and gait flavour, a `_build_*` function in `toy_figure.gd` that creates at
  least the six standard pieces (Body first, Head, ArmL, ArmR, FootL, FootR), its accent in `ACCENTS` and name in
  `NAMES`; `tests/test_view.gd` then checks it builds and fits the hit circle. **Screenshots cannot be made on the
  owner's Linux machine:** no X server, no Xvfb, no GL/EGL or Vulkan libraries (Godot's x11 and wayland drivers fail
  on missing `libXcursor` / `libwayland-client`; headless only has the dummy renderer). The look is checked on the
  phone; rendering in CI (Xvfb with Mesa on a GitHub runner) would be an option.
- **Modifiers:** Modifier definitions, German texts and all their numbers live in `game/sim/mods.gd`.
- **Release:** Testers get APKs from the PUBLIC repository `Joni9993/slice-n-dice-releases` (this one is private).
  How a release is made: (1) add a section `## MAJOR.MINOR.PATCH` to `CHANGELOG.md` (the workflow fails without it;
  it becomes the release notes); (2) merge to `main`, or tag the branch you want to release; (3) push the tag
  `vMAJOR.MINOR.PATCH`. `.github/workflows/release.yml` then runs `tests/run.sh`, sets the version from the tag
  (`tools/set-version.sh`), builds the APK signed with the fixed test key (it fails if the key secrets are missing),
  and publishes a normal (not pre-)release `slice-n-dice-vX.Y.Z.apk` there with `gh release create` using the secret
  `RELEASES_TOKEN` (fine-grained token, contents read/write on that repository only). A retry (Actions > Release >
  Run workflow with the tag; the workflow file must be on `main` for that button) replaces the APK of an existing
  release. The workflow cannot be tested locally; the first real run is its test. Older pre-releases (`v0.1.0`,
  `v0.2.0`, `v0.2.1`) were made by hand and live in the private repository. Version rule: one number
  `MAJOR.MINOR.PATCH`; `tools/set-version.sh` writes it to `application/config/version` in `game/project.godot` (what
  the game shows and compares), and `version/name` and `version/code` (= MAJOR*10000 + MINOR*100 + PATCH, so MINOR
  and PATCH stay below 100) in `game/export_presets.cfg`. The committed files hold the version of the NEXT release
  (now 0.3.1); a test checks that they agree. CI builds of branches use the committed version plus the suffix
  `-dev+<commit>` in `application/config/version` only (set by the `apk` job), so the game shows it is a dev build and
  never offers an update for the same version. How the app finds updates: `game/update/update_check.gd` (pure logic)
  and `main.gd` ask `https://api.github.com/repos/Joni9993/slice-n-dice-releases/releases/latest` once, 3 s after the
  start (not headless, not in server mode, silent on any failure), compare versions and show a banner and a button
  in the settings; the download link is accepted only below `https://github.com/Joni9993/slice-n-dice-releases/` and
  is opened with `OS.shell_open`. Android installs the APK over the old one only if the signing key is the same (trap 7).
- **Traps:** (1) ENet turns an unreliable packet bigger than one MTU into a reliable one unless it is sent with
  `FLAG_UNRELIABLE_FRAGMENT` (`ENetEndpoint` does; from ENet's source, not provable from GDScript). (2)
  `PackedByteArray.decompress_dynamic` works only for gzip, deflate and brotli, not zstd: the snapshot stores its raw
  size. (3) `bytes_to_var` prints an engine ERROR for every malformed buffer (run.sh counts those as failures), so
  `NetProto.unpack` only decodes buffers that start with an Array header; a truncated Array with a valid header still
  prints one error line on the server (harmless noise, not tested). (4) A slider (`Range`) only emits
  `value_changed` after the frame that follows `add_child`. (5) Two RefCounted objects that reference each other leak
  and make Godot print "resources still in use" at exit, which run.sh counts as an error: see the weak reference in
  `LoopbackEndpoint`. (6) Client and server clocks are not synchronised: a client that ticks slower or faster than
  60 Hz makes the server's input buffer run dry or drop inputs (corrections, never a crash). (7) An APK only installs over an
  earlier one when both are signed with the same key; otherwise the old app must be uninstalled first, which deletes
  the tuned values on the phone. CI signs with the fixed test key from the repository secrets `TEST_KEYSTORE_B64`
  and `TEST_KEYSTORE_PASSWORD` (alias `slicendice-test`; created by the owner with `tools/setup-test-keystore.sh`,
  the key itself stays outside the repository on the owner's machine). Without the secrets CI falls back to a
  throwaway key and prints a warning. `v0.1.0` and `v0.2.0` were signed with other keys.
- **Repository:** Private, owned by Dr-Nerdlove. Licence: GNU AGPL v3 (`LICENSE`). Default branch `main`. CI:
  `.github/workflows/ci.yml` runs on every push and pull request: job `test` runs `tests/run.sh`; job `secrets` scans the full git history with a pinned,
  checksum-verified gitleaks binary (`--redact`, no config file; a finding fails the run); job `apk`
  (after `test`) exports the debug APK and uploads it as an artifact (14 days). Godot and the Android export
  templates are downloaded from the official release and cached; the APK is signed with the fixed test key (trap
  7), the Java/SDK/keystore paths are written to Godot's editor settings (no env vars exist for them). No branch protection: not available for private repositories on the owner's free plan (see
  "Protecting `main`").
- **Limits of the environment:** Cloud sessions (Claude Code on the web) cannot open the repository settings
  (rulesets, secrets, Pages); the owner does that on github.com. GitHub is reached through the GitHub MCP tools,
  not the `gh` CLI. Local sessions on the owner's Linux machine have git over HTTPS working.
