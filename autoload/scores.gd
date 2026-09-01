extends Node
## Local leaderboard: the top finished games, persisted between sessions.
##
## Autoloaded as `Scores`. Every completed run is submitted here, so this is
## the single source of truth for the best score shown on the HUD and the menu.

## The mode enum is reached through the script rather than the `Modes` autoload
## because Scores is declared first and would otherwise read it before it is
## ready.
const ModesScript := preload("res://autoload/modes.gd")

const SAVE_PATH := "user://scores.cfg"
## Kept PER MODE, so filtering the board never leaves a mode with one row.
const MAX_ENTRIES := 10

signal changed()

## Id of the entry submitted most recently this session, so the leaderboard can
## highlight the row the player just earned. -1 when there isn't one.
var last_id := -1
var last_rank := 0

var _entries: Array = []
var _next_id := 0


func _ready() -> void:
	_load()


func entries() -> Array:
	return _entries.duplicate(true)


func is_empty() -> bool:
	return _entries.is_empty()


## Best score, overall or within one mode. Runs in different modes are not
## comparable -- sixty seconds of Sprint is not an endless Palette run -- so
## the HUD asks for the current mode and only the menu asks for the overall.
func best(mode := -1) -> int:
	var top := 0
	for e: Dictionary in _entries:
		if mode >= 0 and int(e["mode"]) != mode:
			continue
		top = maxi(top, int(e["score"]))
	return top


## Entries for one mode, already ranked.
func entries_for(mode: int) -> Array:
	var out: Array = []
	for e: Dictionary in _entries:
		if int(e["mode"]) == mode:
			out.append(e.duplicate(true))
	return out


## Records a finished run and returns its 1-based rank WITHIN ITS MODE, or 0
## if the score did not make that mode's table. The mode is stored because a
## Sprint score and an endless Palette score are not comparable, and one table
## that hid the difference would be misleading.
func submit(score: int, lines: int, mode := ModesScript.Id.PALETTE) -> int:
	var entry := {
		"id": _next_id,
		"score": score,
		"lines": lines,
		"mode": int(mode),
		"date": int(Time.get_unix_time_from_system()),
	}
	_next_id += 1
	_entries.append(entry)
	_sort()
	_trim()

	last_id = -1
	last_rank = 0
	var seen := 0
	for e: Dictionary in _entries:
		if int(e["mode"]) != int(mode):
			continue
		seen += 1
		if int(e["id"]) == int(entry["id"]):
			last_id = int(entry["id"])
			last_rank = seen
			break

	_save()
	changed.emit()
	return last_rank


func _sort() -> void:
	# Highest score first; on a tie the older run keeps the better rank.
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return int(a["date"]) < int(b["date"]))


## Caps each mode independently, so a busy Palette table cannot push every
## Sprint run off the board.
func _trim() -> void:
	var kept: Array = []
	var counts: Dictionary = {}
	for e: Dictionary in _entries:
		var m := int(e["mode"])
		var n := int(counts.get(m, 0))
		if n < MAX_ENTRIES:
			counts[m] = n + 1
			kept.append(e)
	_entries = kept


func clear() -> void:
	_entries.clear()
	last_id = -1
	last_rank = 0
	_save()
	changed.emit()


static func format_date(unix_time: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


func _load() -> void:
	_entries.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var stored = cfg.get_value("leaderboard", "entries", [])
	if typeof(stored) != TYPE_ARRAY:
		return
	for row in stored:
		if typeof(row) != TYPE_DICTIONARY or not row.has("score"):
			continue          # ignore anything a hand-edited file got wrong
		# Rows written before modes existed carry a difficulty `level` string
		# and no mode; everything back then was the endless game.
		_entries.append({
			"id": 0,
			"score": int(row.get("score", 0)),
			"lines": int(row.get("lines", 0)),
			"mode": int(row.get("mode", ModesScript.Id.PALETTE)),
			"date": int(row.get("date", 0)),
		})
	_sort()
	_trim()
	# Ids are only meaningful within a session; hand out fresh ones on load.
	for i in _entries.size():
		_entries[i]["id"] = i
	_next_id = _entries.size()


func _save() -> void:
	var cfg := ConfigFile.new()
	var rows: Array = []
	for e: Dictionary in _entries:
		rows.append({"score": e["score"], "lines": e["lines"],
			"mode": e["mode"], "date": e["date"]})
	cfg.set_value("leaderboard", "entries", rows)
	cfg.save(SAVE_PATH)
