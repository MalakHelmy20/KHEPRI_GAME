class_name GameData
extends RefCounted

# =============================================================================
# MOON RUN 2  —  Egypt x NASA, FTL-style roguelike
# All static content lives here: resources, systems, CML tiers, mission
# segments, missions, beacon types, random events (with a 5x5 risk matrix),
# Earth calls (Egyptian legends + NASA bureaucracy), fun facts and foods.
# =============================================================================

# --- Ship resources (bars, 0..100) ------------------------------------------
const RES_META := {
	"power":  {"name": "Power",  "short": "PWR",  "color": Color(1.00, 0.85, 0.25)},
	"oxygen": {"name": "Oxygen", "short": "O2",   "color": Color(0.45, 0.85, 1.00)},
	"water":  {"name": "Water",  "short": "H2O",  "color": Color(0.30, 0.55, 1.00)},
	"food":   {"name": "Food",   "short": "FOOD", "color": Color(0.55, 0.90, 0.35)},
	"fuel":   {"name": "Fuel",   "short": "FUEL", "color": Color(1.00, 0.60, 0.20)},
	"hull":   {"name": "Hull",   "short": "HULL", "color": Color(0.80, 0.82, 0.88)},
	"morale": {"name": "Morale", "short": "MRL",  "color": Color(1.00, 0.45, 0.65)},
}
const RES_ORDER := ["power", "oxygen", "water", "food", "fuel", "hull", "morale"]

# If any of these hits zero, Mission Control sends a care package (a "lifeline").
# Only when the lifelines run out does the mission end - gently, with a retry.
const FATAL := ["oxygen", "water", "food", "hull", "morale"]

# --- Counters (integer stockpiles) ------------------------------------------
const COUNTER_META := {
	"parts":    {"name": "Spare Parts", "short": "PRTS", "start": 6, "max": 24, "color": Color(0.70, 0.75, 0.85)},
	"ordnance": {"name": "Hint Crystals", "short": "HINT", "start": 3, "max": 12, "color": Color(0.75, 0.55, 1.00)},
}
const COUNTER_ORDER := ["parts", "ordnance"]

# --- Ship systems (FTL power grid) ------------------------------------------
# Each system holds 0..max power. Crew stationed in the room adds a bonus level.
const SYSTEMS := [
	{"id": "piloting", "name": "Piloting",        "max": 3, "start": 1, "icon": "P", "desc": "Cockpit. Boosts evasion and launch guidance."},
	{"id": "engines",  "name": "Engines",         "max": 5, "start": 1, "icon": "E", "desc": "Thrust and jump efficiency. Evasion + fuel saving."},
	{"id": "oxygen",   "name": "Oxygen Scrubbers", "max": 3, "start": 2, "icon": "O", "desc": "Recycles air. Keeps oxygen from draining."},
	{"id": "shields",  "name": "Shields",         "max": 4, "start": 1, "icon": "S", "desc": "Absorbs incoming fire before it reaches the hull."},
	{"id": "weapons",  "name": "Tractor Beam",    "max": 4, "start": 1, "icon": "T", "desc": "A friendly beam that grabs floating cargo and gives hints at Puzzle Gates."},
	{"id": "sensors",  "name": "Science Lab",     "max": 3, "start": 0, "icon": "L", "desc": "Scans planets and anomalies for science."},
	{"id": "comms",    "name": "Comms",           "max": 3, "start": 1, "icon": "C", "desc": "Signal margin (dB). Earth calls need a strong link."},
	{"id": "bio",      "name": "BioNutrients Bay", "max": 3, "start": 1, "icon": "B", "desc": "Grows yeast & yogurt. Powers the food mini-game."},
	{"id": "repair",   "name": "Repair Bay",      "max": 3, "start": 0, "icon": "R", "desc": "Fixes damaged systems with spare parts."},
	{"id": "medbay",   "name": "Medbay",          "max": 3, "start": 0, "icon": "M", "desc": "Heals injured crew and steadies morale."},
]
const REACTOR_START := 13   # total power units the reactor can distribute (used 8 -> ~38% spare)

# --- CML tiers (JPL Concept Maturity Levels) --------------------------------
const CML := [
	{"level": 1, "name": "Cocktail Napkin",      "score": 0,  "blurb": "A doodle on a napkin. It has a rocket on it. Sort of."},
	{"level": 2, "name": "Initial Feasibility",  "score": 25, "blurb": "The napkin is now in a PowerPoint."},
	{"level": 3, "name": "Trade Space",          "score": 45, "blurb": "You compare options and pretend it was math."},
	{"level": 4, "name": "Point Design",         "score": 62, "blurb": "A single chosen concept. Engineers stop crying."},
	{"level": 5, "name": "Baseline Concept",     "score": 78, "blurb": "Frozen design. Only the budget is unfrozen."},
	{"level": 6, "name": "PDR",                  "score": 90, "blurb": "Preliminary Design Review survived!"},
	{"level": 7, "name": "CDR",                  "score": 98, "blurb": "Critical Design Review. You are basically NASA now."},
]

