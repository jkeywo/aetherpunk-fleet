extends Control
const Art = preload("res://scripts/art_assets.gd")
const Rig = preload("res://scripts/rigged_art.gd")
var rig_node: Node2D
var definition: Dictionary = {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_layout)

func configure(id: String, enemy: bool = false) -> void:
	configure_data({"id":id},enemy)

func configure_data(unit: Dictionary, enemy: bool = false) -> void:
	configure_definition(Art.visual_rig(unit,enemy))

func configure_definition(value: Dictionary) -> void:
	definition = value.duplicate(true)
	if definition.is_empty():
		if rig_node != null: rig_node.queue_free(); rig_node = null
		queue_redraw()
		return
	if rig_node == null:
		rig_node = Rig.new()
		add_child(rig_node)
	rig_node.configure(definition,Art.ROOT + "rigs/")
	rig_node.playing = false
	_layout()
	_process(0)

func _layout() -> void:
	if rig_node == null: return
	var saved: float = rig_node.strength
	rig_node.strength = 0
	var poses: Dictionary = rig_node.poses(0)
	rig_node.strength = saved
	var bounds := Rect2()
	var first := true
	for part in definition.parts:
		var extent := Vector2(part.size[0],part.size[1])
		var pivot := Vector2(part.pivot[0],part.pivot[1])*extent
		for corner in [Vector2.ZERO,Vector2(extent.x,0),extent,Vector2(0,extent.y)]:
			var point: Vector2 = poses[part.id]*(corner-pivot)
			if first: bounds = Rect2(point,Vector2.ZERO); first=false
			else: bounds = bounds.expand(point)
	bounds = bounds.grow(16)
	var factor := minf(size.x/bounds.size.x,size.y/bounds.size.y)
	rig_node.scale = Vector2.ONE*factor
	rig_node.position = (size-bounds.size*factor)/2-bounds.position*factor

func _process(_delta: float) -> void:
	if rig_node != null and is_visible_in_tree():
		# Scene rebuilds do not restart the idle pose; no combat RNG is involved.
		rig_node.elapsed = Time.get_ticks_msec()/1000.0 + float(abs(str(definition.id).hash())%1000)/100

func _draw() -> void:
	if definition.is_empty():
		var box := Rect2(size*Vector2(.2,.3),size*Vector2(.6,.4))
		draw_rect(box,Color("#91b9c6"),false,1,true)
		draw_line(box.position,box.end,Color("#91b9c6"),1,true)
