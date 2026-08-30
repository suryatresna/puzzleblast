extends "res://scripts/menu_screen.gd"
## About page. The identity strings come from project settings via App so this
## screen and the menu footer can never drift apart.

func _ready() -> void:
	super()
	%Title.text = "About"
	%GameName.text = App.game_name
	%Details.text = "Version %s\nGodot %s\nAndroid & iOS" % [
		App.game_version,
		Engine.get_version_info().string,
	]
