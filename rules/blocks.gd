extends RefCounted
class_name Blocks
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
	Color("2dd4bf"), # morph
	Color("fde047"), # laser
	Color("a3e635"), # fit
	Color("38bdf8"), # diagonal
	Color("8b5cf6"), # blackhole
	Color("e0f2fe"), # thunder
	Color("d946ef"), # teleport
	Color("c2410c"), # meteor
	Color("0369a1"), # tsunami
	Color("92400e"), # earthquake
	Color("14b8a6"), # shuffle
	Color("cbd5e1"), # rewind
]

## Special single-cell pieces. NONE is an ordinary shape.
enum Power { NONE, BOMB, MORPH, LASER, FIT, DIAGONAL, BLACKHOLE, THUNDER,
	TELEPORT, METEOR, TSUNAMI, EARTHQUAKE, SHUFFLE, REWIND }

## Palette index and glyph for each power.
const POWER_COLOR := {
	Power.BOMB: 8,
	Power.MORPH: 9,
	Power.LASER: 10,
	Power.FIT: 11,
	Power.DIAGONAL: 12,
	Power.BLACKHOLE: 13,
	Power.THUNDER: 14,
	Power.TELEPORT: 15,
	Power.METEOR: 16,
	Power.TSUNAMI: 17,
	Power.EARTHQUAKE: 18,
	Power.SHUFFLE: 19,
	Power.REWIND: 20,
}

const BOMB_COLOR := 8
## weight: relative spawn frequency. rotate: also emit the distinct rotations.
const BASE := [
	{"cells": [Vector2i(0, 0)], "weight": 2, "color": 3, "rotate": false},

	# Diagonals. Deliberately rare: a diagonal contributes to two different
	# lines at once but completes neither, so a hand full of them stalls the
	# board. They exist to make a tidy grid suddenly awkward.
	{"cells": [Vector2i(0, 0), Vector2i(1, 1)], "weight": 3, "color": 6,
		"rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)],
		"weight": 2, "color": 6, "rotate": true},
	{"cells": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1)],
		"weight": 2, "color": 7, "rotate": true},

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


## A single cell carrying a power. All of them are 1x1: they are placed like
## any other piece and then do their work.
static func power_piece(power: Power) -> Dictionary:
	return {
		"cells": [Vector2i(0, 0)],
		"color": int(POWER_COLOR[power]),
		"size": Vector2i(1, 1),
		"weight": 0,
		"power": int(power),
	}


static func bomb_piece() -> Dictionary:
	return power_piece(Power.BOMB)


static func power_of(piece: Dictionary) -> Power:
	return int(piece.get("power", Power.NONE)) as Power


static func is_power(piece: Dictionary) -> bool:
	return power_of(piece) != Power.NONE


static func is_bomb(piece: Dictionary) -> bool:
	return power_of(piece) == Power.BOMB


## Every special. Both the dealt hand and the combo reward draw from this, with
## equal odds, so any of the four can turn up either way.
const ALL_POWERS := [Power.BOMB, Power.MORPH, Power.LASER, Power.FIT,
	Power.DIAGONAL, Power.BLACKHOLE, Power.THUNDER, Power.TELEPORT,
	Power.METEOR, Power.TSUNAMI, Power.EARTHQUAKE, Power.SHUFFLE,
	Power.REWIND]

## Shown on the call-out when a streak earns a special.
const POWER_NAMES := {
	Power.BOMB: "BOMB!",
	Power.MORPH: "COLLAPSE!",
	Power.LASER: "LASER!",
	Power.FIT: "FIT!",
	Power.DIAGONAL: "CROSSFIRE!",
	Power.BLACKHOLE: "BLACKHOLE!",
	Power.THUNDER: "THUNDER!",
	Power.TELEPORT: "TELEPORT!",
	Power.METEOR: "METEOR!",
	Power.TSUNAMI: "TSUNAMI!",
	Power.EARTHQUAKE: "EARTHQUAKE!",
	Power.SHUFFLE: "SHUFFLE!",
	Power.REWIND: "REWIND!",
}


static func power_name(power: Power) -> String:
	return String(POWER_NAMES.get(power, "POWER!"))


static func power_color(power: Power) -> Color:
	return COLORS[int(POWER_COLOR[power])]


## An even draw from all four specials.
static func random_special_piece() -> Dictionary:
	return power_piece(ALL_POWERS[randi() % ALL_POWERS.size()])


## Only ever returns ordinary shapes; bombs are dealt by the tray.
## `small_bias` above 1.0 makes 1- and 2-cell pieces correspondingly more
## likely, which is what the easier levels use to keep the board manageable.
static func random_piece(small_bias := 1.0) -> Dictionary:
	var list := catalogue()
	var total := 0.0
	for piece: Dictionary in list:
		total += _biased_weight(piece, small_bias)
	var roll := randf() * total
	for piece: Dictionary in list:
		roll -= _biased_weight(piece, small_bias)
		if roll <= 0.0:
			return piece
	return list[0]


