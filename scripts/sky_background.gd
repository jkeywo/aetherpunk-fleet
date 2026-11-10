extends Control
const Art = preload("res://scripts/art_assets.gd")
var dimming := .55
var far: Texture2D
var near: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	far = Art.texture("sky/far.png")
	near = Art.texture("sky/near.png")

func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()

func _layer(image: Texture2D, speed: float) -> void:
	if image == null or size.y <= 0: return
	var width := image.get_width()*size.y/image.get_height()
	var offset := fmod(Time.get_ticks_msec()/1000.0*speed,width*2)
	var first := int(floor(offset/width))
	for index in range(first,first+int(ceil(size.x/width))+2):
		var x := index*width-offset
		if index%2:
			draw_set_transform(Vector2(x+width,0),0,Vector2(-1,1))
			draw_texture_rect(image,Rect2(0,0,width,size.y),false)
			draw_set_transform(Vector2.ZERO)
		else: draw_texture_rect(image,Rect2(x,0,width,size.y),false)

func _draw() -> void:
	_layer(far,6)
	_layer(near,15)
	draw_rect(Rect2(Vector2.ZERO,size),Color(.025,.06,.095,dimming))
	draw_rect(Rect2(0,0,size.x,58),Color(.02,.045,.065,.5))
