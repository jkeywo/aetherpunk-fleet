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
var ship_dialog: AcceptDialog
var ship_comparison: HBoxContainer
var captain_dialog: AcceptDialog
var captain_comparison: HBoxContainer
var upgrade_dialog: AcceptDialog
var upgrade_comparison: HBoxContainer
var comparison_tier := "two"
var deck_summary: Label
var preparation_tabs: TabContainer
var fleet_deck_body: VBoxContainer
var fleet_deck_summary: Label
var ship_info_dialog: AcceptDialog
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
	var background := preload("res://scripts/sky_background.gd").new()
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
	_label(outer,"Drag ships between positions and captains onto ships. Click a ship’s i button for its details, levels and cards.",14).modulate = Color("#91b9c6")
	preparation_tabs = TabContainer.new()
	preparation_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(preparation_tabs)
	var split := VBoxContainer.new()
	split.name = "Fleet Setup"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preparation_tabs.add_child(split)
	var left_scroll := ScrollContainer.new()
	fleet_scroll = left_scroll
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation",8)
	left_scroll.add_child(left)
	formation = Formation.new()
	formation.large_cards = true
	formation.custom_minimum_size = Vector2(550,420)
	left.add_child(formation)
	formation.position_selected.connect(_select_position)
	var ships_header:=HBoxContainer.new()
	left.add_child(ships_header)
	_label(ships_header,"SHIPS / drag to move or replace",12).modulate=Color("#e8bd77")
	ship_bank = HFlowContainer.new()
	left.add_child(ship_bank)
	var captains_header:=HBoxContainer.new()
	left.add_child(captains_header)
	_label(captains_header,"CAPTAINS / drag onto a ship",12).modulate=Color("#e8bd77")
	ship_info_dialog=AcceptDialog.new()
	ship_info_dialog.name="ShipDetails"
	ship_info_dialog.get_ok_button().text="Close"
	add_child(ship_info_dialog)
	var info_scroll:=ScrollContainer.new()
	info_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_scroll.offset_left=14;info_scroll.offset_top=14;info_scroll.offset_right=-14;info_scroll.offset_bottom=-60
	info_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	ship_info_dialog.add_child(info_scroll)
	var info_columns:=HBoxContainer.new()
	info_columns.custom_minimum_size=Vector2(850,460)
	info_columns.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	info_columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	info_columns.add_theme_constant_override("separation",18)
	info_scroll.add_child(info_columns)
	captain_bank = HFlowContainer.new()
	left.add_child(captain_bank)
	deck_preview = VBoxContainer.new()
	deck_preview.add_theme_constant_override("separation", 8)
	info_columns.add_child(deck_preview)
	deck_preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	deck_preview.custom_minimum_size.x=500
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
	content_scroll.custom_minimum_size.x = 330
	content_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_columns.add_child(content_scroll)
	info_columns.move_child(content_scroll,0)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation",7)
	content_scroll.add_child(inspector)
	var fleet_deck_scroll := ScrollContainer.new()
	fleet_deck_scroll.name = "Fleet Deck"
	fleet_deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preparation_tabs.add_child(fleet_deck_scroll)
	var deck_page := VBoxContainer.new()
	deck_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_page.add_theme_constant_override("separation", 12)
	fleet_deck_scroll.add_child(deck_page)
	fleet_deck_summary = _label(deck_page, "", 22)
	fleet_deck_summary.set_meta("plain_text", true)
	fleet_deck_summary.modulate = Color("#e8bd77")
	_label(deck_page, "The complete deck for your current fleet, grouped by ship, then Attack, Guard, Manoeuvre, Support. One preview per design; copy counts include every physical card.", 14)
	fleet_deck_body = VBoxContainer.new()
	fleet_deck_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fleet_deck_body.add_theme_constant_override("separation", 24)
	deck_page.add_child(fleet_deck_body)
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
	var captain_header := HBoxContainer.new()
	inspector.add_child(captain_header)
	captain_header.add_child(preload("res://scripts/art_assets.gd").portrait_view(slot.captain,Vector2(64,85)))
	_label(captain_header,draft.captains[Catalog.index_by_id(draft.captains,slot.captain)].name,17)
	var options: Array = []
	_menu(inspector,"Level",[{"label":"1 · Starter + captain pairs","value":1},{"label":"2 · Add one upgrade pair","value":2},{"label":"3 · Add both upgrade pairs","value":3}],slot.level,_change.bind(selected_ship,"level"),"level_"+str(selected_ship))
	options=[]
	for package in ship.levels.two: options.append({"label":package.name,"value":package.id,"tooltip":_package_text(package)})
	_menu(inspector,"Level 2 branch",options,slot.level_2,_change.bind(selected_ship,"level_2"),"level_2_"+str(selected_ship),slot.level>=2)
	_button(inspector, "Compare Level 2 branches", _show_upgrades.bind("two"))
	var blocked := ""
	var branch := Catalog.index_by_id(ship.levels.two,slot.level_2)
	if branch>=0: blocked=ship.levels.two[branch].blocks
	options=[]
	var blocked_name := ""
	for package in ship.levels.three:
		if package.id==blocked: blocked_name=package.name
		else: options.append({"label":package.name,"value":package.id,"tooltip":_package_text(package)})
	_menu(inspector,"Level 3 branch",options,slot.level_3,_change.bind(selected_ship,"level_3"),"level_3_"+str(selected_ship),slot.level>=3)
	_button(inspector, "Compare Level 3 branches", _show_upgrades.bind("three"))
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
	_button(ship_bank,"Compare Airships",_show_ships)
	for entry in draft.captains:
		var button := _button(captain_bank,entry.name+" · "+str(entry.tier),func(): pass)
		button.tooltip_text=Rules.rule_text(entry.passive, ship.name)
		button.set_meta("plain_text",true)
		button.set_drag_forwarding(_drag_from.bind({"kind":"captain","captain":entry.id},button),Callable(),Callable())
	_button(captain_bank,"Compare Captains",_show_captains)
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
		widget.set_meta("footer_space",32)
		widget._art_layout()
		badge.position=Vector2(7,widget.size.y-32)
		badge.size=Vector2(widget.size.x-14,30)
		badge.icon=preload("res://scripts/art_assets.gd").portrait(captain.id)
		badge.expand_icon=true
		badge.add_theme_constant_override("icon_max_width",24)
		badge.tooltip_text="Drag to assign/swap this captain.\n"+Rules.rule_text(captain.passive, board.ships[id].name)
		widget.add_child(badge)
		badge.pressed.connect(func(): selected_ship=id; _render())
		badge.set_drag_forwarding(_drag_from.bind({"kind":"captain","captain":captain.id},badge),_can_drop_at.bind(point),_drop_at.bind(point))
		widget.set_meta("captain_badge",badge)
		var info_button:=Button.new()
		info_button.text="i"
		info_button.set_meta("plain_text",true)
		info_button.set_meta("ship_info",id)
		info_button.tooltip_text="Ship details, levels, upgrade branches and cards"
		info_button.position=Vector2(widget.size.x-29,0)
		info_button.size=Vector2(28,26)
		widget.add_child(info_button)
		info_button.pressed.connect(_show_ship_info.bind(id))

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
		fleet_deck_summary.text = "Deck preview unavailable until fleet setup is valid."
		_clear(fleet_deck_body)
		return
	var compiled := Catalog.compile(candidate)
	_render_fleet_deck(compiled, candidate)
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


