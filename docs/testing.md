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

### Store screenshots

`tools/shots.tscn` renders the seven marketing shots at any device resolution:

```bash
"$GODOT" --path . res://tools/shots.tscn \
    --write-movie /tmp/discard/f.png --fixed-fps 60 --disable-vsync \
    -- 1320x2868 res://screenshots/store/iphone-6.9-1320x2868
```

The movie output is **thrown away**. `--write-movie` is passed only because it
is the one thing that forces a deterministic render loop; the harness saves its
own PNGs from a SubViewport.

**Do not try to get the size by resizing the window.** macOS clamps a window to
the screen, so asking for 1320x2868 on a 1920x1080 display gives a 1320x1018
window — and the stretch system then lays the game out **landscape**. Movie
Maker still writes files at the size you asked for, so you get plausible-looking
files with the HUD cut off and the board clipped. Neither `--resolution` nor
`DisplayServer.window_set_size` avoids this; `override.cfg` changes the file
size but not the layout.

The harness instead renders into a `SubViewport` sized to the device, with
`size_2d_override` set to the design-space equivalent and
`size_2d_override_stretch` on. That is exactly what a device does: native
render resolution, UI laid out in design units. The override is derived the way
`canvas_items`/`expand` derives it — `scale = min(w/1080, h/1920)`, which for
anything taller than 9:16 is the width, so the extra height becomes extra board
rather than letterboxing.

Two things that are invisible in an assertion and were both wrong on the first
pass: the score is a **rolling counter**, so a shot taken too early shows a
number that was never the score (the harness calls `reset_to()`), and a wiped
profile has **seen no coach hints**, which puts a tutorial line under a
veteran's board.

Apple requires the **6.9-inch** slot (1320x2868); everything smaller is scaled
from it automatically, and 6.5 inch (1284x2778) is only needed when 6.9 inch is
absent. **The app is universal** (`TARGETED_DEVICE_FAMILY = "1,2"`), so the
**13-inch iPad** slot (2064x2752) is required too — an iPad-capable app cannot
be submitted without it, and no iPhone screenshot is ever scaled to fill it.
Screenshots must carry **no alpha channel**, so the harness converts to
`FORMAT_RGB8` before saving.

An iPad hands the layout the same 1920 design height and **more width** —
1440x1920 on a 13 inch, against 1080x1920 on a phone — because
`canvas_items`/`expand` scales on the tighter axis. Nothing needs a special
case: the board reads its cell size from its own width and stays square,
growing from 1048 to 1113 with a cell of 92 against 87. Verify that with a
probe rather than by eye; a downscaled iPad capture reads as though the grid
has gone oblong when it has not.

### The app preview video

`tools/clip.tscn` renders a scripted run — three clears building a combo, then
a laser, a blackhole and a bomb spending it — as a PNG sequence, and Movie
Maker's WAV alongside it is the soundtrack:

```bash
"$GODOT" --path . res://tools/clip.tscn \
    --write-movie /tmp/discard/f.png --fixed-fps 30 --disable-vsync \
    -- 886x1920 /tmp/clip

ffmpeg -y -framerate 30 -i /tmp/clip/f%05d.png -ss 0.83 -i /tmp/discard/f.wav \
    -map 0:v -map 1:a -shortest \
    -c:v libx264 -profile:v high -level:v 4.0 -pix_fmt yuv420p \
    -preset veryslow -crf 10 -x264-params "deblock=-3,-3" \
    -maxrate 12M -bufsize 24M -r 30 \
    -c:a aac -b:a 256k -ar 48000 -ac 2 -movflags +faststart out.mp4
```

**Every iPhone preview slot is 886x1920**, whatever the screenshot size for
that device is — 15 to 30 seconds, 30fps, H.264 High Profile 4.0.

The `-ss` offset is not cosmetic. Recording starts after the scene has
settled, but the WAV covers the whole run, so without it the audio leads the
picture for the entire clip. Measure it rather than assume it — it is simply
the WAV's length minus the frame count over 30.

Blackhole and bomb are cast at **level 5** in the clip, and the board is packed
to about 0.7 before each. Both matter: a maxed blackhole reaches radius 4.0
against 2.5 at level 3, and a maxed bomb takes 7x7, the row *and* half the
board — but a wide blast over a sparse board destroys nothing much and reads
as a small one.

**Grab frames from the hold loop, not from a `frame_post_draw` handler.**
Reading the viewport texture inside that handler makes it miss emissions: a
first pass wrote 171 frames where Movie Maker, running alongside, wrote 582.

`-tune animation` is the wrong choice here despite the name — it strengthens
deblocking, which softens exactly the hard edges pixel art is made of.
Disabling deblocking instead holds them. Do not chase RGB PSNR either: it
plateaus around 38 dB no matter the bitrate, because H.264 is 4:2:0 and the
loss is chroma. Luma comes in at 44.5 dB, and an A/B at 4x is indistinguishable.
