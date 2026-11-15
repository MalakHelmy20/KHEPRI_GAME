class_name ScanPanel
extends Control

# =============================================================================
# Scientific scanning interface.
# Shows, for each instrument: what it measured, the value, the unit, data
# quality, an interpretation and a learning question. Instruments whose host
# system is unpowered appear OFFLINE, teaching that instruments need power.
# =============================================================================

signal resolved(choice: Dictionary)

var _body := ""
var _target: Dictionary
var _content: VBoxContainer
var _panel: PanelContainer
var _quality_sum := 0.0
var _count := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.12, 0.98)
	sb.border_color = Color(0.35, 0.85, 1.0, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.custom_minimum_size = Vector2(742, 0)
	scroll.add_child(_content)


func _lbl(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


# available: instrument_id -> quality 0..1 (only powered instruments present)
func open(body: String, available: Dictionary) -> void:
	_body = body
	_target = Education.scan_target(body)
	visible = true
	for c in _content.get_children():
		c.queue_free()
	_quality_sum = 0.0
	_count = 0

	if _target.is_empty():
		_content.add_child(_lbl("No data", 20, Color(1, 0.7, 0.4)))
		_add_buttons()
		return

	_content.add_child(_lbl(str(_target.get("title", body)), 24, Color(0.6, 0.9, 1.0)))
	_content.add_child(_lbl("Instruments scan the environment and return measurements for scientists to analyse.", 16, UiTheme.TEXT))
	_content.add_child(HSeparator.new())

	var obs: Array = _target.get("observations", [])
	var instr_defs: Dictionary = Education.instruments()
	for o in obs:
		var iid := str(o.get("instrument", ""))
		var idef: Dictionary = instr_defs.get(iid, {})
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var online: bool = available.has(iid)
		var q: float = float(available.get(iid, 0.0))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(_lbl("[%s]" % str(idef.get("glyph", "?")), 14, Color(0.5, 0.9, 1.0)))
		head.add_child(_lbl(str(idef.get("name", iid)), 15, Color(1, 1, 1)))
		row.add_child(head)
		if online:
			_count += 1
			_quality_sum += q
			row.add_child(_lbl("%s: %s %s" % [str(idef.get("measures", "")), str(o.get("value", "?")), str(o.get("unit", ""))], 18, Color(1.0, 0.9, 0.4)))
			# quality bar
			var qb := ProgressBar.new()
			qb.min_value = 0
			qb.max_value = 1
			qb.value = q
			qb.show_percentage = false
			qb.custom_minimum_size = Vector2(300, 12)
			qb.modulate = Color(0.5, 1, 0.6) if q >= 0.7 else (Color(1, 0.9, 0.4) if q >= 0.5 else Color(1, 0.6, 0.4))
			row.add_child(qb)
			var kind := str(o.get("kind", "simplified"))
			row.add_child(_lbl("Data quality: %s. %s. This reading is a %s." % [_quality_word(q), str(o.get("note", "")), Education.kind_label(kind)], 15, Education.kind_color(kind)))
		else:
			row.add_child(_lbl("OFFLINE - no power to the %s" % _sys_name(str(idef.get("host_system", ""))), 14, Color(1, 0.55, 0.5)))
		_content.add_child(row)
		_content.add_child(HSeparator.new())

	# interpretation
	var interp := VBoxContainer.new()
	interp.add_theme_constant_override("separation", 2)
	interp.add_child(_lbl("What does this tell us?", 15, Color(0.6, 0.95, 0.7)))
	var ib := _lbl(str(_target.get("interpretation", "")), 14, Color(0.92, 0.96, 1.0))
	ib.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ib.custom_minimum_size = Vector2(730, 0)
	interp.add_child(ib)
	_content.add_child(interp)

	# facts
	for f in _target.get("facts", []):
		var fb := _lbl("- " + str(f), 13, Color(0.75, 0.9, 0.8))
		fb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fb.custom_minimum_size = Vector2(730, 0)
		_content.add_child(fb)

	# question
	var ql := _lbl("Think like a scientist: " + str(_target.get("question", "")), 15, Color(1.0, 0.85, 0.4))
	ql.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ql.custom_minimum_size = Vector2(730, 0)
	_content.add_child(ql)

	_content.add_child(_lbl("Note: values labelled 'fictional' are gameplay values, not real measurements.", 11, Color(0.7, 0.75, 0.85)))
	var footer := _lbl("", 11, Color(0.7, 0.78, 0.9))
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.custom_minimum_size = Vector2(730, 0)
	var bits: Array = []
	if str(_target.get("source", "")) != "":
		bits.append("Source: %s (%s)" % [str(_target.get("source", "")), str(_target.get("source_date", ""))])
	if str(_target.get("limits", "")) != "":
		bits.append("Limitations: " + str(_target.get("limits", "")))
	footer.text = "   |   ".join(bits)
	_content.add_child(footer)
	_add_buttons()


func _sys_name(id: String) -> String:
	for s in GameData.SYSTEMS:
		if str(s["id"]) == id:
			return str(s["name"])
	return id


func _quality_word(q: float) -> String:
	if q >= 0.75:
		return "good"
	if q >= 0.5:
		return "fair"
	return "poor"


func _add_buttons() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var log_btn := Button.new()
	log_btn.text = "Log the data"
	log_btn.accessibility_name = "Log the scientific data"
	UiTheme.style_button(log_btn, "gold")
	log_btn.disabled = _count == 0
	log_btn.pressed.connect(func() -> void: _resolve(true))
	row.add_child(log_btn)
	var skip := Button.new()
	skip.text = "Move on"
	UiTheme.style_button(skip, "cyan")
	skip.pressed.connect(func() -> void: _resolve(false))
	row.add_child(skip)
	_content.add_child(row)


func _resolve(do_log: bool) -> void:
	visible = false
	var q := 0.0 if _count == 0 else _quality_sum / float(_count)
	resolved.emit({"log": do_log, "body": _body, "quality": q, "instruments": _count})