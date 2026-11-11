extends Control
## Runtime composition preserves the exact existing card-type glyphs.
const Rules = preload("res://scripts/rules/rule_registry.gd")
const Icons = preload("res://scripts/keyword_icons.gd")
const ROOT := "res://assets/generated/reactions/"
var condition: Dictionary = {}
var glyph: Texture2D
var lower_glyph: Texture2D
var border: Texture2D
var key := ""
var glyph_fraction := 0.56

func configure(spec: Dictionary, extent: int = 36) -> void:
	condition=spec.duplicate(true)
	set_meta("reaction_badge",true)
	custom_minimum_size=Vector2(extent,extent)
	size=custom_minimum_size
	mouse_filter=Control.MOUSE_FILTER_PASS
	var family: String=spec.get("family","card_type")
	glyph_fraction=0.56 if family=="card_type" else (0.64 if family=="position" else 0.60)
	key=str(spec.get("card_type","Attack")).to_lower() if family=="card_type" else (str(spec.get("position","front")) if family=="position" else family)
	border=load(ROOT+"border.png")
	lower_glyph = null
	match family:
		"card_type":
			glyph = Icons.texture(key)
		"position":
			key = Rules.reaction_position(key)
			# A position trigger always refers to the player's formation.
			glyph = Icons.texture("upper" if key == "flank" else key)
			if key == "flank": lower_glyph = Icons.texture("lower")
		_:
			glyph = load(ROOT + key + ".png")
	tooltip_text=description()
	queue_redraw()

func description() -> String:
	match condition.get("family","card_type"):
		"card_type":return "After you play " + ("an " if condition.get("card_type","Attack")=="Attack" else "a ") + condition.get("card_type","Attack") + " card. Payment discards and basic actions do not count."
		"position":return "After you play a card from " + Rules.common_reaction_text(condition).replace("Played card from ", "") + ". Uses the ship's position before the card moves it."
		"damaged":return "After this enemy loses hull during your action. Fully blocked hits do not count."
		"healed":return "After a player ship actually regains hull, including basic repairs and revival. Repairing full hull does not count."
	return Rules.common_reaction_text(condition)

func _draw() -> void:
	if glyph != null:
		var bounds := Rect2(size * ((1.0 - glyph_fraction) / 2.0), size * glyph_fraction)
		if lower_glyph == null:
			draw_texture_rect(glyph, bounds, false)
		else:
			var upper_size := glyph.get_size() * Vector2(1, 0.5)
			var lower_size := lower_glyph.get_size() * Vector2(1, 0.5)
			var half := bounds.size * Vector2(1, 0.5)
			draw_texture_rect_region(glyph, Rect2(bounds.position, half), Rect2(Vector2.ZERO, upper_size))
			draw_texture_rect_region(lower_glyph, Rect2(bounds.position + Vector2(0, half.y), half), Rect2(Vector2(0, lower_size.y), lower_size))
	if border!=null:draw_texture_rect(border,Rect2(Vector2.ZERO,size),false)
