extends BaseButton
## The settings switch from the design: a hard-edged track with a square knob
## that slides between the ends.
##
## Geometry is the design's, doubled -- the mockups are drawn at 2x of the
## 270x480 logical screen, and the game runs at 4x, so a 72x36 track becomes
## 144x72 here.
##
## Colours come from `Themes`: the track is the accent colour when on and the
## socket colour when off, and the knob is the palette's lightest tone.

const TRACK := Vector2(144, 72)
const PAD := 8.0
const KNOB := 56.0
const BORDER := 6.0
const KNOB_BORDER := 4.0
const SLIDE := 0.14        # seconds for the knob to travel

var _t := 0.0              # 0 = off, 1 = on


func _init() -> void:
	toggle_mode = true
	custom_minimum_size = TRACK
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_t = 1.0 if button_pressed else 0.0
	toggled.connect(func(_on: bool) -> void: set_process(true))
	Themes.theme_changed.connect(func(_id: int) -> void: queue_redraw())
	set_process(false)
	queue_redraw()


## Sets the state without animating -- use when populating the screen.
func set_silent(on: bool) -> void:
	set_pressed_no_signal(on)
	_t = 1.0 if on else 0.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if button_pressed else 0.0
	_t = move_toward(_t, target, delta / SLIDE)
	queue_redraw()
	if is_equal_approx(_t, target):
		set_process(false)


func _draw() -> void:
	var ink: Color = Themes.value("ink", Themes.text_color("text"))
	var on: Color = Themes.text_color("accent")
	var off: Color = Themes.value("socket", Themes.text_color("muted"))
	var rect := Rect2(Vector2.ZERO, size)

	draw_rect(rect, (off as Color).lerp(on, _t))
	draw_rect(rect, ink, false, BORDER)

	# The knob slides between the two ends, inset by the track's padding.
	var travel := size.x - PAD * 2.0 - KNOB
	var pos := Vector2(PAD + travel * _t, (size.y - KNOB) * 0.5)
	var knob := Rect2(pos, Vector2(KNOB, KNOB))
	draw_rect(knob, Themes.value("knob", Color.WHITE))
	draw_rect(knob, ink, false, KNOB_BORDER)
