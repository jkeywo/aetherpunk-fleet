extends Node
## Preserve existing layout/text properties while rendering shared icon-rich text.
const Text = preload("res://scripts/keyword_text.gd")
const Icons = preload("res://scripts/keyword_icons.gd")
var tracked: Array = []

func _ready() -> void:
	get_tree().node_added.connect(_added)

func _added(node: Node) -> void:
	if (node is Label or (node is Button and not node is OptionButton)) and not node.has_meta("plain_text"):
		_register.call_deferred(weakref(node))

func _register(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if not is_instance_valid(node) or not node.is_inside_tree() or node.has_meta("plain_text") or node.has_meta("keyword_renderer") or node.theme_type_variation == "TooltipLabel": return
	tracked.append({"node":weakref(node),"text":"","renderer":null,"style":-1})

func _process(_delta: float) -> void:
	var alive: Array = []
	for item in tracked:
		var node = item.node.get_ref()
		if not is_instance_valid(node): continue
		alive.append(item)
		if node.has_meta("plain_text") or not node.is_visible_in_tree(): continue
		if item.renderer != null and is_instance_valid(item.renderer.get_ref()) and node is Button:
			item.renderer.get_ref().modulate.a = 0.5 if node.disabled else 1.0
		var font_size: int = node.get_theme_font_size("font_size")
		if node.text == item.text and font_size == item.style: continue
		item.text = node.text
		item.style = font_size
		if item.renderer == null and not Icons.has_keywords(node.text): continue
		if item.renderer == null:
			var renderer := Text.new()
			renderer.name = "KeywordText"
			renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			renderer.mouse_force_pass_scroll_events = true
			if node is Button:
				renderer.offset_left = float(node.get_meta("keyword_left_padding",8))
				renderer.offset_right = -8
				renderer.offset_top = 2
				renderer.offset_bottom = -2
				renderer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				renderer.autowrap_mode = TextServer.AUTOWRAP_OFF
			else:
				renderer.vertical_alignment = node.vertical_alignment
				renderer.autowrap_mode = node.autowrap_mode
			item["color"] = node.get_theme_color("font_color")
			node.add_child(renderer)
			item.renderer = weakref(renderer)
			for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color","font_disabled_color","font_outline_color"]: node.add_theme_color_override(state,Color.TRANSPARENT)
		var rich = item.renderer.get_ref()
		if not is_instance_valid(rich): item.renderer = null; continue
		rich.configure(node.text,font_size,item.color,node.alignment if node is Button else node.horizontal_alignment)
	tracked = alive
