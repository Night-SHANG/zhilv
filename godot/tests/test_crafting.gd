extends SceneTree
const Loader=preload("res://runtime/scenario_loader.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func finish()->void:
	print("CRAFTING_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func _run()->void:
	var setup:Dictionary=Loader.load_scenario("res://content/first_expedition.json")
	check(setup.ok,"fixture_loads")
	var world=setup.world
	check(world.has_method("craft"),"world_exposes_atomic_crafting")
	if not world.has_method("craft"):finish();return
	var snapshot:Dictionary=world.rule_view()
	snapshot.entities.stacks={};snapshot.entities.instances=snapshot.entities.instances.filter(func(e):return e.id=="creation:plot")
	check(world.load_checkpoint(JSON.stringify(snapshot)).ok,"empty_inventory_fixture")
	var original:String=world.checkpoint_json()
	check(not world.craft("carrier:vessel").ok and world.checkpoint_json()==original,"missing_materials_no_partial_change")
	check(not world.craft("carrier:unknown").ok and world.checkpoint_json()==original,"unknown_recipe_no_change")
	check(not world.craft(7).ok and world.checkpoint_json()==original,"invalid_native_recipe_type_rejected")
	# 原地图屋顶以内的地板可直接采集；测试不直接增加最终库存。
	for cell in [Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1),Vector2i(2,1),Vector2i(-2,1),Vector2i(3,1)]:
		check(world.mine(cell).ok,"mine_stone_%s"%cell)
	check(world.stack_count("core:stone")==6,"six_mined_materials")
	var events:Array=[]
	var receiver:Callable=func(cells:Array):events.append(cells)
	world.committed.connect(receiver)
	var vessel:Dictionary=world.craft("carrier:vessel")
	check(vessel.ok,"craft_vessel")
	if not vessel.ok:world.committed.disconnect(receiver);finish();return
	var v:Dictionary=world.get_instance(vessel.id)
	check(world.stack_count("core:stone")==2,"vessel_cost_exactly_four")
	check(v.state.water_units==0 and v.state.capacity_units==6000 and v.rules.is_empty(),"new_carrier_is_empty_not_fixed_behavior")
	check(v.location=={"kind":"inventory","owner":"player:local"},"crafted_owned_by_player")
	var lamp:Dictionary=world.craft("carrier:lamp")
	check(lamp.ok and lamp.get("id")!=vessel.id,"distinct_instance_ids")
	if not lamp.ok:world.committed.disconnect(receiver);finish();return
	check(world.stack_count("core:stone")==0,"lamp_cost_exactly_two")
	check(world.get_instance(lamp.id).material_id=="user:crystal","lamp_uses_existing_material_capability")
	check(events.size()==2,"one_commit_signal_per_success")
	var completed:String=world.checkpoint_json()
	check(not world.craft("carrier:lamp").ok and world.checkpoint_json()==completed and events.size()==2,"failed_craft_no_signal_or_loss")
	var reload:Dictionary=Loader.load_scenario("res://content/first_expedition.json")
	check(reload.world.load_checkpoint(completed).ok,"crafting_survives_world_checkpoint")
	check(reload.world.get_instance(vessel.id)==v and reload.world.get_instance(lamp.id)==world.get_instance(lamp.id),"crafted_identity_state_preserved")
	# 默认原场景有20石料，制作多个同种载体必须互不覆盖。
	var fresh:Dictionary=Loader.load_scenario("res://content/first_expedition.json")
	var one:Dictionary=fresh.world.craft("carrier:vessel")
	var two:Dictionary=fresh.world.craft("carrier:vessel")
	check(one.ok and two.ok and one.id!=two.id,"same_material_different_instances")
	check(fresh.world.stack_count("core:stone")==12,"multiple_costs_counted")
	var save:String=fresh.world.checkpoint_json()
	check(fresh.world.load_checkpoint(save).ok,"reload_before_next_craft")
	var three:Dictionary=fresh.world.craft("carrier:vessel")
	check(three.ok and three.id!=one.id and three.id!=two.id,"restored_ids_not_reused")
	check(fresh.world.get_instance(one.id).state.water_units==0,"new_craft_does_not_mutate_previous")
	check(fresh.world.total_water_units()==6000,"crafting_creates_no_water")
	world.committed.disconnect(receiver)
	finish()
