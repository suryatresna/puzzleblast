extends Node
## App preview clip: a scripted run that builds a combo, then spends it.
##
## Run (frames land in the directory given as the second argument):
##   "$GODOT" --path . res://tools/clip.tscn \
##       --write-movie /tmp/discard/f.png --fixed-fps 30 --disable-vsync \
##       -- 886x1920 /tmp/clip
##
## Same SubViewport trick as tools/shots.gd, and for the same reason: macOS
## clamps a window to the screen, so the only way to lay the game out portrait
## at a device size is to render it into a viewport of that size. See
## docs/testing.md. `--write-movie` is passed to force a deterministic render
## loop; its own frames are discarded, but its WAV is the clip's soundtrack.
##
## Apple wants 886x1920 for every iPhone preview slot, 15-30s, 30fps.

const DESIGN := Vector2i(1080, 1920)
const FPS := 30

var _size := Vector2i(886, 1920)
var _out := "/tmp/clip"
var _sv: SubViewport
var _scene: Control = null
var _board = null
var _frame := 0
var _recording := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var p: PackedStringArray = String(args[0]).split("x")
		if p.size() == 2:
			_size = Vector2i(int(p[0]), int(p[1]))
	if args.size() > 1:
		_out = String(args[1])
	DirAccess.make_dir_recursive_absolute(_out)

	var scale: float = minf(float(_size.x) / DESIGN.x, float(_size.y) / DESIGN.y)
	var design := Vector2i(DESIGN.x, int(round(_size.y / scale)))
	_sv = SubViewport.new()
	_sv.size = _size
	_sv.size_2d_override = design
	_sv.size_2d_override_stretch = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	print("clip %dx%d  design %dx%d  -> %s" % [_size.x, _size.y, design.x, design.y, _out])

	await _run()
	print("DONE %d frames (%.1fs)" % [_frame, float(_frame) / FPS])
	get_tree().quit(0)


## Hold for `seconds`, saving one frame per engine tick while recording.
##
## The grab is done HERE rather than from a frame_post_draw handler. Reading
## the viewport texture inside that handler makes it miss emissions -- a first
## pass captured 171 frames where Movie Maker, running alongside, wrote 582.
## Awaiting the signal and grabbing after it resumes is exactly one save per
## drawn frame, and the count then matches the script rather than the machine.
func _hold(seconds: float) -> void:
	for i in int(round(seconds * FPS)):
		if _scene and _scene.has_node("%PausePanel"):
			_scene.get_node("%PausePanel").hide()
		await RenderingServer.frame_post_draw
		if _recording:
			var img: Image = _sv.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.save_png("%s/f%05d.png" % [_out, _frame])
			_frame += 1


func _seed() -> void:
	Progress.wipe()
	Progress.add_score(Progress.threshold(50))
	for p: int in Blocks.ALL_POWERS:
		if not Progress._unlocked.has(p):
			Progress._unlocked.append(p)
	Progress.equip(0, Blocks.Power.LASER)
	Progress.equip(1, Blocks.Power.BLACKHOLE)
	Progress.equip(2, Blocks.Power.BOMB)
	Progress.use_tutorial_power()
	Progress._pending_unlocks = 0
	for row: Dictionary in Coach.LADDER:
		Progress.mark_hint_seen(int(row["id"]))
	# Laser at 3, but blackhole and bomb MAXED. The step is the whole point of
	# showing them: blackhole goes from radius 2.5 to 4.0, roughly 21 cells to
	# 49, and the bomb from "5x5 and the row" to "7x7, the row AND half the
	# board". A level 3 cast reads as a tidy hole; a level 5 one clears the
	# screen, which is what a preview is for.
	Progress._uses[Blocks.Power.LASER] = Progress.USES_FOR_LEVEL[2]
	for p: int in [Blocks.Power.BLACKHOLE, Blocks.Power.BOMB]:
		Progress._uses[p] = Progress.USES_FOR_LEVEL[Progress.USES_FOR_LEVEL.size() - 1]
	Progress._charge = 0


