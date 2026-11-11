extends Control
signal resolution_finished
signal payment_finished
const State = preload("res://scripts/battle_state.gd")
const Catalog = preload("res://scripts/content_catalog.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const CardFace = preload("res://scripts/card_face.gd")
const Formation = preload("res://scripts/formation_view.gd")
const Circle = preload("res://scripts/circle_view.gd")
const Fan = preload("res://scripts/hand_fan.gd")
const StancePanel = preload("res://scripts/enemy_row_view.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")
var state
var busy := false
var selected_uid := -2
var selected_slot := -1
var basic_target := -1
var pending_play := false
var pending_visual_sources: Dictionary = {}
var action_options: Dictionary = {}
var selected_crystals := 0
var locked_cost := -1
var selected_boosts: Array = []
var pair_first := -1
var hovered_reaction := -1
var reaction_panel: PanelContainer
var reaction_text: Label
var deck_count_label: Label
var discard_count_label: Label
var discard_pending_label: Label
var discard_dialog: AcceptDialog
var boost_dialog: AcceptDialog
var scry_dialog: ConfirmationDialog
var scry_body: VBoxContainer
var scry_order: Array = []
var scry_zones: Dictionary = {}
var scry_signature := ""
var payment: Array = []
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
var drag_hover_ship := -999
var drag_serial := 0
var drag_payload: Dictionary = {}
var history_dialog: AcceptDialog
var inspection_scroll: ScrollContainer
var trigger_preview_data: Dictionary={}
var actions: VBoxContainer
var end_phase_highlight: Panel
var campaign_attempt := 0


func _ready() -> void:
	get_tree().auto_accept_quit = true
	if BattleSession.campaign_battle:
		var pending := CampaignStore.pending_battle()
		if pending.is_empty():
			get_tree().change_scene_to_file.call_deferred("res://scenes/campaign.tscn")
			return
		campaign_attempt = int(pending.id)
		state = State.new(int(pending.seed), pending.document, pending.options)
	else:
		state = State.new(-1, BattleSession.battle_content(ContentStore.snapshot()))
	BattleSession.clear_result()
	theme = _make_theme()
	_build_ui()
	feedback = Feedback.new()
	feedback.card_stage = Control.new()
	feedback.card_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.card_stage.z_index = 5
	add_child(feedback.card_stage)
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
	var button: Button = preload("res://scripts/card_pile.gd").new() if id in ["DeckPile","DiscardPile"] else Button.new()
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
	var background := preload("res://scripts/sky_background.gd").new()
	background.show_top_strip = false
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
	_button(canvas, "GearButton", "⚙", func(): menu.popup(Rect2i(Vector2i(%GearButton.global_position + Vector2(0, 40)), Vector2i(220, 0))))
	_label(canvas, "Round", "").horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(canvas, "AlliedTitle", "ALLIED FLEET", 13).modulate = Color("#91c8ad")
	_label(canvas, "CircleTitle", "MAGIC CIRCLE", 13).modulate = Color("#d6adee")
	_label(canvas, "EnemyTitle", "ENEMY FORMATION", 13).modulate = Color("#ffb0a0")
	allies = _named(Formation.new(), "Allies", canvas)
	allies.drop_check = _can_drop_ship
	allies.ship_drag_hovered.connect(_drag_over_ship)
	allies.ship_drag_exited.connect(_drag_leave_ship)
	allies.ship_dropped.connect(_drop_ship)
	enemies = _named(Formation.new(), "Enemies", canvas)
	for side in [allies, enemies]:
		side.z_index = 6
		side.large_cards = true
		side.large_unit_height = 156.0
	enemies.drop_check = _can_drop_ship
	enemies.ship_drag_hovered.connect(_drag_over_ship)
	enemies.ship_drag_exited.connect(_drag_leave_ship)
	enemies.ship_dropped.connect(_drop_ship)
	allies.position_selected.connect(_ally_position_pressed)
	allies.unit_selected.connect(func(id): if pending_play and not busy: _set_group_value("primary",id))
	enemies.position_selected.connect(_enemy_position_pressed)
	allies.unit_hovered.connect(func(id):_refresh_trigger_preview(-1,id))
	enemies.unit_hovered.connect(func(id):_refresh_trigger_preview(-1,id))
	allies.unit_exited.connect(func(_id):_refresh_trigger_preview())
	enemies.unit_exited.connect(func(_id):_refresh_trigger_preview())
	circle_view = _named(Circle.new(), "Circle", canvas)
	circle_view.slot_selected.connect(_circle_selected)
	circle_view.slot_hovered.connect(func(slot):_refresh_trigger_preview(-1,-999,slot))
	circle_view.slot_exited.connect(func(_slot):_refresh_trigger_preview())
	circle_view.drop_check = _can_drop_card
	circle_view.drag_slot_hovered.connect(_drag_over_slot)
	circle_view.drag_slot_exited.connect(_drag_leave_slot)
	circle_view.card_dropped.connect(_drop_card)
	stance_panel = _named(StancePanel.new(), "Stance", canvas)
	stance_panel.card_selected.connect(_stance_pressed)
	stance_panel.card_hovered.connect(_reaction_hovered)
	stance_panel.card_exited.connect(_reaction_exited)
	stance_panel.reaction_selected.connect(func(key): _set_group_value("reaction",key))
	reaction_panel = PanelContainer.new()
	reaction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(reaction_panel)
	reaction_panel.position=Vector2(16,382)
	reaction_panel.size=Vector2(350,94)
	reaction_panel.hide()
	reaction_text=Label.new()
	reaction_text.add_theme_font_size_override("font_size",10)
	reaction_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	reaction_text.max_lines_visible=5
	reaction_text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	reaction_panel.add_child(reaction_text)
	hand_view = _named(Fan.new(), "Hand", canvas)
	_button(canvas, "DeckPile", "Deck", func(): %Inspection.text = "Remaining draw pile: %d cards. Order is hidden." % state.deck.size())
	_button(canvas, "DiscardPile", "Discard", _show_discard)
	_build_pile_counters()
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
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
	for group in ["enemy", "circle", "stance", "reaction", "slot"]:
		var control := OptionButton.new()
		control.fit_to_longest_item = false
		control.custom_minimum_size.x = 135
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_named(control, group.capitalize() + "Choice", actions)
		control.item_selected.connect(func(index): action_options[group] = control.get_item_metadata(index); _update_controls())
	_button(actions, "ManaButton", "Mana 0/1", _pay_crystal)
	_button(actions, "BoostButton", "Boosts", _show_boosts)
	_button(actions, "CancelButton", "Cancel", _cancel)
	var end_phase := _button(canvas, "EndPhaseButton", "End Turn", _end_phase)
	end_phase_highlight = Panel.new()
	end_phase_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_phase.add_child(end_phase_highlight)
	end_phase_highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var highlight := StyleBoxFlat.new()
	highlight.draw_center = false
	highlight.border_color = Color("#ffe09a")
	highlight.set_border_width_all(2)
	highlight.set_corner_radius_all(10)
	highlight.shadow_color = Color(1.0, 0.73, 0.26, 0.8)
	highlight.shadow_size = 9
	end_phase_highlight.add_theme_stylebox_override("panel", highlight)
	end_phase_highlight.hide()
	%EndPhaseButton.mouse_entered.connect(func():
		if not busy and not pending_play and dragged_uid<0:_apply_trigger_preview(state.turn_trigger_preview()))
	%EndPhaseButton.mouse_exited.connect(func():_refresh_trigger_preview())
	_button(canvas, "HistoryButton", "History", _show_history)
	_button(actions, "WinButton", "Test Win", _navigate.bind("res://scenes/victory.tscn"))
	_button(actions, "LossButton", "Test Loss", _navigate.bind("res://scenes/defeat.tscn"))
	inspection_scroll = ScrollContainer.new()
	inspection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	canvas.add_child(inspection_scroll)
	var inspection := _label(inspection_scroll, "Inspection", "", 14)
	inspection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspection.modulate = Color("#e8bd77")
	_label(canvas, "Status", "", 12).modulate = Color("#80a7b7")
	menu = PopupMenu.new()
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.add_item("Resume", 0)
	if BattleSession.editor_playtest:
		menu.add_item("Return to Editor", 1)
	menu.add_item("Main Menu", 2)
	if not BattleSession.campaign_battle:
		menu.add_separator()
		menu.add_item("Test Win", 3)
		menu.add_item("Test Loss", 4)
	%WinButton.hide()
	%LossButton.hide()
	add_child(menu)
	menu.about_to_popup.connect(func(): get_tree().paused = true)
	menu.popup_hide.connect(func(): get_tree().paused = false)
	menu.id_pressed.connect(func(id):
		get_tree().paused = false
		if id == 1:
			_navigate("res://scenes/editor.tscn")
		elif id == 2:
			_navigate("res://scenes/main_menu.tscn")
		elif id == 3: _navigate("res://scenes/victory.tscn")
		elif id == 4: _navigate("res://scenes/defeat.tscn"))
	history_dialog = AcceptDialog.new()
	history_dialog.get_ok_button().hide()
	history_dialog.title = "Action history"
	history_dialog.min_size = Vector2i(780, 460)
	add_child(history_dialog)
	boost_dialog = AcceptDialog.new()
	boost_dialog.visibility_changed.connect(func(): if not boost_dialog.visible: _try_resolve_pending.call_deferred())
	boost_dialog.title = "Optional boosts / choose before payment"
	boost_dialog.ok_button_text = "Use selected boosts"
	boost_dialog.min_size = Vector2i(650, 300)
	add_child(boost_dialog)
	scry_dialog = ConfirmationDialog.new()
	scry_dialog.title = "Scry / hidden information already revealed"
	scry_dialog.ok_button_text = "Confirm Scry"
	scry_dialog.min_size = Vector2i(800, 500)
	scry_dialog.dialog_hide_on_ok = false
	scry_dialog.get_cancel_button().hide()
	add_child(scry_dialog)
	scry_body = VBoxContainer.new()
	scry_dialog.add_child(scry_body)
	scry_dialog.confirmed.connect(_confirm_scry)
	scry_dialog.canceled.connect(func(): if state.phase == "scry": _show_scry.call_deferred())
	actions.minimum_size_changed.connect(_layout.call_deferred)
	canvas.resized.connect(_layout)
	_layout()


func _layout() -> void:
	var w: float = canvas.size.x
	var hand_top := maxf(800, canvas.size.y) - 245
	var controls_top := hand_top - 127
	var formation_width := minf(440, w / 2 - 175)
	%GearButton.position = Vector2(16, 6)
	%GearButton.size = Vector2(40, 36)
	%Round.position = Vector2(w - 236, 10)
	%Round.size = Vector2(220, 22)
	%AlliedTitle.position = Vector2(20, 45)
	%EnemyTitle.position = Vector2(w - formation_width, 45)
	%CircleTitle.position = Vector2(w / 2 - 75, 16)
	allies.position = Vector2(8, 62)
	allies.size = Vector2(formation_width, controls_top - 82)
	enemies.position = Vector2(w - formation_width - 8, 62)
	enemies.size = allies.size
	circle_view.position = Vector2(w / 2 - 170, 36)
	circle_view.size = Vector2(340, controls_top - 49)
	stance_panel.position = Vector2(w / 2 + 8, controls_top)
	stance_panel.size = Vector2(w / 2 - 24, 124)
	hand_view.position = Vector2(118, hand_top)
	hand_view.size = Vector2(w - 236, 220)
	%DeckPile.position = Vector2(16, hand_top + 34)
	%DeckPile.size = Vector2(92, 158)
	%DiscardPile.position = Vector2(w - 108, hand_top + 34)
	%DiscardPile.size = Vector2(92, 158)
	%HistoryButton.position = Vector2(16, hand_top - 9)
	%HistoryButton.size = Vector2(92, 36)
	%EndPhaseButton.position = Vector2(w - 114, hand_top - 9)
	%EndPhaseButton.size = Vector2(104, 36)
	actions.position = Vector2(w / 2 - 110, controls_top + 3)
	actions.size = Vector2(98, 108)
	var help_width := actions.position.x - 28
	%Status.position = Vector2(16, controls_top + 42)
	%Status.size = Vector2(help_width, 20)
	inspection_scroll.position = Vector2(16, controls_top + 62)
	inspection_scroll.size = Vector2(help_width, hand_top - inspection_scroll.position.y - 8)
	reaction_panel.position = %Status.position
	reaction_panel.size = Vector2(help_width, hand_top - reaction_panel.position.y - 8)


func _render() -> void:
	_show_board(state.board_snapshot())
	for child in hand_view.get_children():
		hand_view.remove_child(child)
		child.queue_free()
	var ordered_hand: Array = state.hand.duplicate()
	ordered_hand.sort_custom(func(a, b):
		var first: Dictionary = state.card(a)
		var second: Dictionary = state.card(b)
		if first.owner != second.owner: return first.owner < second.owner
		var first_type: int = Rules.TYPES.find(first.type)
		var second_type: int = Rules.TYPES.find(second.type)
		if first_type != second_type: return first_type < second_type
		if first.name != second.name: return first.name.naturalnocasecmp_to(second.name) < 0
		return a < b)
	for uid in ordered_hand:
		if pending_play and (uid == selected_uid or payment.has(uid)):
			continue
		var face := CardFace.new()
		face.name = "Card%d" % uid
		face.set_meta("uid", uid)
		hand_view.add_child(face)
		face.configure(state.card(uid), state.ships[state.card(uid).owner])
		face.pressed.connect(_choose_card.bind(uid))
		face.drag_provider = _begin_card_drag.bind(uid)
		face.tooltip_text += "\nDrag to the circle to play, to %s to repair/recover, an adjacent ally/empty position to swap/move, or an enemy to attack. Basic actions immediately discard this card on drop." % state.ships[state.card(uid).owner].name
		face.mouse_entered.connect(func(): hand_view.hover(face, true);_refresh_trigger_preview(uid))
		face.mouse_exited.connect(func(): hand_view.hover(face, false);_refresh_trigger_preview())
	hand_view.arrange()
	%Round.text = "ROUND %02d / %s" % [state.round_number, state.phase.to_upper()]
	_update_controls()
	if state.phase == "scry": _show_scry.call_deferred()
	if state.outcome != "":
		_navigate.call_deferred("res://scenes/%s.tscn" % state.outcome)


func _show_piles(_snapshot: Dictionary) -> void:
	%DeckPile.show_cards(state.deck.size())
	var top: Dictionary=state.card(state.discard.back()) if not state.discard.is_empty() else {}
	%DiscardPile.show_cards(state.discard.size(),top,state.ships[top.owner] if not top.is_empty() else {})
	%DeckPile.text = "DECK\n%d" % state.deck.size()
	var pending_count: int = payment.size() + (1 if basic_target >= 0 else 0) if pending_play and not busy else 0
	%DiscardPile.text = "DISCARD\n%d" % state.discard.size() + ("\n+%d pending" % pending_count if pending_count > 0 else "")
	if is_instance_valid(deck_count_label):
		deck_count_label.text=str(state.deck.size())
		discard_count_label.text=str(state.discard.size())
		discard_pending_label.text="+%d pending" % pending_count if pending_count>0 else ""
	var pending_names: Array = []
	if pending_play:
		for uid in payment:
			pending_names.append(state.card(uid).name)
		if basic_target >= 0:
			pending_names.append(state.card(selected_uid).name)
	%DiscardPile.tooltip_text = "Click to inspect %d discarded cards, newest first." % state.discard.size() + ("\nPending: " + ", ".join(pending_names) + ". Cancel Play returns these cards." if not pending_names.is_empty() else "")


func _show_board(snapshot: Dictionary) -> void:
	%ManaButton.text = "Mana %d/%d" % [snapshot.mana, snapshot.mana_capacity]
	allies.configure(snapshot, false)
	enemies.configure(snapshot, true, state.definitions.monster)
	var cards: Dictionary = {}
	for uid in snapshot.circle:
		if uid >= 0:
			cards[uid] = state.card(uid)
	var displayed_circle: Array = snapshot.circle.duplicate()
	if pending_play and selected_uid >= 0 and basic_target < 0 and selected_slot >= 0:
		displayed_circle[selected_slot] = selected_uid
		var pending_card: Dictionary = state.card(selected_uid).duplicate(true)
		pending_card["pending_status"] = "PENDING %d/%d" % [_payment_amount(), _current_cost()]
		cards[selected_uid] = pending_card
	circle_view.configure(displayed_circle, snapshot.expanded, cards, snapshot.used_triggers, selected_slot, [], {}, snapshot.persistence)
	stance_panel.configure(snapshot.stance_row, snapshot.stunned, int(action_options.get("stance", -1)), state.enemy_row_capacity)
	%CircleTitle.text = "MAGIC CIRCLE / %d" % (9 if snapshot.expanded else 4)
	_show_piles(snapshot)


func _circle_selected(slot: int) -> void:
	if busy or dragged_uid>=0 or state.phase!="fleet": return
	if pending_play:
		if state.choice_flags(selected_uid,selected_slot,_action_options()).circle and state.circle[slot]>=0: _set_group_value("circle",state.circle[slot])
		elif state.choice_flags(selected_uid,selected_slot,_action_options()).circle and slot==selected_slot: _set_group_value("circle",selected_uid)
		return
	if state.circle[slot] >= 0:
		var info: Dictionary = state.card(state.circle[slot])
		%Inspection.text = info.name + ": " + info.effect
		return
	if selected_uid >= 0 and (slot < 4 or state.expanded):
		_stage_circle(selected_uid, slot)


func _choose_card(uid: int) -> void:
	if busy or dragged_uid >= 0:
		return
	if state.phase == "discard":
		var error: String = state.discard_for_relay(uid)
		if error == "":
			await _present_resolution()
		return
	if state.phase == "refresh": return
	if pending_play:
		if basic_target >= 0:
			%Inspection.text = "This basic action discards its own card. Resolve it or Cancel Play."
			return
		if uid == selected_uid or payment.has(uid) or not state.hand.has(uid):
			return
		if _payment_amount() >= _current_cost():
			%Inspection.text = "Payment complete. Click the highlighted target; the card resolves automatically."
			return
		busy = true
		_update_controls()
		await feedback.stage_payment(uid, self)
		payment.append(uid)
		busy = false
		_render()
		payment_finished.emit()
		return
	if selected_uid == uid:
		_cancel()
	else:
		_select(uid)


func _toggle(items: Array, uid: int) -> void:
	if items.has(uid):
		items.erase(uid)
	else:
		items.append(uid)


func _select(uid: int) -> void:
	if busy or pending_play or dragged_uid >= 0 or state.phase != "fleet":
		return
	selected_uid = uid
	basic_target = -1
	selected_slot = state.first_slot() if uid >= 0 else -1
	payment.clear()
	selected_crystals = 0
	selected_boosts.clear()
	action_options.clear()
	locked_cost = 1 if uid == -1 else -1
	pending_play = uid == -1
	_fill_choices()
	_update_controls()


func _fill_choices() -> void:
	target = -1
	movement_target = -1
	for group in ["primary", "movement", "enemy", "circle", "stance", "reaction", "slot"]:
		var control: OptionButton = get_node({"primary": "%TargetChoice", "movement": "%MovementChoice"}.get(group, "%" + group.capitalize() + "Choice"))
		control.clear()
		var choices: Array = state.choices(selected_uid, group, selected_slot, _action_options())
		if pending_play and not choices.is_empty():
			control.add_item("Choose " + group + "…", -999)
			control.set_item_metadata(0, -999)
		for option in choices:
			control.add_item(option.label, int(option.value) if option.value is int else control.item_count)
			control.set_item_metadata(control.item_count - 1, option.value)
		if control.item_count > 0:
			control.select(0)
			var value: Variant = -999 if pending_play else control.get_item_metadata(0)
			if group == "primary": target = int(value)
			elif group == "movement": movement_target = int(value)
			else: action_options[group] = value


func _cancel() -> void:
	if busy or dragged_uid >= 0:
		return
	_clear_draft()
	_render()


func _clear_draft() -> void:
	pending_play = false
	pending_visual_sources.clear()
	action_options.clear()
	selected_boosts.clear()
	selected_crystals = 0
	pair_first = -1
	locked_cost = -1
	selected_uid = -2
	basic_target = -1
	selected_slot = -1
	payment.clear()
	target = -1
	movement_target = -1
	%TargetChoice.clear()
	%MovementChoice.clear()


func _commit() -> void:
	if busy or dragged_uid >= 0:
		return
	var error := ""
	if state.phase == "refresh":
		error = state.refresh([])
	elif not pending_play:
		return
	elif basic_target >= 0:
		error = state.play_basic(selected_uid, basic_target, _action_options())
	elif selected_uid != -2:
		error = state.play(selected_uid, payment, target, movement_target, selected_slot, _action_options())
	else:
		return
	if error != "":
		%Inspection.text = error
		return
	if pending_play and basic_target < 0:
		for event in state.feedback_events:
			if event.kind == "card_played":
				event["already_staged"] = selected_uid >= 0
				event["payment_previewed"] = true
	pending_play = false
	await _present_resolution()


func _end_phase() -> void:
	if busy or pending_play or dragged_uid >= 0:
		return
	var error: String = state.end_phase()
	if error != "":
		%Inspection.text = error
		return
	await _present_resolution()


func _present_resolution() -> void:
	busy = true
	reaction_panel.hide()
	inspection_scroll.show()
	%Status.show()
	_update_controls()
	await feedback.play(state.feedback_events.duplicate(true), self)
	if state.phase == "refresh" and state.outcome == "":
		state.refresh([])
		await feedback.play(state.feedback_events.duplicate(true),self)
	busy = false
	_clear_draft()
	_render()
	resolution_finished.emit()


func _update_controls() -> void:
	if dragged_uid >= 0:
		_update_drag_feedback()
		return
	circle_view.drag_active = false
	for button in [%CancelButton,%EndPhaseButton,%ManaButton,%BoostButton,%WinButton,%LossButton]: button.disabled = busy
	for group in ["Target","Movement","Enemy","Circle","Stance","Reaction","Slot"]: get_node("%"+group+"Choice").hide()
	for button in hand_view.get_children():
		var uid: int = button.get_meta("uid")
		button.disabled = busy
		button.set_pressed_no_signal(uid == selected_uid or payment.has(uid))
		button.modulate=Color.WHITE
		button.discard_choice=not busy and (state.phase=="discard" or (pending_play and state.phase=="fleet" and basic_target<0 and uid!=selected_uid and _payment_amount()<_current_cost()))
	hand_view.selected_uid = selected_uid
	hand_view.arrange()
	%ManaButton.text = "Mana %d/%d" % [state.mana-(selected_crystals if pending_play else 0),state.fleet_stat("mana_capacity")]
	%ManaButton.disabled = busy or not pending_play or state.phase!="fleet" or state.mana<=selected_crystals or _payment_amount()>=_current_cost()
	%ManaButton.tooltip_text = "Click to pay one mana crystal. Cancel Play refunds pending payment."
	%BoostButton.disabled = busy or selected_uid<0 or state.phase!="fleet" or not payment.is_empty() or selected_crystals>0 or _boost_options().is_empty()
	%BoostButton.text = "Boosts (%d)" % selected_boosts.size()
	%BoostButton.tooltip_text = "Select a card and choose optional boosts before dropping/paying."
	%CancelButton.disabled = busy or selected_uid == -2
	%CancelButton.text = "Cancel Play" if pending_play else "Cancel"
	%EndPhaseButton.disabled = busy or pending_play or state.phase!="fleet"
	end_phase_highlight.visible = not %EndPhaseButton.disabled and state.hand.is_empty()
	%EndPhaseButton.tooltip_text = "Your hand is empty. End your turn." if end_phase_highlight.visible else "End your turn."
	if busy:
		%Inspection.text = "Resolving action and chained effects…"
	elif state.phase == "discard":
		%Inspection.text = "%s: click %d more cards to discard." % [state.pending.title,state.pending.discard_remaining]
	elif state.phase == "scry":
		%Inspection.text = "Scry: choose hand cards and order the remaining cards."
	elif pending_play:
		var preview: Dictionary = state.preview(selected_uid,payment,target,movement_target,selected_slot,_action_options())
		%Inspection.text = "Payment %d/%d. Click highlighted ships/slots for targets. Resolves automatically when ready. Cancel Play refunds the pending action. %s" % [_payment_amount(),_current_cost(),preview.text]
		_show_target_choices()
		_try_resolve_pending.call_deferred()
	else:
		allies.show_basic_targets()
		enemies.show_basic_targets()
		enemies.show_rule_preview()
		%Inspection.text = "Drag to the circle to play. Drop on a ship, adjacent empty position, or enemy for an immediate basic action."
	var cards: Dictionary = {}
	for uid in state.circle:
		if uid>=0: cards[uid]=state.card(uid)
	var shown: Array = state.circle.duplicate()
	var contributors: Array=state.contributing_cards(selected_uid,selected_slot) if selected_uid>=0 else []
	var details: Dictionary=state.contribution_details(selected_uid,selected_slot) if selected_uid>=0 else {}
	if pending_play and selected_uid>=0:
		shown[selected_slot]=selected_uid
		cards[selected_uid]=state.card(selected_uid).duplicate(true)
		cards[selected_uid]["pending_status"]="PENDING %d/%d" % [_payment_amount(),_current_cost()]
		contributors=state.contributing_cards(selected_uid,selected_slot)
		details=state.contribution_details(selected_uid,selected_slot)
	circle_view.configure(shown,state.expanded,cards,state.used_triggers,selected_slot,contributors,details,state.persistence)
	%Status.text = "Hand %d / In circle %d" % [state.hand.size(),state.play_order.size()]
	_show_piles(state.board_snapshot())
	_refresh_trigger_preview()


func _try_resolve_pending() -> void:
	if busy or not pending_play or dragged_uid>=0 or get_tree().paused or boost_dialog.visible or state.phase!="fleet": return
	if state.validate(selected_uid,payment,target,movement_target,selected_slot,_action_options())=="": _commit()


func _show_target_choices() -> void:
	var ally_notes: Dictionary={}
	var enemy_notes: Dictionary={}
	var flags: Dictionary=state.choice_flags(selected_uid,selected_slot,_action_options())
	for group in ["primary","movement","slot"]:
		for item in state.choices(selected_uid,group,selected_slot,_action_options()):
			var value: int=item.value
			if group=="slot" or (flags.movement and not flags.ally) or group=="movement":
				if value in range(4): ally_notes[state.formation[value] if state.formation[value]>=0 else 100+value]="Click to move / choose slot"
			elif flags.ally: ally_notes[value]="Click to choose ally"
	if flags.pair:
		for point in 4:
			if state.formation[point]>=0: ally_notes[state.formation[point]]="Click two adjacent ships to swap"
	for item in state.choices(selected_uid,"enemy",selected_slot,_action_options()): enemy_notes[item.value]="Click to choose enemy"
	if target>=0 and ally_notes.has(target): ally_notes[target]="Selected ally"
	var enemy_id: int=action_options.get("enemy",-999)
	if enemy_notes.has(enemy_id): enemy_notes[enemy_id]="Selected enemy"
	allies.show_rule_preview(ally_notes,target if flags.ally else -999)
	enemies.show_rule_preview(enemy_notes,enemy_id)


func _show_history() -> void:
	history_dialog.dialog_text = "\n".join(state.history.slice(maxi(0, state.history.size() - 30)))
	history_dialog.popup_centered()


func _navigate(destination: String) -> void:
	if busy and destination not in ["res://scenes/main_menu.tscn", "res://scenes/editor.tscn"]:
		return
	get_tree().paused = false
	if destination in ["res://scenes/victory.tscn", "res://scenes/defeat.tscn"]:
		var reported := destination.get_file().get_basename()
		var summary: Dictionary = state.result_summary(reported)
		if BattleSession.campaign_battle:
			if state.outcome != reported: return
			if not CampaignStore.settle(campaign_attempt, summary):
				var dialog := AcceptDialog.new()
				dialog.title = "Campaign save"
				dialog.dialog_text = CampaignStore.last_error
				dialog.ok_button_text = "Retry save"
				dialog.confirmed.connect(func(): _navigate.call_deferred(destination))
				dialog.close_requested.connect(dialog.queue_free)
				add_child(dialog)
				dialog.popup_centered()
				return
		BattleSession.record_result(summary)
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
	preload("res://scripts/art_assets.gd").skin_theme(result)
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
	if event is InputEventMouseMotion and dragged_uid >= 0 and drag_hover_ship != -999:
		var formation_view: Control = enemies if drag_hover_ship < 0 else allies
		var widget: Control = formation_view.target_widget(drag_hover_ship)
		if widget != null:
			var point: Vector2 = widget.get_global_transform_with_canvas().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, widget.size).has_point(point):
				drag_hover_ship = -999
				_update_drag_feedback()
	if event is InputEventMouseMotion and dragged_uid >= 0 and drag_hover_slot >= 0:
		var button: Control = circle_view.buttons[drag_hover_slot]
		var local_point: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, button.size).has_point(local_point):
			drag_hover_slot = -1
			_update_drag_feedback()


