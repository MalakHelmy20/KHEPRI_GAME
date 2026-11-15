class_name SurfaceScene
extends Control

# =============================================================================
# Walk-the-surface sample collection.
# Land on the Moon or Mars, walk your astronaut along the ground, stand next to
# a glowing sample and press E to collect it. Each sample shows a short, real
# science explanation. Collect all three for a bonus, then fly back to the ship.
# =============================================================================

signal finished(samples: int, info: Array)

const WALK_SPEED := 300.0
const GRAVITY := 1500.0
const JUMP_V := -620.0

# Per-body sample spots: label, science fact, x fraction across the ground.
const SAMPLES := {
	"planet_moon": [
		{"name": "Moon dust", "fact": "The Moon is covered in fine grey dust called regolith. The bits are sharp, like tiny glass, so spacesuits need strong boots."},
		{"name": "Basalt rock", "fact": "This dark rock came from ancient lava flows. The dark patches on the Moon are huge plains of frozen lava, called 'seas'."},
		{"name": "Water ice", "fact": "In craters that never see sunlight, the Moon hides frozen water. That ice could one day give astronauts air, water and fuel."},
	],
	"planet_mars": [
		{"name": "Red dust", "fact": "Mars looks red because its dust is full of rust (iron oxide). The whole planet is basically covered in rusty sand."},
		{"name": "Layered rock", "fact": "The stripes in this rock are layers of mud and sand. They are a clue that rivers and lakes flowed here billions of years ago."},
		{"name": "Ice crystal", "fact": "Mars has water ice at its poles and just under the ground, frozen for millions of years. Ice is a top target for future explorers."},
	],
}

var gs: GameState
var body := "planet_moon"
var input_gate: Callable = Callable()

var _collected: Array = []        # indices collected
var _info: Array = []             # short log of what was collected
var _pos := Vector2.ZERO
var _vy := 0.0
var _ground_y := 0.0
var _t := 0.0
var _near := -1
var _cooldown := 0.0
var _facts: Array = []

# Phases: walk and collect samples, then a rover catching mini-game, then done.
const PHASE_EXPLORE := 0
const PHASE_CATCH := 1
const PHASE_DONE := 2
var _phase := PHASE_EXPLORE
var _ready_for_catch := false
var _rover_x := 0.0
var _caught := 0
var _missed := 0
var _catch_target := 10
var _time_left := 45.0
var _spawn_t := 0.0
var _done_t := 0.0
var _items: Array = []        # {pos: Vector2, vy: float, r: float}
var _rover_flash := 0.0

var _player: Sprite2D
var _banner: Label
var _prompt: Label
# popup
var _popup: PanelContainer
var _popup_title: Label
var _popup_body: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false

	_player = Sprite2D.new()
	_player.texture = load("res://assets/generated/crew_astronaut.png")
	_player.scale = Vector2(0.8, 0.8)
	_player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player.z_index = 5
	add_child(_player)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.add_theme_color_override("font_color", UiTheme.GOLD)
	_banner.position = Vector2(24, 18)
	add_child(_banner)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", UiTheme.TEXT)
	_prompt.visible = false
	add_child(_prompt)

	_build_popup()

	var back := Button.new()
	back.text = "Return to ship"
	UiTheme.style_button(back, "magenta")
	back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	back.offset_left = -260.0
	back.offset_top = -86.0
	back.offset_right = -18.0
	back.offset_bottom = -18.0
	back.pressed.connect(leave)
	add_child(back)

	set_process(true)


