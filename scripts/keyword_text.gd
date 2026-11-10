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

func configure(value: String, font_size: int = 14, color: Color = Color.WHITE, alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	source_text = value
	icon_keys.clear()
	clear()
	add_theme_font_size_override("normal_font_size",font_size)
	add_theme_color_override("default_color",color)
	if alignment == HORIZONTAL_ALIGNMENT_CENTER: push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT: push_paragraph(HORIZONTAL_ALIGNMENT_RIGHT)
	for part in Icons.parts(value):
		if part.has("icon"):
			icon_keys.append(part.icon)
			add_image(Icons.texture(part.icon),font_size+3,font_size+3,Color.WHITE,INLINE_ALIGNMENT_CENTER,Rect2(),part.icon,false,Icons.description(part.icon),0,0,part.text)
		else: add_text(part.text)
	if alignment != HORIZONTAL_ALIGNMENT_LEFT: pop()