func _show_ship_info(index: int) -> void:
	selected_ship=index
	_render()
	ship_info_dialog.title=draft.ships[Catalog.index_by_id(draft.ships,draft.setup.fleet[index].ship)].name+" / Preparation"
	ship_info_dialog.popup_centered(Vector2i(mini(1160,int(get_viewport_rect().size.x*.94)),mini(650,int(get_viewport_rect().size.y*.9))))

func _show_deck() -> void:
	_show_ship_info(selected_ship)


func _render_deck_preview(compiled: Dictionary, ship: Dictionary, slot: Dictionary) -> void:
	_clear(deck_cards)
	var groups := _ship_card_groups(ship, slot)
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


func _show_upgrades(tier: String) -> void:
	comparison_tier = tier
	if is_instance_valid(upgrade_dialog):
		upgrade_dialog.hide()
		upgrade_dialog.queue_free()
	upgrade_dialog = AcceptDialog.new()
	upgrade_dialog.name = "UpgradeComparison"
	upgrade_dialog.get_ok_button().text = "Close"
	(ship_info_dialog if ship_info_dialog.visible else self).add_child(upgrade_dialog)
	var slot: Dictionary = draft.setup.fleet[selected_ship]
	var ship: Dictionary = draft.ships[Catalog.index_by_id(draft.ships, slot.ship)]
	var level := 2 if tier == "two" else 3
	upgrade_dialog.title = "%s / Compare Level %d branches" % [ship.name, level]
	var viewer_size := Vector2i(minf(1180, get_viewport_rect().size.x * 0.94), minf(700, get_viewport_rect().size.y * 0.88))
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = viewer_size.x - 40
	upgrade_dialog.add_child(body)
	var caption := Label.new()
	caption.text = "Each branch adds two copies of its card, plus the special rule and passive shown below."
	caption.add_theme_font_size_override("font_size", 13)
	if tier == "three" and slot.level < 2: caption.text += "\nChoose a Level 2 branch first to determine which Level 3 option is blocked."
	if ship.has("legacy_loadout"): caption.text = "Imported loadout: these branches change rules and passives; the imported deck stays fixed."
	body.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	upgrade_comparison = HBoxContainer.new()
	upgrade_comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_comparison.alignment = BoxContainer.ALIGNMENT_CENTER
	upgrade_comparison.add_theme_constant_override("separation", 14)
	scroll.add_child(upgrade_comparison)
	var blocked := ""
	var l2 := Catalog.index_by_id(ship.levels.two, slot.level_2)
	if l2 >= 0: blocked = ship.levels.two[l2].blocks
	var width: float = floor((viewer_size.x - 60 - 14 * (ship.levels[tier].size() - 1)) / ship.levels[tier].size())
	width = minf(width, 370)
	for package in ship.levels[tier]:
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = width
		column.set_meta("branch_id", package.id)
		upgrade_comparison.add_child(column)
		var chosen: bool = slot.level >= level and slot["level_2" if tier == "two" else "level_3"] == package.id
		var locked: bool = tier == "three" and package.id == blocked
		var name_label := _label(column, package.name, 19)
		name_label.set_meta("plain_text", true)
		name_label.custom_minimum_size.y = 48
		var state_text: String = "SELECTED" if chosen else ("BLOCKED by " + ship.levels.two[l2].name if locked else ("Choose Level 2 first" if tier == "three" and slot.level < 2 else "Available / +2 cards"))
		var state_label := _label(column, state_text, 13)
		state_label.custom_minimum_size.y = 36
		state_label.modulate = Color("#f29b8e") if locked else (Color("#91c8ad") if chosen else Color("#e8bd77"))
		var face := CardFace.new()
		face.custom_minimum_size = Vector2(width, 300)
		face.toggle_mode = false
		face.mouse_default_cursor_shape = Control.CURSOR_ARROW
		face.configure(Catalog.present_card(draft.cards[Catalog.index_by_id(draft.cards, package.card)], selected_ship, ship.name), ship)
		face.set_meta("card_id", package.card)
		column.add_child(face)
		var choose := _button(column, "Selected" if chosen else ("Blocked" if locked else "Choose this branch"), _choose_upgrade.bind(tier, package.id))
		choose.set_meta("choose_branch", package.id)
		choose.disabled = chosen or locked or (tier == "three" and slot.level < 2)
		choose.tooltip_text = "Raises this ship to Level %d if needed." % level
		if tier == "two":
			var excluded: Dictionary = ship.levels.three[Catalog.index_by_id(ship.levels.three, package.blocks)]
			_label(column, "Blocks Level 3: " + excluded.name, 12).modulate = Color("#e8bd77")
		_label(column, "SPECIAL RULE", 12).modulate = Color("#91b9c6")
		_label(column, Rules.rule_text(package.rule, ship.name), 13)
		_label(column, "PASSIVE UPGRADE", 12).modulate = Color("#91b9c6")
		_label(column, Rules.rule_text(package.passive, ship.name), 13)
	upgrade_dialog.popup_centered(viewer_size)


