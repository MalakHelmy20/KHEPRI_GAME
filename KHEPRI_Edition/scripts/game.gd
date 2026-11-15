extends Control

# =============================================================================
# MOON RUN 2 - Egypt x NASA, FTL-style controller.
# Owns one GameState and drives every screen: main menu, mission select,
# launch checklist, sector map, ship (space), events/calls (ground), combat,
# the BioNutrients food mini-game, and the end-of-mission science score (user).
# =============================================================================

const PLAYER_SHIP_NAME := "Nefer-1"

var gs: GameState
var rng := RandomNumberGenerator.new()
var screen := "menu"

var _calls_left: Array = []
var _events_left: Array = []
var _log_lines: Array = []
var _pending_node := false

# Audio stream players (managed by ZivaSfx)
# sfx_thrust, sfx_laser, sfx_explosion, sfx_call - handled by ZivaSfx

# --- UI refs ----------------------------------------------------------------
var top_bar: HBoxContainer
var counters_bar: HBoxContainer
var stage: Control
var dash: VBoxContainer
var log_box: RichTextLabel
var menu_page: Control
var tutorial_page: Control
var select_page: Control
var launch_page: Control
var map_view: SectorMapView
var ship_view: ShipView
var res_labels: Dictionary = {}
var cnt_labels: Dictionary = {}
var info_label: Label
var ready_label: Label
var margin_label: Label
var signal_label: Label
var evasion_label: Label
var pack_label: Label
var sys_rows: Dictionary = {}
var action_bar: HBoxContainer
var dash_scroll: ScrollContainer
var _warp: ColorRect

# Radio cutscene
var radio_overlay: Control
var radio_panel: Control
var radio_portrait: Sprite2D
var radio_text: Label
var radio_caller: Label


# popup
var overlay: Control
var pop_title: Label
var pop_role: Label
var pop_body: Label
var pop_fact: Label
var pop_btns: VBoxContainer
var pop_risk: RiskMatrix

# food mini-game
var food_overlay: Control
var food_v: VBoxContainer
var food_active := false
var food_state: Dictionary = {}

# combat / radio / cutscene / tutorial (new components)
var combat_scene: CombatScene
var radio: RadioCommunication
var cutscene: Cutscene
var tutorial: TutorialRunner

# Kids edition: walk around the ship, and walk the surface on the Moon / Mars.
var interior: ShipInterior
var surface: SurfaceScene
var explore_mode := true
var _all_checked_awarded := false
var _music: AudioStreamPlayer
var _music_path := ""
var _radio_timer := 20.0
var tutorial_active := false

# Educational components (data-driven; content lives in data/education.json)
var tips: TipsManager
var room_info: InfoPanel
var briefing: InfoPanel
var library: KnowledgeLibrary
var scan_panel: ScanPanel
var report: ScienceReport
var timeline: MissionTimeline
var _current_scan_body := "anomaly"
var _scan_is_node := false

# Universal Back navigation
var back_btn: Button
var _nav_history: Array = []
var _nav_back_mode := false

# HUD bars (value + word, so status is not color-only) and the science-tip dock
var res_bars: Dictionary = {}
var res_words: Dictionary = {}
var tip_host: Control
var hud_side: VBoxContainer
var reduce_motion := false
var _mission_ended := false

# Contextual dashboard + focus mode. Full controls stay one click away.
var details_box: VBoxContainer
var systems_box: VBoxContainer
var attention_box: VBoxContainer
var attention_title: Label
var next_label: Label
var details_btn: Button
var systems_btn: Button
var details_open := false
var systems_open := false
var sys_row_nodes: Dictionary = {}
var focus_banner: PanelContainer
var focus_label: Label
var _focus_key := ""
var _dismissed_key := ""
var _focus_lock := false
var _focus_ttl := 0.0
var _current_focus_rooms: Array = []
var res_boxes: Dictionary = {}
var _action_buttons: Dictionary = {}
var log_toggle: Button
var log_open := false
var _tip_note_btn: Button
var _design_extra: Label
var _design_btn: Button
var _logged_map_hint := false
var _tutorial_done := false
var _introduced: Dictionary = {}
# Kids edition
var _traveling := false
var _quiz_left: Array = []
var _quiz_current: Dictionary = {}


func _ready() -> void:
	rng.randomize()
	_build_ui()
	_show_menu()
	set_process(true)


func _process(delta: float) -> void:
	if food_active:
		_tick_food(delta)
	if gs == null or gs.game_over:
		return
	# Radio calls happen during travel, on a timer - never only at destinations.
	var blocked: bool = _input_blocked()
	if screen == "space" and radio != null and not radio.is_busy() and not blocked:
		_radio_timer -= delta
		if _radio_timer <= 0.0:
			_radio_timer = rng.randf_range(20.0, 40.0)
			_fire_call()
	# Event highlights linger only long enough to show which room mattered.
	if _focus_ttl > 0.0 and not _focus_lock and not tutorial_active:
		_focus_ttl -= delta
		if _focus_ttl <= 0.0:
			_apply_focus("", "", [], false)
			_update_context()


# =============================================================================
# UI construction
# =============================================================================
func _lbl(text: String, font_size: int = 15, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _res_chip(k: String) -> Control:
	var meta: Dictionary = GameData.RES_META[k]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(112, 0)
	box.tooltip_text = str(meta["name"])
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	# Two compact rows: "<name> <number> <word>" then the bar.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(_lbl(str(meta["short"]), 14, UiTheme.TEXT))
	var num := _lbl("100", 15, UiTheme.TEXT)
	head.add_child(num)
	var word := _lbl("GOOD", 12, UiTheme.GOOD)
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(word)
	box.add_child(head)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.custom_minimum_size = Vector2(108, 12)
	UiTheme.style_bar(bar, meta["color"])
	box.add_child(bar)
	res_labels[k] = num
	res_bars[k] = bar
	res_words[k] = word
	res_boxes[k] = box
	return box


func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://assets/generated/bg_space.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.42, 0.32, 0.62)
	add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.08, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_warp = ColorRect.new()


	_warp.color = Color(0.7, 0.85, 1.0, 0.0)
	_warp.set_anchors_preset(Control.PRESET_FULL_RECT)
	_warp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_warp)



	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# Top bar: simple status bars. Each resource shows a name, a word, a bar, and a number.
	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	root.add_child(top_bar)
	for k in GameData.RES_ORDER:
		top_bar.add_child(_res_chip(k))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	var sci := _lbl("Science 0", 20, UiTheme.GOLD)
	sci.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(sci)
	cnt_labels["science"] = sci

	# Main split
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	root.add_child(main)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	main.add_child(left)

	info_label = _lbl("", 15, Color(0.85, 0.9, 1.0))
	left.add_child(info_label)

	# compact 2D mission timeline (Launch -> ... -> Analysis)
	timeline = MissionTimeline.new()
	timeline.set_events([])
	left.add_child(timeline)

	stage = Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	left.add_child(stage)

	focus_banner = PanelContainer.new()
	focus_banner.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.MAGENTA, 14))
	focus_banner.visible = false
	var focus_row := VBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 6)
	focus_banner.add_child(focus_row)
	focus_label = _lbl("", 16, UiTheme.TEXT)
	focus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	focus_row.add_child(focus_label)
	var got_row := HBoxContainer.new()
	var got := Button.new()
	got.text = "Got it"
	got.accessibility_name = "Dismiss the highlighted hint"
	got.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_button(got, "magenta", true)
	got.pressed.connect(_dismiss_focus)
	got_row.add_child(got)
	focus_row.add_child(got_row)
	left.add_child(focus_banner)

	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 8)
	left.add_child(action_bar)

	log_toggle = Button.new()
	log_toggle.text = "Mission log"
	log_toggle.accessibility_name = "Show or hide the mission log"
	log_toggle.tooltip_text = "Warnings open this on their own. Nothing in the log is deleted."
	log_toggle.visible = false
	log_toggle.pressed.connect(_toggle_log)
	UiTheme.style_button(log_toggle, "cyan", true)
	left.add_child(log_toggle)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.custom_minimum_size = Vector2(0, 0)
	log_box.visible = false
	log_box.add_theme_font_size_override("normal_font_size", 16)
	log_box.add_theme_color_override("default_color", UiTheme.TEXT)
	left.add_child(log_box)

	# Right column: science tip stays pinned at the top; systems scroll beneath it.
	var right_col := VBoxContainer.new()
	hud_side = right_col
	right_col.add_theme_constant_override("separation", 8)
	right_col.custom_minimum_size = Vector2(360, 0)
	main.add_child(right_col)
	tip_host = Control.new()
	tip_host.custom_minimum_size = Vector2(340, 0)
	tip_host.visible = false
	right_col.add_child(tip_host)
	dash_scroll = ScrollContainer.new()
	dash_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dash_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(dash_scroll)
	dash = VBoxContainer.new()
	dash.custom_minimum_size = Vector2(320, 0)
	dash.add_theme_constant_override("separation", 6)
	dash_scroll.add_child(dash)
	_build_dash()

	_build_menu_page()
	_build_select_page()
	_build_launch_page()
	_build_map_view()
	_build_ship_view()
	_build_overlay()
	_build_food_overlay()
	_build_runtime_systems()
	_build_back_button()


# Universal BACK button: returns to the previous window from anywhere.
# Priority: close the open panel/report/scan > leave the tutorial > go back
# one screen > menu.
func _build_back_button() -> void:
	back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.accessibility_name = "Back"
	back_btn.tooltip_text = "Go back (Esc)"
	back_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back_btn.offset_left = 16
	back_btn.offset_bottom = -12
	back_btn.offset_top = -60
	back_btn.offset_right = 150
	UiTheme.style_button(back_btn, "magenta", true)
		# Above the modal hosts (100) so Back is always clickable.
	back_btn.z_index = 120
	back_btn.visible = false
	back_btn.pressed.connect(_go_back)
	add_child(back_btn)


func _page_id(p: Control) -> String:
	if p == menu_page:
		return "menu"
	if p == select_page:
		return "select"
	if p == launch_page:
		return "launch"
	if p == map_view:
		return "map"
	if p == ship_view or p == interior:
		return "ship"
	return ""


func _go_back() -> void:
	if cutscene and cutscene.visible:
		return  # let the cinematic finish
	if combat_scene and combat_scene.visible:
		return  # no escaping a live battle via Back
	if radio and radio.is_busy():
		_log("[color=#ffaa66]Answer the radio call to continue.[/color]")
		return
	# On a planet surface? Back returns you to the ship.
	if surface and surface.visible:
		surface.leave()
		return
	# 1) close any open overlay first
	if report and report.visible:
		report.close_panel()
		return
	if scan_panel and scan_panel.visible:
		scan_panel.visible = false
		if _scan_is_node:
			_scan_is_node = false
			_prompt_next()
		return
	if library and library.visible:
		library.close_library()
		return
	if room_info and room_info.visible:
		room_info.close_panel()
		return
	if briefing and briefing.visible:
		briefing.close_panel()
		return
	if food_overlay and food_overlay.visible:
		food_active = false
		food_overlay.visible = false
		_refresh()
		return
	if overlay and overlay.visible:
		# Mandatory decisions (events, calls, mission results) must be answered
		# with one of their buttons, so Back does not skip them.
		_log("[color=#ffaa66]Pick one of the options to continue.[/color]")
		return
	# 2) leaving the tutorial returns to the menu
	if tutorial_active:
		tutorial_active = false
		if tutorial:
			tutorial.stop()
		_show_menu()
		return
	# 3) otherwise: previous screen
	if _nav_history.size() >= 2:
		_nav_history.pop_back()          # drop current
		var target: String = _nav_history.back()
		_nav_back_mode = true
		match target:
			"menu": _show_menu()
			"select": _show_select()
			"launch": _build_launch_checklist()
			"map": _open_map()
			"ship": _enter_space(false)
			_: _show_menu()
	else:
		_show_menu()


