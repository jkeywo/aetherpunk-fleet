extends Button
## Compact unit presentation shared by battle diamonds and editor previews.
var name_label: Label
var hull_label: Label
var guard_label: Label
var resource_label: Label
var cover_label: Label
var bar: ProgressBar
var art: Control
var shield_fx: Control
var trigger_badge: Label
var predicted_rules: Array=[]
var info_column: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(118, 82)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var column := VBoxContainer.new()
	info_column = column
	resized.connect(_art_layout)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 8
	column.offset_top = 4
	column.offset_right = -8
	column.offset_bottom = -4
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	name_label = Label.new()
	name_label.set_meta("plain_text",true)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_outline_color",Color("#08151f"))
	name_label.add_theme_constant_override("outline_size",4)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	art = preload("res://scripts/rig_view.gd").new()
	art.custom_minimum_size.y = 36
	column.add_child(art)
	hull_label = Label.new()
	hull_label.add_theme_font_size_override("font_size", 10)
	hull_label.set_meta("plain_text",true)
	hull_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hull_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	hull_label.add_theme_font_size_override("font_size",12)
	hull_label.add_theme_color_override("font_outline_color",Color("#08151f"))
	hull_label.add_theme_constant_override("outline_size",4)
	bar = ProgressBar.new()
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#78b7aa")
	fill.set_corner_radius_all(3)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#07161e")
	background.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 19
	column.add_child(bar)
	bar.add_child(hull_label)
	hull_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.value_changed.connect(func(value):hull_label.text="%d / %d" % [roundi(value),roundi(bar.max_value)])
	guard_label = Label.new()
	guard_label.add_theme_font_size_override("font_size", 10)
	guard_label.modulate = Color("#8bd8ff")
	column.add_child(guard_label)
	resource_label=Label.new()
	resource_label.set_meta("plain_text",true)
	resource_label.add_theme_font_size_override("font_size",10)
	column.add_child(resource_label)
	cover_label=Label.new()
	cover_label.add_theme_font_size_override("font_size",10)
	column.add_child(cover_label)
	for child in column.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_fx=preload("res://scripts/visuals/defence_vfx.gd").new()
	add_child(shield_fx)
	art.resized.connect(_defence_layout)
	column.resized.connect(_defence_layout)
	trigger_badge=Label.new()
	trigger_badge.set_meta("plain_text",true)
	trigger_badge.text="◆ TRIGGER"
	trigger_badge.add_theme_font_size_override("font_size",9)
	trigger_badge.modulate=Color("#97f1cf")
	trigger_badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
	trigger_badge.position=Vector2(0,-15)
	add_child(trigger_badge)
	trigger_badge.hide()


func configure(data: Dictionary, enemy: bool = false) -> void:
	name_label.text = data.get("name", "Unit")
	var shared_part: String = data.get("shared_rig_part", "")
	set_meta("shared_rig_part", shared_part)
	if shared_part.is_empty():
		art.configure_data(data, enemy)
	else:
		art.self_modulate.a = 0.0
	for state_name in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1,1,1,0)
		style.border_color = Color(data.get("color", "#b38883")) if not enemy else Color("#a47c79")
		style.set_border_width_all(0)
		style.set_corner_radius_all(5)
		add_theme_stylebox_override(state_name,style)
	_art_layout()
	var maximum: int = int(data.get("max_hull", data.get("hull", 1)))
	var hull: int = int(data.get("hull", maximum))
	hull_label.text = "%d / %d" % [hull, maximum]
	bar.max_value = maxi(1, maximum)
	bar.value = hull
	var weapon: Dictionary = data.get("weapon", {"damage": 0, "range": "Long"})
	guard_label.text="Shields %d" % data.get("guard",0)
	guard_label.visible=int(data.get("guard",0))>0
	shield_fx.configure(int(data.get("guard",0)),0,enemy)
	resource_label.visible=not enemy
	resource_label.text="%s %d/%d" % [data.get("resource_name","Charge"),data.get("resource",0),data.get("resource_capacity",6)] if not enemy else ""
	cover_label.hide()
	_art_layout()
	name_label.modulate = Color("#ffb0a0") if enemy else Color(data.get("color", "#91c8ad"))
	tooltip_text = "%s\nHull %d / %d\n%s" % [name_label.text, hull, maximum, data.get("role", "Leviathan")]
	tooltip_text += "\nArmour %d" % data.get("armour",0)
	if int(data.get("guard",0))>0:tooltip_text+="\nShields %d" % data.guard
	tooltip_text+="\nWeapon %d %s" % [weapon.damage,weapon.range]
	if enemy: tooltip_text += "\nDefault if not activated: " + data.get("default_text", "None")
	else:
		tooltip_text += "\nLevel %d / Captain %s\n%s %d/%d" % [data.get("level", 1), data.get("captain", {}).get("name", "Unassigned"), data.get("resource_name", "Charge"), data.get("resource", 0), data.get("resource_capacity", 6)]
		var mechanism: String = data.get("mechanic_text", "")
		if mechanism.is_empty() and data.get("resource") is Dictionary:
			mechanism = "\n".join(data.resource.get("rules", []).map(func(rule): return preload("res://scripts/rules/rule_registry.gd").rule_text(rule, data.name)))
		tooltip_text += "\n\nUnique mechanic / " + str(data.get("resource_name", "Charge")) + "\n" + (mechanism if not mechanism.is_empty() else "No personal-resource rules configured.") + "\nResources persist between rounds; defeat resets them to zero."


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var label:=preload("res://scripts/keyword_text.gd").new()
	label.custom_minimum_size.x=440
	label.fit_content=true
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.configure(for_text,13)
	margin.add_child(label)
	return panel


func _art_layout() -> void:
	if art == null or info_column == null: return
	var footer := float(get_meta("footer_space",0))
	info_column.offset_bottom = -4-footer
	art.custom_minimum_size.y = maxf(28,size.y-40-footer-(12 if resource_label.visible else 0)-(12 if guard_label.visible else 0)-(12 if cover_label.visible else 0))
	_defence_layout.call_deferred()

func set_cover(amount: int) -> void:
	cover_label.text="Cover %d" % amount
	cover_label.visible=amount>0
	_art_layout()

func _defence_layout() -> void:
	if shield_fx==null or art==null:return
	shield_fx.position=info_column.position+art.position
	shield_fx.size=art.size

func show_trigger_preview(rules: Array = [], hovered_owner: bool = false) -> void:
	predicted_rules=rules.duplicate()
	trigger_badge.visible=not rules.is_empty()
	trigger_badge.tooltip_text="\n".join(rules)
	if is_instance_valid(art.rig_node):
		art.rig_node.set_outline(hovered_owner or not rules.is_empty())

func _get_tooltip(_at_position: Vector2) -> String:
	return tooltip_text+("\n\nWould trigger:\n"+"\n".join(predicted_rules) if not predicted_rules.is_empty() else "")
