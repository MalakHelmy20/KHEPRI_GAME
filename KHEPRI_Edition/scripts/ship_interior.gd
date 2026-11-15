class_name ShipInterior
extends Control

# =============================================================================
# Walk-the-ship interior ("Explore mode") - a cosy, animated deck.
# A top row and a bottom row of ROOMS sit either side of a central corridor.
# You control an astronaut (arrow keys / WASD); stand inside a room and press
# E to peek inside: you get a simple, real-life science explanation.
# Everything is animated by hand (bobbing walk, footstep dust, bubbling plants,
# blinking consoles, wandering crew) so the ship feels alive.
# =============================================================================

signal room_inspected(sys: String)
signal power_requested(sys: String, delta: int)

# Two rows of five rooms. Top row along the top of the deck, bottom row below
# the corridor.
const STATIONS := [
	"bio", "oxygen", "shields", "weapons", "piloting",
	"engines", "repair", "sensors", "comms", "medbay",
]
const ROW_0 := ["bio", "oxygen", "shields", "weapons", "piloting"]
const ROW_1 := ["engines", "repair", "sensors", "comms", "medbay"]

# Friendly room names a seven-year-old understands.
const PRETTY := {
	"piloting": "Cockpit", "engines": "Engine Room", "oxygen": "Air Room",
	"shields": "Shield", "weapons": "Tractor", "sensors": "Science Lab",
	"comms": "Radio Room", "bio": "Space Garden", "repair": "Fix-It Room", "medbay": "Med Bay",
}

const PLAYER_SPEED := 250.0
const CREW_SPEED := 70.0
const INTERACT_COOLDOWN := 0.35

var gs: GameState
var checked: Dictionary = {}
var input_gate: Callable = Callable()

var _player: Sprite2D
var _shadow_on := true
var _crew: Array = []            # {node, target, wait, phase, speed}
var _pos := Vector2.ZERO
var _facing := 1.0
var _walk_phase := 0.0
var _step_prev := 0
var _moving := false
var _t := 0.0
var _near := ""
var _cooldown := 0.0
var _deck_cache := Rect2()
var _dust: Array = []            # {pos, life, r}
var _prompt_card: PanelContainer
var _prompt_label: Label
var _progress_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(560, 380)
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_player = Sprite2D.new()
	_player.texture = load("res://assets/generated/crew_astronaut.png")
	_player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player.z_index = 10
	add_child(_player)

	_build_footer()
	resized.connect(_on_resized)
	set_process(true)


func _build_footer() -> void:
	_prompt_card = PanelContainer.new()
	_prompt_card.add_theme_stylebox_override("panel", UiTheme.card(UiTheme.GOLD, 0.28, 18))
	_prompt_card.visible = false
	_prompt_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt_card)
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_prompt_card.add_child(_prompt_label)

	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 18)
	_progress_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_label)


func set_state(state: GameState) -> void:
	gs = state
	checked.clear()
	if get_viewport():
		get_viewport().gui_release_focus()
	_setup_crew()
	_on_resized()
	if _pos == Vector2.ZERO:
		_pos = _corridor_rect().get_center()
	_refresh_progress()


func _setup_crew() -> void:
	for c in _crew:
		(c["node"] as Node).queue_free()
	_crew.clear()
	if gs == null:
		return
	var cols := [Color(0.75, 0.92, 1.0), Color(1.0, 0.86, 0.62), Color(0.82, 1.0, 0.82), Color(1.0, 0.8, 0.92)]
	for i in gs.crew.size():
		var s := Sprite2D.new()
		s.texture = load("res://assets/generated/crew_astronaut.png")
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.modulate = cols[i % cols.size()]
		s.z_index = 8
		add_child(s)
		_crew.append({"node": s, "target": _random_spot(), "wait": randf_range(0.0, 2.0),
			"phase": randf() * TAU, "speed": randf_range(0.8, 1.2)})
		s.position = _random_spot()


