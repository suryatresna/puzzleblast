extends Node
## Drops a tray piece outside the board, through the real input path, and
## reports whether the frame ever completes.
var g: Control
var stage := "boot"
func _ready() -> void:
	# A hard watchdog: if a frame never returns, this timer never fires either,
	# so also print progress as we go.
	get_tree().create_timer(45.0).timeout.connect(func():
		print("WATCHDOG fired, last stage: ", stage); get_tree().quit(2))
	Progress.wipe(); Progress.add_score(Progress.threshold(2))
	Modes.set_current(Modes.Id.PALETTE)
	g = load("res://scenes/game.tscn").instantiate()
	add_child(g); g.set_anchors_preset(Control.PRESET_FULL_RECT)
	for i in 3: await get_tree().process_frame
	g.size = Vector2(1080, 1920)
	for i in 6: await get_tree().process_frame
	var b = g._board
	# mid-game: a board with plenty on it
	for y in range(3, 8):
		for x in range(0, 8):
			if (x * 3 + y) % 4 != 0: b._grid[y][x] = (x + y) % 8
	b.queue_redraw()
	g._sync_tray()
	for i in 3: await get_tree().process_frame

	var slot := -1
	for i in g.TRAY_SIZE:
		if not g._tray[i].is_empty(): slot = i; break
	print("  picking up slot ", slot)
	stage = "press"
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true
	e.position = g._slots[slot].get_global_rect().get_center()
	g._input(e)
	print("  drag_from=", g._drag_from, " index=", g._drag_index)

	# drag WAY outside the board -- above it, off to the left, off-screen
	for spot: Vector2 in [Vector2(-400, -400), Vector2(20, 30), Vector2(2000, 3000),
			Vector2(-1e6, -1e6)]:
		stage = "move %s" % spot
		print("  moving to ", spot)
		var m := InputEventMouseMotion.new(); m.position = spot
		g._input(m)
		print("    -> origin ", g._drag_origin, " valid=", g._board.preview_valid)
		await get_tree().process_frame

	stage = "release"
	print("  releasing outside")
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT; r.pressed = false
	r.position = Vector2(-1e6, -1e6)
	g._input(r)
	print("  released, drag_from=", g._drag_from)
	await get_tree().process_frame
	stage = "done"
	print("  survived; board alive=", b.alive)
	print("HANG-TEST COMPLETED")
	get_tree().quit(0)
