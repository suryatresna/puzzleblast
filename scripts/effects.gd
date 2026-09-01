extends Node2D
## The "boom" for a cleared line: a white core flash, a debris burst, sparks,
## an expanding shockwave ring and a floating score popup.
##
## Rows and columns are both just rectangles, so every helper takes a Rect2 and
## the same code drives horizontal and vertical clears. Everything scales with
## how many lines went at once. Emitters free themselves when they finish.

const LineBurst := preload("res://ui/effects/line_burst.tscn")
const SparkBurst := preload("res://ui/effects/spark_burst.tscn")
const Confetti := preload("res://ui/effects/confetti.tscn")
const ComboBurst := preload("res://ui/effects/combo_burst.tscn")
const FlowerTexture := preload("res://ui/effects/flower.svg")
const PlacePuff := preload("res://ui/effects/place_puff.tscn")

const POPUP_LABELS := {1: "CLEAR!", 2: "DOUBLE!", 3: "TRIPLE!", 4: "QUAD!"}

## Escalating call-outs for a combo streak, indexed by combo - 1. The streak
## caps at 5, so every rung is reachable.
const COMBO_WORDS := ["combo 1x", "Combo Pair!", "STRIKE!!", "AMAZE!!!", "SUPERDD!!!"]
const COMBO_SIZES := [74, 96, 118, 140, 164]
## Text colours, kept light so they read against the tinted background below.
const COMBO_COLORS := [
	Color(0.945, 0.941, 1),     # 1x     - plain
	Color(0.60, 0.78, 1.0),     # pair   - blue
	Color(1.0, 0.65, 0.85),     # strike - pink
	Color(1.0, 0.87, 0.45),     # amaze  - gold
	Color(0.78, 0.66, 1.0),     # top    - purple
]

## The background palette, walked one step at a time. Each streak takes the
## next colour and the backdrop keeps it -- it never returns to the default
## mid-run -- so the screen reads as a record of how the run has gone.
const COMBO_FLOW := [
	Color(0.231, 0.435, 0.878),  # blue
	Color(0.925, 0.282, 0.600),  # pink
	Color(0.961, 0.702, 0.004),  # gold
	Color(0.545, 0.361, 0.965),  # purple
]

## Only the pink step showers flowers; the rest use plain confetti chips.
const COMBO_FLOW_FLOWERS := [false, true, false, false]

## The banner currently on screen, replaced rather than stacked when clears
## land back to back.
var _banner: Label = null
## The floating points label, also replaced rather than stacked -- an older one
## drifting upward would otherwise sail through the banner.
var _points: Label = null


## `rows` and `cols` are index lists; `extent` is the board's pixel size.
func explode_lines(rows: Array, cols: Array, extent: float, cell: float, color: Color) -> void:
	var line_count: int = rows.size() + cols.size()
	var power := 1.0 + (line_count - 1) * 0.4
	var centers: Array = []

	for y: int in rows:
		var rect := Rect2(0.0, y * cell, extent, cell)
		_blast(rect, power, color, true)
		centers.append(rect.get_center())
	for x: int in cols:
		var rect := Rect2(x * cell, 0.0, cell, extent)
		_blast(rect, power, color, false)
		centers.append(rect.get_center())

	if centers.is_empty():
		return
	var mid := Vector2.ZERO
	for c: Vector2 in centers:
		mid += c
	mid /= centers.size()
	# One ring for the whole clear; per-line rings stack up and read as noise.
	_shockwave(mid, extent, power)


func _blast(rect: Rect2, power: float, color: Color, horizontal: bool) -> void:
	_core_flash(rect, power, color, horizontal)
	_debris(rect, power, color)
	_sparks(rect, power)


## A hard white bar over the line that blows outward and fades. This is what
## sells the hit on the frame the cells disappear.
## `grow` overrides how far the bar swells. A single cleared line wants a big
## multiplier, but a bomb's region is already several rows tall and the same
## factor would sweep it clear over the HUD.
func _core_flash(rect: Rect2, power: float, color: Color, horizontal: bool,
		grow := 0.0) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.8)
	flash.size = rect.size
	flash.position = rect.position
	flash.pivot_offset = rect.size * 0.5
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	if grow <= 0.0:
		grow = 1.7 + power * 0.3
	var target := Vector2(1.04, grow) if horizontal else Vector2(grow, 1.04)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", target, 0.34) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	tween.tween_property(flash, "color", Color(color.r, color.g, color.b, 0.0), 0.34) \
		.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(flash.queue_free)


