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
- **What the project is:** "Spinback Rumble" (formerly the working title "Slice n Dice"; the repository and file names keep the old name), a top-down arena brawler for Android with local multiplayer
  (2-8 players) and a yo-yo as the weapon. Plan and decisions: `docs/PLAN.md`.
- **Product languages:** English only (decided by the owner on 2026-11-15). All texts in the game are English now (translated 2026-11-15, version 0.6.0); all new text is English.
- **Build and test:** Godot 4.7.2, project in `game/`. Run on PC: `godot --path game`. Android debug APK:
  `godot --headless --path game --export-debug "Android" ../build/slice-n-dice-debug.apk` (needs Godot export
  templates, JDK 17 and the Android SDK configured in Godot's editor settings). Tests: `tests/run.sh` (needs `godot` on the
  PATH; ~70 s, nearly all of it the netcode suite) runs the headless checks of the simulation and the menus in
  `tests/test_sim.gd`, of the netcode in `tests/test_net.gd` (loopback with fake clock, real ENet on localhost, the
  real main scene, and local play: LanCode, LanBeacon over real UDP, LocalHost, the Play lobby, the main menu flow with Play vs Training, pause), of the update notice in `tests/test_update.gd` and of the toy figures, their poses and the
  arena geometry in `tests/test_view.gd`; `tests/run.sh sim|net|update|view ...` runs only
  the named suites; it prints only failures and a summary and exits non-zero on a failed check, an engine/script
  error or zero checks. `GAME_DIR=<copy of game/>` runs the tests against a copy and `TEST_PORT_OFFSET=N` shifts the
  localhost ports and the `user://` test file (parallel runs). `tests/run.sh soak` runs a longer bot soak run (~30 s,
  not in CI). `python3 tests/sabotage.py [-j N] [--full] [prefix ...]` breaks the game code on purpose, one change at
  a time, and checks that the tests notice. It works in temporary copies of `game/` outside the repository (the
  working tree is never modified; the script checks that `game/` is identical afterwards), runs only the suite that
  covers an entry (prefix 1-7 sim, 8 net, 9 update, 0 view; an entry that needs another suite goes into
  `SUITES_OVERRIDE`), stops the net suite after its first failing group, and runs `-j N` entries in parallel
  (default: half the CPU cores). All entries (about 320 now; 190 took about 10 min with 6 workers, no gain beyond that on a 12-thread machine; the
  old one-by-one run with the whole suite per entry took about 2.5 h) take roughly 15 to 20 min. The live list `SB` is
  the one at the END of the file (an older, dead copy of it stands above it, ignored); `--full` runs the whole suite for every entry. When game code is refactored,
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
  "Smooth others"; `ArenaView.set_others`), except their yo-yo heads that are out and their shards: those are drawn
  from the predicted sim, in the present, with a decaying visual offset against pops (`ClientCore._apply_predicted`,
  `predict_heads`). Admission: a joined player with no input for `IDLE_TIMEOUT` (30 s) loses the slot, and `NetProto.decode_input` refuses stick values above `MAX_STICK` (2; a huge value becomes inf, then NaN, and poisons the sim). A per-address limit on slots was rejected: friends in one house share one public address and would be refused; a join code/password is the planned answer once a public server exists. Hits are decided on present positions and not lag-compensated (open design decision in
  `docs/PLAN.md`). The server's input buffer per player is adaptive (`ServerCore.Slot.target`). `Sim.save_state()` /
  `load_state()` snapshot every script variable by reflection (`game/sim/state_io.gd`): a variable that is not
  state (computed property, static data) must be listed in its class's `STATE_SKIP`, everything else is included
  automatically. Run the server: `godot --headless --path game -- --server [--port N] [--bots]` (default UDP
  24565; no hosting is set up); check a running one with
  `godot --headless --path game -s tests/net_probe.gd -- HOST[:PORT] [--lag MS] [--loss PCT]`. Decisions and what is
  not done yet: `docs/PLAN.md` (M2).
