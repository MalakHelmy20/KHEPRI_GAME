class_name Cutscene
extends Control

# =============================================================================
# Real 2D cinematic player. Every sequence is animated with tweens, animated
# sprites, particle bursts, a parallax starfield, screen shake, fades and
# sound cues. It is NOT a text box: the ships, planets and particles carry the
# scene, with a short subtitle line at the bottom.
#   play("launch") / play("travel", {"planet": "planet_moon", "caption": "..."})
# =============================================================================

signal finished

const SHIP_TEX := "res://assets/generated/ship_nefer.png"
const STAR_TILE := "res://assets/generated/star_tile.png"
const THRUST := "res://assets/generated/audio/thrust.mp3"

var _seq := ""
var _ctx: Dictionary = {}
var _done := false

var _layer_far: TextureRect
var _layer_near: TextureRect
var _veil: ColorRect
var _flash: ColorRect
var _planet: Sprite2D
var _ship: Sprite2D
var _trail: GPUParticles2D
var _streaks: GPUParticles2D
var _caption: Label
var _skip: Button

var _master: Tween
var _scroll_far: Tween
var _scroll_near: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var tile: Texture2D = load(STAR_TILE)
	_layer_far = _mk_layer(tile, Color(0.5, 0.6, 0.9, 1.0))
	_layer_far.modulate = Color(0.6, 0.7, 1.0, 1.0)
	_layer_near = _mk_layer(tile, Color(1, 1, 1, 1))
	_layer_near.modulate = Color(1, 1, 1, 1)

	_veil = ColorRect.new()
	_veil.color = Color(0.02, 0.02, 0.06, 0.55)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)

	_planet = Sprite2D.new()
	_planet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_planet.visible = false
	_planet.z_index = 5
	add_child(_planet)

	_trail = _mk_particles(Color(0.5, 0.85, 1.0))
	_trail.emitting = false
	add_child(_trail)

	_streaks = _mk_particles(Color(0.85, 0.92, 1.0))
	_streaks.amount = 60
	_streaks.lifetime = 1.1
	_streaks.emitting = false
	var spm := _streaks.process_material as ParticleProcessMaterial
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(700, 400, 0)
	spm.direction = Vector3(-1, 0, 0)
	spm.spread = 4.0
	spm.initial_velocity_min = 500.0
	spm.initial_velocity_max = 900.0
	spm.scale_min = 0.2
	spm.scale_max = 0.5
	add_child(_streaks)

	_ship = Sprite2D.new()
	_ship.texture = load(SHIP_TEX)
	_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ship.visible = false
	_ship.z_index = 10
	add_child(_ship)

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_skip = Button.new()
	_skip.text = "SKIP >>"
	_skip.add_theme_font_size_override("font_size", 14)
	_skip.pressed.connect(_end)
	add_child(_skip)


func _mk_layer(tex: Texture2D, mod: Color) -> TextureRect:
	var l := TextureRect.new()
	l.texture = tex
	l.stretch_mode = TextureRect.STRETCH_TILE
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.modulate = mod
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(-128, 0)
	add_child(l)
	return l