func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.CYAN, 22))
	_popup.visible = false
	# Draw the science note above the astronaut, never under it.
	_popup.z_index = 20
	add_child(_popup)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_popup.add_child(v)
	_popup_title = Label.new()
	_popup_title.add_theme_font_size_override("font_size", 24)
	_popup_title.add_theme_color_override("font_color", UiTheme.GOLD)
	v.add_child(_popup_title)
	_popup_body = Label.new()
	_popup_body.add_theme_font_size_override("font_size", 19)
	_popup_body.add_theme_color_override("font_color", UiTheme.TEXT)
	_popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_body.custom_minimum_size = Vector2(520, 0)
	v.add_child(_popup_body)
	var ok := Button.new()
	ok.text = "Keep exploring"
	UiTheme.style_button(ok, "gold")
	ok.pressed.connect(_close_popup)
	v.add_child(ok)


func open(state: GameState, target_body: String) -> void:
	gs = state
	body = target_body
	_collected.clear()
	_info.clear()
	_facts = SAMPLES.get(body, SAMPLES["planet_moon"])
	_vy = 0.0
	_near = -1
	_cooldown = 0.0
	_phase = PHASE_EXPLORE
	_ready_for_catch = false
	_items.clear()
	_caught = 0
	_missed = 0
	_done_t = 0.0
	if _player:
		_player.visible = true
	_ground_y = maxf(size.y, 540.0) - 120.0
	_pos = Vector2(maxf(size.x, 800.0) * 0.12, _ground_y)
	_popup.visible = false
	var body_name := "the Moon" if body == "planet_moon" else "Mars"
	_banner.text = "Landing on %s  -  collect 3 samples!" % body_name
	# Always cover the whole screen, even if the parent layout has not settled.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vs := get_viewport_rect().size
	if vs.x > 100.0:
		size = vs
	visible = true
	_player.position = _pos
	# Drop any HUD focus so E / walk keys never activate a button underneath.
	if get_viewport():
		get_viewport().gui_release_focus()
	queue_redraw()


# Swallow walk / interact keys so they never reach a HUD button behind us.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _popup and _popup.visible:
		# Enter / Space / E closes the science note instead of pressing a button.
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
			_close_popup()
			get_viewport().set_input_as_handled()
		return
	if input_gate.is_valid() and bool(input_gate.call()):
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("move_left") \
			or event.is_action_pressed("move_right") or event.is_action_pressed("move_up") \
			or event.is_action_pressed("move_down"):
		get_viewport().set_input_as_handled()


func _close_popup() -> void:
	_popup.visible = false
	if _phase == PHASE_DONE:
		# The mini-game is over: close the window and fly back to the ship.
		leave()
		return
	if _ready_for_catch:
		_start_catch()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _cooldown > 0.0:
		_cooldown -= delta
	_ground_y = maxf(size.y, 540.0) - 120.0
	var blocked: bool = input_gate.is_valid() and bool(input_gate.call())
	var ui_blocked: bool = blocked or (_popup != null and _popup.visible)
	if _phase == PHASE_CATCH:
		if not ui_blocked:
			_update_catch(delta)
	elif _phase == PHASE_DONE:
		# Auto-close the window a moment after the mini-game ends.
		_done_t -= delta
		if _done_t <= 0.0:
			leave()
			return
	else:
		if not ui_blocked:
			var dir := 0.0
			if Input.is_action_pressed("move_left"):
				dir -= 1.0
			if Input.is_action_pressed("move_right"):
				dir += 1.0
			_pos.x += dir * WALK_SPEED * delta
			_pos.x = clampf(_pos.x, 40.0, maxf(size.x, 800.0) - 40.0)
			# jump / gravity
			if Input.is_action_just_pressed("move_up") and _pos.y >= _ground_y - 1.0:
				_vy = JUMP_V
			_vy += GRAVITY * delta
			_pos.y += _vy * delta
			if _pos.y >= _ground_y:
				_pos.y = _ground_y
				_vy = 0.0
			if Input.is_action_just_pressed("interact") and _cooldown <= 0.0:
				_try_collect()
		_update_near()
		if _player:
			_player.position = _pos
	queue_redraw()


func _sample_x(i: int) -> float:
	var w := maxf(size.x, 800.0)
	return w * (0.30 + 0.22 * float(i))


