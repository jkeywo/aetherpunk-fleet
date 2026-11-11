extends Node
## Owns the campaign save. All changes are persisted before becoming visible.

const World = preload("res://scripts/campaign_map.gd")
const Content = preload("res://scripts/campaign_content.gd")
const Catalog = preload("res://scripts/content_catalog.gd")
const State = preload("res://scripts/battle_state.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const CRAFT_PRICE := 6
const DOCK_PRICE := 6
const UPGRADE_PRICES := {2: 4, 3: 7}
const REPAIR_AMOUNT := 4
const VERSION := 1
const WINS_PER_RAGE_TIER := 8

var path := "user://campaign.json"
var run: Dictionary = {}
var last_error := ""

func _ready() -> void:
	load_run()

func new_run(source: Dictionary, seed_value: int = -1) -> bool:
	if source.is_empty(): return _fail("Campaign content could not be loaded.")
	var doc := Content.document(source)
	var errors := Catalog.validate(doc)
	if not errors.is_empty(): return _fail("Campaign content is invalid: " + str(errors[0]))
	for id in ["bastion", "kestrel", Content.CRAFTABLE]:
		if Catalog.index_by_id(doc.ships, id) < 0: return _fail("Campaign hull is missing: " + id)
	for id in ["iona", "voss"] + Content.RECRUITS:
		if Catalog.index_by_id(doc.captains, id) < 0: return _fail("Campaign captain is missing: " + id)
	var next := {
		"version":VERSION, "seed":int(randi() & 0x7fffffff) if seed_value < 0 else seed_value,
		"content":doc, "cleared":[], "materials":0, "wins":0, "docks":2,
		"ships":{}, "destroyed":[], "captains":["iona","voss"], "buffs":[],
		"pending":{}, "recruitment":[], "last_sortie":[], "attempt":0, "last_result":{},
		"ended":false,
	}
	for id in ["bastion", "kestrel"]:
		next.ships[id] = _new_ship(next, id)
	return _commit(next)

func load_run() -> bool:
	last_error = ""
	if not FileAccess.file_exists(path):
		run = {}
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not _valid_save(data):
		run = {}
		return _fail("The campaign save could not be read or uses an unsupported version.")
	Content.update_grassland_boss(data.content)
	Content.update_stance_decks(data.content)
	var pending: Dictionary = data.pending
	if pending.get("node") == "grassland_boss" and pending.document.setup.enemies.map(func(entry): return entry.enemy) != Content.BOSS_PARTS:
		var node: Dictionary = World.nodes().grassland_boss
		var scale := World.scaling(node, int(pending.stars), int(pending.get("doom", 0)))
		var enemies := Content.encounter(int(data.seed), node, int(pending.stars))
		pending.document = Content.battle_document(data.content, pending.sortie, enemies, hull_buff(data), scale.hull_percent)
		pending.document.setup.encounter_stars = int(pending.stars)
	if not pending.is_empty(): pending.options.erase("boss_core")
	run = data
	return true

func _valid_save(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != VERSION: return false
	for key in ["content","ships","pending","last_result"]:
		if not value.get(key) is Dictionary: return false
	for key in ["cleared","destroyed","captains","buffs","recruitment","last_sortie"]:
		if not value.get(key) is Array: return false
	for key in ["seed","materials","wins","docks","attempt"]:
		if not (value.get(key) is int or value.get(key) is float) or value[key] < 0 or value[key] != floor(value[key]): return false
	if int(value.docks) not in [2,3] or not value.get("ended") is bool: return false
	if not Catalog.validate(value.content).is_empty(): return false
	var nodes := World.nodes()
	for id in value.cleared:
		if not id is String or not nodes.get(id, {}).get("playable", false): return false
	for id in value.destroyed:
		if not id is String or value.ships.has(id) or Catalog.index_by_id(value.content.ships, id) < 0: return false
	for id in value.captains:
		if not id is String or Catalog.index_by_id(value.content.captains, id) < 0: return false
	for slot in value.last_sortie:
		if not slot is Dictionary or not slot.get("ship") is String or not slot.get("captain") is String or slot.get("position") not in Geometry.POSITIONS: return false
	if not value.last_result.is_empty():
		if not nodes.has(value.last_result.get("node")) or not value.last_result.get("lost") is Array: return false
		if value.last_result.get("outcome") not in ["victory","defeat"] or not _integer(value.last_result.get("materials")): return false
	for id in value.ships:
		var entry: Variant = value.ships[id]
		if not entry is Dictionary or Catalog.index_by_id(value.content.ships, id) < 0: return false
		if not _integer(entry.get("hull")) or not _integer(entry.get("level")): return false
		var level := int(entry.level)
		if level not in [1,2,3] or not entry.get("level_2") is String or not entry.get("level_3") is String: return false
		var definition: Dictionary = value.content.ships[Catalog.index_by_id(value.content.ships, id)]
		var second := Catalog.index_by_id(definition.levels.two, entry.level_2)
		if level >= 2 and second < 0: return false
		if level == 3 and (Catalog.index_by_id(definition.levels.three, entry.level_3) < 0 or definition.levels.two[second].blocks == entry.level_3): return false
	for id in value.recruitment:
		if not id is String or id not in Content.RECRUITS or id in value.captains: return false
	if not value.pending.is_empty():
		var pending: Dictionary = value.pending
		var node: Dictionary = nodes.get(pending.get("node", ""), {})
		if pending.get("id") != value.attempt or not node.get("playable", false) or pending.get("kind") != node.kind: return false
		if not Catalog.validate(pending.get("document")).is_empty() or not pending.get("options") is Dictionary: return false
		if pending.get("sortie") != pending.document.setup.fleet or not _integer(pending.get("seed")): return false
		if not _integer(pending.get("stars")) or int(pending.stars) not in range(1,11): return false
		if not pending.options.get("starting_hull") is Dictionary or not _integer(pending.options.get("enemy_hit_bonus")): return false
		for slot in pending.sortie:
			if not value.ships.has(slot.ship) or not _integer(pending.options.starting_hull.get(slot.ship)): return false
	return true

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and value >= 0 and value == floor(value)

func _fail(message: String) -> bool:
	last_error = message
	return false

func _commit(next: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("Could not write campaign save: " + error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(next))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail("Could not save campaign: " + error_string(error))
	run = next
	last_error = ""
	return true

func rage() -> int:
	return floori(float(run.get("wins", 0)) / WINS_PER_RAGE_TIER)

func rage_progress() -> int:
	return int(run.get("wins", 0)) % WINS_PER_RAGE_TIER

func hull_buff(data: Dictionary = {}) -> int:
	var current := run if data.is_empty() else data
	return 2 if "grassland_boss" in current.get("buffs", []) else 0

func _new_ship(data: Dictionary, id: String) -> Dictionary:
	var entry := {"hull":1, "level":1, "level_2":"", "level_3":""}
	entry.hull = dock_max(id, data, entry)
	return entry

func dock_max(id: String, data: Dictionary = {}, override: Dictionary = {}) -> int:
	var current := run if data.is_empty() else data
	var entry: Dictionary = override if not override.is_empty() else current.ships[id]
	var slot := _fleet_entry(id, entry, "iona", "front")
	var doc := Content.battle_document(current.content, [slot], [{"enemy":"meadow_skimmer","position":"front"}], hull_buff(current), 0)
	var battle := State.new(0, doc)
	if battle.ships.is_empty():
		return int(current.content.ships[Catalog.index_by_id(current.content.ships,id)].hull) + hull_buff(current)
	return int(battle.ships[0].max_hull)

func can_manage() -> bool:
	return not run.is_empty() and not run.ended and run.pending.is_empty() and run.recruitment.is_empty()

func can_craft(data: Dictionary = {}) -> bool:
	var current := run if data.is_empty() else data
	return not current.is_empty() and not current.ships.has(Content.CRAFTABLE) and Content.CRAFTABLE not in current.destroyed and current.materials >= CRAFT_PRICE

func craft() -> bool:
	if not can_manage() or not can_craft(): return _fail("Lamplighter cannot be crafted.")
	var next := run.duplicate(true)
	next.materials -= CRAFT_PRICE
	next.ships[Content.CRAFTABLE] = _new_ship(next, Content.CRAFTABLE)
	return _commit(next)

func expand_docks() -> bool:
	if not can_manage() or run.docks != 2 or run.materials < DOCK_PRICE: return _fail("The third dock is unavailable.")
	var next := run.duplicate(true)
	next.materials -= DOCK_PRICE
	next.docks = 3
	return _commit(next)

func repair(id: String) -> bool:
	if not can_manage() or not run.ships.has(id) or run.materials < 1: return _fail("Repair is unavailable.")
	var maximum := dock_max(id)
	if run.ships[id].hull >= maximum: return _fail("This ship is already at full hull.")
	var next := run.duplicate(true)
	next.materials -= 1
	next.ships[id].hull = mini(maximum, int(next.ships[id].hull) + REPAIR_AMOUNT)
	return _commit(next)

func upgrade(id: String, branch: String) -> bool:
	if not can_manage() or not run.ships.has(id): return _fail("Upgrade is unavailable.")
	var level := int(run.ships[id].level) + 1
	if not UPGRADE_PRICES.has(level) or run.materials < UPGRADE_PRICES[level]: return _fail("Upgrade is unavailable.")
	var ship: Dictionary = run.content.ships[Catalog.index_by_id(run.content.ships, id)]
	var tiers: Array = ship.levels.two if level == 2 else ship.levels.three
	if Catalog.index_by_id(tiers, branch) < 0: return _fail("Choose an available upgrade branch.")
	if level == 3:
		var previous := Catalog.index_by_id(ship.levels.two, run.ships[id].level_2)
		if previous < 0 or ship.levels.two[previous].blocks == branch: return _fail("Choose an unblocked upgrade branch.")
	var before := dock_max(id)
	var next := run.duplicate(true)
	next.materials -= UPGRADE_PRICES[level]
	var entry: Dictionary = next.ships[id]
	entry.level = level
	entry["level_%d" % level] = branch
	var after := dock_max(id, next)
	entry.hull = clampi(int(entry.hull) + after - before, 0, after)
	return _commit(next)

func _fleet_entry(id: String, entry: Dictionary, captain: String, position: String) -> Dictionary:
	return {"ship":id, "captain":captain, "position":position, "level":entry.level, "level_2":entry.level_2, "level_3":entry.level_3}

func operational_ships() -> Array:
	return run.ships.keys().filter(func(id): return run.ships[id].hull > 0)

func starting_hulls() -> Dictionary:
	var hulls := {}
	for id in operational_ships(): hulls[id] = run.ships[id].hull
	return hulls

func sortie_preparation() -> Dictionary:
	var doc: Dictionary = run.content.duplicate(true)
	doc.setup.fixed_hand = false
	doc.setup.opening_hand = []
	for ship in doc.ships: ship.hull = int(ship.hull) + hull_buff()
	var ships := operational_ships()
	var captains: Array = run.captains.duplicate()
	var positions: Array = Geometry.POSITIONS.duplicate()
	var fleet: Array = []
	for slot in run.last_sortie:
		if fleet.size() >= int(run.docks): break
		if slot.ship in ships and slot.captain in captains and slot.position in positions:
			fleet.append(_fleet_entry(slot.ship, run.ships[slot.ship], slot.captain, slot.position))
			ships.erase(slot.ship)
			captains.erase(slot.captain)
			positions.erase(slot.position)
	while fleet.size() < int(run.docks):
		var position: String = positions.pop_front()
		if ships.is_empty() or captains.is_empty():
			fleet.append(_fleet_entry("", {"level":1,"level_2":"","level_3":""}, "", position))
		else:
			var id: String = ships.pop_front()
			fleet.append(_fleet_entry(id, run.ships[id], captains.pop_front(), position))
	doc.setup.fleet = fleet
	return doc

func sortie_error(sortie: Array) -> String:
	if sortie.is_empty() or sortie.size() > int(run.get("docks", 0)): return "Deploy one to %d operational ships." % int(run.get("docks", 0))
	var ships := []
	var captains := []
	var positions := []
	for slot in sortie:
		if not slot is Dictionary: return "Invalid sortie."
		var id: String = slot.get("ship", "")
		var captain: String = slot.get("captain", "")
		var position: String = slot.get("position", "")
		if not run.ships.has(id) or run.ships[id].hull <= 0 or id in ships: return "Choose distinct operational ships."
		if captain not in run.captains or captain in captains: return "Assign a different owned captain to each ship."
		if position not in Geometry.POSITIONS or position in positions: return "Choose a different position for each ship."
		ships.append(id)
		captains.append(captain)
		positions.append(position)
	return ""

func launch(node_id: String, sortie: Array) -> bool:
	var node: Dictionary = World.nodes().get(node_id, {})
	if not can_manage() or not node.get("playable", false) or node_id in run.cleared: return _fail("This encounter is unavailable.")
	var error := sortie_error(sortie)
	if not error.is_empty(): return _fail(error)
	var rating := World.difficulty(node, run.cleared)
	var stars: int = rating.stars
	var launch_rage := rage()
	var scale := World.scaling(node, stars, launch_rage)
	var fleet: Array = []
	var hulls := {}
	for slot in sortie:
		fleet.append(_fleet_entry(slot.ship, run.ships[slot.ship], slot.captain, slot.position))
		hulls[slot.ship] = run.ships[slot.ship].hull
	Geometry.normalize_fleet_slots(fleet)
	var enemies := Content.encounter(int(run.seed), node, stars)
	var doc := Content.battle_document(run.content, fleet, enemies, hull_buff(), scale.hull_percent)
	doc.setup.encounter_stars = stars
	var errors := Catalog.validate(doc)
	if not errors.is_empty(): return _fail(str(errors[0]))
	var next := run.duplicate(true)
	next.attempt += 1
	next.last_sortie = sortie.duplicate(true)
	next.last_result = {}
	next.pending = {
		"id":next.attempt, "node":node_id, "kind":node.kind, "stars":stars, "doom":launch_rage,
		"seed":Content.encounter_seed(int(run.seed), node_id, stars), "sortie":fleet,
		"document":doc, "options":{"starting_hull":hulls, "enemy_hit_bonus":scale.hit_bonus,
			"vary_stance_replacements":true},
	}
	return _commit(next)

func pending_battle() -> Dictionary:
	return run.get("pending", {}).duplicate(true)

func settle(attempt_id: int, summary: Dictionary) -> bool:
	var pending: Dictionary = run.get("pending", {})
	if pending.is_empty():
		return attempt_id > 0 and run.get("last_result", {}).get("attempt") == attempt_id
	if int(pending.id) != attempt_id or summary.get("is_test", true) or summary.get("outcome") not in ["victory","defeat"]:
		return _fail("Campaign outcome does not match the pending battle.")
	var results := {}
	for ship in summary.get("ships", []):
		results[ship.id] = ship
	if results.size() != pending.sortie.size(): return _fail("Campaign outcome has an incomplete fleet.")
	for entry in pending.sortie:
		if not results.has(entry.ship): return _fail("Campaign outcome has an unexpected fleet.")
	var next := run.duplicate(true)
	next.pending = {}
	var reward := 0
	if summary.outcome == "victory":
		next.cleared.append(pending.node)
		next.wins += 1
		if pending.kind == "regular":
			reward = 5 + int(pending.stars)
			next.materials += reward
		elif pending.kind == "town":
			var pool: Array = Content.RECRUITS.filter(func(id): return id not in next.captains)
			var rng := RandomNumberGenerator.new()
			rng.seed = int(pending.seed)
			for i in 3:
				next.recruitment.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		elif pending.kind == "boss":
			var old_buff := hull_buff(next)
			next.buffs.append(pending.node)
			var delta := hull_buff(next) - old_buff
			if delta > 0:
				for id in next.ships:
					if next.ships[id].hull > 0: next.ships[id].hull += delta
		for entry in pending.sortie:
			var ship: Dictionary = results[entry.ship]
			next.ships[entry.ship].hull = dock_max(entry.ship, next) if pending.kind == "boss" else int(ship.hull)
	else:
		for entry in pending.sortie:
			next.ships.erase(entry.ship)
			next.destroyed.append(entry.ship)
		next.ended = not _can_continue(next)
	next.last_result = {"attempt":attempt_id, "node":pending.node, "outcome":summary.outcome, "materials":reward,
		"lost":pending.sortie.map(func(entry): return entry.ship) if summary.outcome == "defeat" else []}
	return _commit(next)

func _can_continue(data: Dictionary) -> bool:
	for entry in data.ships.values():
		if entry.hull > 0 or data.materials >= 1: return true
	return can_craft(data)

func recruit(id: String) -> bool:
	if run.is_empty() or id not in run.recruitment or id in run.captains: return _fail("That captain is not available.")
	var next := run.duplicate(true)
	next.captains.append(id)
	next.recruitment.clear()
	return _commit(next)
