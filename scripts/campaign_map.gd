extends RefCounted
## World geometry uses the same coordinates as the campaign sketch.

const BIOMES := [
	{"id":"grassland", "name":"Grassland", "stars":1, "color":"#567d46", "label":[245,655], "outline":[[148,669],[306,511],[413,616],[254,775]], "points":[[250,704],[248,615],[335,617],[306,583],[302,548]]},
	{"id":"ice", "name":"Ice", "stars":2, "color":"#327f9c", "label":[125,400], "outline":[[42,457],[148,351],[306,511],[201,616]], "points":[[203,518],[168,481],[238,462],[156,446],[74,403]]},
	{"id":"jungle", "name":"Jungle", "stars":2, "color":"#276a46", "label":[411,369], "outline":[[254,457],[360,351],[519,510],[413,616]], "points":[[409,496],[355,442],[447,451],[441,399],[485,425]]},
	{"id":"lava", "name":"Lava", "stars":3, "color":"#a15c39", "label":[233,205], "outline":[[148,351],[307,192],[413,298],[254,457]], "points":[[198,285],[234,325],[285,286],[301,248],[255,212]]},
	{"id":"desert", "name":"Desert", "stars":3, "color":"#a38946", "label":[480,272], "outline":[[360,351],[519,192],[625,298],[466,457]], "points":[[461,342],[420,283],[498,291],[522,235],[592,263]]},
	{"id":"air", "name":"Air", "stars":4, "color":"#568498", "label":[455,118], "outline":[[254,140],[360,34],[519,192],[413,298]], "points":[[409,164],[371,149],[442,136],[346,130],[360,70]]},
]
const STEPS := ["first", "town_west", "town_east", "second", "boss"]
const START := "start"
const START_POINT := Vector2(180,742)
const REGIONAL_LINKS := [
	["first", "town_west"], ["first", "town_east"], ["town_west", "second"],
	["town_east", "second"], ["second", "boss"],
]
const LAVA_LINKS := [
	["first", "town_west"], ["first", "town_east"], ["town_west", "town_east"],
	["town_east", "second"], ["second", "boss"],
]
const CROSS_LINKS := [
	["grassland_town_west", "ice_first"],
	["grassland_second", "jungle_first"],
	["ice_town_east", "jungle_first"],
	["ice_second", "lava_first"],
	["jungle_second", "lava_town_east"],
	["jungle_second", "desert_first"],
	["lava_second", "desert_town_west"],
	["lava_second", "air_first"],
	["desert_second", "air_first"],
]
const GRASSLAND_NAMES := ["Meadow Patrol", "Liberate Windmere", "Liberate Cloverwatch", "High Pasture", "Crown Grazer"]

static func nodes() -> Dictionary:
	var result := {}
	for biome in BIOMES:
		for i in STEPS.size():
			var id: String = biome.id + "_" + STEPS[i]
			var name: String = GRASSLAND_NAMES[i] if biome.id == "grassland" else biome.name + " " + ["Patrol", "West Town", "East Town", "Expedition", "Boss"][i]
			result[id] = {
				"id": id, "name": name, "biome": biome.id, "base": biome.stars,
				"kind": ["regular", "town", "town", "regular", "boss"][i],
				"point": Vector2(biome.points[i][0], biome.points[i][1]),
				"playable": biome.id == "grassland",
			}
	return result

static func links() -> Array:
	var result: Array = [[START, "grassland_first"]]
	for biome in BIOMES:
		var prefix: String = biome.id + "_"
		var regional_links: Array = LAVA_LINKS if biome.id == "lava" else REGIONAL_LINKS
		for pair in regional_links:
			result.append([prefix + pair[0], prefix + pair[1]])
	result.append_array(CROSS_LINKS.duplicate(true))
	return result

static func distances(cleared: Array) -> Dictionary:
	var edges := links()
	var result := {START: 0}
	var queue: Array = [START]
	for id in cleared:
		if not result.has(id):
			queue.append(id)
			result[id] = 0
	var i := 0
	while i < queue.size():
		var current: String = queue[i]
		i += 1
		for edge in edges:
			var next: String = edge[1] if edge[0] == current else (edge[0] if edge[1] == current else "")
			if next.is_empty() or result.has(next): continue
			result[next] = int(result[current]) + 1
			queue.append(next)
	return result

static func difficulty(node: Dictionary, cleared: Array) -> Dictionary:
	var distance: int = distances(cleared).get(node.id, 1)
	var surcharge := maxi(0, distance - 1)
	return {"base": node.base, "distance": distance, "surcharge": surcharge, "stars": mini(10, int(node.base) + surcharge)}

static func scaling(node: Dictionary, stars: int, doom: int) -> Dictionary:
	var boss_doom := 0
	if node.kind == "boss": boss_doom = doom * (2 if node.biome == "air" else 1)
	return {
		"hull_percent": (stars - 1 + boss_doom) * 10,
		"hit_bonus": int(stars >= 4) + int(stars >= 7) + int(stars >= 10) + boss_doom,
		"doom_hull_percent": boss_doom * 10,
		"doom_hit_bonus": boss_doom,
	}
