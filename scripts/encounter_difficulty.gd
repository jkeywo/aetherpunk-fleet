extends RefCounted

const DEFAULT_STARS := 6

static func visible_enemy_cards(stars: int) -> int:
	if stars <= 2: return 1
	if stars <= 5: return 2
	if stars <= 8: return 3
	return 4
