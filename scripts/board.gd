extends Control
## The 8x8 well pieces are dropped onto.
##
## Owns grid state, placement rules, row/column clearing and the "no move left"
## test that ends the run. Presentation beyond drawing the grid itself lives in
## game.gd, which listens to the signals below.

const Blocks := preload("res://scripts/blocks.gd")

signal score_changed(score: int, best: int, combo: int)
signal lines_cleared(rows: Array, cols: Array, cell_count: int, points: int)
signal piece_placed(cells: Array, color_index: int)
signal bomb_detonated(at: Vector2i, from_row: int, to_row: int, cleared: int, points: int)
signal laser_fired(at: Vector2i, cleared: int, points: int, level: int)
signal diagonal_fired(at: Vector2i, cleared: int, points: int, level: int)
signal blackhole_fired(at: Vector2i, radius: float, cleared: int, points: int)
signal thunder_struck(cells: Array, cleared: int, points: int)
signal blocks_teleported(from_cells: Array, to_cells: Array, color_index: int)
signal meteor_landed(cells: Array, color_index: int, points: int)
signal tsunami_swept(cells: Array, color_index: int, points: int)
signal earthquake_shook(moved: Array, nudges: int)
signal board_morphed(dropped: int)
signal piece_fitted(cells: Array, color_index: int)
signal game_over()

## Default grid. `grid` is the live value -- Big Palette plays on 12 -- and is
## set before `reset()`. Not named `size`: that is Control's own property.
const SIZE := 8
const EMPTY := -1

## How long a freshly placed cell spends springing up to full size.
const POP_DURATION := 0.24

const POINTS_PER_CELL := 1
## Awarded per filled cell a bomb takes out.
const BOMB_POINTS_PER_CELL := 5
## Awarded per filled cell a laser burns through.
const LASER_POINTS_PER_CELL := 4
## Worth more per cell than the laser: the diagonals through a point are almost
## always shorter than its row and column, so an equal rate would make this
## strictly the weaker power.
const DIAGONAL_POINTS_PER_CELL := 6
## Most cells a fit piece will grow to. Without a cap it would swallow the
## whole board on an open layout.
const FIT_MAX_CELLS := 5

# --- power level tables ------------------------------------------------------
#
# These live here, beside the scoring constants, because what a laser DOES is a
# game rule. `Progress` owns cost and XP; it does not own geometry. Keeping the
# tables here also means board.gd stays testable with `Board.new()` and a plain
# int, with no autoload to register.
#
# `spread` is extra lines either side, so 0 covers one line, 1 covers three.
# Level 2 reproduces the behaviour these powers had before levels existed, so
# a maxed power beats the old one and a fresh one is weaker.
const MAX_POWER_LEVEL := 5

## Each level is a strict SUPERSET of the one below, so a bomb can never get
## weaker as it levels. That is not automatic: on an 8x8 board a 7x7 blast (49
## cells) already covers more than half the board (32), so "half the board"
## cannot simply be the top of the ramp -- level 5 takes the half AND the
## blast.
const BOMB_BY_LEVEL := [
	{"radius": 1, "row": false, "half": false},   # 3x3
	{"radius": 2, "row": false, "half": false},   # 5x5
	{"radius": 2, "row": true, "half": false},    # 5x5 + the row
	{"radius": 3, "row": true, "half": false},    # 7x7 + the row
	{"radius": 3, "row": true, "half": true},     # ...and the half (the original)
]
const LASER_BY_LEVEL := [
	{"column": false, "row_spread": 0, "col_spread": 0},
	{"column": true, "row_spread": 0, "col_spread": 0},    # the original
	{"column": true, "row_spread": 1, "col_spread": 0},
	{"column": true, "row_spread": 1, "col_spread": 1},
	{"column": true, "row_spread": 2, "col_spread": 2},
]
const DIAGONAL_BY_LEVEL := [
	{"both": false, "spread": 0, "core": 0},
	{"both": true, "spread": 0, "core": 0},                # the original
	{"both": true, "spread": 1, "core": 0},
	{"both": true, "spread": 2, "core": 0},
	{"both": true, "spread": 2, "core": 1},                # + a 3x3 at the strike
]
## Columns a collapse pulls down. 0 means every column.
const MORPH_COLUMNS := [1, 3, 5, 0, 0]
## Level 5 runs the drop twice, so a collapse that opens a line cashes it.
const MORPH_CHAIN_LEVEL := 5
const FIT_CELLS_BY_LEVEL := [3, 5, 7, 9, 12]

## Blackhole. A EUCLIDEAN radius, which is what separates it from the bomb --
## the bomb takes a square, this takes a disc. Levels are supersets for free
## here: a larger radius can only ever contain the smaller one. On an 8x8 the
## ramp covers 5, 9, 21, 37 and 49 cells.
const BLACKHOLE_RADIUS_BY_LEVEL := [1.2, 1.8, 2.5, 3.2, 4.0]

## Thunder picks OCCUPIED cells at random, so it is the one power whose reach
## cannot be a superset cell-for-cell. The ramp is monotonic in expectation
## instead: more strikes, and at the top each one takes its neighbours too.
const THUNDER_BY_LEVEL := [
	{"strikes": 1, "splash": false},
	{"strikes": 2, "splash": false},
	{"strikes": 3, "splash": false},
	{"strikes": 5, "splash": false},
	{"strikes": 8, "splash": true},
]

## Meteor and tsunami are the only powers that ADD blocks, so they are the only
## ones that can make the board worse. Both must leave at least this many cells
## empty AFTER the lines they complete have cleared: `_check_game_over` runs
## after every drop, so a fill that took the last of the room could end the run
## on the shot the player just paid for. It is a floor, not a proof that a
## given tray piece still fits, and a fill with no safe size refuses outright
## and is refunded rather than firing into a corner.
const FILL_FLOOR_ROWS := 1