# --- Mission segments (from the webinar's four pillars) ---------------------
const SEGMENTS := ["Launch", "Space", "Ground", "User"]

# --- Missions (routes) ------------------------------------------------------
const MISSIONS := [
	{
		"id": "earth_moon", "name": "Earth > Moon Outpost",
		"from": "planet_earth", "to": "planet_moon",
		"beacons": 7, "difficulty": 1.0, "fuel_start": 90.0,
		"blurb": "Deliver the first cargo to the lunar outpost. ~3 days. A warm-up.",
		"fact": "Fun fact: The Moon is about 384,400 km away. Apollo crews took roughly three days to get there.",
	},
	{
		"id": "moon_mars", "name": "Moon Outpost > Mars",
		"from": "planet_moon", "to": "planet_mars",
		"beacons": 11, "difficulty": 1.35, "fuel_start": 80.0,
		"blurb": "Refuel at the outpost and push to Mars. Long, lonely, hungry.",
		"fact": "Fun fact: Mars is 55-401 million km away depending on the year, so launch windows matter enormously.",
	},
	{
		"id": "earth_mars", "name": "Earth > Mars (Direct)",
		"from": "planet_earth", "to": "planet_mars",
		"beacons": 14, "difficulty": 1.7, "fuel_start": 100.0,
		"blurb": "Skip the outpost. Ballsy. Bring spare everything.",
		"fact": "Fun fact: Mars missions rely on the MAVEN and Mars Odyssey orbiters as communication relays.",
	},
	{
		"id": "moon_round", "name": "Moon and Back",
		"from": "planet_earth", "to": "planet_moon", "return": true,
		"beacons": 10, "difficulty": 1.2, "fuel_start": 95.0,
		"blurb": "Touch the Moon, grab samples, get everyone home. Two-way fuel budget.",
		"fact": "Fun fact: Apollo 13's loop-around shows how precious a return fuel budget really is.",
	},
]

# --- Crew pool --------------------------------------------------------------
const CREW_NAMES := ["Salma", "Youssef", "Nour", "Karim", "Habiba", "Ziad", "Farida", "Omar"]
const CREW_ROLES := ["Pilot", "Engineer", "Scientist", "Medic"]

# --- Beacon types (used to build the sector map) ----------------------------
const BEACON_TYPES := {
	"empty":     {"name": "Quiet Space",    "color": Color(0.60, 0.68, 0.90), "weight": 2},
	"event":     {"name": "Surprise!",      "color": Color(1.00, 0.80, 0.30), "weight": 6},
	"hazard":    {"name": "Puzzle Gate",    "color": Color(0.80, 0.55, 1.00), "weight": 4},
	"planet":    {"name": "Science Planet", "color": Color(0.40, 0.90, 0.95), "weight": 4},
	"store":     {"name": "Friendly Shop",  "color": Color(0.55, 0.95, 0.55), "weight": 3},
	"outpost":   {"name": "Outpost",        "color": Color(1.00, 0.90, 0.55), "weight": 1},
}

