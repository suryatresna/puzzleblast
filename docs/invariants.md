# Invariants

Rules that, if broken, produce **no error** — the game keeps running and does
the wrong thing. They were scattered across eight sections of `CLAUDE.md`, which
meant anyone reading half of it missed half of them.

Each entry says what breaks and how you would find out.

## Paths

**Three classes of path reference fail silently.** Run
`tools/audit_paths.tscn` after anything moves; it is the only thing that turns
these into a loud failure.

- **`App.SCENE_*` constants.** `goto_scene()` discards the `Error` that
  `change_scene_to_file()` returns, so a dead route fades out onto nothing.
- **Directory prefixes** — `Audio.MUSIC_DIR`, `Audio.SFX_DIR`,
  `Themes.SPRITE_DIR`. Assembled at runtime, so no full path appears in the
  source for grep to find. A wrong directory means `ResourceLoader.exists()`
  returns false and the caller gets `null`: the sound is merely absent.
- **`Themes.DEFS[*]["ui_theme"]`.** `ui_theme()` returns `null` on a missing
  path *by design*, so the screen keeps its own theme and looks almost right.

**`git mv` a `.gd` together with its `.gd.uid`.** An orphaned sidecar is a break
with no message. Only 9 of the project's scene references carry a UID; the rest
resolve by path alone.

## Adding a power

A power missing one of these is **dealt but does nothing**. There are nine
tables, and the enum is written `Blocks.Power.X` in `board.gd` but `Power.X`
inside `blocks.gd` — miss one form and the grep looks clean.

1. `Blocks.Power` — the enum entry
2. `Blocks.COLORS` — one colour, and `Blocks.POWER_COLOR` mapping to its index
3. `Blocks.ALL_POWERS` and `Blocks.POWER_NAMES`
4. `Blocks.draw_power` — a branch, plus the vector glyph it calls
5. `Board._fire_power` — a branch
6. `Themes.GLYPHS` — a glyph name, and a sprite from `tools/gen_pixel_sprites.py`
7. **Every theme's `powers` array.** `board.gd` indexes `Themes.palette()` with
   **no wrap**, so a short array is an out-of-range crash, not a wrong colour.
8. `Progress.COST`, and a tier in `Progress.POWER_TIERS`
9. `Progress.REWARDS` — a `"power"` grant, and `game.gd`'s `POWER_ATMOSPHERE`

## Progression

- **`REWARDS` grants must stay in step with `POWER_TIERS`.** A level that banks
  more unlocks than the open tiers can absorb strands them: the player has
  nothing to spend on. There is a test asserting this.
- **`_catch_up_rewards()` is load-bearing.** `_level` is derived from
  `_total_score` on load and never stored, so retuning `LEVEL_GROWTH` re-levels
  every save. Before the ledger existed, `_apply_reward` ran only inside
  `add_score`'s own loop and a jump from L6 to L30 lost four of six power
  unlocks permanently. **Any future curve change is safe only because of it.**
- **Never restore `board.best` or `game.gd._banked`.** Both are high-water
  marks; restoring them lets the same points bank as XP twice.
- **Rewind must cost more than the largest combo pays.** It returns the board
  but not the charge, so clear → rewind → re-clear is a loop that is only
  unprofitable while `COST[REWIND] > max(CHARGE_PER_COMBO)`. Asserted in a test.
- **Read a power's level before spending, spend after `place()` returns.**
  Spending records a use and can level the power mid-shot, and a drop the board
  refuses must not bill the player.

## Ending a run

- **An empty tray is a transient, never a position.** `has_any_move([])` is
  false whatever the board looks like, so a spent tray reads as a loss even on
  a completely free grid. `_check_game_over` refills before it decides.
- **Affording a power is not the same as being able to fire one.** A power the
  player can pay for but cannot aim is not a move, and counting it as one keeps
  a dead board alive with nothing that can happen. Rewind with nothing recorded
  and Shuffle with nothing that fits are the two that bite: both refund, so the
  player can tap them forever without the position changing. `_check_game_over`
  asks `_has_usable_power()`, not `Progress.has_affordable()`.
- **A blank-looking slot is not an empty one.** The strip renders from
  `Progress.equipped()`, so a socket that draws empty can still be holding an
  affordable power -- which the run-over test will rightly count. A rendering
  bug here looks exactly like a game-over bug.

## Board

- **`can_target()` gates powers, not `can_place()`.** `MORPH` and `FIT` assign
  into `_grid` at the target, so they need an empty cell; `TELEPORT` is the
  mirror and needs an occupied one.
- **`snapshot()` deep-copies `_grid`.** It is an Array of Arrays; a shallow
  `duplicate()` shares the rows, so the snapshot tracks the live board and a
  rewind appears to do nothing.
- **The filling powers must leave a row's worth of cells empty** after the lines
  they complete have cleared. `_check_game_over()` runs after every drag end
  including a power fire, so without the floor a tsunami could end the run on
  the shot the player just paid for.
- **Each bomb level must be a strict superset of the last.** Not automatic: on
  an 8×8 a 7×7 blast covers more than half the board.

