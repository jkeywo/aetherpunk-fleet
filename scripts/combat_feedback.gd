extends CanvasLayer
signal beat_started(kind: String)
signal enemy_presentation_started(kind: String, presentation: Dictionary)
signal enemy_presentation_finished
signal finished
signal attack_started(attacker: int, target: int)
signal area_attack_started(style: String, targets: Array)
signal melee_started(attacker: int, target: int, path: Dictionary)
signal melee_impacted(attacker: int, target: int)
signal melee_finished(attacker: int, target: int)
signal movement_started(paths: Dictionary)
var duration_scale := 1.0
var running := false
var view: Control
var overlay: Control
var banner: PanelContainer
var enemy_card: PanelContainer
var banner_label: Label
var _sources: Dictionary = {}
var _paid: Array = []
var card_stage: Control
var player_card: Control
var focus_overlay: Control
var effect_targets: Dictionary = {}


func play(events: Array, battle_view: Control) -> void:
	if running:
		return
	running = true
	view = battle_view
	_sources.clear()
	_paid.clear()
	_sources.merge(view.pending_visual_sources.duplicate(true))
	await _pause(0.02)
	for button in view.hand_view.get_children():
		_sources[button.get_meta("uid")] = {"node": button, "rect": button.get_global_rect()}
	for slot in view.circle_view.contents.size():
		var uid: int = view.circle_view.contents[slot]
		if uid >= 0:
			var button: Control = view.circle_view.buttons[slot]
			_sources[uid] = {"node": button, "rect": button.get_global_rect()}
	for index in events.size():
		var event: Dictionary = events[index]
		if event.kind in ["enemy_effect_started", "card_effect_started", "card_rule_started", "card_rule_finished", "enemy_effect_finished", "card_triggered", "reaction_triggered", "intent_triggered"]:
			_set_effect_targets()
		var target_beat_follows: bool = index + 1 < events.size() and events[index + 1].kind in ["effect_focus", "area_attack"]
		beat_started.emit(event.kind)
		match event.kind:
			"card_played":
				_message("PLAY / " + event.title, Color("#e8bd77"))
				if not event.get("payment_previewed", false):
					await _discard_cards(event.payment)
				_paid = event.payment.duplicate()
				await _apply_board(event.board)
				if event.uid >= 0:
					await _show_player_card(event.uid, event.slot, event.get("already_staged", false))
			"basic_action":
				_message(event.title, Color("#9ce6b7") if event.action == "repair" else Color("#67bdd4"))
				await _discard_cards([event.uid])
				_paid = [event.uid]
				await _apply_board(event.board)
			"revive_progress":
				await _apply_board(event.board)
				var wreck := _unit(event.target)
				if wreck != null:
					await _popup("RECOVERY +%d\n%d / %d" % [event.amount, event.board.ships[event.target].recovery, event.threshold], _visible_position(wreck.global_position), Color("#9ce6b7"), 0.45)
			"revived":
				await _apply_board(event.board)
				_message("SHIP REVIVED / " + event.title, Color("#9ce6b7"))
				var unit := _unit(event.target)
				if unit != null:
					await _popup("REVIVED / %d HULL" % event.amount, _visible_position(unit.global_position), Color("#9ce6b7"), 0.50)
			"cards_discarded":
				var remaining: Array = event.uids.filter(func(uid): return not _paid.has(uid))
				await _discard_cards(remaining)
				await _apply_board(event.board)
			"cards_drawn":
				await _draw_cards(event.uids)
			"effect_focus":
				_set_effect_targets(event)
				if not effect_targets.is_empty(): await _pause(0.18)
			"area_attack":
				_set_effect_targets({"units": event.targets})
				await _pause(0.18)
				await _area_attack_effect(event)
			"damage", "repair", "guard":
				await _stat_change(event)
			"movement":
				await _move_ships(event.board)
			"reaction_triggered":
				await _finish_player_card()
				view.stance_panel.show_trigger_preview([event.get("reaction_key","")])
				_message("MONSTER REACTION\n" + event.title, Color("#ff927f"))
				view.stance_panel.modulate = Color("#ff927f")
				await _show_enemy_card(event)
				view.stance_panel.modulate = Color.WHITE
				view.stance_panel.show_trigger_preview()
			"stance_changed":
				_message("NEW STANCE / " + event.title, Color("#e8bd77"))
				if event.get("batch_refill", false):
					view.stance_panel.end_activations()
					# Stage the incoming cards before yielding, so the new row never flashes in place.
					view._show_board(event.board)
					await view.stance_panel.animate_refill(_time(0.32))
				elif event.has("incoming_uid"):
					view.stance_panel.clear_lift()
					view._show_board(event.board)
					if event.incoming_uid >= 0:
						await view.stance_panel.animate_refill(_time(0.32), event.incoming_uid)
				else:
					await _apply_board(event.board)
					await _pause(0.30)
			"intent_triggered":
				view.stance_panel.begin_activations()
				_message("ENEMY ACTIVITY / " + event.title, Color("#ff927f"))
				await _show_enemy_card(event)
			"enemy_effect_started":
				if is_instance_valid(enemy_card):
					enemy_card.highlight_effect(event.index)
					if not target_beat_follows: await _pause(0.20)
			"enemy_effect_finished":
				await _hide_enemy_card()
				if event.has("stance_uid"):
					view.stance_panel.clear_lift()
					await _apply_board(event.board)
			"card_triggered":
				await _apply_board(event.board)
				var slot: int = view.circle_view.contents.find(event.uid)
				var already_centered: bool = is_instance_valid(player_card) and player_card.get_meta("uid") == event.uid
				if slot >= 0 and not already_centered:
					await _finish_player_card()
				var source_uid: int = event.get("source_uid", -1)
				var cause: String = event.get("source_event", "effect")
				if source_uid >= 0:
					_message("CHAIN / " + view.state.card(source_uid).name + " → " + view.state.card(event.uid).name + "\n" + cause.to_upper() + " / " + event.title, Color("#9ce6b7"))
					if view.circle_view.contents.has(source_uid) and view.circle_view.contents.has(event.uid):
						await view.circle_view.animate_chain(source_uid, event.uid, cause, _time(0.55))
					else:
						await _pause(0.28)
				else:
					_message("CARD TRIGGER / " + event.title, Color("#9ce6b7"))
					await _pause(0.28)
				if slot >= 0 and not already_centered:
					await _show_player_card(event.uid, slot, true, event.rule_id)
				elif already_centered:
					player_card.highlight_rule(event.rule_id)
			"card_rule_started":
				if is_instance_valid(player_card) and player_card.get_meta("uid") == event.uid:
					player_card.highlight_rule(event.rule_id)
					await _pause(0.18)
			"card_effect_started":
				if is_instance_valid(player_card) and player_card.get_meta("uid") == event.uid and player_card.resolving_rule_id == event.rule_id:
					player_card.highlight_effect(event.index)
					if not target_beat_follows: await _pause(0.20)
			"card_rule_finished":
				if is_instance_valid(player_card) and player_card.get_meta("uid") == event.uid:
					if event.return_to_circle:
						await _finish_player_card()
					else:
						player_card.highlight_rule("")
			"circle_expanded", "circle_reset":
				await _apply_board(event.board)
				_message(event.title, Color("#d6adee"))
				await _pause(0.35)
			"resource":
				await _apply_board(event.board)
				var unit := _unit(event.target)
				if unit != null: await _popup("%+d %s" % [event.amount, event.title], _visible_position(unit.global_position), Color("#d6adee"), 0.30)
			"cover":
				await _apply_board(event.board)
				var point: int = event.position
				var formation_view: Control = view.enemies if point >= 4 else view.allies
				var widget: Control = formation_view.widgets.get(point % 4)
				if widget != null: await _popup("%+d COVER" % event.amount, _visible_position(widget.global_position), Color("#8bd8ff"), 0.28)
			"mana", "persistence", "stunned", "confused", "ship_rule":
				await _apply_board(event.board)
				_message(event.get("title", event.kind.replace("_", " ").capitalize()), Color("#d6adee"))
				await _pause(0.22)
			"destroyed", "disabled":
				_message(("SHIP DISABLED / " if event.kind == "disabled" else "ENEMY DOWN / ") + event.title, Color("#ff927f"))
				await _pause(0.25)
				await _apply_board(event.board)
		view._show_piles(event.board)
	_set_effect_targets()
	if view.state.phase not in ["scry","discard"] or view.state.outcome != "":
		await _finish_player_card()
		await _hide_enemy_card()
		view.stance_panel.clear_lift()
	if view.state.outcome != "":
		view.stance_panel.end_activations()
		_message(view.state.outcome.to_upper(), Color("#e8bd77"))
		await _pause(0.40)
	banner.hide()
	running = false
	finished.emit()


