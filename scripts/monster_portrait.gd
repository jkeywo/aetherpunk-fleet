extends VBoxContainer
## The header marks the monster's own position on the enemy formation.
const Geometry = preload("res://scripts/battle_geometry.gd")
const Icons = preload("res://scripts/keyword_icons.gd")
const RigView = preload("res://scripts/rig_view.gd")

var rig: Control

func configure(visual: Dictionary, owner: int, extent: Vector2 = Vector2(48, 24)) -> void:
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rig = RigView.new()
	rig.custom_minimum_size = extent
	rig.set_meta("owner_portrait", owner)
	add_child(rig)
	rig.configure_data(visual, true)
	var point: int = visual.get("position", -1)
	if point < 0 or point >= Geometry.POSITIONS.size(): return
	var marker := TextureRect.new()
	marker.name = "OwnerPosition"
	marker.texture = Icons.texture(Geometry.POSITIONS[point], true)
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var marker_extent := roundf(extent.y * 0.6)
	marker.custom_minimum_size = Vector2.ONE * marker_extent
	marker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_PASS
	marker.tooltip_text = "Enemy " + Geometry.POSITION_NAMES[point]
	add_child(marker)
