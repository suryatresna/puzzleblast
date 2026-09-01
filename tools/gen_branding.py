#!/usr/bin/env python3
"""Generate the boot splash and app icons from the title mark.

The mark is the design's nine tiles laid out six across; the same layout the
game draws at runtime in `scripts/logo_mark.gd`. These are baked images rather
than runtime draws because Godot needs a file for `boot_splash/image` and
`config/icon`, so they are pinned to the SHIPPED palette (Themes.ACTIVE =
PIXEL_DARK). Re-run after changing that.

Icon sizes:
  * 1024 -- App Store. Saved as RGB with **no alpha channel**: Apple rejects
    icons that carry one, even when it is fully opaque.
  * 512  -- Google Play, and the Godot project icon. 32-bit RGBA.

The tile is drawn at `side // 8`, so 128px at 1024 and 64px at 512. Both are
whole multiples of the 32px logical tile the art was authored at, which keeps
the pixel grid exact at either size rather than resampling it.

Run:  python3 tools/gen_branding.py
"""
import os
from PIL import Image

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..")
# Every output is derived from ROOT, never from another output directory. The
# store icons used to be written as a join against OUT ("../assets/icons/..."),
# so moving OUT silently redirected them -- and save() makedirs, so it would
# have succeeded and quietly stopped regenerating the App Store icon.
TILE = os.path.join(ROOT, "ui", "generated", "sprites", "tile_dark.png")
OUT = os.path.join(ROOT, "ui", "generated")
ICONS = os.path.join(ROOT, "assets", "icons")

# Pixel Dark tile tints: 0 blue, 1 olive, 2 rust, 3 ochre
TINTS = ["#8fa9a1", "#a8842f", "#d0603a", "#e8bc61"]
BG = "#17120f"          # Pixel Dark BG BASE

# Grid position -> palette index, matching logo_mark.gd
CELLS = [((0, 0), 0), ((1, 0), 0), ((2, 0), 3),
         ((3, 0), 2), ((4, 0), 2), ((5, 0), 1),
         ((0, 1), 1), ((1, 1), 1), ((2, 1), 3)]
COLS, ROWS = 6, 2


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def tint(img, c):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    p, q = img.load(), out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = p[x, y]
            q[x, y] = (r * c[0] // 255, g * c[1] // 255, b * c[2] // 255, a)
    return out


def mark(cell):
    """The mark at `cell` px per tile, on a transparent ground."""
    gap = max(1, cell // 8)
    step = cell + gap
    w = COLS * cell + (COLS - 1) * gap
    h = ROWS * cell + (ROWS - 1) * gap
    src = Image.open(os.path.abspath(TILE)).convert("RGBA")
    tiles = {i: tint(src.resize((cell, cell), Image.NEAREST), hx(TINTS[i]))
             for i in set(i for _, i in CELLS)}
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for (cx, cy), i in CELLS:
        out.alpha_composite(tiles[i], (cx * step, cy * step))
    return out


def build_icon(side):
    """Square icon: the mark centred on the theme's base colour."""
    cell = side // 8              # 128 at 1024, 64 at 512 -- both 32*n
    m = mark(cell)
    icon = Image.new("RGBA", (side, side), hx(BG) + (255,))
    icon.alpha_composite(m, ((side - m.width) // 2, (side - m.height) // 2))
    return icon


def save(img, name, absolute=False):
    path = os.path.abspath(name if absolute else os.path.join(OUT, name))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("  %-30s %4dx%-4d %s %5.1f KB"
          % (os.path.basename(name), img.width, img.height,
             img.mode.ljust(4), os.path.getsize(path) / 1024))


if __name__ == "__main__":
    # Boot splash: the mark centred on the theme's base colour. Godot scales
    # this to the screen, so it only needs to be crisp at its own size.
    m = mark(32)
    splash = Image.new("RGBA", (m.width + 64, m.height + 64), hx(BG) + (255,))
    splash.alpha_composite(m, (32, 32))
    save(splash.resize((splash.width * 2, splash.height * 2), Image.NEAREST),
         "boot_splash.png")

    # App icons. The mark is a wide 6x2 block sitting on the vertical centre,
    # so the rounded-corner mask every platform applies cuts only background.
    for side in (1024, 512):
        icon = build_icon(side)
        # The store icons live together; ui/icon.png is what project.godot
        # points at for the editor and desktop window.
        if side == 1024:
            # No alpha: the App Store rejects an icon that has the channel at
            # all, opaque or not.
            save(icon.convert("RGB"), os.path.join(ICONS, "icon_1024.png"),
                 absolute=True)
        else:
            save(icon, os.path.join(ICONS, "icon_512.png"), absolute=True)
            save(icon, "icon.png")
