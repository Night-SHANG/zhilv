extends SceneTree
## 可选的真实渲染证据。只写显式指定的测试目录，不是概念图生成器。
func _initialize() -> void:call_deferred("_run")
func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	var code: int=image.save_png(path)
	print("CAPTURE: ",path," code=",code)
func _run() -> void:
	var output: String=OS.get_environment("RULEWEAVER_CAPTURE_DIR")
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1440,900)
	var app=load("res://presentation/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	await capture(output.path_join("world.png"))
	app.open_loom();await process_frame;await process_frame
	await capture(output.path_join("loom.png"))
	app.loom.open_advanced();await process_frame;await process_frame
	await capture(output.path_join("graph.png"))
	app.loom.advanced.hide()
	root.size=Vector2i(1152,720);await process_frame;await process_frame
	await capture(output.path_join("loom_small.png"))
	app.queue_free();await process_frame;await process_frame;quit()
