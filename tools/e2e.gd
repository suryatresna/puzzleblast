extends Node
## End-to-end: boots the app, walks every route, plays a game with synthesised
## pointer input, fires a power off the strip, ends the run and checks it was
## recorded and persisted.
##
##   "$GODOT" --headless --path . res://tools/e2e.tscn
##
## This is the only test that goes through App.goto_scene and _input. Everything
## else in this repo drives _board.place() or _fire_power() directly, which is
## how a completely dead drag path once survived a whole feature's worth of
## tests. Keep it.
##
## NOTE it wipes user:// progress and writes a leaderboard row.
##
## Survives scene changes: added to the tree root, not to the current scene,
## so change_scene_to_file frees the screen under it and leaves this running.

var f := 0
var log: Array = []
func ck(o: bool, l: String) -> void:
	if o: print("OK    ", l)
	else: print("FAIL  ", l); f += 1

func here() -> String:
	var s: Node = get_tree().current_scene
	return "" if s == null else String(s.scene_file_path).get_file()

func settle(n := 6) -> void:
	for i in n: await get_tree().process_frame

## Navigate the way a tap does, and confirm we actually arrived.
func go(route: String, expect: String) -> void:
	App.goto_scene(String(App.get(route)))
	await get_tree().create_timer(1.2).timeout
	ck(here() == expect, "%s -> %s (landed on %s)" % [route, expect, here()])