func _update_near() -> void:
	_near = -1
	for i in _facts.size():
		if i in _collected:
			continue
		if absf(_pos.x - _sample_x(i)) < 46.0:
			_near = i
			break
	if _prompt == null:
		return
	if _near < 0:
		_prompt.visible = false
	else:
		_prompt.visible = true
		_prompt.text = "Press  E  to collect:  %s" % str(_facts[_near]["name"])
		_prompt.position = Vector2(clampf(_sample_x(_near) - 150.0, 12.0, maxf(size.x, 800.0) - 320.0), _ground_y - 150.0)


func _try_collect() -> void:
	# Recompute which sample is in reach, so a key press is never missed just
	# because the player stepped onto the sample in this very frame.
	_update_near()
	if _near < 0:
		return
	_cooldown = 0.4
	var idx := _near
	_collected.append(idx)
	var fact: Dictionary = _facts[idx]
	_info.append(fact)
	if gs != null:
		gs.apply_fx({"science": 8})
	var done := _collected.size() >= _facts.size()
	var extra := ""
	if done:
		_ready_for_catch = true
		if gs != null:
			gs.apply_fx({"science": 10, "morale": 6})
		extra = "\n\nThat is all three samples - bonus science! Now jump in the rover: a game is about to start where you catch the falling %s." % _dust_name()
	_popup_title.text = "Sample collected: %s" % str(fact["name"])
	_popup_body.text = "%s%s" % [str(fact["fact"]), extra]
	_popup.visible = true
	_popup.reset_size()
	_popup.position = Vector2(
		maxf(size.x, 800.0) * 0.5 - _popup.size.x * 0.5,
		maxf(size.y, 540.0) * 0.5 - _popup.size.y * 0.5)
	_banner.text = "Samples collected:  %d / %d   -   press E at a glow to grab it" % [_collected.size(), _facts.size()]


# Called by the game's "Return to ship" button / hotkey.
func leave() -> void:
	if not visible:
		return
	visible = false
	_popup.visible = false
	finished.emit(_collected.size(), _info.duplicate())


# --- Rover catching mini-game ------------------------------------------------
func _dust_name() -> String:
	return "moon dust" if body == "planet_moon" else "mars dust"


func _rover_rect() -> Rect2:
	var w := maxf(size.x, 800.0)
	var rw := 120.0
	var rh := 46.0
	var cx := clampf(_rover_x, rw * 0.5 + 18.0, w - rw * 0.5 - 18.0)
	return Rect2(cx - rw * 0.5, _ground_y - rh, rw, rh)


func _start_catch() -> void:
	_phase = PHASE_CATCH
	_ready_for_catch = false
	_caught = 0
	_missed = 0
	_time_left = 45.0
	_spawn_t = 0.4
	_items.clear()
	_rover_flash = 0.0
	_rover_x = maxf(size.x, 800.0) * 0.5
	if _player:
		_player.visible = false
	_prompt.visible = false
	_banner.text = "Catch the falling %s!  Move the rover with  <-  ->" % _dust_name()
	if gs != null:
		gs.apply_fx({"morale": 4})


