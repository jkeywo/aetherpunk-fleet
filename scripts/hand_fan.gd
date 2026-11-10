extends Control
var selected_uid := -2


func _ready() -> void:
	resized.connect(arrange)


func arrange() -> void:
	var count := get_child_count()
	if count == 0:
		return
	var width := 154.0
	var spread := minf(143, maxf(24, (size.x - width) / maxf(1, count - 1)))
	for index in count:
		var card: Control = get_child(index)
		var offset: float = index - (count - 1) / 2.0
		card.size = Vector2(width, 208)
		card.pivot_offset = card.size / 2
		card.position = Vector2(size.x / 2 - width / 2 + offset * spread, 5 + absf(offset) * 4)
		card.rotation = offset * 0.025
		card.z_index = index
		if card.get_meta("uid", -3) == selected_uid:
			card.position.y -= 13


func hover(card: Control, enabled: bool) -> void:
	arrange()
	if enabled and is_instance_valid(card):
		card.position.y -= 24
		card.z_index = 100
