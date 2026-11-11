extends RefCounted

const WORLD = preload("res://assets/generated/campaign/world_atlas.png")
const STARTING_CITY = preload("res://assets/generated/campaign/starting_city.png")
const LOCATIONS = preload("res://assets/generated/campaign/locations.png")
const GRASSLAND_BOSS = preload("res://assets/generated/campaign/crown_grazer.png")
const Map = preload("res://scripts/campaign_map.gd")
# The painted sheet has a taller final row.
const ROWS := [0, 177, 354, 531, 708, 885, 1122]

static func location(node: Dictionary) -> Texture2D:
	if node.id == "grassland_boss": return GRASSLAND_BOSS
	var row := Map.BIOMES.find_custom(func(biome): return biome.id == node.biome)
	var column := Map.STEPS.find(node.id.trim_prefix(node.biome + "_"))
	var width := LOCATIONS.get_width() / 5.0
	var left := roundi(column * width)
	var right := roundi((column + 1) * width)
	var tile := AtlasTexture.new()
	tile.atlas = LOCATIONS
	tile.region = Rect2(left + 2, ROWS[row] + 2, right - left - 4, ROWS[row + 1] - ROWS[row] - 4)
	tile.filter_clip = true
	return tile
