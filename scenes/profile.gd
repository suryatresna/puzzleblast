extends MenuScreen
## The player's progression: level, lifetime score, streak, and the power skill
## tree with each power's level.
##
## The powers are laid out as a tree, not a list: `Progress.POWER_TIERS` orders
## them weakest to strongest and seals each tier behind an account level, so
## the order the player meets them in is fixed even though which of a tier's
## two they take is their own choice.
##
## This is also where the loadout is chosen, deliberately: it keeps equipping a
## pre-run decision, so `game.gd` never grows a second modal input state.
##
## One tap does the obvious thing for the card's state -- a locked power with an
## unlock banked gets unlocked, an owned one toggles in and out of the loadout.

const PieceView := preload("res://ui/widgets/piece_view.gd")

const NAME_FONT := 32
const BLURB_FONT := 26
const TIER_FONT := 28
const ICON := 96

## Pixels of travel that separate a tap from a scroll, at 1080px wide.
const TAP_SLOP := 18

var _xp_tween: Tween


func _ready() -> void:
	super()
	# A finger has to travel this far before the list scrolls rather than the
	# card under it being tapped. Without it, the wobble in a tap would nudge
	# the tree and a card release would still land, so a tap would both scroll
	# and equip.
	%Scroll.scroll_deadzone = TAP_SLOP
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
	_animate_xp()
	%Stats.text = "%s lifetime  ·  %d day streak  ·  %d days played" % [
		Progress.commas(Progress.total_score()), Progress.streak(), Progress.days_played(),
	]

	var pending := Progress.pending_unlocks()
	var choosable: int = Progress.available_to_unlock().size()
	if pending > 0 and choosable > 0:
		%Hint.text = "Choose %d new power" % pending if pending == 1 \
			else "Choose %d new powers" % pending
	elif pending > 0:
		# Unlocks in the bank with every open tier already taken. Saying so
		# beats an unexplained "Choose 1" above nothing tappable.
		%Hint.text = "%d unlock waiting  ·  reach the next tier to spend it" % pending \
			if pending == 1 else "%d unlocks waiting  ·  reach the next tier" % pending
	elif Progress.unlocked().is_empty():
		%Hint.text = "Score 1,000 to earn your first power."
	else:
		%Hint.text = "Tap a power to equip it. %d of %d slots." % [
			_equipped_count(), Progress.loadout_size()]
	%Hint.visible = not %Hint.text.is_empty()
	%ResetButton.visible = Progress.has_progress()

	for child in %Powers.get_children():
		child.queue_free()
	# The tree, tier by tier. Powers are not listed in enum order any more:
	# the table IS the order, weakest tier first, so the list reads as the path
	# the player walks rather than as a bag of ten things.
	for i in Progress.POWER_TIERS.size():
		var tier: Dictionary = Progress.POWER_TIERS[i]
		var gate := int(tier["level"])
		var open := level >= gate
		_tier_header(i + 1, gate, open, tier["powers"])
		for power: int in tier["powers"]:
			_card(power, pending, open, gate)


## The XP bar. Normally it just eases to its value; if the player has levelled
## since they last looked, it fills to the top, snaps back to empty and eases
## into the new level -- so the roll-over is the thing they see, not a bar that
## was already where it ended up.
func _animate_xp() -> void:
	if _xp_tween and _xp_tween.is_valid():
		_xp_tween.kill()
	var target := Progress.level_progress()
	var levelled := Progress.has_unseen_level()
	%XpFill.scale.x = 0.0
	_xp_tween = create_tween()
	if levelled:
		var gained: int = Progress.level() - Progress.seen_level()
		# One fill-and-reset per level crossed, capped so a huge jump does not
		# hold the screen for ten seconds.
		for i in mini(gained, 3):
			_xp_tween.tween_property(%XpFill, "scale:x", 1.0, 0.45) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			_xp_tween.tween_property(%XpFill, "scale:x", 0.0, 0.10)
		_xp_tween.tween_callback(_flash_level)
	_xp_tween.tween_property(%XpFill, "scale:x", target, 0.55) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if levelled:
		Progress.mark_level_seen()


