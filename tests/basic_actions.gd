extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var cases := [
		[[-1, 0, -1, -1], [0, -1, -1, -1]],
		[[-1, -1, 0, -1], [0, -1, -1, -1]],
		[[-1, -1, -1, 0], [0, -1, -1, -1]],
		[[-1, 0, -1, 1], [1, 0, -1, -1]],
		[[0, -1, -1, 1], [0, 1, -1, -1]],
		[[0, 1, -1, 2], [0, 1, -1, 2]],
		[[-1, 0, 1, -1], [-1, 0, 1, -1]],
		[[-1, 0, 1, 2], [2, 0, 1, -1]],
		[[0, 1, 2, 3], [0, 1, 2, 3]],
	]
	for entry in cases:
		var formation: Array = entry[0].duplicate()
		Geometry.normalize_formation(formation)
		expect(formation == entry[1], "Incorrect automatic formation correction for %s." % [entry[0]])
	var doc := neutral()
	for slot in doc.setup.fleet:
		if slot.position == "rear": slot.position = "lower"
	doc.setup.fleet[0].position = "rear"
	doc.setup.enemies[0].position = "rear"
	var b = State.new(1, doc)
	expect(b.formation[0] == 0 and b.formation[3] == -1 and b.enemy_formation[0] == 0, "Unsupported starting Rear did not advance on both sides.")
	b = State.new(1, neutral())
	b.formation = [-1, 0, 1, -1]
	var rear_preview: Dictionary = b.basic_preview(uid_for(b, "brace"), 103)
	expect(rear_preview.ok and b.formation == [-1, 0, 1, -1], "Automatic Rear correction should be previewable without moving the live fleet.")
	b.formation = [1, 0, -1, 2]
	b.ships[1].hull = 0
	b._cleanup()
	expect(b.formation == [2, 0, -1, -1] and b.feedback_events.any(func(event): return event.kind == "movement" and event.get("automatic", false)), "Rear did not advance with movement feedback after Front was defeated.")
	b = State.new(1, neutral())
	var uid := uid_for(b, "brace")
	b.ships[0].hull = 24
	expect(b.basic_preview(uid, 0).ok and b.ships[0].hull == 24, "Basic preview mutates.")
	expect(b.play_basic(uid, 0) == "" and b.ships[0].hull == 26 and b.discard.has(uid), "Basic repair did not discard for two hull.")
	expect(b.play_order.is_empty() and conserved(b), "Basic put card in circle/lost cards.")
	b = State.new(1, neutral())
	expect(b.play_basic(uid_for(b, "brace"), 1) == "" and b.formation == [1,0,-1,2], "Adjacent swap failed.")
	expect(b.validate_basic(uid_for(b, "patch"), 1) != "", "Nonadjacent swap accepted.")
	b = State.new(1, neutral())
	b.ships[0].hull = 0
	b.ships[0].resource = 4
	b._cleanup()
	expect(b.ships[0].resource == 0 and b.position_of(0) == -1, "Defeat did not reset resource.")
	expect(b.play_basic(uid_for(b, "brace"), 0) == "" and b.ships[0].recovery == 2 and b.ships[0].hull == 0, "Recovery threshold ignored.")
	all_in_hand(b)
	expect(b.play_basic(uid_for(b, "brace"), 0) == "" and b.ships[0].hull == 6 and b.position_of(0) >= 0, "Basic repair did not revive at six hull.")
	var recovery_doc := neutral()
	card_def(recovery_doc, "brace").rules[0].effects = [{"kind":"repair", "target":"chosen_ally", "amount":4}]
	b = State.new(1, recovery_doc)
	b.ships[1].hull = 0
	b._cleanup()
	expect(b.outcome.is_empty() and b.feedback_events.any(func(event): return event.kind == "disabled" and event.target == 1), "Zero hull should disable a ship while allies remain.")
	uid = uid_for(b, "brace")
	expect(b.choices(uid).any(func(choice): return choice.value == 1), "Ordinary repair cannot target a disabled ship.")
	expect(b.play(uid, [], 1, -1, 0) == "" and b.ships[1].hull == 6 and b.position_of(1) >= 0, "Ordinary repair did not return the disabled ship to formation at six hull.")
	for ship in b.ships: ship.hull = 0
	b._cleanup()
	expect(b.outcome == "defeat", "All ships at zero hull should immediately end the battle in defeat.")
	root.size = Vector2i(1280,800)
	await open_battle(neutral())
	var ui = current_scene
	ui.state.ships[0].hull = 24
	ui._render()
	await begin_drag(ui, "brace")
	var point := await hover_ship(ui, 0)
	expect(ui.drag_hover_ship == 0, "Self repair hover not identified.")
	await mouse(point,false)
	await settle(ui)
	expect(not ui.pending_play and ui.state.ships[0].hull==26 and ui.state.discard.size()==1,"Repair did not resolve immediately on drop.")
	expect(ui.get_node_or_null("%ManoeuvreButton")==null,"Redundant manoeuvre button remains.")
	await open_battle(neutral())
	ui=current_scene
	await begin_drag(ui,"brace")
	point=await hover_ship(ui,102)
	expect(ui.drag_hover_ship==102,"Empty position did not accept movement hover.")
	await mouse(point,false)
	await settle(ui)
	expect(ui.state.formation[2]==0 and ui.state.formation[0]==2 and ui.state.formation[3]==-1,"Drop into an empty flank did not move the Rear ship to the vacated Front.")
	expect(ui.state.discard.size()==1 and conserved(ui.state),"Basic move did not consume exactly one card.")
	await open_battle(neutral())
	ui = current_scene
	var enemy: Dictionary = ui.state.unit(-1)
	var initial_hull: int = enemy.hull
	enemy.armour = 1
	ui.state.ships[0].weapon = {"damage": 3, "range": "Short"}
	ui.state.enemy_formation = [-1, -1, -1, 0]
	uid = uid_for(ui.state, "brace")
	expect(ui.state.validate_basic(uid, -1).contains("Rear"), "Short basic attack can target Rear.")
	ui.state.enemy_formation = [0, -1, -1, -1]
	ui.state.formation = [-1, 1, 2, 0]
	expect(ui.state.validate_basic(uid, -1).contains("Rear"), "Short basic attack can originate in Rear.")
	ui.state.formation = [0, 1, -1, 2]
	ui._render()
	await begin_drag(ui, "brace")
	point = await hover_ship(ui, -1)
	expect(ui.drag_hover_ship == -1 and ui.enemies.target_widget(-1).tooltip_text.contains("attacks"), "Enemy drag preview is missing.")
	expect(enemy.hull == initial_hull and ui.state.hand.has(uid), "Attack preview spent the card or damaged the enemy.")
	var circle: Panel = ui.enemies.basic_indicators.get(-1)
	expect(circle != null and is_equal_approx(circle.size.x, circle.size.y) and is_equal_approx(float(circle.get_theme_stylebox("panel").corner_radius_top_left), circle.size.x / 2.0) and "attack" in circle.get_child(0).icon_keys and "3" in circle.get_child(0).source_text, "Basic attack did not show its effect and icon inside a circle.")
	await mouse(point, false)
	await settle(ui)
	expect(ui.enemies.basic_indicators.is_empty(), "Basic target circles remained after the drop.")
	expect(enemy.hull == initial_hull - 2 and ui.state.discard == [uid], "Basic attack did not discard the card and use weapon damage through armour.")
	expect(ui.state.play_order.is_empty() and not ui.pending_play and conserved(ui.state), "Basic attack entered the circle or required confirmation.")
	var weapon_doc := neutral()
	var shipped: Dictionary = Catalog.read_document("res://data/content.json").document
	var damage: Dictionary = card_def(shipped, "broadside").rules[0].effects[0].damage
	expect(ship_def(shipped, "kestrel").weapon.damage == 3 and R.text("value", damage) == "Weapon +2", "Kestrel and Broadside must author the base damage and card bonus separately.")
	card_def(weapon_doc, "brace").rules[0].effects = [{"kind":"attack", "target":"chosen_enemy", "range":"weapon", "damage":damage}]
	ship_def(weapon_doc, "bastion").weapon.damage = 3
	b = State.new(1, weapon_doc)
	var enemy_hull: int = b.unit(-1).hull
	expect(b.play_basic(uid_for(b, "brace"), -1) == "" and b.unit(-1).hull == enemy_hull - 3, "Basic attacks should use authored weapon damage.")
	b = State.new(1, weapon_doc)
	expect(b.play(uid_for(b, "brace"), [], -1, -1, 0) == "" and b.unit(-1).hull == enemy_hull - 5, "Weapon-based cards should apply their authored bonus.")
	done("Basic attack, recovery and movement")
