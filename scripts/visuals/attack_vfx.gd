extends Control
## Generic aether projectile and impact sparks; never uses battle RNG.
signal impacted
var start := Vector2.ZERO
var finish := Vector2.ZERO
var tint := Color("#8ceaff")
var progress := 0.0:
	set(value):
		if progress<.65 and value>=.65:impacted.emit()
		progress=value
		queue_redraw()

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var direction: Vector2=(finish-start).normalized()
	var flight: float=clampf(progress/.65,0,1)
	var head:=start.lerp(finish,flight)
	if progress<.7:
		var tail:=start.lerp(finish,maxf(0,flight-.18))
		draw_line(tail,head,Color(tint,.13),12,true)
		draw_line(tail,head,Color(tint,.65),4,true)
		draw_line(tail,head,Color.WHITE,1.3,true)
		draw_circle(head,4,Color(tint,.9),true,-1,true)
		for spark in 4:
			var offset:=Vector2(-direction.y,direction.x)*sin(spark*2.7)*3
			draw_line(tail+offset-direction*float(spark*4),head+offset-direction*float(spark*5),Color(tint,.22),1,true)
	if progress>=.65:
		var impact: float=(progress-.65)/.35
		var alpha: float=1-impact
		draw_arc(finish,4+impact*25,0,TAU,32,Color(tint,alpha*.7),2,true)
		draw_circle(finish,7*(1-impact),Color(1,1,1,alpha*.8),true,-1,true)
		for spark in 9:
			var axis:=Vector2.from_angle(spark*TAU/9+.3)
			draw_line(finish+axis*(4+impact*12),finish+axis*(9+impact*27),Color(tint,alpha),2,true)
