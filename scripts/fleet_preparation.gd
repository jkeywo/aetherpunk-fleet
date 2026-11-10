extends Control
const Catalog = preload("res://scripts/content_catalog.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const State = preload("res://scripts/battle_state.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const CardFace = preload("res://scripts/card_face.gd")
const Formation = preload("res://scripts/formation_view.gd")
const Ui = preload("res://scripts/ui_theme.gd")
var source: Dictionary = {}
var draft: Dictionary = {}
var fingerprint := ""
var prefer_fixed := true
var fixed_available := false
var selected_ship := 0
var drag_payload: Dictionary = {}
var controls: Dictionary = {}
var details: Array = []
var inspector: VBoxContainer
var ship_bank: HFlowContainer
var captain_bank: HFlowContainer
var status: Label
var opening: CheckBox
var opening_note: Label
var launch_button: Button
var formation: Control
var encounter: Label
var fleet_scroll: ScrollContainer
var deck_preview: VBoxContainer
var deck_cards: HBoxContainer
var deck_summary: Label
var content_scroll: ScrollContainer

func _ready() -> void:
	get_tree().auto_accept_quit = true
	BattleSession.editor_playtest = false
	source = ContentStore.snapshot()
	fingerprint = JSON.stringify(Catalog.normalized(source)).sha256_text()
	draft = source.duplicate(true)
	prefer_fixed = source.get("setup",{}).get("fixed_hand",false)
	var remembered: Dictionary = BattleSession.preparation_draft
	if remembered.get("fingerprint","") == fingerprint and draft.has("setup"):
		draft.setup.fleet = remembered.fleet.duplicate(true)
		prefer_fixed = remembered.prefer_fixed
		selected_ship = clampi(remembered.get("selected_ship",0),0,2)
	theme = Ui.make()
	_build()
	_render()

func _label(parent: Node, text: String, font: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _clear(node: Node) -> void:
	for child in node.get_children(): node.remove_child(child); child.queue_free()

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("#07121b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,18)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation",10)
	margin.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	_label(header,"FLEET PREPARATION",26).modulate = Color("#e8bd77")
	_button(header,"Reset to Saved Fleet",_reset)
	_button(header,"Main Menu",_back)
	_label(outer,"Select a ship for its options. Drag ships between positions; drag captains onto ships to assign or swap them.",14).modulate = Color("#91b9c6")
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 675
	outer.add_child(split)
	var left_scroll := ScrollContainer.new()
	fleet_scroll = left_scroll
	left_scroll.custom_minimum_size.x = 570
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation",8)
	left_scroll.add_child(left)
	formation = Formation.new()
	formation.large_cards = true
	formation.custom_minimum_size = Vector2(550,370)
	left.add_child(formation)
	formation.position_selected.connect(_select_position)
	_label(left,"SHIPS / drag to move or replace",12).modulate = Color("#e8bd77")
	ship_bank = HFlowContainer.new()
	left.add_child(ship_bank)
	_label(left,"CAPTAINS / drag onto a ship",12).modulate = Color("#e8bd77")
	captain_bank = HFlowContainer.new()
	left.add_child(captain_bank)
	deck_preview = VBoxContainer.new()
	deck_preview.add_theme_constant_override("separation", 8)
	left.add_child(deck_preview)
	deck_summary = _label(deck_preview, "", 17)
	deck_summary.set_meta("plain_text", true)
	deck_summary.modulate = Color("#e8bd77")
	_label(deck_preview, "One preview per design; copy counts show how many enter the deck. Scroll sideways for more cards.", 12)
	var card_scroll := ScrollContainer.new()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck_preview.add_child(card_scroll)
	deck_cards = HBoxContainer.new()
	deck_cards.add_theme_constant_override("separation", 12)
	card_scroll.add_child(deck_cards)
	encounter = _label(left,"",13)
	opening = CheckBox.new()
	opening.text = "Use saved opening when compatible"
	left.add_child(opening)
	opening.toggled.connect(func(value): prefer_fixed=value; _update())
	opening_note = _label(left,"",12)
	content_scroll = ScrollContainer.new()
	content_scroll.custom_minimum_size.x = 380
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(content_scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation",7)
	content_scroll.add_child(inspector)
	var footer := HBoxContainer.new()
	outer.add_child(footer)
	status = _label(footer,"",14)
	status.custom_minimum_size.y = 46
	launch_button = _button(footer,"Launch Battle",_launch)
	launch_button.custom_minimum_size = Vector2(200,46)

func _menu(parent: Node, caption: String, options: Array, current: Variant, callback: Callable, key: String, enabled: bool = true) -> OptionButton:
	_label(parent,caption,12).modulate = Color("#91b9c6")
	var menu := OptionButton.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.fit_to_longest_item = false
	parent.add_child(menu)
	for item in options:
		menu.add_item(item.label)
		menu.set_item_metadata(menu.item_count-1,item.value)
		menu.get_popup().set_item_tooltip(menu.item_count-1,item.get("tooltip",""))
		if typeof(item.value)==typeof(current) and item.value==current: menu.select(menu.item_count-1)
	menu.disabled = not enabled
	menu.item_selected.connect(func(index): callback.call(menu.get_item_metadata(index)))
	controls[key] = menu
	return menu

func _render() -> void:
	_clear(inspector)
	_clear(ship_bank)
	_clear(captain_bank)
	controls.clear()
	details.clear()
	if not draft.get("setup",{}).get("fleet") is Array:
		status.text = "Saved fleet unavailable. " + ContentStore.last_error
		launch_button.disabled=true
		return
	var slot: Dictionary = draft.setup.fleet[selected_ship]
	var ship: Dictionary = draft.ships[Catalog.index_by_id(draft.ships,slot.ship)]
	_label(inspector,ship.name,24).set_meta("plain_text",true)
	_button(inspector, "View selected ship’s deck", _show_deck)
	var options: Array = []
	for entry in draft.ships: options.append({"label":entry.name,"value":entry.id})
	_menu(inspector,"Airship",options,slot.ship,_change.bind(selected_ship,"ship"),"ship_"+str(selected_ship))
	options=[]
	for entry in draft.captains: options.append({"label":entry.name+" · Tier "+str(entry.tier),"value":entry.id,"tooltip":Rules.rule_text(entry.passive, ship.name)})
	_menu(inspector,"Captain",options,slot.captain,_change.bind(selected_ship,"captain"),"captain_"+str(selected_ship))
	options=[]
	for point in 4: options.append({"label":Geometry.POSITION_NAMES[point],"value":Geometry.POSITIONS[point]})
	_menu(inspector,"Starting position",options,slot.position,_change.bind(selected_ship,"position"),"position_"+str(selected_ship))
	_menu(inspector,"Level",[{"label":"1 · Starter + captain pairs","value":1},{"label":"2 · Add one upgrade pair","value":2},{"label":"3 · Add both upgrade pairs","value":3}],slot.level,_change.bind(selected_ship,"level"),"level_"+str(selected_ship))
	options=[]
	for package in ship.levels.two: options.append({"label":package.name,"value":package.id,"tooltip":_package_text(package)})
	_menu(inspector,"Level 2 branch",options,slot.level_2,_change.bind(selected_ship,"level_2"),"level_2_"+str(selected_ship),slot.level>=2)
	var blocked := ""
	var branch := Catalog.index_by_id(ship.levels.two,slot.level_2)
	if branch>=0: blocked=ship.levels.two[branch].blocks
	options=[]
	var blocked_name := ""
	for package in ship.levels.three:
		if package.id==blocked: blocked_name=package.name
		else: options.append({"label":package.name,"value":package.id,"tooltip":_package_text(package)})
	_menu(inspector,"Level 3 branch",options,slot.level_3,_change.bind(selected_ship,"level_3"),"level_3_"+str(selected_ship),slot.level>=3)
	_label(inspector,"Blocked by level 2: "+blocked_name if blocked_name!="" else "Select level 2 to determine the available paths.",12).modulate=Color("#e8bd77")
	details.append(_label(inspector,"",14))
	var rewards := _label(inspector,"",12)
	rewards.modulate=Color("#91c8ad")
	details.append(rewards)
	for entry in draft.ships:
		var button := _button(ship_bank,entry.name,_select_roster.bind(entry.id))
		button.set_meta("plain_text",true)
		button.tooltip_text="Drag to move this ship, or replace a ship in the fleet."
		button.set_drag_forwarding(_drag_from.bind({"kind":"ship","ship":entry.id},button),Callable(),Callable())
	for entry in draft.captains:
		var button := _button(captain_bank,entry.name+" · "+str(entry.tier),func(): pass)
		button.tooltip_text=Rules.rule_text(entry.passive, ship.name)
		button.set_meta("plain_text",true)
		button.set_drag_forwarding(_drag_from.bind({"kind":"captain","captain":entry.id},button),Callable(),Callable())
	opening.set_pressed_no_signal(prefer_fixed)
	opening.disabled=not source.setup.fixed_hand
	_update()

func _select_position(point: int) -> void:
	for i in draft.setup.fleet.size():
		if draft.setup.fleet[i].position==Geometry.POSITIONS[point]: selected_ship=i; _render(); return

func _select_roster(id: String) -> void:
	for i in draft.setup.fleet.size():
		if draft.setup.fleet[i].ship==id: selected_ship=i; _render(); return
	_change(id,selected_ship,"ship")

func _change(value: Variant, index: int, key: String) -> void:
	selected_ship=index
	var slot: Dictionary = draft.setup.fleet[index]
	if key in ["ship","captain","position"]:
		for i in draft.setup.fleet.size():
			if i!=index and draft.setup.fleet[i][key]==value:
				draft.setup.fleet[i][key]=slot[key]
				if key=="ship": _repair_branch(draft.setup.fleet[i])
	slot[key]=value
	_repair_branch(slot)
	_render()
	if controls.has(key+"_"+str(index)): controls[key+"_"+str(index)].grab_focus()

func _package_text(package: Dictionary) -> String:
	var ship: Dictionary = draft.ships[Catalog.index_by_id(draft.ships, draft.setup.fleet[selected_ship].ship)]
	return "2 × "+draft.cards[Catalog.index_by_id(draft.cards,package.card)].name+"\n"+Rules.rule_text(package.rule, ship.name)+"\n"+Rules.rule_text(package.passive, ship.name)

func _repair_branch(slot: Dictionary) -> void:
	Catalog.repair_fleet_branch(slot,draft.ships[Catalog.index_by_id(draft.ships,slot.ship)])

func _wire_formation(board: Dictionary) -> void:
	for point in 4:
		var widget: Button = formation.widgets[point]
		var id: int = board.formation[point]
		widget.set_drag_forwarding(_drag_from.bind({"kind":"ship","ship":draft.setup.fleet[id].ship},widget) if id>=0 else Callable(),_can_drop_at.bind(point),_drop_at.bind(point))
		if id<0: continue
		var captain: Dictionary = draft.captains[Catalog.index_by_id(draft.captains,draft.setup.fleet[id].captain)]
		var badge := Button.new()
		badge.set_meta("plain_text",true)
		badge.text=captain.name+" · Tier "+str(captain.tier)
		badge.add_theme_font_size_override("font_size",12)
		badge.position=Vector2(7,84)
		badge.size=Vector2(widget.size.x-14,30)
		badge.tooltip_text="Drag to assign/swap this captain.\n"+Rules.rule_text(captain.passive, board.ships[id].name)
		widget.add_child(badge)
		badge.pressed.connect(func(): selected_ship=id; _render())
		badge.set_drag_forwarding(_drag_from.bind({"kind":"captain","captain":captain.id},badge),_can_drop_at.bind(point),_drop_at.bind(point))
		widget.set_meta("captain_badge",badge)

func _drag_from(_point: Vector2, payload: Dictionary, origin: Control) -> Dictionary:
	drag_payload=payload.duplicate(true)
	drag_payload["preparation"]=get_instance_id()
	var preview := PanelContainer.new()
	preview.custom_minimum_size=Vector2(190,42)
	preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text=origin.text if origin.text!="" else draft.ships[Catalog.index_by_id(draft.ships,payload.ship)].name
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	preview.add_child(label)
	origin.set_drag_preview(preview)
	_show_drag_targets(drag_payload)
	return drag_payload.duplicate(true)

func _valid_drop(data: Variant, point: int) -> bool:
	if not data is Dictionary or data.get("preparation",-1)!=get_instance_id() or point not in range(4): return false
	var occupied := false
	for slot in draft.setup.fleet:
		if slot.position==Geometry.POSITIONS[point]: occupied=true
	if data.get("kind")=="captain": return occupied and Catalog.index_by_id(draft.captains,data.get("captain",""))>=0
	if data.get("kind")!="ship" or Catalog.index_by_id(draft.ships,data.get("ship",""))<0: return false
	return occupied or draft.setup.fleet.any(func(slot): return slot.ship==data.ship)

func _show_drag_targets(data: Dictionary) -> void:
	var notes: Dictionary={}
	for point in 4:
		if not _valid_drop(data,point): continue
		var id: int=formation.snapshot.formation[point]
		notes[id if id>=0 else 100+point]="Assign captain" if data.kind=="captain" else "Move / swap ship"
	formation.show_rule_preview(notes)

func _can_drop_at(_local: Vector2, data: Variant, point: int) -> bool:
	return _valid_drop(data,point)

func _drop_at(_local: Vector2, data: Variant, point: int) -> void:
	if not _valid_drop(data,point): return
	var target := -1
	for i in draft.setup.fleet.size():
		if draft.setup.fleet[i].position==Geometry.POSITIONS[point]: target=i
	if data.kind=="captain": _change(data.captain,target,"captain")
	else:
		var assigned := -1
		for i in draft.setup.fleet.size():
			if draft.setup.fleet[i].ship==data.ship: assigned=i
		if assigned>=0: _change(Geometry.POSITIONS[point],assigned,"position")
		else: _change(data.ship,target,"ship")

func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_END:
		drag_payload.clear()
		if is_instance_valid(formation): formation.show_rule_preview({},selected_ship)



func _candidate() -> Dictionary:
	var result := draft.duplicate(true)
	result.setup.fixed_hand = false
	fixed_available = false
	if Catalog.validate(result).is_empty() and source.setup.fixed_hand:
		var pool: Array = Catalog.compile(result).deck_keys.duplicate()
		fixed_available = source.setup.opening_hand.size() == 7
		for id in source.setup.opening_hand:
			if not pool.has(id): fixed_available = false; break
			pool.erase(id)
	result.setup.fixed_hand = prefer_fixed and fixed_available
	return result


func _update() -> void:
	var candidate := _candidate()
	var errors := Catalog.validate(candidate)
	launch_button.disabled = not errors.is_empty()
	if not errors.is_empty():
		status.text = "Cannot launch: " + str(errors[0])
		return
	var compiled := Catalog.compile(candidate)
	var sim = State.new(0,candidate)
	var board: Dictionary = sim.board_snapshot()
	formation.configure(board,false)
	_wire_formation(board)
	formation.show_rule_preview({},selected_ship)
	var ship: Dictionary = compiled.ships[selected_ship]
	_render_deck_preview(compiled, ship, candidate.setup.fleet[selected_ship])
	var unit_data: Dictionary = board.ships[selected_ship]
	var lines: Array = ["%s · HULL %d · ARMOUR %d" % [ship.role,unit_data.max_hull,unit_data.armour],"Weapon %d · %s / %s %d" % [unit_data.weapon.damage,unit_data.weapon.range,ship.resource.name,unit_data.resource_capacity]]
	for pair in ship.loadout:
		lines.append("%d × %s" % [pair.count,compiled.cards[pair.card].name])
	details[0].text = "\n".join(lines)
	details[0].tooltip_text = "\n".join(ship.loadout.map(func(pair): return compiled.cards[pair.card].effect))
	var rewards: Array = ["Captain: " + Rules.rule_text(ship.captain.passive, ship.name)]
	var slot: Dictionary = candidate.setup.fleet[selected_ship]
	for tier in ["two","three"]:
		if slot.level < (2 if tier == "two" else 3): continue
		var package: Dictionary = ship.levels[tier][Catalog.index_by_id(ship.levels[tier],slot["level_2" if tier == "two" else "level_3"])]
		rewards.append(package.name + ": " + Rules.rule_text(package.passive, ship.name))
		rewards.append(Rules.rule_text(package.rule, ship.name))
	details[1].text = "\n".join(rewards)
	if ship.has("legacy_loadout"): details[1].text += "\nImported card loadout retained."
	var enemies: Array = []
	for enemy in compiled.enemies: enemies.append(enemy.name)
	encounter.text = "Encounter: " + " · ".join(enemies)
	opening_note.text = "Saved fixed opening: " + ", ".join(source.setup.opening_hand.map(func(id): return compiled.cards[id].name)) if candidate.setup.fixed_hand else ("Shuffled opening: saved hand contains unavailable cards." if prefer_fixed and source.setup.fixed_hand else "Shuffled seven-card opening.")
	var total := 0
	for unit in board.ships: total += int(unit.max_hull)
	status.text = "%d ships · %d cards · %d hull / %s" % [compiled.ships.size(),compiled.deck_keys.size(),total,"Saved opening" if candidate.setup.fixed_hand else "Shuffled opening"]
	status.modulate = Color("#91c8ad")


func _remember() -> void:
	BattleSession.preparation_draft = {"fingerprint": fingerprint, "fleet": draft.setup.fleet.duplicate(true), "prefer_fixed": prefer_fixed, "selected_ship": selected_ship}


func _reset() -> void:
	draft = source.duplicate(true)
	prefer_fixed = source.setup.fixed_hand
	_render()


func _back() -> void:
	if draft.has("setup"): _remember()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _launch() -> void:
	var candidate := _candidate()
	var errors := Catalog.validate(candidate)
	if not errors.is_empty():
		status.text = "Cannot launch: " + str(errors[0])
		return
	_remember()
	BattleSession.prepared_content = candidate.duplicate(true)
	BattleSession.editor_playtest = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_deck() -> void:
	fleet_scroll.ensure_control_visible(deck_preview)


func _render_deck_preview(compiled: Dictionary, ship: Dictionary, slot: Dictionary) -> void:
	_clear(deck_cards)
	var groups: Array = []
	if ship.has("legacy_loadout"):
		for pair in ship.loadout: groups.append({"label": "Imported loadout", "card": pair.card, "count": pair.count})
	else:
		groups.append({"label": "Starter / Level 1", "card": ship.starter, "count": 2})
		groups.append({"label": "Captain / " + ship.captain.name + " / Tier " + str(ship.captain.tier), "card": ship.captain.card, "count": 2})
		for tier in ["two", "three"]:
			var level := 2 if tier == "two" else 3
			if slot.level < level: continue
			var package: Dictionary = ship.levels[tier][Catalog.index_by_id(ship.levels[tier], slot["level_2" if tier == "two" else "level_3"])]
			groups.append({"label": "Level %d / %s / +2 cards" % [level, package.name], "card": package.card, "count": 2})
	var total := 0
	for group in groups:
		total += int(group.count)
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 240
		deck_cards.add_child(column)
		var origin := _label(column, group.label, 12)
		origin.set_meta("plain_text", true)
		origin.custom_minimum_size.y = 40
		origin.modulate = Color("#91b9c6")
		_label(column, "%d copies" % group.count, 14).set_meta("plain_text", true)
		var face := CardFace.new()
		face.set_meta("card_id", group.card)
		face.set_meta("copies", group.count)
		face.set_meta("origin", group.label)
		face.custom_minimum_size = Vector2(240, 320)
		face.toggle_mode = false
		face.mouse_default_cursor_shape = Control.CURSOR_ARROW
		face.configure(compiled.cards[group.card], ship)
		column.add_child(face)
	deck_summary.text = "%s / Level %d / %d cards in deck" % [ship.name, slot.level, total]
