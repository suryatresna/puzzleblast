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
const PlacePuff := preload("res://ui/effects/place_puff.tscn")

const POPUP_LABELS := {1: "CLEAR!", 2: "DOUBLE!", 3: "TRIPLE!", 4: "QUAD!"}


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


func popup(text: String, at: Vector2, color: Color, big: bool) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 84 if big else 58)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.06, 0.9))
	label.add_theme_constant_override("outline_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	# Centre on the requested point once the label knows its own size.
	await get_tree().process_frame
	if not is_instance_valid(label):
		return
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