## A short punch on the level number as the bar rolls over.
func _flash_level() -> void:
	var label: Label = %LevelLabel
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * 1.35
	label.add_theme_color_override("font_color", Themes.text_color("highlight"))
	var punch := create_tween()
	punch.tween_property(label, "scale", Vector2.ONE, 0.45) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	punch.tween_callback(func() -> void: label.remove_theme_color_override("font_color"))


func _equipped_count() -> int:
	var n := 0
	for p: int in Progress.loadout():
		if p != Blocks.Power.NONE:
			n += 1
	return n


## The band above each tier's powers: what it is, and what opens it. Sealed
## tiers say the level rather than just greying out, so the tree reads as a
## path with a price on each step.
func _tier_header(index: int, gate: int, open: bool, powers: Array) -> void:
	var owned := 0
	for p: int in powers:
		if Progress.is_unlocked(p):
			owned += 1

	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", 12)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Powers.add_child(band)

	var title := Label.new()
	title.text = "TIER %d" % index
	title.add_theme_font_size_override("font_size", TIER_FONT)
	title.theme_type_variation = &"TitleLabel" if open else &"FaintLabel"
	band.add_child(title)

	var note := Label.new()
	note.add_theme_font_size_override("font_size", BLURB_FONT)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not open:
		note.text = "Locked  ·  reach level %d" % gate
		note.theme_type_variation = &"DangerLabel"
	elif owned == powers.size():
		note.text = "%d of %d taken" % [owned, powers.size()]
		note.theme_type_variation = &"FaintLabel"
	else:
		note.text = "%d of %d taken" % [owned, powers.size()]
		note.theme_type_variation = &"MutedLabel"
	band.add_child(note)


func _card(power: int, pending: int, tier_open := true, gate := 1) -> void:
	var owned := Progress.is_unlocked(power)
	var equipped := Progress.loadout().has(power)

	var card := PanelContainer.new()
	card.theme_type_variation = &"ModeCardFeatured" if equipped else &"ModeCard"
	# PanelContainer defaults to STOP, and STOP anywhere between the touch and
	# the ScrollContainer breaks the scroll -- see the hit target below.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	%Powers.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	card.add_child(row)

	# The tile renders itself from the piece, exactly as the tray and strip do.
	var icon := PieceView.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE   # decoration, not a target
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
	if not tier_open:
		blurb.text = "Needs level %d  ·  costs %d" % [gate, Progress.cost_of(power)]
	elif not owned:
		blurb.text = "Tap to unlock  ·  costs %d" % Progress.cost_of(power) \
			if pending > 0 else "Locked  ·  costs %d" % Progress.cost_of(power)
	else:
		var lv := Progress.level_of(power)
		var uses := Progress.uses_of(power)
		if lv >= Progress.max_level_of(power):
			blurb.text = "Level %d of %d  ·  maxed  ·  %d uses" % [
				lv, Progress.max_level_of(power), uses]
		else:
			var need: int = Progress.USES_FOR_LEVEL[lv]
			blurb.text = "Level %d of %d  ·  %d/%d uses to level  ·  costs %d" % [
				lv, Progress.max_level_of(power), uses, need, Progress.cost_of(power)]
	if equipped:
		blurb.add_theme_color_override("font_color", Themes.value("ink", Color.BLACK))
	col.add_child(blurb)

	# Whole card is the target, matching the mode picker.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	# PASS, not the Button default of STOP. STOP means "do not propagate to my
	# parent" -- so a touch landing on a card never reached the ScrollContainer
	# above it, and since the cards tile the whole list there was nowhere left
	# to grab. The screen simply would not scroll on a phone. PASS keeps the
	# button clickable and lets the same touch drive the scroll.
	hit.mouse_filter = Control.MOUSE_FILTER_PASS
	hit.pressed.connect(_tapped.bind(power))
	card.add_child(hit)


## One tap, whatever the card needs: unlock it, or move it in or out of the
## loadout.
func _tapped(power: int) -> void:
	if not Progress.is_unlocked(power):
		if not Progress.is_tier_open(power):
			# Silence here reads as a broken button, so the hint answers.
			%Hint.text = "%s unlocks at level %d  ·  you are level %d" % [
				Blocks.power_name(power).trim_suffix("!"),
				Progress.tier_level(power), Progress.level()]
			%Hint.show()
			return
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


