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

## Level-ups replayed on the XP bar in one go. A big clear can cross three at
## once and the player should not sit through every one.
const XP_ROLL_MAX := 3

var _tray: Array = []          # TRAY_SIZE entries; {} means spent
var _slots: Array[Control] = []
## Where the piece being dragged came from. The old `_drag_index >= 0` sentinel
## could not tell a tray card from a sidebar power.
enum DragFrom { NONE, TRAY, POWER }
var _drag_from := DragFrom.NONE
var _drag_index := -1
var _power_slots: Array[Control] = []
## Powers are hidden in Puzzle: a seeded board plus a levelled bomb is no longer
## the same puzzle for two players.
var _powers_enabled := true
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
var _last_combo := 0
var _aura_tween: Tween
## Which step of the background flow the run is on. -1 means the default
## palette; it only ever moves forward, and the backdrop keeps the last colour.
var _flow_step := -1
## How much of this run's score has already been banked as XP. Score is fed to
## Progress as it is earned rather than in one lump at game over, so a level can
## land mid-run -- which is the point of the aura.
var _banked := 0
var _levels_this_run := 0
## True while the screen is wearing the level-up colour. The next combo takes
## the background back, which is what clears it.
var _level_aura := false
## One entry per board-mutating action, oldest first; rewind walks back through
## it. The board keeps no history of its own -- it just hands out plain
## snapshots -- and the tray lives here, so the two are only ever captured
## together. Restoring the board without the tray would take the placed piece
## off the board AND leave the slot spent.
var _history: Array = []
## Kept so one cast restarts the clock on the last. Without it the first one's
## pending restore fires mid-way through the second and cuts its sky short.
var _power_glow: Tween
## Re-lights the doubled-session halo for as long as the run lasts.
var _bonus_pulse: Tween
var _xp_tween: Tween
## While the bar is playing its roll-over, ordinary score updates must not
## retarget it -- they would cut the celebration off mid-fill.
var _xp_rolling := false


func _ready() -> void:
	_slots = [%Slot0, %Slot1, %Slot2, %Slot3, %Slot4]
	_power_slots = [%PowerSlot0, %PowerSlot1, %PowerSlot2]
	Progress.charge_changed.connect(func(_c: int, _m: int) -> void: _sync_powers())
	Progress.loadout_changed.connect(_sync_powers)

	_board.score_changed.connect(_on_score_changed)
	_board.piece_placed.connect(_on_piece_placed)
	_board.bomb_detonated.connect(_on_bomb_detonated)
	_board.laser_fired.connect(_on_laser_fired)
	_board.diagonal_fired.connect(_on_diagonal_fired)
	_board.blackhole_fired.connect(_on_blackhole_fired)
	_board.thunder_struck.connect(_on_thunder_struck)
	_board.blocks_teleported.connect(_on_blocks_teleported)
	_board.meteor_landed.connect(_on_meteor_landed)
	_board.tsunami_swept.connect(_on_tsunami_swept)
	_board.earthquake_shook.connect(_on_earthquake_shook)
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
	if _drag_from != DragFrom.NONE:
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
	for i in TRAY_SIZE:
		_tray.append(Blocks.random_piece())
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






## A restart mid-deal would otherwise leave cards stuck part-way in.
func _kill_deal_tweens() -> void:
	for tween in _deal_tweens:
		if tween is Tween and tween.is_valid():
			tween.kill()
	_deal_tweens.clear()


## Mirrors `_sync_tray` for the power strip: each slot shows its equipped
## power, dimmed when there is not enough charge to fire it.
func _sync_powers() -> void:
	if _power_slots.is_empty():
		return
	# Hidden outright until the first slot unlocks at level 2. An empty strip
	# with a charge meter on it promises a currency the player has nothing to
	# spend on -- and cannot earn a power with, since powers come from levels.
	%PowerBar.visible = _powers_enabled and Progress.loadout_size() > 0
	if not %PowerBar.visible:
		return
	for i in _power_slots.size():
		var slot: Control = _power_slots[i]
		var view: Control = slot.get_node("View")
		var label: Label = slot.get_node("Level")
		var power: int = Progress.equipped(i)
		var held: bool = power != Blocks.Power.NONE
		slot.visible = i < Progress.loadout_size()
		# The dragged power is drawn under the pointer, so its slot reads empty.
		var showing: bool = held and not (_drag_from == DragFrom.POWER and i == _drag_index)
		view.piece = Blocks.power_piece(power) if showing else {}
		view.dimmed = showing and not Progress.can_afford(power)
		label.text = "L%d" % Progress.level_of(power) if showing else ""
		label.add_theme_color_override("font_outline_color",
			Themes.value("ink", Color.BLACK))
	var maximum: int = maxi(1, Progress.max_charge())
	%ChargeFill.scale.x = clampf(float(Progress.charge()) / float(maximum), 0.0, 1.0)
	%Key.text = "%d/%d" % [Progress.charge(), maximum]


