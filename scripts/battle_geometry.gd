extends RefCounted
const POSITIONS := ["front", "upper", "lower", "rear"]
const POSITION_NAMES := ["Front", "Upper Middle", "Lower Middle", "Rear"]
const UNIT_LINKS := [[0, 1], [0, 2], [1, 3], [2, 3]]
const SLOT_NAMES := ["North", "East", "South", "West", "Centre", "North East", "South East", "South West", "North West"]
const CIRCLE_POINTS := [Vector2(1, 0), Vector2(2, 1), Vector2(1, 2), Vector2(0, 1), Vector2(1, 1), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2), Vector2(0, 0)]
const BASE_LINKS := [[0, 1], [1, 2], [2, 3], [3, 0]]
const EXTRA_LINKS := [[4, 0], [4, 1], [4, 2], [4, 3], [5, 0], [5, 1], [6, 1], [6, 2], [7, 2], [7, 3], [8, 3], [8, 0]]


static func neighbours(slot: int, expanded: bool = false) -> Array:
	var result: Array = []
	var links: Array = BASE_LINKS.duplicate()
	if expanded:
		links.append_array(EXTRA_LINKS)
	for link in links:
		if link[0] == slot:
			result.append(link[1])
		elif link[1] == slot:
			result.append(link[0])
	return result


static func normalize_formation(points: Array, empty: Variant = -1) -> Vector2i:
	var count := points.size() - points.count(empty)
	var from := -1
	var to := 0
	match count:
		1:
			if points[0] == empty:
				for point in [1, 2, 3]:
					if points[point] != empty:
						from = point
						break
		2:
			if points[3] != empty:
				from = 3
				to = points.find(empty)
		3:
			if points[0] == empty: from = 3
	if from < 0: return Vector2i(-1, -1)
	points[to] = points[from]
	points[from] = empty
	return Vector2i(from, to)


static func normalize_fleet_slots(fleet: Array) -> void:
	var points: Array = [-1, -1, -1, -1]
	var indices: Array = [-1, -1, -1, -1]
	for index in fleet.size():
		var point := POSITIONS.find(fleet[index].position)
		if point < 0: continue
		indices[point] = index
		if not fleet[index].ship.is_empty(): points[point] = index
	var move := normalize_formation(points)
	if move.x < 0: return
	fleet[indices[move.x]].position = POSITIONS[move.y]
	if indices[move.y] >= 0:
		fleet[indices[move.y]].position = POSITIONS[move.x]


static func unit_neighbours(position: int) -> Array:
	var result: Array = []
	for link in UNIT_LINKS:
		if link[0] == position:
			result.append(link[1])
		elif link[1] == position:
			result.append(link[0])
	return result


static func condition_matches(condition: Dictionary, cards: Array) -> bool:
	var count := 0
	for card in cards:
		if condition.get("tag", "") == "" or card.get("tag_ids", card.get("tags", [])).has(condition.tag):
			count += 1
	return count >= int(condition.get("min", 0))