static func _biased_weight(piece: Dictionary, small_bias: float) -> float:
	var weight := float(piece["weight"])
	if piece["cells"].size() <= 2:
		return weight * small_bias
	return weight


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


## Draws the glyph for `power` inside `rect`. All procedural rather than
## imported sprites, so they stay crisp at both the tray's small preview size
## and the board's large one.
static func draw_power(ci: CanvasItem, rect: Rect2, power: Power) -> void:
	match power:
		Power.BOMB: draw_bomb(ci, rect)
		Power.MORPH: _draw_morph(ci, rect)
		Power.LASER: _draw_laser(ci, rect)
		Power.FIT: _draw_fit(ci, rect)
		Power.DIAGONAL: _draw_diagonal(ci, rect)
		Power.BLACKHOLE: _draw_blackhole(ci, rect)
		Power.THUNDER: _draw_thunder(ci, rect)
		Power.TELEPORT: _draw_teleport(ci, rect)
		Power.METEOR: _draw_meteor(ci, rect)
		Power.TSUNAMI: _draw_tsunami(ci, rect)
		Power.EARTHQUAKE: _draw_earthquake(ci, rect)
		Power.SHUFFLE: _draw_shuffle(ci, rect)
		Power.REWIND: _draw_rewind(ci, rect)


