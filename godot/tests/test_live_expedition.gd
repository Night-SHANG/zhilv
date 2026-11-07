extends SceneTree
## 相同遗迹与目标，通过原生输入/物理帧行走，不调用旧网格_walk或写最终状态。
const Routes = preload("res://scenarios/wet_ruins_routes.gd")
const Play = preload("res://runtime/play_session.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
var passed: int=0
var failed: int=0
var frame_count: int=0
func check(ok: bool,label: String) -> void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func finish() -> void:
	print("LIVE_EXPEDITION_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
func _initialize() -> void:call_deferred("_run")
func button(action: String,pressed: bool) -> void:
	var event:=InputEventAction.new();event.action=action;event.pressed=pressed;event.strength=1.0 if pressed else 0.0
	root.push_input(event)
func frames(p,n: int) -> Dictionary:
	for i in range(n):
		await physics_frame
		frame_count+=1
		var result: Dictionary=p.step_frame(1.0/60.0)
		if not result.ok:return result
	return {"ok":true}
func walk(p,w,target: int) -> Dictionary:
	var desired: int=target*1024+512
	var action: String="rw_move_right" if w.actor_body_foot().x<desired else "rw_move_left"
	button(action,true)
	for i in range(240):
		if abs(w.actor_body_foot().x-desired)<=110:
			button(action,false)
			return {"ok":true,"error":""}
		var result: Dictionary=await frames(p,1)
		if not result.ok:button(action,false);return result
	button(action,false)
	return {"ok":false,"error":"walk_budget_"+str(w.actor_cell())}
func bind_play(setup: Dictionary):
	var p=Play.new();root.add_child(p)
	var result: Dictionary=p.bind_session(setup.expedition,setup.world,Rect2i(-6,-6,20,14))
	check(result.ok,"native_session_binds_ruins")
	return p
func _run() -> void:
	var setup: Dictionary=Routes.setup();check(setup.ok,"same_ruins_scenario_loads")
	if not setup.ok:finish();return
	var p=bind_play(setup);var w=setup.world;var r=setup.runtime;var e=setup.expedition
	check((await frames(p,10)).ok,"settle_original_floor")
	button("rw_move_right",true);await frames(p,35);button("rw_move_right",false)
	check(w.actor_cell().x<2 and e.status().completed.is_empty(),"initial_flood_blocks_actual_player")
	check((await walk(p,w,0)).ok,"walk_back_to_work_area")
	# 原生走路期间水持续扩散：不能沿用旧瞬时回放的干地假设。
	var before_place: String=p.checkpoint_json()
	var wet_place: Dictionary=p.command({"op":"place","id":"creation:vessel","cell":[1,0]})
	check(not wet_place.ok and wet_place.error=="occupied_cell" and p.checkpoint_json()==before_place,"flooded_placement_is_rejected_without_losing_vessel")
	var placed: Dictionary=p.command({"op":"place","id":"creation:vessel","cell":[1,-1]})
	check(placed.ok,"place_real_rule_vessel_above_water: "+str(placed.get("error","")))
	check(Routes.author_pump(r).ok,"publish_graph_authored_from_blank")
	check((await frames(p,72)).ok and w.get_instance("creation:vessel").state.water_units>0,"frame_driver_runs_environment_pump")
	var files=Files.new();var slot: String="live_ruins_"+str(OS.get_process_id())
	var saved_text: String=p.checkpoint_json()
	check(files.save(p,slot).ok,"save_during_native_control_and_pumping")
	p.dispose();p.free();await physics_frame
	setup=Routes.setup();p=bind_play(setup);w=setup.world;r=setup.runtime;e=setup.expedition
	check(files.load_into(p,slot).ok and p.checkpoint_json()==saved_text,"fresh_session_restores_player_program_water_and_goals")
	for i in range(1800):
		if w.get_instance("creation:vessel").state.water_units>=5000:break
		var result: Dictionary=await frames(p,1)
		if not result.ok:check(false,"pump_frames: "+result.error);break
	check(w.get_instance("creation:vessel").state.water_units>=5000,"pumping_clears_passage_without_recipe_check")
	check(p.command({"op":"pickup","id":"creation:vessel"}).ok,"pickup_preserves_pump")
	await frames(p,480)
	var movement: Dictionary=await walk(p,w,6)
	check(movement.ok,"native_player_walks_drained_passage: "+str(movement.get("error","")))
	check(p.command({"op":"place","id":"creation:lamp","cell":[9,-1]}).ok,"place_existing_logical_lamp")
	await frames(p,12)
	check((await walk(p,w,8)).ok,"reach_ruin_with_native_motion")
	check(e.status().completed.has("goal:ruins"),"same_objective_observes_real_actor_light_and_water")
	check((await walk(p,w,-2)).ok,"native_player_returns_to_camp")
	check(p.command({"op":"pour","source":"creation:vessel","target":"creation:plot","amount":500}).ok,"reuse_collected_water_via_same_command_gateway")
	check(e.status().completed==["goal:ruins","goal:irrigate"] and w.get_instance("creation:plot").state.water_units==500,"native_input_expedition_completes")
	check(w.total_water_units()==6000,"live_control_conserves_all_water")
	var out_path: String=OS.get_environment("RULEWEAVER_NATIVE_LIVE_EXPEDITION")
	if not out_path.is_empty():
		var out=FileAccess.open(out_path,FileAccess.WRITE);check(out!=null,"live_route_evidence_open")
		if out!=null:out.store_string(p.checkpoint_json());out.close()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String=files.slot_path(slot)+suffix
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	print("NATIVE_INPUT_FRAMES: ",frame_count)
	p.dispose();p.free();await physics_frame
	finish()
