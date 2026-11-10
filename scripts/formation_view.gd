extends Control
signal ship_drag_hovered(ship_id: int, data: Variant)
signal ship_drag_exited(ship_id: int)
signal ship_dropped(ship_id: int, data: Variant)
signal position_selected(point: int)
signal unit_selected(id: int)
signal unit_hovered(id: int)
signal unit_exited(id: int)
const Geometry = preload("res://scripts/battle_geometry.gd")
const Unit = preload("res://scripts/unit_view.gd")
var widgets: Dictionary = {}
var wreck_widgets: Dictionary = {}
var large_cards := false
var drop_check: Callable
var enemy := false
var snapshot: Dictionary = {}
var cover_clouds: Dictionary={}


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
	cover_clouds.clear()
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
			var unit_id: int=-1-id if is_enemy else id
			widget.mouse_entered.connect(func():unit_hovered.emit(unit_id))
			widget.mouse_exited.connect(func():unit_exited.emit(unit_id))
			var cover_amount: int = int(board.get("cover", [0, 0, 0, 0, 0, 0, 0, 0])[point + (4 if is_enemy else 0)])
			widget.set_cover(cover_amount)
			widget.tooltip_text += "\nSlot cover: " + str(cover_amount)
			if not is_enemy:
				_wire_target(widget, id)
		else:
			widget = Button.new()
			widget.set_meta("empty_slot",true)
			var cover_amount: int = int(board.get("cover", [0, 0, 0, 0, 0, 0, 0, 0])[point + (4 if is_enemy else 0)])
			widget.text = Geometry.POSITION_NAMES[point] + "\nEmpty" + (" / Cover " + str(cover_amount) if cover_amount > 0 else "")
			widget.modulate = Color("#506977")
			for style_name in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
				var empty := StyleBoxFlat.new()
				empty.bg_color = Color.TRANSPARENT
				empty.border_color = Color(.35,.55,.65,.4)
				empty.set_border_width_all(0)
				empty.set_corner_radius_all(5)
				widget.add_theme_stylebox_override(style_name,empty)
			add_child(widget)
			if not is_enemy: _wire_target(widget, 100 + point)
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
			wreck.pressed.connect(func(): unit_selected.emit(ship_id))
	for point in 4:
		var amount: int=int(board.get("cover",[0,0,0,0,0,0,0,0])[point+(4 if is_enemy else 0)])
		if amount<=0:continue
		var cloud=preload("res://scripts/visuals/defence_vfx.gd").new()
		cloud.configure(0,amount,is_enemy)
		add_child(cloud)
		cover_clouds[point]=cloud
	_arrange()
	_layout_clouds.call_deferred()


func _arrange() -> void:
	var w := minf(228 if large_cards else 140, size.x * 0.43)
	var h := 166.0 if large_cards else 128.0
	var coordinates := [Vector2(0.86 if not enemy else 0.14, 0.50), Vector2(0.5, 0.12), Vector2(0.5, 0.88), Vector2(0.14 if not enemy else 0.86, 0.5)]
	for point in widgets:
		widgets[point].size = Vector2(w, h)
		var centre: Vector2 = Vector2(size.x, size.y) * coordinates[point]
		widgets[point].position = (centre - widgets[point].size / 2).clamp(Vector2.ZERO, (size - widgets[point].size).max(Vector2.ZERO))
	var index := 0
	for wreck in wreck_widgets.values():
		wreck.position = Vector2(index * size.x / maxf(1, wreck_widgets.size()), size.y + 8)
		wreck.size = Vector2(size.x / maxf(1, wreck_widgets.size()) - 6, 48)
		index += 1
	_layout_clouds()
	queue_redraw()


func _draw() -> void:
	for link in Geometry.UNIT_LINKS:
		if widgets.has(link[0]) and widgets.has(link[1]):
			draw_line(widgets[link[0]].position + widgets[link[0]].size / 2, widgets[link[1]].position + widgets[link[1]].size / 2, Color("#345866"), 2, true)


func _wire_target(widget: Button, ship_id: int) -> void:
	if widget is Unit:
		if drop_check.is_valid():
			widget.tooltip_text += "\nDrag its own card here to repair, or an adjacent living ship's card to swap. Release to act immediately; this discards the dragged card."
		widget.set_meta("base_guard_text", widget.guard_label.text)
		widget.set_meta("base_guard_visible",widget.guard_label.visible)
	widget.set_meta("base_tooltip", widget.tooltip_text)
	var styles: Dictionary = {}
	for key in ["normal","hover","pressed","hover_pressed"]:
		if widget.has_theme_stylebox_override(key): styles[key] = widget.get_theme_stylebox(key)
	widget.set_meta("base_styles",styles)
	widget.set_drag_forwarding(Callable(), _can_drop_on_ship.bind(ship_id), _drop_on_ship.bind(ship_id))
	widget.mouse_exited.connect(func(): ship_drag_exited.emit(ship_id))


