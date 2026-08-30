extends Control
## Drag-and-drop block puzzle.
##
## Five cards sit in a tray at the bottom. Drag one onto the 8x8 board; filling
## any row or column clears it with a boom. The tray refills once all five are
## spent, and the run ends when nothing left in the tray fits anywhere.

const Blocks := preload("res://scripts/blocks.gd")

const TRAY_SIZE := 5

## How far above the pointer the piece is drawn, in board cells. Without this
## the player's own finger covers the thing they are trying to place.
const DRAG_LIFT_CELLS := 1.4
const SHAKE_DECAY := 7.0

## Dealing a fresh hand: a beat to register the tray emptying, then each card
## pops in a little after the one before it.
const DEAL_DELAY := 0.12
const DEAL_STAGGER := 0.07
const DEAL_TIME := 0.34

## Clearing lines on this many placements in a row earns a bomb. Awarded once
## per streak, so a 5x run hands out one bomb rather than four.
const COMBO_BOMB_THRESHOLD := 2

@onready var _board: Control = %Board
@onready var _effects: Node2D = %Effects
@onready var _drag_view: Control = %DragView
@onready var _overlay: Node2D = %OverlayEffects

var _tray: Array = []          # TRAY_SIZE entries; {} means spent
var _slots: Array[Control] = []
var _drag_index := -1
var _drag_origin := Vector2i.ZERO
var _shake := 0.0
## Best score when this run started, and whether it has been passed yet, so the
## celebration fires exactly once per run.
var _best_at_start := 0
var _beat_best := false
var _deal_tweens: Array = []
var _combo_bomb_given := false


func _ready() -> void:
	_slots = [%Slot0, %Slot1, %Slot2, %Slot3, %Slot4]

	_board.score_changed.connect(_on_score_changed)
	_board.piece_placed.connect(_on_piece_placed)
	_board.bomb_detonated.connect(_on_bomb_detonated)
	_board.lines_cleared.connect(_on_lines_cleared)
	_board.game_over.connect(_on_game_over)

	%PauseButton.pressed.connect(_toggle_pause)
	%ResumeButton.pressed.connect(_toggle_pause)
	%RestartButton.pressed.connect(_restart)
	%QuitButton.pressed.connect(_leave)
	%RetryButton.pressed.connect(_restart)
	%ScoresButton.pressed.connect(App.goto_scene.bind(App.SCENE_LEADERBOARD))
	%MenuButton.pressed.connect(_leave)

	%PausePanel.hide()
	%GameOverPanel.hide()
	_drag_view.hide()

	_restart()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - SHAKE_DECAY * delta * maxf(_shake, 1.0))
		var offset := Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
		_board.shake_offset = offset
		_effects.position = offset
	elif _board.shake_offset != Vector2.ZERO:
		_board.shake_offset = Vector2.ZERO
		_effects.position = Vector2.ZERO


# --- tray --------------------------------------------------------------------

func _refill_tray() -> void:
	_tray.clear()
	for i in TRAY_SIZE:
		_tray.append(Blocks.random_piece())
	# One roll per hand, so a tray holds at most a single bomb.
	if randf() < Blocks.BOMB_TRAY_CHANCE:
		_tray[randi() % TRAY_SIZE] = Blocks.bomb_piece()
	_sync_tray()
	_deal_animation()


## Pops the new hand in one card at a time. Deliberately presentation only --
## `_tray` is already filled by the time this starts, so the caller's
## "any moves left?" check never sees a half-dealt tray.
func _deal_animation() -> void:
	_kill_deal_tweens()
	# The slots have no size until the container has laid them out, which has
	# not happened yet on the very first hand.
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return

	for i in TRAY_SIZE:
		var view: Control = _slots[i].get_node("View")
		if _tray[i].is_empty() or view.size == Vector2.ZERO:
			view.scale = Vector2.ONE
			view.rotation = 0.0
			view.modulate.a = 1.0
			continue

		_deal_tweens.append(_pop_in(view, DEAL_DELAY + i * DEAL_STAGGER))


## Springs one card up from nothing. Shared by the hand deal and by a bomb
## dropped into the tray as a combo reward.
func _pop_in(view: Control, delay: float) -> Tween:
	view.pivot_offset = view.size * 0.5
	view.scale = Vector2(0.3, 0.3)
	view.rotation = -0.18
	view.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(view, "scale", Vector2.ONE, DEAL_TIME) \
		.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(view, "rotation", 0.0, DEAL_TIME) \
		.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(view, "modulate:a", 1.0, DEAL_TIME * 0.6).set_delay(delay)
	return tween


func _tray_has_bomb() -> bool:
	for piece: Dictionary in _tray:
		if Blocks.is_bomb(piece):
			return true
	return false


