extends PanelContainer
const Catalog = preload("res://scripts/content_catalog.gd")
var title: Label
var rules: Label


func _init() -> void:
	var column := VBoxContainer.new()
	add_child(column)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 15)
	title.modulate = Color("#efba84")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	rules = Label.new()
	rules.add_theme_font_size_override("font_size", 11)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.max_lines_visible = 3
	column.add_child(rules)
	mouse_filter = Control.MOUSE_FILTER_PASS


func configure(stance: Dictionary) -> void:
	title.text = "STANCE / " + stance.get("name", "Untitled")
	var lines: Array = []
	for rule in stance.get("reactions", []):
		lines.append(rule.name + ": " + Catalog.trigger_text(rule.trigger) + " → " + Catalog.effects_text(rule.effects))
	lines.append("Enemy phase: " + Catalog.effects_text(stance.get("effects", [])))
	rules.text = "\n".join(lines)
	tooltip_text = title.text + "\n" + rules.text + "\nNext stance is hidden."
