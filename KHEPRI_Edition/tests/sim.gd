extends SceneTree
# Headless balance + soft-lock simulation of GameState (no UI).
func _init() -> void:
	randomize()
	for band in ["junior", "middle"]:
		GameData.band = band
		for m in GameData.MISSIONS:
			var wins := 0
			var stuck := 0
			var jumps_total := 0
			var lifelines_used := 0
			var runs := 300
			for r in range(runs):
				var gs := GameState.new()
				gs.new_run(m)
				# A casual player: a bit of power sense, picks random choices
				gs.add_power("sensors"); gs.add_power("repair")
				var guard := 0
				while not gs.game_over and guard < 200:
					guard += 1
					if not gs.can_afford_jump():
						if not gs.rescue_fuel():
							break
					var opts := gs.travel_options()
					if opts.is_empty():
						break
					var tgt: int = opts[randi() % opts.size()]
					gs.at_node = tgt
					gs.apply_fx({"fuel": -gs.jump_cost()})
					gs.advance_beacon()
					if gs.game_over: break
					var b: Dictionary = gs.beacons[tgt]
					match str(b["type"]):
						"event":
							var e: Dictionary = GameData.EVENTS[randi() % GameData.EVENTS.size()]
							var ch: Dictionary = e["choices"][randi() % e["choices"].size()]
							gs.apply_fx(ch["fx"])
						"hazard":
							if randf() < 0.6: gs.apply_fx({"science": 10, "morale": 6, "parts": 1, "ordnance": 1})
							else: gs.apply_fx({"science": 3, "morale": 1})
						"store":
							gs.apply_fx({"fuel": 22, "food": 12, "water": 12, "power": 12})
						"planet":
							gs.apply_fx({"science": 8})
					if randf() < 0.45:
						var c: Dictionary = GameData.CALLS[randi() % GameData.CALLS.size()]
						gs.apply_fx(c["choices"][randi() % 2]["fx"])
					# player recharges a bit via bio/morale choices occasionally
					if gs.is_final_node() and not gs.game_over:
						break
				if gs.is_final_node() and not gs.game_over:
					wins += 1
				elif guard >= 200:
					stuck += 1
				jumps_total += gs.jumps
				lifelines_used += GameData.LIFELINES - gs.lifelines
			print("%-7s %-24s win %3d%%  stuck %d  avg jumps %.1f  avg lifelines used %.2f" % [band, m["name"], int(100.0 * wins / runs), stuck, float(jumps_total) / runs, float(lifelines_used) / runs])
	quit()