func _show_player_card(uid: int, slot: int, already_staged: bool, rule_id: String = "") -> void:
	var token: Control = view.circle_view.buttons[slot]
	var source: Rect2 = token.get_global_rect()
	if not already_staged:
		source = _sources.get(uid, {}).get("rect", source)
		_hide_source(uid)
	var viewport_size := get_viewport().get_visible_rect().size
	var extent := Vector2(260, 352) * minf(1.0, viewport_size.y / 520.0)
	player_card = preload("res://scripts/card_face.gd").new()
	card_stage.add_child(player_card)
	var data: Dictionary = view.state.card(uid)
	player_card.configure(data, view.state.ships[data.owner])
	player_card.set_meta("uid", uid)
	player_card.size = extent
	player_card.enable_rule_highlights()
	player_card.highlight_rule(rule_id)
	player_card.position = source.position
	player_card.scale = source.size / extent
	_ignore_input(player_card)
	view.circle_view.show_card_in_presentation(uid)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(player_card, "position", (viewport_size - extent) / 2, _time(0.30))
	tween.tween_property(player_card, "scale", Vector2.ONE, _time(0.30))
	await tween.finished
	await _pause(0.20)


func _finish_player_card() -> void:
	if not is_instance_valid(player_card): return
	var slot: int = view.circle_view.contents.find(player_card.get_meta("uid"))
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if slot >= 0:
		var token: Control = view.circle_view.buttons[slot]
		tween.tween_property(player_card, "position", token.global_position, _time(0.24))
		tween.tween_property(player_card, "scale", token.size / player_card.size, _time(0.24))
	else:
		tween.tween_property(player_card, "position:x", get_viewport().get_visible_rect().end.x + 12.0, _time(0.24))
	await tween.finished
	player_card.free()
	player_card = null
	view.circle_view.show_card_in_presentation(-1)


