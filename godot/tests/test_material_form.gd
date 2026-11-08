extends SceneTree
const World=preload("res://runtime/world_session.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func catalog(cost:Variant=500)->Dictionary:
	return {"format":"rw.catalog/0.1","materials":{"core:stone":{"stackable":true},"core:water_crystal":{"stackable":true,"bound_water_units":cost},"user:reservoir":{"stackable":false,"state":"reservoir/0.1"}},"rules":{}}
func snapshot()->Dictionary:
	return {"format":"rw.world/0.2","actor":{"id":"player:local","cell":[-2,0]},"terrain":[],"water":[],"entities":{"format":"rw.instances/0.1","world_id":"world:forming","stacks":{},"instances":[{"id":"creation:caster","material_id":"user:reservoir","rules":[],"state":{"water_units":1500,"capacity_units":2000,"light_on":false},"location":{"kind":"world","cell":[0,0]}}]}}
func command(op:String,dx:int=1,dy:int=0)->Dictionary:
	return {"op":op,"dx":dx,"dy":dy,"material":"core:water_crystal"}
func unchanged(w, commands:Array,label:String)->void:
	var before:String=w.checkpoint_json()
	check(not w.apply_rule_commands("creation:caster",commands).ok and w.checkpoint_json()==before,label)
func _run()->void:
	var w=World.new(catalog());check(w.load_checkpoint(JSON.stringify(snapshot())).ok,"known_material_world_loads")
	var formed:Dictionary=w.apply_rule_commands("creation:caster",[command("form_material")])
	check(formed.ok,"water_can_form_authoritative_terrain")
	if not formed.ok:finish();return
	check(w.material_at(Vector2i(1,0))=="core:water_crystal" and w.get_instance("creation:caster").state.water_units==1000,"real_terrain_and_exact_cost")
	check(w.total_water_units()==1500,"bound_water_in_total")
	var saved:String=w.checkpoint_json();var restored=World.new(catalog())
	check(restored.load_checkpoint(saved).ok and restored.total_water_units()==1500,"bound_water_survives_world_reload")
	unchanged(w,[command("form_material")],"occupied_target_atomic")
	check(w.apply_rule_commands("creation:caster",[command("recover_material")]).ok,"recover_terrain_to_carrier")
	check(w.material_at(Vector2i(1,0)).is_empty() and w.get_instance("creation:caster").state.water_units==1500,"recover_returns_exact_water")
	unchanged(w,[command("recover_material")],"missing_block_cannot_make_water")
	unchanged(w,[{"op":"set_light","value":true},command("recover_material")],"failed_group_does_not_partially_emit_light")
	unchanged(w,[command("form_material"),command("form_material")],"double_form_same_target_atomic")
	check(w.apply_rule_commands("creation:caster",[command("form_material"),command("recover_material")]).ok and w.total_water_units()==1500,"same_group_uses_staged_terrain")
	unchanged(w,[command("form_material"),{"op":"move","dx":1,"dy":0}],"cannot_move_through_newly_formed_block")
	unchanged(w,[command("form_material"),{"op":"release_environment_water","dx":1,"dy":0,"amount":1}],"cannot_release_water_inside_new_solid")
	unchanged(w,[command("form_material",1,1)],"diagonal_action_rejected")
	var bad:Dictionary=command("form_material");bad.dx=1.0;unchanged(w,[bad],"native_float_rejected")
	bad=command("form_material");bad.material="core:stone";unchanged(w,[bad],"stone_cannot_be_minted")
	bad=command("form_material");bad.material="core:unknown";unchanged(w,[bad],"unknown_material_rejected")
	var s:Dictionary=snapshot();s.entities.instances[0].state.water_units=499
	w.load_checkpoint(JSON.stringify(s));unchanged(w,[command("form_material")],"insufficient_water_atomic")
	s=snapshot();s.water=[{"cell":[1,0],"units":1}];w.load_checkpoint(JSON.stringify(s));unchanged(w,[command("form_material")],"one_unit_water_preserved")
	s=snapshot();s.actor.cell=[1,0];w.load_checkpoint(JSON.stringify(s));unchanged(w,[command("form_material")],"actor_body_prevents_formation")
	s=snapshot();s.terrain=[{"cell":[1,0],"material_id":"core:water_crystal"}];s.entities.instances[0].state.water_units=1800;w.load_checkpoint(JSON.stringify(s));unchanged(w,[command("recover_material")],"capacity_overflow_atomic")
	s=snapshot();s.actor.cell=[2,0];s.terrain=[{"cell":[1,0],"material_id":"core:water_crystal"}];w.load_checkpoint(JSON.stringify(s))
	check(w.mine(Vector2i(1,0)).ok,"manual_mining_breaks_crystal")
	check(w.water_at(Vector2i(1,0))==500 and w.stack_count("core:water_crystal")==0 and w.total_water_units()==2000,"mining_releases_not_duplicates")
	check(w.collect_water("creation:caster",Vector2i(1,0),500).ok and w.total_water_units()==2000,"manual_recovery_closes_loop")
	var custom=World.new(catalog(750));custom.load_checkpoint(JSON.stringify(snapshot()))
	check(custom.apply_rule_commands("creation:caster",[command("form_material")]).ok and custom.get_instance("creation:caster").state.water_units==750,"catalog_drives_cost")
	check(custom.total_water_units()==1500,"custom_cost_conserved")
	for invalid in [0,-1,1001,true,1.5,"500"]:
		check(not World.new(catalog(invalid)).load_checkpoint(JSON.stringify(snapshot())).ok,"invalid_cost_"+str(invalid))
	var c:Dictionary=catalog();c.materials["core:water_crystal"].stackable=false
	check(not World.new(c).load_checkpoint(JSON.stringify(snapshot())).ok,"nonterrain_cost_rejected")
	s=snapshot();s.entities.stacks={"core:water_crystal":2};w.load_checkpoint(JSON.stringify(s))
	check(w.total_water_units()==2500,"stacked_bound_resource_in_total")
	check(w.build("core:water_crystal",Vector2i(-3,0)).ok and w.total_water_units()==2500,"build_preserves_total")
	s=snapshot();s.entities.instances[0].location.cell=[1000000,0];w.load_checkpoint(JSON.stringify(s));unchanged(w,[command("form_material")],"outside_world_atomic")
	s=snapshot();s.terrain=[{"cell":[1,0],"material_id":"core:stone"}];w.load_checkpoint(JSON.stringify(s));unchanged(w,[command("recover_material")],"rock_not_recovered_as_water")
	bad=command("form_material");bad["cost"]=0;unchanged(w,[bad],"cost_cannot_be_overridden")
	s=snapshot()
	for i in 16384:s.terrain.append({"cell":[100+i%128,100+int(i/128)],"material_id":"core:stone"})
	check(w.load_checkpoint(JSON.stringify(s)).ok,"terrain_budget_fixture")
	unchanged(w,[command("form_material")],"terrain_budget_atomic")
	s=snapshot();s.actor.cell=[2,0];s.terrain=[{"cell":[1,0],"material_id":"core:water_crystal"}]
	for i in 4096:s.water.append({"cell":[100+i,100],"units":1})
	check(w.load_checkpoint(JSON.stringify(s)).ok,"water_budget_fixture")
	var before:String=w.checkpoint_json()
	check(not w.mine(Vector2i(1,0)).ok and w.checkpoint_json()==before,"mining_at_water_budget_atomic")
	s=snapshot();s.terrain=[{"cell":[1,0],"material_id":"core:water_crystal"}];w.load_checkpoint(JSON.stringify(s))
	check(w.apply_rule_commands("creation:caster",[command("recover_material"),{"op":"release_environment_water","dx":1,"dy":0,"amount":500}]).ok,"recover_then_release_staged")
	check(w.water_at(Vector2i(1,0))==500 and w.total_water_units()==2000,"recover_release_conserved")
	finish()
func finish()->void:
	print("MATERIAL_FORM_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
