extends Button
## Compact unit presentation shared by battle diamonds and editor previews.
var name_label: Label
var hull_label: Label
var guard_label: Label
var bar: ProgressBar
var art: Control
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
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	art = preload("res://scripts/rig_view.gd").new()
	art.custom_minimum_size.y = 36
	column.add_child(art)
	hull_label = Label.new()
	hull_label.add_theme_font_size_override("font_size", 10)
	column.add_child(hull_label)
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
	bar.custom_minimum_size.y = 5
	column.add_child(bar)
	guard_label = Label.new()
	guard_label.add_theme_font_size_override("font_size", 8)
	guard_label.modulate = Color("#8bd8ff")
	column.add_child(guard_label)
	for child in column.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(data: Dictionary, enemy: bool = false) -> void:
	name_label.text = data.get("name", "Unit")
	art.configure(str(data.get("id", "")), enemy)
	for state_name in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(.035,.075,.11,.65 if state_name == "normal" else .85)
		style.border_color = Color(data.get("color", "#b38883")) if not enemy else Color("#a47c79")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		add_theme_stylebox_override(state_name,style)
	_art_layout()
	var maximum: int = int(data.get("max_hull", data.get("hull", 1)))
	var hull: int = int(data.get("hull", maximum))
	hull_label.text = "HULL %d / %d" % [hull, maximum]
	bar.max_value = maxi(1, maximum)
	bar.value = hull
	var weapon: Dictionary = data.get("weapon", {"damage": 0, "range": "Long"})
	guard_label.text = "SH %d / A%d / W%d %s" % [data.get("guard", 0), data.get("armour", 0), weapon.damage, weapon.range]
	if not enemy: guard_label.text += "\n%s %d/%d" % [data.get("resource_name", "Charge"), data.get("resource", 0), data.get("resource_capacity", 6)]
	else: guard_label.text += "\n%d row activation(s)" % data.get("row_activations", 0)
	name_label.modulate = Color("#ffb0a0") if enemy else Color(data.get("color", "#91c8ad"))
	tooltip_text = "%s\nHull %d / %d\n%s" % [name_label.text, hull, maximum, data.get("role", "Leviathan")]
	tooltip_text += "\nArmour %d / Shields %d\nWeapon %d %s" % [data.get("armour", 0), data.get("guard", 0), weapon.damage, weapon.range]
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
	var label := Label.new()
	label.set_meta("plain_text", true)
	label.custom_minimum_size.x = 440
	label.size.x = 440
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.text = for_text
	margin.add_child(label)
	return panel


func _art_layout() -> void:
	if art == null or info_column == null: return
	var footer := float(get_meta("footer_space",0))
	info_column.offset_bottom = -4-footer
	art.custom_minimum_size.y = maxf(24,size.y-70-footer)
