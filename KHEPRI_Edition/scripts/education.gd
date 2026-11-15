class_name Education
extends RefCounted

# =============================================================================
# Data-driven educational content loader.
# All content lives in res://data/education.json so new material can be added
# without touching gameplay scripts. Loaded once and cached; works offline.
# =============================================================================

const PATH := "res://data/education.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_load()
	return _data


static func _load() -> void:
	_data = {}
	if not FileAccess.file_exists(PATH):
		push_error("Education: missing data file " + PATH)
		return
	var txt := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("Education: could not parse " + PATH)


static func segments() -> Array:
	return data().get("segments", [])


static func segment(id: String) -> Dictionary:
	for s in segments():
		if str(s.get("id", "")) == id:
			return s
	return {}


static func rooms() -> Dictionary:
	return data().get("rooms", {})


static func room(sys: String) -> Dictionary:
	var r: Dictionary = rooms()
	return r.get(sys, {})


static func instruments() -> Dictionary:
	return data().get("instruments", {})


static func instrument(id: String) -> Dictionary:
	var i: Dictionary = instruments()
	return i.get(id, {})


static func scan_targets() -> Dictionary:
	return data().get("scan_targets", {})


static func scan_target(body: String) -> Dictionary:
	var t: Dictionary = scan_targets()
	return t.get(body, {})


static func tips() -> Dictionary:
	return data().get("tips", {})


static func tip(id: String) -> Dictionary:
	var t: Dictionary = tips()
	return t.get(id, {})


static func cml() -> Array:
	return data().get("cml", [])


static func library() -> Array:
	return data().get("library", [])


static func missions() -> Dictionary:
	return data().get("missions", {})


static func mission(id: String) -> Dictionary:
	var m: Dictionary = missions()
	return m.get(id, {})


static func sources() -> Array:
	return data().get("sources", [])


# --- helpers ----------------------------------------------------------------
# Human label for how trustworthy a value is.
static func kind_label(kind: String) -> String:
	match kind:
		"real": return "real value"
		"simplified": return "simplified value"
		"fictional": return "fictional game value"
	return kind


static func kind_color(kind: String) -> Color:
	match kind:
		"real": return Color(0.5, 0.95, 0.55)
		"simplified": return Color(1.0, 0.85, 0.35)
		"fictional": return Color(1.0, 0.55, 0.5)
	return Color(0.8, 0.85, 0.95)


# The real-world facts keyed off a room id (used for one-line hints).
static func room_subject(sys: String) -> String:
	return str(room(sys).get("subject", ""))