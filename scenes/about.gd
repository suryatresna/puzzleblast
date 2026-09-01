extends MenuScreen
## About page. The identity strings come from project settings via App so this
## screen and the menu footer can never drift apart.

## Music attribution. The soundtrack is Abstraction's, and the licence asks for
## a visible credit -- keep this on screen.
const MUSIC_BY := "Abstraction"
const MUSIC_URL := "https://abstractionmusic.com/"

func _ready() -> void:
	super()
	%Title.text = "About"
	%GameName.text = App.game_name
	%Details.text = "Version %s\nGodot %s\nAndroid & iOS" % [
		App.game_version,
		Engine.get_version_info().string,
	]
	_build_credit()
	Themes.theme_changed.connect(func(_id: int) -> void: _build_credit())
	# An on-device readout: a build that will not sign in is otherwise only
	# diagnosable with a console attached.
	_sync_game_center()
	GameServices.authentication_changed.connect(
		func(_ok: bool) -> void: _sync_game_center())


func _sync_game_center() -> void:
	var show := OS.get_name() == "iOS"
	%GameCenterStatus.visible = show
	%GameCenterStatus.text = "Game Center: %s" % GameServices.status() if show else ""


## The link colour is pulled from the theme rather than hardcoded, so the
## credit stays readable whichever palette is active.
func _build_credit() -> void:
	var link: String = Themes.text_color("accent").to_html(false)
	%MusicCredit.text = "Music by %s\n[url=%s][color=#%s]%s[/color][/url]" % [
		MUSIC_BY, MUSIC_URL, link, MUSIC_URL.trim_prefix("https://").trim_suffix("/"),
	]
	if not %MusicCredit.meta_clicked.is_connected(_open_link):
		%MusicCredit.meta_clicked.connect(_open_link)


func _open_link(meta: Variant) -> void:
	Audio.play("tap")
	OS.shell_open(String(meta))
