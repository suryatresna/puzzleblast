# Theming

Three themes, the registry that owns them, and the generated artefacts they
depend on.

## Theming

Three themes are defined — **Classic**, **Pixel Warm** and **Pixel Dark**. `Themes.ACTIVE` (`PIXEL_DARK`) is what a fresh install ships with and the only one available until `Progress` unlocks more by level; the settings screen offers whatever `Progress.unlocked_themes()` returns. The choice **is** persisted. Use `Themes.peek()` rather than `set_current()` anywhere that walks every palette — the theme generator and tests — so it does not leave the player on the last one touched.

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

**Branding.** The title mark is the design's nine tiles laid out six across, drawn at runtime by `scripts/logo_mark.gd` from the live block sprite so it follows the palette rather than being a flat image. It appears on both `splash` and `main_menu`. The wordmark is the game name stacked one word per line via `App.game_wordmark()` — derived from the project name, so a rename carries through — styled by the `WordmarkLabel` variation (accent colour plus the design's hard 12px offset shadow). The boot splash and app icons are baked from the same layout by `tools/gen_branding.py` and pinned to the shipped palette (`Themes.ACTIVE`), so regenerate after changing it. Icons: `assets/icons/icon_1024.png` for the App Store — **RGB with no alpha channel**, which Apple requires and which the iOS preset's `icons/icon_1024x1024` slot points at — and `assets/icons/icon_512.png` for Google Play (RGBA). `ui/icon.png` is the same 512 image, and is what `config/icon` uses for the editor and desktop window. Each size draws the tile at `side // 8` (128 and 64), both whole multiples of the 32px logical tile, so the pixel grid stays exact instead of being resampled.

**Surfaces are two-stop gradients.** Every panel, button and backdrop in the design is a vertical `linear-gradient(180deg, top, bottom)`. Rather than store both stops, the nine-patch sprite carries the *ramp* and the theme names only the **top** colour — tinting reproduces the bottom stop. The ramp differs per mode (light panels fall to ~0.90 of the top, dark ones to ~0.62), which is why `panel.png` and `panel_dark.png` are separate sprites. `bg_stops` likewise stores just the design's two endpoints; `background.gd` samples that ramp at each gradient point's own offset, so a 2-stop theme and a 3-stop one both work.

**Settings rows** are built in code from a table in `settings.gd`, not laid out in the `.tscn` — they are repetitive and data-driven. Three shapes: a switch row (`scripts/toggle_switch.gd`), a slider row (`scripts/segment_slider.gd`, the design's 8 discrete segments) and a read-only note card. Both controls take their geometry from the design doubled twice, and their colours from `Themes`. Cards use the `CardPanel` variation: a flat fill with a hard ink border, distinct from the gradient nine-patch the HUD and tray use.

Watch the token names: `#241C16` is the dark **panel**, but the dark **board** is a step darker at `#201914`. The board also carries an ink frame outside the grid (`board_border`), which is the design's `box-shadow: 0 0 0 4px` — 4px at the mockup's 2x, so 2 logical px, 8 in our space.

**The grid size is variable, and the cell snap is conditional.** `cell_size()` prefers a whole multiple of the 32px sprite (`SPRITE_PX`) so tiles scale by an exact integer — 8 across gives 128px cells (4x) — but only while that costs less than `MAX_SNAP_WASTE` (10%) of the available width. A 12-wide board would snap to 64px and fill barely 70% of the screen, leaving a quarter of it dead; it takes 87px at 2.7x instead. The tiles are a smooth gradient with a thick outline rather than fine pixel detail, so the resampling is hard to see while a board a third smaller is impossible to miss.

`base_margin` on the game screen is 16. Note that shrinking it further does **not** enlarge an 8x8 board: 128px is the largest exact multiple that fits, and the next (160) would need 1280px. Because the snapped grid can be narrower than the control, the board panel and its ink frame are drawn around the **grid extent**, not around `size`.

**Pixel geometry.** The design is 270×480 with 32px tiles; the game runs at 1080×1920, exactly 4×. Sprites are therefore generated pre-upscaled (a 32px tile is stored at 128px) rather than relying on filtering — `StyleBoxTexture` nine-patch margins are measured in texture pixels and are *not* scaled when drawn, so a 48px plate with a 12px margin would render tiny corners. `base_margin = 28` on the game screen gives a 1024px board and exactly 128px cells. Under a pixel theme `cell_size()` floors, `grid_origin()` centres the remainder, and `shake_offset` rounds to whole pixels.
