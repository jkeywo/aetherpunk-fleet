extends Control

signal resolution_finished
## Presentation and action drafting; battle_state.gd owns validation and resolution.

const Catalog = preload("res://scripts/content_catalog.gd")
const State = preload("res://scripts/battle_state.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")
const ShipScene = preload("res://scenes/components/ship_panel.tscn")
const CardScene = preload("res://scenes/components/hand_card.tscn")

var state
var movement_target: int = -1
var selected_uid: int = -2
var payment: Array = []
var target: int = -1
var refresh_discards: Array = []
var busy: bool = false
var feedback: CanvasLayer


func _ready() -> void:
	state = State.new(-1, ContentStore.snapshot())
	BattleSession.clear_result()
	theme = _make_theme()
	feedback = Feedback.new()
	add_child(feedback)
	%MenuButton.pressed.connect(_navigate.bind("res://scenes/main_menu.tscn"))
	%WinButton.pressed.connect(_navigate.bind("res://scenes/victory.tscn"))
	%LossButton.pressed.connect(_navigate.bind("res://scenes/defeat.tscn"))
	%PlayButton.pressed.connect(_commit)
	%CancelButton.pressed.connect(_cancel)
	%ManoeuvreButton.pressed.connect(_select.bind(-1))
	%EndPhaseButton.pressed.connect(_end_phase)
	%TargetChoice.item_selected.connect(_target_changed)
	%MovementChoice.item_selected.connect(_movement_changed)
	%ReturnToEditor.visible = BattleSession.editor_playtest
	%ReturnToEditor.pressed.connect(_navigate.bind("res://scenes/editor.tscn"))
	if not state.init_error.is_empty():
		%Inspection.text = "Cannot start battle: " + state.init_error
		%Status.text = "Open the Editor to repair the saved content."
		for button in [%PlayButton, %CancelButton, %ManoeuvreButton, %EndPhaseButton, %WinButton, %LossButton]:
			button.disabled = true
		return
	_render()


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _render() -> void:
	_show_board(state.board_snapshot())
	_clear_children(%Hand)
	var intent: Dictionary = state.definitions.intents[state.intent_index]
	%IntentName.text = intent.name
	%IntentTrigger.text = intent.trigger
	%IntentEffect.text = intent.effect
	var escalation: int = maxi(0, state.round_number - 3)
	if escalation > 0:
		%IntentEffect.text += "\nEscalation: +%d to each damage instance." % escalation
	%Round.text = "ROUND %02d  /  %s" % [state.round_number, state.phase.to_upper()]
	%Escalation.text = "Escalation +%d\nBegins in round 4" % maxi(0, state.round_number - 3)
	_show_piles(state.board_snapshot())
	for uid in state.hand:
		_add_card(uid)
	%History.text = "\n".join(state.history)
	%History.scroll_to_line(maxi(0, state.history.size() - 1))
	_update_controls()
	if state.outcome != "":
		_navigate.call_deferred("res://scenes/%s.tscn" % state.outcome)


func _show_piles(snapshot: Dictionary) -> void:
	%HandCount.text = "SHARED HAND  ·  %d CARDS" % snapshot.hand_size
	%PileCounts.text = "DECK  %d    /    DISCARD  %d" % [snapshot.deck_size, snapshot.discard_size]


func _show_board(snapshot: Dictionary) -> void:
	_clear_children(%Formation)
	%MonsterName.text = state.definitions.monster.name.to_upper()
	%MonsterHull.text = "HULL  %d / %d" % [snapshot.monster_hull, state.definitions.monster.hull]
	%MonsterBar.max_value = state.definitions.monster.hull
	%MonsterBar.value = snapshot.monster_hull
	var reaction: Dictionary = state.definitions.reactions[snapshot.reaction_index]
	%ReactionName.text = reaction.name
	%ReactionTrigger.text = reaction.trigger
	%ReactionEffect.text = reaction.effect
	for index in snapshot.formation.size():
		var ship_id: int = snapshot.formation[index]
		_add_ship(ship_id, index, snapshot.ships[ship_id])


func _add_ship(ship_id: int, rank: int, ship: Dictionary) -> void:
	var panel := ShipScene.instantiate()
	panel.name = ship.name.validate_node_name()
	panel.set_meta("ship_index", ship_id)
	%Formation.add_child(panel)
	panel.get_node("%Rank").text = ["01  /  FRONT", "02  /  CENTRE", "03  /  REAR"][rank]
	panel.get_node("%ShipName").text = ship.name
	panel.get_node("%Role").text = ship.role
	panel.get_node("%Role").modulate = Color(ship.color)
	panel.get_node("%Hull").text = "HULL  %d / %d" % [ship.hull, ship.max_hull]
	panel.get_node("%HullBar").max_value = ship.max_hull
	panel.get_node("%HullBar").value = ship.hull
	panel.get_node("Row/Stats/HullRow/Guard").text = "GUARD %d" % ship.guard
	panel.get_node("%ShipArt").accent = Color(ship.color)


