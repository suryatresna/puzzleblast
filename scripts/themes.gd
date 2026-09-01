extends Node
## The theme registry. Autoloaded as `Themes`.
##
## A theme is pure presentation: a palette, a UI theme resource, and -- for the
## pixel themes -- a set of sprites the board draws with instead of styleboxes.
## Nothing here touches game rules, so switching mid-run is safe.
##
## Consumers read `Themes.data()` (or the typed helpers below) and rebuild
## whatever they cache when `theme_changed` fires.
##
## `ACTIVE` is the theme a fresh install ships with, and the only one available
## until the player levels up. Others are unlocked by `Progress` and chosen from
## the settings screen, so the choice IS persisted -- see `_save()`.
##
## To add a theme: append an entry to `DEFS`. Every consumer is data-driven, so
## a new palette needs no code changes beyond the table -- but a pixel theme
## also needs a `ui_theme` resource and, if its shading differs, sprites from
## `tools/gen_pixel_sprites.py`.

signal theme_changed(id: int)

enum Id { CLASSIC, PIXEL_WARM, PIXEL_DARK }

const SAVE_PATH := "user://settings.cfg"

## The theme a fresh install ships with, before anything is unlocked.
const ACTIVE := Id.PIXEL_DARK

const DEFAULT_ID := ACTIVE

## Sprites live at 4x their logical size (a 32px tile is stored 128px) because
## the game runs at 1080x1920, four times the 270x480 the art was designed for.
## Baking the upscale keeps the pixel grid exact and keeps nine-patch margins
## in proportion -- StyleBoxTexture measures those in texture pixels and does
## not scale them when drawing.
const SPRITE_DIR := "res://ui/pixel/"

