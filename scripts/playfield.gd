extends Control
## The Tetris playfield: grid state, the active piece, gravity, line clears
## and all the drawing.
##
## Presentation lives elsewhere -- game.gd listens to the signals below and
## turns them into particles, shake and HUD updates. The playfield never
## reaches out to those; it only reports what happened.

const Tetromino := preload("res://scripts/tetromino.gd")

signal score_changed(score: int, lines: int, level: int)
signal next_piece_changed(type: int)
## Emitted the instant rows are found full, before they are removed, so the
## effects layer can explode them while they are still on screen.
signal rows_clearing(rows: Array, line_count: int, points: int)
signal piece_locked(cells: Array, type: int)
signal game_over()

const COLS := 10
const VISIBLE_ROWS := 20
## Two hidden rows above the well give pieces somewhere legal to spawn.
const BUFFER_ROWS := 2
const TOTAL_ROWS := VISIBLE_ROWS + BUFFER_ROWS

const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const CLEAR_ANIM := 0.42
const EMPTY := -1

## Points per simultaneous line count, multiplied by level.
const LINE_SCORES := [0, 100, 300, 500, 800]

enum State { READY, PLAYING, CLEARING, PAUSED, OVER }

var state: State = State.READY
var score := 0
var lines := 0
var level := 1

## Drawing offset used for screen shake, in pixels.
var shake_offset := Vector2.ZERO:
	set(value):
		shake_offset = value
		queue_redraw()

var _grid: Array = []
var _type := 0
var _rot := 0
var _pos := Vector2i.ZERO
var _next := 0
var _bag: Array = []

var _fall_accum := 0.0
var _lock_accum := 0.0
var _lock_resets := 0
var _grounded := false

var _clear_rows: Array = []
var _clear_accum := 0.0

var _styles: Array[StyleBoxFlat] = []
var _ghost_style: StyleBoxFlat
var _last_cell := 0.0


func _ready() -> void:
	_build_styles()
	resized.connect(_on_resized)
	reset()


func reset() -> void:
	_grid.clear()
	for y in TOTAL_ROWS:
		var row := []
		row.resize(COLS)
		row.fill(EMPTY)
		_grid.append(row)

	score = 0
	lines = 0
	level = 1
	_bag.clear()
	_clear_rows.clear()
	_fall_accum = 0.0
	_next = _pull_from_bag()
	state = State.PLAYING
	_spawn()
	score_changed.emit(score, lines, level)
	queue_redraw()


# --- piece flow -------------------------------------------------------------

func _pull_from_bag() -> int:
	# 7-bag: every piece appears once before any repeats.
	if _bag.is_empty():
		_bag = range(Tetromino.COUNT)
		_bag.shuffle()
	return _bag.pop_back()


func _spawn() -> void:
	_type = _next
	_next = _pull_from_bag()
	_rot = 0
	# Centre horizontally, and drop the piece just far enough that its topmost
	# mino sits on the first visible row -- spawning inside the buffer would
	# leave the active piece invisible until gravity pulled it into view.
	var width := 4 if _type == Tetromino.I else (2 if _type == Tetromino.O else 3)
	var min_y := 99
	for c: Vector2i in Tetromino.cells(_type, 0):
		min_y = mini(min_y, c.y)
	_pos = Vector2i((COLS - width) / 2, BUFFER_ROWS - min_y)
	_grounded = false
	_lock_accum = 0.0
	_lock_resets = 0
	next_piece_changed.emit(_next)

	if not _can_place(_type, _rot, _pos):
		state = State.OVER
		game_over.emit()
	queue_redraw()


func _can_place(type: int, rot: int, pos: Vector2i) -> bool:
	for cell: Vector2i in Tetromino.cells(type, rot):
		var x := pos.x + cell.x
		var y := pos.y + cell.y
		if x < 0 or x >= COLS or y < 0 or y >= TOTAL_ROWS:
			return false
		if _grid[y][x] != EMPTY:
			return false
	return true


func move(dx: int, dy: int) -> bool:
	if state != State.PLAYING:
		return false
	var target := _pos + Vector2i(dx, dy)
	if not _can_place(_type, _rot, target):
		return false
	_pos = target
	_on_piece_moved()
	queue_redraw()
	return true


func rotate_piece(dir: int) -> bool:
	if state != State.PLAYING:
		return false
	var to_rot := (_rot + dir) & 3
	for kick in Tetromino.kicks(_type, _rot, to_rot):
		if _can_place(_type, to_rot, _pos + kick):
			_rot = to_rot
			_pos += kick
			_on_piece_moved()
			queue_redraw()
			return true
	return false


## Resets lock delay so players can slide a piece along the floor, but only a
## bounded number of times -- otherwise a piece could be stalled forever.
func _on_piece_moved() -> void:
	if _grounded and _lock_resets < MAX_LOCK_RESETS:
		_lock_accum = 0.0
		_lock_resets += 1


func soft_drop() -> void:
	if move(0, 1):
		score += 1
		score_changed.emit(score, lines, level)


func hard_drop() -> void:
	if state != State.PLAYING:
		return
	var dropped := 0
	while _can_place(_type, _rot, _pos + Vector2i(0, 1)):
		_pos.y += 1
		dropped += 1
	score += dropped * 2
	score_changed.emit(score, lines, level)
	_lock()


func ghost_position() -> Vector2i:
	var ghost := _pos
	while _can_place(_type, _rot, ghost + Vector2i(0, 1)):
		ghost.y += 1
	return ghost


# --- locking and clearing ---------------------------------------------------