func _debris(rect: Rect2, power: float, color: Color) -> void:
	var burst: CPUParticles2D = LineBurst.instantiate()
	add_child(burst)
	burst.position = rect.get_center()
	burst.emission_rect_extents = rect.size * 0.5
	var span: float = maxf(rect.size.x, rect.size.y)
	var cell: float = minf(rect.size.x, rect.size.y)
	burst.amount = int(clampf(span / maxf(cell, 1.0), 4.0, 12.0) * 9.0 * power)
	burst.scale_amount_min = cell * 0.10
	burst.scale_amount_max = cell * 0.26
	burst.initial_velocity_min = 220.0 * power
	burst.initial_velocity_max = 900.0 * power
	burst.color = color
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


func _sparks(rect: Rect2, power: float) -> void:
	var burst: CPUParticles2D = SparkBurst.instantiate()
	add_child(burst)
	burst.position = rect.get_center()
	burst.emission_rect_extents = rect.size * 0.4
	burst.amount = int(34 * power)
	burst.initial_velocity_max = 1400.0 * power
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


func _shockwave(center: Vector2, extent: float, power: float) -> void:
	var ring := Ring.new()
	ring.position = center
	ring.thickness = 3.0 + power
	ring.alpha = 0.5
	add_child(ring)

	# Kept inside the board: a larger radius sweeps over the HUD and reads as a
	# stray grey arc rather than a shockwave.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "radius", extent * 0.5, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ring, "alpha", 0.0, 0.4).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


## The bomb blast: a fireball at the bomb itself, then debris and a flash
## across the whole half of the board it takes out.
func explode_bomb(at: Vector2, region: Rect2, cell: float) -> void:
	var fire := Color(1, 0.55, 0.2)

	_core_flash(region, 2.6, fire, region.size.x >= region.size.y, 1.14)
	_debris(region, 2.4, fire)
	_sparks(region, 3.0)
	_shockwave(at, maxf(region.size.x, region.size.y) * 1.15, 2.6)

	# A tight, fast fireball right where the bomb sat.
	var ball: CPUParticles2D = SparkBurst.instantiate()
	add_child(ball)
	ball.position = at
	ball.emission_rect_extents = Vector2(cell * 0.3, cell * 0.3)
	ball.amount = 90
	ball.lifetime = 0.8
	ball.initial_velocity_min = cell * 6.0
	ball.initial_velocity_max = cell * 20.0
	ball.scale_amount_min = cell * 0.08
	ball.scale_amount_max = cell * 0.22
	ball.emitting = true
	ball.finished.connect(ball.queue_free)


## Twin beams down the row and column a laser burned through.
func laser_beam(at: Vector2i, extent: float, cell: float) -> void:
	var beam := Color(1, 0.95, 0.55)
	var row := Rect2(0.0, at.y * cell, extent, cell)
	var col := Rect2(at.x * cell, 0.0, cell, extent)

	_core_flash(row, 1.8, beam, true, 1.35)
	_core_flash(col, 1.8, beam, false, 1.35)
	_sparks(row, 2.2)
	_sparks(col, 2.2)
	_debris(row, 1.6, beam)
	_debris(col, 1.6, beam)
	_shockwave((Vector2(at) + Vector2(0.5, 0.5)) * cell, extent * 0.9, 2.0)


## The diagonal power's beam. The flash primitives here are axis-aligned rects,
## so instead of rotating them this walks the two diagonals and flashes each
## cell -- which also reads better, because the clear really is cell-by-cell
## rather than a continuous band.
func diagonal_beam(at: Vector2i, extent: float, cell: float) -> void:
	var beam: Color = Themes.block_color(12)
	var cells: int = int(round(extent / maxf(cell, 1.0)))
	var centre := (Vector2(at) + Vector2(0.5, 0.5)) * cell
	for i in range(-cells, cells + 1):
		for step: Vector2i in [Vector2i(at.x + i, at.y + i),
				Vector2i(at.x + i, at.y - i)]:
			if step.x < 0 or step.x >= cells or step.y < 0 or step.y >= cells:
				continue
			var r := Rect2(Vector2(step) * cell, Vector2(cell, cell))
			_core_flash(r, 1.4, beam, true, 1.1)
			if absi(i) % 2 == 0:
				_sparks(r, 1.4)
	_shockwave(centre, extent * 0.9, 2.0)


## A downward sweep across the board as everything settles after a morph.
func morph_sweep(extent: float, color: Color) -> void:
	var band := Rect2(0.0, 0.0, extent, extent)
	_core_flash(band, 1.0, color, true, 1.02)

	var burst: CPUParticles2D = ComboBurst.instantiate()
	add_child(burst)
	burst.position = Vector2(extent * 0.5, 0.0)
	burst.emission_rect_extents = Vector2(extent * 0.5, 8.0)
	burst.amount = 90
	burst.lifetime = 0.9
	burst.direction = Vector2(0, 1)
	burst.spread = 18.0
	burst.gravity = Vector2(0, extent * 2.2)
	burst.initial_velocity_min = extent * 0.5
	burst.initial_velocity_max = extent * 1.6
	burst.scale_amount_min = 6.0
	burst.scale_amount_max = 16.0
	burst.color = color
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


