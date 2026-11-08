extends SceneTree
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func frames()->void:await process_frame;await process_frame;await process_frame
func finish()->void:
	print("FORM_UI_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func _run()->void:
	root.size=Vector2i(1152,720)
	var app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames()
	check(app.world.material_ids().has("core:water_crystal"),"trusted_catalog_has_crystal")
	check(app.expedition.status().total==5,"fifth_goal")
	app.open_inventory();check(not app.craft_recipe("carrier:vessel").ok,"no_free_carriers")
	app.new_game("res://content/first_expedition.json");app.open_loom();await frames()
	check(app.loom.document.preset("form").ok,"form_is_editable_graph")
	check(not app.loom.document.validate(app.runtime).ok,"old_scene_cannot_import_new_material")
	app.new_game();app.play.set_paused(false);app.select_tool("mine")
	for p in [Vector2i(0,-2),Vector2i(-1,-2),Vector2i(1,-2),Vector2i(0,-3)]:check(app.act_cell(p).ok,"gather_"+str(p))
	app.open_inventory();check(app.craft_recipe("carrier:vessel").ok,"use_existing_carrier")
	app.open_loom();await frames()
	check(app.loom.document.preset("form").ok and app.loom.document.validate(app.runtime).ok,"form_graph_valid")
	app.loom.open_advanced();await frames()
	check(app.loom.graph.has_node("form") and app.loom._node_ports["form"]==["when"],"typed_native_graph_node")
	check(app.loom.graph.get_node("form").find_children("*","OptionButton",true,false).size()==2,"direction_material_controls")
	app.loom.advanced.hide()
	check(root.get_visible_rect().encloses(app.loom.find_child("ApplyRule",true,false).get_global_rect()),"small_window_apply_visible")
	var before:String=app.workspace_snapshot();var trial:Dictionary=app.loom.preview_graph()
	check(trial.ok and trial.outcome.status=="carried" and app.workspace_snapshot()==before,"preview_no_fake_placement")
	check(app.loom.document.preset("recover").ok and app.loom.document.validate(app.runtime).ok,"recover_graph_valid")
	check(app.save_game("form_ui017").ok and app.load_game("form_ui017").ok,"draft_disk_roundtrip")
	app.open_loom();await frames();check(app.loom.document.node("recover").op=="recover_material","draft_restored")
	for suffix in ["", ".bak", ".tmp"]:
		var p:String=app._files.slot_path("form_ui017")+suffix
		if FileAccess.file_exists(p):DirAccess.remove_absolute(p)
	app.queue_free();await frames();finish()