func _begin_card_drag(uid: int) -> Dictionary:
	if pending_play or dragged_uid >= 0 or busy or get_tree().paused or state.phase != "fleet" or state.outcome != "" or not state.hand.has(uid):
		return {}
	drag_serial += 1
	dragged_uid = uid
	drag_hover_slot = -1
	drag_hover_ship = -999
	drag_payload = {"kind": "fleet_hand_card", "battle": get_instance_id(), "uid": uid, "serial": drag_serial}
	for face in hand_view.get_children():
		if face.get_meta("uid", -1) == uid:
			face.modulate.a = 0.35
	_update_drag_feedback()
	return drag_payload.duplicate()


func _is_our_drag(data: Variant) -> bool:
	return data is Dictionary and not drag_payload.is_empty() and data == drag_payload and dragged_uid >= 0 and state.hand.has(dragged_uid)


func _first_options(uid: int, slot: int) -> Dictionary:
	var result: Dictionary = {}
	for group in ["enemy", "circle", "stance", "reaction", "slot"]:
		var entries: Array = state.choices(uid, group, slot)
		if not entries.is_empty(): result[group] = entries[0].value
	return result


func _drop_slot_error(uid: int, slot: int) -> String:
	if busy or get_tree().paused or state.phase != "fleet" or state.outcome != "" or not state.hand.has(uid):
		return "Cards can only be placed during the fleet phase."
	if slot < 0 or slot >= (9 if state.expanded else 4) or state.circle[slot] >= 0:
		return "Choose an empty unlocked circle slot."
	var funding: Array = []
	var cost: int = state.effective_cost(uid, slot)
	var options := _first_options(uid, slot)
	var crystals: int = mini(cost, state.mana)
	options["crystals"] = crystals
	var total := crystals
	for payer in state.hand:
		if total >= cost: break
		if payer != uid:
			funding.append(payer)
			total += int(state.card(payer).pays)
	var primary: Array = state.choices(uid, "primary", slot)
	var movements: Array = state.choices(uid, "movement", slot)
	return state.validate(uid, funding, primary[0].value if not primary.is_empty() else -1, movements[0].value if not movements.is_empty() else -1, slot, options)