func _apply_board(snapshot: Dictionary) -> void:
	view._show_board(snapshot)
	await _pause(0.02)


func _unit(id: int) -> Control:
	var formation: Control = view.enemies if id < 0 else view.allies
	for widget in formation.widgets.values() + formation.wreck_widgets.values():
		if widget.get_meta("ship_index", -999) == id:
			return widget
	return null


func _stat_change(event: Dictionary) -> void:
	if event.kind == "damage":
		if event.get("attack_style", "") == "": await _attack_effect(event)
		else:
			attack_started.emit(int(event.get("attacker", -999)), int(event.target))
			_flash_defences(event, _unit(int(event.target)))
	await _apply_board(event.board)
	var unit := _unit(event.target)
	if unit == null:
		return
	var tint := Color("#ff927f")
	var amount: int = event.amount
	var text := ""
	if event.kind == "damage":
		text = "-%d HULL" % amount if amount > 0 else "BLOCKED"
		if event.get("hit_total", 1) > 1: text = "%d/%d · " % [event.hit_index, event.hit_total] + text
		if event.get("blocked", 0) > 0:
			text += "\nC%d A%d S%d" % [event.get("cover_absorbed", 0), event.get("armour_absorbed", 0), event.get("shields_absorbed", 0)]
			if amount == 0: tint = Color("#8bd8ff")
		unit.bar.value += amount
	elif event.kind == "repair":
		tint = Color("#9ce6b7")
		text = "+%d HULL" % amount
		unit.bar.value -= amount
	else:
		tint = Color("#8bd8ff")
		text = "%+d SHIELDS" % amount
	var tween := create_tween().set_parallel(true)
	unit.self_modulate = tint
	tween.tween_property(unit, "self_modulate", Color.WHITE, _time(0.32))
	if event.kind == "damage" and amount > 0:
		# Modulate the artwork subtree: self_modulate on the unit frame does not tint its rig.
		var part: String = unit.get_meta("shared_rig_part", "")
		if part.is_empty():
			var resting_tint: Color = unit.art.modulate
			unit.art.modulate = Color("#ff5050")
			tween.tween_property(unit.art, "modulate", resting_tint, _time(0.32))
		else:
			view.enemies.flash_shared_part(part, _time(0.32))
	if event.kind != "guard":
		var final_value: int = event.board.enemies[-1 - event.target].hull if event.target < 0 else event.board.ships[event.target].hull
		tween.tween_property(unit.bar, "value", final_value, _time(0.28))
	await _popup(text, _visible_position(unit.global_position + Vector2(5, 0)), tint, 0.40)


