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
signal bonus_changed(ready: bool, active: bool)

# --- level curve -------------------------------------------------------------

## threshold(L) = BASE * (GROWTH^(L-1) - 1) / (GROWTH - 1)
## L2 at 1,000, L6 at ~7k, L12 at ~29k, L25 at ~184k, L50 at ~6.3M.
##
## GROWTH was 1.35, which put the top power tiers past any reachable score --
## L45 needed 1.55 BILLION lifetime points against maybe 1-20k a run, so four
## of the five tiers and the 12x12 board were decoration. At 1.16 the same gate
## levels land at roughly a week, a fortnight, five months and ten months of
## committed play, and a strong player gets there sooner.
##
## Retuning this re-levels every existing save on the next load, which is what
## _catch_up_rewards() exists to survive -- read its note before touching it.
const LEVEL_BASE := 1000.0
const LEVEL_GROWTH := 1.16
const MAX_LEVEL := 60

## What each level hands over. Levels absent from this table give nothing but
## the number going up.
##   "power"  -> the player may unlock one power of their choosing
##   "slot"   -> a loadout slot
##   "theme"  -> that Themes.Id becomes selectable
##   "charge" -> added to max charge
## Power grants are spaced to match POWER_TIERS: two while the first tier is
## the only one open, then two as each gate falls. Handing out ten unlocks by
## L20, as this table used to, would have left eight of them unspendable behind
## a gate for a very long time.
const REWARDS := {
	2: {"power": 1, "slot": 1},
	3: {"charge": 5},
	4: {"power": 1, "slot": 1},
	5: {"theme": ThemesScript.Id.PIXEL_WARM},
	6: {"slot": 1},
	10: {"theme": ThemesScript.Id.CLASSIC},
	15: {"charge": 5},
	18: {"charge": 5},
	20: {"charge": 5},
	25: {"power": 1},
	27: {"power": 1},
	28: {"power": 1},
	30: {"power": 1},
	35: {"power": 1},
	37: {"power": 1},
	45: {"power": 1},
	47: {"power": 1},
	48: {"power": 1},
	50: {"power": 1},
	# 52, not 55. Tier 5 opens at L50; on the retuned curve L55 is 630 days of
	# committed play against L50's 300, so the tier's second power arrived more
	# than twice as late as the tier itself. Every other tier completes within
	# ~80 days of opening -- this now does too.
	52: {"power": 1},
}

# --- powers ------------------------------------------------------------------

## The level at which the endless board grows from 8x8 to 12x12. The player
## has to have earned the room before they get it.
const BIG_BOARD_LEVEL := 25

const LOADOUT_SIZE := 3
const MAX_POWER_LEVEL := 5

## Powers that cap below MAX_POWER_LEVEL. The two filling powers scale by a
## fraction of the empty board rather than by a cell count, and three steps
## (half, most, nearly all of it) is the whole range that expresses.
const POWER_MAX_LEVEL := {
	Blocks.Power.METEOR: 3,
	Blocks.Power.TSUNAMI: 3,
}

## The skill tree. Powers are ordered weakest to strongest -- the tiers track
## charge cost, which is the game's own measure of how much a power is worth --
## and each tier is sealed behind an account level. A banked unlock cannot be
## spent on a tier that has not opened, so the order the player meets the
## powers in is fixed even though WHICH of a tier's two they take is theirs.
##
## `level` 1 means no gate: the first tier is what a new player chooses from.
const POWER_TIERS := [
	{"level": 1, "powers": [Blocks.Power.FIT, Blocks.Power.MORPH]},
	{"level": 25, "powers": [Blocks.Power.SHUFFLE, Blocks.Power.THUNDER,
		Blocks.Power.LASER]},
	# Rewind breaks the cost ordering on purpose: at 7 it belongs in tier 5,
	# but it is the forgiveness power, and gating it behind the hardest levels
	# would put it furthest from the players who most need it.
	{"level": 30, "powers": [Blocks.Power.DIAGONAL, Blocks.Power.TELEPORT,
		Blocks.Power.REWIND]},
	{"level": 45, "powers": [Blocks.Power.METEOR, Blocks.Power.TSUNAMI,
		Blocks.Power.EARTHQUAKE]},
	{"level": 50, "powers": [Blocks.Power.BLACKHOLE, Blocks.Power.BOMB]},
]

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
	Blocks.Power.BLACKHOLE: 7,
	Blocks.Power.THUNDER: 4,
	Blocks.Power.TELEPORT: 5,
	Blocks.Power.METEOR: 5,
	Blocks.Power.TSUNAMI: 6,
	Blocks.Power.EARTHQUAKE: 6,
	Blocks.Power.SHUFFLE: 4,
	# MUST stay above max(CHARGE_PER_COMBO). Rewind restores the board but
	# never claws back charge already earned, so clear -> rewind -> re-clear is
	# a loop; it is only unprofitable while a rewind costs more than the
	# biggest combo pays. There is a test asserting exactly this.
	Blocks.Power.REWIND: 7,
}

