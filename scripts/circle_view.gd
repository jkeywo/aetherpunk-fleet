extends Control
signal slot_selected(slot: int)
signal slot_hovered(slot: int)
signal slot_exited(slot: int)
signal drag_slot_hovered(slot: int, data: Variant)
signal drag_slot_exited(slot: int)
signal card_dropped(slot: int, data: Variant)
signal link_pulse_started(source_uid: int, receiver_uid: int, event_kind: String)
const Geometry = preload("res://scripts/battle_geometry.gd")
const BONUS_COLOR := Color("#9ce6b7")
var buttons: Array = []
var circle_art: TextureRect
var expanded := false
var selected := -1
var contents: Array = []
var card_data: Dictionary = {}
var bonus_slots: Array = []
var contribution_details: Dictionary = {}
var pulse_source := -1
var pulse_receiver := -1
var pulse_event := ""
var pulse_progress := 0.0
var link_overlay: Control
var drop_check: Callable
var drag_active := false
var valid_drop_slots: Array = []
var drop_errors: Dictionary = {}
var trigger_bases: Dictionary={}


func _ready() -> void:
	circle_art = TextureRect.new()
	circle_art.name = "MagicCircleArt"
	circle_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	circle_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	circle_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	circle_art.offset_left = -28
	circle_art.offset_top = -28
	circle_art.offset_right = 28
	circle_art.offset_bottom = 28
	add_child(circle_art)
	resized.connect(_arrange)


func configure(circle: Array, is_expanded: bool, cards: Dictionary, used: Dictionary = {}, selected_slot: int = -1, contributors: Array = [], details: Dictionary = {}, persistence: Dictionary = {}) -> void:
	trigger_bases.clear()
	expanded = is_expanded
	circle_art.texture = preload("res://scripts/art_assets.gd").texture("circle/stage-%d.png" % (2 if expanded else 1))
	selected = selected_slot
	contents = circle.duplicate()
	card_data = cards
	contribution_details = details.duplicate(true)
	bonus_slots.clear()
	if buttons.is_empty():
		for slot in 9:
			var button := Button.new()
			button.add_theme_font_size_override("font_size", 11)
			button.clip_text = true
			button.pressed.connect(func(): slot_selected.emit(slot))
			button.set_drag_forwarding(Callable(), _can_drop_at.bind(slot), _drop_at.bind(slot))
			button.mouse_exited.connect(func(): drag_slot_exited.emit(slot);slot_exited.emit(slot))
			button.mouse_entered.connect(func():slot_hovered.emit(slot))
			add_child(button)
			buttons.append(button)
		link_overlay = Control.new()
		link_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		link_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(link_overlay)
		link_overlay.draw.connect(_draw_pulse)
	for slot in 9:
		var uid: int = circle[slot]
		var locked: bool = slot >= 4 and not expanded
		var button: Button = buttons[slot]
		var provides: bool = uid >= 0 and contributors.has(uid) and selected >= 0 and Geometry.neighbours(selected, expanded).has(slot)
		button.disabled = locked
		button.visible = not locked
		button.text = "Locked" if locked else Geometry.SLOT_NAMES[slot] + "\n+"
		button.modulate = Color("#3b4859") if locked else Color.WHITE
		button.tooltip_text = Geometry.SLOT_NAMES[slot]
		for style_name in ["normal", "hover", "pressed", "hover_pressed"]:
			button.remove_theme_stylebox_override(style_name)
		for style_name in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var base := StyleBoxFlat.new()
			var framed: bool=uid>=0 or (not locked and (selected>=0 or drag_active))
			base.bg_color = Color(.025,.065,.10,.88 if uid >= 0 else .28) if framed else Color.TRANSPARENT
			base.border_color = Color(.45,.75,.82,.45)
			base.set_border_width_all(1 if framed else 0)
			base.set_corner_radius_all(5)
			button.add_theme_stylebox_override(style_name,base)
		if uid >= 0 and cards.has(uid):
			var card: Dictionary = cards[uid]
			var count := 0
			for key in used:
				if str(key).begins_with(str(uid) + "/"):
					count += 1
			var caption: String = card.get("pending_status", "BONUS" if provides else "In play")
			if count > 0:
				caption = ("BONUS · " if provides else "") + "◆ %d used" % count
			if persistence.has(uid): caption += " · Persistence " + str(persistence[uid])
			button.text = card.name + "\n" + caption
			button.tooltip_text = card.name + "\n" + card.get("effect", "")
			if persistence.has(uid): button.tooltip_text += "\nPersistence %d: remove one at cleanup and keep this card for the next round." % persistence[uid]
			if card.has("pending_status"):
				button.tooltip_text += "\n" + card.pending_status + ". Click hand cards to discard as payment. The card resolves when paid and targeted; Cancel Play returns pending cards."
			button.modulate = Color("#b7d2e6")
		if drag_active and uid < 0 and not locked:
			button.text = Geometry.SLOT_NAMES[slot] + ("\nDROP HERE" if valid_drop_slots.has(slot) else "\nUnavailable")
			button.tooltip_text = "Drop here, click other cards to discard as payment, then click targets. Resolves automatically when ready; Cancel Play refunds pending cards." if valid_drop_slots.has(slot) else str(drop_errors.get(slot, "Unavailable."))
			_highlight(button, Color("#67bdd4") if valid_drop_slots.has(slot) else Color("#8a535b"), Color("#102b36") if valid_drop_slots.has(slot) else Color("#291c25"))
		if slot == selected:
			button.modulate = Color.WHITE
			_highlight(button, Color("#e8bd77"), Color("#302b20"))
		elif provides:
			bonus_slots.append(slot)
			button.modulate = Color.WHITE
			_highlight(button, BONUS_COLOR, Color("#18372e"))
			var reasons: Array = details.get(uid, [])
			button.tooltip_text += "\n\nProviding to " + Geometry.SLOT_NAMES[selected] + ":\n" + "\n".join(reasons)
		elif selected >= 0 and Geometry.neighbours(selected, expanded).has(slot) and uid >= 0:
			button.modulate = Color("#d6adee")
	_arrange()