## Both filling powers take a FRACTION of whatever is still empty, so their
## reach scales with the room available rather than with a fixed cell count.
## Three levels is the whole range that expresses: half of it, most of it,
## nearly all of it. Progress.POWER_MAX_LEVEL caps these two at 3 to match.
const FILL_SHARE_BY_LEVEL := [0.50, 0.70, 0.95]
const FILL_MAX_LEVEL := 3

## Earthquake. Blocks are jostled one cell at a time into whichever neighbour
## packs them tighter, and the shaking STOPS the moment a line completes -- so
## a low level is a nudge and a high one keeps going until something gives.
## Each nudge must strictly improve the board, which is also what guarantees
## the loop terminates rather than sliding one block back and forth.
const EARTHQUAKE_NUDGES_BY_LEVEL := [4, 8, 14, 22, 32]

## Teleport lifts the span x span block at the target and sets it down
## somewhere it fits. `tries` is how many destinations are sampled; `smart`
## picks the sampled destination that completes the most lines rather than the
## first one that fits, which is what turns it from a shuffle into a tool.
const TELEPORT_BY_LEVEL := [
	{"span": 1, "tries": 8, "smart": false},
	{"span": 2, "tries": 12, "smart": false},
	{"span": 2, "tries": 20, "smart": true},
	{"span": 3, "tries": 30, "smart": true},
	{"span": 3, "tries": 60, "smart": true},
]


## Clamps a level to the table range.
static func _lvl(level: int) -> int:
	return clampi(level, 1, MAX_POWER_LEVEL) - 1


## Clamps to a table that is SHORTER than MAX_POWER_LEVEL. The filling powers
## cap at three levels, so indexing them with _lvl() would run off the end.
static func _lvl_in(level: int, count: int) -> int:
	return clampi(level, 1, count) - 1
## How long settled blocks take to drop after a morph.
const FALL_TIME := 0.30
const LINE_BASE := 100
const MAX_COMBO := 5

var score := 0
var best := 0
var combo := 0
## Total rows + columns cleared this run, recorded on the leaderboard.
var lines := 0
var alive := true

## Cells the player is currently hovering a dragged piece over, and whether
## that position is legal. Drawn as a ghost.
var preview_cells: Array = []
var preview_valid := false
var preview_color := 0

var shake_offset := Vector2.ZERO:
	set(value):
		# Pixel themes snap the shake to whole pixels; a sub-pixel offset makes
		# every tile edge crawl against the grid during a screen shake.
		shake_offset = value.round() if _pixel else value
		queue_redraw()

## Cells per side. Change it through `set_grid()`, which rebuilds the board.
var grid := SIZE
var _grid: Array = []
## Cell -> seconds elapsed in its landing animation.
var _pops: Dictionary = {}
## Cell -> {dist, t}: blocks sliding down into place after a morph.
var _falls: Dictionary = {}
var _styles: Array[StyleBoxFlat] = []
var _empty_style := StyleBoxFlat.new()
var _ghost_ok := StyleBoxFlat.new()
var _ghost_bad := StyleBoxFlat.new()
## Cached from `Themes`, refreshed when the theme changes. A pixel theme draws
## the board from sprites instead of styleboxes.
var _pixel := false
var _tile_tex: Texture2D = null
var _socket_tex: Texture2D = null
var _grid_lines := true
var _last_cell := 0.0


## Resizes the grid and starts a fresh board. Presentation caches are rebuilt
## because the cell size changes with the grid.
func set_grid(cells: int) -> void:
	var n := maxi(2, cells)
	if n == grid:
		return
	grid = n
	_last_cell = -1.0
	reset()
	queue_redraw()


func _ready() -> void:
	_build_styles()
	Themes.theme_changed.connect(_on_theme_changed)
	resized.connect(queue_redraw)
	reset()


## Presentation only -- grid state is untouched, so a theme can be switched
## mid-run without disturbing the game.
func _on_theme_changed(_id: int) -> void:
	_build_styles()
	_last_cell = -1.0        # force _sync_metrics to recompute
	queue_redraw()


func reset() -> void:
	_grid.clear()
	for y in grid:
		var row := []
		row.resize(grid)
		row.fill(EMPTY)
		_grid.append(row)
	score = 0
	combo = 0
	lines = 0
	alive = true
	_pops.clear()
	_falls.clear()
	preview_cells = []
	score_changed.emit(score, best, combo)
	queue_redraw()


## Seeds the grid with a starting layout, as {Vector2i: colour index}. Puzzle
## mode uses this; the caller is responsible for the layout being legal (no
## row or column already full, or it clears the moment it is drawn).
func preset(cells: Dictionary) -> void:
	reset()
	for key: Vector2i in cells:
		if key.x < 0 or key.x >= grid or key.y < 0 or key.y >= grid:
			continue
		_grid[key.y][key.x] = int(cells[key])
	queue_redraw()


## How many cells are occupied. Puzzle mode reports progress with it.
func filled_count() -> int:
	var n := 0
	for y in grid:
		for x in grid:
			if _grid[y][x] != EMPTY:
				n += 1
	return n


## Sprites are authored at 32px, so a cell that is a whole multiple of that
## scales every tile by an exact integer -- 8 across gives 128 (4x).
const SPRITE_PX := 32.0

## ...but only while the snap is nearly free. On a 12-wide board the exact
## option is 64px, which fills barely 70% of the width and leaves a quarter of
## the board as dead margin; the honest alternative is 85px at a 2.66x scale.
## The tiles are a smooth gradient with a thick outline rather than fine pixel
## detail, so that resampling is hard to see, while a board a third smaller is
## impossible to miss. Snap when it is cheap, fill when it is not.
const MAX_SNAP_WASTE := 0.10

