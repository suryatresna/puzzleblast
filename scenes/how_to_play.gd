extends MenuScreen
## The reference the coach does not have room for.
##
## `ui/widgets/coach.gd` teaches one line at a time, when each thing first
## matters. That is right for first contact but it can never lay out the whole
## picture, because it lives in a single line under the tray. This screen is
## where the picture goes: the scoring maths, what charge is, what the powers
## do, how levels work.
##
## Rows are built from a table rather than laid out in the .tscn, the way
## settings.gd does it -- they are repetitive, and a section is then one entry
## rather than a dozen nodes.

const HEAD_FONT := 30
const BODY_FONT := 26
const GAP := 10

## Section title, then its lines. Kept here rather than in the scene so the copy
## reads as prose while editing, which is how it will be read on screen.
const SECTIONS := [
	{"head": "Placing", "lines": [
		"Drag a card from the tray onto the board.",
		"The piece is drawn above your finger so your thumb does not cover it.",
		"A ghost shows where it lands — white fits, red does not.",
		"Pieces never rotate. What you see is what you place.",
	]},
	{"head": "Clearing", "lines": [
		"Any full row or column disappears.",
		"One piece can complete several lines at once.",
		"Cards that fit nowhere are greyed out, so you can see trouble coming.",
	]},
	{"head": "Scoring", "lines": [
		"Placing a piece:  1 point per cell.",
		"Clearing lines:  100 × lines² × combo.",
		"Two lines at once scores 400, where two separate clears score 200.",
		"Combo builds on consecutive clears and resets when you place without one.",
		"It caps at ×5.",
	]},
	{"head": "Powers", "lines": [
		"Powers sit in the strip above the tray, and drag onto the board like cards.",
		"Each costs charge, and charge comes from combos of two or more.",
		"A charged power can rescue a board where nothing fits — the run is not over.",
		"Your first bomb is free, to show you what a power does.",
	]},
	{"head": "Levels", "lines": [
		"Every run banks its score as XP, win or lose.",
		"Levels unlock powers, which you choose on the Profile screen.",
		"Powers level up themselves, by being used.",
		"Play three days running, or three times in a day, to earn a double-XP run.",
	]},
	{"head": "Modes", "lines": [
		"Palette — the endless run. The board grows at level 25.",
		"Big Palette — the same rules, on a larger board from the start.",
		"Sprint — sixty seconds.",
		"Puzzle — a set board with a target. Powers are disabled.",
	]},
]


func _ready() -> void:
	super()
	%Title.text = "How to play"
	for section: Dictionary in SECTIONS:
		_section(String(section["head"]), section["lines"])


func _section(head: String, lines: Array) -> void:
	var title := Label.new()
	title.text = head.to_upper()
	title.add_theme_font_size_override("font_size", HEAD_FONT)
	title.theme_type_variation = &"AccentLabel"
	%Body.add_child(title)

	for line: String in lines:
		var row := Label.new()
		row.text = line
		row.add_theme_font_size_override("font_size", BODY_FONT)
		row.theme_type_variation = &"MutedLabel"
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		%Body.add_child(row)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, GAP)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Body.add_child(gap)