func press(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true; e.position = at
	get_tree().current_scene._input(e)
func move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new(); e.position = at
	get_tree().current_scene._input(e)
func release(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = false; e.position = at
	get_tree().current_scene._input(e)

func filled(b) -> int:
	var n := 0
	for y in b.grid:
		for x in b.grid:
			if b._grid[y][x] != b.EMPTY: n += 1
	return n


func _ready() -> void:
	get_tree().create_timer(280.0).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(2))
	await settle(10)
	Progress.wipe()

	# ---------- the app boots where project.godot says ----------
	# This harness IS the main scene, so current_scene is the test. Assert the
	# real boot route instead: what project.godot points at, and that it loads.
	var boot := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	ck(boot == "res://scenes/splash.tscn", "project.godot boots %s" % boot)
	var packed: PackedScene = load(boot)
	ck(packed != null and packed.can_instantiate(), "and that scene instantiates")

	# ---------- every route actually navigates ----------
	await go("SCENE_MAIN_MENU", "main_menu.tscn")
	await go("SCENE_SETTINGS", "settings.tscn")
	await go("SCENE_ABOUT", "about.tscn")
	await go("SCENE_LEADERBOARD", "leaderboard.tscn")
	await go("SCENE_MODES", "mode_select.tscn")
	await go("SCENE_PROFILE", "profile.tscn")
	await go("SCENE_MAIN_MENU", "main_menu.tscn")

	# ---------- play a real game, by dragging ----------
	Modes.set_current(Modes.Id.PALETTE)
	await go("SCENE_GAME", "game.tscn")
	var g: Node = get_tree().current_scene
	await settle(8)
	var b = g.get_node("%Board")
	var cell: float = b.cell_size()
	var origin: Vector2 = b.global_position

	var placed := 0
	for turn in 40:
		if not b.alive: break
		# find a slot with a card, and a legal square for it
		var slot := -1
		for i in g.TRAY_SIZE:
			if not g._tray[i].is_empty(): slot = i; break
		if slot < 0: break
		var piece: Dictionary = g._tray[slot]
		var target := Vector2i(-1, -1)
		for y in b.grid:
			for x in b.grid:
				if b.can_place(piece["cells"], Vector2i(x, y)):
					target = Vector2i(x, y); break
			if target.x >= 0: break
		if target.x < 0: break
		# drag it there for real: press the slot, move over the board, release
		var before := filled(b)
		press(g._slots[slot].get_global_rect().get_center())
		if g._drag_from != g.DragFrom.TRAY: break
		# _update_drag computes: origin = round((pointer - lift - px/2 - board)/cell)
		# so invert it, reading the carried piece's real pixel size rather than
		# guessing it from the cell count.
		var px: Vector2 = g._drag_view.piece_pixel_size()
		var pointer: Vector2 = origin + Vector2(target) * cell + px * 0.5 \
			+ Vector2(0.0, g.DRAG_LIFT_CELLS * cell)
		move(pointer)
		release(pointer)
		await get_tree().process_frame
		# NOT filled(b) > before: a placement that completes a line clears it,
		# so the board can end up emptier. The card being spent is the signal.
		if g._tray[slot].is_empty() or filled(b) != before: placed += 1
		else:
			break
	ck(placed >= 8, "dragged %d pieces onto the board by input" % placed)
	ck(b.score > 0, "which scored %d" % b.score)

	# ---------- fire a power, by dragging it off the strip ----------
	# Always restart first, for two reasons. The loop above plays until nothing
	# fits, which trips _check_game_over -- and _input returns early once the
	# board is dead, so later presses are swallowed. And even when the run
	# survives (charge in the bank keeps it alive), the board can be completely
	# full, leaving FIT no empty cell to target.
	g._restart()
	await settle(8)
	ck(b.alive, "board is live for the power test")
	Progress.add_score(Progress.threshold(4))
	for p: int in Progress.available_to_unlock(): Progress.unlock(p)
	Progress.equip(0, Blocks.Power.FIT)
	Progress._charge = 30
	g._sync_powers()
	var pslot: Control = g._power_slots[0]
	# `visible` flips synchronously but the rect needs a layout pass, so
	# pressing too early hit a degenerate rect and picked up nothing.
	for i in 30:
		await get_tree().process_frame
		if pslot.visible and pslot.get_global_rect().size.x > 1.0:
			break
	ck(pslot.visible and pslot.get_global_rect().size.x > 1.0,
		"the power strip is laid out (%s)" % pslot.get_global_rect().size)
	var charge0: int = Progress.charge()
	press(pslot.get_global_rect().get_center())
	ck(g._drag_from == g.DragFrom.POWER, "dragging the strip picks up a power")
	# aim at an empty cell -- FIT needs one
	var empty := Vector2i(-1, -1)
	for y in b.grid:
		for x in b.grid:
			if b._grid[y][x] == b.EMPTY: empty = Vector2i(x, y); break
		if empty.x >= 0: break
	var ppx: Vector2 = origin + (Vector2(empty) + Vector2(0.5, 0.5)) * cell \
		+ Vector2(0.0, g.DRAG_LIFT_CELLS * cell)
	move(ppx)
	release(ppx)
	await settle(3)
	ck(Progress.uses_of(Blocks.Power.FIT) == 1,
		"and firing it recorded a use (%d)" % Progress.uses_of(Blocks.Power.FIT))
	ck(Progress.charge() < charge0, "and cost charge (%d -> %d; the clear in "
		% [charge0, Progress.charge()] + "between also re-clamped it to max)")

	# ---------- finish the run, and check it is recorded ----------
	var score: int = b.score
	var before_best: int = Scores.best(Modes.Id.PALETTE)
	b.declare_game_over()
	await settle(8)
	ck(not b.alive, "the run ended")
	ck(g.get_node("%GameOverPanel").visible, "the game-over panel showed")
	ck(Scores.best(Modes.Id.PALETTE) >= maxi(before_best, score),
		"the leaderboard kept it (best %d)" % Scores.best(Modes.Id.PALETTE))
	ck(Progress.total_score() > 0, "and it banked %s XP" % Progress.commas(Progress.total_score()))

	# ---------- progression survives a reload ----------
	var xp: int = Progress.total_score()
	var lvl: int = Progress.level()
	Progress._loaded = false
	Progress._unlocked.clear(); Progress._loadout.clear()
	Progress._uses.clear(); Progress._themes.clear()
	Progress._ensure_loaded()
	ck(Progress.total_score() == xp and Progress.level() == lvl,
		"progress round-trips through disk (L%d, %s)" % [Progress.level(),
			Progress.commas(Progress.total_score())])

	# ---------- back out to the menu ----------
	await go("SCENE_MAIN_MENU", "main_menu.tscn")
	Progress.wipe()
	print("")
	print("E2E ", "OK" if f == 0 else "FAILED", " (%d)" % f)
	get_tree().quit(1 if f else 0)
