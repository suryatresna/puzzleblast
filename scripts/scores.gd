extends Node
## Local leaderboard: the top finished games, persisted between sessions.
##
## Autoloaded as `Scores`. Every completed run is submitted here, so this is
## the single source of truth for the best score shown on the HUD and the menu.

const SAVE_PATH := "user://scores.cfg"
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


func best() -> int:
	return int(_entries[0]["score"]) if not _entries.is_empty() else 0


## Records a finished run and returns its 1-based rank, or 0 if the score did
## not make the table.
func submit(score: int, lines: int) -> int:
	var entry := {
		"id": _next_id,
		"score": score,
		"lines": lines,
		"date": int(Time.get_unix_time_from_system()),
	}
	_next_id += 1

	_entries.append(entry)
	# Highest score first; on a tie the older run keeps the better rank.
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return int(a["date"]) < int(b["date"]))
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)

	last_id = -1
	last_rank = 0
	for i in _entries.size():
		if int(_entries[i]["id"]) == int(entry["id"]):
			last_id = int(entry["id"])
			last_rank = i + 1
			break

	_save()
	changed.emit()
	return last_rank


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
		_entries.append({
			"id": 0,
			"score": int(row.get("score", 0)),
			"lines": int(row.get("lines", 0)),
			"date": int(row.get("date", 0)),
		})
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return int(a["date"]) < int(b["date"]))
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)
	# Ids are only meaningful within a session; hand out fresh ones on load.
	for i in _entries.size():
		_entries[i]["id"] = i
	_next_id = _entries.size()


func _save() -> void:
	var cfg := ConfigFile.new()
	var rows: Array = []
	for e: Dictionary in _entries:
		rows.append({"score": e["score"], "lines": e["lines"], "date": e["date"]})
	cfg.set_value("leaderboard", "entries", rows)
	cfg.save(SAVE_PATH)
