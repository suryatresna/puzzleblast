extends TextureRect
## The title mark: the design's nine tiles laid out six across.
##
##     blue  blue  ochre  rust  rust  olive
##     olive olive ochre
##
## Drawn from the live block sprite so it is tinted by whatever theme is
## active, rather than being a flat image that would drift from the palette.
## On a non-pixel theme the node falls back to the vector logo it was given
## in the scene.

## Grid position paired with a palette index. The indices are the design's
## four tile tints: 0 blue, 1 olive, 2 rust, 3 ochre.
const CELLS := [
	[Vector2i(0, 0), 0], [Vector2i(1, 0), 0], [Vector2i(2, 0), 3],
	[Vector2i(3, 0), 2], [Vector2i(4, 0), 2], [Vector2i(5, 0), 1],
	[Vector2i(0, 1), 1], [Vector2i(1, 1), 1], [Vector2i(2, 1), 3],
]
const COLS := 6
const ROWS := 2
## Gap between tiles, as a fraction of a tile -- 4px on a 32px tile.
const GAP := 0.125

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

	# Fit the 6x2 grid into whichever axis runs out first, on whole pixels so
	# the tiles keep the same grid the board uses.
	var span_x := COLS + (COLS - 1) * GAP
	var span_y := ROWS + (ROWS - 1) * GAP
	var cell := floorf(minf(size.x / span_x, size.y / span_y))
	if cell <= 0.0:
		return
	var step := cell * (1.0 + GAP)
	var used := Vector2(cell * span_x, cell * span_y)
	var origin := ((size - used) * 0.5).floor()

	for entry: Array in CELLS:
		var at: Vector2i = entry[0]
		draw_texture_rect(tile,
			Rect2(origin + Vector2(at) * step, Vector2(cell, cell)),
			false, Themes.block_color(int(entry[1])))
