extends HFlowContainer
## Read-only stance loadout shared by campaign and Custom Battle inspections.

const EnemyRow = preload("res://scripts/enemy_row_view.gd")

func _init(enemy: Dictionary, card_width: float = 320.0, position: int = -1) -> void:
	name = "StanceList"
	add_theme_constant_override("h_separation", 12)
	add_theme_constant_override("v_separation", 12)
	var counts: Dictionary = {}
	for entry in enemy.stance_loadout:
		counts[entry.stance] = counts.get(entry.stance, 0) + int(entry.count)
	for stance in enemy.stances:
		if not counts.has(stance.id): continue
		var preview := EnemyRow.new()
		preview.custom_minimum_size = Vector2(card_width, 220)
		add_child(preview)
		preview.configure([stance.merged({
			"uid": 0,
			"owner": -1,
			"owner_name": enemy.name,
			"owner_visual": enemy.merged({"position": position}, true),
			"copies": counts[stance.id],
		})], {}, -1, 1)
