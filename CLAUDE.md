# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

This file is the orientation layer: what the project is, how to run and verify
it, and where to read more. Detail lives in `docs/` so this stays short — it is
loaded into context on every turn.

## Project

**Pix Blast** — a drag-and-drop block puzzle (Block Blast / 1010!-style) built
in **Godot 4.7.2**, targeting Android and iOS in portrait. Drag cards from a
five-slot tray onto the board; filling a row or column clears it. The run ends
when nothing left in the tray fits anywhere.

Beyond that core: thirteen powers earned through a level-gated skill tree,
four game modes, three themes, a local leaderboard and Apple Game Center.

## Repository map

```
autoload/     the 7 singletons -- 1:1 with project.godot's [autoload] block
rules/        board, blocks -- game logic, no presentation dependency
scenes/       one screen = .tscn + .gd, plus the MenuScreen base they share
ui/           background, theme.tres; widgets/ effects/ fonts/ pixel/
platform/     device shims (haptics)
assets/       audio and store icons
tools/        asset generators, and the path audit
docs/         everything below
```

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

# AFTER EVERY iOS EXPORT, before archiving in Xcode. Godot rewrites
# ios/pixblast/pixblast-Info.plist on every export, so this is not a one-off:
# it drops UIRequiresFullScreen (deprecated in iOS 26, and what made iPadOS
# run the game in a compatibility window) and the empty NS*UsageDescription
# keys the App Store rejects. Idempotent.
python3 tools/fix_ios_plist.py
```

There is no test framework, linter, or build script. Verification is done by writing a throwaway scene + script, running it, and deleting it — see below.

### Verifying a change

```bash
# After ANY file moves. Three classes of path in this project fail silently.
"$GODOT" --headless --path . res://tools/audit_paths.tscn
```

The full harness recipe, its four gotchas, and how to capture screenshots are in
**`docs/testing.md`**.

## Where to read more

| Document | Covers |
|---|---|
| **`docs/invariants.md`** | **Rules that break things silently. Read this before changing anything.** |
| `docs/architecture.md` | Scene flow, autoloads, the three-way split, input, layout, mobile |
| `docs/powers.md` | The thirteen powers, how to register a new one, atmospheres |
| `docs/progression.md` | Levels, the skill tree and its gates, modes, the 2x session |
| `docs/theming.md` | The theme registry, pixel geometry, regenerating artefacts |
| `docs/testing.md` | The throwaway-scene harness, gotchas, screenshots, the audit |
| `docs/history.md` | What was removed and why -- difficulty, the Tetris prototype |
| `docs/gamecenter.md` | Game Center setup that cannot be done from this repo |
| `docs/plan/tutorial.md` | How the game teaches itself: the coach ladder and the free bomb |
| `docs/plan/` | Forward-looking proposals, not descriptions of what exists — each carries a status banner |

## The one thing to know first

Most of this project's file references are plain strings with **no UID
protection**, and three classes of them fail with no error at all: `App`'s
`SCENE_*` route constants, the runtime-assembled directory prefixes in `Audio`
and `Themes`, and `Themes.DEFS[*]["ui_theme"]`. A broken one looks exactly like
a working game until you navigate to the wrong screen.

So after moving any file, "it still runs" proves nothing. Run the audit.

## Known gaps

- Game Center is code-complete but **not usable until the iOS plugin is installed and App Store Connect leaderboards exist** — see `docs/gamecenter.md`. Leaderboard IDs live only in `GameServices.LEADERBOARDS`.
- The leaderboard tags every row with its mode and filters by it.
- `scenes/profile.tscn` shows level, XP, streak and the power **skill tree** (in a `ScrollContainer`, so it grows without a layout change), and is where the loadout is chosen — deliberately a pre-run decision, so `game.gd` never grows a second modal input state.
- `scenes/mode_select.tscn` covers Palette, Big Palette, Sprint and Puzzle. Daily and the tile-set row from the design are not built.
- `scenes/settings.tscn` follows the design's card-row layout: music, sound, music volume, grid lines, haptics. The design's RESTORE PURCHASES is not built — there is no IAP.
- Effects are still placeholders from `tools/gen_audio.py`. Music is by Abstraction (https://abstractionmusic.com/) and is credited on the About page — that credit is a licence obligation, so do not remove it. Confetti is silent.
- Music files must **not** loop — the playlist advances on `finished`, so a looping track would never hand over. `Audio._set_loop` clears the flag on every track it plays. If you ever do need a looping WAV, setting `loop_mode` without also setting `loop_end` yields a zero-length loop: `playing` stays true, the position never advances, and the track is silent. `--headless` and Movie Maker both use the Dummy audio driver, so audio bugs only surface in a real windowed run.
- The leaderboard is local-only; there is no backend or platform integration.
- An iOS export preset exists (`export_presets.cfg`, target `ios/pixblast.ipa`); no Android preset is configured. The build is **universal** (`TARGETED_DEVICE_FAMILY = "1,2"`) and lays out correctly on iPad, which gets extra width and the same design height. **`min_ios_version` is `26.0`**, which is very restrictive — it is the reach limit, not a layout one. **`ios/` is gitignored by design** (612 MB of regenerated export output, including two `libgodot.a` slices over GitHub's 100 MB file limit), so **Xcode Cloud cannot build this repo** — release by exporting locally and uploading via Organizer/Transporter. See `docs/history.md`. Godot 4.7.2's iOS **simulator** slice is x86_64-only while Xcode 26 simulators are arm64-only, so the simulator cannot run this on Apple Silicon — use a physical device or the macOS build.
