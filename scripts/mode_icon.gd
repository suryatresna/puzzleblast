extends Control
## The 64px badge on a mode card, per the design.
##
##   swatches  a 2x2 grid of palette colours   (Palette)
##   60        the Sprint clock, as a numeral  (Sprint)
##   gem       an octagon, matching the shop's currency shape (Puzzle)
##
## Drawn rather than authored so it follows the theme.

const SIZE := 128.0
const BORDER := 6.0

@export var kind := "swatches":
	set(v):
		kind = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	Themes.theme_changed.connect(func(_id: int) -> void: queue_redraw())


func _draw() -> void:
	var ink: Color = Themes.value("ink", Themes.text_color("text"))
	var face: Color = Themes.value("slot_top", Themes.value("card", Color.WHITE))
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, face)
	draw_rect(rect, ink, false, BORDER)

	match kind:
		"swatches":
			# Four palette tints, the mode's whole idea in one badge.
			var pad := 14.0
			var cell := (size.x - pad * 3.0) * 0.5
			var tints := [6, 3, 2, 1]          # steel, ochre, rust, olive
			for i in 4:
				var at := Vector2(pad + (i % 2) * (cell + pad),
					pad + (i / 2) * (cell + pad))
				draw_rect(Rect2(at, Vector2(cell, cell)), Themes.block_color(tints[i]))
		"60":
			var font := get_theme_default_font()
			var s := "60"
			var fs := 52
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, Vector2((size.x - w.x) * 0.5,
				(size.y + w.y * 0.6) * 0.5), s,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Themes.text_color("text"))
		"big":
			# A 3x3 of small tiles: the same mark as Palette, but denser.
			var pad3 := 12.0
			var c3 := (size.x - pad3 * 4.0) / 3.0
			for i in 9:
				var at3 := Vector2(pad3 + (i % 3) * (c3 + pad3),
					pad3 + (i / 3) * (c3 + pad3))
				draw_rect(Rect2(at3, Vector2(c3, c3)),
					Themes.block_color([6, 3, 2, 1, 0, 3, 2, 1, 6][i]))
		"gem":
			# The design's octagon: a square with the corners cut at 25%.
			var c := size * 0.5
			var r := size.x * 0.28
			var k := r * 0.5
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-k, -r), c + Vector2(k, -r), c + Vector2(r, -k),
				c + Vector2(r, k), c + Vector2(k, r), c + Vector2(-k, r),
				c + Vector2(-r, k), c + Vector2(-r, -k),
			]), Themes.text_color("highlight"))
