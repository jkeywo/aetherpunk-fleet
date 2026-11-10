extends RefCounted
## Original art is addressed by stable content IDs; unknown content keeps a fallback.
static var textures: Dictionary = {}
static var definitions: Dictionary = {}
static var buttons: Dictionary = {}
const ROOT := "res://assets/generated/"

static func texture(path: String) -> Texture2D:
	if not textures.has(path): textures[path] = load(ROOT + path) as Texture2D
	return textures[path]

static func rig(id: String, enemy: bool = false) -> Dictionary:
	if definitions.is_empty():
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "rigs/rigs.json"))
		for entry in document.rigs: definitions[entry.id] = entry
	var key := ("enemy-" if enemy else "ship-") + id.replace("_", "-")
	return definitions.get(key, {})

static func portrait(id: String) -> Texture2D:
	return texture("captains/" + id + ".png") if id in ["iona", "voss", "rook"] else null

static func portrait_view(id: String, minimum: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = portrait(id)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if view.texture != null and minimum.x > minimum.y*1.3:
		var face := AtlasTexture.new()
		face.atlas = view.texture
		face.region = Rect2(0,0,view.texture.get_width(),760)
		view.texture = face
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.custom_minimum_size = minimum if view.texture != null else Vector2.ZERO
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.visible = view.texture != null
	return view

static func button_style(state: String, margins: Vector4) -> StyleBoxTexture:
	if not buttons.has(state):
		var image := texture("ui/button-" + state + ".png").get_image().get_region(Rect2i(80,183,2013,349))
		# Runtime texture sizing preserves the original PNG and keeps nine-slice UI minima small.
		image.resize(320,56,Image.INTERPOLATE_LANCZOS)
		buttons[state] = ImageTexture.create_from_image(image)
	var style := StyleBoxTexture.new()
	style.texture = buttons[state]
	style.texture_margin_left = 18
	style.texture_margin_right = 18
	style.texture_margin_top = 9
	style.texture_margin_bottom = 9
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	return style

static func skin_theme(value: Theme, margins: Vector4 = Vector4(10,6,10,6)) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var skin := button_style("pressed" if state in ["pressed", "hover_pressed"] else ("hover" if state == "hover" else "normal"), margins)
		if state == "disabled": skin.modulate_color = Color(.55,.6,.65,.65)
		value.set_stylebox(state,"Button",skin)