func _can_drop_card(data: Variant, slot: int) -> bool:
	return _is_our_drag(data) and _drop_slot_error(dragged_uid, slot) == ""


func _drag_over_slot(slot: int, data: Variant) -> void:
	if not _is_our_drag(data) or drag_hover_slot == slot:
		return
	drag_hover_slot = slot
	drag_hover_ship = -999
	_update_drag_feedback()


func _drag_leave_slot(slot: int) -> void:
	if dragged_uid >= 0 and drag_hover_slot == slot:
		drag_hover_slot = -1
		_update_drag_feedback()


func _update_drag_feedback() -> void:
	for control in [%CancelButton, %EndPhaseButton, %TargetChoice, %MovementChoice, %WinButton, %LossButton]:
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
	var trigger_data: Dictionary={}
	var title: String = state.card(dragged_uid).name
	if drag_hover_ship != -999:
		var preview: Dictionary = state.basic_preview(dragged_uid, drag_hover_ship)
		trigger_data=state.trigger_preview(dragged_uid,[], -1,-1,-1,{},drag_hover_ship)
		%Inspection.text = ("Release to act immediately. " if preview.ok else "Cannot drop: ") + preview.text
	elif drag_hover_slot >= 0:
		var error: String = circle_view.drop_errors[drag_hover_slot]
		if error == "":
			highlight = drag_hover_slot
			var primary: Array = state.choices(dragged_uid, "primary", highlight)
			var movements: Array = state.choices(dragged_uid, "movement", highlight)
			var ally: int = primary[0].value if not primary.is_empty() else -1
			var movement: int = movements[0].value if not movements.is_empty() else -1
			var selected_payment: Array = payment if selected_uid == dragged_uid and state.effective_cost(dragged_uid, highlight) > 0 else []
			var preview: Dictionary = state.preview(dragged_uid, selected_payment, ally, movement, highlight, _first_options(dragged_uid, highlight))
			trigger_data=state.trigger_preview(dragged_uid,selected_payment,ally,movement,highlight,_first_options(dragged_uid,highlight))
			contributors = preview.contributors
			details = preview.contribution_details
			%Inspection.text = "Drop %s → %s, then click cards to discard as payment and click any required target. %s" % [title, Geometry.SLOT_NAMES[highlight], preview.text]
		else:
			%Inspection.text = "Cannot place %s: %s" % [title, error]
	else:
		%Inspection.text = "Drag %s to the circle to stage a play, its own ship to repair/recover, an adjacent ship/empty position to swap/move, or an enemy to attack. Basic actions resolve immediately on drop." % title
	circle_view.configure(state.circle, state.expanded, cards, state.used_triggers, highlight, contributors, details, state.persistence)
	_apply_trigger_preview(trigger_data)


