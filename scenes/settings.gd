extends "res://scripts/menu_screen.gd"
## Settings, laid out as the design's card rows.
##
## Three row shapes, all from the mockups:
##   * a switch row  -- label on the left, sliding toggle on the right
##   * a slider row  -- label above a row of discrete segments
##   * a note card   -- read-only copy
##
## The theme is deliberately absent: it is a build-time choice (see
## `Themes.ACTIVE`), not a user setting.
##
## Difficulty is not listed as an option on purpose: it follows the score
## during a run rather than being chosen up front. It is shown as a read-only
## card so the ramp still reads as design rather than bad luck.

const Haptics := preload("res://scripts/haptics.gd")
const ToggleSwitch := preload("res://scripts/toggle_switch.gd")
const SegmentSlider := preload("res://scripts/segment_slider.gd")

## Label sizes are the design's, doubled twice: the mockups are 2x of the
## 270x480 screen and the game runs at 4x.
const ROW_FONT := 30
const NOTE_FONT := 26

var _rows: Dictionary = {}


func _ready() -> void:
	super()
	_build_rows()
	%Footer.text = "%s v%s\n%dx%d  ·  NEAREST FILTER" % [
		App.game_name.to_upper(), App.game_version,
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920),
	]
	Themes.theme_changed.connect(func(_id: int) -> void: _sync())
	_sync()


func _build_rows() -> void:
	for child in %Rows.get_children():
		child.queue_free()
	_rows.clear()
	# Toggles first, then the volume card -- the design's grouping.
	_rows["music"] = _switch_row("MUSIC", Audio.music_on,
		func(on: bool) -> void: Audio.music_on = on)
	_rows["sound"] = _switch_row("SOUND", Audio.sound_on, _set_sound)
	_rows["volume"] = _slider_row("MUSIC VOLUME", Audio.music_volume,
		func(v: float) -> void: Audio.music_volume = v)
	_rows["grid"] = _switch_row("GRID LINES", Themes.grid_lines(),
		func(on: bool) -> void: Themes.set_grid_lines(on))
	_rows["haptics"] = _switch_row("HAPTICS", Haptics.is_enabled(), _set_haptics)
	_rows["difficulty"] = _note_row("DIFFICULTY  ·  FOLLOWS YOUR SCORE",
		_difficulty_summary())


## A card with a label and a control on the right.
func _card(label: String) -> Array:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	%Rows.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	card.add_child(row)
	var text := Label.new()
	text.text = label
	text.add_theme_font_size_override("font_size", ROW_FONT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	return [card, row]


func _switch_row(label: String, on: bool, changed: Callable) -> Dictionary:
	var parts := _card(label)
	var sw := ToggleSwitch.new()
	sw.set_silent(on)
	sw.toggled.connect(changed)
	(parts[1] as HBoxContainer).add_child(sw)
	return {"card": parts[0], "switch": sw}


func _value_row(label: String, tapped: Callable) -> Dictionary:
	var parts := _card(label)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", ROW_FONT)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.theme_type_variation = &"AccentLabel"
	(parts[1] as HBoxContainer).add_child(value)
	# The whole card is the target, matching the design's `cursor:pointer`.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(tapped)
	(parts[0] as PanelContainer).add_child(hit)
	return {"card": parts[0], "value": value}


func _slider_row(label: String, start: float, changed: Callable) -> Dictionary:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	%Rows.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 28)
	card.add_child(col)
	var text := Label.new()
	text.text = label
	text.add_theme_font_size_override("font_size", ROW_FONT)
	col.add_child(text)
	var slider := SegmentSlider.new()
	slider.set_silent(start)
	slider.value_changed.connect(changed)
	col.add_child(slider)
	return {"card": card, "slider": slider}


func _note_row(title: String, body: String) -> Dictionary:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	%Rows.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", NOTE_FONT)
	head.theme_type_variation = &"AccentLabel"
	col.add_child(head)
	var note := Label.new()
	note.text = body
	note.add_theme_font_size_override("font_size", NOTE_FONT)
	note.theme_type_variation = &"MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	return {"card": card}


func _sync() -> void:
	(_rows["music"]["switch"] as BaseButton).set_pressed_no_signal(Audio.music_on)
	(_rows["sound"]["switch"] as BaseButton).set_pressed_no_signal(Audio.sound_on)
	(_rows["volume"]["slider"] as Control).set_silent(Audio.music_volume)
	(_rows["grid"]["switch"] as BaseButton).set_pressed_no_signal(Themes.grid_lines())
	(_rows["haptics"]["switch"] as BaseButton).set_pressed_no_signal(Haptics.is_enabled())


## Playing a sample on enable is the only way to hear what was just switched
## on without leaving the screen.
func _set_sound(on: bool) -> void:
	Audio.sound_on = on
	if on:
		Audio.play("tap")


## Haptics owns the preference and persists it itself, so the choice sticks
## across launches whether or not this screen is opened again.
func _set_haptics(on: bool) -> void:
	Haptics.set_enabled(on)
	if on:
		Haptics.place()          # a sample of what was just switched on


## Spells out the ramp so the tightening deal reads as design, not bad luck.
func _difficulty_summary() -> String:
	var lines: Array[String] = []
	for level: int in Difficulty.BANDS:
		var from: int = Difficulty.threshold_of(level)
		var head: String = "from 0" if from == 0 else "from %d points" % from
		lines.append("%s  (%s)\n    %s"
			% [Difficulty.name_of(level), head, Difficulty.blurb_of(level)])
	return "\n".join(lines)
