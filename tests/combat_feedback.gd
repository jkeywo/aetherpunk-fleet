extends SceneTree

var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/gdd_content.json"))
## Real asynchronous playback: ordering, locks, cleanup, and leaving during feedback.

const State = preload("res://scripts/battle_state.gd")
var failures: int = 0
var checks: int = 0
var beats: Array = []
var hull_at_reaction: int = -1
var monster_at_reaction: int = -1


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _button(key: String) -> Button:
	for button in current_scene.get_node("%Hand").get_children():
		if current_scene.state.card_keys[button.get_meta("uid")] == key:
			return button
	return null


func _beat(kind: String) -> void:
	beats.append(kind)
	if kind == "reaction_triggered":
		hull_at_reaction = current_scene.get_node("%Formation/Bastion").get_node("%HullBar").value
		monster_at_reaction = current_scene.get_node("%MonsterBar").value


func _open_battle() -> void:
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	current_scene.feedback.duration_scale = 0.04
	await process_frame


func _run() -> void:
	root.get_node("ContentStore").saved = fixture.duplicate(true)
	await _open_battle()
	var battle = current_scene
	battle.state.reaction_deck = [1, 2, 3, 4, 5]
	battle.feedback.beat_started.connect(_beat)
	_button("advance").pressed.emit()
	_button("tow").pressed.emit()
	var hand_before: Array = battle.state.hand.duplicate()
	var random_before: int = battle.state.rng.state
	var prior_events: Array = battle.state.feedback_events.duplicate(true)
	battle.state.preview(battle.selected_uid, battle.payment, battle.target)
	expect(battle.state.hand == hand_before and battle.state.rng.state == random_before, "Preview mutated state.")
	expect(battle.state.feedback_events == prior_events, "Preview emitted real feedback.")
	battle.get_node("%PlayButton").pressed.emit()
	expect(battle.busy, "Resolution did not lock synchronously.")
	expect(battle.get_node("%PlayButton").disabled and battle.get_node("%EndPhaseButton").disabled, "Combat controls were not disabled.")
	for button in battle.get_node("%Hand").get_children():
		expect(button.disabled, "Hand accepted input during feedback.")
	# Simulate duplicate signals even though the buttons are disabled.
	battle.get_node("%PlayButton").pressed.emit()
	battle.get_node("%EndPhaseButton").pressed.emit()
	battle._cancel()
	expect(battle.state.monster_hull == 66 and battle.state.round_number == 1, "Reentrant input executed another operation.")
	await battle.resolution_finished
	expect(not battle.busy and not battle.feedback.running, "Playback did not unlock.")
	expect(beats == ["card_played", "damage", "movement", "cards_discarded", "reaction_triggered", "damage", "reaction_revealed"], "Action/reaction feedback order incorrect.")
	expect(hull_at_reaction == 28 and monster_at_reaction == 66, "Reaction damage appeared before its announcement.")
	expect(battle.get_node("%Formation/Bastion").get_node("%HullBar").value == 25, "Final ship hull display incorrect.")
	expect(battle.get_node("%ReactionName").text == "Violent Recoil", "Replacement was not shown after reaction.")
	expect(not battle.feedback.banner.visible, "Reaction banner remained visible after playback.")
	await process_frame
	expect(battle.feedback.overlay.get_child_count() == 1, "Transient feedback nodes leaked.")

	# A repair followed by damage must retain both events rather than showing only the net +1.
	battle.state = State.new(5, fixture)
	battle.state.ships[0].hull = 24
	battle.state.reaction_index = 3
	battle._render()
	await process_frame
	_button("patch").pressed.emit()
	_button("escort").pressed.emit()
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	var repair_amount := -1
	var damage_amount := -1
	for event in battle.state.feedback_events:
		if event.kind == "repair":
			repair_amount = event.amount
		if event.kind == "damage":
			damage_amount = event.amount
	expect(repair_amount == 4 and damage_amount == 3 and battle.state.ships[0].hull == 25, "Repair and reaction damage were collapsed into a net change.")

	# Guard gained, consumed by damage, and expired are distinct feedback beats.
	battle.state = State.new(6, fixture)
	battle._render()
	await process_frame
	_button("brace").pressed.emit()
	_button("tow").pressed.emit()
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.ships[0].guard == 8, "Guard feedback changed the actual effect.")
	battle.get_node("%EndPhaseButton").pressed.emit()
	await battle.resolution_finished
	var blocked := -1
	var expired := -1
	for event in battle.state.feedback_events:
		if event.kind == "damage":
			blocked = event.blocked
		if event.kind == "guard":
			expired = event.amount
	expect(blocked == 7 and expired == -1 and battle.state.ships[0].hull == 28, "Guard consumption and expiry were not distinct.")
	expect(not battle.get_node("%PlayButton").disabled, "Refresh controls did not unlock.")

	# A menu exit cancels node-bound animation without delayed navigation or orphan controls.
	await _open_battle()
	battle = current_scene
	battle.feedback.duration_scale = 1.0
	_button("advance").pressed.emit()
	_button("tow").pressed.emit()
	battle.get_node("%PlayButton").pressed.emit()
	expect(battle.busy, "Cancellation fixture was not animating.")
	battle.get_node("%MenuButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "MainMenu", "Menu was not available during feedback.")
	for frame in 5:
		await process_frame
	expect(current_scene.name == "MainMenu", "An abandoned sequence changed the scene later.")
	print("Combat feedback: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)
