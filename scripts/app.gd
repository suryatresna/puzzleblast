extends CanvasLayer
## Autoloaded application shell.
##
## Owns the two things every screen needs: the identity strings shown in the
## UI, and scene routing. Routing goes through here (rather than each screen
## calling `change_scene_to_file` itself) so every transition gets the same
## fade and so a double-tap cannot kick off two scene loads at once.

const SCENE_SPLASH := "res://scenes/splash.tscn"
const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const SCENE_SETTINGS := "res://scenes/settings.tscn"
const SCENE_ABOUT := "res://scenes/about.tscn"
const SCENE_LEADERBOARD := "res://scenes/leaderboard.tscn"
const SCENE_GAME := "res://scenes/game.tscn"

const FADE_DURATION := 0.22

var game_name: String:
	get: return ProjectSettings.get_setting("application/config/name", "ComplexPuzzle")

var game_version: String:
	get: return ProjectSettings.get_setting("application/config/version", "0.0.0")

var _fade: ColorRect
var _transitioning := false


func _ready() -> void:
	# Above every screen, and still animating if the tree is ever paused.
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fade = ColorRect.new()
	_fade.name = "FadeOverlay"
	_fade.color = Color(0.035, 0.031, 0.086, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Fade to black, swap in `path`, fade back. Calls made while a transition is
## already running are dropped, so mashing two menu buttons loads one scene.
func goto_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true

	# Swallow input for the duration so the outgoing screen can't be tapped.
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0)

	get_tree().change_scene_to_file(path)
	# change_scene_to_file is deferred; let the swap land before revealing it.
	await get_tree().process_frame
	await get_tree().process_frame

	await _fade_to(0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false


## Leaves the app. Note that iOS App Store review rejects apps that quit
## programmatically, so the menu hides its Exit entry on that platform.
func quit_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0)
	get_tree().quit()


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_fade, "color:a", alpha, FADE_DURATION)
	await tween.finished
