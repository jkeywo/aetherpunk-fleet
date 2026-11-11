extends "res://tests/support/v3_test.gd"
func bench(bank: Node, key: String, id: String) -> Control:
	for frame in bank.get_children():
		if frame.get_meta(key,"") == id: return frame
	return null
func drag(from_control: Control, destination: Control) -> void:
	var from: Vector2=from_control.get_global_transform_with_canvas()*Vector2(20,20)
	await motion(from);await mouse(from,true)
	await motion(from+Vector2(-65,-50),true)
	expect(root.gui_is_dragging(),"Native framed slot drag did not start.")
	var prep = current_scene
	if destination == prep.unassign_ship_slot:
		expect(prep.unassign_ship_slot.visible and not prep.unassign_captain_slot.visible,"Dragging an assigned ship should show only Unassign airship.")
	elif destination == prep.unassign_captain_slot:
		expect(prep.unassign_captain_slot.visible and not prep.unassign_ship_slot.visible,"Dragging an assigned captain should show only Unassign captain.")
	elif from_control.get_parent() in [prep.ship_bank, prep.captain_bank]:
		expect(not prep.unassign_ship_slot.visible and not prep.unassign_captain_slot.visible,"Dragging from the available roster showed an unassign slot.")
	var point: Vector2=destination.get_global_transform_with_canvas()*(destination.size/2)
	await motion(point,true);await mouse(point,false);await flush()
	expect(not prep.unassign_ship_slot.visible and not prep.unassign_captain_slot.visible,"An unassign slot remained visible after the drop.")
func click(control: Control) -> void:
	var point: Vector2=control.get_global_transform_with_canvas()*(control.size/2)
	await motion(point);await mouse(point,true);await mouse(point,false);await flush()
func visible_text(node: Node) -> String:
	var text := ""
	if (node is Label or node is Button) and node.is_visible_in_tree(): text = node.text + "\n"
	for child in node.get_children(): text += visible_text(child)
	return text
