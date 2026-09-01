#!/usr/bin/env python3
"""Generate the Pixel Blast pixel-art sprites.

Everything here follows the tile recipe in `docs/plan/pixelart.md` /
"Pixel Blast Theme.dc.html":

    background: linear-gradient(155deg, c0, c1 55%, c2)
    inset  0  hi 0 rgba(255,255,255,.45)   top highlight
    inset  0 -hi 0 rgba(0,0,0,.16)         bottom bevel
    inset hi   0 0 rgba(255,255,255,.14)   left highlight
    1px ink outline, radius = round(px/10)

Sprites are authored at their LOGICAL size (32 for a tile, 48 for a
nine-patch plate) and upscaled x4 with NEAREST, because the game runs at
1080x1920 -- 4x the design's 270x480. Upscaling at generation time keeps the
pixel grid exact and means StyleBoxTexture nine-patch margins stay in
proportion (they are measured in texture pixels and are NOT scaled when
drawn).

Tiles are near-white so one sprite serves every colour, tinted at draw time:
    draw_texture_rect(tex, rect, false, LIGHT[v])
The stored gradient is normalised against the LIGHT stop, so tinting with the
light colour reproduces the mid stop at 55% and the dark stop at the bottom.

Run:  python3 tools/gen_pixel_sprites.py
"""
import math, os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "ui", "generated", "sprites")
SCALE = 4          # 270x480 design -> 1080x1920 runtime
TILE = 32          # logical tile size
PLATE = 48         # logical nine-patch plate size

# Normalised gradient stops, measured from the design's four ramps.
# Mean of c0/c1 across the palette is ~1.125, of c2/c1 ~0.825; expressed
# relative to the LIGHT stop that becomes 1.0 / 0.889 / 0.733.
G_LIGHT, G_MID, G_DARK = 1.0, 0.889, 0.733
MID_STOP = 0.55


def rounded_mask(size, radius):
    """A hard-edged rounded-rect mask. No antialiasing -- this is pixel art."""
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1],
                                        radius=radius, fill=255)
    return m


def gradient_155(size):
    """Luminance ramp along the design's 155deg axis, as floats."""
    ang = math.radians(155.0)
    dx, dy = math.sin(ang), -math.cos(ang)      # CSS 0deg points up
    span = abs(dx) * (size - 1) + abs(dy) * (size - 1)
    ox = 0.0 if dx >= 0 else (size - 1)
    oy = 0.0 if dy >= 0 else (size - 1)
    out = []
    for y in range(size):
        row = []
        for x in range(size):
            t = ((x - ox) * dx + (y - oy) * dy) / span
            if t <= MID_STOP:
                k = t / MID_STOP
                v = G_LIGHT + (G_MID - G_LIGHT) * k
            else:
                k = (t - MID_STOP) / (1.0 - MID_STOP)
                v = G_MID + (G_DARK - G_MID) * k
            row.append(v)
        out.append(row)
    return out


def tile_sprite(dark=False):
    """Near-white tintable block face.

    Dark mode uses the same geometry with the shading rebalanced, per the
    spec: highlight .45 -> .28, bevel .16 -> .34.
    """
    hl, bev, side = (0.28, 0.34, 0.10) if dark else (0.45, 0.16, 0.14)
    size = TILE
    hi = max(2, round(size / 16))          # 2 logical px
    radius = max(2, round(size / 10))      # 3 logical px
    grad = gradient_155(size)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = grad[y][x]
            # inset highlights / bevel, as flat bands like the CSS box-shadow
            if y < hi:
                v = v + (1.0 - v) * hl            # top highlight
            elif y >= size - hi:
                v = v * (1.0 - bev)               # bottom bevel
            if x < hi:
                v = v + (1.0 - v) * side          # left highlight
            c = max(0, min(255, round(v * 255)))
            px[x, y] = (c, c, c, 255)
    # 1px ink outline, dark enough to read as ink once tinted
    d = ImageDraw.Draw(img)
    ink = (15, 12, 10, 255) if dark else (58, 46, 33, 255)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius,
                        outline=ink, width=1)
    img.putalpha(rounded_mask(size, radius))
    return img