# --- Geometry ---------------------------------------------------------------
func _deck_rect() -> Rect2:
	var w := maxf(size.x, 460.0)
	var h := maxf(size.y, 320.0)
	return Rect2(16, 46, w - 32, h - 116)


func _deck() -> Rect2:
	if _deck_cache == Rect2():
		_deck_cache = _deck_rect()
	return _deck_cache


func _corridor_h() -> float:
	return clampf(_deck().size.y * 0.17, 54.0, 88.0)


func _corridor_rect() -> Rect2:
	var d := _deck()
	var corr := _corridor_h()
	var rh := (d.size.y - corr) / 2.0
	return Rect2(d.position.x, d.position.y + rh, d.size.x, corr)


func _room_rect(sys: String) -> Rect2:
	var d := _deck()
	var idx := STATIONS.find(sys)
	if idx < 0:
		return Rect2()
	var col := idx % 5
	var row := floori(float(idx) / 5.0)
	var cw := d.size.x / 5.0
	var corr := _corridor_h()
	var rh := (d.size.y - corr) / 2.0
	var y := d.position.y
	if row == 1:
		y = d.position.y + rh + corr
	return Rect2(d.position.x + col * cw, y, cw, rh)


func _station_center(sys: String) -> Vector2:
	var r := _room_rect(sys)
	return r.get_center() + Vector2(0, r.size.y * 0.14)


func _room_at(p: Vector2) -> String:
	for sys in STATIONS:
		if _room_rect(sys).grow(-8.0).has_point(p):
			return sys
	return ""


func _random_spot() -> Vector2:
	var d := _deck()
	return d.position + Vector2(randf_range(0.1, 0.9) * d.size.x, randf_range(0.12, 0.88) * d.size.y)


func _on_resized() -> void:
	_deck_cache = _deck_rect()
	if _pos == Vector2.ZERO:
		_pos = _corridor_rect().get_center()


# --- Input / update ---------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	_deck_cache = _deck_rect()
	if _cooldown > 0.0:
		_cooldown -= delta
	var blocked: bool = input_gate.is_valid() and bool(input_gate.call())
	_moving = false
	if not blocked and gs != null:
		var dir := Vector2.ZERO
		if Input.is_action_pressed("move_left"):
			dir.x -= 1.0
		if Input.is_action_pressed("move_right"):
			dir.x += 1.0
		if Input.is_action_pressed("move_up"):
			dir.y -= 1.0
		if Input.is_action_pressed("move_down"):
			dir.y += 1.0
		if dir != Vector2.ZERO:
			_moving = true
			dir = dir.normalized()
			_pos += dir * PLAYER_SPEED * delta
			_walk_phase += delta * 13.0
			if absf(dir.x) > 0.1:
				_facing = signf(dir.x)
			var pad := 16.0
			_pos.x = clampf(_pos.x, _deck().position.x + pad, _deck().end.x - pad)
			_pos.y = clampf(_pos.y, _deck().position.y + pad, _deck().end.y - pad)
			_emit_footsteps()
		if Input.is_action_just_pressed("interact") and _cooldown <= 0.0:
			_try_interact()
	_update_near()
	_update_crew(delta)
	_update_dust(delta)
	_update_player()
	queue_redraw()


func _emit_footsteps() -> void:
	var step := int(_walk_phase / PI)
	if step != _step_prev:
		_step_prev = step
		if not UiTheme.reduce_motion:
			_dust.append({"pos": _pos + Vector2(-_facing * 6.0, 12.0), "life": 0.5, "r": 3.0})


func _update_dust(delta: float) -> void:
	for i in range(_dust.size() - 1, -1, -1):
		var p: Dictionary = _dust[i]
		p["life"] = float(p["life"]) - delta
		p["r"] = float(p["r"]) + delta * 20.0
		if float(p["life"]) <= 0.0:
			_dust.remove_at(i)