func _update_catch(delta: float) -> void:
	_time_left -= delta
	var dir := 0.0
	if Input.is_action_pressed("move_left"):
		dir -= 1.0
	if Input.is_action_pressed("move_right"):
		dir += 1.0
	_rover_x += dir * 430.0 * delta
	_rover_x = clampf(_rover_x, 70.0, maxf(size.x, 800.0) - 70.0)
	# spawn the next falling piece of moon dust
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = randf_range(0.42, 0.9)
		var w := maxf(size.x, 800.0)
		_items.append({"pos": Vector2(randf_range(50.0, w - 50.0), 70.0),
			"vy": randf_range(175.0, 265.0), "r": randf_range(11.0, 17.0)})
	var rr := _rover_rect()
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		it["pos"].y += float(it["vy"]) * delta
		var p: Vector2 = it["pos"]
		if p.y >= rr.position.y + 4.0 and p.x >= rr.position.x - 8.0 and p.x <= rr.end.x + 8.0:
			_items.remove_at(i)
			_caught += 1
			_rover_flash = 0.22
			if gs != null:
				gs.apply_fx({"science": 1})
			_play_catch_sound()
			continue
		if p.y > _ground_y + 50.0:
			_items.remove_at(i)
			_missed += 1
	if _rover_flash > 0.0:
		_rover_flash -= delta
	_banner.text = "Catch the %s!   Caught: %d / %d    Time: %ds" % [
		_dust_name(), _caught, _catch_target, int(ceil(maxf(_time_left, 0.0)))]
	if _caught >= _catch_target or _time_left <= 0.0:
		_finish_catch()


func _play_catch_sound() -> void:
	var path := "res://assets/generated/audio/radio_blip.mp3"
	if ResourceLoader.exists(path):
		ZivaSfx.play(self, load(path), 0.0, 0.0)


func _finish_catch() -> void:
	if _phase == PHASE_DONE:
		return
	_phase = PHASE_DONE
	_done_t = 2.4
	var win := _caught >= _catch_target
	if gs != null:
		gs.apply_fx({"science": 10 if win else 4, "morale": 6 if win else 2})
	_popup_title.text = "Great catching!" if win else "Time is up!"
	_popup_body.text = "The rover caught %d piece(s) of %s.%s\n\nThey are safely stowed for scientists on Earth. Returning to the ship..." % [
		_caught, _dust_name(), "  Amazing work!" if win else "  Nice try!"]
	_popup.visible = true
	_popup.reset_size()
	_popup.position = Vector2(
		maxf(size.x, 800.0) * 0.5 - _popup.size.x * 0.5,
		maxf(size.y, 540.0) * 0.5 - _popup.size.y * 0.5)
	_banner.text = "Mission complete - returning to the ship..."


# --- Draw -------------------------------------------------------------------
func _draw() -> void:
	var w := maxf(size.x, 800.0)
	var h := maxf(size.y, 540.0)
	var ground_top := h - 120.0
	# sky
	var sky_top := Color(0.05, 0.05, 0.14)
	var sky_bot := Color(0.10, 0.14, 0.30)
	var ground := Color(0.42, 0.44, 0.50)
	var ground_dark := Color(0.30, 0.32, 0.38)
	if body == "planet_mars":
		sky_top = Color(0.35, 0.16, 0.10)
		sky_bot = Color(0.80, 0.46, 0.22)
		ground = Color(0.66, 0.32, 0.20)
		ground_dark = Color(0.48, 0.22, 0.14)
	# sky bands
	var bands := 24
	for i in bands:
		var t := float(i) / float(bands - 1)
		var c := sky_top.lerp(sky_bot, t)
		draw_rect(Rect2(0, float(i) * ground_top / float(bands), w, ground_top / float(bands) + 1.0), c, true)
	# stars on the Moon, sun haze on Mars
	if body == "planet_moon":
		for i in 60:
			var sx := fmod(float(i) * 137.5, w)
			var sy := fmod(float(i) * 89.3, ground_top * 0.9)
			draw_circle(Vector2(sx, sy), 1.6, Color(1, 1, 1, 0.7))
		draw_circle(Vector2(w * 0.82, h * 0.16), 34.0, Color(0.35, 0.65, 1.0))
		draw_circle(Vector2(w * 0.82, h * 0.16), 34.0, Color(0.6, 0.85, 1.0), false, 2.0)
	else:
		draw_circle(Vector2(w * 0.80, h * 0.18), 46.0, Color(1.0, 0.9, 0.6, 0.9))
	# ground
	draw_rect(Rect2(0, ground_top, w, h - ground_top), ground, true)
	draw_rect(Rect2(0, ground_top, w, 8.0), ground_dark, true)
	for i in 26:
		var rx := fmod(float(i) * 211.0, w)
		draw_circle(Vector2(rx, ground_top + 40.0 + fmod(float(i) * 53.0, 70.0)), 5.0 + fmod(float(i), 4.0), ground_dark)
	# sample spots
	var f := ThemeDB.fallback_font
	for i in _facts.size():
		var sx := _sample_x(i)
		var sy := ground_top + 26.0
		if i in _collected:
			draw_circle(Vector2(sx, sy), 12.0, UiTheme.GOOD)
			_draw_centered(f, "v", Vector2(sx, sy + 5.0), 16, Color(0.05, 0.2, 0.1))
			continue
		var glow := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(Vector2(sx, sy), 18.0 + glow * 4.0, Color(1.0, 0.9, 0.4, 0.25 + 0.2 * glow))
		draw_circle(Vector2(sx, sy), 11.0, Color(1.0, 0.86, 0.4))
		draw_circle(Vector2(sx, sy), 11.0, UiTheme.GOLD, false, 2.0)
		_draw_centered(f, "!", Vector2(sx, sy + 6.0), 18, Color(0.2, 0.12, 0.0))
	if _phase != PHASE_EXPLORE:
		_draw_catch(f)


