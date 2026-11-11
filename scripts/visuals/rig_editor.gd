extends AcceptDialog
## Local working copy. Only Apply changes the workshop draft; Save All writes content.
const Schema = preload("res://scripts/visuals/rig_schema.gd")
const Preview = preload("res://scripts/visuals/rig_preview.gd")
signal applied(value: Dictionary)
var draft: Dictionary = {}
var selected_id := ""
var sources: Array = []
var parts: ItemList
var properties: VBoxContainer
var preview: Control
var status: Label
var clock: HSlider
var play: Button
var fields: Dictionary = {}
var import_dialog: FileDialog
var edit_mode: OptionButton

func configure(value: Dictionary, unit_id: String, display_name: String) -> void:
	draft = Schema.editable(value,unit_id)
	title = display_name+" / Sprites & animation"
	sources = Schema.sprites()
	selected_id = draft.parts[0].id if not draft.parts.is_empty() else ""
	_build()
	_refresh()

func _box(parent: Node, horizontal := false) -> BoxContainer:
	var box: BoxContainer = HBoxContainer.new() if horizontal else VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",8)
	parent.add_child(box)
	return box

func _label(parent: Node, text: String) -> Label:
	var label:=Label.new();label.text=text;parent.add_child(label);return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button:=Button.new();button.text=text;button.pressed.connect(action);parent.add_child(button);return button

func _scroll(parent: Node, minimum: Vector2) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=minimum;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	return _box(scroll) as VBoxContainer

