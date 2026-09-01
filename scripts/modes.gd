extends Node
## Game modes. Autoloaded as `Modes`.
##
## A mode changes the rules of a run, not its presentation:
##
##   PALETTE  endless, exactly as the game has always played
##   SPRINT   sixty seconds, scored on whatever you manage in them
##   PUZZLE   a seeded starting board with a lines-to-clear objective
##
## `current` is read by `game.gd` when a run starts, so the mode must be set
## before routing to the play screen. Puzzle progress persists to
## `user://settings.cfg`; this node owns the `[modes]` section.
##
## NOTE ON PUZZLE BOARDS: the design describes "120 hand-built boards". These
## are generated from the level number instead, so board N is always identical
## but nobody authored it by hand. Swapping in authored layouts later only
## means replacing `puzzle_layout()`.

signal solved_changed

const SAVE_PATH := "user://settings.cfg"
const Blocks := preload("res://scripts/blocks.gd")

enum Id { PALETTE, SPRINT, PUZZLE, BIG_PALETTE }

## Cells per side, per mode. The board snaps its cell size to a whole multiple
## of the 32px sprite, so 8 plays at 128px cells and 12 at 87px.
##
## PALETTE is the exception: it starts at 8 and grows to 12 once the player
## reaches `Progress.BIG_BOARD_LEVEL`, so the endless mode opens up as they do.
const GRIDS := {
	Id.PALETTE: 8,
	Id.SPRINT: 8,
	Id.PUZZLE: 8,
	Id.BIG_PALETTE: 12,
}

## Seconds on the Sprint clock.
const SPRINT_SECONDS := 60.0

## How many puzzles exist. Boards are generated per level, so this is just how
## far the ladder goes.
const PUZZLE_COUNT := 120

const DEFS := {
	Id.PALETTE: {
		"name": "PALETTE",
		"blurb": "Endless. Colour flows with combos.",
		"icon": "swatches",
		"featured": true,      # drawn in the accent colour on the picker
	},
	Id.SPRINT: {
		"name": "SPRINT",
		"blurb": "Sixty seconds. Clear everything.",
		"icon": "60",
		"featured": false,
	},
	Id.BIG_PALETTE: {
		"name": "BIG PALETTE",
		"blurb": "Twelve across. Room to breathe, longer to fill.",
		"icon": "big",
		"featured": false,
	},
	Id.PUZZLE: {
		"name": "PUZZLE",
		"blurb": "%d seeded boards. %d solved.",
		"icon": "gem",
		"featured": false,
	},
}

var current: int = Id.PALETTE
## The board Puzzle mode will deal next, 1-based.
var puzzle_level := 1
var _solved: Dictionary = {}
var _loaded := false


func _ready() -> void:
	_load()


func data(id: int = current) -> Dictionary:
	return DEFS[id]


func mode_name(id: int = current) -> String:
	return String(DEFS[id]["name"])


## The picker's second line. Puzzle folds its progress into the text.
func blurb(id: int = current) -> String:
	var text := String(DEFS[id]["blurb"])
	if id == Id.PUZZLE:
		return text % [PUZZLE_COUNT, solved_count()]
	return text


func ids() -> Array:
	return DEFS.keys()


## Cells per side for a mode.
##
## Reads `Progress` at call time rather than caching: this runs when a run
## starts, long after every autoload is up, and the level can change between
## runs. Guarded anyway, because `Modes` is registered before `Progress`.
func grid_of(id: int = current) -> int:
	var base: int = int(GRIDS.get(id, 8))
	if id != Id.PALETTE:
		return base
	var progress: Node = get_node_or_null("/root/Progress")
	if progress == null:
		return base
	if progress.level() >= progress.BIG_BOARD_LEVEL:
		return int(GRIDS[Id.BIG_PALETTE])
	return base


func set_current(id: int) -> void:
	if DEFS.has(id):
		current = id


# --- puzzle progress ---------------------------------------------------------

func solved_count() -> int:
	_load()
	return _solved.size()


func is_solved(level: int) -> bool:
	_load()
	return _solved.has(level)


func mark_solved(level: int) -> void:
	_load()
	if _solved.has(level):
		return
	_solved[level] = true
	_save()
	solved_changed.emit()


## The next unsolved board, wrapping back to 1 once every one is done.
func next_unsolved() -> int:
	_load()
	for level in range(1, PUZZLE_COUNT + 1):
		if not _solved.has(level):
			return level
	return 1


# --- puzzle generation -------------------------------------------------------

## Lines the player must clear to solve this board. Ramps with the level so
## later boards ask for more.
func puzzle_target(level: int) -> int:
	return 2 + mini(6, (level - 1) / 12)


## Starting layout for a board, as {Vector2i: colour index}.
##
## Deterministic from the level. Two invariants matter: no row or column may
## start already full (it would clear the instant the board is drawn), and the
## board must keep enough room that the opening deal has somewhere to go.
func puzzle_layout(level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("pixelblast-puzzle-%d" % level)
	var size: int = grid_of(Id.PUZZLE)
	var cells: Dictionary = {}
	# Density climbs slowly: an early board is a light scatter, a late one is
	# most of the way to full.
	var density: float = clampf(0.28 + float(level - 1) * 0.004, 0.28, 0.6)
	for y in size:
		for x in size:
			if rng.randf() < density:
				cells[Vector2i(x, y)] = rng.randi_range(0, 7)
	# Guarantee a gap in every row and column.
	for i in size:
		var row_full := true
		var col_full := true
		for j in size:
			if not cells.has(Vector2i(j, i)): row_full = false
			if not cells.has(Vector2i(i, j)): col_full = false
		if row_full:
			cells.erase(Vector2i(rng.randi_range(0, size - 1), i))
		if col_full:
			cells.erase(Vector2i(i, rng.randi_range(0, size - 1)))
	return cells


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for level: int in Array(cfg.get_value("modes", "solved", [])):
		_solved[int(level)] = true
	puzzle_level = clampi(int(cfg.get_value("modes", "puzzle_level", 1)),
		1, PUZZLE_COUNT)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # keep the other sections
	var list: Array = _solved.keys()
	list.sort()
	cfg.set_value("modes", "solved", list)
	cfg.set_value("modes", "puzzle_level", puzzle_level)
	cfg.save(SAVE_PATH)
