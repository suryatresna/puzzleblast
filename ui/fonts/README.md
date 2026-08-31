# Fonts

Both faces are used by the pixel themes and are licensed under the
[SIL Open Font License 1.1](https://scripts.sil.org/OFL), which permits
bundling in an application, including a commercial one.

| File | Family | Source |
|---|---|---|
| `silkscreen.ttf`, `silkscreen_bold.ttf` | Silkscreen — Jason Kottke | https://fonts.google.com/specimen/Silkscreen |
| `pixelify.ttf`, `pixelify_bold.ttf` | Pixelify Sans — Stefie Justprince | https://fonts.google.com/specimen/Pixelify+Sans |

Silkscreen is only crisp at multiples of its 8px design grid, so it is used
only where a theme resource owns the size (buttons). Pixelify Sans is the body
face because the scenes carry per-node sizes that are not multiples of 8.

Re-download with:

```bash
curl -A "Mozilla/4.0" "https://fonts.googleapis.com/css2?family=Silkscreen:wght@400;700"
```

A modern browser UA gets woff2 back instead of ttf.
