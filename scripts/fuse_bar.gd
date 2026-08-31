extends Control
## The Sprint clock, drawn as a burning fuse.
##
## The design's progress bar is a recessed track with a hard ink border and a
## gradient fill; this is that bar running down instead of up, with a spark at
## the burning edge and the fill shifting toward the danger colour as time runs
## out. Colours come from `Themes` so it matches whatever palette is active.

signal finished

const HEIGHT := 32.0
const BORDER := 4.0
const PAD := 4.0
## Below this fraction the fuse flashes.
const PANIC := 0.25

var duration := 60.0
var remaining := 60.0
var running := false

var _blink := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	Themes.theme_changed.connect(func(_id: int) -> void: queue_redraw())
	set_process(false)


func start(seconds: float) -> void:
	duration = maxf(1.0, seconds)
	remaining = duration
	running = true
	_blink = 0.0
	set_process(true)
	queue_redraw()


func stop() -> void:
	running = false
	set_process(false)
	queue_redraw()


func fraction() -> float:
	return clampf(remaining / maxf(duration, 0.001), 0.0, 1.0)


func _process(delta: float) -> void:
	if not running:
		return
	remaining = maxf(0.0, remaining - delta)
	_blink += delta
	queue_redraw()
	if remaining <= 0.0:
		running = false
		set_process(false)
		finished.emit()


func _draw() -> void:
	var ink: Color = Themes.value("ink", Themes.text_color("text"))
	var track: Color = Themes.value("socket", Themes.text_color("muted"))
	var hot: Color = Themes.text_color("danger")
	var warm: Color = Themes.text_color("accent")

	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, track)
	draw_rect(rect, ink, false, BORDER)

	var f := fraction()
	if f <= 0.0:
		return
	# The fuse shortens from the right; colour slides to danger as it burns.
	var inner := Rect2(rect.position + Vector2(PAD, PAD),
		Vector2(maxf(0.0, (size.x - PAD * 2.0) * f), size.y - PAD * 2.0))
	var fill: Color = warm.lerp(hot, 1.0 - f)
	if f < PANIC and int(_blink * 6.0) % 2 == 0:
		fill = fill.lightened(0.35)
	draw_rect(inner, fill)

	# A spark sitting on the burning edge.
	var spark := Vector2(inner.position.x + inner.size.x, inner.position.y)
	var w := minf(10.0, inner.size.x)
	if w > 0.0:
		draw_rect(Rect2(spark - Vector2(w, 0), Vector2(w, inner.size.y)),
			fill.lightened(0.5))
