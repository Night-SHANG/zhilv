extends SceneTree
## 真实原生规则行为测试；不以Python模拟替代Godot执行。
const Codec = preload("res://runtime/snapshot_codec.gd")
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
var passed: int = 0
var failed: int = 0
var catalog: Dictionary
var pack_text: String
var world_text: String

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func fixture() -> Array:
	var w = World.new(catalog)
	check(w.load_checkpoint(world_text).ok, "world_fixture_load")
	var r = Runtime.new(catalog, w)
	check(r.install_pack(pack_text).ok, "install_rule_pack")
	return [w, r]

func normalized(v: Variant) -> Variant:
	# 仅测试辅助：正常JSON整数由Godot解析为float，构造修改样例前恢复整数。
	if v is Dictionary:
		var d: Dictionary = {}
		for k in v:
			d[k] = normalized(v[k])
		return d
	if v is Array:
		var a: Array = []
		for item in v:
			a.append(normalized(item))
		return a
	return int(v) if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floor(v) else v

func pack_data() -> Dictionary:
	return normalized(JSON.parse_string(pack_text))

func rejected_pack(r, p: Dictionary, label: String, expected_error: String) -> void:
	var before: String = r.pack_json()
	var result: Dictionary = r.install_pack(JSON.stringify(p))
	check(not result.ok and result.get("error") == expected_error, label + ": " + str(result.get("error", "")))
	check(r.pack_json() == before, label + "_preserves_installed_pack")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(30.0).timeout.connect(func():
		printerr("FAIL: rules_suite_timeout")
		quit(1))
	var root: String = OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	catalog = normalized(JSON.parse_string(FileAccess.get_file_as_string(root.path_join("rules_catalog.json"))))
	pack_text = FileAccess.get_file_as_string(root.path_join("rules_pack.json"))
	world_text = FileAccess.get_file_as_string(root.path_join("rules_world.json"))
	var w = World.new(catalog)
	var initial: Dictionary = w.load_checkpoint(world_text)
	check(initial.ok, "initial_world: " + str(initial.get("error", "")))
	var r = Runtime.new(catalog, w)
	var installed: Dictionary = r.install_pack(pack_text)
	check(installed.ok, "install_typed_rule_graph: " + str(installed.get("error", "")))
	if not installed.ok:
		finish()
		return

	check(Codec.has_version([1], 1), "native_integer_catalog_version")
	check(Codec.has_version([1.0], 1), "parsed_json_catalog_version")
	check(not Codec.has_version([1.5], 1), "fractional_catalog_version_not_coerced")
	check(not Codec.has_version([true], 1), "boolean_catalog_version_not_coerced")
	var p: Dictionary = pack_data()
	p.modules[0].nodes[0].op = "execute_script"
	rejected_pack(r, p, "reject_unknown_primitive", "unknown_primitive")
	p = pack_data()
	p.modules[0].nodes[2].inputs.value = "missing"
	rejected_pack(r, p, "reject_missing_port_source", "missing_reference_or_type_mismatch")
	p = pack_data()
	p.modules[2].nodes[1].op = "bool"
	p.modules[2].nodes[1].config.value = true
	rejected_pack(r, p, "reject_call_argument_type_mismatch", "missing_reference_or_type_mismatch")
	p = pack_data()
	p.modules[0].nodes[0] = {"id":"night","op":"not","inputs":{"value":"night"},"config":{}}
	rejected_pack(r, p, "reject_data_cycle", "data_cycle")
	p = pack_data()
	p.modules[2].nodes[2].config.id = "user:absorb"
	p.modules[2].nodes[2].inputs.erase("amount")
	rejected_pack(r, p, "reject_recursive_behavior", "recursive_call")
	p = pack_data()
	p.modules[2].nodes[2].config.version = 99
	rejected_pack(r, p, "reject_missing_module_version", "missing_call_version")
	p = pack_data()
	p.modules[0].nodes.append(p.modules[0].nodes[0].duplicate(true))
	rejected_pack(r, p, "reject_duplicate_node", "node_fields_or_duplicate")
	p = pack_data()
	p.modules[0].nodes[0].extra = true
	rejected_pack(r, p, "reject_unknown_node_field", "node_fields_or_duplicate")
	p = pack_data()
	p.modules[0].effects = ["night"]
	rejected_pack(r, p, "reject_value_used_as_effect", "invalid_effect_entry")
	p = pack_data()
	p.modules[0].nodes[2].inputs.when = "lamp"
	rejected_pack(r, p, "reject_effect_as_input", "missing_reference_or_type_mismatch")
	p = pack_data()
	p.modules[3].nodes[1].config.dx = 2
	rejected_pack(r, p, "reject_nonlocal_move", "invalid_move_step")
	p = pack_data()
	p.modules[0].nodes[1].config.value = false
	rejected_pack(r, p, "reject_same_version_content_replacement", "version_content_conflict")
	p = pack_data()
	p.modules.remove_at(0)
	rejected_pack(r, p, "reject_removing_referenced_rule", "missing_bound_rule_version")
	check(not r.install_pack('{"format":"rw.rules/0.1","format":"rw.rules/0.1","modules":[]}').ok, "duplicate_json_key")
	check(not r.install_pack(pack_text.replace('"version": 1', '"version": 1.5')).ok, "fractional_version_rejected")
	check(not r.install_pack(" ".repeat(262145)).ok, "pack_byte_budget")

	var result: Dictionary = r.advance(false)
	check(result.ok and result.errors.is_empty(), "day_tick_without_errors")
	check(w.get_instance("creation:001").state.water_units == 100, "parameterized_submodule_transfers_water")
	check(w.get_instance("creation:002").state.water_units == 400, "source_loses_exact_same_water")
	check(not w.get_instance("creation:001").state.light_on, "day_light_off")
	result = r.advance(true)
	check(result.ok and result.errors.is_empty(), "night_tick_without_errors")
	check(w.get_instance("creation:001").state.light_on, "night_light_on")
	check(w.get_instance("creation:003").state.light_on, "same_graph_different_material")
	check(not w.get_instance("creation:004").state.light_on, "inventory_instances_sleep")
	check(w.get_instance("creation:001").state.water_units == 200, "repeated_execution_uses_new_snapshot")

	var replay: Array = fixture()
	replay[1].advance(false)
	replay[1].advance(true)
	check(replay[1].checkpoint_json() == r.checkpoint_json(), "deterministic_replay")
	var before: String = w.checkpoint_json()
	result = r.advance(false, 1)
	check(result.ok and not result.errors.is_empty(), "per_instance_instruction_budget_reports_failure")
	check(w.checkpoint_json() == before, "budget_failure_discards_entire_instance_plan")
	before = r.checkpoint_json()
	check(not r.advance(false, 512, 1).ok, "total_tick_budget_rejects_step")
	check(r.checkpoint_json() == before, "total_budget_has_no_partial_commit_or_tick")
	check(not r.advance("night").ok, "context_type_not_coerced")

	check(w.pickup("creation:001").ok, "pickup_programmed_instance")
	var water_before: int = w.get_instance("creation:001").state.water_units
	r.advance(false)
	check(w.get_instance("creation:001").state.water_units == water_before, "picked_up_program_does_not_run")
	var files = Files.new()
	var slot: String = "rules_test_" + str(OS.get_process_id())
	check(files.save(r, slot).ok, "save_world_and_rules_together")
	var restored_world = World.new(catalog)
	var restored = Runtime.new(catalog, restored_world)
	check(files.load_into(restored, slot).ok, "restore_rules_and_world_from_disk")
	check(restored.checkpoint_json() == r.checkpoint_json(), "graph_tick_and_state_roundtrip")
	check(restored_world.place("creation:001", Vector2i(3,2)).ok, "replace_saved_creation")
	result = restored.advance(false)
	check(result.ok and result.errors.is_empty(), "restored_graph_continues_execution")
	check(restored_world.get_instance("creation:001").state.water_units == water_before + 100, "restored_program_retains_resource_state")
	before = restored.checkpoint_json()
	check(not restored.load_checkpoint('{"format":"unknown"}').ok, "corrupt_runtime_restore_rejected")
	check(restored.checkpoint_json() == before, "failed_restore_preserves_running_state")
	var evidence: String = OS.get_environment("RULEWEAVER_NATIVE_RULES")
	if not evidence.is_empty():
		var f = FileAccess.open(evidence, FileAccess.WRITE)
		check(f != null, "rules_evidence_open")
		if f != null:
			f.store_string(restored.checkpoint_json())
			f.close()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = files.slot_path(slot) + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	var moving: Array = fixture()
	var d: Dictionary = normalized(JSON.parse_string(world_text))
	d.entities.instances[0].rules = [{"id":"user:drift","version":1},{"id":"user:night_light","version":1}]
	check(moving[0].load_checkpoint(JSON.stringify(d)).ok, "moving_fixture")
	check(moving[1].advance(true).ok, "move_and_light_tick")
	check(moving[0].get_instance("creation:001").location.cell == [3,3], "move_one_cell")
	var entity_before: Dictionary = moving[0].get_instance("creation:001")
	result = moving[1].advance(false)
	check(not result.errors.is_empty(), "collision_reported")
	check(moving[0].get_instance("creation:001") == entity_before, "collision_rolls_back_light_and_move")
	var own: Array = fixture()
	before = own[0].checkpoint_json()
	check(not own[0].apply_rule_commands("creation:001", [{"op":"set_water","value":999}]).ok, "forbid_arbitrary_state_write")
	check(not own[0].apply_rule_commands("creation:004", [{"op":"set_light","value":true}]).ok, "forbid_inventory_rule_execution")
	check(not own[0].apply_rule_commands("creation:003", [{"op":"take_water","source":"creation:002","amount":1}]).ok, "forbid_remote_water_transfer")
	check(own[0].checkpoint_json() == before, "rejected_world_commands_preserve_state")
	var reentry: Dictionary = {}
	var callback: Callable = func(_cells: Array): reentry["result"] = own[1].advance(false)
	own[0].committed.connect(callback)
	check(own[1].advance(true).ok, "outer_tick_runs")
	check(reentry.has("result") and reentry.result.get("error") == "runtime_busy", "reject_reentrant_tick")
	own[0].committed.disconnect(callback)
	finish()

func finish() -> void:
	print("RULES_TEST_RESULT: ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
