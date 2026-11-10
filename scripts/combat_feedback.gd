extends CanvasLayer
## Plays public combat events. Rules resolve once; animation never mutates battle state.

signal beat_started(kind: String)
signal finished

var duration_scale: float = 1.0
var running: bool = false
var view: Control
var overlay: Control
var banner: PanelContainer
var banner_label: Label
var _sources: Dictionary = {}
var _paid: Array = []
var _played_uid: int = -2
var _played_position := Vector2.ZERO


func _ready() -> void:
	layer = 20
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	banner = PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(banner)
	banner_label = Label.new()
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 22)
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(banner_label)
	banner.hide()


func play(events: Array, battle_view: Control) -> void:
	if running:
		return
	running = true
	view = battle_view
	_sources.clear()
	_paid.clear()
	_played_uid = -2
	# Let container layouts settle before recording screen-space card positions.
	await _pause(0.025)
	for button in view.get_node("%Hand").get_children():
		_sources[button.get_meta("uid")] = {"node": button, "rect": button.get_global_rect()}
	for event in events:
		beat_started.emit(event.kind)
		match event.kind:
			"card_played":
				_played_uid = event.uid
				_message("PLAYING  /  " + event.title, Color("#e8bd77"))
				await _discard_cards(event.payment)
				_paid = event.payment.duplicate()
				if event.uid >= 0:
					await _lift_card(event.uid)
			"cards_discarded":
				var remaining: Array = []
				for uid in event.uids:
					if not _paid.has(uid):
						remaining.append(uid)
				await _discard_cards(remaining)
			"cards_drawn":
				await _draw_cards(event.uids)
			"damage", "repair", "guard":
				await _stat_change(event)
			"movement":
				await _move_ships(event.board)
			"reaction_triggered":
				_message("MONSTER REACTION\n" + event.title, Color("#ff927f"))
				_highlight_reaction(true)
				await _pause(0.58)
				_highlight_reaction(false)
			"reaction_revealed":
				await _apply_board(event.board)
				_message("NEW REACTION  /  " + event.title, Color("#e8bd77"))
				await _pause(0.38)
			"intent_triggered":
				_message("ENEMY INTENT\n" + event.title, Color("#ff927f"))
				await _pause(0.50)
			"destroyed":
				_message("SHIP LOST  /  " + event.title, Color("#ff927f"))
				var panel := _ship_panel(event.target)
				if panel != null:
					var tween := create_tween()
					tween.tween_property(panel, "modulate:a", 0.0, _time(0.25))
					await tween.finished
				await _apply_board(event.board)
		view._show_piles(event.board)
	if view.state.outcome != "":
		_message(view.state.outcome.to_upper(), Color("#e8bd77") if view.state.outcome == "victory" else Color("#ff927f"))
		await _pause(0.55)
	banner.hide()
	_highlight_reaction(false)
	running = false
	finished.emit()


func _time(seconds: float) -> float:
	return maxf(0.001, seconds * duration_scale)