func _mk_particles(col: Color) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.texture = _dot_texture()
	p.amount = 30
	p.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10, 24, 0)
	pm.direction = Vector3(-1, 0, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 120.0
	pm.initial_velocity_max = 260.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.95))
	g.set_color(1, Color(col.r * 0.4, col.g * 0.5, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	return p


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


func _layout() -> void:
	var s := size
	if s.x < 10.0:
		s = Vector2(1280, 720)
	_layer_far.size = Vector2(s.x + 128.0, s.y)
	_layer_near.size = Vector2(s.x + 128.0, s.y)
	_veil.size = s
	_flash.size = s
	_caption.position = Vector2(0, s.y - 78.0)
	_caption.size = Vector2(s.x, 40)
	_skip.position = Vector2(s.x - 100.0, 12.0)


# --- Public API -------------------------------------------------------------
func play(seq: String, ctx: Dictionary = {}) -> void:
	_seq = seq
	_ctx = ctx
	_done = false
	visible = true
	_layout()
	_reset()
	_start_scroll()
	_run()


func _start_scroll() -> void:
	if _scroll_far and _scroll_far.is_valid():
		_scroll_far.kill()
	if _scroll_near and _scroll_near.is_valid():
		_scroll_near.kill()
	_layer_far.position.x = -128.0
	_layer_near.position.x = -128.0
	_scroll_far = create_tween().set_loops()
	_scroll_far.tween_property(_layer_far, "position:x", 0.0, 16.0).from(-128.0)
	_scroll_near = create_tween().set_loops()
	_scroll_near.tween_property(_layer_near, "position:x", 0.0, 7.0).from(-128.0)


func _reset() -> void:
	if _master and _master.is_valid():
		_master.kill()
	_layer_far.modulate = Color(0.6, 0.7, 1.0, 1.0)
	_layer_near.modulate = Color(1, 1, 1, 1)
	_veil.color = Color(0.02, 0.02, 0.06, 0.45)
	_flash.color.a = 0.0
	_planet.visible = false
	_ship.visible = false
	_ship.modulate = Color(1, 1, 1, 1)
	_trail.emitting = false
	_streaks.emitting = false
	_caption.text = str(_ctx.get("caption", ""))
	_caption.modulate.a = 0.0
	position = Vector2.ZERO


func _shake(mag: float, dur: float, tw: Tween) -> void:
	if UiTheme.reduce_motion:
		tw.tween_interval(0.01)
		return
	var steps := 6
	var per := dur / float(steps)
	for i in steps:
		tw.tween_property(self, "position", Vector2(randf_range(-mag, mag), randf_range(-mag, mag)), per)
	tw.tween_property(self, "position", Vector2.ZERO, 0.06)


func _show_caption(tw: Tween, hold: float) -> void:
	tw.tween_property(_caption, "modulate:a", 1.0, 0.5)
	tw.tween_interval(hold)
	tw.tween_property(_caption, "modulate:a", 0.0, 0.5)


func _planet_for(body: String) -> Texture2D:
	var p := "res://assets/generated/%s.png" % body
	if ResourceLoader.exists(p):
		return load(p)
	return load("res://assets/generated/planet_moon.png")


func _from() -> String:
	return str(_ctx.get("from", "planet_earth"))


func _to() -> String:
	return str(_ctx.get("planet", "planet_moon"))


# --- Sequences --------------------------------------------------------------
func _run() -> void:
	var s := size
	if s.x < 10.0:
		s = Vector2(1280, 720)
	match _seq:
		"launch": _seq_launch(s)
		"depart_earth": _seq_depart(s)
		"travel": _seq_travel(s)
		"planet_approach": _seq_approach(s)
		"arrival": _seq_arrival(s)
		_: _seq_story(s)
	if _master:
		_master.finished.connect(_on_master_done)


func _seq_launch(s: Vector2) -> void:
	_ship.visible = true
	_ship.texture = load(SHIP_TEX)
	_ship.rotation = -PI / 2.0
	_ship.scale = Vector2(0.5, 0.5)
	_ship.position = Vector2(s.x * 0.5, s.y * 0.86)
	_trail.position = _ship.position
	_trail.rotation = PI  # flame points down while flying up
	_trail.emitting = true
	if _caption.text == "":
		_caption.text = "LIFT-OFF - clearing the tower"
	ZivaSfx.play(self, load(THRUST), 0.05, -2.0)
	_master = create_tween()
	_shake(9.0, 0.7, _master)
	_master.tween_property(_ship, "position", Vector2(s.x * 0.5, s.y * 0.45), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_master.parallel().tween_property(_trail, "position", Vector2(s.x * 0.5, s.y * 0.45), 1.1)
	_master.parallel().tween_property(_ship, "scale", Vector2(0.7, 0.7), 1.1)
	_master.parallel().tween_property(_caption, "modulate:a", 1.0, 0.5)
	_master.tween_property(_ship, "position", Vector2(s.x * 0.5, -s.y * 0.6), 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_master.parallel().tween_property(_trail, "position", Vector2(s.x * 0.5, -s.y * 0.6), 1.5)
	_master.tween_interval(0.3)
	_master.tween_property(_caption, "modulate:a", 0.0, 0.4)


func _seq_depart(s: Vector2) -> void:
	_planet.visible = true
	_planet.texture = _planet_for(_from())
	_planet.position = Vector2(s.x * 0.28, s.y * 0.5)
	_planet.scale = Vector2(2.4, 2.4)
	_ship.visible = true
	_ship.texture = load(SHIP_TEX)
	_ship.rotation = -PI / 2.0
	_ship.scale = Vector2(0.45, 0.45)
	_ship.position = Vector2(s.x * 0.5, s.y * 0.62)
	_trail.position = _ship.position
	_trail.rotation = PI
	_trail.emitting = true
	if _caption.text == "":
		_caption.text = "DEPARTING EARTH"
	ZivaSfx.play(self, load(THRUST), 0.05, -6.0)
	_master = create_tween()
	_master.tween_property(_caption, "modulate:a", 1.0, 0.5)
	_master.parallel().tween_property(_planet, "position", Vector2(-s.x * 0.22, s.y * 0.5), 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_master.parallel().tween_property(_planet, "scale", Vector2(0.7, 0.7), 3.0)
	_master.parallel().tween_property(_ship, "position", Vector2(s.x + 200.0, s.y * 0.12), 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_master.parallel().tween_property(_trail, "position", Vector2(s.x + 200.0, s.y * 0.12), 3.0)
	_master.tween_property(_caption, "modulate:a", 0.0, 0.4)


func _seq_travel(s: Vector2) -> void:
	_planet.visible = false
	_ship.visible = true
	_ship.texture = load(SHIP_TEX)
	_ship.rotation = -PI / 2.0
	_ship.scale = Vector2(0.5, 0.5)
	_ship.position = Vector2(s.x * 0.5, s.y * 0.5)
	_trail.position = Vector2(s.x * 0.5, s.y * 0.62)
	_trail.rotation = PI
	_trail.emitting = true
	_streaks.emitting = true
	_streaks.position = Vector2(s.x * 0.5, s.y * 0.5)
	_layer_far.modulate = Color(0.7, 0.85, 1.0, 1.0)
	if _caption.text == "":
		_caption.text = "TRAVELING THROUGH SPACE"
	ZivaSfx.play(self, load(THRUST), 0.05, -10.0)
	_master = create_tween()
	_master.tween_property(_caption, "modulate:a", 1.0, 0.5)
	_master.parallel().tween_property(_streaks, "modulate:a", 1.0, 0.4)
	# gentle bob
	var bob := create_tween().set_loops()
	bob.tween_property(_ship, "position:y", _ship.position.y + 8.0, 1.0).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_ship, "position:y", _ship.position.y - 8.0, 1.0).set_trans(Tween.TRANS_SINE)
	_master.tween_interval(2.6)
	_master.parallel().tween_property(_streaks, "modulate:a", 0.0, 0.8)
	_master.tween_interval(0.4)
	_master.tween_property(_caption, "modulate:a", 0.0, 0.4)
	_master.tween_callback(bob.kill)


func _seq_approach(s: Vector2) -> void:
	_planet.visible = true
	_planet.texture = _planet_for(_to())
	_planet.position = Vector2(s.x * 0.72, s.y * 0.5)
	_planet.scale = Vector2(0.2, 0.2)
	_ship.visible = true
	_ship.texture = load(SHIP_TEX)
	_ship.rotation = -PI / 2.0
	_ship.scale = Vector2(0.4, 0.4)
	_ship.position = Vector2(-120.0, s.y * 0.5)
	_trail.position = _ship.position
	_trail.rotation = PI
	_trail.emitting = true
	if _caption.text == "":
		_caption.text = "PLANET APPROACH"
	ZivaSfx.play(self, load(THRUST), 0.05, -8.0)
	_master = create_tween()
	_master.tween_property(_caption, "modulate:a", 1.0, 0.5)
	_master.parallel().tween_property(_planet, "scale", Vector2(2.0, 2.0), 3.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_master.parallel().tween_property(_ship, "position", Vector2(s.x * 0.4, s.y * 0.5), 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_master.parallel().tween_property(_trail, "position", Vector2(s.x * 0.4, s.y * 0.5), 3.2)
	_master.tween_property(_caption, "modulate:a", 0.0, 0.4)


func _seq_arrival(s: Vector2) -> void:
	_planet.visible = true
	_planet.texture = _planet_for(_to())
	_planet.position = Vector2(s.x * 0.5, s.y * 0.5)
	_planet.scale = Vector2(2.6, 2.6)
	_ship.visible = true
	_ship.texture = load(SHIP_TEX)
	_ship.rotation = 0.0
	_ship.scale = Vector2(0.4, 0.4)
	_ship.position = Vector2(s.x * 0.5, s.y * 0.62)
	_trail.emitting = false
	if _caption.text == "":
		_caption.text = "ARRIVAL - welcome to the destination"
	_master = create_tween()
	_master.tween_property(_caption, "modulate:a", 1.0, 0.5)
	_master.parallel().tween_property(_ship, "position", Vector2(s.x * 0.5, s.y * 0.5), 1.4).set_trans(Tween.TRANS_SINE)
	_master.tween_property(_flash, "color:a", 0.9, 0.35)
	_master.tween_callback(_flash_pop)
	_master.tween_interval(0.6)
	_master.tween_property(_flash, "color:a", 0.0, 0.6)
	_master.tween_property(_caption, "modulate:a", 0.0, 0.5)


func _flash_pop() -> void:
	_planet.scale = Vector2(3.2, 3.2)


func _seq_story(s: Vector2) -> void:
	_planet.visible = true
	_planet.texture = _planet_for(_to())
	_planet.position = Vector2(s.x * 0.5, s.y * 0.46)
	_planet.scale = Vector2(1.6, 1.6)
	_ship.visible = true
	_ship.texture = load(SHIP_TEX)
	_ship.rotation = -PI / 2.0
	_ship.scale = Vector2(0.45, 0.45)
	_ship.position = Vector2(s.x * 0.28, s.y * 0.62)
	_trail.emitting = true
	_trail.position = _ship.position
	_trail.rotation = PI
	if _caption.text == "":
		_caption.text = "An important moment..."
	_master = create_tween()
	_master.tween_property(_caption, "modulate:a", 1.0, 0.5)
	_master.parallel().tween_property(_planet, "scale", Vector2(2.2, 2.2), 3.0).set_trans(Tween.TRANS_SINE)
	_master.tween_property(_caption, "modulate:a", 0.0, 0.5)


# --- Completion -------------------------------------------------------------
func _on_master_done() -> void:
	_finish()


func _end() -> void:
	if _master and _master.is_valid():
		_master.kill()
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	visible = false
	_trail.emitting = false
	_streaks.emitting = false
	finished.emit()