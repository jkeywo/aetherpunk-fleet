extends Control
## The world map and its campaign management panels.

const World = preload("res://scripts/campaign_map.gd")
const Content = preload("res://scripts/campaign_content.gd")
const Catalog = preload("res://scripts/content_catalog.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const ThemeFactory = preload("res://scripts/ui_theme.gd")
const Atlas = preload("res://scripts/campaign_atlas.gd")
const Art = preload("res://scripts/art_assets.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const Difficulty = preload("res://scripts/encounter_difficulty.gd")
const DifficultyIcons = preload("res://scripts/difficulty_icons.gd")
const CampaignArt = preload("res://scripts/campaign_art.gd")
const RigView = preload("res://scripts/rig_view.gd")
const StanceList = preload("res://scripts/enemy_stance_list.gd")

class RageTrack extends Control:
	const RADIUS := 7.0
	const SPACING := 22.0
	const FILL := Color("#e38e80")
	var filled := 0
	var total := 0

	func _draw() -> void:
		for index in total:
			var center := Vector2(RADIUS + 1.0 + index * SPACING, size.y / 2.0)
			var earned := index < filled
			draw_circle(center, RADIUS, FILL, earned, -1.0 if earned else 1.5, true)

var selected_id := "grassland_first"
var message := ""
var content: VBoxContainer
var sidebar: VBoxContainer
var detail: VBoxContainer
var atlas: Control
var layout: HBoxContainer
var docks_overlay: PanelContainer
var enemy_overlay: PanelContainer
var inspected_enemy_button: Button

func _ready() -> void:
	theme = ThemeFactory.make()
	if CampaignStore.run.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
		return
	selected_id = BattleSession.campaign_node
	if selected_id.is_empty():
		selected_id = CampaignStore.run.get("last_result", {}).get("node", "grassland_first")
	BattleSession.campaign_battle = false
	message = CampaignStore.last_error
	_render()

func _render() -> void:
	var run: Dictionary = CampaignStore.run
	if run.ended or not run.recruitment.is_empty():
		var screen := PanelContainer.new()
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(screen)
		content = _scroll_body(screen)
		var back := _back_button(content, _main_menu)
		back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if not message.is_empty(): _label(content, message).modulate = Color("#f0ca90")
		if run.ended: _summary()
		else: _recruitment()
		return

	layout = HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	atlas = Atlas.new()
	atlas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(atlas)
	atlas.configure(run.cleared, selected_id)
	atlas.selected.connect(_select)
	atlas.restore_camera.call_deferred(BattleSession.campaign_camera)

	var back := _back_button(atlas, _main_menu)
	back.position = Vector2(14, 12)
	back.tooltip_text = "Back to Main Menu"
	var zoom_controls := HBoxContainer.new()
	atlas.add_child(zoom_controls)
	zoom_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	zoom_controls.offset_left = 14
	zoom_controls.offset_top = -48
	var zoom_out := _button(zoom_controls, "−", atlas.zoom_by.bind(1.0 / 1.3))
	zoom_out.custom_minimum_size.x = 38
	zoom_out.tooltip_text = "Zoom out"
	var zoom_in := _button(zoom_controls, "+", atlas.zoom_by.bind(1.3))
	zoom_in.custom_minimum_size.x = 38
	zoom_in.tooltip_text = "Zoom in"
	_button(zoom_controls, "Reset View", atlas.reset_camera).tooltip_text = "Reset map pan and zoom"

	var right := PanelContainer.new()
	var resize_sidebar := func(): right.custom_minimum_size.x = clampf(size.x * 0.32, 260, 390)
	resize_sidebar.call()
	resized.connect(resize_sidebar)
	layout.add_child(right)
	sidebar = _scroll_body(right)
	_render_sidebar()

func _scroll_body(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var margins := MarginContainer.new()
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: margins.add_theme_constant_override("margin_" + side, 8)
	scroll.add_child(margins)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margins.add_child(body)
	return body

func _main_menu() -> void:
	_remember_map()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _remember_map() -> void:
	if not is_instance_valid(atlas): return
	BattleSession.campaign_node = selected_id
	BattleSession.campaign_camera = atlas.camera()

func _select(id: String) -> void:
	selected_id = id
	atlas.configure(CampaignStore.run.cleared, id)
	_render_sidebar()

func _render_sidebar() -> void:
	_clear(sidebar)
	var run: Dictionary = CampaignStore.run
	var rage := _panel(sidebar)
	_label(rage, "Rage %d" % CampaignStore.rage(), 21)
	var progress := RageTrack.new()
	progress.name = "RageProgress"
	progress.filled = CampaignStore.rage_progress()
	progress.total = CampaignStore.WINS_PER_RAGE_TIER
	progress.custom_minimum_size.y = 18
	rage.add_child(progress)
	_label(rage, "%d / %d wins toward the next tier" % [progress.filled, progress.total], 13)
	var docks := _panel(sidebar)
	_label(docks, "Docks", 21)
	_label(docks, "%d materials · %d sortie slots" % [run.materials, run.docks], 14)
	for id in run.ships:
		var owned: Dictionary = run.ships[id]
		var ship: Dictionary = _ship(id)
		var hull := "%d / %d hull" % [owned.hull, CampaignStore.dock_max(id)]
		_label(docks, "%s · Lv %d · %s" % [ship.name, owned.level, hull if owned.hull > 0 else "Disabled"], 13)
	if not run.destroyed.is_empty():
		_label(docks, "Lost: " + _ship_names(run.destroyed), 13).modulate = Color("#ffab90")
	_button(docks, "Manage Docks", _open_docks)

	detail = _panel(sidebar)
	if not message.is_empty(): _label(detail, message).modulate = Color("#f0ca90")
	if "grassland_boss" in run.cleared:
		_label(detail, "Grassland complete · Fleet maximum hull +2").modulate = Color("#a6e0b0")
	_encounter()

func _back_button(parent: Node, action: Callable) -> Button:
	var button := _button(parent, "Back", action)
	button.icon = ThemeFactory.back_icon()
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _summary() -> void:
	var panel := _panel(content)
	_label(panel, "Run ended", 28)
	_label(panel, "%d encounters cleared · Rage %d" % [CampaignStore.run.wins, CampaignStore.rage()])
	_label(panel, "No operational ship remains and the fleet cannot afford to repair or craft a hull.")
	_label(panel, "Lost hulls: " + _ship_names(CampaignStore.run.destroyed))

func _ship_names(ids: Array) -> String:
	var names: Array = []
	for id in ids:
		var index := Catalog.index_by_id(CampaignStore.run.content.ships, id)
		if index >= 0: names.append(CampaignStore.run.content.ships[index].name)
	return ", ".join(names)

func _recruitment() -> void:
	_label(content, "Choose a captain", 25)
	_label(content, "The liberated town offers three captains. One joins your fleet.")
	var row := HFlowContainer.new()
	content.add_child(row)
	for id in CampaignStore.run.recruitment:
		var captain := _captain(id)
		var panel := _panel(row)
		panel.custom_minimum_size.x = 300
		var portrait := Art.portrait_view(id, Vector2(84, 84))
		panel.add_child(portrait)
		_label(panel, "%s · Tier %d" % [captain.name, captain.tier], 20)
		_label(panel, Rules.rule_text(captain.passive, captain.name))
		var card: Dictionary = CampaignStore.run.content.cards[Catalog.index_by_id(CampaignStore.run.content.cards, captain.card)]
		_label(panel, card.name, 17)
		for rule in card.rules: _label(panel, Rules.rule_text(rule, captain.name))
		_button(panel, "Recruit " + captain.name, _recruit.bind(id))

func _recruit(id: String) -> void:
	_apply(CampaignStore.recruit(id))

func _encounter() -> void:
	var run: Dictionary = CampaignStore.run
	var node: Dictionary = World.nodes()[selected_id]
	var rating := World.difficulty(node, run.cleared)
	var scale := World.scaling(node, rating.stars, CampaignStore.rage())
	var illustration := TextureRect.new()
	illustration.texture = CampaignArt.location(node)
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	illustration.custom_minimum_size.y = 124
	detail.add_child(illustration)
	_label(detail, node.name, 23)
	_label(detail, "%s  ·  %s" % [node.biome.capitalize(), node.kind.capitalize()])
	var rating_row := HBoxContainer.new()
	detail.add_child(rating_row)
	var skulls := TextureRect.new()
	skulls.texture = DifficultyIcons.texture(int(rating.stars))
	skulls.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	skulls.tooltip_text = "Difficulty %d / 10. A large skull counts as five." % rating.stars
	rating_row.add_child(skulls)
	var rating_label := _label(rating_row, "%d / 10" % rating.stars, 19)
	rating_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	rating_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rating_label.modulate = Color("#f0ca90")
	_label(detail, "Base %d + distance %d · %d %s from cleared territory" % [rating.base, rating.surcharge, rating.distance, "link" if rating.distance == 1 else "links"])
	var row_size := Difficulty.visible_enemy_cards(int(rating.stars))
	_label(detail, "Up to %d visible enemy %s" % [row_size, "card" if row_size == 1 else "cards"])
	_label(detail, "Enemy scaling · +%d%% base hull · +%d damage per hit" % [scale.hull_percent, scale.hit_bonus])
	if node.kind == "boss":
		_label(detail, "Rage contribution · +%d%% base hull · +%d damage per hit" % [scale.doom_hull_percent, scale.doom_hit_bonus])
		if node.playable:
			_label(detail, "The Crown Grazer occupies all four slots. Target its body, either claw, or its tail separately. Defeat all four parts to win.")
	if node.playable:
		if node.kind == "regular": _label(detail, "Reward · %d materials" % (5 + int(rating.stars)))
		elif node.kind == "town": _label(detail, "Reward · Choose one of three captains")
		else: _label(detail, "Reward · +2 maximum hull for the run, plus full repair for deployed ships")
		_enemy_preview(node, int(rating.stars), scale)
	if not node.playable: _label(detail, "Not in this build", 18).modulate = Color("#f0ca90")
	elif selected_id in run.cleared: _label(detail, "Cleared", 18).modulate = Color("#a6e0b0")
	var launch := _button(detail, "Choose Sortie", _open_sortie)
	launch.disabled = not node.playable or selected_id in run.cleared or not CampaignStore.can_manage() or CampaignStore.operational_ships().is_empty()
	if node.playable and selected_id not in run.cleared and CampaignStore.operational_ships().is_empty():
		launch.tooltip_text = "Repair or craft an airship at the docks to launch."

func _enemy_preview(node: Dictionary, stars: int, scale: Dictionary) -> void:
	var run: Dictionary = CampaignStore.run
	for item in Content.encounter(int(run.seed), node, stars):
		var enemy: Dictionary = run.content.leviathans[Catalog.index_by_id(run.content.leviathans, item.enemy)]
		var position: String = Geometry.POSITION_NAMES[Geometry.POSITIONS.find(item.position)]
		var hull := ceili(int(enemy.hull) * (100 + int(scale.hull_percent)) / 100.0)
		var button := Button.new()
		button.text = "%s · %s · %d hull" % [position, enemy.name, hull]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size.y = 33
		button.add_theme_font_size_override("font_size", 13)
		button.set_meta("keyword_left_padding", 18)
		button.set_meta("enemy_positions", true)
		button.tooltip_text = "Inspect %s’s stance cards (%s)" % [enemy.name, position]
		button.pressed.connect(_inspect_enemy.bind(button, enemy, position, hull, int(scale.hit_bonus)))
		detail.add_child(button)

func _inspect_enemy(button: Button, enemy: Dictionary, position: String, hull: int, hit_bonus: int) -> void:
	if is_instance_valid(enemy_overlay): return
	inspected_enemy_button = button
	layout.hide()
	enemy_overlay = PanelContainer.new()
	enemy_overlay.name = "EnemyInspector"
	enemy_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(enemy_overlay)
	var body := _scroll_body(enemy_overlay)
	var back := _back_button(body, _close_enemy_inspector)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.grab_focus()
	var header := HBoxContainer.new()
	body.add_child(header)
	var visual := RigView.new()
	visual.custom_minimum_size = Vector2(120, 86)
	header.add_child(visual)
	visual.configure_data(enemy, true)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(summary)
	_label(summary, enemy.name, 24).set_meta("plain_text", true)
	_label(summary, "%s · %d hull · %d armour" % [position, hull, enemy.armour]).set_meta("enemy_positions", true)
	if hit_bonus > 0:
		_label(summary, "Encounter bonus · +%d damage per hit" % hit_bonus)
	var fallback := Catalog.effects_text(enemy.default_action, enemy.name)
	if not fallback.is_empty():
		_label(body, "Default action — " + fallback)
	_label(body, "Stance cards", 18)
	body.add_child(StanceList.new(enemy, 390, Geometry.POSITION_NAMES.find(position)))

func _close_enemy_inspector() -> void:
	remove_child(enemy_overlay)
	enemy_overlay.queue_free()
	enemy_overlay = null
	layout.show()
	if is_instance_valid(inspected_enemy_button):
		inspected_enemy_button.grab_focus()
	inspected_enemy_button = null

func _open_docks() -> void:
	if is_instance_valid(docks_overlay): return
	layout.hide()
	docks_overlay = PanelContainer.new()
	docks_overlay.name = "DocksOverlay"
	docks_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(docks_overlay)
	_render_docks()

func _close_docks() -> void:
	remove_child(docks_overlay)
	docks_overlay.queue_free()
	docks_overlay = null
	layout.show()
	_render_sidebar()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"): return
	if is_instance_valid(enemy_overlay):
		_close_enemy_inspector()
	elif is_instance_valid(docks_overlay):
		_close_docks()
	else:
		return
	get_viewport().set_input_as_handled()

func _render_docks() -> void:
	_clear(docks_overlay)
	var body := _scroll_body(docks_overlay)
	var header := HBoxContainer.new()
	body.add_child(header)
	_back_button(header, _close_docks).grab_focus()
	var heading := _label(header, "Docks", 26)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var run: Dictionary = CampaignStore.run
	_label(header, "%d materials · %d sortie slots" % [run.materials, run.docks], 17).autowrap_mode = TextServer.AUTOWRAP_OFF
	if not message.is_empty(): _label(body, message).modulate = Color("#f0ca90")
	var actions := HFlowContainer.new()
	body.add_child(actions)
	if not run.ships.has(Content.CRAFTABLE) and Content.CRAFTABLE not in run.destroyed:
		var craft := _button(actions, "Craft Lamplighter · 6 materials", func(): _apply(CampaignStore.craft()))
		craft.disabled = not CampaignStore.can_craft()
	if run.docks == 2:
		var expand := _button(actions, "Expand to three docks · 6 materials", func(): _apply(CampaignStore.expand_docks()))
		expand.disabled = run.materials < CampaignStore.DOCK_PRICE
	var roster := HFlowContainer.new()
	roster.add_theme_constant_override("h_separation", 14)
	roster.add_theme_constant_override("v_separation", 14)
	body.add_child(roster)
	for id in run.ships: _dock_ship(roster, id)

func _dock_ship(parent: Control, id: String) -> void:
	var run: Dictionary = CampaignStore.run
	var owned: Dictionary = run.ships[id]
	var ship := _ship(id)
	var panel := _panel(parent)
	panel.custom_minimum_size.x = 325
	var visual := RigView.new()
	visual.custom_minimum_size.y = 140
	panel.add_child(visual)
	visual.configure_data(ship)
	var maximum := CampaignStore.dock_max(id)
	_label(panel, "%s · Level %d" % [ship.name, owned.level], 19)
	_label(panel, "%d / %d hull" % [owned.hull, maximum])
	if owned.hull == 0: _label(panel, "Disabled. Repair to return to service.")
	var repair := _button(panel, "Repair +4 hull · 1 material", _repair.bind(id))
	repair.disabled = run.materials < 1 or owned.hull >= maximum
	var level := int(owned.level) + 1
	if level > 3: return
	var branches: Array = ship.levels.two if level == 2 else ship.levels.three
	var blocked := ""
	if level == 3:
		blocked = ship.levels.two[Catalog.index_by_id(ship.levels.two, owned.level_2)].blocks
	var price: int = CampaignStore.UPGRADE_PRICES[level]
	for branch in branches:
		if branch.id == blocked: continue
		var upgrade := _button(panel, "%s · Level %d · %d materials" % [branch.get("name", branch.id), level, price], _upgrade.bind(id, branch.id))
		upgrade.disabled = run.materials < price
		upgrade.tooltip_text = Rules.rule_text(branch.rule, ship.name) + "\n" + Rules.rule_text(branch.passive, ship.name)

func _ship(id: String) -> Dictionary:
	var ships: Array = CampaignStore.run.content.ships
	return ships[Catalog.index_by_id(ships, id)]

func _repair(id: String) -> void:
	_apply(CampaignStore.repair(id))

func _upgrade(id: String, branch: String) -> void:
	_apply(CampaignStore.upgrade(id, branch))

func _apply(success: bool) -> void:
	message = "" if success else CampaignStore.last_error
	if is_instance_valid(docks_overlay):
		_render_docks()
	elif success:
		get_tree().reload_current_scene.call_deferred()
	else:
		_label(content, message).modulate = Color("#f0ca90")

func _open_sortie() -> void:
	if not CampaignStore.can_manage(): return
	_remember_map()
	get_tree().change_scene_to_file("res://scenes/campaign_sortie.tscn")

func _captain(id: String) -> Dictionary:
	return CampaignStore.run.content.captains[Catalog.index_by_id(CampaignStore.run.content.captains, id)]

func _panel(parent: Node) -> VBoxContainer:
	var frame := PanelContainer.new()
	parent.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	frame.add_child(box)
	return box

func _label(parent: Node, value: String, size_value: int = 15) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_value)
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 33
	button.pressed.connect(action)
	parent.add_child(button)
	return button
