extends Node
## Music and sound effects. Autoloaded as `Audio`.
##
## Assets live in `assets/audio/` and are meant to be replaced -- see
## assets/audio/README.md.
## Lookup is extension-agnostic: `Audio.play("place")` resolves
## `res://assets/audio/sfx/place` against .wav, .ogg and .mp3 in that order, so
## swapping a file's format needs no code change. A missing file is not an
## error; it just plays nothing, which keeps the game running while assets are
## being replaced.
##
## Preferences live in `user://settings.cfg` under [audio], alongside the
## other settings sections. This node owns those keys.

const SAVE_PATH := "user://settings.cfg"
const MUSIC_DIR := "res://assets/audio/music/"

## Tracks kept out of the in-game shuffle. `game_over` is reserved as the lose
## stinger; `theme` is the generated placeholder from before real music was
## added. Anything else dropped into assets/audio/music/ joins the shuffle
## automatically.
const MUSIC_EXCLUDE := ["game_over", "theme"]

## Played once when a run ends, instead of the shuffle.
const GAME_OVER_TRACK := "game_over"

## The menu bed: a fixed running order rather than a shuffle, so the front of
## the game always sounds the same.
const MENU_TRACKS := ["beach_house", "high_end_party", "light_music"]

## How many times a track repeats before the playlist moves on.
const MENU_REPEATS := 4
const GAME_REPEATS := 5

## Shortest track the shuffle will play. The music folder also contains short
## stingers and beat loops from the same asset pack (2-9s); dropped into a
## playlist that advances on `finished`, those would change the music every
## few seconds. Set to 0.0 to shuffle everything regardless of length.
const MIN_TRACK_SECONDS := 20.0
const SFX_DIR := "res://assets/audio/sfx/"
const EXTENSIONS := [".wav", ".ogg", ".mp3"]

## How many effects can overlap. A line clear that cascades fires several in
## the same frame, so one player is not enough.
const VOICES := 8

## Music sits under the effects on purpose -- it is a bed, not the point.
const MUSIC_HEADROOM_DB := -8.0
const SFX_HEADROOM_DB := -4.0

signal settings_changed

var music_on := true:
	set(v):
		if v == music_on: return
		music_on = v
		_save()
		_refresh_music()
		settings_changed.emit()

var sound_on := true:
	set(v):
		if v == sound_on: return
		sound_on = v
		_save()
		settings_changed.emit()

## 0.0 .. 1.0
var music_volume := 0.7:
	set(v):
		var c := clampf(v, 0.0, 1.0)
		if is_equal_approx(c, music_volume): return
		music_volume = c
		_save()
		_apply_music_volume()
		settings_changed.emit()

## PLAYLIST shuffles the bed; STINGER is a one-shot that must not be followed
## by another track (the game-over jingle).
enum Mode { PLAYLIST, STINGER }

## Which bed is running. MENU is a fixed short rotation; GAME shuffles the
## whole library.
enum List { MENU, GAME }

var _mode: int = Mode.PLAYLIST
var _list: int = List.MENU
## Plays remaining for the current track before the playlist advances.
var _repeats_left := 0
## Names still to play in the current shuffle, refilled when exhausted so
## every track is heard once before any repeats.
var _bag: Array[String] = []
var _tracks: Array[String] = []
var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}
var _loaded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # music continues while paused
	_load()
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_voices.append(p)
	_apply_music_volume()
	_tracks = _scan_music()
	# Start the bed here rather than from App: autoloads run in declaration
	# order and App is first, so it cannot safely call into this node yet.
	play_music()


## Plays a one-shot effect by name, e.g. "place" or "clear".
func play(name: String, pitch := 1.0) -> void:
	if not sound_on:
		return
	var stream := _resolve(SFX_DIR + name)
	if stream == null:
		return
	# Round-robin so a new sound never cuts off the previous one.
	var p := _voices[_next]
	_next = (_next + 1) % _voices.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = SFX_HEADROOM_DB
	p.play()


## Starts or resumes a bed. Safe to call repeatedly -- it is a no-op while the
## requested playlist is already running, so a scene change does not restart
## the track. Switching lists, or returning from a game-over stinger, starts
## the new list immediately.
func play_music(list: int = _list) -> void:
	if _music == null:
		return          # called before _ready; _ready starts the bed itself
	if _mode == Mode.PLAYLIST and _music.playing and list == _list:
		return
	var changed := list != _list
	_list = list
	_mode = Mode.PLAYLIST
	if changed:
		_bag.clear()    # start the new list cleanly rather than mid-rotation
	_next_track()


## Plays one track once, in place of the shuffle. Nothing follows it -- the
## bed stays quiet until `play_music()` is called again, which App does on the
## next scene change.
func play_stinger(track: String) -> void:
	if _music == null:
		return
	var stream := _resolve(MUSIC_DIR + track, false)
	if stream == null:
		play_music()    # a missing stinger must not leave the game silent
		return
	_mode = Mode.STINGER
	_set_loop(stream, false)
	_music.stream = stream
	_apply_music_volume()
	if music_on:
		_music.play()