## A doubled-XP session, earned two ways: by coming back three days running, or
## by playing three times in one day. Both bank the SAME single bonus, and
## `_bonus_ready` is a bool rather than a count, so hitting both -- or hitting
## one repeatedly -- can never stack them into a farm.
const STREAK_FOR_BONUS := 3
const PLAYS_FOR_BONUS := 3
const BONUS_XP_MULTIPLIER := 2

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
## The highest level the player has actually been shown. The profile compares
## it against `level` to decide whether its XP bar should celebrate.
var _seen_level := 1
## Highest level whose one-off rewards have been paid. See _catch_up_rewards().
var _rewarded_through := 1
## Runs started today, and whether a doubled session is waiting to be spent.
var _plays_today := 0
var _bonus_ready := false
## True only for the run currently being played. Not persisted: a bonus that was
## claimed and then abandoned mid-run is spent, the same as one played out.
var _bonus_active := false


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


## True when the player has levelled since the profile last showed them. Drives
## the XP bar's level-up animation.
func has_unseen_level() -> bool:
	_ensure_loaded()
	return _level > _seen_level


## The level the celebration should count up FROM.
func seen_level() -> int:
	_ensure_loaded()
	return _seen_level


func mark_level_seen() -> void:
	_ensure_loaded()
	if _seen_level == _level:
		return
	_seen_level = _level
	_save()


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
	_catch_up_rewards()
	_save()
	if gained > 0:
		level_changed.emit(_level, _pending_unlocks)
	return gained


## Grants the rewards for every level reached but not yet paid out, and records
## how far the ledger has been settled.
##
## `_level` is derived from the score, never stored, so it can move without
## anyone having gained anything -- most obviously if LEVEL_GROWTH is ever
## retuned, which re-levels every existing save on the next load. Before this
## existed, `_apply_reward` ran only from inside `add_score`'s own loop, so a
## level that arrived any other way silently skipped its grants: the player
## landed on an open tier with nothing banked to spend on it, and those powers
## and themes were gone for good.
##
## `"slot"` and `"charge"` never needed this -- `loadout_size()` and
## `max_charge()` re-derive them from `_level` on every call rather than
## accumulating. Only `"power"` and `"theme"` are paid once.
func _catch_up_rewards() -> bool:
	if _rewarded_through >= _level:
		return false
	for l in range(_rewarded_through + 1, _level + 1):
		_apply_reward(l)
	_rewarded_through = _level
	return true


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


## Which tier a power sits in, 1-based. 0 for anything not in the tree.
func tier_of(power: int) -> int:
	for i in POWER_TIERS.size():
		if (POWER_TIERS[i]["powers"] as Array).has(power):
			return i + 1
	return 0


## The account level that opens this power's tier. 1 when it is ungated.
func tier_level(power: int) -> int:
	var t := tier_of(power)
	if t <= 0:
		return 1
	return int(POWER_TIERS[t - 1]["level"])


## Whether the player has reached the level that opens this power's tier.
func is_tier_open(power: int) -> bool:
	_ensure_loaded()
	return _level >= tier_level(power)


## Powers the player could spend a banked unlock on right now.
func available_to_unlock() -> Array[int]:
	_ensure_loaded()
	var out: Array[int] = []
	for tier: Dictionary in POWER_TIERS:
		if _level < int(tier["level"]):
			continue
		for p: int in tier["powers"]:
			if not _unlocked.has(p):
				out.append(p)
	return out


## Spends one pending unlock on `power`. Returns false if there is nothing to
## spend, the power is already owned, it is not a real power, or its tier has
## not opened yet -- a banked unlock cannot skip a gate.
func unlock(power: int) -> bool:
	_ensure_loaded()
	if _pending_unlocks <= 0 or _unlocked.has(power):
		return false
	if not Blocks.ALL_POWERS.has(power):
		return false
	if not is_tier_open(power):
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