func cell_size() -> float:
	var c := size.x / float(grid)
	if not _pixel:
		return c
	var fill := floorf(c)
	var snapped := maxf(SPRITE_PX, floorf(c / SPRITE_PX) * SPRITE_PX)
	if fill <= 0.0:
		return fill
	return snapped if 1.0 - (snapped / fill) <= MAX_SNAP_WASTE else fill


## Offset that centres the grid when flooring the cell size leaves a remainder.
func grid_origin(cell: float) -> Vector2:
	if not _pixel:
		return Vector2.ZERO
	return Vector2(floorf((size.x - cell * grid) * 0.5),
		floorf((size.y - cell * grid) * 0.5))


# --- placement ---------------------------------------------------------------

## Powers that WRITE a tile behave like an ordinary piece and need an empty
## cell: `_morph` and `_fit` both assign into `_grid` at the target, so aiming
## one at an occupied cell would silently recolour a block. Everything else
## only destroys, and aiming a laser at a cluster is the whole point of firing
## one by hand.
const PLACING_POWERS := [Blocks.Power.MORPH, Blocks.Power.FIT]

## Powers that operate ON a block rather than on a square of board. Teleport
## has nothing to pick up over an empty cell, so aiming it at one is a misfire
## the player should not be billed for.
const OCCUPIED_POWERS := [Blocks.Power.TELEPORT]


## Whether a power may be fired at this spot. Ordinary placement (power NONE)
## is unchanged -- it still goes through can_place().
func can_target(cells: Array, origin: Vector2i, power := Blocks.Power.NONE) -> bool:
	if power == Blocks.Power.NONE or PLACING_POWERS.has(power):
		return can_place(cells, origin)
	if not _in_bounds(cells, origin):
		return false
	if OCCUPIED_POWERS.has(power):
		return _grid[origin.y][origin.x] != EMPTY
	return true


## Bounds only, without the occupancy test.
func _in_bounds(cells: Array, origin: Vector2i) -> bool:
	for c: Vector2i in cells:
		var p: Vector2i = origin + c
		if p.x < 0 or p.x >= grid or p.y < 0 or p.y >= grid:
			return false
	return true


func can_place(cells: Array, origin: Vector2i) -> bool:
	for c: Vector2i in cells:
		var p := origin + c
		if p.x < 0 or p.x >= grid or p.y < 0 or p.y >= grid:
			return false
		if _grid[p.y][p.x] != EMPTY:
			return false
	return true


## Places the piece, resolves any completed lines and updates the score.
## Returns false if the position was illegal and nothing changed.
func place(cells: Array, origin: Vector2i, color_index: int,
		power := Blocks.Power.NONE, level := 1) -> bool:
	if not alive or not can_target(cells, origin, power):
		return false

	if power != Blocks.Power.NONE:
		return _fire_power(power, origin, color_index, level)

	var placed: Array = []
	for c: Vector2i in cells:
		var p := origin + c
		_grid[p.y][p.x] = color_index
		_pops[p] = 0.0
		placed.append(p)
	score += placed.size() * POINTS_PER_CELL
	piece_placed.emit(placed, color_index)

	_resolve_lines()
	# Track the high-water mark here rather than only on clears, so the points
	# awarded for placing a piece count toward the best score too.
	best = maxi(best, score)
	score_changed.emit(score, best, combo)
	queue_redraw()
	return true


## Returns false when the power could not do anything -- `game.gd` treats that
## as a misfire and hands the charge back. Only teleport can fail: everything
## else either destroys something or legitimately hits an empty board.
func _fire_power(power: Blocks.Power, at: Vector2i, color_index: int,
		level := 1) -> bool:
	match power:
		Blocks.Power.BOMB: _detonate(at, level)
		Blocks.Power.LASER: _laser(at, level)
		Blocks.Power.MORPH: _morph(at, color_index, level)
		Blocks.Power.FIT: _fit(at, color_index, level)
		Blocks.Power.DIAGONAL: _diagonal(at, level)
		Blocks.Power.BLACKHOLE: _blackhole(at, level)
		Blocks.Power.THUNDER: _thunder(at, level)
		Blocks.Power.TELEPORT: return _teleport(at, level)
		Blocks.Power.METEOR: return _meteor(color_index, level)
		Blocks.Power.TSUNAMI: return _tsunami(color_index, level)
		Blocks.Power.EARTHQUAKE: return _earthquake(level)
		# The tray belongs to game.gd, not to the board. It intercepts these
		# two before place() is ever called; returning false here means a
		# wiring mistake shows up as a refund rather than as a power that
		# silently does nothing.
		Blocks.Power.SHUFFLE: return false
		Blocks.Power.REWIND: return false
	return true


## Burns out the whole row and column the laser lands on.
func _laser(at: Vector2i, level := 1) -> void:
	var spec: Dictionary = LASER_BY_LEVEL[_lvl(level)]
	var doomed := {}
	for d in range(-int(spec["row_spread"]), int(spec["row_spread"]) + 1):
		var y: int = at.y + d
		if y < 0 or y >= grid:
			continue
		for x in grid:
			doomed[Vector2i(x, y)] = true
	if bool(spec["column"]):
		for d in range(-int(spec["col_spread"]), int(spec["col_spread"]) + 1):
			var x: int = at.x + d
			if x < 0 or x >= grid:
				continue
			for y in grid:
				doomed[Vector2i(x, y)] = true

	var cleared := 0
	for cell: Vector2i in doomed:
		if _grid[cell.y][cell.x] != EMPTY:
			cleared += 1
		_grid[cell.y][cell.x] = EMPTY
		_pops.erase(cell)

	var points := cleared * LASER_POINTS_PER_CELL
	score += points
	best = maxi(best, score)
	laser_fired.emit(at, cleared, points, _lvl(level) + 1)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Clears both diagonals through the placed cell -- the one shape the laser