func _drop_card(slot: int, data: Variant) -> void:
	if not _can_drop_card(data, slot):
		return
	var uid := dragged_uid
	_finish_card_drag(false)
	_stage_circle(uid, slot)


func _finish_card_drag(refresh: bool = true) -> void:
	dragged_uid = -1
	drag_hover_slot = -1
	drag_hover_ship = -999
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
		drag_hover_ship = -999
		_update_drag_feedback()


func _drop_ship(ship_id: int, data: Variant) -> void:
	if not _can_drop_ship(data, ship_id): return
	var uid := dragged_uid
	_finish_card_drag(false)
	var error: String = state.play_basic(uid, ship_id)
	if error != "":
		%Inspection.text = error
		_update_controls()
		return
	await _present_resolution()


func _update_basic_highlights(uid: int = -1, hovered: int = -999) -> void:
	if uid < 0 and basic_target >= 0:
		uid = selected_uid
		hovered = basic_target
	if uid < 0:
		allies.show_basic_targets()
		enemies.show_basic_targets()
		return
	var previews: Dictionary = {}
	for ship_id in state.basic_targets():
		previews[ship_id] = state.basic_preview(uid, ship_id)
	allies.show_basic_targets(previews, hovered)
	enemies.show_basic_targets(previews, hovered)


