class_name InfoPanel
extends Control

# =============================================================================
# A reusable compact information panel (modal card).
# Used for ship-room details, instrument details and library card details.
# Content is passed in as data, so nothing is hard-coded here.
# =============================================================================

signal closed

var _title: Label
var _subtitle: Label
var _content: VBoxContainer
var _footer: Label
var _panel: PanelContainer
var _accent := Color(0.35, 0.85, 0.6)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.04, 0.11, 0.98)
	sb.border_color = UiTheme.CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.35)
	sb.shadow_size = 8
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(660, 0)
	center.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", UiTheme.GOLD)
	v.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
	v.add_child(_subtitle)
	v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(624, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.custom_minimum_size = Vector2(610, 0)
	scroll.add_child(_content)

	_footer = Label.new()
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.custom_minimum_size = Vector2(624, 0)
	_footer.add_theme_font_size_override("font_size", 12)
	_footer.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
	v.add_child(_footer)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var close := Button.new()
	close.text = "Close"
	close.accessibility_name = "Close"
	UiTheme.style_button(close, "cyan", true)
	close.pressed.connect(close_panel)
	row.add_child(close)


func open(title: String, subtitle: String, sections: Array, footer: String = "", accent: Color = Color(0.35, 0.85, 0.6)) -> void:
	_create_content()
	_title.text = title
	_subtitle.text = subtitle
	_accent = accent
	_title.add_theme_color_override("font_color", accent)
	_footer.text = footer
	for sec in sections:
		if sec is Dictionary:
			_add_section(str(sec.get("label", "")), str(sec.get("body", "")), sec.get("color", accent))
	visible = true
	# simple pop-in
	_panel.pivot_offset = Vector2.ZERO
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)


func _create_content() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func _add_section(label: String, body: String, color: Variant) -> void:
	if label != "":
		var l := Label.new()
		l.text = label
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(color))
		_content.add_child(l)
	if body != "":
		var b := Label.new()
		b.text = body
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(600, 0)
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
		_content.add_child(b)


func close_panel() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()