extends "res://tests/drag_drop.gd"


func _run() -> void:
	_test_rules()
	await _test_ship_dragging()
	await _test_editor()
	done("Basic ship actions")


func _test_rules() -> void:
	var doc := neutral()
	var b = State.new(9, doc)
	var uid := uid_for(b, "brace")
	var before: String = JSON.stringify(b.board_snapshot())
	expect(b.play_basic(uid, 0) != "" and JSON.stringify(b.board_snapshot()) == before, "Full-hull repair consumed a card or mutated state.")
	b.ships[0].hull = 27
	b.definitions.cards.brace.cost = 99
	b.definitions.cards.brace.allowed_positions = ["rear"]
	var rng_before: int = b.rng.state
	var preview: Dictionary = b.basic_preview(uid, 0)
	expect(preview.ok and "+1 hull" in preview.text and "Discard Brace for Impact" in preview.text, "Basic repair preview did not cap healing or explain its cost.")
	expect(b.ships[0].hull == 27 and b.rng.state == rng_before and b.hand.has(uid), "Basic preview mutated hull, RNG, or hand.")
	expect(b.play_basic(uid, 0) == "" and b.ships[0].hull == 28, "Basic repair failed to ignore printed cost/rank or cap hull.")
	expect(b.discard == [uid] and b.circle.all(func(card): return card < 0) and conserved(b), "Basic repair did not discard exactly its card outside the circle.")
	expect(b.feedback_events.filter(func(event): return event.kind == "card_triggered").is_empty(), "Discarded basic-action card fired circle triggers.")
	expect(b.validate_basic(uid, 0) != "", "Spent card could be reused for a basic action.")
	b = State.new(9, doc)
	uid = uid_for(b, "brace")
	expect(b.play_basic(uid, 2) != "" and b.hand.has(uid), "Nonadjacent swap accepted or consumed payment.")
	expect(b.play_basic(uid, 1) == "" and b.formation == [1, 0, -1, 2], "Adjacent ship swap failed.")
	expect(b.discard == [uid] and b.root_context.tags == ["Movement"] and b.root_context.cost == 0, "Basic swap cost or reaction tags incorrect.")
	expect(conserved(b) and b.play_order.is_empty(), "Basic swap lost cards or occupied the circle.")
	b = State.new(9, neutral())
	all_in_hand(b)
	for slot in 9:
		b.play(b.hand[0], [], -1, -1, slot)
	uid = b.hand[0]
	var owner: int = b.card(uid).owner
	b.ships[owner].hull = int(b.ships[owner].max_hull) - 8
	var hull_before: int = b.ships[owner].hull
	var circle_before: Array = b.circle.duplicate()
	expect(b.play_basic(uid, owner) == "" and b.ships[owner].hull == hull_before + 2, "Full circle blocked a basic ship repair.")
	expect(b.circle == circle_before and b.expanded and conserved(b), "Basic action changed a full circle or lost a card.")
	b = State.new(9, doc)
	b._damage(1, 999)
	b._cleanup()
	expect(b.formation[1] == -1 and b.ships[1].last_position == 1, "Destroyed position was not remembered.")
	expect(b.play_basic(uid_for(b, "broadside"), 0) != "" and b.play_basic(uid_for(b, "brace"), 1) != "", "Defeated ship was allowed to swap.")
	uid = uid_for(b, "salvo")
	expect(b.play_basic(uid, 1) == "" and b.ships[1].hull == 0 and b.ships[1].recovery == 2, "First recovery action revived early or failed to accumulate.")
	expect(not b.formation.has(1) and b.result_summary("victory").survivors == 2, "Recovering wreck counted as a survivor.")
	b.end_phase()
	expect(b.ships[1].recovery == 2, "Recovery progress was lost at turn boundary.")
	b.refresh([])
	all_in_hand(b)
	uid = uid_for(b, "broadside")
	preview = b.basic_preview(uid, 1)
	expect(preview.ok and "REVIVE with 4 hull at Upper Middle" in preview.text, "Revival preview missing destination or hull.")
	expect(b.play_basic(uid, 1) == "" and b.ships[1].hull == 4 and b.formation[1] == 1, "Recovery threshold did not revive the ship.")
	expect(b.ships[1].recovery == 0 and b.ships[1].guard == 0 and b.result_summary("victory").survivors == 3, "Revive retained stale progress/guard or wrong result totals.")
	expect(conserved(b), "Revival lost a physical card.")
	b._damage(1, 999)
	b._cleanup()
	expect(b.ships[1].recovery == 0 and not b.formation.has(1), "Second destruction retained revival state.")
	b._swap_points(0, 1)
	b.ships[1].recovery = 2
	uid = uid_for(b, "strafe")
	expect(b.play_basic(uid, 1) == "" and b.formation[0] == 1 and b.formation[1] == 0, "Revive did not use first empty position when former slot was occupied.")

	# Basic actions participate in visible enemy reactions, but not circle events.
	doc = neutral()
	doc.leviathans[0].stances[0].reactions = [{"id": "scent", "name": "Recovery Scent", "trigger": {"kind": "healed", "threshold": 1}, "effects": [{"kind": "damage_ship", "target": "repaired", "amount": 1}]}]
	b = State.new(3, doc)
	b._damage(1, 999)
	b._cleanup()
	b.play_basic(uid_for(b, "broadside"), 1)
	expect(b.ships[1].recovery == 2 and b.feedback_events.filter(func(event): return event.kind == "reaction_triggered").is_empty(), "Recovery below threshold counted as actual hull healing.")
	preview = b.basic_preview(uid_for(b, "salvo"), 1)
	expect("REACTION: Recovery Scent" in preview.text and "final hull: 0 → 3" in preview.text, "Revival reaction consequences missing from preview.")
	b.play_basic(uid_for(b, "salvo"), 1)
	expect(b.ships[1].hull == 3 and b.feedback_events.filter(func(event): return event.kind == "reaction_triggered").size() == 1, "Revival did not resolve its single visible reaction.")
	doc.leviathans[0].stances[0].reactions[0] = {"id": "wings", "name": "Swap Gust", "trigger": {"kind": "tag", "tag": "Movement"}, "effects": [{"kind": "damage_ship", "target": "actor", "amount": 2}]}
	b = State.new(3, doc)
	b.play_basic(uid_for(b, "brace"), 1)
	expect(b.formation[1] == 0 and b.ships[0].hull == 26, "Swap did not provoke Movement reaction after changing position.")
	doc.setup["basic_actions"] = {"repair": 3, "revive_threshold": 5}
	b = State.new(3, doc)
	b._damage(1, 999)
	b._cleanup()
	b.play_basic(uid_for(b, "broadside"), 1)
	expect(b.ships[1].recovery == 3 and b.ships[1].hull == 0, "Configured basic repair amount ignored.")
	b.play_basic(uid_for(b, "salvo"), 1)
	expect(b.ships[1].hull == 5, "Crossing a configured threshold did not revive at that threshold.")
	doc.setup.basic_actions.revive_threshold = 50
	b = State.new(3, doc)
	b._damage(1, 999)
	b._cleanup()
	b.ships[1].recovery = 49
	b.play_basic(uid_for(b, "broadside"), 1)
	expect(b.ships[1].hull == 20, "Revived hull exceeded maximum hull.")
	doc.setup.basic_actions.repair = 0
	expect(not Catalog.validate(doc).is_empty(), "Zero basic repair passed validation.")
	doc.setup.basic_actions = {"repair": 2, "revive_threshold": -1}
	expect(not Catalog.validate(doc).is_empty(), "Invalid revive threshold passed validation.")
	doc.setup.basic_actions = "bad"
	expect(not Catalog.validate(doc).is_empty(), "Malformed basic action configuration passed validation.")
	b = State.new(3, neutral())
	for ship_id in 3:
		b._damage(ship_id, 999)
	b._cleanup()
	expect(b.outcome == "defeat" and b.play_basic(uid_for(b, "salvo"), 1) != "", "Fleet destruction did not end the encounter.")