func target_widget(ship_id: int) -> Control:
	if ship_id >= 100: return widgets.get(ship_id - 100)
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
	var candidates: Array = range(snapshot.get("ships", []).size())
	for point in widgets:
		if snapshot.get("formation", []).size() == 4 and snapshot.formation[point] < 0: candidates.append(100 + int(point))
	for ship_id in candidates:
		var widget := target_widget(ship_id) as Button
		if widget == null:
			continue
		for key in ["normal", "hover", "pressed", "hover_pressed"]:
			if widget.get_meta("base_styles",{}).has(key): widget.add_theme_stylebox_override(key,widget.get_meta("base_styles")[key])
			else: widget.remove_theme_stylebox_override(key)
		widget.tooltip_text = str(widget.get_meta("base_tooltip", ""))
		if widget is Unit:
			widget.guard_label.text = str(widget.get_meta("base_guard_text", ""))
			widget.guard_label.visible=widget.get_meta("base_guard_visible",false)
		if not hints.has(ship_id) or (widget.get_meta("empty_slot",false) and not valid.has(ship_id)):
			continue
		widget.tooltip_text = str(hints[ship_id])
		var tint := Color("#8a535b")
		var fill := Color("#241d26")
		if valid.has(ship_id):
			tint = Color("#9ce6b7") if ship_id == actor else Color("#67bdd4")
			if widget is Unit:
				widget.guard_label.text = "REPAIR (discard 1 card)" if ship_id == actor else "SWAP (discard 1 card)"
				widget.guard_label.show()
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




func show_rule_preview(notes: Dictionary = {}, source: int = -999) -> void:
	var candidates: Array=[]
	for point in widgets: candidates.append({"widget":widgets[point],"id":widgets[point].get_meta("ship_index",100+int(point))})
	for id in wreck_widgets: candidates.append({"widget":wreck_widgets[id],"id":id})
	for entry in candidates:
		var widget: Button=entry.widget
		var id: int=entry.id
		if not widget.has_meta("rule_base_tooltip"):
			widget.set_meta("rule_base_tooltip",widget.tooltip_text)
			widget.set_meta("rule_base_tint",widget.modulate)
			var styles: Dictionary={}
			for style_name in ["normal","hover","pressed","hover_pressed"]:
				if widget.has_theme_stylebox_override(style_name): styles[style_name]=widget.get_theme_stylebox(style_name)
			widget.set_meta("rule_base_styles",styles)
		for state in ["normal","hover","pressed","hover_pressed"]:
			if widget.get_meta("rule_base_styles",{}).has(state): widget.add_theme_stylebox_override(state,widget.get_meta("rule_base_styles")[state])
			else: widget.remove_theme_stylebox_override(state)
		widget.tooltip_text=str(widget.get_meta("rule_base_tooltip",""))
		widget.modulate=widget.get_meta("rule_base_tint",Color.WHITE)
		for child in widget.get_children():
			if child.get_meta("rule_preview",false): widget.remove_child(child); child.queue_free()
		if not notes.has(id) and id!=source: continue
		widget.modulate=Color.WHITE
		var color:=Color("#f3b179") if id==source else (Color("#67bdd4") if str(notes.get(id,"")).begins_with("Click") else Color("#f0d18a"))
		for state in ["normal","hover","pressed","hover_pressed"]:
			var box:=StyleBoxFlat.new()
			box.bg_color=Color("#2b2d36")
			box.border_color=color
			box.set_border_width_all(3)
			box.set_corner_radius_all(5)
			widget.add_theme_stylebox_override(state,box)
		if notes.has(id):
			widget.tooltip_text+="\n"+str(notes[id])
			var label:=Label.new()
			label.set_meta("rule_preview",true)
			label.text=str(notes[id])
			label.add_theme_font_size_override("font_size",10)
			label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			label.position=Vector2(0,-32)
			label.size=Vector2(widget.size.x,30)
			label.modulate=color
			label.mouse_filter=Control.MOUSE_FILTER_IGNORE
			widget.add_child(label)

func _layout_clouds() -> void:
	for point in cover_clouds:
		var widget: Control=widgets[point]
		var cloud: Control=cover_clouds[point]
		cloud.position=widget.position+Vector2(8,22)
		cloud.size=Vector2(widget.size.x-16,maxf(30,widget.size.y-68))
