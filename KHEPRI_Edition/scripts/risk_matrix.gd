class_name RiskMatrix
extends Control

# A 5x5 likelihood x impact risk matrix (the sort NASA reviewers love).
var likelihood: int = 3
var impact: int = 3


func _ready() -> void:
	custom_minimum_size = Vector2(168, 150)


func set_risk(l: int, i: int) -> void:
	likelihood = clampi(l, 1, 5)
	impact = clampi(i, 1, 5)
	queue_redraw()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	var grid_w := size.x - 42.0
	var grid_h := size.y - 26.0
	var cell := Vector2(grid_w / 5.0, grid_h / 5.0)
	var origin := Vector2(30, 6)
	# cells: x = likelihood, y = impact (impact grows upward)
	for cx in range(5):
		for cy in range(5):
			var l := cx + 1
			var im := cy + 1
			var score := l * im
			var col := Color(0.25, 0.7, 0.35, 0.55)
			if score >= 13:
				col = Color(0.95, 0.3, 0.25, 0.7)
			elif score >= 8:
				col = Color(0.95, 0.75, 0.25, 0.6)
			var r := Rect2(origin + Vector2(cx * cell.x, (4 - cy) * cell.y), cell - Vector2(2, 2))
			draw_rect(r, col, true)
			draw_rect(r, Color(0, 0, 0, 0.4), false, 1.0)
	# marker
	var mx := origin.x + (likelihood - 1) * cell.x + cell.x * 0.5
	var my := origin.y + (5 - impact) * cell.y + cell.y * 0.5
	draw_circle(Vector2(mx, my), 5.0, Color(1, 1, 1))
	draw_arc(Vector2(mx, my), 8.0, 0, TAU, 20, Color(0, 0, 0, 0.8), 2.0)
	# labels
	draw_string(f, Vector2(2, size.y - 6), "Impact ", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.85, 0.95))
	draw_string(f, Vector2(origin.x, size.y - 6), "Likelihood >", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.85, 0.95))
	draw_string(f, Vector2(size.x - 46, grid_h * 0.5), GameData.RISK_LABELS[impact - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))