func hover_ship(battle, ship_id: int) -> Vector2:
	var widget: Control = battle.allies.target_widget(ship_id)
	var point: Vector2 = widget.get_global_transform_with_canvas() * (widget.size / 2)
	await motion(point, true)
	return point


func _test_ship_dragging() -> void:
	root.size = Vector2i(1280, 800)
	await open_battle(neutral())
	var battle = current_scene
	battle.state.ships[0].hull = 24
	battle._render()
	await begin_drag(battle, "brace")
	expect("+2 hull" in battle.allies.target_widget(0).tooltip_text, "Repair target tooltip missing heal amount.")
	expect("Swap Bastion ↔ Kestrel" in battle.allies.target_widget(1).tooltip_text, "Adjacent swap tooltip missing ships.")
	expect("adjacent" in battle.allies.target_widget(2).tooltip_text, "Nonadjacent target lacks rejection explanation.")
	var point := await hover_ship(battle, 0)
	expect(battle.drag_hover_ship == 0 and battle.drag_hover_slot == -1 and "Repair Bastion" in battle.get_node("%Inspection").text, "Ship hover did not switch to basic repair preview.")
	expect(battle.allies.target_widget(0).get_theme_stylebox("normal").border_color == Color("#e8bd77"), "Hovered valid ship lacks gold highlight.")
	await mouse(point, false)
	expect(battle.basic_target == 0 and battle.selected_slot == -1 and battle.state.ships[0].hull == 24, "Ship drop auto-resolved or selected the circle.")
	expect(battle.get_node("%PlayButton").text == "Repair / Recover" and not battle.get_node("%TargetChoice").visible, "Basic repair confirmation controls incorrect.")
	var repair_uid: int = battle.selected_uid
	await begin_drag(battle, "tow")
	point = await hover_ship(battle, 2)
	expect(not battle._can_drop_ship(battle.drag_payload, 2) and "full hull" in battle.get_node("%Inspection").text, "Full-hull basic target was accepted or unexplained.")
	await mouse(point, false)
	expect(battle.basic_target == 0 and battle.selected_uid == repair_uid, "Invalid ship drop lost the previously selected basic action.")
	await begin_drag(battle, "tow")
	point = await hover_slot(battle, 0)
	expect(battle.drag_hover_ship == -1 and battle.circle_view.selected == 0, "Moving from ship targets to circle preview left stale hover state.")
	await motion(Vector2(400, 410), true)
	await mouse(Vector2(400, 410), false)
	expect(battle.basic_target == 0 and battle.state.ships[0].hull == 24, "Cancelling a circle drag changed or resolved the basic action draft.")
	field_key(battle, "tow").pressed.emit()
	expect(battle.basic_target == -1 and battle.payment.is_empty() and battle.selected_uid == uid_for(battle.state, "tow"), "Selecting another card added misleading payment to a basic action.")
	await begin_drag(battle, "brace")
	point = await hover_ship(battle, 0)
	await mouse(point, false)
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.ships[0].hull == 26 and battle.state.discard.size() == 1 and battle.basic_target == -1, "Confirmed repair failed to discard/unlock.")
	await begin_drag(battle, "advance")
	point = await hover_ship(battle, 1)
	await mouse(point, false)
	expect(battle.basic_target == 1 and battle.get_node("%PlayButton").text == "Swap Ships", "Adjacent drag did not select a basic swap.")
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.formation == [1, 0, -1, 2] and battle.state.play_order.is_empty(), "Native ship drop swap failed or entered the circle.")

	await open_battle(neutral())
	battle = current_scene
	battle.state._damage(1, 999)
	battle.state._cleanup()
	battle._render()
	expect(battle.allies.wreck_widgets.has(1) and "Recovery 0 / 4" in battle.allies.wreck_widgets[1].text, "Defeated ship lacks a visible recovery target.")
	await begin_drag(battle, "salvo")
	point = await hover_ship(battle, 1)
	expect("0 → 2 / 4" in battle.get_node("%Inspection").text and battle.circle_view.valid_drop_slots.is_empty(), "Defeated owner's card could not preview recovery or was circle-playable.")
	await mouse(point, false)
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.ships[1].recovery == 2 and "Recovery 2 / 4" in battle.allies.wreck_widgets[1].text, "Recovery progress did not update on the wreck target.")
	await begin_drag(battle, "broadside")
	point = await hover_ship(battle, 1)
	expect("REVIVE with 4 hull" in battle.allies.wreck_widgets[1].tooltip_text, "Threshold-crossing tooltip does not announce revival.")
	await mouse(point, false)
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.ships[1].hull == 4 and not battle.allies.wreck_widgets.has(1), "Native wreck recovery did not revive and replace the target.")
	expect(battle.allies.widgets[1].get_meta("ship_index") == 1 and not battle.busy and conserved(battle.state), "Revived unit, feedback unlock, or card conservation incorrect.")
	await flush()
	expect(battle.feedback.overlay.get_child_count() == 1, "Basic action animations leaked transient nodes.")


func _test_editor() -> void:
	var content_store = root.get_node("ContentStore")
	content_store.saved = fixture.duplicate(true)
	content_store.editor_state = {}
	content_store.migration_pending = false
	change_scene_to_file("res://scenes/editor.tscn")
	await scene_changed
	var editor = current_scene
	expect(editor.setup_controls.basic_repair.value == 2 and editor.setup_controls.revive_threshold.value == 4, "Editor did not show backwards-compatible basic action defaults.")
	editor.setup_controls.basic_repair.value = 3
	editor.setup_controls.revive_threshold.value = 5
	expect(editor.draft.setup.basic_actions == {"repair": 3, "revive_threshold": 5} and editor.is_dirty(), "Editor basic action values did not update the draft.")
	expect(Catalog.compile(editor.draft).basic_actions.repair == 3, "Compiled battle ignored authored basic action rules.")
	var path := "user://basic_action_test.json"
	expect(Catalog.save_document(path, editor.draft) == "" and Catalog.read_document(path).document.setup.basic_actions.revive_threshold == 5, "Basic action rules did not survive save/reload.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
