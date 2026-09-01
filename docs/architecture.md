# Architecture

How the project is laid out and how the pieces talk to each other. Start here
before changing anything structural.

## Repository map

```
autoload/     the 7 singletons -- 1:1 with project.godot's [autoload] block
rules/        board, blocks -- game logic with no presentation dependency
scenes/       one screen = .tscn + .gd, plus the MenuScreen base they share
ui/           background, theme.tres
  widgets/    reusable Controls that know nothing about the game
  effects/    the particle scenes, and effects.gd which spawns them
  fonts/      vendored third-party TTFs -- never edit
  pixel/      GENERATED sprites; reproduce with tools/, never hand-edit
platform/     device shims (haptics; ads and IAP would go here)
assets/       audio and store icons
tools/        asset generators and the path audit
docs/         this directory
```

`rules/` is named that rather than `game/` deliberately: `game/board.gd` sitting
next to `scenes/game.gd` would recreate the ambiguity the split exists to remove.

## Scene flow

`splash.tscn` → `main_menu.tscn` → `{ game | leaderboard | settings | about }`, all routed through the `App` autoload.

## Autoloads

- **`App`** (`scripts/app.gd`) — a `CanvasLayer` at layer 128 owning scene routing and the fade overlay. Always navigate with `App.goto_scene(App.SCENE_*)`; it drops re-entrant calls so a double-tap cannot load two scenes. Also exposes `game_name` / `game_version` read from project settings.
- **`Scores`** (`scripts/scores.gd`) — the local leaderboard, persisted to `user://scores.cfg`. Top 10 **per mode**, so filtering never leaves a mode with one row, and `submit()` returns the rank within that mode. `best()` is the overall best (the menu); `best(mode)` is per-mode (the HUD) — a Sprint score and an endless run are not comparable. Rows written before modes existed carry a `level` from the removed difficulty system and no mode; the loader ignores the field and migrates them to Palette. Single source of truth for the best score; nothing else should write a save file.
- **`Themes`** (`scripts/themes.gd`) — the theme registry. See **Theming** below.
- **`Modes`** (`scripts/modes.gd`) — game modes. `PALETTE` is the endless game the project has always had; `SPRINT` runs a 60-second fuse; `PUZZLE` deals a seeded starting board with a lines-to-clear objective. `current` must be set **before** routing to the play screen — `game.gd` reads it once in `_setup_mode()`, which `_restart()` calls. Owns the `[modes]` section of `user://settings.cfg`.
- **`GameServices`** (`scripts/game_services.gd`) — Apple Game Center: authenticate on launch, greet the signed-in player on the welcome page, submit every finished run, open Apple's leaderboard UI. Godot 4 has **no built-in Game Center module** (it moved out of the engine after 3.x), so this binds at runtime to the `GameCenter` singleton from godot-ios-plugins. Guarded twice — iOS *and* singleton present — so it is a silent no-op in the editor, on desktop, on Android, and on an iOS build without the plugin. The local `Scores` table stays the source of truth; nothing may depend on Game Center succeeding. Setup that cannot be done from this repo is in `docs/gamecenter.md`.
- **`Progress`** (`scripts/progress.gd`) — player progression: level from cumulative score, power unlocks and levels, the 3-power loadout, charge, unlocked themes, daily streak, and the doubled-XP session. Owns `user://progress.cfg` outright — charge changes a dozen times a run and every write to the shared `settings.cfg` rewrites all of it. The level is re-derived from the score on load, never trusted from disk.
- **`Audio`** (`scripts/audio.gd`) — a shuffled music playlist and sound effects. Two beds, picked per screen by `App._playlist_for()`: a fixed menu rotation (4 plays per track) and a shuffled in-game list (5 plays per track). Tracks are scanned from `assets/audio/music/` at runtime and named in `snake_case`; `game_over` is held back and played when a run ends. Effect streams are cached, music streams are not — the library is tens of megabytes and only one track plays at a time. Owns the `[audio]` section of `user://settings.cfg`. Effects resolve by name against `.wav`/`.ogg`/`.mp3`, so assets can be replaced without code changes — see `assets/audio/README.md`. It starts its own music in `_ready()` rather than being started by `App`, because autoloads run in declaration order and `App` is first.

