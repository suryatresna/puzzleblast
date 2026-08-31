extends Control
## Welcome page. Every entry routes through App so the transitions stay
## consistent; the game itself is still a placeholder, so New Game lands on a
## stub screen rather than doing nothing at all.

func _ready() -> void:
	%Title.text = App.game_wordmark()
	%Version.text = "v%s" % App.game_version
	%Best.text = "best  %d" % Scores.best() if not Scores.is_empty() else ""

	%NewGameButton.pressed.connect(App.goto_scene.bind(App.SCENE_GAME))
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
