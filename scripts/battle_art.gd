@tool
extends Control
## Lightweight vector silhouettes, scaled to the available UI space.

@export_enum("Ship", "Leviathan") var subject: int = 0
@export var accent: Color = Color("#d8b477"):
	set(value):
		accent = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var scale_factor := minf(size.x / 240.0, size.y / 90.0)
	var origin := (size - Vector2(240, 90) * scale_factor) / 2.0
	draw_set_transform(origin, 0, Vector2.ONE * scale_factor)
	if subject == 0:
		draw_colored_polygon(PackedVector2Array([
			Vector2(30, 68), Vector2(207, 68), Vector2(181, 84), Vector2(65, 84)]), accent.darkened(0.4))
		draw_line(Vector2(83, 47), Vector2(88, 68), accent, 2, true)
		draw_line(Vector2(164, 47), Vector2(158, 68), accent, 2, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(15, 33), Vector2(45, 13), Vector2(170, 10),
			Vector2(217, 32), Vector2(172, 53), Vector2(48, 53)]), accent.darkened(0.6))
		draw_polyline(PackedVector2Array([
			Vector2(15, 33), Vector2(45, 13), Vector2(170, 10),
			Vector2(217, 32), Vector2(172, 53), Vector2(48, 53), Vector2(15, 33)]), accent, 2, true)
		draw_line(Vector2(28, 33), Vector2(205, 32), accent.darkened(0.15), 1, true)
		for x in [68, 112, 155]:
			draw_line(Vector2(x, 15), Vector2(x, 50), accent.darkened(0.2), 1, true)
		draw_circle(Vector2(198, 75), 4, Color("#88d9ed"))
	else:
		for y in [22, 45, 68]:
			draw_line(Vector2(0, y), Vector2(240, y), Color("#193945"), 1, true)
		var body := PackedVector2Array([
			Vector2(8, 47), Vector2(61, 38), Vector2(87, 26), Vector2(120, 30),
			Vector2(153, 12), Vector2(148, 35), Vector2(194, 32), Vector2(229, 45),
			Vector2(208, 57), Vector2(172, 55), Vector2(143, 67), Vector2(111, 58),
			Vector2(80, 77), Vector2(90, 53), Vector2(54, 53), Vector2(8, 47)])
		draw_colored_polygon(body, Color("#254e60"))
		draw_polyline(body, Color("#84b6bf"), 2, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(109, 37), Vector2(61, 3), Vector2(147, 28)]), Color("#396b7a"))
		draw_circle(Vector2(209, 43), 3, Color("#e8bd77"))
		draw_line(Vector2(186, 50), Vector2(221, 49), Color("#d2e3db"), 1, true)
	draw_set_transform(Vector2.ZERO)
