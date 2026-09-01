extends Control
class_name MenuScreen
## Shared behaviour for the screens reached from the main menu.
##
## Each of them needs the same three ways back: the on-screen Back button, the
## Android hardware back button, and Escape on desktop. Subclasses that define
## their own `_ready` must call `super()`.

func _ready() -> void:
	# Every button on every menu screen clicks.
	for b: Button in find_children("*", "Button", true, false):
		b.pressed.connect(func() -> void: Audio.play("tap"))
	var back := get_node_or_null("%BackButton")
	if back:
		back.pressed.connect(go_back)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		go_back()


func go_back() -> void:
	App.goto_scene(App.SCENE_MAIN_MENU)
