extends Control
signal resolution_finished
const State = preload("res://scripts/battle_state.gd")
const Catalog = preload("res://scripts/content_catalog.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const CardFace = preload("res://scripts/card_face.gd")
const Formation = preload("res://scripts/formation_view.gd")
const Circle = preload("res://scripts/circle_view.gd")
const Fan = preload("res://scripts/hand_fan.gd")
const StancePanel = preload("res://scripts/stance_view.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")
var state
var busy := false
var selected_uid := -2
var selected_slot := -1
var basic_target := -1
var payment: Array = []
var refresh_discards: Array = []
var target := -1
var movement_target := -1
var canvas: Control
var allies: Control
var enemies: Control
var circle_view: Control
var hand_view: Control
var stance_panel: Control
var feedback: CanvasLayer
var menu: PopupMenu
var dragged_uid := -1
var drag_hover_slot := -1
var drag_hover_ship := -1
var drag_serial := 0
var drag_payload: Dictionary = {}
var history_dialog: AcceptDialog
var header: HBoxContainer
var actions: HBoxContainer


func _ready() -> void:
	state = State.new(-1, ContentStore.snapshot())
	BattleSession.clear_result()
	theme = _make_theme()
	_build_ui()
	feedback = Feedback.new()
	add_child(feedback)
	if state.init_error != "":
		%Inspection.text = state.init_error
		return
	_render()


func _named(node: Node, id: String, parent: Node) -> Node:
	node.name = id
	parent.add_child(node)
	node.owner = self
	node.unique_name_in_owner = true
	return node


func _button(parent: Node, id: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	_named(button, id, parent)
	button.pressed.connect(callback)
	return button


func _label(parent: Node, id: String, text: String, font: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font)
	_named(label, id, parent)
	return label


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#07121b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	canvas = Control.new()
	canvas.custom_minimum_size = Vector2(1100, 800)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(canvas)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	canvas.add_child(header)
	_button(header, "GearButton", "⚙", func(): menu.popup(Rect2i(Vector2i(%GearButton.global_position + Vector2(0, 40)), Vector2i(220, 0))))
	var title := _label(header, "Title", "AETHERPUNK / FLEET COMMAND", 20)
	title.modulate = Color("#e8bd77")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(header, "Round", "")
	_label(canvas, "AlliedTitle", "ALLIED FLEET", 13).modulate = Color("#91c8ad")
	_label(canvas, "CircleTitle", "MAGIC CIRCLE", 13).modulate = Color("#d6adee")
	_label(canvas, "EnemyTitle", "ENEMY FORMATION", 13).modulate = Color("#ffb0a0")
	allies = _named(Formation.new(), "Allies", canvas)
	allies.drop_check = _can_drop_ship
	allies.ship_drag_hovered.connect(_drag_over_ship)
	allies.ship_drag_exited.connect(_drag_leave_ship)
	allies.ship_dropped.connect(_drop_ship)
	enemies = _named(Formation.new(), "Enemies", canvas)
	circle_view = _named(Circle.new(), "Circle", canvas)
	circle_view.slot_selected.connect(_circle_selected)
	circle_view.drop_check = _can_drop_card
	circle_view.drag_slot_hovered.connect(_drag_over_slot)
	circle_view.drag_slot_exited.connect(_drag_leave_slot)
	circle_view.card_dropped.connect(_drop_card)
	stance_panel = _named(StancePanel.new(), "Stance", canvas)
	hand_view = _named(Fan.new(), "Hand", canvas)
	_button(canvas, "DeckPile", "Deck", func(): %Inspection.text = "Remaining draw pile: %d cards. Order is hidden." % state.deck.size())
	_button(canvas, "DiscardPile", "Discard", func(): %Inspection.text = "Discard: %d cards. Played cards stay in the circle until next turn." % state.discard.size())
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 7)
	canvas.add_child(actions)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.fit_to_longest_item = false
	_named(choice, "TargetChoice", actions)
	choice.item_selected.connect(func(index): target = choice.get_item_id(index); _update_controls())
	var movement := OptionButton.new()
	movement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	movement.fit_to_longest_item = false
	_named(movement, "MovementChoice", actions)
	movement.item_selected.connect(func(index): movement_target = movement.get_item_id(index); _update_controls())
	_button(actions, "PlayButton", "Play Card", _commit)
	_button(actions, "CancelButton", "Cancel", _cancel)
	_button(actions, "ManoeuvreButton", "Manoeuvre", _select.bind(-1))
	_button(actions, "EndPhaseButton", "End Fleet Phase", _end_phase)
	_button(actions, "HistoryButton", "History", _show_history)
	_button(actions, "WinButton", "Test Win", _navigate.bind("res://scenes/victory.tscn"))
	_button(actions, "LossButton", "Test Loss", _navigate.bind("res://scenes/defeat.tscn"))
	var inspection := _label(canvas, "Inspection", "", 14)
	inspection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspection.modulate = Color("#e8bd77")
	_label(canvas, "Status", "", 12).modulate = Color("#80a7b7")
	menu = PopupMenu.new()
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.add_item("Resume", 0)
	if BattleSession.editor_playtest:
		menu.add_item("Return to Editor", 1)
	menu.add_item("Main Menu", 2)
	add_child(menu)
	menu.about_to_popup.connect(func(): get_tree().paused = true)
	menu.popup_hide.connect(func(): get_tree().paused = false)
	menu.id_pressed.connect(func(id):
		get_tree().paused = false
		if id == 1:
			_navigate("res://scenes/editor.tscn")
		elif id == 2:
			_navigate("res://scenes/main_menu.tscn"))
	history_dialog = AcceptDialog.new()
	history_dialog.title = "Action history"
	history_dialog.min_size = Vector2i(780, 460)
	add_child(history_dialog)
	canvas.resized.connect(_layout)
	_layout()


func _layout() -> void:
	var w: float = canvas.size.x
	header.position = Vector2(16, 10)
	header.size = Vector2(w - 32, 38)
	%AlliedTitle.position = Vector2(20, 65)
	%EnemyTitle.position = Vector2(w - 355, 65)
	%CircleTitle.position = Vector2(w / 2 - 75, 58)
	allies.position = Vector2(8, 110)
	allies.size = Vector2(360, 255)
	enemies.position = Vector2(w - 368, 110)
	enemies.size = Vector2(360, 255)
	circle_view.position = Vector2(w / 2 - 152, 83)
	circle_view.size = Vector2(304, 286)
	stance_panel.position = Vector2(w - 378, 386)
	stance_panel.size = Vector2(360, 82)
	hand_view.position = Vector2(118, 477)
	hand_view.size = Vector2(w - 236, 220)
	%DeckPile.position = Vector2(16, 514)
	%DeckPile.size = Vector2(92, 158)
	%DiscardPile.position = Vector2(w - 108, 514)
	%DiscardPile.size = Vector2(92, 158)
	actions.position = Vector2(16, 710)
	actions.size = Vector2(w - 32, 38)
	%Inspection.position = Vector2(18, 752)
	%Inspection.size = Vector2(w - 36, 42)
	%Status.position = Vector2(20, 435)
	%Status.size = Vector2(w - 430, 38)


func _render() -> void:
	_show_board(state.board_snapshot())
	for child in hand_view.get_children():
		hand_view.remove_child(child)
		child.queue_free()
	for uid in state.hand:
		var face := CardFace.new()
		face.name = "Card%d" % uid
		face.set_meta("uid", uid)
		hand_view.add_child(face)
		face.configure(state.card(uid), state.ships[state.card(uid).owner])
		face.pressed.connect(_choose_card.bind(uid))
		face.drag_provider = _begin_card_drag.bind(uid)
		face.tooltip_text += "\nDrag to the circle to play, to %s to repair/recover, or an adjacent living ally to swap. Basic actions discard this card." % state.ships[state.card(uid).owner].name
		face.mouse_entered.connect(func(): hand_view.hover(face, true))
		face.mouse_exited.connect(func(): hand_view.hover(face, false))
	hand_view.arrange()
	%Round.text = "ROUND %02d / %s" % [state.round_number, state.phase.to_upper()]
	_update_controls()
	if state.outcome != "":
		_navigate.call_deferred("res://scenes/%s.tscn" % state.outcome)


func _show_piles(snapshot: Dictionary) -> void:
	%DeckPile.text = "DECK\n%d" % snapshot.deck_size
	%DiscardPile.text = "DISCARD\n%d" % snapshot.discard_size


func _show_board(snapshot: Dictionary) -> void:
	allies.configure(snapshot, false)
	enemies.configure(snapshot, true, state.definitions.monster)
	var cards: Dictionary = {}
	for uid in snapshot.circle:
		if uid >= 0:
			cards[uid] = state.card(uid)
	circle_view.configure(snapshot.circle, snapshot.expanded, cards, snapshot.used_triggers, selected_slot)
	stance_panel.configure(state.definitions.stances[snapshot.stance_index])
	%CircleTitle.text = "MAGIC CIRCLE / %d" % (9 if snapshot.expanded else 4)
	_show_piles(snapshot)


func _circle_selected(slot: int) -> void:
	if busy or dragged_uid >= 0 or state.phase != "fleet":
		return
	if state.circle[slot] >= 0:
		var info: Dictionary = state.card(state.circle[slot])
		%Inspection.text = info.name + ": " + info.effect
		return
	if selected_uid >= 0 and (slot < 4 or state.expanded):
		selected_slot = slot
		basic_target = -1
		_fill_choices()
		_update_controls()


func _choose_card(uid: int) -> void:
	if busy or dragged_uid >= 0:
		return
	if state.phase == "discard":
		var error: String = state.discard_for_relay(uid)
		if error == "":
			await _present_resolution()
		return
	if state.phase == "refresh":
		_toggle(refresh_discards, uid)
	elif basic_target >= 0:
		if selected_uid == uid:
			_cancel()
		else:
			_select(uid)
		return
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
	if busy or dragged_uid >= 0 or state.phase != "fleet":
		return
	selected_uid = uid
	basic_target = -1
	selected_slot = state.first_slot() if uid >= 0 else -1
	payment.clear()
	_fill_choices()
	_update_controls()


func _fill_choices() -> void:
	target = -1
	movement_target = -1
	for pair in [[%TargetChoice, "primary"], [%MovementChoice, "movement"]]:
		var control: OptionButton = pair[0]
		control.clear()
		for option in state.choices(selected_uid, pair[1], selected_slot):
			control.add_item(option.label, option.value)
		if control.item_count > 0:
			control.select(0)
			if pair[1] == "primary":
				target = control.get_item_id(0)
			else:
				movement_target = control.get_item_id(0)


func _cancel() -> void:
	if busy or dragged_uid >= 0:
		return
	_clear_draft()
	_update_controls()


func _clear_draft() -> void:
	selected_uid = -2
	basic_target = -1
	selected_slot = -1
	payment.clear()
	refresh_discards.clear()
	target = -1
	movement_target = -1
	%TargetChoice.clear()
	%MovementChoice.clear()


func _commit() -> void:
	if busy or dragged_uid >= 0:
		return
	var error := ""
	if state.phase == "refresh":
		error = state.refresh(refresh_discards)
	elif basic_target >= 0:
		error = state.play_basic(selected_uid, basic_target)
	elif selected_uid != -2:
		error = state.play(selected_uid, payment, target, movement_target, selected_slot)
	else:
		return
	if error != "":
		%Inspection.text = error
		return
	await _present_resolution()


func _end_phase() -> void:
	if busy or dragged_uid >= 0:
		return
	var error: String = state.end_phase()
	if error != "":
		%Inspection.text = error
		return
	await _present_resolution()


func _present_resolution() -> void:
	busy = true
	_update_controls()
	await feedback.play(state.feedback_events.duplicate(true), self)
	busy = false
	_clear_draft()
	_render()
	resolution_finished.emit()


func _update_controls() -> void:
	if dragged_uid >= 0:
		_update_drag_feedback()
		return
	circle_view.drag_active = false
	if busy:
		allies.show_basic_targets()
	else:
		_update_basic_highlights()
	var contributing: Array = []
	var contribution_details: Dictionary = {}
	for button in [%PlayButton, %CancelButton, %ManoeuvreButton, %EndPhaseButton, %TargetChoice, %MovementChoice, %WinButton, %LossButton]:
		button.disabled = busy
	for button in hand_view.get_children():
		var uid: int = button.get_meta("uid")
		button.disabled = busy
		button.set_pressed_no_signal(uid == selected_uid or payment.has(uid) or refresh_discards.has(uid))
		button.modulate = Color("#a9e3cb") if payment.has(uid) or refresh_discards.has(uid) else Color.WHITE
	hand_view.selected_uid = selected_uid
	hand_view.arrange()
	%TargetChoice.visible = basic_target < 0 and selected_uid != -2 and %TargetChoice.item_count > 0
	%MovementChoice.visible = basic_target < 0 and selected_uid != -2 and %MovementChoice.item_count > 0
	if busy:
		%Inspection.text = "Resolving action and chained effects…"
		return
	%PlayButton.disabled = true
	%PlayButton.text = "Play Card"
	%CancelButton.disabled = selected_uid == -2 and refresh_discards.is_empty()
	%EndPhaseButton.disabled = state.phase != "fleet"
	%ManoeuvreButton.disabled = state.phase != "fleet"
	if state.phase == "discard":
		%Inspection.text = "%s: discard %d more card(s)." % [state.pending.title, state.pending.discard_remaining]
	elif state.phase == "refresh":
		%PlayButton.disabled = false
		%PlayButton.text = "Refill Hand"
		%Inspection.text = "New player turn: circle cleared. Select optional hand discards, then refill to seven."
	elif basic_target >= 0:
		var result: Dictionary = state.basic_preview(selected_uid, basic_target)
		%PlayButton.disabled = not result.ok
		%PlayButton.text = result.action if result.ok else "Basic Action"
		%Inspection.text = result.text
	elif selected_uid != -2:
		var result: Dictionary = state.preview(selected_uid, payment, target, movement_target, selected_slot)
		%PlayButton.disabled = not result.ok
		%Inspection.text = result.text
		contributing = result.get("contributors", [])
		contribution_details = result.get("contribution_details", {})
		%PlayButton.text = "Manoeuvre" if selected_uid < 0 else "Play Card"
	else:
		%Inspection.text = "Select a card to play, or drag it onto its own ship to repair/recover or an adjacent ally to swap."
	%Status.text = "Hand %d / In circle %d\nGreen BONUS = contributor. Purple = adjacent. Next stance hidden." % [state.hand.size(), state.play_order.size()]
	var cards: Dictionary = {}
	for uid in state.circle:
		if uid >= 0:
			cards[uid] = state.card(uid)
	circle_view.configure(state.circle, state.expanded, cards, state.used_triggers, selected_slot if basic_target < 0 else -1, contributing, contribution_details)


func _show_history() -> void:
	history_dialog.dialog_text = "\n".join(state.history.slice(maxi(0, state.history.size() - 30)))
	history_dialog.popup_centered()


func _navigate(destination: String) -> void:
	if busy and destination not in ["res://scenes/main_menu.tscn", "res://scenes/editor.tscn"]:
		return
	get_tree().paused = false
	if destination in ["res://scenes/victory.tscn", "res://scenes/defeat.tscn"]:
		BattleSession.record_result(state.result_summary(destination.get_file().get_basename()))
	if destination in ["res://scenes/main_menu.tscn", "res://scenes/editor.tscn"]:
		BattleSession.editor_playtest = false
	get_tree().change_scene_to_file(destination)


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and dragged_uid >= 0:
		_finish_card_drag()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and dragged_uid >= 0 and drag_hover_ship >= 0:
		var widget: Control = allies.target_widget(drag_hover_ship)
		if widget != null:
			var point: Vector2 = widget.get_global_transform_with_canvas().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, widget.size).has_point(point):
				drag_hover_ship = -1
				_update_drag_feedback()
	if event is InputEventMouseMotion and dragged_uid >= 0 and drag_hover_slot >= 0:
		var button: Control = circle_view.buttons[drag_hover_slot]
		var local_point: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, button.size).has_point(local_point):
			drag_hover_slot = -1
			_update_drag_feedback()


