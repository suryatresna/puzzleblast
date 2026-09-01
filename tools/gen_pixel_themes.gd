extends Node
## Builds the pixel Theme resources from the palette in `scripts/themes.gd`.
##
## Run:  Godot --headless --path . res://tools/gen_pixel_themes.tscn
##
## Hand-writing a Theme .tres with nine-patch StyleBoxTextures is long and easy
## to get subtly wrong, so the resources are generated instead. Re-run this
## after changing a palette in `Themes.DEFS` or regenerating the sprites.

const PLATE := "res://ui/pixel/plate.png"
const SPRITES := "res://ui/pixel/"

## Nine-patch inset: 12 logical px on a 48px plate, stored at 4x.
const MARGIN := 48.0

## Silkscreen is only crisp at multiples of its 8px design grid, so it is used
## where this file owns the size. Pixelify Sans is the body face -- the scenes
## carry per-node sizes (22, 26, 34...) that are not multiples of 8, and it
## tolerates those far better.
const HEAD := "res://ui/fonts/silkscreen.ttf"
const BODY := "res://ui/fonts/pixelify.ttf"

const SPECS := {
	# Buttons are the ochre ramp #E8BC61 -> #D6A549 in BOTH modes; the plate
	# sprite carries the ramp, so these name the top stop only.
	"res://ui/theme_pixel.tres": {
		"text": Color("4a3b2a"),
		"btn": Color("e8bc61"), "btn_hover": Color("f2d989"),
		"btn_press": Color("cc9a3f"), "btn_off": Color("d8cdb4"),
		"btn_text": Color("4a3b2a"),
		"sep": Color(0.29, 0.231, 0.165, 0.35),
	},
	"res://ui/theme_pixel_dark.tres": {
		"text": Color("f0e2c6"),
		"btn": Color("e8bc61"), "btn_hover": Color("f2d989"),
		"btn_press": Color("cc9a3f"), "btn_off": Color("4a3f33"),
		"btn_text": Color("17120f"),
		"sep": Color(0.941, 0.886, 0.776, 0.18),
	},
}


## Label type variations. Screens set `theme_type_variation` instead of a
## per-node colour override, so text follows the theme instead of staying
## whatever the scene hardcoded.
const VARIATIONS := {
	"TitleLabel": "text", "MutedLabel": "muted", "FaintLabel": "faint",
	"AccentLabel": "accent", "HighlightLabel": "highlight",
	"DangerLabel": "danger",
}


func _ready() -> void:
	for path: String in SPECS:
		var ok := _build(path, SPECS[path])
		print(("OK    " if ok else "FAIL  "), path)
	# The classic theme is hand-maintained; only the variations are injected.
	_add_variations_to("res://ui/theme.tres", Themes.Id.CLASSIC)
	get_tree().quit(0)


## Adds (or refreshes) the Label variations on an existing theme resource.
func _add_variations_to(path: String, id: int) -> void:
	var t: Theme = load(path)
	if t == null:
		print("FAIL  ", path); return
	_variations(t, id)
	print(("OK    " if ResourceSaver.save(t, path) == OK else "FAIL  "),
		path, "  (+variations)")


