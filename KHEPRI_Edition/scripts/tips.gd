class_name TipsManager
extends Node

# =============================================================================
# Contextual educational tips.
# Docked in the top-right science panel during flight. Each tip is shown at
# most once per session (unless forced), with a gap so they stay readable.
# Every tip can be revisited in the Knowledge Library.
# =============================================================================

const COOLDOWN := 9.0     # seconds between tips
const HOLD := 8.0         # how long a tip stays on screen

signal opened(on: bool)

var _root: Control
var _dock: Control
var _docked := false
var _seen: Dictionary = {}
var _queue: Array = []
var _active := false
var _gap := 0.0
var _hide_t := 0.0
var _last := ""
var _open := false

var _toast: PanelContainer
var _text: Label
var _title: Label


func setup(root: Control, dock: Control = null) -> void:
	_root = root
	_dock = dock
	_docked = dock != null
	_build()


func _build() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.MAGENTA, 14))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _docked:
		for c in _dock.get_children():
			c.queue_free()
		_toast.set_anchors_preset(Control.PRESET_FULL_RECT)
		_toast.modulate.a = 1.0
		_dock.add_child(_toast)
	else:
		_toast.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_toast.offset_left = -360
		_toast.offset_top = 72
		_toast.offset_right = -16
		_toast.offset_bottom = 210
		_toast.custom_minimum_size = Vector2(340, 120)
		_toast.modulate.a = 1.0
		_toast.z_index = 45
		_root.add_child(_toast)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_toast.add_child(v)
	_title = Label.new()
	_title.text = "SCIENCE TIP"
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", UiTheme.MAGENTA)
	v.add_child(_title)
	_text = Label.new()
	_text.text = "Every mission starts with a question. What do you want to discover?"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(280, 0)
	_text.add_theme_font_size_override("font_size", 16)
	_text.add_theme_color_override("font_color", UiTheme.TEXT)
	v.add_child(_text)
	_toast.visible = false
	_set_open(false)


func has_seen(id: String) -> bool:
	return _seen.has(id)


func mark_seen(id: String) -> void:
	_seen[id] = true


# Show a tip by id. Returns true if it was actually queued/shown.
func show_tip(id: String, force: bool = false) -> bool:
	var t: Dictionary = Education.tip(id)
	if t.is_empty():
		return false
	if _seen.has(id) and not force:
		return false
	_seen[id] = true
	_queue.append({"id": id, "text": str(t.get("text", ""))})
	return true


func clear() -> void:
	_queue.clear()


func is_open() -> bool:
	return _open


func has_note() -> bool:
	return _last != ""


func replay() -> void:
	if _last == "":
		return
	_text.text = _last
	_active = true
	_hide_t = HOLD
	_toast.modulate.a = 1.0
	_set_open(true)


func _process(delta: float) -> void:
	if _gap > 0.0:
		_gap -= delta
	if _active:
		_hide_t -= delta
		if _hide_t <= 0.0:
			_active = false
			_set_open(false)
			_gap = COOLDOWN
	elif not _queue.is_empty() and _gap <= 0.0:
		_show(_queue.pop_front())


func _set_open(on: bool) -> void:
	_open = on
	if _toast:
		_toast.visible = on
	opened.emit(on)


func _show(item: Dictionary) -> void:
	_active = true
	_hide_t = HOLD
	_last = str(item.get("text", ""))
	_text.text = _last
	_toast.modulate.a = 1.0
	_set_open(true)
	if not UiTheme.reduce_motion:
		_toast.modulate.a = 0.55
		var tw := create_tween()
		tw.tween_property(_toast, "modulate:a", 1.0, 0.25)