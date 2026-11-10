extends Control
signal position_selected(point: int)
const Geometry = preload("res://scripts/battle_geometry.gd")
const Unit = preload("res://scripts/unit_view.gd")
var widgets: Dictionary = {}
var enemy := false
var snapshot: Dictionary = {}


func _ready() -> void:
	resized.connect(_arrange)


func configure(board: Dictionary, is_enemy: bool = false, monster: Dictionary = {}) -> void:
	snapshot = board.duplicate(true)
	enemy = is_enemy
	for child in get_children():
		remove_child(child)
		child.queue_free()
	widgets.clear()
	for point in 4:
		var id: int = -1
		if is_enemy:
			if point == int(board.get("enemy_position", 0)) and int(board.get("monster_hull", 0)) > 0:
				id = 0
		else:
			id = board.get("formation", [-1, -1, -1, -1])[point]
		var widget: Button
		if id >= 0:
			widget = Unit.new()
			add_child(widget)
			var data: Dictionary = monster.duplicate(true) if is_enemy else board.ships[id].duplicate(true)
			if is_enemy:
				data["max_hull"] = monster.get("hull", 1)
				data["hull"] = board.monster_hull
			widget.configure(data, is_enemy)
			widget.set_meta("ship_index", -1 if is_enemy else id)
		else:
			widget = Button.new()
			widget.text = Geometry.POSITION_NAMES[point] + "\nEmpty"
			widget.modulate = Color("#506977")
			add_child(widget)
		widget.pressed.connect(func(): position_selected.emit(point))
		widgets[point] = widget
	_arrange()


func _arrange() -> void:
	var w := minf(144, size.x * 0.43)
	var h := 80.0
	var coordinates := [Vector2(0.77 if not enemy else 0.23, 0.50), Vector2(0.5, 0.12), Vector2(0.5, 0.88), Vector2(0.23 if not enemy else 0.77, 0.5)]
	for point in widgets:
		widgets[point].size = Vector2(w, h)
		var centre: Vector2 = Vector2(size.x, size.y) * coordinates[point]
		widgets[point].position = (centre - widgets[point].size / 2).clamp(Vector2.ZERO, (size - widgets[point].size).max(Vector2.ZERO))
	queue_redraw()


func _draw() -> void:
	for link in Geometry.UNIT_LINKS:
		if widgets.has(link[0]) and widgets.has(link[1]):
			draw_line(widgets[link[0]].position + widgets[link[0]].size / 2, widgets[link[1]].position + widgets[link[1]].size / 2, Color("#345866"), 2, true)