func _add_card(uid: int) -> void:
	var info: Dictionary = state.card(uid)
	var ship: Dictionary = state.ships[info.owner]
	var button := CardScene.instantiate() as Button
	button.name = "Card%d" % uid
	button.set_meta("uid", uid)
	%Hand.add_child(button)
	button.get_node("%Owner").text = ship.name.to_upper()
	button.get_node("%Owner").modulate = Color(ship.color)
	button.get_node("%CardName").text = info.name
	button.get_node("%Cost").text = "COST %d" % info.cost
	button.get_node("%Payment").text = "PAYS %d" % info.pays
	button.get_node("%Ranks").text = "RANKS  " + info.ranks
	button.get_node("%Tags").text = info.tags
	button.get_node("%Effect").text = info.effect
	button.tooltip_text = "%s — %s\nCost %d | Pays %d | Ranks %s\n%s\n%s" % [
		info.name, ship.name, info.cost, info.pays, info.ranks, info.tags, info.effect]
	if ship.hull <= 0:
		button.get_node("%Owner").text += " / LOST"
	button.pressed.connect(_choose_card.bind(uid))


func _choose_card(uid: int) -> void:
	if busy:
		return
	if state.phase == "discard":
		var error: String = state.discard_for_relay(uid)
		if error != "":
			%Inspection.text = error
			return
		await _present_resolution()
		return
	if state.phase == "refresh":
		_toggle(refresh_discards, uid)
	elif selected_uid == -2:
		_select(uid)
		return
	elif selected_uid == uid:
		_cancel()
		return
	else:
		_toggle(payment, uid)
	_update_controls()


func _toggle(items: Array, uid: int) -> void:
	if items.has(uid):
		items.erase(uid)
	else:
		items.append(uid)


func _select(uid: int) -> void:
	if busy or state.phase != "fleet":
		return
	selected_uid = uid
	payment.clear()
	target = -1
	movement_target = -1
	%TargetChoice.clear()
	%MovementChoice.clear()
	for option in state.choices(uid):
		%TargetChoice.add_item(option.label, option.value)
	if %TargetChoice.item_count > 0:
		%TargetChoice.select(0)
		target = %TargetChoice.get_item_id(0)
	for option in state.choices(uid, "movement"):
		%MovementChoice.add_item(option.label, option.value)
	if %MovementChoice.item_count > 0:
		%MovementChoice.select(0)
		movement_target = %MovementChoice.get_item_id(0)
	_update_controls()


func _movement_changed(index: int) -> void:
	if busy:
		return
	movement_target = %MovementChoice.get_item_id(index)
	_update_controls()


func _target_changed(index: int) -> void:
	if busy:
		return
	target = %TargetChoice.get_item_id(index)
	_update_controls()


func _clear_draft() -> void:
	selected_uid = -2
	payment.clear()
	target = -1
	refresh_discards.clear()
	movement_target = -1
	%TargetChoice.clear()
	%MovementChoice.clear()


func _cancel() -> void:
	if busy:
		return
	_clear_draft()
	_update_controls()


func _commit() -> void:
	if busy or (state.phase != "refresh" and selected_uid == -2):
		return
	var error := ""
	if state.phase == "refresh":
		error = state.refresh(refresh_discards)
	elif selected_uid != -2:
		error = state.play(selected_uid, payment, target, movement_target)
	if error != "":
		%Inspection.text = error
		return
	await _present_resolution()


func _end_phase() -> void:
	if busy:
		return
	var error: String = state.end_phase()
	if error != "":
		%Inspection.text = error
		return
	await _present_resolution()


func _present_resolution() -> void:
	busy = true
	_update_controls()
	%Inspection.text = "Resolving combat…"
	%Status.text = "Combat feedback — actions locked until resolution finishes."
	await feedback.play(state.feedback_events.duplicate(true), self)
	_clear_draft()
	busy = false
	_render()
	resolution_finished.emit()


