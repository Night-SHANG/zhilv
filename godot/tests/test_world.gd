extends SceneTree
## 原生世界交互测试：不是完整角色物理、规则图或视觉验收。
const World = preload("res://runtime/world_session.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
var passed: int = 0
var failed: int = 0
var notifications: int = 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func _changed(_cells: Array) -> void:
	notifications += 1

func _initialize() -> void:
	var root_path: String = OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root_path.path_join("catalog.json")))
	var text: String = FileAccess.get_file_as_string(root_path.path_join("world_checkpoint.json"))
	var w = World.new(catalog)
	check(w.load_checkpoint(text).ok, "load_world_checkpoint")
	if failed > 0:
		print("WORLD_TEST_RESULT: ", passed, " passed; ", failed, " failed")
		quit(1)
		return
	w.committed.connect(_changed)
	check(w.material_at(Vector2i(1, 3)) == "core:stone", "terrain_query")
	check(w.material_at(Vector2i(3, 2)) == "user:reservoir", "instance_query_uses_same_world")
	check(w.material_at(Vector2i(1, 2)) == "", "empty_cell")
	check(w.stack_count("core:stone") == 8, "vendor_inventory_count")
	check(w.mine(Vector2i(1, 3)).ok, "mine_reachable_tile")
	check(w.material_at(Vector2i(1, 3)) == "" and w.stack_count("core:stone") == 9, "mine_world_inventory_transaction")
	var before: String = w.checkpoint_json()
	check(not w.mine(Vector2i(1, 3)).ok and w.checkpoint_json() == before, "cannot_double_mine")
	check(notifications == 1, "failed_command_does_not_emit")
	check(w.build("core:stone", Vector2i(1, 3)).ok and w.stack_count("core:stone") == 8, "build_consumes_exactly_one")
	before = w.checkpoint_json()
	check(not w.place("creation:002", Vector2i(1, 3)).ok and w.checkpoint_json() == before, "terrain_blocks_creation")
	check(not w.build("core:stone", Vector2i(0, 1)).ok and w.checkpoint_json() == before, "cannot_build_on_actor_head")
	check(not w.build("core:stone", Vector2i(0, 2)).ok and w.checkpoint_json() == before, "cannot_build_on_actor_foot")
	check(not w.build("core:stone", Vector2i(5, 2)).ok and w.checkpoint_json() == before, "out_of_reach_is_atomic")
	check(not w.build("core:missing", Vector2i(1, 2)).ok and w.checkpoint_json() == before, "unknown_material_is_atomic")
	var original: Dictionary = w.get_instance("creation:001")
	check(w.pickup("creation:001").ok, "pickup_through_world_gateway")
	check(w.get_instance("creation:001").state == original.state and w.get_instance("creation:001").rules == original.rules, "pickup_keeps_state_and_program")
	check(w.material_at(Vector2i(3, 2)) == "", "pickup_removes_world_occupancy")
	before = w.checkpoint_json()
	check(not w.pickup("creation:001").ok and w.checkpoint_json() == before, "double_pickup_does_not_duplicate")
	check(w.place("creation:001", Vector2i(1, 2)).ok, "replace_keeps_identity")
	before = w.checkpoint_json()
	check(not w.step_actor(Vector2i.RIGHT).ok and w.checkpoint_json() == before, "creation_blocks_actor")
	check(not w.step_actor(Vector2i(2, 0)).ok and w.checkpoint_json() == before, "cannot_teleport_actor")
	check(w.step_actor(Vector2i.LEFT).ok and w.actor_cell() == Vector2i(-1, 2), "grid_step_negative_coordinates")
	check(w.step_actor(Vector2i.RIGHT).ok, "grid_step_back")
	check(w.build("core:stone", Vector2i(0, 0)).ok, "head_obstacle_setup")
	before = w.checkpoint_json()
	check(not w.step_actor(Vector2i.UP).ok and w.checkpoint_json() == before, "head_collision_checked")
	check(w.pour_water("creation:001", "creation:002", 100).ok, "reachable_world_to_inventory_transfer")
	check(w.get_instance("creation:001").state.water_units == 275 and w.get_instance("creation:002").state.water_units == 100, "transfer_conserves_exact_quantity")
	before = w.checkpoint_json()
	check(not w.pour_water("creation:001", "creation:002", -1).ok and w.checkpoint_json() == before, "invalid_transfer_unchanged")
	check(not w.load_checkpoint(text.replace('"core:stone"', '"unknown:stone"')).ok and w.checkpoint_json() == before, "bad_import_preserves_whole_world")
	var blocked: Dictionary = JSON.parse_string(text)
	blocked.terrain.append({"cell": [1, 2], "material_id": "core:stone"})
	var b = World.new(catalog)
	check(b.load_checkpoint(JSON.stringify(blocked)).ok, "load_wall_fixture")
	var b_before: String = b.checkpoint_json()
	check(not b.pickup("creation:001").ok and b.checkpoint_json() == b_before, "cannot_pickup_through_wall")
	check(not b.pour_water("creation:001", "creation:002", 1).ok and b.checkpoint_json() == b_before, "cannot_transfer_through_wall")
	check(not b.build("core:stone", Vector2i(2, 1)).ok, "diagonal_corner_blocked")
	check(b.mine(Vector2i(1, 2)).ok and b.pickup("creation:001").ok, "remove_wall_then_reach_creation")
	var empty = World.new(catalog)
	check(not empty.mine(Vector2i.ZERO).ok and not empty.pickup("creation:001").ok, "unloaded_world_rejects_commands")
	var corrupt: Dictionary = JSON.parse_string(text)
	corrupt.terrain.append({"cell": [3, 2], "material_id": "core:stone"})
	check(not w.load_checkpoint(JSON.stringify(corrupt)).ok and w.checkpoint_json() == before, "overlap_import_is_atomic")
	var files = Files.new()
	var slot: String = "world_" + str(OS.get_process_id()) + "_" + str(Time.get_ticks_usec())
	check(w.pickup("creation:001").ok and files.save(w, slot).ok, "save_world_after_pickup")
	var disk = World.new(catalog)
	check(files.load_into(disk, slot).ok and disk.checkpoint_json() == w.checkpoint_json(), "whole_world_disk_roundtrip")
	check(disk.place("creation:001", Vector2i(2, 2)).ok, "place_after_reload")
	check(disk.get_instance("creation:001").state.water_units == 275 and disk.get_instance("creation:001").rules == original.rules, "reload_keeps_water_and_rule_versions")
	check(disk.material_at(Vector2i(1, 3)) == "core:stone" and disk.actor_cell() == Vector2i(0, 2), "reload_keeps_terrain_and_actor")
	var exported: String = OS.get_environment("RULEWEAVER_NATIVE_WORLD")
	if not exported.is_empty():
		var out = FileAccess.open(exported, FileAccess.WRITE)
		check(out != null, "world_evidence_open")
		if out != null:
			out.store_string(disk.checkpoint_json())
			out.close()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = files.slot_path(slot) + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("WORLD_TEST_RESULT: ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
