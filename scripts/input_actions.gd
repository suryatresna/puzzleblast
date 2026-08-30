extends RefCounted
## Keyboard bindings for gameplay, registered at runtime.
##
## These live in code rather than project.godot because Godot serialises
## InputEvent resources into a form that is painful to hand-edit and easy to
## corrupt. Touch input is handled separately in game.gd.

const BINDINGS := {
	"piece_left": [KEY_LEFT, KEY_A],
	"piece_right": [KEY_RIGHT, KEY_D],
	"piece_soft_drop": [KEY_DOWN, KEY_S],
	"piece_hard_drop": [KEY_SPACE],
	"piece_rotate_cw": [KEY_UP, KEY_W, KEY_X],
	"piece_rotate_ccw": [KEY_Z],
	"game_pause": [KEY_P],
}


static func register() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
