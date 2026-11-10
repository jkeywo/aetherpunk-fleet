extends Button
## The same card face is used by the hand, hover inspector, and live editor.
var labels: Dictionary = {}
var info: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(154, 208)
	toggle_mode = true
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	for spec in [["numbers", 14], ["owner", 11], ["name", 18], ["positions", 11], ["rules", 13], ["tags", 11]]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", spec[1])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if spec[0] == "rules":
			label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(label)
		labels[spec[0]] = label
	_ignore(margin)


func _ignore(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore(child)


func configure(card: Dictionary, owner: Dictionary = {}) -> void:
	info = card.duplicate(true)
	labels.numbers.text = "COST %d     PAYS %d" % [card.get("cost", 0), card.get("pays", 1)]
	labels.numbers.modulate = Color("#e8bd77")
	labels.owner.text = str(owner.get("name", "Unassigned")).to_upper()
	labels.owner.modulate = Color(owner.get("color", "#91c8ad"))
	labels.name.text = card.get("name", "Untitled card") if not str(card.get("name", "")).strip_edges().is_empty() else "Untitled card"
	labels.positions.text = card.get("ranks", ", ".join(card.get("positions", [])))
	labels.rules.text = card.get("effect", "")
	labels.tags.text = card.get("tags", "") if card.get("tags") is String else " · ".join(card.get("tags", []))
	labels.tags.modulate = Color("#88b5c7")
	tooltip_text = labels.name.text + "\n" + labels.positions.text + "\n" + labels.rules.text