## The top level this power can reach. Most go to MAX_POWER_LEVEL.
func max_level_of(power: int) -> int:
	return int(POWER_MAX_LEVEL.get(power, MAX_POWER_LEVEL))


## 1..max_level_of(power), from the use count.
func level_of(power: int) -> int:
	var n := uses_of(power)
	var level := 1
	for i in range(1, USES_FOR_LEVEL.size()):
		if n >= USES_FOR_LEVEL[i]:
			level = i + 1
	return mini(level, max_level_of(power))


## Progress toward the next power level, 0..1. 1.0 when maxed.
func power_progress(power: int) -> float:
	var l := level_of(power)
	if l >= max_level_of(power):
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
	_plays_today = 0                 # a new day, so the play count starts over
	if _streak % STREAK_FOR_BONUS == 0:
		_grant_bonus()
	_save()
	streak_changed.emit(_streak)
	return true


# --- the doubled session ------------------------------------------------------

## Counts a run as started. Every PLAYS_FOR_BONUS runs in a day earns a bonus.
func note_run_started() -> void:
	_ensure_loaded()
	_plays_today += 1
	if _plays_today % PLAYS_FOR_BONUS == 0:
		_grant_bonus()
	_save()


## Banks a doubled session. Idempotent while one is already waiting -- that is
## what stops the two triggers stacking.
func _grant_bonus() -> void:
	if _bonus_ready:
		return
	_bonus_ready = true
	bonus_changed.emit(true, _bonus_active)


## Spends a waiting bonus on the run about to start. Returns whether it did.
func claim_bonus() -> bool:
	_ensure_loaded()
	_bonus_active = _bonus_ready
	if _bonus_ready:
		_bonus_ready = false
		_save()
	bonus_changed.emit(_bonus_ready, _bonus_active)
	return _bonus_active


func bonus_active() -> bool:
	_ensure_loaded()
	return _bonus_active


func bonus_ready() -> bool:
	_ensure_loaded()
	return _bonus_ready


## What a run's score is worth as XP right now.
func xp_multiplier() -> int:
	return BONUS_XP_MULTIPLIER if bonus_active() else 1


## Runs still to play today before the next bonus lands. 0 when one is already
## waiting. Drives the "play again" hint on the game-over panel.
func runs_until_bonus() -> int:
	_ensure_loaded()
	if _bonus_ready:
		return 0
	return PLAYS_FOR_BONUS - (_plays_today % PLAYS_FOR_BONUS)


func plays_today() -> int:
	_ensure_loaded()
	return _plays_today


## Thousands separators, for the screens that display these numbers.
static func commas(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" + out) if n < 0 else out


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
	_seen_level = maxi(1, int(cfg.get_value("progress", "seen_level", 1)))
	# Saves written before the ledger existed were settled by add_score as they
	# went, so they owe nothing up to their level: default to -1 and let the
	# assignment below seed it from the derived level.
	_rewarded_through = int(cfg.get_value("progress", "rewarded_through", -1))
	_plays_today = maxi(0, int(cfg.get_value("progress", "plays_today", 0)))
	_bonus_ready = bool(cfg.get_value("progress", "bonus_ready", false))
	# The level is derived, never trusted from disk -- a hand-edited file
	# cannot grant levels the score does not support.
	_level = level_for_score(_total_score)
	if _rewarded_through < 0:
		_rewarded_through = _level        # pre-ledger save: already settled
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
	# After everything is loaded, never before: the catch-up appends themes and
	# banks unlocks, and running it first would write into empty state and then
	# be overwritten by the file.
	if _catch_up_rewards():
		_save()
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
	cfg.set_value("progress", "seen_level", _seen_level)
	cfg.set_value("progress", "rewarded_through", _rewarded_through)
	cfg.set_value("progress", "plays_today", _plays_today)
	cfg.set_value("progress", "bonus_ready", _bonus_ready)
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
	_seen_level = 1
	_rewarded_through = 1
	_plays_today = 0
	_bonus_ready = false
	_bonus_active = false
	_save()
	level_changed.emit(_level, 0)
	charge_changed.emit(0, max_charge())
	loadout_changed.emit()
