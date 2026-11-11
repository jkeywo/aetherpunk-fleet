extends RichTextLabel
const Icons = preload("res://scripts/keyword_icons.gd")
var source_text := ""
var icon_keys: Array = []

func _init() -> void:
	set_meta("keyword_renderer",true)
	bbcode_enabled = false
	scroll_active = false
	selection_enabled = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true

func configure(value: String, font_size: int = 14, color: Color = Color.WHITE, alignment: int = HORIZONTAL_ALIGNMENT_LEFT, enemy_positions: bool = false, keep_words: bool = false) -> void:
	source_text = value
	icon_keys.clear()
	clear()
	add_theme_font_size_override("normal_font_size",font_size)
	add_theme_color_override("default_color",color)
	if alignment == HORIZONTAL_ALIGNMENT_CENTER: push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT: push_paragraph(HORIZONTAL_ALIGNMENT_RIGHT)
	var icon_size := font_size + (1 if keep_words else 3)
	for part in Icons.parts(value):
		if part.has("icon"):
			icon_keys.append(part.icon)
			add_image(Icons.texture(part.icon, enemy_positions),icon_size,icon_size,Color.WHITE,INLINE_ALIGNMENT_CENTER,Rect2(),part.icon,false,Icons.description(part.icon),0,0,"" if keep_words else part.text)
			if keep_words: add_text("\u00a0" + part.text)
		else: add_text(part.text)
	if alignment != HORIZONTAL_ALIGNMENT_LEFT: pop()
