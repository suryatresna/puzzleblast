# Powers

The thirteen powers, how they are registered, and what each one does.

## Pieces

`scripts/blocks.gd` holds 18 base shapes in `BASE`, including three diagonals; rotations are **generated at load** and de-duplicated, producing 37 pieces. To add a shape, add one line to `BASE` — do not hand-write rotations. Pieces are plain `Dictionary` values: `{cells, color, size, weight}`, plus `power` for a special.

**Thirteen powers**, in `Blocks.Power`: bomb, collapse (`MORPH`), laser, fit, diagonal, blackhole, thunder, teleport, meteor, tsunami, earthquake, shuffle and rewind. `Blocks.COLORS` is a flat 21-entry table — eight shape colours then thirteen power colours — and `Blocks.POWER_COLOR` maps each power to its index (8..20). **`board.gd` indexes `Themes.palette()` directly, with no wrap**, so a theme whose `powers` array is short of the highest index is an out-of-range crash, not a wrong colour. Adding an eleventh means an entry in every theme's `powers` array, a glyph in `Themes.GLYPHS`, a sprite from the generator, a branch in `Board._fire_power` **and** one in `Blocks.draw_power`, plus `ALL_POWERS`, `POWER_NAMES`, `Progress.COST` and a `"power"` grant in `Progress.REWARDS`. Both matches are written `Blocks.Power.X` in board.gd and `Power.X` in blocks.gd; miss one and the power is dealt but silently does nothing.

The three newest differ from the first five in kind, not just in numbers:

- **Blackhole** takes a *disc* — a Euclidean radius — where the bomb takes a square, so its corners survive. Levels are supersets for free, since a larger radius contains the smaller.
- **Thunder** strikes random *occupied* cells and ignores where it was dropped. It is the only power whose reach cannot be a superset cell-for-cell; the ramp is monotonic in expectation instead. It is the answer to a board too full to place into.
- **Teleport** is the only power that *rearranges* rather than removes: it lifts the span×span block at the target and sets it down where it fits, preferring destinations that complete lines at level 3+. It is also the first power that can **misfire** — a full board has nowhere to put the block — which is why `_fire_power` and `place()` return `bool`. A misfire restores every block exactly and returns false, and `game.gd` reads that as a free cancel.
- **Rewind** is the only power that looks backwards, and the only one that is not an action: it restores the board **and the tray** to a previous moment. `board.gd` keeps no history — it just hands out plain data via `snapshot()`/`restore()` — because the tray lives in `game.gd`, which owns the ring buffer and pushes an entry before every board-mutating action. Restoring the board without the tray would take the placed piece off the board *and* leave the slot spent.

  `snapshot()` **deep**-copies `_grid` (`duplicate(true)`); a shallow copy shares the row arrays, so the snapshot would silently track the live board and a rewind would look like a no-op. It carries `lines` as well as `score` and `combo` — `lines` goes on the leaderboard.

  Two things are deliberately *not* restored, and both are load-bearing. **`board.best` and `game.gd._banked`** are high-water marks; restoring them would let the same points bank as XP twice (`_bank()` only sends deltas above `_banked`, and `Progress.add_score` has no un-bank path and saves to disk immediately). **Charge and power uses** are spent for good — which is what prices out the loop: rewind restores the board but not the charge a combo paid, so clear → rewind → re-clear only loses money while `COST[REWIND] > max(CHARGE_PER_COMBO)`. That is a constraint, not a balance preference; there is a test asserting it. A refused cast calls `_drop_history()` so a misfire cannot leave a phantom step that rewinds to where the player already is.

  Sprint's fuse is restorable state (`fuse_bar.gd` accumulates pure delta) and is deliberately left alone — rewinding time would make the mode meaningless.

  Its effect is a **held state**, not a bang — see *Power atmospheres* below.

- **Meteor** and **tsunami** are the only powers that *add* blocks, so they are the only ones that can make the board worse. Both take a **share of whatever is still empty** rather than a fixed cell count, from `FILL_SHARE_BY_LEVEL` — 50%, 70%, 95%. That is the whole range the mechanic expresses, so **these two cap at 3 levels, not 5**: `Progress.POWER_MAX_LEVEL` holds the exceptions, `max_level_of()` is what the profile and `level_of()` clamp against, and `Board._lvl_in()` is the clamp for a table shorter than `MAX_POWER_LEVEL` (using `_lvl()` on one would run off the end).

  They differ only in *which* empty cells they take. Meteor picks greedily by line pressure, counting cells already queued in the same cast (`_pending_pressure` — without it the greedy order keeps picking from the same untouched row, because nothing has been written yet). Tsunami floods bottom-up, which is its aim: the lowest gaps are the rows a run leaves most nearly complete.

  Both obey one invariant: **at least `FILL_FLOOR_ROWS` rows' worth of cells are still empty once the lines they complete have cleared.** `_check_game_over()` runs after *every* drag end including a power fire, so without it a tsunami could end the run on the shot the player just paid for. `_empties_after_fill()` simulates the clear exactly and `_safe_fill_size()` walks the request down to the largest size that holds — exact rather than conservative, so a 95% cast is honoured whenever it is safe. Safety is **not monotonic** in fill size (filling more can clear more and end up emptier), which is why that walk starts at the request rather than growing from zero. A cast with no safe size returns false and is refunded, like a teleport misfire.

