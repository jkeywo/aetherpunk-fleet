extends "res://tests/support/v3_test.gd"
const AreaVfx = preload("res://scripts/visuals/area_attack_vfx.gd")
var styles: Array = []
func buttons(node: Node, label: String) -> Array:
	var found: Array = []
	if node is Button and node.text == label: found.append(node)
	for child in node.get_children(): found.append_array(buttons(child, label))
	return found
func encounter(effect: Dictionary) -> Dictionary:
	var doc := neutral(true)
	doc.setup.enemies = []
	for point in Geometry.POSITIONS: doc.setup.enemies.append({"enemy":"stormmaw", "position":point})
	card_def(doc,"brace").rules[0].effects = [effect]
	return doc
func beam(range_text: String = "Long", hits: int = 1) -> Dictionary:
	return {"kind":"beam", "damage":4, "hits":hits, "range":range_text}
func blast() -> Dictionary:
	return {"kind":"explosion", "target":"chosen_enemy", "range":"Long", "main_effects":[attack(6,1,"Long","area_target"), {"kind":"stun","target":"area_reaction"}], "adjacent_effects":[attack(2,1,"Long","area_target")]}
func losses(b) -> Array:
	return b.enemies.map(func(u): return u.max_hull-u.hull)
func _run() -> void:
	for origin in 4:
		var doc := encounter(beam())
		var b = State.new(2,doc)
		var old: int = b.formation.find(0)
		b.formation[old] = b.formation[origin]
		b.formation[origin] = 0
		var uid := uid_for(b,"brace")
		var rng_before: int = b.rng.state
		var preview: Dictionary = b.preview(uid,[],-1,-1,0)
		expect(preview.ok and losses(b)==[0,0,0,0] and b.rng.state==rng_before,"Beam preview mutated live state.")
		expect(b.play(uid,[],-1,-1,0)=="","Beam play failed.")
		var expected: Array = [4,0,0,4] if origin in [0,3] else ([0,4,0,0] if origin==1 else [0,0,4,0])
		expect(losses(b)==expected,"Beam hit wrong lane from " + str(origin))
		expect(b.feedback_events.filter(func(e):return e.kind=="area_attack").size()==1,"Beam did not group its visual.")
	var doc := encounter(beam("Short"))
	var b = State.new(2,doc)
	b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(losses(b)==[4,0,0,0],"Short beam hit Rear.")
	b = State.new(2,doc);b.formation=[-1,1,2,0]
	expect("Short" in b.validate(uid_for(b,"brace"),[],-1,-1,0),"Short beam allowed firing from Rear.")
	doc = encounter(beam("Long",2));b = State.new(2,doc)
	b.enemies[0].armour=1;b.enemies[3].armour=1;b.cover[4]=2;b.enemies[0].guard=1
	b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(losses(b)==[3,0,0,6] and b.cover[4]==0 and b.enemies[0].guard==0,"Beam multi-hit bypassed cover/armour/shields.")
	doc=encounter(beam());b=State.new(2,doc);b.enemy_formation[0]=-1
	b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(losses(b)==[0,0,0,4],"Empty Front stopped beam from reaching Rear.")
	# Movement resolves before the beam's lane is chosen.
	doc=encounter(beam());card_def(doc,"brace").rules[0].effects=[{"kind":"move","target":"owner","destination":"upper","guard":0},beam()]
	b=State.new(2,doc);b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(losses(b)==[0,4,0,0],"Beam used pre-movement lane.")
	# Blast primary effects are distinct from splash, and stun binds to the main enemy.
	doc=encounter(blast())
	doc.leviathans[0].stances[0].reactions=[{"id":"watch","name":"Watch","category":"Test","conditions":{"kind":"always"},"effects":[]}]
	b=State.new(2,doc)
	b.enemy_row=[0,3,6]
	b.stance_deck=b.stance_deck.filter(func(token):return not b.enemy_row.has(token))
	var before: int=b.rng.state
	var preview: Dictionary=b.preview(uid_for(b,"brace"),[],-1,-1,0,{"enemy":-1})
	expect(preview.ok and losses(b)==[0,0,0,0] and b.stunned.is_empty() and b.rng.state==before,"Explosion preview leaked damage/stun/RNG.")
	b.play(uid_for(b,"brace"),[],-1,-1,0,{"enemy":-1})
	expect(losses(b)==[6,2,2,0],"Front blast did not distinguish primary and adjacent targets.")
	expect(b.feedback_events.any(func(e):return e.kind=="stunned"),"Primary blast failed to stun its target reaction.")
	for event in b.feedback_events.filter(func(e):return e.kind=="reaction_triggered"):
		expect(event.presentation.owner!=-1,"Stunned main target reacted.")
	b=State.new(2,encounter(blast()));b.play(uid_for(b,"brace"),[],-1,-1,0,{"enemy":-2})
	expect(losses(b)==[2,6,0,2],"Upper blast crossed to nonadjacent Lower.")
	b=State.new(2,encounter(blast()));b.enemies[0].hull=1;b.play(uid_for(b,"brace"),[],-1,-1,0,{"enemy":-1})
	expect(b.enemies[0].hull==0 and b.enemies[1].hull==68 and b.enemies[2].hull==68,"Main target death cancelled splash.")
	# Delayed decisions suspend the area queue without losing bound targets.
	doc=encounter(blast());card_def(doc,"brace").rules[0].effects[0].main_effects.insert(0,{"kind":"discard","amount":1})
	b=State.new(2,doc);b.play(uid_for(b,"brace"),[],-1,-1,0,{"enemy":-1})
	expect(b.phase=="discard" and losses(b)==[0,0,0,0],"Explosion failed to suspend for discard.")
	b.discard_for_relay(b.hand[0])
	expect(b.phase=="fleet" and losses(b)==[6,2,2,0],"Explosion lost effects after discard.")
	# Enemy attacks use the same area primitives against the fleet diamond.
	doc=neutral();doc.leviathans[0].stances[0].effects=[beam()]
	b=State.new(2,doc);b.formation=[0,1,-1,2];b.end_phase()
	expect(b.ships[0].hull==16 and b.ships[1].hull==20 and b.ships[2].hull==6,"Enemy beams did not hit both fleet ends for all activations.")
	doc=neutral();var enemy_blast:=blast();enemy_blast.main_effects.resize(1);doc.leviathans[0].stances[0].effects=[enemy_blast]
	b=State.new(2,doc);b.formation=[0,1,2,-1];b.end_phase()
	expect(b.ships[0].hull==10 and b.ships[1].hull==14 and b.ships[2].hull==12,"Enemy explosions did not use separate main/splash effects.")
	doc=encounter(blast());card_def(doc,"brace").rules[0].effects[0].range="Short"
	b=State.new(2,doc);b.play(uid_for(b,"brace"),[],-1,-1,0,{"enemy":-2})
	expect(losses(b)==[2,6,0,0],"Short explosion affected Rear through splash.")
	# Limits remain one per physical card/action unless explicitly authored per hit.
	doc=encounter(beam("Long",2));doc.ships[0].resource.rules=[rule("on-hit","hit_resolved",[{"kind":"gain_resource","target":"owner","amount":1}],"owner","ship")]
	b=State.new(2,doc);b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(b.ships[0].resource==1,"Area hits multiplied once-per-action rules.")
	doc.ships[0].resource.rules[0].limit="once_per_hit"
	b=State.new(2,doc);b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(b.ships[0].resource==4,"Per-hit rules lost beam victims/hits.")
	doc=encounter(beam())
	card_def(doc,"brace").rules[1]=rule("follow-up","hit_resolved",[attack(1,1,"Long","event_target")],"owner")
	b=State.new(2,doc);b.play(uid_for(b,"brace"),[],-1,-1,0)
	var followups: Array=b.feedback_events.filter(func(event):return event.kind=="damage" and event.get("attack_style","")=="")
	expect(followups.size()==1,"Allied follow-up inherited the area visual and lost its projectile.")
	# Registry catches malformed child effects; generated forms expose both lists.
	var errors: Array=[]
	var invalid:=blast();invalid.adjacent_effects=[{"kind":"attack","damage":-1}]
	R.validate_spec("effect",invalid,"Blast",errors)
	expect(not errors.is_empty(),"Invalid nested blast effects escaped validation.")
	var text:=R.text("effect",blast())
	expect("main target" in text and "adjacent" in text and "Stun" in text,"Explosion rules text omitted a group.")
	var editor = preload("res://scripts/rules/spec_editor.gd").new()
	root.add_child(editor)
	var edited := blast()
	editor.configure("effect", edited)
	expect(buttons(editor,"Add effect").size()==2,"Explosion editor did not expose separate effect lists.")
	buttons(editor,"Add effect")[0].pressed.emit()
	expect(edited.main_effects.size()==3 and edited.adjacent_effects.size()==1,"Adding a main effect changed the splash list.")
	buttons(editor,"↓")[0].pressed.emit()
	expect(edited.main_effects[0].kind=="stun" and edited.main_effects[1].kind=="attack","Nested effect reordering failed to update backing data.")
	buttons(editor,"Remove")[0].pressed.emit()
	expect(edited.main_effects.size()==2 and edited.main_effects[0].kind=="attack","Nested effect removal failed.")
	editor.free()
	doc=encounter(blast());doc.leviathans[0].stances[0].effects=[{"kind":"explosion","main_effects":[{"kind":"discard","amount":1}]}]
	expect(not Catalog.validate(doc).is_empty(),"Nested effect bypassed enemy context restrictions.")
	# Real battle feedback uses one distinct area visual, then ordinary damage/defence popups.
	await open_battle(encounter(beam()));var view=current_scene
	view.feedback.area_attack_started.connect(func(style,_targets):styles.append(style))
	stage_card(view,"brace",0);await settle(view)
	expect(styles==["beam"],"Beam feedback did not use its dedicated visual.")
	await open_battle(encounter(blast()));view=current_scene
	view.feedback.area_attack_started.connect(func(style,_targets):styles.append(style))
	stage_card(view,"brace",0);view.enemies.widgets[0].pressed.emit();await settle(view)
	expect(styles==["beam","explosion"],"Explosion feedback did not use its dedicated visual.")
	expect(view.feedback.overlay.get_child_count()==1 and not view.busy,"Area effects leaked visuals or input locks.")
	done("Beam and explosion area effects")