func _choose_upgrade(tier: String, id: String) -> void:
	var slot: Dictionary = draft.setup.fleet[selected_ship]
	var ship: Dictionary = draft.ships[Catalog.index_by_id(draft.ships, slot.ship)]
	if Catalog.index_by_id(ship.levels[tier], id) < 0: return
	if tier == "three":
		var l2 := Catalog.index_by_id(ship.levels.two, slot.level_2)
		if slot.level < 2 or l2 < 0 or ship.levels.two[l2].blocks == id: return
	slot.level = maxi(slot.level, 2 if tier == "two" else 3)
	slot["level_2" if tier == "two" else "level_3"] = id
	_repair_branch(slot)
	_render()
	_show_upgrades(tier)


func _show_captains() -> void:
	if is_instance_valid(captain_dialog):
		captain_dialog.hide()
		captain_dialog.queue_free()
	captain_dialog = AcceptDialog.new()
	captain_dialog.name = "CaptainComparison"
	captain_dialog.get_ok_button().text = "Close"
	add_child(captain_dialog)
	var slot: Dictionary = draft.setup.fleet[selected_ship]
	var ship: Dictionary = draft.ships[Catalog.index_by_id(draft.ships, slot.ship)]
	captain_dialog.title = ship.name + " / Compare captains"
	var viewer_size := Vector2i(minf(1180, get_viewport_rect().size.x * 0.94), minf(700, get_viewport_rect().size.y * 0.88))
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = viewer_size.x - 40
	captain_dialog.add_child(body)
	var caption := Label.new()
	caption.text = "Two copies of the shown card and its passive replace the current captain.\nA captain assigned elsewhere swaps places with this ship's current captain."
	caption.add_theme_font_size_override("font_size", 13)
	if ship.has("legacy_loadout"): caption.text = "Imported loadout: captain passives change; the imported deck stays fixed.\nAssigned captains swap places with this ship's current captain."
	body.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	captain_comparison = HBoxContainer.new()
	captain_comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	captain_comparison.alignment = BoxContainer.ALIGNMENT_CENTER
	captain_comparison.add_theme_constant_override("separation", 14)
	scroll.add_child(captain_comparison)
	var visible_count := clampi(draft.captains.size(), 1, 3)
	var width: float = minf(370, floor((viewer_size.x - 60 - 14 * (visible_count - 1)) / visible_count))
	for captain in draft.captains:
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = width
		column.set_meta("captain_id", captain.id)
		captain_comparison.add_child(column)
		var assigned := -1
		for i in draft.setup.fleet.size():
			if draft.setup.fleet[i].captain == captain.id: assigned = i
		var current: bool = assigned == selected_ship
		var other_name := ""
		if assigned >= 0: other_name = draft.ships[Catalog.index_by_id(draft.ships, draft.setup.fleet[assigned].ship)].name
		column.add_child(preload("res://scripts/art_assets.gd").portrait_view(captain.id,Vector2(width,145)))
		var title := _label(column, captain.name + " / Tier " + str(captain.tier), 19)
		title.set_meta("plain_text", true)
		title.custom_minimum_size.y = 48
		var assigned_label := _label(column, "ASSIGNED HERE" if current else ("Assigned to " + other_name if assigned >= 0 else "Available / 2 copies"), 13)
		assigned_label.custom_minimum_size.y = 36
		assigned_label.modulate = Color("#91c8ad") if current else Color("#e8bd77")
		var face := CardFace.new()
		face.custom_minimum_size = Vector2(width, 300)
		face.toggle_mode = false
		face.mouse_default_cursor_shape = Control.CURSOR_ARROW
		face.configure(Catalog.present_card(draft.cards[Catalog.index_by_id(draft.cards, captain.card)], selected_ship, ship.name), ship)
		face.set_meta("card_id", captain.card)
		face.set_meta("copies", 2)
		column.add_child(face)
		var assign := _button(column, "Assigned" if current else ("Swap with " + other_name if assigned >= 0 else "Assign to " + ship.name), _assign_captain.bind(captain.id))
		assign.set_meta("assign_captain", captain.id)
		assign.disabled = current
		assign.tooltip_text = "Two copies of this card will act as " + ship.name + "."
		_label(column, "PASSIVE BONUS / on " + ship.name, 12).modulate = Color("#91b9c6")
		var passive := _label(column, Rules.rule_text(captain.passive, ship.name), 14)
		passive.set_meta("captain_passive", captain.id)
	captain_dialog.popup_centered(viewer_size)