## cannot make. Unlike a row and column, the two diagonals through a point vary
## in length with where it sits, so a corner strike is weak and a centre strike
## is strong. That is the trade the player is making.
func _diagonal(at: Vector2i, level := 1) -> void:
	var spec: Dictionary = DIAGONAL_BY_LEVEL[_lvl(level)]
	var spread: int = int(spec["spread"])
	var doomed := {}
	for i in range(-grid, grid):
		# `off` walks the parallel diagonals either side of the strike.
		for off in range(-spread, spread + 1):
			var line: Array[Vector2i] = [Vector2i(at.x + i + off, at.y + i)]
			if bool(spec["both"]):
				line.append(Vector2i(at.x + i + off, at.y - i))
			for cell: Vector2i in line:
				if cell.x >= 0 and cell.x < grid and cell.y >= 0 and cell.y < grid:
					doomed[cell] = true
	for r in range(-int(spec["core"]), int(spec["core"]) + 1):
		for c in range(-int(spec["core"]), int(spec["core"]) + 1):
			var cell := Vector2i(at.x + c, at.y + r)
			if cell.x >= 0 and cell.x < grid and cell.y >= 0 and cell.y < grid:
				doomed[cell] = true

	var cleared := 0
	for cell: Vector2i in doomed:
		if _grid[cell.y][cell.x] != EMPTY:
			cleared += 1
		_grid[cell.y][cell.x] = EMPTY
		_pops.erase(cell)

	var points := cleared * DIAGONAL_POINTS_PER_CELL
	score += points
	best = maxi(best, score)
	diagonal_fired.emit(at, cleared, points, _lvl(level) + 1)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Drops every settled block to the bottom of its column, closing the gaps a
## run leaves behind. Rows completed by the collapse then clear and score, so a
## well-timed morph can cash in a board that looked wasted.
func _morph(at: Vector2i, color_index: int, level := 1) -> void:
	_grid[at.y][at.x] = color_index          # the piece itself falls too
	_pops[at] = 0.0

	# A low-level collapse only pulls the columns around the strike; by level 4
	# it takes the whole board, and level 5 runs a second pass so a drop that
	# opens a line gets to cash it.
	var span: int = int(MORPH_COLUMNS[_lvl(level)])
	var passes: int = 2 if _lvl(level) + 1 >= MORPH_CHAIN_LEVEL else 1
	var dropped := 0
	for pass_i in passes:
		dropped += _drop_columns(at.x, span)

	board_morphed.emit(dropped)
	_resolve_lines()
	best = maxi(best, score)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Pulls settled blocks to the bottom of their column. `span` columns centred
## on `centre`, or every column when span is 0. Returns how many blocks moved.
func _drop_columns(centre: int, span: int) -> int:
	var dropped := 0
	var from_x: int = 0 if span <= 0 else maxi(0, centre - span / 2)
	var to_x: int = grid - 1 if span <= 0 else mini(grid - 1, centre + span / 2)
	for x in range(from_x, to_x + 1):
		var write := grid - 1
		for y in range(grid - 1, -1, -1):
			if _grid[y][x] == EMPTY:
				continue
			if write != y:
				_grid[write][x] = _grid[y][x]
				_grid[y][x] = EMPTY
				_pops.erase(Vector2i(x, y))
				# Remember how far it fell so it can be animated in.
				_falls[Vector2i(x, write)] = {"dist": float(write - y), "t": 0.0}
				dropped += 1
			write -= 1
	return dropped


## Grows to fill the pocket of empty cells it was dropped into, up to
## FIT_MAX_CELLS. Breadth-first from the drop point, so it spreads evenly
## rather than snaking off in one direction.
func _fit(at: Vector2i, color_index: int, level := 1) -> void:
	var filled: Array = []
	var seen := {at: true}
	var queue: Array = [at]

	var budget: int = int(FIT_CELLS_BY_LEVEL[_lvl(level)])
	while not queue.is_empty() and filled.size() < budget:
		var cell: Vector2i = queue.pop_front()
		_grid[cell.y][cell.x] = color_index
		_pops[cell] = 0.0
		filled.append(cell)
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = cell + step
			if n.x < 0 or n.x >= grid or n.y < 0 or n.y >= grid:
				continue
			if seen.has(n) or _grid[n.y][n.x] != EMPTY:
				continue
			seen[n] = true
			queue.append(n)

	score += filled.size() * POINTS_PER_CELL
	piece_fitted.emit(filled, color_index)
	_resolve_lines()
	best = maxi(best, score)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Wipes the half of the board the bomb landed in.## Wipes the half of the board the bomb landed in. The split is along the
## horizontal midline, so the player can aim it at whichever half is worse.
## Nothing is scored for the bomb cell itself -- only for what it destroys.
func _detonate(at: Vector2i, level := 1) -> void:
	var spec: Dictionary = BOMB_BY_LEVEL[_lvl(level)]
	var radius: int = int(spec["radius"])
	var doomed := {}

	for y in range(at.y - radius, at.y + radius + 1):
		for x in range(at.x - radius, at.x + radius + 1):
			if x >= 0 and x < grid and y >= 0 and y < grid:
				doomed[Vector2i(x, y)] = true
	if bool(spec["row"]):
		for x in grid:
			doomed[Vector2i(x, at.y)] = true
	if bool(spec["half"]):
		@warning_ignore("integer_division")
		var half := grid / 2
		var top: int = 0 if at.y < half else half
		for y in range(top, top + half):
			for x in grid:
				doomed[Vector2i(x, y)] = true

	var cleared := 0
	var from_row := grid
	var to_row := 0
	for cell: Vector2i in doomed:
		from_row = mini(from_row, cell.y)
		to_row = maxi(to_row, cell.y)
		if _grid[cell.y][cell.x] != EMPTY:
			cleared += 1
			_grid[cell.y][cell.x] = EMPTY
			_pops.erase(cell)

	var points := cleared * BOMB_POINTS_PER_CELL
	score += points
	best = maxi(best, score)
	# A bomb neither builds nor breaks a line-clear streak.
	bomb_detonated.emit(at, from_row, to_row, cleared, points)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Collapses a disc of the board into the target. Unlike the bomb, which takes
