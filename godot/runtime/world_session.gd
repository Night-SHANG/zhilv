extends RefCounted
## 测试先行的世界适配入口；本提交故意不实现，必须被原生CI断言拒绝。
func _init(_catalog: Dictionary) -> void:
	pass

func load_checkpoint(_text: String) -> Dictionary:
	return {"ok": false, "error": "not_implemented"}
