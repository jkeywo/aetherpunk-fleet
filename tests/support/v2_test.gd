extends SceneTree
const Catalog = preload("res://scripts/content_catalog.gd")
const State = preload("res://scripts/battle_state.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
var fixture: Dictionary = Catalog.migrate(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/diamond_content.json")))
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(text)


func done(label: String) -> void:
	print("%s: %d checks, %d failures." % [label, checks, failures])
	quit(1 if failures > 0 else 0)


func neutral() -> Dictionary:
	var doc := fixture.duplicate(true)
	for card in doc.cards:
		card.cost = 0
		card.positions = Geometry.POSITIONS.duplicate()
		card.tags = ["Attack"]
		card.effects = [{"kind": "guard", "target": "actor", "amount": 0}]
		card.on_play = []
		card.modifiers = []
		card.triggers = []
	doc.leviathans[0].stances = [{"id": "quiet", "name": "Quiet", "reactions": [], "effects": []}]
	doc.leviathans[0].starting_stance = "quiet"
	return doc


func uid_for(battle, key: String) -> int:
	for uid in battle.hand:
		if battle.card_keys[uid] == key:
			return uid
	return -1


func card_def(doc: Dictionary, id: String) -> Dictionary:
	return doc.cards[Catalog.index_by_id(doc.cards, id)]


func all_in_hand(battle) -> void:
	battle.hand = battle.hand + battle.deck + battle.discard
	battle.deck.clear()
	battle.discard.clear()


func conserved(battle) -> bool:
	var ids: Array = battle.hand + battle.deck + battle.discard + battle.held + battle.play_order
	var unique: Dictionary = {}
	for uid in ids:
		unique[uid] = true
	return ids.size() == battle.card_keys.size() and unique.size() == ids.size()


func trigger(id: String, event: String, effects: Array) -> Dictionary:
	return {"id": id, "name": id, "event": event, "tag": "", "threshold": 1,
		"condition": {"tag": "", "min": 0}, "effects": effects}


func field_key(battle, key: String) -> Button:
	for button in battle.hand_view.get_children():
		if battle.state.card_keys[button.get_meta("uid")] == key:
			return button
	return null


func flush() -> void:
	await process_frame
	await process_frame


func select_option(control: OptionButton, value: String) -> void:
	for index in control.item_count:
		if str(control.get_item_metadata(index)) == value:
			control.select(index)
			control.item_selected.emit(index)
			return
	expect(false, "Missing option " + value)


func open_battle(doc: Dictionary = {}) -> void:
	root.get_node("ContentStore").saved = fixture.duplicate(true) if doc.is_empty() else doc.duplicate(true)
	root.get_node("ContentStore").migration_pending = false
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	current_scene.feedback.duration_scale = 0.02
	await flush()


func _run() -> void:
	pass


func stage_card(battle, key: String, slot: int) -> void:
	battle._select(uid_for(battle.state, key))
	battle._circle_selected(slot)


func choose_first_targets(battle) -> void:
	for id in ["%TargetChoice", "%MovementChoice"]:
		var control: OptionButton = battle.get_node(id)
		if control.item_count > 1 and control.get_item_id(0) == -999:
			control.select(1)
			control.item_selected.emit(1)


func pay_with(battle, key: String) -> void:
	field_key(battle, key).pressed.emit()
	await battle.payment_finished