## a square, the reach is a true radius -- corners survive a blackhole that
## would have died to a bomb of the same nominal size.
func _blackhole(at: Vector2i, level := 1) -> void:
	var radius: float = float(BLACKHOLE_RADIUS_BY_LEVEL[_lvl(level)])
	var span := int(ceilf(radius))
	var cleared := 0
	for y in range(at.y - span, at.y + span + 1):
		for x in range(at.x - span, at.x + span + 1):
			if x < 0 or x >= grid or y < 0 or y >= grid:
				continue
			if Vector2(x - at.x, y - at.y).length() > radius:
				continue
			if _grid[y][x] != EMPTY:
				cleared += 1
				_grid[y][x] = EMPTY
				_pops.erase(Vector2i(x, y))

	var points := cleared * BOMB_POINTS_PER_CELL
	score += points
	best = maxi(best, score)
	blackhole_fired.emit(at, radius, cleared, points)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Strikes occupied cells at random, wherever they are. The drop point does not
## aim it -- it is weather, not artillery -- which is why it is the cheapest
## power that removes blocks and the only one that is useful on a full board
## the player cannot otherwise reach into.
func _thunder(_at: Vector2i, level := 1) -> void:
	var spec: Dictionary = THUNDER_BY_LEVEL[_lvl(level)]
	var occupied: Array[Vector2i] = []
	for y in grid:
		for x in grid:
			if _grid[y][x] != EMPTY:
				occupied.append(Vector2i(x, y))
	occupied.shuffle()

	var struck: Array = []
	var doomed := {}
	for i in mini(int(spec["strikes"]), occupied.size()):
		var cell: Vector2i = occupied[i]
		struck.append(cell)
		doomed[cell] = true
		if bool(spec["splash"]):
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = cell + step
				if n.x >= 0 and n.x < grid and n.y >= 0 and n.y < grid:
					doomed[n] = true

	var cleared := 0
	for cell: Vector2i in doomed:
		if _grid[cell.y][cell.x] != EMPTY:
			cleared += 1
			_grid[cell.y][cell.x] = EMPTY
			_pops.erase(cell)

	var points := cleared * BOMB_POINTS_PER_CELL
	score += points
	best = maxi(best, score)
	thunder_struck.emit(struck, cleared, points)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Lifts the square of blocks at the target and sets it down somewhere it fits.
## The blocks are not destroyed -- this is the one power that rearranges rather
## than removes, which is what makes it the answer to a board that is not full
## but is badly shaped.
func _teleport(at: Vector2i, level := 1) -> bool:
	var spec: Dictionary = TELEPORT_BY_LEVEL[_lvl(level)]
	var span: int = int(spec["span"])

	# Lift: the occupied cells of the span x span square, as offsets from `at`,
	# keeping each one's colour so the block arrives looking like itself.
	var lifted: Array[Vector2i] = []
	var colors: Array[int] = []
	for dy in span:
		for dx in span:
			var c := Vector2i(at.x + dx, at.y + dy)
			if c.x >= grid or c.y >= grid:
				continue
			if _grid[c.y][c.x] != EMPTY:
				lifted.append(Vector2i(dx, dy))
				colors.append(int(_grid[c.y][c.x]))
	if lifted.is_empty():
		return false

	for i in lifted.size():
		var c: Vector2i = at + lifted[i]
		_grid[c.y][c.x] = EMPTY
		_pops.erase(c)

	var best_at := Vector2i(-1, -1)
	var best_gain := -1
	for _try in int(spec["tries"]):
		var dest := Vector2i(randi() % grid, randi() % grid)
		if dest == at or not can_place(lifted, dest):
			continue
		if not bool(spec["smart"]):
			best_at = dest
			break
		var gain := _lines_completed_by(lifted, dest)
		if gain > best_gain:
			best_gain = gain
			best_at = dest

	# Nowhere to go: put it back exactly where it was. The caller reads this as
	# a misfire and refunds, so a full board cannot eat the charge.
	if best_at.x < 0:
		for i in lifted.size():
			var c: Vector2i = at + lifted[i]
			_grid[c.y][c.x] = colors[i]
		return false

	var landed: Array = []
	for i in lifted.size():
		var c: Vector2i = best_at + lifted[i]
		_grid[c.y][c.x] = colors[i]
		_pops[c] = 0.0
		landed.append(c)

	var from_cells: Array = []
	for off: Vector2i in lifted:
		from_cells.append(at + off)
	blocks_teleported.emit(from_cells, landed, colors[0])
	_resolve_lines()
	best = maxi(best, score)
	score_changed.emit(score, best, combo)
	queue_redraw()
	return true


## Every empty cell on the board.
func _empty_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in grid:
		for x in grid:
			if _grid[y][x] == EMPTY:
				out.append(Vector2i(x, y))
	return out


## How close this cell is to completing a line: the fuller of its row and its
## column. Filling the highest-pressure cell is what makes an aimed meteor
## finish lines rather than clutter the board.
func _fill_pressure(cell: Vector2i) -> int:
	var row := 0
	var col := 0
	for i in grid:
		if _grid[cell.y][i] != EMPTY:
			row += 1
		if _grid[i][cell.x] != EMPTY:
			col += 1
	return maxi(row, col)


## Writes `cells` into the grid and scores them, then resolves any lines they
## completed. Shared by both filling powers.
func _settle_fill(cells: Array, color_index: int) -> int:
	for c: Vector2i in cells:
		_grid[c.y][c.x] = color_index
		_pops[c] = 0.0
	var points: int = cells.size() * POINTS_PER_CELL
	score += points
	return points