- **Local play (version 0.5.0, in the Play lobby since 0.6.0):** one device hosts, the others on the same Wi-Fi or in the host phone's hotspot join (Play > Together, the former tab "Lokal"; the Online tab and `--server` stay in Training). Three classes in `game/net/`: `LanCode` (pure) turns the host's IPv4
  address into a code of 4 to 7 characters (2 class bits, then the address bits, zero padding to a multiple of 5 bits;
  192.168.x.y 4 characters, 172.16/12 5, 10.x.y.z 6, any other 7; alphabet of 32 without 0 O 1 I; decoding ignores case,
  spaces and dashes; the port is always `NetProto.DEFAULT_PORT` 24565) and `pick_local_address` chooses the address to
  host on from `IP.get_local_interfaces()` (never loopback, link-local, IPv6; 192.168 before 172.16/12 before 10 before
  the rest; Wi-Fi / hotspot interface names before mobile data). `LanBeacon` is the discovery: the host broadcasts a 10 byte
  hand-rolled packet ("SND1", protocol version, game port, players, max) once a second to UDP port 24566, to
  255.255.255.255 and to a.b.c.255 of every local network; a looking device binds 24566 (only while the lobby is open
  and it is neither hosting nor connected; the listener is owned by `PlayLobby`, runs only while the lobby is open) and lists games of the same protocol
  version, expiring after 3.5 s, with caps against floods. Hand-rolled bytes because `bytes_to_var` prints engine errors on
  garbage. `LocalHost` is the embedded server (`ENetEndpoint` + `ServerCore` on a COPY of the config it is given, which `main.gd` makes the fixed Play config, with `accept_client_mods` off; plus the
  announcer); `main.gd` drives it every frame (also with a menu open) and connects the host's OWN client to 127.0.0.1
  through the normal client path (`_start_client`; a local join never overwrites the saved Online address). Leaving, joining
  elsewhere or closing the app stops the host (the match ends). `ServerCore.run(delta)` is the shared frame driver (also
  used by `ServerMain`). A port that is taken is probed with a plain UDP bind first because a failing ENet listen prints an
  engine error. Android needs `ACCESS_WIFI_STATE` and `CHANGE_WIFI_MULTICAST_STATE` (export preset keys
  `permissions/access_wifi_state`, `permissions/change_wifi_multicast_state`, checked against Godot's Android export source):
  without the second the system drops received broadcasts; Godot takes the MulticastLock when a socket calls
  `set_broadcast_enabled(true)`. Facts for a later iOS port: unicast UDP (joining by code) needs only the Local Network
  prompt (`NSLocalNetworkUsageDescription`); sending or receiving broadcast or multicast needs Apple's
  `com.apple.developer.networking.multicast` entitlement (to be requested from Apple) or Bonjour with a declared service type
  through a native plugin; an app cannot switch the hotspot on (iOS: not at all; Android: only a local-only hotspot with a
  random name and password); broadcast from the hotspot phone itself is unreliable on some Android devices, hence the code;
  a backgrounded or closed host app ends the match. Not verified on real devices yet (broadcast on real Wi-Fi, the hotspot case).
- **Rejoin (version 0.6.0, protocol version 5):** each install has a random token (`NetStore.token()`, 32 hex characters, saved in `user://online.json` next to the address and the last Play game; `NetStore.path` is overridable for tests). `ClientCore.token` (a random one by default, `main.gd` sets the install's) goes in `[T_HELLO, VERSION, token]`; the server drops a hello whose token is not a String of 8..64 characters of 0-9a-f (`NetProto.valid_token`). `ServerCore.Slot` has `token` and `away`. A player who leaves or times out while `match_locked()` and in the roster is NOT removed: `away = true`, peer -1, the sim player stays enabled and standing (empty input, never a bot's), keeps points and roster place; `away_slots()` lists them. All away slots are freed when the phase becomes MATCH_OVER or OFF. In `_on_hello` the token lookup comes BEFORE the "started" refusal: a returning token gets its slot back (also a take-over when the server still has the old peer: old peer disconnected, erased from `_peer_slot` without the leave logic); a new token during a match is still refused. `ClientCore` fails with "lost" after `LOST_TIMEOUT` (3 s of `poll(dt)` time) without a snapshot while ONLINE, and an ENet disconnect while ONLINE is "lost" too ("closed" stays for leaving on purpose). `main.gd`, Play joiner only (`local_host == null`, not Training): a "lost"/"timeout"/"closed" failure in COUNTDOWN/PLAY/RESULT (and SHOP since step 6) starts `_begin_reconnect` (stays on GAME with the frozen last state, `MatchOverlay.reconnect_panel` "Reconnecting …", a new `_start_client` to the same host/port every `RECONNECT_EVERY` 1.5 s for `RECONNECT_TIME` 20 s; "started"/"full"/"version" ends it at once; failing ends in the main menu with "Connection lost"; the Main menu button cancels it). The joined Play game (`_joined`) is stored as `_last_game` (memory and `NetStore`) while a match runs and cleared at MATCH_OVER, on Main menu, Solo/Training or any failed Rejoin (refused or host unreachable: the automatic reconnect already covered short hiccups, so a dead game must not keep its button); the Play lobby shows a "Rejoin" button (`PlayLobby.rejoin_btn`) while one is stored and the device is not connected/hosting; it joins through the normal path and the server's answer decides. Not verified on real devices; a host that leaves ends the match for everybody as before (the host's own client has no reconnect).
- **Menus, Play and Training (version 0.6.0):** `game/main.gd` has three screens (`Screen.MENU`, `LOBBY`, `GAME`); the app starts on
  the main menu over the dimmed arena and the offline sim ticks only in `GAME` (and not while the tuning menu or the pause
  panel is open; online it never waits). **Rule: Play never sees tuned values.** `train_cfg` is the tuned config
  (`TuningStore`, edited by `TuningMenu`, used by Training and the Online page); `play_cfg = _make_play_cfg()` is a fresh
  `Config.new()` with only `character` copied from the saved one, `bot_mode` ACTIVE and no modifier levels, made anew for every
  Play game / local host / join. The fixed values go to `LocalHost.start`; `ServerCore.accept_client_mods` (default true, so
  `--server` and the Online tab behave as before) is set false by `LocalHost`, so a client's `T_MODS` is ignored. Files in
  `game/ui/`: `UiKit` (static helpers: colour constants of the mockup, the shared cached `Theme` with button variations
  Main/Paper/Dark/Quiet and panels Paper/Ink, `title` with offset print shadow, `eyebrow`, `backdrop` = dim + blur shader reading
  `hint_screen_texture`; menu screens set `root.theme = UiKit.theme()`, the old `TuningMenu` and `Hud` do not use it), `MainMenu`
  (also Settings page and the update banner, which no longer lives in the HUD), `PlayLobby` (mode card, figure choice with
  `FigurePreview` drawn with default sizes, Solo, Together; it edits only `character` of the saved config and saves it at once),
  `PauseMenu`. The HUD has `play_mode` (only a pause button drawn as two bars). The pause button / Escape / Android back
  (`NOTIFICATION_WM_GO_BACK_REQUEST`, `application/config/quit_on_go_back=false`): in a Play game the pause panel (Resume /
  Main menu), in Training the tuning menu (which has a Main menu button), in the lobby back, in the main menu leave Settings
  or quit (`main.quit_hook` replaces the quit in tests). `Main menu` ends any session (`_end_session`); a Play session that
  ends by itself (host left, connection lost) returns to the main menu (`_leave_online`). Connection status texts are one English text each in `main.gd` `STATUS` (shown on the Online page of Training and in the lobby). Fonts (`game/ui/fonts/`): Unbounded and
  Rubik, variable TTFs from github.com/google/fonts, both SIL Open Font License 1.1 (licence texts next to the fonts; keep them
  when fonts are updated); weights through `FontVariation` (`UiKit.font`). The UI was written without being able to look at it
  (no display here): spacing and sizes need a look on the phone. **Name:** `application/config/name` and the export preset
  `package/name` are "Spinback Rumble"; `package/unique_name` stays `io.slicendice.prototype` (a new id would be a separate app
  and the testers would lose their data). On PC Godot derives the `user://` folder from the project name, so the saved
  Training values of the old name ("Slice n Dice (Prototype)") are not found any more (Android is not affected); copying
  `tuning.json` over is enough. `use_custom_user_dir` was not used: Godot puts a custom dir directly under the data path
  (not under `godot/app_userdata/`), so it would not match the old folder on every platform.
