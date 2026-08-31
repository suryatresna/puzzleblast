extends Control
## Drag-and-drop block puzzle.
##
## Five cards sit in a tray at the bottom. Drag one onto the 8x8 board; filling
## any row or column clears it with a boom. The tray refills once all five are
## spent, and the run ends when nothing left in the tray fits anywhere.

const Blocks := preload("res://scripts/blocks.gd")
const Haptics := preload("res://scripts/haptics.gd")

const TRAY_SIZE := 5

## How far above the pointer the piece is drawn, in board cells. Without this
## the player's own finger covers the thing they are trying to place.
const DRAG_LIFT_CELLS := 1.4
const SHAKE_DECAY := 7.0

## How hard the dragged piece is pulled onto the grid once it is over a legal
## spot. Higher is snappier; this settles in roughly a tenth of a second, so
## the piece reads as magnetised to the cell rather than floating under the
## finger. Set to 0 to disable snapping and follow the pointer exactly.
const DRAG_SNAP_SPEED := 34.0

## Dealing a fresh hand: a beat to register the tray emptying, then each card
## pops in a little after the one before it.
const DEAL_DELAY := 0.12
const DEAL_STAGGER := 0.07
const DEAL_TIME := 0.34

## Streak length that earns a bomb comes from the difficulty setting; a bomb is
## awarded once per streak, so a 5x run hands out one rather than four.

## Colours for the combo badge: muted with no streak running, gold once the
## multiplier is actually worth something.
## Fallbacks only -- see `_combo_color`, which reads the active theme.
const COMBO_IDLE := Color(0.651, 0.635, 0.8)
const COMBO_HOT := Color(1, 0.83, 0.32)

@onready var _board: Control = %Board
@onready var _effects: Node2D = %Effects
@onready var _drag_view: Control = %DragView
@onready var _overlay: Node2D = %OverlayEffects
@onready var _aura: ColorRect = %ComboAura
@onready var _atmosphere: Node2D = %ComboParticles
@onready var _background: Control = %Background

var _tray: Array = []          # TRAY_SIZE entries; {} means spent
var _slots: Array[Control] = []
var _drag_index := -1
var _drag_origin := Vector2i.ZERO
## Where the dragged piece is heading; `_process` eases it there each frame.
var _drag_target := Vector2.ZERO
var _shake := 0.0
## Best score when this run started, and whether it has been passed yet, so the
## celebration fires exactly once per run.
var _best_at_start := 0
var _beat_best := false
var _deal_tweens: Array = []
## Lines cleared this run; Puzzle mode scores its objective against it.
var _puzzle_cleared := 0
var _combo_power_given := false
var _last_combo := 0
var _aura_tween: Tween
## Which step of the background flow the run is on. -1 means the default
## palette; it only ever moves forward, and the backdrop keeps the last colour.
var _flow_step := -1


func _ready() -> void:
	_slots = [%Slot0, %Slot1, %Slot2, %Slot3, %Slot4]

	_board.score_changed.connect(_on_score_changed)
	_board.piece_placed.connect(_on_piece_placed)
	Difficulty.tightened.connect(_on_difficulty_tightened)
	_board.bomb_detonated.connect(_on_bomb_detonated)
	_board.laser_fired.connect(_on_laser_fired)
	_board.board_morphed.connect(_on_board_morphed)
	_board.piece_fitted.connect(_on_piece_fitted)
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
	%FuseBar.finished.connect(_on_time_up)

	_restart()


func _process(delta: float) -> void:
	if _drag_index >= 0:
		# Frame-rate independent easing, so the pull feels the same at 30 or
		# 120 fps rather than being tied to how often _process happens to run.
		var t: float = 1.0 - exp(-DRAG_SNAP_SPEED * delta) if DRAG_SNAP_SPEED > 0.0 else 1.0
		_drag_view.position = _drag_view.position.lerp(_drag_target, t)

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
	var bias: float = Difficulty.small_piece_bias()
	for i in TRAY_SIZE:
		_tray.append(Blocks.random_piece(bias))
	# One roll per hand, so a tray holds at most a single special. Which of the
	# four turns up is an even draw.
	if randf() < Difficulty.tray_special_chance():
		_tray[randi() % TRAY_SIZE] = Blocks.random_special_piece()
	_sync_tray()
	_deal_animation()


