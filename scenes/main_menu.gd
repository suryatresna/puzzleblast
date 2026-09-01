extends Control
## Welcome page. Every entry routes through App so the transitions stay
## consistent.

func _ready() -> void:
	%Title.text = App.game_wordmark()
	%Version.text = "v%s" % App.game_version
	%Best.text = "best  %d" % Scores.best() if not Scores.is_empty() else ""
	# Game Center sign-in is async and usually lands after this screen is up,
	# so the greeting is set now and again whenever authentication changes.
	GameServices.authentication_changed.connect(_sync_greeting)
	_sync_greeting()

	%NewGameButton.pressed.connect(_new_game)
	# The action is the same either way -- progression always carries over.
	# The label just stops "New Game" reading like a reset.
	%NewGameButton.text = "Continue" if Progress.has_progress() else "New Game"
	%ModesButton.pressed.connect(App.goto_scene.bind(App.SCENE_MODES))
	%ProfileButton.pressed.connect(App.goto_scene.bind(App.SCENE_PROFILE))
	%LeaderboardButton.pressed.connect(App.goto_scene.bind(App.SCENE_LEADERBOARD))
	%SettingsButton.pressed.connect(App.goto_scene.bind(App.SCENE_SETTINGS))
	%AboutButton.pressed.connect(App.goto_scene.bind(App.SCENE_ABOUT))
	%ExitButton.pressed.connect(App.quit_game)

	# Apple rejects iOS apps that offer a way to quit themselves, so the entry
	# is dropped there rather than shipped as a dead button.
	%ExitButton.visible = OS.get_name() != "iOS"

	%NewGameButton.grab_focus()


func _notification(what: int) -> void:
	# Android back button on the top-level menu means "leave the app".
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		App.quit_game()


## New Game is the front door: it always starts the endless mode, so it cannot
## silently drop the player into whatever they last picked on the Modes screen.
func _new_game() -> void:
	Modes.set_current(Modes.Id.PALETTE)
	App.goto_scene(App.SCENE_GAME)


func _sync_greeting(_ok: bool = false) -> void:
	var text := GameServices.greeting()
	%Greeting.text = text
	%Greeting.visible = not text.is_empty()