func _update_player() -> void:
	if _player == null:
		return
	var bob := 0.0
	var sx := 1.0
	var sy := 1.0
	if _moving and not UiTheme.reduce_motion:
		bob = sin(_walk_phase * 2.0) * 2.5
		sx = 1.0 + sin(_walk_phase * 2.0) * 0.06
		sy = 1.0 - sin(_walk_phase * 2.0) * 0.06
	elif not UiTheme.reduce_motion:
		# gentle idle breathing
		sy = 1.0 + sin(_t * 2.0) * 0.03
	_player.position = _pos + Vector2(0, bob)
	_player.scale = Vector2(0.8 * sx * _facing, 0.8 * sy)
	_player.flip_h = _facing < 0.0


func _update_crew(delta: float) -> void:
	for c in _crew:
		var node: Sprite2D = c["node"]
		var target: Vector2 = c["target"]
		if c["wait"] > 0.0:
			c["wait"] = float(c["wait"]) - delta
		else:
			var to: Vector2 = target - node.position
			if to.length() < 8.0:
				c["wait"] = randf_range(1.2, 3.5)
				c["target"] = _random_spot()
			else:
				node.position += to.normalized() * CREW_SPEED * float(c["speed"]) * delta
				node.flip_h = to.x < 0.0
		var walking: bool = c["wait"] <= 0.0
		var s := 0.5 if walking else 0.5 + sin(_t * 2.0 + c["phase"]) * 0.02
		node.scale = Vector2(s, s)


func _update_near() -> void:
	_near = _room_at(_pos)
	if _prompt_card == null:
		return
	if _near == "":
		_prompt_card.visible = false
		return
	_prompt_card.visible = true
	var done: bool = checked.has(_near)
	_prompt_label.text = ("Look again:  %s" if done else "Press E to look inside:  %s") % _pretty(_near)
	_prompt_card.reset_size()
	_prompt_card.position = Vector2(
		clampf(_station_center(_near).x - _prompt_card.size.x * 0.5, 8.0, size.x - _prompt_card.size.x - 8.0),
		_deck().end.y + 6.0)


func _try_interact() -> void:
	if _near == "":
		return
	_cooldown = INTERACT_COOLDOWN
	checked[_near] = true
	_refresh_progress()
	room_inspected.emit(_near)


func request_power(sys: String, delta: int) -> void:
	power_requested.emit(sys, delta)


# Swallow walk / interact keys so they never reach a HUD button behind the deck.
func _input(event: InputEvent) -> void:
	if not visible or gs == null:
		return
	if input_gate.is_valid() and bool(input_gate.call()):
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("move_left") \
			or event.is_action_pressed("move_right") or event.is_action_pressed("move_up") \
			or event.is_action_pressed("move_down"):
		get_viewport().set_input_as_handled()


func _refresh_progress() -> void:
	if _progress_label == null:
		return
	_progress_label.text = "Rooms explored:  %d / %d" % [checked.size(), STATIONS.size()]
	_progress_label.position = Vector2(20, 14)


func _pretty(sys: String) -> String:
	return str(PRETTY.get(sys, sys.capitalize()))


# --- Palette ----------------------------------------------------------------
func _accent(sys: String) -> Color:
	match sys:
		"bio":
			return Color(0.5, 0.95, 0.5)
		"oxygen":
			return Color(0.5, 0.85, 1.0)
		"shields":
			return Color(0.5, 1.0, 0.95)
		"weapons":
			return Color(0.85, 0.6, 1.0)
		"piloting":
			return Color(1.0, 0.85, 0.4)
		"engines":
			return Color(1.0, 0.6, 0.3)
		"repair":
			return Color(0.8, 0.82, 0.9)
		"sensors":
			return Color(0.45, 1.0, 0.8)
		"comms":
			return Color(1.0, 0.6, 0.85)
		"medbay":
			return Color(1.0, 0.55, 0.6)
	return UiTheme.CYAN


