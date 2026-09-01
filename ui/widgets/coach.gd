extends RefCounted
class_name Coach
## Teaches the game one line at a time, in the hint label that already exists.
##
## Deliberately NOT a walkthrough. `game.gd` owns all pointer handling and is
## already large; a scripted tutorial would have to block input, gate what is
## tappable and unwind on pause, restart and game over -- a second modal input
## state, which the loadout being a pre-run decision exists to avoid. So this is
## passive: it picks the most urgent thing the player has not been told yet,
## says it once, and gets out of the way.
##
## The ladder is a TABLE, like POWER_ATMOSPHERE and Modes.DEFS. Adding a lesson
## should be one row, not one branch.
##
## Pure with respect to the scene: `pick()` takes a snapshot dictionary and
## returns a row, so the whole ladder is testable without instantiating
## anything.

## What the tray says once there is nothing left to teach.
const RESTING := "drag a card onto the board  ·  fill a row or column to clear it"

## Ordered most urgent first; the first row whose `when` holds and whose `id`
## is unseen wins. Ids are persisted, so they must never be renumbered -- add
## new rows with new numbers rather than inserting.
##
## Keep every line to about eight words: the label is one autowrapping line
## under the tray, the board is width-limited at 1048 of 1080px, and Sprint has
## no vertical slack, so there is nowhere for a second line to go.
const LADDER := [
	{"id": 1, "when": "first_run",      "text": "drag a card onto the board"},
	# The bomb rungs sit ABOVE the evergreen lessons on purpose. The free bomb
	# is a transient offer sitting on screen right now, where "fill a row or
	# column" keeps. It matters for players whose save predates the coach:
	# every rung is unseen for them, and without this they would be told to
	# fill a row while a free bomb went unexplained beside the tray.
	{"id": 6, "when": "bomb_offered",   "text": "a free bomb  ·  drag it onto the board"},
	{"id": 7, "when": "bomb_spent",     "text": "that one was free  ·  powers cost charge"},
	{"id": 2, "when": "placed_one",     "text": "fill a row or column to clear it"},
	{"id": 3, "when": "card_dimmed",    "text": "greyed cards fit nowhere  ·  plan around them"},
	{"id": 4, "when": "cleared_one",    "text": "clear again next turn to build a combo"},
	{"id": 5, "when": "combo_two",      "text": "two lines at once scores 4x two singles"},
	{"id": 8, "when": "unlock_waiting", "text": "you earned a power  ·  choose it on Profile"},
	{"id": 9, "when": "short_charge",   "text": "combos charge your powers  ·  2x and up"},
	{"id": 10, "when": "rescue",        "text": "a charged power can save a stuck board"},
	{"id": 11, "when": "ran_once",      "text": "every run banks XP  ·  win or lose"},
]


## The line to show for this state, or RESTING when there is nothing left.
## `state` carries one bool per `when` key above.
static func pick(state: Dictionary) -> Dictionary:
	for row: Dictionary in LADDER:
		var id := int(row["id"])
		if not bool(state.get(row["when"], false)):
			continue
		if Progress.hint_seen(id):
			continue
		return row
	return {}


## Picks the line to show, and retires the PREVIOUS one if we have moved on.
##
## Retiring on display was wrong: the caller refreshes on every placement, so a
## rung was marked seen the instant it appeared and replaced a moment later --
## "a free bomb, drag it onto the board" vanished before the player had touched
## the bomb. A rung now persists while its condition holds, and is only retired
## once something else takes its place.
##
## Returns `{id, text}`; pass the previous `id` back in on the next call.
static func advise(state: Dictionary, last_id := 0) -> Dictionary:
	var row := pick(state)
	var id := int(row.get("id", 0))
	if last_id > 0 and id != last_id:
		Progress.mark_hint_seen(last_id)
	return {"id": id, "text": String(row.get("text", RESTING))}
