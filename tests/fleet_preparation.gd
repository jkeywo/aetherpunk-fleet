extends "res://tests/support/v3_test.gd"
func select_value(prep, key: String, value: Variant) -> void:
	if not prep.controls.has(key):
		var index:=int(key.get_slice("_",1))
		if key.begins_with("ship_"):
			prep._show_ships()
			for column in prep.ship_comparison.get_children():
				for child in column.get_children():
					if child.get_meta("choose_ship","")==value:child.pressed.emit();break
			prep.ship_dialog.hide()
		elif key.begins_with("captain_"):
			prep._show_captains()
			for column in prep.captain_comparison.get_children():
				for child in column.get_children():
					if child.get_meta("assign_captain","")==value:child.pressed.emit();break
			prep.captain_dialog.hide()
		else:
			prep._drop_at(Vector2.ZERO,{"kind":"ship","ship":prep.draft.setup.fleet[index].ship,"preparation":prep.get_instance_id()},Geometry.POSITIONS.find(value))
		await flush()
		return
	prep._show_ship_info(int(key.get_slice("_",key.get_slice_count("_")-1)))
	var menu: OptionButton = prep.controls[key]
	for index in menu.item_count:
		if typeof(menu.get_item_metadata(index)) == typeof(value) and menu.get_item_metadata(index) == value:
			menu.select(index)
			menu.item_selected.emit(index)
			await flush()
			return
	expect(false,"Missing preparation option " + key + ": " + str(value))

func preview_faces(prep) -> Array:
	return prep.deck_cards.get_children().map(func(column): return column.get_child(column.get_child_count() - 1))