## Pops the new hand in one card at a time. Deliberately presentation only --
## `_tray` is already filled by the time this starts, so the caller's
## "any moves left?" check never sees a half-dealt tray.
func _deal_animation() -> void:
	Audio.play("deal")
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


## True when the hand already holds any special, so the combo reward never
## stacks a second one on top.
func _tray_has_power() -> bool:
	for piece: Dictionary in _tray:
		if Blocks.is_power(piece):
			return true
	return false


## Hands the player a special for stringing clears together -- any of the four,
## drawn at random, so a streak is not always worth the same thing. Skipped when
## the hand already holds one, keeping the "at most one special" rule intact.
func _maybe_grant_combo_power() -> void:
	var threshold: int = Difficulty.combo_power_threshold()
	if threshold <= 0:
		return                       # this band never grants one
	if _combo_power_given or _board.combo < threshold:
		return
	_combo_power_given = true
	if _tray_has_power():
		return

	# Prefer a slot the player has already emptied; only displace a live card
	# if the hand happens to be full.
	var empty_slots: Array = []
	for i in TRAY_SIZE:
		if _tray[i].is_empty():
			empty_slots.append(i)
	var slot: int = empty_slots.pick_random() if not empty_slots.is_empty() \
		else randi() % TRAY_SIZE

	var reward: Dictionary = Blocks.random_special_piece()
	var power: Blocks.Power = Blocks.power_of(reward)
	_tray[slot] = reward
	_sync_tray()
	_pop_in(_slots[slot].get_node("View"), 0.0)

	var at: Vector2 = _slots[slot].get_global_rect().get_center() - Vector2(0.0, 150.0)
	_overlay.popup(Blocks.power_name(power), at, Blocks.power_color(power), false)
	Haptics.clear_lines(3)      # reward buzz, distinct from a plain clear


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
			# Land on the pick-up point immediately; easing in from wherever
			# the view happened to sit last would look like a glitch.
			_drag_view.position = _drag_target
			return


func _update_drag(pointer: Vector2) -> void:
	if _drag_index < 0:
		return
	var cell: float = _board.cell_size()
	var piece_px: Vector2 = _drag_view.piece_pixel_size()

	# The piece is centred on a point lifted above the finger.
	var focus := pointer - Vector2(0.0, DRAG_LIFT_CELLS * cell)
	var top_left := focus - piece_px * 0.5

	var local := top_left - _board.global_position
	_drag_origin = Vector2i(roundi(local.x / cell), roundi(local.y / cell))

	var cells: Array = _drag_view.piece["cells"]
	_board.preview_valid = _board.can_place(cells, _drag_origin)

	# Over a legal spot the piece is pulled onto the exact cell it will occupy,
	# so what you see is precisely what gets placed. Off the grid, or over an
	# illegal spot, it tracks the pointer so the drag never feels stuck.
	if _board.preview_valid and DRAG_SNAP_SPEED > 0.0:
		_drag_target = _board.global_position + Vector2(_drag_origin) * cell
	else:
		_drag_target = top_left

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

	_board.place(piece["cells"], _drag_origin, piece["color"], Blocks.power_of(piece))
	_tray[index] = {}

	if _tray_spent():
		_refill_tray()
	else:
		_sync_tray()

	_maybe_grant_combo_power()

	if not _board.has_any_move(_remaining_pieces()):
		_board.declare_game_over()


# --- board reactions ---------------------------------------------------------

