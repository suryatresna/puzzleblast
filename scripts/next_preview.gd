extends Control
## Draws the upcoming piece, centred in whatever box the HUD gives it.

const Tetromino := preload("res://scripts/tetromino.gd")

var type := -1:
	set(value):
		type = value
		queue_redraw()

var _style := StyleBoxFlat.new()


func _draw() -> void:
	if type < 0:
		return
	var cells: Array = Tetromino.cells(type, 0)

	# Tight bounds so every piece is optically centred, not box-centred.
	var min_c := Vector2i(99, 99)
	var max_c := Vector2i(-99, -99)
	for c: Vector2i in cells:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var span := Vector2(max_c.x - min_c.x + 1, max_c.y - min_c.y + 1)

	var cell: float = minf(size.x / span.x, size.y / span.y) * 0.82
	var origin := (size - span * cell) * 0.5

	var color: Color = Tetromino.COLORS[type]
	_style.bg_color = color
	_style.border_color = color.lightened(0.35)
	_style.set_corner_radius_all(int(cell * 0.18))
	_style.set_border_width_all(maxi(1, int(cell * 0.06)))

	for c: Vector2i in cells:
		var p := Vector2(c.x - min_c.x, c.y - min_c.y) * cell + origin
		draw_style_box(_style, Rect2(p + Vector2(cell, cell) * 0.05, Vector2(cell, cell) * 0.9))
