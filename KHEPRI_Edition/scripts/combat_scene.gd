class_name CombatScene
extends Control

# =============================================================================
# 2D ship-to-ship combat.
#  - two large ships face each other in the middle (player left, enemy right)
#  - hull / shield indicators, choices UNDER the ships (no big opaque window)
#  - lasers and missiles visibly travel across the screen and hit the hull
#  - impact sparks, explosions, screen shake and ship hit-reactions
#  - the enemy counterattacks: enemy attacks reduce the PLAYER's hull
# =============================================================================

signal combat_finished(result: String)   # "win" | "lose" | "flee"

const PLAYER_TEX := "res://assets/generated/ship_nefer.png"
const ENEMY_TEX := "res://assets/generated/ship_raider.png"
const ENEMY_TEX2 := "res://assets/generated/ship_raider_2.png"
const EXPLOSION_TEX := "res://assets/generated/explosion.png"
const LASER_STREAM := "res://assets/generated/audio/laser.mp3"
const EXPLOSION_STREAM := "res://assets/generated/audio/explosion.mp3"

var gs: GameState
var rng := RandomNumberGenerator.new()

var _enemy_name := "Raider"
var _enemy_hull := 60.0
var _enemy_hull_max := 60.0
var _enemy_weapons := 4.0
var _evade_bonus := 0.0
var _shield_bonus := 0.0
var _shields_up := true
var _busy := false
var _finished := false

# Player is much more fragile - one mistake and you lose
var _player_hull := 20.0
var _player_hull_max := 20.0
# Shield is a separate Sprite2D node, not a float
# Player is much more fragile - one mistake and you lose

var _player_hover := 0.0
var _enemy_hover := 0.0
var _hover_speed := 3.0
var _hover_amplitude := 15.0

var _world: Control
var _bg: ColorRect
var _title: Label
var _player_ship: Sprite2D
var _enemy_ship: Sprite2D
var _player_shield: Sprite2D
var _enemy_shield: Sprite2D
var _ph_bar: ProgressBar
var _eh_bar: ProgressBar
var _ph_lbl: Label
var _eh_lbl: Label
var _log_lbl: Label
var _player_row: VBoxContainer
var _enemy_row: VBoxContainer
var _btn_row: HBoxContainer
var _buttons: Array = []
var _pbase := Vector2.ZERO
var _ebase := Vector2.ZERO
var _pscale := 0.5
var _escale := 0.5
var _t := 0.0

var _player_engine: GPUParticles2D
var _enemy_engine: GPUParticles2D

# Lane indicators for dodging - show which row the bullet will hit
var _lane_indicators := []
var _current_lane_warning := -1
var _lane_warning_time := 0.0
var _lane_warning_duration := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	rng.randomize()
	_build()


