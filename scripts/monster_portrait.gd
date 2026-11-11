extends Control
## Position glyphs sit behind the owning monster and face the enemy direction.
var rig: Control
var position_glyph: Texture2D
var condition: Dictionary = {}

func configure(visual: Dictionary, spec: Dictionary = {}, extent: Vector2 = Vector2(48,24)) -> void:
	condition=spec.duplicate(true)
	custom_minimum_size=extent
	size=extent
	mouse_filter=Control.MOUSE_FILTER_PASS
	if spec.get("kind")=="reaction_trigger" and spec.get("family")=="position":
		position_glyph=load("res://assets/generated/reactions/"+str(spec.get("position","front"))+".png")
		tooltip_text=preload("res://scripts/rules/rule_registry.gd").common_reaction_text(spec)+". Front is left and Rear is right around the enemy; Upper Flank is above and Lower Flank below."
		set_meta("reaction_badge",true)
	rig=preload("res://scripts/rig_view.gd").new()
	add_child(rig)
	rig.configure_data(visual,true)
	resized.connect(_layout)
	_layout()
	queue_redraw()

func _layout() -> void:
	if rig==null:return
	rig.position=size*Vector2(.27,.20) if position_glyph!=null else Vector2.ZERO
	rig.size=size*Vector2(.46,.60) if position_glyph!=null else size
	rig._layout()

func _draw() -> void:
	if position_glyph==null:return
	# Enemy faces left, opposite to the player formation used by the source glyphs.
	draw_set_transform(Vector2(size.x,0),0,Vector2(-1,1))
	var square:=Vector2.ONE*minf(size.x,size.y)
	draw_texture_rect(position_glyph,Rect2((size-square)/2,square),false,Color(1,1,1,.8))
	draw_set_transform(Vector2.ZERO)