func _draw_catch(f: Font) -> void:
	# falling moon dust
	for it in _items:
		var p: Vector2 = it["pos"]
		var r: float = it["r"]
		draw_circle(p, r + 6.0, Color(1.0, 0.9, 0.5, 0.22))
		draw_circle(p, r, Color(0.88, 0.88, 0.94))
		draw_circle(p, r, UiTheme.GOLD, false, 2.0)
		draw_circle(p - Vector2(r * 0.3, r * 0.3), r * 0.32, Color(1, 1, 1, 0.7))
	# the rover you drive
	var rr := _rover_rect()
	var rover_body := Color(1.0, 0.95, 0.55) if _rover_flash > 0.0 else Color(0.76, 0.79, 0.9)
	draw_circle(Vector2(rr.position.x + 24.0, rr.end.y - 8.0), 13.0, Color(0.18, 0.18, 0.24))
	draw_circle(Vector2(rr.end.x - 24.0, rr.end.y - 8.0), 13.0, Color(0.18, 0.18, 0.24))
	draw_rect(Rect2(rr.position.x, rr.position.y + 10.0, rr.size.x, rr.size.y - 20.0), rover_body, true)
	draw_rect(Rect2(rr.position.x, rr.position.y + 10.0, rr.size.x, rr.size.y - 20.0), Color(0.33, 0.38, 0.5), false, 3.0)
	draw_rect(Rect2(rr.position.x + 12.0, rr.position.y - 2.0, rr.size.x - 24.0, 16.0), Color(0.4, 0.9, 1.0, 0.85), true)
	draw_arc(Vector2(rr.get_center().x, rr.position.y - 2.0), 18.0, PI, TAU, 18, UiTheme.CYAN, 3.0)
	_draw_centered(f, "ROVER", Vector2(rr.get_center().x, rr.position.y + 30.0), 13, Color(0.14, 0.17, 0.24))
	# catch progress bar
	var w := maxf(size.x, 800.0)
	draw_rect(Rect2(w * 0.5 - 160.0, 98.0, 320.0, 16.0), Color(0.05, 0.08, 0.16, 0.8), true)
	draw_rect(Rect2(w * 0.5 - 160.0, 98.0, 320.0 * clampf(float(_caught) / float(_catch_target), 0.0, 1.0), 16.0), UiTheme.GOOD, true)
	_draw_centered(f, "caught  %d / %d" % [_caught, _catch_target], Vector2(w * 0.5, 92.0), 16, UiTheme.TEXT)


func _draw_centered(f: Font, text: String, center: Vector2, fs: int, col: Color) -> void:
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, center + Vector2(-sz.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)