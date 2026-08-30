# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**ComplexPuzzle** — a drag-and-drop block puzzle (Block Blast / 1010!-style) built in **Godot 4.7.2**, targeting Android and iOS in portrait. Drag cards from a five-slot tray onto an 8×8 board; filling a row or column clears it. The run ends when nothing left in the tray fits anywhere.

## Commands

The Godot binary is not on `PATH`. Use the full path:

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

# Run the game (main scene is scenes/splash.tscn)
"$GODOT" --path .

# Run a specific scene
"$GODOT" --path . res://scenes/game.tscn

# Reimport assets after adding an .svg/.png (Godot generates .import metadata;
# a scene referencing an unimported asset fails to load)
"$GODOT" --headless --import --path .

# Parse-check every script without running (surfaces GDScript warnings)
"$GODOT" --headless --path . res://some_test_scene.tscn
```

There is no test framework, linter, or build script. Verification is done by writing a throwaway scene + script, running it, and deleting it — see below.

### Writing and running a test

Tests are ad-hoc: a `Node` script that asserts, prints, and calls `get_tree().quit(code)`, paired with a two-line `.tscn`. Put both at the project root, run, then delete.

```gdscript
# _t.gd
extends Node
var fails := 0
func check(ok: bool, label: String) -> void:
    if ok: print("OK    ", label)
    else:  print("FAIL  ", label); fails += 1

func _ready() -> void:
    var game: Control = load("res://scenes/game.tscn").instantiate()
    add_child(game)
    for i in 3: await get_tree().process_frame   # let containers lay out
    # ... assertions ...
    get_tree().quit(1 if fails else 0)
```

```bash
"$GODOT" --headless --path . res://_t.tscn; rm -f _t.gd _t.tscn _t.gd.uid
```

Always guard the run with a watchdog — a script that errors before `quit()` leaves Godot spinning forever, and macOS has no `timeout`:

```bash
"$GODOT" --headless --path . res://_t.tscn > out.log 2>&1 &
PID=$!; ( sleep 60; kill -9 $PID 2>/dev/null ) & WD=$!
wait $PID; kill $WD 2>/dev/null; cat out.log
```

### Test-harness gotchas

These cost real debugging time; they are properties of Godot, not of this codebase.

- **Use a `Node` scene, not `--script` with a `SceneTree`.** Autoloads (`App`, `Scores`) are not registered under a replaced main loop, so anything touching them fails to compile. If you must use `SceneTree`, do work in `_initialize()` — `root` does not exist yet in `_init()`.
- **GDScript lambdas capture locals by value.** A signal probe that does `func(): flag = true` will never update the outer `flag`. Mutate an `Array` or `Dictionary` instead — those are references.
- **Injected input arrives in window pixels, layout rects are in viewport pixels.** The viewport is 1080×1920 inside a 540×960 window, so `Input.parse_input_event` positions must be scaled by `window_size / viewport_size`. Injected *motion* is unreliable regardless (Godot substitutes the real cursor position) — drive `_begin_drag` / `_update_drag` / `_end_drag` directly instead.
- **Nodes created with `.new()` need `reset()` called manually** — `_ready()` initialises grid state and does not run until the node enters the tree.

### Screenshots

A backgrounded window has its rendering suspended by macOS, so `get_viewport().get_texture().get_image()` returns byte-identical frames. `SubViewport` with `UPDATE_ALWAYS` and `window_move_to_foreground()` both fail too. Use **Movie Maker mode**, which renders deterministically to disk:

```bash
"$GODOT" --path . res://_shot.tscn --write-movie out/f.png --fixed-fps 60 --disable-vsync
```

Frames are named `f00000000.png`. The game auto-pauses on focus loss (see `_notification` in `game.gd`), so a capture harness must force `%PausePanel.hide()` each frame.

## Architecture

### Scene flow

`splash.tscn` → `main_menu.tscn` → `{ game | leaderboard | settings | about }`, all routed through the `App` autoload.

### Autoloads

- **`App`** (`scripts/app.gd`) — a `CanvasLayer` at layer 128 owning scene routing and the fade overlay. Always navigate with `App.goto_scene(App.SCENE_*)`; it drops re-entrant calls so a double-tap cannot load two scenes. Also exposes `game_name` / `game_version` read from project settings.
- **`Scores`** (`scripts/scores.gd`) — the local leaderboard, top 10, persisted to `user://scores.cfg`. Single source of truth for the best score; nothing else should write a save file.