func _pause(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_interval(_time(seconds))
	await tween.finished


func _message(text: String, tint: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#10212b")
	style.border_color = tint
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	banner.add_theme_stylebox_override("panel", style)
	banner_label.text = text
	banner_label.modulate = tint
	var width: float = minf(740, get_viewport().get_visible_rect().size.x - 40)
	banner.custom_minimum_size = Vector2(width, 60)
	banner.size = Vector2(width, 0)
	banner.position = Vector2((get_viewport().get_visible_rect().size.x - width) / 2.0, 12)
	banner.show()


func _highlight_reaction(enabled: bool) -> void:
	var panel := view.get_node("%ReactionName").get_parent().get_parent() as PanelContainer
	if enabled:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#482b2b")
		style.border_color = Color("#ff927f")
		style.set_border_width_all(3)
		style.set_corner_radius_all(5)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", style)
	else:
		panel.remove_theme_stylebox_override("panel")


func _visible_position(point: Vector2, extent: Vector2 = Vector2(160, 100)) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	return Vector2(clampf(point.x, 12, maxf(12, viewport_size.x - extent.x - 12)),
		clampf(point.y, 90, maxf(90, viewport_size.y - extent.y - 12)))


func _source_position(uid: int) -> Vector2:
	if _sources.has(uid):
		return _visible_position(_sources[uid].rect.position, _sources[uid].rect.size)
	return _visible_position(get_viewport().get_visible_rect().size * Vector2(0.45, 0.45))


func _ghost(uid: int, full_card: bool = false) -> Control:
	var ghost: Control
	if full_card and _sources.has(uid):
		ghost = _sources[uid].node.duplicate(0) as Control
		ghost.size = _sources[uid].rect.size
	else:
		var panel := PanelContainer.new()
		var label := Label.new()
		panel.custom_minimum_size = Vector2(164, 78)
		label.custom_minimum_size = Vector2(140, 36)
		label.text = view.state.card(uid).name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(label)
		panel.size = Vector2(164, 78)
		ghost = panel
	overlay.add_child(ghost)
	ghost.theme = view.theme
	ghost.modulate = Color.WHITE
	ghost.position = _source_position(uid)
	_ignore_input(ghost)
	return ghost


func _ignore_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_ignore_input(child)


func _hide_source(uid: int) -> void:
	if _sources.has(uid):
		_sources[uid].node.modulate.a = 0.0


func _lift_card(uid: int) -> void:
	var ghost := _ghost(uid, true)
	_hide_source(uid)
	_played_position = _visible_position(ghost.position + Vector2(0, -125), ghost.size)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ghost, "position", _played_position, _time(0.30)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "scale", Vector2.ONE * 0.88, _time(0.30))
	tween.tween_property(ghost, "modulate:a", 0.0, _time(0.12)).set_delay(_time(0.20))
	await tween.finished
	ghost.queue_free()


func _discard_cards(uids: Array) -> void:
	if uids.is_empty():
		return
	var pile := view.get_node("%PileCounts") as Control
	var destination := _visible_position(pile.get_global_rect().get_center(), Vector2(45, 35))
	var tween := create_tween().set_parallel(true)
	var ghosts: Array = []
	for index in uids.size():
		var uid: int = uids[index]
		var ghost := _ghost(uid)
		if uid == _played_uid:
			ghost.position = _played_position
		ghosts.append(ghost)
		_hide_source(uid)
		var delay: float = _time(minf(0.12, index * 0.035))
		tween.tween_property(ghost, "position", destination, _time(0.28)).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(ghost, "scale", Vector2.ONE * 0.20, _time(0.28)).set_delay(delay)
		tween.tween_property(ghost, "modulate:a", 0.0, _time(0.15)).set_delay(delay + _time(0.13))
	await tween.finished
	for ghost in ghosts:
		ghost.queue_free()
	await _popup("DISCARD +%d" % uids.size(), destination, Color("#e8bd77"), 0.26)


func _draw_cards(uids: Array) -> void:
	if uids.is_empty():
		return
	var pile := view.get_node("%PileCounts") as Control
	var start := _visible_position(pile.get_global_rect().get_center())
	var hand := view.get_node("%Hand") as Control
	var finish := _visible_position(hand.get_global_rect().get_center(), Vector2(164, 78))
	var tween := create_tween().set_parallel(true)
	var ghosts: Array = []
	for index in uids.size():
		var ghost := _ghost(uids[index])
		ghost.position = start + Vector2(index * 4, 0)
		ghost.modulate.a = 0.4
		ghosts.append(ghost)
		var delay: float = _time(minf(0.16, index * 0.035))
		tween.tween_property(ghost, "position", finish + Vector2(index * 12, 0), _time(0.28)).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(ghost, "modulate:a", 1.0, _time(0.15)).set_delay(delay)
	await tween.finished
	for ghost in ghosts:
		ghost.queue_free()


func _ship_panel(ship_id: int) -> Control:
	for panel in view.get_node("%Formation").get_children():
		if panel.get_meta("ship_index", -1) == ship_id:
			return panel
	return null


func _apply_board(snapshot: Dictionary) -> void:
	view._show_board(snapshot)
	await _pause(0.02)


func _stat_change(event: Dictionary) -> void:
	await _apply_board(event.board)
	var panel: Control = view.get_node("%MonsterBar").get_parent().get_parent().get_parent() if event.target == -1 else _ship_panel(event.target)
	if panel == null:
		return
	var anchor := _visible_position(panel.global_position + Vector2(panel.size.x * 0.5 - 90, 10), Vector2(240, 70))
	var tint := Color("#ff927f")
	var text := ""
	var bar: ProgressBar
	var amount: int = event.amount
	if event.kind == "damage":
		text = "-%d HULL" % amount if amount > 0 else "BLOCKED"
		if amount == 0 and event.blocked > 0:
			tint = Color("#8bd8ff")
		if event.blocked > 0:
			text += "\n-%d GUARD · BLOCKED %d" % [event.blocked, event.blocked]
		bar = view.get_node("%MonsterBar") if event.target == -1 else panel.get_node("%HullBar")
		bar.value += amount
	elif event.kind == "repair":
		tint = Color("#9ce6b7")
		text = "+%d HULL" % amount if amount > 0 else "HULL FULL"
		bar = panel.get_node("%HullBar")
		bar.value -= amount
	else:
		tint = Color("#8bd8ff")
		text = "%+d GUARD" % amount
		if amount < 0:
			text += " · EXPIRED"
	var tween := create_tween().set_parallel(true)
	panel.self_modulate = tint
	tween.tween_property(panel, "self_modulate", Color.WHITE, _time(0.42))
	if bar != null:
		var final_value: int = event.board.monster_hull if event.target == -1 else event.board.ships[event.target].hull
		tween.tween_property(bar, "value", final_value, _time(0.32)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _popup(text, anchor, tint, 0.52)


func _move_ships(snapshot: Dictionary) -> void:
	var ghosts: Dictionary = {}
	for panel in view.get_node("%Formation").get_children():
		var ghost := panel.duplicate(0) as Control
		overlay.add_child(ghost)
		ghost.theme = view.theme
		ghost.position = panel.global_position
		ghost.size = panel.size
		_ignore_input(ghost)
		ghosts[panel.get_meta("ship_index")] = ghost
	await _apply_board(snapshot)
	var tween := create_tween().set_parallel(true)
	for panel in view.get_node("%Formation").get_children():
		if ghosts.has(panel.get_meta("ship_index")):
			panel.modulate.a = 0.0
			tween.tween_property(ghosts[panel.get_meta("ship_index")], "position", panel.global_position, _time(0.34)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	for ghost in ghosts.values():
		ghost.queue_free()
	for panel in view.get_node("%Formation").get_children():
		panel.modulate.a = 1.0


func _popup(text: String, point: Vector2, tint: Color, duration: float) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color("#07121b"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = point
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", point.y - 34, _time(duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, _time(duration * 0.45)).set_delay(_time(duration * 0.55))
	await tween.finished
	label.queue_free()