const DEFS := {
	Id.CLASSIC: {
		"name": "Classic",
		"blurb": "The original deep indigo look.",
		"text": Color(0.945, 0.941, 1),
		"muted": Color(0.651, 0.635, 0.8),
		"faint": Color(0.651, 0.635, 0.8, 0.7),
		"accent": Color(0.133, 0.827, 0.933),
		"highlight": Color(1, 0.83, 0.32),
		"danger": Color(0.984, 0.443, 0.522),
		"outline": Color(0.02, 0.02, 0.06, 0.95),
		"ui_theme": "res://ui/theme.tres",
		"pixel": false,
		"blocks": [
			Color("22d3ee"), Color("5b7cfa"), Color("ff9f45"), Color("ffd452"),
			Color("4ade80"), Color("9b8cff"), Color("fb7185"), Color("f472b6"),
		],
		"powers": [Color("ef4444"), Color("2dd4bf"), Color("fde047"), Color("a3e635"),
			Color("38bdf8"), Color("8b5cf6"), Color("e0f2fe"), Color("d946ef"),
			Color("c2410c"), Color("0369a1")],
		"board_bg": Color(0.043, 0.039, 0.098, 0.93),
		"socket": Color(1, 1, 1, 0.035),
		"card": Color(0.11, 0.098, 0.243, 0.66),
		"knob": Color(0.945, 0.941, 1),
		"wordmark": Color(0.945, 0.941, 1),
		"shadow": Color(0.02, 0.02, 0.06, 0.5),
		"ghost_ok": Color(1, 1, 1, 0.28),
		"ghost_bad": Color(0.98, 0.44, 0.52, 0.28),
		"bg_stops": [
			Color(0.129, 0.114, 0.31), Color(0.071, 0.063, 0.169),
			Color(0.035, 0.031, 0.086),
		],
		"combo_flow": [
			Color(0.231, 0.435, 0.878), Color(0.925, 0.282, 0.600),
			Color(0.961, 0.702, 0.004), Color(0.545, 0.361, 0.965),
		],
	},
	Id.PIXEL_WARM: {
		"name": "Pixel Warm",
		"blurb": "Warm retro pixel art on paper.",
		"text": Color("4a3b2a"),
		"muted": Color("6b5638"),
		"faint": Color("9a855f"),
		"accent": Color("b9512c"),
		"highlight": Color("806124"),
		"danger": Color("963e20"),
		"outline": Color("f6ebd5", 0.92),
		"ui_theme": "res://ui/theme_pixel.tres",
		"pixel": true,
		"tile": "tile", "socket_tex": "socket",
		# Tiles are tinted with the LIGHT stop of each ramp: the stored sprite
		# is normalised against it, so multiplying reproduces the mid stop at
		# 55% and the dark stop at the bottom edge.
		# The first four are the designer's; the rest extend the same register.
		"blocks": [
			Color("b6cbc3"), Color("9a7a34"), Color("cc6a41"), Color("e4b963"),
			Color("8ca271"), Color("b67f8e"), Color("6b8f9b"), Color("b07a48"),
		],
		# order matches Blocks.POWER_COLOR: bomb, collapse, laser, fit
		"powers": [Color("cc6a41"), Color("6b8f9b"), Color("e4b963"), Color("8ca271"),
			Color("b6cbc3"), Color("8f7aa8"), Color("dfe7ea"), Color("b57a9e"),
			Color("9c5a3c"), Color("4e7a91")],
		"board_bg": Color("eadbbe"),
		"board_border": Color("4a3b2a"),
		"socket": Color("e4d4b4"),
		"ink": Color("4a3b2a"),
		# Two-stop surfaces: the theme names the TOP colour, the nine-patch
		# sprite carries the ramp down to the bottom stop.
		"chip_top": Color("f9f1e1"),
		"slot_top": Color("efe1c4"),
		"card": Color("f9f1e1"),
		"knob": Color("f6ebd5"),
		# The wordmark's hard offset shadow.
		"wordmark": Color("b9512c"),
		"shadow": Color("e8d3ac"),
		"panel_tex": "panel",
		"ghost_ok": Color(0.725, 0.318, 0.173, 0.28),
		"ghost_bad": Color(0.290, 0.231, 0.165, 0.14),
		# The screen is the design's two-stop ramp. Intermediate gradient
		# points are interpolated at runtime -- see background.gd.
		"bg_stops": [Color("f6ebd5"), Color("efdfc0")],
		"combo_flow": [
			Color("a1b8b0"), Color("b9512c"), Color("d6a549"), Color("806124"),
		],
	},
	Id.PIXEL_DARK: {
		"name": "Pixel Dark",
		"blurb": "The same sprites, dark ink on dark paper.",
		"text": Color("f0e2c6"),
		"muted": Color("a08b67"),
		"faint": Color("6e5c42"),
		"accent": Color("d6a549"),
		"highlight": Color("e8bc61"),
		"danger": Color("d0603a"),
		"outline": Color("0f0c0a", 0.95),
		"ui_theme": "res://ui/theme_pixel_dark.tres",
		"pixel": true,
		"tile": "tile_dark", "socket_tex": "socket_dark",
		"blocks": [
			Color("8fa9a1"), Color("a8842f"), Color("d0603a"), Color("e8bc61"),
			Color("7c9166"), Color("a06e7c"), Color("5f7f8a"), Color("9c6b3f"),
		],
		"powers": [Color("d0603a"), Color("5f7f8a"), Color("e8bc61"), Color("7c9166"),
			Color("8fa9a1"), Color("8a6fa8"), Color("cfe0e8"), Color("b06a95"),
			Color("a85536"), Color("3f6f88")],
		# #241C16 is the PANEL token; the board itself is a step darker.
		"board_bg": Color("201914"),
		"board_border": Color("0f0c0a"),
		"socket": Color("2b211b"),
		"ink": Color("0f0c0a"),
		"chip_top": Color("3a2c22"),
		"slot_top": Color("3a2c22"),
		"card": Color("241c16"),
		"knob": Color("f0e2c6"),
		"wordmark": Color("d6a549"),
		"shadow": Color("3a2c22"),
		"panel_tex": "panel_dark",
		"ghost_ok": Color(0.725, 0.318, 0.173, 0.34),
		"ghost_bad": Color(0.941, 0.886, 0.776, 0.10),
		"bg_stops": [Color("2a211a"), Color("17120f")],
		"combo_flow": [
			Color("75908a"), Color("b9512c"), Color("d6a549"), Color("8a6a24"),
		],
	},
}

## Glyph sprite per power, keyed by `Blocks.Power`. Only the pixel themes use
## these; Classic keeps the procedural glyphs in `blocks.gd`.
const GLYPHS := {
	1: "glyph_bomb",      # Power.BOMB
	2: "glyph_collapse",  # Power.MORPH
	3: "glyph_laser",     # Power.LASER
	4: "glyph_fit",       # Power.FIT
	5: "glyph_diagonal",  # Power.DIAGONAL
	6: "glyph_blackhole", # Power.BLACKHOLE
	7: "glyph_thunder",   # Power.THUNDER
	8: "glyph_teleport",  # Power.TELEPORT
	9: "glyph_meteor",    # Power.METEOR
	10: "glyph_tsunami",  # Power.TSUNAMI
}

