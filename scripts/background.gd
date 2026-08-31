extends Control
## The shared backdrop. Can ease its whole palette toward a theme colour, which
## is how a combo streak recolours the screen.
##
## The gradient resource is duplicated on ready: sub-resources are shared
## between instances of a scene, so tinting one background would otherwise leak
## the colour into every other screen.

## Default palette, top stop first.
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
	_apply(0.0)


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
	for i in mini(BASE.size(), _gradient.get_point_count()):
		_gradient.set_color(i, BASE[i].lerp(_tint, amount * WEIGHT[i]))