## A soft puff at each cell a piece just landed on. Deliberately small: this
## fires on every placement, so anything louder would wear thin fast.
func place_puff(cells: Array, cell: float, color: Color) -> void:
	for c: Vector2i in cells:
		var puff: CPUParticles2D = PlacePuff.instantiate()
		add_child(puff)
		puff.position = (Vector2(c) + Vector2(0.5, 0.5)) * cell
		puff.emission_sphere_radius = cell * 0.34
		puff.amount = 10
		puff.scale_amount_min = cell * 0.04
		puff.scale_amount_max = cell * 0.10
		puff.initial_velocity_min = cell * 0.6
		puff.initial_velocity_max = cell * 2.0
		puff.color = color.lightened(0.25)
		puff.emitting = true
		puff.finished.connect(puff.queue_free)


## Celebration for a new best: two corner poppers firing inward, plus a wide
## curtain falling from above.
func celebrate(area: Vector2) -> void:
	_popper(Vector2(area.x * 0.06, area.y * 0.92), Vector2(0.55, -1.0), area)
	_popper(Vector2(area.x * 0.94, area.y * 0.92), Vector2(-0.55, -1.0), area)
	_curtain(area)


func _popper(at: Vector2, dir: Vector2, area: Vector2) -> void:
	var burst: CPUParticles2D = Confetti.instantiate()
	add_child(burst)
	burst.position = at
	burst.emission_rect_extents = Vector2(12, 12)
	burst.direction = dir.normalized()
	burst.spread = 34.0
	burst.amount = 110
	burst.initial_velocity_min = area.y * 0.55
	burst.initial_velocity_max = area.y * 1.05
	burst.gravity = Vector2(0, area.y * 0.62)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


func _curtain(area: Vector2) -> void:
	var fall: CPUParticles2D = Confetti.instantiate()
	add_child(fall)
	fall.position = Vector2(area.x * 0.5, -20.0)
	fall.emission_rect_extents = Vector2(area.x * 0.5, 8.0)
	fall.amount = 150
	fall.lifetime = 3.2
	fall.explosiveness = 0.4
	fall.gravity = Vector2(0, area.y * 0.34)
	fall.emitting = true
	fall.finished.connect(fall.queue_free)


## Colour at a given step of the flow, wrapping round the end. The active
## theme supplies the palette; COMBO_FLOW is the fallback.
static func flow_color(step: int) -> Color:
	var flow: Array = Themes.value("combo_flow", COMBO_FLOW)
	if flow.is_empty():
		flow = COMBO_FLOW
	return flow[posmod(step, flow.size())]


static func flow_has_flowers(step: int) -> bool:
	return COMBO_FLOW_FLOWERS[posmod(step, COMBO_FLOW.size())]


## Ambient shower behind the board for a combo. Drifts upward from the bottom
## of the screen so it reads as atmosphere rather than another explosion.
## `combo` only sets the intensity; the colour comes from the flow.
func combo_atmosphere(tint: Color, flowers: bool, combo: int, area: Vector2) -> void:
	var tier: int = clampi(combo - 1, 0, 4)
	var burst: CPUParticles2D = ComboBurst.instantiate()
	add_child(burst)
	burst.position = Vector2(area.x * 0.5, area.y + 40.0)
	burst.emission_rect_extents = Vector2(area.x * 0.5, 30.0)
	burst.amount = 60 + tier * 22
	burst.initial_velocity_min = area.y * 0.20
	burst.initial_velocity_max = area.y * 0.62
	burst.gravity = Vector2(0, -area.y * 0.05)
	burst.color = tint.lightened(0.25)

	if flowers:
		# Flowers are a sprite, so they need to be smaller and spin lazily.
		burst.texture = FlowerTexture
		burst.scale_amount_min = 0.45
		burst.scale_amount_max = 1.0
		burst.angular_velocity_min = -90.0
		burst.angular_velocity_max = 90.0
	else:
		burst.scale_amount_min = 8.0 + tier * 2.0
		burst.scale_amount_max = 20.0 + tier * 4.0

	burst.emitting = true
	burst.finished.connect(burst.queue_free)


