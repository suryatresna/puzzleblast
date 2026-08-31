extends "res://scripts/menu_screen.gd"
## Shows the stored top runs, newest achievement highlighted, filtered by mode.
##
## Scores are kept per mode (see `Scores.MAX_ENTRIES`), so a filter always has
## a full table rather than whatever survived a shared cap.

const ROW_HEIGHT := 96
## `-1` is the All filter; the rest are `Modes.Id` values.
const ALL := -1

var _filter := ALL
var _chips: Dictionary = {}

@onready var _list: VBoxContainer = %List
@onready var _empty: Label = %EmptyLabel


func _ready() -> void:
	super()
	%ClearButton.pressed.connect(_confirm_clear)
	# Apple's own board, on the filter currently in view. Hidden entirely when
	# Game Center is not usable, rather than shipped as a dead button.
	%GameCenterButton.pressed.connect(_open_game_center)
	%GameCenterButton.visible = GameServices.available()
	GameServices.authentication_changed.connect(
		func(_ok: bool) -> void: %GameCenterButton.visible = GameServices.available())
	Scores.changed.connect(_rebuild)
	_build_filters()
	_rebuild()


## One chip per mode, plus All. Built from `Modes` so a new mode appears here
## without touching this screen.
func _build_filters() -> void:
	for child in %Filters.get_children():
		child.queue_free()
	_chips.clear()
	var options: Array = [ALL]
	options.append_array(Modes.ids())
	for id: int in options:
		var chip := Button.new()
		chip.text = "ALL" if id == ALL else Modes.mode_name(id)
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_font_size_override("font_size", 26)
		chip.pressed.connect(_set_filter.bind(id))
		%Filters.add_child(chip)
		_chips[id] = chip
	_sync_chips()


func _set_filter(id: int) -> void:
	_filter = id
	_sync_chips()
	_rebuild()


func _sync_chips() -> void:
	for id: int in _chips:
		var chip: Button = _chips[id]
		var on: bool = id == _filter
		chip.button_pressed = on
		# The pressed stylebox is darker than normal, which would make the
		# ACTIVE filter the quietest chip on the row. Dim the others instead.
		chip.modulate.a = 1.0 if on else 0.55


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	var entries: Array = Scores.entries() if _filter == ALL \
		else Scores.entries_for(_filter)
	# The scroller claims all the spare height, which would shove the empty
	# message to the bottom of the screen, so it is hidden when there is
	# nothing to scroll.
	_empty.visible = entries.is_empty()
	%Scroll.visible = not entries.is_empty()
	# Clearing wipes every mode, so only offer it when something is stored at
	# all -- not merely when the current filter has rows.
	%ClearButton.visible = not Scores.is_empty()
	%Filters.visible = not Scores.is_empty()
	if Scores.is_empty():
		_empty.text = "No games finished yet.\nPlay a round and your score lands here."
	elif _filter != ALL:
		_empty.text = "Nothing in %s yet." % Modes.mode_name(_filter)
	if entries.is_empty():
		return

	for i in entries.size():
		_list.add_child(_make_row(i + 1, entries[i]))


func _make_row(rank: int, entry: Dictionary) -> Control:
	var highlight := int(entry["id"]) == Scores.last_id and Scores.last_id >= 0

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pixel: bool = Themes.is_pixel()
	var style := StyleBoxFlat.new()
	style.bg_color = Themes.value("chip_top", Color(0.11, 0.098, 0.243, 0.55))
	style.border_color = Themes.text_color("accent") if highlight \
		else Themes.value("ink", Color(0.486, 0.424, 0.941, 0.2))
	style.set_border_width_all(6 if pixel else 2)
	style.set_corner_radius_all(8 if pixel else 22)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", style)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	var rank_label := Label.new()
	rank_label.text = "%d" % rank
	rank_label.custom_minimum_size = Vector2(70, 0)
	rank_label.add_theme_font_size_override("font_size", 40)
	rank_label.add_theme_color_override("font_color",
		Themes.text_color("highlight") if rank <= 3 else Themes.text_color("muted"))
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(rank_label)

	# The mode tag: which game this score came from, since they are not
	# comparable across modes.
	var tag := Label.new()
	tag.text = Modes.mode_name(int(entry.get("mode", Modes.Id.PALETTE)))
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_color", Themes.text_color("accent"))
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.custom_minimum_size = Vector2(180, 0)
	box.add_child(tag)

	var score_label := Label.new()
	score_label.text = str(entry["score"])
	score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_label.add_theme_font_size_override("font_size", 44)
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(score_label)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 0)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(meta)

	var lines_label := Label.new()
	lines_label.text = "%d lines" % int(entry["lines"])
	lines_label.add_theme_font_size_override("font_size", 26)
	lines_label.add_theme_color_override("font_color", Themes.text_color("muted"))
	lines_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(lines_label)

	var date_label := Label.new()
	date_label.text = Scores.format_date(int(entry["date"]))
	date_label.add_theme_font_size_override("font_size", 24)
	date_label.add_theme_color_override("font_color", Themes.text_color("faint"))
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(date_label)

	return row


## Two taps to wipe the table, since it cannot be undone.
func _confirm_clear() -> void:
	if %ClearButton.text.begins_with("Clear"):
		%ClearButton.text = "Tap again to erase"
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(self) and is_inside_tree():
			%ClearButton.text = "Clear scores"
		return
	Scores.clear()
	%ClearButton.text = "Clear scores"


func _open_game_center() -> void:
	GameServices.show_leaderboard(_filter if _filter != ALL else Modes.Id.PALETTE)
