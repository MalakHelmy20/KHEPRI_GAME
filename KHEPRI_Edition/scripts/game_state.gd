class_name GameState
extends RefCounted

# =============================================================================
# Runtime state + rules for one Moon Run. Pure logic, no UI. The controller
# (game.gd) owns one of these and drives the views from it.
# =============================================================================

var mission: Dictionary = {}
var resources: Dictionary = {}     # res id -> float 0..100
var counters: Dictionary = {}      # counter id -> int
var science: int = 0

# Educational: log of scientific observations made during the mission.
var scans: Array = []              # each: {body, quality, used:[instr ids]}
var instruments_used: Dictionary = {}   # instr id -> count
var samples: Array = []            # each: {body, name, fact} - surface samples

# Systems: power level assigned to each id, plus damage integrity 0..1
var sys_power: Dictionary = {}
var sys_integrity: Dictionary = {}

# Crew: array of {name, role, room, hp}
var crew: Array = []

# Sector map
var beacons: Array = []            # {layer, type, pos, next:[...], visited, scanned}
var at_node: int = 0
var node_log: Dictionary = {}      # node index -> true when resolved

# Progress / meta
var jumps: int = 0
var day: int = 1
var reactor: int = 0
var game_over: bool = false
var won: bool = false
var end_reason: String = ""
var return_trip: bool = false
var turn_phase: String = "space"   # "return" when heading back
# Kids edition: gentle safety net instead of instant game-over.
var lifelines: int = 3
var notices: Array = []            # friendly messages for the controller to show
var gates_solved: int = 0
var gates_seen: int = 0

# ---------------------------------------------------------------------------
func new_run(d: Dictionary) -> void:
	mission = d.duplicate(true)
	resources = {"power": 85.0, "oxygen": 95.0, "water": 90.0, "food": 90.0,
		"fuel": float(d.get("fuel_start", 90.0)), "hull": 100.0, "morale": 90.0}
	counters = {}
	for k in GameData.COUNTER_ORDER:
		counters[k] = int(GameData.COUNTER_META[k]["start"])
	science = 0
	scans = []
	instruments_used = {}
	samples = []
	sys_power = {}
	sys_integrity = {}
	for s in GameData.SYSTEMS:
		sys_power[s["id"]] = int(s["start"])
		sys_integrity[s["id"]] = 1.0
	reactor = GameData.REACTOR_START
	crew = []
	var pool := GameData.CREW_NAMES.duplicate()
	pool.shuffle()
	for i in range(4):
		crew.append({"name": pool[i], "role": GameData.CREW_ROLES[i],
			"room": ["piloting", "engines", "oxygen", "bio"][i], "hp": 100.0})
	jumps = 0
	day = 1
	game_over = false
	won = false
	end_reason = ""
	return_trip = bool(d.get("return", false))
	turn_phase = "space"
	lifelines = GameData.LIFELINES
	notices = []
	gates_solved = 0
	gates_seen = 0
	_generate_sector()

# --- Sector generation ------------------------------------------------------
func _generate_sector() -> void:
	beacons = []
	var layers := int(mission.get("beacons", 8))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Build a 2D grid of nodes: layer -> list of node indices.
	var layer_nodes: Array = []
	for l in range(layers):
		var count := 2
		if l == 0 or l == layers - 1:
			count = 1
		else:
			count = rng.randi_range(1, 3)
		var ids: Array = []
		for c in range(count):
			var t := _pick_beacon_type(l, layers, rng)
			var nx := 0.0
			if count > 1:
				nx = float(c) / float(count - 1)
			else:
				nx = 0.5
			beacons.append({
				"layer": l, "type": t, "pos": Vector2(nx, 0.0),
				"next": [], "visited": false, "done": false,
				"name": _cute_name(rng),
			})
			ids.append(beacons.size() - 1)
		layer_nodes.append(ids)
	# Assign vertical positions spread across each layer's nodes.
	for l in range(layers):
		var ids: Array = layer_nodes[l]
		var n: int = ids.size()
		for i in range(n):
			beacons[ids[i]]["pos"].y = float(i + 1) / float(n + 1)
	# Link each layer to the next (1-2 links each way, keeping the graph connected).
	for l in range(layers - 1):
		var cur: Array = layer_nodes[l]
		var nxt: Array = layer_nodes[l + 1]
		for i in range(cur.size()):
			var target := int(round(float(i) / maxf(1.0, float(cur.size() - 1)) * float(nxt.size() - 1)))
			beacons[cur[i]]["next"].append(nxt[target])
		for j in range(nxt.size()):
			# make sure every next node is reachable from someone
			var reachable := false
			for i in cur.size():
				if nxt[j] in beacons[cur[i]]["next"]:
					reachable = true
					break
			if not reachable:
				beacons[cur[rng.randi_range(0, cur.size() - 1)]]["next"].append(nxt[j])
	at_node = layer_nodes[0][0]
	beacons[at_node]["visited"] = true