## Game separation of concerns

The play screen splits cleanly in three. Respect this when adding features:

- **`scripts/board.gd`** — grid state, placement legality, row/column clearing, bomb detonation, scoring, and the "no moves left" test. Owns all game rules and its own `_draw()`. **Never reaches out to presentation**; it only emits signals.
- **`scenes/game.gd`** — orchestration. Turns board signals into HUD updates, effects, screen shake and tray management. Owns all input.
- **`scripts/effects.gd`** — a `Node2D` that spawns particles, flashes, shockwaves and popups. Stateless with respect to the game.

`board.gd` signals: `score_changed`, `lines_cleared`, `piece_placed`, `bomb_detonated`, `laser_fired`, `diagonal_fired`, `blackhole_fired`, `thunder_struck`, `blocks_teleported`, `meteor_landed`, `tsunami_swept`, `earthquake_shook`, `board_morphed`, `piece_fitted`, `game_over`. Rewind emits nothing — it is a restore, not an event, and `restore()` re-emits `score_changed` so the HUD follows.

## Two effects layers

`game.tscn` has **two** nodes running `effects.gd`, and picking the wrong one is a common mistake:

- `%Effects` — a child of the board, so its coordinates are **board-local**. Use for line clears, placement puffs, bomb blasts.
- `%OverlayEffects` — a child of the scene root, drawn **above the game-over panel**. Use for confetti and anything that must not be hidden by an overlay. Coordinates are screen-space.

## Input

**`_begin_drag` must set `_drag_from`.** `_update_drag` returns immediately while it is `NONE` and `_end_drag` dispatches on it, so leaving it unset kills the entire drag path — every placement and every power cast — silently. That shipped once and went unnoticed for the whole powers rewrite, because every test in this repo drives `_board.place()` or `game.gd._fire_power()` directly and nothing exercised `_input`. `_start_drag()` is the shared pick-up tail for both the tray and the strip and documents the ordering.

There is now an input test that calls `_input()` with synthesised `InputEventMouseButton`/`MouseMotion` rather than `Input.parse_input_event` — the latter needs window/viewport scaling and Godot substitutes the real cursor for injected motion anyway. **Keep it in the standing regression**; this class of bug is invisible to every other test here.

Pointer handling lives in `_input()` on `game.gd`, not `_unhandled_input()`, because a drag spans the tray and the board and must not depend on which Control sits under the pointer. The root `Game` node has `mouse_filter = 2` (IGNORE) — with the default STOP it swallows every event before the script sees it. Touch is emulated as mouse by default, so handling mouse events covers both platforms.

## Layout conventions

Screens follow: `Background` instance → `SafeArea` (`MarginContainer` + `safe_area_margin.gd`) → `Layout` VBox. Containers and decorative nodes are set `mouse_filter = 2` so clicks reach the script. Buttons and panels get their look from `ui/theme.tres`; avoid per-node style overrides unless a node genuinely differs.

Two layout traps seen in this repo:
- An `AspectRatioContainer` needs `size_flags_vertical = 3`, or sibling spacers starve it and it collapses to zero size.
- A `ScrollContainer` claims all spare height even when empty — hide it and show the empty-state label instead.

## Mobile specifics

- Design resolution 1080×1920 portrait; the window override only affects desktop test runs.
- `scripts/safe_area_margin.gd` folds notch/home-indicator insets into a `MarginContainer`'s margins, on Android and iOS only (on desktop `get_display_safe_area()` describes the whole monitor).
- **Metal is already the renderer** on macOS and iOS — Godot 4.7 defaults `rendering_device/driver.ios` and `.macos` to `metal`. Do not add explicit driver settings; Godot strips settings equal to defaults on save.
- The Exit menu entry is hidden on iOS, since Apple rejects apps that quit themselves.
