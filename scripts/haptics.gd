extends RefCounted
## Handheld vibration, tiered by how significant the moment is.
##
## This owns its own on/off preference and loads it on first use. It used to
## rely on the Settings screen to load it, which meant a player who turned
## vibration off and relaunched got it back until they opened Settings again.
##
## `Input.vibrate_handheld` is a no-op on desktop, but the platform is checked
## anyway so the intent is explicit and no stray buzz can fire during a
## headless test run.
##
## Intensity is deliberately restrained: placing a piece happens constantly, so
## it gets a tap you feel rather than notice, and only clears and blasts are
## allowed to be assertive.

const SAVE_PATH := "user://settings.cfg"

const PLACE_MS := 10
const PLACE_AMP := 0.30

const CLEAR_MS := 22
const CLEAR_AMP := 0.55

const BIG_MS := 40
const BIG_AMP := 0.85

const BLAST_MS := 60
const BLAST_AMP := 1.0

## A single placement can set off several of these at once -- the piece landing,
## a line clearing, a combo reward, a difficulty step. Android restarts the
## motor on every call, so back-to-back buzzes run together into one long
## rumble that feels stuck. Within this window only a stronger buzz gets
## through; weaker ones are dropped.
const THROTTLE_MS := 70

static var _enabled := true
static var _loaded := false
static var _last_time := 0
static var _last_strength := 0.0


static func is_enabled() -> bool:
	_ensure_loaded()
	return _enabled


## Persists immediately, so the choice survives a relaunch even if the player
## never returns to Settings.
static func set_enabled(on: bool) -> void:
	_ensure_loaded()
	if on == _enabled:
		return
	_enabled = on
	if not on:
		stop()
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # keep anything else already in the file
	cfg.set_value("game", "vibration", _enabled)
	cfg.save(SAVE_PATH)


## Cuts off whatever is currently playing. There is no cancel call in the API,
## so this overrides the running vibration with a one-millisecond nudge, which
## is how Android's vibrator behaves: a new request replaces the old.
static func stop() -> void:
	_last_time = 0
	_last_strength = 0.0
	if OS.get_name() not in ["Android", "iOS"]:
		return
	Input.vibrate_handheld(1, 0.01)


## A piece settling onto the board.
static func place() -> void:
	_buzz(PLACE_MS, PLACE_AMP)


## One or two lines going at once.
static func clear_lines(line_count: int) -> void:
	if line_count >= 3:
		_buzz(BIG_MS, BIG_AMP)
	else:
		_buzz(CLEAR_MS, CLEAR_AMP)


## A bomb or laser going off.
static func blast() -> void:
	_buzz(BLAST_MS, BLAST_AMP)


## Two beats, so beating your record feels different from a big clear. The
## second beat re-checks the setting, in case it was switched off in between.
static func celebrate(tree: SceneTree) -> void:
	_buzz(BIG_MS, BIG_AMP)
	if not is_enabled() or tree == null:
		return
	await tree.create_timer(0.14).timeout
	_buzz(BLAST_MS, BLAST_AMP)


static func _buzz(duration_ms: int, amplitude: float) -> void:
	if not is_enabled():
		return
	if OS.get_name() not in ["Android", "iOS"]:
		return

	var now := Time.get_ticks_msec()
	var strength := amplitude * float(duration_ms)
	if now - _last_time < THROTTLE_MS:
		if strength <= _last_strength:
			return               # something stronger is already running
	else:
		_last_strength = 0.0

	_last_time = now
	_last_strength = strength
	Input.vibrate_handheld(duration_ms, amplitude)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_enabled = bool(cfg.get_value("game", "vibration", true))