func _build_dash() -> void:
	dash.add_child(_lbl("NOW", 18, UiTheme.MAGENTA))
	next_label = _lbl("Choose a mission to begin.", 16, UiTheme.TEXT)
	next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dash.add_child(next_label)
	# "Last science note" button removed to keep the young explorer's HUD simple;
	# the science tips still appear on their own when they matter.
	details_btn = Button.new()
	details_btn.text = "Ship details"
	details_btn.accessibility_name = "Show or hide spare power, signal and evasion"
	details_btn.pressed.connect(_toggle_details)
	UiTheme.style_button(details_btn, "cyan", true)
	dash.add_child(details_btn)
	details_box = VBoxContainer.new()
	details_box.visible = false
	details_box.add_theme_constant_override("separation", 4)
	dash.add_child(details_box)
	ready_label = _lbl("Ready check: --", 15, UiTheme.TEXT)
	ready_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_box.add_child(ready_label)
	margin_label = _lbl("Spare power: --", 15, UiTheme.TEXT)
	margin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_box.add_child(margin_label)
	signal_label = _lbl("Telecom signal: --", 15, UiTheme.TEXT)
	signal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_box.add_child(signal_label)
	evasion_label = _lbl("Evasion: --", 15, UiTheme.TEXT)
	details_box.add_child(evasion_label)
	pack_label = _lbl("Backpack: --", 15, UiTheme.TEXT)
	details_box.add_child(pack_label)
	dash.add_child(HSeparator.new())
	attention_title = _lbl("NEEDS ATTENTION", 16, UiTheme.PINK)
	dash.add_child(attention_title)
	attention_box = VBoxContainer.new()
	attention_box.add_theme_constant_override("separation", 4)
	dash.add_child(attention_box)
	systems_btn = Button.new()
	systems_btn.text = "All systems"
	systems_btn.accessibility_name = "Show or hide every ship system"
	systems_btn.pressed.connect(_toggle_systems)
	UiTheme.style_button(systems_btn, "gold", true)
	dash.add_child(systems_btn)
	systems_box = VBoxContainer.new()
	systems_box.visible = false
	systems_box.add_theme_constant_override("separation", 4)
	dash.add_child(systems_box)
	for s in GameData.SYSTEMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var name_l := _lbl(str(s["name"]), 14, UiTheme.TEXT)
		name_l.custom_minimum_size = Vector2(132, 0)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_l)
		var lvl := _lbl("", 14, UiTheme.GOLD)
		lvl.custom_minimum_size = Vector2(46, 0)
		row.add_child(lvl)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 1
		bar.custom_minimum_size = Vector2(54, 14)
		bar.show_percentage = false
		UiTheme.style_bar(bar, UiTheme.CYAN)
		row.add_child(bar)
		var minus := Button.new()
		minus.text = "-"
		minus.accessibility_name = "Remove power from %s" % str(s["name"])
		minus.custom_minimum_size = Vector2(40, 36)
		UiTheme.style_button(minus, "cyan", true)
		minus.pressed.connect(_remove_power.bind(s["id"]))
		row.add_child(minus)
		var plus := Button.new()
		plus.text = "+"
		plus.accessibility_name = "Add power to %s" % str(s["name"])
		plus.custom_minimum_size = Vector2(40, 36)
		UiTheme.style_button(plus, "gold", true)
		plus.pressed.connect(_add_power.bind(s["id"]))
		row.add_child(plus)
		systems_box.add_child(row)
		sys_rows[s["id"]] = {"lvl": lvl, "bar": bar}
		sys_row_nodes[s["id"]] = row
	var hint := _lbl("Click a room to add power. Right-click to remove it. Click a crew member, then a room, to move them.", 15, UiTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	systems_box.add_child(hint)


func _build_menu_page() -> void:
	menu_page = _make_page()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 8)
	menu_page.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.CYAN, 20))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(panel)
	var inner := MarginContainer.new()
	for s2 in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(s2, 16)
	panel.add_child(inner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	inner.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var insignia := TextureRect.new()
	insignia.texture = load("res://assets/generated/edu_insignia.png")
	insignia.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	insignia.custom_minimum_size = Vector2(96, 96)
	insignia.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(insignia)
	var mascot := TextureRect.new()
	mascot.texture = load("res://assets/generated/mascot_mishmish.png")
	mascot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mascot.custom_minimum_size = Vector2(96, 96)
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(mascot)
	var ht := VBoxContainer.new()
	ht.add_theme_constant_override("separation", 2)
	head.add_child(ht)
	ht.add_child(_lbl("MOON RUN: GALAXY EXPLORERS", 40, UiTheme.GOLD))
	ht.add_child(_lbl("Egypt x NASA - a friendly space adventure for curious kids!", 18, UiTheme.CYAN))
	var segs := HBoxContainer.new()
	segs.add_theme_constant_override("separation", 10)
	v.add_child(segs)
	for s in Education.segments():
		segs.add_child(_segment_chip(s))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	v.add_child(btns)
	var tutBtn := Button.new()
	tutBtn.name = "TutBtn"
	tutBtn.text = "Tutorial"
	tutBtn.accessibility_name = "Start the tutorial"
	tutBtn.pressed.connect(_start_tutorial)
	UiTheme.style_button(tutBtn, "cyan")
	btns.add_child(tutBtn)
	var start := Button.new()
	start.name = "StartBtn"
	start.text = "Start mission"
	start.accessibility_name = "Choose a mission"
	start.pressed.connect(_show_select)
	UiTheme.style_button(start, "gold")
	btns.add_child(start)
	var lib := Button.new()
	lib.name = "LibBtn"
	lib.text = "Knowledge library"
	lib.pressed.connect(_open_library)
	UiTheme.style_button(lib, "magenta")
	btns.add_child(lib)
	var motion := CheckButton.new()
	motion.text = "Calmer motion"
	motion.tooltip_text = "Turns down flashes, screen shake, and pulsing. Helpful if motion is uncomfortable."
	motion.accessibility_name = "Calmer motion"
	motion.add_theme_font_size_override("font_size", 16)
	motion.add_theme_color_override("font_color", UiTheme.TEXT)
	motion.toggled.connect(_on_motion_toggled)
	v.add_child(motion)
	var keys := _lbl("Use the arrow keys or WASD to walk around the ship, and press E to look at a room.", 16, UiTheme.TEXT_DIM)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(keys)


func _on_motion_toggled(on: bool) -> void:
	reduce_motion = on
	UiTheme.reduce_motion = on


func _segment_chip(s: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.MAGENTA, 12))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	box.add_child(inner)
	var icon := TextureRect.new()
	var p := "res://assets/generated/%s.png" % str(s.get("icon", ""))
	if ResourceLoader.exists(p):
		icon.texture = load(p)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(40, 40)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inner.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.add_child(_lbl(str(s.get("name", "")), 15, UiTheme.GOLD))
	var bl := _lbl(str(s.get("blurb", "")), 13, UiTheme.TEXT)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size = Vector2(150, 0)
	col.add_child(bl)
	inner.add_child(col)
	return box


