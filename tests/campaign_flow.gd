extends "res://tests/support/v3_test.gd"

const World = preload("res://scripts/campaign_map.gd")
const CampaignContent = preload("res://scripts/campaign_content.gd")
var campaign
var source: Dictionary
var sortie := [
	{"ship":"bastion","captain":"iona","position":"front"},
	{"ship":"kestrel","captain":"voss","position":"upper"},
]

func _run() -> void:
	root.size = Vector2i(1280, 800)
	campaign = root.get_node("CampaignStore")
	source = root.get_node("ContentStore").snapshot()
	campaign.path = "user://campaign-flow-%d.json" % Time.get_ticks_usec()
	if not campaign.new_run(source, 824):
		expect(false, campaign.last_error)
		done("Campaign")
		return
	_map_rules()
	_reaction_coverage()
	_progression()
	_losses_and_doom()
	await _scene_flow()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(campaign.path))
	done("Campaign graph, progression, boss and navigation")

func _map_rules() -> void:
	var nodes := World.nodes()
	expect(nodes.size() == 30 and World.links().size() == 40 and World.distances([]).size() == 31, "World graph is incomplete or disconnected.")
	var revised_routes := [
		["ice_first", "grassland_town_west", "grassland_second"],
		["jungle_first", "ice_town_east", "ice_second"],
		["jungle_second", "lava_town_east", ""],
		["lava_town_west", "lava_town_east", "lava_second"],
		["lava_second", "desert_town_west", "desert_first"],
	]
	for route in revised_routes:
		var distances := World.distances([route[0]])
		expect(distances[route[1]] == 1, "Missing revised route from %s to %s." % [route[0], route[1]])
		if not route[2].is_empty():
			expect(distances[route[2]] == 2, "An old route still links %s to %s." % [route[0], route[2]])
	for biome in World.BIOMES:
		var region := nodes.values().filter(func(node): return node.biome == biome.id)
		expect(region.size() == 5 and region.filter(func(node): return node.kind == "town").size() == 2, "Incorrect biome encounter types.")
	expect(World.difficulty(nodes.grassland_boss, []).stars == 4, "The starting city did not determine a distant boss rating.")
	expect(World.difficulty(nodes.grassland_boss, ["grassland_second"]).stars == 1, "Difficulty did not use the nearest cleared node.")
	expect(World.difficulty(nodes.air_boss, []).stars == 10, "Difficulty did not cap at ten stars.")
	for stars in range(1, 11):
		var generated := CampaignContent.encounter(824, nodes.grassland_second, stars)
		expect(generated.size() == mini(4, 1 + floori((stars - 1) / 2.0)) and generated == CampaignContent.encounter(824, nodes.grassland_second, stars), "Encounter generation did not scale deterministically.")
		var doc := neutral(true)
		doc.setup.encounter_stars = stars
		var battle = State.new(0, doc)
		var row_size: int = [1,1,2,2,2,3,3,3,4,4][stars - 1]
		expect(battle.enemy_row.size() == row_size, "Wrong visible card count at %d stars." % stars)
		battle._replace_row(battle.enemy_row[0])
		expect(battle.enemy_row.size() == row_size, "Enemy row replacement did not respect stars.")
		battle.end_phase()
		var activations: Array = battle.feedback_events.filter(func(event): return event.kind == "intent_triggered" and event.has("stance_uid"))
		expect(activations.size() == row_size, "The visible row did not set the phase activation count.")
	expect(World.scaling(nodes.air_boss, 7, 2).hit_bonus == 6 and World.scaling(nodes.air_boss, 7, 2).hull_percent == 100, "Final boss Doom scaling is incorrect.")
	expect(World.scaling(nodes.ice_boss, 4, 2).hit_bonus == 3 and World.scaling(nodes.ice_boss, 4, 2).hull_percent == 50, "Regional boss Doom scaling is incorrect.")
	expect(World.scaling(nodes.ice_first, 10, 3).hit_bonus == 3, "Doom incorrectly affected a normal encounter.")
	expect(not campaign.launch("ice_first", sortie) and campaign.run.pending.is_empty(), "Unimplemented biome launched.")
	expect(campaign.launch("grassland_boss", sortie) and campaign.run.pending.stars == 4, "Uncleared boss was gated.")
	expect(campaign.new_run(source, 824), campaign.last_error)

