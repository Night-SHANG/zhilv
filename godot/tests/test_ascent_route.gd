extends "res://tests/test_extended_route.gd"
## 继承前四目标真实输入；不传送、不注入资源、不直接完成目标。
var route_with_stone:bool=false
func finish()->void:
	print("ASCENT_ROUTE_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func jump_toward(target:int)->bool:
	var desired:int=target*1024+512
	var code:Key=KEY_D if app.world.actor_body_foot().x<desired else KEY_A
	key(code,true);key(KEY_SPACE,true);await frames(1);key(KEY_SPACE,false)
	for i in 90:
		if abs(app.world.actor_body_foot().x-desired)<110:
			key(code,false);await frames(45);return true
		await frames(1)
	key(code,false);return false
func apply_form(direction:Vector2i)->bool:
	app.open_loom();await frames(2)
	var made:Dictionary=app.loom.document.preset("form")
	check(made.ok,"formation_editable_graph")
	if not made.ok:return false
	app.loom.document.change_config("target",{"dx":direction.x,"dy":direction.y})
	app.loom.document.change_config("form",{"dx":direction.x,"dy":direction.y,"material":"core:water_crystal"})
	await frames(1)
	var before:String=app.workspace_snapshot()
	await click(app.loom.find_child("PreviewRule",true,false))
	check(app.workspace_snapshot()==before,"preview_does_not_mutate")
	await click(app.loom.find_child("ApplyRule",true,false));app.close_loom();await frames(12)
	return true
func _continue_after_first_section(vessel:String,lamp:String)->void:
	await super._continue_after_first_section(vessel,lamp)
	if failed:return
	check(app.guidance_state().stage=="ascent","fifth_goal_hint")
	if app.guidance_state().stage!="ascent":return
	await click(app._pause_button)
	await cell(Vector2i(8,1),MOUSE_BUTTON_RIGHT);await cell(Vector2i(7,0),MOUSE_BUTTON_RIGHT)
	check(app.world.get_instance(vessel).location.kind=="inventory" and app.world.get_instance(lamp).location.kind=="inventory","reuse_same_objects")
	check(await jump_toward(4),"jump_out_of_lower_corridor")
	check(app.world.actor_cell()==Vector2i(4,0),"native_body_lands_on_upper_floor")
	check(await walk(0),"walk_to_high_route")
	await click(app._tools[4]);await cell(Vector2i(-1,-3));await frames(12)
	check(app.world.get_instance(lamp).location=={"kind":"world","cell":[-1,-3]},"same_lamp_lights_ascent")
	if not route_with_stone:
		app.select_item(vessel);await click(app._tools[3]);await cell(Vector2i(1,-2))
		check(app.world.get_instance(vessel).location=={"kind":"world","cell":[1,-2]},"position_caster")
		if not await apply_form(Vector2i.LEFT):return
		check(app.world.material_at(Vector2i(0,-2))=="core:water_crystal","high_step_from_water")
		await cell(Vector2i(1,-2),MOUSE_BUTTON_RIGHT)
		check(app.world.get_instance(vessel).location.kind=="inventory","caster_recovered_step_remains")
	else:
		await click(app._tools[2]);await cell(Vector2i(0,-2))
		check(app.world.material_at(Vector2i(0,-2))=="core:stone","stone_alternative_high_step")
	check(await walk(3),"walk_to_jump_side")
	if not route_with_stone:
		for i in 20:
			app.select_item(vessel);app.select_tool("collect")
			mouse(app.viewport_canvas.global_position+app.viewport_canvas.cell_center(Vector2i(1,0)))
			app.select_tool("vessel")
			mouse(app.viewport_canvas.global_position+app.viewport_canvas.cell_center(Vector2i(1,0)))
			await frames(1)
			if app.world.get_instance(vessel).location.kind=="world":break
		check(app.world.get_instance(vessel).location=={"kind":"world","cell":[1,0]},"collect_residual_water_before_placement")
		if not await apply_form(Vector2i.UP):return
		check(app.world.material_at(Vector2i(1,-1))=="core:water_crystal","second_step")
		await cell(Vector2i(1,0),MOUSE_BUTTON_RIGHT)
		check(app.world.bound_water_units()==1000 and app.world.total_water_units()==6000,"1000_water_bound_in_two_steps")
	else:
		await click(app._tools[2]);await cell(Vector2i(1,-1))
		check(app.world.material_at(Vector2i(1,-1))=="core:stone" and app.world.stack_count("core:stone")==2,"stone_route_pays_two_stones")
	check(app.save_game("ascent017").ok and app.load_game("ascent017").ok,"mid_route_disk_restore")
	await click(app._pause_button);await frames(2)
	check(await jump_toward(1),"jump_onto_first_real_step")
	check(app.world.actor_cell()==Vector2i(1,-2),"native_body_supported_by_step")
	check(await jump_toward(0),"jump_onto_high_step")
	check(app.expedition.status().completed==["goal:ruins","goal:irrigate","goal:lower_archive","goal:lower_supply","goal:high_observatory"],"five_goals_with_real_position_and_light")
	check(app.world.total_water_units()==6000,"6000_water_conserved")
	check(app.guidance_state().stage=="freeplay","sandbox_remains_open")
	app.play.set_paused(true)
	var env:String="RULEWEAVER_NATIVE_ASCENT_STONE" if route_with_stone else "RULEWEAVER_NATIVE_ASCENT"
	var out:String=OS.get_environment(env)
	if not out.is_empty():
		var f:=FileAccess.open(out,FileAccess.WRITE);check(f!=null,"ascent_evidence_open")
		if f!=null:f.store_string(app.workspace_snapshot());f.close()
	for suffix in ["", ".bak", ".tmp"]:
		var p:String=app._files.slot_path("ascent017")+suffix
		if FileAccess.file_exists(p):DirAccess.remove_absolute(p)