func _stage_circle(uid: int, slot: int) -> void:
	if pending_play or _drop_slot_error(uid, slot) != "":
		return
	var boosts: Array = selected_boosts.duplicate() if selected_uid==uid else []
	_select(uid)
	selected_boosts=boosts
	selected_slot = slot
	locked_cost = state.effective_cost(uid, slot)
	pending_play = true
	var face: Node = hand_view.get_node_or_null("Card%d" % uid)
	if face != null:
		pending_visual_sources[uid] = {"rect": face.get_global_rect()}
	_fill_choices()
	_render()



func _action_options() -> Dictionary:
	var result := action_options.duplicate(true)
	result["crystals"] = selected_crystals
	result["boosts"] = selected_boosts.duplicate()
	if pending_play and locked_cost >= 0 and basic_target < 0: result["locked_cost"] = locked_cost
	return result


func _current_cost() -> int:
	return locked_cost if pending_play and locked_cost >= 0 else (state.effective_cost(selected_uid, selected_slot) if selected_uid != -2 else 0)


func _payment_amount() -> int:
	return state.payment_total(payment) + selected_crystals


func _pay_crystal() -> void:
	if busy or not pending_play or basic_target >= 0 or state.phase != "fleet" or state.mana <= selected_crystals or _payment_amount() >= _current_cost(): return
	selected_crystals += 1
	_update_controls()
	payment_finished.emit()


