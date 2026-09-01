extends Control
## Launch screen. Fades the logo up, holds a beat, then hands off to the main
## menu. A tap, click or key press skips the rest of the sequence -- returning
## players should never have to sit through it.

const FADE_IN := 0.5
const HOLD := 1.1

@onready var _content: Control = %Content
@onready var _title: Label = %Title
@onready var _loading_bar: Control = %LoadingBarFill

var _leaving := false


func _ready() -> void:
	# Taken from project settings so the name lives in exactly one place.
	_title.text = App.game_wordmark()
	var n: int = Modes.grid_of(Modes.Id.PALETTE)
	%Tagline.text = "%d × %d  ·  DROP  ·  CLEAR" % [n, n]
	_content.modulate.a = 0.0
	_loading_bar.scale.x = 0.0

	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(_content, "modulate:a", 1.0, FADE_IN).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_loading_bar, "scale:x", 1.0, FADE_IN + HOLD) \
		.set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(HOLD)
	await tween.finished
	_leave()


func _unhandled_input(event: InputEvent) -> void:
	if _is_dismiss(event):
		accept_event()
		_leave()


func _is_dismiss(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed
	return event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	App.goto_scene(App.SCENE_MAIN_MENU)