func _highlight(button: Button, tint: Color, fill: Color) -> void:
	for style_name in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill.lightened(0.10) if style_name in ["hover", "hover_pressed"] else fill
		style.border_color = tint
		style.set_border_width_all(3)
		style.set_corner_radius_all(5)
		button.add_theme_stylebox_override(style_name, style)


func _arrange() -> void:
	var cell := Vector2(size.x / 3.0, size.y / 3.0)
	for slot in buttons.size():
		buttons[slot].position = Geometry.CIRCLE_POINTS[slot] * cell + Vector2(4, 4)
		buttons[slot].size = cell - Vector2(8, 8)
	queue_redraw()
	if is_instance_valid(link_overlay):
		link_overlay.queue_redraw()


func _draw() -> void:
	var cell := Vector2(size.x / 3.0, size.y / 3.0)
	var links: Array = Geometry.BASE_LINKS.duplicate()
	if expanded:
		links.append_array(Geometry.EXTRA_LINKS)
	for link in links:
		var tint := Color("#694c80")
		var width := 2.0
		if selected >= 0 and link.has(selected):
			var other: int = link[1] if link[0] == selected else link[0]
			tint = BONUS_COLOR if bonus_slots.has(other) else Color("#9b819e")
			width = 5.0 if bonus_slots.has(other) else 2.0
		draw_line((Geometry.CIRCLE_POINTS[link[0]] + Vector2.ONE / 2) * cell, (Geometry.CIRCLE_POINTS[link[1]] + Vector2.ONE / 2) * cell, tint, width, true)


