extends Node

# Unit checks for the kids-edition additions: friendly theme, walkable ship
# interior, and the Moon/Mars surface sample collection. Run with run_tests.


func test_theme_card_styles() -> void:
	assert(UiTheme.card(UiTheme.CYAN) is StyleBoxFlat)
	assert(UiTheme.panel(UiTheme.GOLD) is StyleBoxFlat)


func test_age_band_removed_but_logic_intact() -> void:
	# The explorer-level buttons are gone, but the content pool must still work.
	assert(GameData.quiz_pool().size() > 0)


func test_interior_has_all_stations() -> void:
	assert(ShipInterior.STATIONS.size() == 10)
	assert(ShipInterior.PRETTY.size() == 10)


func test_surface_samples_present() -> void:
	assert(SurfaceScene.SAMPLES["planet_moon"].size() == 3)
	assert(SurfaceScene.SAMPLES["planet_mars"].size() == 3)
	for s in SurfaceScene.SAMPLES["planet_moon"]:
		assert(str(s["name"]) != "")
		assert(str(s["fact"]).length() > 20)


func test_report_advice_and_value() -> void:
	var r := ScienceReport.new()
	var tips: Array = r._recommendations({
		"resources": {"oxygen": 20.0, "fuel": 30.0, "hull": 40.0},
		"scans": [], "samples": [], "gates_seen": 2, "gates_solved": 1, "lifelines_used": 1})
	assert(tips.size() >= 3, "advice should have several points")
	assert(" ".join(tips).contains("science you bring home"))
	var values: Array = r._value_points("earth_moon")
	assert(values.size() >= 3)
	assert(r._real_reflection("earth_moon").length() > 40)
	assert(r._score_explanation({"resources": {}, "science": 10}, 55, "B", 2).length() > 20)
	r.free()


func test_report_row_labels_never_wrap() -> void:
	# Regression: the Science/Score/Grade/Days row labels must not wrap, or they
	# stack one character per line and the numbers look like gibberish.
	var r := ScienceReport.new()
	add_child(r)
	r.open({
		"won": true, "score": 62, "grade": "B", "stars": 2, "rank": "Scientist",
		"science": 24, "jumps": 2, "days": 3, "mission_id": "earth_moon",
		"mission_name": "Earth > Moon Outpost", "scans": [], "samples": [],
		"resources": {"power": 60.0, "oxygen": 40.0},
		"gates_seen": 2, "gates_solved": 1, "lifelines_used": 1,
		"stage_name": "TRADE STUDIES", "stage_question": "Which design is better?",
	})
	var rows := 0
	var paragraphs := 0
	for n in r.find_children("*", "Label", true, false):
		var lab := n as Label
		if lab.text.begins_with("Score") or lab.text.begins_with("Grade") \
				or lab.text.begins_with("Days") or lab.text.begins_with("Science returned") \
				or lab.text.begins_with("Science  "):
			rows += 1
			assert(lab.autowrap_mode == TextServer.AUTOWRAP_OFF, "row label must not wrap: " + lab.text)
		elif lab.text.length() > 80:
			paragraphs += 1
			assert(lab.autowrap_mode != TextServer.AUTOWRAP_OFF, "long paragraph should wrap")
	r.queue_free()
	assert(rows >= 4, "expected the score row labels, found %d" % rows)
	assert(paragraphs >= 1, "expected at least one wrapping paragraph")


func test_samples_are_recorded() -> void:
	var gs := GameState.new()
	gs.new_run(GameData.MISSIONS[0])
	gs.record_sample("planet_moon", {"name": "Moon dust", "fact": "Fine grey regolith."})
	assert(gs.samples.size() == 1)
	assert(str(gs.samples[0]["name"]) == "Moon dust")


func test_game_state_ready_for_surface() -> void:
	# A fresh run must be able to accept surface science without errors.
	var gs := GameState.new()
	gs.new_run(GameData.MISSIONS[0])
	var before := gs.science
	gs.apply_fx({"science": 8})
	assert(gs.science == before + 8)