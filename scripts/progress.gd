extends Node
## Player progression. Autoloaded as `Progress`.
##
## Cumulative lifetime score is the XP. Crossing a level threshold grants a
## reward -- a power to unlock (the player picks which), a theme, or charge
## capacity. Powers themselves level 1..5 by being USED, not by spending
## anything, so the only way to a better bomb is to keep throwing bombs.
##
## Charge is a shared pool earned from combos and spent firing powers. It
## PERSISTS between runs: a short session still banks something, which is the
## whole reason to come back tomorrow.
##
## This owns `user://progress.cfg` outright rather than adding a fifth writer
## to the shared `settings.cfg`. Charge changes a dozen times a run, and every
## write to the shared file rewrites all of it -- enough to clobber a
## concurrent settings save. `scores.cfg` sets the precedent that a
## frequently-mutated domain gets its own file.

const Blocks := preload("res://scripts/blocks.gd")
const ThemesScript := preload("res://scripts/themes.gd")

const SAVE_PATH := "user://progress.cfg"

signal level_changed(level: int, pending_unlocks: int)
signal charge_changed(charge: int, max_charge: int)
signal power_level_changed(power: int, level: int)
signal loadout_changed()
signal streak_changed(streak: int)

# --- level curve -------------------------------------------------------------

## threshold(L) = BASE * (GROWTH^(L-1) - 1) / (GROWTH - 1)
## L2 at 1,000, L6 at ~10k, L12 at ~75k. Escalating so the early levels land
## fast and the tail stays long.
const LEVEL_BASE := 1000.0
const LEVEL_GROWTH := 1.35
const MAX_LEVEL := 60

## What each level hands over. Levels absent from this table give nothing but
## the number going up.
##   "power"  -> the player may unlock one power of their choosing
##   "slot"   -> a loadout slot
##   "theme"  -> that Themes.Id becomes selectable
##   "charge" -> added to max charge
const REWARDS := {
	2: {"power": 1, "slot": 1},
	3: {"charge": 5},
	4: {"power": 1, "slot": 1},
	5: {"theme": ThemesScript.Id.PIXEL_WARM},
	6: {"power": 1, "slot": 1},
	8: {"power": 1},
	10: {"theme": ThemesScript.Id.CLASSIC},
	12: {"power": 1},
	15: {"charge": 5},
	18: {"charge": 5},
	20: {"charge": 5},
}

# --- powers ------------------------------------------------------------------

## The level at which the endless board grows from 8x8 to 12x12. The player
## has to have earned the room before they get it.
const BIG_BOARD_LEVEL := 25

const LOADOUT_SIZE := 3
const MAX_POWER_LEVEL := 5

## Cumulative uses to reach each level. Index 0 is level 1, so a freshly
## unlocked power starts at 1 with zero uses.
const USES_FOR_LEVEL := [0, 10, 35, 85, 185]

## Charge to fire, per power. Roughly proportional to reach.
const COST := {
	Blocks.Power.BOMB: 8,
	Blocks.Power.MORPH: 4,
	Blocks.Power.LASER: 5,
	Blocks.Power.FIT: 3,
	Blocks.Power.DIAGONAL: 5,
}

const BASE_MAX_CHARGE := 10

## Charge paid by a clear, indexed by combo - 1. A combo of 1 pays nothing:
## charge is a reward for a streak, not for playing.
const CHARGE_PER_COMBO := [0, 1, 2, 3, 4]

var _loaded := false
var _total_score := 0
var _level := 1
## Level-ups banked but not yet spent on a power choice.
var _pending_unlocks := 0
var _unlocked: Array[int] = []
var _loadout: Array[int] = []
var _uses: Dictionary = {}
var _charge := 0
var _themes: Array[int] = []
var _last_played := ""
var _streak := 0
var _days_played := 0


func _ready() -> void:
	_ensure_loaded()


# --- level -------------------------------------------------------------------

## Cumulative score needed to reach `level`.
static func threshold(level: int) -> int:
	if level <= 1:
		return 0
	return int(round(LEVEL_BASE * (pow(LEVEL_GROWTH, level - 1) - 1.0)
		/ (LEVEL_GROWTH - 1.0)))


## The level a given lifetime score earns. Inverts `threshold`.
static func level_for_score(score: int) -> int:
	var level := 1
	while level < MAX_LEVEL and score >= threshold(level + 1):
		level += 1
	return level


func total_score() -> int:
	_ensure_loaded()
	return _total_score


func level() -> int:
	_ensure_loaded()
	return _level


## Whether the player has anything to carry over. Drives the menu's
## New Game / Continue label.
func has_progress() -> bool:
	_ensure_loaded()
	return _total_score > 0 or _level > 1


func pending_unlocks() -> int:
	_ensure_loaded()
	return _pending_unlocks


## Progress toward the next level, 0..1. Returns 1.0 at the cap.
func level_progress() -> float:
	_ensure_loaded()
	if _level >= MAX_LEVEL:
		return 1.0
	var floor_score := threshold(_level)
	var next := threshold(_level + 1)
	return clampf(float(_total_score - floor_score) / float(next - floor_score),
		0.0, 1.0)