func _dot_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _ring_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.15))
	g.add_point(0.82, Color(1, 1, 1, 0.9))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _build() -> void:
	_world = Control.new()
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)

	_bg = ColorRect.new()
	_bg.color = Color(0.02, 0.02, 0.05, 0.92)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_world.add_child(_bg)

	_player_shield = _mk_shield(Color(0.4, 0.8, 1.0))
	_enemy_shield = _mk_shield(Color(1.0, 0.5, 0.4))

	_player_ship = Sprite2D.new()
	_player_ship.texture = load(PLAYER_TEX)
	_player_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_ship.z_index = 10
	_world.add_child(_player_ship)

	_enemy_ship = Sprite2D.new()
	_enemy_ship.texture = load(ENEMY_TEX)
	_enemy_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_enemy_ship.z_index = 10
	_enemy_ship.rotation = -PI / 2.0  # nose points at the player
	_world.add_child(_enemy_ship)

	# Lane indicator lines - show which row enemy bullets will hit
	var lane_y_positions := [_pbase.y - 50, _pbase.y, _pbase.y + 50]
	var line_left := Vector2(_world.position.x + 20, 0)
	var line_right := Vector2(_world.position.x + _world.size.x - 20, 0)
	for y in lane_y_positions:
		var line := Line2D.new()
		line.z_index = 11
		# Set line points - from left to right across the screen
		var left := _world.position.x + 20
		var right := _world.position.x + _world.size.x - 20
		line.set_point_position(0, Vector2(left, y))
		line.set_point_position(1, Vector2(right, y))
		# Set line color via modulate (overall tint)
		line.modulate = Color(1.0, 0.8, 0.0, 1.0)
		_world.add_child(line)
		_lane_indicators.append(line)
		line.visible = false

	# Player engine trail particles
	_player_engine = GPUParticles2D.new()
	_player_engine.texture = _dot_texture()
	_player_engine.amount = 8
	_player_engine.lifetime = 0.8
	_player_engine.one_shot = false
	_player_engine.explosiveness = 0.5
	_player_engine.position = _player_ship.position
	_player_engine.z_index = 12
	_player_engine.visible = false
	_world.add_child(_player_engine)

	# Enemy engine trail particles
	_enemy_engine = GPUParticles2D.new()
	_enemy_engine.texture = _dot_texture()
	_enemy_engine.amount = 8
	_enemy_engine.lifetime = 0.8
	_enemy_engine.one_shot = false
	_enemy_engine.explosiveness = 0.5
	_enemy_engine.position = _enemy_ship.position
	_enemy_engine.z_index = 12
	_enemy_engine.visible = false
	_world.add_child(_enemy_engine)

	_title = _mk_label("COMBAT", 24, Color(1.0, 0.6, 0.4))
	_title.z_index = 20
	_world.add_child(_title)

	_player_row = VBoxContainer.new()
	_player_row.z_index = 20
	_world.add_child(_player_row)
	_player_row.add_child(_mk_label("Nefer-1", 15, Color(0.6, 0.9, 1.0)))
	_ph_bar = _mk_bar(Color(0.4, 0.85, 1.0))
	_player_row.add_child(_ph_bar)
	_ph_lbl = _mk_label("", 12)
	_player_row.add_child(_ph_lbl)

	_enemy_row = VBoxContainer.new()
	_enemy_row.z_index = 20
	_world.add_child(_enemy_row)
	_enemy_row.add_child(_mk_label(_enemy_name, 15, Color(1.0, 0.7, 0.6)))
	_eh_bar = _mk_bar(Color(1.0, 0.45, 0.4))
	_enemy_row.add_child(_eh_bar)
	_eh_lbl = _mk_label("", 12)
	_enemy_row.add_child(_eh_lbl)

	_log_lbl = _mk_label("Choose your action.", 15, Color(0.92, 0.95, 1.0))
	_log_lbl.z_index = 20
	_world.add_child(_log_lbl)

	_btn_row = HBoxContainer.new()
	_btn_row.z_index = 20
	_btn_row.add_theme_constant_override("separation", 8)
	_world.add_child(_btn_row)
	var defs := [
		{"t": "Laser  [1]", "cb": _on_laser},
		{"t": "Missile  [2]", "cb": _on_missile},
		{"t": "Shields  [3]", "cb": _on_shield},
		{"t": "Evade  [4]", "cb": _on_evade},
		{"t": "Flee  [5]", "cb": _on_flee},
	]
	for d in defs:
		var b := Button.new()
		b.text = str(d["t"])
		b.custom_minimum_size = Vector2(120, 48)
		UiTheme.style_button(b, "cyan", true)
		b.pressed.connect(d["cb"])
		_btn_row.add_child(b)
		_buttons.append(b)


