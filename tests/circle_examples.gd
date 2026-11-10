extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var b = State.new(1,fixture)
	expect(b.init_error == "", "Shipped content invalid.")
	for design in fixture.cards:
		expect(design.rules.size() >= 2 and design.rules.size() <= 3, "Shipped card outside convention: " + design.id)
		expect(not Catalog.present_card(design, 0).effect.is_empty(), "Generated card text empty.")
	var adjacency := false
	var persistence_found := false
	var controls := false
	for design in fixture.cards:
		var text := JSON.stringify(design.rules)
		adjacency = adjacency or "adjacent" in text
		persistence_found = persistence_found or "add_persistence" in text
		controls = controls or "scry" in text
	expect(adjacency and persistence_found and controls, "Shipped examples missing key mechanics.")
	for i in 4:
		expect(Geometry.neighbours(i,false).size() == 2, "Initial graph not cycle.")
	expect(Geometry.neighbours(4,true).size() == 4 and Geometry.neighbours(5,true).size() == 2, "Expanded graph wrong.")
	done("Authored card examples")