func _cute_name(rng: RandomNumberGenerator) -> String:
	var names: Array = GameData.PLANET_NAMES
	return str(names[rng.randi_range(0, names.size() - 1)])

func _pick_beacon_type(l: int, layers: int, rng: RandomNumberGenerator) -> String:
	if l == layers - 1:
		return "outpost"
	# Weighted pick. "outpost" only ever appears as the final node.
	var total := 0
	for k in GameData.BEACON_TYPES:
		if k == "outpost":
			continue
		total += int(GameData.BEACON_TYPES[k]["weight"])
	var roll := rng.randi_range(0, total - 1)
	for k in GameData.BEACON_TYPES:
		if k == "outpost":
			continue
		roll -= int(GameData.BEACON_TYPES[k]["weight"])
		if roll < 0:
			return k
	return "event"

func layer_count() -> int:
	var m := 0
	for b in beacons:
		m = maxi(m, int(b["layer"]))
	return m + 1

func is_final_node() -> bool:
	return beacons[at_node]["layer"] >= layer_count() - 1

func travel_options() -> Array:
	var out: Array = []
	for n in beacons[at_node]["next"]:
		out.append(n)
	return out

# ---------------------------------------------------------------------------
# System helpers
# ---------------------------------------------------------------------------
func sys_level(id: String) -> int:
	return int(sys_power.get(id, 0))

func sys_online(id: String) -> bool:
	return sys_level(id) > 0 and float(sys_integrity.get(id, 1.0)) > 0.05

# Effective output: power level scaled by damage, plus a crew bonus.
func sys_effective(id: String) -> float:
	if not sys_online(id):
		return 0.0
	var lvl := float(sys_level(id))
	var integ := float(sys_integrity.get(id, 1.0))
	var crew_bonus := 1.0 if crew_in(id) >= 1 else 0.0
	var out := (lvl + crew_bonus * 0.5) * integ
	# A dead battery really does cut system output, not only the HUD bar.
	if float(resources.get("power", 100.0)) <= 1.0:
		out *= 0.5
	return out

func crew_in(id: String) -> int:
	var n := 0
	for c in crew:
		if c["room"] == id and float(c["hp"]) > 25.0:
			n += 1
	return n

func power_used() -> int:
	var t := 0
	for k in sys_power:
		t += int(sys_power[k])
	return t

func power_spare() -> int:
	return reactor - power_used()

func power_spare_pct() -> float:
	if reactor <= 0:
		return 0.0
	return float(power_spare()) / float(reactor)

func can_power(id: String) -> bool:
	var s := _sys_def(id)
	if sys_level(id) >= int(s["max"]):
		return false
	return power_spare() > 0

func add_power(id: String) -> bool:
	if can_power(id):
		sys_power[id] = sys_level(id) + 1
		return true
	return false

func remove_power(id: String) -> bool:
	if sys_level(id) > 0:
		sys_power[id] = sys_level(id) - 1
		return true
	return false


func damage_system(id: String, amount: float) -> void:
	if not sys_integrity.has(id):
		return
	sys_integrity[id] = clampf(float(sys_integrity[id]) - amount, 0.0, 1.0)


# Powered Repair Bay mends the worst system. A spare part finishes a real patch.
func repair_tick() -> String:
	if not sys_online("repair"):
		return ""
	var id := _worst_system()
	if id == "" or float(sys_integrity[id]) > 0.97:
		return ""
	var before := float(sys_integrity[id])
	var gain := 0.08 + sys_effective("repair") * 0.04
	var spent := false
	if before < 0.82 and int(counters.get("parts", 0)) > 0:
		counters["parts"] = int(counters["parts"]) - 1
		gain += 0.22
		spent = true
	sys_integrity[id] = clampf(before + gain, 0.0, 1.0)
	if spent:
		return "Repair Bay patched %s using 1 spare part." % _sys_name(id)
	if before < 0.9:
		return "Repair Bay is working on %s. A spare part would finish the job faster." % _sys_name(id)
	return ""


