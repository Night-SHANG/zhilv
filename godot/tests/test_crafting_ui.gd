extends SceneTree
## 新开局的真实Control/键鼠流程；不改写世界终态，也不预先注入工具。
var passed:int=0
var failed:int=0
var app
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func finish()->void:
	print("CRAFTING_UI_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func frames(n:int)->void:
	for i in n:await physics_frame
	await process_frame
func key(code:Key,down:bool)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=down;root.push_input(event)
func mouse(pos:Vector2,button:MouseButton=MOUSE_BUTTON_LEFT)->void:
	var motion:=InputEventMouseMotion.new();motion.position=pos;motion.global_position=pos;root.push_input(motion)
	var event:=InputEventMouseButton.new();event.position=pos;event.global_position=pos;event.button_index=button;event.pressed=true;root.push_input(event)
	event=event.duplicate();event.pressed=false;root.push_input(event)
func click(control:Control)->void:
	mouse(control.get_global_rect().get_center());await process_frame;await process_frame
func cell(pos:Vector2i,button:MouseButton=MOUSE_BUTTON_LEFT)->void:
	mouse(app.viewport_canvas.global_position+app.viewport_canvas.cell_center(pos),button);await frames(1)
func select_list(id:String)->bool:
	var list:ItemList=app.inventory.item_list
	for i in list.item_count:
		if list.get_item_metadata(i)==id:
			mouse(list.global_position+list.get_item_rect(i).get_center());await frames(1);return app.selected_id==id
	return false
func walk(target:int)->bool:
	var desired:int=target*1024+512
	var code:Key=KEY_D if app.world.actor_body_foot().x<desired else KEY_A
	key(code,true)
	for i in 300:
		if abs(app.world.actor_body_foot().x-desired)<110:key(code,false);await frames(1);return true
		await frames(1)
	key(code,false);return false
func _run()->void:
	root.size=Vector2i(1152,720)
	app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames(3)
	check(app.has_method("open_inventory"),"actual_inventory_interface_exists")
	if not app.has_method("open_inventory"):app.queue_free();await process_frame;finish();return
	check(app.setup_complete and app.world.stack_count("core:stone")==0,"fresh_start_no_materials")
	check(app.player_items().is_empty(),"fresh_start_no_free_tools")
	app.open_loom();check(not app.loom.visible,"empty_selection_does_not_open_invalid_loom")
	await click(app._pause_button);await frames(8)
	await click(app._tools[1])
	for p in [Vector2i(0,-2),Vector2i(-1,-2),Vector2i(1,-2),Vector2i(0,-3),Vector2i(-1,-3),Vector2i(1,-3)]:
		await cell(p)
		check(app.world.material_at(p).is_empty(),"real_mouse_mines_%s"%p)
	check(app.world.stack_count("core:stone")==6,"gathered_six_stone_by_input")
	key(KEY_B,true);key(KEY_B,false);await frames(2)
	check(app.inventory.visible and app.runtime.clock_state().paused,"B_opens_paused_inventory")
	var frozen:String=app.play.checkpoint_json()
	key(KEY_D,true);await frames(8);key(KEY_D,false)
	check(app.play.checkpoint_json()==frozen and not app.act_cell(Vector2i(0,1)).ok,"inventory_blocks_world_input")
	check(root.get_visible_rect().encloses(app.inventory.recipe_buttons["carrier:lamp"].get_global_rect()),"small_window_craft_buttons_visible")
	await click(app.inventory.recipe_buttons["carrier:vessel"])
	var vessel:String=app.selected_id
	check(vessel.begins_with("creation:made_") and app.world.stack_count("core:stone")==2,"real_button_crafts_unique_vessel")
	if app.world.get_instance(vessel).is_empty():app.queue_free();await process_frame;finish();return
	await click(app.inventory.recipe_buttons["carrier:lamp"])
	var lamp:String=app.selected_id
	check(lamp!=vessel and app.world.stack_count("core:stone")==0,"real_button_crafts_lamp_no_free_materials")
	check(app.inventory.recipe_buttons["carrier:vessel"].disabled,"unaffordable_craft_disabled")
	check(await select_list(vessel),"actual_inventory_row_selects_specific_instance")
	await click(app.inventory.place_button);await frames(2)
	check(not app.inventory.visible and not app.runtime.clock_state().paused and app.selected_id==vessel,"place_selection_restores_previous_run_state")
	await cell(Vector2i(1,-1))
	check(app.world.get_instance(vessel).location.kind=="world","crafted_vessel_placed_not_fixed_id")
	key(KEY_TAB,true);key(KEY_TAB,false);await frames(2)
	app.loom.document.preset("pump",250);await frames(1)
	await click(app.loom.find_child("ApplyRule",true,false))
	check(app.world.get_instance(vessel).rules.size()==1,"created_vessel_receives_authored_behavior")
	# 把一个尚未连线的动作留在草稿中；保存不能偷偷发布这段不完整规则。
	app.loom.document.add("set_light")
	var draft:Dictionary=app.loom.document.snapshot()
	check(not app.loom.document.validate(app.runtime).ok,"unfinished_draft_remains_unpublishable")
	check(app.save_game("fresh_route014").ok,"save_unfinished_draft_and_world_together")
	check(app.load_game("fresh_route014").ok,"load_complete_workspace")
	app.open_loom();await frames(2)
	check(app.loom.document.snapshot()==draft,"incomplete_draft_restored_exactly")
	check(app.world.get_instance(vessel).rules.size()==1,"loading_draft_does_not_publish")
	app.close_loom();await click(app._pause_button)
	for i in 2400:
		if app.world.get_instance(vessel).state.water_units>=5000:break
		await frames(1)
	check(app.world.get_instance(vessel).state.water_units>=5000,"crafted_authored_pump_drains_real_water")
	await cell(Vector2i(1,-1),MOUSE_BUTTON_RIGHT)
	check(app.world.get_instance(vessel).location.kind=="inventory","recover_same_filled_instance")
	await frames(480)
	check(await walk(6),"fresh_player_crosses_drained_passage")
	await click(app._tools[4]);await cell(Vector2i(9,-1));await frames(12)
	check(app.world.get_instance(lamp).location.kind=="world" and app.world.get_instance(lamp).state.light_on,"crafted_lamp_not_named_fixture_illuminates")
	check(await walk(8),"fresh_player_reaches_ruins")
	check(app.expedition.status().completed.has("goal:ruins"),"same_goal_accepts_crafted_tools")
	check(await walk(-2),"fresh_player_returns_to_camp")
	app.select_item(vessel)
	await click(app.find_child("DeliverWater",true,false))
	check(app.expedition.status().completed==["goal:ruins","goal:irrigate"],"gather_craft_program_explore_deliver_complete")
	check(app.world.total_water_units()==6000,"complete_fresh_loop_conserves_6000_water")
	check(app.world.get_instance(lamp).state.water_units==0,"distinct_carriers_do_not_share_state")
	app.open_inventory();await frames(2)
	check(app.inventory.item_list.item_count==1,"inventory_lists_carried_not_world_items")
	var out:String=OS.get_environment("RULEWEAVER_NATIVE_FRESH_PLAY")
	if not out.is_empty():
		var f:=FileAccess.open(out,FileAccess.WRITE)
		check(f!=null,"fresh_evidence_open")
		if f!=null:f.store_string(app.workspace_snapshot());f.close()
	for suffix in ["", ".bak", ".tmp"]:
		var path:String=app._files.slot_path("fresh_route014")+suffix
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	app.queue_free();await frames(2);finish()