var _id: int = ACTIVE
## Display preference rather than a theme, but it shares this node's owner-
## ship of the presentation half of settings.cfg rather than adding another
## autoload for one boolean.
var _grid_lines := true
var _loaded := false
var _cache: Dictionary = {}


func _ready() -> void:
	_ensure_loaded()


## The active theme id.
func current() -> int:
	_ensure_loaded()
	return _id


## Switches theme and remembers it. Callers are responsible for checking the
## theme is unlocked; `settings.gd` only offers unlocked ones.
func set_current(id: int) -> void:
	_ensure_loaded()
	if not DEFS.has(id) or id == _id:
		return
	_id = id
	_save()
	theme_changed.emit(_id)


## Switches without persisting. For the theme generator and tests, which walk
## every palette and must not leave the player on the last one they touched.
func peek(id: int) -> void:
	_ensure_loaded()
	if not DEFS.has(id) or id == _id:
		return
	_id = id
	theme_changed.emit(_id)


## Whether the board draws separators between cells.
func grid_lines() -> bool:
	_ensure_loaded()
	return _grid_lines


func set_grid_lines(on: bool) -> void:
	_ensure_loaded()
	if on == _grid_lines:
		return
	_grid_lines = on
	_save()
	theme_changed.emit(_id)


## The active theme's whole definition.
func data() -> Dictionary:
	return DEFS[current()]


func value(key: String, fallback: Variant = null) -> Variant:
	var d := data()
	return d[key] if d.has(key) else fallback


func is_pixel() -> bool:
	return bool(value("pixel", false))


func theme_name(id: int = -1) -> String:
	return String(DEFS[id if DEFS.has(id) else current()]["name"])


func ids() -> Array:
	return DEFS.keys()


## The full 12-entry palette, laid out to match `Blocks.COLORS`: eight shape
## colours then the four power colours.
## A semantic text colour: "text", "muted", "faint", "accent", "highlight",
## "danger" or "outline". The design names three distinct body tones rather
## than fading one, so `faint` is stored, not derived.
func text_color(role: String) -> Color:
	if role == "faint" and not data().has("faint"):
		return Color(value("muted", Color.GRAY), 0.7)
	return value(role, Color.WHITE)


func palette() -> Array:
	var out: Array = []
	out.append_array(value("blocks", []) as Array)
	out.append_array(value("powers", []) as Array)
	return out


## Block colour for a piece's `color` index, wrapping so a palette shorter than
## the piece table still works.
func block_color(index: int) -> Color:
	var list: Array = value("blocks", [])
	if list.is_empty():
		return Color.WHITE
	return list[index % list.size()]


## Colour for a `Blocks.Power`, falling back to the block palette.
func power_color(power: int) -> Color:
	var list: Array = value("powers", [])
	if power <= 0 or list.is_empty():
		return block_color(0)
	return list[(power - 1) % list.size()]


## The UI theme resource for the active theme, or null if it is missing --
## callers keep their scene's own theme in that case rather than blanking out.
func ui_theme() -> Theme:
	var path := String(value("ui_theme", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return _load(path) as Theme


## The block-face sprite, or null on a non-pixel theme.
func tile_texture() -> Texture2D:
	return _sprite(String(value("tile", "")))


func socket_texture() -> Texture2D:
	return _sprite(String(value("socket_tex", "")))


func glyph_texture(power: int) -> Texture2D:
	if not is_pixel() or not GLYPHS.has(power):
		return null
	return _sprite(String(GLYPHS[power]))


func _sprite(name: String) -> Texture2D:
	if name.is_empty():
		return null
	var path := SPRITE_DIR + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return _load(path) as Texture2D


func _load(path: String) -> Resource:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var saved: int = int(cfg.get_value("game", "theme", ACTIVE))
	if DEFS.has(saved):
		_id = saved
	_grid_lines = bool(cfg.get_value("game", "grid_lines", true))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # keep anything else already in the file
	cfg.set_value("game", "theme", _id)
	cfg.set_value("game", "grid_lines", _grid_lines)
	cfg.save(SAVE_PATH)
