extends "res://tests/support/v2_test.gd"


func _run() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/gdd_content.json"))
	var before := JSON.stringify(raw)
	expect(Catalog.validate(raw).is_empty(), "Legacy fixture rejected.")
	var migrated := Catalog.migrate(raw)
	expect(JSON.stringify(raw) == before and migrated.version == 2, "Migration mutated input or wrong version.")
	expect(migrated.cards[0].positions == ["front", "upper", "lower"], "Rank migration incorrect.")
	expect(migrated.leviathans[0].stances.size() == 6 and migrated.leviathans[0].stances[0].reactions[0].id == "wings", "Legacy behaviours were lost.")
	expect(migrated.setup.positions == ["front", "upper", "rear"], "Formation migration incorrect.")
	expect(Catalog.validate(migrated).is_empty(), "Migrated data invalid.")
	expect(JSON.stringify(migrated) == JSON.stringify(fixture), "Migration differs from the frozen version-2 fixture.")
	for bad in [null, [], {}, {"version": 99}]:
		expect(not Catalog.validate(bad).is_empty(), "Malformed document accepted.")
	var bad := migrated.duplicate(true)
	bad.cards[0].positions = []
	expect(not Catalog.validate(bad).is_empty(), "Empty position list accepted.")
	bad = migrated.duplicate(true)
	bad.setup.positions = ["front", "front", "rear"]
	expect(not Catalog.validate(bad).is_empty(), "Duplicate positions accepted.")
	bad = migrated.duplicate(true)
	bad.leviathans[0].starting_stance = "missing"
	expect(not Catalog.validate(bad).is_empty(), "Missing stance accepted.")
	bad = migrated.duplicate(true)
	bad.cards[0].effects = [1]
	expect(not Catalog.validate(bad).is_empty(), "Malformed effects accepted.")
	bad = migrated.duplicate(true)
	bad.cards[0].triggers = [trigger("bad", "played", [{"kind": "swap_adjacent"}])]
	expect(not Catalog.validate(bad).is_empty(), "Interactive trigger effect accepted.")
	bad = migrated.duplicate(true)
	bad.cards[0].modifiers = [{"stat": "cost", "amount": -1, "tag": "", "condition": {"tag": "", "min": 0}}]
	expect(not Catalog.validate(bad).is_empty(), "Negative modifier accepted.")
	var dir := "user://diamond_content_tests"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/content.json"
	expect(Catalog.save_document(path, raw) == "", "Could not write legacy temporary file.")
	var text_before := FileAccess.get_file_as_string(path)
	var loaded := Catalog.read_document(path)
	expect(loaded.ok and loaded.migrated and loaded.document.version == 2, "Read migration failed.")
	expect(FileAccess.get_file_as_string(path) == text_before, "Read rewrote the version-1 file.")
	expect(Catalog.save_document(path, loaded.document) == "", "Explicit version-2 save failed.")
	expect(Catalog.read_document(path).ok and not Catalog.read_document(path).migrated, "Saved version 2 did not round-trip.")
	text_before = FileAccess.get_file_as_string(path)
	expect(Catalog.save_document(path, bad) != "" and FileAccess.get_file_as_string(path) == text_before, "Rejected save changed file.")
	expect(Catalog.save_document(dir + "/missing/fail.json", fixture) != "", "Failed write reported success.")
	var custom := fixture.duplicate(true)
	custom.setup.fixed_hand = false
	custom.setup.positions = ["rear", "lower", "front"]
	custom.setup.enemy_position = "rear"
	custom.leviathans[0].hull = 120
	var a = State.new(12, custom)
	var b = State.new(12, custom)
	expect(a.hand == b.hand and a.formation == [2, -1, 1, 0] and a.enemy_position == 3, "Seeded random hand or edited positions incorrect.")
	expect(a.monster_hull == 120, "Edited monster hull ignored.")
	custom.ships[0].hull = 99
	expect(a.ships[0].max_hull == 28, "Battle retained editor references.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	done("Content migration and persistence")
