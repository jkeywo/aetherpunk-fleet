extends Control

signal selected(id: String)
const World = preload("res://scripts/campaign_map.gd")
const Art = preload("res://scripts/campaign_art.gd")
const EXTENT := Vector2(660, 790)
const MAX_ZOOM := 3.5
const DEFAULT_ZOOM := 2.5
const DEFAULT_CENTER := Vector2(0.34, 0.795)
const ART_INSET := 3
const CIRCLE_MASK := """
shader_type canvas_item;
uniform float diameter;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float radius = diameter * 0.5;
	float edge = length(local_position - vec2(radius)) - radius;
	COLOR.a *= 1.0 - smoothstep(-1.0, 0.0, edge);
}
"""

class EncounterMarker extends Button:
	func _has_point(point: Vector2) -> bool:
		var center := size * 0.5
		return point.distance_squared_to(center) <= center.x * center.x

var nodes := World.nodes()
var links := World.links()
var points: Dictionary = {}
var buttons: Dictionary = {}
var cleared: Array = []
var active := ""
var zoom := DEFAULT_ZOOM
var pan := Vector2.ZERO
var previous_size := Vector2.ZERO
var marker_diameter := 0.0
var circle_material := ShaderMaterial.new()
var drag_button := MOUSE_BUTTON_NONE

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	var mask := Shader.new()
	mask.code = CIRCLE_MASK
	circle_material.shader = mask
	for id in nodes:
		var node: Dictionary = nodes[id]
		var button := EncounterMarker.new()
		button.name = id
		button.set_meta("plain_text", true)
		button.tooltip_text = node.name
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.clip_contents = true
		var tile := TextureRect.new()
		tile.texture = Art.location(node)
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.material = circle_material
		button.add_child(tile)
		tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile.offset_left = ART_INSET
		tile.offset_top = ART_INSET
		tile.offset_right = -ART_INSET
		tile.offset_bottom = -ART_INSET
		var badge := Label.new()
		badge.name = "Badge"
		badge.set_meta("plain_text", true)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_color_override("font_outline_color", Color("#091620"))
		badge.add_theme_constant_override("outline_size", 5)
		button.add_child(badge)
		button.pressed.connect(func(): selected.emit(id))
		add_child(button)
		buttons[id] = button
	resized.connect(_layout_map)
	_layout_map()

func configure(done: Array, active_id: String) -> void:
	cleared = done.duplicate()
	active = active_id
	_refresh()

func camera() -> Dictionary:
	return {"zoom":zoom, "center": (size / 2 - pan) / (size * zoom)} if size.x > 0 and size.y > 0 else {}

func restore_camera(saved: Dictionary) -> void:
	if saved.is_empty() or size.x <= 0 or size.y <= 0: return
	zoom = clampf(saved.zoom, 1.0, MAX_ZOOM)
	pan = size / 2 - saved.center * size * zoom
	_layout_map()

func reset_camera() -> void:
	zoom = DEFAULT_ZOOM
	pan = size * (Vector2(0.5, 0.5) - DEFAULT_CENTER * zoom)
	_layout_map()

func zoom_by(factor: float) -> void:
	_zoom_at(factor, size / 2)

func _zoom_at(factor: float, anchor: Vector2) -> void:
	var next := clampf(zoom * factor, 1.0, MAX_ZOOM)
	pan = anchor - (anchor - pan) * (next / zoom)
	zoom = next
	_layout_map()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(1.18 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.18, event.position)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed: drag_button = event.button_index
			elif drag_button == event.button_index: drag_button = MOUSE_BUTTON_NONE
			accept_event()
	elif event is InputEventMouseMotion and drag_button != MOUSE_BUTTON_NONE:
		if event.button_mask == 0:
			drag_button = MOUSE_BUTTON_NONE
			return
		pan += event.relative
		_layout_map()
		accept_event()
	elif event is InputEventScreenDrag:
		pan += event.relative
		_layout_map()
		accept_event()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor, event.position)
		accept_event()
	elif event is InputEventPanGesture:
		pan -= event.delta * 20.0
		_layout_map()
		accept_event()

