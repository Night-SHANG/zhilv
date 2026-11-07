extends SceneTree
## 真实引擎截图。预演场景由正式操作准备，后续场景读取实际完整输入回放产物。
func _initialize()->void:call_deferred("run")
func capture(path:String)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var result:int=root.get_texture().get_image().save_png(path)
	if result!=OK:printerr("CAPTURE_FAILED ",path);quit(1)
	print("CAPTURE ",path)
func frames(n:int)->void:
	for i in n:await physics_frame
	await process_frame
func run()->void:
	var dir:String=OS.get_environment("RULEWEAVER_CAPTURE_DIR")
	if dir.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(dir)
	root.size=Vector2i(1440,900)
	var app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames(3)
	await capture(dir.path_join("first_guide.png"))
	app.play.set_paused(false);app.select_tool("mine")
	for cell in [Vector2i(0,-2),Vector2i(-1,-2),Vector2i(1,-2),Vector2i(0,-3),Vector2i(-1,-3),Vector2i(1,-3)]:
		if not app.act_cell(cell).ok:quit(1);return
	app.open_inventory();var vessel:Dictionary=app.craft_recipe("carrier:vessel");var lamp:Dictionary=app.craft_recipe("carrier:lamp")
	if not vessel.ok or not lamp.ok:quit(1);return
	app.select_item(vessel.id);app.close_inventory();app.select_tool("vessel")
	if not app.act_cell(Vector2i(1,-1)).ok:quit(1);return
	await frames(30);app.open_loom();app.loom.document.preset("pump",250);await frames(3)
	var before:String=app.workspace_snapshot()
	var preview:Dictionary=app.loom.preview_graph()
	if not preview.ok or before!=app.workspace_snapshot():quit(1);return
	await capture(dir.path_join("preview.png"))
	root.size=Vector2i(1152,720);await capture(dir.path_join("preview_small.png"))
	app.close_loom()
	var source:String=OS.get_environment("RULEWEAVER_CAPTURE_WORKSPACE")
	if not source.is_empty():
		var Workspace=load("res://presentation/workspace_checkpoint.gd")
		var ws=Workspace.new(app.play);var loaded:Dictionary=ws.load_checkpoint(FileAccess.get_file_as_string(source))
		if not loaded.ok:printerr(loaded);quit(1);return
		app.selected_id=ws.editor.selected;app.tool=ws.editor.tool;app._draft_cache=ws.editor.drafts;app.play.set_paused(true);app._refresh_hud()
		root.size=Vector2i(1440,900);await capture(dir.path_join("lower_completed.png"))
	app.queue_free();await process_frame;quit()
