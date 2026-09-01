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
signal laser_fired(at: Vector2i, cleared: int, points: int)
signal diagonal_fired(at: Vector2i, cleared: int, points: int)
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
		power := Blocks.Power.NONE) -> bool:
	if not alive or not can_place(cells, origin):
		return false

	if power != Blocks.Power.NONE:
		_fire_power(power, origin, color_index)
		return true

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


func _fire_power(power: Blocks.Power, at: Vector2i, color_index: int) -> void:
	match power:
		Blocks.Power.BOMB: _detonate(at)
		Blocks.Power.LASER: _laser(at)
		Blocks.Power.MORPH: _morph(at, color_index)
		Blocks.Power.FIT: _fit(at, color_index)
		Blocks.Power.DIAGONAL: _diagonal(at)


## Burns out the whole row and column the laser lands on.
func _laser(at: Vector2i) -> void:
	var doomed := {}
	for x in grid:
		doomed[Vector2i(x, at.y)] = true
	for y in grid:
		doomed[Vector2i(at.x, y)] = true

	var cleared := 0
	for cell: Vector2i in doomed:
		if _grid[cell.y][cell.x] != EMPTY:
			cleared += 1
		_grid[cell.y][cell.x] = EMPTY
		_pops.erase(cell)

	var points := cleared * LASER_POINTS_PER_CELL
	score += points
	best = maxi(best, score)
	laser_fired.emit(at, cleared, points)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Clears both diagonals through the placed cell -- the one shape the laser
## cannot make. Unlike a row and column, the two diagonals through a point vary
## in length with where it sits, so a corner strike is weak and a centre strike
## is strong. That is the trade the player is making.
func _diagonal(at: Vector2i) -> void:
	var doomed := {}
	for i in range(-grid, grid):
		for cell: Vector2i in [Vector2i(at.x + i, at.y + i),
				Vector2i(at.x + i, at.y - i)]:
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
	diagonal_fired.emit(at, cleared, points)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Drops every settled block to the bottom of its column, closing the gaps a
## run leaves behind. Rows completed by the collapse then clear and score, so a
## well-timed morph can cash in a board that looked wasted.
func _morph(at: Vector2i, color_index: int) -> void:
	_grid[at.y][at.x] = color_index          # the piece itself falls too
	_pops[at] = 0.0

	var dropped := 0
	for x in grid:
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

	board_morphed.emit(dropped)
	_resolve_lines()
	best = maxi(best, score)
	score_changed.emit(score, best, combo)
	queue_redraw()


## Grows to fill the pocket of empty cells it was dropped into, up to
## FIT_MAX_CELLS. Breadth-first from the drop point, so it spreads evenly
## rather than snaking off in one direction.
func _fit(at: Vector2i, color_index: int) -> void:
	var filled: Array = []
	var seen := {at: true}
	var queue: Array = [at]

	while not queue.is_empty() and filled.size() < FIT_MAX_CELLS:
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
func _detonate(at: Vector2i) -> void:
	@warning_ignore("integer_division")
	var half := grid / 2
	var from_row: int = 0 if at.y < half else half
	var to_row: int = from_row + half - 1

	var cleared := 0
	for y in range(from_row, to_row + 1):
		for x in grid:
			if _grid[y][x] != EMPTY:
				cleared += 1
				_grid[y][x] = EMPTY
				_pops.erase(Vector2i(x, y))

	var points := cleared * BOMB_POINTS_PER_CELL
	score += points
	best = maxi(best, score)
	# A bomb neither builds nor breaks a line-clear streak.
	bomb_detonated.emit(at, from_row, to_row, cleared, points)
	score_changed.emit(score, best, combo)
	queue_redraw()


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
