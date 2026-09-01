@tool
extends MarginContainer
## A MarginContainer that keeps its contents clear of notches, rounded corners
## and the iOS home indicator by folding the device safe area into its margins.
##
## The safe area is reported in physical screen pixels, so it is scaled into
## viewport units before being applied. Desktop runs get `base_margin` only --
## there `get_display_safe_area()` describes the whole monitor, not the window.

@export var base_margin := 56:
	set(value):
		base_margin = value
		if is_inside_tree():
			_apply()


func _ready() -> void:
	_apply()
	get_viewport().size_changed.connect(_apply)


func _apply() -> void:
	var inset := Vector4.ZERO
	if OS.get_name() in ["Android", "iOS"]:
		inset = _safe_area_inset()

	add_theme_constant_override("margin_left", base_margin + int(inset.x))
	add_theme_constant_override("margin_top", base_margin + int(inset.y))
	add_theme_constant_override("margin_right", base_margin + int(inset.z))
	add_theme_constant_override("margin_bottom", base_margin + int(inset.w))


## Left / top / right / bottom insets, in viewport units.
func _safe_area_inset() -> Vector4:
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return Vector4.ZERO

	var safe := Rect2(DisplayServer.get_display_safe_area())
	var ratio := get_viewport_rect().size / window
	return Vector4(
		maxf(safe.position.x, 0.0) * ratio.x,
		maxf(safe.position.y, 0.0) * ratio.y,
		maxf(window.x - safe.end.x, 0.0) * ratio.x,
		maxf(window.y - safe.end.y, 0.0) * ratio.y,
	)