## Hands the player a bomb for stringing clears together. Skipped when the tray
## already holds one, which keeps the "at most one bomb in hand" rule intact.
func _maybe_grant_combo_bomb() -> void:
	if _combo_bomb_given or _board.combo < COMBO_BOMB_THRESHOLD:
		return
	_combo_bomb_given = true
	if _tray_has_bomb():
		return

	# Prefer a slot the player has already emptied; only displace a live card
	# if the hand happens to be full.
	var empty_slots: Array = []
	for i in TRAY_SIZE:
		if _tray[i].is_empty():
			empty_slots.append(i)
	var slot: int = empty_slots.pick_random() if not empty_slots.is_empty() \
		else randi() % TRAY_SIZE

	_tray[slot] = Blocks.bomb_piece()
	_sync_tray()
	_pop_in(_slots[slot].get_node("View"), 0.0)

	var at: Vector2 = _slots[slot].get_global_rect().get_center() - Vector2(0.0, 150.0)
	_overlay.popup("BOMB!", at, Blocks.COLORS[Blocks.BOMB_COLOR], false)


## A restart mid-deal would otherwise leave cards stuck part-way in.
func _kill_deal_tweens() -> void:
	for tween in _deal_tweens:
		if tween is Tween and tween.is_valid():
			tween.kill()
	_deal_tweens.clear()


func _sync_tray() -> void:
	for i in TRAY_SIZE:
		var view: Control = _slots[i].get_node("View")
		# The card being dragged is drawn under the pointer, so its slot shows
		# empty rather than a duplicate sitting in the tray.
		var piece: Dictionary = {} if i == _drag_index else _tray[i]
		view.piece = piece
		# Grey out anything that no longer fits anywhere, so the player can see
		# why the run is about to end.
		view.dimmed = not piece.is_empty() and not _board.has_any_move([piece])


func _tray_spent() -> bool:
	for piece: Dictionary in _tray:
		if not piece.is_empty():
			return false
	return true


func _remaining_pieces() -> Array:
	var out: Array = []
	for piece: Dictionary in _tray:
		if not piece.is_empty():
			out.append(piece)
	return out


# --- input -------------------------------------------------------------------

## Pointer handling sits in _input rather than _unhandled_input because the
## drag spans the tray and the board, and must not depend on which Control
## happens to sit under the pointer. Buttons still work: a press only starts a
## drag when it lands inside a tray slot.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		if %GameOverPanel.visible: _leave()
		else: _toggle_pause()
		return

	if not _board.alive or %PausePanel.visible or %GameOverPanel.visible:
		return

	# Touch is emulated as mouse by default, so handling mouse covers both.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_end_drag(event.position)
	elif event is InputEventMouseMotion and _drag_index >= 0:
		_update_drag(event.position)


func _begin_drag(pointer: Vector2) -> void:
	for i in TRAY_SIZE:
		if _tray[i].is_empty():
			continue
		if _slots[i].get_global_rect().has_point(pointer):
			_drag_index = i
			_drag_view.piece = _tray[i]
			_drag_view.fixed_cell = _board.cell_size()
			_drag_view.size = _drag_view.piece_pixel_size()
			_drag_view.show()
			_sync_tray()
			_update_drag(pointer)
			return


func _update_drag(pointer: Vector2) -> void:
	if _drag_index < 0:
		return
	var cell: float = _board.cell_size()
	var piece_px: Vector2 = _drag_view.piece_pixel_size()

	# The piece is centred on a point lifted above the finger.
	var focus := pointer - Vector2(0.0, DRAG_LIFT_CELLS * cell)
	var top_left := focus - piece_px * 0.5
	_drag_view.position = top_left

	var local := top_left - _board.global_position
	_drag_origin = Vector2i(roundi(local.x / cell), roundi(local.y / cell))

	var cells: Array = _drag_view.piece["cells"]
	_board.preview_valid = _board.can_place(cells, _drag_origin)
	var ghost: Array = []
	for c: Vector2i in cells:
		ghost.append(_drag_origin + c)
	_board.preview_cells = ghost
	_board.queue_redraw()


func _end_drag(_pointer: Vector2) -> void:
	if _drag_index < 0:
		return
	var index := _drag_index
	var piece: Dictionary = _tray[index]
	_drag_index = -1
	_drag_view.hide()
	_board.preview_cells = []
	_board.queue_redraw()

	# _begin_drag only ever picks a filled slot, but bail rather than index into
	# an empty dictionary if that invariant is ever broken.
	if piece.is_empty():
		_sync_tray()
		return

	if not _board.can_place(piece["cells"], _drag_origin):
		_sync_tray()          # illegal drop puts the card back in its slot
		return

	_board.place(piece["cells"], _drag_origin, piece["color"], Blocks.is_bomb(piece))
	_tray[index] = {}

	if _tray_spent():
		_refill_tray()
	else:
		_sync_tray()

	_maybe_grant_combo_bomb()

	if not _board.has_any_move(_remaining_pieces()):
		_board.declare_game_over()


# --- board reactions ---------------------------------------------------------

