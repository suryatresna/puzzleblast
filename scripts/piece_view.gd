extends Control
## Draws one piece. Used both for the tray cards (which shrink the piece to fit
## their slot) and for the piece being dragged (which matches the board's cell
## size so what you see is exactly what will be placed).


## Empty dictionary means "nothing here" -- a spent tray slot.
var piece: Dictionary = {}:
	set(value):
		piece = value
		queue_redraw()

## 0 auto-fits the piece to this control's rect; anything else is used directly.
var fixed_cell := 0.0:
	set(value):
		fixed_cell = value
		queue_redraw()

var dimmed := false:
	set(value):
		dimmed = value
		queue_redraw()

var _style := StyleBoxFlat.new()


func _ready() -> void:
	resized.connect(queue_redraw)
	Themes.theme_changed.connect(func(_id: int) -> void: queue_redraw())


## Pixel size the piece will occupy at the current cell size.
func piece_pixel_size() -> Vector2:
	if piece.is_empty():
		return Vector2.ZERO
	var span: Vector2i = piece["size"]
	return Vector2(span) * _cell()


func _cell() -> float:
	if fixed_cell > 0.0:
		return fixed_cell
	if piece.is_empty():
		return 0.0
	var span: Vector2i = piece["size"]
	# 0.86 leaves a little breathing room inside the slot.
	return minf(size.x / span.x, size.y / span.y) * 0.86


func _draw() -> void:
	if piece.is_empty():
		return
	var cell := _cell()
	if cell <= 0.0:
		return

	var span: Vector2i = piece["size"]
	var origin := Vector2.ZERO
	if fixed_cell <= 0.0:
		origin = (size - Vector2(span) * cell) * 0.5

	var color: Color = Themes.palette()[int(piece["color"])]
	if dimmed:
		color = color.darkened(0.55)
	_style.bg_color = color
	_style.border_color = color.lightened(0.35)
	_style.set_corner_radius_all(int(cell * 0.2))
	_style.set_border_width_all(maxi(1, int(cell * 0.06)))

	var power: Blocks.Power = Blocks.power_of(piece)
	var pixel := Themes.is_pixel()
	var tile: Texture2D = Themes.tile_texture() if pixel else null
	var glyph: Texture2D = Themes.glyph_texture(power) if pixel else null
	var inset := 0.0 if pixel else cell * 0.06
	for c: Vector2i in piece["cells"]:
		var p := origin + Vector2(c) * cell + Vector2(inset, inset)
		var rect := Rect2(p, Vector2(cell - inset * 2.0, cell - inset * 2.0))
		if tile != null:
			draw_texture_rect(tile, rect, false, color)
		else:
			draw_style_box(_style, rect)
		if power == Blocks.Power.NONE:
			continue
		if glyph != null:
			draw_texture_rect(glyph, rect, false,
				Color(1, 1, 1, 0.55 if dimmed else 1.0))
		else:
			Blocks.draw_power(self, rect, power)