## Panel variations, so the HUD chip, tray slots and splash progress bar stop
## carrying hardcoded styleboxes in the scene files.
func _panels(t: Theme, id: int) -> void:
	var d: Dictionary = Themes.DEFS[id]
	var pixel: bool = bool(d["pixel"])
	var socket: Color = d.get("socket", Color(1, 1, 1, 0.05))
	var accent: Color = d.get("accent", Color.WHITE)
	var panel_tex: String = SPRITES + String(d.get("panel_tex", "panel")) + ".png"

	var hud: StyleBox
	var slot: StyleBox
	if pixel:
		hud = _plate(panel_tex, d.get("chip_top", socket))
		hud.content_margin_left = 26.0
		hud.content_margin_right = 26.0
		hud.content_margin_top = 14.0
		hud.content_margin_bottom = 14.0
		slot = _plate(panel_tex, d.get("slot_top", socket))
		slot.content_margin_left = 0.0
		slot.content_margin_right = 0.0
		slot.content_margin_top = 0.0
		slot.content_margin_bottom = 0.0
	else:
		# The classic look, lifted verbatim from the styleboxes that used to
		# live in game.tscn so nothing shifts for the default theme.
		var h := StyleBoxFlat.new()
		h.bg_color = Color(0.11, 0.098, 0.243, 0.66)
		h.border_color = Color(0.486, 0.424, 0.941, 0.26)
		h.set_border_width_all(2)
		h.set_corner_radius_all(22)
		h.content_margin_left = 26.0
		h.content_margin_right = 26.0
		h.content_margin_top = 14.0
		h.content_margin_bottom = 14.0
		hud = h
		var sl := StyleBoxFlat.new()
		sl.bg_color = Color(0.08, 0.07, 0.18, 0.5)
		sl.border_color = Color(0.486, 0.424, 0.941, 0.18)
		sl.set_border_width_all(2)
		sl.set_corner_radius_all(20)
		slot = sl

	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", hud)
	t.set_type_variation("SlotPanel", "PanelContainer")
	t.set_stylebox("panel", "SlotPanel", slot)

	# Settings cards: flat fill with a hard ink border, per the design -- not
	# the gradient nine-patch the HUD and tray use.
	var card := StyleBoxFlat.new()
	card.bg_color = d.get("card", Color(1, 1, 1, 0.06))
	if pixel:
		card.border_color = d.get("ink", Color.BLACK)
		card.set_border_width_all(6)
		card.set_corner_radius_all(8)
	else:
		card.border_color = Color(0.486, 0.424, 0.941, 0.26)
		card.set_border_width_all(2)
		card.set_corner_radius_all(22)
	card.content_margin_left = 40.0
	card.content_margin_right = 40.0
	card.content_margin_top = 34.0
	card.content_margin_bottom = 34.0
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)

	# Mode cards: the design's hard border plus an 8px lip beneath, which is a
	# zero-blur offset shadow rather than a real one.
	for variation: String in ["ModeCard", "ModeCardFeatured"]:
		var card_bg: Color = d.get("chip_top", Color(1, 1, 1, 0.06))
		if variation == "ModeCardFeatured":
			card_bg = d.get("blocks", [Color.WHITE])[0]     # the palette blue
		var mc := StyleBoxFlat.new()
		mc.bg_color = card_bg
		mc.border_color = d.get("ink", Color(0.486, 0.424, 0.941, 0.26))
		mc.set_border_width_all(6 if pixel else 2)
		mc.set_corner_radius_all(8 if pixel else 22)
		mc.content_margin_left = 40.0
		mc.content_margin_right = 40.0
		mc.content_margin_top = 34.0
		mc.content_margin_bottom = 34.0
		if pixel:
			mc.shadow_color = d.get("ink", Color.BLACK)
			mc.shadow_size = 0
			mc.shadow_offset = Vector2(0, 16)
		t.set_type_variation(variation, "PanelContainer")
		t.set_stylebox("panel", variation, mc)

	# The square back button in the design's header.
	var icon := card.duplicate() as StyleBoxFlat
	icon.content_margin_left = 22.0
	icon.content_margin_right = 22.0
	icon.content_margin_top = 14.0
	icon.content_margin_bottom = 14.0
	t.set_type_variation("IconButton", "Button")
	t.set_stylebox("normal", "IconButton", icon)
	t.set_stylebox("hover", "IconButton", icon)
	t.set_stylebox("pressed", "IconButton", icon)
	t.set_stylebox("focus", "IconButton", icon)
	var icon_text: Color = d.get("text", Color.WHITE)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		t.set_color(c, "IconButton", icon_text)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(socket, 0.5) if pixel else Color(0.945, 0.941, 1, 0.12)
	track.set_corner_radius_all(0 if pixel else 4)
	t.set_type_variation("BarTrack", "Panel")
	t.set_stylebox("panel", "BarTrack", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = accent if pixel else Color(0.608, 0.549, 1, 0.9)
	fill.set_corner_radius_all(0 if pixel else 4)
	t.set_type_variation("BarFill", "Panel")
	t.set_stylebox("panel", "BarFill", fill)


func _variations(t: Theme, id: int) -> void:
	var was := Themes.current()
	Themes.peek(id)
	for name: String in VARIATIONS:
		t.set_type_variation(name, "Label")
		t.set_color("font_color", name, Themes.text_color(VARIATIONS[name]))
	_panels(t, id)

	# The wordmark: the design's hard offset shadow, 6px at the mockup's 2x,
	# so 3 logical px -> 12 here.
	t.set_type_variation("WordmarkLabel", "Label")
	t.set_color("font_color", "WordmarkLabel", Themes.value("wordmark", Color.WHITE))
	t.set_color("font_shadow_color", "WordmarkLabel", Themes.value("shadow", Color.BLACK))
	t.set_constant("shadow_offset_x", "WordmarkLabel", 12)
	t.set_constant("shadow_offset_y", "WordmarkLabel", 12)
	t.set_constant("shadow_outline_size", "WordmarkLabel", 0)
	t.set_constant("line_spacing", "WordmarkLabel", -14)

	Themes.peek(was)


func _plate(tex_path: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(tex_path)
	sb.texture_margin_left = MARGIN
	sb.texture_margin_right = MARGIN
	sb.texture_margin_top = MARGIN
	sb.texture_margin_bottom = MARGIN
	sb.modulate_color = tint
	sb.content_margin_left = 40.0
	sb.content_margin_right = 40.0
	sb.content_margin_top = 22.0
	sb.content_margin_bottom = 22.0
	return sb


func _build(path: String, s: Dictionary) -> bool:
	var head: FontFile = load(HEAD)
	var body: FontFile = load(BODY)
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = 40

	# Buttons carry the head face: this file owns their size, so it can be
	# pinned to a multiple of 8 and stay crisp.
	t.set_font("font", "Button", head)
	t.set_font_size("font_size", "Button", 40)
	t.set_stylebox("normal", "Button", _plate(PLATE, s["btn"]))
	t.set_stylebox("hover", "Button", _plate(PLATE, s["btn_hover"]))
	t.set_stylebox("pressed", "Button", _plate(PLATE, s["btn_press"]))
	t.set_stylebox("disabled", "Button", _plate(PLATE, s["btn_off"]))
	t.set_stylebox("focus", "Button", _plate(PLATE, s["btn_hover"]))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		t.set_color(c, "Button", s["btn_text"])
	t.set_color("font_disabled_color", "Button", Color(s["btn_text"], 0.5))

	_variations(t, Themes.Id.PIXEL_DARK if path.ends_with("_dark.tres") \
		else Themes.Id.PIXEL_WARM)
	t.set_color("font_color", "Label", s["text"])
	t.set_font_size("font_size", "Label", 40)
	t.set_color("default_color", "RichTextLabel", s["text"])
	t.set_font_size("normal_font_size", "RichTextLabel", 38)

	var id := Themes.Id.PIXEL_DARK if path.ends_with("_dark.tres") \
		else Themes.Id.PIXEL_WARM
	var panel := _plate(SPRITES + String(Themes.DEFS[id]["panel_tex"]) + ".png",
		Themes.DEFS[id]["chip_top"])
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)

	var sep := StyleBoxFlat.new()
	sep.bg_color = s["sep"]
	sep.content_margin_top = 2.0
	sep.content_margin_bottom = 2.0
	t.set_stylebox("separator", "HSeparator", sep)

	return ResourceSaver.save(t, path) == OK