# --- Random events ----------------------------------------------------------
# likelihood x impact feed the 5x5 risk matrix (1..5 each).
const EVENTS := [
	{
		"title": "SOLAR FLARE WARNING",
		"text": "The Sun just sneezed in your direction. Radiation alarms are flashing across the hull.",
		"fact": "Fun fact: Solar flares disturb radio and satellites. Long-duration crews shelter in a shielded 'storm cellar' to wait them out.",
		"likelihood": 4, "impact": 3,
		"choices": [
			{"label": "Shelter the crew (fuel -6, power -5)", "fx": {"fuel": -6, "power": -5}, "msg": "You hide in the storm cellar. Everyone sits very close together.", "risk": 0},
			{"label": "Ride it out (hull -16, morale -6)", "fx": {"hull": -16, "morale": -6}, "msg": "Brave. The ship's skin is now lightly toasted.", "risk": 3},
		],
	},
	{
		"title": "MICROMETEOROID HIT",
		"text": "TINK! A sesame-seed of space dust hits the hull at absurd speed.",
		"fact": "Fun fact: Spacecraft use layered Whipple shielding so tiny grains burst apart before they reach the pressure hull.",
		"likelihood": 5, "impact": 2,
		"choices": [
			{"label": "Patch it now (parts -1, power -4)", "fx": {"parts": -1, "power": -4}, "msg": "Patched. The sesame seed lost.", "risk": 0},
			{"label": "Ignore it (hull -18)", "fx": {"hull": -18}, "msg": "The hole whistles quietly. That is not good.", "risk": 4},
		],
	},
	{
		"title": "THE TOILET IS BROKEN",
		"text": "The most important machine on the ship has stopped working. The crew is staring at you.",
		"fact": "Fun fact: Space toilets use airflow instead of gravity. When they fail, it is a genuine mission problem.",
		"likelihood": 3, "impact": 4,
		"choices": [
			{"label": "Fix it (parts -1, morale -4)", "fx": {"parts": -1, "morale": -4}, "msg": "It works again. Nobody speaks of this.", "risk": 0},
			{"label": "Ignore it (morale -20)", "fx": {"morale": -20}, "msg": "The crew is now drawing very grumpy faces on a napkin.", "risk": 5},
		],
	},
	{
		"title": "FUEL LEAK",
		"text": "A valve is dripping fuel. Slowly. Dramatically.",
		"fact": "Fun fact: Every kilogram of fuel launched from Earth is expensive, so missions plan fuel with big safety margins.",
		"likelihood": 4, "impact": 4,
		"choices": [
			{"label": "Tighten the valve (parts -1, power -4)", "fx": {"parts": -1, "power": -4}, "msg": "Valve tightened. Mostly.", "risk": 0},
			{"label": "Let it drip (fuel -16)", "fx": {"fuel": -16}, "msg": "You lose a good chunk of fuel and some dignity.", "risk": 4},
		],
	},
	{
		"title": "LUCKY SUN BOOST",
		"text": "The solar panels line up perfectly and everything glows. Even the coffee is warm.",
		"fact": "Fun fact: Solar panels make power from sunlight, and in space there is no cloudy day.",
		"likelihood": 3, "impact": 1,
		"choices": [
			{"label": "Store the power (power +22)", "fx": {"power": 22}, "msg": "Batteries full. The ship hums happily.", "risk": 0},
			{"label": "Celebrate (morale +16, fuel +2)", "fx": {"morale": 16, "fuel": 2}, "msg": "You celebrate. Somebody put the launch playlist on again.", "risk": 0},
		],
	},
	{
		"title": "WATER RECYCLER CLOGGED",
		"text": "The water recycler is bubbling and burping. The water looks a bit cloudy. Hmm.",
		"fact": "Fun fact: The International Space Station recycles most of its water, even from the air the crew breathes out, back into clean drinking water.",
		"likelihood": 3, "impact": 4,
		"choices": [
			{"label": "Clean the filters (parts -1, water -8)", "fx": {"parts": -1, "water": -8}, "msg": "Filters cleaned. The water tastes like victory and chlorine.", "risk": 0},
			{"label": "Use the cloudy water anyway (water +12, morale -8)", "fx": {"water": 12, "morale": -8}, "msg": "You get water, but the crew makes funny faces.", "risk": 3},
		],
	},
	{
		"title": "PHOBOS-DEIMOS SAMPLE RETURN RUMOUR",
		"text": "Mission Control forwards you a wild idea to grab samples from the Martian moons. It is 3am. You are intrigued.",
		"fact": "Fun fact: Phobos and Deimos sample-return is a real proposed mission concept — a low-gravity grab is genuinely easier than landing on Mars.",
		"likelihood": 2, "impact": 2,
		"choices": [
			{"label": "Study it (science +8, power -4)", "fx": {"science": 8, "power": -4}, "msg": "You write notes in the margins. NASA will call this 'Trade Space'.", "risk": 0},
			{"label": "Sleep instead (morale +6)", "fx": {"morale": 6}, "msg": "You sleep. The idea waits, patient, on the napkin.", "risk": 0},
		],
	},
	{
		"title": "OXYGEN SCRUBBER FAILURE",
		"text": "The CO2 scrubber cartridge is spent and the backup is... decorative.",
		"fact": "Fun fact: Astronauts burn about 0.8 kg of oxygen a day, so life support has almost no slack.",
		"likelihood": 3, "impact": 5,
		"choices": [
			{"label": "Cannibalise the spare (parts -2, oxygen +14)", "fx": {"parts": -2, "oxygen": 14}, "msg": "You fixed it with a part labelled 'do not touch'. It is fine.", "risk": 0},
			{"label": "Ration air (oxygen -18, morale -6)", "fx": {"oxygen": -18, "morale": -6}, "msg": "The crew breathes slowly and glares efficiently.", "risk": 5},
		],
	},
	{
		"title": "CURIOSITY SENDS YOU A POSTCARD",
		"text": "The Curiosity rover relays a photo of a rock that looks, honestly, a little like a face.",
		"fact": "Fun fact: Curiosity has been roving Gale Crater since 2012 and still sends data back through Mars orbiters.",
		"likelihood": 2, "impact": 1,
		"choices": [
			{"label": "Analyse the image (science +10)", "fx": {"science": 10}, "msg": "It is a rock. You name it 'Ahmed'. Ahmed the rock enters history.", "risk": 0},
			{"label": "Send it to the group chat (morale +8)", "fx": {"morale": 8}, "msg": "The group chat is delighted. Twelve laughing emojis from Earth.", "risk": 0},
		],
	},
	{
		"title": "CREW BIRTHDAY",
		"text": "It is somebody's birthday! There is no cake, but there is freeze-dried ice cream and one tiny candle.",
		"fact": "Fun fact: Long missions run on rituals — birthdays, movie nights and shared meals protect crew morale.",
		"likelihood": 3, "impact": 1,
		"choices": [
			{"label": "Throw a party (food -6, morale +18)", "fx": {"food": -6, "morale": 18}, "msg": "Everyone sings. Badly. In space. Perfect.", "risk": 0},
			{"label": "Skip it (morale -10)", "fx": {"morale": -10}, "msg": "The birthday goes unmentioned. So does your name, for a while.", "risk": 3},
		],
	},
]