func _on_score_changed(score: int, best: int, combo: int) -> void:
	%ScoreValue.set_value(score)
	Difficulty.update(score)
	%BestValue.text = "best  %d   ·   %s" % [best, Difficulty.level_name()]
	_show_combo(combo)
	if combo == 0:
		_combo_power_given = false

	# Overtaking the previous best is worth celebrating the moment it happens,
	# not just on the game over screen. Skipped on a first-ever run, where
	# there is no record to beat.
	if not _beat_best and _best_at_start > 0 and score > _best_at_start:
		_beat_best = true
		_celebrate_best()


## Tints the whole screen in the rung's colour and sends a matching shower up
## behind the board. Kept at low alpha and faded out quickly -- this sits under
## the playfield, and anything stronger makes the blocks hard to read.
func _wash_background(combo: int, screen: Vector2) -> void:
	if combo < 2 or _flow_step < 0:
		return                       # a lone clear does not colour the screen

	var tint: Color = _overlay.flow_color(_flow_step)
	_atmosphere.combo_atmosphere(
		tint, _overlay.flow_has_flowers(_flow_step), combo, screen)

	if _aura_tween and _aura_tween.is_valid():
		_aura_tween.kill()
	var peak := Color(tint.r, tint.g, tint.b, 0.18)
	_aura.color = peak
	_aura_tween = create_tween()
	_aura_tween.tween_property(_aura, "color", Color(tint.r, tint.g, tint.b, 0.0), 1.1) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## The badge only lights up once a streak is actually multiplying the score.
## A permanent "x1" reads as though a combo is always running, which it is not:
## combo 0 means the last placement cleared nothing.
func _show_combo(combo: int) -> void:
	var label: Label = %ComboValue
	if combo >= 2:
		label.text = "x%d" % combo
		label.add_theme_color_override("font_color", Themes.text_color("highlight"))
		%ComboBox.modulate.a = 1.0
	elif combo == 1:
		label.text = "x1"
		label.add_theme_color_override("font_color", Themes.text_color("muted"))
		%ComboBox.modulate.a = 0.8
	else:
		label.text = "--"
		label.add_theme_color_override("font_color", Themes.text_color("muted"))
		%ComboBox.modulate.a = 0.45

	# Only punch when the streak actually grew, not on every score change.
	if combo > _last_combo and combo >= 2:
		_pulse_combo()
	_last_combo = combo


## Recolours the whole backdrop for the duration of a streak, and eases it back
## to the default palette once the streak breaks.
## Steps the backdrop to the next colour in the flow and leaves it there. The
## background is never washed back to the default mid-run: it holds the last
## streak's colour until another streak moves it along.
func _advance_flow() -> void:
	_flow_step += 1
	_background.tint_to(_overlay.flow_color(_flow_step), 1.0)


func _pulse_combo() -> void:
	var label: Control = %ComboValue
	label.pivot_offset = label.size * 0.5
	# from() pins the start; see the note in score_counter.gd.
	var peak := Vector2(1.4, 1.4)
	label.scale = peak
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.30).from(peak) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Called out so the ramp is visible: the deal quietly getting stingier with no
## explanation would just read as bad luck.
func _on_difficulty_tightened(level: int) -> void:
	var screen: Vector2 = get_viewport_rect().size
	_overlay.popup("%s" % Difficulty.name_of(level).to_upper(),
		screen * Vector2(0.5, 0.30), Color(1, 0.55, 0.2), false)
	Haptics.clear_lines(2)


func _celebrate_best() -> void:
	var area: Vector2 = get_viewport_rect().size
	_overlay.celebrate(area)
	_overlay.popup("NEW BEST!", area * Vector2(0.5, 0.34), Color(1, 0.83, 0.32), true)
	Haptics.celebrate(get_tree())


## Every landing gets a small puff so placing a piece feels like it connects.
func _on_piece_placed(cells: Array, color_index: int) -> void:
	Audio.play("place")
	_effects.place_puff(cells, _board.cell_size(), Blocks.COLORS[color_index])
	_shake = maxf(_shake, 2.5)
	Haptics.place()


