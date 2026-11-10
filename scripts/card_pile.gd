extends Button
## Native clickable piles with real card art; the draw order stays hidden.
const Art=preload("res://scripts/art_assets.gd")
const Face=preload("res://scripts/card_face.gd")
var face: Control
var is_discard := false
var count := 0
var top_signature := ""

func _init() -> void:
	set_meta("plain_text",true)
	clip_contents=false
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","hover_pressed","focus","disabled"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	resized.connect(_layout)

func show_cards(amount: int, card: Dictionary = {}, owner_data: Dictionary = {}) -> void:
	count=amount
	is_discard=name=="DiscardPile"
	if is_discard and not card.is_empty():
		if face==null:
			face=Face.new()
			face.custom_minimum_size=Vector2.ZERO
			face.mouse_filter=Control.MOUSE_FILTER_IGNORE
			face.toggle_mode=false
			add_child(face)
			move_child(face,0)
		var signature:=JSON.stringify(card)+str(owner_data.get("color",""))
		if signature!=top_signature:
			face.configure(card,owner_data)
			top_signature=signature
		face.show()
	elif face!=null:face.hide()
	_layout()
	queue_redraw()

func _layout() -> void:
	if face!=null:
		face.size=Vector2(154,208)
		face.scale=(size-Vector2(6,8))/face.size
		face.position=Vector2.ZERO

func _draw() -> void:
	var rect:=Rect2(Vector2.ZERO,size-Vector2(6,8))
	if count>1:
		for offset in [Vector2(6,8),Vector2(3,4)]:
			draw_style_box(_edge(Color("#172c34"),Color("#ad9564")),Rect2(offset,rect.size))
	if not is_discard or count>0:
		if not is_discard:draw_texture_rect(Art.texture("ui/card-back.png"),rect,false)
	else:
		draw_style_box(_edge(Color(.02,.05,.08,.4),Color(.7,.65,.5,.4)),rect)
		var icon=preload("res://scripts/keyword_icons.gd").texture("discard")
		draw_texture_rect(icon,Rect2(rect.size/2-Vector2(17,32),Vector2(34,34)),false,Color(1,1,1,.5))
	if is_hovered():draw_style_box(_edge(Color.TRANSPARENT,Color("#f1d18c")),rect)

func _edge(fill: Color, edge: Color) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style