# --- Earth calls (Ground segment) -------------------------------------------
# Egyptian legends + NASA bureaucracy. Text-only cameos, written for comedy.
const CALLS := [
	{
		"caller": "AMR DIAB", "role": "Legendary singer / unofficial mission DJ",
		"text": "\"Habibi! El noor goes with you to Mars. When the beat drops, everyone on Fleet Radio sings. Do not let the oxygen drop instead, yalla!\"",
		"fact": "Fun fact: Music is real morale gear — NASA crews routinely ask for playlists on long missions.",
		"choices": [
			{"label": "Boost the engines (+6 fuel used, +8 morale)", "fx": {"fuel": -6, "morale": 8}, "msg": "The bridge turns into a dance floor. Zero-g dancing is chaos."},
			{"label": "Blast El Helwa Di through the ship (morale +14, power -3)", "fx": {"morale": 14, "power": -3}, "msg": "Morale soars. The speakers complain."},
		],
	},
	{
		"caller": "TAMER HOSNY", "role": "Heartthrob of Mission Control",
		"text": "\"Ya captain! Enta hero, habibi. I wrote you a song: 'Sahbak fi el fodaa' — 'Your friend in space'. Please fix the hull before the chorus.\"",
		"fact": "Fun fact: Engineers keep 'spares' because a single failed part can end a mission — redundancy is romantic too.",
		"choices": [
			{"label": "Fix a system (parts -1, power +5)", "fx": {"parts": -1, "power": 5}, "msg": "You repair while humming. The chorus lands."},
			{"label": "Sing along (morale +10, food -3)", "fx": {"morale": 10, "food": -3}, "msg": "Beautiful. Slightly off-key. The crew applauds anyway."},
		],
	},
	{
		"caller": "RAMY SABRY", "role": "Singer of feelings, now in charge of crew mental health",
		"text": "\"I am a little sad today. But you? You are going to the Moon. Sing it with me: we miss you, come back safe. Bring water.\"",
		"fact": "Fun fact: NASA studies crew psychology closely — isolation is one of the hardest parts of deep-space travel.",
		"choices": [
			{"label": "Group therapy session (morale +16, power -4)", "fx": {"morale": 16, "power": -4}, "msg": "Everyone shares feelings. Nobody cries in zero-g (tears just float there, judging)."},
			{"label": "Stay stoic (morale +4)", "fx": {"morale": 4}, "msg": "You nod, professionally. Ramy is unconvinced but supportive."},
		],
	},
	{
		"caller": "MOHAMED SALAH", "role": "The Egyptian King, Team Fitness Advisor",
		"text": "\"Listen, champ. Possession is like oxygen — never give it away for free. Press high, drink water, and hit the target. You'll do great.\"",
		"fact": "Fun fact: Microgravity weakens bones and muscles, so ISS crews exercise about 2 hours every single day.",
		"choices": [
			{"label": "Run the fitness drill (+12 morale, +8 water used)", "fx": {"morale": 12, "water": -8}, "msg": "The whole crew trains. Everyone celebrates like it's a Champions League final."},
			{"label": "Hydrate and rest (water +10, morale +4)", "fx": {"water": 10, "morale": 4}, "msg": "Mo approves. Hydration is elite performance."},
		],
	},
	{
		"caller": "TANTE NADIA", "role": "Your mother, calling from Alexandria",
		"text": "\"Habibi, did you eat? Do not tell me a spaceship is an excuse. I made too much koshary anyway. Eat something. Wear a jacket, it is cold up there.\"",
		"fact": "Fun fact: NASA tests yeast that grows nutrients like beta carotene on the ISS, so food stays nutritious over years.",
		"choices": [
			{"label": "Grow a yeast snack (food +16, power -4)", "fx": {"food": 16, "power": -4}, "msg": "You eat. She hears it through the radio and finally approves.", "start_bio": true},
			{"label": "Say you already ate (morale -8)", "fx": {"morale": -8}, "msg": "She knows. A mother always knows."},
		],
	},
	{
		"caller": "ENG. FAHMY", "role": "Chief Engineer & part-time stand-up comic",
		"text": "\"Good news: the toilet is fixed. Bad news: I never told you it was broken. Ha ha. Please check the hull. Ha ha. Please check the hull.\"",
		"fact": "Fun fact: Real missions keep spare equipment lists and margins so one broken part doesn't end the trip.",
		"choices": [
			{"label": "Inspect the hull (hull +12, power -4)", "fx": {"hull": 12, "power": -4}, "msg": "Hull inspected. Eng. Fahmy laughs at his own joke again."},
			{"label": "Laugh and carry on (morale +10)", "fx": {"morale": 10}, "msg": "You laugh. The hull does not."},
		],
	},
	{
		"caller": "EXPORT COMPLIANCE OFFICE", "role": "Earth, Building 7, 3rd floor",
		"text": "\"Hello, Captain. Did you file Form 27B for the engine? We are very sorry to ask while you are flying to Mars.\"",
		"fact": "Fun fact: Export control (ITAR/EAR) really does follow spacecraft hardware, even mid-mission.",
		"choices": [
			{"label": "File the form (power -2, morale -4)", "fx": {"power": -2, "morale": -4}, "msg": "Form filed. Stamped by gravity."},
			{"label": "Say 'The Moon can't hear you' (morale +8)", "fx": {"morale": 8}, "msg": "The line goes quiet. Victory."},
		],
	},
	{
		"caller": "PLANETARY PROTECTION OFFICER", "role": "Guardian of the Solar System",
		"text": "\"Captain. Your boots have Earth microbes. Mars does not want your microbes. Please sterilise. I will wait. I have infinite patience and a checklist.\"",
		"fact": "Fun fact: Planetary Protection rules stop us accidentally contaminating other worlds with Earth life.",
		"choices": [
			{"label": "Sterilise the airlock (power -5, morale -3)", "fx": {"power": -5, "morale": -3}, "msg": "Everything is scrubbed. You feel medically clean and emotionally tired."},
			{"label": "Argue that microbes are friends (science +6, morale +6)", "fx": {"science": 6, "morale": 6}, "msg": "You win the argument and lose the meeting. Science gains."},
		],
	},
	{
		"caller": "NEPA REVIEW BOARD", "role": "Environmental paperwork, in space",
		"text": "\"Before you can land, we need an environmental impact statement. For Mars. Which has no environment. Please proceed.\"",
		"fact": "Fun fact: NEPA reviews are a real US requirement for federal projects — even ones leaving the planet.",
		"choices": [
			{"label": "Complete the review (power -4, morale +6)", "fx": {"power": -4, "morale": 6}, "msg": "You fill 400 pages. On Mars, a robot files them. Somewhere, an auditor smiles."},
			{"label": "Delegate it to the interns on Earth (morale -4, science +4)", "fx": {"morale": -4, "science": 4}, "msg": "The interns cry quietly. You gain 4 science and lose 4 karma."},
		],
	},
	{
		"caller": "ARTEMIS FLIGHT DIRECTOR", "role": "Human spaceflight, feeling nostalgic",
		"text": "\"Orion says hello. We went back to the Moon, and now you are going further. Make us proud — and check your margins, 35% spare, minimum. That is the rule.\"",
		"fact": "Fun fact: The Artemis programme aims to return humans to the Moon and then push on toward Mars.",
		"choices": [
			{"label": "Trim to healthy margins (fuel +6, power +4)", "fx": {"fuel": 6, "power": 4}, "msg": "You tighten the budget. Flight Director approves."},
			{"label": "Spend the margin for speed (fuel -8, morale +8)", "fx": {"fuel": -8, "morale": 8}, "msg": "Fast and loose. The crew loves it. Engineering does not."},
		],
	},
	{
		"caller": "TAMER EL GAYAR", "role": "Egyptian internet legend / funny-video king",
		"text": "\"Oy oy oy! Captain! Everything floats in space, even my jokes! Smile, because the whole planet is watching your mission. Welcome to the next level!\"",
		"fact": "Fun fact: Everything floats in microgravity, so astronauts tie their tools down with Velcro and straps.",
		"choices": [
			{"label": "Laugh it off (morale +10)", "fx": {"morale": 10}, "msg": "You giggle. The crew wishes they had your sense of humor."},
			{"label": "Ask for his favorite snack idea (food +8, power -3)", "fx": {"food": 8, "power": -3}, "msg": "Tamer shares a snack idea. Everybody's tummy is happy."},
		],
	},
	{
		"caller": "DINA EL SHERBINY", "role": "Egyptian actress",
		"text": "\"Welcome back, Captain. I watched your launch on TV — you looked just like a movie star. Please land safe, I have a new role waiting for you.\"",
		"fact": "Fun fact: Egyptian actresses have been part of the cultural fabric since the golden age of cinema, and space inspires new art forms.",
		"choices": [
			{"label": "Send a video greeting (morale +12)", "fx": {"morale": 12}, "msg": "Dina sends a video from Earth. You watch it in the crew lounge."},
			{"label": "Ask for autograph (food -4, morale +6)", "fx": {"food": -4, "morale": 6}, "msg": "She signs a photo. The crew frames it."},
		],
	},
	{
		"caller": "ASTRONAUT HALA", "role": "Space Station astronaut, floating upside down",
		"text": "\"Hi Captain! I am floating next to a bubble of orange juice right now. Space is the best science lab ever. Ask me anything, or just wave at the camera!\"",
		"fact": "Fun fact: Water in space pulls itself into a floating ball because nothing is pulling it down.",
		"choices": [
			{"label": "Ask her for a science trick (science +8, power -4)", "fx": {"science": 8, "power": -4}, "msg": "Hala shows you how a water bubble wobbles. Everyone learns something."},
			{"label": "Wave at the camera (morale +10)", "fx": {"morale": 10}, "msg": "You wave. Hala does a floaty backflip. The crew cheers."},
		],
	},
	{
		"caller": "HAMDA HELAL", "role": "Egyptian singer / media personality",
		"text": "\"Ahlan wa sahlan ya Captain! El hilm el gameeza fe el space, ya3ny el ambiance is everything. Don't forget your sunglasses!\"",
		"fact": "Fun fact: Egyptian music spans millennia from Umm Kulthum to modern pop — rhythm is in our blood.",
		"choices": [
			{"label": "Request a song (morale +10, power -3)", "fx": {"morale": 10, "power": -3}, "msg": "Hamda plays a track. The bridge vibes."},
			{"label": "Learn about the culture (science +6, morale +4)", "fx": {"science": 6, "morale": 4}, "msg": "You ask about Egyptian traditions. Hamda schools you."},
		],
	},
]