- **Earthquake** moves what is already there: blocks hop one cell into whichever neighbour packs them tighter, over and over, and the shaking **stops the moment a line completes**. Only strictly improving moves are taken, which is both what makes it useful and what guarantees the loop terminates instead of rocking one block back and forth. The budget is an upper bound, not a target — so a higher level need not shake longer on a *different* board. Test the ramp on a **fixed** board, where a higher level runs a superset of the same greedy moves.
- **Shuffle is the one power the board never sees.** It rewrites the tray, and `board.gd` has no idea a tray exists, so `game.gd._fire_power()` intercepts it before `place()` is ever called and its level table (`SHUFFLE_FITTING_BY_LEVEL`) lives there rather than beside the others. `Board._fire_power` still carries an explicit `SHUFFLE: return false` branch, so a wiring mistake shows up as a refund rather than as a power that silently does nothing. It deals pieces that fit the current board (`has_any_move`) and are no bigger than 3×3, guaranteeing more slots as it levels; a board where nothing fits at all refuses and refunds.

  In practice a big fill *gives room back*: measured over 900 random casts the board never fell below one row's worth of empty cells, worst case 37, and a level-3 tsunami left the board emptier in 60 of 60 casts. Measure their level ramps on what they **wrote** (the `meteor_landed` / `tsunami_swept` payload), never on the net change in empty cells.

The **bomb** is a 1×1 special that clears the half of the board it lands in (split on the horizontal midline). It arrives two ways: a 20% roll **per tray refill** (never per card — that could deal three at once), and as a reward for a 2× combo. Both paths respect one invariant: **at most one bomb in hand at a time**.

## Power atmospheres

Every power washes the sky to its own colour and gathers light around the board for a beat. One table drives it — `POWER_ATMOSPHERE` in `game.gd`, `{sky, motes, hold}` per power — and one helper, `_power_atmosphere(power)`, called from each `_on_*` handler. **A new power needs a row here or its cast is silent**; the table is keyed by `Blocks.Power`, so a missing entry is a no-op rather than an error.

- **Nothing holds past 1.6s.** The backdrop is what the board is read against; a colour held longer stops being an accent and becomes the palette. Holds run 0.9s (fit, shuffle) to 1.6s (blackhole, rewind), roughly tracking each power's reach.
- **Light skies must be checked against the HUD.** The score and `best` line are cream, and the top gradient stop lerps 85% of the way to the sky colour. Thunder's cloud started at `0.68` grey and measured *within six values* of the text behind it — the score simply vanished. It sits at `0.46` now, which still reads as a white cloud against the near-black default. Measure luminance rather than eyeballing it: a delta above ~100 against the brightest digit is comfortable.
- `Effects.time_field()` is the only emitter in `effects.gd` that keeps **feeding** rather than firing once. It stops at the hold and then waits one mote lifetime so the last ones fade instead of vanishing; the lifetime scales off the hold, or a short cast leaves motes drifting long after its sky has gone.
- It emits **outward**: `%ComboParticles` sits behind the board, so anything aimed inward is hidden under the board's own panel. The halo therefore reads top-and-bottom — the board is 1048px of a 1080px screen, so the side bands have almost no margin to drift into.
- `_power_glow` is held so a later cast restarts the clock; without it the earlier one's pending restore fires mid-way through and cuts the new sky short. The restore goes through `_restore_flow()`, which also drops a level-up wash — a cast's own colour supersedes it.
- A **refused** cast lights nothing. The atmosphere lives in the `_on_*` signal handlers, which only run when the board actually did something.

## Powers and progression

Powers no longer appear in the tray. They are unlocked by levelling, equipped to a 3-slot loadout on the profile screen, shown in a strip above the tray, paid for with charge earned from combos, and dragged onto the board like any other piece.

- **`board.gd` owns what a power does**, via the level tables next to the scoring constants (`BOMB_BY_LEVEL` and friends). `Progress` owns cost and XP, never geometry — that keeps `board.gd` testable with a bare `Board` and an int, with no autoload to register.
- **Level 2 reproduces each power's pre-progression behaviour.** A maxed power beats what shipped; a fresh one is weaker.
- **Each bomb level must be a strict superset of the last.** That is not automatic: on an 8×8 board a 7×7 blast covers 49 cells against half the board's 32, so "half the board" cannot cap the ramp.
- **`can_target()` gates power placement**, not `can_place()`. Only destructive powers may be aimed at an occupied cell; `MORPH` and `FIT` both assign into `_grid` at the target, so relaxing them would silently recolour a block. `TELEPORT` is the mirror image — it is in `OCCUPIED_POWERS` and requires a block *under* it, since there is nothing to pick up over an empty cell.
- **In `_fire_power`, read the level before spending and spend after `place()` returns.** Spending records a use and can level the power up mid-shot, and a drop the board refuses must not bill the player.
- **`_check_game_over()` replaces the bare `has_any_move` test.** A dead tray does not end the run while a charged power remains. `board.gd` knows nothing about this; `game.gd` decides when to call `declare_game_over`.
- **Score is banked as XP continuously**, not in one lump at game over: `game.gd._bank()` sends only the delta since the last call, so a level can land mid-run and feeding it twice cannot double-count. `_on_game_over` just tops up the remainder.
- A mid-run level-up washes the backdrop in the highlight colour at **0.55**, not the full 1.0 the combo flow uses. That tint *persists* until a combo reclaims it, and the highlight colour is far lighter than the flow colours — at full strength the player reads tiles off a bright gold field.
- The menu's first entry reads **New Game** or **Continue** depending on `Progress.has_progress()`. Both do the same thing — progression always carries over — the label only stops "New Game" reading like a reset.
- Powers are disabled in Puzzle mode — a seeded board plus a levelled bomb is not the same puzzle for two players.