def socket_sprite(dark=False):
    """Empty-cell recess. Near-white so it can be tinted per theme."""
    top, left = (0.40, 0.25) if dark else (0.16, 0.08)
    size, radius = TILE, 4
    img = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = 1.0
            if y < 3:
                v *= 1.0 - top                     # inset top shadow
            if x < 3:
                v *= 1.0 - left                    # inset left shadow
            c = round(v * 255)
            px[x, y] = (c, c, c, 255)
    ImageDraw.Draw(img).rounded_rectangle([0, 0, size - 1, size - 1],
                                          radius=radius,
                                          outline=(210, 210, 210, 255), width=1)
    img.putalpha(rounded_mask(size, radius))
    return img


def plate_sprite(bottom, ink=(58, 46, 33, 255)):
    """48x48 nine-patch plate. texture_margin_* = 12 logical (48 at 4x).

    Every surface in the design is a two-stop vertical gradient, so the plate
    carries the ramp and the theme only supplies the TOP colour: tinting with
    that colour reproduces the bottom stop. `bottom` is the ratio between them,
    e.g. #F9F1E1 -> #EADBBE is about 0.90, while the dark #3A2C22 -> #241C16
    is a much steeper 0.62.
    """
    size, radius = PLATE, 6
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ramp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = ramp.load()
    for y in range(size):
        v = 1.0 + (bottom - 1.0) * (y / float(size - 1))
        c = max(0, min(255, round(v * 255)))
        for x in range(size):
            px[x, y] = (c, c, c, 255)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1],
                                           radius=radius, fill=255)
    img.paste(ramp, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # 1px top highlight, matching the tile's language
    d.rectangle([2, 1, size - 3, 1], fill=(255, 255, 255, 255))
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius,
                        outline=ink, width=1)
    return img


