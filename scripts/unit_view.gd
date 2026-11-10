extends Button
## Compact unit presentation shared by battle diamonds and editor previews.
var name_label: Label
var hull_label: Label
var guard_label: Label
var bar: ProgressBar
var art: Control


func _init() -> void:
	custom_minimum_size = Vector2(142, 82)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 8
	column.offset_top = 4
	column.offset_right = -8
	column.offset_bottom = -4
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	hull_label = Label.new()
	hull_label.add_theme_font_size_override("font_size", 11)
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
	guard_label.add_theme_font_size_override("font_size", 9)
	guard_label.modulate = Color("#8bd8ff")
	column.add_child(guard_label)
	for child in column.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(data: Dictionary, enemy: bool = false) -> void:
	name_label.text = data.get("name", "Unit")
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
	else: tooltip_text += "\nLevel %d / Captain %s\n%s %d/%d" % [data.get("level", 1), data.get("captain", {}).get("name", "Unassigned"), data.get("resource_name", "Charge"), data.get("resource", 0), data.get("resource_capacity", 6)]
