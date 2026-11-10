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
	column.add_theme_constant_override("separation", 1)
	add_child(column)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	hull_label = Label.new()
	hull_label.add_theme_font_size_override("font_size", 12)
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
	bar.custom_minimum_size.y = 7
	column.add_child(bar)
	guard_label = Label.new()
	guard_label.add_theme_font_size_override("font_size", 11)
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
	guard_label.text = ("LEVIATHAN" if enemy else str(data.get("role", "SHIP"))) + "  /  GUARD %d" % int(data.get("guard", 0))
	name_label.modulate = Color("#ffb0a0") if enemy else Color(data.get("color", "#91c8ad"))
	tooltip_text = "%s\nHull %d / %d\n%s" % [name_label.text, hull, maximum, data.get("role", "Leviathan")]
