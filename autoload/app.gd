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
const SCENE_HOW_TO_PLAY := "res://scenes/how_to_play.tscn"
const SCENE_LEADERBOARD := "res://scenes/leaderboard.tscn"
const SCENE_GAME := "res://scenes/game.tscn"
const SCENE_MODES := "res://scenes/mode_select.tscn"
const SCENE_PROFILE := "res://scenes/profile.tscn"

const FADE_DURATION := 0.22


var game_name: String:
	get: return ProjectSettings.get_setting("application/config/name", "Pix Blast")

var game_version: String:
	get: return ProjectSettings.get_setting("application/config/version", "0.0.0")

var _fade: ColorRect
var _transitioning := false


func _ready() -> void:
	_lock_handheld_orientation()
	Themes.theme_changed.connect(_on_theme_changed)
	# The first scene is loaded by the engine, so set its bed here.
	Audio.play_music.call_deferred(_playlist_for(SCENE_SPLASH))
	# The first scene is loaded by the engine, not by goto_scene.
	apply_theme.call_deferred()
	# Above every screen, and still animating if the tree is ever paused.
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fade = ColorRect.new()
	_fade.name = "FadeOverlay"
	_fade.color = Color(0.035, 0.031, 0.086, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Portrait on a phone, free to rotate on a tablet.
##
## The project declares EVERY orientation, which looks wrong for a portrait
## game and is deliberate: iPadOS will not give the full screen to an app that
## supports a single orientation. It runs it in a compatibility window instead
## -- the game centred on the display with the rest left blank, which reads as
## "the background does not fill the screen" because what surrounds it is the
## system, not the game.
##
## So the plist says the app can rotate, and a phone is locked back to portrait
## here. A phone in landscape would leave the board marooned in the middle of a
## very wide strip; a tablet has the room to carry it either way, and the board
## sizes itself from its own width so it stays square at any aspect.
func _lock_handheld_orientation() -> void:
	if OS.get_name() != "iOS" and OS.get_name() != "Android":
		return
	if _is_tablet():
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)


## iOS model names are stable enough to test directly ("iPad13,1"). Elsewhere,
## fall back to the shorter screen edge in inches -- about 4.5in on the largest
## phones, comfortably under 7in on the smallest tablets.
func _is_tablet() -> bool:
	match OS.get_name():
		"iOS":
			return OS.get_model_name().begins_with("iPad")
		"Android":
			var dpi := DisplayServer.screen_get_dpi()
			if dpi <= 0:
				return false
			var px: Vector2i = DisplayServer.screen_get_size()
			return minf(px.x, px.y) / float(dpi) >= 6.0
		_:
			# Desktop has no handheld orientation to lock, and the inch test
			# would call a monitor a tablet.
			return false


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
	apply_theme()
	# Each screen picks its bed: the play screen shuffles the whole library,
	# everything else runs the short menu rotation. Also what brings music
	# back after a game-over stinger.
	Audio.play_music(_playlist_for(path))

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


## Backgrounding the app should never leave the motor running.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_CLOSE_REQUEST:
		Haptics.stop()


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_fade, "color:a", alpha, FADE_DURATION)
	await tween.finished


## Pushes the active theme's UI resource onto the current scene root. Godot
## propagates a Control's theme down the tree, so setting it on the root is
## enough -- per-node overrides in a scene still win, which is why screens
## avoid them (see the layout conventions in CLAUDE.md).
func apply_theme() -> void:
	var root := get_tree().current_scene as Control
	if root == null:
		return
	var ui := Themes.ui_theme()
	if ui != null:
		root.theme = ui


func _on_theme_changed(_id: int) -> void:
	apply_theme()


## The game name as the title screens draw it: upper case, one word per line.
## Derived from the project name so a rename carries through.
func game_wordmark() -> String:
	return "\n".join(Array(game_name.to_upper().split(" ", false)))


func _playlist_for(path: String) -> int:
	return Audio.List.GAME if path == SCENE_GAME else Audio.List.MENU
