extends Control
## The shared backdrop. Can ease its whole palette toward a theme colour, which
## is how a combo streak recolours the screen.
##
## The gradient resource is duplicated on ready: sub-resources are shared
## between instances of a scene, so tinting one background would otherwise leak
## the colour into every other screen.

## Fallback palette, top stop first, used only if the active theme does not
## name one. The live values come from `Themes` so a theme swap repaints every
## backdrop in the game.
const BASE := [
	Color(0.129, 0.114, 0.31),
	Color(0.071, 0.063, 0.169),
	Color(0.035, 0.031, 0.086),
]
## How far each stop travels toward the tint. The top shifts most, so the
## bottom of the screen stays dark and the board keeps its contrast.
const WEIGHT := [0.85, 0.55, 0.28]

var _gradient: Gradient
var _tint := Color(0.5, 0.5, 0.5)
var _amount := 0.0
var _tween: Tween


func _ready() -> void:
	var rect := get_node_or_null("Gradient") as TextureRect
	if rect == null or rect.texture == null:
		return
	var tex: GradientTexture2D = rect.texture.duplicate(true)
	rect.texture = tex
	_gradient = tex.gradient
	Themes.theme_changed.connect(_on_theme_changed)
	_apply(_amount)


## Eases the backdrop toward `color`. An `amount` of 0 returns to the default
## palette; the colour is retained while fading out so it does not snap.
func tint_to(color: Color, amount: float, duration := 0.45) -> void:
	if amount > 0.0:
		_tint = color
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply, _amount, amount, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func tint_amount() -> float:
	return _amount


func _apply(amount: float) -> void:
	_amount = amount
	if _gradient == null:
		return
	var stops: Array = Themes.value("bg_stops", BASE)
	if stops.is_empty():
		stops = BASE
	var points := _gradient.get_point_count()
	for i in points:
		# The theme names a ramp of any length; sample it at this point's own
		# offset so a two-stop design and a three-stop one both work.
		var t := _gradient.get_offset(i) if points > 1 else 0.0
		var base: Color = _ramp(stops, t)
		var w: float = WEIGHT[i] if i < WEIGHT.size() else WEIGHT[WEIGHT.size() - 1]
		_gradient.set_color(i, base.lerp(_tint, amount * w))


## Colour at `t` (0..1) along an evenly spaced list of stops.
func _ramp(stops: Array, t: float) -> Color:
	if stops.size() == 1:
		return stops[0]
	var span := 1.0 / float(stops.size() - 1)
	var i := clampi(int(t / span), 0, stops.size() - 2)
	return (stops[i] as Color).lerp(stops[i + 1], clampf((t - i * span) / span, 0.0, 1.0))


## A theme swap repaints immediately, keeping whatever combo tint is active so
## a streak in progress is not visually interrupted.
func _on_theme_changed(_id: int) -> void:
	_apply(_amount)
