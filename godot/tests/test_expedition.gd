extends SceneTree
var passed: int=0
var failed: int=0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1; print("PASS: ",label)
	else: failed+=1; printerr("FAIL: ",label)
func _initialize() -> void: call_deferred("_run")
func finish() -> void:
	print("EXPEDITION_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
func _run() -> void:
	check(ResourceLoader.exists("res://scenarios/wet_ruins_routes.gd"),"complete_expedition_routes_exist")
	if failed>0: finish(); return
	var Routes=load("res://scenarios/wet_ruins_routes.gd")
	var outputs: Dictionary={}
	for route in ["manual","drainage","authored"]:
		var result: Dictionary=Routes.run(route)
		check(result.ok,route+"_complete_route: "+str(result.get("error","")))
		if not result.ok: continue
		outputs[route]=result
		check(result.completed==["goal:ruins","goal:irrigate"],route+"_same_outcome_goals")
		check(result.total_water==6000,route+"_all_water_accounted_for")
		check(result.plot_water>=500,route+"_collected_water_reused_at_camp")
		check(result.visited_lit,"visit_required_real_position_and_logical_light")
	check(outputs.size()==3,"three_different_solutions_no_recipe_gate")
	if outputs.size()!=3: finish(); return
	check(outputs.manual.mined==0 and outputs.authored.mined==0 and outputs.drainage.mined>0,"solutions_change_world_in_different_ways")
	check(outputs.authored.authored_rule and not outputs.manual.authored_rule and not outputs.drainage.authored_rule,"ordinary_play_does_not_require_programming")
	var replay: Dictionary=Routes.run("authored",true)
	check(replay.ok and replay.checkpoint==outputs.authored.checkpoint,"mid_flow_disk_restore_matches_uninterrupted_route")
	var reversed: Dictionary=Routes.run("authored",false,true)
	check(reversed.ok and reversed.checkpoint==outputs.authored.checkpoint,"reversed_water_input_order_has_same_outcome")
	# 失败和预算不足不损害进度/世界；已完成里程碑不能因走回营地而丢失。
	var setup: Dictionary=Routes.setup()
	check(setup.ok,"fresh_expedition_setup")
	if not setup.ok: finish(); return
	var e=setup.expedition; var r=setup.runtime; var w=setup.world
	check(e.observe().completed.is_empty(),"fresh_world_not_precompleted")
	var before: String=e.checkpoint_json()
	check(not e.act({"op":"collect","id":"creation:vessel","cell":[2,0],"amount":true}).ok and e.checkpoint_json()==before,"bad_player_command_does_not_change_world_or_goals")
	check(not e.act({"op":"teleport","cell":[8,0]}).ok,"unsupported_commands_not_executable")
	var corrupt: Dictionary=JSON.parse_string(before); corrupt.completed=["goal:irrigate"]
	check(not e.validate_checkpoint(JSON.stringify(corrupt)).ok,"completion_requires_prerequisite")
	corrupt=JSON.parse_string(before); corrupt.scenario_version=99
	check(not e.validate_checkpoint(JSON.stringify(corrupt)).ok,"scenario_version_mismatch_rejected")
	corrupt=JSON.parse_string(before); corrupt.completed=["goal:unknown"]
	check(not e.validate_checkpoint(JSON.stringify(corrupt)).ok,"unknown_goal_rejected")
	corrupt=JSON.parse_string(before); corrupt.simulation.world.water[0].units=1001
	check(not e.load_checkpoint(JSON.stringify(corrupt)).ok and e.checkpoint_json()==before,"bad_environment_save_preserves_expedition")
	check(e.load_checkpoint(outputs.authored.checkpoint).ok and e.status().completed==["goal:ruins","goal:irrigate"],"finished_progress_restores_with_world")
	var data: Dictionary=e.status(); data.completed.clear()
	check(e.status().completed.size()==2,"progress_query_returns_copy")
	var out_path: String=OS.get_environment("RULEWEAVER_NATIVE_EXPEDITION")
	if not out_path.is_empty():
		var out=FileAccess.open(out_path,FileAccess.WRITE)
		check(out!=null,"expedition_evidence_open")
		if out!=null:
			var pack: Dictionary={"format":"rw.expedition_evidence/0.1","routes":{}}
			for route in outputs:
				pack.routes[route]={"checkpoint":outputs[route].checkpoint,"total_water":outputs[route].total_water,"plot_water":outputs[route].plot_water,"mined":outputs[route].mined,"authored_rule":outputs[route].authored_rule}
			out.store_string(JSON.stringify(pack)); out.close()
	finish()