## How many cells would be empty if `order[0..n)` were filled and every line
## that completed then cleared. Exact rather than a guess: it is what lets the
## fill honour a 95% share whenever that is safe, instead of capping every cast
## at a conservative floor.
func _empties_after_fill(order: Array, n: int) -> int:
	var filled := {}
	for i in n:
		filled[order[i]] = true

	var full_rows := {}
	var full_cols := {}
	for y in grid:
		var whole := true
		for x in grid:
			if _grid[y][x] == EMPTY and not filled.has(Vector2i(x, y)):
				whole = false
				break
		if whole:
			full_rows[y] = true
	for x in grid:
		var whole := true
		for y in grid:
			if _grid[y][x] == EMPTY and not filled.has(Vector2i(x, y)):
				whole = false
				break
		if whole:
			full_cols[x] = true

	var empty := 0
	for y in grid:
		for x in grid:
			if full_rows.has(y) or full_cols.has(x):
				empty += 1
				continue
			if _grid[y][x] == EMPTY and not filled.has(Vector2i(x, y)):
				empty += 1
	return empty


## The largest prefix of `order` that still leaves the board alive. Safety is
## NOT monotonic -- filling more can clear more and end up emptier -- so this
## walks down from what the level asked for and takes the first size that
## holds, which is the biggest one at or under the request.
func _safe_fill_size(order: Array, want: int) -> int:
	var floor_cells: int = grid * FILL_FLOOR_ROWS
	for n in range(want, -1, -1):
		if _empties_after_fill(order, n) >= floor_cells:
			return n
	return 0


## How many cells this level fills, as a share of what is still empty.
func _fill_share(empties: int, level: int) -> int:
	var share: float = float(FILL_SHARE_BY_LEVEL[_lvl_in(level, FILL_MAX_LEVEL)])
	return int(round(float(empties) * share))


## Rains single blocks onto empty cells, hunting for the ones that complete a
## line. Level sets the share of the empty board it takes: half, most, or
## nearly all of it. Whatever it completes clears on the spot, so a big meteor
## usually hands back more room than it took.
func _meteor(color_index: int, level := 1) -> bool:
	var empties := _empty_cells()
	if empties.is_empty():
		return false
	empties.shuffle()                        # ties resolve differently each cast

	# Ordered greedily by line pressure, recomputed as the fill goes, so the
	# volley finishes one line before starting another rather than smearing
	# across the board.
	var order: Array = []
	var pool := empties.duplicate()
	var want: int = _fill_share(empties.size(), level)
	var pending := {}
	while order.size() < want and not pool.is_empty():
		var pick := 0
		var best := -1
		for k in pool.size():
			var p: int = _fill_pressure(pool[k]) + _pending_pressure(pending, pool[k])
			if p > best:
				best = p
				pick = k
		var cell: Vector2i = pool[pick]
		pool.remove_at(pick)
		order.append(cell)
		pending[cell] = true

	var take := _safe_fill_size(order, order.size())
	if take <= 0:
		return false
	var landed: Array = order.slice(0, take)
	var points := _settle_fill(landed, color_index)
	meteor_landed.emit(landed, color_index, points)
	_resolve_lines()
	best = maxi(best, score)
	score_changed.emit(score, best, combo)
	queue_redraw()
	return true


## Rows and columns this cell shares with cells already queued for the fill.
## Without it the greedy order would keep picking from the same untouched row,
## because writing has not happened yet and _fill_pressure cannot see the plan.
func _pending_pressure(pending: Dictionary, cell: Vector2i) -> int:
	var row := 0
	var col := 0
	for c: Vector2i in pending:
		if c.y == cell.y:
			row += 1
		if c.x == cell.x:
			col += 1
	return maxi(row, col)


## Floods the board from the bottom up, like water, taking a share of whatever
## is empty. Filling the lowest gaps first is the aim: those are the rows a run
## leaves most nearly complete.
func _tsunami(color_index: int, level := 1) -> bool:
	var empties := _empty_cells()
	if empties.is_empty():
		return false
	# Bottom row first; within a row, the fuller column first, so a wave that
	# cannot finish a row still leaves the board tidier than it found it.
	empties.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y > b.y
		return _fill_pressure(a) > _fill_pressure(b))

	var want: int = _fill_share(empties.size(), level)
	var take := _safe_fill_size(empties, want)
	if take <= 0:
		return false
	var filled: Array = empties.slice(0, take)
	var points := _settle_fill(filled, color_index)
	tsunami_swept.emit(filled, color_index, points)
	_resolve_lines()
	best = maxi(best, score)
	score_changed.emit(score, best, combo)
	queue_redraw()
	return true


## Rows plus columns that are currently complete.
## Everything about the board that belongs to the run, as plain data. Paired
## with restore() to let game.gd keep an undo history -- the board itself keeps
## no history, and knows nothing about who is holding these.
##
## `_grid` is an Array OF Arrays, so this is a DEEP copy: a shallow duplicate()
## shares the row arrays and the snapshot would silently track the live board,
## making a rewind look like it did nothing.
func snapshot() -> Dictionary:
	return {
		"grid": _grid.duplicate(true),
		"score": score,
		"combo": combo,
		"lines": lines,
	}


## Puts a snapshot back. `best` is deliberately NOT restored: it is the run's
## high-water mark, and an undo should not erase a score the player really
## reached. Animation state is dropped rather than restored -- it is transient
## and self-draining.
func restore(snap: Dictionary) -> void:
	_grid = (snap["grid"] as Array).duplicate(true)
	score = int(snap["score"])
	combo = int(snap["combo"])
	lines = int(snap["lines"])
	_pops.clear()
	_falls.clear()
	score_changed.emit(score, best, combo)
	queue_redraw()


func _count_full_lines() -> int:
	var n := 0
	for y in grid:
		var whole := true
		for x in grid:
			if _grid[y][x] == EMPTY:
				whole = false
				break
		if whole:
			n += 1
	for x in grid:
		var whole := true
		for y in grid:
			if _grid[y][x] == EMPTY:
				whole = false
				break
		if whole:
			n += 1
	return n