## Banks a finished run. Returns how many levels it gained.
func add_score(points: int) -> int:
	_ensure_loaded()
	if points <= 0:
		return 0
	_total_score += points
	var was := _level
	_level = level_for_score(_total_score)
	var gained := _level - was
	for l in range(was + 1, _level + 1):
		_apply_reward(l)
	_save()
	if gained > 0:
		level_changed.emit(_level, _pending_unlocks)
	return gained


func _apply_reward(level_reached: int) -> void:
	var r: Dictionary = REWARDS.get(level_reached, {})
	if r.has("power"):
		_pending_unlocks += int(r["power"])
	if r.has("theme"):
		var t := int(r["theme"])
		if not _themes.has(t):
			_themes.append(t)
	# "slot" and "charge" are derived from the level, not stored -- see
	# loadout_size() and max_charge(). Nothing to do here.


## Loadout capacity: one slot per "slot" reward at or below the current level.
func loadout_size() -> int:
	_ensure_loaded()
	var n := 0
	for l: int in REWARDS:
		if l <= _level and REWARDS[l].has("slot"):
			n += int(REWARDS[l]["slot"])
	return mini(n, LOADOUT_SIZE)


func max_charge() -> int:
	_ensure_loaded()
	var n := BASE_MAX_CHARGE
	for l: int in REWARDS:
		if l <= _level and REWARDS[l].has("charge"):
			n += int(REWARDS[l]["charge"])
	return n


# --- power unlocks and loadout ----------------------------------------------

func unlocked() -> Array[int]:
	_ensure_loaded()
	return _unlocked.duplicate()


func is_unlocked(power: int) -> bool:
	_ensure_loaded()
	return _unlocked.has(power)


## Spends one pending unlock on `power`. Returns false if there is nothing to
## spend, the power is already owned, or it is not a real power.
func unlock(power: int) -> bool:
	_ensure_loaded()
	if _pending_unlocks <= 0 or _unlocked.has(power):
		return false
	if not Blocks.ALL_POWERS.has(power):
		return false
	_pending_unlocks -= 1
	_unlocked.append(power)
	# A newly unlocked power equips itself if there is room, so a player who
	# never opens the loadout screen still gets to use what they earned.
	if _loadout.size() < loadout_size():
		_loadout.append(power)
	_save()
	loadout_changed.emit()
	level_changed.emit(_level, _pending_unlocks)
	return true


func loadout() -> Array[int]:
	_ensure_loaded()
	return _loadout.duplicate()


## The power in a loadout slot, or Power.NONE.
func equipped(slot: int) -> int:
	_ensure_loaded()
	if slot < 0 or slot >= _loadout.size():
		return Blocks.Power.NONE
	return _loadout[slot]


## Puts `power` in `slot`. Passing Power.NONE clears it. A power already in
## another slot is moved rather than duplicated.
func equip(slot: int, power: int) -> bool:
	_ensure_loaded()
	if slot < 0 or slot >= loadout_size():
		return false
	if power != Blocks.Power.NONE and not _unlocked.has(power):
		return false
	while _loadout.size() < loadout_size():
		_loadout.append(Blocks.Power.NONE)
	if power != Blocks.Power.NONE:
		var existing := _loadout.find(power)
		if existing >= 0 and existing != slot:
			_loadout[existing] = Blocks.Power.NONE
	_loadout[slot] = power
	_save()
	loadout_changed.emit()
	return true


# --- power levels ------------------------------------------------------------

func uses_of(power: int) -> int:
	_ensure_loaded()
	return int(_uses.get(power, 0))


## 1..MAX_POWER_LEVEL, from the use count.
func level_of(power: int) -> int:
	var n := uses_of(power)
	var level := 1
	for i in range(1, USES_FOR_LEVEL.size()):
		if n >= USES_FOR_LEVEL[i]:
			level = i + 1
	return level


## Progress toward the next power level, 0..1. 1.0 when maxed.
func power_progress(power: int) -> float:
	var l := level_of(power)
	if l >= MAX_POWER_LEVEL:
		return 1.0
	var from: int = USES_FOR_LEVEL[l - 1]
	var to: int = USES_FOR_LEVEL[l]
	return clampf(float(uses_of(power) - from) / float(to - from), 0.0, 1.0)


# --- charge ------------------------------------------------------------------

func charge() -> int:
	_ensure_loaded()
	return _charge


func cost_of(power: int) -> int:
	return int(COST.get(power, 999))


func can_afford(power: int) -> bool:
	_ensure_loaded()
	return _unlocked.has(power) and _charge >= cost_of(power)


## True when anything in the loadout could be fired right now. `game.gd` uses
## this so a run does not end while a usable power is still in the bank.
func has_affordable() -> bool:
	_ensure_loaded()
	for p: int in _loadout:
		if p != Blocks.Power.NONE and can_afford(p):
			return true
	return false