## The run has ended -- the player lost, or nothing in the tray fits.
func play_game_over() -> void:
	play_stinger(GAME_OVER_TRACK)


func stop_music() -> void:
	if _music != null:
		_music.stop()


## Advances the shuffle. The bag is refilled once empty, so every track plays
## before any repeats, and a refill avoids replaying the track that just
## finished back to back.
func _next_track() -> void:
	var pool := _pool()
	if pool.is_empty():
		return
	if _bag.is_empty():
		_bag = pool.duplicate()
		if _list == List.GAME:
			# The menu list keeps its authored order; only the game shuffles.
			_bag.shuffle()
		if _bag.size() > 1 and _bag[0] == _current_track_name():
			_bag.push_back(_bag.pop_front())

	# Skip anything too short to work as a bed. Length is only known once the
	# stream is loaded, so this filters at selection rather than at scan time,
	# which also avoids holding the whole library in memory at boot.
	var stream: AudioStream = null
	for attempt in pool.size():
		if _bag.is_empty():
			break
		var name: String = _bag.pop_front()
		stream = _resolve(MUSIC_DIR + name, false)
		if stream != null and (_list == List.MENU
				or stream.get_length() >= MIN_TRACK_SECONDS):
			break
		stream = null
	if stream == null:
		return
	_set_loop(stream, false)      # the playlist advances instead of looping
	_music.stream = stream
	_repeats_left = MENU_REPEATS if _list == List.MENU else GAME_REPEATS
	_apply_music_volume()
	if music_on:
		_music.play()


## Track names for the active list. The menu list is filtered to what is
## actually on disk so a missing file degrades to the rest of the rotation
## rather than silence.
func _pool() -> Array[String]:
	if _list == List.GAME:
		return _tracks
	var out: Array[String] = []
	for name: String in MENU_TRACKS:
		if _resolve(MUSIC_DIR + name, false) != null:
			out.append(name)
	return out if not out.is_empty() else _tracks


func _current_track_name() -> String:
	if _music == null or _music.stream == null:
		return ""
	return String(_music.stream.resource_path).get_file().get_basename()


## Every music file in the directory that is not excluded. Scanned rather than
## listed so dropping a track into assets/audio/music/ needs no code change.
func _scan_music() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		push_warning("Audio: cannot open %s" % MUSIC_DIR)
		return found
	for entry: String in dir.get_files():
		# An exported build lists imported files, sometimes with a suffix.
		var file := entry
		for suffix: String in [".import", ".remap"]:
			if file.ends_with(suffix):
				file = file.trim_suffix(suffix)
		if not EXTENSIONS.has("." + file.get_extension().to_lower()):
			continue
		var name := file.get_basename()
		if name in MUSIC_EXCLUDE or name in found:
			continue
		found.append(name)
	found.sort()                  # stable order in, shuffled on the way out
	return found


## Music files loop only when they are the whole bed; a playlist advances.
func _set_loop(stream: AudioStream, on: bool) -> void:
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		if not on:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
		elif w.loop_mode == AudioStreamWAV.LOOP_DISABLED or w.loop_end <= 0:
			# Enabling the mode without a region loops over a ZERO-LENGTH
			# window: `playing` stays true, the position never advances, and
			# nothing is audible.
			w.loop_begin = 0
			w.loop_end = maxi(1, int(round(w.get_length() * w.mix_rate)))
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = on
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = on


## First existing file among the supported extensions, or null.
##
## Effects are cached -- they are small and fire constantly. Music is not:
## the library runs to tens of megabytes, and only one track plays at a time.
func _resolve(base: String, cache := true) -> AudioStream:
	if cache and _cache.has(base):
		return _cache[base]
	var found: AudioStream = null
	for ext: String in EXTENSIONS:
		if ResourceLoader.exists(base + ext):
			found = load(base + ext) as AudioStream
			if found != null:
				break
	if cache:
		_cache[base] = found
	if found == null:
		push_warning("Audio: no file for %s (tried %s)" % [base, ", ".join(EXTENSIONS)])
	return found


func _apply_music_volume() -> void:
	if _music == null:
		return
	# linear_to_db floors at -inf, which silences cleanly at zero.
	_music.volume_db = MUSIC_HEADROOM_DB + linear_to_db(maxf(music_volume, 0.0001))


func _refresh_music() -> void:
	if _music == null:
		return
	if music_on:
		if _music.stream != null and not _music.playing:
			_music.play()
		elif _music.stream == null:
			_next_track()
	else:
		_music.stop()


func _on_music_finished() -> void:
	# A stinger is deliberately the end of the line -- App restarts the bed on
	# the next scene change.
	if _mode != Mode.PLAYLIST or not music_on:
		return
	_repeats_left -= 1
	if _repeats_left > 0:
		_music.play()          # same track again
		return
	_next_track()


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	music_on = bool(cfg.get_value("audio", "music", true))
	sound_on = bool(cfg.get_value("audio", "sound", true))
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", 0.7)), 0.0, 1.0)


func _save() -> void:
	if not _loaded:
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # keep the other sections
	cfg.set_value("audio", "music", music_on)
	cfg.set_value("audio", "sound", sound_on)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.save(SAVE_PATH)