func _worst_system() -> String:
	var id := ""
	var worst := 1.0
	for k in sys_integrity:
		var v := float(sys_integrity[k])
		if v < worst:
			worst = v
			id = str(k)
	return id


func _random_system() -> String:
	if GameData.SYSTEMS.is_empty():
		return ""
	return str(GameData.SYSTEMS[randi() % GameData.SYSTEMS.size()]["id"])


func _sys_name(id: String) -> String:
	for s in GameData.SYSTEMS:
		if s["id"] == id:
			return str(s["name"])
	return id

func _sys_def(id: String) -> Dictionary:
	for s in GameData.SYSTEMS:
		if s["id"] == id:
			return s
	return {}

# ---------------------------------------------------------------------------
# Derived combat / navigation stats
# ---------------------------------------------------------------------------
func evasion() -> float:
	return clampf(0.05 + sys_effective("engines") * 0.05 + sys_effective("piloting") * 0.05, 0.0, 0.60)

func shield_strength() -> float:
	return sys_effective("shields") * 8.0

func jump_cost() -> float:
	return maxf(3.0, 7.0 - sys_effective("engines") * 0.9)

func signal_db() -> float:
	return 1.0 + sys_effective("comms") * 2.0

func signal_label() -> String:
	var db := signal_db()
	var st := "LOST"
	if db >= 6.0:
		st = "STRONG"
	elif db >= 3.0:
		st = "OK"
	elif db >= 1.5:
		st = "WEAK"
	return "%s  (%.1f dB margin)" % [st, db]

# ---------------------------------------------------------------------------
# Applying effects from events / calls / actions
# ---------------------------------------------------------------------------
func apply_fx(fx: Dictionary, soften: bool = true) -> void:
	for k in fx:
		var v := float(fx[k])
		# Kids edition: ouch-effects are softer (junior band most of all).
		if soften and v < 0.0 and k != "science" and k != "fuel":
			v = v * GameData.soft()
		if k == "science":
			science = maxi(0, science + int(v))
		elif resources.has(k):
			resources[k] = clampf(float(resources[k]) + v, 0.0, 100.0)
		elif counters.has(k):
			counters[k] = clampi(int(counters[k]) + int(v), 0, int(GameData.COUNTER_META[k]["max"]))
		elif k == "hull":
			resources["hull"] = clampf(float(resources["hull"]) + v, 0.0, 100.0)
	_check_end({})


# --- Educational data tracking ----------------------------------------------
func record_scan(body: String, quality: float, used: Array) -> void:
	scans.append({"body": body, "quality": quality, "used": used.duplicate()})
	for iid in used:
		instruments_used[iid] = int(instruments_used.get(iid, 0)) + 1


func scan_count() -> int:
	return scans.size()


# A physical sample picked up on the Moon or Mars surface.
func record_sample(body: String, sample: Dictionary) -> void:
	samples.append({"body": body, "name": str(sample.get("name", "Sample")),
		"fact": str(sample.get("fact", ""))})

# ---------------------------------------------------------------------------
# Per-jump tick: consumption, recharge, crew health
# ---------------------------------------------------------------------------
func advance_beacon() -> Dictionary:
	var diff := float(mission.get("difficulty", 1.0)) * GameData.drain()
	var report := {"warnings": []}
	jumps += 1
	day += 1

	# Battery: solar recharge minus draw from running systems.
	var draw := float(power_used()) * 0.5 * diff
	resources["power"] = clampf(float(resources["power"]) + 3.0 - draw, 0.0, 100.0)

	# Oxygen: scrubbers slow the loss.
	var o2_loss := maxf(1.2, 5.0 - sys_effective("oxygen") * 1.1) * diff
	resources["oxygen"] = clampf(float(resources["oxygen"]) - o2_loss, 0.0, 100.0)

	# Water: recycler (bio) slows loss.
	var h2o_loss := maxf(0.8, 3.2 - sys_effective("bio") * 0.45) * diff
	resources["water"] = clampf(float(resources["water"]) - h2o_loss, 0.0, 100.0)

	# Food: bio bay produces, crew eats.
	var food_loss := maxf(1.0, 4.2 - sys_effective("bio") * 1.3) * diff
	resources["food"] = clampf(float(resources["food"]) - food_loss, 0.0, 100.0)

	# Morale drifts down, medbay steadies it.
	resources["morale"] = clampf(float(resources["morale"]) - (0.8 - sys_effective("medbay") * 0.3) * diff, 0.0, 100.0)

	# A hurt hull stresses a random system. The Repair Bay answers on the same jump.
	if float(resources["hull"]) < 40.0 and randf() < 0.4:
		var victim := _random_system()
		damage_system(victim, 0.14)
		report["warnings"].append("%s was stressed by the damaged hull." % _sys_name(victim))

	var fixed := repair_tick()
	if fixed != "":
		report["warnings"].append(fixed)

	# Brownout: with a dead battery, systems run at half strength.
	if float(resources["power"]) <= 1.0:
		report["warnings"].append("BROWN-OUT: battery empty, systems running at half power.")

	# Crew health follows life support.
	var strain := 0.0
	if float(resources["oxygen"]) < 30.0:
		strain += 4.0
	if float(resources["water"]) < 25.0:
		strain += 4.0
	if float(resources["food"]) < 25.0:
		strain += 4.0
	var heal := sys_effective("medbay") * 3.0
	for c in crew:
		c["hp"] = clampf(float(c["hp"]) - strain + heal + 2.0, 0.0, 100.0)

	_check_end(report)
	return report