def glyph(name):
    """Power glyphs, inset to 62% of the tile per the spec."""
    size = TILE
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    W = (255, 255, 255, 255)
    inset = round(size * (1.0 - 0.62) / 2.0)     # 6px -> a 20x20 field
    a, b = inset, size - inset - 1
    mid = size // 2
    if name == "bomb":
        d.ellipse([a + 1, a + 4, b - 1, b], fill=W)
        d.rectangle([mid - 2, a + 1, mid + 1, a + 4], fill=W)      # neck
        d.line([mid + 1, a + 2, b - 1, a - 1], fill=W, width=2)    # fuse
    elif name == "laser":
        d.rectangle([a, mid - 2, b, mid + 1], fill=W)              # horizontal
        d.rectangle([mid - 2, a, mid + 1, b], fill=W)              # vertical
    elif name == "collapse":
        for i, y in enumerate((a, a + 7, a + 14)):                 # 3 chevrons
            for k in range(5):
                d.rectangle([a + k, y + k, b - k, y + k + 1], fill=W)
                break
            d.polygon([(a, y), (b, y), (mid, y + 5)], fill=W)
    elif name == "diagonal":
        # Two crossed strokes. Drawn as stepped blocks rather than with a line
        # tool so the diagonal stays chunky instead of antialiasing itself.
        span = b - a
        for i in range(span + 1):
            t = a + i
            for ox in range(-1, 2):
                for oy in range(-1, 2):
                    if abs(ox) + abs(oy) > 1:
                        continue
                    d.point((t + ox, t + oy), fill=W)
                    d.point((t + ox, (a + b) - t + oy), fill=W)
    elif name == "blackhole":
        # A ring with the hole punched back out, so the glyph reads as a mouth
        # rather than a filled dot at tile size.
        d.ellipse([a, a, b, b], fill=W)
        d.ellipse([a + 6, a + 6, b - 6, b - 6], fill=(0, 0, 0, 0))
    elif name == "thunder":
        d.polygon([(mid + 1, a), (a + 3, mid + 2), (mid - 1, mid + 2),
                   (mid - 2, b), (b - 3, mid - 2), (mid + 1, mid - 2)], fill=W)
    elif name == "teleport":
        # A diamond gateway with the block already through it.
        for i in range(mid - a + 1):
            d.point((mid - i, mid - (mid - a - i)), fill=W)
            d.point((mid + i, mid - (mid - a - i)), fill=W)
            d.point((mid - i, mid + (mid - a - i)), fill=W)
            d.point((mid + i, mid + (mid - a - i)), fill=W)
            d.point((mid - i + 1, mid - (mid - a - i)), fill=W)
            d.point((mid + i - 1, mid + (mid - a - i)), fill=W)
        d.rectangle([mid - 2, mid - 2, mid + 1, mid + 1], fill=W)
    elif name == "meteor":
        # A rock low-right with three streaks trailing up-left behind it.
        d.ellipse([mid - 2, mid - 2, b, b], fill=W)
        for i in range(3):
            oy = a + i * 5
            d.line([(a, oy), (a + 7, oy + 7)], fill=W, width=2)
    elif name == "tsunami":
        # Three swells as a triangle wave. Amplitude has to be a good third of
        # the row spacing or the crests flatten out and it reads as stripes.
        span = b - a
        period = span / 2.0
        for y in (a + 2, a + 9, a + 16):
            for k in range(span + 1):
                phase = (k % period) / period          # 0..1 across one swell
                dy = phase * 2.0 if phase < 0.5 else (1.0 - phase) * 2.0
                oy = y + round(3 - dy * 3)             # crest up, trough down
                d.point((a + k, oy), fill=W)
                d.point((a + k, oy + 1), fill=W)
    elif name == "earthquake":
        # A fault line with DISPLACEMENT: ground either side of the split sits
        # at different heights. A plain zigzag read as the thunder bolt.
        d.rectangle([a, mid - 5, mid - 2, mid - 2], fill=W)        # left, high
        d.rectangle([mid + 2, mid + 1, b, mid + 4], fill=W)        # right, low
        for k in range(7):                                          # the split
            d.point((mid - 1 + (k % 2), mid - 5 + k), fill=W)
            d.point((mid + (k % 2), mid - 5 + k), fill=W)
        d.rectangle([a + 3, b - 3, a + 6, b - 2], fill=W)           # rubble
        d.rectangle([b - 6, a + 2, b - 3, a + 3], fill=W)
    elif name == "shuffle":
        # Two arrows trading places. The head is a triangle with its APEX at
        # the tip and its base behind it -- reversed, it reads as a barbell.
        for sgn, y in ((1, mid - 5), (-1, mid + 4)):
            d.line([(a + 2, y), (b - 2, y)], fill=W, width=3)
            tip = (b - 1) if sgn > 0 else (a + 1)
            base = tip - sgn * 5
            d.polygon([(tip, y), (base, y - 4), (base, y + 4)], fill=W)
    elif name == "rewind":
        # A counter-clockwise arrow: the clock turned back. Built from polar
        # coordinates rather than stacked PIL shapes -- an annulus with an
        # angular gap, so the hole cannot be filled in by a later primitive.
        import math
        cx = cy = (a + b) / 2.0
        outer, inner = 9.0, 5.0
        for y in range(size):
            for x in range(size):
                dx, dy = x - cx, y - cy
                dist = math.hypot(dx, dy)
                if not (inner <= dist <= outer):
                    continue
                # Screen coords: -90 deg is up. Leave the top open.
                ang = math.degrees(math.atan2(dy, dx))
                if -160.0 <= ang <= -35.0:
                    continue
                d.point((x, y), fill=W)
        # Head on the left end of the arc, pointing left: the way it travels
        # going backwards.
        d.polygon([(cx - outer - 2, cy - 3), (cx - inner + 1, cy - 8),
                   (cx - inner + 1, cy + 1)], fill=W)
    elif name == "fit":
        for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):        # 4 arrows
            cx = mid + dx * 6
            cy = mid + dy * 6
            d.polygon([(cx, cy + dy * 4), (cx - 4, cy - dy), (cx + 4, cy - dy)],
                      fill=W)
    return img


def save(img, name):
    big = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    path = os.path.abspath(os.path.join(OUT, name + ".png"))
    big.save(path)
    print("  %-16s %dx%d" % (name + ".png", big.width, big.height))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("generating pixel sprites at %dx:" % SCALE)
    save(tile_sprite(), "tile")
    save(tile_sprite(True), "tile_dark")
    save(socket_sprite(), "socket")
    save(socket_sprite(True), "socket_dark")
    # buttons: #E8BC61 -> #D6A549 is ~0.92, and is shared by both themes
    save(plate_sprite(0.92), "plate")
    # light panels: #F9F1E1 -> #EADBBE is ~0.90
    save(plate_sprite(0.90), "panel")
    # dark panels: #3A2C22 -> #241C16 is a much steeper ~0.62
    save(plate_sprite(0.62, ink=(15, 12, 10, 255)), "panel_dark")
    for g in ("bomb", "laser", "collapse", "fit", "diagonal",
              "blackhole", "thunder", "teleport", "meteor", "tsunami",
              "earthquake", "shuffle", "rewind"):
        save(glyph(g), "glyph_" + g)
    print("done -> ui/pixel/")
