extends Button
## Shared card layout: type, title, top-right cost, discard crystals, ship border, rules.
const Icons = preload("res://scripts/keyword_icons.gd")
var labels: Dictionary = {}
var info: Dictionary = {}
var owner_info: Dictionary = {}
var drag_provider: Callable
var discard_choice := false:
	set(value):
		discard_choice=value
		queue_redraw()
var ship_color := Color("#91c8ad")

func _init() -> void:
	set_meta("plain_text",true)
	custom_minimum_size = Vector2(154,208)
	toggle_mode = true
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for entry in [["name",12],["owner",9],["positions",8],["rules",11],["numbers",12],["tags",9]]:
		var label := Label.new()
		if entry[0] in ["name","owner","numbers","tags"]: label.set_meta("plain_text",true)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",entry[1])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		labels[entry[0]] = label
	labels.name.max_lines_visible = 2
	labels.name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.numbers.hide()
	labels.tags.hide()
	resized.connect(_layout)

func configure(card: Dictionary, owner: Dictionary = {}) -> void:
	info = card.duplicate(true)
	if card.has("rules"):
		info["effect"] = "\n".join(card.rules.map(func(rule): return preload("res://scripts/rules/rule_registry.gd").rule_text(rule, str(owner.get("name", "")))))
	owner_info = owner.duplicate(true)
	ship_color = Color(owner.get("color","#91c8ad"))
	labels.name.text = card.get("name","Untitled card") if not str(card.get("name","")).strip_edges().is_empty() else "Untitled card"
	labels.owner.text = str(owner.get("name","Unassigned")).to_upper()
	labels.owner.modulate = ship_color
	labels.positions.text = card.get("ranks",", ".join(card.get("positions",[])))
	labels.rules.text = str(info.get("effect","")).replace(" [once per action]","")
	labels.numbers.text = "COST %d / PAYS %d" % [card.get("cost",0),card.get("pays",1)]
	labels.tags.text = card.get("type","")
	tooltip_text = labels.name.text + "\nShip: " + str(owner.get("name","Unassigned")) + "\n" + card.get("type","") + " / " + labels.numbers.text + "\n" + labels.positions.text + "\n" + info.get("effect","")
	for state in ["normal","hover","pressed","hover_pressed","focus","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#132b38").lightened(0.08 if state in ["hover","hover_pressed","pressed"] else 0.0)
		style.border_color = ship_color.lightened(0.18 if state == "focus" else 0.0)
		style.set_border_width_all(3)
		style.set_corner_radius_all(7)
		add_theme_stylebox_override(state,style)
	_layout()
	queue_redraw()

func _layout() -> void:
	if labels.is_empty(): return
	var wide := size.x >= 230
	labels.name.add_theme_font_size_override("font_size",17 if wide else 12)
	labels.rules.add_theme_font_size_override("font_size",16 if wide else 11)
	labels.name.position = Vector2(39,23)
	labels.name.size = Vector2(maxf(42,size.x-85),32)
	labels.owner.position = Vector2(9,size.y-16)
	labels.owner.size = Vector2(size.x-90,13)
	labels.positions.position = Vector2(size.x-76,size.y-16)
	labels.positions.size = Vector2(68,13)
	labels.rules.position = Vector2(10,64)
	labels.rules.size = Vector2(size.x-20,maxf(20,size.y-86))

func _draw() -> void:
	var frame := preload("res://scripts/art_assets.gd").texture("ui/card-frame.png")
	# The blank footer, reflected vertically, provides an ornate empty header.
	# No opaque badge mask can cover the brass frame or ship-coloured border.
	draw_set_transform(Vector2(0,60),0,Vector2(1,-1))
	draw_texture_rect_region(frame,Rect2(0,0,size.x,60),Rect2(0,1350,1024,186))
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect_region(frame,Rect2(0,60,size.x,maxf(1,size.y-80)),Rect2(0,350,1024,1000))
	draw_texture_rect_region(frame,Rect2(0,size.y-20,size.x,20),Rect2(0,1350,1024,186))
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color.TRANSPARENT
	outline.border_color = ship_color.lightened(.2 if button_pressed else 0)
	outline.set_border_width_all(3)
	outline.set_corner_radius_all(7)
	draw_style_box(outline,Rect2(Vector2.ZERO,size))
	var type_key := Icons.key(info.get("type","Support"))
	draw_texture_rect(Icons.texture(type_key),Rect2(8,10,25,25),false)
	var centre := Vector2(size.x-23,21)
	draw_circle(centre,16,Color("#091721"))
	draw_arc(centre,16,0,TAU,40,ship_color,2,true)
	var font := get_theme_default_font()
	var cost := str(int(info.get("cost",0)))
	draw_string(font,centre+Vector2(-font.get_string_size(cost,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x/2,7),cost,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	var count: int = int(info.get("pays",1))
	for i in mini(count,4):
		var x: float = size.x-23 + (i-(mini(count,4)-1)/2.0)*8
		var points := PackedVector2Array([Vector2(x,38),Vector2(x+4,44),Vector2(x,50),Vector2(x-4,44)])
		draw_colored_polygon(points,Color("#cb7af1"))
		draw_polyline(points+PackedVector2Array([points[0]]),Color("#572d71"),1,true)
	if count > 4: draw_string(font,Vector2(size.x-36,60),"×"+str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("#d8a8f5"))
	if discard_choice:
		# Hollow concentric strokes keep the art and rules readable through the halo.
		for ring in range(6,0,-1):
			var glow:=StyleBoxFlat.new()
			glow.draw_center=false
			glow.border_color=Color(1,.13,.22,.8*(1-float(ring)/8))
			glow.set_border_width_all(2)
			glow.set_corner_radius_all(6)
			var inset:=float(ring*2)
			draw_style_box(glow,Rect2(Vector2.ONE*inset,size-Vector2.ONE*inset*2))
	draw_line(Vector2(8,57),Vector2(size.x-8,57),ship_color.darkened(0.5),1,true)

func _get_tooltip(at_position: Vector2) -> String:
	if Rect2(5,5,32,38).has_point(at_position): return Icons.description(Icons.key(info.get("type","Support")))
	if Rect2(size.x-43,3,42,58).has_point(at_position): return "Mana cost: %d\nDiscard production: %d mana. Purple crystals show the amount produced." % [info.get("cost",0),info.get("pays",1)]
	return tooltip_text

func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or not drag_provider.is_valid(): return null
	var data: Variant = drag_provider.call()
	if not data is Dictionary or data.is_empty(): return null
	var preview := Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face = get_script().new()
	face.configure(info,owner_info)
	face.theme = theme
	face.position = Vector2(20,20)
	face.size = Vector2(154,208)
	face.scale = Vector2.ONE*0.75
	face.modulate.a = 0.8
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(face)
	set_drag_preview(preview)
	return data
