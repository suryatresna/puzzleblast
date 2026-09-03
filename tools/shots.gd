extends Node
## Store screenshots, rendered at true device resolution.
##
## Run:
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --path . res://tools/shots.tscn \
##       --write-movie /tmp/discard/f.png --fixed-fps 60 --disable-vsync -- 1320x2868
##
## `--write-movie` is not for its output, which is discarded: it is the only
## way to force a deterministic render loop. A backgrounded macOS window has
## its rendering suspended, so anything that reads a texture gets the same
## frame over and over (see docs/testing.md). This harness saves its own PNGs
## from a SubViewport and ignores the movie entirely.
##
## Why a SubViewport rather than just sizing the window: macOS clamps a window
## to the screen, so asking for 1320x2868 on a 1920x1080 display yields a
## 1320x1018 window -- and the stretch system then lays the game out LANDSCAPE.
## Movie Maker still writes files at the requested size, so the result looks
## plausible and is silently wrong: the HUD is cut off and the board clipped.

## Design resolution, from project.godot's window/size/viewport_*.
const DESIGN := Vector2i(1080, 1920)

## Default output. Override with the second argument.
const OUT_DIR := "res://screenshots/"

var _size := Vector2i(1320, 2868)      # 6.9", the slot Apple requires
var _out := OUT_DIR
var _sv: SubViewport
var _scene: Control = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var parts: PackedStringArray = String(args[0]).split("x")
		if parts.size() == 2:
			_size = Vector2i(int(parts[0]), int(parts[1]))
	if args.size() > 1:
		_out = String(args[1])
		if not _out.ends_with("/"):
			_out += "/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	# What a real device does: render at native resolution, but lay the UI out
	# in design units. `scale` is how canvas_items/expand maps one to the
	# other -- min of the two ratios, which for a screen taller than 9:16 is
	# always the width. The extra height becomes extra board, not letterbox.
	var scale: float = minf(float(_size.x) / DESIGN.x, float(_size.y) / DESIGN.y)
	var design := Vector2i(DESIGN.x, int(round(_size.y / scale)))

	_sv = SubViewport.new()
	_sv.size = _size
	_sv.size_2d_override = design
	_sv.size_2d_override_stretch = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.transparent_bg = false
	add_child(_sv)
	print("target %dx%d  design %dx%d  scale %.4f" % [
		_size.x, _size.y, design.x, design.y, scale])

	for shot: String in ["menu", "powers", "blackhole", "bomb", "line-clear",
			"skill-tree", "leaderboard"]:
		await _capture(shot)
	print("DONE")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		if _scene and _scene.has_node("%PausePanel"):
			_scene.get_node("%PausePanel").hide()
		await get_tree().process_frame


func _save(name: String) -> void:
	# The score is a rolling counter, so a shot taken while it is still
	# travelling shows a number that was never the score. Snap it -- the same
	# call _restart and _rewind use when a value must not animate.
	if _scene and _scene.has_node("%ScoreValue") and "_board" in _scene:
		_scene.get_node("%ScoreValue").reset_to(_scene._board.score)
		await _frames(2)
	await RenderingServer.frame_post_draw
	var img: Image = _sv.get_texture().get_image()
	# The store rejects an alpha channel outright.
	img.convert(Image.FORMAT_RGB8)
	var path := "%s%s.png" % [_out, name]
	var err := img.save_png(path)
	print("  %-28s %dx%d  %s" % [path, img.get_width(), img.get_height(),
		"ok" if err == OK else "ERR %d" % err])


func _open(path: String) -> Control:
	if _scene:
		_scene.queue_free()
		await get_tree().process_frame
	var s: Control = load(path).instantiate()
	_sv.add_child(s)
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ui: Theme = Themes.ui_theme()
	if ui:
		s.theme = ui                  # what App.apply_theme() does for a route
	_scene = s
	await _frames(3)
	return s