- **Look (toy figures, playroom):** all in `game/view`, view only. No UI during a round (UI only between rounds; information lives in the world; exceptions: the countdown and, since 2026-11-17, the markers above the heads in `game/view/overhead_view.gd`: modifier icons at round start, a "YOU" tag at the own figure, the zone countdown number; screen-space labels placed with `Camera3D.unproject_position` at `HEAD_RADII` player radii above the floor; the decisions are static functions tested in `tests/test_view.gd`; look not checked on a screen) and the UI style (flat, one tomato-red accent, yellow price tags, fonts Unbounded and Rubik): see `docs/PLAN.md` (sections 5 and 6) and `docs/ui-mockup.html`. `toy_kit.gd`: the shared materials (glossy
  plastic with clearcoat and rim, plush, wood) and unit meshes; share them, do not create materials per figure.
  `toy_figure.gd`: builds the four figures (sizes in player radii, +z is the front) and applies the pose;
  `toy_pose.gd`: pure "sim state -> pose targets" plus the springs (fixed sub-steps); `toy_motion.gd`: follows one
  player in the sim the view draws it from (online the others come from the display sim) and notices throw,
  catch, dash end, death, respawn. `playroom.gd`: floor, fence, blocks, crate, box of the arena; arena geometry
  itself is in `game/sim/config.gd`. Which toy a slot gets: `ArenaView.FIGURE_KINDS`. To add a figure: a new
  `ToyPose.Kind` with its `CYCLE` entry and gait flavour, a `_build_*` function in `toy_figure.gd` that creates at
  least the six standard pieces (Body first, Head, ArmL, ArmR, FootL, FootR), its accent in `ACCENTS` and name in
  `NAMES`; `tests/test_view.gd` then checks it builds and fits the hit circle (body shell and `solid_reach()` of body and head: 0.9 to 1.3 player radii, the hit circle is the same for every figure). The standard pieces may be empty: the imp, the top, the roly-poly doll and the die have no visible feet (a test checks it), the duck's FootL/FootR carry its wheels (turned by the walk phase), the dino's hinged UPPER jaw (node "Jaw" = skull with the eyes, snout and upper teeth; the lower jaw with tongue and teeth is fixed to the Head piece; it opens upward, towards the camera, with the `JAW` pose channel) and the doll's rocking (`TILT_F`/`TILT_S`, underdamped springs) are pose channels in `toy_pose.gd`; the top's base turns with `ToyMotion.spin`. The die really rolls: all its cube visuals hang on the node `_cube` (child of Body); `ToyMotion.tumble` (a Basis in the figure's frame) is rotated from the drawn movement of every frame (one side length = a quarter turn), eases back to the identity (face to the front, with a small hop, `die_hop()`) when it stands, is stunned or spawns, and `die_height()` keeps the cube on the floor; the pose gives the die no lean, roll or twist. **Held yo-yo:** `ArenaView.drawn_head_r` draws a held head at NORMAL size (`Config.head_radius` x `HELD_SCALE`) and a thrown one at its real size (Big Chunk), eased over `GROW_TIME` (`grow_step`, state `_grow`, view only); `ToyFigure.hand_side(head_index, head_count)` gives the hand (+1 right = the yo-yo arm `_paw`, -1 left = `_paw_l` on `ArmL`; with two heads head 0 right, head 1 left; `left_hold` mirrors the left arm onto the right one's pose). The 3D meshes of a figure count 15..58 including the shadow, colour ring, stars and ghosts (8); the dino is the richest. `rounded_box()` is the only hand-built mesh: Godot's front faces are clockwise from outside, a test compares its winding with `BoxMesh`. **Screenshots cannot be made on the
  owner's Linux machine:** no X server, no Xvfb, no GL/EGL or Vulkan libraries (Godot's x11 and wayland drivers fail
  on missing `libXcursor` / `libwayland-client`; headless only has the dummy renderer). The look is checked on the
  phone; rendering in CI (Xvfb with Mesa on a GitHub runner) would be an option.
