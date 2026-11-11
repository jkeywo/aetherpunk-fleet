extends Button
## Shared card layout: type, title, top-right cost, discard crystals, ship border, rules.
const Icons = preload("res://scripts/keyword_icons.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const KeywordText = preload("res://scripts/keyword_text.gd")
var labels: Dictionary = {}
var info: Dictionary = {}
var owner_info: Dictionary = {}
var drag_provider: Callable
var discard_choice := false:
	set(value):
		discard_choice=value
		queue_redraw()
var trigger_rules: Array=[]:
	set(value):
		trigger_rules=value
		queue_redraw()
var ship_color := Color("#91c8ad")
var resolving_rule_id := ""
var resolving_rule_rows: Dictionary = {}
var resolving_effect_rows: Dictionary = {}
var resolving_effect_index := -1
var rule_scroll: ScrollContainer

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
		info["effect"] = "\n".join(card.rules.map(func(rule): return Rules.rule_text(rule, str(owner.get("name", "")))))
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

func enable_rule_highlights() -> void:
	if info.get("rules", []).is_empty(): return
	labels.rules.hide()
	rule_scroll = ScrollContainer.new()
	rule_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(rule_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	rule_scroll.add_child(column)
	for rule in info.rules:
		var row := PanelContainer.new()
		column.add_child(row)
		var owner_name: String = owner_info.get("name", "")
		var effects: Array = rule.get("effects", [])
		if effects.size() <= 1:
			_add_rule_text(row, Rules.rule_text(rule, owner_name).replace(" [once per action]", ""))
		else:
			var lines := VBoxContainer.new()
			lines.add_theme_constant_override("separation", 3)
			row.add_child(lines)
			_add_rule_text(lines, Rules.rule_heading(rule, owner_name))
			var effect_rows: Array[PanelContainer] = []
			for effect in effects:
				var effect_row := PanelContainer.new()
				lines.add_child(effect_row)
				effect_row.add_theme_stylebox_override("panel", _effect_style(false))
				_add_rule_text(effect_row, Rules.text("effect", effect, owner_name))
				effect_rows.append(effect_row)
			resolving_effect_rows[rule.id] = effect_rows
			for modifier in rule.get("modifiers", []):
				_add_rule_text(lines, Rules.text("modifier", modifier, owner_name))
			var suffix := Rules.rule_suffix(rule).replace(" [once per action]", "").strip_edges()
			if not suffix.is_empty(): _add_rule_text(lines, suffix)
		resolving_rule_rows[rule.id] = row
	highlight_rule("")
	_layout()


func _add_rule_text(parent: Control, value: String) -> void:
	var text := KeywordText.new()
	text.fit_content = true
	text.configure(value, 15)
	parent.add_child(text)


func highlight_effect(index: int) -> void:
	var rows: Array = resolving_effect_rows.get(resolving_rule_id, [])
	resolving_effect_index = index if index >= 0 and index < rows.size() else -1
	for i in rows.size():
		var row: PanelContainer = rows[i]
		row.add_theme_stylebox_override("panel", _effect_style(i == resolving_effect_index))
	if resolving_effect_index >= 0:
		rule_scroll.ensure_control_visible.call_deferred(rows[resolving_effect_index])


func _effect_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#66502f") if active else Color.TRANSPARENT
	style.border_color = Color("#ffd18a")
	style.border_width_left = 3 if active else 0
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style

func highlight_rule(rule_id: String) -> void:
	highlight_effect(-1)
	resolving_rule_id = rule_id if resolving_rule_rows.has(rule_id) else ""
	for id in resolving_rule_rows:
		var row: PanelContainer = resolving_rule_rows[id]
		var active: bool = id == resolving_rule_id
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#344737") if active else Color.TRANSPARENT
		style.border_color = Color("#a6e6b8")
		style.border_width_left = 3 if active else 0
		style.set_corner_radius_all(4)
		style.content_margin_left = 7
		style.content_margin_right = 7
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		row.add_theme_stylebox_override("panel", style)
		row.modulate = Color.WHITE if active or resolving_rule_id.is_empty() else Color("#92a3ad")
	if not resolving_rule_id.is_empty():
		rule_scroll.ensure_control_visible.call_deferred(resolving_rule_rows[resolving_rule_id])


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
	if rule_scroll != null:
		rule_scroll.position = labels.rules.position
		rule_scroll.size = labels.rules.size

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
	if not trigger_rules.is_empty() and not discard_choice:
		var trigger_style:=StyleBoxFlat.new()
		trigger_style.draw_center=false
		trigger_style.border_color=Color("#97f1cf")
		trigger_style.set_border_width_all(3)
		trigger_style.set_corner_radius_all(7)
		draw_style_box(trigger_style,Rect2(Vector2(4,4),size-Vector2(8,8)))
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
	return tooltip_text+("\nWould trigger:\n"+"\n".join(trigger_rules) if not trigger_rules.is_empty() else "")

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
