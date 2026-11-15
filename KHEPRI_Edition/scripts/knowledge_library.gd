class_name KnowledgeLibrary
extends Control

# =============================================================================
# Optional in-game knowledge library. Categories on the left, cards on the
# right. All content comes from Education (education.json), so new material can
# be added without changing this script. Includes a "Science tips" section so
# children can revisit every contextual tip.
# =============================================================================

signal closed

var _info: InfoPanel
var _cats_v: VBoxContainer
var _cards_v: VBoxContainer
var _cat_title: Label
var _current := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var t := Label.new()
	t.text = "KNOWLEDGE LIBRARY"
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := Button.new()
	close.text = "Close"
	close.accessibility_name = "Close the knowledge library"
	UiTheme.style_button(close, "magenta", true)
	close.pressed.connect(close_library)
	head.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	# categories column
	var cat_panel := PanelContainer.new()
	cat_panel.custom_minimum_size = Vector2(240, 0)
	cat_panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.CYAN, 14))
	body.add_child(cat_panel)
	var cat_scroll := ScrollContainer.new()
	cat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cat_panel.add_child(cat_scroll)
	_cats_v = VBoxContainer.new()
	_cats_v.add_theme_constant_override("separation", 4)
	_cats_v.custom_minimum_size = Vector2(220, 0)
	cat_scroll.add_child(_cats_v)

	# cards column
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_cat_title = Label.new()
	_cat_title.add_theme_font_size_override("font_size", 20)
	_cat_title.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	right.add_child(_cat_title)
	var cards_scroll := ScrollContainer.new()
	cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(cards_scroll)
	_cards_v = VBoxContainer.new()
	_cards_v.add_theme_constant_override("separation", 6)
	_cards_v.custom_minimum_size = Vector2(880, 0)
	_cards_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_scroll.add_child(_cards_v)

	_info = InfoPanel.new()
	add_child(_info)


func open_library() -> void:
	visible = true
	_build_categories()
	_show_category(0)


func close_library() -> void:
	visible = false
	closed.emit()


func _categories() -> Array:
	var cats: Array = Education.library()
	var out: Array = []
	# mission design first, then the rest, then tips and sources
	for c in cats:
		out.append({"name": str(c.get("category", "")), "icon": str(c.get("icon", "")), "cards": c.get("cards", [])})
	out.append({"name": "Science tips", "icon": "", "cards": _tip_cards()})
	out.append({"name": "Sources", "icon": "", "cards": _source_cards()})
	return out


func _tip_cards() -> Array:
	var cards: Array = []
	var tips: Dictionary = Education.tips()
	for id in tips:
		var t: Dictionary = tips[id]
		cards.append({
			"title": _prettify(id),
			"body": str(t.get("text", "")),
			"category": "Science tips",
			"related": "Shown in context during play",
			"kind": "real",
			"source": "",
		})
	return cards


func _source_cards() -> Array:
	var cards: Array = []
	for s in Education.sources():
		cards.append({
			"title": str(s.get("title", "")),
			"body": "Reference used to guide the educational content of Moon Run.",
			"category": str(s.get("date", "")),
			"related": str(s.get("url", "")),
			"kind": "real",
			"source": str(s.get("url", "")),
		})
	return cards


func _prettify(id: String) -> String:
	return id.replace("_", " ").capitalize()


func _build_categories() -> void:
	for c in _cats_v.get_children():
		c.queue_free()
	var cats := _categories()
	for i in cats.size():
		var cat: Dictionary = cats[i]
		var b := Button.new()
		b.text = "  " + str(cat["name"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(220, 44)
		UiTheme.style_button(b, "cyan", true)
		b.pressed.connect(_show_category.bind(i))
		_cats_v.add_child(b)


func _show_category(i: int) -> void:
	_current = i
	var cats := _categories()
	if i < 0 or i >= cats.size():
		return
	var cat: Dictionary = cats[i]
	_cat_title.text = str(cat["name"])
	for c in _cards_v.get_children():
		c.queue_free()
	for card in cat["cards"]:
		var b := Button.new()
		b.text = "  " + str(card.get("title", "Card"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(640, 48)
		UiTheme.style_button(b, "gold", true)
		b.pressed.connect(_open_card.bind(card))
		_cards_v.add_child(b)


func _open_card(card: Dictionary) -> void:
	var sections: Array = []
	if str(card.get("body", "")) != "":
		sections.append({"label": "", "body": str(card["body"])})
	if str(card.get("example", "")) != "":
		sections.append({"label": "Example", "body": str(card["example"])})
	if str(card.get("related", "")) != "":
		sections.append({"label": "Where you see it", "body": str(card["related"])})
	var kind := str(card.get("kind", "real"))
	sections.append({"label": "Type of information", "body": Education.kind_label(kind), "color": Education.kind_color(kind)})
	if str(card.get("uncertainty", "")) != "":
		sections.append({"label": "Uncertainty / limitations", "body": str(card["uncertainty"]), "color": Color(1.0, 0.85, 0.5)})
	var footer := ""
	if str(card.get("source", "")) != "":
		footer = "Source: %s (%s)" % [str(card["source"]), str(card.get("source_date", ""))]
		if str(card.get("source_url", "")) != "":
			footer += "\n" + str(card["source_url"])
	_info.open(str(card.get("title", "Info")), str(card.get("category", "")), sections, footer, Color(0.5, 0.9, 1.0))