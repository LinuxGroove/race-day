# Race Day

A grand prix racing game for 1–8 players (and AI up to a 20-car grid), with split screen for two on one device that also joins LAN and online races, in Godot 4.7 with GDScript. The concept is idea 20 in [game-ideas](https://github.com/LinuxGroove/game-ideas/blob/main/ideas/20-race-day.md). Online play goes through the shared [game server](https://github.com/LinuxGroove/game-server); **read game-ideas' [online-addon.md](https://github.com/LinuxGroove/game-ideas/blob/main/online-addon.md) before touching networking, online or the shared add-on.**

## Commands

```sh
godot --headless --path . --import
godot --headless --path . tools/check_scripts.tscn                  # every script compiles
godot --headless --path . tests/run_tests.tscn -- --games=2         # unit tests, school runs and whole AI races
godot --headless --path . tests/run_tests.tscn -- --only=_test_knockout   # one test
godot --path . -- --quick --circuit=monte_pineta --laps=3           # straight into a Quick Race
godot --path . -- --tt --circuit=port_lumen                         # straight into Time Trial
CIRCUIT=hay_valley,cliffside RACE=1 godot --headless --path . -s tools/circuit_check.gd   # build, an AI lap, a pit stop and a race per layout
MAPS=/tmp/maps godot --headless --path . -s tools/circuit_maps.gd   # a map of every layout
ASSISTS=default godot --headless --path . tools/handling_check.tscn   # how often a clumsy driver spins, runs off or hits a wall
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots [only=greenfield]
```

Run the script check and the tests before every commit, and `tools/circuit_check.gd` with `RACE=1` after changing a circuit, the AI or the car. Headless runs reimport assets and rewrite many `*.glb.import` files and `icon.png.import`; revert those (`git checkout -- '*.import'`, `rm icon.png.import`) unless you meant to change them. Headless physics runs in real time, so tests that drive the race scene take a while; the race sim alone (`Race.step`) runs as fast as it can.

## Layout

| Path | What |
|---|---|
| `game/game_config.gd` | `GAME_ID`, `PROTOCOL`, player limits, `QUICK_MATCH_SIZE`, setting defaults (assists, comfort), input map, cameras |
| `game/race/` | `Race` (a session's rules with no nodes: start, laps, sectors, flags, penalties, pit stops, safety car, snapshots for rewind), `Teams` (teams, drivers, points), `Weather` |
| `game/car/` | `CarSim` (the car on the 120 Hz tick), `CarSpec`, `Tyres`, `CarView` (Kenney model, livery, wheels, cockpit and T-cam points) |
| `game/ai/` | `AiDriver`: the line's speeds scaled by pace, traffic, racecraft, mistakes, recovering from a spin |
| `game/track/` | `Track` (the road sampled every few metres: centre, width, banking, kerbs, run-off, pit lane, sectors, DRS), `TrackPlan` (pieces and landmarks), `Circuits` (every layout's plan and info), `ProvingGround`, `RacingLine` |
| `game/world/` | Scenery, lighting, sky and weather round each circuit |
| `game/play/` | `RaceScene`, `RaceCamera`, `PlayerDriver` (assists), `BrakingLine`, ghosts and lap references, `RacingSchool`, `RaceNet` |
| `game/audio/` | Engine sound (baked samples and synthesis), tyres, crowds, radio, music, and the voice budget |
| `game/ui/` | Title (every mode's page), lobby, HUD, pause menu with car setup, results, how to play, menu backdrop |
| `game/net/session.gd` | `Session` autoload: lobby, split-screen seats and transport for solo, LAN, online rooms and quick match |
| `game/net/online_server.gd` | Default game server; `SERVER_KEY` stays `defaultkey` in git |
| `game/progress.gd` | `Progress` autoload: championship and career seasons, upgrades, school medals, setups, best laps and ghosts |
| `addons/linuxgroove/` | Shared LinuxGroove add-on (settings, input and seats, theme, screen fitting, LAN, online, names) |
| `addons/com.heroiclabs.nakama/` | Vendored Nakama client with a local patch (see its `VENDORED.md`) |
| `tests/run_tests.gd` | Headless test runner; add checks with `check(ok, "what")` |
| `tools/` | Script checker, circuit check and maps, screenshots, engine baking, `version.sh`, `release.sh` |
| `docs/screenshots/` | A screenshot of every layout from every camera, and the menus (`--all` above writes them and the README index) |

## How the game is built

- **The sim has no nodes.** `Race` runs a session (practice, qualifying or the race) at `Race.DT` (1/120 s) from a seed, with `CarSim`s and `AiDriver`s, so tests and `circuit_check` run whole races headless. `RaceScene` only drives it, draws it and plays it. Car forward is `(sin yaw, cos yaw)`; models face +Z.
- **Circuits are code.** A layout is a `TrackPlan` of straights and corners (`straight()`, `left(deg, radius)`, `right()`, `TrackPlan.AUTO` straights that close the lap), heights, widths, kerbs, run-off, a pit lane and landmarks for the scenery; `reversed()` and `shortcut()` make second layouts. `Circuits._all()` holds each layout's info (venue, name, layout, round, theme, time of day, rain chance, laps, `length_km`, blurb). Main layouts' ids are the venue; second layouts add `_reverse`, `_club`, `_junior`, `_international`, `_short`, `_national` or `_oval`. `Circuits.calendar()` is the sixteen rounds in order.
- **Cars are the size they look.** `CarSim.BODIES` is each chassis's footprint (half width, nose, tail from the middle of its wheels), which barriers and car-to-car contact use; a test checks it covers the models, so update it when a chassis or its scale changes. Barriers stand where `Track.bar` says, for the cars and the scenery alike. `CarView` seats each tyre on `Track.ground_y` and only the body pitches and rolls.
- **No rubber-banding.** AI pace comes from the driver's skill and the difficulty (0–110) only. The racing line's speeds are worked out once per layout; the AI drives to them and reacts to the cars it's told about.
- **Assists** live in the `assists` settings section and `PlayerDriver` applies them; the Racing School overrides them per test. Steering help is on by default: it catches slides and keeps the lock to what the front tyres can use. The car itself understeers a little (more rear grip than front) so too much lock runs wide rather than spins; `tools/handling_check.tscn` measures how forgiving it is, so run it after changing the car or the assists.
- **Cameras are gentle on purpose** (Ken gets motion sick): level horizon, no shake or head bob, a soft chase spring that stays stable at low frame rates. Keep those defaults and keep comfort options in the settings.
- **Host-authoritative weekends.** Peer 1 runs `Race` and the AI. Each device drives its own players' cars and sends them (`_c_car`); the host sends cars, timing and events with `rpc_id` (`_h_*` in `RaceNet`). Split-screen players are seats of their device's peer, with actor id `peer * 4 + seat`.
- **One Session for every mode.** Solo, split screen, LAN, online rooms and quick match all run the same code. Follow the rules in online-addon.md: never attach the bridge's peer yourself, never send a second hello, no `await` between joining and setting `mode`.
- **Bump `PROTOCOL`** whenever any RPC's arguments or meaning change (including `RaceNet`'s timing state).
- **Online results** come from `Session.report_race` (host only, online rooms only, the race session only, seat 0 of each device only) to the server's `race-day.race_report`, which writes stats and the wins, weekly wins, podiums and poles boards. Time Trial laps go to `lap_<layout>` boards through `core.score_submit`. Changing either means changing `modules/src/games/race-day.ts` in game-server too, and deploying the server first. A new layout id needs adding there as well.
- **Play tests.** The shared add-on's `LGPlaytest` records a play test when the Play test recording setting is on (or with `-- --playtest`): a picture every few seconds, game events, frame times and controls, the player's notes (F8, or Note this moment in the pause menu) and a survey when they quit, all in one zip in `user://playtest/`. Game events go through `LGPlaytest.event()` and `moment()`; the round's own survey questions (and standard ones to skip) are `GameConfig.PLAYTEST`. Quit through `LGScenes.quit()` so the survey comes first.
- **Everything works offline.** No server, no network and online turned off must all still play.
- **Launch ping.** `game/main.gd` calls `LGLaunchPing.send(GameConfig.GAME_ID)` at startup: one anonymous request to the game server's `/launch` (game, random install id, version, OS, CPU) so the server counts every player, online or not. It's skipped headless, from source and with `DO_NOT_TRACK` set, and never blocks or retries.

## The shared add-on

`addons/linuxgroove/` and `addons/com.heroiclabs.nakama/` are copies shared with [Foam Frenzy](https://github.com/LinuxGroove/foam-frenzy), [Graveyard Hollow](https://github.com/LinuxGroove/LampLighters), [Tiptoe](https://github.com/LinuxGroove/tiptoe), [Joyride Junction](https://github.com/LinuxGroove/joyride-junction) and [Block Party: Skyway](https://github.com/LinuxGroove/block-party-skyway). Fix shared behaviour in the add-on, not with a workaround here, keep it game-agnostic, and port the change to the other games in the same piece of work. When the change affects how games should use the add-on, update online-addon.md in game-ideas too. Keep the `_disconnect_peer` and `_close` patch in `NakamaMultiplayerPeer.gd` when updating nakama-godot.

## Style

- Match the surrounding code: `##` doc comments on classes and non-obvious functions, short comments only where the reason isn't obvious.
- Connect signals with methods (or `bind`), not lambdas; a lambda on an autoload signal stays connected after its screen is freed.
- Build pieces so tests can drive them without a network or a scene change: `Race` needs no nodes, and UI panels build without a race.
- Controller first: everything works with a pad, and the keyboard always works too.
- Player-facing text is plain and short, in the game's words (the weekend, qualifying, the race, the pit lane, the safety car).

## Testing online

Prefer a local game server to `play.linuxgroove.com`, since test runs create real accounts and rooms. online-addon.md describes running one in LXD or Docker and the two-instance tests for joining by code and quick match. Device logs live in `~/snap/race-day/current/.local/share/race-day/logs/godot.log`.

## Releases

Pushing to `main` builds the snap and publishes it to the `edge` channel; a GitHub release publishes to `candidate`. The **Windows and macOS** workflow (`desktop.yml`) exports both from Linux with the `Windows Desktop` and `macOS` presets: pushes to `main` keep the zips as artifacts for 5 days, and releases get them attached. They aren't signed by Microsoft or Apple, and the release notes tell players how to open them. CI injects the server key from the `GAME_SERVER_KEY` secret, so never commit the real key.

Versions are `vYYYY.WW.MINOR`, derived from git by `tools/version.sh` (`2026.41.0` on a tag, `2026.41.0+3.g1a2b3c4d` after it); CI stamps it into `project.godot` before building and nobody edits it by hand. Make releases with the **Release** workflow (Actions, Release, Run workflow), which refuses commits whose CI hasn't passed. Commit subjects become the release notes, so write them for players.
