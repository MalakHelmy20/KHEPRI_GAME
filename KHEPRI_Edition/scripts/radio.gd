class_name RadioCommunication
extends Control

# =============================================================================
# Reusable radio-call component.
#  - slides a panel in from the bottom-left / bottom-right, alternating
#  - shows a pixel-art caller portrait, caller name, role and typewritten text
#  - animated "incoming transmission" indicator + looping static + blips
#  - subtitle line and choice buttons; emits call_finished(choice)
#  - queues calls so two calls can never overlap
# =============================================================================

signal call_finished(choice: Dictionary)
signal call_shown(call: Dictionary)

const PANEL_W := 470.0
const PANEL_H := 232.0
const MARGIN := 18.0
const STATIC_STREAM := "res://assets/generated/audio/radio_static.mp3"
const BLIP_STREAM := "res://assets/generated/audio/radio_blip.mp3"

# caller-name keyword -> portrait file (res://assets/generated/portrait_<key>.png)
const PORTRAIT_FOR := {
	"amr diab": "singer",
	"tamer hosny": "singer",
	"ramy sabry": "singer",
	"hamda helal": "singer",
	"dina el sherbiny": "actress",
	"mohamed salah": "athlete",
	"tante nadia": "mother",
	"eng. fahmy": "engineer",
	"export compliance": "official",
	"planetary protection": "official",
	"nepa": "official",
	"artemis": "astronaut",
	"tamer el gayar": "meme",
	"astronaut hala": "astronaut",
}

var gs: GameState
var _queue: Array = []
var _busy := false
var _side_right := false
var _current: Dictionary = {}
var _full_text := ""
var _shown := 0
var _type_acc := 0.0
var _blip_acc := 0

var _panel: PanelContainer
var _portrait: TextureRect
var _frame: Panel
var _name_lbl: Label
var _role_lbl: Label
var _delay_lbl: Label
var _dialog_lbl: Label
var _fact_lbl: Label
var _trans_lbl: Label
var _indicator: RadioBars
var _btns: VBoxContainer
var _static_player: AudioStreamPlayer
var _t := 0.0


class RadioBars:
	extends Control
	var t := 0.0
	var active := true

	func _init() -> void:
		custom_minimum_size = Vector2(42, 18)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var n := 5
		var bw := 6.0
		var gap := 2.0
		for i in n:
			var ph := 0.4 + 0.6 * absf(sin(t * 6.0 + float(i) * 0.9))
			var h := 4.0 + ph * (size.y - 4.0)
			var x := float(i) * (bw + gap)
			var col := Color(0.4, 1.0, 0.6, 0.9) if active else Color(0.6, 0.6, 0.65, 0.5)
			draw_rect(Rect2(x, size.y - h, bw, h), col, true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_static_player = AudioStreamPlayer.new()
	_static_player.stream = load(STATIC_STREAM)
	_static_player.volume_db = -14.0
	if AudioServer.get_bus_index(&"SFX") != -1:
		_static_player.bus = &"SFX"
	add_child(_static_player)
	_build_ui()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.04, 0.12, 0.96)
	style.border_color = UiTheme.CYAN
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_panel.add_child(row)

	# portrait column with an animated frame
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 4)
	row.add_child(pcol)
	_frame = Panel.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.02, 0.05, 0.1, 1.0)
	fs.border_color = UiTheme.MAGENTA
	fs.set_border_width_all(3)
	fs.set_corner_radius_all(6)
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.custom_minimum_size = Vector2(120, 120)
	pcol.add_child(_frame)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_left = 4.0
	_portrait.offset_top = 4.0
	_portrait.offset_right = -4.0
	_portrait.offset_bottom = -4.0
	_frame.add_child(_portrait)
	_indicator = RadioBars.new()
	pcol.add_child(_indicator)

	# text column
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 4)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tcol)
	_trans_lbl = _mk_label("", 12, Color(0.4, 1.0, 0.6))
	_trans_lbl.text = "* INCOMING TRANSMISSION *"
	tcol.add_child(_trans_lbl)
	_delay_lbl = _mk_label("", 11, Color(0.8, 0.85, 1.0))
	_delay_lbl.name = "DelayLbl"
	tcol.add_child(_delay_lbl)
	_name_lbl = _mk_label("", 22, Color(1.0, 0.85, 0.3))
	tcol.add_child(_name_lbl)
	_role_lbl = _mk_label("", 13, Color(0.65, 0.8, 1.0))
	tcol.add_child(_role_lbl)
	_dialog_lbl = _mk_label("", 16, Color(0.92, 0.95, 1.0))
	_dialog_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_lbl.custom_minimum_size = Vector2(300, 70)
	_dialog_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tcol.add_child(_dialog_lbl)
	_fact_lbl = _mk_label("", 12, Color(0.6, 0.92, 0.72))
	_fact_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fact_lbl.custom_minimum_size = Vector2(300, 0)
	tcol.add_child(_fact_lbl)

	# choice buttons under the panel
	_btns = VBoxContainer.new()
	_btns.add_theme_constant_override("separation", 3)
	_btns.name = "Choices"
	add_child(_btns)


