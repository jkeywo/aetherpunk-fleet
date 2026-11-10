extends VBoxContainer
signal changed
const R = preload("res://scripts/rules/rule_registry.gd")
const Spec = preload("res://scripts/rules/spec_editor.gd")
var rule: Dictionary = {}
var backing: Dictionary = {}


func configure(value: Dictionary) -> void:
	backing = value
	rule = value.duplicate(true)
	if not changed.is_connected(_commit): changed.connect(_commit)
	_build()


func _commit() -> void:
	backing.clear()
	backing.merge(rule.duplicate(true))


func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color("#d6adee")
	parent.add_child(label)


func _build() -> void:
	for node in get_children():
		remove_child(node)
		node.queue_free()
	add_theme_constant_override("separation", 7)
	_label(self, "RULE / " + str(rule.get("id", "")))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Optional rule name"
	name_edit.text = rule.get("name", "")
	add_child(name_edit)
	name_edit.text_changed.connect(func(value): rule.name = value; changed.emit())
	var controls := HBoxContainer.new()
	add_child(controls)
	_menu(controls, R.ZONES, rule.get("zone", "circle"), func(value): rule.zone = value; changed.emit())
	_menu(controls, R.LIMITS, rule.get("limit", "once_per_action"), func(value): rule.limit = value; changed.emit())
	var optional := CheckBox.new()
	optional.text = "Optional boost"
	optional.button_pressed = rule.get("optional", false)
	add_child(optional)
	optional.toggled.connect(func(value): rule.optional = value; changed.emit())
	_label(self, "TRIGGER")
	var trigger := Spec.new()
	add_child(trigger)
	var previous: String = rule.trigger.kind
	trigger.configure("trigger", rule.trigger)
	trigger.changed.connect(func():
		if previous != rule.trigger.kind:
			if rule.trigger.kind == "passive": rule.effects = []
			else: rule.modifiers = []
			_build.call_deferred()
		changed.emit())
	_label(self, "CONDITIONS")
	var condition := Spec.new()
	add_child(condition)
	if not rule.has("conditions"): rule.conditions = {"kind": "always"}
	condition.configure("condition", rule.conditions)
	condition.changed.connect(func(): changed.emit())
	if rule.trigger.kind == "passive":
		_list(self, "modifier", "modifiers")
	else:
		_list(self, "cost", "costs")
		_list(self, "effect", "effects")


func _menu(parent: Node, values: Array, initial: String, update: Callable) -> void:
	var menu := OptionButton.new()
	menu.fit_to_longest_item = false
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(menu)
	for value in values:
		menu.add_item(str(value).replace("_", " ").capitalize())
		menu.set_item_metadata(menu.item_count - 1, value)
		if value == initial: menu.select(menu.item_count - 1)
	menu.item_selected.connect(func(index): update.call(menu.get_item_metadata(index)))


func _list(parent: Node, category: String, key: String) -> void:
	if not rule.has(key): rule[key] = []
	_label(parent, key.to_upper())
	var add := Button.new()
	add.text = "Add " + category
	parent.add_child(add)
	add.pressed.connect(func():
		var kind: String = {"cost": "ship_resource", "effect": "add_shields", "modifier": "armour"}[category]
		rule[key].append(R.fresh(category, kind))
		_build()
		changed.emit())
	for index in rule[key].size():
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
				var list: Array = rule[key]
				if label == "Remove": list.remove_at(index)
				else:
					var destination: int = index + (-1 if label == "↑" else 1)
					if destination >= 0 and destination < list.size():
						var value: Variant = list[index]
						list.remove_at(index)
						list.insert(destination, value)
				_build()
				changed.emit())
		var component := Spec.new()
		column.add_child(component)
		component.configure(category, rule[key][index])
		component.changed.connect(func(): changed.emit())
