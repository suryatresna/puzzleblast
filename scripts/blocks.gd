extends RefCounted
## Shapes for the drag-and-drop block puzzle.
##
## Each base entry lists one piece's cells (origin normalised to 0,0), a spawn
## weight and a palette colour. Distinct rotations are generated at load rather
## than written out by hand, so adding a shape means adding one line.

const COLORS := [
	Color("22d3ee"), # cyan
	Color("5b7cfa"), # blue
	Color("ff9f45"), # orange
	Color("ffd452"), # yellow
	Color("4ade80"), # green
	Color("9b8cff"), # violet
	Color("fb7185"), # rose
	Color("f472b6"), # pink
	Color("ef4444"), # bomb
]

## Index into COLORS for the bomb tile.
const BOMB_COLOR := 8
## Chance that a freshly dealt tray contains a bomb. Rolled once per refill,
## not per card, so a hand can never hold more than one -- three bombs at once
## would trivialise the board.
const BOMB_TRAY_CHANCE := 0.20

## weight: relative spawn frequency. rotate: also emit the distinct rotations.
const BASE := [
	{"cells": [Vector2i(0, 0)], "weight": 2, "color": 3, "rotate": false},

	{"cells": [Vector2i(0, 0), Vector2i(1, 0)], "weight": 6, "color": 0, "rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		"weight": 7, "color": 0, "rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
		"weight": 5, "color": 1, "rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)],
		"weight": 3, "color": 1, "rotate": true},

	{"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"weight": 7, "color": 3, "rotate": false},
	{"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(0, 2), Vector2i(1, 2)], "weight": 2, "color": 5, "rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)],
		"weight": 1, "color": 6, "rotate": false},

	# Corners and the classic tetromino set.
	{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"weight": 8, "color": 4, "rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
		"weight": 4, "color": 2, "rotate": true},
	{"cells": [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(0, 2)],
		"weight": 4, "color": 1, "rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
		"weight": 4, "color": 5, "rotate": true},
	{"cells": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"weight": 3, "color": 4, "rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
		"weight": 3, "color": 6, "rotate": true},

	# Big 3x3 corner.
	{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)],
		"weight": 3, "color": 7, "rotate": true},
]

static var _catalogue: Array = []
static var _total_weight := 0


## Every playable piece as {cells, color, size, weight}.
static func catalogue() -> Array:
	if _catalogue.is_empty():
		_build()
	return _catalogue


## A single cell that detonates on placement, clearing half the board.
static func bomb_piece() -> Dictionary:
	return {
		"cells": [Vector2i(0, 0)],
		"color": BOMB_COLOR,
		"size": Vector2i(1, 1),
		"weight": 0,
		"bomb": true,
	}


static func is_bomb(piece: Dictionary) -> bool:
	return bool(piece.get("bomb", false))


## Only ever returns ordinary shapes; bombs are dealt by the tray.
static func random_piece() -> Dictionary:
	var list := catalogue()
	var roll := randi_range(0, _total_weight - 1)
	for piece: Dictionary in list:
		roll -= piece["weight"]
		if roll < 0:
			return piece
	return list[0]


static func bounds(cells: Array) -> Vector2i:
	var w := 0
	var h := 0
	for c: Vector2i in cells:
		w = maxi(w, c.x + 1)
		h = maxi(h, c.y + 1)
	return Vector2i(w, h)


static func _build() -> void:
	_catalogue.clear()
	_total_weight = 0
	for entry: Dictionary in BASE:
		var seen := {}
		var variants: Array = [_normalize(entry["cells"])]
		if entry["rotate"]:
			var current: Array = variants[0]
			for i in 3:
				current = _normalize(_rotate_cw(current))
				variants.append(current)
		for cells: Array in variants:
			var key := str(cells)
			if seen.has(key):
				continue          # square and bar rotations repeat themselves
			seen[key] = true
			_catalogue.append({
				"cells": cells,
				"color": entry["color"],
				"size": bounds(cells),
				"weight": entry["weight"],
			})
			_total_weight += int(entry["weight"])


static func _rotate_cw(cells: Array) -> Array:
	var max_y := 0
	for c: Vector2i in cells:
		max_y = maxi(max_y, c.y)
	var out: Array = []
	for c: Vector2i in cells:
		out.append(Vector2i(max_y - c.y, c.x))
	return out


## Shifts to origin and sorts, so two spellings of the same shape compare equal.
static func _normalize(cells: Array) -> Array:
	var min_x := 9999
	var min_y := 9999
	for c: Vector2i in cells:
		min_x = mini(min_x, c.x)
		min_y = mini(min_y, c.y)
	var out: Array = []
	for c: Vector2i in cells:
		out.append(c - Vector2i(min_x, min_y))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## Draws a bomb glyph inside `rect`. Procedural rather than an imported sprite
## so it stays crisp at the tray's small preview size and the board's large one.
static func draw_bomb(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var body := span * 0.30
	var centre := rect.get_center() + Vector2(0.0, span * 0.05)

	ci.draw_circle(centre, body, Color(0.09, 0.08, 0.13))
	ci.draw_circle(centre - Vector2(body * 0.30, body * 0.34), body * 0.24,
		Color(1, 1, 1, 0.28))

	var fuse_a := centre + Vector2(body * 0.52, -body * 0.78)
	var fuse_b := fuse_a + Vector2(span * 0.09, -span * 0.12)
	ci.draw_line(fuse_a, fuse_b, Color(0.88, 0.78, 0.58), maxf(1.0, span * 0.05))
	ci.draw_circle(fuse_b, span * 0.075, Color(1, 0.72, 0.25))
	ci.draw_circle(fuse_b, span * 0.038, Color(1, 1, 0.88))
