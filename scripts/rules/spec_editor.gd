extends VBoxContainer
## Generic typed chunk editor, generated entirely from the registry schema.
signal changed
const R = preload("res://scripts/rules/rule_registry.gd")
var category := ""
var spec: Dictionary = {}
var depth := 0
var backing: Dictionary = {}


func configure(kind: String, value: Dictionary, nesting: int = 0) -> void:
	category = kind
	backing = value
	spec = value.duplicate(true)
	if not changed.is_connected(_commit): changed.connect(_commit)
	depth = nesting
	if category == "condition":
		for group in ["all", "any", "not"]:
			if spec.has(group):
				var children: Variant = spec[group]
				spec.clear()
				spec.merge({"kind": group, "condition": children} if group == "not" else {"kind": group, "items": children})
				break
	_build()


func _commit() -> void:
	backing.clear()
	backing.merge(spec.duplicate(true))


func _clear() -> void:
	for node in get_children():
		remove_child(node)
		node.queue_free()


func _build() -> void:
	_clear()
	add_theme_constant_override("separation", 5)
	if depth > 12:
		var label := Label.new()
		label.text = "Maximum editor nesting reached."
		add_child(label)
		return
	var choices := OptionButton.new()
	choices.fit_to_longest_item = false
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(choices)
	for id in R.ids(category):
		choices.add_item(R.descriptor(category, id).title)
		choices.set_item_metadata(choices.item_count - 1, id)
		if id == spec.get("kind", ""): choices.select(choices.item_count - 1)
	choices.item_selected.connect(func(index):
		spec.clear()
		spec.merge(R.fresh(category, choices.get_item_metadata(index)))
		_build()
		changed.emit())
	var schema: Dictionary = R.descriptor(category, spec.get("kind", "")).get("fields", {})
	for key in schema:
		var meta: Dictionary = schema[key]
		var initial: Variant = spec.get(key, meta.default)
		var row := VBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(row)
		var label := Label.new()
		label.text = key.replace("_", " ").capitalize()
		label.add_theme_font_size_override("font_size", 12)
		label.modulate = Color("#91b9c6")
		row.add_child(label)
		match meta.type:
			"int":
				_integer(row, initial, int(meta.min), func(value): spec[key] = value; changed.emit())
			"string":
				var edit := LineEdit.new()
				edit.text = str(initial)
				row.add_child(edit)
				edit.text_changed.connect(func(value): spec[key] = value; changed.emit())
			"enum", "target":
				var menu := OptionButton.new()
				menu.fit_to_longest_item = false
				row.add_child(menu)
				for item in meta.choices:
					menu.add_item(str(item).replace("_", " ").capitalize() if item != "" else "Any")
					menu.set_item_metadata(menu.item_count - 1, item)
					if initial == item: menu.select(menu.item_count - 1)
				menu.item_selected.connect(func(index): spec[key] = menu.get_item_metadata(index); changed.emit())
			"value":
				_value(row, initial, func(value): spec[key] = value; changed.emit())
			"condition":
				if not spec.has(key): spec[key] = initial.duplicate(true)
				var nested = get_script().new()
				row.add_child(nested)
				nested.configure("condition", spec[key], depth + 1)
				nested.changed.connect(func(): changed.emit())
			"conditions", "values":
				if not spec.has(key): spec[key] = initial.duplicate(true)
				_list(row, key, meta.type)


func _integer(parent: Node, initial: Variant, minimum: int, update: Callable) -> void:
	var control := SpinBox.new()
	control.min_value = minimum
	control.max_value = 99999
	control.allow_greater = false
	control.value = int(initial)
	parent.add_child(control)
	control.value_changed.connect(func(value): update.call(int(value)))


func _value(parent: Node, initial: Variant, update: Callable) -> void:
	var choice := OptionButton.new()
	choice.add_item("Constant amount")
	choice.add_item("Value calculation")
	choice.select(1 if initial is Dictionary else 0)
	parent.add_child(choice)
	choice.item_selected.connect(func(index):
		update.call({"kind": "weapon_damage", "target": "owner"} if index == 1 else 1)
		_build())
	if initial is Dictionary:
		var nested = get_script().new()
		parent.add_child(nested)
		nested.configure("value", initial, depth + 1)
		nested.changed.connect(func(): changed.emit())
	else:
		_integer(parent, initial, 0, update)


func _list(parent: Node, key: String, type: String) -> void:
	var list: Array = spec[key]
	var add := Button.new()
	add.text = "Add condition" if type == "conditions" else "Add value"
	parent.add_child(add)
	add.pressed.connect(func():
		list.append({"kind": "always"} if type == "conditions" else 1)
		_build()
		changed.emit())
	for index in list.size():
		var panel := PanelContainer.new()
		parent.add_child(panel)
		var column := VBoxContainer.new()
		panel.add_child(column)
		var tools := HBoxContainer.new()
		column.add_child(tools)
		for label in ["↑", "↓", "Remove"]:
			var button := Button.new()
			button.text = label
			tools.add_child(button)
			button.pressed.connect(func():
				if label == "Remove": list.remove_at(index)
				else:
					var destination: int = index + (-1 if label == "↑" else 1)
					if destination >= 0 and destination < list.size():
						var item: Variant = list[index]
						list.remove_at(index)
						list.insert(destination, item)
				_build()
				changed.emit())
		if type == "conditions":
			var nested = get_script().new()
			column.add_child(nested)
			nested.configure("condition", list[index], depth + 1)
			nested.changed.connect(func(): changed.emit())
		else:
			_value(column, list[index], func(value): list[index] = value; changed.emit())