func _assign_captain(id: String) -> void:
	if Catalog.index_by_id(draft.captains, id) < 0: return
	_change(id, selected_ship, "captain")
	_show_captains()


func _show_ships() -> void:
	if is_instance_valid(ship_dialog):
		ship_dialog.hide()
		ship_dialog.queue_free()
	ship_dialog = AcceptDialog.new()
	ship_dialog.name = "ShipComparison"
	ship_dialog.get_ok_button().text = "Close"
	add_child(ship_dialog)
	var slot: Dictionary = draft.setup.fleet[selected_ship]
	ship_dialog.title = slot.position.capitalize() + " / Compare ships"
	var viewer_size := Vector2i(minf(1180, get_viewport_rect().size.x * 0.94), minf(700, get_viewport_rect().size.y * 0.88))
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = viewer_size.x - 40
	ship_dialog.add_child(body)
	var caption := Label.new()
	caption.text = "Base stats exclude captains and upgrades. Each starter design contributes two copies.\nShips already in your fleet swap slots. Captains and level choices stay with their slots."
	caption.add_theme_font_size_override("font_size", 13)
	body.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	ship_comparison = HBoxContainer.new()
	ship_comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_comparison.alignment = BoxContainer.ALIGNMENT_CENTER
	ship_comparison.add_theme_constant_override("separation", 14)
	scroll.add_child(ship_comparison)
	var visible_count := clampi(draft.ships.size(), 1, 3)
	var width: float = minf(370, floor((viewer_size.x - 60 - 14 * (visible_count - 1)) / visible_count))
	for ship in draft.ships:
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = width
		column.set_meta("ship_id", ship.id)
		ship_comparison.add_child(column)
		var assigned := -1
		for i in draft.setup.fleet.size():
			if draft.setup.fleet[i].ship == ship.id: assigned = i
		var current: bool = assigned == selected_ship
		var position_name: String = draft.setup.fleet[assigned].position.capitalize() if assigned >= 0 else ""
		var title := _label(column, ship.name, 21)
		title.set_meta("plain_text", true)
		title.custom_minimum_size.y = 36
		title.modulate = Color(ship.color)
		var assigned_label := _label(column, "SELECTED / " + position_name if current else ("In fleet / " + position_name if assigned >= 0 else "Available"), 13)
		assigned_label.custom_minimum_size.y = 30
		assigned_label.modulate = Color("#91c8ad") if current else Color("#e8bd77")
		var stats := _label(column, "%s\nHull %d / Armour %d\nWeapon %d / %s\n%s capacity %d" % [ship.role, ship.hull, ship.armour, ship.weapon.damage, ship.weapon.range, ship.resource.name, ship.resource.capacity], 14)
		stats.custom_minimum_size.y = 84
		stats.set_meta("ship_stats", ship.id)
		for starter_id in [ship.starter]+([ship.starter_two] if ship.get("starter_two","")!="" else []):
			var face := CardFace.new()
			face.custom_minimum_size = Vector2(width, 240)
			face.toggle_mode = false
			face.mouse_default_cursor_shape = Control.CURSOR_ARROW
			face.configure(Catalog.present_card(draft.cards[Catalog.index_by_id(draft.cards, starter_id)], selected_ship, ship.name), ship)
			face.set_meta("card_id", starter_id)
			face.set_meta("copies", 2)
			column.add_child(face)
		var choose := _button(column, "Selected" if current else ("Swap with " + position_name if assigned >= 0 else "Choose for " + slot.position.capitalize()), _choose_ship.bind(ship.id))
		choose.set_meta("choose_ship", ship.id)
		choose.disabled = current
		_label(column, "UNIQUE MECHANIC / " + ship.resource.name, 12).modulate = Color("#91b9c6")
		var mechanism: Array = ship.resource.rules.duplicate() + ship.rules.duplicate()
		var explanation := _label(column, "\n".join(mechanism.map(func(rule): return Rules.rule_text(rule, ship.name))) if not mechanism.is_empty() else "No unique mechanism configured.", 12)
		explanation.set_meta("ship_mechanism", ship.id)
	ship_dialog.popup_centered(viewer_size)


