extends "res://tests/support/v3_test.gd"
const Schema=preload("res://scripts/visuals/rig_schema.gd")
const Editor=preload("res://scripts/visuals/rig_editor.gd")
const Rig=preload("res://scripts/rigged_art.gd")
const Art=preload("res://scripts/art_assets.gd")
func _run() -> void:
	root.size=Vector2i(1280,800)
	var templates:=Schema.templates()
	for definition in templates:expect(Schema.validate(definition).is_empty(),"Invalid existing template: "+definition.id)
	var original: Dictionary=templates[3].duplicate(true)
	var rig:=Schema.editable(original,"custom")
	rig.parts.reverse()
	expect(Schema.ordered_parts(rig).size()==rig.parts.size(),"Parent order must be independent of draw/list order.")
	var renderer:=Rig.new();root.add_child(renderer);renderer.configure(rig)
	expect(renderer.configuration_error=="","Editable mixed-source rig rejected.")
	var lookup: Dictionary=renderer.part_definitions()
	for time in [0,2,8]:
		var poses: Dictionary=renderer.poses(time)
		for item in rig.parts:
			if item.has("parent"):
				expect(poses[item.id].origin.distance_to(poses[item.parent]*renderer._uv(lookup[item.parent],item.anchor))<.001,"Limb anchor detached during rotation.")
	var reflection:=rig.duplicate(true)
	for item in reflection.parts:item.motion.enabled=false
	var root_part: Dictionary=reflection.parts.filter(func(item):return not item.has("parent"))[0]
	root_part.flip_x=true;root_part.rest_degrees=15
	renderer.configure(reflection)
	expect(renderer.poses(0)==renderer.poses(5),"Disabled motion kept animating.")
	expect(renderer.poses(0)[root_part.id].determinant()<0,"Horizontal flip did not propagate through transforms.")
	renderer.configure(rig)
	var invalid:=rig.duplicate(true);invalid.parts[0].parent="missing"
	expect(not Schema.validate(invalid).is_empty(),"Missing parent accepted.")
	invalid=rig.duplicate(true)
	var body: Dictionary=invalid.parts.filter(func(item):return not item.has("parent"))[0]
	body.parent=invalid.parts.filter(func(item):return item.id!=body.id)[0].id;body.anchor=[.5,.5]
	expect(not Schema.validate(invalid).is_empty() and Schema.ordered_parts(invalid).is_empty(),"Cyclic links accepted.")
	invalid=rig.duplicate(true);invalid.parts[0].motion.period=0
	expect(not Schema.validate(invalid).is_empty(),"Zero animation period accepted.")
	invalid=rig.duplicate(true);invalid.parts[0].region=[0,0,99999,99999]
	expect(not Schema.validate(invalid).is_empty(),"Out-of-bounds atlas region accepted.")
	var dialog:=Editor.new();root.add_child(dialog);dialog.configure(original,"test","Stormmaw")
	dialog.popup_centered(Vector2i(1180,740));await flush()
	expect(dialog.parts.item_count==original.parts.size(),"Parts browser not populated.")
	dialog.selected_id=original.parts[0].id
	dialog.duplicate_part()
	expect(dialog.draft.parts.size()==original.parts.size()+1,"Duplicate failed.")
	expect(dialog.part().parent==original.parts[0].id,"Duplicated body must remain linked.")
	dialog.remove_part()
	expect(dialog.draft.parts.size()==original.parts.size(),"Remove leaf failed.")
	dialog.selected_id=original.parts[0].id;dialog.remove_part()
	expect(dialog.draft.parts.size()==original.parts.size() and "first" in dialog.status.text,"Referenced body deletion not blocked.")
	dialog.selected_id=original.parts[1].id
	dialog.set_source(Schema.sprites()[0]);dialog.part().motion.degrees=2.5;dialog._refresh()
	var old_parent: String=dialog.part().parent
	var old_joint: Vector2=dialog.preview.rig.poses(dialog.preview.time)[dialog.selected_id].origin
	dialog.set_parent(original.parts[3].id);dialog._refresh()
	expect(dialog.preview.rig.poses(dialog.preview.time)[dialog.selected_id].origin.distance_to(old_joint)<.001,"Reparenting moved the joint.")
	dialog.set_parent(old_parent);dialog._refresh()
	var child_id: String=dialog.selected_id
	dialog.selected_id=old_parent
	dialog.set_parent(child_id)
	expect(not dialog.part().has("parent"),"Parent picker allowed a descendant cycle.")
	dialog.selected_id=child_id;dialog._refresh()
	expect(dialog.preview.rig.part_textures[dialog.selected_id]!=null,"Chosen sprite missing from live preview.")
	expect(original==templates[3],"Editor modified shared template.")
	var applied: Array=[];dialog.applied.connect(func(value):applied.append(value))
	dialog.confirmed.emit()
	expect(applied.size()==1 and applied[0]!=original,"Apply did not return a detached authored rig.")
	await flush()
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	doc.ships[0].visual_rig=applied[0]
	expect(Catalog.validate(doc).is_empty(),"Authored rig rejected by content validation.")
	var path:="user://rig_workshop_roundtrip.json"
	expect(Catalog.save_document(path,doc)=="","Rig save failed.")
	var loaded:=Catalog.read_document(path)
	expect(loaded.ok and same(loaded.document.ships[0].visual_rig,doc.ships[0].visual_rig),"Rig failed save/reload roundtrip.")
	var battle:=State.new(42,doc)
	var before: Dictionary=battle.ships[0].visual_rig.duplicate(true)
	doc.ships[0].visual_rig.parts[0].motion.degrees=99
	expect(battle.ships[0].visual_rig==before,"Editor changes leaked into battle snapshot.")
	expect(battle.result_summary("victory").ships[0].visual_rig==before,"Results lost authored ship art.")
	var corrupt:=doc.duplicate(true);corrupt.ships[0].visual_rig.parts[0].texture="res://missing.png"
	expect(Catalog.save_document(path,corrupt)!="" and Catalog.read_document(path).ok,"Invalid rig damaged saved document.")
	var imported:=Schema.import_png(Schema.texture_path(templates[0],templates[0].parts[0]),"user://rig_workshop_import")
	expect(imported.ok and FileAccess.file_exists(imported.path),"PNG import failed.")
	expect(not Schema.import_png("user://missing.png").ok,"Missing PNG import accepted.")
	expect(not Schema.import_png(imported.path,"res://../outside").ok,"Unsafe import destination accepted.")

	# Exercise the actual workshop integration, not just the popup in isolation.
	var store=root.get_node("ContentStore")
	store.saved=Catalog.read_document("res://data/content.json").document
	store.path="user://rig_editor_flow.json";store.editor_state={}
	change_scene_to_file("res://scenes/editor.tscn")
	await scene_changed
	await flush()
	var workshop=current_scene
	var unit: Dictionary=workshop.selected_entry()
	var saved_unit: Dictionary=unit.duplicate(true)
	workshop._open_rig_editor(unit)
	await flush()
	var popup=workshop.get_children().filter(func(child):return child.get_script()==Editor)[0]
	popup.part().motion.degrees=7
	popup.canceled.emit()
	await flush()
	expect(workshop.selected_entry()==saved_unit and not workshop.is_dirty(),"Cancel changed the workshop draft.")
	workshop._open_rig_editor(workshop.selected_entry())
	await flush()
	popup=workshop.get_children().filter(func(child):return child.get_script()==Editor)[0]
	popup.selected_id=popup.draft.parts[1].id;popup._refresh()
	popup.preview.pivot_mode=true;popup.preview.running=false
	popup.preview.queue_redraw()
	await flush()
	# Direct GUI input uses the same handlers as a physical mouse.
	popup.preview.sprite_rect=Rect2(20,20,200,100)
	popup.preview._update_point(Vector2(70,95))
	expect(popup.part().pivot==[.25,.75] and popup.fields.pivot0.value==.25,"Clicking sprite hinge did not update data and fields.")
	popup.preview.pivot_mode=false;popup.preview.rig.strength=0
	popup.preview.time=0
	var parent_pose: Transform2D=popup.preview.rig.poses(0)[popup.part().parent]
	var parent: Dictionary=popup.preview.rig.part_definitions()[popup.part().parent]
	var local: Vector2=popup.preview.rig._uv(parent,[.7,.4])
	popup.preview._update_point(popup.preview.origin+(parent_pose*local)*popup.preview.zoom)
	expect(is_equal_approx(popup.part().anchor[0],.7) and is_equal_approx(popup.part().anchor[1],.4),"Dragging attachment used the wrong coordinate space.")
	popup.part().motion.degrees=3.25;popup.confirmed.emit()
	await flush()
	expect(workshop.is_dirty() and store.saved.leviathans[0]==saved_unit,"Apply bypassed draft/save boundary.")
	expect(workshop._save(),"Save All rejected authored rig.")
	expect(store.saved.leviathans[0].visual_rig.parts[1].motion.degrees==3.25,"Save All lost motion configuration.")
	workshop._open_rig_editor(workshop.selected_entry());await flush()
	popup=workshop.get_children().filter(func(child):return child.get_script()==Editor)[0]
	expect(popup.draft.parts[1].pivot==[.25,.75],"Reopened rig did not restore authored hinge.")
	popup.canceled.emit();await flush()
	workshop.test_button.pressed.emit()
	await scene_changed
	await flush()
	var actual=current_scene
	expect(actual.state.enemies[0].visual_rig.parts[1].motion.degrees==3.25,"Playtest ignored saved rig.")
	var enemy_widget=actual.enemies.target_widget(-1)
	expect(enemy_widget.art.rig_node.definition.parts[1].pivot==[.25,.75],"Battle rendering ignored saved pivot.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	renderer.free()
	done("Workshop visual rigs")

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