## A level-50 profile: the honest state for a player holding Blackhole, which
## is tier 5, and the level at which the endless board has grown to 12x12.
func _seed() -> void:
	Progress.wipe()
	Progress.add_score(Progress.threshold(50))
	Progress.add_score(int(Progress.threshold(51) - Progress.threshold(50)) / 3)
	for p: int in Blocks.ALL_POWERS:
		if not Progress._unlocked.has(p):
			Progress._unlocked.append(p)
	Progress.equip(0, Blocks.Power.BOMB)
	Progress.equip(1, Blocks.Power.BLACKHOLE)
	Progress.equip(2, Blocks.Power.LASER)
	Progress._charge = Progress.max_charge()
	Progress.use_tutorial_power()
	# Seeding _unlocked directly bypasses unlock(), which is what spends the
	# bank -- without this the profile truthfully reports unlocks waiting.
	Progress._pending_unlocks = 0
	# A level-50 player has met every lesson. Leaving them unseen puts a
	# tutorial line under the tray of a veteran's board.
	for row: Dictionary in Coach.LADDER:
		Progress.mark_hint_seen(int(row["id"]))
	for p: int in [Blocks.Power.BOMB, Blocks.Power.BLACKHOLE, Blocks.Power.LASER]:
		Progress._uses[p] = Progress.USES_FOR_LEVEL[2]


func _seed_scores() -> void:
	Scores.clear()
	for row: Array in [[48120, 61], [39880, 52], [31240, 44], [27600, 38],
			[19450, 29], [14380, 22], [9260, 15], [5140, 9]]:
		Scores.submit(row[0], row[1], Modes.Id.PALETTE)


## A board that reads as played-in. Blocks pile up from the bottom in a real
## run, so the odds are weighted by depth: an even sprinkle reads as noise.
func _paint(b, density: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903
	b.reset()
	for y in b.grid:
		var depth: float = float(y) / float(b.grid - 1)
		for x in b.grid:
			if rng.randf() < density * (0.45 + 1.0 * depth):
				b._grid[y][x] = rng.randi_range(0, 7)
	# Never leave a complete line: it would clear the instant anything landed.
	for y in b.grid:
		b._grid[y][rng.randi_range(0, b.grid - 1)] = b.EMPTY
	for x in b.grid:
		b._grid[rng.randi_range(0, b.grid - 1)][x] = b.EMPTY
	b.queue_redraw()


func _capture(shot: String) -> void:
	_seed()
	match shot:
		"menu":
			await _open(App.SCENE_MAIN_MENU)
			await _frames(30)
		"skill-tree":
			await _open(App.SCENE_PROFILE)
			await _frames(40)
		"leaderboard":
			_seed_scores()
			await _open(App.SCENE_LEADERBOARD)
			await _frames(40)
		_:
			Modes.set_current(Modes.Id.PALETTE)
			var g: Control = await _open(App.SCENE_GAME)
			var b = g._board
			_paint(b, 0.42 if shot != "line-clear" else 0.5)
			b.score = 24680
			b.best = 48120
			b.combo = 1
			g._best_at_start = 48120
			g._banked = b.score
			b.score_changed.emit(b.score, b.best, b.combo)
			g._sync_tray()
			g._sync_powers()
			await _frames(30)
			match shot:
				"blackhole": _cast(g, 1, Vector2i(b.grid / 2, b.grid / 2)); await _frames(12)
				"bomb":      _cast(g, 0, Vector2i(b.grid / 2, b.grid / 2 + 1)); await _frames(12)
				"line-clear": await _clear(g, b); await _frames(30)
	await _save(shot)


func _cast(g: Control, slot: int, at: Vector2i) -> void:
	var power: int = Progress.equipped(slot)
	g._start_drag(g.DragFrom.POWER, slot, Blocks.power_piece(power), Vector2.ZERO)
	g._drag_origin = at
	g._end_drag(Vector2.ZERO)


## Fills every gap but one in three rows, then drops a piece finishing them
## together, so the shot catches a real multi-line clear rather than a mock.
func _clear(g: Control, b) -> void:
	var rows := [b.grid - 2, b.grid - 3, b.grid - 4]
	for y: int in rows:
		for x in b.grid:
			b._grid[y][x] = (x + y) % 8
		b._grid[y][3] = b.EMPTY
	var piece := {"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		"size": Vector2i(1, 3), "color": 4}
	g._tray[0] = piece
	g._sync_tray()
	await _frames(6)
	g._start_drag(g.DragFrom.TRAY, 0, piece, Vector2.ZERO)
	g._drag_origin = Vector2i(3, rows.min())
	g._end_drag(Vector2.ZERO)
