extends Node2D
## Shared anchored idle rig. Atlas regions remain separate drawable parts.
const Schema = preload("res://scripts/visuals/rig_schema.gd")
var definition: Dictionary = {}
var part_textures: Dictionary = {}
var configuration_error := ""
var atlas: Texture2D
var elapsed := 0.0
var playing := true
var show_anchors := false
var strength := 1.0


func configure(value: Dictionary, base_path: String = "res://assets/generated/rigs/") -> void:
	definition = {}
	part_textures.clear()
	atlas = null
	var errors := Schema.validate(value,"Visual rig",false)
	configuration_error = "\n".join(errors)
	if not errors.is_empty(): queue_redraw(); return
	definition = value.duplicate(true)
	for part in definition.parts:
		var source := Schema.texture_path(definition,part,base_path)
		part_textures[part.id] = Schema.load_texture(source)
		if atlas == null: atlas = part_textures[part.id]
	queue_redraw()


func _process(delta: float) -> void:
	if playing: elapsed += delta
	queue_redraw()


func _uv(part: Dictionary, value: Array) -> Vector2:
	return (Vector2(value[0], value[1]) - Vector2(part.pivot[0], part.pivot[1])) * Vector2(part.size[0], part.size[1])


func part_definitions() -> Dictionary:
	var result: Dictionary = {}
	for part in definition.get("parts", []): result[part.id] = part
	return result


func poses(time: float) -> Dictionary:
	var result: Dictionary = {}
	var parts := part_definitions()
	for part in Schema.ordered_parts(definition):
		var motion: Dictionary = part.motion
		var wave := sin(time * TAU / float(motion.period) + float(motion.phase)) if motion.get("enabled",true) else 0.0
		var angle := deg_to_rad(float(part.get("rest_degrees",0))) + deg_to_rad(float(motion.degrees)) * wave * strength
		var bob := float(motion.bob_y) * wave * strength
		var origin: Vector2
		if part.get("parent","")!="":
			var attachment := _uv(parts[part.parent], part.anchor)
			var offset: Array = part.get("offset", [0, 0])
			attachment += Vector2(offset[0], offset[1] + bob)
			origin = attachment
		else:
			origin = Vector2(part.position[0], part.position[1] + bob)
		var transform := Transform2D(angle,origin)
		if part.get("flip_x",false): transform = transform * Transform2D.FLIP_X
		if part.get("flip_y",false): transform = transform * Transform2D.FLIP_Y
		result[part.id] = result[part.parent]*transform if part.get("parent","")!="" else transform
	return result


func marker_position(id: String, time: float = -1.0) -> Vector2:
	for marker in definition.get("markers", []):
		if marker.id == id:
			var transforms := poses(elapsed if time < 0 else time)
			var parts := part_definitions()
			if transforms.has(marker.part): return transforms[marker.part] * _uv(parts[marker.part], marker.uv)
	return Vector2.ZERO


func _draw() -> void:
	if definition.is_empty() or atlas == null: return
	var transforms := poses(elapsed)
	var parts := part_definitions()
	for cable in definition.get("cables", []):
		var a: Vector2 = transforms[cable.from] * _uv(parts[cable.from], cable.from_uv)
		var b: Vector2 = transforms[cable.to] * _uv(parts[cable.to], cable.to_uv)
		draw_line(a, b, Color("#342d25"), 3.8, true)
		draw_line(a, b, Color("#b49a67"), 1.9, true)
	var ordered: Array = definition.parts.duplicate()
	ordered.sort_custom(func(a, b): return a.get("z",0) < b.get("z",0))
	for part in ordered:
		draw_set_transform_matrix(transforms[part.id])
		var size_value := Vector2(part.size[0], part.size[1])
		var pivot := Vector2(part.pivot[0], part.pivot[1]) * size_value
		var region: Array = part.region
		draw_texture_rect_region(part_textures[part.id], Rect2(-pivot, size_value), Rect2(region[0], region[1], region[2], region[3]), Color(1,1,1,float(part.get("opacity",1))))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if show_anchors:
		for part in definition.parts:
			var point: Vector2 = transforms[part.id].origin
			draw_circle(point, 5, Color("#ffbd6b") if part.has("parent") else Color("#78e8e8"))
			draw_string(ThemeDB.fallback_font, point + Vector2(9, -8), str(part.get("label",part.id)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#fff4db"))
		for cable in definition.get("cables", []):
			for end in [[cable.from, cable.from_uv], [cable.to, cable.to_uv]]:
				draw_circle(transforms[end[0]] * _uv(parts[end[0]], end[1]), 3, Color("#78e8e8"))

		for marker in definition.get("markers", []):
			var point := marker_position(marker.id)
			draw_circle(point, 7, Color("#6cecff"), false, 2, true)
			draw_line(point - Vector2(11,0), point + Vector2(11,0), Color("#6cecff"), 2)
			draw_line(point - Vector2(0,11), point + Vector2(0,11), Color("#6cecff"), 2)
			draw_string(ThemeDB.fallback_font, point + Vector2(10,18), str(marker.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#6cecff"))