func _run() -> void:
	root.size = Vector2i(1280,800)
	var store_node = root.get_node("ContentStore")
	var session = root.get_node("BattleSession")
	store_node.saved = fixture.duplicate(true)
	var saved := JSON.stringify(store_node.saved)
	var project_hash := FileAccess.get_sha256("res://data/content.json")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	var prep = current_scene
	await flush()
	expect(prep.name == "FleetPreparation" and prep.controls.size() == 3,"Start Game did not open preparation controls.")
	expect(prep.fixed_available and prep._candidate().setup.fixed_hand and not prep.launch_button.disabled,"Saved opening not preserved.")
	expect("18 cards" in prep.status.text and "ARMOUR 3" in prep.details[0].text,"Fleet/card/effective-stat preview incorrect.")
	expect(preview_faces(prep).map(func(face): return face.get_meta("card_id")) == ["brace", "field_orders", "escort"] and "6 cards" in prep.deck_summary.text, "Initial selected-ship deck preview is incomplete.")
	expect(preview_faces(prep).all(func(face): return face.get_meta("copies") == 2 and face.owner_info.name == "Bastion" and not face.labels.rules.text.is_empty()), "Card previews lost copy counts, ship styling, or rules.")
	await select_value(prep,"ship_0","kestrel")
	expect(prep.draft.setup.fleet[0].ship == "kestrel" and prep.draft.setup.fleet[1].ship == "bastion","Choosing an occupied ship did not swap unique assignments.")
	await select_value(prep,"captain_0","rook")
	expect(prep.draft.setup.fleet[0].captain == "rook" and prep.draft.setup.fleet[1].captain == "iona","Captain reassignment duplicated a captain.")
	expect(preview_faces(prep)[1].get_meta("card_id") == "command_barrage" and preview_faces(prep)[1].owner_info.name == "Kestrel", "Captain assignment did not update card preview or acting ship.")
	await select_value(prep,"level_0",3)
	expect(preview_faces(prep).size() == 4 and "8 cards" in prep.deck_summary.text, "Level 3 preview does not show both upgrade pairs.")
	var level_three: OptionButton = prep.controls.level_3_0
	var options: Array = []
	for index in level_three.item_count: options.append(level_three.get_item_metadata(index))
	expect(not options.has("artillery") and options.size() == 2,"Blocked level-3 option was selectable.")
	expect(not level_three.get_popup().get_item_tooltip(0).is_empty(),"Upgrade option lacks reward tooltip.")
	await select_value(prep,"level_3_0","conductor")
	expect(preview_faces(prep)[3].get_meta("card_id") == "cyclone_salvo" and "Level 3" in preview_faces(prep)[3].get_meta("origin"), "Level-3 branch preview did not change.")
	await select_value(prep,"level_2_0","assault")
	expect(preview_faces(prep)[2].get_meta("card_id") == "strafe", "Level-2 branch preview did not change.")
	expect(prep.draft.setup.fleet[0].level_3 == "conductor","Shared legal level-3 choice did not survive branch change.")
	await select_value(prep,"level_3_0","artillery")
	await select_value(prep,"level_2_0","defence")
	expect(prep.draft.setup.fleet[0].level_3 != "artillery","Branch switch left an illegal level-3 choice.")
	await select_value(prep,"level_0",1)
	expect(prep.draft.setup.fleet[0].level_2 == "" and prep.draft.setup.fleet[0].level_3 == "" and prep.controls.level_2_0.disabled and prep.controls.level_3_0.disabled,"Lowering level kept active upgrade branches.")
	expect(not prep._candidate().setup.fixed_hand and "opening" not in prep.status.text.to_lower(),"Incompatible saved opening did not fall back to shuffled.")
	expect(preview_faces(prep).size() == 2 and "4 cards" in prep.deck_summary.text, "Lowering level left upgrade cards in preview.")
	prep._show_deck()
	await flush()
	expect(prep.ship_info_dialog.visible and prep.deck_preview.is_visible_in_tree(), "Ship info did not reveal card previews.")
	await select_value(prep,"position_0","rear")
	expect(prep.draft.setup.fleet[2].position == "front","Occupied position was duplicated.")
	var chosen: Array = prep.draft.setup.fleet.duplicate(true)
	expect(JSON.stringify(store_node.saved) == saved and FileAccess.get_sha256("res://data/content.json") == project_hash,"Preparation changed authored content.")
	prep._back()
	await scene_changed
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	prep = current_scene
	expect(prep.draft.setup.fleet == chosen,"Returning from main menu lost session preparation.")
	prep.launch_button.pressed.emit()
	await scene_changed
	current_scene.start_button.pressed.emit()
	await scene_changed
	var battle = current_scene
	battle.feedback.duration_scale = 0.01
	expect(battle.state.document.setup.fleet == chosen and battle.state.card_keys.size() == 16,"Launch ignored prepared levels/loadout.")
	expect(battle.state.definitions.cards.command_barrage.owner == 0 and battle.state.formation == [2,1,-1,0],"Prepared captain owner/order was not applied.")
	var returned: Dictionary = session.battle_content(store_node.saved)
	returned.setup.fleet[0].level = 3
	expect(session.prepared_content.setup.fleet[0].level == 1,"Battle content snapshot leaked mutable references.")
	battle.state.ships[0].hull = 1
	battle.get_node("%WinButton").pressed.emit()
	await scene_changed
	expect(current_scene.find_child("PrepareFleet",true,false) != null,"Result has no route back to preparation.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	battle = current_scene
	expect(battle.state.document.setup.fleet == chosen and battle.state.ships[0].hull == 20 and battle.state.round_number == 1,"Retry did not reset the same prepared fleet.")
	battle.get_node("%WinButton").pressed.emit()
	await scene_changed
	current_scene.find_child("PrepareFleet",true,false).pressed.emit()
	await scene_changed
	prep = current_scene
	expect(prep.draft.setup.fleet == chosen,"Result preparation route lost selection.")
	prep._reset()
	expect(prep.draft.setup.fleet == fixture.setup.fleet and prep._candidate().setup.fixed_hand,"Reset did not restore saved fleet/opening.")
	# Editor playtests continue to use authored setup, even after a prepared battle.
	store_node.path = "user://fleet_preparation_editor_test.json"
	change_scene_to_file("res://scenes/editor.tscn")
	await scene_changed
	current_scene._test_battle()
	await scene_changed
	expect(current_scene.state.document.setup.fleet == fixture.setup.fleet and session.editor_playtest,"Prepared fleet leaked into editor playtest.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store_node.path))
	# Saved content changes invalidate stale cached choices rather than dangling references.
	store_node.saved.ships[0].hull = 29
	change_scene_to_file("res://scenes/fleet_preparation.tscn")
	await scene_changed
	prep = current_scene
	expect(prep.draft.setup.fleet == fixture.setup.fleet and "HULL 29" in prep.details[0].text,"Changed saved content reused stale preparation definitions.")
	expect(FileAccess.get_sha256("res://data/content.json") == project_hash,"Preparation integration wrote repository content.")
	done("Fleet preparation flow")
