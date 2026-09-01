# Prompt: convert Pixel Blast to pixel art

> **Status: delivered.** The pixel themes described here shipped as Pixel Warm and
> Pixel Dark. See `docs/theming.md`.

Hand this to an agent (or follow it yourself) to re-theme the game as pixel art.

This conversion has been done once already and then reverted on request, so
everything below is measured rather than guessed — including the mistakes.
Read the **Traps** section before writing any code; four of the five cost real
debugging time the first time round.

---

## Goal

Re-theme **Pixel Blast** — an 8×8 drag-and-drop block puzzle — as **modern
pixel art with a smooth colour palette**. Keep the existing deep indigo /
violet / cyan feel; this is not a retro NES-palette exercise. Smooth gradients
are explicitly in scope and should *not* be dithered.

Gameplay, rules, scoring and difficulty must be untouched. This is a
presentation change only.

## Where the project starts

| Thing | Current state |
|---|---|
| Design resolution | 1080×1920, `stretch/mode="canvas_items"`, `aspect="expand"` |
| Texture filter | engine default (linear) |
| Board | `SIZE = 8`, cell size derived from width — currently **127px** |
| Blocks & sockets | drawn procedurally with `draw_style_box` rounded rects |
| Power glyphs | drawn with `draw_line` / `draw_circle` in `blocks.gd` |
| Buttons & panels | `StyleBoxFlat` in `ui/theme.tres` |
| Font | engine default, no custom font |
| Particles | `CPUParticles2D`, sizes in 1080-space |

Asset generation is available through the **PixelLab MCP** (`create_image_pixflux`,
`create_font`, `create_ui_asset`). Check `get_balance` first.

---

## Phases

Do these in order and verify after each. Phase 1 alone will look *worse* than
what you started with — flat colours at low resolution — but it is the
substrate everything else depends on, so confirm it before spending
generations.

### 1. Foundation — no assets

```
window/size/viewport_width=270
window/size/viewport_height=480
window/stretch/mode="viewport"
window/stretch/aspect="keep_height"
rendering/textures/canvas_textures/default_texture_filter=0
```

270×480 upscales by exactly ×4 to 1080×1920 and by whole numbers to most
phone heights. `viewport` stretch renders the whole frame small and scales it;
`canvas_items` re-renders UI at native resolution and defeats the look
entirely.

Then rescale every hardcoded size by 4 — font sizes, margins, separations,
`custom_minimum_size`, corner radii, offsets. Set all `border_width_*` to 1.

**Set `base_margin = 7` on the game screen's SafeArea.** That gives
`270 − 14 = 256`, so cells land on exactly **32px** — the right size for a
32×32 tile drawn 1:1. At the default margin you get 31.75px cells and every
tile is resampled, which defeats the exercise.

Make the board snap to whole pixels:

- `cell_size()` returns `floor(size.x / SIZE)`
- add a `grid_origin()` that centres the leftover pixels
- round screen shake to whole pixels in `game.gd`

### 2. Font — 0 generations

Use **Geist Pixel** from Google Fonts. Do not generate one; two attempts at
generating a font were worse than the free option and cost 50 generations.

```bash
curl -s "https://fonts.googleapis.com/css2?family=Geist+Pixel"   # gives the ttf url
```

Import it, set `antialiasing=0`. Godot detects it as a pixel font and disables
subpixel positioning and hinting on its own. Hang it off `ui/theme.tres` as
`default_font` so every control picks it up at once.

Type scale: **8 / 16 / 24 / 32**. Geist Pixel is narrow — `Pixel Blast` is only
125px at size 24 — so titles can sit at 32 comfortably.

### 3. Core sprites — ~6 generations

Generate at **32×32**, `no_background=true`, `outline="selective outline"`,
`shading="basic shading"`, `detail="low detail"`.

- **1 block tile**, near-white with a top-left highlight and bottom-right bevel
- **1 socket** for empty cells, dark and recessed
- **4 power glyphs**: bomb, collapse (three down chevrons), laser (a plus of
  two full-width beams), fit (four arrows pointing outward)

**Generate one tile, not twelve.** Draw it with
`draw_texture_rect(tex, rect, false, Blocks.COLORS[value])` — the near-white
art multiplies straight to the palette colour and keeps its shading. Twelve
separate sprites would drift apart visually and need regenerating every time
the palette moves.