## The XP plate in the top bar. It sits in the slack the bar already had
## between the pause button and the combo plate, so it costs the board nothing
## -- the row is still as tall as the combo plate, which is taller.
func _sync_xp() -> void:
	if _xp_rolling:
		return
	%XpKey.text = "LEVEL %d  ·  2x" % Progress.level() if Progress.bonus_active() \
		else "LEVEL %d" % Progress.level()
	var target := Progress.level_progress()
	if _xp_tween and _xp_tween.is_valid():
		_xp_tween.kill()
	# Eased rather than snapped: a placement worth a few hundred points should
	# visibly move the bar, which is the whole reason it is on screen.
	_xp_tween = create_tween()
	_xp_tween.tween_property(%XpFill, "scale:x", target, 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Runs the bar over the top once per level gained, then settles it on the new
## level's true progress. Capped, because a huge single clear can cross two or
## three levels and the player should not sit through all of them.
func _roll_xp(gained: int) -> void:
	if _xp_tween and _xp_tween.is_valid():
		_xp_tween.kill()
	_xp_rolling = true
	var tint: Color = Themes.text_color("highlight")
	var from: int = maxi(1, Progress.level() - gained)
	# Lit for the WHOLE roll rather than at the turnover, where the colour fell
	# inside a 0.1s drop and read as an ordinary fill. The bar is recoloured by
	# swapping its stylebox, not by `modulate` -- modulate multiplies, and the
	# fill is already dark, so tinting it gold only ever made it dimmer.
	var box := _xp_box()
	var base: Color = box.bg_color if box else Color.WHITE
	if box:
		box.bg_color = tint
	_xp_tween = create_tween()
	for i in mini(gained, XP_ROLL_MAX):
		var reached := from + i + 1
		_xp_tween.tween_property(%XpFill, "scale:x", 1.0, 0.32) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		_xp_tween.tween_callback(func() -> void:
			%XpKey.text = "LEVEL %d" % reached
			_punch_xp_key())
		_xp_tween.tween_property(%XpFill, "scale:x", 0.0, 0.10)
	_xp_tween.tween_callback(func() -> void: %XpKey.text = "LEVEL %d" % Progress.level())
	_xp_tween.tween_property(%XpFill, "scale:x", Progress.level_progress(), 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if box:
		_xp_tween.parallel().tween_property(box, "bg_color", base, 0.5)
	_xp_tween.tween_callback(_end_xp_roll)


## A private copy of the fill's stylebox, so the roll can recolour it without
## touching the theme every bar shares. Returns null under a theme whose BarFill
## is a nine-patch rather than a flat box -- the roll still plays, unlit.
func _xp_box() -> StyleBoxFlat:
	%XpFill.remove_theme_stylebox_override("panel")
	var sb: StyleBox = %XpFill.get_theme_stylebox("panel", "BarFill")
	if not (sb is StyleBoxFlat):
		return null
	var box: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
	%XpFill.add_theme_stylebox_override("panel", box)
	return box


## Drops the override so the bar goes back to following the theme -- otherwise a
## theme swap would leave it wearing the old palette's colour.
func _end_xp_roll() -> void:
	_xp_rolling = false
	%XpFill.remove_theme_stylebox_override("panel")


## A scale punch on the level number, so the eye is pulled to the plate even if
## the player was watching the board when the bar rolled.
func _punch_xp_key() -> void:
	var key: Label = %XpKey
	key.pivot_offset = key.size * 0.5
	var punch := create_tween()
	punch.tween_property(key, "scale", Vector2(1.35, 1.35), 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	punch.tween_property(key, "scale", Vector2.ONE, 0.22) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


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
	elif event is InputEventMouseMotion and _drag_from != DragFrom.NONE:
		_update_drag(event.position)


func _begin_drag(pointer: Vector2) -> void:
	for i in TRAY_SIZE:
		if _tray[i].is_empty():
			continue
		if _slots[i].get_global_rect().has_point(pointer):
			_start_drag(DragFrom.TRAY, i, _tray[i], pointer)
			return

	# The strip. Only a slot holding a power the player can actually pay for
	# picks up -- an unaffordable one is drawn dimmed, and dragging it just to
	# be refused on the drop would be a lie.
	if not _powers_enabled:
		return
	for i in _power_slots.size():
		if i >= Progress.loadout_size() or not _power_slots[i].visible:
			continue
		var power: int = Progress.equipped(i)
		if power == Blocks.Power.NONE or not Progress.can_afford(power):
			continue
		if _power_slots[i].get_global_rect().has_point(pointer):
			_start_drag(DragFrom.POWER, i, Blocks.power_piece(power), pointer)
			return


## The shared tail of a pick-up, from either the tray or the strip.
##
## `_drag_from` MUST be assigned before `_update_drag` runs: that function
## returns immediately while it is NONE. Leaving it unset is what killed the
## entire drag path -- every placement and every power cast -- because
## `_end_drag` then matched NONE and did nothing at all.
func _start_drag(from: DragFrom, index: int, piece: Dictionary,
		pointer: Vector2) -> void:
	_drag_from = from
	_drag_index = index
	_drag_view.piece = piece
	_drag_view.fixed_cell = _board.cell_size()
	_drag_view.size = _drag_view.piece_pixel_size()
	_drag_view.show()
	# Redraw the source so the slot being carried reads as empty.
	if from == DragFrom.TRAY:
		_sync_tray()
	else:
		_sync_powers()
	_update_drag(pointer)
	# Land on the pick-up point immediately; easing in from wherever the view
	# happened to sit last would look like a glitch.
	_drag_view.position = _drag_target


func _update_drag(pointer: Vector2) -> void:
	if _drag_from == DragFrom.NONE:
		return
	var cell: float = _board.cell_size()
	var piece_px: Vector2 = _drag_view.piece_pixel_size()

	# The piece is centred on a point lifted above the finger.
	var focus := pointer - Vector2(0.0, DRAG_LIFT_CELLS * cell)
	var top_left := focus - piece_px * 0.5

	var local := top_left - _board.global_position
	_drag_origin = Vector2i(roundi(local.x / cell), roundi(local.y / cell))

	var cells: Array = _drag_view.piece["cells"]
	_board.preview_valid = _board.can_target(cells, _drag_origin,
		Blocks.power_of(_drag_view.piece))

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
	match _drag_from:
		DragFrom.TRAY: _drop_tray_piece()
		DragFrom.POWER: _fire_power()
	_drag_from = DragFrom.NONE
	_drag_view.hide()
	_board.preview_cells = []
	_board.queue_redraw()
	_check_game_over()


func _drop_tray_piece() -> void:
	var index := _drag_index
	var piece: Dictionary = _tray[index]
	# _begin_drag only ever picks a filled slot, but bail rather than index into
	# an empty dictionary if that invariant is ever broken.
	if piece.is_empty():
		_sync_tray()
		return
	if not _board.can_place(piece["cells"], _drag_origin):
		_sync_tray()          # illegal drop puts the card back in its slot
		return

	_push_history()
	_board.place(piece["cells"], _drag_origin, piece["color"])
	_tray[index] = {}
	if _tray_spent():
		_refill_tray()
	else:
		_sync_tray()


## Fires the equipped power the player dragged out of the strip.
##
## Order matters twice here. The level is read BEFORE spending, because
## spending records a use and can push the power to the next level -- a shot
## must resolve at the level it was shown at. And charge is taken only after
## `place()` reports it actually fired, so a drop the board refuses cannot
## still bill the player.
## Slots guaranteed to be dealt a piece that actually fits, by shuffle level.
## This table lives here rather than beside the others in board.gd because the
## tray is this screen's, not the board's -- board.gd has no idea a tray exists.
const SHUFFLE_FITTING_BY_LEVEL := [3, 4, 5, 5, 5]
## From here up, the guaranteed slots take the LARGEST piece that fits rather
## than any of them, so a levelled shuffle is worth more than a re-roll.
const SHUFFLE_BIG_LEVEL := 4
## Nothing wider or taller than this is offered: the request is for pieces that
## slot into the gaps a played board leaves, not for another 4-long bar.
const SHUFFLE_MAX_SPAN := 3

## The doubled-XP session: gold, and re-lit on this cadence for the whole run.
const BONUS_TINT := Color(1.0, 0.82, 0.25)
const BONUS_PULSE_SECONDS := 3.5

## Actions a rewind steps back over, by level.
const REWIND_STEPS_BY_LEVEL := [1, 2, 3, 4, 5]
## Backdrop and light for every power: the sky it washes the screen to, the
## colour of the motes gathering round the board, and how long it holds.
##
## A cast is a moment the player sits in, not a one-frame bang -- but only just.
## Nothing here runs past 1.6s: the backdrop is what the board is read against,
## and holding a colour over it any longer stops being an accent and starts
## being the game's palette. Reach roughly tracks how big the power is.
const POWER_ATMOSPHERE := {
	Blocks.Power.FIT:
		{"sky": Color(0.28, 0.50, 0.08), "motes": Color(0.72, 0.95, 0.35), "hold": 0.9},
	Blocks.Power.SHUFFLE:
		{"sky": Color(0.05, 0.42, 0.38), "motes": Color(0.45, 0.95, 0.88), "hold": 0.9},
	Blocks.Power.MORPH:
		{"sky": Color(0.05, 0.35, 0.34), "motes": Color(0.35, 0.90, 0.85), "hold": 1.0},
	Blocks.Power.LASER:
		{"sky": Color(0.62, 0.52, 0.05), "motes": Color(1.00, 0.95, 0.50), "hold": 1.0},
	Blocks.Power.DIAGONAL:
		{"sky": Color(0.07, 0.35, 0.60), "motes": Color(0.40, 0.80, 1.00), "hold": 1.0},
	Blocks.Power.BOMB:
		{"sky": Color(0.55, 0.16, 0.05), "motes": Color(1.00, 0.60, 0.25), "hold": 1.2},
	# A storm sky, not paper white. The HUD is drawn in cream, and the top
	# gradient stop lerps 85% of the way to this colour -- at 0.68 the score
	# and the "best" line measured within six values of the sky behind them and
	# simply disappeared. Against the near-black default this still reads as a
	# white cloud rolling in.
	Blocks.Power.THUNDER:
		{"sky": Color(0.46, 0.49, 0.54), "motes": Color(1.00, 0.92, 0.35), "hold": 1.2},
	Blocks.Power.TELEPORT:
		{"sky": Color(0.45, 0.08, 0.50), "motes": Color(0.95, 0.50, 1.00), "hold": 1.2},
	Blocks.Power.EARTHQUAKE:
		{"sky": Color(0.35, 0.25, 0.10), "motes": Color(0.85, 0.72, 0.45), "hold": 1.4},
	Blocks.Power.METEOR:
		{"sky": Color(0.42, 0.14, 0.03), "motes": Color(1.00, 0.62, 0.30), "hold": 1.4},
	Blocks.Power.TSUNAMI:
		{"sky": Color(0.02, 0.22, 0.42), "motes": Color(0.50, 0.85, 1.00), "hold": 1.5},
	# Night, with the disc's own violet falling into it.
	Blocks.Power.BLACKHOLE:
		{"sky": Color(0.02, 0.01, 0.05), "motes": Color(0.72, 0.55, 1.00), "hold": 1.6},
	# The Time Stone.
	Blocks.Power.REWIND:
		{"sky": Color(0.13, 0.85, 0.42), "motes": Color(0.45, 0.95, 0.60), "hold": 1.6},
}
## One deeper than the longest rewind, so the top level always has its full
## reach available rather than being clipped by the buffer.
const HISTORY_MAX := 6


## Captures everything an undo has to put back. Deliberately absent:
## `_board.best` and `_banked`, both high-water marks -- restoring them would
## let the same points be banked as XP twice -- and anything in `Progress`,
## because charge and power uses are spent for good. That last one is what
## keeps rewind from being a charge pump.
func _push_history() -> void:
	_history.append({
		"board": _board.snapshot(),
		# Shallow is right: entries are references into the static piece
		# catalogue and are replaced wholesale, never mutated in place.
		"tray": _tray.duplicate(),
		"puzzle_cleared": _puzzle_cleared,
		"last_combo": _last_combo,
		"flow_step": _flow_step,
	})
	while _history.size() > HISTORY_MAX:
		_history.pop_front()


## Undoes a push for an action the board then refused, so a misfire cannot
## leave a phantom step that rewinds to exactly where the player already is.
func _drop_history() -> void:
	if not _history.is_empty():
		_history.pop_back()


## Steps back over the last few actions -- placements and power casts alike --
## and puts the board and the tray back as they were before them.
func _rewind(level: int) -> bool:
	if _history.is_empty():
		return false
	var lvl: int = clampi(level, 1, REWIND_STEPS_BY_LEVEL.size())
	var steps: int = mini(int(REWIND_STEPS_BY_LEVEL[lvl - 1]), _history.size())
	var snap: Dictionary = {}
	for i in steps:
		snap = _history.pop_back()

	_board.restore(snap["board"])
	_tray = (snap["tray"] as Array).duplicate()
	_puzzle_cleared = int(snap["puzzle_cleared"])
	_last_combo = int(snap["last_combo"])
	_flow_step = int(snap["flow_step"])

	_kill_deal_tweens()
	_sync_tray()
	_sync_objective()
	# The counter snaps rather than rolling when the value drops, but its guard
	# compares against what is currently SHOWN, so a rewind landing mid-roll
	# could still animate upward toward a smaller number. Snap it outright.
	%ScoreValue.reset_to(_board.score)
	_on_rewound(steps)
	return true


## Washes the sky to the power's own colour and gathers light around the board
## for as long as POWER_ATMOSPHERE says, then hands the backdrop back to
## wherever the combo flow had it -- which is also what drops a level-up wash,
## since the cast's own colour supersedes it.
func _power_atmosphere(power: int) -> void:
	var spec: Dictionary = POWER_ATMOSPHERE.get(power, {})
	if spec.is_empty():
		return
	var hold: float = float(spec["hold"])
	_background.tint_to(spec["sky"], 1.0, 0.25)

	# Hugs the drawn grid, not the control: under a pixel theme the snapped
	# grid is narrower than `size` and a halo on the control would float away
	# from the board's edge.
	var cell: float = _board.cell_size()
	var span: float = cell * _board.grid
	var at: Vector2 = _board.global_position + _board.grid_origin(cell)
	_atmosphere.time_field(Rect2(at, Vector2(span, span)), spec["motes"], hold)

	if _power_glow and _power_glow.is_valid():
		_power_glow.kill()
	_power_glow = create_tween()
	_power_glow.tween_interval(hold)
	_power_glow.tween_callback(_restore_flow)


## A sweep back across the board rather than puffs on the restored cells: the
## point of a rewind is that the whole board moved, not that particular tiles
## arrived.
func _on_rewound(steps: int) -> void:
	Audio.play("collapse", 1.25)
	var tint: Color = Blocks.power_color(Blocks.Power.REWIND)
	# The sweep is darkened well below the glyph's colour. Rewind's palette
	# entry is a pale slate, and at full strength the sweep washed the whole
	# board out for a beat -- the one thing an undo must not do is hide the
	# board it just restored. The banner keeps the true colour.
	_effects.morph_sweep(_board.size.x, tint.darkened(0.55))
	_overlay.combo_banner_text(
		"REWIND!" if steps == 1 else "REWIND x%d" % steps, tint)

	_power_atmosphere(Blocks.Power.REWIND)
	_shake = 5.0
	Haptics.clear_lines(2)
	_sync_powers()


## A doubled session announces itself and keeps announcing it: the halo is
## re-lit on a slow repeat for the whole run, because a one-off flash at the
## start would be gone by the time the player is deciding whether it was worth
## coming back. The backdrop is deliberately left alone -- the combo flow owns
## it, and a session-long tint would fight every clear.
func _begin_bonus_session() -> void:
	_sync_xp()
	_overlay.combo_banner_text("DOUBLE XP!", BONUS_TINT)
	Haptics.celebrate(get_tree())
	if _bonus_pulse and _bonus_pulse.is_valid():
		_bonus_pulse.kill()
	_bonus_pulse = create_tween().set_loops()
	_bonus_pulse.tween_callback(_pulse_bonus_aura)
	_bonus_pulse.tween_interval(BONUS_PULSE_SECONDS)
	_pulse_bonus_aura()


func _end_bonus_session() -> void:
	if _bonus_pulse and _bonus_pulse.is_valid():
		_bonus_pulse.kill()
	_sync_xp()


func _pulse_bonus_aura() -> void:
	if not Progress.bonus_active():
		_end_bonus_session()
		return
	var cell: float = _board.cell_size()
	var span: float = cell * _board.grid
	var at: Vector2 = _board.global_position + _board.grid_origin(cell)
	_atmosphere.time_field(Rect2(at, Vector2(span, span)), BONUS_TINT,
		BONUS_PULSE_SECONDS * 0.6)


func _fire_power() -> void:
	var power: int = Progress.equipped(_drag_index)
	if power == Blocks.Power.NONE or not Progress.can_afford(power):
		_sync_powers()
		return
	var level: int = Progress.level_of(power)

	# Rewind is not itself an action, so it is never recorded as a step --
	# rewinding a rewind would be a loop with no bottom.
	if power == Blocks.Power.REWIND:
		if not _rewind(level):
			_sync_powers()    # nothing to undo yet: a free cancel
			return
		Progress.spend(power)
		_sync_powers()
		return

	# Shuffle never reaches the board: it rewrites the tray, which lives here.
	if power == Blocks.Power.SHUFFLE:
		_push_history()
		if not _shuffle_tray(level):
			_drop_history()
			_sync_powers()    # no piece fits anywhere: a free cancel
			return
		Progress.spend(power)
		_on_tray_shuffled()
		_sync_powers()
		return

	var piece: Dictionary = Blocks.power_piece(power)
	_push_history()
	if not _board.place(piece["cells"], _drag_origin, piece["color"], power, level):
		_drop_history()
		_sync_powers()        # dropped off the board: a free cancel
		return
	Progress.spend(power)
	_sync_powers()


## Re-deals the tray with pieces the board can actually take. Returns false
## when nothing in the catalogue fits at all -- which is exactly the board
## where a shuffle would be worthless, so the charge is handed back.
func _shuffle_tray(level: int) -> bool:
	var lvl: int = clampi(level, 1, SHUFFLE_FITTING_BY_LEVEL.size())
	var guaranteed: int = int(SHUFFLE_FITTING_BY_LEVEL[lvl - 1])

	var fitting: Array = []
	for piece: Dictionary in Blocks.catalogue():
		var span: Vector2i = piece["size"]
		if span.x > SHUFFLE_MAX_SPAN or span.y > SHUFFLE_MAX_SPAN:
			continue
		if _board.has_any_move([piece]):
			fitting.append(piece)
	if fitting.is_empty():
		return false

	# The biggest fitting piece is worth the most, so a levelled shuffle hands
	# those out; below that it is an even draw from whatever fits.
	var by_cells := fitting.duplicate()
	by_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["cells"] as Array).size() > (b["cells"] as Array).size())

	_kill_deal_tweens()
	_tray.clear()
	for i in TRAY_SIZE:
		if i < guaranteed:
			if lvl >= SHUFFLE_BIG_LEVEL:
				# Spread across the top of the list rather than five copies of
				# the single largest piece.
				_tray.append(by_cells[mini(i, by_cells.size() - 1)])
			else:
				_tray.append(fitting[randi() % fitting.size()])
		else:
			_tray.append(Blocks.random_piece())
	_sync_tray()
	_deal_animation()
	return true


func _on_tray_shuffled() -> void:
	Audio.play("place", 1.1)
	var tint: Color = Blocks.power_color(Blocks.Power.SHUFFLE)
	_overlay.combo_banner_text("SHUFFLE!", tint)
	_power_atmosphere(Blocks.Power.SHUFFLE)
	Haptics.clear_lines(1)


## The earthquake. Blocks hop one cell at a time, so the screen shakes for the
## whole cast rather than punching once, and each landing gets a puff.
func _on_earthquake_shook(moved: Array, nudges: int) -> void:
	Audio.play("collapse", 0.7)
	var cell: float = _board.cell_size()
	var tint: Color = Blocks.power_color(Blocks.Power.EARTHQUAKE)
	for c: Vector2i in _sample_cells(moved, MAX_FILL_PUFFS):
		_effects.place_puff([c], cell, tint)
	_overlay.combo_banner_text("EARTHQUAKE!", tint)
	_power_atmosphere(Blocks.Power.EARTHQUAKE)
	# Scaled by how long the ground kept moving, and the strongest shake in the
	# game: this is the one power whose whole idea is the shaking.
	_shake = 14.0 + mini(nudges, 32) * 0.9
	Haptics.blast()
	_sync_tray()


## A run is only over when neither the tray nor the strip can do anything. A
## board with no legal card but a charged bomb in the bank is still playable.
func _check_game_over() -> void:
	if _board.has_any_move(_remaining_pieces()):
		return
	if _powers_enabled and Progress.has_affordable():
		return
	_board.declare_game_over()


# --- board reactions ---------------------------------------------------------

func _on_score_changed(score: int, best: int, combo: int) -> void:
	_bank(score)
	%ScoreValue.set_value(score)
	%BestValue.text = "best  %d" % best
	_sync_xp()
	_show_combo(combo)

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
	_level_aura = false
	_background.tint_to(_overlay.flow_color(_flow_step), 1.0)


## Drops the level-up colour and returns the backdrop to wherever the combo
## flow had it.
func _restore_flow() -> void:
	_level_aura = false
	if _flow_step < 0:
		_background.tint_to(Color.WHITE, 0.0, 0.45)
	else:
		_background.tint_to(_overlay.flow_color(_flow_step), 1.0, 0.45)


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
	# A streak pays charge; a lone clear pays nothing.
	Progress.award_combo(_board.combo)
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
	elif _level_aura and _board.combo >= 2:
		# Mid-streak when the level landed: put the flow colour back rather
		# than stepping it, which would skip a rung.
		_restore_flow()
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
	_power_atmosphere(Blocks.Power.BOMB)
	_effects.popup("BOOM!", region.get_center(), fire, true)
	if points > 0:
		_effects.popup("+%d" % points, region.get_center() + Vector2(0.0, cell * 1.5),
			Color(0.945, 0.941, 1), false)
	print_verbose("bomb cleared %d cells for %d points" % [cleared, points])

	_shake = 26.0
	Haptics.blast()
	# Half the board just opened up, so dead cards may be playable again.
	_sync_tray()


func _on_laser_fired(at: Vector2i, cleared: int, points: int, _level := 1) -> void:
	Audio.play("laser")
	var cell: float = _board.cell_size()
	var extent: float = _board.size.x
	_effects.laser_beam(at, extent, cell)
	_power_atmosphere(Blocks.Power.LASER)
	_overlay.combo_banner_text("LASER!", Color(1, 0.95, 0.55))
	if points > 0:
		_overlay.points_popup("+%d" % points,
			get_viewport_rect().size * Vector2(0.5, 0.60), Color(0.945, 0.941, 1), false)
	_shake = 20.0
	Haptics.blast()
	_sync_tray()


## The diagonal power. Same treatment as the laser, struck along both diagonals
## instead of the row and column.
func _on_diagonal_fired(at: Vector2i, cleared: int, points: int, _level := 1) -> void:
	Audio.play("laser", 0.85)
	var cell: float = _board.cell_size()
	var extent: float = _board.size.x
	_effects.diagonal_beam(at, extent, cell)
	_power_atmosphere(Blocks.Power.DIAGONAL)
	_overlay.combo_banner_text("CROSSFIRE!", Blocks.power_color(Blocks.Power.DIAGONAL))
	if points > 0:
		_overlay.points_popup("+%d" % points,
			get_viewport_rect().size * Vector2(0.5, 0.60), Color(0.945, 0.941, 1), false)
	_shake = 20.0
	Haptics.blast()
	_sync_tray()


## The blackhole. An implosion sized to the disc it actually cleared, so the
## effect traces the cells that went rather than a generic blast.
func _on_blackhole_fired(at: Vector2i, radius: float, cleared: int, points: int) -> void:
	Audio.play("bomb", 0.6)
	var cell: float = _board.cell_size()
	var centre := (Vector2(at) + Vector2(0.5, 0.5)) * cell
	var tint: Color = Blocks.power_color(Blocks.Power.BLACKHOLE)
	var reach: float = (radius + 0.5) * cell
	_effects.implode(centre, reach, cell, tint)
	_power_atmosphere(Blocks.Power.BLACKHOLE)
	_overlay.combo_banner_text("BLACKHOLE!", tint)
	if points > 0:
		_overlay.points_popup("+%d" % points,
			get_viewport_rect().size * Vector2(0.5, 0.60), Color(0.945, 0.941, 1), false)
	print_verbose("blackhole r=%.1f cleared %d for %d" % [radius, cleared, points])
	# Gentler than the bomb: the board is being pulled in, not blown apart.
	_shake = 10.0
	Haptics.blast()
	_sync_tray()


## Thunder. One puff per strike rather than a single blast, because the strikes
## are scattered and a blast at any one of them would misreport where it hit.
func _on_thunder_struck(cells: Array, cleared: int, points: int) -> void:
	Audio.play("laser", 1.15)
	var cell: float = _board.cell_size()
	var tint: Color = Blocks.power_color(Blocks.Power.THUNDER)
	for c: Vector2i in cells:
		_effects.place_puff([c], cell, tint)
	_overlay.combo_banner_text("THUNDER!", tint)
	_power_atmosphere(Blocks.Power.THUNDER)
	if points > 0:
		_overlay.points_popup("+%d" % points,
			get_viewport_rect().size * Vector2(0.5, 0.60), Color(0.945, 0.941, 1), false)
	print_verbose("thunder struck %d cells for %d" % [cleared, points])
	_shake = 8.0 + mini(cells.size(), 8) * 1.5
	Haptics.blast()
	_sync_tray()


## Teleport. Puffs at both ends -- the block leaving and the block arriving --
## so the eye can follow where it went.
func _on_blocks_teleported(from_cells: Array, to_cells: Array, color_index: int) -> void:
	Audio.play("fit", 0.9)
	var cell: float = _board.cell_size()
	var tint: Color = Blocks.power_color(Blocks.Power.TELEPORT)
	_effects.place_puff(from_cells, cell, tint)
	_effects.place_puff(to_cells, cell, Blocks.COLORS[color_index])
	_overlay.combo_banner_text("TELEPORT!", tint)
	_power_atmosphere(Blocks.Power.TELEPORT)
	_shake = 6.0
	Haptics.clear_lines(2)
	_sync_tray()


## Cells to puff for a filling power. Both now take a SHARE of the empty board,
## so a big cast can land forty blocks at once -- one puff each buried the
## board under a solid wall of particles. Sampling evenly keeps the impacts
## spread across the whole area that was filled.
const MAX_FILL_PUFFS := 10


func _sample_cells(cells: Array, limit: int) -> Array:
	if cells.size() <= limit:
		return cells
	var out: Array = []
	var step: float = float(cells.size()) / float(limit)
	for i in limit:
		out.append(cells[int(i * step)])
	return out


## Meteor. Puffs at the impacts rather than one blast, because the drops are
## scattered and a single burst would misreport where they landed. The blocks
## themselves are drawn in the meteor's own palette entry, so the debris on the
## board still reads as debris after the effect has gone.
func _on_meteor_landed(cells: Array, color_index: int, points: int) -> void:
	Audio.play("place", 0.8)
	var cell: float = _board.cell_size()
	var tint: Color = Blocks.COLORS[color_index]
	for c: Vector2i in _sample_cells(cells, MAX_FILL_PUFFS):
		_effects.place_puff([c], cell, tint)
	_overlay.combo_banner_text("METEOR!", tint)
	_power_atmosphere(Blocks.Power.METEOR)
	if points > 0:
		_overlay.points_popup("+%d" % points,
			get_viewport_rect().size * Vector2(0.5, 0.60), Color(0.945, 0.941, 1), false)
	_shake = 6.0 + mini(cells.size(), 16) * 0.6
	Haptics.blast()
	# The board just gained blocks, so cards that fitted a moment ago may not.
	_sync_tray()


## Tsunami. The sweep runs across the board like the collapse does, but tinted
## as water and followed by a puff on every cell the wave filled.
func _on_tsunami_swept(cells: Array, color_index: int, points: int) -> void:
	Audio.play("collapse", 0.85)
	var cell: float = _board.cell_size()
	var tint: Color = Blocks.COLORS[color_index]
	_effects.morph_sweep(_board.size.x, tint)
	for c: Vector2i in _sample_cells(cells, MAX_FILL_PUFFS):
		_effects.place_puff([c], cell, tint)
	_overlay.combo_banner_text("TSUNAMI!", tint)
	_power_atmosphere(Blocks.Power.TSUNAMI)
	if points > 0:
		_overlay.points_popup("+%d" % points,
			get_viewport_rect().size * Vector2(0.5, 0.60), Color(0.945, 0.941, 1), false)
	_shake = 8.0 + mini(cells.size(), 24) * 0.4
	Haptics.clear_lines(3)
	_sync_tray()


func _on_board_morphed(dropped: int) -> void:
	Audio.play("collapse")
	_effects.morph_sweep(_board.size.x, Blocks.COLORS[Blocks.POWER_COLOR[Blocks.Power.MORPH]])
	_overlay.combo_banner_text("COLLAPSE!", Blocks.COLORS[Blocks.POWER_COLOR[Blocks.Power.MORPH]])
	_power_atmosphere(Blocks.Power.MORPH)
	_shake = 6.0 + mini(dropped, 20) * 0.8
	Haptics.clear_lines(3)
	_sync_tray()


func _on_piece_fitted(cells: Array, color_index: int) -> void:
	Audio.play("fit")
	_effects.place_puff(cells, _board.cell_size(), Blocks.COLORS[color_index])
	_overlay.combo_banner_text("FIT!", Blocks.COLORS[color_index])
	_power_atmosphere(Blocks.Power.FIT)
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
	# Every run banks its score as XP, win or lose -- a bad run still advances
	# something, which is the property the game lacked entirely.
	# Most of the run is already banked; this only picks up whatever landed
	# after the last score_changed.
	_bank(_board.score)
	var levels_gained: int = _levels_this_run
	var rank: int = Scores.submit(_board.score, _board.lines, Modes.current)
	# Game Center gets every finished run. The call is a no-op off iOS, and
	# queues if sign-in has not landed yet, so the local table stays the
	# source of truth either way.
	GameServices.submit_score(_board.score, Modes.current)
	_board.best = Scores.best(Modes.current)
	if rank == 1:
		_overlay.celebrate(get_viewport_rect().size)
	elif levels_gained > 0:
		_overlay.level_aura(get_viewport_rect().size)
	_show_level_up(levels_gained)
	%FinalScore.text = str(_board.score)
	%FinalBest.text = "%d lines cleared" % _board.lines
	%RankLabel.text = _rank_text(rank)
	_end_bonus_session()
	# The nudge the whole bonus exists for: say what one more run is worth,
	# after the rank line so it reads as the reason to tap Retry.
	var nudge := _bonus_hint()
	if not nudge.is_empty():
		%RankLabel.text += "\n" + nudge
	var title: Label = %GameOverPanel/Center/Box/Title
	if solved:
		title.text = "BOARD\nSOLVED"
	elif Modes.current == Modes.Id.SPRINT:
		title.text = "TIME\nUP"
	else:
		title.text = "NO ROOM\nLEFT"
	%GameOverPanel.show()
	%RetryButton.grab_focus()


## What the next run is worth, in one line. Empty when there is nothing to say.
func _bonus_hint() -> String:
	if Progress.bonus_ready():
		return "Next run earns DOUBLE XP"
	var runs: int = Progress.runs_until_bonus()
	if runs == 1:
		return "One more run today earns DOUBLE XP"
	return "%d more runs today earn DOUBLE XP" % runs


## Banks the score earned since the last call. Only the delta goes across, so
## feeding continuously and topping up at game over cannot double-count.
func _bank(score: int) -> void:
	var delta := score - _banked
	if delta <= 0:
		return
	_banked = score
	var gained := Progress.add_score(delta * Progress.xp_multiplier())
	if gained <= 0:
		return
	_levels_this_run += gained
	_celebrate_level(gained)


## A level landed mid-run. Wash the screen in the level colour and light the
## aura; the next combo puts the background back, because `_advance_flow` and
## `_wash_background` reclaim it.
func _celebrate_level(gained: int) -> void:
	_level_aura = true
	_roll_xp(gained)
	# A level can grant the first loadout slot, which is what brings the power
	# strip on screen. Nothing else re-syncs it: `loadout_changed` fires when a
	# power is equipped, and at this point none is.
	_sync_powers()
	var tint: Color = Themes.text_color("highlight")
	# Only part-way to the tint. The combo flow can afford a full wash because
	# its colours are dark enough to sit under the board; the highlight colour
	# is not, and this one PERSISTS until a combo clears it -- so the player
	# would be reading tiles off a bright gold field until then.
	_background.tint_to(tint, 0.55, 0.35)

	if _aura_tween and _aura_tween.is_valid():
		_aura_tween.kill()
	# Brighter and longer than a combo wash: this happens a handful of times a
	# session, not several times a run.
	_aura.color = Color(tint.r, tint.g, tint.b, 0.30)
	_aura_tween = create_tween()
	_aura_tween.tween_property(_aura, "color", Color(tint.r, tint.g, tint.b, 0.0), 2.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	var screen: Vector2 = get_viewport_rect().size
	_overlay.combo_banner_text("LEVEL %d" % Progress.level(), tint)
	_overlay.level_aura(screen)
	Haptics.celebrate(get_tree())


## The end-of-run level readout. Levels are only ever gained here, so this is
## the one place a player finds out -- it gets the confetti and a banner, not a
## line of small print.
func _show_level_up(gained: int) -> void:
	%LevelUp.visible = gained > 0
	%LevelUpNote.visible = gained > 0
	if gained <= 0:
		return
	%LevelUp.add_theme_color_override("font_outline_color",
		Themes.value("ink", Color.BLACK))
	%LevelUp.text = "LEVEL %d" % Progress.level() if gained == 1 \
		else "LEVEL %d   (+%d)" % [Progress.level(), gained]

	# Say what the level actually bought, since that is the reason to care.
	var earned: Array[String] = []
	if Progress.pending_unlocks() > 0:
		earned.append("a new power to choose")
	for l in range(Progress.level() - gained + 1, Progress.level() + 1):
		var r: Dictionary = Progress.REWARDS.get(l, {})
		if r.has("theme"):
			earned.append("%s theme" % Themes.theme_name(int(r["theme"])))
		if r.has("charge"):
			earned.append("+%d charge" % int(r["charge"]))
		if l == Progress.BIG_BOARD_LEVEL:
			earned.append("a bigger board")
	%LevelUpNote.text = "Unlocked: " + ", ".join(earned) if not earned.is_empty() \
		else "Keep going."


	# No floating banner here: combo_banner_text draws at screen centre, which
	# is exactly where the game-over panel puts this label, and the two
	# collided. The confetti plus the panel's own line carry it.
	Haptics.celebrate(get_tree())


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
	_drag_from = DragFrom.NONE
	_drag_index = -1
	_drag_view.hide()
	_board.preview_cells = []
	_board.queue_redraw()
	if not _tray.is_empty():
		_sync_tray()
	_sync_powers()


func _restart() -> void:
	%PausePanel.hide()
	%GameOverPanel.hide()
	_show_level_up(0)
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
	_banked = 0
	_levels_this_run = 0
	_level_aura = false
	_background.tint_to(Color.WHITE, 0.0, 0.2)
	_shake = 0.0
	_best_at_start = Scores.best(Modes.current)
	_beat_best = false
	_last_combo = 0
	%ScoreValue.reset_to(0)
	# touch_day first: crossing into a new day can itself bank a bonus, and the
	# claim below should be able to spend it on this very run.
	Progress.touch_day()
	Progress.note_run_started()
	if Progress.claim_bonus():
		_begin_bonus_session()
	else:
		_end_bonus_session()
	_board.reset()
	_setup_mode()
	_board.best = Scores.best(Modes.current)
	_history.clear()
	_refill_tray()
	_sync_powers()
	_end_xp_roll()
	_sync_xp()


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
	# Puzzle boards are seeded and shared, so a levelled power would make board
	# N a different puzzle for two players.
	_powers_enabled = Modes.current != Modes.Id.PUZZLE
	# Before anything else: the grid changes the cell size, and every layout
	# and legality check downstream depends on it.
	_board.set_grid(Modes.grid_of())
	match Modes.current:
		Modes.Id.BIG_PALETTE:
			%FuseBar.hide()
			%Objective.hide()
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
	_sync_powers()


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
