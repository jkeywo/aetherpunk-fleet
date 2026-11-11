extends Control
## Beam and blast geometry uses screen-space targets and no gameplay RNG.
var style := "beam"
var start := Vector2.ZERO
var centre := Vector2.ZERO
var impacts: Array = []
var tint := Color("#8ceaff")
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if impacts.is_empty(): return
	if style == "beam":
		var strength := sin(clampf(progress, 0, 1) * PI)
		var end: Vector2 = impacts.back()
		draw_line(start, end, Color(tint, strength * .16), 24, true)
		draw_line(start, end, Color(tint, strength * .75), 9, true)
		draw_line(start, end, Color(1, 1, 1, strength), 3, true)
		for point in impacts:
			draw_arc(point, 8 + progress * 17, 0, TAU, 32, Color(tint, strength), 2, true)
			for i in 6:
				var axis := Vector2.from_angle(i * TAU / 6 + progress)
				draw_line(point + axis * 7, point + axis * (12 + strength * 12), Color(tint, strength), 2, true)
	else:
		if progress < .3:
			var head := start.lerp(centre, progress / .3)
			draw_line(start.lerp(centre, maxf(0, progress / .3 - .15)), head, Color(tint, .8), 5, true)
			draw_circle(head, 5, Color("#fff1bb"), true, -1, true)
		else:
			var blast := (progress - .3) / .7
			var radius := 32.0
			for point in impacts: radius = maxf(radius, centre.distance_to(point) + 18)
			var alpha := 1 - blast
			draw_circle(centre, (12 + radius * blast) * .65, Color(tint, alpha * .13), true, -1, true)
			draw_arc(centre, 10 + radius * blast, 0, TAU, 64, Color(tint, alpha), 4, true)
			draw_arc(centre, 6 + radius * blast * .7, 0, TAU, 48, Color("#ffe3a6", alpha), 2, true)
			for i in 16:
				var axis := Vector2.from_angle(i * TAU / 16 + .17)
				draw_line(centre + axis * (10 + blast * radius * .55), centre + axis * (20 + blast * radius), Color(tint, alpha), 2, true)
			for point in impacts:
				if blast * radius + 20 >= centre.distance_to(point):
					draw_arc(point, 5 + blast * 17, 0, TAU, 24, Color(tint, alpha), 2, true)