func _build_select_page() -> void:
	select_page = _make_page()
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	select_page.add_child(v)
	v.add_child(_lbl("CHOOSE A DESTINATION", 32, UiTheme.GOLD))
	var sub := _lbl("Each card shows the worlds, how hard the route is, and how many jumps it takes.", 16, UiTheme.TEXT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for m in GameData.MISSIONS:
		grid.add_child(_mission_card(m))


func _mission_card(m: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.CYAN, 18))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(420, 0)
	var margin := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 8)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)
	var pics := HBoxContainer.new()
	pics.alignment = BoxContainer.ALIGNMENT_CENTER
	pics.add_theme_constant_override("separation", 14)
	pics.add_child(_planet_icon(str(m.get("from", "planet_earth")), 88.0))
	pics.add_child(_lbl(">", 28, UiTheme.MAGENTA))
	pics.add_child(_planet_icon(str(m.get("to", "planet_moon")), 88.0))
	col.add_child(pics)
	var from_n := str(m.get("from", "")).replace("planet_", "").capitalize()
	var to_n := str(m.get("to", "")).replace("planet_", "").capitalize()
	var title := _lbl("%s   to   %s" % [from_n, to_n], 20, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var route_name := _lbl(str(m.get("name", "")), 15, UiTheme.CYAN)
	route_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(route_name)
	var blurb := _lbl(str(m.get("blurb", "")), 14, UiTheme.TEXT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(blurb)
	var diff := float(m.get("difficulty", 1.0))
	var jumps := int(m.get("beacons", 8))
	var meta := _lbl("%s    %s    %d jumps" % [_diff_label(diff), _diff_stars(diff), jumps], 15, UiTheme.PINK)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(meta)
	col.add_child(_route_dots(jumps))
	var note := _lbl("Gold dot is the start. Pink dot is the destination.", 13, UiTheme.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)
	var b := Button.new()
	b.name = "Mission_%s" % m["id"]
	b.text = "Fly this route"
	b.accessibility_name = "Fly %s. %s. %d jumps." % [str(m.get("name", "")), _diff_label(diff), jumps]
	b.pressed.connect(_start_mission.bind(m))
	UiTheme.style_button(b, "gold")
	col.add_child(b)
	return panel


func _planet_icon(id: String, px: float) -> TextureRect:
	var t := TextureRect.new()
	var path := "res://assets/generated/%s.png" % id
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


func _route_dots(n: int) -> Control:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 5)
	var count := clampi(n, 2, 14)
	for i in count:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(12, 12)
		if i == 0:
			d.color = UiTheme.GOLD
		elif i == count - 1:
			d.color = UiTheme.MAGENTA
		else:
			d.color = UiTheme.CYAN_DIM
		box.add_child(d)
	return box


func _diff_label(d: float) -> String:
	if d < 1.15:
		return "Easy"
	if d < 1.5:
		return "Medium"
	return "Hard"


func _diff_stars(d: float) -> String:
	var n := 1
	if d >= 1.5:
		n = 3
	elif d >= 1.15:
		n = 2
	return "* ".repeat(n).strip_edges()


func _build_launch_page() -> void:
	launch_page = _make_page()
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	launch_page.add_child(v)
	v.add_child(_lbl("LAUNCH CHECKLIST", 30, UiTheme.GOLD))
	var hint := _lbl("Launch segment. Mission Control wants 80% of the rows to say READY. Words tell you the status, not only the color.", 16, UiTheme.TEXT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var design := _lbl("", 15, UiTheme.TEXT)
	design.name = "DesignInfo"
	design.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(design)
	_design_btn = Button.new()
	_design_btn.text = "Why this mission"
	_design_btn.accessibility_name = "Show the instruments and engineering trade-off"
	_design_btn.pressed.connect(_toggle_design_info)
	UiTheme.style_button(_design_btn, "magenta", true)
	v.add_child(_design_btn)
	_design_extra = _lbl("", 15, UiTheme.TEXT_DIM)
	_design_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_design_extra.visible = false
	v.add_child(_design_extra)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "CheckList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var go := Button.new()
	go.name = "GoBtn"
	go.text = "LAUNCH"
	go.pressed.connect(_launch_now.bind(false))
	UiTheme.style_button(go, "gold")
	v.add_child(go)
	var go_any := Button.new()
	go_any.name = "GoAnyBtn"
	go_any.text = "Launch anyway (risky)"
	go_any.pressed.connect(_launch_now.bind(true))
	UiTheme.style_button(go_any, "magenta")
	v.add_child(go_any)


func _build_map_view() -> void:
	map_view = SectorMapView.new()
	map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_view.travel_requested.connect(_travel)
	stage.add_child(map_view)
	map_view.visible = false


func _build_ship_view() -> void:
	ship_view = ShipView.new()
	ship_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	ship_view.system_clicked.connect(_add_power)
	ship_view.system_right_clicked.connect(_remove_power)
	stage.add_child(ship_view)
	ship_view.visible = false

	# Walk-the-ship interior: the friendly, hands-on way to inspect stations.
	interior = ShipInterior.new()
	interior.set_anchors_preset(Control.PRESET_FULL_RECT)
		# The interior must also go quiet while a planet surface is on top, so E on
	# the surface never triggers a room panel behind it.
	interior.input_gate = Callable(self, "_input_blocked")
	interior.room_inspected.connect(_on_interior_inspect)
	stage.add_child(interior)
	interior.visible = false


func _active_space_page() -> Control:
	if explore_mode:
		return interior
	return ship_view


func _set_space_view() -> void:
	var p := _active_space_page()
	if ship_view:
		ship_view.visible = (p == ship_view)
	if interior:
		interior.visible = (p == interior)


func _toggle_explore() -> void:
	explore_mode = not explore_mode
	_set_space_view()
	if get_viewport():
		get_viewport().gui_release_focus()
	if explore_mode and interior and gs != null:
		interior.set_state(gs)
	_build_space_actions()
	_refresh()


func _on_interior_inspect(sys: String) -> void:
	_open_room_info(sys)
	if interior and gs != null and not _all_checked_awarded and interior.checked.size() >= ShipInterior.STATIONS.size():
		_all_checked_awarded = true
		gs.apply_fx({"science": 8, "morale": 6})
		_log("[color=#9fe0b0]You checked every station on the ship. Bonus science! Now you are ready to fly.[/color]")
		_refresh()


# Land on the Moon / Mars: walk the surface, collect samples, then return.
func _land_and_collect(body: String) -> void:
	if surface == null:
		return
	surface.open(gs, body)
	var result: Variant = await surface.finished
	var got := 0
	if result is Array and (result as Array).size() > 0:
		got = int((result as Array)[0])
		# Log each sample so the final report can describe what came home.
		if (result as Array).size() > 1 and (result as Array)[1] is Array:
			for item in (result as Array)[1]:
				if item is Dictionary:
					gs.record_sample(body, item)
	_log("[color=#8fe0ff]Back aboard the Nefer-1 with %d sample%s stowed safely.[/color]" % [got, "" if got == 1 else "s"])
	_refresh()


func _make_page() -> Control:
	var p := Control.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.visible = false
	stage.add_child(p)
	return p


# =============================================================================
# Top bar / dashboard refresh
# =============================================================================
func _refresh() -> void:
	if gs == null:
		return
	_flush_notices()
	for k in GameData.RES_ORDER:
		var v := int(round(float(gs.resources[k])))
		(res_labels[k] as Label).text = str(v)
		if res_bars.has(k):
			(res_bars[k] as ProgressBar).value = v
		if res_words.has(k):
			var word := UiTheme.status_word(float(v))
			var wl := res_words[k] as Label
			wl.text = word
			wl.add_theme_color_override("font_color", UiTheme.status_color(float(v)))
	for k in GameData.COUNTER_ORDER:
		if cnt_labels.has(k):
			(cnt_labels[k] as Label).text = "%s %d" % [GameData.COUNTER_META[k]["short"], int(gs.counters[k])]
	if cnt_labels.has("science"):
		(cnt_labels["science"] as Label).text = "Science %d" % gs.science
	if pack_label:
		pack_label.text = "Backpack: %d spare parts, %d hint crystals" % [
			int(gs.counters.get("parts", 0)), int(gs.counters.get("ordnance", 0))]
	# dashboard
	var rc := gs.ready_check()
	var ready_word := "READY" if rc >= 0.8 else "NEEDS WORK"
	ready_label.text = "Ready check: %s  %d%%" % [ready_word, int(rc * 100)]
	ready_label.add_theme_color_override("font_color", UiTheme.GOOD if rc >= 0.8 else UiTheme.WARN)
	var spare := gs.power_spare_pct()
	var spare_word := "GOOD" if spare >= 0.35 else "LOW"
	var brown := float(gs.resources["power"]) <= 1.0
	margin_label.text = "Spare power: %s %d%% (target 35%% or more) used %d/%d%s" % [spare_word, int(spare * 100), gs.power_used(), gs.reactor, ("  BROWN-OUT" if brown else "")]
	margin_label.add_theme_color_override("font_color", UiTheme.GOOD if spare >= 0.35 else UiTheme.BAD)
	signal_label.text = "Telecom signal: " + gs.signal_label()
	evasion_label.text = "Evasion: %d%%    Jump cost: %d fuel" % [int(gs.evasion() * 100), int(gs.jump_cost())]
	for s in GameData.SYSTEMS:
		var id: String = s["id"]
		var lvl: int = gs.sys_level(id)
		var maxl: int = int(s["max"])
		(sys_rows[id]["lvl"] as Label).text = "%d/%d" % [lvl, maxl]
		var integ := float(gs.sys_integrity.get(id, 1.0))
		(sys_rows[id]["bar"] as ProgressBar).value = integ
	info_label.text = "%s  |  Day %d  |  %s" % [str(gs.mission.get("name", "")), gs.day, _phase_text()]
	if timeline:
		timeline.set_events(_timeline_events())
	# Contextual tips based on the live state (each shown at most once).
	if tips:
		if float(gs.resources["oxygen"]) < 35.0:
			tips.show_tip("life_support")
		for id in gs.sys_integrity:
			if float(gs.sys_integrity[id]) < 1.0:
				tips.show_tip("reliability")
				break
	if ship_view and ship_view.visible:
		ship_view.queue_redraw()
	if interior and interior.visible:
		interior.queue_redraw()
	_update_context()


func _phase_text() -> String:
	if gs.turn_phase == "return":
		return "Return leg"
	return "Outbound"


func _toggle_details() -> void:
	details_open = not details_open
	if details_box:
		details_box.visible = details_open
	if details_btn:
		details_btn.text = "Hide details" if details_open else "Ship details"


func _toggle_systems() -> void:
	systems_open = not systems_open
	if systems_box:
		systems_box.visible = systems_open
	if systems_btn:
		systems_btn.text = "Hide systems" if systems_open else "All systems"


func _dismiss_focus() -> void:
	_dismissed_key = _focus_key
	_focus_lock = false
	_apply_focus("", "", [], false)
	_layout_system_rows()
	if next_label:
		next_label.text = _next_action_text()


func _next_action_text() -> String:
	if gs == null:
		return "Choose a mission to begin."
	match screen:
		"launch":
			return "Read the checklist. Launch when most rows say READY."
		"map":
			return "Cyan rings are jumps you can take. The pink ring is your ship."
		"space":
			if float(gs.resources["fuel"]) < gs.jump_cost():
				return "Not enough fuel for another jump. Find a depot or hold position."
			if gs.is_final_node():
				return "This is the last beacon. Finish what is here to complete the leg."
			return "When the ship looks steady, open the sector map and jump."
		_:
			return str(gs.mission.get("name", "Moon Run"))


func _system_needs_attention(id: String) -> bool:
	if gs == null:
		return false
	if float(gs.sys_integrity.get(id, 1.0)) < 0.9:
		return true
	var o2 := float(gs.resources["oxygen"])
	var fuel := float(gs.resources["fuel"])
	var food := float(gs.resources["food"])
	var water := float(gs.resources["water"])
	var hull := float(gs.resources["hull"])
	var morale := float(gs.resources["morale"])
	var power := float(gs.resources["power"])
	match id:
		"oxygen":
			return o2 < 40.0 or not gs.sys_online(id)
		"engines":
			return fuel < 30.0 or power <= 15.0
		"bio":
			return food < 30.0 or water < 30.0
		"repair":
			return hull < 40.0
		"medbay":
			return morale < 35.0
		"comms":
			return gs.signal_db() < 3.0
		"shields":
			return hull < 45.0
		_:
			return false


func _layout_system_rows() -> void:
	if systems_box == null or attention_box == null:
		return
	var urgent := 0
	var focusing := not _current_focus_rooms.is_empty()
	for s in GameData.SYSTEMS:
		var id: String = s["id"]
		var row: Control = sys_row_nodes.get(id)
		if row == null:
			continue
		var hot := _system_needs_attention(id) or (id in _current_focus_rooms)
		var dest: Node = attention_box if hot else systems_box
		if row.get_parent() != dest:
			row.get_parent().remove_child(row)
			dest.add_child(row)
			if dest == systems_box and dest.get_child_count() > 1:
				dest.move_child(row, dest.get_child_count() - 2)
		row.modulate.a = 1.0 if (not focusing or id in _current_focus_rooms) else 0.38
		if hot:
			urgent += 1
	if attention_title:
		attention_title.visible = urgent > 0
		attention_title.text = "NEEDS ATTENTION  (%d)" % urgent
	if systems_btn:
		systems_btn.text = "Hide systems" if systems_open else "All systems"
	if details_btn:
		details_btn.text = "Hide details" if details_open else "Ship details"
	if timeline:
		timeline.modulate.a = 0.4 if focusing else 1.0


func _update_context() -> void:
	if not _focus_lock:
		if _focus_key == "action:scan" and gs != null and gs.sys_online("sensors"):
			_apply_focus("", "", [], false)
		elif _focus_key == "action:bio" and gs != null and gs.sys_online("bio"):
			_apply_focus("", "", [], false)
		elif _focus_key == "action:power" and gs != null and gs.power_spare() > 0:
			_apply_focus("", "", [], false)
		var auto := _auto_focus()
		var can_replace := _focus_key == "" or _focus_key.begins_with("auto:") or _focus_key.begins_with("intro:") or _focus_key.begins_with("event:") or _focus_key.begins_with("action:")
		if can_replace and not auto.is_empty():
			if _focus_key != str(auto["key"]):
				_apply_focus(str(auto["key"]), str(auto["text"]), auto["rooms"], false)
		elif _focus_key.begins_with("auto:"):
			_apply_focus("", "", [], false)
		elif _focus_key == "":
			_maybe_introduce()
	if next_label:
		if _focus_key != "" and focus_banner and focus_banner.visible:
			if _current_focus_rooms.is_empty():
				next_label.text = "Follow the note under the ship, or press Got it."
			else:
				next_label.text = "The highlighted rooms are the ones that matter right now."
		else:
			next_label.text = _next_action_text()
	_layout_system_rows()
	_sync_tip_note()


func _maybe_introduce() -> void:
	if gs == null or tutorial_active or _focus_lock or screen != "space":
		return
	if _tutorial_done:
		_introduced["flight"] = true
		_introduced["crew"] = true
		_introduced["scan"] = true
	if not _introduced.has("flight"):
		_introduced["flight"] = true
		_apply_focus("intro:flight", "Click a room to route power. Right-click takes it back. The small i explains the real science.", ["engines", "piloting"], false)
		return
	if gs.jumps >= 1 and not _introduced.has("crew"):
		_introduced["crew"] = true
		_apply_focus("intro:crew", "Click a crew member, then a room, to station them. They make that system work better.", ["oxygen", "bio"], false)
		return
	if gs.scan_count() == 0 and gs.jumps >= 2 and not _introduced.has("scan"):
		_introduced["scan"] = true
		_apply_focus("intro:scan", "Power the Science Lab, then press Scan. Logged data is what the mission is scored on.", ["sensors"], false)
		return
	if float(gs.resources["food"]) < 55.0 and not _introduced.has("bio"):
		_introduced["bio"] = true
		_apply_focus("intro:bio", "Food is dropping. Power the BioNutrients Bay, then press Bio bay to grow a batch.", ["bio"], false)


func _auto_focus() -> Dictionary:
	if gs == null or not (screen in ["space", "launch", "map"]):
		return {}
	var checks: Array = [
		["oxygen", float(gs.resources["oxygen"]) <= 30.0, "Oxygen is low. Add power to the Oxygen Scrubbers, or station a crew member there.", ["oxygen"]],
		["hull", float(gs.resources["hull"]) <= 35.0, "The hull is damaged. Power the Repair Bay before the next hit.", ["repair"]],
		["fuel", float(gs.resources["fuel"]) <= 20.0 and not gs.is_final_node(), "Fuel is low. Jump only if you can pay the cost, or look for a depot.", ["engines"]],
		["food", float(gs.resources["food"]) <= 25.0, "Food is low. Power the BioNutrients Bay and grow a batch.", ["bio"]],
		["water", float(gs.resources["water"]) <= 25.0, "Water is low. The BioNutrients Bay slows how fast the crew uses it.", ["bio"]],
		["morale", float(gs.resources["morale"]) <= 30.0, "Morale is low. Put someone in the Medbay to steady the crew.", ["medbay"]],
		["power", float(gs.resources["power"]) <= 12.0, "The battery is nearly empty. Turn off a system you do not need right now.", ["engines"]],
		["signal", gs.signal_db() < 1.5, "Earth can barely hear you. Add power to Comms or the next call will be missed.", ["comms"]],
	]
	for s in GameData.SYSTEMS:
		var sid: String = s["id"]
		if float(gs.sys_integrity.get(sid, 1.0)) < 0.75:
			checks.append(["dmg_" + sid, true, "%s is damaged. Power the Repair Bay and keep a spare part aboard." % str(s["name"]), ["repair", sid]])
	for c in checks:
		if not bool(c[1]):
			continue
		var key := "auto:" + str(c[0])
		if key == _dismissed_key:
			continue
		return {"key": key, "text": str(c[2]), "rooms": c[3]}
	return {}


func _rooms_for_alert(title: String) -> Array:
	var t := title.to_upper()
	if "OXYGEN" in t or "AIR" in t:
		return ["oxygen"]
	if "FUEL" in t:
		return ["engines"]
	if "WATER" in t or "TOILET" in t:
		return ["bio"]
	if "HULL" in t or "METEOR" in t:
		return ["repair"]
	if "SOLAR" in t or "FLARE" in t or "RADIATION" in t:
		return ["shields"]
	if "SCAN" in t or "SAMPLE" in t or "CURIOSITY" in t or "PHOBOS" in t:
		return ["sensors"]
	if "SIGNAL" in t or "CALL" in t or "COMM" in t:
		return ["comms"]
	if "MORALE" in t:
		return ["medbay"]
	if "POWER" in t or "SUN" in t or "BATTERY" in t:
		return ["engines"]
	return []


func _concise_alert(title: String, body: String) -> String:
	var sentence := body.split(". ")[0]
	if sentence.length() > 140:
		sentence = sentence.substr(0, 137) + "..."
	if sentence.ends_with("."):
		return "%s. %s" % [title, sentence]
	return "%s. %s." % [title, sentence]


func _apply_focus(key: String, text: String, rooms: Array, lock: bool, ignore_dismiss: bool = false) -> void:
	if key != "" and key == _dismissed_key and not lock and not ignore_dismiss:
		return
	_focus_key = key
	_focus_lock = lock
	if key.begins_with("event:"):
		_focus_ttl = 9.0
	else:
		_focus_ttl = 0.0
	_current_focus_rooms = rooms.duplicate()
	if focus_banner and focus_label:
		focus_banner.visible = text != ""
		focus_label.text = text
	# (Ship details stay closed unless the player opens them, to keep the
	#  screen uncluttered for young explorers.)
	if ship_view:
		ship_view.set_focus_rooms(rooms)
	_layout_focus_chrome()


func _focus_resources() -> Array:
	var out: Array = []
	for room in _current_focus_rooms:
		match str(room):
			"oxygen":
				out.append("oxygen")
			"engines", "piloting":
				out.append("fuel")
				out.append("power")
			"bio":
				out.append("food")
				out.append("water")
			"repair", "shields":
				out.append("hull")
			"medbay":
				out.append("morale")
			"weapons", "sensors", "comms":
				out.append("power")
	return out


func _resource_expanded(k: String, v: float) -> bool:
	if k in ["oxygen", "fuel", "hull"]:
		return true
	if v < 50.0:
		return true
	return k in _focus_resources()


func _actions_for_focus() -> Array:
	var out: Array = []
	for room in _current_focus_rooms:
		match str(room):
			"bio":
				out.append("bio")
			"sensors":
				out.append("scan")
			"engines", "piloting":
				out.append("map")
			"repair", "shields":
				out.append("hull")
	return out


func _layout_focus_chrome() -> void:
	var focusing := not _current_focus_rooms.is_empty()
	var related := _focus_resources()
	for k in res_boxes:
		var box: Control = res_boxes[k]
		var v := 100.0
		if gs != null:
			v = float(gs.resources[k])
		var expanded := _resource_expanded(k, v)
		box.custom_minimum_size.x = 112 if expanded else 66
		if res_bars.has(k):
			(res_bars[k] as CanvasItem).visible = expanded
		if res_words.has(k):
			(res_words[k] as CanvasItem).visible = expanded
		var hot: bool = (not focusing) or related.has(str(k)) or v < 25.0
		box.modulate.a = 1.0 if hot else 0.42
	if log_box:
		log_box.modulate.a = 0.5 if focusing else 1.0
	if tip_host:
		tip_host.modulate.a = 0.45 if focusing else 1.0
	var wanted := _actions_for_focus()
	for id in _action_buttons:
		var b: Button = _action_buttons[id]
		if not focusing or wanted.is_empty() or id in wanted:
			b.modulate.a = 1.0
		else:
			b.modulate.a = 0.45


func _log(t: String) -> void:
	_log_lines.append(t)
	if _log_lines.size() > 60:
		_log_lines.pop_front()
	if log_box:
		log_box.clear()
		for line in _log_lines:
			log_box.append_text(line + "\n")
	if "ff9a6b" in t or "ffaa66" in t or "ff7a6b" in t:
		_set_log_open(true)


func _toggle_log() -> void:
	_set_log_open(not log_open)


func _set_log_open(on: bool) -> void:
	log_open = on
	if log_box:
		log_box.visible = on and top_bar != null and top_bar.visible
		log_box.custom_minimum_size.y = 110 if on else 0
	if log_toggle:
		log_toggle.text = "Hide mission log" if on else "Mission log"


func _replay_tip() -> void:
	if tips:
		tips.replay()


func _sync_tip_note() -> void:
	var hud_on := top_bar != null and top_bar.visible
	if _tip_note_btn:
		_tip_note_btn.visible = hud_on and tips != null and tips.has_note() and not tips.is_open()


func _on_tip_presence(on: bool) -> void:
	if tip_host:
		tip_host.visible = on and top_bar != null and top_bar.visible
		tip_host.custom_minimum_size.y = 112 if on else 0
	_sync_tip_note()


func _toggle_design_info() -> void:
	if _design_extra == null:
		return
	_design_extra.visible = not _design_extra.visible
	if _design_btn:
		_design_btn.text = "Hide mission notes" if _design_extra.visible else "Why this mission"


# =============================================================================
# Menu / mission select / launch
# =============================================================================
# The mission HUD (resources, ship systems dashboard, timeline, log) belongs to
# mission preparation and flight - not to the main menu or mission select.
func _set_hud_visible(on: bool) -> void:
	if top_bar:
		top_bar.visible = on
	if hud_side:
		hud_side.visible = on
	if dash_scroll:
		dash_scroll.visible = on
	if tip_host:
		tip_host.visible = on and tips != null and tips.is_open()
	if info_label:
		info_label.visible = on
	if timeline:
		timeline.visible = on
	if log_toggle:
		log_toggle.visible = on
	if log_box:
		log_box.visible = on and log_open
	_sync_tip_note()


func _show_menu() -> void:
	screen = "menu"
	_traveling = false
	tutorial_active = false
	_focus_lock = false
	_apply_focus("", "", [], false)
	_set_hud_visible(false)
	if back_btn:
		back_btn.visible = false
	_stop_music()
	if radio:
		radio.play_static(false)
	if tutorial and tutorial.has_method("stop"):
		tutorial.stop()
	_show_page(menu_page)
	var start := menu_page.find_child("StartBtn", true, false) as Button
	if start:
		start.grab_focus()


func _show_select() -> void:
	screen = "select"
	_set_hud_visible(false)
	_show_page(select_page)


func _show_page(p: Control) -> void:
	for pg in [menu_page, select_page, launch_page, map_view, ship_view, interior]:
		if pg:
			pg.visible = (pg == p)
	_clear_actions()
	# navigation history for the universal Back button
	var id := _page_id(p)
	if id != "":
		if _nav_back_mode:
			_nav_back_mode = false
		elif _nav_history.is_empty() or _nav_history.back() != id:
			_nav_history.append(id)
	if back_btn:
		back_btn.visible = id != "menu"


func _start_mission(m: Dictionary) -> void:
	gs = GameState.new()
	gs.new_run(m)
	_mission_ended = false
	_pending_node = false
	_traveling = false
	_quiz_left.clear()
	_calls_left = range(GameData.CALLS.size())
	_calls_left.shuffle()
	_events_left = range(GameData.EVENTS.size())
	_events_left.shuffle()
	_log_lines.clear()
	_log("[color=#8fb4ff]Mission: %s. Ground Control: 'Good luck, Captain.'[/color]" % m["name"])
	_log("Fun fact: " + str(m["fact"]))
	_introduced.clear()
	_logged_map_hint = false
	_focus_ttl = 0.0
	_dismissed_key = ""
	# Opening briefing (commander explains the mission and the four segments).
	_set_hud_visible(true)
	_build_briefing(m)
	_refresh()

func _build_launch_checklist() -> void:
	screen = "launch"
	_show_page(launch_page)
	var list := launch_page.find_child("CheckList", true, false) as VBoxContainer
	for c in list.get_children():
		c.queue_free()
	for s in GameData.SYSTEMS:
		list.add_child(_check_row(_sys_readiness(s), str(s["name"])))
	for k in GameData.RES_ORDER:
		var amount := float(gs.resources[k])
		var st2 := 2 if amount >= 50.0 else (1 if amount >= 25.0 else 0)
		list.add_child(_check_row(st2, "%s  %d" % [str(GameData.RES_META[k]["name"]), int(amount)]))
	var rc := gs.ready_check()
	var go := launch_page.find_child("GoBtn", true, false) as Button
	go.disabled = rc < 0.8
	go.text = "LAUNCH  (%d%% ready)" % int(rc * 100)
	var go_any := launch_page.find_child("GoAnyBtn", true, false) as Button
	go_any.visible = rc < 0.8
	_fill_design_info()
	tips.show_tip("launch")
	_refresh()


func _fill_design_info() -> void:
	var lbl := launch_page.find_child("DesignInfo", true, false) as Label
	if lbl == null:
		return
	var em := Education.mission(str(gs.mission.get("id", "")))
	var defs := Education.instruments()
	var names: Array = []
	for iid in em.get("instruments", []):
		names.append(str(defs.get(iid, {}).get("name", iid)))
	var lines: Array = []
	lines.append("OBJECTIVE: " + str(em.get("objective", "Explore the target and return scientific data.")))
	if str(em.get("question", "")) != "":
		lines.append("QUESTION: " + str(em.get("question", "")))
	lbl.text = "\n".join(lines)
	if _design_extra:
		var extra: Array = []
		extra.append("INSTRUMENTS: " + (", ".join(names) if not names.is_empty() else "standard suite"))
		extra.append("Feasibility asks if the systems, supplies and instruments are ready. A trade study is the choice to carry more instruments: they find more science, and they draw more power.")
		extra.append("Every instrument adds mass and draws power, so electricity is shared between science, life support and the engines.")
		_design_extra.text = "\n".join(extra)
		_design_extra.visible = false
	if _design_btn:
		_design_btn.text = "Why this mission"


func _check_row(st: int, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var word := "READY"
	var col := UiTheme.GOOD
	if st == 1:
		word = "CAUTION"
		col = UiTheme.WARN
	elif st == 0:
		word = "NOT READY"
		col = UiTheme.BAD
	var tag := _lbl(word, 15, col)
	tag.custom_minimum_size = Vector2(120, 28)
	row.add_child(tag)
	row.add_child(_lbl(label_text, 16, UiTheme.TEXT))
	return row


# Readiness state for the launch checklist: 2 = ready, 1 = caution, 0 = unavailable.
func _sys_readiness(s: Dictionary) -> int:
	var online: bool = gs.sys_online(str(s["id"]))
	var integ := float(gs.sys_integrity.get(str(s["id"]), 1.0))
	if not online:
		return 0
	if integ < 0.5:
		return 0
	if integ < 0.9 or gs.sys_level(str(s["id"])) < int(s["start"]):
		return 1
	return 2


func _launch_now(risky: bool) -> void:
	if risky:
		gs.apply_fx({"morale": -6, "hull": -8})
		_log("[color=#ff9a6b]You launch with missing margins. Engineering winces.[/color]")
		if _fail_if_over():
			return
	else:
		_log("[color=#9fe0b0]All green. Launch! Next stop: %s.[/color]" % str(gs.mission.get("to", "")).replace("planet_", "").capitalize())
	# Real 2D cutscenes: lift-off, then departure from Earth.
	await _play_cutscene("launch")
	await _play_cutscene("depart_earth", {"from": str(gs.mission.get("from", "planet_earth"))})
	_enter_space(false)
	if tips:
		tips.show_tip("engineering")
	# the first call often arrives on the way out
	if randf() < 0.6 and _calls_left.size() > 0:
		_pending_node = false
		_fire_call()


# =============================================================================
# Space screen + sector map
# =============================================================================
func _enter_space(open_map: bool) -> void:
	screen = "space"
	_show_page(_active_space_page())
	ship_view.set_state(gs)
	interior.set_state(gs)
	# No HUD button keeps keyboard focus, so walk keys and E never activate one.
	if get_viewport():
		get_viewport().gui_release_focus()
	_build_space_actions()
	_refresh()
	_play_music("res://assets/generated/audio/music_space.mp3")
	if radio:
		radio.play_static(true)
		radio.set_delay(_signal_delay_text())
	_radio_timer = rng.randf_range(14.0, 26.0)
	if open_map:
		_open_map()


func _build_space_actions() -> void:
	_clear_actions()
	action_bar.add_child(_action_button("Systems board" if explore_mode else "Walk the ship", "", _toggle_explore, "view"))
	action_bar.add_child(_action_button("Sector map", "M", _open_map, "map"))
	action_bar.add_child(_action_button("Bio bay", "B", _open_food, "bio"))
	action_bar.add_child(_action_button("Scan", "C", _scan, "scan"))
	var hull_cb := func() -> void:
		var f: Dictionary = GameData.FLEET[rng.randi() % GameData.FLEET.size()]
		_popup("HULL STATUS", "Space segment", "Hull at %d%%. %s" % [int(gs.resources["hull"]), f["name"] + " says: " + f["fact"]],
			"Tip: keep about 35% spare power, the same way real missions keep a safety margin.", [{"label": "Acknowledged", "msg": ""}], null)
	action_bar.add_child(_action_button("Hull status", "", hull_cb, "hull"))
	action_bar.add_child(_action_button("Library", "", _open_library, "library"))
	_layout_focus_chrome()


func _action_button(text: String, shortcut: String, cb: Callable, id: String = "") -> Button:
	var b := Button.new()
	b.text = text if shortcut == "" else "%s  [%s]" % [text, shortcut]
	b.tooltip_text = text
	b.accessibility_name = text
	b.pressed.connect(cb)
	UiTheme.style_button(b, "cyan", true)
	if id != "":
		_action_buttons[id] = b
	return b


func _open_map() -> void:
	screen = "map"
	if radio:
		radio.play_static(false)
	_show_page(map_view)
	map_view.set_state(gs)
	_clear_actions()
	var back := Button.new()
	back.text = "Back to ship"
	back.pressed.connect(_enter_space.bind(false))
	UiTheme.style_button(back, "magenta", true)
	action_bar.add_child(back)
	if not _logged_map_hint:
		_logged_map_hint = true
		_log("Choose a jump. Each jump costs fuel and a day of supplies.")
	tips.show_tip("navigation")
	_refresh()


func _travel(target: int) -> void:
	# Guard: ignore double clicks while a jump is already playing out.
	if _traveling or gs == null or gs.game_over or _mission_ended:
		return
	var cost := gs.jump_cost()
	if float(gs.resources["fuel"]) < cost:
		# Never leave a kid stuck: a tow truck helps, or the mission ends gently.
		if not gs.rescue_fuel():
			_end_mission(false)
			return
		_refresh()
	_traveling = true
	_warp_flash()
	# Move first, so reaching the last stop with an empty tank is still a win.
	gs.at_node = target
	gs.beacons[target]["visited"] = true
	gs.apply_fx({"fuel": -cost})
	var rep: Dictionary = gs.advance_beacon()
	for w in rep.get("warnings", []):
		_log("[color=#ffaa66]%s[/color]" % w)
	_log("[b]Jump %d[/b]: -%d fuel. Supplies tick down." % [gs.jumps, int(cost)])
	if gs.game_over:
		_traveling = false
		_end_mission(false)
		return
	if radio:
		radio.play_static(false)
	# A short animated travel cutscene plays between beacons.
	await _play_cutscene("travel", {"planet": str(gs.mission.get("to", "planet_moon")), "caption": "ZOOMING THROUGH SPACE  -  jump %d" % gs.jumps})
	_traveling = false
	if gs == null or _mission_ended or screen == "menu":
		return
	_enter_space(false)
	# Ground segment: Earth calls happen on a chance, then the node resolves.
	if randf() < 0.45 and _calls_left.size() > 0:
		_pending_node = true
		_fire_call()
	else:
		_resolve_node()


func _warp_flash() -> void:
	if _warp == null or UiTheme.reduce_motion:
		return
	# Meteor field effect: brief purple-blue haze with random twinkles
	_warp.color = Color(0.35, 0.5, 0.95, 0.28)
	var tw := create_tween()
	for i in range(3):
		var c := Color.from_hsv(0.62 + randf_range(-0.08, 0.1), 0.45, 0.85, 0.28)
		tw.tween_property(_warp, "color", c, 0.05).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(_warp, "color:a", 0.0, 0.4).set_trans(Tween.TRANS_LINEAR)


func _resolve_node() -> void:
	var b: Dictionary = gs.beacons[gs.at_node]
	if bool(b["done"]):
		return
	b["done"] = true
	match str(b["type"]):
		"event": _fire_event()
		"hazard": _start_combat()
		"planet": _resolve_planet()
		"store": _resolve_store()
		"outpost": _arrive()
		_:
			_log("Empty space. The stars are quiet. You drink something beige.")
			_prompt_next()

func _scan() -> void:
	# Scientific instrument scan of the local environment (deep-space survey).
	_open_scan("anomaly", false)


# =============================================================================
# Node resolutions
# =============================================================================
func _fire_event() -> void:
	if _events_left.size() == 0:
		_events_left = range(GameData.EVENTS.size())
		_events_left.shuffle()
	var e: Dictionary = GameData.EVENTS[_events_left.pop_front()]
	_popup(str(e["title"]), "Ship alert", str(e["text"]), str(e["fact"]), e["choices"], e)


func _fire_call() -> void:
	if gs == null:
		return
	if _calls_left.size() == 0:
		_calls_left = range(GameData.CALLS.size())
		_calls_left.shuffle()
	var c: Dictionary = GameData.CALLS[_calls_left.pop_front()]
	# Comms needs enough signal margin to actually take the call.
	if gs.signal_db() < 1.5:
		_log("[color=#ff9a6b]Signal too weak (%.1f dB). You miss a call from %s![/color]" % [gs.signal_db(), c["caller"]])
		gs.apply_fx({"morale": -4})
		_apply_focus("auto:signal", "That call from %s never connected. Add power to Comms before the next one." % str(c["caller"]), ["comms"], true, true)
		_layout_system_rows()
		_refresh()
		if _pending_node:
			_pending_node = false
			_resolve_node()
		return
	# Educational context for the Ground segment.
	tips.show_tip("communications")
	tips.show_tip("signal_delay")
	# The sliding radio panel replaces the old text popup for calls.
	if radio:
		radio.set_state(gs)
		radio.set_delay(_signal_delay_text())
		radio.queue_call(c)
		_apply_focus("event:call", "%s is calling. Read the message, then choose one reply." % str(c["caller"]), ["comms"], true)
		_layout_system_rows()
	else:
		_popup(str(c["caller"]) + " IS CALLING", str(c["role"]), str(c["text"]), str(c["fact"]), c["choices"], null)


func _resolve_planet() -> void:
	var body := str(gs.mission.get("to", "planet_moon"))
	await _play_cutscene("planet_approach", {"planet": body, "caption": "PLANET APPROACH - science target"})
	# Get off the ship and walk the surface to collect samples.
	if body in ["planet_moon", "planet_mars"]:
		await _land_and_collect(body)
	# Scientific observation: run the instruments and show real measurements.
	_open_scan(body, true)


func _resolve_store() -> void:
	_popup("RESUPPLY DEPOT", "A friendly cargo hauler drifts alongside",
		"A depot ship offers a one-time top-up. They will also trade science for spare parts.",
		"Fun fact: Deep-space resupply is a real logistics challenge - every kilogram has to come from somewhere.",
		[
			{"label": "Refuel & resupply (fuel +22, food +12, water +12, power +12)", "fx": {"fuel": 22, "food": 12, "water": 12, "power": 12}, "msg": "Tanks full. The hauler waves goodbye."},
			{"label": "Trade 6 science for 3 spare parts", "fx": {"science": -6, "parts": 3}, "msg": "A fair swap. Engineering is thrilled."},
			{"label": "Move on", "fx": {}, "msg": "You leave with what you have."},
		], null)


func _arrive() -> void:
	if gs.return_trip and gs.turn_phase == "space":
		await _play_cutscene("arrival", {"planet": "planet_moon", "caption": "LUNAR OUTPOST REACHED"})
		gs.turn_phase = "return"
		gs.mission["to"] = "planet_earth"
		gs.mission["from"] = "planet_moon"
		gs._generate_sector()
		gs.at_node = 0
		gs.beacons[0]["visited"] = true
		_log("[color=#ffd86b]Lunar outpost reached! The crew tops up your tanks for the trip home. Grab samples and go.[/color]")
		gs.apply_fx({"science": 25, "morale": 10, "fuel": 45, "food": 15, "water": 15, "oxygen": 15})
		_enter_space(true)
		return
	var dest := str(gs.mission.get("to", "planet_moon"))
	await _play_cutscene("arrival", {"planet": dest, "caption": "ARRIVAL AT DESTINATION"})
	if dest in ["planet_moon", "planet_mars"]:
		await _land_and_collect(dest)
	_end_mission(true)


# =============================================================================
# Combat
# =============================================================================
func _start_combat(mult: float = 1.0) -> void:
	if combat_scene == null:
		combat_scene = CombatScene.new()
		add_child(combat_scene)
		combat_scene.combat_finished.connect(_on_combat_finished)
	combat_scene.start(gs, "Raider", mult)
	combat_scene.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _flush_notices() -> void:
	if gs == null or gs.notices.is_empty():
		return
	var last := ""
	for n in gs.notices:
		last = str(n)
		_log("[color=#ffd86b]%s[/color]" % last)
	gs.notices.clear()
	_apply_focus("event:care", last, [], false)


func _start_puzzle_gate(easy: bool = false) -> void:
	if gs == null:
		return
	var pool: Array = GameData.quiz_pool()
	if easy:
		pool = pool.filter(func(qq): return str(qq["band"]) == "junior")
	if _quiz_left.is_empty():
		for n in range(pool.size()):
			_quiz_left.append(n)
		_quiz_left.shuffle()
	var q: Dictionary = pool[int(_quiz_left.pop_front()) % pool.size()]
	var opts: Array = q["a"].duplicate()
	opts.shuffle()
	var critters := ["A cheeky comet critter", "A sleepy asteroid owl", "A giggling space jellyfish", "A polite moon bunny", "A bouncy star-hopper"]
	_quiz_current = {"q": q, "opts": opts, "removed": [], "easy": easy,
		"critter": critters[rng.randi() % critters.size()]}
	gs.gates_seen += 1
	radio.play_static(false)
	_log("[color=#d9b3ff]PUZZLE GATE: %s floats up with a riddle for you![/color]" % _quiz_current["critter"])
	# The Tractor Beam gives a free hint when it is well powered.
	if gs.sys_effective("weapons") >= 2.0:
		_remove_one_wrong()
		_log("[color=#9fe0b0]Your Tractor Beam grabbed one wrong answer out of the way![/color]")
	_show_quiz()
	tips.show_tip("mission_safety")


func _remove_one_wrong() -> void:
	var q: Dictionary = _quiz_current["q"]
	var wrong: Array = []
	for o in _quiz_current["opts"]:
		if o != q["a"][0] and not (o in _quiz_current["removed"]):
			wrong.append(o)
	if wrong.size() > 1:
		_quiz_current["removed"].append(wrong[rng.randi() % wrong.size()])


func _show_quiz() -> void:
	var q: Dictionary = _quiz_current["q"]
	var choices: Array = []
	for o in _quiz_current["opts"]:
		if o in _quiz_current["removed"]:
			continue
		choices.append({"label": str(o), "quiz": (o == q["a"][0]), "answer": str(o)})
	var crystals := int(gs.counters.get("ordnance", 0))
	if crystals > 0 and (_quiz_current["opts"].size() - _quiz_current["removed"].size()) > 2:
		choices.append({"label": "Use a Hint Crystal (you have %d)" % crystals, "hint": true})
	_popup("PUZZLE GATE", "%s blocks the way and asks:" % _quiz_current["critter"],
		str(q["q"]), "Topic: %s   -   %s says: take your time!" % [str(q["topic"]), GameData.MASCOT], choices, null)


func _on_quiz_answer(ch: Dictionary) -> void:
	var q: Dictionary = _quiz_current["q"]
	var ok := bool(ch["quiz"])
	var title := ""
	var body := ""
	if ok:
		gs.gates_solved += 1
		gs.apply_fx({"science": 10, "morale": 6, "parts": 1, "ordnance": 1})
		title = "CORRECT! WELL DONE!"
		body = "%s\n\n%s\n\nReward: +10 Science, +1 Spare Part, +1 Hint Crystal, happy crew!" % [str(q["a"][0]), str(q["why"])]
		_log("[color=#9fe0b0]Correct! %s[/color]" % str(q["why"]))
	else:
		gs.apply_fx({"science": 3, "morale": 1})
		title = "NICE TRY!"
		body = "The answer was: %s\n\n%s\n\nYou still learned something: +3 Science. The gate opens anyway!" % [str(q["a"][0]), str(q["why"])]
		_log("[color=#ffd86b]Not quite. The answer was %s. %s[/color]" % [str(q["a"][0]), str(q["why"])])
	_refresh()
	_popup(title, "%s smiles and floats away." % _quiz_current["critter"], body,
		"%s the space cat purrs: learning is the real treasure." % GameData.MASCOT,
		[{"label": "Continue the journey", "quiz_done": true}], null)


func _use_hint() -> void:
	if gs == null or _quiz_current.is_empty():
		return
	if int(gs.counters.get("ordnance", 0)) > 0:
		gs.apply_fx({"ordnance": -1}, false)
		_remove_one_wrong()
		_log("[color=#d9b3ff]Hint Crystal used. One wrong answer vanished![/color]")
	_show_quiz()


func _finish_gate() -> void:
	_focus_lock = false
	_quiz_current = {}
	if tutorial_active and tutorial:
		tutorial._on_combat_finished("win")
		return
	_refresh()
	if _fail_if_over():
		return
	tips.show_tip("combat_safety")
	_prompt_next()


func _on_combat_finished(_result: String) -> void:
	# Legacy hook (the old battle screen is no longer used in the kids edition).
	if gs == null:
		return
	_focus_lock = false
	_refresh()
	if _fail_if_over():
		return
	if not tutorial_active:
		_prompt_next()


# =============================================================================
# Audio helpers
# =============================================================================
func _play_music(path: String) -> void:
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.volume_db = -14.0
		add_child(_music)
	if _music_path == path and _music.playing:
		return
	_music_path = path
	var st: AudioStream = load(path)
	_music.stream = st
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	_music.play()


func _stop_music() -> void:
	if _music and _music.playing:
		_music.stop()
	_music_path = ""


func _play_verdict(won: bool) -> void:
	_stop_music()
	# Prefer the user-supplied WIn.mp3 / lose.mp3 if present, else the generated cues.
	var wins := ["res://assets/generated/audio/win.mp3", "res://assets/generated/audio/WIn.mp3"]
	var loses := ["res://assets/generated/audio/lose.mp3", "res://assets/generated/audio/Lose.mp3"]
	var list: Array = wins if won else loses
	for p in list:
		if ResourceLoader.exists(p):
			ZivaSfx.play(self, load(p), 0.0, 0.0)
			return
	ZivaSfx.play(self, load("res://assets/generated/audio/victory.mp3" if won else "res://assets/generated/audio/defeat.mp3"), 0.0, 0.0)


# =============================================================================
# Cutscene / radio helpers
# =============================================================================
func _play_cutscene(seq: String, ctx: Dictionary = {}) -> void:
	if cutscene == null:
		return
	cutscene.play(seq, ctx)
	await cutscene.finished


func _on_call_finished(choice: Dictionary) -> void:
	if gs == null:
		return
	_focus_lock = false
	if choice.has("fx"):
		gs.apply_fx(choice["fx"])
	if choice.has("msg") and str(choice["msg"]) != "":
		_log("[color=#9fe0b0]   " + str(choice["msg"]) + "[/color]")
	_refresh()
	if _fail_if_over():
		return
	if choice.has("start_bio"):
		_open_food()
	if _pending_node:
		_pending_node = false
		_resolve_node()


func tutorial_fire_radio() -> void:
	_fire_call()


func tutorial_fire_combat() -> void:
	_start_combat(0.4)


func _on_tutorial_finished() -> void:
	tutorial_active = false
	_tutorial_done = true
	_prompt_next()


# =============================================================================
# Educational systems (data-driven)
# =============================================================================
func _open_room_info(sys: String) -> void:
	var r := Education.room(sys)
	if r.is_empty():
		return
	ship_view.set_selected_room(sys)
	var sections: Array = [
		{"label": "What it does", "body": str(r.get("what", ""))},
		{"label": "Why spacecraft need it", "body": str(r.get("why", ""))},
		{"label": "If it fails", "body": str(r.get("failure", ""))},
		{"label": "Real-world equivalent", "body": str(r.get("real", ""))},
		{"label": "Science fact", "body": str(r.get("fact", "")), "color": Color(0.6, 0.95, 0.7)},
	]
	if str(r.get("reflection", "")) != "":
		sections.append({"label": "Think like a scientist", "body": str(r.get("reflection", "")), "color": Color(1.0, 0.86, 0.4)})
	var footer := "Game system: %s" % sys
	if str(r.get("source", "")) != "":
		footer += "   |   Source: %s (%s)" % [str(r.get("source", "")), str(r.get("source_date", ""))]
	room_info.open(str(r.get("title", sys)), str(r.get("subject", "")), sections, footer, Color(0.5, 0.9, 1.0))


func _on_room_info_closed() -> void:
	if ship_view:
		ship_view.set_selected_room("")


func _open_library() -> void:
	if library:
		library.open_library()


# Instruments available depend on whether their host system has power.
func _available_instruments() -> Dictionary:
	var out := {}
	var defs := Education.instruments()
	for iid in defs:
		var host := str(defs[iid].get("host_system", "sensors"))
		if gs.sys_online(host):
			# more power and crew -> better data quality
			var eff := gs.sys_effective(host)
			out[iid] = clampf(0.40 + eff * 0.22, 0.30, 0.95)
	return out


func _open_scan(body: String, is_node: bool) -> void:
	if gs == null:
		return
	if not gs.sys_online("sensors"):
		_log("[color=#ffaa66]Science Lab is unpowered. Add power to run the instruments.[/color]")
		_apply_focus("action:scan", "The Science Lab has no power, so the instruments are offline. Add power, then scan again.", ["sensors"], false, true)
		_layout_system_rows()
		if is_node:
			_prompt_next()
		return
	_current_scan_body = body
	_scan_is_node = is_node
	tips.show_tip("exploration")
	scan_panel.open(body, _available_instruments())


func _on_scan_resolved(choice: Dictionary) -> void:
	var logged := bool(choice.get("log", false))
	var body := str(choice.get("body", "anomaly"))
	var q := float(choice.get("quality", 0.0))
	var instruments := int(choice.get("instruments", 0))
	if logged and instruments > 0:
		var used: Array = _available_instruments().keys()
		gs.record_scan(body, q, used)
		var gain := int(round(3.0 + q * 10.0 + float(used.size())))
		gs.apply_fx({"science": gain, "power": -3})
		_log("[color=#8fe0ff]Science logged from %s: +%d science (data quality %d%%).[/color]" % [body.replace("planet_", "").capitalize(), gain, int(q * 100.0)])
		tips.show_tip("data")
		if q < 0.6:
			tips.show_tip("uncertainty")
	else:
		_log("[color=#ffaa66]No data logged. Without observations there is nothing to analyse.[/color]")
	_refresh()
	if _scan_is_node:
		_scan_is_node = false
		_prompt_next()


func _signal_delay_text() -> String:
	if gs == null:
		return ""
	var to := str(gs.mission.get("to", ""))
	var d := "almost instant"
	if to == "planet_mars":
		d = "about 3 to 22 minutes, one way"
	elif to == "planet_moon":
		d = "about 1.3 seconds, one way"
	return "Signal delay: " + d


func _after_briefing() -> void:
	_build_launch_checklist()


func _on_report_closed() -> void:
	_show_select()


func _build_briefing(m: Dictionary) -> void:
	var em := Education.mission(str(m.get("id", "")))
	var sections: Array = []
	sections.append({"label": "", "body": "Welcome aboard, explorer.\nYou are now part of a scientific space mission. Your job is not simply to travel between planets. Your job is to explore, investigate, collect information, and help scientists understand the universe."})
	sections.append({"label": "How a mission works", "body": "Before launch, engineers prepare the spacecraft and check that everything is ready. During the mission the spacecraft uses instruments to observe the environment and collect scientific data. Back on Earth, mission control receives that information and helps manage the mission. Finally, scientists analyse the data to answer important questions."})
	sections.append({"label": "Your resources are limited", "body": "Your spacecraft has limited fuel, oxygen, power and other resources. Manage them while completing your objectives. Remember: reaching a destination is only part of the mission - what we discover there is what makes the mission valuable."})
	sections.append({"label": "Mission objective", "body": str(em.get("objective", "Explore the target and return scientific data.")), "color": Color(1.0, 0.86, 0.4)})
	if str(em.get("question", "")) != "":
		sections.append({"label": "Scientific question", "body": str(em.get("question", "")), "color": Color(0.6, 0.95, 0.7)})
	var instr_names: Array = []
	var defs := Education.instruments()
	for iid in em.get("instruments", []):
		instr_names.append(str(defs.get(iid, {}).get("name", iid)))
	sections.append({"label": "Instruments for this mission", "body": ", ".join(instr_names) if not instr_names.is_empty() else "Standard instrument suite."})
	sections.append({"label": "Four mission segments", "body": "Launch (prepare and go) -> Space (fly, power, observe) -> Ground (mission control and radio) -> User (scientists analyse the data). Not every real mission follows this exact order, but all four ideas are part of most missions."})
	briefing.open("MISSION BRIEFING", str(m.get("name", "")), sections,
		"Destination: %s   |   CML stage 1 - THE IDEA: what do we want to discover?" % str(em.get("destination", "")),
		Color(1.0, 0.86, 0.4))


func _timeline_events() -> Array:
	if gs == null:
		return []
	var arrived: bool = gs.is_final_node()
	var scanned: bool = gs.scan_count() > 0
	var ev: Array = []
	ev.append({"label": "Launch", "status": "done"})
	ev.append({"label": "Departure", "status": "done"})
	ev.append({"label": "Travel", "status": "done" if arrived else "current"})
	ev.append({"label": "Arrival", "status": "done" if arrived else "upcoming"})
	ev.append({"label": "Observation", "status": "done" if scanned else ("current" if arrived else "upcoming")})
	ev.append({"label": "Data relay", "status": "done" if (scanned and arrived) else ("current" if scanned else "upcoming")})
	ev.append({"label": "Analysis", "status": "current" if gs.game_over else "upcoming"})
	return ev


# =============================================================================
# Food mini-game (BioNutrients)
# =============================================================================
func _open_food() -> void:
	if not gs.sys_online("bio"):
		_log("[color=#ffaa66]BioNutrients Bay has no power. Add power to grow food.[/color]")
		_apply_focus("action:bio", "The BioNutrients Bay is off. Add power before you can grow food.", ["bio"], false, true)
		_layout_system_rows()
		return
	var f: Dictionary = GameData.FOODS[rng.randi() % GameData.FOODS.size()]
	food_state = {
		"food": f,
		"temp": f["target_temp"] - rng.randf_range(3.0, 6.0),
		"shakes_done": 0,
		"good_time": 0.0,
		"bad_time": 0.0,
		"shake_meter": 0.0,
		"shake_dir": 1.0,
		"shake_zone": rng.randf_range(0.35, 0.65),
		"log": "Get the temperature to the target and press SHAKE when the meter is in the green band.",
		"done": false,
	}
	food_active = true
	food_overlay.visible = true
	_show_food()


func _tick_food(delta: float) -> void:
	if food_state.get("done", false):
		return
	# ambient drift away from target
	food_state["temp"] += (rng.randf_range(-1.6, 0.6)) * delta * 4.0
	# shake meter oscillates
	food_state["shake_meter"] += food_state["shake_dir"] * delta * 0.65
	if food_state["shake_meter"] > 1.0:
		food_state["shake_meter"] = 1.0
		food_state["shake_dir"] = -1.0
	elif food_state["shake_meter"] < 0.0:
		food_state["shake_meter"] = 0.0
		food_state["shake_dir"] = 1.0
	var f: Dictionary = food_state["food"]
	var err := absf(float(food_state["temp"]) - float(f["target_temp"]))
	if err <= float(f["tolerance"]):
		food_state["good_time"] += delta
	else:
		food_state["bad_time"] += delta
	_update_food_labels()


func _show_food() -> void:
	var v := food_v
	for c in v.get_children():
		c.queue_free()
	var f: Dictionary = food_state["food"]
	v.add_child(_lbl("BIONUTRIENTS BAY", 24, Color(0.6, 0.95, 0.5)))
	v.add_child(_lbl(str(f["name"]), 18))
	var desc := _lbl(str(f["desc"]), 13, Color(0.8, 0.9, 0.8))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(460, 0)
	v.add_child(desc)
	food_overlay.set_meta("temp_lbl", v)
	var tl := _lbl("", 20, Color(1, 0.85, 0.4))
	tl.name = "TempLbl"
	v.add_child(tl)
	var tb := ProgressBar.new()
	tb.name = "TempBar"
	tb.min_value = 0
	tb.max_value = 60
	tb.custom_minimum_size = Vector2(460, 18)
	UiTheme.style_bar(tb, UiTheme.GOLD)
	v.add_child(tb)
	var sl := _lbl("", 16)
	sl.name = "ShakeLbl"
	v.add_child(sl)
	var sb := ProgressBar.new()
	sb.name = "ShakeBar"
	sb.min_value = 0
	sb.max_value = 1
	sb.custom_minimum_size = Vector2(460, 18)
	UiTheme.style_bar(sb, UiTheme.CYAN)
	v.add_child(sb)
	var loglbl := _lbl("", 14, Color(0.9, 0.95, 1.0))
	loglbl.name = "LogLbl"
	loglbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loglbl.custom_minimum_size = Vector2(460, 0)
	v.add_child(loglbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var heat := Button.new()
	heat.text = "Heat +4 C"
	heat.pressed.connect(_food_adjust.bind(4.0))
	UiTheme.style_button(heat, "gold", true)
	var cool := Button.new()
	cool.text = "Cool -4 C"
	cool.pressed.connect(_food_adjust.bind(-4.0))
	UiTheme.style_button(cool, "cyan", true)
	var shake := Button.new()
	shake.text = "SHAKE!"
	shake.pressed.connect(_food_shake)
	UiTheme.style_button(shake, "magenta", true)
	var finish := Button.new()
	finish.text = "Finish batch"
	finish.pressed.connect(_food_finish)
	UiTheme.style_button(finish, "gold", true)
	row.add_child(heat)
	row.add_child(cool)
	row.add_child(shake)
	row.add_child(finish)
	v.add_child(row)
	_update_food_labels()


func _food_adjust(d: float) -> void:
	food_state["temp"] = clampf(float(food_state["temp"]) + d, 0.0, 60.0)
	_update_food_labels()


func _food_shake() -> void:
	var zone: float = food_state["shake_zone"]
	var m: float = food_state["shake_meter"]
	if absf(m - zone) < 0.16:
		food_state["shakes_done"] = int(food_state["shakes_done"]) + 1
		food_state["good_time"] += 4.0
		food_state["log"] = "Perfect shake! (%d/%d)" % [food_state["shakes_done"], food_state["food"]["shakes"]]
	else:
		food_state["bad_time"] += 5.0
		food_state["log"] = "Botched shake - contamination risk rising."
	food_state["shake_zone"] = rng.randf_range(0.2, 0.8)
	_update_food_labels()


func _food_finish() -> void:
	food_state["done"] = true
	var f: Dictionary = food_state["food"]
	var good: float = food_state["good_time"]
	var bad: float = food_state["bad_time"]
	var made := float(f["yield"]) * clampf(good / 20.0, 0.2, 1.0)
	if bad > good * 0.7:
		made *= 0.4
		food_state["log"] = "Contaminated batch! Only a little safe food."
	gs.apply_fx({"food": int(made), "power": -5, "science": 4})
	_log("[color=#9fe0b0]BioNutrients: +%d food from %s. %s[/color]" % [int(made), f["name"], str(f["fact"])])
	food_active = false
	food_overlay.visible = false
	_refresh()
	_fail_if_over()


func _update_food_labels() -> void:
	if not food_overlay.visible:
		return
	var v := food_v
	var f: Dictionary = food_state["food"]
	var tl := v.get_node("TempLbl") as Label
	var heat_word := "ON TARGET"
	if float(food_state["temp"]) > float(f["target_temp"]) + float(f["tolerance"]):
		heat_word = "TOO HOT"
	elif float(food_state["temp"]) < float(f["target_temp"]) - float(f["tolerance"]):
		heat_word = "TOO COLD"
	tl.text = "%s   %.1f C   (target %.0f C)" % [heat_word, food_state["temp"], f["target_temp"]]
	tl.add_theme_color_override("font_color", UiTheme.GOOD if heat_word == "ON TARGET" else UiTheme.WARN)
	var tb := v.get_node("TempBar") as ProgressBar
	tb.value = food_state["temp"]
	var sl := v.get_node("ShakeLbl") as Label
	var in_zone := absf(float(food_state["shake_meter"]) - float(food_state["shake_zone"])) < 0.16
	sl.text = "%s   meter %d%%   green band %d%%   shakes %d/%d" % [
		"SHAKE NOW" if in_zone else "WAIT",
		int(float(food_state["shake_meter"]) * 100.0),
		int(float(food_state["shake_zone"]) * 100.0),
		food_state["shakes_done"], f["shakes"]]
	sl.add_theme_color_override("font_color", UiTheme.GOOD if in_zone else UiTheme.TEXT)
	var sb := v.get_node("ShakeBar") as ProgressBar
	sb.value = food_state["shake_meter"]
	sb.modulate = Color(0.5, 1, 0.5) if in_zone else Color(1, 0.7, 0.4)
	(v.get_node("LogLbl") as Label).text = str(food_state["log"])


# =============================================================================
# Popups / overlay
# =============================================================================
func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)
	_attach_center_panel(overlay, "Popup")


func _build_food_overlay() -> void:
	food_overlay = Control.new()
	food_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	food_overlay.visible = false
	add_child(food_overlay)
	_attach_center_panel(food_overlay, "Food")


func _build_runtime_systems() -> void:
	# Full-screen gameplay components. Added last so they render above the HUD.
	combat_scene = CombatScene.new()
	add_child(combat_scene)
	combat_scene.combat_finished.connect(_on_combat_finished)

	radio = RadioCommunication.new()
	add_child(radio)
	radio.call_finished.connect(_on_call_finished)

	cutscene = Cutscene.new()
	add_child(cutscene)

	tutorial = TutorialRunner.new()
	add_child(tutorial)
	tutorial.setup(self, ship_view, radio, combat_scene)
	tutorial.finished.connect(_on_tutorial_finished)
	tutorial.quit_requested.connect(func() -> void:
		tutorial_active = false
		_show_menu())

	# --- Educational systems (data-driven from data/education.json) ---
	room_info = InfoPanel.new()
	add_child(room_info)
	room_info.closed.connect(_on_room_info_closed)

	briefing = InfoPanel.new()
	add_child(briefing)
	briefing.closed.connect(_after_briefing)

	library = KnowledgeLibrary.new()
	add_child(library)

	scan_panel = ScanPanel.new()
	add_child(scan_panel)
	scan_panel.resolved.connect(_on_scan_resolved)

	report = ScienceReport.new()
	add_child(report)
	report.closed.connect(_on_report_closed)

	# Full-screen surface exploration (Moon / Mars sample collection).
	surface = SurfaceScene.new()
	add_child(surface)
	surface.input_gate = Callable(self, "_ui_modal_open")

	tips = TipsManager.new()
	add_child(tips)
	tips.setup(self, tip_host)
	tips.opened.connect(_on_tip_presence)

	ship_view.room_info_requested.connect(_open_room_info)

	# Modal panels must always draw ABOVE the walkable ship / surface sprites,
	# otherwise the astronaut and crew appear on top of quiz and sample popups.
	for host in [overlay, food_overlay, combat_scene, radio, cutscene, tutorial,
			room_info, briefing, library, scan_panel, report, surface]:
		# TutorialRunner is a plain Node, not a CanvasItem, so it has no z_index.
		if host is CanvasItem:
			(host as CanvasItem).z_index = 100


func _attach_center_panel(host: Control, name_hint: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.CYAN, 18))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 20)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	if host == food_overlay:
		food_v = v
	# popup-only fields live in the Popup host
	if name_hint == "Popup":
		pop_title = _lbl("", 24, Color(1.0, 0.85, 0.3))
		v.add_child(pop_title)
		pop_role = _lbl("", 14, Color(0.65, 0.8, 1.0))
		v.add_child(pop_role)
		pop_body = _lbl("", 17)
		pop_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pop_body.custom_minimum_size = Vector2(560, 0)
		v.add_child(pop_body)
		pop_fact = _lbl("", 14, Color(0.6, 0.92, 0.72))
		pop_fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pop_fact.custom_minimum_size = Vector2(560, 0)
		v.add_child(pop_fact)
		pop_risk = RiskMatrix.new()
		pop_risk.visible = false
		v.add_child(pop_risk)
		pop_btns = VBoxContainer.new()
		pop_btns.add_theme_constant_override("separation", 6)
		v.add_child(pop_btns)
	else:
		panel.custom_minimum_size = Vector2(520, 0)


func _popup(title: String, role: String, body: String, fact: String, choices: Array, source: Variant) -> void:
	pop_title.text = title
	pop_role.text = role
	pop_body.text = body
	pop_fact.text = fact
	if source != null and source is Dictionary and source.has("likelihood"):
		pop_risk.visible = true
		pop_risk.set_risk(int(source["likelihood"]), int(source["impact"]))
	else:
		pop_risk.visible = false
	for c in pop_btns.get_children():
		c.queue_free()
		c.get_parent().remove_child(c)
	for ch in choices:
		var b := Button.new()
		b.text = str(ch["label"])
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiTheme.style_button(b, "cyan", true)
		b.pressed.connect(_on_popup_choice.bind(ch))
		pop_btns.add_child(b)
	overlay.visible = true
	_refresh()
	var rooms := _rooms_for_alert(title)
	var note := _concise_alert(title, body)
	if rooms.is_empty() and title == "HULL STATUS":
		rooms = ["repair"]
		note = "Hull status. Repair Bay power and spare parts are what keep the ship together."
	_apply_focus("event:" + title, note, rooms, true)
	_layout_system_rows()


# =============================================================================
# Power / crew actions
# =============================================================================
func _add_power(id: String) -> void:
	if gs == null:
		return
	if gs.add_power(id):
		tips.show_tip("power")
		_refresh()
	else:
		var maxed := false
		for s in GameData.SYSTEMS:
			if s["id"] == id and gs.sys_level(id) >= int(s["max"]):
				maxed = true
		if maxed:
			_log("[color=#ffaa66]%s is already at full power.[/color]" % ship_view.dept_name(id))
		else:
			_log("[color=#ffaa66]No spare reactor power. Right-click a room you can turn down.[/color]")
			_apply_focus("action:power", "No spare reactor power. Right-click a room you can turn down, then try again.", [], false, true)
			_layout_system_rows()


func _remove_power(id: String) -> void:
	if gs == null:
		return
	gs.remove_power(id)
	_refresh()


func _clear_actions() -> void:
	_action_buttons.clear()
	if action_bar == null:
		return
	for c in action_bar.get_children():
		c.queue_free()


# =============================================================================
# End / score
# =============================================================================
func _end_mission(won: bool) -> void:
	if _mission_ended or gs == null:
		return
	_mission_ended = true
	gs.game_over = true
	gs.won = won
	if tutorial_active and tutorial:
		tutorial_active = false
		tutorial.stop()
	food_active = false
	if food_overlay:
		food_overlay.visible = false
	if overlay:
		overlay.visible = false
	# Victory / defeat audio cue (uses the supplied WIn.mp3 / lose.mp3 if present).
	_play_verdict(won)
	if radio:
		radio.play_static(false)
	var score := gs.mission_score()
	if not won:
		score = int(score * 0.4)
	var stars := _star_count(won, score)
	var rank := _rank_for(stars)
	var edu := _edu_stage(score)
	_log("[color=#8fe0ff]%s - %s  |  %d stars[/color]" % [("MISSION COMPLETE" if won else "MISSION INCOMPLETE"), rank, stars])
	if not won:
		tips.show_tip("failure")
	tips.show_tip("data")
	tips.show_tip("uncertainty")
	# Stage-clear banner plus the scientific report (User segment).
	report.open({
		"won": won,
		"score": score,
		"grade": _grade_for(score),
		"stars": stars,
		"rank": rank,
		"science": gs.science,
		"jumps": gs.jumps,
		"days": gs.day,
		"mission_id": str(gs.mission.get("id", "")),
		"mission_name": str(gs.mission.get("name", "")),
		"scans": gs.scans,
		"samples": gs.samples.duplicate(),
		"resources": gs.resources.duplicate(),
		"gates_solved": gs.gates_solved,
		"gates_seen": gs.gates_seen,
		"lifelines_used": GameData.LIFELINES - gs.lifelines,
		"reason": gs.end_reason,
		"stage_name": str(edu.get("name", "")),
		"stage_blurb": str(edu.get("blurb", "")),
		"stage_question": str(edu.get("question", "")),
	})
	_refresh()


func _star_count(won: bool, score: int) -> int:
	if not won:
		return 1 if score >= 40 else 0
	if score >= 78:
		return 3
	if score >= 48:
		return 2
	return 1


func _rank_for(stars: int) -> String:
	match stars:
		3:
			return "Mission lead"
		2:
			return "Scientist"
		1:
			return "Explorer"
		_:
			return "Cadet"


func _grade_for(score: int) -> String:
	if score >= 90:
		return "A+"
	if score >= 78:
		return "A"
	if score >= 62:
		return "B"
	if score >= 45:
		return "C"
	if score >= 25:
		return "D"
	return "F"


func _edu_stage(score: int) -> Dictionary:
	var stages: Array = Education.cml()
	if stages.is_empty():
		return {}
	var idx := 0
	if score >= 70:
		idx = mini(3, stages.size() - 1)
	elif score >= 45:
		idx = mini(2, stages.size() - 1)
	elif score >= 25:
		idx = mini(1, stages.size() - 1)
	var picked: Dictionary = stages[idx]
	return picked


func _on_popup_choice(ch: Dictionary) -> void:
	overlay.visible = false
	_focus_lock = false
	if ch.has("hint"):
		_use_hint()
		return
	if ch.has("quiz"):
		_on_quiz_answer(ch)
		return
	if ch.has("quiz_done"):
		_finish_gate()
		return
	if ch.has("restart"):
		_show_select()
		return
	if ch.has("fx"):
		gs.apply_fx(ch["fx"])
	if ch.has("msg") and str(ch["msg"]) != "":
		_log("[color=#9fe0b0]   " + str(ch["msg"]) + "[/color]")
	_refresh()
	if _fail_if_over():
		return
	if ch.has("start_bio"):
		_open_food()
	if _pending_node:
		_pending_node = false
		_resolve_node()
		return
	_prompt_next()


func _prompt_next() -> void:
	if gs == null:
		return
	if tutorial_active:
		return
	if gs.game_over:
		if not _mission_ended:
			_end_mission(gs.won)
		return
	if gs.is_final_node():
		return
	_open_map()


func _fail_if_over() -> bool:
	if gs != null and gs.game_over and not _mission_ended:
		_end_mission(false)
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()
		return
	if _input_blocked():
		return
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	var key := (event as InputEventKey).keycode
	if screen == "space":
		if key == KEY_M:
			_open_map()
			get_viewport().set_input_as_handled()
		elif key == KEY_B:
			_open_food()
			get_viewport().set_input_as_handled()
		elif key == KEY_C:
			_scan()
			get_viewport().set_input_as_handled()
	elif screen == "map" and key == KEY_M:
		_enter_space(false)
		get_viewport().set_input_as_handled()


func _ui_modal_open() -> bool:
	if overlay and overlay.visible:
		return true
	if food_overlay and food_overlay.visible:
		return true
	if food_active:
		return true
	if combat_scene and combat_scene.visible:
		return true
	if cutscene and cutscene.visible:
		return true
	if radio and radio.is_busy():
		return true
	if report and report.visible:
		return true
	if scan_panel and scan_panel.visible:
		return true
	if library and library.visible:
		return true
	if room_info and room_info.visible:
		return true
	if briefing and briefing.visible:
		return true
	if tutorial_active:
		return true
	return false


# True when any modal panel/overlay is open, or a walkable surface is showing.
func _input_blocked() -> bool:
	if surface and surface.visible:
		return true
	return _ui_modal_open()


func _start_tutorial() -> void:
	# Interactive guided tutorial: a real run on the ship with live guidance.
	gs = GameState.new()
	gs.new_run(GameData.MISSIONS[0])
	_mission_ended = false
	_calls_left = range(GameData.CALLS.size())
	_calls_left.shuffle()
	_events_left = range(GameData.EVENTS.size())
	_events_left.shuffle()
	_log_lines.clear()
	_log("[color=#8fb4ff]TUTORIAL: welcome aboard the Nefer-1, Captain.[/color]")
	_log("Follow the banner at the top. Click rooms to route power and move crew.")
	tutorial_active = true
	_set_hud_visible(true)
	_nav_history.clear()
	_enter_space(false)
	_refresh()
	tutorial.start(gs)
