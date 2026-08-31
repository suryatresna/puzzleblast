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
- **`Themes`** (`scripts/themes.gd`) — the theme registry. See **Theming** below.
- **`Audio`** (`scripts/audio.gd`) — a shuffled music playlist and sound effects. Two beds, picked per screen by `App._playlist_for()`: a fixed menu rotation (4 plays per track) and a shuffled in-game list (5 plays per track). Tracks are scanned from `audio/music/` at runtime and named in `snake_case`; `game_over` is held back and played when a run ends. Effect streams are cached, music streams are not — the library is tens of megabytes and only one track plays at a time. Owns the `[audio]` section of `user://settings.cfg`. Effects resolve by name against `.wav`/`.ogg`/`.mp3`, so assets can be replaced without code changes — see `audio/README.md`. It starts its own music in `_ready()` rather than being started by `App`, because autoloads run in declaration order and `App` is first.

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

### Theming

Three themes are defined — **Classic** (the original indigo look), **Pixel Warm** and **Pixel Dark** — but the active one is a **build-time constant**, `Themes.ACTIVE`, currently `PIXEL_DARK`. There is deliberately no user-facing switch and the choice is not persisted; to re-theme the game, change that one line. `Themes.set_current()` exists only for the theme generator and tests.

`scripts/themes.gd` is the single source of truth. A theme is one entry in `DEFS` — palette, semantic text colours, a UI theme resource, and for the pixel themes a set of sprites. **Adding a theme should need no code outside that table.**

Rules that keep it that way:

- **Never hardcode a colour in a scene or script.** Scenes use `theme_type_variation` (`TitleLabel`, `MutedLabel`, `FaintLabel`, `AccentLabel`, `HighlightLabel`, `DangerLabel`, `HudPanel`, `SlotPanel`, `BarTrack`, `BarFill`); scripts call `Themes.text_color(role)` or `Themes.palette()`. A `theme_override_colors/*` or `theme_override_styles/*` in a `.tscn` is a bug — it will not follow the theme.
- Anything that caches theme values must rebuild on the `theme_changed` signal. `board.gd`, `piece_view.gd`, `background.gd` and `logo_mark.gd` all do.
- `App.apply_theme()` pushes the UI theme onto the scene root after every swap; Godot propagates it down the tree.
- Themes are **presentation only** — switching mid-run must never touch grid state or score.

Both generated artefacts are reproducible; re-run them after changing a palette:

```bash
python3 tools/gen_pixel_sprites.py                       # ui/pixel/*.png
"$GODOT" --headless --path . res://tools/gen_pixel_themes.tscn   # ui/theme*.tres
```

`gen_pixel_themes` reads its colours from `Themes.DEFS`, and also injects the type variations into the hand-maintained `ui/theme.tres`.

**Branding.** The title mark is the design's nine tiles laid out six across, drawn at runtime by `scripts/logo_mark.gd` from the live block sprite so it follows the palette rather than being a flat image. It appears on both `splash` and `main_menu`. The wordmark is the game name stacked one word per line via `App.game_wordmark()` — derived from the project name, so a rename carries through — styled by the `WordmarkLabel` variation (accent colour plus the design's hard 12px offset shadow). The boot splash and app icon are baked from the same layout by `tools/gen_branding.py`; because Godot needs files on disk for those, they are pinned to the shipped palette and must be regenerated if `Themes.ACTIVE` changes.

**Surfaces are two-stop gradients.** Every panel, button and backdrop in the design is a vertical `linear-gradient(180deg, top, bottom)`. Rather than store both stops, the nine-patch sprite carries the *ramp* and the theme names only the **top** colour — tinting reproduces the bottom stop. The ramp differs per mode (light panels fall to ~0.90 of the top, dark ones to ~0.62), which is why `panel.png` and `panel_dark.png` are separate sprites. `bg_stops` likewise stores just the design's two endpoints; `background.gd` samples that ramp at each gradient point's own offset, so a 2-stop theme and a 3-stop one both work.

**Settings rows** are built in code from a table in `settings.gd`, not laid out in the `.tscn` — they are repetitive and data-driven. Three shapes: a switch row (`scripts/toggle_switch.gd`), a slider row (`scripts/segment_slider.gd`, the design's 8 discrete segments) and a read-only note card. Both controls take their geometry from the design doubled twice, and their colours from `Themes`. Cards use the `CardPanel` variation: a flat fill with a hard ink border, distinct from the gradient nine-patch the HUD and tray use.

Watch the token names: `#241C16` is the dark **panel**, but the dark **board** is a step darker at `#201914`. The board also carries an ink frame outside the grid (`board_border`), which is the design's `box-shadow: 0 0 0 4px` — 4px at the mockup's 2x, so 2 logical px, 8 in our space.

**Pixel geometry.** The design is 270×480 with 32px tiles; the game runs at 1080×1920, exactly 4×. Sprites are therefore generated pre-upscaled (a 32px tile is stored at 128px) rather than relying on filtering — `StyleBoxTexture` nine-patch margins are measured in texture pixels and are *not* scaled when drawn, so a 48px plate with a 12px margin would render tiny corners. `base_margin = 28` on the game screen gives a 1024px board and exactly 128px cells. Under a pixel theme `cell_size()` floors, `grid_origin()` centres the remainder, and `shake_offset` rounds to whole pixels.

### Layout conventions

Screens follow: `Background` instance → `SafeArea` (`MarginContainer` + `safe_area_margin.gd`) → `Layout` VBox. Containers and decorative nodes are set `mouse_filter = 2` so clicks reach the script. Buttons and panels get their look from `ui/theme.tres`; avoid per-node style overrides unless a node genuinely differs.

Two layout traps seen in this repo:
- An `AspectRatioContainer` needs `size_flags_vertical = 3`, or sibling spacers starve it and it collapses to zero size.
- A `ScrollContainer` claims all spare height even when empty — hide it and show the empty-state label instead.

## Dead code

`scripts/playfield.gd`, `tetromino.gd`, `next_preview.gd` and `input_actions.gd` are leftovers from an earlier falling-block (Tetris) prototype. They form an orphaned island — nothing live references them — and are safe to delete.

## Known gaps

- `scenes/settings.tscn` follows the design's card-row layout: music, sound, music volume, grid lines, haptics. The design's RESTORE PURCHASES is not built — there is no IAP.
- Effects are still placeholders from `tools/gen_audio.py`; music is real. Confetti is silent.
- `audio/music/theme.wav` and `audio/sfx/game_over.wav` are superseded and unreferenced.
- Looping WAVs need `edit/loop_mode=1` in their `.import`. Setting `loop_mode` at runtime without also setting `loop_end` yields a zero-length loop: `playing` stays true, the position never advances, and the track is silent. `--headless` and Movie Maker both use the Dummy audio driver, so audio bugs only surface in a real windowed run.
- The leaderboard is local-only; there is no backend or platform integration.
- No export presets are configured. Note that Godot 4.7.2's iOS **simulator** slice is x86_64-only while Xcode 26 simulators are arm64-only, so the simulator cannot run this on Apple Silicon — use a physical device or the macOS build.
