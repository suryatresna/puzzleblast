# Testing and verification

There is no test framework, linter or build script. Verification is done by
writing a throwaway scene plus script, running it headless, and deleting it.

## End-to-end

```bash
"$GODOT" --headless --path . res://tools/e2e.tscn
```

Boots the app, walks every `App.SCENE_*` route asserting the scene actually
changed, plays a game by synthesising pointer events, fires a power off the
strip, ends the run and checks it was recorded and persisted.

**This is the only test that goes through `App.goto_scene` and `_input`.**
Everything else in this repo drives `_board.place()` or `_fire_power()`
directly, which is how a completely dead drag path once survived a whole
feature's worth of tests. It wipes `user://` progress and writes a leaderboard
row.

Two things it taught, both of which will bite anyone writing a similar test:

- **`_input` returns early once `_board.alive` is false.** Play until nothing
  fits and every later press is silently swallowed. Restart the board before
  testing anything that needs input.
- **A surviving run can still have a completely full board.** Charge in the bank
  keeps the run alive past a dead tray, so "alive" does not mean "has an empty
  cell". A power that needs one has nowhere to go.

To place a piece at a chosen cell, invert what `_update_drag` does — and read
the carried piece's real `piece_pixel_size()` rather than deriving it from the
cell count:

```gdscript
pointer = board.global_position + Vector2(target) * cell \
        + drag_view.piece_pixel_size() * 0.5 \
        + Vector2(0.0, game.DRAG_LIFT_CELLS * cell)
```

Judge success by the tray slot emptying, **not** by the board's fill count: a
placement that completes a line clears it, so the board can end up emptier than
it started.

## --headless renders at the wrong size

`--headless` gives a **1920x1920 square** viewport, not the project's 1080x1920.
A scene left to size itself from it lays out at 158px cells instead of 128px:

```
viewport under --headless: (1920, 1920)     board 1267px, cell 158
size forced to 1080x1920:  board 1048px, cell 128   <- the real layout
```

So **any layout assertion made headlessly is measuring the wrong thing** unless
the harness sets `size = Vector2(1080, 1920)` on the scene root itself. Logic
tests are unaffected; anything about geometry needs the forced size, or a
windowed Movie Maker capture.

## The path audit

Run this after anything moves:

```bash
"$GODOT" --headless --path . res://tools/audit_paths.tscn
```

It walks every `res://` path the project names and exits non-zero if one does
not resolve. It exists because three classes of reference in this project fail
**silently** -- see `docs/invariants.md`. "It still runs" does not prove a move
was clean; this does.

Note the **first** `--import` after files move reports phantom autoload errors:
Godot boots the autoloads from a stale UID cache before rescanning. The second
run is clean. Do not chase it.

## Writing and running a test

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

## Test-harness gotchas

These cost real debugging time; they are properties of Godot, not of this codebase.

- **Use a `Node` scene, not `--script` with a `SceneTree`.** Autoloads (`App`, `Scores`) are not registered under a replaced main loop, so anything touching them fails to compile. If you must use `SceneTree`, do work in `_initialize()` — `root` does not exist yet in `_init()`.
- **GDScript lambdas capture locals by value.** A signal probe that does `func(): flag = true` will never update the outer `flag`. Mutate an `Array` or `Dictionary` instead — those are references.
- **Injected input arrives in window pixels, layout rects are in viewport pixels.** The viewport is 1080×1920 inside a 540×960 window, so `Input.parse_input_event` positions must be scaled by `window_size / viewport_size`. Injected *motion* is unreliable regardless (Godot substitutes the real cursor position) — drive `_begin_drag` / `_update_drag` / `_end_drag` directly instead.
- **Nodes created with `.new()` need `reset()` called manually** — `_ready()` initialises grid state and does not run until the node enters the tree.

## Screenshots

A backgrounded window has its rendering suspended by macOS, so `get_viewport().get_texture().get_image()` returns byte-identical frames. `SubViewport` with `UPDATE_ALWAYS` and `window_move_to_foreground()` both fail too. Use **Movie Maker mode**, which renders deterministically to disk:

```bash
"$GODOT" --path . res://_shot.tscn --write-movie out/f.png --fixed-fps 60 --disable-vsync
```

Frames are named `f00000000.png`. The game auto-pauses on focus loss (see `_notification` in `game.gd`), so a capture harness must force `%PausePanel.hide()` each frame.
