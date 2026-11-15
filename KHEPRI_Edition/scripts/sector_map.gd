class_name SectorMapView
extends Control

# =============================================================================
# FTL-style sector map: branching beacons you jump between. Reachable nodes
# glow and are clickable; the current node is marked; the destination body
# (Moon/Mars) sits at the far right.
# =============================================================================

signal travel_requested(node_index: int)

const MARGIN := Vector2(70, 60)

var gs: GameState
var _t: float = 0.0
var _beacon_tex: Texture2D
var _hover: int = -1
var _dest: Sprite2D


func _ready() -> void:
	custom_minimum_size = Vector2(560, 340)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_beacon_tex = load("res://assets/generated/beacon.png")
	_dest = Sprite2D.new()
	_dest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dest.z_index = -1
	add_child(_dest)
	set_process(true)


func set_state(state: GameState) -> void:
	gs = state
	if _dest:
		var body := str(gs.mission.get("to", "planet_moon"))
		_dest.texture = load("res://assets/generated/%s.png" % body)
		if _dest.texture:
			var sc := 56.0 / float(_dest.texture.get_width())
			_dest.scale = Vector2(sc, sc)
	queue_redraw()


func _node_pos(i: int) -> Vector2:
	if gs == null or i < 0 or i >= gs.beacons.size():
		return Vector2.ZERO
	var b: Dictionary = gs.beacons[i]
	var layers := maxf(1.0, float(gs.layer_count() - 1))
	var px := MARGIN.x + (size.x - MARGIN.x * 2.0) * (float(b["layer"]) / layers)
	var usable := size.y - MARGIN.y * 2.0 - 28.0
	var py := MARGIN.y + usable * float(b["pos"].y)
	return Vector2(px, py)


func _process(delta: float) -> void:
	_t += delta
	if _dest:
		_dest.position = Vector2(size.x - 34, size.y * 0.5)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if gs == null:
		return
	if event is InputEventMouseMotion:
		_hover = _node_at((event as InputEventMouseMotion).position)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var i := _node_at((event as InputEventMouseButton).position)
		if i >= 0 and i in gs.travel_options():
			travel_requested.emit(i)


func _node_at(pos: Vector2) -> int:
	if gs == null:
		return -1
	for i in gs.beacons.size():
		if _node_pos(i).distance_to(pos) < 32.0:
			return i
	return -1


func _draw() -> void:
	if gs == null:
		return
	var f := ThemeDB.fallback_font
	var opts: Array = gs.travel_options()
	# links
	for i in gs.beacons.size():
		for n in gs.beacons[i]["next"]:
			var a := _node_pos(i)
			var b := _node_pos(n)
			var active: bool = (i == gs.at_node and n in opts) or bool(gs.beacons[i]["visited"])
			var col := Color(0.5, 0.8, 1.0, 0.55) if active else Color(0.5, 0.55, 0.7, 0.22)
			draw_dashed_line(a, b, col, 2.0, 7.0)
	# destination planet on the far right (drawn by the _dest Sprite2D)
	var dpos := Vector2(size.x - 34, size.y * 0.5)
	draw_string(f, dpos + Vector2(-40, 52), "TO " + str(gs.mission.get("to", "")).replace("planet_", "").to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.GOLD)
	# beacons
	for i in gs.beacons.size():
		var b: Dictionary = gs.beacons[i]
		var p := _node_pos(i)
		var meta: Dictionary = GameData.BEACON_TYPES[b["type"]]
		var base: Color = meta["color"]
		var reachable: bool = i in opts
		var pulse := 1.0
		if reachable and not UiTheme.reduce_motion:
			pulse = 1.0 + 0.12 * sin(_t * 3.0)
		var sz := 34.0 * pulse
		if _beacon_tex:
			var mod := base
			if not reachable and not b["visited"]:
				mod = base.darkened(0.35)
			if b["visited"]:
				mod = base.darkened(0.55)
			draw_texture_rect(_beacon_tex, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, mod)
		# ring for reachable / current
		if reachable:
			draw_arc(p, 24.0, 0, TAU, 32, UiTheme.CYAN, 2.5)
		if i == gs.at_node:
			draw_arc(p, 28.0, 0, TAU, 32, UiTheme.MAGENTA, 3.0)
			draw_string(f, p + Vector2(-18, -30), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.GOLD)
		if _hover == i or reachable:
			draw_string(f, p + Vector2(-46, 36), "%s (%s)" % [str(b.get("name", "")), str(meta["name"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95))
	# trajectory: faint path through the nodes already travelled
	var prev := -1
	for i in gs.beacons.size():
		if bool(gs.beacons[i]["visited"]):
			if prev >= 0:
				draw_line(_node_pos(prev), _node_pos(i), Color(1.0, 0.85, 0.3, 0.45), 2.0)
			prev = i
	# title and legend
	draw_string(f, Vector2(12, 22), "GALAXY MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.CYAN)
	draw_string(f, Vector2(12, 42), "Pick a glowing planet to visit next! The pink ring is your ship. Hover a planet to peek.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.TEXT)
	var lx := 12.0
	var ly := size.y - 8.0
	for k in GameData.BEACON_TYPES:
		var lm: Dictionary = GameData.BEACON_TYPES[k]
		var short_name := str(lm["name"]).split(" ")[0]
		draw_rect(Rect2(lx, ly - 12, 10, 10), lm["color"], true)
		draw_string(f, Vector2(lx + 14, ly), short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.94, 1.0))
		lx += 18.0 + f.get_string_size(short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x