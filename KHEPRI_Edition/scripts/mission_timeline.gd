class_name MissionTimeline
extends Control

# =============================================================================
# Compact 2D mission timeline with event markers and status indicators.
# Real missions do not all follow the same order; the note says so.
# =============================================================================

const STEP := 130.0
const MARGIN := 74.0

var _events: Array = []   # [{label, status: "done"|"current"|"upcoming"}]
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 60)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func set_events(events: Array) -> void:
	_events = events
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _status_color(status: String) -> Color:
	match status:
		"done": return Color(0.4, 0.95, 0.5)
		"current": return Color(1.0, 0.85, 0.3)
		"upcoming": return Color(0.5, 0.55, 0.7)
	return Color(0.7, 0.7, 0.7)


func _draw() -> void:
	var f := ThemeDB.fallback_font
	if _events.is_empty():
		draw_string(f, Vector2(4, 32), "Timeline: --", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9))
		return
	var y := 22.0
	var n := _events.size()
	# base line
	var x0 := MARGIN
	var x1 := MARGIN + STEP * float(n - 1)
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.35, 0.45, 0.6, 0.9), 3.0)
	for i in n:
		var e: Dictionary = _events[i]
		var x := MARGIN + STEP * float(i)
		var col := _status_color(str(e.get("status", "upcoming")))
		var r := 8.0
		if str(e.get("status", "")) == "current":
			r = 9.0 + 2.0 * absf(sin(_t * 3.0))
			draw_arc(Vector2(x, y), r + 5.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.5), 2.0)
		if str(e.get("status", "")) == "done":
			# tick mark inside the node
			draw_line(Vector2(x - 4, y), Vector2(x - 1, y + 3), Color(0.05, 0.12, 0.06), 2.0)
			draw_line(Vector2(x - 1, y + 3), Vector2(x + 4, y - 4), Color(0.05, 0.12, 0.06), 2.0)
		draw_circle(Vector2(x, y), r, col)
		draw_arc(Vector2(x, y), r, 0, TAU, 20, Color(0.02, 0.03, 0.06, 0.9), 1.5)
		# label (wrapped to 2 short lines by spaces)
		var label := str(e.get("label", ""))
		var words := label.split(" ", false)
		var lines: Array = [label]
		if label.length() > 12 and words.size() > 1:
			var mid := int(ceil(float(words.size()) / 2.0))
			lines = [" ".join(words.slice(0, mid)), " ".join(words.slice(mid))]
		for li in lines.size():
			var ln: String = lines[li]
			var sz := f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
			draw_string(f, Vector2(x - sz.x * 0.5, 46 + li * 12.0), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.94, 1.0))
	# note
	draw_string(f, Vector2(4, 14), "MISSION TIMELINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.85, 1.0))