func _reaction_coverage() -> void:
	var ids := ["meadow_skimmer", "pasture_ray", "ridge_hunter"] + CampaignContent.BOSS_PARTS
	for id in ids:
		var enemy: Dictionary = campaign.run.content.leviathans[Catalog.index_by_id(campaign.run.content.leviathans, id)]
		var count := 1 if id in CampaignContent.BOSS_PARTS else 3
		expect(enemy.stances.size() == count and enemy.stance_loadout.size() == count, "%s has an incorrect stance count." % id)
		for stance in enemy.stances:
			expect(stance.reactions.size() == 1 and not stance.effects.is_empty(), "%s should have a reaction and an intent." % stance.name)
		for left in range(enemy.stances.size()):
			for right in range(left + 1, enemy.stances.size()):
				expect(enemy.stances[left].effects != enemy.stances[right].effects and enemy.stances[left].reactions[0].conditions != enemy.stances[right].reactions[0].conditions, "%s repeats an intent or trigger." % id)

	var fleet: Array = campaign.sortie_preparation().setup.fleet.filter(func(slot): return not slot.ship.is_empty())
	var doc := CampaignContent.battle_document(CampaignContent.document(neutral()), fleet, [{"enemy":"meadow_skimmer","position":"front"}], 0, 0)
	doc.setup.encounter_stars = 1
	var battle := State.new(3, doc, {"vary_stance_replacements":true})
	expect(battle.init_error.is_empty() and not battle.enemy_row.is_empty(), "Campaign reaction fixture failed to initialize: " + battle.init_error)
	if battle.enemy_row.is_empty(): return
	all_in_hand(battle)
	battle.enemy_row = [0]
	battle.stance_deck.clear()
	battle.stance_discard = [1, 2]
	var initial_card: int = battle.enemy_row[0]
	expect(battle.play(uid_for(battle, "brace"), [], -1, -1, 0) == "", "Failed to play from the front against Meadow Skimmer.")
	expect(battle.feedback_events.any(func(event): return event.kind == "reaction_triggered") and initial_card not in battle.enemy_row, "Meadow Skimmer did not react and replace its stance.")

	var previous_name: String = battle.stance().name
	battle.stance_discard.append_array(battle.stance_deck)
	battle.stance_deck.clear()
	expect(battle.end_phase() == "" and battle.stance().name != previous_name, "Enemy-phase refill repeated the spent stance after reshuffling.")

	var legacy: Dictionary = campaign.run.duplicate(true)
	var index := Catalog.index_by_id(legacy.content.leviathans, "meadow_skimmer")
	legacy.content.leviathans[index].stances.resize(1)
	legacy.content.leviathans[index].stance_loadout = [{"stance":"action","count":3}]
	legacy.content.leviathans[index].stances[0].reactions.clear()
	expect(campaign._commit(legacy) and campaign.load_run(), "Could not reload a campaign saved before reactions were added.")
	expect(campaign.run.content.leviathans[index].stances.size() == 3 and campaign.run.content.leviathans[index].stances[0].reactions.size() == 1, "Legacy campaign did not gain the expanded stance deck for new sorties.")

func _battle():
	var pending: Dictionary = campaign.pending_battle()
	var b = State.new(int(pending.seed), pending.document, pending.options)
	expect(b.init_error.is_empty(), b.init_error)
	return b

func _kill(b, target: int) -> void:
	b.effect_attack(attack(999, 1, "Long", "event_target"), {"owner":0,"uid":-1,"event":{"target":target}})
	b._drain()

