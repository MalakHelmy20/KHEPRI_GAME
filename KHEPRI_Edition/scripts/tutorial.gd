class_name TutorialRunner
extends Node

# =============================================================================
# Interactive guided tutorial - informative edition.
# Each step: a detailed explanation of WHAT to do, WHY it matters (the real
# space-science idea behind it), a highlighted target, a "Learn more" button
# that opens the same educational panels used in the game, a progress tracker,
# and a Quit button. The universal Back button also exits the tutorial.
# =============================================================================

signal finished
signal quit_requested

var game: Node
var gs: GameState
var ship_view: ShipView
var radio: RadioCommunication
var combat: CombatScene

var step := -1
var completed: Array = []
var _active := false

var _hl: Highlight
var _banner: PanelContainer
var _title_lbl: Label
var _hint_lbl: Label
var _why_lbl: Label
var _progress_lbl: Label
var _next_btn: Button
var _learn_btn: Button
var _quit_btn: Button

# step signals
var _crew_moved := false
var _radio_done := false
var _combat_done := false


class Highlight:
	extends Control
	var ship_view: ShipView
	var rooms: Array = []
	var t := 0.0

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_rooms(r: Array) -> void:
		rooms = r
		queue_redraw()

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		if ship_view == null or rooms.is_empty():
			return
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		for r in rooms:
			var rect: Rect2 = ship_view.room_rect(str(r))
			if rect.size == Vector2.ZERO:
				continue
			var g := rect.grow(6.0)
			draw_rect(g, Color(1.0, 0.85, 0.2, 0.18 + 0.18 * pulse), true)
			draw_rect(g, Color(1.0, 0.9, 0.3, 0.85), false, 3.0)


# Each step: title, hint (what to do, concretely), why (the science idea),
# rooms to highlight, mode, and learn (title + sections for the Learn-more panel).
const STEPS := [
	{
		"title": "1 / 6  Power the ship systems",
		"hint": "The reactor holds 13 power units. Click the highlighted ENGINE ROOM once to route 1 unit into it (right-click a room to take power back). Power is what makes a room actually work.",
		"why": "Real spacecraft generate limited electricity from solar panels or reactors. Every system - engines, life support, instruments - competes for that power, so engineers decide what to run and what to switch off.",
		"rooms": ["engines"],
		"mode": "power",
		"learn_room": "engines",
	},
	{
		"title": "2 / 6  Move your crew",
		"hint": "Click any crew member (they get a yellow ring), then click a room to send them there. A crew member in a room boosts that system's output by half a level - so put people where the work is.",
		"why": "On real missions the crew is part of the spacecraft: astronauts maintain systems, run experiments and repair faults. NASA trains each astronaut so they can operate several systems, not just one.",
		"rooms": ["piloting", "engines", "oxygen", "bio"],
		"mode": "crew",
		"learn_room": "medbay",
	},
	{
		"title": "3 / 6  Answer a radio call",
		"hint": "A call is coming in from Earth. The panel slides in with the caller's portrait, their message and your choices. Click one of the two choice buttons to answer. Choices change your resources - just like real decisions change a mission.",
		"why": "Spacecraft talk to Earth through ground stations - giant dish antennas like NASA's Deep Space Network. Radio signals travel at the speed of light but distances are huge, so replies are never instant and spacecraft must sometimes act on their own.",
		"rooms": [],
		"mode": "radio",
		"learn": {"title": "Communications with Earth", "body": "Mission control monitors telemetry (the spacecraft's own health data), sends commands, and helps plan every move. A signal to the Moon takes about 1.3 seconds; to Mars, minutes."},
	},
	{
		"title": "4 / 6  Manage your resources",
		"hint": "Look at the top bar. Each resource has a word: GOOD, OK, LOW, or EMPTY. A jump spends fuel and supplies. Press CONTINUE when you have looked.",
		"why": "Mission planners track every resource with a margin - on the ISS about 93% of water is recycled, and oxygen is measured in kilograms per crew member per day. Running out of any one of them can end a mission, so planners keep a safety margin in everything.",
		"rooms": [],
		"mode": "next",
		"learn_room": "oxygen",
	},
	{
		"title": "5 / 6  Solve a Puzzle Gate",
		"hint": "A friendly Puzzle Gate! A space critter asks a science question. Pick an answer, or press USE A HINT CRYSTAL to make a wrong answer disappear. Wrong answers are okay - you still learn something! Finish the puzzle to continue.",
		"why": "Real scientists solve puzzles every day: they ask questions, test ideas and learn from mistakes. Space missions avoid danger by planning carefully, not by fighting - engineers protect the ship from space dust and radiation instead.",
		"rooms": [],
		"mode": "combat",
		"learn_room": "shields",
	},
	{
		"title": "6 / 6  You're ready, Captain!",
		"hint": "You now know: power management, crew movement, radio, resources and Puzzle Gates. On the ship screen the i buttons next to each room open real science explanations, and the KNOWLEDGE LIBRARY button has everything again. Press CONTINUE to start the mission for real.",
		"why": "A real mission succeeds the same way you just practised: careful planning, healthy margins, a working crew, and science collected at every chance. Reaching the destination is only part of the mission - what you discover there is what makes it valuable.",
		"rooms": [],
		"mode": "next",
	},
]


