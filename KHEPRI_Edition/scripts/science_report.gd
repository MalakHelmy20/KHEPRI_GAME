class_name ScienceReport
extends Control

# =============================================================================
# Post-mission scientific report (User segment). Presents the mission like a
# science result rather than an exam: objective, instruments, data, findings,
# what the evidence supports, what cannot yet be concluded, and the next
# research question.
# =============================================================================

signal closed

var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 30)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.custom_minimum_size = Vector2(980, 0)
	scroll.add_child(_content)


func _lbl(text: String, fs: int, col: Color = Color(0.92, 0.96, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# No forced minimum width: labels fill their container and wrap to it, so
	# wide text never overflows the report (the HBox rows were forcing 960px each).
	return l


# A short label for use INSIDE a horizontal row. Wrapping must be off here,
# otherwise the row squeezes it to one character per line.
func _lbl_nowrap(text: String, fs: int, col: Color = Color(0.92, 0.96, 1.0)) -> Label:
	var l := _lbl(text, fs, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _field(title: String, body: String, col: Color = Color(0.92, 0.96, 1.0)) -> void:
	_content.add_child(_lbl(title, 16, UiTheme.CYAN))
	_content.add_child(_lbl(body, 16, col))


func open(info: Dictionary) -> void:
	visible = true
	for c in _content.get_children():
		c.queue_free()

	var won := bool(info.get("won", true))
	var mid := str(info.get("mission_id", ""))
	var m: Dictionary = Education.mission(mid)
	var score := int(info.get("score", 0))
	var grade := str(info.get("grade", "C"))
	var stars := int(info.get("stars", 0))
	var rank := str(info.get("rank", "Explorer"))

	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.GOLD if won else UiTheme.MAGENTA, 18))
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	banner.add_child(bv)
	bv.add_child(_lbl("STAGE CLEAR!" if won else "MISSION ENDED", 36, UiTheme.GOLD if won else UiTheme.PINK))
	bv.add_child(_lbl(_stars_line(stars), 28, UiTheme.GOLD))
	bv.add_child(_lbl("Rank: %s" % rank, 20, UiTheme.TEXT))
	bv.add_child(_lbl(str(info.get("mission_name", "")), 16, UiTheme.CYAN))
	var rewards := HBoxContainer.new()
	rewards.add_theme_constant_override("separation", 18)
	rewards.add_child(_lbl_nowrap("Science  %d" % int(info.get("science", 0)), 18, UiTheme.GOOD))
	rewards.add_child(_lbl_nowrap("Score  %d/100" % score, 18, UiTheme.CYAN))
	rewards.add_child(_lbl_nowrap("Grade  %s" % grade, 18, UiTheme.PINK))
	rewards.add_child(_lbl_nowrap("Days  %d" % int(info.get("days", 0)), 18, UiTheme.TEXT))
	bv.add_child(rewards)
	if str(info.get("stage_name", "")) != "":
		bv.add_child(_lbl("Design stage: %s" % str(info.get("stage_name", "")), 16, UiTheme.GOLD))
		bv.add_child(_lbl(str(info.get("stage_question", "")), 16, UiTheme.TEXT))
		bv.add_child(_lbl(str(info.get("stage_blurb", "")), 15, UiTheme.TEXT_DIM))
	bv.add_child(_lbl("Arriving is only part of a mission. Scientists need the data you bring home.", 16, UiTheme.TEXT))
	bv.add_child(_claim_button())
	_content.add_child(banner)
	_content.add_child(HSeparator.new())
	_content.add_child(_lbl("SCIENTIFIC MISSION REPORT", 26, UiTheme.CYAN))

	# headline scores
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	head.add_child(_lbl_nowrap("Science returned: %d" % int(info.get("science", 0)), 18, Color(0.6, 0.95, 0.7)))
	head.add_child(_lbl_nowrap("Science score: %d / 100" % score, 18, Color(0.6, 0.95, 0.7)))
	head.add_child(_lbl_nowrap("Grade: %s" % grade, 18, Color(0.6, 0.95, 0.7)))
	head.add_child(_lbl_nowrap("Jumps: %d     Days: %d" % [int(info.get("jumps", 0)), int(info.get("days", 0))], 18, Color(0.8, 0.9, 1.0)))
	_content.add_child(head)
	_content.add_child(HSeparator.new())

	if not won:
		_field("Mission status", str(info.get("reason", "The mission ended before all objectives were met.")), Color(1.0, 0.7, 0.6))

	# objective & question
	_field("Mission objective", str(m.get("objective", "Explore the target and return scientific data.")))
	if str(m.get("question", "")) != "":
		_field("Scientific question", str(m.get("question", "")), Color(1.0, 0.86, 0.4))

	# instruments used
	var scans: Array = info.get("scans", [])
	var instr_counts: Dictionary = {}
	var quality_total := 0.0
	var quality_n := 0
	for s in scans:
		quality_total += float(s.get("quality", 0.0))
		quality_n += 1
		for iid in s.get("used", []):
			instr_counts[iid] = int(instr_counts.get(iid, 0)) + 1
	var instr_defs: Dictionary = Education.instruments()
	var instr_txt := "No instrument data was collected this mission."
	if not instr_counts.is_empty():
		var parts: Array = []
		for iid in instr_counts:
			parts.append("%s x%d" % [str(instr_defs.get(iid, {}).get("name", iid)), int(instr_counts[iid])])
		instr_txt = ", ".join(parts)
	_content.add_child(_lbl("Instruments used", 14, Color(0.55, 0.85, 1.0)))
	_content.add_child(_lbl(instr_txt, 15))
	# instrument usage bars
	if not instr_counts.is_empty():
		var maxc := 1
		for iid in instr_counts:
			maxc = maxi(maxc, int(instr_counts[iid]))
		for iid in instr_counts:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var nm := Label.new()
			nm.text = str(instr_defs.get(iid, {}).get("name", iid))
			nm.custom_minimum_size = Vector2(220, 0)
			nm.add_theme_font_size_override("font_size", 13)
			row.add_child(nm)
			var bar := ProgressBar.new()
			bar.min_value = 0
			bar.max_value = maxc
			bar.value = int(instr_counts[iid])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(300, 12)
			bar.modulate = Color(0.5, 0.9, 1.0)
			row.add_child(bar)
			_content.add_child(row)

	# data collected
	_field("Data collected", "%d observation set(s) logged across %d jump(s)." % [scans.size(), int(info.get("jumps", 0))])

	# data quality
	var qtext := "No measurements were logged, so data quality cannot be assessed."
	if quality_n > 0:
		var avg := quality_total / float(quality_n)
		var word := "good" if avg >= 0.75 else ("fair" if avg >= 0.5 else "poor")
		qtext = "Average data quality: %s (%.0f%%). More power to the instruments and crew support improve quality." % [word, avg * 100.0]
	_field("Data quality", qtext)

	# findings
	if str(m.get("finding", "")) != "":
		_field("Main finding", str(m.get("finding", "")), Color(0.7, 1.0, 0.8))
	_field("What the evidence supports", "The measurements are consistent with the main finding above. This is what the mission can safely report.")
	_field("What cannot yet be concluded", str(m.get("limitations", "A few measurements cannot describe a whole world.")), Color(1.0, 0.85, 0.6))
	if str(m.get("next_question", "")) != "":
		_field("Suggested next research question", str(m.get("next_question", "")), Color(1.0, 0.86, 0.4))

	# --- samples brought home -------------------------------------------------
	var samples: Array = info.get("samples", [])
	_content.add_child(HSeparator.new())
	_content.add_child(_lbl("SAMPLES BROUGHT HOME", 24, UiTheme.GOLD))
	if samples.is_empty():
		_content.add_child(_lbl("No surface samples were collected this mission. Next time, land on the Moon or Mars and press E at each glowing spot to pick one up.", 16, UiTheme.TEXT_DIM))
	else:
		_content.add_child(_lbl("%d sample(s) were stored safely for scientists on Earth:" % samples.size(), 16, UiTheme.TEXT))
		for s in samples:
			_content.add_child(_lbl("- %s  (%s)" % [str(s.get("name", "")), _body_name(str(s.get("body", "")))], 16, UiTheme.GOLD))
			_content.add_child(_lbl("    %s" % str(s.get("fact", "")), 15, Color(0.85, 0.95, 1.0)))

	# --- recommendations ------------------------------------------------------
	_content.add_child(HSeparator.new())
	_content.add_child(_lbl("MISSION CONTROL'S ADVICE FOR NEXT TIME", 24, UiTheme.PINK))
	_content.add_child(_lbl("Friendly advice built from how your mission actually went:", 16, UiTheme.TEXT_DIM))
	for tip in _recommendations(info):
		_content.add_child(_lbl("- " + tip, 16, UiTheme.TEXT))

	# --- real-life reflection -------------------------------------------------
	_content.add_child(HSeparator.new())
	_content.add_child(_lbl("HOW REAL MISSIONS DO THIS", 24, UiTheme.CYAN))
	_content.add_child(_lbl(_real_reflection(mid), 16, Color(0.82, 0.96, 1.0)))
	_content.add_child(_lbl(_real_reflection_2(mid), 16, Color(0.82, 0.96, 1.0)))
	_content.add_child(_lbl("Why it matters: real space agencies spend years and huge budgets on the same choices you just made - what to carry, how much power to spend, and what to bring home.", 15, UiTheme.TEXT_DIM))

	# --- learning value -------------------------------------------------------
	_content.add_child(HSeparator.new())
	_content.add_child(_lbl("WHAT THIS MISSION TEACHES", 24, UiTheme.GOOD))
	for v in _value_points(mid):
		_content.add_child(_lbl("- " + v, 16, UiTheme.TEXT))

	# --- score breakdown ------------------------------------------------------
	_content.add_child(HSeparator.new())
	_content.add_child(_lbl("HOW YOUR SCORE WAS BUILT", 22, UiTheme.CYAN))
	_content.add_child(_lbl(_score_explanation(info, score, grade, stars), 16, UiTheme.TEXT))

	_content.add_child(HSeparator.new())
	_content.add_child(_lbl("Values labelled fictional in the game are gameplay values, not real measurements. Educational figures are labelled real or simplified and come from the bundled sources.", 15, UiTheme.TEXT_DIM))

	var btnrow := HBoxContainer.new()
	btnrow.alignment = BoxContainer.ALIGNMENT_END
	btnrow.add_child(_claim_button())
	_content.add_child(btnrow)


func _body_name(b: String) -> String:
	match b:
		"planet_moon":
			return "Moon"
		"planet_mars":
			return "Mars"
		"planet_earth":
			return "Earth"
	return b.replace("planet_", "").capitalize()


# Advice for the next mission, built from how THIS run actually went.
func _recommendations(info: Dictionary) -> Array:
	var res: Dictionary = info.get("resources", {})
	var out: Array = []
	if float(res.get("oxygen", 100.0)) < 55.0:
		out.append("Add power to the Air Room so the oxygen lasts the whole trip.")
	if float(res.get("food", 100.0)) < 55.0:
		out.append("Visit the Space Garden to grow snacks before the shelf runs empty.")
	if float(res.get("water", 100.0)) < 55.0:
		out.append("Keep the Space Garden powered: it slows how fast the crew uses water.")
	if float(res.get("fuel", 100.0)) < 45.0:
		out.append("Plan shorter routes, or stop at a friendly depot to refuel.")
	if float(res.get("hull", 100.0)) < 65.0:
		out.append("Power the Fix-It Room and carry a spare part in case the hull is hit.")
	if float(res.get("morale", 100.0)) < 55.0:
		out.append("Answer the radio calls from home and use the Med Bay to keep the crew cheerful.")
	if float(res.get("power", 100.0)) < 45.0:
		out.append("Keep about a third of the reactor spare as a safety margin, like real missions do.")
	var scan_n: int = (info.get("scans", []) as Array).size()
	if scan_n < 2:
		out.append("Power the Science Lab and scan more worlds - the data is what makes a mission valuable.")
	var sample_n: int = (info.get("samples", []) as Array).size()
	if sample_n < 3:
		out.append("Land on the Moon or Mars and collect all three glowing samples for bonus science.")
	if int(info.get("gates_seen", 0)) > int(info.get("gates_solved", 0)):
		out.append("Take your time at the Puzzle Gates - reading the riddle carefully earns more science.")
	if int(info.get("lifelines_used", 0)) > 0:
		out.append("You used %d care package(s). Watching the bars early means fewer surprises." % int(info.get("lifelines_used", 0)))
	if out.is_empty():
		out.append("Outstanding! You managed every resource well and still returned real science. Try a harder route next.")
	out.append("Remember: reaching the destination is only half the mission - the science you bring home is the other half.")
	return out


func _real_reflection(mid: String) -> String:
	match mid:
		"earth_moon":
			return "NASA's Artemis programme is working to send humans back to the Moon, and Egypt's own space agency (EgSA) builds satellites that study Earth and space. Your mission found what they found: a world with no air swings from scorching days to freezing nights."
		"moon_mars", "earth_mars":
			return "NASA's Perseverance rover is collecting Mars samples to bring home, and the MAVEN orbiter studies how Mars lost its air. Your readings of thin air and cold ground match what those real missions found."
		"moon_round":
			return "Apollo 11 brought 21.5 kg of Moon rock home in 1969, and scientists still study those samples today. Bringing samples back is hard and costly - which is exactly why they are so valuable."
	return "Real space agencies plan every gram of mass, watt of power and drop of fuel - the same trade-offs you made on this mission."


func _real_reflection_2(mid: String) -> String:
	match mid:
		"earth_moon":
			return "Real Moon missions carry thermal sensors for the same reason: with no air to hold heat, Apollo astronauts needed suits that coped with both extremes."
		"moon_mars", "earth_mars":
			return "Real Mars missions carry thermal and pressure sensors for the same reason: the thin carbon-dioxide air barely warms the surface, yet dust storms can still grow planet-wide."
		"moon_round":
			return "Real sample-return missions, like Japan's Hayabusa and NASA's planned Mars Sample Return, are among the hardest missions ever attempted."
	return "Ground stations such as NASA's Deep Space Network listen for spacecraft around the clock - your radio calls were a simplified version of that."


func _value_points(mid: String) -> Array:
	var out: Array = [
		"Every mission starts with a question, and the answer comes from data - not from luck.",
		"Mass, power, fuel and data are all limited, so engineers trade one against another.",
		"Science is teamwork: a pilot, an engineer, a scientist and a medic each keep the mission alive.",
	]
	var m: Dictionary = Education.mission(mid)
	var shown := 0
	for iid in m.get("instruments", []):
		if shown >= 3:
			break
		var d: Dictionary = Education.instrument(str(iid))
		if not d.is_empty():
			out.append("%s measures %s (in %s)." % [str(d.get("name", "")), str(d.get("measures", "")), str(d.get("unit", ""))])
			shown += 1
	return out


func _score_explanation(info: Dictionary, score: int, grade: String, stars: int) -> String:
	var res: Dictionary = info.get("resources", {})
	var avg := 0.0
	if not res.is_empty():
		var total := 0.0
		for k in GameData.RES_ORDER:
			total += float(res.get(k, 0.0))
		avg = total / float(GameData.RES_ORDER.size())
	var sci := int(info.get("science", 0))
	return "Resources kept averaged %.0f%%, and you returned %d science. Half of your score comes from how well you looked after the ship and crew, and the other half from the science you brought home. That gives %d/100, grade %s and %d of 3 stars." % [avg, sci, score, grade, stars]


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _stars_line(n: int) -> String:
	var glyphs := ""
	for i in 3:
		glyphs += "★ " if i < n else "☆ "
	return "%s   %d of 3 stars" % [glyphs.strip_edges(), n]


func _claim_button() -> Button:
	var b := Button.new()
	b.text = "Claim"
	b.accessibility_name = "Claim results and return to mission select"
	b.tooltip_text = "Save these results and pick another mission"
	b.custom_minimum_size = Vector2(220, 52)
	UiTheme.style_button(b, "gold")
	b.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	return b