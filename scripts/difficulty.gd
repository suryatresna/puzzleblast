extends Node
##==============================================================================
## DIFFICULTY TUNING
##
## Everything governing how hard the game gets lives in BANDS below. Nothing
## else in the project holds a difficulty number, so this table is the only
## file to touch when rebalancing.
##
## The player never picks a level. A run opens on the first band and moves up
## as the score passes each threshold, so difficulty tracks how well the run is
## actually going. It only ever tightens: clearing the board drops the stack but
## not the score, and a band is never handed back.
##
## Only bomb supply and the shape of the deal change between bands. The board
## size, the rules and the scoring are identical throughout, so a high score
## always means the player survived the tight end of the curve.
##------------------------------------------------------------------------------
## THE KNOBS
##
##   from_score  int    Score at which this band takes over. The first band
##                      must be 0, and values must increase down the table.
##                      These are raw score values -- see POINTS_PER_CELL,
##                      LINE_BASE and BOMB_POINTS_PER_CELL in board.gd for what
##                      a point is worth, since retuning those shifts every
##                      threshold here.
##
##   tray_special float 0.0-1.0. Chance a freshly dealt hand contains a special.
##                      Which one -- bomb, collapse, laser or fit -- is drawn at
##                      random with equal odds. Rolled once per refill, never
##                      per card, so a hand never holds more than one.
##                      0.0 means this band deals no specials at all.
##                      At 0.55 a special turns up in a little over half of
##                      hands; at 0.15, about one hand in seven.
##
##   combo_power int    Streak length that earns a special. Which one is drawn
##                      at random from all four, so a streak may pay out a
##                      bomb, a collapse, a laser or a fit.
##                        1 = any line clear
##                        3 = only a STRIKE!! streak
##                        0 = this band never grants one
##                      Awarded once per streak however long the streak runs,
##                      and never while an unused special is still in hand.
##
##   small_bias  float  Multiplier on the spawn weight of 1- and 2-cell pieces.
##                      1.0 leaves the deal untouched. 2.6 takes small pieces
##                      from about 9% of the deal to about 21%.
##
## To retune: edit the numbers. To add a band: add a Level entry and a matching
## row, in ascending score order. _ready() validates the table on startup and
## pushes a clear error if it is inconsistent, rather than failing quietly.
##==============================================================================

enum Level { EASY, MEDIUM, HARD, SUPER_HARD }

const BANDS := {
	Level.EASY: {
		"name": "Easy",
		"blurb": "Bombs are common and the deal favours small pieces.",
		"from_score": 0,
		"tray_special": 0.55,
		"combo_power": 1,
		"small_bias": 2.6,
	},
	Level.MEDIUM: {
		"name": "Medium",
		"blurb": "A bomb whenever you clear a line.",
		"from_score": 800,
		"tray_special": 0.24,
		"combo_power": 1,
		"small_bias": 1.0,
	},
	Level.HARD: {
		"name": "Hard",
		"blurb": "A bomb only when you reach a STRIKE!! streak.",
		"from_score": 2500,
		"tray_special": 0.55,
		"combo_power": 3,
		"small_bias": 1.0,
	},
	Level.SUPER_HARD: {
		"name": "Super Hard",
		"blurb": "Super rare bombs. Nothing but the board and the deal.",
		"from_score": 6000,
		"tray_special": 0.15,
		"combo_power": 5,
		"small_bias": 1.0,
	},
}

##==============================================================================
## Runtime state. Nothing below needs editing to rebalance the game.
##==============================================================================

## Fires when a run crosses into a tighter band, so the game can call it out.
signal tightened(level: Level)

var current: Level = Level.EASY
## Hardest band this run has reached; recorded on the leaderboard.
var peak: Level = Level.EASY


func _ready() -> void:
	validate()


## The band a given score falls in.
static func for_score(score: int) -> Level:
	var level: Level = Level.EASY
	# Dictionary keys come back as plain ints, hence the explicit cast.
	for candidate: int in BANDS:
		if score >= int(BANDS[candidate]["from_score"]):
			level = candidate as Level
	return level


static func name_of(level: Level) -> String:
	return String(BANDS[level]["name"])


static func blurb_of(level: Level) -> String:
	return String(BANDS[level]["blurb"])


static func threshold_of(level: Level) -> int:
	return int(BANDS[level]["from_score"])


## Called as the score moves. Difficulty only ever tightens within a run.
func update(score: int) -> void:
	var next: Level = for_score(score)
	if next <= current:
		return
	current = next
	peak = next
	tightened.emit(current)


func reset() -> void:
	current = Level.EASY
	peak = Level.EASY


func band() -> Dictionary:
	return BANDS[current]


func level_name() -> String:
	return name_of(current)


func peak_name() -> String:
	return name_of(peak)


func tray_special_chance() -> float:
	return float(band()["tray_special"])


## Streak length that earns a bomb, or 0 when this band never grants one.
func combo_power_threshold() -> int:
	return int(band()["combo_power"])


func small_piece_bias() -> float:
	return float(band()["small_bias"])


## Score at which the next band begins, or 0 when already at the last one.
func next_threshold() -> int:
	var levels: Array = BANDS.keys()
	var i: int = levels.find(current)
	if i < 0 or i + 1 >= levels.size():
		return 0
	return int(BANDS[levels[i + 1]]["from_score"])


## Checks the table is coherent. Returns the problems found, empty when fine.
## A bad edit here would otherwise show up as strange pacing hours later.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var levels: Array = BANDS.keys()

	for level: int in Level.values():
		if not BANDS.has(level):
			problems.append("Level %d has no BANDS row" % level)

	if not levels.is_empty() and int(BANDS[levels[0]]["from_score"]) != 0:
		problems.append("the first band must start at score 0")

	var previous := -1
	for level: int in levels:
		var row: Dictionary = BANDS[level]
		var label := String(row.get("name", "?"))

		var from := int(row["from_score"])
		if from <= previous:
			problems.append("%s: from_score %d must be greater than %d"
				% [label, from, previous])
		previous = from

		var chance := float(row["tray_special"])
		if chance < 0.0 or chance > 1.0:
			problems.append("%s: tray_special %.2f is outside 0.0-1.0" % [label, chance])

		if int(row["combo_power"]) < 0:
			problems.append("%s: combo_power cannot be negative" % label)

		if float(row["small_bias"]) <= 0.0:
			problems.append("%s: small_bias must be above 0" % label)

	for problem in problems:
		push_error("Difficulty config: " + problem)
	return problems