## Pays out a clear. `combo` is board.gd's 1..MAX_COMBO streak counter.
func award_combo(combo: int) -> void:
	_ensure_loaded()
	var i := clampi(combo - 1, 0, CHARGE_PER_COMBO.size() - 1)
	var gain: int = CHARGE_PER_COMBO[i]
	if gain <= 0:
		return
	var before := _charge
	_charge = mini(_charge + gain, max_charge())
	if _charge != before:
		_save()
		charge_changed.emit(_charge, max_charge())


## Spends the cost of `power` and records the use. Returns false when it could
## not be paid for -- callers must only fire on true.
func spend(power: int) -> bool:
	_ensure_loaded()
	if not can_afford(power):
		return false
	_charge -= cost_of(power)
	var was := level_of(power)
	_uses[power] = uses_of(power) + 1
	_save()
	charge_changed.emit(_charge, max_charge())
	var now := level_of(power)
	if now != was:
		power_level_changed.emit(power, now)
	return true


# --- themes ------------------------------------------------------------------

## Themes the player may select. The shipped theme is always available so a
## fresh install is never themeless.
func unlocked_themes() -> Array[int]:
	_ensure_loaded()
	var out: Array[int] = [ThemesScript.ACTIVE]
	for t: int in _themes:
		if not out.has(t):
			out.append(t)
	return out


func is_theme_unlocked(id: int) -> bool:
	return unlocked_themes().has(id)


# --- daily -------------------------------------------------------------------

func streak() -> int:
	_ensure_loaded()
	return _streak


func days_played() -> int:
	_ensure_loaded()
	return _days_played


static func _today() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


## Records that the player showed up. Call once when a run starts. Returns true
## if this is the first run of a new day.
func touch_day() -> bool:
	_ensure_loaded()
	var today := _today()
	if _last_played == today:
		return false
	# Consecutive only if the last visit was literally yesterday.
	var yesterday := Time.get_datetime_string_from_unix_time(
		Time.get_unix_time_from_system() - 86400).substr(0, 10)
	_streak = _streak + 1 if _last_played == yesterday else 1
	_last_played = today
	_days_played += 1
	_save()
	streak_changed.emit(_streak)
	return true


# --- persistence -------------------------------------------------------------

func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_total_score = maxi(0, int(cfg.get_value("progress", "total_score", 0)))
	_pending_unlocks = maxi(0, int(cfg.get_value("progress", "pending_unlocks", 0)))
	_charge = maxi(0, int(cfg.get_value("progress", "charge", 0)))
	_last_played = String(cfg.get_value("progress", "last_played", ""))
	_streak = maxi(0, int(cfg.get_value("progress", "streak", 0)))
	_days_played = maxi(0, int(cfg.get_value("progress", "days_played", 0)))
	# The level is derived, never trusted from disk -- a hand-edited file
	# cannot grant levels the score does not support.
	_level = level_for_score(_total_score)
	for p in Array(cfg.get_value("progress", "unlocked", [])):
		var power := int(p)
		if Blocks.ALL_POWERS.has(power) and not _unlocked.has(power):
			_unlocked.append(power)
	# Slot POSITION is meaningful, so an empty or no-longer-owned slot is kept
	# as NONE rather than dropped -- collapsing the array would shift every
	# power after it into the wrong slot.
	for p in Array(cfg.get_value("progress", "loadout", [])):
		var power := int(p)
		var keep: bool = power != Blocks.Power.NONE \
			and _unlocked.has(power) and not _loadout.has(power)
		_loadout.append(power if keep else Blocks.Power.NONE)
	_loadout.resize(mini(_loadout.size(), LOADOUT_SIZE))
	var stored: Dictionary = cfg.get_value("progress", "uses", {})
	for key in stored:
		var power := int(key)
		if Blocks.ALL_POWERS.has(power):
			_uses[power] = maxi(0, int(stored[key]))
	for t in Array(cfg.get_value("progress", "themes", [])):
		var id := int(t)
		if not _themes.has(id):
			_themes.append(id)
	_charge = mini(_charge, max_charge())


func _save() -> void:
	if not _loaded:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "total_score", _total_score)
	cfg.set_value("progress", "pending_unlocks", _pending_unlocks)
	cfg.set_value("progress", "unlocked", _unlocked)
	cfg.set_value("progress", "loadout", _loadout)
	cfg.set_value("progress", "uses", _uses)
	cfg.set_value("progress", "charge", _charge)
	cfg.set_value("progress", "themes", _themes)
	cfg.set_value("progress", "last_played", _last_played)
	cfg.set_value("progress", "streak", _streak)
	cfg.set_value("progress", "days_played", _days_played)
	cfg.save(SAVE_PATH)


## Wipes everything. Only for a deliberate reset from a settings screen.
func wipe() -> void:
	_loaded = true
	_total_score = 0
	_level = 1
	_pending_unlocks = 0
	_unlocked.clear()
	_loadout.clear()
	_uses.clear()
	_charge = 0
	_themes.clear()
	_last_played = ""
	_streak = 0
	_days_played = 0
	_save()
	level_changed.emit(_level, 0)
	charge_changed.emit(0, max_charge())
	loadout_changed.emit()