func _on_score_changed(score: int, best: int, combo: int) -> void:
	%ScoreValue.text = str(score)
	%BestValue.text = str(best)
	%ComboValue.text = "x%d" % maxi(combo, 1)
	if combo == 0:
		_combo_bomb_given = false

	# Overtaking the previous best is worth celebrating the moment it happens,
	# not just on the game over screen. Skipped on a first-ever run, where
	# there is no record to beat.
	if not _beat_best and _best_at_start > 0 and score > _best_at_start:
		_beat_best = true
		_celebrate_best()


func _celebrate_best() -> void:
	var area: Vector2 = get_viewport_rect().size
	_overlay.celebrate(area)
	_overlay.popup("NEW BEST!", area * Vector2(0.5, 0.34), Color(1, 0.83, 0.32), true)


## Every landing gets a small puff so placing a piece feels like it connects.
func _on_piece_placed(cells: Array, color_index: int) -> void:
	_effects.place_puff(cells, _board.cell_size(), Blocks.COLORS[color_index])
	_shake = maxf(_shake, 2.5)


func _on_lines_cleared(rows: Array, cols: Array, _cell_count: int, points: int) -> void:
	var cell: float = _board.cell_size()
	var extent: float = _board.size.x
	var line_count: int = rows.size() + cols.size()
	var color: Color = Blocks.COLORS[0] if line_count < 3 else Blocks.COLORS[3]

	_effects.explode_lines(rows, cols, extent, cell, color)
	var mid := Vector2(extent * 0.5, extent * 0.5)
	_effects.popup(_effects.clear_label(line_count), mid, color, line_count >= 3)
	_effects.popup("+%d" % points, mid + Vector2(0.0, cell * 1.5),
		Color(0.945, 0.941, 1), false)

	_shake = 8.0 + line_count * 6.0
	# Clearing can free space, so previously dead cards may be playable again.
	_sync_tray()


## Every finished run goes on the leaderboard, whether or not it placed.
func _on_bomb_detonated(at: Vector2i, from_row: int, to_row: int,
		cleared: int, points: int) -> void:
	var cell: float = _board.cell_size()
	var region := Rect2(0.0, from_row * cell, _board.size.x, (to_row - from_row + 1) * cell)
	var centre := (Vector2(at) + Vector2(0.5, 0.5)) * cell
	var fire := Color(1, 0.55, 0.2)

	_effects.explode_bomb(centre, region, cell)
	_effects.popup("BOOM!", region.get_center(), fire, true)
	if points > 0:
		_effects.popup("+%d" % points, region.get_center() + Vector2(0.0, cell * 1.5),
			Color(0.945, 0.941, 1), false)
	print_verbose("bomb cleared %d cells for %d points" % [cleared, points])

	_shake = 26.0
	# Half the board just opened up, so dead cards may be playable again.
	_sync_tray()


func _on_game_over() -> void:
	var rank: int = Scores.submit(_board.score, _board.lines)
	_board.best = Scores.best()
	if rank == 1:
		_overlay.celebrate(get_viewport_rect().size)
	%FinalScore.text = str(_board.score)
	%FinalBest.text = "%d lines cleared" % _board.lines
	%RankLabel.text = _rank_text(rank)
	%GameOverPanel.show()
	%RetryButton.grab_focus()


func _rank_text(rank: int) -> String:
	if rank == 1:
		return "NEW BEST"
	if rank > 0:
		return "#%d on the leaderboard" % rank
	return "best  %d" % Scores.best()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if %GameOverPanel.visible: _leave()
		else: _toggle_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _board.alive and not %GameOverPanel.visible:
			_pause()


# --- screen state ------------------------------------------------------------

func _pause() -> void:
	if %PausePanel.visible or %GameOverPanel.visible:
		return
	_cancel_drag()
	%PausePanel.show()
	%ResumeButton.grab_focus()


func _toggle_pause() -> void:
	if %GameOverPanel.visible:
		return
	if %PausePanel.visible:
		%PausePanel.hide()
	else:
		_pause()


func _cancel_drag() -> void:
	_drag_index = -1
	_drag_view.hide()
	_board.preview_cells = []
	_board.queue_redraw()
	if not _tray.is_empty():
		_sync_tray()


func _restart() -> void:
	%PausePanel.hide()
	%GameOverPanel.hide()
	_cancel_drag()
	_kill_deal_tweens()
	for i in _slots.size():
		var view: Control = _slots[i].get_node("View")
		view.scale = Vector2.ONE
		view.rotation = 0.0
		view.modulate.a = 1.0
	for child in _effects.get_children():
		child.queue_free()
	for child in _overlay.get_children():
		child.queue_free()
	_shake = 0.0
	_best_at_start = Scores.best()
	_beat_best = false
	_combo_bomb_given = false
	_board.reset()
	_board.best = Scores.best()
	_refill_tray()


func _leave() -> void:
	App.goto_scene(App.SCENE_MAIN_MENU)
