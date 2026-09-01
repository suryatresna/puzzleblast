extends Node
## Apple Game Center. Autoloaded as `GameServices`.
##
## Godot 4 has no built-in Game Center module -- it moved out of the engine
## after 3.x -- so this binds at runtime to the `GameCenter` singleton provided
## by the godot-ios-plugins build. See `docs/gamecenter.md` for installing it
## and for the App Store Connect side.
##
## Everything here is guarded twice: the platform must be iOS, and the
## singleton must actually be present. On desktop, Android, in the editor, or
## on an iOS build without the plugin, every call is a silent no-op and the
## local leaderboard carries on as the source of truth. Nothing in the game
## should ever depend on Game Center succeeding.

signal authentication_changed(ok: bool)

const ModesScript := preload("res://autoload/modes.gd")

const SINGLETON := "GameCenter"

## Leaderboard IDs, one per mode. These must match the identifiers created in
## App Store Connect exactly -- a mismatch fails silently on Apple's side.
##
## Reverse-DNS on the bundle id, which is Apple's convention: leaderboard ids
## are unique across the whole account rather than per app, and they cannot be
## renamed once created -- a new id means starting the board's scores over.
const LEADERBOARDS := {
	ModesScript.Id.PALETTE: "com.suryatresna.pixelblast.palette",
	ModesScript.Id.SPRINT: "com.suryatresna.pixelblast.sprint",
	ModesScript.Id.PUZZLE: "com.suryatresna.pixelblast.puzzle",
}

## Sign-in cannot be requested from `_ready()`. The plugin needs the app's
## root view controller:
##
##     root_controller = [[UIApplication sharedApplication] delegate].window.rootViewController;
##     ERR_FAIL_COND_V(!root_controller, FAILED);
##
## and UIKit has not built the window that early, so the call returns FAILED
## and no handler is ever installed. The first attempt is therefore deferred a
## little and retried until it is accepted.
const AUTH_FIRST_DELAY := 0.5
const AUTH_RETRY_DELAY := 1.0
const AUTH_MAX_ATTEMPTS := 15

## GKError codes worth naming, from Apple's GKErrorCodes. The distinction that
## matters is whether retrying could ever help.
const GK_ERRORS := {
	1: "unknown error",
	2: "cancelled by the player",
	3: "cannot reach Game Center servers",
	4: "the player denied access",
	5: "invalid credentials",
	6: "not authenticated",
	7: "authentication already in progress",
	8: "invalid player",
	15: "this app is not recognised by Game Center",
	16: "Game Center is not supported here",
}

## Codes that are worth another attempt later. Everything else is a decision
## (cancelled, denied) or a misconfiguration (unrecognised app), where retrying
## only pesters the player or spams the log.
const GK_RETRYABLE := [1, 3, 7]

## How long to wait before retrying a transient server failure. Apple's sandbox
## fails this way often enough that giving up on the first one is wrong.
const AUTH_RECOVER_DELAY := 30.0
const AUTH_MAX_RECOVERIES := 4

## Scores that finished before sign-in completed. Authentication is async and a
## run can end during it, so submissions are held rather than dropped.
const MAX_PENDING := 16

var authenticated := false
## The signed-in player's name, as Apple wants it shown. Empty when signed out.
## This is text from another user's account, so it is only ever put in a plain
## Label -- never BBCode, where it could carry markup.
var player_name := ""
## Why the last sign-in attempt failed, for diagnosing a device that will not
## authenticate. Empty when things are working.
var last_error := ""

var _gc: Object = null
var _pending: Array = []
## True once authenticate() has been ACCEPTED -- not once it has succeeded.
## Apple reports the outcome later, through the event queue.
var _auth_requested := false
var _auth_attempts := 0
var _auth_timer := AUTH_FIRST_DELAY
var _auth_recoveries := 0


var _queue_stuck := false


func _ready() -> void:
	set_process(false)
	if not _bind():
		return
	# Deliberately not authenticating here -- see AUTH_FIRST_DELAY.
	set_process(true)


## True when Game Center is usable on this build. Callers use it to hide UI
## that would otherwise do nothing.
func available() -> bool:
	return _gc != null


## Requests sign-in now, and restarts the retry schedule. Called automatically
## once the view hierarchy is up; exposed so a UI can offer a manual retry.
func authenticate() -> void:
	_auth_requested = false
	_auth_attempts = 0
	_auth_timer = 0.0


func _attempt_auth(delta: float) -> void:
	if _auth_requested:
		return                          # already accepted, or given up
	_auth_timer -= delta
	if _auth_timer > 0.0:
		return
	if _gc == null or not _gc.has_method("authenticate"):
		_auth_requested = true          # nothing to retry against
		return
	_auth_attempts += 1
	# Returns FAILED while the root view controller is still missing, which is
	# the normal state for the first frames of the app.
	var err: int = int(_gc.call("authenticate"))
	if err == OK:
		_auth_requested = true
		last_error = ""
		return
	_auth_timer = AUTH_RETRY_DELAY
	if _auth_attempts >= AUTH_MAX_ATTEMPTS:
		_auth_requested = true          # stop retrying; report it
		last_error = ("authenticate() kept returning error %d -- the app never "
			+ "presented a root view controller") % err
		push_warning("GameServices: " + last_error)


## Sends a score to the board for `mode`. Safe to call unconditionally; it
## queues while signing in and does nothing at all without the plugin.
func submit_score(score: int, mode: int) -> void:
	if _gc == null:
		return
	var board := String(LEADERBOARDS.get(mode, ""))
	if board.is_empty():
		push_warning("GameServices: no leaderboard id for mode %d" % mode)
		return
	if not authenticated:
		if _pending.size() < MAX_PENDING:
			_pending.append({"score": score, "board": board})
		return
	_post(score, board)


