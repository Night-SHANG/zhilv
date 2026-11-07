extends SceneTree
## 实际渲染证据：用正式采集/制作入口准备界面，不写最终库存。
func _initialize()->void:call_deferred("_run")
func capture(file:String)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var code:int=root.get_texture().get_image().save_png(file)
	print("CAPTURE ",file," ",code)
func _run()->void:
	var output:String=OS.get_environment("RULEWEAVER_CAPTURE_DIR")
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var app=load("res://presentation/main.tscn").instantiate();root.size=Vector2i(1440,900);root.add_child(app)
	await process_frame;await physics_frame;await physics_frame
	await capture(output.path_join("fresh_world.png"))
	app.play.set_paused(false);app.select_tool("mine")
	for pos in [Vector2i(0,-2),Vector2i(-1,-2),Vector2i(1,-2),Vector2i(0,-3),Vector2i(-1,-3),Vector2i(1,-3)]:
		var result:Dictionary=app.act_cell(pos)
		if not result.ok:printerr(result);quit(1);return
	app.open_inventory()
	var vessel:Dictionary=app.craft_recipe("carrier:vessel");var lamp:Dictionary=app.craft_recipe("carrier:lamp")
	if not vessel.ok or not lamp.ok:quit(1);return
	app.select_item(vessel.id)
	await capture(output.path_join("inventory.png"))
	root.size=Vector2i(1152,720)
	await capture(output.path_join("inventory_small.png"))
	app.open_loom()
	await capture(output.path_join("crafted_loom_small.png"))
	app.queue_free();await process_frame;quit()