func _boost_options() -> Array:
	if selected_uid < 0 or state.card(selected_uid).is_empty(): return []
	var c: Dictionary = state._context(selected_uid, target, movement_target, selected_slot, _action_options())
	if basic_target >= 0:
		c["ally"] = basic_target
		c["basic_type"] = "Support" if int(state.card(selected_uid).owner) == basic_target else "Manoeuvre"
	return state.boost_options(selected_uid, c)


func _show_boosts() -> void:
	if selected_uid<0 or busy or not payment.is_empty() or selected_crystals>0: return
	for child in boost_dialog.get_children():
		if child.get_meta("boost_body", false):
			boost_dialog.remove_child(child)
			child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.set_meta("boost_body", true)
	scroll.custom_minimum_size = Vector2(620,220)
	boost_dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_plain_label(column, "Reserve personal resource before mana payment. Cancel Play spends nothing. Automatic spending uses the remaining resource.", 13)
	for option in _boost_options():
		var check := CheckBox.new()
		check.text = option.title
		check.tooltip_text = Rules.rule_text(option.rule, str(state.ships[state.card(selected_uid).owner].name))
		check.button_pressed = selected_boosts.has(option.key)
		column.add_child(check)
		_plain_label(column, Rules.rule_text(option.rule, str(state.ships[state.card(selected_uid).owner].name)), 13).custom_minimum_size.x = 590
		check.toggled.connect(func(enabled):
			if enabled and not selected_boosts.has(option.key): selected_boosts.append(option.key)
			elif not enabled: selected_boosts.erase(option.key)
			_fill_choices()
			_update_controls())
	boost_dialog.popup_centered(Vector2i(650,300))


