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

## Rejected: Xcode Cloud

**Xcode Cloud cannot build this repository, and adding it would mean committing
a Godot export.** Releases are made by exporting from Godot locally and
uploading through Xcode Organizer or Transporter.

Xcode Cloud builds from what is pushed, and `ios/` is gitignored on purpose:
Godot regenerates the whole directory on every export, and it comes to
**612 MB**. What a build would actually need is the generated project (40 KB),
the app sources (652 KB), `pixblast.pck` (19 MB), `MoltenVK.xcframework`
(20 MB) and `pixblast.xcframework` — **409 MB of Godot engine**.

That last one is not merely large. It holds two `libgodot.a` slices of 211 MB
(device) and 198 MB (simulator), and **GitHub refuses any file over 100 MB**,
so a push carrying them is rejected outright. Git LFS is the usual answer and
does not help here: Xcode Cloud does not support it.

Both remaining routes require `ci_scripts/ci_post_clone.sh` to download the
Godot toolchain — roughly 1 GB of export templates on every build — either to
restore the engine into a partly committed project, or to regenerate the
project outright. The second also has to survive Xcode Cloud validating the
project path when the workflow is configured, which happens before any script
of ours has run.

For a Godot project the cost is not worth it: Xcode Cloud is built around
native Xcode projects, where the sources in the repo *are* the build. Here they
are an export artefact.

Two things worth knowing if this is ever revisited:

- The generated `pixblast.xcodeproj` contains **no absolute paths** and its
  scheme is already shared, so it is genuinely portable — the blocker is the
  engine binary, nothing else.
- The **simulator slice is dead weight**: 198 MB, and on Godot 4.7.2 it is
  x86_64-only, so it cannot run on an Apple Silicon simulator regardless.
  Dropping it halves the framework, though it stays over the 100 MB limit.