func _lock() -> void:
	var locked: Array = []
	for cell: Vector2i in Tetromino.cells(_type, _rot):
		var p := _pos + cell
		_grid[p.y][p.x] = _type
		locked.append(p)
	piece_locked.emit(locked, _type)

	var full := _full_rows()
	if full.is_empty():
		_spawn()
		return

	var count: int = full.size()
	var points: int = LINE_SCORES[mini(count, 4)] * level
	score += points
	lines += count
	var new_level := 1 + lines / 10
	if new_level != level:
		level = new_level
	score_changed.emit(score, lines, level)

	_clear_rows = full
	_clear_accum = 0.0
	state = State.CLEARING
	rows_clearing.emit(full.duplicate(), count, points)
	queue_redraw()


func _full_rows() -> Array:
	var full: Array = []
	for y in TOTAL_ROWS:
		var complete := true
		for x in COLS:
			if _grid[y][x] == EMPTY:
				complete = false
				break
		if complete:
			full.append(y)
	return full


func _collapse_rows() -> void:
	# Walk bottom-up, copying surviving rows down over the cleared ones.
	var write := TOTAL_ROWS - 1
	for read in range(TOTAL_ROWS - 1, -1, -1):
		if read in _clear_rows:
			continue
		if write != read:
			_grid[write] = _grid[read]
		write -= 1
	while write >= 0:
		var row := []
		row.resize(COLS)
		row.fill(EMPTY)
		_grid[write] = row
		write -= 1
	_clear_rows.clear()


# --- tick -------------------------------------------------------------------

func _gravity_interval() -> float:
	# Tetris Worlds curve: ~0.8s per cell at level 1, accelerating each level.
	return maxf(0.03, pow(0.8 - (level - 1) * 0.007, level - 1))


func _process(delta: float) -> void:
	match state:
		State.CLEARING:
			_clear_accum += delta
			queue_redraw()
			if _clear_accum >= CLEAR_ANIM:
				_collapse_rows()
				state = State.PLAYING
				_spawn()
		State.PLAYING:
			_fall_accum += delta
			if _fall_accum >= _gravity_interval():
				_fall_accum = 0.0
				if not move(0, 1):
					_grounded = true
			_grounded = not _can_place(_type, _rot, _pos + Vector2i(0, 1))
			if _grounded:
				_lock_accum += delta
				if _lock_accum >= LOCK_DELAY:
					_lock()
			else:
				_lock_accum = 0.0
		_:
			pass


# --- drawing ----------------------------------------------------------------

func _build_styles() -> void:
	_styles.clear()
	for color in Tetromino.COLORS:
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.border_color = color.lightened(0.35)
		_styles.append(style)
	_ghost_style = StyleBoxFlat.new()
	_ghost_style.bg_color = Color(1, 1, 1, 0.06)
	_ghost_style.border_color = Color(1, 1, 1, 0.32)


func _on_resized() -> void:
	queue_redraw()


func cell_size() -> float:
	return size.x / float(COLS)


func _sync_style_metrics(cell: float) -> void:
	if is_equal_approx(cell, _last_cell):
		return
	_last_cell = cell
	var radius := int(cell * 0.18)
	var border := maxi(1, int(cell * 0.06))
	for style in _styles:
		style.set_corner_radius_all(radius)
		style.set_border_width_all(border)
	_ghost_style.set_corner_radius_all(radius)
	_ghost_style.set_border_width_all(border)


func _cell_rect(x: int, y: int, cell: float) -> Rect2:
	var inset := cell * 0.06
	return Rect2(
		Vector2(x * cell + inset, (y - BUFFER_ROWS) * cell + inset) + shake_offset,
		Vector2(cell - inset * 2.0, cell - inset * 2.0))


func _draw() -> void:
	var cell := cell_size()
	if cell <= 0.0:
		return
	_sync_style_metrics(cell)

	# Well background and grid.
	var well := Rect2(shake_offset, size)
	draw_rect(well, Color(0.035, 0.031, 0.086, 0.72))
	var line_color := Color(1, 1, 1, 0.045)
	for x in range(1, COLS):
		draw_line(Vector2(x * cell, 0) + shake_offset,
			Vector2(x * cell, size.y) + shake_offset, line_color, 1.0)
	for y in range(1, VISIBLE_ROWS):
		draw_line(Vector2(0, y * cell) + shake_offset,
			Vector2(size.x, y * cell) + shake_offset, line_color, 1.0)

	# Settled blocks. Rows being cleared flash white and shrink away.
	var clear_t: float = clampf(_clear_accum / CLEAR_ANIM, 0.0, 1.0) if state == State.CLEARING else 0.0
	for y in range(BUFFER_ROWS, TOTAL_ROWS):
		var clearing: bool = y in _clear_rows
		for x in COLS:
			var value: int = _grid[y][x]
			if value == EMPTY:
				continue
			var rect := _cell_rect(x, y, cell)
			if clearing:
				# Shrink toward the row centre while flashing to white.
				var shrink := 1.0 - clear_t
				rect = Rect2(
					rect.position + rect.size * (1.0 - shrink) * 0.5,
					rect.size * shrink)
				var flash: Color = Tetromino.COLORS[value].lerp(Color.WHITE, clear_t)
				draw_rect(rect, Color(flash.r, flash.g, flash.b, 1.0 - clear_t * 0.35))
			else:
				draw_style_box(_styles[value], rect)

	if state != State.PLAYING:
		return

	# Ghost, then the live piece on top of it.
	var ghost := ghost_position()
	if ghost != _pos:
		for c: Vector2i in Tetromino.cells(_type, _rot):
			draw_style_box(_ghost_style, _cell_rect(ghost.x + c.x, ghost.y + c.y, cell))
	for c: Vector2i in Tetromino.cells(_type, _rot):
		var p := _pos + c
		if p.y >= BUFFER_ROWS:
			draw_style_box(_styles[_type], _cell_rect(p.x, p.y, cell))
