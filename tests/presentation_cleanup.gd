extends "res://tests/support/v3_test.gd"
const Icons=preload("res://scripts/keyword_icons.gd")
const Pile=preload("res://scripts/card_pile.gd")
func effects(card: Dictionary) -> int:
	var count:=0
	for rule in card.rules:count+=rule.effects.size()+rule.modifiers.size()
	return count
func _run() -> void:
	root.size=Vector2i(1280,800)
	var doc: Dictionary=Catalog.read_document("res://data/content.json").document
	for ship in doc.ships:
		expect(ship.starter!=ship.starter_two and effects(card_def(doc,ship.starter))==1 and effects(card_def(doc,ship.starter_two))==2,"Starter designs need one and two effects.")
		expect(Catalog.references(doc,"cards",ship.starter_two).any(func(line):return "second starter" in line),"Second starter deletion is not blocked.")
	var level_one:=doc.duplicate(true)
	for slot in level_one.setup.fleet:slot.level=1;Catalog.repair_fleet_branch(slot,ship_def(level_one,slot.ship))
	level_one.setup.fixed_hand=false
	var compiled:=Catalog.compile(level_one)
	expect(compiled.deck_keys.size()==18,"Level-one fleet needs four ship cards plus two captain cards per ship.")
	for ship in compiled.ships:
		expect(ship.loadout.size()==3 and ship.loadout.all(func(pair):return pair.count==2),"Level-one pair counts incorrect.")
	var invalid:=doc.duplicate(true);invalid.ships[0].starter_two=invalid.ships[1].starter
	expect(not Catalog.validate(invalid).is_empty(),"Starter owned by another ship was accepted.")
	invalid=doc.duplicate(true);invalid.ships[0].starter_two=invalid.ships[0].starter
	expect(not Catalog.validate(invalid).is_empty(),"Identical starter designs accepted.")
	var store=root.get_node("ContentStore")
	store.saved=doc.duplicate(true)
	change_scene_to_file("res://scenes/fleet_preparation.tscn")
	await scene_changed
	await flush()
	var prep=current_scene
	expect(prep.controls.size()==3 and prep.controls.has("level_0") and not prep.controls.has("ship_0") and not prep.controls.has("captain_0") and not prep.controls.has("position_0"),"Redundant assignment menus remain.")
	expect(not prep.inspector.is_visible_in_tree() and not prep.deck_preview.is_visible_in_tree(),"Details or card row still visible on main preparation screen.")
	expect(prep.ship_bank.get_children().any(func(child):return child.text=="Compare Airships") and prep.captain_bank.get_children().any(func(child):return child.text=="Compare Captains"),"Comparison buttons are not beside drag sources.")
	var info=prep.formation.target_widget(1).get_children().filter(func(child):return child.get_meta("ship_info",-1)==1)[0]
	var info_point: Vector2=info.get_global_transform_with_canvas()*(info.size/2)
	await mouse(info_point,true);await mouse(info_point,false);await flush()
	expect(prep.ship_info_dialog.visible and prep.selected_ship==1 and prep.inspector.is_visible_in_tree() and prep.deck_preview.is_visible_in_tree(),"Ship i button did not open its own details/cards.")
	expect(prep.deck_cards.get_child_count()==4 and "8 cards" in prep.deck_summary.text,"Details popup omitted second starter pair.")
	# Upgrade comparisons must remain usable when opened from the details popup.
	prep._show_upgrades("two");await flush()
	expect(prep.upgrade_dialog.visible,"Branch comparison cannot open over details.")
	prep.upgrade_dialog.hide();prep.ship_info_dialog.hide()
	await open_battle(doc)
	var b=current_scene
	b.feedback.duration_scale=.01
	for side in [b.allies,b.enemies]:
		for widget in side.widgets.values():
			if not widget.has_meta("ship_index"):continue
			expect(widget.get_theme_stylebox("normal").border_width_left==0,"Resting unit still has a border.")
			expect(widget.hull_label.get_parent()==widget.bar and widget.hull_label.text=="%d / %d"%[widget.bar.value,widget.bar.max_value],"Health value is not inside its bar.")
			expect(not widget.guard_label.visible and not "Armour" in widget.guard_label.text and not "Weapon" in widget.guard_label.text,"Zero shields or equipment stats clutter unit.")
			expect(widget.size.x>=140 and widget.art.custom_minimum_size.y>36,"Unit art has not grown.")
	var unit=b.allies.target_widget(0)
	var tooltip=unit._make_custom_tooltip(unit.tooltip_text)
	var rich=tooltip.get_child(0).get_child(0)
	expect(rich.icon_keys.has("armour") and rich.icon_keys.has("weapon"),"Equipment tooltip is missing icons.")
	tooltip.free()
	b.state.ships[0].guard=4;b._render();await flush()
	expect(b.allies.target_widget(0).guard_label.visible and "4" in b.allies.target_widget(0).guard_label.text,"Positive shields disappeared.")
	b.state.ships[0].guard=0;b._render();await flush()
	expect(not b.allies.target_widget(0).guard_label.visible,"Shields remain after being depleted.")
	expect(b.get_node("%DeckPile").get_script()==Pile and preload("res://scripts/art_assets.gd").texture("ui/card-back.png")!=null,"Draw pile does not use generated card art.")
	var uid: int=b.state.hand[0]
	b.state.hand.erase(uid);b.state.discard.append(uid);b._render();await flush()
	expect(b.get_node("%DiscardPile").face.info.name==b.state.card(uid).name and b.discard_count_label.text=="1","Discard pile does not show actual top card/count.")
	var pile_point: Vector2=b.get_node("%DiscardPile").get_global_rect().get_center()
	await mouse(pile_point,true);await mouse(pile_point,false);await flush()
	expect(b.discard_dialog.visible,"Native click on the discard card face did not open its ordered pile viewer.")
	b.discard_dialog.hide()
	var condition:={"kind":"card_matches","target":"event_card","card_type":"Attack"}
	expect(R.reaction_condition_text(condition)=="On played Attack","Reaction condition wording is incorrect.")
	# Mandatory discards and mana payment are choices; normal hand cards are not discard targets.
	expect(b.hand_view.get_children().all(func(card):return not card.discard_choice),"Idle hand glows as discard choices.")
	b.state.effect_discard({"amount":1},{"owner":0,"uid":-1,"event":{},"ancestry":[]});b._render();await flush()
	expect(b.hand_view.get_children().all(func(card):return card.discard_choice),"Mandatory discard did not highlight the hand red.")
	var reject: int=b.state.hand[0]
	await b._choose_card(reject);await settle(b)
	expect(b.state.discard.back()==reject and b.hand_view.get_children().all(func(card):return not card.discard_choice),"Discard choice did not resolve and clear glow.")
	var brace: int=uid_for(b.state,"brace")
	if brace<0:brace=b.state.hand.filter(func(id):return b.state.card(id).cost>0)[0]
	b._stage_circle(brace,b.state.first_slot());await flush()
	expect(b.hand_view.get_children().all(func(card):return card.discard_choice),"Payment choices are missing red glow.")
	b._cancel();await flush()
	expect(b.hand_view.get_children().all(func(card):return not card.discard_choice),"Cancelling payment left discard glow.")
	var sim=State.new(5,level_one)
	sim.end_phase()
	var retained: Array=sim.hand.duplicate()
	expect(sim.refresh([retained[0]])!="" and sim.hand==retained and sim.phase=="refresh","Voluntary discard bypassed state validation.")
	expect(sim.refresh([])=="" and retained.all(func(id):return sim.hand.has(id)),"Automatic refill discarded retained hand cards.")
	change_scene_to_file("res://scenes/editor.tscn")
	await scene_changed
	var editor=current_scene
	editor.tabs.current_tab=1;await flush()
	editor._duplicate_entry("ships")
	var authored: Dictionary=editor.selected_entry()
	expect(Catalog.validate(editor.draft).is_empty() and card_def(editor.draft,authored.starter_two).owner==authored.id,"Duplicated ship did not remap its second starter.")
	editor._new_entry("ships")
	authored=editor.selected_entry()
	expect(effects(card_def(editor.draft,authored.starter))==1 and effects(card_def(editor.draft,authored.starter_two))==2,"New ship lacks simple and compound starter designs.")
	done("Preparation and combat presentation")
