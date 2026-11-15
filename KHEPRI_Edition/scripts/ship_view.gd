class_name ShipView
extends Control

# =============================================================================
# FTL-style top-down ship view.
#  - draws the hull sprite, a room per system, system glyphs + power pips
#  - click a system room to add power (right-click removes)
#  - click a crew member, then a room, to move them
#  - particles: engine flame, hull smoke, explosion FX; shield shimmer; pulsing
# =============================================================================

signal system_clicked(id: String)
signal system_right_clicked(id: String)
signal crew_moved(crew_index: int, room_id: String)
signal room_info_requested(id: String)   # educational hotspot clicked

const SHIP_OFFSET := Vector2(24, 10)
const ROOM_SIZE := Vector2(66, 58)
const INFO_DOT_R := 9.0   # radius of the small "i" educational hotspot

# Room layout over the 512x320 hull: rear on the left, nose on the right.
const ROOMS := [
	{"sys": "bio",      "c": Vector2(112, 96)},
	{"sys": "oxygen",   "c": Vector2(190, 96)},
	{"sys": "shields",  "c": Vector2(268, 96)},
	{"sys": "weapons",  "c": Vector2(346, 96)},
	{"sys": "piloting", "c": Vector2(432, 96)},
	{"sys": "engines",  "c": Vector2(112, 214)},
	{"sys": "repair",   "c": Vector2(190, 214)},
	{"sys": "sensors",  "c": Vector2(268, 214)},
	{"sys": "comms",    "c": Vector2(346, 214)},
	{"sys": "medbay",   "c": Vector2(432, 214)},
]

# Proper department names shown above each room (never the internal id).
const DEPT_NAMES := {
	"piloting": "Cockpit / Navigation",
	"engines":  "Engine Room",
	"oxygen":   "Oxygen Control",
	"shields":  "Shield Generator",
	"weapons":  "Tractor Beam",
	"sensors":  "Science Laboratory",
	"comms":    "Communications Room",
	"bio":      "BioNutrients Bay",
	"repair":   "Repair Bay",
	"medbay":   "Medical Bay",
}

var gs: GameState
var selected_crew: int = -1
var selected_room: String = ""
var focus_rooms: Array = []
var _hover_sys: String = ""
var _t: float = 0.0

var _ship: Sprite2D
var _crew_nodes: Array = []          # Sprite2D per crew member
var _thruster: GPUParticles2D
var _smoke: GPUParticles2D
var _boom: Sprite2D
var _boom_tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(560, 340)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_ship = Sprite2D.new()
	_ship.texture = load("res://assets/generated/ship_nefer.png")
	_ship.centered = false
	_ship.position = SHIP_OFFSET
	# The ship is the BACKGROUND layer: draw it behind this Control's own
	# _draw() output so the room boxes / labels sit on top of the artwork.
	_ship.show_behind_parent = true
	add_child(_ship)

	_build_thruster()
	_build_smoke()

	_boom = Sprite2D.new()
	_boom.texture = load("res://assets/generated/explosion.png")
	_boom.scale = Vector2(1.4, 1.4)
	_boom.visible = false
	_boom.z_index = 5
	add_child(_boom)

	# Mission-patch insignia painted on the hull (upper deck, centre).
	if ResourceLoader.exists("res://assets/generated/edu_insignia.png"):
		var patch := Sprite2D.new()
		patch.texture = load("res://assets/generated/edu_insignia.png")
		patch.centered = true
		patch.scale = Vector2(0.5, 0.5)
		patch.position = SHIP_OFFSET + Vector2(256, 158)
		patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		patch.z_index = 1
		add_child(patch)

	set_process(true)