func _status_color(sys: String) -> Color:
	if gs == null:
		return UiTheme.CYAN
	var integ := float(gs.sys_integrity.get(sys, 1.0))
	if integ < 0.35:
		return Color(1.0, 0.4, 0.4)
	if not gs.sys_online(sys):
		return Color(0.62, 0.64, 0.74)
	if integ < 0.75:
		return Color(1.0, 0.8, 0.32)
	return _accent(sys)


func _glyph(sys: String) -> String:
	for s in GameData.SYSTEMS:
		if s["id"] == sys:
			return str(s["icon"])
	return "?"


# --- Draw -------------------------------------------------------------------
func _draw() -> void:
	var d := _deck()
	var f := ThemeDB.fallback_font
	# hull
	draw_rect(d.grow(8.0), Color(0.07, 0.09, 0.24, 0.75), true)
	draw_rect(d.grow(8.0), Color(0.55, 0.85, 1.0, 0.9), false, 4.0)
	# corridor floor + moving light dashes
	var corr := _corridor_rect()
	draw_rect(corr, Color(0.12, 0.15, 0.34, 1.0), true)
	draw_line(Vector2(corr.position.x, corr.position.y), Vector2(corr.end.x, corr.position.y), Color(0.5, 0.7, 1.0, 0.4), 1.5)
	draw_line(Vector2(corr.position.x, corr.end.y), Vector2(corr.end.x, corr.end.y), Color(0.5, 0.7, 1.0, 0.4), 1.5)
	var dash_n := 16
	for i in dash_n:
		var x := corr.position.x + fmod(float(i) * (corr.size.x / dash_n) + _t * 40.0, corr.size.x)
		draw_rect(Rect2(x, corr.get_center().y - 2.0, 26.0, 4.0), Color(0.6, 0.85, 1.0, 0.18))
	# rooms
	for sys in STATIONS:
		_draw_room(f, sys)
	# dust puffs
	for p in _dust:
		var a := clampf(float(p["life"]) / 0.5, 0.0, 1.0)
		draw_circle(p["pos"], float(p["r"]), Color(0.8, 0.85, 1.0, 0.25 * a))
	# player shadow
	if _shadow_on:
		draw_circle(_pos + Vector2(0, 14.0), 15.0, Color(0.0, 0.0, 0.0, 0.30))
	# crew name tags
	for i in _crew.size():
		if gs != null and i < gs.crew.size():
			_draw_label(f, str(gs.crew[i]["name"]), (_crew[i]["node"] as Node2D).position + Vector2(0, -24), 12, UiTheme.TEXT_DIM)


func _draw_room(f: Font, sys: String) -> void:
	var r := _room_rect(sys)
	var accent := _accent(sys)
	var st := _status_color(sys)
	var is_near: bool = sys == _near
	var done: bool = checked.has(sys)
	# floor
	draw_rect(r, Color(accent.r, accent.g, accent.b, 0.16), true)
	# walls: outer edge + sides; door gap on the corridor side
	var row := floori(float(STATIONS.find(sys)) / 5.0)
	var wall := Color(st.r, st.g, st.b, 0.55 if not done else 0.85)
	var w := 3.0
	var door_w := 44.0
	var cx := r.get_center().x
	# sides
	draw_line(Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), wall, w)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), wall, w)
	# outer edge (top for row 0, bottom for row 1)
	if row == 0:
		draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), wall, w)
	else:
		draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), wall, w)
	# corridor edge with a doorway gap
	var ey := r.end.y if row == 0 else r.position.y
	draw_line(Vector2(r.position.x, ey), Vector2(cx - door_w * 0.5, ey), wall, w)
	draw_line(Vector2(cx + door_w * 0.5, ey), Vector2(r.end.x, ey), wall, w)
	# doorway light
	draw_rect(Rect2(cx - door_w * 0.5, ey - 3.0, door_w, 6.0), Color(1.0, 0.95, 0.7, 0.55))
	# furniture along the outer wall
	_draw_furniture(f, sys, r, accent)
	# station glow where you stand
	var c := _station_center(sys)
	var pulse := 0.0 if UiTheme.reduce_motion else 0.5 + 0.5 * sin(_t * 3.0)
	if is_near:
		draw_circle(c + Vector2(0, 6.0), 34.0 + pulse * 5.0, Color(1.0, 0.9, 0.45, 0.30))
		draw_circle(c + Vector2(0, 6.0), 30.0, Color(1.0, 0.9, 0.45, 0.16))
	# sign plate with the room name
	var nm := _pretty(sys)
	var name_y := r.position.y + 22.0 if row == 0 else r.end.y - 10.0
	_draw_centered(f, nm, Vector2(r.get_center().x, name_y), 16, UiTheme.TEXT)
	# checked tick on a bright disc
	if done:
		draw_circle(Vector2(r.end.x - 16.0, (r.position.y + 16.0) if row == 0 else (r.end.y - 16.0)), 12.0, UiTheme.GOOD)
		_draw_centered(f, "v", Vector2(r.end.x - 16.0, (r.position.y + 21.0) if row == 0 else (r.end.y - 11.0)), 17, Color(0.05, 0.2, 0.1))


