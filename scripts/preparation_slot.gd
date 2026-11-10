extends PanelContainer
## A framed drag surface; only the small information control is a button.
signal info_requested
var label_text := ""
var name_label: Label
var subtitle_label: Label
var information: Button
var base_color := Color("#627f8a")

static func info_button() -> Button:
	var button := Button.new()
	button.text = "i"
	button.set_meta("plain_text", true)
	button.custom_minimum_size = Vector2(32,32)
	button.add_theme_font_size_override("font_size",18)
	for state in ["normal","hover","pressed","hover_pressed","focus","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#173544") if state in ["hover","pressed","hover_pressed"] else Color("#081924")
		style.border_color = Color("#f1d69b")
		style.set_border_width_all(2)
		style.set_corner_radius_all(30)
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(state,Color.WHITE)
	return button

func configure(title: String, subtitle: String, portrait_id: String = "", color: Color = Color("#627f8a"), show_info: bool = true) -> void:
	label_text = title
	base_color = color
	set_meta("drag_label",title)
	custom_minimum_size = Vector2(228,72)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_highlight(false)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",8)
	margin.add_child(row)
	if not portrait_id.is_empty():
		var portrait := preload("res://scripts/art_assets.gd").portrait_view(portrait_id,Vector2(42,58))
		if portrait.texture != null:
			var crop := AtlasTexture.new()
			crop.atlas = portrait.texture
			crop.region = Rect2(0,0,portrait.texture.get_width(),mini(760,portrait.texture.get_height()))
			portrait.texture = crop
		portrait.custom_minimum_size = Vector2(42,58)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	name_label = Label.new()
	name_label.set_meta("plain_text",true)
	name_label.text = title
	name_label.add_theme_font_size_override("font_size",13)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	subtitle_label = Label.new()
	subtitle_label.set_meta("plain_text",true)
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size",11)
	subtitle_label.modulate = Color("#b7ced6")
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(subtitle_label)
	if show_info:
		information = info_button()
		information.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		information.tooltip_text = "Details for " + title
		row.add_child(information)
		information.pressed.connect(func(): info_requested.emit())

func set_highlight(active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#214b50") if active else Color("#0b202b")
	style.border_color = Color("#b6f2d3") if active else base_color
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(9)
	add_theme_stylebox_override("panel",style)
