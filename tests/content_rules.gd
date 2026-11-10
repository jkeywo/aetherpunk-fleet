extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var before: String = FileAccess.get_sha256("res://data/content.json")
	for path in ["res://tests/fixtures/gdd_content.json", "res://tests/fixtures/diamond_content.json"]:
		var text := FileAccess.get_file_as_string(path)
		var source: Dictionary = JSON.parse_string(text)
		expect(Catalog.validate(source).is_empty(), "Legacy content rejected before migration.")
		var migrated := Catalog.migrate(source)
		expect(migrated.version == 3 and Catalog.validate(migrated).is_empty(), "Migration did not create valid version 3.")
		expect(source.version != 3 and FileAccess.get_file_as_string(path) == text, "Read-only migration rewrote input.")
		expect(migrated.cards.map(func(card): return card.id) == source.cards.map(func(card): return card.id), "Migration changed stable card IDs.")
		var b = State.new(3, migrated)
		expect(b.init_error == "" and b.card_keys.size() == 18, "Imported loadout was not preserved.")
		expect(migrated.cards.all(func(card): return card.get("legacy_import", false)), "Imported rule convention was not flagged.")
	expect(Catalog.validate(fixture).is_empty() and fixture.cards.size() == 21 and fixture.captains.size() == 3, "Shipped content invalid or incomplete.")
	expect(fixture.cards.all(func(card): return card.rules.size() >= 2 and card.rules.size() <= 3 and not card.get("legacy_import", false)), "Seeded cards violate 2–3-block convention.")
	for bad in [null, [], {}, {"version": 99}]:
		expect(not Catalog.validate(bad).is_empty(), "Malformed root accepted.")
	var bad := fixture.duplicate(true)
	bad.cards[0].owner = "missing"
	expect(not Catalog.validate(bad).is_empty(), "Missing owner accepted.")
	bad = fixture.duplicate(true)
	bad.cards[0].rules[0].effects[0].kind = "execute_script"
	expect(not Catalog.validate(bad).is_empty(), "Unregistered script effect accepted.")
	bad = fixture.duplicate(true)
	bad.cards[0].rules[0].effects[0].target = "chosen_stance"
	expect(not Catalog.validate(bad).is_empty(), "Incompatible effect target accepted.")
	bad = fixture.duplicate(true)
	bad.ships[0].armour = -1
	expect(not Catalog.validate(bad).is_empty(), "Negative armour accepted.")
	bad = fixture.duplicate(true)
	bad.cards[0].rules = [bad.cards[0].rules[0]]
	expect(Catalog.validate(bad).is_empty(), "Simple one-rule starter card rejected.")
	bad = fixture.duplicate(true)
	bad.setup.fleet[0].captain = bad.setup.fleet[1].captain
	expect(not Catalog.validate(bad).is_empty(), "Duplicate captain accepted.")
	bad = fixture.duplicate(true)
	bad.setup.enemies[1].position = bad.setup.enemies[0].position
	expect(not Catalog.validate(bad).is_empty(), "Overlapping enemies accepted.")
	bad = fixture.duplicate(true)
	bad.setup.opening_hand = ["salvo", "salvo", "salvo", "salvo", "salvo", "salvo", "salvo"]
	expect(not Catalog.validate(bad).is_empty(), "Unavailable fixed-hand copies accepted.")
	bad = fixture.duplicate(true)
	bad.leviathans[0].stance_loadout[0].count = 0
	expect(not Catalog.validate(bad).is_empty(), "Zero enemy copy count accepted.")
	bad = fixture.duplicate(true)
	bad.setup.basic_actions.repair = 0
	expect(not Catalog.validate(bad).is_empty(), "Invalid basic repair accepted.")
	var directory := "user://fleet_v3_tests"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/content.json"
	expect(Catalog.save_document(path, fixture) == "", "Temporary content save failed.")
	var loaded := Catalog.read_document(path)
	expect(loaded.ok and not loaded.migrated and loaded.document == fixture, "Version-3 round trip changed content.")
	var saved_text := FileAccess.get_file_as_string(path)
	expect(Catalog.save_document(path, bad) != "" and FileAccess.get_file_as_string(path) == saved_text, "Invalid save replaced prior content.")
	expect(Catalog.save_document(directory + "/missing/blocked.json", fixture) != "", "Failed write was reported successful.")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ bad")
	file.close()
	expect(not Catalog.read_document(path).ok, "Malformed JSON read succeeded.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	expect(FileAccess.get_sha256("res://data/content.json") == before, "Content tests modified repository data.")
	expect(not Catalog.references(fixture, "cards", "brace").is_empty() and not Catalog.references(fixture, "captains", "iona").is_empty(), "Deletion reference checks missing.")
	done("Content v3 and migrations")