func _win(b) -> void:
	for id in b.alive_ids(true):
		if b.outcome.is_empty(): _kill(b, id)
	expect(b.outcome == "victory", "Battle did not produce a genuine victory.")
	expect(campaign.settle(int(campaign.run.attempt), b.result_summary()), campaign.last_error)

func _progression() -> void:
	expect(campaign.run.ships.size() == 2 and campaign.run.docks == 2 and campaign.run.materials == 0, "Invalid starter fleet.")
	expect(not campaign.launch("grassland_first", [sortie[0], sortie[0]]), "Duplicate sortie accepted.")
	expect(campaign.launch("grassland_first", sortie), campaign.last_error)
	var b = _battle()
	expect(b.hand.size() == 6 and b.ships[0].hull == b.ships[0].max_hull, "Two-ship opening did not use the normal refill or full hull.")
	var pending: Dictionary = campaign.pending_battle()
	var initial_hand: Array = b.hand.duplicate()
	pending.document.setup.fleet.clear()
	expect(campaign.load_run() and _battle().hand == initial_hand and campaign.run.pending.document.setup.fleet.size() == 2, "Pending launch failed reload, seeding or snapshot isolation.")
	b.ships[0].hull -= 6
	b.ships[1].hull = 0
	_win(b)
	expect(campaign.run.materials == 6 and campaign.run.ships.bastion.hull == campaign.dock_max("bastion") - 6 and campaign.run.ships.kestrel.hull == 0, "Normal win did not preserve damage or disabled hull.")
	expect(campaign.load_run() and campaign.settle(int(campaign.run.attempt), b.result_summary()) and campaign.run.materials == 6, "Duplicate settlement granted rewards after reload.")
	expect(not campaign.launch("grassland_first", sortie), "Cleared node could be farmed.")
	expect(campaign.repair("kestrel") and campaign.run.ships.kestrel.hull == 4 and campaign.run.materials == 5, "Disabled ship did not return to service.")
	expect(campaign.launch("grassland_town_west", sortie), campaign.last_error)
	b = _battle()
	expect(b.ships[1].hull == 4, "Starting hull was lost in battle handoff.")
	_win(b)
	var choices: Array = campaign.run.recruitment.duplicate()
	expect(choices.size() == 3 and campaign.load_run() and campaign.run.recruitment == choices, "Town choices were missing or rerolled after reload.")
	expect(campaign.recruit(choices[0]) and not campaign.recruit(choices[1]), "Recruitment accepted more than one captain.")
	expect(campaign.launch("grassland_town_east", sortie), campaign.last_error)
	_win(_battle())
	choices = campaign.run.recruitment.duplicate()
	expect(choices.size() == 3 and choices.all(func(id): return id not in campaign.run.captains), "Second town did not offer three unowned captains.")
	campaign.recruit(choices[0])
	expect(campaign.launch("grassland_second", [sortie[0]]), campaign.last_error)
	b = _battle()
	expect(b.ships.size() == 1 and b.hand.size() == 5, "A one-ship sortie did not open with five cards.")
	_win(b)
	expect(campaign.run.materials == 11 and campaign.craft(), "Materials did not unlock Lamplighter.")
	expect(not campaign.expand_docks() and campaign.run.docks == 2, "Dock expansion charged more materials than available.")
	campaign.run.materials = 17
	expect(campaign.expand_docks() and campaign.run.docks == 3, "Third dock was not unlocked.")
	var ship: Dictionary = source.ships[Catalog.index_by_id(source.ships, "bastion")]
	var branch: Dictionary = ship.levels.two[0]
	expect(campaign.upgrade("bastion", branch.id) and not campaign.upgrade("bastion", branch.blocks), "Ship upgrades did not respect branch restrictions.")
	expect(campaign.upgrade("bastion", ship.levels.three.filter(func(entry): return entry.id != branch.blocks)[0].id) and campaign.run.ships.bastion.level == 3, "Legal level-three upgrade failed.")
	campaign.run.ships.lamplighter.hull -= 3
	var reserve_hull: int = campaign.run.ships.lamplighter.hull
	expect(campaign.launch("grassland_boss", sortie), campaign.last_error)
	b = _battle()
	expect(b.enemy_formation == [0, 1, 2, 3] and b.stat(-1, "armour") == 3 and b.stat(-1, "weapon_damage") == 3, "Crown Grazer did not occupy all four slots with independent stats.")
	expect(b.stance_cards.size() == 8, "Crown Grazer did not contribute two cards per part.")
	for owner in [-1, -2, -3, -4]:
		expect(b.stance_cards.filter(func(card): return card.owner == owner).size() == 2, "A boss part lost its own stance cards.")
	var formation = preload("res://scripts/formation_view.gd").new()
	root.add_child(formation)
	formation.size = Vector2(410, 310)
	formation.configure(b.board_snapshot(), true)
	expect(formation.shared_rig != null and formation.shared_rig.definition.parts.size() == 4 and formation.shared_rig.size.x == 400, "Battle did not assemble one four-part rig across the formation.")
	for owner in [-1, -2, -3, -4]:
		var widget: Control = formation.target_widget(owner)
		expect(widget != null and widget.art.rig_node == null and widget.get_meta("shared_rig_part") == b.unit(owner).shared_rig_part, "A boss slot lacks an independent target or draws duplicate art.")
	formation.free()
	var art = preload("res://scripts/campaign_art.gd")
	expect(art.location(World.nodes().grassland_boss) == art.GRASSLAND_BOSS, "Grassland marker still uses the old boss painting.")
	b.ships[1].hull = 0
	_kill(b, -2)
	expect(b.outcome.is_empty() and b.alive_ids(true).size() == 3 and b.enemy_formation[1] == -1, "Defeating one claw affected other parts or ended the encounter.")
	expect(b.enemy_row.all(func(uid): return b.stance_cards[uid].owner != -2), "Defeated claw still contributed visible stances.")
	for owner in b.alive_ids(true): _kill(b, owner)
	expect(b.outcome == "victory" and b.alive_ids(true).is_empty(), "Defeating all Crown Grazer parts did not win the encounter.")
	expect(campaign.settle(int(campaign.run.attempt), b.result_summary()), campaign.last_error)
	expect(campaign.run.cleared.size() == 5 and campaign.hull_buff() == 2 and campaign.run.ships.kestrel.hull == campaign.dock_max("kestrel"), "Grassland reward did not fully repair the deployed fleet or grant its buff.")
	expect(campaign.run.ships.lamplighter.hull == reserve_hull + 2, "Boss victory repaired the reserve or failed to apply its hull buff.")

