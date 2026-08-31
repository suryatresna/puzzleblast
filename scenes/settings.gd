extends "res://scripts/menu_screen.gd"
## Settings. Difficulty is not listed here on purpose -- it follows the score
## during a run rather than being chosen up front.

const Haptics := preload("res://scripts/haptics.gd")


func _ready() -> void:
	super()
	%VibrateButton.pressed.connect(_toggle_vibrate)
	_sync_vibrate()
	%DifficultyNote.text = _difficulty_summary()


## Spells out the ramp so the tightening deal reads as design, not bad luck.
func _difficulty_summary() -> String:
	var lines: Array[String] = []
	for level: int in Difficulty.BANDS:
		var from: int = Difficulty.threshold_of(level)
		var head: String = "from 0" if from == 0 else "from %d points" % from
		lines.append("%s  (%s)\n    %s"
			% [Difficulty.name_of(level), head, Difficulty.blurb_of(level)])
	return "\n".join(lines)


## Haptics owns the preference and persists it itself, so the choice sticks
## across launches whether or not this screen is ever opened again.
func _toggle_vibrate() -> void:
	Haptics.set_enabled(not Haptics.is_enabled())
	if Haptics.is_enabled():
		Haptics.place()          # a sample of what was just switched on
	_sync_vibrate()


func _sync_vibrate() -> void:
	%VibrateButton.text = "Vibration:  %s" % ("On" if Haptics.is_enabled() else "Off")
