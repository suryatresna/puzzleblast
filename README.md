# ComplexPuzzle

A drag-and-drop block puzzle for Android and iOS, built with **Godot 4.7.2**.

Five cards sit in a tray at the bottom of the screen. Drag one onto the 8×8 board; fill any row or column and it clears. The tray refills once all five are spent, and the run ends when nothing left in your hand fits anywhere.

| Menu | Line clear | Bomb | Leaderboard |
|:---:|:---:|:---:|:---:|
| ![Main menu](screenshots/menu.png) | ![Clearing four lines at once](screenshots/line-clear.png) | ![Bomb clearing the bottom half](screenshots/bomb.png) | ![Leaderboard](screenshots/leaderboard.png) |

## How it plays

**Placing.** Drag a card from the tray onto the board. The piece is drawn slightly *above* your finger so your thumb doesn't cover it, and a ghost shows where it will land — white when it fits, red when it doesn't. Release outside a legal spot and the card returns to its slot. Pieces never rotate; what you see in the tray is what you place.

**Clearing.** Any full row or column disappears. A piece can complete several lines at once, and a cell sitting on both a full row and a full column only counts once.

**Running out.** Cards that no longer fit anywhere are greyed out, so you can see trouble coming. When none of your remaining cards fit, the game ends.

### Scoring

| Action | Points |
|---|---|
| Placing a piece | 1 per cell |
| Clearing lines | `100 × lines² × combo` |
| Bomb blast | 5 per cell destroyed |

Clearing **two lines at once** is worth far more than two separate clears — `100 × 2² = 400` against `100 + 100`.

**Combo** builds when you clear on consecutive placements and resets the moment you place without clearing. It caps at ×5. Chaining three single clears scores 100, then 200, then 300.

### Bombs

A bomb is a single red card that **wipes the half of the board it lands in** — top or bottom, split down the middle, so you aim it at whichever half is worse. It scores 5 points per cell it destroys and leaves your combo streak untouched.

Bombs arrive two ways:

- **Randomly** — a 20% chance per tray refill, roughly one every five hands (about every 24 placements).
- **Earned** — reach a **×2 combo** and one drops into your tray.

You'll never hold more than one at a time, and a streak grants at most one bomb however long it runs.

### Leaderboard

Every finished run is recorded. The top 10 are kept with score, lines cleared and date, and the run you just played is highlighted. Scores persist to `user://scores.cfg` and are local to the device.

## Running it

Requires **Godot 4.7.2**. The project uses no external dependencies or build steps.

Open `project.godot` in the Godot editor and press Play, or from the command line:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

The game starts at `scenes/splash.tscn`. It's designed for 1080×1920 portrait; on desktop it opens in a half-size window so it fits on a monitor.

To jump straight to a screen while working on it:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/game.tscn
```

## Layout

```
scenes/     screens: splash, main_menu, game, leaderboard, settings, about
scripts/    app (routing) · scores (leaderboard) · board (rules)
            blocks (piece data) · effects · piece_view · safe_area_margin
ui/         theme.tres, background, icon/logo, effects/ (particle scenes)
```

Two autoloads carry global state: **`App`** owns scene routing and the fade between screens, **`Scores`** owns the leaderboard and is the single source of truth for the best score.

The play screen keeps rules and presentation apart. `board.gd` holds the grid, placement legality, clearing, scoring and the "no moves left" test, and reports what happened through signals — it never touches the UI. `game.gd` listens and turns those signals into HUD updates, particles and screen shake.

Pieces come from 15 base shapes in `blocks.gd`; rotations are generated at load and de-duplicated into 37 distinct pieces. Adding a shape means adding one line.

## Platform notes

- **Portrait**, 1080×1920 design resolution, with `canvas_items` stretch so it adapts across phone aspect ratios.
- **Safe areas** are handled on Android and iOS — notches, rounded corners and the home indicator are folded into the layout margins.
- **Metal** is the renderer on macOS and iOS. Godot 4.7 has a native Metal backend and selects it by default; no configuration is needed.
- The **Exit** menu entry is hidden on iOS, since Apple's review guidelines reject apps that quit themselves.
- Godot 4.7.2's iOS **simulator** library is x86_64-only while Xcode 26 simulators are arm64-only, so the simulator cannot run this on Apple Silicon. Test on a physical device, or use the macOS build — it exercises the same Metal backend.

## Status

Playable end to end: splash, menu, a full game with bombs and combos, game over, and a persistent leaderboard.

Not done yet:

- **No audio.** Every moment — placing, clearing, the bomb, the confetti — is silent. This is the most noticeable gap.
- **Settings** is a navigable placeholder with no working options.
- The leaderboard is **local only**; there's no backend or Game Center / Play Games integration.
- **No export presets** are configured, so there is no Android or iOS build set up yet.

`scripts/playfield.gd`, `tetromino.gd`, `next_preview.gd` and `input_actions.gd` are leftovers from an earlier falling-block prototype. Nothing references them and they can be deleted.
