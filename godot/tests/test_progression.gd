extends SceneTree
const Loader=preload("res://runtime/scenario_loader.gd")
const Expedition=preload("res://runtime/expedition_session.gd")
const Workspace=preload("res://presentation/workspace_checkpoint.gd")
const World=preload("res://runtime/world_session.gd")
const Runtime=preload("res://runtime/rule_runtime.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func finish()->void:
	print("PROGRESSION_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func upgraded()->Dictionary:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/first_expedition.json"))
	var d:Dictionary=data.definition.duplicate(true)
	d.version=2
	d["compatible_versions"]=[{"version":1,"goal_ids":["goal:ruins","goal:irrigate"]}]
	d.objectives.append({"id":"goal:lower_archive","type":"visit","requires":["goal:irrigate"],"cell":[6,2],"lit":true,"max_water":199})
	d.objectives.append({"id":"goal:lower_supply","type":"supply","requires":["goal:lower_archive"],"cell":[8,1],"water_units":1000})
	return d
func _run()->void:
	var s:Dictionary=Loader.load_scenario("res://content/first_expedition.json")
	check(s.ok,"legacy_scenario_loads")
	var old:String=s.expedition.checkpoint_json()
	var e=Expedition.new();var d:Dictionary=upgraded();var bound:Dictionary=e.attach(s.runtime,s.world,d)
	check(bound.ok,"append_only_definition_and_cell_supply_supported")
	if not bound.ok:finish();return
	check(e.status().total==4,"four_real_world_goals")
	check(e.load_checkpoint(old).ok,"previous_version_restores_into_extended_definition")
	check(e.checkpoint_value().scenario_version==2,"next_save_uses_current_goal_version")
	check(e.checkpoint_value().simulation==s.expedition.checkpoint_value().simulation,"migration_changes_no_world_resource_or_rule")
	for mode in ["new_goal_in_old","unknown_version","unknown_goal","duplicate_completed","different_scenario"]:
		var bad:Dictionary=Workspace.integer_tree(JSON.parse_string(old))
		match mode:
			"new_goal_in_old":bad.completed=["goal:ruins","goal:irrigate","goal:lower_archive"]
			"unknown_version":bad.scenario_version=99
			"unknown_goal":bad.completed=["goal:unknown"]
			"duplicate_completed":bad.completed=["goal:ruins","goal:ruins"]
			"different_scenario":bad.scenario_id="scenario:other"
		var before:String=e.checkpoint_json()
		check(not e.load_checkpoint(JSON.stringify(bad)).ok and e.checkpoint_json()==before,"atomic_reject_"+mode)
	var legacy_done:Dictionary=Workspace.integer_tree(JSON.parse_string(old));legacy_done.completed=["goal:ruins","goal:irrigate"]
	check(e.load_checkpoint(JSON.stringify(legacy_done)).ok and e.status().completed==legacy_done.completed,"old_completed_first_section_is_not_reset")
	for mode in ["nonprefix","newer","duplicate","bad_type","extra"]:
		var def:Dictionary=upgraded()
		match mode:
			"nonprefix":def.compatible_versions[0].goal_ids=["goal:irrigate"]
			"newer":def.compatible_versions[0].version=3
			"duplicate":def.compatible_versions.append(def.compatible_versions[0].duplicate(true))
			"bad_type":def.compatible_versions[0].goal_ids="all"
			"extra":def.compatible_versions[0]["grant_all"]=true
		var x=Expedition.new()
		check(not x.attach(s.runtime,s.world,def).ok,"migration_descriptor_rejects_"+mode)
	var catalog:Dictionary={"format":"rw.catalog/0.1","materials":{"core:stone":{"stackable":true},"user:reservoir":{"stackable":false,"state":"reservoir/0.1"}},"rules":{}}
	var w=World.new(catalog)
	var world:Dictionary={"format":"rw.world/0.2","actor":{"id":"player:local","cell":[-1,0]},"terrain":[],"water":[],"entities":{"format":"rw.instances/0.1","world_id":"world:supply_test","stacks":{},"instances":[{"id":"creation:arbitrary","material_id":"user:reservoir","rules":[],"state":{"water_units":120,"capacity_units":1000,"light_on":false},"location":{"kind":"inventory","owner":"player:local"}}]}}
	check(w.load_checkpoint(JSON.stringify(world)).ok,"unit_supply_fixture")
	var r=Runtime.new(catalog,w)
	r.install_pack('{"format":"rw.rules/0.1","modules":[{"id":"user:idle","version":1,"parameters":{},"nodes":[{"id":"yes","op":"bool","config":{"value":true},"inputs":{}}],"effects":[]}]}');r.configure_clock(100,50)
	var supply=Expedition.new()
	check(supply.attach(r,w,{"id":"scenario:supply","version":1,"objectives":[{"id":"goal:visit","type":"visit","requires":[],"cell":[0,0],"lit":false,"max_water":1000},{"id":"goal:supply","type":"supply","requires":["goal:visit"],"cell":[1,0],"water_units":100}]}).ok,"generic_result_based_supply_goal")
	check(supply.act({"op":"place","id":"creation:arbitrary","cell":[1,0]}).ok and supply.status().completed.is_empty(),"filled_station_does_not_skip_prerequisite")
	check(supply.act({"op":"move","delta":[1,0]}).ok and supply.status().completed==["goal:visit","goal:supply"],"any_carrier_can_satisfy_supply_after_visit")
	check(w.total_water_units()==120,"goal_consumes_or_mints_no_water")
	var incomplete:Dictionary=world.duplicate(true);incomplete.entities.instances[0].state.water_units=99
	w.load_checkpoint(JSON.stringify(incomplete));supply.attach(r,w,{"id":"scenario:supply2","version":1,"objectives":[{"id":"goal:supply","type":"supply","requires":[],"cell":[1,0],"water_units":100}]})
	supply.act({"op":"place","id":"creation:arbitrary","cell":[1,0]})
	check(supply.status().completed.is_empty(),"insufficient_station_water_does_not_complete")
	check(Loader.load_scenario("res://content/fresh_expedition.json").expedition.status().total==5,"default_scene_exposes_next_section")
	finish()