func _begin_card_drag(uid: int) -> Dictionary:
	if dragged_uid >= 0 or busy or get_tree().paused or state.phase != "fleet" or state.outcome != "" or not state.hand.has(uid):
		return {}
	drag_serial += 1
	dragged_uid = uid
	drag_hover_slot = -1
	drag_hover_ship = -1
	drag_payload = {"kind": "fleet_hand_card", "battle": get_instance_id(), "uid": uid, "serial": drag_serial}
	for face in hand_view.get_children():
		if face.get_meta("uid", -1) == uid:
			face.modulate.a = 0.35
	_update_drag_feedback()
	return drag_payload.duplicate()


func _is_our_drag(data: Variant) -> bool:
	return data is Dictionary and not drag_payload.is_empty() and data == drag_payload and dragged_uid >= 0 and state.hand.has(dragged_uid)


func _drop_slot_error(uid: int, slot: int) -> String:
	if busy or get_tree().paused or state.phase != "fleet" or state.outcome != "" or not state.hand.has(uid):
		return "Cards can only be placed during the fleet phase."
	if slot < 0 or slot >= (9 if state.expanded else 4) or state.circle[slot] >= 0:
		return "Choose an empty unlocked circle slot."
	# A destination is valid if the hand can fund it, even before payment is selected.
	var funding: Array = []
	var cost: int = state.effective_cost(uid, slot)
	var total := 0
	for payer in state.hand:
		if total >= cost:
			break
		if payer != uid:
			funding.append(payer)
			total += int(state.card(payer).pays)
	var primary: Array = state.choices(uid, "primary", slot)
	var movements: Array = state.choices(uid, "movement", slot)
	var ally: int = primary[0].value if not primary.is_empty() else -1
	var movement: int = movements[0].value if not movements.is_empty() else -1
	return state.validate(uid, funding, ally, movement, slot)


