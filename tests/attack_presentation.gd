extends "res://tests/support/v3_test.gd"
const Schema = preload("res://scripts/visuals/rig_schema.gd")
const Art = preload("res://scripts/art_assets.gd")
const RigView = preload("res://scripts/rig_view.gd")
const Editor = preload("res://scripts/visuals/rig_editor.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")
var melee_origins: Array = []
var contacts: Array = []
var returns: Array = []
var paths: Dictionary = {}
var observed_view
func _melee_started(actor: int, target: int, path: Dictionary) -> void:
	melee_origins.append(actor)
	paths[actor] = path
	var source = observed_view.feedback._unit(actor)
	expect(source.art.modulate.a==0,"Melee left duplicate artwork in its formation slot.")
	var ghost = observed_view.feedback.overlay.get_children().filter(func(node):return node.has_meta("melee_actor"))[0]
	expect(ghost.position.distance_to(path.from)<.01,"Swoop started away from its source.")
func _melee_impact(actor: int, target: int) -> void:
	contacts.append(actor)
	var ghost = observed_view.feedback.overlay.get_children().filter(func(node):return node.has_meta("melee_actor"))[0]
	expect(ghost.marker_global("attack").distance_to(paths[actor].impact)<.01,"Melee attack marker missed its contact point.")
func _melee_returned(actor: int, target: int) -> void:
	returns.append(actor)
	expect(observed_view.feedback._unit(actor).art.modulate.a==1,"Attacker was not restored on return.")
	expect(observed_view.feedback.overlay.get_children().all(func(node):return not node.has_meta("melee_actor")),"Swoop ghost survived its return.")
