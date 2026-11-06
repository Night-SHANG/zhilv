extends SceneTree
const World = preload("res://runtime/world_session.gd")

func _initialize() -> void:
	var root: String = OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("catalog.json")))
	var text: String = FileAccess.get_file_as_string(root.path_join("world_checkpoint.json"))
	var world = World.new(catalog)
	var result: Dictionary = world.load_checkpoint(text)
	if not result.ok:
		printerr("FAIL: load_world_checkpoint: ", result.error)
		print("WORLD_TEST_RESULT: 0 passed; 1 failed")
		quit(1)
		return
	print("WORLD_TEST_RESULT: 1 passed; 0 failed")
	quit(0)
