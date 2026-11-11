extends PanelContainer
## Read-only enemy behaviour presentation shared by reactions and intents.
const Rules = preload("res://scripts/rules/rule_registry.gd")
const Text = preload("res://scripts/keyword_text.gd")
var presentation: Dictionary = {}
var effect_rows: Array[PanelContainer] = []
var active_effect_index := -1
var scroll: ScrollContainer

func configure(kind: String, data: Dictionary) -> void:
	presentation = data.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0c202d")
	style.border_color = Color("#ff927f") if kind == "reaction_triggered" else Color("#e8bd77")
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	for side in ["left","right","top","bottom"]: style.set("content_margin_"+side,18)
	add_theme_stylebox_override("panel",style)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	scroll.add_child(column)
	var header := Label.new()
	header.set_meta("plain_text",true)
	header.text = "REACTION" if kind == "reaction_triggered" else "ENEMY INTENT"
	header.add_theme_font_size_override("font_size",15)
	header.modulate = style.border_color
	column.add_child(header)
	var owner_row:=HBoxContainer.new()
	column.add_child(owner_row)
	var portrait := preload("res://scripts/monster_portrait.gd").new()
	portrait.configure(data.get("owner_visual", {}), data.get("owner", -999), Vector2(72, 34))
	owner_row.add_child(portrait)
	var owner_label:=Label.new()
	owner_label.text=data.get("owner_name","Enemy")
	owner_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	owner_label.set_meta("plain_text",true)
	owner_label.add_theme_font_size_override("font_size",16)
	owner_row.add_child(owner_label)
	for pair in [[data.get("name","Enemy activity"),24],[data.get("stance_name",""),13]]:
		if str(pair[0]).is_empty(): continue
		var label := Label.new()
		label.set_meta("plain_text",true)
		label.text = pair[0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",pair[1])
		column.add_child(label)
	if kind == "reaction_triggered":
		if data.get("conditions",{}).get("kind") == "reaction_trigger" and not data.get("custom_trigger",false):
			var badge := preload("res://scripts/reaction_badge.gd").new()
			badge.configure(data.conditions, 64)
			badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			column.add_child(badge)
		else:
			var condition := Text.new()
			condition.fit_content = true
			condition.configure(Rules.reaction_condition_text(data.get("conditions",{"kind":"always"}),data.get("owner_name","")),16)
			column.add_child(condition)
	column.add_child(HSeparator.new())
	for effect in data.get("effects", []):
		var row := PanelContainer.new()
		column.add_child(row)
		var line := Text.new()
		line.fit_content = true
		line.configure(Rules.text("effect", effect, data.get("owner_name", "")), 20)
		row.add_child(line)
		effect_rows.append(row)
	if effect_rows.is_empty():
		var empty := Label.new()
		empty.text = "No additional effects."
		column.add_child(empty)
	highlight_effect(-1)
	_ignore_mouse(self)


func highlight_effect(index: int) -> void:
	active_effect_index = index if index >= 0 and index < effect_rows.size() else -1
	for i in effect_rows.size():
		var row := effect_rows[i]
		var active := i == active_effect_index
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#49382a") if active else Color.TRANSPARENT
		style.border_color = Color("#ffd09a")
		style.border_width_left = 3 if active else 0
		style.set_corner_radius_all(4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		row.add_theme_stylebox_override("panel", style)
		row.modulate = Color.WHITE if active or active_effect_index < 0 else Color("#92a3ad")
	if active_effect_index >= 0:
		scroll.ensure_control_visible.call_deferred(effect_rows[active_effect_index])


func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_PASS if node.has_meta("reaction_badge") else Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)
