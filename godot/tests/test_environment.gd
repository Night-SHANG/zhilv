extends SceneTree
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Draft = preload("res://runtime/rule_draft.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
var passed: int=0
var failed: int=0
var observed_runtime
var observed_ticks: Array=[]
func check(ok: bool,label: String) -> void:
	if ok: passed+=1; print("PASS: ",label)
	else: failed+=1; printerr("FAIL: ",label)
func finish() -> void:
	print("ENVIRONMENT_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
func _initialize() -> void: call_deferred("_run")
func catalog() -> Dictionary:
	return {"format":"rw.catalog/0.1","materials":{"core:stone":{"stackable":true},"user:reservoir":{"stackable":false,"state":"reservoir/0.1"},"user:crystal":{"stackable":false,"state":"reservoir/0.1"}},"rules":{}}
func fixture() -> Dictionary:
	return {"format":"rw.world/0.2","actor":{"id":"player:local","cell":[-2,0]},"terrain":[{"cell":[1,1],"material_id":"core:stone"},{"cell":[2,0],"material_id":"core:stone"}],"water":[{"cell":[1,0],"units":600}],"entities":{"format":"rw.instances/0.1","world_id":"world:environment","stacks":{"core:stone":5},"instances":[{"id":"creation:pump","material_id":"user:reservoir","rules":[],"state":{"water_units":0,"capacity_units":1000,"light_on":false},"location":{"kind":"world","cell":[0,0]}}]}}
func n(id: String,op: String,config: Dictionary={}) -> Dictionary: return {"id":id,"op":op,"config":config,"inputs":{}}
func pump_pack(id: String="user:environment_pump", lighting: bool=false) -> String:
	var d=Draft.new(); d.start(id,1)
	for node in [n("source","neighbor_water"),n("available","water_units"),n("water","read_state",{"field":"water_units"}),n("capacity","read_state",{"field":"capacity_units"}),n("room","sub"),n("rate","int",{"value":250}),n("limited","min"),n("amount","min"),n("zero","int",{"value":0}),n("can_take","lt"),n("take","take_environment_water")]: d.upsert_node(node)
	for edge in [["available","source","source"],["room","a","capacity"],["room","b","water"],["limited","a","rate"],["limited","b","available"],["amount","a","limited"],["amount","b","room"],["can_take","a","zero"],["can_take","b","amount"],["take","when","can_take"],["take","source","source"],["take","amount","amount"]]: d.connect_input(edge[0],edge[1],edge[2])
	var effects: Array=["take"]
	if lighting:
		d.upsert_node(n("always","bool",{"value":true})); d.upsert_node(n("night","is_night")); d.upsert_node(n("lamp","set_light")); d.connect_input("lamp","when","always"); d.connect_input("lamp","value","night"); effects.append("lamp")
	d.set_effects(effects)
	return d.pack_json()
func _observe() -> void: observed_ticks.append(observed_runtime.clock_state().tick)
func _run() -> void:
	var w=World.new(catalog()); var r=Runtime.new(catalog(),w)
	check(r.has_method("configure_clock"),"clock_and_environment_runtime_exist")
	if failed>0: finish(); return
	check(w.load_checkpoint(JSON.stringify(fixture())).ok,"environment_world_load")
	var packed: String=pump_pack("user:environment_pump",true)
	check(r.publish_pack(packed,{"creation:pump":[{"id":"user:environment_pump","version":1}]}).ok,"author_environment_pump_using_general_nodes")
	check(r.configure_clock(8,4).ok,"configure_fixed_day_night")
	check(not r.configure_clock(8.0,4).ok and not r.configure_clock(8,8).ok,"invalid_clock_rejected")
	check(not r.advance(false).ok,"clocked_world_rejects_external_night_override")
	observed_runtime=r; w.reloaded.connect(_observe)
	check(r.advance_tick().ok,"first_atomic_environment_tick")
	check(w.water_at(Vector2i(1,0))==350 and w.get_instance("creation:pump").state.water_units==250,"rule_extracts_real_environment_water")
	check(w.total_water_units()==600 and observed_ticks==[1],"observer_sees_committed_tick_and_resource_state")
	check(r.advance_tick().ok and r.advance_tick().ok,"advance_pump_until_source_dry")
	check(w.water_at(Vector2i(1,0))==0 and w.get_instance("creation:pump").state.water_units==600,"clamped_pump_takes_last_remainder")
	check(r.advance_tick().ok and not w.get_instance("creation:pump").state.light_on,"four_day_ticks_light_off")
	check(not r.clock_state().night,"clock_phase_matches_the_last_completed_day_tick")
	check(r.advance_tick().ok and w.get_instance("creation:pump").state.light_on,"night_phase_switches_program_without_manual_flag")
	check(r.clock_state().night,"clock_phase_matches_the_completed_night_tick")
	var before: String=r.checkpoint_json()
	check(not r.advance_tick(1,1).ok and r.checkpoint_json()==before,"instruction_budget_preserves_tick_and_world")
	check(r.set_paused(true).ok,"pause_clock")
	before=r.checkpoint_json()
	check(r.advance_tick().ok and r.checkpoint_json()==before,"pause_does_not_advance_or_accumulate")
	check(r.single_step().ok and r.clock_state().paused and r.clock_state().tick==6,"single_step_runs_once_while_remaining_paused")
	var files=Files.new(); var slot: String="environment_"+str(OS.get_process_id())
	check(files.save(r,slot).ok,"save_clock_water_and_graphs_together")
	var restored_world=World.new(catalog()); var restored=Runtime.new(catalog(),restored_world)
	check(files.load_into(restored,slot).ok and restored.checkpoint_json()==r.checkpoint_json(),"restore_clock_phase_pause_and_dynamic_rules")
	check(restored.single_step().ok and r.single_step().ok and restored.checkpoint_json()==r.checkpoint_json(),"continued_replay_matches_after_disk_restore")
	var malformed: Dictionary=JSON.parse_string(r.checkpoint_json()); malformed.clock.daylight_ticks=99
	before=r.checkpoint_json()
	check(not r.load_checkpoint(JSON.stringify(malformed)).ok and r.checkpoint_json()==before,"bad_clock_save_preserves_live_state")
	w.reloaded.disconnect(_observe); observed_runtime=null
	# 流体预算失败发生在规则求值之后，也必须撤回候选世界和tick。
	var ww=World.new(catalog()); ww.load_checkpoint(JSON.stringify(fixture())); var rr=Runtime.new(catalog(),ww)
	rr.publish_pack(packed,{"creation:pump":[{"id":"user:environment_pump","version":1}]}); rr.configure_clock(8,4)
	before=rr.checkpoint_json()
	check(not rr.advance_tick(512,32768,1).ok and rr.checkpoint_json()==before,"fluid_budget_failure_rolls_back_rule_and_tick")
	# 环境原语不能与实例引用端口错连。
	var invalid: Dictionary=JSON.parse_string(packed)
	for node in invalid.modules[0].nodes:
		if node.id=="source": node.op="neighbor"; node.config={"material":""}
	check(not rr.preview_pack(JSON.stringify(invalid)).ok,"instance_ref_cannot_feed_environment_cell_port")
	# 同一通用程序用于另一种物质，并测试容量不足时自行限量。
	var crystal: Dictionary=fixture(); crystal.entities.instances[0].material_id="user:crystal"; crystal.entities.instances[0].state.capacity_units=100
	var cw=World.new(catalog()); cw.load_checkpoint(JSON.stringify(crystal)); var cr=Runtime.new(catalog(),cw)
	check(cr.publish_pack(pump_pack(),{"creation:pump":[{"id":"user:environment_pump","version":1}]}).ok,"same_pump_reused_on_crystal")
	cr.configure_clock(8,4); cr.advance_tick(); cr.advance_tick()
	check(cw.get_instance("creation:pump").state.water_units==100 and cw.water_at(Vector2i(1,0))==500,"full_capacity_stops_without_creation_specific_code")
	# 手工和规则的环境排水都走同一条事务账本。
	var drain=Draft.new(); drain.start("user:drain",1)
	for node in [n("yes","bool",{"value":true}),n("amount","int",{"value":25}),n("release","release_environment_water",{"dx":1,"dy":0})]: drain.upsert_node(node)
	drain.connect_input("release","when","yes"); drain.connect_input("release","amount","amount"); drain.set_effects(["release"])
	check(cr.publish_pack(drain.pack_json(),{"creation:pump":[{"id":"user:drain","version":1}]}).ok,"author_generic_release_rule")
	check(cr.advance_tick().ok and cw.get_instance("creation:pump").state.water_units==75 and cw.total_water_units()==600,"rule_release_conserves_environment_and_container")
	# 环境黑暗是天光遮挡，不把灯自己的亮光当作关闭条件，避免闪烁循环。
	var dark: Dictionary=fixture(); dark.terrain.append({"cell":[0,-2],"material_id":"core:stone"})
	var dw=World.new(catalog()); dw.load_checkpoint(JSON.stringify(dark)); var dr=Runtime.new(catalog(),dw)
	var lamp=Draft.new(); lamp.start("user:ambient_lamp",1)
	for node in [n("yes","bool",{"value":true}),n("dark","is_ambient_dark"),n("light","set_light")]: lamp.upsert_node(node)
	lamp.connect_input("light","when","yes"); lamp.connect_input("light","value","dark"); lamp.set_effects(["light"])
	check(dr.publish_pack(lamp.pack_json(),{"creation:pump":[{"id":"user:ambient_lamp","version":1}]}).ok,"author_ambient_lamp")
	dr.configure_clock(8,4); dr.advance_tick(); dr.advance_tick()
	check(dw.get_instance("creation:pump").state.light_on and dw.has_light_at(Vector2i(1,0),true),"cave_light_stays_on_in_day_and_lights_visible_neighbor")
	check(not dw.has_light_at(Vector2i(3,0),true),"opaque_wall_blocks_logical_light")
	check(ResourceLoader.exists("res://runtime/simulation_driver.gd"),"fixed_step_driver_exists")
	if ResourceLoader.exists("res://runtime/simulation_driver.gd"):
		var Driver=load("res://runtime/simulation_driver.gd"); var driver=Driver.new()
		check(driver.bind_runtime(rr,10).ok,"bind_clock_to_native_driver")
		var t: int=rr.clock_state().tick
		check(driver.process_delta(0.05).ok and rr.clock_state().tick==t,"half_step_does_not_advance")
		check(driver.process_delta(0.05).steps==1 and rr.clock_state().tick==t+1,"two_half_steps_advance_once")
		rr.set_paused(true); t=rr.clock_state().tick
		check(driver.process_delta(10.0).steps==0 and rr.clock_state().tick==t,"pause_discards_wall_clock_backlog")
		rr.set_paused(false)
		check(driver.process_delta(0.1).steps==1,"unpause_does_not_catch_up_sleep_time")
		check(driver.process_delta(10.0).steps==4,"long_frame_has_bounded_catchup")
		check(not driver.process_delta(NAN).ok and not driver.process_delta(-0.1).ok,"invalid_driver_time_rejected")
		driver.free()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String=files.slot_path(slot)+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	finish()