func setup(g: Node, sv: ShipView, rd: RadioCommunication, cb: CombatScene) -> void:
	game = g
	ship_view = sv
	radio = rd
	combat = cb
	_build_ui()
	_hl = Highlight.new()
	_hl.ship_view = sv
	sv.add_child(_hl)
	if not sv.crew_moved.is_connected(_on_crew_moved):
		sv.crew_moved.connect(_on_crew_moved)
	if not radio.call_finished.is_connected(_on_radio_finished):
		radio.call_finished.connect(_on_radio_finished)
	if not combat.combat_finished.is_connected(_on_combat_finished):
		combat.combat_finished.connect(_on_combat_finished)
	if not sv.system_clicked.is_connected(_on_system_clicked):
		sv.system_clicked.connect(_on_system_clicked)


func _build_ui() -> void:
	_banner = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.96)
	sb.border_color = Color(1.0, 0.85, 0.3, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	_banner.add_theme_stylebox_override("panel", sb)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_banner.offset_left = 14
	_banner.offset_right = 614
	_banner.offset_top = -330
	_banner.offset_bottom = -158
	_banner.z_index = 50
	_banner.visible = false
	game.add_child(_banner)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	_banner.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	_title_lbl = _mk_label("", 16, Color(1.0, 0.85, 0.3))
	head.add_child(_title_lbl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_progress_lbl = _mk_label("", 12, Color(0.6, 0.95, 0.7))
	head.add_child(_progress_lbl)

	_hint_lbl = _mk_label("", 14, Color(0.92, 0.96, 1.0))
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.custom_minimum_size = Vector2(640, 0)
	v.add_child(_hint_lbl)

	var why_row := HBoxContainer.new()
	why_row.add_theme_constant_override("separation", 6)
	v.add_child(why_row)
	var why_tag := _mk_label("WHY IT MATTERS", 11, Color(0.5, 0.9, 1.0))
	why_row.add_child(why_tag)
	_why_lbl = _mk_label("", 12, Color(0.75, 0.92, 1.0))
	_why_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why_lbl.custom_minimum_size = Vector2(560, 0)
	why_row.add_child(_why_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_next_btn = Button.new()
	_next_btn.text = "Continue >>"
	_next_btn.pressed.connect(advance)
	row.add_child(_next_btn)
	_learn_btn = Button.new()
	_learn_btn.text = "Learn more"
	_learn_btn.pressed.connect(_open_learn)
	row.add_child(_learn_btn)
	_quit_btn = Button.new()
	_quit_btn.text = "Quit tutorial"
	_quit_btn.pressed.connect(_quit)
	row.add_child(_quit_btn)


func _mk_label(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


# --- Lifecycle --------------------------------------------------------------
func start(state: GameState) -> void:
	gs = state
	_active = true
	step = -1
	completed.clear()
	advance()


func stop() -> void:
	_active = false
	_banner.visible = false
	if _hl:
		_hl.set_rooms([])


func _quit() -> void:
	# Leaving the tutorial keeps the current mission running.
	stop()
	quit_requested.emit()


func advance() -> void:
	if not _active:
		return
	if step >= 0:
		var id := str(STEPS[step]["title"])
		if not completed.has(id):
			completed.append(id)
	step += 1
	if step >= STEPS.size():
		_finish()
		return
	_enter(step)


func _enter(i: int) -> void:
	var s: Dictionary = STEPS[i]
	_title_lbl.text = "TUTORIAL  -  " + str(s["title"])
	_hint_lbl.text = str(s["hint"])
	_why_lbl.text = str(s["why"])
	_progress_lbl.text = "%d / %d done" % [completed.size(), STEPS.size()]
	_banner.visible = true
	_next_btn.visible = true
	_learn_btn.visible = s.has("learn_room") or s.has("learn")
	_hl.set_rooms(s["rooms"])
	match str(s["mode"]):
		"radio":
			_radio_done = false
			fire_radio()
		"combat":
			_combat_done = false
			fire_combat()


# Learn more opens the same educational panels used in the real game.
func _open_learn() -> void:
	if step < 0 or step >= STEPS.size():
		return
	var s: Dictionary = STEPS[step]
	if s.has("learn_room") and game.has_method("_open_room_info"):
		game._open_room_info(str(s["learn_room"]))
		return
	if s.has("learn") and game.get("room_info") != null:
		var l: Dictionary = s["learn"]
		game.room_info.open(str(l["title"]), "Tutorial: why this matters",
			[{"label": "", "body": str(l["body"])}],
			"Source: bundled NASA/CSA reference material - see the Knowledge Library.", Color(0.5, 0.9, 1.0))


func fire_radio() -> void:
	if game and game.has_method("tutorial_fire_radio"):
		game.tutorial_fire_radio()


func fire_combat() -> void:
	if game and game.has_method("tutorial_fire_combat"):
		game.tutorial_fire_combat()


# --- Signal handlers --------------------------------------------------------
func _on_crew_moved(_i: int, _room: String) -> void:
	if _active and step >= 0 and str(STEPS[step]["mode"]) == "crew":
		_crew_moved = true


func _on_system_clicked(_id: String) -> void:
	if _active and step >= 0 and str(STEPS[step]["mode"]) == "power":
		advance()


func _on_radio_finished(_choice: Dictionary) -> void:
	if _active and step >= 0 and str(STEPS[step]["mode"]) == "radio":
		_radio_done = true


func _on_combat_finished(_result: String) -> void:
	if _active and step >= 0 and str(STEPS[step]["mode"]) == "combat":
		_combat_done = true
		await game.get_tree().create_timer(0.8).timeout
		if _active and step < STEPS.size() and str(STEPS[step]["mode"]) == "combat":
			advance()


func _process(_delta: float) -> void:
	if not _active or step < 0 or step >= STEPS.size():
		return
	var mode := str(STEPS[step]["mode"])
	if mode == "crew" and _crew_moved:
		advance()
	elif mode == "radio" and _radio_done:
		advance()


func _finish() -> void:
	_active = false
	_title_lbl.text = "TUTORIAL COMPLETE"
	_hint_lbl.text = "All %d steps completed. The mission is yours now, Captain - keep your margins green and keep scanning." % completed.size()
	_why_lbl.text = ""
	_progress_lbl.text = "%d / %d done" % [completed.size(), STEPS.size()]
	_next_btn.visible = false
	_learn_btn.visible = false
	_quit_btn.text = "Close"
	if _hl:
		_hl.set_rooms([])
	finished.emit()