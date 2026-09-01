extends "res://scripts/menu_screen.gd"
## The player's progression: level, lifetime score, streak, and the five powers
## with their levels.
##
## This is also where the loadout is chosen, deliberately: it keeps equipping a
## pre-run decision, so `game.gd` never grows a second modal input state.
##
## One tap does the obvious thing for the card's state -- a locked power with an
## unlock banked gets unlocked, an owned one toggles in and out of the loadout.

const Blocks := preload("res://scripts/blocks.gd")
const PieceView := preload("res://scripts/piece_view.gd")

const NAME_FONT := 32
const BLURB_FONT := 26
const ICON := 96


func _ready() -> void:
	super()
	Progress.level_changed.connect(func(_l: int, _p: int) -> void: _rebuild())
	Progress.loadout_changed.connect(_rebuild)
	Progress.power_level_changed.connect(func(_p: int, _l: int) -> void: _rebuild())
	%ResetButton.pressed.connect(_confirm_reset)
	_rebuild()


func _rebuild() -> void:
	var level := Progress.level()
	%LevelLabel.text = "LEVEL %d" % level
	var to_next := Progress.threshold(level + 1)
	%XpLabel.text = "%s / %s" % [Progress.commas(Progress.total_score()), Progress.commas(to_next)]
	%XpFill.scale.x = Progress.level_progress()
	%Stats.text = "%s lifetime  ·  %d day streak  ·  %d days played" % [
		Progress.commas(Progress.total_score()), Progress.streak(), Progress.days_played(),
	]

	var pending := Progress.pending_unlocks()
	if pending > 0:
		%Hint.text = "Choose %d new power" % pending if pending == 1 \
			else "Choose %d new powers" % pending
	elif Progress.unlocked().is_empty():
		%Hint.text = "Score 1,000 to earn your first power."
	else:
		%Hint.text = "Tap a power to equip it. %d of %d slots." % [
			_equipped_count(), Progress.loadout_size()]
	%Hint.visible = not %Hint.text.is_empty()
	%ResetButton.visible = Progress.has_progress()

	for child in %Powers.get_children():
		child.queue_free()
	for power: int in Blocks.ALL_POWERS:
		_card(power, pending)


func _equipped_count() -> int:
	var n := 0
	for p: int in Progress.loadout():
		if p != Blocks.Power.NONE:
			n += 1
	return n


func _card(power: int, pending: int) -> void:
	var owned := Progress.is_unlocked(power)
	var equipped := Progress.loadout().has(power)

	var card := PanelContainer.new()
	card.theme_type_variation = &"ModeCardFeatured" if equipped else &"ModeCard"
	%Powers.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	card.add_child(row)

	# The tile renders itself from the piece, exactly as the tray and strip do.
	var icon := PieceView.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.piece = Blocks.power_piece(power)
	icon.dimmed = not owned
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)

	var name_label := Label.new()
	name_label.text = Blocks.power_name(power).trim_suffix("!")
	name_label.add_theme_font_size_override("font_size", NAME_FONT)
	name_label.theme_type_variation = &"TitleLabel"
	if equipped:
		# The featured card sits on a light tile, so both lines go dark --
		# a cream title above dark body text reads as two different states.
		name_label.add_theme_color_override("font_color",
			Themes.value("ink", Color.BLACK))
	col.add_child(name_label)

	var blurb := Label.new()
	blurb.add_theme_font_size_override("font_size", BLURB_FONT)
	blurb.theme_type_variation = &"MutedLabel"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not owned:
		blurb.text = "Locked" if pending <= 0 else "Tap to unlock"
	else:
		var lv := Progress.level_of(power)
		var uses := Progress.uses_of(power)
		if lv >= Progress.MAX_POWER_LEVEL:
			blurb.text = "Level %d  ·  maxed  ·  %d uses" % [lv, uses]
		else:
			var need: int = Progress.USES_FOR_LEVEL[lv]
			blurb.text = "Level %d  ·  %d/%d uses to level  ·  costs %d" % [
				lv, uses, need, Progress.cost_of(power)]
	if equipped:
		blurb.add_theme_color_override("font_color", Themes.value("ink", Color.BLACK))
	col.add_child(blurb)

	# Whole card is the target, matching the mode picker.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(_tapped.bind(power))
	card.add_child(hit)


## One tap, whatever the card needs: unlock it, or move it in or out of the
## loadout.
func _tapped(power: int) -> void:
	if not Progress.is_unlocked(power):
		Progress.unlock(power)      # no-op without a banked unlock
		return
	var slot := Progress.loadout().find(power)
	if slot >= 0:
		Progress.equip(slot, Blocks.Power.NONE)
		return
	var free := Progress.loadout().find(Blocks.Power.NONE)
	if free < 0 and Progress.loadout().size() < Progress.loadout_size():
		free = Progress.loadout().size()
	if free < 0:
		# Every slot is taken; replace the first so a tap is never inert.
		free = 0
	Progress.equip(free, power)


## Two taps to wipe, matching the leaderboard's Clear scores. Everything goes:
## level, powers, their levels, charge and unlocked themes -- so it asks twice
## and says so plainly rather than hiding behind the word "reset".
func _confirm_reset() -> void:
	if %ResetButton.text.begins_with("Reset"):
		%ResetButton.text = "Tap again to erase all progress"
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(self) and is_inside_tree():
			%ResetButton.text = "Reset level"
		return
	Progress.wipe()
	# An unlocked theme may have just been revoked; fall back to the shipped one.
	if not Progress.is_theme_unlocked(Themes.current()):
		Themes.set_current(Themes.ACTIVE)
	%ResetButton.text = "Reset level"
	_rebuild()


