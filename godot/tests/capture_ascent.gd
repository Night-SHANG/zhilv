extends "res://tests/test_ascent_route.gd"
## 经完整实际输入流程截图；不是概念图或写入最终世界。
func capture(name:String)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var folder:String=OS.get_environment("RULEWEAVER_CAPTURE_DIR")
	if folder.is_empty():return
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name))==OK,"capture_"+name)
func _continue_after_first_section(vessel:String,lamp:String)->void:
	await super._continue_after_first_section(vessel,lamp)
	if failed:return
	root.size=Vector2i(1440,900);await frames(3);await capture("ascent_complete.png")
	root.size=Vector2i(1152,720);await frames(3);await capture("ascent_small.png")
	app.select_item(vessel);app.open_loom();await frames(3);await capture("formation_loom_small.png")
	app.loom.open_advanced();await frames(5)
	app.loom.graph.arrange_nodes();app.loom.graph.zoom=0.55;app.loom.graph.scroll_offset=Vector2(-20,-20);await frames(5);await capture("formation_graph.png")
	app.loom.advanced.hide();app.close_loom()
