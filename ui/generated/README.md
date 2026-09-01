# Generated — do not hand-edit

Everything in this directory is produced by a script in `tools/`. Edits here are
overwritten the next time one runs. Change the source, then regenerate.

| Artefact | Produced by |
|---|---|
| `sprites/*.png` | `python3 tools/gen_pixel_sprites.py` |
| `theme_pixel.tres`, `theme_pixel_dark.tres` | `"$GODOT" --headless --path . res://tools/gen_pixel_themes.tscn` |
| `boot_splash.png`, `icon.png` | `python3 tools/gen_branding.py` |

`gen_pixel_themes` reads its colours from `Themes.DEFS` in `autoload/themes.gd`,
so a palette change means re-running it. `gen_branding.py` also writes the store
icons to `assets/icons/` — those are derived from `ROOT`, never from this
directory, so moving this directory cannot silently redirect them.

`ui/theme.tres` is deliberately **not** here: it is hand-maintained, and being
the loose file next to this directory is the signal. Note that
`gen_pixel_themes` does mutate it in place to inject the type variations.
