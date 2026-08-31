extends Label
## A score readout that rolls up to new values instead of snapping to them,
## with a punch and a colour flash sized to how much was just gained.
##
## The roll is deliberately short for small gains -- placing a piece is worth a
## handful of points and should not leave the number visibly ticking -- and
## longer for a big line clear, so a large jump reads as an event.

const BASE_COLOR := Color(0.945, 0.941, 1)
const FLASH_COLOR := Color(1, 0.83, 0.32)

## The punch is driven by hand in _process rather than by a Tween. A tween
## latches its start value on the frame it first runs, which left the number
## sitting at normal size for a frame or two after the hit.
const PUNCH_TIME := 0.30

const MIN_ROLL := 0.18
const MAX_ROLL := 0.85
## Seconds of roll per point gained, before clamping.
const ROLL_PER_POINT := 0.0045

var _shown := 0
var _target := 0
var _roll: Tween
var _flash: Tween
var _punch_left := 0.0
var _punch_size := 0.0


func _ready() -> void:
	_recentre()
	resized.connect(_recentre)
	_render(0.0)
	_tint(0.0)


func _recentre() -> void:
	# Scale has to grow from the middle of the number, not its top-left.
	pivot_offset = size * 0.5


## Rolls the display up to `value`. `animate = false` snaps, for resets.
func set_value(value: int, animate := true) -> void:
	if animate and value == _target:
		return
	var gain: int = value - _shown
	_target = value

	_kill()

	# Snap on reset, or when the score moves backwards (a new run starting).
	if not animate or gain <= 0:
		_shown = value
		_render(float(value))
		_punch_left = 0.0
		scale = Vector2.ONE
		_tint(0.0)
		return

	var duration: float = clampf(gain * ROLL_PER_POINT, MIN_ROLL, MAX_ROLL)
	var punch: float = clampf(0.06 + gain * 0.0004, 0.06, 0.26)

	_roll = create_tween()
	_roll.tween_method(_render, float(_shown), float(value), duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	_punch_size = punch
	_punch_left = PUNCH_TIME
	_apply_punch()

	_flash = create_tween()
	_flash.tween_method(_tint, 1.0, 0.0, maxf(duration, 0.35)).set_ease(Tween.EASE_IN)


## Jumps straight to a value with no animation at all.
func reset_to(value: int) -> void:
	set_value(value, false)


func _render(raw: float) -> void:
	_shown = int(round(raw))
	text = str(_shown)


func _tint(amount: float) -> void:
	add_theme_color_override("font_color", BASE_COLOR.lerp(FLASH_COLOR, amount))


## Decays the punch quadratically: hardest right after the hit, settling to
## exactly 1.0 with no overshoot in either direction.
func _process(delta: float) -> void:
	if _punch_left <= 0.0:
		return
	_punch_left = maxf(0.0, _punch_left - delta)
	_apply_punch()


func _apply_punch() -> void:
	var k: float = _punch_left / PUNCH_TIME
	scale = Vector2.ONE * (1.0 + _punch_size * k * k)


func _kill() -> void:
	for tween in [_roll, _flash]:
		if tween is Tween and tween.is_valid():
			tween.kill()