## What moving the block at `src` to the empty cell `dst` is worth. Completing
## a line dwarfs everything else; below that it is simply whether the block
## ends up in fuller company than it left. Measured after the move, so the hole
## the block leaves behind counts against it.
func _shift_gain(src: Vector2i, dst: Vector2i) -> int:
	var color: int = _grid[src.y][src.x]
	_grid[src.y][src.x] = EMPTY
	_grid[dst.y][dst.x] = color
	var gain: int = _count_full_lines() * 1000 \
		+ _fill_pressure(dst) - _fill_pressure(src)
	_grid[dst.y][dst.x] = EMPTY
	_grid[src.y][src.x] = color
	return gain


## Shakes the board: settled blocks hop one cell into whichever neighbour packs
## them tighter, over and over, and it stops as soon as a line completes. Only
## strictly improving moves are taken, which both keeps the shaking useful and
## guarantees it terminates instead of rocking one block back and forth.
func _earthquake(level := 1) -> bool:
	var budget: int = int(EARTHQUAKE_NUDGES_BY_LEVEL[_lvl(level)])
	var moved: Array = []

	for step in budget:
		var from := Vector2i(-1, -1)
		var to := Vector2i(-1, -1)
		# NOT named `best`: that is the member holding the high score, and a
		# local of the same name would silently swallow the update below.
		var best_gain := 0               # strictly positive, so ties do nothing
		for y in grid:
			for x in grid:
				if _grid[y][x] == EMPTY:
					continue
				var src := Vector2i(x, y)
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT,
						Vector2i.UP, Vector2i.DOWN]:
					var dst := src + d
					if dst.x < 0 or dst.x >= grid or dst.y < 0 or dst.y >= grid:
						continue
					if _grid[dst.y][dst.x] != EMPTY:
						continue
					var gain := _shift_gain(src, dst)
					if gain > best_gain:
						best_gain = gain
						from = src
						to = dst
		if best_gain <= 0:
			break                        # nothing left that helps

		_grid[to.y][to.x] = _grid[from.y][from.x]
		_grid[from.y][from.x] = EMPTY
		_pops.erase(from)
		_pops[to] = 0.0
		moved.append(to)
		if _count_full_lines() > 0:
			break                        # shook something loose; stop here

	if moved.is_empty():
		return false
	earthquake_shook.emit(moved, moved.size())
	_resolve_lines()
	best = maxi(best, score)
	score_changed.emit(score, best, combo)
	queue_redraw()
	return true


## How many rows and columns would be completed by dropping `cells` at
## `origin`. Used to choose between candidate teleport destinations.
func _lines_completed_by(cells: Array, origin: Vector2i) -> int:
	var filled := {}
	for c: Vector2i in cells:
		filled[origin + c] = true
	var count := 0
	for y in grid:
		var full := true
		for x in grid:
			if _grid[y][x] == EMPTY and not filled.has(Vector2i(x, y)):
				full = false
				break
		if full:
			count += 1
	for x in grid:
		var full := true
		for y in grid:
			if _grid[y][x] == EMPTY and not filled.has(Vector2i(x, y)):
				full = false
				break
		if full:
			count += 1
	return count


func _resolve_lines() -> void:
	var full_rows: Array = []
	var full_cols: Array = []

	for y in grid:
		var complete := true
		for x in grid:
			if _grid[y][x] == EMPTY:
				complete = false
				break
		if complete:
			full_rows.append(y)

	for x in grid:
		var complete := true
		for y in grid:
			if _grid[y][x] == EMPTY:
				complete = false
				break
		if complete:
			full_cols.append(x)

	if full_rows.is_empty() and full_cols.is_empty():
		combo = 0
		return

	# A cell sitting on both a full row and a full column must only count once.
	var doomed := {}
	for y: int in full_rows:
		for x in grid:
			doomed[Vector2i(x, y)] = true
	for x: int in full_cols:
		for y in grid:
			doomed[Vector2i(x, y)] = true

	combo = mini(combo + 1, MAX_COMBO)
	var line_count: int = full_rows.size() + full_cols.size()
	lines += line_count
	var points: int = LINE_BASE * line_count * line_count * combo
	score += points
	best = maxi(best, score)

	lines_cleared.emit(full_rows, full_cols, doomed.size(), points)

	for cell: Vector2i in doomed:
		_grid[cell.y][cell.x] = EMPTY
		_pops.erase(cell)


func _process(delta: float) -> void:
	if not _falls.is_empty():
		var landed: Array = []
		for cell: Vector2i in _falls:
			_falls[cell]["t"] += delta
			if _falls[cell]["t"] >= FALL_TIME:
				landed.append(cell)
		for cell: Vector2i in landed:
			_falls.erase(cell)
		queue_redraw()

	if _pops.is_empty():
		return
	var finished: Array = []
	for cell: Vector2i in _pops:
		_pops[cell] += delta
		if _pops[cell] >= POP_DURATION:
			finished.append(cell)
	for cell: Vector2i in finished:
		_pops.erase(cell)
	queue_redraw()


## True when at least one of `pieces` fits somewhere. Used to end the game.
func has_any_move(pieces: Array) -> bool:
	for piece: Dictionary in pieces:
		if piece.is_empty():
			continue
		var span: Vector2i = piece["size"]
		for y in range(grid - span.y + 1):
			for x in range(grid - span.x + 1):
				if can_place(piece["cells"], Vector2i(x, y)):
					return true
	return false


func declare_game_over() -> void:
	if not alive:
		return
	alive = false
	best = maxi(best, score)
	game_over.emit()


## Grid cell containing a point given in this control's local space.
func cell_at(local: Vector2) -> Vector2i:
	var c := cell_size()
	if c <= 0.0:
		return Vector2i.ZERO
	var p := local - grid_origin(c)
	return Vector2i(floori(p.x / c), floori(p.y / c))


