extends Control
signal card_selected(uid: int)
signal card_hovered(uid: int)
signal card_exited(uid: int)
signal reaction_selected(key: String)
const Catalog = preload("res://scripts/content_catalog.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
var buttons: Array = []
var row: Array = []
var selected := -1
var reaction_buttons: Dictionary={}
var trigger_keys: Array=[]


func _ready() -> void:
	resized.connect(_arrange)


func configure(cards: Array, stunned: Dictionary = {}, highlighted: int = -1) -> void:
	row = cards.duplicate(true)
	selected = highlighted
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	reaction_buttons.clear()
	trigger_keys.clear()
	for index in (1 if row.size() == 1 and size.x < 400 else 3):
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.clip_contents = true
		for state in ["normal","hover","pressed","hover_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("#102632")
			style.border_color = Color("#5a7783")
			style.set_border_width_all(1)
			style.set_corner_radius_all(5)
			button.add_theme_stylebox_override(state,style)
		button.add_theme_font_size_override("font_size", 11)
		add_child(button)
		buttons.append(button)
		if index >= row.size():
			button.text = "ENEMY ROW: Empty\nNo additional physical cards available"
			button.disabled = true
			continue
		var stance: Dictionary = row[index]
		var lines: Array = []
		for reaction in stance.get("reactions", []):
			var key := str(stance.uid) + "/" + str(reaction.id)
			lines.append(("STUNNED: " if stunned.has(key) else "React: ") + Rules.reaction_condition_text(reaction.conditions, stance.get("owner_name", "")) + " → " + Catalog.effects_text(reaction.effects, stance.get("owner_name", "")))
		lines.append("Act: " + Catalog.effects_text(stance.get("effects", []), stance.get("owner_name", "")))
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 8)
		button.add_child(margin)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(column)
		var heading := Label.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.add_theme_font_size_override("font_size", 11)
		heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		heading.text = "%d: %s · %s" % [index + 1, stance.get("owner_name", "Enemy"), stance.name]
		column.add_child(heading)
		for reaction in stance.get("reactions",[]):
			var react := Button.new()
			var key := str(stance.uid)+"/"+str(reaction.id)
			react.text=("Stunned: " if stunned.has(key) else "Reaction: ")+Rules.reaction_condition_text(reaction.conditions,stance.get("owner_name", ""))+" → "+Catalog.effects_text(reaction.effects, stance.get("owner_name", ""))
			react.add_theme_font_size_override("font_size",10)
			react.clip_text=true
			for state in ["normal","hover","pressed","hover_pressed"]:
				var style := StyleBoxFlat.new()
				style.bg_color = Color("#152e3b")
				style.border_color = Color("#3d6476")
				style.set_border_width_all(1)
				style.set_corner_radius_all(3)
				react.add_theme_stylebox_override(state,style)
			react.tooltip_text=reaction.name+"\n"+Rules.reaction_condition_text(reaction.conditions,stance.get("owner_name", ""))+" → "+Catalog.effects_text(reaction.effects, stance.get("owner_name", ""))
			react.set_meta("base_tooltip",react.tooltip_text)
			reaction_buttons[key]=react
			column.add_child(react)
			react.pressed.connect(func(): reaction_selected.emit(key))
			react.mouse_entered.connect(func(): card_hovered.emit(stance.uid))
			react.mouse_exited.connect(func(): card_exited.emit(stance.uid))
		var body := Label.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_font_size_override("font_size", 10)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.max_lines_visible = 5
		body.text = "Intent: " + Catalog.effects_text(stance.get("effects",[]), stance.get("owner_name", ""))
		column.add_child(body)
		button.tooltip_text = "%s: %s\n" % [stance.get("owner_name", "Enemy"), stance.name]
		for reaction in stance.get("reactions", []):
			button.tooltip_text += reaction.name + " [" + reaction.get("category", "") + "]\n" + Rules.reaction_condition_text(reaction.conditions, stance.get("owner_name", "")) + " → " + Catalog.effects_text(reaction.effects, stance.get("owner_name", "")) + "\n"
		button.tooltip_text += "Enemy phase: " + Catalog.effects_text(stance.get("effects", []), stance.get("owner_name", "")) + "\nReplacements remain hidden until revealed."
		button.set_meta("stance_uid", stance.uid)
		button.pressed.connect(func(): card_selected.emit(stance.uid))
		button.mouse_entered.connect(func(): card_hovered.emit(stance.uid))
		button.mouse_exited.connect(func(): card_exited.emit(stance.uid))
		if highlighted == stance.uid: button.modulate = Color("#f6d491")
	_arrange()


func _arrange() -> void:
	for index in buttons.size():
		buttons[index].position = Vector2(index * size.x / maxf(1, buttons.size()), 0)
		buttons[index].size = Vector2(size.x / maxf(1, buttons.size()) - 5, size.y)

func show_trigger_preview(keys: Array = [], provisional: bool = false) -> void:
	trigger_keys=keys.duplicate()
	for key in reaction_buttons:
		var button: Button=reaction_buttons[key]
		var active: bool=keys.has(key)
		button.tooltip_text=str(button.get_meta("base_tooltip",""))+("\nWould trigger with this action; complete payment/targets." if provisional else "\nWill trigger with this action.") if active else str(button.get_meta("base_tooltip",""))
		for state in ["normal","hover","pressed","hover_pressed"]:
			var style:=StyleBoxFlat.new()
			style.bg_color=Color("#4a3029") if active else Color("#152e3b")
			style.border_color=Color("#ffbd78") if active else Color("#3d6476")
			style.set_border_width_all(3 if active else 1)
			style.set_corner_radius_all(3)
			button.add_theme_stylebox_override(state,style)
		button.set_meta("trigger_preview",active)
