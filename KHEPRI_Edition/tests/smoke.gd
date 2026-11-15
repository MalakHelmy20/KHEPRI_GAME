extends SceneTree
# Headless playthrough of the real Main scene: starts a mission and clicks through everything.
var g: Node
var steps := 0
var done := false
var mission_idx := 0
var band := "junior"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: mission_idx = int(args[0])
	if args.size() > 1: band = args[1]
	GameData.band = band
	Engine.time_scale = 30.0
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)

func _first_btn(n: Node) -> Button:
	if n == null or not (n is CanvasItem) or not (n as CanvasItem).is_visible_in_tree():
		return null
	for b in n.find_children("*", "Button", true, false):
		var bb := b as Button
		if bb.is_visible_in_tree() and not bb.disabled and bb.text != "":
			return bb
	return null

func _press(b: Button) -> void:
	b.pressed.emit()

var _started := false
func _process(_d: float) -> bool:
	steps += 1
	if steps == 5 and not _started:
		_started = true
		if band == "tutorial":
			GameData.band = "junior"
			g._start_tutorial()
		else:
			g._start_mission(GameData.MISSIONS[mission_idx])
		return false
	if not _started:
		return false
	if steps > 60000:
		print("FAIL: timeout, screen=", g.screen, " traveling=", g._traveling, " node=", g.gs.at_node)
		quit(1); return true
	if band == "tutorial" and g._tutorial_done:
		print("PASS tutorial finished, gates seen=", g.gs.gates_seen)
		quit(0); return true
	if g._mission_ended and g.report.visible:
		print("PASS ", GameData.MISSIONS[mission_idx]["name"], " band=", band, " won=", g.gs.won, " jumps=", g.gs.jumps, " sci=", g.gs.science, " gates=", g.gs.gates_solved, "/", g.gs.gates_seen, " lifelines left=", g.gs.lifelines, " reason=", g.gs.end_reason)
		quit(0); return true
	if steps % 3 != 0:
		return false
	if g.cutscene and g.cutscene.visible: 
		return false
	if g._traveling: return false
	# blockers, in order
	if band == "tutorial" and g.tutorial and not (g.overlay and g.overlay.visible) and not (g.radio and g.radio.is_busy()):
		var tb := _first_btn(g.tutorial)
		if tb:
			_press(tb)
			return false
	if g.overlay and g.overlay.visible:
		var b := _first_btn(g.pop_btns)
		if b: _press(b)
		return false
	if g.radio and g.radio.is_busy():
		var rb := _first_btn(g.radio._btns)
		if rb: _press(rb)
		return false
	for n in [g.scan_panel, g.briefing, g.room_info, g.library]:
		if n and n.visible:
			var sb := _first_btn(n)
			if sb: _press(sb)
			return false
	if g.food_overlay and g.food_overlay.visible:
		g.food_active = false; g.food_overlay.visible = false
		return false
	# Surface landing: walk to an uncollected sample, grab it, then fly back.
	if g.surface and g.surface.visible:
		var idx := 0
		while idx < g.surface._facts.size() and idx in g.surface._collected:
			idx += 1
		if idx < g.surface._facts.size():
			print("SURFACE ", g.surface.body, " collecting sample ", idx)
			g.surface._pos.x = g.surface._sample_x(idx)
			g.surface._try_collect()
		g.surface.leave()
		return false
	if g.screen == "launch":
		g._launch_now(false); return false
	if g.screen == "map":
		var opts: Array = g.gs.travel_options()
		if opts.size() > 0 and not g.gs.is_final_node():
			g._travel(opts[randi() % opts.size()])
		return false
	if g.screen == "space":
		if g.gs.is_final_node(): return false
		g._open_map(); return false
	# launch page buttons etc.
	if g.launch_page and g.launch_page.visible:
		g._launch_now(false); return false
	return false