func _map_point(point: Vector2) -> Vector2:
	return pan + point / EXTENT * size * zoom

func _layout_map() -> void:
	if size.x <= 0 or size.y <= 0: return
	if size != previous_size:
		if previous_size.x > 0 and previous_size.y > 0:
			pan *= size / previous_size
		else:
			pan = size * (Vector2(0.5, 0.5) - DEFAULT_CENTER * zoom)
		previous_size = size
	pan = pan.clamp(size * (1.0 - zoom), Vector2.ZERO)
	points[World.START] = _map_point(World.START_POINT)
	var diameter := roundf(clampf(size.y * 0.103 * minf(1.0, zoom / DEFAULT_ZOOM), 24.0, 110.0))
	var resized_markers := diameter != marker_diameter
	if resized_markers:
		marker_diameter = diameter
		circle_material.set_shader_parameter("diameter", diameter - ART_INSET * 2.0)
	for id in nodes:
		points[id] = _map_point(nodes[id].point)
		var button: Button = buttons[id]
		if resized_markers:
			button.size = Vector2(diameter, diameter)
			var badge: Label = button.get_node("Badge")
			badge.position = Vector2(diameter * 0.23, diameter * 0.13)
			badge.add_theme_font_size_override("font_size", roundi(clampf(diameter * 0.2, 10.0, 17.0)))
		button.position = points[id] - button.size / 2.0
	if resized_markers: _refresh()
	queue_redraw()

func _refresh() -> void:
	for id in buttons:
		var node: Dictionary = nodes[id]
		var button: Button = buttons[id]
		var complete: bool = id in cleared
		button.get_node("Badge").text = "OK" if complete else ("T" if node.kind == "town" else ("B" if node.kind == "boss" else "F"))
		button.tooltip_text = node.name + (" · Cleared" if complete else (" · Not in this build" if not node.playable else ""))
		button.get_child(0).modulate = Color.WHITE if node.playable else Color(0.69, 0.75, 0.76)
		var border := Color("#ffe0a0") if id == active else (Color("#9cd7a8") if complete else (Color("#e38e80") if node.kind == "boss" else Color("#a9c5c1")))
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("#102530")
			style.border_color = border.lightened(0.25) if state == "hover" else border
			style.set_border_width_all(ART_INSET)
			style.set_corner_radius_all(roundi(button.size.x / 2.0))
			button.add_theme_stylebox_override(state, style)
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(Art.WORLD, Rect2(pan, size * zoom), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.08, 0.12, 0.22))
	for link in links:
		if points.has(link[0]) and points.has(link[1]):
			var explored: bool = (link[0] in cleared or link[0] == World.START) and link[1] in cleared
			draw_line(points[link[0]], points[link[1]], Color(0.02, 0.07, 0.11, 0.78), 4.0, true)
			draw_line(points[link[0]], points[link[1]], Color("#efca7e") if explored else Color(0.83, 0.88, 0.86, 0.8), 1.6, true)
	for biome in World.BIOMES:
		var font := ThemeDB.fallback_font
		var point := _map_point(Vector2(biome.label[0], biome.label[1]))
		var width := font.get_string_size(biome.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var baseline := point - Vector2(width / 2, 0)
		draw_string_outline(font, baseline, biome.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color("#162430"))
		draw_string(font, baseline, biome.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#fff2d7"))
	if points.has(World.START):
		var center: Vector2 = points[World.START]
		var radius := marker_diameter / 2.0
		draw_circle(center, radius, Color("#efca7e"), true, -1.0, true)
		draw_circle(center, radius - ART_INSET, Color("#193847"), true, -1.0, true)
		var city_size: Vector2 = Art.STARTING_CITY.get_size()
		city_size *= (marker_diameter - ART_INSET * 2.0) / city_size.length()
		draw_texture_rect(Art.STARTING_CITY, Rect2(center - city_size / 2.0, city_size), false)
