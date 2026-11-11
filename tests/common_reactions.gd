extends "res://tests/support/v3_test.gd"
const Badge=preload("res://scripts/reaction_badge.gd")
const Icons=preload("res://scripts/keyword_icons.gd")
func condition(family: String, value: String = "") -> Dictionary:
	var result: Dictionary={"kind":"reaction_trigger","family":family}
	if family=="card_type":result.card_type=value
	if family=="position":result.position=value
	return result
func doc_with(spec: Dictionary) -> Dictionary:
	var doc:=neutral()
	doc.leviathans[0].stances[0].reactions=[{"id":"common","name":"Common reaction","category":"Retaliation","conditions":spec,"effects":[]}]
	return doc
func reacted(b) -> bool:return b.feedback_events.any(func(event):return event.kind=="reaction_triggered")
func portraits(node: Node) -> Array:
	var result: Array=[]
	if node.has_meta("owner_portrait"):result.append(node)
	for child in node.get_children():result.append_array(portraits(child))
	return result
func select_option(menu: OptionButton, value: String) -> void:
	for index in menu.item_count:
		if menu.get_item_metadata(index)==value:menu.select(index);menu.item_selected.emit(index);return
func _run() -> void:
	for type in R.TYPES:
		var doc:=doc_with(condition("card_type",type))
		var design: Dictionary=card_def(doc,"brace")
		design.type=type
		var b=State.new(3,doc)
		expect(b.play(uid_for(b,"brace"),[],-1,-1,0)=="" and reacted(b),"Played card type does not trigger: "+type)
		var badge:=Badge.new();root.add_child(badge);badge.configure(condition("card_type",type))
		expect(badge.glyph==Icons.texture(type.to_lower()) and badge.border!=null,"Type trigger replaced the existing card-type symbol.")
		badge.free()
	var doc:=doc_with(condition("card_type","Attack"))
	card_def(doc,"brace").cost=1
	var b=State.new(3,doc)
	expect(b.play(uid_for(b,"brace"),[uid_for(b,"broadside")],-1,-1,0)=="" and not reacted(b),"Discarded Attack counted as played Attack.")
	for point in 4:
		var family_position: String="front" if point==0 else ("rear" if point==3 else ("upper" if point==1 else "lower"))
		doc=doc_with(condition("position",family_position))
		b=State.new(3,doc)
		b.formation.erase(0);b.formation.insert(point,0)
		expect(b.play(uid_for(b,"brace"),[],-1,-1,0)=="" and reacted(b),"Origin position not recognized: "+str(point))
	doc=doc_with(condition("position","front"))
	card_def(doc,"brace").rules[0].effects=[{"kind":"move","target":"owner","destination":"lower","guard":0}]
	b=State.new(3,doc)
	expect(b.play(uid_for(b,"brace"),[],-1,-1,0)=="" and reacted(b) and b.position_of(0)==2,"Position trigger used final rank rather than card origin.")
	doc=doc_with(condition("damaged"));card_def(doc,"broadside").rules[0].effects=[attack(1)]
	b=State.new(3,doc)
	var before_rng: int=b.rng.state
	var before_state:=JSON.stringify(b.board_snapshot())
	expect(b.preview(uid_for(b,"broadside"),[],-1,-1,0).ok and before_state==JSON.stringify(b.board_snapshot()) and before_rng==b.rng.state,"Common trigger preview mutated live state/RNG.")
	expect(b.play(uid_for(b,"broadside"),[],-1,-1,0)=="" and reacted(b),"One actual hull damage did not trigger monster damaged.")
	b=State.new(3,doc);b.enemies[0].guard=20
	expect(b.play(uid_for(b,"broadside"),[],-1,-1,0)=="" and not reacted(b),"Fully shielded hit triggered hull-damaged reaction.")
	# Damage to another monster must not satisfy this monster's trigger.
	var multi:=neutral(true)
	multi.leviathans[0].stances[0].reactions=[{"id":"common","name":"Common","category":"Retaliation","conditions":condition("damaged"),"effects":[]}]
	card_def(multi,"broadside").rules[0].effects=[attack(1)]
	b=State.new(3,multi)
	b.enemy_row=range(b.stance_cards.size()).filter(func(uid):return b.stance_cards[uid].owner==-1).slice(0,3)
	b.play(uid_for(b,"broadside"),[],-1,-1,0,{"enemy":-2})
	expect(not reacted(b),"Other monster's damage triggered this monster's reaction.")
	doc=doc_with(condition("healed"))
	b=State.new(3,doc);b.ships[0].hull-=2
	expect(b.play_basic(uid_for(b,"brace"),0)=="" and reacted(b),"Basic repair did not trigger actual player healing.")
	b=State.new(3,doc)
	card_def(doc,"brace").rules[0].effects=[{"kind":"repair","target":"owner","amount":2}]
	b=State.new(3,doc)
	expect(b.play(uid_for(b,"brace"),[],-1,-1,0)=="" and not reacted(b),"Overhealing full hull triggered On heal.")
	doc=doc_with(condition("card_type","Support"));b=State.new(3,doc);b.ships[0].hull-=2
	expect(b.play_basic(uid_for(b,"brace"),0)=="" and not reacted(b),"Basic repair counted as playing Support.")
	doc=doc_with(condition("position","front"));b=State.new(3,doc)
	expect(b.play_basic(uid_for(b,"brace"),1)=="" and not reacted(b),"Basic swap counted as playing a card from Front.")
	var shipped: Dictionary=Catalog.read_document("res://data/content.json").document
	for enemy in shipped.leviathans:
		for stance in enemy.stances:
			for reaction in stance.reactions:expect(reaction.conditions.kind=="reaction_trigger","Shipped enemy retained complex trigger.")
	await open_battle(shipped)
	var battle=current_scene
	expect(battle.stance_panel.buttons.all(func(button):return button.get_meta("stance_uid",-1)<0 or not button.tooltip_text.is_empty()),"Reaction icon hover lacks its full explanation.")
	var badges: Array=[]
	for react in battle.stance_panel.reaction_buttons.values():
		for child in react.get_children():
			if child is Badge:badges.append(child)
	expect(not badges.is_empty() and badges.all(func(badge):return badge.glyph!=null and badge.border!=null),"Live reaction row missing generated glyphs/shared frame.")
	var owner_images:=portraits(battle.stance_panel)
	expect(owner_images.size()==battle.state.enemy_row.size() and owner_images.all(func(p):return not p.definition.is_empty() and p.definition==preload("res://scripts/art_assets.gd").visual_rig(battle.state.unit(p.get_meta("owner_portrait")),true)),"Reaction cards do not show their actual owner monster artwork.")
	for position in ["front","upper","lower","rear"]:
		var composite:=preload("res://scripts/monster_portrait.gd").new()
		root.add_child(composite)
		composite.configure(battle.state._enemy_visual(-1),condition("position",position),Vector2(140,68))
		await flush()
		expect(composite.position_glyph!=null and composite.rig.rig_node!=null and composite.rig.rig_node.scale.x>0,"Position marker lost its actual monster image before layout.")
		composite.free()
	change_scene_to_file("res://scenes/editor.tscn")
	await scene_changed
	var editor=current_scene
	editor.tabs.current_tab=0
	editor.selected_ids.leviathans=editor.draft.leviathans[0].id
	editor.editing_stance=editor.draft.leviathans[0].stances[0].id
	editor._refresh()
	await flush()
	var r: Dictionary=editor.selected_entry().stances[0].reactions[0]
	var family_menu: OptionButton=editor.fields["reaction_trigger_"+r.id]
	expect(family_menu.item_count==5,"Enemy editor lacks the four common families plus Custom.")
	select_option(family_menu,"position")
	await flush()
	expect(r.conditions.family=="position" and editor.fields.has("reaction_position_"+r.id) and not editor.fields.has("reaction_type_"+r.id),"Position trigger exposes incorrect editor parameters.")
	select_option(editor.fields["reaction_position_"+r.id],"upper")
	await flush()
	expect(r.conditions.position=="upper", "Position editor choice does not reach authored data.")
	select_option(editor.fields["reaction_trigger_"+r.id],"damaged")
	await flush()
	expect(r.conditions.family=="damaged" and not editor.fields.has("reaction_position_"+r.id) and not editor.fields.has("reaction_type_"+r.id) and Catalog.validate(editor.draft).is_empty(),"Damage trigger still requires a threshold or saves invalid data.")
	select_option(editor.fields["reaction_trigger_"+r.id],"custom")
	await flush()
	expect(r.get("custom_trigger",false) and r.conditions.kind=="reaction_trigger" and r.conditions.family=="damaged","Custom trigger mode did not preserve the original condition for editing.")
	var custom_forms: Array=editor.forms.leviathans.find_children("*","VBoxContainer",true,false).filter(func(node):return node.has_meta("custom_reaction"))
	expect(custom_forms.size()==1,"Custom trigger has no editable legacy condition tree.")
	var custom: Dictionary={"kind":"all","items":[{"kind":"card_matches","target":"event_card","card_type":"Attack"},{"kind":"metric_at_least","metric":"hull_damage","amount":8}]}
	r.conditions=custom
	editor._rebuild_form();editor._live_preview()
	await flush()
	expect(r.conditions==custom and Catalog.validate(editor.draft).is_empty(),"Custom compound trigger was lost or rejected.")
	var preview_rows: Array=editor.preview_form.find_children("*","Button",true,false).filter(func(button):return button.tooltip_text.contains("hull damage"))
	expect(not preview_rows.is_empty() and preview_rows.any(func(button):return "8" in button.text),"Custom reactions did not retain the old readable text layout.")
	done("Common reaction families and badges")