func _draw_furniture(_f: Font, sys: String, r: Rect2, accent: Color) -> void:
	var row := floori(float(STATIONS.find(sys)) / 5.0)
	# furniture sits against the outer wall, away from the doorway
	var base_y := r.position.y + 44.0 if row == 0 else r.end.y - 40.0
	var cx := r.get_center().x
	var blink := 0.5 + 0.5 * sin(_t * 5.0 + float(sys.length()))
	match sys:
		"bio":  # plants growing + bubbles
			for i in 3:
				var px := cx - 24.0 + i * 24.0
				draw_rect(Rect2(px - 8.0, base_y + 10.0, 16.0, 12.0), Color(0.45, 0.3, 0.2), true)
				var h := 16.0 + sin(_t * 2.0 + i) * 3.0
				draw_rect(Rect2(px - 3.0, base_y + 10.0 - h, 6.0, h), accent, true)
			for i in 4:
				var by := base_y + 8.0 - fmod(_t * 26.0 + i * 14.0, 34.0)
				draw_circle(Vector2(cx + 30.0, by), 2.4, Color(0.8, 1.0, 0.8, 0.7))
		"oxygen":  # air tanks
			for i in 2:
				var tx := cx - 14.0 + i * 28.0
				draw_rect(Rect2(tx - 8.0, base_y - 4.0, 16.0, 30.0), Color(0.7, 0.8, 0.9), true)
				draw_rect(Rect2(tx - 8.0, base_y - 4.0, 16.0, 30.0), accent, false, 2.0)
				draw_circle(Vector2(tx, base_y - 8.0), 5.0, accent)
		"shields":  # pulsing dome
			var rr := 22.0 + (0.0 if UiTheme.reduce_motion else sin(_t * 3.0) * 3.0)
			draw_arc(Vector2(cx, base_y + 14.0), rr, PI, TAU, 24, accent, 3.0)
			draw_arc(Vector2(cx, base_y + 14.0), rr - 7.0, PI, TAU, 24, Color(accent.r, accent.g, accent.b, 0.5), 2.0)
		"weapons":  # tractor magnet ring
			draw_arc(Vector2(cx, base_y + 6.0), 16.0, 0, TAU, 20, accent, 4.0)
			draw_arc(Vector2(cx, base_y + 6.0), 16.0 + blink * 8.0, 0, TAU, 20, Color(accent.r, accent.g, accent.b, 0.35), 2.0)
			draw_line(Vector2(cx - 12.0, base_y + 6.0), Vector2(cx + 12.0, base_y + 6.0), Color(0.9, 0.9, 1.0), 2.0)
		"piloting":  # console with a flickering screen
			draw_rect(Rect2(cx - 30.0, base_y - 2.0, 60.0, 26.0), Color(0.2, 0.24, 0.4), true)
			draw_rect(Rect2(cx - 24.0, base_y + 2.0, 48.0, 12.0), Color(0.4, 0.9, 1.0, 0.5 + blink * 0.4), true)
			for i in 3:
				draw_circle(Vector2(cx - 20.0 + i * 20.0, base_y - 6.0), 4.0, Color(1.0, 0.6 + blink * 0.3, 0.3))
		"engines":  # pipes + flickering flame
			draw_rect(Rect2(cx - 30.0, base_y + 2.0, 60.0, 12.0), Color(0.5, 0.5, 0.6), true)
			var fl := 14.0 + (0.0 if UiTheme.reduce_motion else sin(_t * 20.0) * 5.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 8.0, base_y + 14.0), Vector2(cx + 8.0, base_y + 14.0),
				Vector2(cx, base_y + 14.0 + fl)]), Color(1.0, 0.7, 0.2, 0.85))
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 4.0, base_y + 14.0), Vector2(cx + 4.0, base_y + 14.0),
				Vector2(cx, base_y + 14.0 + fl * 0.6)]), Color(1.0, 1.0, 0.7, 0.9))
		"repair":  # tool bench + warning light
			draw_rect(Rect2(cx - 28.0, base_y, 56.0, 20.0), Color(0.4, 0.42, 0.5), true)
			draw_rect(Rect2(cx - 24.0, base_y + 4.0, 48.0, 12.0), Color(0.3, 0.32, 0.4), true)
			draw_circle(Vector2(cx + 24.0, base_y - 6.0), 5.0, Color(1.0, 0.5 + blink * 0.4, 0.3))
		"sensors":  # telescope with a sweeping beam
			draw_rect(Rect2(cx - 24.0, base_y + 6.0, 48.0, 10.0), Color(0.35, 0.45, 0.5), true)
			var ang := -0.6 + (0.0 if UiTheme.reduce_motion else sin(_t * 1.5) * 0.5)
			var tip := Vector2(cx, base_y + 6.0) + Vector2(cos(ang), sin(ang)) * 34.0
			draw_line(Vector2(cx, base_y + 6.0), tip, accent, 4.0)
			draw_circle(tip, 4.0, Color(0.8, 1.0, 0.9))
		"comms":  # dish with expanding signal arcs
			draw_arc(Vector2(cx, base_y + 8.0), 16.0, PI * 0.15, PI * 0.85, 18, Color(0.8, 0.85, 0.95), 4.0)
			for i in 3:
				var a := 0.6 - i * 0.16
				draw_arc(Vector2(cx, base_y + 8.0), 22.0 + i * 8.0 + blink * 3.0, -PI * 0.6, -PI * 0.05, 16,
					Color(accent.r, accent.g, accent.b, a), 2.0)
			draw_rect(Rect2(cx - 2.0, base_y + 8.0, 4.0, 14.0), Color(0.7, 0.75, 0.85), true)
		"medbay":  # bed + beating heart cross
			draw_rect(Rect2(cx - 28.0, base_y + 6.0, 56.0, 16.0), Color(0.85, 0.88, 0.95), true)
			draw_rect(Rect2(cx - 28.0, base_y + 6.0, 18.0, 8.0), Color(0.95, 0.95, 1.0), true)
			var beat := 1.0 + (0.0 if UiTheme.reduce_motion else maxf(0.0, sin(_t * 4.0)) * 0.35)
			var hs := 8.0 * beat
			draw_rect(Rect2(cx + 16.0 - hs * 0.35, base_y - 8.0 - hs, hs * 0.7, hs * 2.0), Color(1.0, 0.4, 0.45))
			draw_rect(Rect2(cx + 16.0 - hs, base_y - 8.0 - hs * 0.35, hs * 2.0, hs * 0.7), Color(1.0, 0.4, 0.45))


func _draw_centered(f: Font, text: String, center: Vector2, fs: int, col: Color) -> void:
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, center + Vector2(-sz.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_label(f: Font, text: String, center: Vector2, fs: int, col: Color) -> void:
	_draw_centered(f, text, center, fs, col)