func _losses_and_doom() -> void:
	campaign.new_run(source, 824)
	campaign.run.wins = 7
	expect(campaign.rage() == 0 and campaign.rage_progress() == 7, "Seven victories should fill seven Rage circles.")
	expect(campaign.launch("grassland_boss", sortie) and campaign.run.pending.doom == 0, "Eighth potential win used Doom early.")
	_win(_battle())
	expect(campaign.rage() == 1 and campaign.rage_progress() == 0, "Eighth win did not advance Rage and reset the circles.")
	campaign.new_run(source, 824)
	campaign.run.wins = 16
	campaign.run.materials = 6
	campaign.craft()
	expect(campaign.launch("grassland_boss", sortie) and campaign.run.pending.doom == 2 and campaign.run.pending.options.enemy_hit_bonus == 3, "Doom launch snapshot did not scale the boss.")
	var b = _battle()
	expect(b.enemies[0].hull == 48, "Star and Doom hull bonuses did not add against base hull.")
	for enemy in b.enemies: enemy.hull = 0
	for ship in b.ships: ship.hull = 0
	b._cleanup()
	expect(b.outcome == "defeat", "Simultaneous boss and fleet loss did not prioritize defeat.")
	campaign.settle(int(campaign.run.attempt), b.result_summary())
	expect(campaign.run.wins == 16 and campaign.run.cleared.is_empty() and campaign.run.destroyed.size() == 2 and campaign.run.captains.size() == 2 and not campaign.run.ended, "Defeat gave progression, lost captains, or failed to preserve reserve.")
	campaign.launch("grassland_first", [{"ship":"lamplighter","captain":"iona","position":"front"}])
	b = _battle()
	b.ships[0].hull = 0
	b._cleanup()
	campaign.settle(int(campaign.run.attempt), b.result_summary())
	expect(campaign.run.ended and campaign.run.ships.is_empty() and not campaign.can_craft(), "Final hull loss did not end the run.")

