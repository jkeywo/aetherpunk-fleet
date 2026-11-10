extends Control
signal ship_drag_hovered(ship_id: int, data: Variant)
signal ship_drag_exited(ship_id: int)
signal ship_dropped(ship_id: int, data: Variant)
signal position_selected(point: int)
const Geometry = preload("res://scripts/battle_geometry.gd")
const Unit = preload("res://scripts/unit_view.gd")
var widgets: Dictionary = {}
var wreck_widgets: Dictionary = {}
var drop_check: Callable
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
	wreck_widgets.clear()
	for point in 4:
		var id: int = -1
		if is_enemy:
			if board.has("enemy_formation"):
				id = int(board.enemy_formation[point])
			elif point == int(board.get("enemy_position", 0)) and int(board.get("monster_hull", 0)) > 0:
				id = 0
		else:
			id = board.get("formation", [-1, -1, -1, -1])[point]
		var widget: Button
		if id >= 0:
			widget = Unit.new()
			add_child(widget)
			var data: Dictionary = (board.enemies[id].duplicate(true) if board.has("enemies") else monster.duplicate(true)) if is_enemy else board.ships[id].duplicate(true)
			if is_enemy and not board.has("enemies"):
				data["max_hull"] = monster.get("hull", 1)
				data["hull"] = board.monster_hull
			widget.configure(data, is_enemy)
			widget.set_meta("ship_index", -1 - id if is_enemy else id)
			var cover_amount: int = int(board.get("cover", [0, 0, 0, 0, 0, 0, 0, 0])[point + (4 if is_enemy else 0)])
			if cover_amount > 0: widget.hull_label.text += "  C" + str(cover_amount)
			widget.tooltip_text += "\nSlot cover: " + str(cover_amount)
			if not is_enemy:
				_wire_target(widget, id)
		else:
			widget = Button.new()
			var cover_amount: int = int(board.get("cover", [0, 0, 0, 0, 0, 0, 0, 0])[point + (4 if is_enemy else 0)])
			widget.text = Geometry.POSITION_NAMES[point] + "\nEmpty" + (" / Cover " + str(cover_amount) if cover_amount > 0 else "")
			widget.modulate = Color("#506977")
			add_child(widget)
		widget.pressed.connect(func(): position_selected.emit(point))
		widgets[point] = widget
	if not is_enemy:
		var threshold: int = int(board.get("basic_actions", {}).get("revive_threshold", 4))
		for ship_id in board.get("ships", []).size():
			var ship: Dictionary = board.ships[ship_id]
			if int(ship.hull) > 0:
				continue
			var wreck := Button.new()
			wreck.add_theme_font_size_override("font_size", 12)
			wreck.clip_text = true
			wreck.text = "%s / WRECK\nRecovery %d / %d" % [ship.name, ship.get("recovery", 0), threshold]
			wreck.tooltip_text = "%s is defeated. Recovery %d / %d. Drag one of its own cards here to recover; revival needs an empty position." % [ship.name, ship.get("recovery", 0), threshold]
			wreck.set_meta("ship_index", ship_id)
			add_child(wreck)
			_wire_target(wreck, ship_id)
			wreck_widgets[ship_id] = wreck
	_arrange()


func _arrange() -> void:
	var w := minf(144, size.x * 0.43)
	var h := 80.0
	var coordinates := [Vector2(0.77 if not enemy else 0.23, 0.50), Vector2(0.5, 0.12), Vector2(0.5, 0.88), Vector2(0.23 if not enemy else 0.77, 0.5)]
	for point in widgets:
		widgets[point].size = Vector2(w, h)
		var centre: Vector2 = Vector2(size.x, size.y) * coordinates[point]
		widgets[point].position = (centre - widgets[point].size / 2).clamp(Vector2.ZERO, (size - widgets[point].size).max(Vector2.ZERO))
	var index := 0
	for wreck in wreck_widgets.values():
		wreck.position = Vector2(index * size.x / maxf(1, wreck_widgets.size()), size.y + 8)
		wreck.size = Vector2(size.x / maxf(1, wreck_widgets.size()) - 6, 48)
		index += 1
	queue_redraw()


func _draw() -> void:
	for link in Geometry.UNIT_LINKS:
		if widgets.has(link[0]) and widgets.has(link[1]):
			draw_line(widgets[link[0]].position + widgets[link[0]].size / 2, widgets[link[1]].position + widgets[link[1]].size / 2, Color("#345866"), 2, true)


func _wire_target(widget: Button, ship_id: int) -> void:
	if widget is Unit:
		if drop_check.is_valid():
			widget.tooltip_text += "\nDrag its own card here to repair, or an adjacent living ship's card to swap. Basic actions discard the dragged card."
		widget.set_meta("base_guard_text", widget.guard_label.text)
	widget.set_meta("base_tooltip", widget.tooltip_text)
	widget.set_drag_forwarding(Callable(), _can_drop_on_ship.bind(ship_id), _drop_on_ship.bind(ship_id))
	widget.mouse_exited.connect(func(): ship_drag_exited.emit(ship_id))


func target_widget(ship_id: int) -> Control:
	if wreck_widgets.has(ship_id):
		return wreck_widgets[ship_id]
	for widget in widgets.values():
		if widget.get_meta("ship_index", -999) == ship_id:
			return widget
	return null


func _can_drop_on_ship(_point: Vector2, data: Variant, ship_id: int) -> bool:
	if not drop_check.is_valid():
		return false
	ship_drag_hovered.emit(ship_id, data)
	return bool(drop_check.call(data, ship_id))


func _drop_on_ship(_point: Vector2, data: Variant, ship_id: int) -> void:
	if drop_check.is_valid() and drop_check.call(data, ship_id):
		ship_dropped.emit(ship_id, data)


func show_basic_targets(hints: Dictionary = {}, valid: Array = [], selected_ship: int = -1, actor: int = -1) -> void:
	for ship_id in snapshot.get("ships", []).size():
		var widget := target_widget(ship_id) as Button
		if widget == null:
			continue
		for key in ["normal", "hover", "pressed", "hover_pressed"]:
			widget.remove_theme_stylebox_override(key)
		widget.tooltip_text = str(widget.get_meta("base_tooltip", ""))
		if widget is Unit:
			widget.guard_label.text = str(widget.get_meta("base_guard_text", ""))
		if not hints.has(ship_id):
			continue
		widget.tooltip_text = str(hints[ship_id])
		var tint := Color("#8a535b")
		var fill := Color("#241d26")
		if valid.has(ship_id):
			tint = Color("#9ce6b7") if ship_id == actor else Color("#67bdd4")
			if widget is Unit:
				widget.guard_label.text = "REPAIR (discard 1 card)" if ship_id == actor else "SWAP (discard 1 card)"
			fill = Color("#153329") if ship_id == actor else Color("#102b36")
			if selected_ship == ship_id:
				tint = Color("#e8bd77")
		for key in ["normal", "hover", "pressed", "hover_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = fill.lightened(0.08) if key in ["hover", "hover_pressed"] else fill
			style.border_color = tint
			style.set_border_width_all(3 if valid.has(ship_id) else 1)
			style.set_corner_radius_all(5)
			widget.add_theme_stylebox_override(key, style)
