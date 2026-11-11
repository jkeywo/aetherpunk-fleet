extends SceneTree
const Catalog = preload("res://scripts/content_catalog.gd")
const R = preload("res://scripts/rules/rule_registry.gd")
const State = preload("res://scripts/battle_state.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
var fixture: Dictionary = Catalog.migrate(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/fleet_content.json")))
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func _run() -> void: pass
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func done(label: String) -> void:
	print("%s: %d checks, %d failures." % [label, checks, failures])
	quit(1 if failures > 0 else 0)
func flush() -> void:
	await process_frame
	await process_frame
func neutral(multi: bool = false) -> Dictionary:
	var doc := fixture.duplicate(true)
	for ship in doc.ships:
		ship.armour = 0
		ship.rules = []
		ship.resource.rules = []
		for tier in ["two", "three"]:
			for package in ship.levels[tier]:
				var passive := R.rule("passive", [], "ship")
				passive.modifiers = [{"kind": "armour", "target": "owner", "amount": 0}]
				package.passive = passive
				package.rule = rule("unused", "turn_start", [{"kind": "gain_resource", "target": "owner", "amount": 0}], "owner", "ship")
	for captain in doc.captains:
		captain.passive = R.rule("passive", [], "captain")
		captain.passive.modifiers = [{"kind": "armour", "target": "owner", "amount": 0}]
	for card in doc.cards:
		card.cost = 0
		card.positions = Geometry.POSITIONS.duplicate()
		card.rules = [rule("play", "on_play", [{"kind": "add_shields", "target": "owner", "amount": 0}]), rule("unused", "turn_start", [{"kind": "gain_resource", "target": "owner", "amount": 0}])]
	for enemy in doc.leviathans:
		enemy.armour = 0
		enemy.default_action = []
		enemy.stances = [{"id": "quiet", "name": "Quiet", "reactions": [], "effects": []}]
		enemy.stance_loadout = [{"stance": "quiet", "count": 3}]
	if not multi: doc.setup.enemies = [doc.setup.enemies[0]]
	return doc
func rule(id: String, event: String, effects: Array, subject: String = "self_card", zone: String = "circle", condition: Dictionary = {"kind": "always"}) -> Dictionary:
	var value := R.rule(event, effects, zone)
	value.id = id
	value.trigger.subject = subject
	value.conditions = condition.duplicate(true)
	return value
func attack(damage: Variant = 4, hits: int = 1, range_text: String = "Long", target: String = "chosen_enemy") -> Dictionary:
	return {"kind": "attack", "damage": damage, "hits": hits, "range": range_text, "target": target}
func card_def(doc: Dictionary, id: String) -> Dictionary: return doc.cards[Catalog.index_by_id(doc.cards, id)]
func ship_def(doc: Dictionary, id: String) -> Dictionary: return doc.ships[Catalog.index_by_id(doc.ships, id)]
func uid_for(battle, id: String) -> int:
	for uid in battle.hand:
		if battle.card_keys[uid] == id: return uid
	return -1
func all_in_hand(battle) -> void:
	battle.hand += battle.deck + battle.discard
	battle.deck.clear()
	battle.discard.clear()
func conserved(battle) -> bool:
	var ids: Array = battle.hand + battle.deck + battle.discard + battle.held + battle.play_order + battle.pending.get("revealed", [])
	var unique: Array = []
	for uid in ids:
		if unique.has(uid): return false
		unique.append(uid)
	return ids.size() == battle.card_keys.size()
func field_key(battle, id: String) -> Button:
	for face in battle.hand_view.get_children():
		if battle.state.card_keys[face.get_meta("uid")] == id: return face
	return null
func open_battle(doc: Dictionary = {}) -> void:
	root.get_node("ContentStore").saved = fixture.duplicate(true) if doc.is_empty() else doc.duplicate(true)
	root.get_node("ContentStore").migration_pending = false
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	current_scene.feedback.duration_scale = 0.01
	await flush()
func stage_card(battle, id: String, slot: int) -> void:
	battle._select(uid_for(battle.state, id))
	battle._circle_selected(slot)
func choose_first_targets(battle) -> void:
	var uid: int=battle.selected_uid
	var slot: int=battle.selected_slot
	var options: Dictionary=battle._action_options()
	var flags: Dictionary=battle.state.choice_flags(uid,slot,options)
	var primary: Array=battle.state.choices(uid,"primary",slot,options)
	if not primary.is_empty():
		var value: int=primary[0].value
		if flags.pair:
			battle._ally_position_pressed(int((value-100)/4))
			battle._ally_position_pressed((value-100)%4)
		elif flags.ally: battle.allies.target_widget(value).pressed.emit()
		else: battle.allies.widgets[value].pressed.emit()
	var moves: Array=battle.state.choices(uid,"movement",slot,options)
	if not moves.is_empty(): battle.allies.widgets[moves[0].value].pressed.emit()
	var enemies: Array=battle.state.choices(uid,"enemy",slot,options)
	if not enemies.is_empty(): battle.enemies.widgets[battle.state.position_of(enemies[0].value)].pressed.emit()
	for group in ["circle","stance","reaction","slot"]:
		var list: Array=battle.state.choices(uid,group,slot,options)
		if list.is_empty(): continue
		var value: Variant=list[0].value
		if group=="circle": battle.circle_view.buttons[battle.state.circle.find(value) if battle.state.circle.has(value) else slot].pressed.emit()
		elif group=="stance": battle._stance_pressed(value)
		elif group=="reaction": battle.stance_panel.reaction_selected.emit(value)
		elif group=="slot": battle.allies.widgets[value].pressed.emit()

func settle(battle) -> void:
	await flush()
	if is_instance_valid(battle) and battle.busy: await battle.resolution_finished
	await flush()


func pay_with(battle, id: String) -> void:
	field_key(battle, id).pressed.emit()
	await battle.payment_finished
func motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(40, -60)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event)
	await flush()
func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event)
	await flush()
func begin_drag(battle, id: String) -> void:
	var face := field_key(battle, id)
	expect(face != null, "Missing hand card " + id)
	if face == null: return
	await motion(face.get_global_transform_with_canvas() * Vector2(60, 60))
	var point: Vector2 = face.get_global_transform_with_canvas() * Vector2(60, 60)
	await mouse(point, true)
	await motion(point + Vector2(0, -80), true)
	expect(root.gui_is_dragging() and battle.dragged_uid == face.get_meta("uid"), "Native card drag did not start.")
func hover_slot(battle, slot: int) -> Vector2:
	var button: Control = battle.circle_view.buttons[slot]
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size / 2)
	await motion(point, true)
	return point
func hover_ship(battle, id: int) -> Vector2:
	var formation = battle.enemies if id < 0 else battle.allies
	var button: Control = formation.target_widget(id)
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size / 2)
	await motion(point, true)
	return point
func drop_card(battle, id: String, slot: int) -> void:
	await begin_drag(battle, id)
	var point := await hover_slot(battle, slot)
	await mouse(point, false)