func _move_ships(snapshot: Dictionary) -> void:
	var ghosts: Dictionary={}
	var starts: Dictionary={}
	for side in [view.allies,view.enemies]:
		for widget in side.widgets.values():
			if not widget.has_meta("ship_index"):continue
			var id: int=widget.get_meta("ship_index")
			starts[id]=widget.global_position
			# Recreate a clean visual instead of duplicating script-owned child trees.
			var ghost=preload("res://scripts/unit_view.gd").new()
			overlay.add_child(ghost)
			ghost.theme=view.theme
			ghost.size=widget.size
			var unit_data: Dictionary=side.snapshot.enemies[-1-id] if id<0 else side.snapshot.ships[id]
			ghost.configure(unit_data,id<0)
			ghost.position=widget.global_position
			_ignore_input(ghost)
			ghosts[id]=ghost
	# Hide destination sprites synchronously, before a rendered frame can show a teleport.
	view._show_board(snapshot)
	var paths: Dictionary={}
	var tween:=create_tween().set_parallel(true)
	for id in ghosts:
		var unit:=_unit(id)
		if unit==null or starts[id].distance_to(unit.global_position)<.1:
			ghosts[id].queue_free()
			continue
		unit.modulate.a=0
		var finish: Vector2=unit.global_position
		paths[id]={"from":starts[id],"to":finish}
		var ghost: Control=ghosts[id]
		var start: Vector2=starts[id]
		tween.tween_method(func(progress):
			if is_instance_valid(ghost):ghost.position=arc_position(start,finish,progress),0.0,1.0,_time(.42)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	movement_started.emit(paths.duplicate(true))
	if paths.is_empty():tween.kill();await _pause(.01)
	else:await tween.finished
	for ghost in ghosts.values():
		if is_instance_valid(ghost):ghost.queue_free()
	for side in [view.allies,view.enemies]:
		for widget in side.widgets.values():widget.modulate.a=1

static func arc_position(start: Vector2, finish: Vector2, progress: float) -> Vector2:
	var displacement:=finish-start
	var normal:=Vector2(-displacement.y,displacement.x).normalized()
	var bend:=clampf(displacement.length()*.18,18,38)
	return start.lerp(finish,progress)+normal*sin(progress*PI)*bend

func _attack_effect(event: Dictionary) -> void:
	var target := _unit(int(event.target))
	if target == null: return
	var attacker: int = int(event.get("attacker", -999))
	var style: String = event.get("presentation", "melee" if attacker < 0 else "ranged")
	attack_started.emit(attacker, int(event.target))
	if style == "melee": await _melee_effect(event)
	elif style in ["beam", "explosion"]:
		await _area_attack_effect(event.merged({"style":style, "targets":[int(event.target)]}, true))
		_flash_defences(event, target)
	else: await _projectile_effect(event)


func _projectile_effect(event: Dictionary) -> void:
	var target := _unit(int(event.target))
	if target == null: return
	var attacker: int = int(event.get("attacker", -999))
	var source := _unit(attacker)
	var effect = preload("res://scripts/visuals/attack_vfx.gd").new()
	effect.set_meta("attack_vfx", true)
	effect.z_index = 6
	effect.finish = _impact_point(target, event)
	effect.start = _attack_origin(source, event.get("origin_marker", "attack")) if source != null else effect.finish + Vector2(45 if attacker < 0 else -45, 0)
	effect.tint = Color("#ffac79") if attacker < 0 else Color("#8ceaff")
	overlay.add_child(effect)
	effect.impacted.connect(func(): _flash_defences(event, target))
	var tween := create_tween()
	tween.tween_property(effect, "progress", 1.0, _time(.30))
	await tween.finished
	effect.queue_free()


static func swoop_position(start: Vector2, finish: Vector2, progress: float) -> Vector2:
	var displacement := finish - start
	var normal := Vector2(-displacement.y, displacement.x).normalized()
	return start.lerp(finish, progress) + normal * sin(progress * PI) * clampf(displacement.length() * .12, 20, 85)


func _melee_effect(event: Dictionary) -> void:
	var attacker: int = int(event.get("attacker", -999))
	var source := _unit(attacker)
	var target := _unit(int(event.target))
	if source == null or target == null:
		await _projectile_effect(event)
		return
	# Only the artwork leaves its slot; formation, shields and labels stay put.
	var ghost = preload("res://scripts/rig_view.gd").new()
	ghost.set_meta("melee_actor", attacker)
	ghost.z_index = 6
	overlay.add_child(ghost)
	ghost.size = source.art.size
	ghost.enemy_facing = attacker < 0
	ghost.configure_definition(source.art.definition)
	ghost.position = source.art.global_position
	ghost.pivot_offset = ghost.size / 2
	ghost.set_process(false)
	if ghost.rig_node != null and source.art.rig_node != null: ghost.rig_node.elapsed = source.art.rig_node.elapsed
	var marker: String = event.get("origin_marker", "attack")
	var start: Vector2 = ghost.position
	var origin_offset: Vector2 = ghost.marker_global(marker) - start
	var contact := _impact_point(target, event)
	var finish: Vector2 = contact - origin_offset
	var saved_tint: Color = source.art.modulate
	ghost.modulate = saved_tint
	source.art.modulate.a = 0
	melee_started.emit(attacker, int(event.target), {"from":start, "to":finish, "origin":start+origin_offset, "impact":contact})
	var tween := create_tween()
	tween.tween_method(func(progress):
		ghost.position = swoop_position(start, finish, progress)
		ghost.rotation = sin(progress * PI) * deg_to_rad(8) * signf(finish.x-start.x), 0.0, 1.0, _time(.34)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	ghost.position = finish
	ghost.rotation = 0
	_flash_defences(event, target)
	if int(event.get("amount", 0)) > 0:
		target.art.modulate = Color("#ff5050")
		create_tween().tween_property(target.art, "modulate", Color.WHITE, _time(.20))
	var impact = preload("res://scripts/visuals/attack_vfx.gd").new()
	impact.z_index = 6
	impact.start = contact; impact.finish = contact; impact.progress = .65
	impact.tint = Color("#ffac79")
	overlay.add_child(impact)
	melee_impacted.emit(attacker, int(event.target))
	var strike := create_tween()
	strike.tween_property(impact, "progress", 1.0, _time(.12))
	await strike.finished
	impact.queue_free()
	var retreat := create_tween()
	retreat.tween_method(func(progress):
		ghost.position = swoop_position(finish, start, progress)
		ghost.rotation = -sin(progress * PI) * deg_to_rad(6) * signf(finish.x-start.x), 0.0, 1.0, _time(.28)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await retreat.finished
	ghost.position = start; ghost.rotation = 0
	if is_instance_valid(source): source.art.modulate = saved_tint
	ghost.free()
	melee_finished.emit(attacker, int(event.target))


func _attack_origin(unit: Control, marker: String = "attack") -> Vector2:
	if unit != null and not str(unit.get_meta("shared_rig_part", "")).is_empty():
		return view.enemies.shared_part_point(unit.get_meta("shared_rig_part"))
	if unit != null and "art" in unit and unit.art.has_method("marker_global"): return unit.art.marker_global(marker)
	return _art_centre(unit) if unit != null else Vector2.ZERO


func _flash_defences(event: Dictionary, target: Control) -> void:
	if not is_instance_valid(target): return
	if int(event.get("shields_absorbed", 0)) > 0: target.shield_fx.flash()
	if int(event.get("cover_absorbed", 0)) > 0:
		var side: Control = view.enemies if int(event.target) < 0 else view.allies
		var formation: Array = event.board.enemy_formation if int(event.target) < 0 else event.board.formation
		var point: int = formation.find(-1 - int(event.target) if int(event.target) < 0 else int(event.target))
		if side.cover_clouds.has(point): side.cover_clouds[point].flash()


func _area_attack_effect(event: Dictionary) -> void:
	var presentation: String = event.get("presentation", event.style)
	area_attack_started.emit(event.style, event.targets.duplicate())
	if presentation in ["melee", "ranged"]:
		for id in event.targets:
			var single: Dictionary = event.merged({"target":id}, true)
			if presentation == "melee": await _melee_effect(single)
			else: await _projectile_effect(single)
		return
	var effect = preload("res://scripts/visuals/area_attack_vfx.gd").new()
	effect.style = presentation
	effect.set_meta("area_vfx", presentation)
	effect.z_index = 6
	var source := _unit(int(event.attacker))
	var target := _unit(int(event.target))
	if target == null: effect.free(); return
	effect.centre = _art_centre(target)
	effect.start = _attack_origin(source, event.get("origin_marker", "attack")) if source != null else effect.centre + Vector2(-80, 0)
	for id in event.targets:
		var victim := _unit(int(id))
		if victim != null: effect.impacts.append(_art_centre(victim))
	effect.tint = Color("#ffac79") if presentation == "explosion" else Color("#8ceaff")
	overlay.add_child(effect)
	var tween := create_tween()
	tween.tween_property(effect, "progress", 1.0, _time(.55 if presentation == "explosion" else .45))
	await tween.finished
	effect.queue_free()


func _art_centre(unit: Control) -> Vector2:
	if not str(unit.get_meta("shared_rig_part", "")).is_empty():
		return view.enemies.shared_part_point(unit.get_meta("shared_rig_part"))
	return unit.art.marker_global("impact") if "art" in unit and unit.art.has_method("marker_global") else unit.get_global_rect().get_center()


func _set_effect_targets(targets: Dictionary = {}) -> void:
	effect_targets.clear()
	for key in ["units", "slots", "circle_slots", "stances"]:
		if not targets.get(key, []).is_empty(): effect_targets[key] = targets[key]
	focus_overlay.queue_redraw()


func _process(_delta: float) -> void:
	if not effect_targets.is_empty(): focus_overlay.queue_redraw()


func _draw_effect_targets() -> void:
	for id in effect_targets.get("units", []):
		_draw_focus_frame(_unit(id), Color("#ffd18a"))
	for point in effect_targets.get("slots", []):
		var formation_view: Control = view.enemies if point >= 4 else view.allies
		_draw_focus_frame(formation_view.widgets.get(point % 4), Color("#a4e6ff"))
	for slot in effect_targets.get("circle_slots", []):
		_draw_focus_frame(view.circle_view.buttons[slot], Color("#a4e6ff"))
	for uid in effect_targets.get("stances", []):
		_draw_focus_frame(view.stance_panel.card_button(uid), Color("#ffd18a"))


func _draw_focus_frame(widget: Control, tint: Color) -> void:
	if not is_instance_valid(widget): return
	var bounds := widget.get_global_rect().grow(3)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(tint, 0.07)
	frame.border_color = tint
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(9)
	frame.shadow_color = Color(tint, 0.38)
	frame.shadow_size = 7
	focus_overlay.draw_style_box(frame, bounds)


func _ready() -> void:
	layer = 20
	focus_overlay = Control.new()
	focus_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(focus_overlay)
	focus_overlay.draw.connect(_draw_effect_targets)
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


func _visible_position(point: Vector2, extent: Vector2 = Vector2(160, 100)) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	return Vector2(clampf(point.x, 12, maxf(12, viewport_size.x - extent.x - 12)),
		clampf(point.y, 90, maxf(90, viewport_size.y - extent.y - 12)))


func _source_position(uid: int) -> Vector2:
	if _sources.has(uid):
		return _visible_position(_sources[uid].rect.position, _sources[uid].rect.size)
	return _visible_position(get_viewport().get_visible_rect().size * Vector2(0.45, 0.45))


func _ghost(uid: int) -> Control:
	var ghost := PanelContainer.new()
	var label := Label.new()
	ghost.custom_minimum_size = Vector2(164, 78)
	label.custom_minimum_size = Vector2(140, 36)
	label.text = view.state.card(uid).name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost.add_child(label)
	ghost.size = Vector2(164, 78)
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
	if _sources.has(uid) and is_instance_valid(_sources[uid].get("node")):
		_sources[uid].node.modulate.a = 0.0


func _discard_cards(uids: Array) -> void:
	if uids.is_empty():
		return
	var pile := view.get_node("%DiscardPile") as Control
	var destination := _visible_position(pile.get_global_rect().get_center(), Vector2(45, 35))
	var tween := create_tween().set_parallel(true)
	var ghosts: Array = []
	for index in uids.size():
		var uid: int = uids[index]
		var ghost := _ghost(uid)
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
	var pile := view.get_node("%DiscardPile") as Control
	var start := _visible_position(view.get_node("%DeckPile").get_global_rect().get_center())
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


func stage_payment(uid: int, battle_view: Control) -> void:
	if running:
		return
	running = true
	view = battle_view
	_sources.clear()
	var face: Control = view.hand_view.get_node("Card%d" % uid)
	_sources[uid] = {"node": face, "rect": face.get_global_rect()}
	view.pending_visual_sources[uid] = {"rect": face.get_global_rect()}
	_message("PAYMENT / " + view.state.card(uid).name, Color("#e8bd77"))
	await _discard_cards([uid])
	banner.hide()
	running = false

func _impact_point(target: Control, event: Dictionary) -> Vector2:
	var enemy: bool=int(event.target)<0
	var side: Control=view.enemies if enemy else view.allies
	var points: Array=event.board.enemy_formation if enemy else event.board.formation
	var point: int=points.find(-1-int(event.target) if enemy else int(event.target))
	if int(event.get("cover_absorbed",0))>0 and side.cover_clouds.has(point):
		var cloud: Control=side.cover_clouds[point]
		return cloud.global_position+cloud.size*Vector2(.22 if enemy else .78,.53)
	if int(event.get("shields_absorbed",0))>0 and "shield_fx" in target:
		return target.shield_fx.global_position+target.shield_fx.size*Vector2(.05 if enemy else .95,.53)
	return _art_centre(target)


func _show_enemy_card(event: Dictionary) -> void:
	await _hide_enemy_card()
	var data: Dictionary = event.get("presentation",{}).duplicate(true)
	if data.is_empty(): return
	var viewport_size := get_viewport().get_visible_rect().size
	var extent := Vector2(minf(370,viewport_size.x-40),minf(440,viewport_size.y-130))
	var enemy_source_rect := Rect2(viewport_size/2,Vector2(80,80))
	var token: int = event.get("stance_uid",-1)
	if token >= 0:
		var button: Control = view.stance_panel.card_button(token)
		if button != null: enemy_source_rect = button.get_global_rect()
	else:
		var source := _unit(data.get("owner",-1))
		if source != null: enemy_source_rect=source.get_global_rect()
	enemy_card = preload("res://scripts/enemy_effect_card.gd").new()
	if token >= 0:
		enemy_card.set_meta("lifted_uid", token)
	enemy_card.theme = view.theme
	card_stage.add_child(enemy_card)
	enemy_card.configure(event.kind,data)
	enemy_card.size = extent
	enemy_card.position = enemy_source_rect.position
	enemy_card.scale = enemy_source_rect.size/extent
	enemy_card.modulate.a = 1.0 if token >= 0 else 0.25
	if token >= 0: view.stance_panel.lift_card(token)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(enemy_card,"position",(viewport_size-extent)/2,_time(0.30)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(enemy_card,"scale",Vector2.ONE,_time(0.30)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(enemy_card,"modulate:a",1.0,_time(0.20))
	await tween.finished
	enemy_presentation_started.emit(event.kind,data.duplicate(true))
	await _pause(0.65)


func _hide_enemy_card() -> void:
	if not is_instance_valid(enemy_card): return
	var right_edge := get_viewport().get_visible_rect().end.x
	var tween := create_tween()
	tween.tween_property(enemy_card, "position:x", right_edge + 12.0, _time(0.24)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished
	enemy_card.free()
	enemy_card = null
	enemy_presentation_finished.emit()
