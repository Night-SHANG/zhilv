extends SceneTree
## 只能由真实 Godot 执行；Python 文件检查不能代替本测试。

const InventoryScript = preload("res://vendor/coheronia/inventory.gd")
const Serializer = preload("res://vendor/coheronia/world_serialize.gd")
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
	print("ENGINE_VERSION: ", Engine.get_version_info().get("string", "unknown"))
	var inv = InventoryScript.new()
	inv.add("core:stone", 3)
	check(inv.count("core:stone") == 3, "ordinary_stack_add")
	check(inv.remove("core:stone", 2) and inv.count("core:stone") == 1, "ordinary_stack_remove")
	check(not inv.remove("core:stone", 2) and inv.count("core:stone") == 1, "insufficient_remove_is_unchanged")
	inv.add("core:wood", 2)
	inv.set_layout(["core:stone", "core:stone", "missing:id"], 3)
	var layout: Array = inv.layout_to_array(3)
	check(layout.count("core:stone") == 1 and layout.count("core:wood") == 1 and not layout.has("missing:id"), "layout_normalization")
	var decoded: Variant = JSON.parse_string(JSON.stringify(inv.to_dict()))
	var restored = InventoryScript.new()
	restored.from_dict(decoded)
	check(restored.count("core:stone") == 1 and restored.count("core:wood") == 2, "count_json_roundtrip")
	var cells := {Vector2i(-2, 5): "core:stone"}
	var encoded: Dictionary = Serializer.encode_cells(cells)
	check(encoded.get("-2,5") == "core:stone", "negative_coordinate_encode")
	check(Serializer.decode_cell_strings(encoded) == cells, "cell_string_roundtrip")
	var levels := {Vector2i(1, 2): 0.5}
	check(Serializer.decode_cell_floats(Serializer.encode_cells(levels)) == levels, "cell_float_roundtrip")
	print("VENDOR_TEST_RESULT: ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