func _check_end(_report: Dictionary) -> void:
	if game_over:
		return
	for k in GameData.FATAL:
		if float(resources[k]) <= 0.0:
			if lifelines > 0:
				lifelines -= 1
				resources[k] = 40.0
				notices.append(_care_text(k))
				continue
			game_over = true
			won = false
			end_reason = _loss_text(k)
			return
	if float(resources["fuel"]) <= 0.0 and not is_final_node():
		if not rescue_fuel():
			return

# Called when the tank is too empty for the next jump. Uses a lifeline (tow truck),
# or ends the mission gently if none are left. Returns true if the ship can go on.
func rescue_fuel() -> bool:
	if lifelines > 0:
		lifelines -= 1
		resources["fuel"] = maxf(float(resources["fuel"]), 32.0)
		notices.append("A friendly space tow truck zooms by and tops up your fuel tank! (Care packages left: %d)" % lifelines)
		return true
	game_over = true
	won = false
	end_reason = "The tank ran dry and Mission Control is sending a tow truck. Every explorer needs practice - try a new route!"
	return false

func can_afford_jump() -> bool:
	return float(resources["fuel"]) >= jump_cost()

func _care_text(k: String) -> String:
	match k:
		"oxygen": return "Mission Control beams up a care package: fresh air tanks! (Care packages left: %d)" % lifelines
		"water":  return "Mission Control beams up a care package: sparkling water! (Care packages left: %d)" % lifelines
		"food":   return "Mission Control beams up a care package: yummy snacks! (Care packages left: %d)" % lifelines
		"hull":   return "Mission Control beams up a care package: shiny hull patches! (Care packages left: %d)" % lifelines
		"morale": return "Mission Control sends a surprise cheer-up video from Earth! (Care packages left: %d)" % lifelines
	return "Mission Control sends a care package! (Care packages left: %d)" % lifelines

func _loss_text(k: String) -> String:
	var tail := " Mission Control sends a rescue ship. Great try, explorer - let's fly again!"
	match k:
		"oxygen": return "The air tanks ran low." + tail
		"water":  return "The water tanks ran low." + tail
		"food":   return "The snack shelf ran empty." + tail
		"hull":   return "The ship needs a big repair." + tail
		"morale": return "The crew needs a long rest and a cheer-up party." + tail
	return "Mission paused." + tail

# ---------------------------------------------------------------------------
# Scoring (User segment)
# ---------------------------------------------------------------------------
func mission_score() -> int:
	var total := 0.0
	for k in GameData.RES_ORDER:
		total += float(resources[k])
	var avg := total / float(GameData.RES_ORDER.size())
	# Science from the User segment is the headline number.
	var score := int(avg * 0.55 + clampf(float(science) * 0.9, 0.0, 45.0))
	return clampi(score, 0, 100)

func cml_tier(score: int) -> Dictionary:
	var tier: Dictionary = GameData.CML[0]
	for t in GameData.CML:
		if score >= int(t["score"]):
			tier = t
	return tier

func ready_check() -> float:
	# Fraction of "green" indicators: systems healthy & powered, resources ok.
	var total := 0
	var green := 0
	for s in GameData.SYSTEMS:
		total += 1
		if sys_online(s["id"]) and float(sys_integrity[s["id"]]) > 0.5:
			green += 1
	for k in GameData.RES_ORDER:
		total += 1
		if float(resources[k]) >= 50.0:
			green += 1
	return float(green) / float(total)