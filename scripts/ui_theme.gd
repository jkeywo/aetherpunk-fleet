extends RefCounted

static func back_icon() -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 28 28"><path d="M16 6L8 14l8 8M8 14h14" fill="none" stroke="#fff2d5" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>')
	return ImageTexture.create_from_image(image)

static func make() -> Theme:
	var result := Theme.new()
	result.default_font_size = 15
	result.set_color("font_color", "Label", Color("#e7ecea"))
	result.set_font_size("normal_font_size", "RichTextLabel", 14)
	var normal := _style(Color("#132e3b"), Color("#3f6573"))
	var hover := _style(Color("#1c3e4d"), Color("#89b6bf"))
	var focus := _style(Color.TRANSPARENT, Color("#e8bd77"))
	result.set_stylebox("panel", "PanelContainer", _style(Color("#102632"), Color("#30505c")))
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, normal)
		result.set_stylebox("hover", type, hover)
		result.set_stylebox("pressed", type, hover)
		result.set_stylebox("focus", type, focus)
	result.set_stylebox("normal", "LineEdit", normal)
	result.set_stylebox("focus", "LineEdit", focus)
	result.set_stylebox("panel", "TabContainer", _style(Color("#0c202b"), Color("#30505c")))
	result.set_stylebox("tab_selected", "TabBar", hover)
	result.set_stylebox("tab_unselected", "TabBar", normal)
	result.set_stylebox("panel", "ItemList", normal)
	result.set_stylebox("selected", "ItemList", hover)
	preload("res://scripts/art_assets.gd").skin_theme(result)
	return result


static func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