- **Toy train:** a moving hazard in the simulation (`Sim._step_train`, geometry in `game/sim/train_track.gd`: a rounded rectangle around the arena centre, scaled with the arena; speed `Config.train_speed`, default 5.7, 0 = off). It kills players with `_kill(victim, null)` (event `killer: -1`, `cause: "train"`, no kill credit), shoves the crate; its cars are solid for yo-yo heads like the crate (`Sim._push_train` in `_resolve_head` and `_sweep_retract` when `pass_level < 2`; a head lying OUT is shoved aside in `_step_train` and can kill that way), while strings, wires and shards still pass over it; its position is ordinary state. Tests switch it off in `mk()` (test_sim) and `make_rig()` (test_net, `with_train` turns it on) because the client's world clock follows the server's, so a client with a moving train is never equal to a purely local sim. When the arena or the obstacles change, the geometry checks at the end of `_train_tests` (clearance to obstacles, walls, spawns, the gap around the centre block) must still hold.
- **Maps (version 0.10.0; layout of map 0 since 0.11.0, protocol version 10; layout of map 1 since 0.12.0, protocol version 11; layout of map 2 since 0.13.0, protocol version 12):** six maps (`MapDef.Id`: TRAIN = the old playroom, BELTS, LAVA, BOUNCE, MAGNETS, PIGGY; `Config.MAP_COUNT`, must equal `MapDef.NAMES.size()`), each with a twist. Design and numbers: `docs/maps.md`. Where things live: `game/sim/map_def.gd` (`MapDef`: layout data per map index, every twist number, pure helper functions), the section "maps" at the end of `game/sim/sim.gd` (`_step_map` and the rules: belts, lava, pads, magnets, pig; `set_map`, `_build_statics`), `game/input/bot.gd` (what bots do about the twists), `game/view/playroom.gd` and `game/view/map_props.gd` (the look). State in the snapshot: `Sim.map_id`, `map_t` (the twist clock), `lava_cells`, `lava_wave`, `pig_coins`, `pig_t`, `SimPlayer.air_*`, `MatchMode.bonus` (coins a map paid, e.g. the pig; part of `coin_parts` and the result text "piggy bank N"), and the rotation bag. **The map is chosen only in Training** (the "Map" selector on the values page of the tuning menu, saved as `Config.map` like `character`, not reset by Reset). **Play never uses it:** `main._make_play_cfg` sets `Config.map = Config.MAP_ROTATE` (-1), so Solo, hosting and joining (the value reaches joiners in `T_WELCOME`) ROTATE: `Sim.start_match` empties `MatchMode.map_bag`, `Sim._start_round` takes the next map from `Sim._next_rotation_map` (a bag of ALL maps shuffled with the sim's rng, each map once before any repeat, reshuffled when used up, the first map of a new shuffle is never the one just played) and calls `set_map`. Free play (phase OFF, e.g. the hosted lobby before Start match) uses map 0 under rotation. Training and `--server` use their fixed map and never rotate. There is no lobby picker. `Config.from_dict` accepts -1..MAP_COUNT-1, anything else becomes 0. To add a map: raise `MAP_COUNT`, add a name to `NAMES`, entries to every per-map array in `MapDef` (OBSTACLES, SPAWNS (8), ZONE_SPOTS (4 areas of ARENA_SIZE / 4), CRATE_STARTS, BOX_POSITIONS, SPECIAL_OBSTACLES, HINTS), a new `Id`, its twist in `_step_map`, its look in `Playroom` / `MapProps`; `tests/test_sim.gd` `_map_geometry` then checks the geometry and the bot/determinism tests run on it automatically; add a test and a sabotage entry for the twist. Traps: the chest (crate) starts on the belt of Assembly Line and pushes a test player, so twist tests move it away (`map_sim(..., far_crate)`); a test that runs more rounds than `target` ends the match; changing the maps changes the snapshot, so `NetProto.VERSION` must go up. Looked at on still pictures only, not in motion or on a phone.
- **Map 0 floor plan (step A0, version 0.11.0, protocol version 10):** `Config.OBSTACLES` has 11 walls, point-symmetric: the centre block with a wall on each side (a pinwheel inside the track loop), four walls from the top and bottom walls towards the track (x 9.0 and 22.2, 4.2 m long) and four walls from the left and right walls (6.4 m long, y 4.2 and 9.4) that close the side rooms off from the corner rooms. Spawns: four corner rooms, two side rooms, two in the top and bottom corridors. Tests that need OPEN floor with hard-coded positions: `tests/test_sim.gd` `mk()` already strips the obstacles; `tests/test_net.gd` does it with `open_arena()` (called by `warm_up`, `interp_setup`), which keeps only the outer walls. A new test that walks across map 0 either does the same or uses a position on free floor (`godot --headless --path game -s ../tools/map_ascii.gd -- 0`).
- **Map 1 floor plan (step A1, version 0.12.0, protocol version 11):** `MapDef.OBSTACLES[1]` has 12 walls, point-symmetric: two dividing walls at x 9..10 and 22..23 (each in three pieces: a 2.6 m belt opening where the belt crosses it, a 2.4 m walking door at the end away from the belt), four horizontal covers (0..6.4 and 0..5.6 wide, from the left and right walls, under/over the belt's outer runs; they also hide the three starts of each side part from each other) and two short walls at the vertical belt run on opposite sides. Spawns: three per side part, two in the middle off the belt; zone areas moved off the walls (left x 0.8, y 5.8 and 10.4). `_map_geometry` checks the belt rules; `_assembly_plan_tests` (symmetry, no wall on the belt, openings as wide as the belt). Tests that need open floor on map 1 use stripped arenas like map 0.
- **Map 2 floor plan (step A2, version 0.13.0, protocol version 12):** `MapDef.OBSTACLES[2]` has 12 walls, point-symmetric: a windmill of four bars (1.0 m thick, two long and two short, open at two opposite corners) around a 2 m courtyard at the centre and a small room with a 2 m way out in each corner. Walls next to a zone area sit flush against it (0.4 m off the mat seam); no wall closes more than half the seam inside a mat pair (`_lava_plan_tests`). Zone areas: top-middle-right, bottom-middle-left, left, right. `_lava_escape_tests` checks, for 12 seeds and 8 waves, that every free spot of a marked mat has a safe mat within speed x `LAVA_WARN` of walking on the NavGrid; `Bot._lava_steer` walks the NavGrid path (`_steer_point`). Trap: two 0.8 m walls that touch can overlap by float32 rounding and fail the overlap rule; use sizes whose sums are exact (the 1.0 m bars) or leave a gap. Tests with hard-coded positions on map 2: keep them off the walls (`godot --headless --path game -s ../tools/map_ascii.gd -- 2`).
- **Map 3 floor plan (step A3, protocol version 13):** `MapDef.OBSTACLES[3]` has 11 walls, mirror-symmetric about x = 16 (not point-symmetric): three long walls (1.0 m thick at x 8.5, 15.5, 22.5) divide the room into four strips, each with ONE 4.0 m walking door (left wall top, middle wall bottom, right wall top), plus short covers inside the strips. `MapDef.PADS`: every strip has one trampoline and one landing spot (S1 to S2, S2 to S4, S4 to S3, S3 to S1), landing spots have the stomp radius plus a player of free floor and are never in a doorway, no pad within 2 m of a spawn (`_bounce_plan_tests`). Zone areas: bottom of the two outer strips, top across the two upper doors. Bot: `_pad_goal` (Bounce House only) takes a trampoline when it is close on foot, not a bad idea (`_pad_bad`) and saves `BOT_PAD_GAIN` metres of walking (uses `NavGrid.path_length`). Tests with hard-coded positions on map 3: keep them off the walls (`godot --headless --path game -s ../tools/map_ascii.gd -- 3`).
- **Map 4 floor plan (step A4, version 0.13.0, protocol version 14):** `MapDef.OBSTACLES[4]` has 17 obstacles, point-symmetric, the two magnet blocks first, the long middle wall (2) third: per magnet an outer wall and a wall above and below (3.0 m, open corners; the middle wall is the fourth side), a stem from the top or bottom wall to each of those horizontal walls (closes the lane towards the end room), a 3.0 m stem from the top and bottom wall to the middle wall (2.0 m doors), and a cross wall near each short side. The passage rule counts the magnet blocks, so no wall stands closer than 2.0 m to one. Zone areas: the four corners of the end rooms. Tests that need open floor on map 4 strip the obstacles (`s.statics.resize(s.wall_count)`), as the magnet bending tests do. Trap: a rectangle that should end exactly on the outer wall can end 1 ulp beyond it (`Rect2(8.6, 11.6, 0.8, 2.8)`); the bottom stems use the height 2.799999.
- **Map 5 floor plan (step A5, version 0.13.0, protocol version 15):** `MapDef.OBSTACLES[5]` has 13 obstacles, point-symmetric, the pig first: a ring of eight 1.0 m thick pieces round an open 8 x 6.4 m square (four L-shaped corners; entrances 2.5 m wide top and bottom, 2.4 m left and right), two aisle walls (x 5 and 26, 6 m long) and a 3 m wall from each short wall that splits the aisle (without them no eight starts are hidden from each other). From outside the ring the pig can be hit only through an entrance (`_piggy_plan_tests`). `Bot._pig_wanted` needs a clear line to the pig. Chest and present sit on the centre line outside the ring (1.6 m from the outer wall); spawns are kept 3 m from them. Zone areas: the four corners as before. The existing pig tests throw from (8.5, 7.2), straight through the left entrance. Step A (all six floor plans) is done; the zone times ("After all six" in `docs/map-rework.md`) are still open and are the owners' decision.
- **Map rework, step F foundations (`docs/map-rework.md`):** `NavGrid` (`game/sim/nav_grid.gd`, pure, derived, never in the snapshot): 0.8 m cells, the sim's `statics` grown by the player radius, breadth-first search over 8 neighbours without cutting corners, `line_clear` (segment against the grown statics), cached per map id by `NavGrid.for_sim` (rebuilt when the statics or the radius differ). The chest is not in it; belts, pads and lava are floor. Bots (`Bot._steer_point`) walk straight with a clear line, otherwise to the farthest clear waypoint of the path (searched every 0.2 s), snap wander targets onto free floor, and throw only at the nearest enemy they have a clear line to (`THROW_CLEARANCE`). Spawn rule (`Sim._next_spawn`, used by `_start_round`): the first point is drawn with the sim's rng, every further player gets the free point farthest from all given ones (ties: lowest index); `_respawn` and free play are unchanged. `MapDef.REWORKED` (`[0, 1, 2]` since step A2) lists the maps whose floor plan is rebuilt; the strict rules of `_map_geometry` (10 to 18 obstacles, spawns 6 m apart and out of sight under 14 m, 1.5 m free floor, the 2.0 m passage rule) run only for them. The connectivity rule (spawns, zone centres, chest, present reachable on the NavGrid) runs for every map; the 2.0 m passage rule FAILS on the old layouts of maps 0 to 4 (blocks closer than 2.0 m to a wall or to each other), so it is behind `REWORKED` too. `tools/map_ascii.gd` prints a map as text (`godot --headless --path game -s ../tools/map_ascii.gd -- [id]`). `Playroom.block_pieces` draws an obstacle longer than 1.5 times its short side as a row of equal near-square blocks. No protocol change: no snapshot state and no layout changed.
- **Game modes and Teams (version 0.15.0, protocol version 16; foundation and sim; the lobby, overlay and view are in the next entry):** `Config.GameMode` { FFA, TEAMS, POTATO } in `Config.game_mode` (saved with the settings like `target_score`, not reset, copied by `main._make_play_cfg`, which also makes the player count even for Teams through `TeamStanding.even_count`; joiners get it in `T_WELCOME` with `cfg.to_dict()`). `MatchMode.create(kind)` builds the rules object (`LastStanding`, `TeamStanding` in `game/sim/team_standing.gd`; POTATO is `HotPotato`, see its entry); `Sim._init(cfg, seed, mode_kind := -1)` uses it, and **client and server must build the same class because `StateIO.restore` keeps the existing `mode` instance** (the client builds it from the welcome's config). Training passes `Config.GameMode.FFA` to `Sim.new` (`main._new_sim`), `--server` uses `Config.new()`. Hooks on `MatchMode` (FFA defaults = the old behaviour): `harms(a, v)`, `scores(i, scorer)`, `uses_zone()`, `step(sim, dt)` (called every PLAY tick), `allowed_colors(i)`, `survivor_label()`, `is_team_mode()` / `team_of(i)`, `scored(i)` / `won(i)`. **Every harm by an attacker goes through `Sim._hit(victim, attacker)`** (head, body, blast, shard, lethal wire, stomp; the stun wire and head-vs-head collisions test `harms` directly); deaths without a killer (train, zone, lava, own blast) stay `_kill(p, null, cause)`. The scratch flag that used to be called `_hit` is now `_head_hit`. Teams: `TeamStanding.team` (per slot, `i % 2` at the start, snapshot state; 0 Red, 1 Blue), `Sim.swap_team(i, j)` (exchanges teams AND colours, so team sizes and unique colours hold), `Sim.can_start()` (used by `start_match` and the lobby's Start button: FFA two players, Teams the same number on each team, at least one), `team_points(t)` is computed. **`last_scorer`, `winner` and `round_scorer` hold a TEAM index in Teams, a slot in FFA**: ask `mode.scored(i)` / `mode.won(i)`; `MatchOverlay` already does (and names teams "Red"/"Blue"). Colour halves `TeamStanding.COLOR_HALVES` (Red 0 3 5 6 = pink, orange, yellow, red; Blue 1 2 4 7 = cyan, lime, purple, blue; lime is the one cool-ish stretch). Bots skip players for whom `not harms(me, o)` (`_nearest_enemy`, `_nearest_visible_enemy`, `_pad_bad`). Net: `T_TEAM` (`[T_TEAM]`, `ClientCore.send_team()`), `ServerCore.request_team_switch(i)` (only in OFF / MATCH_OVER and Teams, swaps with the first non-human seat of the other team, otherwise refused and counted in `dropped_packets`), joiners are placed on the team with fewer humans (`_team_with_fewer_humans`). `LanBeacon` packet is 11 bytes, magic "SND2", the last byte is the game mode (`found` entries have `"mode"`; `LocalHost` announces it); the lobby text ("Teams 3v3") is built by `PlayLobby.found_text`. Tests: `_team_tests` in `tests/test_sim.gd`, `test_teams_net` in `tests/test_net.gd`, sabotage entries "4 teams: ..." and "8 teams: ...". Traps: a new attack that hurts players must call `_hit`, not `_kill`; a rig that needs open floor strips the obstacles (`team_sim` does). Not covered by a test: the beacon announcement of `LocalHost`, `main.gd` passing FFA for Training.
- **Hot Potato (feature/hot-potato, protocol version 17):** `HotPotato` (`game/sim/hot_potato.gd`, extends `LastStanding`, returned by `MatchMode.create(POTATO)`; reachable by `Config.game_mode = POTATO` until the lobby has the button). All numbers are constants there (`FUSE_BASE` 8, `FUSE_PER_PLAYER` 2, `BOMB_GAP` 2, `TAGBACK_TIME` 1.5, `CARRIER_SPEED` 1.15, `POTATO_STUN` 0.6, `BLINK_TIME` 3). State (snapshot): `bomb_holder`, `bomb_t`, `bomb_fuse`, `bomb_gap`, `bomb_from`, `tagback_t`. New `MatchMode` hooks (defaults = old behaviour): `on_hit(sim, a, v)` (asked by `Sim._hit`: true = the normal kill proceeds; Hot Potato passes the bomb or stuns and returns false in PLAY, outside PLAY it kills as in Last Standing), `own_blast_kills()` (false here; `Sim._explode` skips the self kill), `speed_mult(i)` (applied to the walking speed in `_step_player`, not to dashes), `uses_zone()` (false: `Sim._step_zone` is skipped, `zone_active()` is false so the overhead zone number shows nothing). Rules run in `HotPotato.step` (PLAY, before the round end check); the bomb state is reset in `begin_round_coins` (called at every round start). Events `bomb_pass` (from, to) and `bomb_explode` (pos, victim); the explosion kill is `_kill(carrier, last passer or null, "bomb")` (the kill event has no "cause" when there is a passer, as for every kill with credit). The passer's own hit on the new carrier during the lock does nothing (otherwise his yo-yo, still on the victim, would stun him in the next tick). Bots (`game/input/bot.gd`, `_potato_*`): the carrier hunts (`_nearest_potato_prey` skips the lock), the others flee within 7 m (`_flee_spot`, NavGrid line checks) and throw at the carrier or rarely at others. View: `game/view/bomb_view.gd` (`BombView`, one bomb node per slot, shown over the slot that carries it in the sim THAT figure is drawn from; static `holder`, `fuse_fraction`, `fuse_length`, `blink_red(bomb_t)` are the tested decisions; the blink is a function of `bomb_t` alone) used by `ArenaView.render`; `ArenaView.handle_event` draws `bomb_pass` and `bomb_explode` (the old explosion picture). Tests: `_potato_tests`, `_potato_bot_tests` in `tests/test_sim.gd`, `test_potato_net` in `tests/test_net.gd`, `test_bomb_view` in `tests/test_view.gd`, sabotage entries "7 potato ...", "8 potato ...", "0 potato ...". Traps: a mode that must not kill with attacks has to be asked through `_hit` (a new attack calls `_hit`, never `_kill`); `potato_sim()` in the tests uses map 0 stripped of obstacles; a net rig needs four human clients (no bots, who would pass the bomb) to keep the bomb still. Not done: a look at the bomb on a real screen.
- **Mode UI (feature/mode-lobby, version 0.15.0):** `PlayLobby` mode card: a row of three buttons `mode_buttons` (`MODE_NAMES`: "Free-for-all" / "Teams" / "Hot Potato", index = `Config.GameMode`, font 15), saved as `Config.game_mode` like `target_score` (signal `mode_chosen`); the heading "Last Standing" is gone. Targets are 10/15/20 in every mode. In Teams the Players row shows only the buttons for 4, 6 and 8, written 2v2 / 3v3 / 4v4 (`player_buttons` keeps its seven buttons, the others are hidden; the saved `player_count` is not touched, `_mark_players` shows `TeamStanding.even_count` of it, `main._make_play_cfg` snaps it). **While hosting or connected the mode, players and target buttons are disabled and their handlers do nothing; a joiner sees the HOST's values** (`set_host_cfg(client.cfg)`, set by `main._refresh_start` every frame in the lobby; `_shown_cfg()` picks them; the joiner's own saved values are not touched). Hosting/connected in Teams: a row with `team_label` ("Red 2 · Blue 1 · You: Red") and `switch_btn` ("Switch team", signal `switch_team_requested`, `main._switch_team` -> `ClientCore.send_team`; enabled only in phase OFF / MATCH_OVER, as the server takes it), fed by `set_teams(red, blue, mine, can_switch)` from the client's sim (all enabled players by `team_of`); the Start button text is "Teams are uneven" when it is disabled over uneven teams (`set_start` follows `Sim.can_start()`). Found games: `PlayLobby.found_text` adds " – Teams 3v3" (room size / 2) or " – Hot Potato" from the beacon's `"mode"`, nothing for free for all. Solo: `main.start_solo` builds the sim from `play_cfg` (so the mode); in Teams you are slot 0 = Red and the bots fill, there is no switch button. `MatchOverlay`: in Teams `_team_board` puts two columns Red | Blue into `rows_box` (node "TeamBoard"; each column: a header label in `ArenaView.TEAM_COLORS`, `ScorePips` of `team_points(t)`, then the member rows from `make_member_row`: swatch in the personal colour, name, coin tag); texts from the static `round_text` / `match_over_text` ("Your team scores!", "Red team scores!", "Your team wins the match!", "Blue team wins the match!"; Hot Potato: "<name> survived the bombs!", "You survived the bombs!"). **Team ring:** `ArenaView.TEAM_COLORS` (clear red and blue) colour ONLY the floor ring under the figure in Teams (`ArenaView.ring_color_of`, `ToyFigure(kind, colour, ring_colour)` / `ring_color`); yo-yo, string, throw arrow, ghosts, confetti and the scoreboard swatch keep the personal colour. `ArenaView` remembers the ring colour per player (`_shown_ring`) and rebuilds the figure when it changes (a team switch). **Overhead markers and the bomb:** `OverheadView.anchor_radii(src, i)` is `HEAD_RADII` normally and `BombView.TOP_RADII` (+0.2) for the carrier, so YOU, the icons and the zone number stack above the bomb. Tests: `_lobby_mode_tests` in `tests/test_sim.gd`; `test_main_modes`, `test_mode_overlay`, the mode loop in `test_lobby_fits` and the Teams board in `test_screens_fit` in `tests/test_net.gd`; `test_team_ring` and the marker checks of `test_bomb_view` in `tests/test_view.gd`; sabotage entries "7 mode ...", "8 mode ...", "0 mode ...". Not checked: the look on a real screen (the three mode buttons at font 15 in the first column, the stacked markers over the bomb, the red/blue rings).
- **Up to eight players (feature/eight-players):** `Config.NUM_PLAYERS` (8) is the number of SLOTS in the sim, `MatchMode`, `ServerCore` and `ClientCore` (snapshots always carry eight); `Config.player_count` (2..8, default 4, `MIN_PLAYERS`/`DEFAULT_PLAYERS`) is how many play. It is saved with the settings like `target_score` (clamped on load, not reset by Reset), chosen in the Play lobby (`PlayLobby.player_buttons`, row "Players" in the mode card) and copied into `play_cfg` by `main._make_play_cfg`. `Sim.new` enables only the first `player_count` slots (the others are switched on by whoever fills them); `ServerCore` with bots enables `player_count` slots and lets joiners take only slots below `player_count` (a joining human replaces a bot, the total stays); `LocalHost` announces `player_count` as the room size; Solo = you plus `player_count - 1` bots (`main._apply_bot_mode`). Training and `--server` stay at four (`Config.TRAINING_PLAYERS`, default `player_count` 4). The "Server is full" text no longer names a number (the joiner does not know the host's room size). Not checked on a phone: performance and look with eight figures.
- **No scrolling (fix/lobby-fits-screen):** the owner wants no scroll container in the menus, the lobby and the in-match panels. The base screen is 1280 x 576 and `stretch/aspect = "expand"` makes every other screen at least that big, so every screen must fit 1280 x 576. The Play lobby is three columns (mode card + Solo | figure | Together); while hosting or connected its joining half (hint, games found, code field) is hidden, the games list shows at most `PlayLobby.MAX_FOUND` (2), and `UiKit.compact` / `UiKit.tighten` make buttons and panels smaller. `test_lobby_fits` (lobby, several window shapes, fullest states) and `test_screens_fit` (Settings, pause, round/match-over panel with eight rows, shop) in `tests/test_net.gd` check the combined minimum size and that no control leaves the screen, and that there is no `ScrollContainer`. The Training tuning menu (`game/view/tuning_menu.gd`, developer sandbox) still scrolls on purpose. Look not checked on a real screen.
- **Throw arrow (feature/throw-arrow, 0.16.0):** while charging, `ArenaView` draws no flight path or landing mark any more, only a small flat triangle per player (`_aim_arrows`, one shared `ArrayMesh`, material per player recoloured with the colour) next to the figure: `ArenaView.aim_arrow(p, cfg, pos)` (static, tested in `test_aim_arrow`) gives position and angle, along `aim_dir`, `ARROW_NEAR` 1.9 to `ARROW_FAR` 2.6 player radii out with `charge_t / charge_time` (the colour ring is 1.3), size `ARROW_SIZE` 0.6 radii. `Sim.aim_path` stays (tests, map docs) but the view no longer calls it. Look not checked on a screen.
- **Figure choice:** `SimPlayer.skin` says which toy figure a player is drawn as (presentation only: the simulation never reads it, but it is in the snapshot). `Config.SKIN_COUNT` must equal `ToyFigure.NAMES.size()` (a test checks it): when a figure is added, raise it. The human's choice is `Config.character` (saved with the settings, not reset by "Reset"; in the Play lobby). Offline `main.gd` gives player 0 the choice and bot i `character + i`; online the client sends `NetProto.T_SKIN` and the server validates the range. `ClientCore` keeps its own choice on top of snapshots. **Colour choice (protocol version 8):** `SimPlayer.color` (0..`Config.COLOR_COUNT`-1, default the slot index; presentation only, in the snapshot) picks one of the eight `ArenaView.PLAYER_COLORS` (a test checks the counts agree) and is used everywhere the player is identified: yo-yo, string, throw arrow, bursts, the scoreboard swatch (`ArenaView.color_of(player)`), the HUD labels and a flat ring on the floor around the figure (`ToyFigure` `ColorRing`, ghosts and confetti too). The figure body keeps its own fixed colour (`ToyFigure.BODY_COLORS`, one per `NAMES` entry; the duck's beak accent is orange so it differs from its yellow body). Colours of ENABLED players are unique: `Sim.set_color(i, k)` wraps k and takes the next free colour on a collision, `set_player_enabled(i, true)` resolves a clash too, `Sim.assign_colors(k)` is the offline layout (player 0 gets k, the others the rest in order). The human's choice is `Config.player_color` (saved with the settings like `character`, clamped on load, not reset; swatch row in the Play lobby; copied into `play_cfg`). Online the client sends `NetProto.T_COLOR` (validated, invalid dropped and counted) and, UNLIKE skin, the server's value wins: `ClientCore` keeps no wish on top of snapshots. `ArenaView` rebuilds a figure, the yo-yo heads and the throw arrow when a player's colour changes. Look not checked on a screen.
- **Rounds and points (step 3, version 0.6.0):** the match rules live in the sim: `Sim.mode` (`MatchMode` in `game/sim/match_mode.gd`: phase OFF / COUNTDOWN / PLAY / RESULT / MATCH_OVER, points, roster, target, last scorer; `LastStanding` = the rules), part of the snapshot. Phase OFF is free play (Training, `--server`, the warm-up lobby): respawns, no rounds. `Sim.start_match(target)` (needs 2 enabled players; also the rematch) starts it; a round that ends starts the next one after 4 s. `ServerCore.match_locked()` refuses new players (reason "started") during COUNTDOWN / PLAY / RESULT / SHOP; they may join in OFF and MATCH_OVER. The target (10/15/20) is `Config.target_score`, saved with the settings like `character` (not reset by Reset) and copied into `play_cfg` by `_make_play_cfg`; chosen in `PlayLobby` (`target_buttons`). Flow in `main.gd`: `start_solo` builds the sim and calls `sim.start_match`; hosting: the host's client and joiners stay on the LOBBY screen while the server's phase is OFF (Start match = `_start_hosted_match` -> `local_host.core.start_match(train_cfg.target_score)`, enabled with 2+ enabled players, bots included; a joiner sees "Waiting for the host to start") and switch to GAME as soon as the drawn sim's phase leaves OFF (a late joiner at MATCH_OVER goes straight to GAME). Training and the Online tab are unchanged (GAME at once, no match). `game/ui/match_overlay.gd` (`MatchOverlay`, updated every frame from `main._process`, Play only) reads the drawn sim: big 3-2-1 and "GO!" (0.6 s), the round result panel and the match-over panel (both appear 0.8 s after the last hit) with the scoreboard, Rematch (Solo and host: `_rematch`, same target) or "Waiting for the host", Main menu. The countdown is a deliberate exception to "No UI during a round". Offline bots get " (bot)" in the names, online nobody does. Rejoin: see the next entry. Not done: the shop, looked at on a real screen. The scoreboard shows each player's points as `ScorePips` (`game/ui/score_pips.gd`: `target` circles in groups of 5, newest pip pulses); a test keeps the panel with 8 players and target 20 inside the 1280x576 base viewport.
- **Shrinking zone (M3 step 4, version 0.7.0):** only in a match (phase PLAY clock; none in phase OFF). Fixed rules in `MatchMode` (`ZONE_FULL_TIME` 20 s, `ZONE_SHRINK_TIME` 30 s, `ZONE_DEATH_TIME` 3 s; not tunable `Config` vars, so Play never sees tuned values), the four final spots (ARENA_SIZE / 4, y = 0 is the top wall) in `Config.ZONE_SPOTS`. `Sim.zone_rect()` / `zone_active()`; state `mode.zone_t`, `mode.zone_spot` (drawn in `_start_round` from the saved rng) and `SimPlayer.zone_t`, all in the snapshot. A full timer kills through `_kill(p, null, "zone")` (no credit). Bots (`BOT_ZONE_MARGIN`) steer in. View: `game/view/zone_view.gd` (veil and edge line; materials from `ToyKit.overlay`). The time left outside the zone is a big red number above the head (`OverheadView`, owner decision 2026-11-17; the old fill ring is gone). Trap: a test that lets players stand still in a running match for 20+ s gets them killed by the zone (see the `zone_t = 0.0` line in `test_rejoin`). Geometry test: every spot is a free area (no obstacle, crate, box, train track). Look not checked (no display).
- **Coins (M3 step 5, version 0.7.0):** numbers in `game/sim/economy.gd` (`Economy`; fixed match rules, not `Config`). State per slot in `MatchMode` (`coins`, `earned`, `round_kills`, `leader_kills`, `underdog`, `leader`; snapshot state): `begin_round_coins` at round start, `note_kill` from `Sim._kill` (phase PLAY, credit only), `award_coins` in `_check_round_end` before the point is added; `coin_parts` is the breakdown the result panel shows (`MatchOverlay.coin_text`). A test pins the numbers to the plan: change both together.
- **Shop (M3 step 6, version 0.7.0, protocol version 7):** phase `MatchMode.Phase.SHOP` (after RESULT, not after the deciding round; `MatchMode.running()` = countdown, play, result, shop is what locks joining and allows reconnecting). Numbers in `Economy` (`SHOP_TIME`, `OFFERS`, `REROLL_PRICE`, `SLOTS`, bot timing); prices `Mods.PRICES`. State per slot in `MatchMode` (`owned`, `offers`, `locked`, `shop_ready`, `shop_seq`); commands `Sim.shop_buy/shop_reroll/shop_sell/shop_lock/shop_done` with the `shop_seq` counter against repeats; `ServerCore.apply_shop` for `NetProto.T_SHOP`; `ClientCore.send_shop`; `main._shop` routes the `ShopPanel` buttons (Solo into the sim, online to the server). **Rework 2026-11-16:** the build slots are the keys of `owned` in insertion order; selling removes a modifier with all copies for `floor(copies * price / 2)` (`MatchMode.sell_refund`; wire: `SHOP_SELL` with the index in `Mods.ORDER`); a per-offer lock (`locked`, toggled by `shop_lock`, wire `SHOP_LOCK`) keeps an offer through rerolls and into the next shop (`Sim._roll_offers`), buying or `start_match` clears it. Cards use `Mods.short(id)` (short texts; the long ones are for Training), `ModIcon` draws the icons, `ShopPanel` has no scrolling and a test checks its minimum size. **Rule: in a match (`phase != OFF`) the modifiers come only from `owned`:** `main._sync_mods`, `ClientCore` (on snapshots and on a change) and the server's `T_MODS` all skip `apply_mods` then; `start_match` clears the build. **Even odds (protocol version 18):** `Sim._roll_offers` draws every offer uniformly from ALL of `Mods.ORDER` (not only what `can_take`), so full slots or max-level mods still show up; the card says "Slots full – sell one" / "Max level" with Buy disabled, `shop_buy` and bots still check `can_take`, locked offers stay even when unbuyable. Tests that need the next round go through the shop: `next_round()` in `tests/test_sim.gd` marks everybody done.
- **Touch settings (M3 step 7, version 0.7.0):** `game/input/touch_settings.gd` (`TouchSettings`, pure data and geometry) is saved per device in `user://touch.json` (`TouchSettings.path` is overridable for tests; missing or damaged file = defaults, numbers clamped, parsed with `JSON.new().parse` so garbage prints no engine error). It is not part of `Config` and the tuning Reset does not touch it; Play and Training use it alike. `main.gd` loads one instance (`touch_settings`) and hands it to `InputRouter.touch` and `MainMenu.setup`, so a change in Settings acts at once. Fields: stick mode (Floating default / Fixed), `scale`, `opacity` (multiplier on the drawn alpha), `swap`, and `custom` places (relative 0..1, only for controls the player placed; defaults are the old pixel offsets / 1280x576, mirrored when swapped; `to_screen` clamps a whole control onto the screen). Swap mirrors defaults and, when toggled, custom places. Floating mode ignores stick places; the Dash button place is used in both modes. Fixed sticks take only touches within `GRAB` (1.5) radii and their centre does not follow the finger. `TouchLayoutEditor` (`game/ui/touch_layout_editor.gd`) works on a copy; Save writes, Cancel / Android back discards. The look and feel of the Settings page and the editor are not checked on a real screen.
- **Modifiers:** Modifier definitions (only Training's sandbox sets levels; Play has none until the shop exists), English texts and all their numbers live in `game/sim/mods.gd`.
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
  (now 0.15.0); a test checks that they agree. CI builds of branches use the committed version plus the suffix
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
  "Protecting `main`"). GitHub security settings (set by the owner, Nov 2026): Dependabot alerts on (with the dependency graph); secret scanning is not available for private repositories on the
  free plan; automatic dependency submission and AI scan off (Actions minutes and AI credits for little gain). A Dependabot alert is checked in a session before anything is changed.
- **Limits of the environment:** Cloud sessions (Claude Code on the web) cannot open the repository settings
  (rulesets, secrets, Pages); the owner does that on github.com. GitHub is reached through the GitHub MCP tools,
  not the `gh` CLI. Local sessions on the owner's Linux machine have git over HTTPS working.
