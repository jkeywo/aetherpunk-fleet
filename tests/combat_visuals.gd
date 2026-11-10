extends "res://tests/support/v3_test.gd"
const Feedback=preload("res://scripts/combat_feedback.gd")
var attacks: Array=[]
var moves: Array=[]
func _run() -> void:
	var doc:=neutral()
	card_def(doc,"brace").rules[1]=rule("chain","adjacent_card_played",[{"kind":"add_shields","target":"owner","amount":2}],"adjacent")
	card_def(doc,"broadside").cost=2
	card_def(doc,"broadside").rules[0].effects=[attack(4,2)]
	doc.ships[1].resource.rules=[rule("attack_charge","attack_started",[{"kind":"gain_resource","target":"owner","amount":1}],"owner","ship")]
	doc.leviathans[0].stances[0].reactions=[{"id":"counter","name":"Counter","category":"Retaliation","conditions":{"kind":"card_matches","target":"event_card","card_type":"Attack"},"effects":[attack(3,1,"Long","chosen_ally")]}]
	await open_battle(doc)
	var b=current_scene
	var source: int=uid_for(b.state,"brace")
	b.state.play(source,[],-1,-1,0);b._render();await flush()
	var action: int=uid_for(b.state,"broadside")
	var before:=JSON.stringify(b.state.board_snapshot())
	var rng: int=b.state.rng.state
	var hand: Array=b.state.hand.duplicate()
	var cues: Dictionary=b.state.trigger_preview(action,[],-1,-1,1,{"enemy":-1})
	expect(cues.reactions.size()==1 and cues.cards.has(source) and cues.ships.has(1),"Unpaid preview omitted reaction, allied chain or ship rule.")
	expect(cues.provisional,"Unpaid preview must be labelled provisional.")
	expect(JSON.stringify(b.state.board_snapshot())==before and b.state.rng.state==rng and b.state.hand==hand,"Trigger preview mutated live combat or RNG.")
	b._select(action);b.selected_slot=1;b._update_controls();await flush()
	expect(b.stance_panel.trigger_keys==cues.reactions and b.stance_panel.reaction_buttons[cues.reactions[0]].get_meta("trigger_preview"),"Selecting card did not highlight exact visible reaction.")
	expect("TRIGGER" in b.circle_view.buttons[0].text and b.allies.target_widget(1).trigger_badge.visible,"Allied trigger sources were not highlighted.")
	b.selected_slot=2;b._update_controls();await flush()
	expect(not "TRIGGER" in b.circle_view.buttons[0].text,"Changing circle adjacency retained stale trigger highlight.")
	b._cancel();await flush()
	expect(b.stance_panel.trigger_keys.is_empty() and not b.allies.target_widget(1).trigger_badge.visible,"Cancelling left predicted triggers highlighted.")
	# Only actual choices add payment-discard chains.
	card_def(doc,"patch").rules[1]=rule("fuel","discarded",[{"kind":"gain_resource","target":"owner","amount":1}],"self_card","any")
	var sim=State.new(1,doc)
	var paid: int=uid_for(sim,"patch")
	var unpaid_cues: Dictionary=sim.trigger_preview(uid_for(sim,"broadside"))
	var paid_cues: Dictionary=sim.trigger_preview(uid_for(sim,"broadside"),[paid])
	expect(not unpaid_cues.cards.has(paid) and paid_cues.cards.has(paid),"Preview invented or ignored a payment-discard trigger.")
	# Explicitly suppressing a visible reaction removes its predicted cue.
	var key: String=cues.reactions[0]
	b.state.stunned[key]=true
	expect(not b.state.trigger_preview(action,[],-1,-1,1,{"enemy":-1}).reactions.has(key),"Stunned reaction remained highlighted.")
	b.state.stunned.clear()
	b.state.ships[0].guard=5;b.state.cover[0]=4;b.state.cover[4]=3
	b._render();await flush()
	var cloud_position: Vector2=b.allies.cover_clouds[0].position
	expect(b.allies.target_widget(0).shield_fx.visible and not b.allies.target_widget(1).shield_fx.visible,"Shield field ignores actual shield count.")
	expect(b.allies.cover_clouds.has(0) and b.enemies.cover_clouds.has(0),"Cover clouds missing on one side.")
	expect(b.allies.cover_clouds[0].mouse_filter==Control.MOUSE_FILTER_IGNORE and b.allies.target_widget(0).shield_fx.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Defence visuals intercept targeting.")
	b.feedback.attack_started.connect(func(attacker,target):attacks.append([attacker,target]))
	b.feedback.movement_started.connect(func(paths):moves.append(paths))
	# Commit via the actual payment/target UI and count all friendly and enemy hits.
	b._stage_circle(action,1)
	await flush()
	while b.pending_play and b._payment_amount()<b._current_cost():
		var payer: int=b.state.hand.filter(func(uid):return uid!=action and not b.payment.has(uid))[0]
		await b._choose_card(payer)
		await flush()
	choose_first_targets(b);await settle(b)
	expect(attacks.size()==3 and attacks[0]==[1,-1] and attacks[2][0]<0,"Generic projectiles do not match multi-hit attacks and enemy reactions.")
	expect(b.state.monster_hull==65,"Visual attack feedback changed cover/armour/hull resolution.")
	# Opposite travel directions must bow onto opposite sides, with exact endpoints.
	var a:=Vector2(100,100);var z:=Vector2(260,210)
	expect(Feedback.arc_position(a,z,0).distance_to(a)<.001 and Feedback.arc_position(a,z,1).distance_to(z)<.001,"Movement arc misses endpoints.")
	expect(Feedback.arc_position(a,z,.5).distance_to(Feedback.arc_position(z,a,.5))>40,"Swapping arcs overlap at the midpoint.")
	all_in_hand(b.state);b._render();await flush()
	var card: int=b.state.hand.filter(func(uid):return b.state.card(uid).owner==1)[0]
	b.state.play_basic(card,0)
	await b._present_resolution();await flush()
	expect(moves.size()==1 and moves[0].size()==2 and moves[0].has(0) and moves[0].has(1),"Swap did not animate both ships.")
	expect(b.allies.cover_clouds[0].position==cloud_position and b.state.cover[0]==1,"Cover moved with the ship or changed during swap animation.")
	expect(b.feedback.overlay.get_child_count()==1 and not b.busy,"Transient attack/movement visuals leaked or left input locked.")
	var target_widget=b.allies.target_widget(0)
	var impact: Vector2=b.feedback._impact_point(target_widget,{"target":0,"shields_absorbed":1,"cover_absorbed":0,"board":b.state.board_snapshot()})
	expect(impact.x>target_widget.art.get_global_rect().get_center().x,"Shield absorption did not put the impact on the forward field.")
	b.state.ships[0].guard=0;b.state.cover[0]=0;b._render();await flush()
	expect(not b.allies.target_widget(0).shield_fx.visible and not b.allies.cover_clouds.has(0),"Depleted defences retained their visual effects.")
	# Drag-hovering a basic repair previews the actual repair resource loop and response.
	doc=neutral()
	doc.ships[0].resource.rules=[rule("repair_loop","repaired",[{"kind":"gain_resource","target":"owner","amount":1}],"owner","ship")]
	card_def(doc,"brace").rules[1]=rule("ending","turn_end",[{"kind":"gain_resource","target":"owner","amount":1}])
	doc.leviathans[0].stances[0].reactions=[{"id":"scent","name":"Aether Scent","category":"Retaliation","conditions":{"kind":"metric_at_least","metric":"healed","amount":1},"effects":[attack(1,1,"Long","chosen_ally")]}]
	await open_battle(doc);b=current_scene
	source=uid_for(b.state,"brace");b.state.play(source,[],-1,-1,0)
	all_in_hand(b.state);b.state.ships[0].hull-=3;b._render();await flush()
	var repair_card: int=b.state.hand.filter(func(uid):return b.state.card(uid).owner==0)[0]
	var payload: Dictionary=b._begin_card_drag(repair_card)
	b._drag_over_ship(0,payload)
	expect(b.stance_panel.trigger_keys.size()==1 and b.allies.target_widget(0).trigger_badge.visible,"Basic repair hover did not highlight its reaction/resource trigger.")
	expect(b.state.ships[0].hull==25 and b.state.ships[0].resource==0,"Hovering basic repair committed its effects.")
	b._drag_leave_ship(0)
	expect(b.stance_panel.trigger_keys.is_empty(),"Leaving basic target retained stale trigger cues.")
	b._finish_card_drag()
	b.get_node("%EndPhaseButton").mouse_entered.emit()
	expect("TRIGGER" in b.circle_view.buttons[0].text,"End-phase hover omitted a turn-end card trigger.")
	b.get_node("%EndPhaseButton").mouse_exited.emit()
	expect(not "TRIGGER" in b.circle_view.buttons[0].text,"End-phase trigger cue did not reset.")
	expect(b.state.ships[0].resource==0 and b.state.round_number==1,"End-phase hover advanced combat.")
	done("Trigger previews, attacks and defence visuals")