## Loose blocks low on the board, so it reads as a run in progress rather than
## a contrived setup. Never leaves a full line.
func _scatter(density: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	# reset() zeroes the score along with the grid, so a mid-clip re-scatter
	# sent the HUD back to 0 and the run looked like it had restarted. Carry
	# the running total across, and snap the counter so it does not roll.
	var keep_score: int = _board.score
	var keep_best: int = _board.best
	_board.reset()
	_board.score = keep_score
	_board.best = keep_best
	for y in _board.grid:
		var depth: float = float(y) / float(_board.grid - 1)
		for x in _board.grid:
			if rng.randf() < density * (0.25 + depth):
				_board._grid[y][x] = rng.randi_range(0, 7)
	for y in _board.grid:
		_board._grid[y][rng.randi_range(0, _board.grid - 1)] = _board.EMPTY
	for x in _board.grid:
		_board._grid[rng.randi_range(0, _board.grid - 1)][x] = _board.EMPTY
	_board.queue_redraw()
	_board.score_changed.emit(_board.score, _board.best, _board.combo)
	if _scene.has_node("%ScoreValue"):
		_scene.get_node("%ScoreValue").reset_to(_board.score)


## Fills `rows` except one column, so a bar dropped there completes them all
## at once -- a real clear through the real placement path, not a fake.
func _prime(rows: Array, gap: int) -> void:
	for y: int in rows:
		for x in _board.grid:
			_board._grid[y][x] = (x * 3 + y) % 8
		_board._grid[y][gap] = _board.EMPTY
	_board.queue_redraw()


func _drop_bar(rows: Array, gap: int) -> void:
	var cells: Array = []
	for i in rows.size():
		cells.append(Vector2i(0, i))
	var piece := {"cells": cells, "size": Vector2i(1, rows.size()),
		"color": 4 + (rows.size() % 4)}
	_scene._tray[0] = piece
	_scene._sync_tray()
	await _hold(0.25)
	_scene._start_drag(_scene.DragFrom.TRAY, 0, piece, Vector2.ZERO)
	_scene._drag_origin = Vector2i(gap, rows.min())
	_scene._end_drag(Vector2.ZERO)


func _cast(slot: int, at: Vector2i) -> void:
	var power: int = Progress.equipped(slot)
	Progress._charge = Progress.max_charge()
	_scene._sync_powers()
	await _hold(0.2)
	_scene._start_drag(_scene.DragFrom.POWER, slot, Blocks.power_piece(power), Vector2.ZERO)
	_scene._drag_origin = at
	_scene._end_drag(Vector2.ZERO)


func _run() -> void:
	_seed()
	Modes.set_current(Modes.Id.PALETTE)
	var s: Control = load(App.SCENE_GAME).instantiate()
	_sv.add_child(s)
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ui: Theme = Themes.ui_theme()
	if ui:
		s.theme = ui
	_scene = s
	await _hold(0.3)
	_board = s._board
	_scatter(0.30)
	_board.score = 0
	_board.best = 48120
	_scene._best_at_start = 48120
	_board.score_changed.emit(0, 48120, 0)
	_scene._sync_tray()
	_scene._sync_powers()
	await _hold(0.5)

	_recording = true
	var mid: int = _board.grid / 2

	# --- the combo ladder: one line, then two, then two again -------------
	await _hold(0.9)
	_prime([_board.grid - 1], 4)
	await _drop_bar([_board.grid - 1], 4)
	await _hold(1.5)

	_prime([_board.grid - 2, _board.grid - 3], 7)
	await _drop_bar([_board.grid - 2, _board.grid - 3], 7)
	await _hold(1.8)

	_prime([_board.grid - 4, _board.grid - 5], 2)
	await _drop_bar([_board.grid - 4, _board.grid - 5], 2)
	await _hold(2.0)

	# --- and what the combo bought ----------------------------------------
	_scatter(0.42)
	await _hold(0.6)
	await _cast(0, Vector2i(mid + 1, mid))          # LASER
	await _hold(2.4)

	# Packed tighter for the two maxed casts: a wide blast over a sparse board
	# destroys nothing much and reads as a small one.
	_scatter(0.66)
	await _hold(0.6)
	await _cast(1, Vector2i(mid, mid))              # BLACKHOLE, level 5
	await _hold(3.0)

	_scatter(0.72)
	await _hold(0.6)
	await _cast(2, Vector2i(mid, mid + 1))          # BOMB, level 5
	await _hold(3.2)

	await _hold(1.2)
	_recording = false
