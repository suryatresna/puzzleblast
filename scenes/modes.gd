extends "res://scripts/menu_screen.gd"
## The mode picker, laid out as the design's cards.
##
## Cards are built from `Modes.DEFS` rather than placed in the scene, so adding
## a mode is a table entry. Tapping one sets it as current and starts a run --
## the picker is the only place `Modes.current` is written.

const ModeIcon := preload("res://scripts/mode_icon.gd")

const TITLE_FONT := 38
const BLURB_FONT := 30


func _ready() -> void:
	super()
	_build()
	Modes.solved_changed.connect(_build)


func _build() -> void:
	for child in %Cards.get_children():
		child.queue_free()
	for id: int in Modes.ids():
		_card(id)


func _card(id: int) -> void:
	var d: Dictionary = Modes.data(id)
	var card := PanelContainer.new()
	card.theme_type_variation = \
		&"ModeCardFeatured" if bool(d.get("featured", false)) else &"ModeCard"
	%Cards.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	card.add_child(row)

	var icon := ModeIcon.new()
	icon.kind = String(d["icon"])
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)

	var title := Label.new()
	title.text = Modes.mode_name(id)
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	# The featured card sits on the accent colour, so its text flips to paper.
	title.theme_type_variation = \
		&"TitleLabel" if not bool(d.get("featured", false)) else &"FaintLabel"
	if bool(d.get("featured", false)):
		title.add_theme_color_override("font_color", Themes.value("knob", Color.WHITE))
	col.add_child(title)

	var blurb := Label.new()
	blurb.text = Modes.blurb(id)
	blurb.add_theme_font_size_override("font_size", BLURB_FONT)
	blurb.theme_type_variation = &"MutedLabel"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bool(d.get("featured", false)):
		blurb.add_theme_color_override("font_color",
			Themes.value("ink", Color.BLACK))
	col.add_child(blurb)

	# The whole card is the target, matching the design's `cursor:pointer`.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(_start.bind(id))
	card.add_child(hit)


func _start(id: int) -> void:
	Modes.set_current(id)
	if id == Modes.Id.PUZZLE:
		Modes.puzzle_level = Modes.next_unsolved()
	App.goto_scene(App.SCENE_GAME)