func _set_group_value(group: String, value: Variant) -> void:
	var control: OptionButton = get_node({"primary": "%TargetChoice", "movement": "%MovementChoice"}.get(group, "%" + group.capitalize() + "Choice"))
	for index in control.item_count:
		if typeof(control.get_item_metadata(index)) == typeof(value) and control.get_item_metadata(index) == value:
			control.select(index)
			if group == "primary": target = int(value)
			elif group == "movement": movement_target = int(value)
			else: action_options[group] = value
			_update_controls()
			return


func _ally_position_pressed(point: int) -> void:
	if busy or not pending_play: return
	var flags: Dictionary=state.choice_flags(selected_uid,selected_slot,_action_options())
	if flags.pair and not flags.ally:
		if pair_first<0: pair_first=point; %Inspection.text="Choose the second adjacent ship."; return
		_set_group_value("primary",100+mini(pair_first,point)*4+maxi(pair_first,point))
		pair_first=-1
	elif flags.ally and (target<0 or (not flags.movement and not flags.slot)) and state.formation[point]>=0:
		_set_group_value("primary",state.formation[point])
	elif flags.movement:
		_set_group_value("movement" if flags.ally else "primary",point)
	elif flags.slot: _set_group_value("slot",point)


func _enemy_position_pressed(point: int) -> void:
	if busy or not pending_play or basic_target >= 0 or state.enemy_formation[point] < 0: return
	_set_group_value("enemy", -1 - int(state.enemy_formation[point]))


func _stance_pressed(uid: int) -> void:
	if pending_play and not busy and basic_target < 0:
		_set_group_value("stance", uid)
	else:
		%Inspection.text = state.row_card(uid).owner_name + " / " + state.row_card(uid).name + ". Hover for complete reaction and activation rules."


func _show_scry() -> void:
	if state.phase != "scry" or busy: return
	var signature := JSON.stringify(state.pending.revealed)
	if signature != scry_signature:
		scry_signature = signature
		scry_dialog.dialog_text = ""
		scry_order = state.pending.revealed.duplicate()
		scry_zones.clear()
		for uid in scry_order: scry_zones[uid] = "top"
	_render_scry()
	scry_dialog.popup_centered(Vector2i(800,500))


func _render_scry() -> void:
	for child in scry_body.get_children():
		scry_body.remove_child(child)
		child.queue_free()
	_plain_label(scry_body, "Take exactly %d. Remaining cards may return to the top or be discarded. Top and discard orders follow the list from top to bottom. Once revealed, these choices must be completed." % state.pending.take, 14)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(750, 340)
	scry_body.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	for index in scry_order.size():
		var uid: int = scry_order[index]
		var row := HBoxContainer.new()
		column.add_child(row)
		var title := _plain_label(row, state.card(uid).name + " / " + state.card(uid).type, 15, 450)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.tooltip_text = state.card(uid).effect
		var choice := OptionButton.new()
		for zone in ["hand", "top", "discard"]:
			choice.add_item(zone.capitalize())
			choice.set_item_metadata(choice.item_count - 1, zone)
			if scry_zones[uid] == zone: choice.select(choice.item_count - 1)
		row.add_child(choice)
		choice.item_selected.connect(func(i): scry_zones[uid] = choice.get_item_metadata(i); _update_scry_selection())
		for text in ["↑", "↓"]:
			var button := Button.new()
			button.text = text
			row.add_child(button)
			button.pressed.connect(func():
				var destination: int = index + (-1 if text == "↑" else 1)
				if destination >= 0 and destination < scry_order.size():
					scry_order.remove_at(index)
					scry_order.insert(destination, uid)
					_render_scry())

	_update_scry_selection()


func _update_scry_selection() -> void:
	var count := 0
	for uid in scry_order:
		if scry_zones[uid] == "hand": count += 1
	scry_dialog.get_ok_button().disabled = count != int(state.pending.take)
	scry_dialog.title = "Scry / hand %d of %d · order the rest" % [count, state.pending.take]


func _confirm_scry() -> void:
	var take: Array = []
	var top: Array = []
	var rejected: Array = []
	for uid in scry_order:
		match scry_zones[uid]:
			"hand": take.append(uid)
			"top": top.append(uid)
			"discard": rejected.append(uid)
	var error: String = state.choose_scry(take, top, rejected)
	if error != "":
		scry_dialog.dialog_text = error
		return
	scry_dialog.hide()
	scry_signature = ""
	await _present_resolution()


func _plain_label(parent: Node, text: String, font: int = 13, width: float = 590) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = width
	label.size.x = width
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override('font_size', font)
	parent.add_child(label)
	return label