func _update_controls() -> void:
	if busy:
		for button in [%PlayButton, %CancelButton, %ManoeuvreButton, %EndPhaseButton, %TargetChoice, %MovementChoice, %WinButton, %LossButton]:
			button.disabled = true
		for button in %Hand.get_children():
			button.disabled = true
		return
	%TargetChoice.disabled = false
	%MovementChoice.disabled = false
	%WinButton.disabled = false
	%LossButton.disabled = false
	for button in %Hand.get_children():
		var uid: int = button.get_meta("uid")
		var is_action := uid == selected_uid
		var marked := payment.has(uid) or refresh_discards.has(uid)
		button.set_pressed_no_signal(is_action or marked)
		button.modulate = Color("#a9e3cb") if marked else Color.WHITE
		button.get_node("%Cost").text = ("PLAY %d" if is_action else "COST %d") % state.card(uid).cost
		button.get_node("%Payment").text = ("PAY %d" if payment.has(uid) else "PAYS %d") % state.card(uid).pays
		if state.phase == "refresh" and marked:
			button.get_node("%Payment").text = "DROP"
	%TargetChoice.visible = selected_uid != -2 and %TargetChoice.item_count > 0
	%MovementChoice.visible = selected_uid != -2 and %MovementChoice.item_count > 0
	%CancelButton.disabled = selected_uid == -2 and refresh_discards.is_empty()
	%ManoeuvreButton.disabled = state.phase != "fleet" or state.formation.size() < 2
	%EndPhaseButton.disabled = state.phase != "fleet"
	%PlayButton.disabled = true
	%PlayButton.text = "Play Card"
	if state.phase == "discard":
		%Inspection.text = "%s: choose %d more card(s) to discard before continuing." % [state.pending.title, state.pending.discard_remaining]
		%Status.text = "Action in progress: choose one discard."
	elif state.phase == "refresh":
		%PlayButton.disabled = false
		%PlayButton.text = "Refill Hand"
		%Inspection.text = "NEW ROUND: optionally click cards to discard, then Refill Hand. Keeping %d; discarding %d." % [
			state.hand.size() - refresh_discards.size(), refresh_discards.size()]
		%Status.text = "Keep cards you want; refill to seven."
	elif selected_uid != -2:
		var result: Dictionary = state.preview(selected_uid, payment, target, movement_target)
		%PlayButton.disabled = not result.ok
		%PlayButton.text = "Manoeuvre" if selected_uid == -1 else "Play Card"
		%Inspection.text = result.text
		var title: String = "Basic manoeuvre" if selected_uid == -1 else state.card(selected_uid).name
		var cost: int = 1 if selected_uid == -1 else state.card(selected_uid).cost
		%Status.text = "%s  /  Payment %d of %d" % [title, state.payment_total(payment), cost]
	else:
		%Inspection.text = "Select an action card, then click other cards to pay. Choose a target if needed, then Play Card. Cancel to change action."
		%Status.text = "Fleet phase — choose an action or end the phase."


func _navigate(destination: String) -> void:
	# Menu remains an immediate escape while feedback is playing.
	if busy and destination not in ["res://scenes/main_menu.tscn", "res://scenes/editor.tscn"]:
		return
	if destination in ["res://scenes/victory.tscn", "res://scenes/defeat.tscn"]:
		var result: String = destination.get_file().get_basename()
		BattleSession.record_result(state.result_summary(result))
	if destination in ["res://scenes/main_menu.tscn", "res://scenes/editor.tscn"]:
		BattleSession.editor_playtest = false
	var error := get_tree().change_scene_to_file(destination)
	if error != OK:
		push_error("Unable to open %s: %s" % [destination, error_string(error)])


func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", Color("#e7ecea"))
	var panel := _box(Color("#102632"), Color("#30505c"))
	result.set_stylebox("panel", "PanelContainer", panel)
	var button := _box(Color("#132e3b"), Color("#3f6573"))
	var hover := _box(Color("#1c3e4d"), Color("#89b6bf"))
	var selected := _box(Color("#253e46"), Color("#e8bd77"))
	result.set_stylebox("normal", "Button", button)
	result.set_stylebox("hover", "Button", hover)
	result.set_stylebox("pressed", "Button", selected)
	result.set_stylebox("hover_pressed", "Button", selected)
	var disabled := _box(Color("#101f28"), Color("#253b46"))
	result.set_stylebox("disabled", "Button", disabled)
	var focus := _box(Color.TRANSPARENT, Color("#e8bd77"))
	result.set_stylebox("focus", "Button", focus)
	result.set_stylebox("normal", "OptionButton", button)
	result.set_stylebox("hover", "OptionButton", hover)
	result.set_stylebox("pressed", "OptionButton", selected)
	result.set_stylebox("focus", "OptionButton", focus)
	var background := _box(Color("#07161e"), Color("#203d48"))
	var fill := _box(Color("#78b7aa"), Color.TRANSPARENT)
	result.set_stylebox("background", "ProgressBar", background)
	result.set_stylebox("fill", "ProgressBar", fill)
	return result


func _box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box