func _build() -> void:
	get_ok_button().text="Apply to Workshop Draft"
	add_cancel_button("Cancel")
	confirmed.connect(func(): applied.emit(draft.duplicate(true)); queue_free())
	canceled.connect(queue_free)
	close_requested.connect(queue_free)
	var outer:=ScrollContainer.new();outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left=12;outer.offset_top=12;outer.offset_right=-12;outer.offset_bottom=-64
	add_child(outer)
	var body:=_box(outer) as VBoxContainer
	body.custom_minimum_size=Vector2(1080,560)
	_label(body,"Choose sprites, link limbs to a body, then set their hinges and subtle idle motion. Apply changes the draft; Save All saves the project.").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var toolbar:=_box(body,true)
	_label(toolbar,"Start from")
	var templates:=OptionButton.new();templates.fit_to_longest_item=false;templates.custom_minimum_size.x=180;templates.add_item("Choose template…");templates.add_item("Empty rig")
	var definitions:=Schema.templates()
	for template in definitions: templates.add_item(template.name)
	toolbar.add_child(templates)
	templates.item_selected.connect(func(index):
		if index==0:return
		draft=Schema.empty(draft.id) if index==1 else Schema.editable(definitions[index-2],draft.id)
		selected_id=draft.parts[0].id if not draft.parts.is_empty() else ""
		_refresh();templates.select(0))
	_button(toolbar,"Import PNG…",_open_import)
	_label(toolbar,"PNG sprites / atlas slices / one root body")
	var columns:=_box(body,true)
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left:=_box(columns)
	left.custom_minimum_size.x=200
	left.size_flags_horizontal=Control.SIZE_FILL
	_label(left,"PARTS / draw layer")
	parts=ItemList.new();parts.custom_minimum_size=Vector2(180,260);parts.size_flags_vertical=Control.SIZE_EXPAND_FILL
	left.add_child(parts)
	parts.item_selected.connect(func(index):selected_id=draft.parts[index].id;_properties();_update_preview())
	_button(left,"Add sprite",add_part)
	_button(left,"Duplicate part",duplicate_part)
	_button(left,"Remove part",remove_part)
	var middle:=_box(columns)
	var controls:=_box(middle,true)
	play=_button(controls,"Pause",func():preview.running=not preview.running;preview.rig.strength=1;_sync_clock())
	_button(controls,"Rest pose",func():preview.running=false;preview.time=0;preview.rig.strength=0;_sync_clock())
	_button(controls,"Animate",func():preview.rig.strength=1;preview.running=true;_sync_clock())
	var anchors:=CheckButton.new();anchors.text="Anchors";anchors.button_pressed=true
	controls.add_child(anchors);anchors.toggled.connect(func(value):preview.rig.show_anchors=value)
	var mode:=OptionButton.new();mode.add_item("Assembly / drag attachment");mode.add_item("Sprite / click hinge");mode.add_item("Attack markers / drag point");edit_mode=mode
	middle.add_child(mode)
	mode.item_selected.connect(func(index):preview.pivot_mode=index==1;preview.marker_mode=index==2;preview.queue_redraw())
	preview=Preview.new();preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;middle.add_child(preview)
	preview.changed.connect(func():_sync_numbers();_validate();_sync_clock())
	preview.selected.connect(func(id):selected_id=id;_select_list();_properties())
	clock=HSlider.new();clock.min_value=0;clock.max_value=30;clock.step=.01;middle.add_child(clock)
	clock.value_changed.connect(func(value):preview.running=false;preview.time=value;preview.rig.strength=1;_sync_clock())
	_label(middle,"Assembly: drag a sprite to place its joint on its parent.\nSprite view: click its local hinge. Gold cross = selected hinge. Cyan cross = attack/impact marker.
Marker mode: drag the selected named point on its sprite.").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	properties=_scroll(columns,Vector2(340,410))
	properties.get_parent().size_flags_horizontal=Control.SIZE_FILL
	status=_label(body,"");status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y=48

func _process(_delta: float) -> void:
	if is_instance_valid(clock):
		clock.set_value_no_signal(fmod(preview.time,30))
		play.text="Pause" if preview.running else "Play"

func _sync_clock() -> void:
	play.text="Pause" if preview.running else "Play"
	clock.set_value_no_signal(fmod(preview.time,30))

func part() -> Dictionary:
	for item in draft.parts:
		if item.id==selected_id:return item
	return {}

func _select_list() -> void:
	for index in draft.parts.size():
		if draft.parts[index].id==selected_id:parts.select(index)

func _refresh() -> void:
	parts.clear()
	for item in draft.parts:
		parts.add_item(str(item.get("label",item.id))+"  ["+str(item.z)+"]")
		parts.set_item_tooltip(parts.item_count-1,"Root body" if not item.has("parent") else "Attached to "+str(item.parent))
	_select_list();_properties();_update_preview()

func _update_preview() -> void:
	# Keep the last valid pose while a temporary invalid input is being corrected.
	if Schema.validate(draft,"Rig",false).is_empty():preview.configure(draft,selected_id)
	_validate()

func _validate() -> void:
	var errors:=Schema.validate(draft)
	get_ok_button().disabled=not errors.is_empty()
	status.text="Ready. %d parts, %d cables. Changes are local until Apply."%[draft.parts.size(),draft.cables.size()] if errors.is_empty() else "\n".join(errors)
	status.modulate=Color("#a8ded3") if errors.is_empty() else Color("#ffc58a")

func _changed() -> void:
	for index in draft.parts.size():parts.set_item_text(index,str(draft.parts[index].get("label",draft.parts[index].id))+"  ["+str(draft.parts[index].z)+"]")
	_update_preview()

func _number(parent: Node, text: String, value: float, minimum: float, maximum: float, action: Callable, key: String = "", step: float = .01) -> void:
	var row:=_box(parent,true);var label:=_label(row,text);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var spin:=SpinBox.new();spin.min_value=minimum;spin.max_value=maximum;spin.step=step;spin.value=value;spin.custom_minimum_size.x=122
	row.add_child(spin);spin.value_changed.connect(func(amount):action.call(amount);_changed())
	if key!="":fields[key]=spin

func _pair(parent: Node, title_text: String, item: Dictionary, key: String, fallback: Array, minimum: float, maximum: float) -> void:
	_label(parent,title_text)
	for axis in 2:
		_number(parent,"X / U" if axis==0 else "Y / V",item.get(key,fallback)[axis],minimum,maximum,func(value):
			if not item.has(key):item[key]=fallback.duplicate()
			item[key][axis]=value,key+str(axis))

func _check(parent: Node, text: String, item: Dictionary, key: String, fallback: bool=false) -> void:
	var control:=CheckButton.new();control.text=text;control.button_pressed=item.get(key,fallback);parent.add_child(control)
	control.toggled.connect(func(value):item[key]=value;_changed())

func _properties() -> void:
	for child in properties.get_children():properties.remove_child(child);child.queue_free()
	fields.clear()
	var item:=part()
	if item.is_empty():_label(properties,"Add a sprite or choose a template.");return
	_markers()
	_label(properties,"PART / "+str(item.id))
	var name_field:=LineEdit.new();name_field.text=item.get("label",item.id);properties.add_child(name_field)
	name_field.text_changed.connect(func(value):item.label=value;parts.set_item_text(parts.get_selected_items()[0],value+"  ["+str(item.z)+"]"))
	_label(properties,"Sprite source / atlas slice")
	var source:=OptionButton.new();source.fit_to_longest_item=false;source.custom_minimum_size.x=310;source.clip_text=true
	source.add_item("Current: "+Schema.texture_path(draft,item).get_file())
	for sprite in sources:source.add_item(sprite.label)
	properties.add_child(source)
	source.item_selected.connect(func(index):
		if index==0:return
		set_source(sources[index-1]);_properties();_changed())
	for index in 4:
		_number(properties,["Region X","Region Y","Region width","Region height"][index],item.region[index],0 if index<2 else 1,8192,func(value):item.region[index]=value,"",1)
	var parent_select:=OptionButton.new();parent_select.fit_to_longest_item=false;parent_select.add_item("No parent / root body");parent_select.set_item_metadata(0,"")
	for candidate in draft.parts:
		if candidate.id==item.id or _descendant(candidate,item.id):continue
		parent_select.add_item(str(candidate.get("label",candidate.id)));parent_select.set_item_metadata(parent_select.item_count-1,candidate.id)
	for index in parent_select.item_count:
		if parent_select.get_item_metadata(index)==item.get("parent",""):parent_select.select(index)
	_label(properties,"Attach to parent");properties.add_child(parent_select)
	parent_select.item_selected.connect(func(index):set_parent(str(parent_select.get_item_metadata(index)));_properties();_changed())
	_pair(properties,"Rendered size",item,"size",[200,200],.01,10000)
	_pair(properties,"Hinge in this sprite / normalized",item,"pivot",[.5,.5],0,1)
	if item.has("parent"):
		_pair(properties,"Attachment on parent / normalized",item,"anchor",[.5,.5],0,1)
		_pair(properties,"Offset from attachment / pixels",item,"offset",[0,0],-10000,10000)
	else:_pair(properties,"Root position / canvas pixels",item,"position",[500,325],-10000,10000)
	_number(properties,"Draw layer",item.z,-1000,1000,func(value):item.z=value,"",1)
	_number(properties,"Rest rotation / degrees",item.get("rest_degrees",0),-360,360,func(value):item.rest_degrees=value)
	_check(properties,"Flip horizontally",item,"flip_x")
	_check(properties,"Flip vertically",item,"flip_y")
	_number(properties,"Opacity",item.get("opacity",1),0,1,func(value):item.opacity=value)
	_label(properties,"IDLE ANIMATION / rotates around hinge")
	_check(properties,"Enable idle motion",item.motion,"enabled",true)
	_number(properties,"Rotation amplitude / °",item.motion.degrees,0,180,func(value):item.motion.degrees=value)
	_number(properties,"Vertical drift / px",item.motion.bob_y,0,1000,func(value):item.motion.bob_y=value)
	_number(properties,"Cycle / seconds",item.motion.period,.05,3600,func(value):item.motion.period=value)
	_number(properties,"Phase offset / °",rad_to_deg(item.motion.phase),-3600,3600,func(value):item.motion.phase=deg_to_rad(value))
	_label(properties,"Limbs: use rotation with zero drift to keep the joint fixed.\nBalloon: a little drift moves it independently; cables follow.").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_cables()

func _sync_numbers() -> void:
	for marker in draft.get("markers", []):
		for axis in 2:
			var key := "marker_" + str(marker.id) + str(axis)
			if fields.has(key): fields[key].set_value_no_signal(marker.uv[axis])
	var item:=part()
	for key in ["pivot","anchor","position","offset"]:
		for axis in 2:
			if fields.has(key+str(axis)) and item.has(key):fields[key+str(axis)].set_value_no_signal(item[key][axis])

func _descendant(candidate: Dictionary, ancestor: String) -> bool:
	var lookup: Dictionary={}
	for item in draft.parts:lookup[item.id]=item
	var parent_id: String=candidate.get("parent","")
	var seen: Array=[]
	while parent_id!="" and lookup.has(parent_id) and not seen.has(parent_id):
		if parent_id==ancestor:return true
		seen.append(parent_id);parent_id=lookup[parent_id].get("parent","")
	return false

func set_parent(id: String) -> void:
	var item:=part()
	if id==item.id:return
	for candidate in draft.parts:
		if candidate.id==id and _descendant(candidate,item.id):return
	var poses: Dictionary=preview.rig.poses(preview.time)
	var world: Vector2=poses[item.id].origin if poses.has(item.id) else Vector2(500,325)
	var bob:=0.0
	if item.motion.get("enabled",true):bob=float(item.motion.bob_y)*sin(preview.time*TAU/float(item.motion.period)+float(item.motion.phase))*preview.rig.strength
	if id=="":
		item.erase("parent");item.erase("anchor");item.erase("offset")
		item.position=[world.x,world.y-bob]
	else:
		var parent: Dictionary=preview.rig.part_definitions()[id]
		var local: Vector2=poses[id].affine_inverse()*world-Vector2(0,bob)
		var uv:=local/Vector2(parent.size[0],parent.size[1])+Vector2(parent.pivot[0],parent.pivot[1])
		item.parent=id;item.anchor=[clampf(uv.x,0,1),clampf(uv.y,0,1)]
		var offset: Vector2=local-preview.rig._uv(parent,item.anchor)
		item.offset=[offset.x,offset.y];item.erase("position")

func set_source(sprite: Dictionary) -> void:
	var item:=part()
	item.texture=sprite.texture;item.region=sprite.region.duplicate();item.pivot=sprite.get("pivot",[.5,.5]).duplicate()
	item.size[1]=float(item.size[0])*float(item.region[3])/float(item.region[2])

func _unique_id() -> String:
	var index:=1
	while draft.parts.any(func(item):return item.id=="part_"+str(index)):index+=1
	return "part_"+str(index)

func add_part() -> void:
	if sources.is_empty() or draft.parts.size()>=64:return
	var sprite: Dictionary=sources[0]
	var item: Dictionary={"id":_unique_id(),"texture":sprite.texture,"region":sprite.region.duplicate(),"size":[300,300.0*sprite.region[3]/sprite.region[2]],"pivot":sprite.pivot.duplicate(),"z":draft.parts.size(),"motion":{"degrees":1,"bob_y":0,"period":8,"phase":0}}
	if draft.parts.is_empty():item.position=[500,325]
	else:item.parent=selected_id if selected_id!="" else draft.parts[0].id;item.anchor=[.5,.5]
	draft.parts.append(item);selected_id=item.id;_refresh()

func duplicate_part() -> void:
	if part().is_empty() or draft.parts.size()>=64:return
	var item:=part().duplicate(true);item.id=_unique_id();item.label=str(item.get("label",selected_id))+" copy"
	if not item.has("parent"):item.parent=selected_id;item.anchor=[.5,.5];item.erase("position")
	draft.parts.append(item);selected_id=item.id;_refresh()

func remove_part() -> void:
	var references: Array=[]
	for item in draft.parts:
		if item.get("parent","")==selected_id:references.append("child "+item.id)
	for marker in draft.get("markers", []):
		if marker.part==selected_id:references.append("marker " + marker.id)
	for index in draft.cables.size():
		if draft.cables[index].from==selected_id or draft.cables[index].to==selected_id:references.append("cable "+str(index+1))
	if not references.is_empty():status.text="Reattach or remove these first: "+", ".join(references);return
	draft.parts.erase(part());selected_id=draft.parts[0].id if not draft.parts.is_empty() else "";_refresh()

func select_marker(id: String) -> void:
	preview.selected_marker = id
	preview.marker_mode = true
	preview.pivot_mode = false
	edit_mode.select(2)
	preview.queue_redraw()


func add_marker() -> void:
	if part().is_empty() or draft.markers.size() >= 32: return
	var id := "attack"
	var index := 2
	while draft.markers.any(func(marker): return marker.id == id):
		id = "attack_" + str(index)
		index += 1
	draft.markers.append({"id":id, "part":selected_id, "uv":[.5,.5]})
	select_marker(id)
	_properties(); _changed()


func _markers() -> void:
	_label(properties, "ATTACK / IMPACT MARKERS")
	_label(properties, "Named points follow their part. Attacks choose an origin marker; default: attack.").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(properties, "Add marker", add_marker)
	for marker in draft.markers:
		var group := _box(properties)
		var tools := _box(group, true)
		_button(tools, "Drag " + str(marker.id), func(): select_marker(marker.id))
		_button(tools, "Remove marker", func(): draft.markers.erase(marker); _properties(); _changed())
		var name_field := LineEdit.new()
		name_field.text = marker.id
		group.add_child(name_field)
		name_field.text_changed.connect(func(value):
			if preview.selected_marker == marker.id: preview.selected_marker = value
			for axis in 2:
				var old_key := "marker_" + str(marker.id) + str(axis)
				if fields.has(old_key):
					fields["marker_" + value + str(axis)] = fields[old_key]
					fields.erase(old_key)
			marker.id = value; _changed())
		var choose := OptionButton.new()
		choose.fit_to_longest_item = false
		for item in draft.parts:
			choose.add_item("Part / " + str(item.get("label",item.id)))
			choose.set_item_metadata(choose.item_count-1,item.id)
			if marker.part == item.id: choose.select(choose.item_count-1)
		group.add_child(choose)
		choose.item_selected.connect(func(index): marker.part=choose.get_item_metadata(index); _changed())
		for axis in 2:
			_number(group, "Socket U" if axis==0 else "Socket V", marker.uv[axis], 0, 1, func(value): marker.uv[axis]=value, "marker_"+str(marker.id)+str(axis))


func _cables() -> void:
	_label(properties,"CABLES / endpoints follow their parts")
	_button(properties,"Add cable",func():draft.cables.append({"from":selected_id,"to":selected_id,"from_uv":[.25,.5],"to_uv":[.75,.5]});_properties();_changed())
	for cable in draft.cables:
		var group:=_box(properties)
		for side in ["from","to"]:
			var choose:=OptionButton.new();choose.fit_to_longest_item=false
			for item in draft.parts:
				choose.add_item(side+" / "+str(item.get("label",item.id)))
				choose.set_item_metadata(choose.item_count-1,item.id)
				if cable[side]==item.id:choose.select(choose.item_count-1)
			group.add_child(choose)
			choose.item_selected.connect(func(index):cable[side]=choose.get_item_metadata(index);_changed())
			_pair(group,side+" socket / normalized",cable,side+"_uv",[.5,.5],0,1)
		_button(group,"Remove cable",func():draft.cables.erase(cable);_properties();_changed())

func _open_import() -> void:
	import_dialog=FileDialog.new();import_dialog.title="Import transparent sprite PNG"
	import_dialog.access=FileDialog.ACCESS_FILESYSTEM;import_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.filters=PackedStringArray(["*.png ; PNG sprites"])
	add_child(import_dialog)
	import_dialog.file_selected.connect(func(path):
		var result:=Schema.import_png(path)
		if not result.ok:status.text=result.error;return
		sources=Schema.sprites()
		if part().is_empty():add_part()
		set_source({"texture":result.path,"region":result.region,"pivot":[.5,.5]});_properties();_changed()
		import_dialog.queue_free())
	import_dialog.canceled.connect(import_dialog.queue_free)
	import_dialog.popup_centered_ratio(.8)