func _can_drop_card(data: Variant, slot: int) -> bool:
	return _is_our_drag(data) and _drop_slot_error(dragged_uid, slot) == ""


func _drag_over_slot(slot: int, data: Variant) -> void:
	if not _is_our_drag(data) or drag_hover_slot == slot:
		return
	drag_hover_slot = slot
	drag_hover_ship = -1
	_update_drag_feedback()


func _drag_leave_slot(slot: int) -> void:
	if dragged_uid >= 0 and drag_hover_slot == slot:
		drag_hover_slot = -1
		_update_drag_feedback()


func _update_drag_feedback() -> void:
	for control in [%PlayButton, %CancelButton, %ManoeuvreButton, %EndPhaseButton, %TargetChoice, %MovementChoice, %WinButton, %LossButton]:
		control.disabled = true
	circle_view.drag_active = true
	_update_basic_highlights(dragged_uid, drag_hover_ship)
	circle_view.valid_drop_slots = []
	circle_view.drop_errors = {}
	for slot in 9:
		var error := _drop_slot_error(dragged_uid, slot)
		circle_view.drop_errors[slot] = error
		if error == "":
			circle_view.valid_drop_slots.append(slot)
	var cards: Dictionary = {}
	for uid in state.circle:
		if uid >= 0:
			cards[uid] = state.card(uid)
	var contributors: Array = []
	var details: Dictionary = {}
	var highlight := -1
	var title: String = state.card(dragged_uid).name
	if drag_hover_ship >= 0:
		var preview: Dictionary = state.basic_preview(dragged_uid, drag_hover_ship)
		%Inspection.text = ("Drop to select basic action, then confirm. " if preview.ok else "Cannot drop: ") + preview.text
	elif drag_hover_slot >= 0:
		var error: String = circle_view.drop_errors[drag_hover_slot]
		if error == "":
			highlight = drag_hover_slot
			var primary: Array = state.choices(dragged_uid, "primary", highlight)
			var movements: Array = state.choices(dragged_uid, "movement", highlight)
			var ally: int = primary[0].value if not primary.is_empty() else -1
			var movement: int = movements[0].value if not movements.is_empty() else -1
			var selected_payment: Array = payment if selected_uid == dragged_uid and state.effective_cost(dragged_uid, highlight) > 0 else []
			var preview: Dictionary = state.preview(dragged_uid, selected_payment, ally, movement, highlight)
			contributors = preview.contributors
			details = preview.contribution_details
			%Inspection.text = "Drop %s → %s, then choose payment and confirm. %s" % [title, Geometry.SLOT_NAMES[highlight], preview.text]
		else:
			%Inspection.text = "Cannot place %s: %s" % [title, error]
	else:
		%Inspection.text = "Drag %s to the circle, its own ship to repair/recover, or an adjacent ally to swap. Drop selects; confirm to spend the card." % title
	circle_view.configure(state.circle, state.expanded, cards, state.used_triggers, highlight, contributors, details)


