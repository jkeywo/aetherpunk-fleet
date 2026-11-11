extends Control
signal ship_drag_hovered(ship_id: int, data: Variant)
signal ship_drag_exited(ship_id: int)
signal ship_dropped(ship_id: int, data: Variant)
signal position_selected(point: int)
signal unit_selected(id: int)
signal unit_hovered(id: int)
signal unit_exited(id: int)
const Geometry = preload("res://scripts/battle_geometry.gd")
const Catalog = preload("res://scripts/content_catalog.gd")
const Unit = preload("res://scripts/unit_view.gd")
const Rig = preload("res://scripts/rig_view.gd")
const KeywordText = preload("res://scripts/keyword_text.gd")
const BASIC_CIRCLE_SIZE := 84.0
var widgets: Dictionary = {}
var wreck_widgets: Dictionary = {}
var basic_indicators: Dictionary = {}
var large_cards := false
var large_unit_height := 166.0
var drop_check: Callable
var enemy := false
var snapshot: Dictionary = {}
var cover_clouds: Dictionary={}
var shared_rig: Control


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
	basic_indicators.clear()
	cover_clouds.clear()
	shared_rig = null
	if enemy:
		for data in board.get("enemies", []):
			var part: String = data.get("shared_rig_part", "")
			if part.is_empty(): continue
			if shared_rig == null:
				shared_rig = Rig.new()
				add_child(shared_rig)
				shared_rig.configure_data(data, true)
			if shared_rig.rig_node != null and data.hull <= 0:
				shared_rig.rig_node.part_tints[part] = Color(.43, .42, .38, .68)
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
			_wire_target(widget, unit_id)
		else:
			widget = Button.new()
			widget.set_meta("empty_slot",true)
			widget.set_meta("enemy_positions", is_enemy)
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
		for ship_id in board.get("ships", []).size():
			var ship: Dictionary = board.ships[ship_id]
			if not ship.get("disabled", int(ship.get("hull", 1)) <= 0):
				continue
			var wreck := Button.new()
			wreck.add_theme_font_size_override("font_size", 12)
			wreck.clip_text = true
			wreck.text = "%s / DISABLED\n%d hull" % [ship.name, ship.hull]
			wreck.tooltip_text = "%s is disabled at %d hull. Repair it to %d hull to rejoin the formation." % [ship.name, ship.hull, Catalog.REVIVED_HULL]
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
	if shared_rig != null:
		shared_rig.position = Vector2(5, 0)
		shared_rig.size = size - Vector2(10, 0)
	var w := minf(228 if large_cards else 140, size.x * 0.43)
	var h := large_unit_height if large_cards else 128.0
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
	for id in basic_indicators:
		_position_basic_indicator(id, basic_indicators[id])
	queue_redraw()


func _draw() -> void:
	if shared_rig != null: return
	for link in Geometry.UNIT_LINKS:
		if widgets.has(link[0]) and widgets.has(link[1]):
			draw_line(widgets[link[0]].position + widgets[link[0]].size / 2, widgets[link[1]].position + widgets[link[1]].size / 2, Color("#345866"), 2, true)


func shared_part_point(part: String) -> Vector2:
	return shared_rig.marker_global(part)


func flash_shared_part(part: String, duration: float) -> void:
	if shared_rig == null or shared_rig.rig_node == null: return
	var rig: Node2D = shared_rig.rig_node
	var resting: Color = rig.part_tints.get(part, Color.WHITE)
	rig.part_tints[part] = Color("#ff5050")
	var tween := rig.create_tween()
	tween.tween_method(func(tint: Color): rig.part_tints[part] = tint, Color("#ff5050"), resting, duration)


func _wire_target(widget: Button, ship_id: int) -> void:
	if widget is Unit:
		if drop_check.is_valid():
			if ship_id < 0:
				widget.tooltip_text += "\nDrop a ship card here to attack with that ship’s weapon. Discards the card."
			else:
				widget.tooltip_text += "\nDrag its own card here to repair, or an adjacent living ship's card to swap. Release to act immediately; this discards the dragged card."
	widget.set_meta("base_tooltip", widget.tooltip_text)
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


func show_basic_targets(previews: Dictionary = {}, hovered: int = -999) -> void:
	for indicator in basic_indicators.values():
		remove_child(indicator)
		indicator.queue_free()
	basic_indicators.clear()
	var candidates: Array = wreck_widgets.keys()
	for point in widgets:
		var widget: Button = widgets[point]
		if widget.has_meta("ship_index"): candidates.append(widget.get_meta("ship_index"))
		elif not enemy: candidates.append(100 + int(point))
	for id in candidates:
		var widget := target_widget(id) as Button
		if widget == null: continue
		var preview: Dictionary = previews.get(id, {})
		widget.tooltip_text = preview.get("text", widget.get_meta("base_tooltip", ""))
		if not preview.get("ok", false): continue
		var circle := Panel.new()
		circle.name = "BasicActionCircle"
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		circle.size = Vector2.ONE * BASIC_CIRCLE_SIZE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#132b38")
		style.border_color = Color("#e8bd77") if id == hovered else Color("#67bdd4")
		style.set_border_width_all(3 if id == hovered else 2)
		style.set_corner_radius_all(roundi(BASIC_CIRCLE_SIZE / 2))
		circle.add_theme_stylebox_override("panel", style)
		add_child(circle)
		basic_indicators[id] = circle
		_position_basic_indicator(id, circle)
		var label := KeywordText.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.configure(preview.indicator, 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false, true)
		circle.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _position_basic_indicator(id: int, circle: Control) -> void:
	var widget: Control = target_widget(id)
	if widget != null:
		circle.position = widget.position + (widget.size - circle.size) / 2.0




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
