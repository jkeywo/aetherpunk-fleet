extends "res://tests/support/v3_test.gd"
const Art=preload("res://scripts/art_assets.gd")
func _run() -> void:
	root.size=Vector2i(1280,800)
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	await open_battle(doc)
	var b=current_scene
	for side in [b.allies,b.enemies]:
		for widget in side.widgets.values():
			if not widget.has_meta("ship_index"): continue
			expect(widget.art.rig_node != null and widget.art.rig_node.atlas != null,"Unit is missing generated art.")
			expect(widget.art.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Artwork intercepts native targeting/drag.")
			var rig=widget.art.rig_node
			var parts: Dictionary=rig.part_definitions()
			var okay:=true
			for time in [0,3,8,15]:
				var poses: Dictionary=rig.poses(time)
				for part in rig.definition.parts:
					if part.has("parent") and not part.has("offset"):
						var anchor: Vector2=poses[part.parent]*rig._uv(parts[part.parent],part.anchor)
						okay=okay and anchor.distance_to(poses[part.id].origin)<.0001
			expect(okay,"Live unit limb detached from its parent.")
	expect(b.allies.target_widget(0).get_theme_stylebox("normal") is StyleBoxFlat,"Resetting targeting reverted a unit to command-button art.")
	var elapsed: float=b.allies.target_widget(0).art.rig_node.elapsed
	await flush()
	b._render()
	await flush()
	expect(b.allies.target_widget(0).art.rig_node.elapsed>=elapsed,"Rebuilding units restarted their idle poses.")
	expect("stage-1.png" in b.circle_view.circle_art.texture.resource_path and b.circle_view.buttons.filter(func(button):return button.visible).size()==4,"Four-card stage art or active slots incorrect.")
	b.state.expanded=true
	b._render()
	expect("stage-2.png" in b.circle_view.circle_art.texture.resource_path and b.circle_view.buttons.all(func(button):return button.visible),"Expanded circle art did not unlock nine live targets.")
	for id in ["iona","voss","rook"]:expect(Art.portrait(id)!=null,"Missing captain portrait: "+id)
	expect(Art.rig("custom_ship").is_empty() and Art.portrait("custom_captain")==null,"Custom content did not use safe art fallback.")
	var reused=preload("res://scripts/rig_view.gd").new()
	root.add_child(reused)
	reused.configure("bastion")
	reused.configure("custom_ship")
	expect(reused.rig_node==null,"Custom content retained a previous entry's art.")
	reused.free()
	var normal=b.get_node("%EndPhaseButton").get_theme_stylebox("normal")
	var hover=b.get_node("%EndPhaseButton").get_theme_stylebox("hover")
	var pressed=b.get_node("%EndPhaseButton").get_theme_stylebox("pressed")
	expect(normal is StyleBoxTexture and normal.texture!=hover.texture and normal.texture!=pressed.texture,"Command buttons lost separate normal/hover/pressed assets.")
	root.size=Vector2i(1024,640)
	await flush()
	expect(b.canvas.custom_minimum_size.y>=800,"Small-window battle no longer scrolls to its controls.")
	done("Generated art and native combat integration")