# --- Science fleet (used as fun facts / scoring) ----------------------------
const FLEET := [
	{"name": "Curiosity", "fact": "Roving Gale Crater since 2012, looking for signs that Mars was once habitable."},
	{"name": "Perseverance", "fact": "Hunting for ancient microbial life and caching samples for a future return to Earth."},
	{"name": "MAVEN", "fact": "Studying how Mars lost its atmosphere to space, one solar storm at a time."},
	{"name": "Mars Odyssey", "fact": "An orbiting communications relay and mapper, still working after decades."},
	{"name": "Artemis", "fact": "NASA's programme to return humans to the Moon as a stepping stone to Mars."},
	{"name": "Phobos & Deimos return", "fact": "A proposed mission to grab samples from the Martian moons with far less fuel than a Mars landing."},
]

# --- Foods (BioNutrients mini-game) -----------------------------------------
const FOODS := [
	{
		"id": "yeast", "name": "Beta-Carotene Yeast",
		"target_temp": 30.0, "tolerance": 2.5, "yield": 18.0,
		"shakes": 3, "shake_window": 1.6,
		"desc": "Incubates at 30 C. Rich in beta carotene (it is what makes carrots orange).",
		"fact": "Fun fact: NASA's BioNutrients project grows nutrient-producing yeast on demand so astronauts get fresh vitamins.",
	},
	{
		"id": "yogurt", "name": "Space Yogurt",
		"target_temp": 42.0, "tolerance": 2.0, "yield": 22.0,
		"shakes": 4, "shake_window": 1.2,
		"desc": "Incubates at 42 C. Pickier than yeast, but tastier and yields more.",
		"fact": "Fun fact: Yogurt cultures are fussy about temperature — a few degrees off and you get sad milk instead.",
	},
]