func animate_chain(source_uid: int, receiver_uid: int, event_kind: String, duration: float) -> void:
	var source: int = contents.find(source_uid)
	var receiver: int = contents.find(receiver_uid)
	if source < 0 or receiver < 0 or not Geometry.neighbours(source, expanded).has(receiver):
		return
	pulse_source = source
	pulse_receiver = receiver
	pulse_event = event_kind
	set_pulse_progress(0.0)
	link_pulse_started.emit(source_uid, receiver_uid, event_kind)
	var tween := create_tween()
	tween.tween_method(set_pulse_progress, 0.0, 1.0, maxf(0.001, duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	pulse_source = -1
	pulse_receiver = -1
	pulse_event = ""
	link_overlay.queue_redraw()


func set_pulse_progress(value: float) -> void:
	pulse_progress = value
	if is_instance_valid(link_overlay):
		link_overlay.queue_redraw()


func _edge_point(button: Control, direction: Vector2) -> Vector2:
	var half := button.size / 2
	var factor := minf(half.x / maxf(0.001, absf(direction.x)), half.y / maxf(0.001, absf(direction.y)))
	return button.position + half + direction * (factor + 2.0)


func _draw_pulse() -> void:
	if pulse_source < 0 or pulse_receiver < 0:
		return
	var source: Control = buttons[pulse_source]
	var receiver: Control = buttons[pulse_receiver]
	var direction := (receiver.get_rect().get_center() - source.get_rect().get_center()).normalized()
	var start := _edge_point(source, direction)
	var finish := _edge_point(receiver, -direction)
	var tint: Color = {"damage": Color("#ffb17d"), "hull_damaged": Color("#ffb17d"), "guard": Color("#8bd8ff"), "shields_added": Color("#8bd8ff"), "repair": BONUS_COLOR, "repaired": BONUS_COLOR}.get(pulse_event, Color("#d6adee"))
	var glow := tint
	glow.a = 0.25 + sin(pulse_progress * PI) * 0.45
	link_overlay.draw_rect(source.get_rect().grow(-2), glow, false, 4, true)
	link_overlay.draw_rect(receiver.get_rect().grow(-2), tint, false, 4, true)
	link_overlay.draw_line(start, finish, Color(tint, 0.30), 12, true)
	link_overlay.draw_line(start, finish, tint, 4, true)
	var spark := start.lerp(finish, pulse_progress)
	link_overlay.draw_circle(spark, 8, Color(tint, 0.35), true, -1, true)
	link_overlay.draw_circle(spark, 4, Color.WHITE, true, -1, true)
	var head := finish - direction * 7
	var perpendicular := Vector2(-direction.y, direction.x) * 5
	link_overlay.draw_colored_polygon(PackedVector2Array([finish, head + perpendicular, head - perpendicular]), tint)


func _can_drop_at(_at_position: Vector2, data: Variant, slot: int) -> bool:
	if not drop_check.is_valid():
		return false
	drag_slot_hovered.emit(slot, data)
	return bool(drop_check.call(data, slot))


func _drop_at(_at_position: Vector2, data: Variant, slot: int) -> void:
	if drop_check.is_valid() and drop_check.call(data, slot):
		card_dropped.emit(slot, data)


func _process(_delta: float) -> void:
	if circle_art != null and is_visible_in_tree():
		circle_art.modulate.a = .48 + .045*sin(Time.get_ticks_msec()/1000.0*TAU/8)

func show_trigger_preview(triggers: Dictionary = {}) -> void:
	for point in contents.size():
		var uid: int=contents[point]
		var button: Button=buttons[point]
		if not trigger_bases.has(point):
			var styles: Dictionary={}
			for state in ["normal","hover","pressed","hover_pressed"]:styles[state]=button.get_theme_stylebox(state)
			trigger_bases[point]={"text":button.text,"tooltip":button.tooltip_text,"styles":styles}
		button.text=trigger_bases[point].text
		button.tooltip_text=trigger_bases[point].tooltip
		for state in trigger_bases[point].styles:button.add_theme_stylebox_override(state,trigger_bases[point].styles[state])
		if not triggers.has(uid):continue
		button.text+="\nTRIGGER"
		button.tooltip_text+="\nWould trigger:\n"+"\n".join(triggers[uid])
		for state in ["normal","hover","pressed","hover_pressed"]:
			var style: StyleBoxFlat=button.get_theme_stylebox(state).duplicate()
			style.border_color=Color("#97f1cf")
			style.set_border_width_all(3)
			button.add_theme_stylebox_override(state,style)
