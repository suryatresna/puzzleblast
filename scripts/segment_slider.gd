extends Control
## The design's volume control: a row of discrete segments, filled from the
## left. Tapping or dragging across it sets the value.
##
## Geometry is the design's doubled twice -- the mockups are 2x of the 270x480
## screen and the game runs at 4x, so a 24px-tall segment becomes 48 here.

signal value_changed(value: float)

const SEGMENTS := 8
const HEIGHT := 48.0
const GAP := 8.0
const BORDER := 4.0

## 0.0 .. 1.0, quantised to whole segments.
var value := 0.7:
	set(v):
		var q := _quantise(v)
		if is_equal_approx(q, value):
			return
		value = q
		queue_redraw()

var _held := false


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	Themes.theme_changed.connect(func(_id: int) -> void: queue_redraw())


## Sets the value without emitting -- use when populating the screen.
func set_silent(v: float) -> void:
	value = _quantise(v)


func _quantise(v: float) -> float:
	return roundf(clampf(v, 0.0, 1.0) * SEGMENTS) / float(SEGMENTS)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_held = mb.pressed
			if mb.pressed:
				_set_from(mb.position.x)
	elif event is InputEventMouseMotion and _held:
		_set_from((event as InputEventMouseMotion).position.x)


func _set_from(x: float) -> void:
	# Round to the nearest boundary so tapping the middle of a segment fills it.
	var v := _quantise(x / maxf(size.x, 1.0))
	if is_equal_approx(v, value):
		return
	value = v
	value_changed.emit(value)


func _draw() -> void:
	var ink: Color = Themes.value("ink", Themes.text_color("text"))
	var on: Color = Themes.text_color("accent")
	var off: Color = Themes.value("socket", Themes.text_color("muted"))
	var w := (size.x - GAP * (SEGMENTS - 1)) / float(SEGMENTS)
	var lit := int(roundf(value * SEGMENTS))
	for i in SEGMENTS:
		var r := Rect2(i * (w + GAP), (size.y - HEIGHT) * 0.5, w, HEIGHT)
		draw_rect(r, on if i < lit else off)
		draw_rect(r, ink, false, BORDER)
