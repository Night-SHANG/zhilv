extends SceneTree
## 将实际运行引擎内置的许可完整写入分发目录，不携带任何系统字体。
func _initialize() -> void:
	var dir: String=OS.get_environment("RULEWEAVER_LICENSE_OUT")
	if dir.is_empty():quit(1);return
	var file:=FileAccess.open(dir.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(Engine.get_license_text());file.close()
	file=FileAccess.open(dir.path_join("GODOT_THIRD_PARTY.json"),FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify({"copyright":Engine.get_copyright_info(),"licenses":Engine.get_license_info()},"\t"));file.close();quit(0)
