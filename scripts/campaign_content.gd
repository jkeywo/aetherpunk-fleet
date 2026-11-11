extends RefCounted
## Authored Grassland pools and rewards. Campaign definitions are copied into each run.

const Catalog = preload("res://scripts/content_catalog.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const Art = preload("res://scripts/art_assets.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const World = preload("res://scripts/campaign_map.gd")
const RECRUITS := ["rook", "brin_reed", "tess_fen", "hale_brook"]
const CRAFTABLE := "lamplighter"
const BOSS := "crown_grazer"
const BOSS_PARTS := [BOSS, "crown_grazer_far_claw", "crown_grazer_near_claw", "crown_grazer_tail"]
const LEGACY_BOSS_IDS := ["grazer_core", "grazer_upper", "grazer_lower", "grazer_tail"]
const POOLS := {
	"grassland_first": ["meadow_skimmer", "pasture_ray"],
	"grassland_town_west": ["meadow_skimmer", "ridge_hunter"],
	"grassland_town_east": ["pasture_ray", "ridge_hunter"],
	"grassland_second": ["ridge_hunter", "pasture_ray", "meadow_skimmer"],
}

static func document(source: Dictionary) -> Dictionary:
	var doc := source.duplicate(true)
	var enemies := [
		_enemy("meadow_skimmer", "Meadow Skimmer", 16, "needlewing", "Skim Strike", [_attack(2)], [_attack(1)]),
		_enemy("pasture_ray", "Pasture Ray", 17, "storm_ray", "Rising Sweep", [_attack(2)], [_attack(1)]),
		_enemy("ridge_hunter", "Ridge Hunter", 20, "needlewing", "Diving Hunt", [_attack(3)], [_attack(1)]),
	]
	for enemy in enemies:
		if Catalog.index_by_id(doc.leviathans, enemy.id) < 0: doc.leviathans.append(enemy)
	update_grassland_boss(doc)
	update_stance_decks(doc)
	_add_captain(doc, RECRUITS[1], "Brin Reed", "Reed Barrage", "Attack", "weapon_damage", _attack(4, "chosen_enemy"))
	_add_captain(doc, RECRUITS[2], "Tess Fen", "Fen Bulwark", "Guard", "armour", {"kind":"add_shields","target":"chosen_ally","amount":4})
	_add_captain(doc, RECRUITS[3], "Hale Brook", "Brook Repairs", "Support", "repair_amount", {"kind":"repair","target":"chosen_ally","amount":3})
	return doc

static func update_stance_decks(doc: Dictionary) -> void:
	var reactions := {
		"meadow_skimmer": _reaction("skim_counter", "Skim Counter", {"family":"position","position":"front"}, [_attack(1)]),
		"pasture_ray": _reaction("static_arc", "Static Arc", {"family":"healed"}, [_attack(2)]),
		"ridge_hunter": _reaction("counter_dive", "Counter Dive", {"family":"card_type","card_type":"Attack"}, [_attack(2)]),
	}
	var alternates := _alternate_stances()
	for enemy in doc.leviathans:
		if not reactions.has(enemy.id) or enemy.stances.size() != 1: continue
		var original: Dictionary = enemy.stances[0]
		if original.id != "action" or enemy.stance_loadout.size() != 1 or enemy.stance_loadout[0].stance != "action": continue
		if original.reactions.is_empty():
			original.reactions.append(reactions[enemy.id].duplicate(true))
		enemy.stances.append_array(alternates[enemy.id])
		enemy.stance_loadout = enemy.stances.map(func(stance): return {"stance":stance.id, "count":1})

static func _alternate_stances() -> Dictionary:
	return {
		"meadow_skimmer": [
			_stance("low_pass", "Low Pass", [_attack(3)], {"family":"card_type","card_type":"Attack"}, "Slipstream", [_shields(1)]),
			_stance("grasswake", "Grasswake", [_repair(2)], {"family":"card_type","card_type":"Manoeuvre"}, "Wake Snap", [_attack(1)]),
		],
		"pasture_ray": [
			_stance("charged_glide", "Charged Glide", [_attack(1), _repair(1)], {"family":"position","position":"flank"}, "Static Lash", [_attack(2)]),
			_stance("forked_sweep", "Forked Sweep", [_attack(1, "chosen_ally", 2)], {"family":"damaged"}, "Grounding Pulse", [_shields(2)]),
		],
		"ridge_hunter": [
			_stance("ridge_feint", "Ridge Feint", [_attack(2, "chosen_ally", 2)], {"family":"card_type","card_type":"Manoeuvre"}, "Pursuit", [_attack(2)]),
			_stance("high_perch", "High Perch", [_attack(2), _repair(1)], {"family":"position","position":"rear"}, "Talons First", [_attack(3)]),
		],
	}

static func _crown_grazer_parts() -> Array:
	var designs := [
		["Body", "body", 32, 3, 3, 2, _stance("crown_charge", "Crown Charge", [_grazer_attack(5)], {"family":"position","position":"front"}, "Antler Feint", [_grazer_attack(2)])],
		["Far Claw", "far_limb", 12, 1, 1, 1, _stance("twin_rake", "Twin Rake", [_grazer_attack(2, 2)], {"family":"position","position":"flank"}, "Side Swipe", [_grazer_attack(2)])],
		["Near Claw", "near_limb", 12, 1, 1, 1, _stance("meadow_mantle", "Meadow Mantle", [_shields(3), _repair(2)], {"family":"healed"}, "Feeding Pulse", [_repair(2)])],
		["Tail", "tail", 14, 1, 2, 1, _stance("tail_sweep", "Tail Sweep", [{"kind":"swap_ends", "fallback_damage":2}, _grazer_attack(2)], {"family":"damaged"}, "Tail Recoil", [_shields(2)])],
	]
	var result: Array = []
	for i in designs.size():
		var design: Array = designs[i]
		var stance: Dictionary = design[6]
		var unit := _enemy(BOSS_PARTS[i], design[0], design[2], BOSS, stance.name, stance.effects, [_grazer_attack(design[5])])
		unit.role = "Crown Grazer"
		unit.armour = design[3]
		unit.weapon.damage = design[4]
		unit.shared_rig_part = design[1]
		unit.stances = [stance]
		unit.stance_loadout = [{"stance": stance.id, "count": 2}]
		result.append(unit)
	return result


static func _grazer_attack(amount: int, hits: int = 1) -> Dictionary:
	return _attack(amount, "chosen_ally", hits).merged({"presentation": "ranged"})


static func update_grassland_boss(doc: Dictionary) -> void:
	doc.leviathans = doc.leviathans.filter(func(enemy): return enemy.id not in LEGACY_BOSS_IDS and enemy.id not in BOSS_PARTS)
	doc.leviathans.append_array(_crown_grazer_parts())


static func _stance(id: String, name: String, intent: Array, trigger: Dictionary, reaction_name: String, effects: Array) -> Dictionary:
	return {"id":id, "name":name, "effects":intent, "reactions":[_reaction(id + "_reaction", reaction_name, trigger, effects)]}

static func _repair(amount: int, target: String = "owner") -> Dictionary:
	return {"kind":"repair", "target":target, "amount":amount}

static func _shields(amount: int, target: String = "owner") -> Dictionary:
	return {"kind":"add_shields", "target":target, "amount":amount}

static func _reaction(id: String, name: String, trigger: Dictionary, effects: Array) -> Dictionary:
	return {
		"id":id, "name":name, "category":"Retaliation",
		"conditions":trigger.merged({"kind":"reaction_trigger"}), "effects":effects,
	}

static func _attack(amount: int, target: String = "chosen_ally", hits: int = 1) -> Dictionary:
	return {"kind":"attack","target":target,"damage":amount,"hits":hits,"range":"Long"}

static func _enemy(id: String, name: String, hull: int, rig: String, intent: String, effects: Array, fallback: Array) -> Dictionary:
	return {
		"id":id, "name":name, "hull":hull, "armour":0, "weapon":{"damage":1,"range":"Long"},
		"visual_rig":Art.rig(rig, true).duplicate(true),
		"stances":[{"id":"action","name":intent,"effects":effects,"reactions":[]}],
		"stance_loadout":[{"stance":"action","count":3}],
		"default_action":fallback,
	}

static func _add_captain(doc: Dictionary, id: String, name: String, card_name: String, type: String, stat: String, effect: Dictionary) -> void:
	if Catalog.index_by_id(doc.captains, id) >= 0: return
	var card_id := id + "_orders"
	var passive := Rules.rule("passive", [], "captain")
	passive.trigger.subject = "owner"
	passive.modifiers = [{"kind":stat,"target":"owner","amount":1}]
	doc.captains.append({"id":id,"name":name,"tier":1,"card":card_id,"passive":passive})
	doc.cards.append({"id":card_id,"name":card_name,"owner":id,"type":type,"traits":[],"cost":1,"pays":1,
		"positions":Geometry.POSITIONS.duplicate(),"rules":[Rules.rule("on_play",[effect])]})

static func encounter(seed_value: int, node: Dictionary, stars: int) -> Array:
	var ids: Array
	if node.kind == "boss":
		ids = BOSS_PARTS
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = encounter_seed(seed_value, node.id, stars)
		var pool: Array = POOLS[node.id]
		ids = []
		for i in mini(4, 1 + floori((stars - 1) / 2.0)):
			ids.append(pool[rng.randi_range(0, pool.size() - 1)])
	var formation: Array = []
	for i in ids.size():
		formation.append({"enemy":ids[i],"position":Geometry.POSITIONS[i]})
	return formation

static func encounter_seed(seed_value: int, node_id: String, stars: int) -> int:
	return hash("%d/%s/%d" % [seed_value, node_id, stars]) & 0x7fffffff

static func battle_document(source: Dictionary, sortie: Array, enemies: Array, hull_buff: int, hull_percent: int) -> Dictionary:
	var doc := source.duplicate(true)
	doc.setup.fleet = sortie.duplicate(true)
	doc.setup.enemies = enemies.duplicate(true)
	doc.setup.fixed_hand = false
	doc.setup.opening_hand = []
	for ship in doc.ships:
		ship.hull = int(ship.hull) + hull_buff
	for enemy in doc.leviathans:
		if enemies.any(func(entry): return entry.enemy == enemy.id):
			enemy.hull = ceili(int(enemy.hull) * (100 + hull_percent) / 100.0)
	return doc
