extends SceneTree
## 新水层必须与库存/造物共享一份整数账本，不能靠删除余水让测试通过。
const World = preload("res://runtime/world_session.gd")
const Codec = preload("res://runtime/world_codec.gd")
var passed: int = 0
var failed: int = 0
var notifications: int = 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1; print("PASS: ", label)
	else: failed += 1; printerr("FAIL: ", label)
func finish() -> void:
	print("WATER_TEST_RESULT: ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
func _initialize() -> void: call_deferred("_run")
func catalog() -> Dictionary:
	return {"format":"rw.catalog/0.1","materials":{"core:stone":{"stackable":true},"user:reservoir":{"stackable":false,"state":"reservoir/0.1"}},"rules":{}}
func fixture() -> Dictionary:
	return {"format":"rw.world/0.2","actor":{"id":"player:local","cell":[0,0]},"terrain":[{"cell":[1,1],"material_id":"core:stone"},{"cell":[2,1],"material_id":"core:stone"}],"water":[{"cell":[1,0],"units":600},{"cell":[2,0],"units":400}],"entities":{"format":"rw.instances/0.1","world_id":"world:water","stacks":{"core:stone":5},"instances":[{"id":"creation:bucket","material_id":"user:reservoir","rules":[],"state":{"water_units":0,"capacity_units":1000,"light_on":false},"location":{"kind":"inventory","owner":"player:local"}}]}}
func _changed(_cells: Array) -> void: notifications += 1
func _run() -> void:
	var w = World.new(catalog())
	check(w.has_method("collect_water") and ResourceLoader.exists("res://runtime/water_flow.gd"), "environment_water_interfaces_exist")
	if failed > 0: finish(); return
	var Flow = load("res://runtime/water_flow.gd")
	var a: Dictionary = {Vector2i(0,0):1}
	var result: Dictionary = Flow.step(a,{})
	check(result.ok and result.water.get(Vector2i(0,1),0)==1 and result.water.size()==1,"one_unit_falls_one_cell_without_evaporation")
	check(a=={Vector2i(0,0):1},"solver_does_not_mutate_input")
	var floor_map: Dictionary = {Vector2i(-1,1):true,Vector2i(0,1):true,Vector2i(1,1):true,Vector2i(-1,0):true,Vector2i(2,0):true}
	result = Flow.step({Vector2i.ZERO:1000},floor_map)
	check(result.ok and result.water.get(Vector2i.ZERO,0)==500 and result.water.get(Vector2i.RIGHT,0)==500,"supported_water_equalizes_horizontally")
	var still: Dictionary = Flow.step(result.water,floor_map)
	check(still.ok and still.changed.is_empty(),"settled_water_does_not_churn")
	check(Flow.step({Vector2i(1000000,1000000):1},{Vector2i(999999,1000000):true}).water=={Vector2i(1000000,1000000):1},"world_boundary_never_loses_water")
	check(not Flow.step({Vector2i.ZERO:1001},{}).ok,"overfilled_cell_rejected")
	check(not Flow.step({Vector2i.ZERO:1.0},{}).ok,"native_float_units_rejected")
	check(not Flow.step({"bad":1},{}).ok,"invalid_cell_type_rejected")
	check(not Flow.step({Vector2i.ZERO:1},{Vector2i.ZERO:true}).ok,"water_in_solid_rejected")
	check(not Flow.step({Vector2i.ZERO:1000},floor_map,1).ok,"new_water_cell_budget_rejects_whole_step")
	check(not Flow.step({Vector2i.ZERO:1000},floor_map,4096,1).ok,"operation_budget_rejects_whole_step")
	var forward: Dictionary={Vector2i(0,0):333,Vector2i(1,0):777,Vector2i(0,-1):99}
	var reverse: Dictionary={Vector2i(0,-1):99,Vector2i(1,0):777,Vector2i(0,0):333}
	check(Flow.step(forward,floor_map).water==Flow.step(reverse,floor_map).water,"dictionary_order_does_not_change_flow")
	var chamber: Dictionary={}
	for x in range(-3,4): chamber[Vector2i(x,4)]=true
	for y in range(-2,5): chamber[Vector2i(-3,y)]=true; chamber[Vector2i(3,y)]=true
	var pool: Dictionary={Vector2i.ZERO:1000,Vector2i(0,-1):999,Vector2i(1,0):1}
	var conserved: bool=true
	for i in range(80):
		result=Flow.step(pool,chamber)
		if not result.ok: conserved=false; break
		pool=result.water
		var total: int=0
		for n in pool.values(): total+=n
		if total!=2000: conserved=false; break
	check(conserved,"eighty_flow_steps_exact_mass_conservation")
	check(w.load_checkpoint(JSON.stringify(fixture())).ok,"load_water_world_02")
	w.committed.connect(_changed)
	check(w.total_water_units()==1000 and w.water_at(Vector2i(1,0))==600,"environment_and_container_share_total")
	var before: String=w.checkpoint_json()
	check(not w.build("core:stone",Vector2i(1,0)).ok and w.checkpoint_json()==before,"building_cannot_erase_water")
	check(not w.place("creation:bucket",Vector2i(1,0)).ok and w.checkpoint_json()==before,"creation_cannot_erase_water")
	check(not w.step_actor(Vector2i.RIGHT).ok and w.checkpoint_json()==before,"deep_water_blocks_grid_entry")
	check(not w.collect_water("creation:bucket",Vector2i(1,0),601).ok and w.checkpoint_json()==before,"overdraw_is_atomic")
	check(not w.collect_water("creation:bucket",Vector2i(1,0),true).ok,"bool_amount_not_an_integer")
	check(not w.collect_water("creation:bucket",Vector2i(1,0),-1).ok,"negative_amount_rejected")
	check(not w.collect_water("creation:bucket",Vector2i(99,0),1).ok,"distant_water_inaccessible")
	check(notifications==0,"failed_water_commands_emit_nothing")
	check(w.collect_water("creation:bucket",Vector2i(1,0),500).ok,"manual_water_collection")
	check(w.water_at(Vector2i(1,0))==100 and w.get_instance("creation:bucket").state.water_units==500 and w.total_water_units()==1000,"collection_exact_ledger")
	check(w.step_actor(Vector2i.RIGHT).ok,"shallow_water_is_wadeable")
	check(w.release_water("creation:bucket",Vector2i(2,0),200).ok,"manual_water_release")
	check(w.water_at(Vector2i(2,0))==600 and w.total_water_units()==1000,"release_preserves_total")
	before=w.checkpoint_json()
	check(not w.release_water("creation:bucket",Vector2i(2,1),1).ok and w.checkpoint_json()==before,"cannot_pour_into_solid")
	check(not w.release_water("creation:bucket",Vector2i(2,0),401).ok and w.checkpoint_json()==before,"insufficient_container_water_rejected")
	var reload=World.new(catalog())
	check(reload.load_checkpoint(before).ok and reload.checkpoint_json()==before,"water_world_roundtrip")
	var bad: Dictionary=fixture(); bad.water.append(bad.water[0].duplicate(true))
	check(not reload.load_checkpoint(JSON.stringify(bad)).ok and reload.checkpoint_json()==before,"duplicate_water_cell_rejected_without_damage")
	bad=fixture(); bad.water[0].cell=[1,1]
	check(not reload.load_checkpoint(JSON.stringify(bad)).ok,"water_terrain_overlap_rejected")
	bad=fixture(); bad.water[0].units=0
	check(not reload.load_checkpoint(JSON.stringify(bad)).ok,"zero_entries_not_persisted")
	bad=fixture(); bad.water[0].units=600.5
	check(not reload.load_checkpoint(JSON.stringify(bad)).ok,"fractional_wire_water_rejected")
	bad=fixture(); bad.format="rw.world/9"
	check(not reload.load_checkpoint(JSON.stringify(bad)).ok,"unknown_world_format_rejected")
	var legacy: Dictionary=fixture(); legacy.erase("water"); legacy.format="rw.world/0.1"
	check(reload.load_checkpoint(JSON.stringify(legacy)).ok and reload.rule_view().format=="rw.world/0.1","legacy_dry_world_retains_format")
	check(reload.enable_environment().ok and reload.rule_view().format=="rw.world/0.2" and reload.total_water_units()==0,"explicit_dry_world_upgrade")
	check(w.advance_water().ok and w.total_water_units()==1000,"native_world_flow_commit_conserves")
	w.committed.disconnect(_changed)
	finish()