## An arrow running counter-clockwise: the clock turned back.
static func _draw_rewind(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var ink := Color(0.10, 0.12, 0.16)
	var r := span * 0.27
	var thick := maxf(2.0, span * 0.085)
	# Open at the top left, where the head goes.
	ci.draw_arc(c, r, PI * 1.15, TAU + PI * 0.55, 28, ink, thick)
	var tip := c + Vector2(-r, 0.0) + Vector2(0.0, -span * 0.02)
	var h := span * 0.11
	ci.draw_colored_polygon(PackedVector2Array([
		tip + Vector2(-h * 0.9, 0.0),
		tip + Vector2(h * 0.5, -h),
		tip + Vector2(h * 0.5, h),
	]), ink)


## A fault line splitting the ground.
static func _draw_earthquake(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var ink := Color(0.14, 0.08, 0.02)
	var thick := maxf(2.0, span * 0.09)
	var pts := [
		c + Vector2(-span * 0.30, -span * 0.26),
		c + Vector2(-span * 0.08, -span * 0.06),
		c + Vector2(-span * 0.20, span * 0.08),
		c + Vector2(span * 0.06, span * 0.30),
	]
	for i in pts.size() - 1:
		ci.draw_line(pts[i], pts[i + 1], ink, thick)
	# the ground either side, cracked apart
	ci.draw_line(c + Vector2(span * 0.10, -span * 0.30),
		c + Vector2(span * 0.30, -span * 0.30), ink, thick * 0.7)
	ci.draw_line(c + Vector2(-span * 0.30, span * 0.28),
		c + Vector2(-span * 0.14, span * 0.28), ink, thick * 0.7)


## Two arrows trading places.
static func _draw_shuffle(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var ink := Color(0.02, 0.16, 0.15)
	var thick := maxf(2.0, span * 0.08)
	var head := span * 0.10
	for dir in [1.0, -1.0]:
		var y: float = c.y + dir * span * 0.14
		var from := Vector2(c.x - dir * span * 0.28, y)
		var to := Vector2(c.x + dir * span * 0.28, y)
		ci.draw_line(from, to, ink, thick)
		var back := Vector2(-dir, 0.0) * head
		ci.draw_line(to, to + back + Vector2(0.0, head), ink, thick)
		ci.draw_line(to, to + back - Vector2(0.0, head), ink, thick)


## A rock on a streaking trail.
static func _draw_meteor(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var ink := Color(0.16, 0.06, 0.02)
	var head := c + Vector2(span * 0.13, span * 0.15)
	for i in 3:
		var off := span * (0.10 + i * 0.09)
		ci.draw_line(head - Vector2(off, off) - Vector2(span * 0.10, 0.0),
			head - Vector2(off, off) + Vector2(span * 0.06, 0.0),
			ink, maxf(2.0, span * 0.06))
	ci.draw_circle(head, span * 0.17, ink)


## Three stacked swells: the wave coming in.
static func _draw_tsunami(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var ink := Color(0.01, 0.10, 0.20)
	var thick := maxf(2.0, span * 0.075)
	var w := span * 0.30
	for i in 3:
		var y: float = c.y - span * 0.18 + i * span * 0.18
		# Each swell is a shallow arc, drawn as two strokes meeting at a crest.
		ci.draw_line(Vector2(c.x - w, y), Vector2(c.x - w * 0.35, y - w * 0.30),
			ink, thick)
		ci.draw_line(Vector2(c.x - w * 0.35, y - w * 0.30), Vector2(c.x, y), ink, thick)
		ci.draw_line(Vector2(c.x, y), Vector2(c.x + w * 0.35, y - w * 0.30), ink, thick)
		ci.draw_line(Vector2(c.x + w * 0.35, y - w * 0.30), Vector2(c.x + w, y), ink, thick)


## A ring with a dark core: the circle of pull, and the hole at the middle.
static func _draw_blackhole(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var ink := Color(0.06, 0.03, 0.13)
	ci.draw_arc(c, span * 0.28, 0.0, TAU, 28, ink, maxf(2.0, span * 0.09))
	ci.draw_circle(c, span * 0.11, ink)


## A bolt. Drawn as one polygon so it stays sharp at any size.
static func _draw_thunder(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var ink := Color(0.10, 0.16, 0.22)
	var pts := PackedVector2Array([
		c + Vector2(span * 0.06, -span * 0.32),
		c + Vector2(-span * 0.20, span * 0.04),
		c + Vector2(-span * 0.02, span * 0.04),
		c + Vector2(-span * 0.08, span * 0.32),
		c + Vector2(span * 0.20, -span * 0.06),
		c + Vector2(span * 0.01, -span * 0.06),
	])
	ci.draw_colored_polygon(pts, ink)


## A portal: a diamond gateway with the block already through it.
static func _draw_teleport(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var ink := Color(0.16, 0.03, 0.16)
	var r := span * 0.30
	var thick := maxf(2.0, span * 0.08)
	var d := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
	])
	for i in 4:
		ci.draw_line(d[i], d[(i + 1) % 4], ink, thick)
	ci.draw_rect(Rect2(c - Vector2(span * 0.09, span * 0.09),
		Vector2(span * 0.18, span * 0.18)), ink)


## Three chevrons falling: the whole board drops and compacts.
static func _draw_morph(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var w := span * 0.22
	var thick := maxf(2.0, span * 0.09)
	var ink := Color(0.05, 0.16, 0.15)
	for i in 3:
		var y: float = c.y - span * 0.20 + i * span * 0.19
		ci.draw_line(Vector2(c.x - w, y), Vector2(c.x, y + w * 0.8), ink, thick)
		ci.draw_line(Vector2(c.x, y + w * 0.8), Vector2(c.x + w, y), ink, thick)


## A crosshair with beams running off both axes.
static func _draw_laser(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var thick := maxf(2.0, span * 0.08)
	var ink := Color(0.20, 0.14, 0.02)
	ci.draw_line(Vector2(rect.position.x + span * 0.08, c.y),
		Vector2(rect.end.x - span * 0.08, c.y), ink, thick)
	ci.draw_line(Vector2(c.x, rect.position.y + span * 0.08),
		Vector2(c.x, rect.end.y - span * 0.08), ink, thick)
	ci.draw_circle(c, span * 0.17, ink)
	ci.draw_circle(c, span * 0.09, Color(1, 1, 0.92))


## Four arrows pushing outward: the piece grows to fill the gap.
static func _draw_fit(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var thick := maxf(2.0, span * 0.085)
	var ink := Color(0.13, 0.20, 0.03)
	var reach := span * 0.30
	var head := span * 0.11
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tip := c + dir * reach
		ci.draw_line(c + dir * span * 0.10, tip, ink, thick)
		var side := Vector2(-dir.y, dir.x) * head
		ci.draw_line(tip, tip - dir * head + side, ink, thick)
		ci.draw_line(tip, tip - dir * head - side, ink, thick)


## Draws a bomb glyph inside `rect`.
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


## Two crossed strokes -- the diagonal counterpart to the laser's plus, drawn
## in the same ink and inset by the same margin so the set reads as a family.
static func _draw_diagonal(ci: CanvasItem, rect: Rect2) -> void:
	var span := minf(rect.size.x, rect.size.y)
	var pad := span * 0.08
	var thick := maxf(2.0, span * 0.08)
	var ink := Color(0.20, 0.14, 0.02)
	var tl := rect.position + Vector2(pad, pad)
	var br := rect.end - Vector2(pad, pad)
	ci.draw_line(tl, br, ink, thick)
	ci.draw_line(Vector2(br.x, tl.y), Vector2(tl.x, br.y), ink, thick)
	ci.draw_circle(rect.get_center(), span * 0.13, ink)
	ci.draw_circle(rect.get_center(), span * 0.07, Color(1, 1, 0.92))
