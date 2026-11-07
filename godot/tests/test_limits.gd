extends SceneTree
## 满库存种类时，世界事务必须正常拒绝而不是访问不存在的校验结果。
const World = preload("res://runtime/world_session.gd")
var passed: int = 0
var failed: int = 0
var changes: int = 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func _changed(_cells: Array) -> void:
	changes += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(10.0).timeout.connect(func():
		printerr("FAIL: limits_suite_did_not_complete")
		quit(1))
	var fixture_root: String = OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_root.path_join("catalog.json")))
	var text: String = FileAccess.get_file_as_string(fixture_root.path_join("world_checkpoint.json"))
	var baseline = World.new(catalog)
	var d: Dictionary = baseline.validate_checkpoint(text).snapshot
	d.entities.stacks = {}
	for i in range(1024):
		var id: String = "core:material" + str(i)
		catalog.materials[id] = {"stackable": true}
		d.entities.stacks[id] = 1
	var world = World.new(catalog)
	check(world.load_checkpoint(JSON.stringify(d)).ok, "load_maximum_stack_kinds")
	world.committed.connect(_changed)
	var before: String = world.checkpoint_json()
	var result: Variant = world.mine(Vector2i(1, 3))
	check(result is Dictionary and result.get("ok") == false, "full_stack_kinds_rejected_normally")
	check(world.checkpoint_json() == before, "full_stack_kinds_preserves_whole_world")
	check(world.material_at(Vector2i(1, 3)) == "core:stone", "full_stack_kinds_does_not_delete_mined_tile")
	check(changes == 0, "full_stack_kinds_does_not_emit_change")
	print("LIMITS_TEST_RESULT: ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
