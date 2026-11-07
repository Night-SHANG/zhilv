extends SceneTree
## 捕捉实际Godot界面；通过正式词条API准备内容，不添加生成概念图片。
func _initialize()->void:call_deferred("_run")
func frames()->void:await process_frame;await process_frame;await process_frame
func capture(path:String)->void:
	await frames();await RenderingServer.frame_post_draw
	var result:int=root.get_texture().get_image().save_png(path)
	print("CAPTURE ",path," ",result)
func _run()->void:
	var output:String=OS.get_environment("RULEWEAVER_CAPTURE_DIR")
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1440,900)
	var app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames()
	app.play.set_paused(false);app.select_tool("mine")
	for cell in [Vector2i(0,-2),Vector2i(-1,-2),Vector2i(1,-2),Vector2i(0,-3),Vector2i(-1,-3),Vector2i(1,-3)]:
		if not app.act_cell(cell).ok:quit(1);return
	app.open_inventory()
	var vessel:Dictionary=app.craft_recipe("carrier:vessel")
	if not vessel.ok or not app.craft_recipe("carrier:lamp").ok:quit(1);return
	app.select_item(vessel.id);app.open_loom();await frames()
	var panel=app.loom
	panel.document.preset("pump",125);panel.document.expose_constant("rate","rate");panel.word_name.text="user:water_pump"
	if not panel.publish_word_named().ok:quit(1);return
	panel.document.preset("lamp");panel.word_name.text="user:dark_lamp"
	if not panel.publish_word_named().ok:quit(1);return
	panel.document.preset("blank");panel.document.append_word(app.runtime,"user:water_pump",1);panel.document.append_word(app.runtime,"user:dark_lamp",1)
	await frames();panel._content_scroll.scroll_vertical=120
	await capture(output.path_join("words.png"))
	root.size=Vector2i(1152,720);await frames();panel._content_scroll.scroll_vertical=160
	await capture(output.path_join("words_small.png"))
	panel.open_advanced();await frames()
	await capture(output.path_join("word_graph_initial.png"))
	panel.graph.arrange_nodes();panel.graph.zoom=0.55;panel.graph.scroll_offset=Vector2(-20,-20);await frames()
	await capture(output.path_join("word_graph_arranged.png"))
	panel.advanced.hide();panel.document.preset("pump",125);panel.document.expose_constant("rate","rate");await frames();panel.open_advanced();await frames()
	var nodes:Array=[]
	for child in panel.graph.get_children():
		if child is GraphNode:nodes.append(child)
	var overlaps:Array=[]
	for i in nodes.size():
		for j in range(i+1,nodes.size()):
			if nodes[i].get_global_rect().grow(-1).intersects(nodes[j].get_global_rect().grow(-1)):overlaps.append([String(nodes[i].name),String(nodes[j].name)])
	print("GRAPH_OVERLAPS ",overlaps)
	await capture(output.path_join("parameter_graph_initial.png"))
	app.queue_free();await frames();quit()