## A level-up. Colour columns rising the full height of the screen -- the same
## drift as `combo_atmosphere`, but one emitter per palette colour instead of a
## single tint, which is what makes it read as a celebration rather than as a
## bigger combo.
##
## Replaces the confetti this used to throw: confetti fell from the top, which
## fought the aura washing up from the bottom.
func level_aura(area: Vector2) -> void:
	var palette: Array = Themes.value("blocks", [])
	if palette.is_empty():
		palette = [Color.WHITE]
	var columns: int = mini(6, palette.size())
	for i in columns:
		var burst: CPUParticles2D = ComboBurst.instantiate()
		add_child(burst)
		# Spread the columns evenly, each covering its own slice of the width so
		# the rise reads as a curtain rather than a single plume.
		var slice: float = area.x / float(columns)
		burst.position = Vector2(slice * (i + 0.5), area.y + 40.0)
		burst.emission_rect_extents = Vector2(slice * 0.6, 30.0)
		burst.amount = 44
		burst.lifetime = 2.6
		burst.initial_velocity_min = area.y * 0.30
		burst.initial_velocity_max = area.y * 0.80
		burst.gravity = Vector2(0, -area.y * 0.06)
		burst.color = (palette[i % palette.size()] as Color).lightened(0.15)
		burst.scale_amount_min = 8.0
		burst.scale_amount_max = 22.0
		burst.one_shot = true
		burst.emitting = true
		burst.finished.connect(burst.queue_free)


static func combo_word(combo: int) -> String:
	return COMBO_WORDS[clampi(combo - 1, 0, COMBO_WORDS.size() - 1)]


## Big centre-screen call-out for a combo. Punches in, holds, then drifts off.
## Higher rungs are larger, hotter and kick harder.
func combo_banner(combo: int, at: Vector2) -> void:
	var tier: int = clampi(combo - 1, 0, COMBO_WORDS.size() - 1)
	_banner_text(COMBO_WORDS[tier], COMBO_COLORS[tier], COMBO_SIZES[tier],
		float(tier) / float(COMBO_WORDS.size() - 1), at)


## The same treatment with explicit words, for the power pieces -- they are not
## combo rungs but deserve the same weight on screen.
func combo_banner_text(text: String, color: Color) -> void:
	_banner_text(text, color, 112, 0.55, get_viewport_rect().size * Vector2(0.5, 0.46))


func _banner_text(text: String, color: Color, size: int, strength: float, at: Vector2) -> void:
	if is_instance_valid(_banner):
		_banner.queue_free()

	var label := Label.new()
	_banner = label
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Themes.text_color("outline"))
	label.add_theme_constant_override("outline_size", int(14 + strength * 12))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	await get_tree().process_frame
	if not is_instance_valid(label):
		return

	# A Label outside a container keeps size (0,0) until told otherwise, so the
	# width test below would never fire without this.
	label.reset_size()

	# The longest words overrun a phone's width at the largest sizes. The cap
	# has to account for the punch, not just the resting size, or the overshoot
	# pushes the ends back off screen.
	var kick: float = 1.12 + strength * 0.16
	var max_width: float = get_viewport_rect().size.x * 0.92
	var fit: float = 1.0
	if label.size.x > 0.0:
		fit = minf(1.0, max_width / (label.size.x * kick))

	label.position = at - label.size * 0.5
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * (0.45 * fit)
	label.rotation = deg_to_rad(-6.0 * strength)
	label.modulate.a = 0.0

	var overshoot: float = kick * fit
	var hold: float = 0.30 + strength * 0.25

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE * overshoot, 0.13) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(label, "rotation", 0.0, 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(label, "modulate:a", 1.0, 0.10)

	tween.chain().tween_property(label, "scale", Vector2.ONE * fit, 0.12) \
		.set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(hold)
	tween.chain().tween_property(label, "position:y", label.position.y - 90.0, 0.34) \
		.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.34)
	tween.chain().tween_callback(label.queue_free)


## Like popup(), but only one is ever on screen.
func points_popup(text: String, at: Vector2, color: Color, big: bool) -> void:
	if is_instance_valid(_points):
		_points.queue_free()
	_points = _make_popup(text, color, big)
	await _float_popup(_points, at)


func popup(text: String, at: Vector2, color: Color, big: bool) -> void:
	await _float_popup(_make_popup(text, color, big), at)


func _make_popup(text: String, color: Color, big: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 84 if big else 58)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Themes.text_color("outline"))
	label.add_theme_constant_override("outline_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _float_popup(label: Label, at: Vector2) -> void:
	# Centre on the requested point once the label knows its own size.
	await get_tree().process_frame
	if not is_instance_valid(label):
		return
	label.reset_size()
	label.position = at - label.size * 0.5
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.4, 0.4)

	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(label, "position:y", label.position.y - 110.0, 0.9) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


func clear_label(line_count: int) -> String:
	return POPUP_LABELS.get(line_count, "COMBO x%d" % line_count)


## Minimal expanding ring, drawn rather than textured so it stays crisp at any
## resolution and needs no art asset.
class Ring extends Node2D:
	var radius := 0.0:
		set(value):
			radius = value
			queue_redraw()
	var alpha := 0.5:
		set(value):
			alpha = value
			queue_redraw()
	var thickness := 4.0

	func _draw() -> void:
		if radius <= 0.0:
			return
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(1, 1, 1, alpha), thickness, true)