### Game separation of concerns

The play screen splits cleanly in three. Respect this when adding features:

- **`scripts/board.gd`** — grid state, placement legality, row/column clearing, bomb detonation, scoring, and the "no moves left" test. Owns all game rules and its own `_draw()`. **Never reaches out to presentation**; it only emits signals.
- **`scenes/game.gd`** — orchestration. Turns board signals into HUD updates, effects, screen shake and tray management. Owns all input.
- **`scripts/effects.gd`** — a `Node2D` that spawns particles, flashes, shockwaves and popups. Stateless with respect to the game.

`board.gd` signals: `score_changed`, `lines_cleared`, `piece_placed`, `bomb_detonated`, `game_over`.

### Two effects layers

`game.tscn` has **two** nodes running `effects.gd`, and picking the wrong one is a common mistake:

- `%Effects` — a child of the board, so its coordinates are **board-local**. Use for line clears, placement puffs, bomb blasts.
- `%OverlayEffects` — a child of the scene root, drawn **above the game-over panel**. Use for confetti and anything that must not be hidden by an overlay. Coordinates are screen-space.

### Pieces

`scripts/blocks.gd` holds 15 base shapes in `BASE`; rotations are **generated at load** and de-duplicated, producing 37 pieces. To add a shape, add one line to `BASE` — do not hand-write rotations. Pieces are plain `Dictionary` values: `{cells, color, size, weight}`, plus `bomb: true` for the bomb.

The **bomb** is a 1×1 special that clears the half of the board it lands in (split on the horizontal midline). It arrives two ways: a 20% roll **per tray refill** (never per card — that could deal three at once), and as a reward for a 2× combo. Both paths respect one invariant: **at most one bomb in hand at a time**.

### Input

Pointer handling lives in `_input()` on `game.gd`, not `_unhandled_input()`, because a drag spans the tray and the board and must not depend on which Control sits under the pointer. The root `Game` node has `mouse_filter = 2` (IGNORE) — with the default STOP it swallows every event before the script sees it. Touch is emulated as mouse by default, so handling mouse events covers both platforms.

### Mobile specifics

- Design resolution 1080×1920 portrait; the window override only affects desktop test runs.
- `scripts/safe_area_margin.gd` folds notch/home-indicator insets into a `MarginContainer`'s margins, on Android and iOS only (on desktop `get_display_safe_area()` describes the whole monitor).
- **Metal is already the renderer** on macOS and iOS — Godot 4.7 defaults `rendering_device/driver.ios` and `.macos` to `metal`. Do not add explicit driver settings; Godot strips settings equal to defaults on save.
- The Exit menu entry is hidden on iOS, since Apple rejects apps that quit themselves.

### Layout conventions

Screens follow: `Background` instance → `SafeArea` (`MarginContainer` + `safe_area_margin.gd`) → `Layout` VBox. Containers and decorative nodes are set `mouse_filter = 2` so clicks reach the script. Buttons and panels get their look from `ui/theme.tres`; avoid per-node style overrides unless a node genuinely differs.

Two layout traps seen in this repo:
- An `AspectRatioContainer` needs `size_flags_vertical = 3`, or sibling spacers starve it and it collapses to zero size.
- A `ScrollContainer` claims all spare height even when empty — hide it and show the empty-state label instead.

## Dead code

`scripts/playfield.gd`, `tetromino.gd`, `next_preview.gd` and `input_actions.gd` are leftovers from an earlier falling-block (Tetris) prototype. They form an orphaned island — nothing live references them — and are safe to delete. **This is not a git repository**, so deletions are unrecoverable; confirm before removing anything.

## Known gaps

- No audio at all. Every moment (deal, placement, line clear, bomb, confetti) is silent.
- `scenes/settings.tscn` is a navigable placeholder with no working options.
- The leaderboard is local-only; there is no backend or platform integration.
- No export presets are configured. Note that Godot 4.7.2's iOS **simulator** slice is x86_64-only while Xcode 26 simulators are arm64-only, so the simulator cannot run this on Apple Silicon — use a physical device or the macOS build.