# --- drawing -----------------------------------------------------------------

func _build_styles() -> void:
	_pixel = Themes.is_pixel()
	_grid_lines = Themes.grid_lines()
	_tile_tex = Themes.tile_texture()
	_socket_tex = Themes.socket_texture()
	_styles.clear()
	for color: Color in Themes.palette():
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.border_color = color.lightened(0.35)
		_styles.append(style)
	_empty_style.bg_color = Themes.value("socket", Color(1, 1, 1, 0.035))
	_ghost_ok.bg_color = Themes.value("ghost_ok", Color(1, 1, 1, 0.28))
	_ghost_bad.bg_color = Themes.value("ghost_bad", Color(0.98, 0.44, 0.52, 0.28))


func _sync_metrics(cell: float) -> void:
	if is_equal_approx(cell, _last_cell):
		return
	_last_cell = cell
	var radius := int(cell * 0.2)
	var border := maxi(1, int(cell * 0.06))
	for style in _styles:
		style.set_corner_radius_all(radius)
		style.set_border_width_all(border)
	for style in [_empty_style, _ghost_ok, _ghost_bad]:
		style.set_corner_radius_all(radius)


func cell_rect(x: int, y: int, cell: float) -> Rect2:
	# Pixel tiles butt up against each other: the sprite carries its own ink
	# outline and bevel, so an inset would just open gaps in the grid.
	var inset := 0.0 if _pixel else cell * 0.06
	return Rect2(
		Vector2(x * cell + inset, y * cell + inset) + grid_origin(cell) + shake_offset,
		Vector2(cell - inset * 2.0, cell - inset * 2.0))


func _draw() -> void:
	var cell := cell_size()
	if cell <= 0.0:
		return
	_sync_metrics(cell)

	# Both the panel and its frame hug the GRID, not this control. They are the
	# same size only when the cells divide the control exactly; on a 12-wide
	# board the cell snaps down to 64px and the grid is narrower, which would
	# otherwise leave dead board inside the frame.
	var extent := Vector2(cell * grid, cell * grid)
	var panel := Rect2(grid_origin(cell) + shake_offset, extent)

	# Nearly opaque on purpose: the combo shower drifts behind this panel, and
	# at a lower alpha the particles bleed through and look like they are on
	# top of the playfield.
	draw_rect(panel, Themes.value("board_bg", Color(0.043, 0.039, 0.098, 0.93)))

	# The design frames the playfield with an ink border sitting just outside
	# the grid (`box-shadow: 0 0 0 4px` at 2x, so 2 logical px -> 8 here).
	var frame: Variant = Themes.value("board_border", null)
	if frame != null:
		var w := 8.0
		draw_rect(panel.grow(w * 0.5), frame as Color, false, w)

	for y in grid:
		for x in grid:
			var value: int = _grid[y][x]
			if value == EMPTY:
				_draw_cell(cell_rect(x, y, cell), -1)
				continue
			var rect := cell_rect(x, y, cell)
			var key := Vector2i(x, y)
			if _falls.has(key):
				# Drawn above its final cell, easing down into place.
				var ft: float = clampf(float(_falls[key]["t"]) / FALL_TIME, 0.0, 1.0)
				var eased: float = 1.0 - pow(1.0 - ft, 3.0)
				var lift: float = float(_falls[key]["dist"]) * cell * (1.0 - eased)
				rect.position.y -= lift
			if _pops.has(key):
				# Springs from 55% up through a slight overshoot to full size.
				var t: float = clampf(float(_pops[key]) / POP_DURATION, 0.0, 1.0)
				var pop: float = Tween.interpolate_value(
					0.55, 0.45, t, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT)
				rect = Rect2(rect.position + rect.size * (1.0 - pop) * 0.5,
					rect.size * pop)
			_draw_cell(rect, value)

	if _grid_lines:
		_draw_grid(cell)

	for c: Vector2i in preview_cells:
		if c.x < 0 or c.x >= grid or c.y < 0 or c.y >= grid:
			continue
		_draw_ghost(cell_rect(c.x, c.y, cell), preview_valid)


## Separators on the internal cell boundaries. Optional -- the settings screen
## exposes it, since the sockets already imply the grid and some players find
## the extra lines noisy.
func _draw_grid(cell: float) -> void:
	var ink: Color = Themes.value("board_border", Themes.value("socket", Color.WHITE))
	var line := Color(ink, 0.28 if _pixel else 0.10)
	var w := 4.0 if _pixel else 2.0
	var o := grid_origin(cell) + shake_offset
	for i in range(1, grid):
		var x := o.x + i * cell
		draw_line(Vector2(x, o.y), Vector2(x, o.y + cell * grid), line, w)
		var y := o.y + i * cell
		draw_line(Vector2(o.x, y), Vector2(o.x + cell * grid, y), line, w)


## One cell. `value` is a palette index, or -1 for an empty socket.
func _draw_cell(rect: Rect2, value: int) -> void:
	if _pixel:
		var tex := _socket_tex if value < 0 else _tile_tex
		if tex != null:
			var tint: Color = _empty_style.bg_color if value < 0 \
				else Themes.palette()[value]
			draw_texture_rect(tex, rect, false, tint)
			return
	draw_style_box(_empty_style if value < 0 else _styles[value], rect)


func _draw_ghost(rect: Rect2, ok: bool) -> void:
	var fill: Color = _ghost_ok.bg_color if ok else _ghost_bad.bg_color
	if _pixel:
		# Flat fill plus a hard 3px inset border, per the design's GHOST_OK.
		draw_rect(rect, fill)
		draw_rect(rect, Color(fill, minf(1.0, fill.a * 3.0)), false, 12.0)
		return
	draw_style_box(_ghost_ok if ok else _ghost_bad, rect)