# --- Risk matrix labels (5x5) -----------------------------------------------
const RISK_LABELS := ["Negligible", "Low", "Moderate", "High", "Severe"]

# =============================================================================
# KIDS EDITION additions
# =============================================================================
# Grade band chosen on the title screen: "junior" (ages 8-10) or "middle" (11-14).
static var band := "junior"

static func is_junior() -> bool:
	return band == "junior"

# Bad things hurt less in the junior band, so mistakes teach instead of punish.
static func soft() -> float:
	return 0.6 if band == "junior" else 1.0

# How fast supplies run down.
static func drain() -> float:
	return 0.75 if band == "junior" else 1.25

const LIFELINES := 3
const MASCOT := "Mishmish"

const PLANET_NAMES := ["Bloop", "Zorbi", "Fizzle", "Wobblo", "Nibbles", "Gloop", "Twinkle", "Pogo", "Marzipan",
	"Sphinxy", "Koshary", "Zigzag", "Mango", "Pyramidia", "Noodle", "Sparkle", "Lotus", "Bubbly", "Dune", "Habibi-7",
	"Falafel", "Orbit", "Cosmo", "Sandy", "Scarab", "Nile-9", "Giggle", "Planetoid P"]

# Quiz bank: first answer in "a" is the correct one (shuffled when shown).
const QUIZ := [
	{"band": "junior", "topic": "Moon", "q": "What is the name of Earth's natural satellite?", "a": ["The Moon", "Mars", "The Sun", "A comet"], "why": "The Moon travels around Earth about once every month."},
	{"band": "junior", "topic": "Mars", "q": "Which planet is called the Red Planet?", "a": ["Mars", "Jupiter", "Venus", "Neptune"], "why": "Mars is covered in rusty, iron-rich dust that makes it look red."},
	{"band": "junior", "topic": "Solar system", "q": "How many planets are in our solar system?", "a": ["8", "6", "9", "12"], "why": "Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus and Neptune."},
	{"band": "junior", "topic": "Sun", "q": "What is at the center of our solar system?", "a": ["The Sun", "The Moon", "Earth", "Jupiter"], "why": "The Sun is a star. Everything in our solar system travels around it."},
	{"band": "junior", "topic": "Planets", "q": "Which planet is the biggest in our solar system?", "a": ["Jupiter", "Earth", "Mars", "Mercury"], "why": "Jupiter is so big that more than 1,000 Earths could fit inside it."},
	{"band": "junior", "topic": "Gravity", "q": "What invisible force keeps your feet on the ground?", "a": ["Gravity", "Wind", "Magnets", "Sound"], "why": "Gravity pulls things toward the center of a planet or moon."},
	{"band": "junior", "topic": "Space", "q": "Is there air to breathe in outer space?", "a": ["No, space is almost empty", "Yes, lots of air", "Only near stars", "Only at night"], "why": "Space is a near-empty vacuum, so astronauts carry their own air supply."},
	{"band": "junior", "topic": "Astronauts", "q": "Why do astronauts float inside the space station?", "a": ["They are falling around Earth together with the station", "There is no Earth nearby", "The station is very light", "Magic boots"], "why": "The station and crew are in constant free-fall around Earth, so they feel weightless."},
	{"band": "junior", "topic": "Energy", "q": "Spacecraft solar panels turn sunlight into what?", "a": ["Electricity", "Water", "Snow", "Wind"], "why": "Solar panels make electricity that powers lights, computers and radios."},
	{"band": "junior", "topic": "Planets", "q": "Which planet is famous for its big, bright rings?", "a": ["Saturn", "Mars", "Mercury", "Earth"], "why": "Saturn's rings are made of billions of pieces of ice and rock."},
	{"band": "junior", "topic": "Rovers", "q": "Which one is a real NASA rover that explores Mars?", "a": ["Perseverance", "Sphinx-Runner", "Moon Buggy 9", "Falafel-1"], "why": "Perseverance landed on Mars in 2021 to look for signs of ancient life."},
	{"band": "junior", "topic": "Earth", "q": "About how long does Earth take to spin around once (one day)?", "a": ["24 hours", "1 hour", "7 days", "1 year"], "why": "One spin of Earth gives us day and night."},
	{"band": "junior", "topic": "Life support", "q": "Which gas do astronauts need to breathe?", "a": ["Oxygen", "Helium", "Smoke", "Steam"], "why": "Oxygen is why spaceships carry tanks and air scrubbers."},
	{"band": "junior", "topic": "Apollo", "q": "About how long did Apollo astronauts take to fly to the Moon?", "a": ["About 3 days", "About 3 minutes", "About 3 months", "About 3 years"], "why": "The Moon is far away, but a rocket can get there in around three days."},
	{"band": "junior", "topic": "Egypt", "q": "Egypt has its own space agency. What is it called?", "a": ["Egyptian Space Agency (EgSA)", "Pyramid Rocket Club", "Nile Air Force", "Sphinx Science Hub"], "why": "The Egyptian Space Agency was set up in 2018 to grow space science in Egypt."},
	{"band": "junior", "topic": "Sky", "q": "Ancient Egyptians built the pyramids lined up very closely with north, south, east and west. What might have helped them?", "a": ["Watching the sky", "A compass app", "Satellites", "A GPS phone"], "why": "Scientists think builders used the Sun and the stars to find direction."},
	{"band": "junior", "topic": "Stars", "q": "What are stars made of?", "a": ["Very hot glowing gas", "Solid ice", "Tiny lamps", "Rock and sand"], "why": "Stars are giant balls of hot gas that make their own light."},
	{"band": "middle", "topic": "Moon", "q": "How strong is gravity on the Moon compared to Earth?", "a": ["About one-sixth", "The same", "Twice as strong", "There is none"], "why": "A 60 kg kid would weigh about 10 kg on the Moon, so jumping is fun!"},
	{"band": "middle", "topic": "Distance", "q": "About how far is the Moon from Earth?", "a": ["About 384,000 km", "About 3,840 km", "About 38 million km", "About 384 million km"], "why": "That is roughly 30 Earths lined up side by side."},
	{"band": "middle", "topic": "Light", "q": "About how long does light take to travel from the Moon to Earth?", "a": ["About 1.3 seconds", "About 1.3 minutes", "About 1.3 hours", "Instantly"], "why": "Light travels about 300,000 km every second, so radio calls to the Moon have a small delay."},
	{"band": "middle", "topic": "Seasons", "q": "What causes the seasons on Earth?", "a": ["Earth's tilted axis", "Earth getting closer and farther from the Moon", "Clouds blocking the Sun", "The Sun turning off"], "why": "The tilt changes how directly sunlight hits each part of Earth during the year."},
	{"band": "middle", "topic": "Mars", "q": "Mars' thin atmosphere is mostly made of which gas?", "a": ["Carbon dioxide", "Oxygen", "Hydrogen", "Water vapor"], "why": "That is why people cannot breathe on Mars without a spacesuit."},
	{"band": "middle", "topic": "Orbits", "q": "What keeps a satellite in orbit around Earth?", "a": ["Its forward speed balanced with gravity", "A giant invisible rope", "Rocket fuel burning forever", "Earth's wind"], "why": "The satellite keeps falling toward Earth but moves sideways so fast that it keeps missing it."},
	{"band": "middle", "topic": "Rockets", "q": "Rockets work because of which idea?", "a": ["Every action has an equal and opposite reaction", "Heat always rises", "Light moves in waves", "Objects like to stay cold"], "why": "A rocket pushes hot gas down and the gas pushes the rocket up (Newton's third law)."},
	{"band": "middle", "topic": "Communication", "q": "Why can't Mission Control chat with a Mars rover in real time?", "a": ["Radio signals take minutes to travel that far", "Mars has no radio waves", "Rovers are asleep at night", "Space blocks all signals"], "why": "A signal takes roughly 3 to 22 minutes one way, depending on where Earth and Mars are."},
	{"band": "middle", "topic": "Distance", "q": "What is a light-year?", "a": ["The distance light travels in one year", "One year of sunlight", "A very bright star", "The time to orbit the Sun"], "why": "A light-year is a distance of about 9.5 trillion km."},
	{"band": "middle", "topic": "Mars", "q": "Why do Mars missions launch only about every two years?", "a": ["Earth and Mars line up for a shorter trip", "Mars switches off", "Rockets need two years to cool", "Mars is hidden by clouds"], "why": "Good launch windows come around every 26 months or so and save lots of fuel."},
	{"band": "middle", "topic": "Plants", "q": "Which gas do plants release when they make food using sunlight?", "a": ["Oxygen", "Carbon monoxide", "Helium", "Nitrogen"], "why": "Photosynthesis turns sunlight, water and carbon dioxide into sugar and oxygen. Space farms use this!"},
	{"band": "middle", "topic": "Scientific method", "q": "In a fair experiment you change only one thing at a time. Why?", "a": ["So you know what caused the result", "To finish faster", "To use less paper", "So nobody can repeat it"], "why": "Changing just one variable lets scientists tell which thing made the difference."},
	{"band": "middle", "topic": "Data", "q": "You measure a rock's temperature three times: 10, 11 and 10 degrees. Why repeat measurements?", "a": ["To check the result is reliable", "Because the first one is always wrong", "To make the rock hotter", "It is only for fun"], "why": "Repeating a measurement shows whether the numbers agree and helps spot mistakes."},
	{"band": "middle", "topic": "Planets", "q": "Which planet is the hottest in our solar system?", "a": ["Venus", "Mercury", "Mars", "Jupiter"], "why": "Venus has a thick carbon-dioxide atmosphere that traps heat, hotter than Mercury even though Mercury is closer to the Sun."},
	{"band": "middle", "topic": "ISS", "q": "About how often does the space station circle Earth?", "a": ["Every 90 minutes", "Every 24 hours", "Every week", "Every year"], "why": "It moves at about 28,000 km/h, so the crew sees about 16 sunrises a day."},
	{"band": "middle", "topic": "Atmosphere", "q": "What is the most common gas in Earth's air?", "a": ["Nitrogen", "Oxygen", "Carbon dioxide", "Hydrogen"], "why": "Air is about 78% nitrogen and about 21% oxygen."},
	{"band": "middle", "topic": "Engineering", "q": "Spacecraft carry spare parts and extra power. Engineers call this extra safety room a...", "a": ["Margin", "Decoration", "Bonus level", "Shortcut"], "why": "Real missions keep a safety margin, because something always surprises you in space."},
]

# Questions for the chosen band. Middle schoolers also get the easier ones sometimes.
static func quiz_pool() -> Array:
	var out: Array = []
	for q in QUIZ:
		if band == "middle" or str(q["band"]) == "junior":
			out.append(q)
	if band == "middle":
		# Weight toward middle-school questions by listing them twice.
		for q2 in QUIZ:
			if str(q2["band"]) == "middle":
				out.append(q2)
	return out