func _choose_ship(id: String) -> void:
	if Catalog.index_by_id(draft.ships, id) < 0: return
	_change(id, selected_ship, "ship")
	_show_ships()


func _ship_card_groups(ship: Dictionary, slot: Dictionary) -> Array:
	var groups: Array = []
	if ship.has("legacy_loadout"):
		for pair in ship.loadout: groups.append({"label": "Imported loadout", "card": pair.card, "count": pair.count})
	else:
		groups.append({"label": "Starter / Level 1", "card": ship.starter, "count": 2})
		if ship.get("starter_two","")!="":groups.append({"label":"Starter / Level 1 / second pair","card":ship.starter_two,"count":2})
		groups.append({"label": "Captain / " + ship.captain.name + " / Tier " + str(ship.captain.tier), "card": ship.captain.card, "count": 2})
		for tier in ["two", "three"]:
			var level := 2 if tier == "two" else 3
			if slot.level < level: continue
			var package: Dictionary = ship.levels[tier][Catalog.index_by_id(ship.levels[tier], slot["level_2" if tier == "two" else "level_3"])]
			groups.append({"label": "Level %d / %s / +2 cards" % [level, package.name], "card": package.card, "count": 2})
	return groups


func _render_fleet_deck(compiled: Dictionary, candidate: Dictionary) -> void:
	_clear(fleet_deck_body)
	var fleet_total := 0
	var design_total := 0
	for index in compiled.ships.size():
		var ship: Dictionary = compiled.ships[index]
		var slot: Dictionary = candidate.setup.fleet[index]
		var quantities: Dictionary = {}
		var origins: Dictionary = {}
		for pair in ship.loadout: quantities[pair.card] = quantities.get(pair.card, 0) + int(pair.count)
		for group in _ship_card_groups(ship, slot):
			if not origins.has(group.card): origins[group.card] = []
			if not origins[group.card].has(group.label): origins[group.card].append(group.label)
		var ship_total := 0
		for count in quantities.values(): ship_total += int(count)
		fleet_total += ship_total
		design_total += quantities.size()
		var section := VBoxContainer.new()
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_theme_constant_override("separation", 10)
		section.set_meta("ship_index", index)
		fleet_deck_body.add_child(section)
		var heading := _label(section, "%s / %s / Level %d / %d cards" % [ship.name, slot.position.capitalize(), slot.level, ship_total], 21)
		heading.set_meta("plain_text", true)
		heading.modulate = Color(ship.color)
		_label(section, "Captain: " + ship.captain.name, 14).set_meta("plain_text", true)
		for type in Rules.TYPES:
			var keys: Array = quantities.keys().filter(func(id): return compiled.cards[id].type == type)
			if keys.is_empty(): continue
			keys.sort_custom(func(a, b):
				var first: String = compiled.cards[a].name
				var second: String = compiled.cards[b].name
				return first.naturalnocasecmp_to(second) < 0 if first != second else str(a) < str(b))
			var type_total := 0
			for id in keys: type_total += int(quantities[id])
			_label(section, "%s / %d cards" % [type, type_total], 16)
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			flow.add_theme_constant_override("h_separation", 14)
			flow.add_theme_constant_override("v_separation", 14)
			flow.set_meta("card_type", type)
			section.add_child(flow)
			for id in keys:
				var cell := VBoxContainer.new()
				cell.custom_minimum_size.x = 240
				flow.add_child(cell)
				var caption := _label(cell, "%d copies / %s" % [quantities[id], "; ".join(origins.get(id, []))], 12)
				caption.custom_minimum_size.y = 40
				caption.set_meta("plain_text", true)
				var face := CardFace.new()
				face.custom_minimum_size = Vector2(240, 300)
				face.toggle_mode = false
				face.mouse_default_cursor_shape = Control.CURSOR_ARROW
				face.configure(compiled.cards[id], ship)
				face.set_meta("card_id", id)
				face.set_meta("ship_index", index)
				face.set_meta("copies", quantities[id])
				face.set_meta("origins", origins.get(id, []).duplicate())
				cell.add_child(face)
	fleet_deck_summary.text = "Fleet deck / %d cards / %d designs / %d ships" % [fleet_total, design_total, compiled.ships.size()]
