extends Control
signal slot_selected(slot: int)
const Geometry = preload("res://scripts/battle_geometry.gd")
var buttons: Array = []
var expanded := false
var selected := -1
var contents: Array = []
var card_data: Dictionary = {}


func _ready() -> void:
	resized.connect(_arrange)


func configure(circle: Array, is_expanded: bool, cards: Dictionary, used: Dictionary = {}, selected_slot: int = -1, contributors: Array = []) -> void:
	expanded = is_expanded
	selected = selected_slot
	contents = circle.duplicate()
	card_data = cards
	if buttons.is_empty():
		for slot in 9:
			var button := Button.new()
			button.add_theme_font_size_override("font_size", 11)
			button.clip_text = true
			button.pressed.connect(func(): slot_selected.emit(slot))
			add_child(button)
			buttons.append(button)
	for slot in 9:
		var uid: int = circle[slot]
		var locked: bool = slot >= 4 and not expanded
		var button: Button = buttons[slot]
		button.disabled = locked
		button.text = "Locked" if locked else Geometry.SLOT_NAMES[slot] + "\n+"
		button.modulate = Color("#3b4859") if locked else Color.WHITE
		button.tooltip_text = Geometry.SLOT_NAMES[slot]
		if uid >= 0 and cards.has(uid):
			var card: Dictionary = cards[uid]
			var count := 0
			for key in used:
				if str(key).begins_with(str(uid) + "/"):
					count += 1
			button.text = card.name + ("\n◆ %d used" % count if count > 0 else "\nIn play")
			button.tooltip_text = card.name + "\n" + card.get("effect", "")
			button.modulate = Color("#b7d2e6")
		if slot == selected:
			button.modulate = Color("#f6d491")
		elif contributors.has(uid):
			button.modulate = Color("#b3e6bb")
		elif selected >= 0 and Geometry.neighbours(selected, expanded).has(slot) and uid >= 0:
			button.modulate = Color("#d6adee")
	_arrange()


func _arrange() -> void:
	var cell := Vector2(size.x / 3.0, size.y / 3.0)
	for slot in buttons.size():
		buttons[slot].position = Geometry.CIRCLE_POINTS[slot] * cell + Vector2(4, 4)
		buttons[slot].size = cell - Vector2(8, 8)
	queue_redraw()


func _draw() -> void:
	var cell := Vector2(size.x / 3.0, size.y / 3.0)
	var links: Array = Geometry.BASE_LINKS.duplicate()
	if expanded:
		links.append_array(Geometry.EXTRA_LINKS)
	for link in links:
		var tint := Color("#9a61b8")
		if selected >= 0 and link.has(selected):
			tint = Color("#e8bd77")
		draw_line((Geometry.CIRCLE_POINTS[link[0]] + Vector2.ONE / 2) * cell, (Geometry.CIRCLE_POINTS[link[1]] + Vector2.ONE / 2) * cell, tint, 2, true)