func _mk_label(text: String, fs: int, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _mk_bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = 100
	b.show_percentage = false
	b.custom_minimum_size = Vector2(240, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.18)
	sb.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", sb)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _mk_shield(col: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _ring_texture()
	s.modulate = Color(col.r, col.g, col.b, 0.0)
	s.z_index = 9
	s.scale = Vector2(2.4, 2.4)
	_world.add_child(s)
	return s


func _enemy_name_lbl_set(n: String) -> void:
	if _enemy_row.get_child_count() > 0:
		(_enemy_row.get_child(0) as Label).text = n


# --- Layout -----------------------------------------------------------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _world:
		_layout()


func _layout() -> void:
	var s := size
	if s.x < 10.0:
		s = Vector2(1280, 720)
	_bg.size = s
	_player_row.position = Vector2(24, 54)
	_enemy_row.position = Vector2(s.x - 264, 54)
	_title.position = Vector2(24, 14)
	_log_lbl.position = Vector2(24, s.y - 128.0)
	_log_lbl.size = Vector2(s.x - 48.0, 30)
	_btn_row.position = Vector2(24, s.y - 92.0)

	_pscale = (s.x * 0.30) / float(_player_ship.texture.get_width())
	_escale = (s.x * 0.24) / float(_enemy_ship.texture.get_width())
	_player_ship.scale = Vector2(_pscale, _pscale)
	_enemy_ship.scale = Vector2(_escale, _escale)
	_pbase = Vector2(s.x * 0.25, s.y * 0.46)
	_ebase = Vector2(s.x * 0.76, s.y * 0.44)
	_player_ship.position = _pbase
	_enemy_ship.position = _ebase
	_player_shield.position = _pbase
	_enemy_shield.position = _ebase


# --- Public start -----------------------------------------------------------
func start(state: GameState, enemy_name: String, diff: float) -> void:
	gs = state
	_enemy_name = enemy_name
	_enemy_hull_max = 60.0 * diff
	_enemy_hull = _enemy_hull_max
	_enemy_weapons = 4.0 * diff
	_evade_bonus = 0.0
	_shield_bonus = 0.0
	_busy = false
	_finished = false
	_enemy_name_lbl_set(enemy_name)
	var use2 := rng.randf() < 0.5
	_enemy_ship.texture = load(ENEMY_TEX2 if use2 else ENEMY_TEX)
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	_update_bars()
	_log_lbl.text = "%s attacks! Choose your action." % enemy_name
	_set_buttons_enabled(true)
	_shields_up = gs.sys_online("shields")
	_refresh_shield_visuals()


func _update_bars() -> void:
	var hull := float(gs.resources["hull"])
	_ph_bar.value = hull
	_ph_lbl.text = "Hull %d%%   Shields %d" % [int(hull), int(gs.shield_strength())]
	_eh_bar.value = clampf(_enemy_hull / maxf(1.0, _enemy_hull_max) * 100.0, 0.0, 100.0)
	_eh_lbl.text = "Hull %d%%" % int(clampf(_enemy_hull / maxf(1.0, _enemy_hull_max) * 100.0, 0.0, 100.0))


func _refresh_shield_visuals() -> void:
	_player_shield.modulate.a = 0.0
	_enemy_shield.modulate.a = 0.0


func _set_buttons_enabled(on: bool) -> void:
	for b in _buttons:
		b.disabled = not on
	if on:
		_buttons[1].disabled = int(gs.counters["ordnance"]) <= 0
		_buttons[0].disabled = not gs.sys_online("weapons")


# --- Player actions ---------------------------------------------------------
func _on_laser() -> void:
	if _busy:
		return
	if not gs.sys_online("weapons"):
		_log_lbl.text = "Weapons have no power."
		return
	_busy = true
	_set_buttons_enabled(false)
	var dmg := 6.0 + gs.sys_effective("weapons") * 5.0
	_log_lbl.text = "Firing lasers..."
	var muzzle := _player_ship.position + Vector2(_pscale * 220.0, 0)
	await _fire_bolt(muzzle, _enemy_ship.position, Color(0.5, 1.0, 0.6), 0.28, false)
	_enemy_hull -= dmg
	gs.apply_fx({"power": -3})
	await _impact(_enemy_ship.position, false)
	_enemy_hit_react()
	_update_bars()
	_log_lbl.text = "Lasers hit for %d damage!" % int(dmg)
	await _wait(0.25)
	_after_player_action()


func _on_missile() -> void:
	if _busy:
		return
	if int(gs.counters["ordnance"]) <= 0:
		_log_lbl.text = "No ordnance left!"
		return
	_busy = true
	_set_buttons_enabled(false)
	var dmg := 14.0 + gs.sys_effective("weapons") * 4.0
	gs.apply_fx({"ordnance": -1})
	_log_lbl.text = "Missile away!"
	var muzzle := _player_ship.position + Vector2(_pscale * 220.0, 40)
	await _fire_bolt(muzzle, _enemy_ship.position, Color(1.0, 0.75, 0.3), 0.75, true)
	_enemy_hull -= dmg
	await _impact(_enemy_ship.position, true)
	_enemy_hit_react()
	_update_bars()
	_log_lbl.text = "Missile detonates! %d damage!" % int(dmg)
	await _wait(0.25)
	_after_player_action()


func _on_shield() -> void:
	if _busy:
		return
	_busy = true
	_set_buttons_enabled(false)
	_shields_up = true
	_shield_bonus = gs.shield_strength() * 0.6
	_log_lbl.text = "Shields raised! Brace for impact."
	await _raise_shield(_player_shield, _pbase)
	await _wait(0.3)
	_after_player_action()


func _on_evade() -> void:
	if _busy:
		return
	if float(gs.resources["fuel"]) < 3.0:
		_log_lbl.text = "Not enough fuel to manoeuvre!"
		return
	_busy = true
	_set_buttons_enabled(false)
	gs.apply_fx({"fuel": -3})
	_evade_bonus = 0.35
	_log_lbl.text = "Evasive manoeuvres - hard to hit!"
	var tw := create_tween()
	tw.tween_property(_player_ship, "position:y", _pbase.y - 60.0, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_player_ship, "position:y", _pbase.y + 40.0, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_player_ship, "position:y", _pbase.y, 0.18).set_trans(Tween.TRANS_SINE)
	await tw.finished
	_after_player_action()


func _on_flee() -> void:
	if _busy:
		return
	if float(gs.resources["fuel"]) < 8.0:
		_log_lbl.text = "Not enough fuel to escape!"
		return
	_busy = true
	_set_buttons_enabled(false)
	gs.apply_fx({"fuel": -8, "hull": -6})
	_log_lbl.text = "Fleeing the fight..."
	var tw := create_tween()
	tw.tween_property(_player_ship, "position", _pbase + Vector2(-size.x, -40), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	_finish("flee")


func _after_player_action() -> void:
	_update_bars()
	if _enemy_hull <= 0.0:
		await _enemy_destroyed()
		_finish("win")
		return
	await _enemy_turn()
	if float(gs.resources["hull"]) <= 0.0:
		await _player_destroyed()
		_finish("lose")
		return
	_busy = false
	_shield_bonus = 0.0
	_evade_bonus = 0.0
	_set_buttons_enabled(true)
	_log_lbl.text = "Choose your action."


# --- Enemy turn -------------------------------------------------------------
func _enemy_turn() -> void:
	_log_lbl.text = "%s returns fire..." % _enemy_name
	
	# Increased fire rate - enemy shoots more frequently
	var shoot_chance := 0.7 - minf(0.3, _enemy_weapons * 0.05)
	var missile := rng.randf() < shoot_chance
	await _fire_bolt(_enemy_ship.position + Vector2(-_escale * 180.0, 0), _player_ship.position, Color(1.0, 0.4, 0.35), 0.5 if missile else 0.3, missile)
	
	var ev := gs.evasion() + _evade_bonus
	if rng.randf() < ev:
		_log_lbl.text = "You dodge their shot!"
		var miss := _player_ship.position + Vector2(rng.randf_range(-90, 90), rng.randf_range(-70, 70))
		await _impact(miss, false)
		await _wait(0.3)
		return

	var raw := _enemy_weapons * rng.randf_range(1.4, 2.6)
	var shield_total := gs.shield_strength() + _shield_bonus
	var absorbed := minf(raw, shield_total)
	var hull_dmg := maxf(0.0, raw - shield_total) * 0.5
	gs.apply_fx({"hull": -hull_dmg})
	var hurt := ""
	if hull_dmg >= 4.0 and not GameData.SYSTEMS.is_empty():
		var pick: Dictionary = GameData.SYSTEMS[rng.randi() % GameData.SYSTEMS.size()]
		gs.damage_system(str(pick["id"]), 0.18)
		hurt = " %s is damaged." % str(pick["name"])
	await _impact(_player_ship.position, raw > 12.0)
	_player_hit_react()
	_update_bars()
	_log_lbl.text = "Enemy hits! Shields absorb %d, hull takes %d.%s" % [int(absorbed), int(hull_dmg), hurt]
	if shield_total > 0.0:
		await _raise_shield(_player_shield, _pbase, true)
	await _wait(0.3)


# --- FX ---------------------------------------------------------------------
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _fire_bolt(from: Vector2, to: Vector2, col: Color, dur: float, missile: bool) -> void:
	var size_v := Vector2(12, 12) if missile else Vector2(54, 7)
	var bolt := ColorRect.new()
	bolt.color = col
	bolt.size = size_v
	bolt.pivot_offset = size_v * 0.5
	bolt.position = from - size_v * 0.5
	bolt.rotation = (to - from).angle()
	bolt.z_index = 15
	_world.add_child(bolt)
	var flash := ColorRect.new()
	flash.color = Color(col.r, col.g, col.b, 0.7)
	flash.size = Vector2(26, 26)
	flash.pivot_offset = Vector2(13, 13)
	flash.position = from - Vector2(13, 13)
	flash.z_index = 15
	_world.add_child(flash)
	var ftw := create_tween()
	ftw.tween_property(flash, "scale", Vector2(2.2, 2.2), 0.16)
	ftw.parallel().tween_property(flash, "modulate:a", 0.0, 0.16)
	ftw.tween_callback(flash.queue_free)
	ZivaSfx.play(self, load(LASER_STREAM), 0.1, -5.0)

	var tw := create_tween()
	tw.tween_property(bolt, "position", to - size_v * 0.5, dur).set_trans(Tween.TRANS_LINEAR)
	await tw.finished
	bolt.queue_free()


func _impact(at: Vector2, big: bool) -> void:
	ZivaSfx.play(self, load(EXPLOSION_STREAM), 0.12, -3.0 if big else -8.0)
	_shake(14.0 if big else 6.0, 0.3)
	var boom := Sprite2D.new()
	boom.texture = load(EXPLOSION_TEX)
	boom.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	boom.position = at
	boom.scale = Vector2(0.3, 0.3)
	boom.z_index = 16
	_world.add_child(boom)
	var tw := create_tween()
	tw.tween_property(boom, "scale", Vector2(1.7, 1.7) if big else Vector2(1.1, 1.1), 0.28).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(boom, "modulate:a", 0.0, 0.5)
	tw.tween_callback(boom.queue_free)
	_sparks(at, big)
	await get_tree().create_timer(0.3).timeout


func _sparks(at: Vector2, big: bool) -> void:
	var p := GPUParticles2D.new()
	p.texture = _dot_texture()
	p.amount = 26 if big else 14
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = at
	p.z_index = 17
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 6.0
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 90.0
	pm.initial_velocity_max = 260.0
	pm.scale_min = 0.4
	pm.scale_max = 1.1
	pm.gravity = Vector3(0, 60, 0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	g.set_color(1, Color(1.0, 0.4, 0.2, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	_world.add_child(p)
	p.emitting = true
	await get_tree().create_timer(1.2).timeout
	p.queue_free()


func _shake(mag: float, dur: float) -> void:
	if UiTheme.reduce_motion:
		return
	var steps := 6
	var per := dur / float(steps)
	var tw := create_tween()
	for i in steps:
		tw.tween_property(_world, "position", Vector2(rng.randf_range(-mag, mag), rng.randf_range(-mag, mag)), per)
	tw.tween_property(_world, "position", Vector2.ZERO, 0.05)


func _raise_shield(shield: Sprite2D, at: Vector2, brief: bool = false) -> void:
	shield.position = at
	shield.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(shield, "modulate:a", 0.9, 0.15)
	tw.parallel().tween_property(shield, "scale", Vector2(3.2, 3.2), 0.2)
	if brief:
		tw.tween_property(shield, "modulate:a", 0.0, 0.4)
	await tw.finished


func _enemy_hit_react() -> void:
	var tw := create_tween()
	tw.tween_property(_enemy_ship, "position", _ebase + Vector2(30, 0), 0.08)
	tw.parallel().tween_property(_enemy_ship, "modulate", Color(1.6, 0.6, 0.6), 0.08)
	tw.tween_property(_enemy_ship, "position", _ebase, 0.3).set_trans(Tween.TRANS_ELASTIC)
	tw.parallel().tween_property(_enemy_ship, "modulate", Color(1, 1, 1), 0.3)


func _player_hit_react() -> void:
	var tw := create_tween()
	tw.tween_property(_player_ship, "position", _pbase + Vector2(-30, 0), 0.08)
	tw.parallel().tween_property(_player_ship, "modulate", Color(1.6, 0.6, 0.6), 0.08)
	tw.tween_property(_player_ship, "position", _pbase, 0.3).set_trans(Tween.TRANS_ELASTIC)
	tw.parallel().tween_property(_player_ship, "modulate", Color(1, 1, 1), 0.3)


func _enemy_destroyed() -> void:
	_log_lbl.text = "Enemy destroyed!"
	for i in 4:
		_impact(_enemy_ship.position + Vector2(rng.randf_range(-50, 50), rng.randf_range(-40, 40)), i == 0)
		await _wait(0.12)
	var tw := create_tween()
	tw.tween_property(_enemy_ship, "modulate:a", 0.0, 0.5)
	await tw.finished


func _player_destroyed() -> void:
	_log_lbl.text = "Hull breached!"
	for i in 3:
		_impact(_player_ship.position + Vector2(rng.randf_range(-40, 40), rng.randf_range(-30, 30)), true)
		await _wait(0.15)


# --- End --------------------------------------------------------------------
func _finish(result: String) -> void:
	if _finished:
		return
	_finished = true
	_set_buttons_enabled(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_really_finish.bind(result))


func _really_finish(result: String) -> void:
	visible = false
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_finished.emit(result)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy or _finished or gs == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_on_laser()
				get_viewport().set_input_as_handled()
			KEY_2:
				_on_missile()
				get_viewport().set_input_as_handled()
			KEY_3:
				_on_shield()
				get_viewport().set_input_as_handled()
			KEY_4:
				_on_evade()
				get_viewport().set_input_as_handled()
			KEY_5:
				_on_flee()
				get_viewport().set_input_as_handled()
			KEY_W:
				# Move player ship up
				_player_ship.position = _pbase + Vector2(-_pscale * 100, -20)
				get_viewport().set_input_as_handled()
			KEY_S:
				# Move player ship down
				_player_ship.position = _pbase + Vector2(-_pscale * 100, 20)
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	if not visible:
		return
	# Continuous hover/float animation for player ship
	_player_hover += delta * _hover_speed
	_player_ship.position = _pbase + Vector2(0, sin(_player_hover) * _hover_amplitude)
	
	# Continuous hover/float animation for enemy ship
	_enemy_hover += delta * _hover_speed
	_enemy_ship.position = _ebase + Vector2(0, sin(_enemy_hover + 1.3) * _hover_amplitude)
	
	# Engine trail particles follow player ship
	_player_engine.position = _player_ship.position
	_player_engine.visible = _shields_up and gs and gs.sys_online("weapons") and float(gs.resources["fuel"]) > 0.0
	
	# Engine trail particles follow enemy ship
	_enemy_engine.position = _enemy_ship.position
	_enemy_engine.visible = true
	
	# Shield glow pulse animation
	if _shields_up and gs and gs.sys_online("shields"):
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		_player_shield.modulate = Color(0.5, 0.9, 1.0, pulse)
		_enemy_shield.modulate = Color(1.0, 0.5, 0.4, pulse)
		
		var shield_bonus_total := gs.shield_strength() + _shield_bonus
		_enemy_shield.modulate = Color(1.0, 0.5, 0.4, maxf(_enemy_shield.modulate.a, pulse))