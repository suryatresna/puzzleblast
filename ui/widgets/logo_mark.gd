extends TextureRect
## The title mark: four tiles in a square, the bottom-right one tilted.
##
##     ochre  rust
##     olive  sage (rotated)
##
## The pixel form of `ui/logo.svg`, down to the tilt -- one block sitting off
## the grid the other three keep. All four tints are used, so the odd one is
## marked by its angle rather than by being the only colour that differs.
##
## The tilt fits without collision, and not by luck: a square turned 14 degrees
## grows about 10.6% of its width on each side, and GAP leaves 12.5%. That is
## the same margin `logo.svg` relies on. Change one and check the other.
##
## Drawn from the live block sprite so it is tinted by whatever theme is
## active, rather than being a flat image that would drift from the palette.
## On a non-pixel theme the node falls back to the vector logo it was given
## in the scene.

## Grid position paired with a palette index. The indices are the design's
## four tile tints: 0 blue, 1 olive, 2 rust, 3 ochre.
const CELLS := [
	[Vector2i(0, 0), 3], [Vector2i(1, 0), 2],
	[Vector2i(0, 1), 1], [Vector2i(1, 1), 0],
]
const COLS := 2
const ROWS := 2
## Gap between tiles, as a fraction of a tile -- 4px on a 32px tile.
const GAP := 0.125
## The one tile that sits off the grid, and how far over it leans.
const TILTED := Vector2i(1, 1)
const TILT_DEG := 14.0

var _svg: Texture2D


func _ready() -> void:
	_svg = texture
	Themes.theme_changed.connect(func(_id: int) -> void: _sync())
	resized.connect(queue_redraw)
	_sync()


func _sync() -> void:
	# Dropping the texture stops TextureRect painting so _draw owns the node.
	texture = null if Themes.is_pixel() else _svg
	queue_redraw()


func _draw() -> void:
	if not Themes.is_pixel():
		return
	var tile := Themes.tile_texture()
	if tile == null:
		return

	# Fit the grid into whichever axis runs out first, on whole pixels so the
	# tiles keep the same grid the board uses. The tilted tile reaches past its
	# cell on the right and the bottom, so that overhang is reserved here --
	# without it the lean would spill outside the node and over the line below.
	var lean: float = (cos(deg_to_rad(TILT_DEG)) + sin(deg_to_rad(TILT_DEG)) - 1.0) * 0.5
	var span_x := COLS + (COLS - 1) * GAP + lean
	var span_y := ROWS + (ROWS - 1) * GAP + lean
	var cell := floorf(minf(size.x / span_x, size.y / span_y))
	if cell <= 0.0:
		return
	var step := cell * (1.0 + GAP)
	var used := Vector2(cell * span_x, cell * span_y)
	var origin := ((size - used) * 0.5).floor()

	for entry: Array in CELLS:
		var at: Vector2i = entry[0]
		var box := Rect2(origin + Vector2(at) * step, Vector2(cell, cell))
		var tint: Color = Themes.block_color(int(entry[1]))
		if at == TILTED:
			# Rotate about the tile's own centre. draw_set_transform replaces
			# the canvas transform, so the rect is drawn around the origin and
			# the transform puts it back where it belongs.
			draw_set_transform(box.get_center(), deg_to_rad(TILT_DEG), Vector2.ONE)
			draw_texture_rect(tile, Rect2(-box.size * 0.5, box.size), false, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tile, box, false, tint)
