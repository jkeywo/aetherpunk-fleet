extends Control
const Rig = preload("res://scripts/rigged_art.gd")
signal changed
signal selected(id: String)
var rig = Rig.new()
var definition: Dictionary = {}
var selected_id := ""
var pivot_mode := false
var dragging := false
var running := true
var time := 0.0
var zoom := 1.0
var origin := Vector2.ZERO
var sprite_rect := Rect2()
var overlay := Node2D.new()

func _ready() -> void:
	custom_minimum_size = Vector2(420,360)
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	add_child(rig)
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	rig.playing = false
	rig.show_anchors = true
	resized.connect(fit)

func configure(value: Dictionary, id: String) -> void:
	definition = value
	selected_id = id
	rig.configure(value)
	fit()

func fit() -> void:
	var canvas: Array = definition.get("canvas",[1000,650])
	zoom = minf((size.x-32)/float(canvas[0]),(size.y-32)/float(canvas[1]))
	zoom = maxf(.01,zoom)
	origin = (size-Vector2(canvas[0],canvas[1])*zoom)/2
	rig.position = origin
	rig.scale = Vector2.ONE*zoom
	queue_redraw()

func part() -> Dictionary:
	for item in definition.get("parts",[]):
		if item.id == selected_id: return item
	return {}

func _process(delta: float) -> void:
	if running: time += delta
	rig.elapsed = time
	rig.visible = not pivot_mode
	overlay.queue_redraw()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#101e2b"))
	for x in range(0,int(size.x),32): draw_line(Vector2(x,0),Vector2(x,size.y),Color(1,1,1,.035))
	for y in range(0,int(size.y),32): draw_line(Vector2(0,y),Vector2(size.x,y),Color(1,1,1,.035))
	var item := part()
	if item.is_empty(): return
	if pivot_mode:
		var texture: Texture2D = rig.part_textures.get(selected_id)
		if texture == null: return
		var region: Array = item.region
		var factor := minf((size.x-40)/region[2],(size.y-40)/region[3])
		var dimensions := Vector2(region[2],region[3])*factor
		sprite_rect = Rect2((size-dimensions)/2,dimensions)
		draw_texture_rect_region(texture,sprite_rect,Rect2(region[0],region[1],region[2],region[3]))
		_marker(sprite_rect.position+Vector2(item.pivot[0],item.pivot[1])*dimensions)

func _draw_overlay() -> void:
	if pivot_mode or not rig.configuration_error.is_empty(): return
	var poses: Dictionary = rig.poses(time)
	if not poses.has(selected_id): return
	var point: Vector2 = origin+poses[selected_id].origin*zoom
	overlay.draw_circle(point,9,Color("#ffe196"),false,2,true)
	overlay.draw_line(point-Vector2(14,0),point+Vector2(14,0),Color("#ffe196"),2)
	overlay.draw_line(point-Vector2(0,14),point+Vector2(0,14),Color("#ffe196"),2)


func _marker(point: Vector2) -> void:
	draw_circle(point,9,Color("#ffe196"),false,2,true)
	draw_line(point-Vector2(14,0),point+Vector2(14,0),Color("#ffe196"),2)
	draw_line(point-Vector2(0,14),point+Vector2(0,14),Color("#ffe196"),2)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			running = false
			if not pivot_mode:
				# Select the topmost visible sprite; transparent atlas pixels do not steal clicks.
				var ordered: Array = definition.get("parts",[]).duplicate()
				ordered.sort_custom(func(a,b): return a.z>b.z)
				var poses: Dictionary = rig.poses(time)
				for candidate in ordered:
					if not poses.has(candidate.id): continue
					var local: Vector2 = poses[candidate.id].affine_inverse()*((event.position-origin)/zoom)
					var uv := local/Vector2(candidate.size[0],candidate.size[1])+Vector2(candidate.pivot[0],candidate.pivot[1])
					if uv.x<0 or uv.y<0 or uv.x>1 or uv.y>1: continue
					var texture: Texture2D = rig.part_textures[candidate.id]
					var pixel := Vector2(candidate.region[0],candidate.region[1])+uv*Vector2(candidate.region[2],candidate.region[3])
					if texture.get_image().get_pixel(clampi(int(pixel.x),0,texture.get_width()-1),clampi(int(pixel.y),0,texture.get_height()-1)).a<.1: continue
					selected_id=candidate.id; selected.emit(selected_id); break
			_update_point(event.position)
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		_update_point(event.position)
		accept_event()

func _update_point(point: Vector2) -> void:
	var item := part()
	if item.is_empty() or not rig.configuration_error.is_empty(): return
	if pivot_mode:
		var uv := (point-sprite_rect.position)/sprite_rect.size
		item.pivot=[clampf(uv.x,0,1),clampf(uv.y,0,1)]
	else:
		var local := (point-origin)/zoom
		if item.has("parent"):
			var poses: Dictionary = rig.poses(time)
			var parent: Dictionary = rig.part_definitions()[item.parent]
			var offset: Array = item.get("offset",[0,0])
			local = poses[item.parent].affine_inverse()*local-Vector2(offset[0],offset[1])
			# Account for the selected part's own idle drift at the paused instant.
			var motion: Dictionary = item.motion
			if motion.get("enabled",true): local.y -= float(motion.bob_y)*sin(time*TAU/float(motion.period)+float(motion.phase))*rig.strength
			var uv := local/Vector2(parent.size[0],parent.size[1])+Vector2(parent.pivot[0],parent.pivot[1])
			item.anchor=[clampf(uv.x,0,1),clampf(uv.y,0,1)]
		else:
			var motion: Dictionary = item.motion
			if motion.get("enabled",true): local.y -= float(motion.bob_y)*sin(time*TAU/float(motion.period)+float(motion.phase))*rig.strength
			item.position=[local.x,local.y]
	rig.configure(definition)
	changed.emit()
	queue_redraw()