## Presentation

- **Never hardcode a colour.** A `theme_override_colors/*` or
  `theme_override_styles/*` in a `.tscn` will not follow the theme. Scenes use
  `theme_type_variation`; scripts call `Themes.text_color()` or
  `Themes.palette()`.
- **Anything caching theme values rebuilds on `theme_changed`.**
- **`%Effects` is board-local; `%OverlayEffects` is screen-space.** Picking the
  wrong one puts the effect in the wrong place, or under the game-over panel.
- **A particle emitter behind an opaque control is invisible.** The power
  slot's piece view is a nine-patch filling the slot, so the charge motes are
  emitted *wider* than the tile on purpose -- only what escapes the edges is
  ever seen. `place_puff.tscn` also carries a `scale_amount_curve` that shrinks
  each particle to nothing; reused at slot size that leaves a single pixel.
  Both faults pass every assertion. Capture it.
- **Check a light backdrop against the HUD.** The top gradient stop lerps 85% of
  the way to the sky colour, and the score is cream. Thunder's first cloud
  measured within six luminance values of the text behind it and the score
  vanished. Measure; do not eyeball.

## Native plugin queues

**Never drain a native queue with a bare `while count > 0`.** `GameServices`
pumps the Game Center plugin every frame on the main thread, and the queue
belongs to code this project does not control. A pop that fails to consume turns
that loop into a device-wide freeze with no error and nothing in the log — the
phone simply stops responding. The pump is bounded twice: a per-frame cap, and a
check that the count actually fell. If it did not, it warns once and stands
down.

## Input

- **`_drag_index` is shared between the tray and the strip**, so it never means
  "a tray slot" on its own. Anything keyed on it must test `_drag_from` too —
  `_sync_tray` did not, and a power cast from strip slot N blanked *tray* slot
  N, leaving a card that looked gone but still dragged.
- **The tray re-syncs at the end of a drag, after the state is cleared.** The
  drop handlers run while the drag is still current, so a refused drop synced
  with its own index still set and left the slot it had just restored looking
  empty.
- **Both the tray AND the strip must re-sync at the end of a drag.** Every
  `_sync_powers()` inside `_fire_power` runs while the drag is still current,
  so the slot just used draws as empty -- including the free-cancel paths
  (dropped off the board, rewind with no history, shuffle with nothing that
  fits), where no charge changes and so nothing fires afterwards to put it
  back. The socket then sits blank while the power is still equipped, still
  affordable and still draggable. This is the same defect as the tray one
  above; fixing only the tray left the strip broken.
- **`_begin_drag` must set `_drag_from`.** `_update_drag` returns immediately
  while it is `NONE` and `_end_drag` dispatches on it, so leaving it unset kills
  every placement and every power cast — silently. This shipped once and
  survived a whole feature's worth of tests, because every test in this repo
  drives `_board.place()` or `_fire_power()` directly. **Keep the `_input` test.**

## Scrolling

- **A `ScrollContainer` with `mouse_filter = 2` (IGNORE) receives nothing.** Not
  the wheel, not a drag, not a pan. It still lays out and still shows a
  scrollbar, so it looks entirely correct and simply will not move. Both
  `profile` and `how_to_play` shipped this way.
- **`MOUSE_FILTER_STOP` anywhere between a touch and the ScrollContainer breaks
  the scroll**, because STOP means "do not propagate to my parent" whether or
  not the event was used. `Button` and `PanelContainer` both default to STOP,
  so the profile's power cards -- a Button inside a PanelContainer, tiling the
  whole list -- left a phone with nowhere to grab. Anything scrollable that a
  finger can land on must be PASS or IGNORE the whole way up.
- **This cannot be tested by synthesising touch.** Neither `push_input` nor
  `Input.parse_input_event` drives `ScrollContainer`'s touch-drag path, even
  with `Input.set_emulate_touch_from_mouse(true)` -- a *bare* container with
  plain labels does not scroll either, so a failure there proves nothing. Test
  the wheel, which does route, and assert the filter chain directly.

## Other

- **`Modes.current` must be set before routing to the play screen.** `game.gd`
  reads it once, in `_setup_mode()`.
- **Music must not loop.** The playlist advances on `finished`, so a looping
  track never hands over. Setting `loop_mode` without `loop_end` gives a
  zero-length loop: `playing` stays true, position never advances, silence.
  `--headless` and Movie Maker both use the Dummy audio driver, so audio bugs
  only surface in a real windowed run.
- **The Abstraction music credit on the About page is a licence obligation.**
  Do not remove it.
- **`user://` save paths must never change.** Changing one orphans player data.
  On desktop the containing directory is derived from `application/config/name`
  too (`app_userdata/<project name>/`), so **renaming the project moves every
  save with it**. The rename to *Pix Blast* did exactly that, deliberately and
  before launch. On iOS and Android `user://` is the app sandbox and does not
  follow the name, so shipped devices are unaffected — but a desktop rename
  after launch would strand local data.
- **`ios/plugins/` cannot move.** Godot hardcodes `res://<platform>/plugins`.