func _on_lines_cleared(rows: Array, cols: Array, _cell_count: int, points: int) -> void:
	_puzzle_cleared += rows.size() + cols.size()
	_sync_objective()
	if _puzzle_solved():
		# Let the clear animation read before the panel drops.
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if _board.alive:
				_board.declare_game_over())
	# Combo raises the pitch so a streak reads as one rising phrase.
	var step: int = clampi(_board.combo - 1, 0, 4)
	if _board.combo >= 2:
		Audio.play("combo", 1.0 + step * 0.08)
	else:
		Audio.play("clear")

	var cell: float = _board.cell_size()
	var extent: float = _board.size.x
	var line_count: int = rows.size() + cols.size()
	var color: Color = Blocks.COLORS[0] if line_count < 3 else Blocks.COLORS[3]

	_effects.explode_lines(rows, cols, extent, cell, color)

	# The combo call-out replaces the old per-clear word: two labels fighting
	# for the middle of the board read as clutter. Both sit on the overlay so
	# they are centred on the screen rather than on the board.
	var screen: Vector2 = get_viewport_rect().size
	# combo == 2 is exactly the clear that opens a streak, so the palette steps
	# once per streak rather than once per clear.
	if _board.combo == 2:
		_advance_flow()
	_wash_background(_board.combo, screen)
	_overlay.combo_banner(_board.combo, screen * Vector2(0.5, 0.46))
	_overlay.points_popup("+%d" % points, screen * Vector2(0.5, 0.60),
		Color(0.945, 0.941, 1), line_count >= 3)

	_shake = 8.0 + line_count * 6.0
	Haptics.clear_lines(line_count)
	# Clearing can free space, so previously dead cards may be playable again.
	_sync_tray()


## Every finished run goes on the leaderboard, whether or not it placed.
func _on_bomb_detonated(at: Vector2i, from_row: int, to_row: int,
		cleared: int, points: int) -> void:
	Audio.play("bomb")
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
	Haptics.blast()
	# Half the board just opened up, so dead cards may be playable again.
	_sync_tray()


func _on_laser_fired(at: Vector2i, cleared: int, points: int) -> void:
	Audio.play("laser")
	var cell: float = _board.cell_size()
	var extent: float = _board.size.x
	_effects.laser_beam(at, extent, cell)
	_overlay.combo_banner_text("LASER!", Color(1, 0.95, 0.55))
	if points > 0:
		_overlay.points_popup("+%d" % points,
			get_viewport_rect().size * Vector2(0.5, 0.60), Color(0.945, 0.941, 1), false)
	_shake = 20.0
	Haptics.blast()
	_sync_tray()


func _on_board_morphed(dropped: int) -> void:
	Audio.play("collapse")
	_effects.morph_sweep(_board.size.x, Blocks.COLORS[Blocks.POWER_COLOR[Blocks.Power.MORPH]])
	_overlay.combo_banner_text("COLLAPSE!", Blocks.COLORS[Blocks.POWER_COLOR[Blocks.Power.MORPH]])
	_shake = 6.0 + mini(dropped, 20) * 0.8
	Haptics.clear_lines(3)
	_sync_tray()


func _on_piece_fitted(cells: Array, color_index: int) -> void:
	Audio.play("fit")
	_effects.place_puff(cells, _board.cell_size(), Blocks.COLORS[color_index])
	_overlay.combo_banner_text("FIT!", Blocks.COLORS[color_index])
	_shake = 5.0
	Haptics.clear_lines(1)
	_sync_tray()


