extends Node
## Walks every res:// path the project names and asserts it resolves.
##
## This exists because most of this project's references are plain strings with
## no UID protection, and THREE classes of them fail silently rather than
## erroring: App's SCENE_* constants (goto_scene ignores change_scene_to_file's
## return), the directory prefixes in Audio and Themes (ResourceLoader.exists()
## returns false and the caller gets null), and Themes.DEFS["ui_theme"] (which
## returns null by design so a screen keeps its own theme). A broken path in any
## of those looks exactly like a working game until you navigate to the wrong
## screen or listen for the wrong sound.
##
## So "it still runs" proves nothing after a file moves. This does.
##
##   "$GODOT" --headless --path . res://tools/audit_paths.tscn
##
## Exits non-zero on the first missing path. Keep it green.

const Blocks := preload("res://scripts/blocks.gd")

var _fails := 0
var _checked := 0


func _ready() -> void:
	_routes()
	_themes()
	_audio()
	_project_settings()
	_source_strings()
	print("")
	if _fails == 0:
		print("PATH AUDIT OK  (%d paths resolve)" % _checked)
	else:
		print("PATH AUDIT FAILED  (%d of %d bad)" % [_fails, _checked])
	get_tree().quit(1 if _fails else 0)


func _ok(path: String, what: String) -> void:
	_checked += 1
	if path.ends_with("/"):
		if not DirAccess.dir_exists_absolute(path):
			_bad(path, what + " (directory)")
		return
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		_bad(path, what)


func _bad(path: String, what: String) -> void:
	_fails += 1
	print("MISSING  %-52s  %s" % [path, what])


## Every screen App can route to. These fail silently: change_scene_to_file
## returns an Error that goto_scene discards, so a dead constant just fades to
## nothing.
func _routes() -> void:
	for name in ["SCENE_SPLASH", "SCENE_MAIN_MENU", "SCENE_SETTINGS", "SCENE_ABOUT",
			"SCENE_LEADERBOARD", "SCENE_GAME", "SCENE_MODES", "SCENE_PROFILE"]:
		var path := String(App.get(name))
		if path.is_empty():
			_fails += 1
			print("MISSING  App.%s is not defined" % name)
			continue
		_ok(path, "App." + name)


## Every theme's UI resource and every power glyph sprite. ui_theme() returning
## null is a supported state, so a broken path here never raises.
func _themes() -> void:
	for id: int in [0, 1, 2]:
		Themes.peek(id)
		_ok(String(Themes.value("ui_theme", "")), "Themes.DEFS[%d].ui_theme" % id)
		for power: int in Blocks.ALL_POWERS:
			if Themes.GLYPHS.has(power):
				_ok("res://ui/pixel/%s.png" % Themes.GLYPHS[power],
					"glyph for %s" % Blocks.power_name(power))
		for key in ["tile", "tile_dark", "socket", "socket_dark", "plate",
				"panel", "panel_dark"]:
			_ok("res://ui/pixel/%s.png" % key, "sprite " + key)
	Themes.peek(Themes.ACTIVE)


## The two audio directories, and every effect name the game asks for by string.
## Audio resolves names against .wav/.ogg/.mp3 in turn and returns null on a
## miss, so a wrong directory is inaudible rather than fatal.
func _audio() -> void:
	_ok(Audio.MUSIC_DIR, "Audio.MUSIC_DIR")
	_ok(Audio.SFX_DIR, "Audio.SFX_DIR")
	# Both directories: play() resolves against sfx and play_stinger() against
	# music, and the scrape cannot tell which call a name came from.
	for name in _effect_names():
		var found := false
		for dir in [Audio.SFX_DIR, Audio.MUSIC_DIR]:
			for ext in [".wav", ".ogg", ".mp3"]:
				if ResourceLoader.exists(dir + name + ext):
					found = true
					break
			if found:
				break
		_checked += 1
		if not found:
			_bad(name + ".{wav,ogg,mp3}", "Audio effect \"%s\" in neither dir" % name)


## Scrapes every Audio.play("name") out of the source, so the list cannot drift.
func _effect_names() -> Array:
	var re := RegEx.create_from_string('Audio\\.play(?:_stinger)?\\("([a-z_]+)"')
	var names := {}
	for path in _all_scripts():
		for line in FileAccess.get_file_as_string(path).split("\n"):
			# Skip comments, or this file's own docstring describing the scrape
			# gets read as a call site.
			if (line as String).strip_edges().begins_with("#"):
				continue
			for m in re.search_all(line):
				names[m.get_string(1)] = true
	return names.keys()


## Everything project.godot names.
func _project_settings() -> void:
	for key in ["application/run/main_scene", "application/config/icon",
			"application/boot_splash/image", "gui/theme/custom"]:
		var path := String(ProjectSettings.get_setting(key, ""))
		if path.is_empty():
			continue
		_ok(path, key)
	# Autoloads are declared with a leading '*' for the singleton flag.
	for name in ["App", "Scores", "Themes", "Audio", "Modes", "GameServices", "Progress"]:
		var raw := String(ProjectSettings.get_setting("autoload/" + name, ""))
		if raw.is_empty():
			_fails += 1
			print("MISSING  autoload %s is not registered" % name)
			continue
		_ok(raw.trim_prefix("*"), "autoload " + name)


## Every res:// literal in every script, comments excluded. Catches preload,
## extends, load, ResourceLoader.exists and any bare path constant.
func _source_strings() -> void:
	var re := RegEx.create_from_string('"(res://[^"]*)"')
	for path in _all_scripts():
		var line_no := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			line_no += 1
			var bare := (line as String).strip_edges()
			if bare.begins_with("#"):
				continue          # a path in prose is documentation, not a load
			for m in re.search_all(line):
				var found: String = m.get_string(1)
				# A template, not a path -- the real one is built at runtime and
				# its pieces are covered by the directory checks above.
				if found.contains("%"):
					continue
				_ok(found, "%s:%d" % [path.get_file(), line_no])


func _all_scripts() -> Array:
	var out: Array = []
	_walk("res://", out)
	return out


func _walk(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry) if dir_path != "res://" \
			else "res://" + entry
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "ios":
				_walk(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