func _build_pile_counters() -> void:
	for pair in [[%DeckPile,"Deck"],[%DiscardPile,"Discard"]]:
		var button: Button=pair[0]
		button.set_meta("plain_text",true)
		for color in ["font_color","font_hover_color","font_pressed_color","font_disabled_color"]: button.add_theme_color_override(color,Color.TRANSPARENT)
		var box:=VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		box.offset_top=-60
		box.offset_right=-6
		box.offset_bottom=-10
		box.alignment=BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(box)
		var heading:=Label.new()
		heading.text=pair[1]
		heading.add_theme_font_size_override("font_size",12)
		heading.add_theme_color_override("font_outline_color",Color("#07151f"))
		heading.add_theme_constant_override("outline_size",7)
		heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		heading.mouse_filter=Control.MOUSE_FILTER_IGNORE
		box.add_child(heading)
		var number:=Label.new()
		number.set_meta("plain_text",true)
		number.add_theme_font_size_override("font_size",22)
		number.add_theme_color_override("font_outline_color",Color("#07151f"))
		number.add_theme_constant_override("outline_size",7)
		number.add_theme_color_override("font_color",Color.WHITE)
		number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		number.mouse_filter=Control.MOUSE_FILTER_IGNORE
		box.add_child(number)
		if pair[1]=="Deck": deck_count_label=number
		else:
			discard_count_label=number
			discard_pending_label=Label.new()
			discard_pending_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			discard_pending_label.add_theme_font_size_override("font_size",10)
			discard_pending_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
			box.add_child(discard_pending_label)

func _reaction_hovered(uid: int) -> void:
	if busy or dragged_uid>=0: return
	hovered_reaction=uid
	var action: Dictionary={"uid":selected_uid,"actor":state.card(selected_uid).get("owner",-999),"target":target}
	var preview: Dictionary=state.reaction_preview(uid,action)
	if preview.is_empty(): return
	var ally_notes: Dictionary={}
	var enemy_notes: Dictionary={}
	for id in preview.notes:
		if id>=0: ally_notes[id]=preview.notes[id]
		else: enemy_notes[id]=preview.notes[id]
	allies.show_rule_preview(ally_notes)
	enemies.show_rule_preview(enemy_notes,preview.source)
	%Inspection.text=preview.text
	reaction_text.text=preview.text
	reaction_panel.show()
	inspection_scroll.hide()
	%Status.hide()

func _reaction_exited(uid: int) -> void:
	if hovered_reaction!=uid: return
	hovered_reaction=-1
	reaction_panel.hide()
	inspection_scroll.show()
	%Status.show()
	if not busy: _update_controls()


func _show_discard() -> void:
	if is_instance_valid(discard_dialog):
		discard_dialog.free()
	discard_dialog = AcceptDialog.new()
	discard_dialog.name = "DiscardViewer"
	discard_dialog.title = "Discard pile / %d cards" % state.discard.size()
	discard_dialog.get_ok_button().hide()
	add_child(discard_dialog)
	var body := VBoxContainer.new()
	discard_dialog.add_child(body)
	var heading := Label.new()
	heading.text = "Newest (top of pile) to oldest (bottom).\nPending payments are not yet discarded."
	heading.add_theme_font_size_override("font_size", 14)
	body.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	scroll.add_child(row)
	if state.discard.is_empty():
		var empty := Label.new()
		empty.text = "The discard pile is empty."
		row.add_child(empty)
	for offset in state.discard.size():
		var uid: int = state.discard[state.discard.size() - 1 - offset]
		var column := VBoxContainer.new()
		row.add_child(column)
		var order := Label.new()
		order.set_meta("plain_text", true)
		order.text = "#%d%s" % [offset + 1, " - TOP / NEWEST" if offset == 0 else (" - BOTTOM / OLDEST" if offset == state.discard.size() - 1 else "")]
		column.add_child(order)
		var face := CardFace.new()
		face.set_meta("discard_uid", uid)
		face.custom_minimum_size = Vector2(240, 350)
		face.toggle_mode = false
		face.mouse_default_cursor_shape = Control.CURSOR_ARROW
		face.configure(state.card(uid), state.ships[state.card(uid).owner])
		column.add_child(face)
	var viewer_size := Vector2i(minf(960, get_viewport_rect().size.x * 0.9), minf(490, get_viewport_rect().size.y * 0.9))
	body.custom_minimum_size.x = maxf(240, viewer_size.x - 40)
	discard_dialog.popup_centered(viewer_size)

func _refresh_trigger_preview(hover_uid: int = -1, hover_target: int = -999, hover_slot: int = -1) -> void:
	if dragged_uid>=0:return
	var data: Dictionary={}
	var uid: int=selected_uid if pending_play or hover_uid<0 else hover_uid
	if not busy and state.phase=="fleet" and uid>=0:
		var payments:=payment.duplicate() if pending_play else []
		if pending_play and hover_uid>=0 and hover_uid!=uid and not payments.has(hover_uid) and _payment_amount()<_current_cost():payments.append(hover_uid)
		var primary: int=target
		var move: int=movement_target
		var slot: int=selected_slot if pending_play or hover_slot<0 else hover_slot
		var choices: Dictionary=_action_options() if uid==selected_uid else {}
		if hover_target!=-999 and pending_play:
			var flags: Dictionary=state.choice_flags(uid,slot,choices)
			if hover_target<0:choices.enemy=hover_target
			elif flags.ally:primary=hover_target
			elif flags.movement:primary=state.position_of(hover_target)
			elif flags.slot:choices.slot=state.position_of(hover_target)
		data=state.trigger_preview(uid,payments,primary,move,slot,choices)
	var hovered_owner: int = int(state.card(hover_uid).get("owner", -999)) if not busy and state.phase == "fleet" else -999
	_apply_trigger_preview(data, hovered_owner)

func _apply_trigger_preview(data: Dictionary = {}, hovered_owner: int = -999) -> void:
	trigger_preview_data=data.duplicate(true)
	stance_panel.show_trigger_preview(data.get("reactions",[]),data.get("provisional",false))
	circle_view.show_trigger_preview(data.get("cards",{}))
	for face in hand_view.get_children():face.trigger_rules=data.get("cards",{}).get(face.get_meta("uid",-1),[])
	for id in state.ships.size():
		var widget=allies.target_widget(id)
		if widget!=null and widget.has_method("show_trigger_preview"):widget.show_trigger_preview(data.get("ships",{}).get(id,[]), id == hovered_owner)
	var discard_face=%DiscardPile.face
	if discard_face!=null and not state.discard.is_empty():discard_face.trigger_rules=data.get("cards",{}).get(state.discard.back(),[])