func _run() -> void:
	root.size=Vector2i(1280,800)
	var store_node=root.get_node("ContentStore")
	store_node.saved=fixture.duplicate(true)
	var saved:=JSON.stringify(store_node.saved)
	var hash_before:=FileAccess.get_sha256("res://data/content.json")
	change_scene_to_file("res://scenes/fleet_preparation.tscn")
	await scene_changed
	await flush()
	var prep=current_scene
	expect(not prep.unassign_ship_slot.visible and not prep.unassign_captain_slot.visible,"Unassign slots were visible before any drag.")
	expect(prep.ship_bank.get_child_count()==1 and prep.captain_bank.get_child_count()==1,"Assigned ships/captains still appear in available rows.")
	expect(not prep.unassign_ship_slot is Button and not prep.unassign_captain_slot is Button,"Available rows still use command buttons.")
	var badge: Control=prep.formation.target_widget(0).get_meta("captain_badge")
	expect(badge is PanelContainer and badge.name_label.text=="Iona Vale" and badge.subtitle_label.text=="Tier 1","Captain does not have a framed, two-line layout.")
	expect(badge.information.get_theme_stylebox("normal") is StyleBoxFlat and badge.information.get_theme_stylebox("normal").corner_radius_top_left>=26,"Info button retained ornate button art.")
	await click(badge.information)
	expect(prep.captain_info_dialog.visible and "Captain details" in prep.captain_info_dialog.title,"Captain's own info button did not open details.")
	prep.captain_info_dialog.hide()
	expect("Encounter:" not in visible_text(prep) and "opening" not in visible_text(prep).to_lower() and "hull" not in prep.status.text.to_lower() and "opening" not in prep.status.text.to_lower(),"Removed encounter/opening/hull clutter remains.")
	expect(prep.find_child("BackButton",true,false).text=="Back" and prep.find_child("BackButton",true,false).icon!=null,"Back arrow button missing.")
	await drag(badge,prep.unassign_captain_slot)
	expect(prep.draft.setup.fleet[0].captain=="" and prep.launch_button.disabled and bench(prep.captain_bank,"captain_id","iona")!=null,"Unassign captain did not bench it and block incomplete launch.")
	expect(prep.formation.target_widget(0).get_meta("captain_badge").label_text=="No captain","Empty captain target not rendered.")
	await drag(bench(prep.captain_bank,"captain_id","iona"),prep.formation.target_widget(0))
	expect(prep.draft.setup.fleet[0].captain=="iona" and not prep.launch_button.disabled and bench(prep.captain_bank,"captain_id","iona")==null,"Benched captain could not be reassigned.")
	await drag(prep.formation.target_widget(0),prep.unassign_ship_slot)
	expect(prep.draft.setup.fleet[0].ship=="" and prep.draft.setup.fleet[0].captain=="" and prep.launch_button.disabled,"Unassign ship did not free both ship and captain.")
	expect(bench(prep.ship_bank,"ship_id","bastion")!=null and bench(prep.captain_bank,"captain_id","iona")!=null,"Freed ship/captain missing from available slots.")
	var point: int=Geometry.POSITIONS.find(prep.draft.setup.fleet[0].position)
	await drag(bench(prep.ship_bank,"ship_id","bastion"),prep.formation.widgets[point])
	expect(prep.draft.setup.fleet[0].ship=="bastion" and prep.draft.setup.fleet[0].captain=="" and prep.launch_button.disabled,"Available ship could not occupy empty position independently of captain.")
	await drag(bench(prep.captain_bank,"captain_id","iona"),prep.formation.target_widget(0))
	expect(Catalog.validate(prep._candidate()).is_empty() and not prep.launch_button.disabled,"Reassembled fleet is not valid.")
	# Moving an assigned captain into a vacancy leaves its old ship vacant.
	await drag(prep.formation.target_widget(0).get_meta("captain_badge"),prep.unassign_captain_slot)
	await drag(prep.formation.target_widget(1).get_meta("captain_badge"),prep.formation.target_widget(0))
	expect(prep.draft.setup.fleet[0].captain=="rook" and prep.draft.setup.fleet[1].captain=="","Moving into vacant captain target invented a replacement captain.")
	await drag(bench(prep.captain_bank,"captain_id","iona"),prep.formation.target_widget(1))
	expect(not prep.launch_button.disabled,"Completing moved captain assignments did not enable launch.")
	prep._unassign({"kind":"ship","ship":"bastion","preparation":prep.get_instance_id()},"ship")
	var partial: Array=prep.draft.setup.fleet.duplicate(true)
	prep._back();await scene_changed
	current_scene.get_node("%PrimaryButton").pressed.emit();await scene_changed
	prep=current_scene
	expect(prep.draft.setup.fleet==partial and prep.launch_button.disabled,"Returning to preparation lost incomplete fleet draft.")
	prep._reset();await flush()
	expect(prep.draft.setup.fleet==fixture.setup.fleet and not prep.launch_button.disabled,"Reset failed from incomplete setup.")
	for id in ["bastion","kestrel","lamplighter"]: prep._unassign({"kind":"ship","ship":id,"preparation":prep.get_instance_id()},"ship")
	expect(prep.draft.setup.fleet.all(func(slot):return slot.ship=="" and slot.captain=="") and prep.formation.snapshot.formation==[-1,-1,-1,-1],"Fully unassigned fleet cannot be edited safely.")
	for index in 3:
		var next_point: int=[3,0,1][index]
		prep._drop_at(Vector2.ZERO,{"kind":"ship","ship":["bastion","kestrel","lamplighter"][index],"preparation":prep.get_instance_id()},next_point)
		prep._drop_at(Vector2.ZERO,{"kind":"captain","captain":["iona","rook","voss"][index],"preparation":prep.get_instance_id()},next_point)
	expect(not prep.launch_button.disabled and Catalog.validate(prep._candidate()).is_empty(),"An empty fleet cannot be rebuilt, including a previously unused position.")
	var old:=JSON.stringify(prep.draft)
	prep._unassign({"kind":"ship","ship":"bastion","preparation":-1},"ship")
	expect(JSON.stringify(prep.draft)==old,"Foreign drag payload changed preparation.")
	expect(JSON.stringify(store_node.saved)==saved and FileAccess.get_sha256("res://data/content.json")==hash_before,"Preparation roster editing changed authored content.")
	done("Framed preparation rosters and unassignment")
