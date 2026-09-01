# History

Things that were removed or replaced, kept because the reasoning still matters
when someone wonders why the code looks the way it does.

## Removed: the difficulty ramp

`Difficulty` was an autoload that widened four score bands within a run (Easy →
Super Hard), tightening the deal and calling itself out with a banner. It has
been deleted: levelling covers progression now, and by the end only one of its
knobs was still connected. `tray_special` and `combo_power` died with the move
to the charge strip, leaving just `small_bias` — 2.6 for the first 800 points,
1.0 from there — so **the only gameplay it still changed was a gentler opening
deal**. `Blocks.random_piece()` already defaults to a bias of 1.0, so removing
it is the whole change.

The HUD line dropped its suffix (`best 8420 · Super Hard` → `best 8420`); the
level and XP bar in the top bar say what the old band suffix used to.

Old leaderboard rows still carry a `level` string from it. `scores.gd` never
reads the field, so nothing needs migrating.

## Removed: the Tetris prototype

`playfield.gd`, `tetromino.gd`, `next_preview.gd` and `input_actions.gd` were
leftovers from an earlier falling-block prototype, orphaned for a long time and
deleted in the restructure. `tetromino.gd` was preloaded by the other two, so it
looked referenced until they went first -- delete order mattered.