## Opens Apple's own leaderboard UI, on the board for `mode`.
func show_leaderboard(mode: int = ModesScript.Id.PALETTE) -> void:
	if _gc == null or not authenticated or not _gc.has_method("show_game_center"):
		return
	_gc.call("show_game_center", {
		"view": "leaderboards",
		"leaderboard_id": String(LEADERBOARDS.get(mode, "")),
	})


## One line describing where Game Center stands. Meant for diagnosing a build
## on-device, where the console is not to hand.
func status() -> String:
	if _gc == null:
		# Nothing bound: say which of the two reasons applies.
		if OS.get_name() != "iOS":
			return "not iOS (%s)" % OS.get_name()
		return "plugin missing: no %s singleton" % SINGLETON
	if authenticated:
		return "signed in as %s" % player_name
	if not last_error.is_empty():
		if not _auth_requested:
			return "retrying in a moment -- " + last_error
		return "sign-in failed: " + last_error
	if not _auth_requested:
		return "waiting for the view hierarchy (attempt %d)" % (_auth_attempts + 1)
	return "signing in..."


## "Welcome <name>!", or empty when there is nobody to greet. Callers can bind
## this straight to a Label and hide it when the result is empty.
func greeting() -> String:
	if not authenticated or player_name.is_empty():
		return ""
	return "Welcome %s!" % player_name


func _post(score: int, board: String) -> void:
	if _gc == null or not _gc.has_method("post_score"):
		return
	_gc.call("post_score", {"score": score, "category": board})


## Apple's servers fail transiently more often than they should, especially in
## the sandbox. Schedule another attempt for those; leave the rest alone.
func _schedule_recovery(code: int) -> void:
	if not GK_RETRYABLE.has(code):
		return
	if _auth_recoveries >= AUTH_MAX_RECOVERIES:
		return
	_auth_recoveries += 1
	_auth_requested = false
	_auth_attempts = 0
	_auth_timer = AUTH_RECOVER_DELAY


func _bind() -> bool:
	if OS.get_name() != "iOS":
		return false
	if not Engine.has_singleton(SINGLETON):
		# An iOS build without the plugin: worth saying once, not fatal.
		push_warning("GameServices: iOS build has no %s singleton; "
			% SINGLETON + "see docs/gamecenter.md")
		return false
	_gc = Engine.get_singleton(SINGLETON)
	return true


## Latched so a broken plugin warns once, not sixty times a second.



## Most events a frame will ever carry. The queue holds authentication results
## and leaderboard acknowledgements, which arrive a handful at a time; anything
## past this is the plugin misbehaving, not a real backlog.
const MAX_EVENTS_PER_FRAME := 32


## The plugin reports results through a queue rather than signals, so it has to
## be drained each frame.
##
## Bounded twice, because this runs on the main thread on a phone and the queue
## belongs to native code we do not control. It used to be a bare
## `while count > 0: pop()`, which trusts the plugin to decrement -- and if a
## pop ever fails to consume, that spins forever and the whole device stops
## responding, with no error and nothing in the log.
func _process(delta: float) -> void:
	if _gc == null or not _gc.has_method("get_pending_event_count"):
		set_process(false)
		return
	_attempt_auth(delta)

	var drained := 0
	while drained < MAX_EVENTS_PER_FRAME:
		var pending := int(_gc.call("get_pending_event_count"))
		if pending <= 0:
			return
		_handle(_gc.call("pop_pending_event"))
		drained += 1
		# The pop must actually shorten the queue. If it did not, the plugin is
		# not draining and looping again would hang the frame -- stop, and say
		# so once rather than every frame forever.
		if int(_gc.call("get_pending_event_count")) >= pending:
			if not _queue_stuck:
				_queue_stuck = true
				push_warning("GameServices: event queue is not draining (%d pending);"
					% pending + " giving up on it to keep the frame alive.")
			set_process(false)
			return
	# Hit the per-frame cap with events still waiting: fine, take the rest next
	# frame rather than blocking this one.


func _handle(event: Variant) -> void:
	if typeof(event) != TYPE_DICTIONARY:
		return
	var e: Dictionary = event
	match String(e.get("type", "")):
		"authentication":
			var ok: bool = String(e.get("result", "")) == "ok"
			# Apple documents `displayName` as the string to show; `alias` is
			# the fallback for older responses that omit it.
			var name := String(e.get("displayName", "")).strip_edges()
			if name.is_empty():
				name = String(e.get("alias", "")).strip_edges()
			var changed: bool = ok != authenticated or name != player_name
			authenticated = ok
			player_name = name if ok else ""
			if ok:
				last_error = ""
			else:
				# Apple's reason, which is the only thing that identifies a
				# misconfigured App ID or provisioning profile. Losing it makes
				# a device that will not sign in impossible to diagnose.
				var code: int = int(e.get("error_code", -1))
				var meaning: String = String(GK_ERRORS.get(code, "unrecognised code"))
				last_error = "%s -- %s (code %d)" % [
					meaning,
					String(e.get("error_description", "no description")),
					code,
				]
				push_warning("GameServices: sign-in failed: " + last_error)
				_schedule_recovery(code)
			if changed:
				authentication_changed.emit(ok)
			if ok:
				_flush()
		"post_score":
			if String(e.get("result", "")) != "ok":
				push_warning("GameServices: score post failed: %s"
					% String(e.get("error_description", "unknown")))


func _flush() -> void:
	var queued := _pending.duplicate()
	_pending.clear()
	for row: Dictionary in queued:
		_post(int(row["score"]), String(row["board"]))