func _mk_label(text: String, fs: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	return l


func set_state(state: GameState) -> void:
	gs = state


# Educational: how long a radio signal takes to travel from Earth to the ship.
func set_delay(text: String) -> void:
	if _delay_lbl:
		_delay_lbl.text = text


# --- Public API -------------------------------------------------------------
func is_busy() -> bool:
	return _busy


func queue_call(data: Dictionary) -> void:
	if _busy:
		_queue.append(data)
		return
	_play(data)


# Continuous travel static (interval ambience)
func play_static(on: bool) -> void:
	if on and not _static_player.playing:
		_static_player.play()
	elif not on and _static_player.playing:
		_static_player.stop()


func _portrait_key(caller: String) -> String:
	var low := caller.to_lower()
	for k in PORTRAIT_FOR:
		if low.contains(k):
			return str(PORTRAIT_FOR[k])
	return "astronaut"


func _play(data: Dictionary) -> void:
	_busy = true
	_current = data
	_full_text = str(data.get("text", ""))
	_shown = 0
	_type_acc = 0.0
	_blip_acc = 0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var caller := str(data.get("caller", "UNKNOWN"))
	_name_lbl.text = caller
	_role_lbl.text = str(data.get("role", ""))
	_fact_lbl.text = str(data.get("fact", ""))
	_dialog_lbl.text = _full_text
	_dialog_lbl.visible_characters = 0
	var key := _portrait_key(caller)
	var path := "res://assets/generated/portrait_%s.png" % key
	if ResourceLoader.exists(path):
		_portrait.texture = load(path)
	else:
		_portrait.texture = load("res://assets/generated/portrait_astronaut.png")

	# build choice buttons
	for c in _btns.get_children():
		c.queue_free()
	var choices: Array = data.get("choices", [])
	if choices.is_empty():
		choices = [{"label": "Acknowledge", "fx": {}, "msg": ""}]
	for ch in choices:
		var b := Button.new()
		b.text = str(ch.get("label", "Okay"))
		UiTheme.style_button(b, "gold", true)
		b.pressed.connect(_on_choice.bind(ch))
		_btns.add_child(b)

	# play the transmission blip + static burst
	ZivaSfx.play(self, load(BLIP_STREAM), 0.02, -3.0)
	play_static(true)

	# position off-screen then slide in
	_side_right = not _side_right
	_place_panel(true)
	_indicator.active = true
	_trans_lbl.modulate.a = 1.0
	var end_pos := _end_panel_pos()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "position", end_pos, 0.45)
	# button container follows the panel
	_place_buttons(true)
	var tw2 := create_tween()
	tw2.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_btns, "position", _end_buttons_pos(), 0.45)
	call_shown.emit(data)


func _root_size() -> Vector2:
	# This Control may report a zero size when it is laid out, so fall back to
	# the viewport size for positioning the panel/buttons.
	var s := size
	if s.x < 10.0 or s.y < 10.0:
		s = get_viewport_rect().size
	return s


func _end_panel_pos() -> Vector2:
	var s := _root_size()
	var x := MARGIN if not _side_right else s.x - PANEL_W - MARGIN
	var y := s.y - PANEL_H - 160.0
	return Vector2(x, y)


func _start_panel_pos() -> Vector2:
	var e := _end_panel_pos()
	return Vector2(e.x, _root_size().y + 30.0)


func _place_panel(off: bool) -> void:
	_panel.position = _start_panel_pos() if off else _end_panel_pos()


func _end_buttons_pos() -> Vector2:
	var e := _end_panel_pos()
	return Vector2(e.x + MARGIN, e.y + PANEL_H + 4.0)


func _start_buttons_pos() -> Vector2:
	var e := _end_buttons_pos()
	return Vector2(e.x, size.y + 34.0)


func _place_buttons(off: bool) -> void:
	_btns.position = _start_buttons_pos() if off else _end_buttons_pos()
	_btns.custom_minimum_size = Vector2(PANEL_W - MARGIN * 2.0, 0)


func _process(delta: float) -> void:
	_t += delta
	if _trans_lbl:
		_trans_lbl.modulate.a = 0.4 + 0.6 * absf(sin(_t * 4.0))
	if _frame:
		var glow := 0.5 + 0.5 * absf(sin(_t * 3.0))
		_frame.modulate = Color(1, 1, 1, 0.7 + 0.3 * glow)
	# typewriter reveal
	if _busy and _shown < _full_text.length():
		_type_acc += delta * 46.0
		var want := int(_type_acc)
		if want > _shown:
			_shown = mini(want, _full_text.length())
			_dialog_lbl.visible_characters = _shown
			_blip_acc += 1
			if _blip_acc % 4 == 0:
				ZivaSfx.play(self, load(BLIP_STREAM), 0.05, -14.0)


func _on_choice(ch: Dictionary) -> void:
	if not _busy:
		return
	# skip typewriter on first click while still typing
	if _shown < _full_text.length():
		_shown = _full_text.length()
		_dialog_lbl.visible_characters = -1
		return
	_exit(ch)


func _exit(ch: Dictionary) -> void:
	_indicator.active = false
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "position", _start_panel_pos(), 0.32)
	tw.parallel().tween_property(_btns, "position", _start_buttons_pos(), 0.32)
	tw.tween_callback(_finish_exit.bind(ch))


func _finish_exit(ch: Dictionary) -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	call_finished.emit(ch)
	# play the next queued call, if any
	if not _queue.is_empty():
		_play(_queue.pop_front())
	else:
		play_static(false)