extends SceneTree
## 原生实例生命周期回归。没有图形、地形或规则执行，不能代替可玩性验收。
const Store = preload("res://runtime/instance_store.gd")
const Codec = preload("res://runtime/snapshot_codec.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
var passed: int = 0
var failed: int = 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var root: String = OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("catalog.json")))
	var text: String = FileAccess.get_file_as_string(root.path_join("checkpoint.json"))
	if not catalog is Dictionary or text.is_empty():
		printerr("Missing fixtures")
		quit(1)
		return
	var store = Store.new(catalog)
	check(store.load_checkpoint(text).ok, "load_existing_wire_contract")
	var original: Dictionary = store.get_instance("creation:001")
	check(store.pickup("creation:001", "player:local").ok, "pickup_world_instance")
	check(store.get_instance("creation:001").state == original.state, "pickup_keeps_water_and_light")
	check(store.get_instance("creation:001").rules == original.rules, "pickup_keeps_rule_versions")
	var held: String = store.checkpoint_json()
	check(not store.pickup("creation:001", "player:local").ok and store.checkpoint_json() == held, "double_pickup_rejected_without_change")
	check(not store.place("creation:001", "player:other", Vector2i(5, 2)).ok and store.checkpoint_json() == held, "wrong_owner_rejected_without_change")
	var restored = Store.new(catalog)
	check(restored.load_checkpoint(held).ok and restored.get_instance("creation:001").state == original.state, "inventory_checkpoint_roundtrip")
	check(restored.place("creation:001", "player:local", Vector2i(-5, 2)).ok, "place_on_negative_coordinate")
	var before: String = restored.checkpoint_json()
	check(not restored.place("creation:002", "player:local", Vector2i(-5, 2)).ok and restored.checkpoint_json() == before, "occupied_cell_is_atomic")
	check(not restored.place("creation:002", "player:local", Vector2i(1000001, 0)).ok, "coordinate_bounds")
	check(not restored.transfer_water("creation:001", "creation:002", -1).ok, "negative_transfer_rejected")
	check(not restored.transfer_water("creation:001", "creation:001", 1).ok, "self_transfer_rejected")
	check(not restored.transfer_water("creation:001", "creation:002", 999).ok and restored.checkpoint_json() == before, "insufficient_transfer_is_atomic")
	check(restored.transfer_water("creation:001", "creation:002", 100).ok, "integer_water_transfer")
	check(restored.get_instance("creation:001").state.water_units == 275 and restored.get_instance("creation:002").state.water_units == 100, "water_total_is_conserved")
	var leaked: Dictionary = restored.get_instance("creation:001")
	leaked.state.water_units = 999
	check(restored.get_instance("creation:001").state.water_units == 275, "read_returns_deep_copy")
	check(restored.change_stack("core:stone", 2).ok and restored.stack_count("core:stone") == 10, "vendor_inventory_add")
	check(restored.change_stack("core:stone", -3).ok and restored.stack_count("core:stone") == 7, "vendor_inventory_remove")
	check(not restored.change_stack("user:reservoir", 1).ok, "stateful_material_cannot_stack")
	check(not restored.change_stack("core:stone", -99).ok and restored.stack_count("core:stone") == 7, "inventory_underflow_is_atomic")
	before = restored.checkpoint_json()
	check(not restored.load_checkpoint(text.replace('"water_units": 375', '"water_units": true')).ok and restored.checkpoint_json() == before, "bad_import_keeps_current_world")
	check(not Codec.decode(text.replace('"water_units": 375', '"water_units": 0, "water_units": 375'), catalog).ok, "duplicate_json_key")
	check(not Codec.decode(text.replace('"water_units": 375', '"water_units": 375.0'), catalog).ok, "fractional_syntax_rejected")
	check(not Codec.decode(text.replace('"water_units": 375', '"water_units": 3.75e2'), catalog).ok, "exponent_syntax_rejected")
	check(not Codec.decode(text.replace('"water_units": 375', '"water_units": NaN'), catalog).ok, "nonfinite_rejected")
	check(not Codec.decode(text.replace('"version": 1', '"version": 99'), catalog).ok, "missing_dependency")
	check(not Codec.decode(text.replace('"creation:002"', '"creation:001"'), catalog).ok, "duplicate_identity")
	check(not Codec.decode("[".repeat(17) + "0" + "]".repeat(17), catalog).ok, "depth_budget")
	check(not Codec.decode(" ".repeat(1048577), catalog).ok, "byte_budget")
	check(not Codec.decode(text.replace('"light_on": false', '"light_on": false, "script": "unsafe"'), catalog).ok, "unknown_fields_rejected")
	var files = Files.new()
	var slot: String = "test_" + str(OS.get_process_id()) + "_" + str(Time.get_ticks_usec())
	check(not files.save(restored, "../escape").ok, "save_path_traversal_rejected")
	check(files.save(restored, slot).ok, "save_first_checkpoint")
	var disk = Store.new(catalog)
	check(files.load_into(disk, slot).ok and disk.checkpoint_json() == restored.checkpoint_json(), "disk_roundtrip_keeps_state_and_ownership")
	var backup_text: String = disk.checkpoint_json()
	check(restored.transfer_water("creation:001", "creation:002", 1).ok and files.save(restored, slot).ok, "second_save_creates_previous_backup")
	var handle = FileAccess.open(files.slot_path(slot), FileAccess.WRITE)
	if handle != null:
		handle.store_string("{broken")
		handle.close()
	var recovered: Dictionary = files.load_into(disk, slot, true)
	check(recovered.ok and recovered.get("recovered", false) and disk.checkpoint_json() == backup_text, "corrupt_primary_recovers_backup_explicitly")
	check(not files.save(restored, slot).ok, "refuse_overwrite_corrupt_primary")
	var missing_before: String = disk.checkpoint_json()
	check(not files.load_into(disk, slot + "_missing").ok and disk.checkpoint_json() == missing_before, "missing_save_does_not_reset_world")
	# 只清理本测试刚创建的随机槽位，不接触玩家其他文件。
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = files.slot_path(slot) + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var evidence: String = OS.get_environment("RULEWEAVER_NATIVE_CHECKPOINT")
	if not evidence.is_empty():
		var out = FileAccess.open(evidence, FileAccess.WRITE)
		check(out != null, "evidence_file_open")
		if out != null:
			out.store_string(restored.checkpoint_json())
			out.close()
	print("LIFECYCLE_TEST_RESULT: ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