func _run() -> void:
	for rig in Schema.templates():
		expect(Schema.validate(rig).is_empty() and rig.markers.any(func(marker):return marker.id=="attack"),"Shipped unit has no valid attack marker.")
	var definition: Dictionary=Schema.editable(Art.rig("bastion"),"test")
	var visual=RigView.new();root.add_child(visual);visual.position=Vector2(70,40);visual.size=Vector2(240,160);visual.configure_definition(definition)
	var marker: Dictionary=definition.markers[0]
	visual.set_process(false);visual.rig_node.elapsed=3.5
	var part: Dictionary=visual.rig_node.part_definitions()[marker.part]
	var expected: Vector2=visual.rig_node.to_global(visual.rig_node.poses(3.5)[marker.part]*visual.rig_node._uv(part,marker.uv))
	expect(visual.marker_global("attack").distance_to(expected)<.001,"Attack marker did not follow animated/scaled part transforms.")
	definition.parts[0].flip_x=true;visual.configure_definition(definition);visual.rig_node.elapsed=3.5
	expected=visual.rig_node.to_global(visual.rig_node.poses(3.5)[marker.part]*visual.rig_node._uv(part,marker.uv))
	expect(visual.marker_global("attack").distance_to(expected)<.001,"Marker did not follow a flipped sprite.")
	var invalid:=definition.duplicate(true);invalid.markers[0].part="missing"
	expect(not Schema.validate(invalid).is_empty(),"Missing marker part accepted.")
	invalid=definition.duplicate(true);invalid.markers.append(invalid.markers[0].duplicate(true))
	expect(not Schema.validate(invalid).is_empty(),"Duplicate marker IDs accepted.")
	invalid=definition.duplicate(true);invalid.markers[0].uv=[2,0]
	expect(not Schema.validate(invalid).is_empty(),"Out-of-bounds marker accepted.")
	var legacy:=definition.duplicate(true);legacy.erase("markers");visual.configure_definition(legacy)
	expect(visual.marker_global("attack").is_finite(),"Legacy rig without markers has no safe origin.")
	visual.free()
	var editor=Editor.new();root.add_child(editor);editor.configure(Art.rig("bastion"),"bastion","Bastion")
	editor.popup_centered(Vector2i(1180,740));await flush()
	expect(editor.get_ok_button().get_global_rect().end.y<=editor.size.y and editor.fields.has("marker_attack0"),"Marker controls or Apply button are inaccessible.")
	editor.add_marker()
	var id: String=editor.draft.markers.back().id
	expect(id=="attack_2" and editor.preview.marker_mode,"Adding a marker did not select its drag mode.")
	var bound: Dictionary=editor.preview.rig.part_definitions()[editor.draft.markers.back().part]
	var point: Vector2=editor.preview.origin+editor.preview.rig.poses(editor.preview.time)[bound.id]*editor.preview.rig._uv(bound,[.7,.3])*editor.preview.zoom
	editor.preview._update_point(point)
	expect(Vector2(editor.draft.markers.back().uv[0],editor.draft.markers.back().uv[1]).distance_to(Vector2(.7,.3))<.001,"Dragging a marker did not update its part-local socket.")
	editor.selected_id=bound.id;editor.remove_part()
	expect("marker" in editor.status.text,"Referenced marker did not block part deletion.")
	var doc:=neutral();doc.ships[0].visual_rig=editor.draft.duplicate(true)
	var effect:=attack(4);effect.presentation="melee";effect.origin_marker="attack_2";card_def(doc,"brace").rules[0].effects=[effect]
	var file:="user://attack_presentation_roundtrip.json"
	expect(Catalog.save_document(file,doc)=="","Attack markers/presentation could not be saved.")
	var loaded:=Catalog.read_document(file)
	expect(loaded.ok and same(loaded.document.ships[0].visual_rig.markers,doc.ships[0].visual_rig.markers) and card_def(loaded.document,"brace").rules[0].effects[0].presentation=="melee","Attack presentation lost its save/reload data.")
	editor.free()
	# Styles change presentation only: identical damage, targeting, RNG and previews.
	for style in ["auto","ranged","beam","explosion","melee"]:
		doc=neutral();effect=attack(4);effect.presentation=style;effect.origin_marker="attack";card_def(doc,"brace").rules[0].effects=[effect]
		var b=State.new(4,doc);var uid:=uid_for(b,"brace");var seed: int=b.rng.state
		var preview: Dictionary=b.preview(uid,[],-1,-1,0)
		expect(preview.ok and b.rng.state==seed and b.monster_hull==70,"Attack styling changed preview isolation.")
		b.play(uid,[],-1,-1,0)
		var hit: Dictionary=b.feedback_events.filter(func(event):return event.kind=="damage")[0]
		expect(b.monster_hull==66 and hit.presentation==("ranged" if style=="auto" else style) and hit.origin_marker=="attack","Style changed damage or failed to reach feedback: "+style)
	for style in ["ranged","beam","explosion","melee"]:
		doc=neutral();effect=attack(3,1,"Long","chosen_ally");effect.presentation=style
		doc.leviathans[0].stances[0].effects=[effect]
		var b=State.new(4,doc);b.end_phase()
		var attacks: Array=b.feedback_events.filter(func(event):return event.kind=="damage")
		expect(attacks.size()==3 and attacks.all(func(event):return event.presentation==style) and b.ships[0].hull==19,"Enemy attack ignored its explicit presentation or changed damage: "+style)
	# Real resolution contains both a player ram and an automatically melee monster response.
	doc=neutral();effect=attack(4);effect.presentation="melee";card_def(doc,"brace").rules[0].effects=[effect]
	doc.leviathans[0].stances[0].reactions=[{"id":"bite","name":"Bite","category":"Retaliation","conditions":{"kind":"always"},"effects":[attack(3,1,"Long","chosen_ally")]}]
	await open_battle(doc);observed_view=current_scene
	observed_view.feedback.duration_scale=.15
	observed_view.feedback.melee_started.connect(_melee_started)
	observed_view.feedback.melee_impacted.connect(_melee_impact)
	observed_view.feedback.melee_finished.connect(_melee_returned)
	var formation_before: Array=observed_view.state.formation.duplicate()
	stage_card(observed_view,"brace",0);await settle(observed_view)
	expect(melee_origins==[0,-1] and contacts==melee_origins and returns==melee_origins,"Player ram/monster swoop did not strike and return in order.")
	expect(observed_view.state.formation==formation_before and observed_view.state.monster_hull==66 and observed_view.state.ships[0].hull==25,"Swoop altered formation or damage.")
	expect(observed_view.feedback.overlay.get_child_count()==1 and not observed_view.busy,"Melee presentation leaked visuals or locked input.")
	var from:=Vector2(1200,200);var to:=Vector2(200,230)
	expect(Feedback.swoop_position(from,to,0)==from and Feedback.swoop_position(from,to,1).distance_to(to)<.001 and Feedback.swoop_position(from,to,.5).distance_to(from.lerp(to,.5))>50,"Swoop curve/endpoints are incorrect.")
	# A ranged visual actually launches from a named marker rather than artwork centre.
	var view=observed_view
	view.feedback.duration_scale=1
	var source=view.feedback._unit(0)
	var origin: Vector2=source.art.marker_global("attack")
	view.feedback._projectile_effect({"attacker":0,"target":-1,"origin_marker":"attack","board":view.state.board_snapshot()})
	var particles: Array=view.feedback.overlay.get_children().filter(func(node):return node.has_meta("attack_vfx"))
	expect(particles.size()==1 and particles[0].start.distance_to(origin)<.001,"Ranged PFX did not originate at the attack marker.")
	await create_timer(.35).timeout
	done("Attack markers and configurable melee/ranged presentations")

func same(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index in a.size():
			if not same(a[index],b[index]):return false
		return true
	return a==b