func _scene_flow() -> void:
	campaign.run = {}
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	expect(current_scene.get_node("%ContinueCampaignButton").disabled, "Continue should require a saved run.")
	current_scene.get_node("%NewCampaignButton").pressed.emit()
	await scene_changed
	var view = current_scene
	await flush()
	expect(view.atlas.buttons.size() == 30 and view.atlas.global_position == Vector2.ZERO and is_equal_approx(view.atlas.size.y, root.get_visible_rect().size.y), "Campaign atlas is not full bleed.")
	var rage_track = view.sidebar.find_child("RageProgress", true, false)
	expect(rage_track != null and rage_track.total == 8 and rage_track.filled == 0, "New campaign did not show eight empty Rage circles.")
	var enemy_labels: Array = view.detail.get_children().filter(func(child): return child.has_meta("enemy_positions"))
	expect(enemy_labels.size() == 1 and enemy_labels[0] is Button and enemy_labels[0].text.begins_with("Front"), "Campaign enemy preview did not expose an enemy-facing inspection button.")
	var enemy_button: Button = enemy_labels[0]
	var click_point := enemy_button.get_global_rect().get_center()
	await motion(click_point)
	await mouse(click_point, true)
	await mouse(click_point, false)
	await flush()
	var stance_list: HFlowContainer = view.enemy_overlay.find_child("StanceList", true, false) if is_instance_valid(view.enemy_overlay) else null
	expect(stance_list != null and stance_list.get_child_count() == 3 and not view.layout.visible, "Clicking a campaign enemy did not reveal its three stance cards.")
	if stance_list != null:
		var first_preview = stance_list.get_child(0)
		var second_preview := stance_list.get_child(1) as Control
		expect(second_preview.position.x > first_preview.position.x and second_preview.position.y == first_preview.position.y, "Stance cards were not arranged side by side.")
		var first_card: Button = first_preview.buttons[0]
		expect(first_card.size.x >= 380 and first_card.size.y >= 220, "Inspector stance face did not fill its card slot.")
		var intent := first_card.find_child("Intent", true, false) as RichTextLabel
		var rules := first_card.find_child("ReactionRules", true, false) as RichTextLabel
		expect(intent != null and "Intent" in intent.get_parsed_text() and "Attack" in intent.get_parsed_text() and "attack" in intent.get("icon_keys") and intent.fit_content and first_card.get_global_rect().encloses(intent.get_global_rect()), "Full intent text did not fit on the inspector card.")
		expect(rules != null and "Attack" in rules.get_parsed_text() and "attack" in rules.get("icon_keys") and rules.get_parsed_text().split("\n").size() == 3 and rules.get_parent().get_child(0).has_meta("reaction_badge") and first_card.get_global_rect().encloses(rules.get_global_rect()), "Full reaction name, trigger, effect, and badge did not fit on the inspector card.")
		expect(first_card.find_child("OwnerPosition", true, false) is TextureRect, "Inspector card did not show the enemy position below its portrait.")
		var escape := InputEventAction.new()
		escape.action = "ui_cancel"
		escape.pressed = true
		root.push_input(escape)
		await flush()
		expect(view.enemy_overlay == null and view.layout.visible and enemy_button.has_focus() and view.selected_id == "grassland_first" and campaign.run.pending.is_empty(), "Closing inspection did not return to the same encounter without launching.")
	var atlas = view.atlas
	var opening_camera: Dictionary = atlas.camera()
	expect(opening_camera.zoom == 2.5 and opening_camera.center.distance_to(Vector2(0.34, 0.795)) < 0.001, "Atlas did not open focused on Grassland.")
	var marker: Button = atlas.buttons.grassland_first
	expect(marker.size == Vector2(82, 82) and marker.call("_has_point", marker.size / 2) and not marker.call("_has_point", Vector2.ZERO), "Encounter marker size or circular hit area is incorrect.")
	atlas.zoom_by(0.1)
	expect(atlas.camera().zoom == 1.0 and marker.size.x < 82, "Zooming out did not reveal the full atlas with smaller markers.")
	atlas.reset_camera()
	expect(atlas.camera() == opening_camera, "Reset View did not restore the opening view.")
	atlas.zoom_by(0.1)
	atlas.zoom_by(2)
	var camera: Dictionary = atlas.camera()
	expect(camera.zoom == 2 and camera.center.distance_to(Vector2(0.5, 0.5)) < 0.001, "Zoom did not preserve its focal point.")
	await motion(Vector2(140, 150))
	await mouse(Vector2(140, 150), true)
	await motion(Vector2(180, 90), true)
	await mouse(Vector2(180, 90), false)
	expect(atlas.camera().center != camera.center, "Dragging the atlas did not pan the map.")
	camera = atlas.camera()
	view._open_docks()
	await flush()
	expect(view.docks_overlay.size == root.get_visible_rect().size and not view.layout.visible, "Docks did not open as a full-screen modal.")
	view._close_docks()
	expect(view.atlas == atlas and atlas.camera() == camera, "Closing the docks reset the map camera.")
	view._select("air_boss")
	view._select("grassland_first")
	view._open_sortie()
	await scene_changed
	var preparation = current_scene
	expect(preparation.name == "CampaignSortie" and preparation.campaign_sortie and not preparation.launch_button.disabled, "Dedicated sortie did not open fleet preparation.")
	expect(preparation._selectable_ships().size() == 2 and preparation._selectable_captains().size() == 2 and preparation.draft.setup.fleet.size() == 2, "Sortie exposed unowned roster or the wrong capacity.")
	preparation._change(3, 0, "level")
	expect(preparation.draft.setup.fleet[0].level == 1, "Sortie allowed a free upgrade.")
	preparation._back()
	await scene_changed
	view = current_scene
	await flush()
	expect(view.selected_id == "grassland_first" and view.atlas.camera() == camera and campaign.run.pending.is_empty(), "Returning from sortie changed the encounter, camera or save.")
	view._open_sortie()
	await scene_changed
	current_scene.launch_button.pressed.emit()
	await scene_changed
	var battle = current_scene
	expect(battle.state.ships.size() == 2 and battle.state.enemy_row.size() == 1 and battle.stance_panel.buttons.size() == 1 and battle.menu.get_item_index(3) < 0 and battle.menu.get_item_index(4) < 0, "Campaign battle showed test outcomes or used a custom fleet.")
	expect(battle.stance_panel.reaction_buttons.size() == 1, "The campaign enemy's reaction did not appear on its card.")
	battle._navigate("res://scenes/victory.tscn")
	expect(not campaign.run.pending.is_empty(), "A test navigation granted campaign rewards.")
	_kill(battle.state, -1)
	battle._render()
	await scene_changed
	expect(current_scene.get_node("%PrimaryButton").text == "Return to Map" and campaign.run.materials == 6, "Campaign result did not settle through the battle screen.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	expect(is_instance_valid(current_scene.atlas) and campaign.run.pending.is_empty(), "Campaign result did not return to the map.")
