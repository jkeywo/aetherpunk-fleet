extends Control
## Cosmetic only. Shields travel with units; cover instances belong to formation slots.
var shields := 0
var cover := 0
var enemy := false
var flash_strength := 0.0

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func configure(shield_count: int, cover_count: int, is_enemy: bool) -> void:
	shields=shield_count;cover=cover_count;enemy=is_enemy
	visible=shields>0 or cover>0
	set_process(visible)
	queue_redraw()

func flash() -> void:
	flash_strength=1
	queue_redraw()

func _process(delta: float) -> void:
	flash_strength=maxf(0,flash_strength-delta*4)
	queue_redraw()

func _draw() -> void:
	var time:=Time.get_ticks_msec()/1000.0
	var facing: float=-1 if enemy else 1
	var centre:=Vector2(size.x*(.22 if enemy else .78),size.y*.53)
	if shields>0:
		var points:=PackedVector2Array()
		for step in 33:
			var angle: float=-PI/2+PI*step/32
			points.append(centre+Vector2(facing*cos(angle)*size.x*.17,sin(angle)*size.y*.5))
		draw_colored_polygon(points,Color(.2,.76,1,.10+flash_strength*.15))
		var shimmer: float=.7+.15*sin(time*2)
		for width in [8,4,1.5]:
			draw_polyline(points,Color(.35,.85,1,(.07 if width==8 else .18 if width==4 else .75)*shimmer+flash_strength*.18),width,true)
		for line in 5:
			var y: float=(float(line)/4-.5)*size.y*.75
			var extent: float=sqrt(maxf(0,1-pow(y/maxf(1,size.y*.5),2)))*size.x*.17
			draw_line(centre+Vector2(0,y),centre+Vector2(facing*extent,y),Color(.4,.9,1,.16+flash_strength*.2),1,true)
		var spark_angle: float=sin(time*.8)*PI*.42
		var spark:=centre+Vector2(facing*cos(spark_angle)*size.x*.17,sin(spark_angle)*size.y*.5)
		draw_circle(spark,2.3,Color(.7,.97,1,.9),true,-1,true)
	if cover>0:
		# Soft layered puffs, in front of the slot rather than over its labels.
		for puff in 8:
			var offset:=Vector2(sin(puff*2.4)*size.x*.08,cos(puff*1.7)*size.y*.32)
			offset+=Vector2(sin(time*.45+puff)*2,cos(time*.35+puff)*1.2)
			var radius: float=minf(18,size.y*.23)*(1+.22*sin(puff*3.1))
			for layer in range(5,0,-1):
				var alpha: float=(.014+float(6-layer)*.008)+flash_strength*.025
				draw_circle(centre+offset,radius*(.65+layer*.12),Color(.78,.86,.9,alpha),true,-1,true)
			draw_arc(centre+offset,radius*.68,PI*1.1,PI*1.8,10,Color(.9,.95,.96,.12+flash_strength*.2),1,true)
