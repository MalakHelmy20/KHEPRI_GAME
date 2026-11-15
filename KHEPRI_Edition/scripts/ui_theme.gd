class_name UiTheme
extends RefCounted

# Shared visual language for Moon Run: a bright, friendly look for young
# explorers. Big rounded shapes, warm colors, and lots of contrast.
# Status is never communicated by color alone — pair every color with a word.

# Panels sit on a deep-but-warm night blue so the bright accents pop.
const NAVY := Color(0.11, 0.12, 0.32, 0.96)
const NAVY_SOFT := Color(0.16, 0.18, 0.40, 0.94)
const TEXT := Color(1.0, 0.99, 0.96)
const TEXT_DIM := Color(0.80, 0.85, 0.98)
# Friendly accents: sky blue, candy purple, bubblegum, sunshine, mint, coral.
const CYAN := Color(0.42, 0.86, 1.0)
const CYAN_DIM := Color(0.32, 0.62, 0.90)
const MAGENTA := Color(0.80, 0.58, 1.0)
const PINK := Color(1.0, 0.60, 0.78)
const GOLD := Color(1.0, 0.85, 0.36)
const GOOD := Color(0.46, 0.96, 0.62)
const WARN := Color(1.0, 0.80, 0.30)
const BAD := Color(1.0, 0.46, 0.50)

static var reduce_motion := false


static func panel(accent: Color = CYAN, radius: int = 28) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAVY
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.98)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.shadow_size = 10
	sb.set_content_margin_all(12)
	return sb


# A soft rounded card used for chips, room plates and surface markers.
static func card(accent: Color, fill: float = 0.18, radius: int = 22) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAVY_SOFT.lerp(accent, fill)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	return sb


static func style_button(b: Button, kind: String = "cyan", compact: bool = false) -> void:
	var accent := CYAN
	match kind:
		"gold":
			accent = GOLD
		"magenta":
			accent = MAGENTA
		"pink":
			accent = PINK
		_:
			accent = CYAN
	# Buttons are big and easy to tap, so small hands can hit them reliably.
	var h := 46.0 if compact else 56.0
	var fs := 18 if compact else 22
	b.add_theme_font_size_override("font_size", fs)
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, h)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", _btn_box(accent, 0.22, 3))
	b.add_theme_stylebox_override("hover", _btn_box(accent, 0.40, 3))
	b.add_theme_stylebox_override("pressed", _btn_box(accent, 0.56, 3))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(0.42, 0.44, 0.56), 0.10, 3))
	b.add_theme_stylebox_override("focus", _btn_box(Color(1, 1, 1), 0.28, 4))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.70, 0.72, 0.80))
	b.add_theme_color_override("font_focus_color", Color.WHITE)


static func _btn_box(accent: Color, fill_a: float, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.16, 0.38, 0.97).lerp(accent, fill_a)
	sb.border_color = accent
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(24)
	sb.content_margin_left = 18
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func style_bar(bar: ProgressBar, fill: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.08, 0.16, 1.0)
	bg.border_color = Color(fill.r, fill.g, fill.b, 0.55)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(9)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.show_percentage = false


static func status_word(v: float) -> String:
	if v <= 0.0:
		return "EMPTY"
	if v < 25.0:
		return "LOW"
	if v < 50.0:
		return "OK"
	return "GOOD"


static func status_color(v: float) -> Color:
	if v <= 0.0 or v < 25.0:
		return BAD
	if v < 50.0:
		return WARN
	return GOOD
