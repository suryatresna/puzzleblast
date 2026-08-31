extends "res://scripts/menu_screen.gd"
## Shows the stored top runs, newest achievement highlighted.

const ROW_HEIGHT := 96

@onready var _list: VBoxContainer = %List
@onready var _empty: Label = %EmptyLabel


func _ready() -> void:
	super()
	%ClearButton.pressed.connect(_confirm_clear)
	Scores.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	var entries: Array = Scores.entries()
	# The scroller claims all the spare height, which would shove the empty
	# message to the bottom of the screen, so it is hidden when there is
	# nothing to scroll.
	_empty.visible = entries.is_empty()
	%Scroll.visible = not entries.is_empty()
	%ClearButton.visible = not entries.is_empty()
	if entries.is_empty():
		return

	for i in entries.size():
		_list.add_child(_make_row(i + 1, entries[i]))


func _make_row(rank: int, entry: Dictionary) -> Control:
	var highlight := int(entry["id"]) == Scores.last_id and Scores.last_id >= 0

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.169, 0.145, 0.376, 0.85) if highlight \
		else Color(0.11, 0.098, 0.243, 0.55)
	style.border_color = Color(0.133, 0.827, 0.933, 0.75) if highlight \
		else Color(0.486, 0.424, 0.941, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
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
		Color(1, 0.83, 0.32) if rank <= 3 else Color(0.651, 0.635, 0.8))
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(rank_label)

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
	var level := String(entry.get("level", ""))
	lines_label.text = "%d lines" % int(entry["lines"]) if level.is_empty() \
		else "%d lines  ·  %s" % [int(entry["lines"]), level]
	lines_label.add_theme_font_size_override("font_size", 26)
	lines_label.add_theme_color_override("font_color", Color(0.651, 0.635, 0.8))
	lines_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(lines_label)

	var date_label := Label.new()
	date_label.text = Scores.format_date(int(entry["date"]))
	date_label.add_theme_font_size_override("font_size", 24)
	date_label.add_theme_color_override("font_color", Color(0.651, 0.635, 0.8, 0.7))
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