func _build_thruster() -> void:
	_thruster = GPUParticles2D.new()
	_thruster.texture = _dot_texture()
	_thruster.amount = 26
	_thruster.lifetime = 0.7
	_thruster.position = SHIP_OFFSET + Vector2(22, 160)
	_thruster.z_index = -1
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8, 46, 0)
	pm.direction = Vector3(-1, 0, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 60.0
	pm.initial_velocity_max = 140.0
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 1.0, 1.0, 0.9))
	g.set_color(1, Color(0.2, 0.5, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_thruster.process_material = pm
	# Behind the room boxes so the flame never covers the department labels.
	_thruster.show_behind_parent = true
	add_child(_thruster)


func _build_smoke() -> void:
	_smoke = GPUParticles2D.new()
	_smoke.texture = _dot_texture()
	_smoke.amount = 20
	_smoke.lifetime = 1.6
	_smoke.position = SHIP_OFFSET + Vector2(260, 160)
	_smoke.z_index = -1
	_smoke.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(180, 90, 0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 30.0
	pm.scale_min = 1.0
	pm.scale_max = 2.6
	var g := Gradient.new()
	g.set_color(0, Color(0.35, 0.35, 0.4, 0.8))
	g.set_color(1, Color(0.2, 0.2, 0.25, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_smoke.process_material = pm
	# Drifts over the hull but stays under the room boxes / labels.
	_smoke.show_behind_parent = true
	add_child(_smoke)


func _dot_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex


func set_state(state: GameState) -> void:
	gs = state
	setup_crew()


func setup_crew() -> void:
	for n in _crew_nodes:
		n.queue_free()
	_crew_nodes.clear()
	if gs == null:
		return
	for i in gs.crew.size():
		var s := Sprite2D.new()
		s.texture = load("res://assets/generated/crew_astronaut.png")
		s.centered = true
		s.scale = Vector2(0.5, 0.5)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.z_index = 6
		s.modulate = _crew_color(i)
		# scatter within their starting room
		var r := _room_center(gs.crew[i]["room"])
		s.position = r + Vector2(randf_range(-12, 12), randf_range(-10, 10))
		add_child(s)
		_crew_nodes.append(s)
	queue_redraw()


func _crew_color(i: int) -> Color:
	var cols := [Color(1, 1, 1), Color(0.7, 0.9, 1.0), Color(1.0, 0.85, 0.6), Color(0.8, 1.0, 0.8)]
	return cols[i % cols.size()]


func _room_center(sys: String) -> Vector2:
	for r in ROOMS:
		if r["sys"] == sys:
			return SHIP_OFFSET + Vector2(r["c"])
	return SHIP_OFFSET + Vector2(260, 160)


func room_rect(sys: String) -> Rect2:
	for r in ROOMS:
		if r["sys"] == sys:
			var c: Vector2 = SHIP_OFFSET + Vector2(r["c"])
			return Rect2(c - ROOM_SIZE * 0.5, ROOM_SIZE)
	return Rect2()


func room_center(sys: String) -> Vector2:
	return _room_center(sys)


# --- Input ------------------------------------------------------------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_sys != "":
		_hover_sys = ""
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if gs == null:
		return
	if event is InputEventMouseMotion:
		var hovered := _sys_at((event as InputEventMouseMotion).position)
		if hovered != _hover_sys:
			_hover_sys = hovered
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var pos: Vector2 = mb.position
		# educational hotspot (left click only): opens a room info panel without
		# changing power or moving crew, so existing functionality is preserved.
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := _info_dot_at(pos)
			if hit != "":
				room_info_requested.emit(hit)
				return
		# crew pick first
		for i in _crew_nodes.size():
			if pos.distance_to(_crew_nodes[i].position) < 16.0:
				select_crew(i)
				return
		var sys := _sys_at(pos)
		if sys == "":
			if mb.button_index == MOUSE_BUTTON_LEFT and selected_crew >= 0:
				select_crew(-1)
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			system_right_clicked.emit(sys)
		else:
			if selected_crew >= 0:
				move_crew(selected_crew, sys)
			else:
				system_clicked.emit(sys)


func _sys_at(pos: Vector2) -> String:
	for r in ROOMS:
		if room_rect(r["sys"]).has_point(pos):
			return r["sys"]
	return ""


func _info_dot_pos(sys: String) -> Vector2:
	var rect := room_rect(sys)
	return rect.position + Vector2(rect.size.x - 8.0, 8.0)


func _info_dot_at(pos: Vector2) -> String:
	for r in ROOMS:
		var sys: String = r["sys"]
		if pos.distance_to(_info_dot_pos(sys)) <= INFO_DOT_R:
			return sys
	return ""


func set_selected_room(sys: String) -> void:
	selected_room = sys
	queue_redraw()


func set_focus_rooms(rooms: Array) -> void:
	focus_rooms = rooms.duplicate()
	queue_redraw()


func select_crew(i: int) -> void:
	selected_crew = i
	queue_redraw()


func move_crew(i: int, sys: String) -> void:
	if gs == null or i < 0 or i >= gs.crew.size():
		return
	gs.crew[i]["room"] = sys
	var target := _room_center(sys) + Vector2(randf_range(-14, 14), randf_range(-10, 10))
	var node: Sprite2D = _crew_nodes[i]
	var tw := create_tween()
	tw.tween_property(node, "position", target, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	selected_crew = -1
	crew_moved.emit(i, sys)
	queue_redraw()


# --- FX ---------------------------------------------------------------------
func flash_explosion(at_global: Vector2) -> void:
	_boom.position = at_global
	_boom.visible = true
	_boom.modulate = Color(1, 1, 1, 1)
	_boom.scale = Vector2(0.4, 0.4)
	if _boom_tween:
		_boom_tween.kill()
	_boom_tween = create_tween()
	_boom_tween.tween_property(_boom, "scale", Vector2(1.8, 1.8), 0.35).set_trans(Tween.TRANS_BACK)
	_boom_tween.parallel().tween_property(_boom, "modulate:a", 0.0, 0.5)
	_boom_tween.tween_callback(func() -> void: _boom.visible = false)


# --- Draw -------------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	if gs == null:
		return
	# thruster intensity from engines
	_thruster.emitting = gs.sys_online("engines") and float(gs.resources["fuel"]) > 5.0
	# hull smoke when hull is low
	_smoke.emitting = float(gs.resources["hull"]) < 55.0
	# gentle idle bob for crew
	for i in _crew_nodes.size():
		var n: Sprite2D = _crew_nodes[i]
		n.scale = Vector2(0.5, 0.5) * (1.0 + sin(_t * 3.0 + i) * 0.05)
	queue_redraw()


func _draw() -> void:
	if gs == null:
		return
	var f := ThemeDB.fallback_font
	# shield shimmer (drawn over the hull, under the labels)
	if gs.sys_online("shields"):
		var a := 0.10 + 0.06 * sin(_t * 2.0)
		var center := SHIP_OFFSET + Vector2(256, 160)
		draw_circle(center, 150.0, Color(0.4, 0.8, 1.0, a))
		draw_arc(center, 150.0, 0, TAU, 64, Color(0.6, 0.9, 1.0, a + 0.15), 2.0)
	# rooms: boxes, glyph, power pips then the department name on top of everything
	var focusing := not focus_rooms.is_empty()
	for r in ROOMS:
		var sys: String = r["sys"]
		var rect := room_rect(sys)
		var col := _sys_color(sys)
		var focused: bool = sys in focus_rooms
		if focusing and not focused:
			col = col.darkened(0.55)
		var fill_a := 0.22
		if focusing and not focused:
			fill_a = 0.08
		elif focused:
			fill_a = 0.38
		draw_rect(rect, Color(col.r, col.g, col.b, fill_a), true)
		draw_rect(rect, col, false, 2.0)
		if focused:
			var pulse := 1.0 if UiTheme.reduce_motion else (0.45 + 0.55 * sin(_t * 4.0))
			draw_rect(rect.grow(5.0), Color(UiTheme.MAGENTA.r, UiTheme.MAGENTA.g, UiTheme.MAGENTA.b, 0.35 + 0.4 * pulse), false, 3.0)
		# system glyph centred in the box
		var glyph := _glyph(sys)
		var gsz := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(f, rect.position + Vector2((rect.size.x - gsz.x) * 0.5, 24), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.35 if (focusing and not focused and _hover_sys != sys) else 0.9))
		# power pips along the bottom of the box
		var maxp := _sys_max(sys)
		var lvl := gs.sys_level(sys)
		var total_w := 4.0 * (maxp - 1)
		var start_x := rect.position.x + (rect.size.x - total_w) * 0.5
		for p in maxp:
			var pr := Rect2(start_x + p * 4.0, rect.position.y + rect.size.y - 10, 3.6, 6)
			draw_rect(pr, Color(1, 0.85, 0.25, 0.95) if p < lvl else Color(1, 1, 1, 0.18), true)
		# Names stay readable. During focus, rooms that are not involved fade back.
		var label_a := 0.96
		if focusing and not focused and _hover_sys != sys:
			label_a = 0.28
		_draw_dept_label(f, sys, rect, label_a)
		var dot_a := 0.28
		if focused or _hover_sys == sys or selected_room == sys:
			dot_a = 1.0
		elif gs.jumps < 1:
			dot_a = 0.85
		elif float(gs.sys_integrity.get(sys, 1.0)) < 0.9:
			dot_a = 0.95
		_draw_info_dot(f, sys, dot_a)
		if selected_room == sys:
			draw_rect(rect.grow(4.0), Color(0.95, 0.35, 0.72, 0.95), false, 3.0)
	if selected_crew >= 0 and selected_crew < gs.crew.size():
		var who := str(gs.crew[selected_crew]["name"])
		draw_string(f, Vector2(16, 18), "Selected: %s. Click a room to station them." % who,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.9, 0.45, 0.98))
	# selected crew ring (crew sprites are children drawn above this)
	if selected_crew >= 0 and selected_crew < _crew_nodes.size():
		draw_arc(_crew_nodes[selected_crew].position, 16.0, 0, TAU, 24, Color(1, 0.9, 0.3), 2.0)


func dept_name(sys: String) -> String:
	return str(DEPT_NAMES.get(sys, sys.capitalize()))


func _draw_info_dot(f: Font, sys: String, alpha: float) -> void:
	var p := _info_dot_pos(sys)
	draw_circle(p, INFO_DOT_R, Color(0.05, 0.12, 0.2, 0.9 * alpha))
	draw_arc(p, INFO_DOT_R, 0, TAU, 18, Color(0.5, 0.9, 1.0, 0.95 * alpha), 1.5)
	var sz := f.get_string_size("i", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(f, p + Vector2(-sz.x * 0.5, 5.0), "i", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.95, 1.0, alpha))


func _draw_dept_label(f: Font, sys: String, rect: Rect2, alpha: float = 0.96) -> void:
	var lines := _wrap_dept(dept_name(sys))
	var lh := 12.0
	var top := rect.position.y - 8.0 - lh * float(lines.size())
	var maxw := rect.size.x + 4.0
	for i in lines.size():
		var line: String = lines[i]
		# shrink the font per line so a name never spills over its neighbour
		var fs := 11
		var sz := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		while sz.x > maxw and fs > 7:
			fs -= 1
			sz = f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := Vector2(rect.position.x + (rect.size.x - sz.x) * 0.5, top + lh * float(i + 1))
		var plate := Rect2(pos + Vector2(-3, -fs - 1), sz + Vector2(6, fs + 4))
		draw_rect(plate, Color(0.02, 0.03, 0.08, 0.85 * alpha), true)
		draw_string(f, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))


func _wrap_dept(dept: String) -> Array:
	var words := dept.split(" ", false)
	if words.size() == 1:
		return [dept]
	# try one line first; if it is wider than a room, split into two balanced lines
	var f := ThemeDB.fallback_font
	if words.size() <= 2 and f.get_string_size(dept, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= ROOM_SIZE.x + 4.0:
		return [dept]
	var mid := int(ceil(float(words.size()) / 2.0))
	return [" ".join(words.slice(0, mid)), " ".join(words.slice(mid))]


func _sys_color(sys: String) -> Color:
	var integ := float(gs.sys_integrity.get(sys, 1.0))
	if integ < 0.35:
		return Color(1.0, 0.3, 0.25)      # red: damaged
	if not gs.sys_online(sys):
		return Color(0.55, 0.55, 0.6)     # grey: unpowered
	if integ < 0.75:
		return Color(1.0, 0.8, 0.25)
	return Color(0.25, 0.92, 0.95)


func _glyph(sys: String) -> String:
	for s in GameData.SYSTEMS:
		if s["id"] == sys:
			return str(s["icon"])
	return "?"


func _sys_max(sys: String) -> int:
	for s in GameData.SYSTEMS:
		if s["id"] == sys:
			return int(s["max"])
	return 0