extends "res://tests/test_crafting_ui.gd"
## 复用首段真实键鼠路径，再继续同一世界；不另送材料、造物或水。
func finish()->void:
	print("EXTENDED_ROUTE_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func _continue_after_first_section(vessel:String,lamp:String)->void:
	check(app.guidance_state().stage=="lower","first_delivery_opens_next_exploration_hint")
	var carried_rules:Array=app.world.get_instance(vessel).rules.duplicate(true)
	app.close_inventory();await frames(2)
	check(await walk(6),"walk_back_to_lower_access")
	await cell(Vector2i(9,-1),MOUSE_BUTTON_RIGHT)
	check(app.world.get_instance(lamp).location.kind=="inventory","reuse_same_lamp_for_next_section")
	await click(app._tools[1]);await cell(Vector2i(6,1));await frames(180)
	check(app.world.actor_cell()==Vector2i(6,2),"dig_floor_and_reach_lower_passage_with_real_gravity")
	for p in [Vector2i(5,1),Vector2i(7,1),Vector2i(8,1)]:
		await cell(p);check(app.world.material_at(p).is_empty(),"excavate_lower_headroom_%s"%p)
	await click(app._tools[4]);await cell(Vector2i(7,0));await frames(12)
	print("LOWER_LAMP_INPUT: ",app._last_status)
	check(app.world.get_instance(lamp).location.kind=="world" and app.world.get_instance(lamp).state.light_on,"same_lamp_lights_lower_passage")
	check(app.expedition.status().completed==["goal:ruins","goal:irrigate","goal:lower_archive"],"lower_visit_requires_actual_position_and_light")
	check(app.guidance_state().stage=="supply","guidance_switches_to_result_based_supply")
	check(app.save_game("extended015").ok,"save_between_followup_objectives")
	check(app.load_game("extended015").ok,"restore_followup_progress")
	check(app.expedition.status().completed.size()==3 and app.guidance_state().stage=="supply","restore_keeps_current_objective_without_reset_or_skip")
	await click(app._pause_button);await frames(30)
	app.select_item(vessel);await click(app._tools[3])
	print("SUPPLY_TARGET_WATER: ",app.world.water_at(Vector2i(8,1)))
	await cell(Vector2i(8,1));await frames(12)
	print("LOWER_SUPPLY_INPUT: ",app._last_status," paused=",app.runtime.clock_state().paused)
	check(app.world.get_instance(vessel).location=={"kind":"world","cell":[8,1]},"same_carrier_becomes_lower_supply_station")
	check(app.world.get_instance(vessel).rules==carried_rules,"reusing_carrier_preserves_original_program")
	check(app.expedition.status().completed==["goal:ruins","goal:irrigate","goal:lower_archive","goal:lower_supply"],"all_four_world_result_objectives_complete")
	check(app.world.total_water_units()==6000,"followup_mints_or_discards_no_water")
	check(app.world.stack_count("core:stone")==4,"only_newly_dug_four_floor_blocks_added")
	check(app.guidance_state().stage=="freeplay","completion_keeps_sandbox_open")
	app.play.set_paused(true)
	var out:String=OS.get_environment("RULEWEAVER_NATIVE_EXTENDED")
	if not out.is_empty():
		var f:=FileAccess.open(out,FileAccess.WRITE);check(f!=null,"extended_evidence_open")
		if f!=null:f.store_string(app.workspace_snapshot());f.close()
	for suffix in ["", ".bak", ".tmp"]:
		var p:String=app._files.slot_path("extended015")+suffix
		if FileAccess.file_exists(p):DirAccess.remove_absolute(p)