func _drop_card(slot: int, data: Variant) -> void:
	if not _can_drop_card(data, slot):
		return
	var uid := dragged_uid
	var retained_payment: Array = payment.duplicate() if selected_uid == uid else []
	_finish_card_drag(false)
	_select(uid)
	selected_slot = slot
	payment = retained_payment if state.effective_cost(uid, slot) > 0 else []
	_fill_choices()
	_update_controls()


func _finish_card_drag(refresh: bool = true) -> void:
	dragged_uid = -1
	drag_hover_slot = -1
	drag_hover_ship = -1
	drag_payload.clear()
	circle_view.drag_active = false
	circle_view.valid_drop_slots.clear()
	circle_view.drop_errors.clear()
	for face in hand_view.get_children():
		face.modulate.a = 1.0
	if refresh:
		_update_controls()


func _can_drop_ship(data: Variant, ship_id: int) -> bool:
	return _is_our_drag(data) and not busy and not get_tree().paused and state.validate_basic(dragged_uid, ship_id) == ""


func _drag_over_ship(ship_id: int, data: Variant) -> void:
	if not _is_our_drag(data) or drag_hover_ship == ship_id:
		return
	drag_hover_slot = -1
	drag_hover_ship = ship_id
	_update_drag_feedback()


func _drag_leave_ship(ship_id: int) -> void:
	if dragged_uid >= 0 and drag_hover_ship == ship_id:
		drag_hover_ship = -1
		_update_drag_feedback()


func _drop_ship(ship_id: int, data: Variant) -> void:
	if not _can_drop_ship(data, ship_id):
		return
	var uid := dragged_uid
	_finish_card_drag(false)
	_select(uid)
	basic_target = ship_id
	selected_slot = -1
	%TargetChoice.clear()
	%MovementChoice.clear()
	_update_controls()


func _update_basic_highlights(uid: int = -1, hovered: int = -1) -> void:
	if uid < 0 and basic_target >= 0:
		uid = selected_uid
		hovered = basic_target
	if uid < 0:
		allies.show_basic_targets()
		return
	var hints: Dictionary = {}
	var valid: Array = []
	for ship_id in state.ships.size():
		var preview: Dictionary = state.basic_preview(uid, ship_id)
		hints[ship_id] = preview.text
		if preview.ok:
			valid.append(ship_id)
	allies.show_basic_targets(hints, valid, hovered, int(state.card(uid).owner))