Inset the power glyphs to about **62%** of the tile. Drawn edge to edge the
dark ink swallows the colour and every power reads as the same murky square.

### 4. UI chrome — ~2 generations

Generate at **48×48** with evenly rounded corners:

- **1 button plate**, near-white
- **1 panel frame**, dark hollow centre

Convert `ui/theme.tres` from `StyleBoxFlat` to `StyleBoxTexture` with
`texture_margin_* = 12` (nine-patch). Tint per state with `modulate_color` —
one sprite covers normal / hover / pressed / disabled / focus.

Avoid `create_ui_asset` here; it costs 20–40 generations and returns a whole
panel you then have to slice.

### 5. Effects — ~1 generation

The particles are already square chips and read fine as pixel art. Only two
things need doing:

- Replace `ui/effects/flower.svg` with a generated 32×32 pixel blossom.
- **Rescale the particle sizes that no code path overrides.** Most derive from
  `cell` and rescale for free; these do not, and will render 4× too large:

  | File | Field |
  |---|---|
  | `ui/effects/confetti.tscn` | `scale_amount_min/max` |
  | `ui/effects/spark_burst.tscn` | `scale_amount_min/max` |
  | `scripts/effects.gd` ~line 212 | `burst.scale_amount_*` (morph sweep) |
  | `scripts/effects.gd` ~line 300 | flower scale — a 32px sprite needs ~0.12–0.30, not 0.45–1.0 |
  | `scripts/effects.gd` ~line 305 | `8.0 + tier * 2.0` style literals |

  Find them with: grep for `scale_amount` in `effects.gd` and check which are
  written as `cell * n` (fine) versus bare numbers (need dividing).

### 6. Background — probably nothing

The backdrop is a smooth gradient with a runtime tint system driving the combo
colour flow. **Leave it.** The brief asks for smooth colour, and banding it
would fight that while also breaking `background.gd`'s tint lerp.

---

## Traps

Every one of these was hit for real.

**Don't run overlapping regexes when rescaling.** Patterns like
`font_size = (\d+)` and `font_sizes/font_size = (\d+)` match the *same* text.
Applied in sequence they divide twice, and the whole UI silently collapses to
the minimum size — titles end up smaller than body text. Use one
non-overlapping pass, and diff the result before moving on.

**Take a backup you have verified exists.** `cp -r a b c dest` fails silently
when `dest` does not exist. Confirm the backup before destructive edits; the
first attempt at this conversion was saved only by a fallback path.

**Containers reset `scale` and `rotation` on every re-sort.**
`Container.fit_child_in_rect()` clears both. Any label that animates its scale
*and* changes its text — the score counter, for one — will have the animation
wiped on the frames where the text's minimum size changes. Fix structurally:
put the animated label inside a plain `Control` wrapper rather than directly in
the container. This is not fixable with tween settings; it was chased through
four wrong hypotheses.

**A Label outside a container has `size == (0, 0)`** until you call
`reset_size()`. Any width measurement — fitting a banner to the screen, say —
silently no-ops without it.

**Bold pixel fonts at 8px have no room for counters.** A generated Bold face
renders `0` as a solid block, which is fatal for a score display. If generating
at all, use Regular. Better: use Geist Pixel and skip the problem.

---

## Verification

After each phase, run a headless check that asserts rather than eyeballing:

- viewport is 270×480
- `cell_size()` is a whole number and ≥ 8
- every `cell_rect()` lands on integer pixel positions
- no `Label` or `Button` text is wider than 270px with autowrap off
- all six screens instantiate
- a full automated playthrough still reaches game over and records a score
- zero warnings in the run output

For screenshots use **Movie Maker mode** — a backgrounded macOS window has its
rendering suspended, so viewport readbacks come back byte-identical:

```bash
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --path . res://_shot.tscn --write-movie out/f.png --fixed-fps 60 --disable-vsync
```

The game auto-pauses on focus loss, so a capture harness must force
`%PausePanel.hide()` every frame or you will screenshot the pause overlay.

---

## Budget

The first run of this cost **9 generations** for art (plus 75 wasted on fonts
that Geist Pixel made unnecessary). Budget **~10–15** and check `get_balance`
first. The saving comes entirely from tinting one sprite per role instead of
generating one per variant.