func _on_game_over() -> void:
	# The GameOver track replaces the bed for the whole end-of-run panel; a
	# one-shot effect on top of it would just muddy the jingle.
	%FuseBar.stop()
	var solved := _puzzle_solved()
	if solved:
		Modes.mark_solved(Modes.puzzle_level)
		if Modes.puzzle_level < Modes.PUZZLE_COUNT:
			Modes.puzzle_level += 1
	# A solved board gets the victory jingle; everything else gets the loss one.
	if solved:
		Audio.play_stinger("victory")
	else:
		Audio.play_game_over()
	Haptics.stop()               # nothing should still be buzzing on game over
	var rank: int = Scores.submit(_board.score, _board.lines, Modes.current)
	# Game Center gets every finished run. The call is a no-op off iOS, and
	# queues if sign-in has not landed yet, so the local table stays the
	# source of truth either way.
	GameServices.submit_score(_board.score, Modes.current)
	_board.best = Scores.best(Modes.current)
	if rank == 1:
		_overlay.celebrate(get_viewport_rect().size)
	%FinalScore.text = str(_board.score)
	%FinalBest.text = "%d lines cleared" % _board.lines
	%RankLabel.text = _rank_text(rank)
	var title: Label = %GameOverPanel/Center/Box/Title
	if solved:
		title.text = "BOARD\nSOLVED"
	elif Modes.current == Modes.Id.SPRINT:
		title.text = "TIME\nUP"
	else:
		title.text = "NO ROOM\nLEFT"
	%GameOverPanel.show()
	%RetryButton.grab_focus()


func _rank_text(rank: int) -> String:
	if rank == 1:
		return "NEW BEST"
	if rank > 0:
		return "#%d on the leaderboard" % rank
	return "best  %d" % Scores.best(Modes.current)


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
	Haptics.stop()
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
	for child in _atmosphere.get_children():
		child.queue_free()
	if _aura_tween and _aura_tween.is_valid():
		_aura_tween.kill()
	_aura.color = Color(0, 0, 0, 0)
	# A new run starts from the default palette again.
	_flow_step = -1
	Difficulty.reset()
	_background.tint_to(Color.WHITE, 0.0, 0.2)
	_shake = 0.0
	_best_at_start = Scores.best(Modes.current)
	_beat_best = false
	_combo_power_given = false
	_last_combo = 0
	%ScoreValue.reset_to(0)
	_board.reset()
	_setup_mode()
	_board.best = Scores.best(Modes.current)
	_refill_tray()


func _leave() -> void:
	Haptics.stop()
	App.goto_scene(App.SCENE_MAIN_MENU)


# --- game modes --------------------------------------------------------------

## Applies the mode chosen on the picker. Called once per run, after the board
## and HUD exist but before the first deal, so a preset board is in place when
## the opening hand is checked for a legal move.
func _setup_mode() -> void:
	_puzzle_cleared = 0
	%FuseBar.stop()
	match Modes.current:
		Modes.Id.SPRINT:
			%FuseBar.show()
			%FuseBar.start(Modes.SPRINT_SECONDS)
			%Objective.show()
			%Objective.text = "SPRINT  ·  SCORE WHAT YOU CAN"
		Modes.Id.PUZZLE:
			%FuseBar.hide()
			_board.preset(Modes.puzzle_layout(Modes.puzzle_level))
			%Objective.show()
			_sync_objective()
		_:
			%FuseBar.hide()
			%Objective.hide()


func _sync_objective() -> void:
	if Modes.current != Modes.Id.PUZZLE:
		return
	var target := Modes.puzzle_target(Modes.puzzle_level)
	%Objective.text = "BOARD %d  ·  CLEAR %d LINES  ·  %d/%d" % [
		Modes.puzzle_level, target, mini(_puzzle_cleared, target), target,
	]


## Sprint ran out. The board decides the run is over so every end-of-run path
## stays in one place.
func _on_time_up() -> void:
	if _board.alive:
		_board.declare_game_over()


## True when a Puzzle board has met its objective.
func _puzzle_solved() -> bool:
	return Modes.current == Modes.Id.PUZZLE \
		and _puzzle_cleared >= Modes.puzzle_target(Modes.puzzle_level)
