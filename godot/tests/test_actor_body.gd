extends SceneTree
const World = preload("res://runtime/world_session.gd")
const WC = preload("res://runtime/world_codec.gd")
var passed: int=0
var failed: int=0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1; print("PASS: ",label)
	else: failed+=1; printerr("FAIL: ",label)
func finish() -> void:
	print("ACTOR_BODY_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
func _initialize() -> void: call_deferred("_run")
static func catalog() -> Dictionary:
	return {"format":"rw.catalog/0.1","materials":{"core:stone":{"stackable":true},"user:reservoir":{"stackable":false,"state":"reservoir/0.1"}},"rules":{}}
static func fixture() -> Dictionary:
	return {"format":"rw.world/0.2","actor":{"id":"player:local","cell":[0,0]},"terrain":[],"water":[],"entities":{"format":"rw.instances/0.1","world_id":"world:platform","stacks":{"core:stone":30},"instances":[{"id":"creation:one","material_id":"user:reservoir","rules":[],"state":{"water_units":0,"capacity_units":1000,"light_on":false},"location":{"kind":"inventory","owner":"player:local"}}]}}
func _run() -> void:
	var w=World.new(catalog())
	check(w.has_method("enable_actor_body"),"continuous_body_interface_exists")
	if failed>0: finish(); return
	check(w.load_checkpoint(JSON.stringify(fixture())).ok,"old_environment_loads")
	check(w.enable_actor_body().ok,"old_actor_promoted_without_moving")
	check(w.rule_view().format=="rw.world/0.3" and w.actor_body_foot()==Vector2i(512,1024),"versioned_integer_foot")
	check(w.actor_occupied_cells()==[Vector2i(0,-1),Vector2i(0,0)],"centered_body_two_cells")
	check(w.move_actor_body(Vector2i(900,1024)).ok,"fractional_horizontal_move")
	check(w.actor_occupied_cells().size()==4,"body_crosses_two_columns")
	var before: String=w.checkpoint_json()
	check(not w.build("core:stone",Vector2i(1,0)).ok and w.checkpoint_json()==before,"cannot_build_into_body_side")
	check(not w.place("creation:one",Vector2i(1,-1)).ok and w.checkpoint_json()==before,"cannot_place_into_body_head_side")
	check(not w.move_actor_body(Vector2i(4000,1024)).ok and w.checkpoint_json()==before,"body_cannot_teleport")
	check(w.step_actor(Vector2i.LEFT).ok and w.actor_body_foot()==Vector2i(-124,1024),"legacy_step_translates_full_body")
	check(w.actor_cell()==Vector2i(-1,0),"negative_floor_not_truncate")
	check(w.enable_environment().ok and w.rule_view().format=="rw.world/0.3","water_activation_does_not_drop_body")
	before=w.checkpoint_json()
	var clone=World.new(catalog())
	check(clone.load_checkpoint(before).ok and clone.checkpoint_json()==before,"body_snapshot_roundtrip")
	var bad: Dictionary=w.rule_view(); bad.actor.cell=[0,0]
	check(not w.load_checkpoint(JSON.stringify(bad)).ok and w.checkpoint_json()==before,"derived_cell_mismatch_rejected")
	bad=w.rule_view(); bad.actor.body_foot[0]=1.5
	check(not w.load_checkpoint(JSON.stringify(bad)).ok,"fractional_body_unit_rejected")
	bad=w.rule_view(); bad.actor.body_foot=[true,1024]
	check(not w.load_checkpoint(JSON.stringify(bad)).ok,"boolean_body_unit_rejected")
	bad=w.rule_view(); bad.terrain.append({"cell":[0,0],"material_id":"core:stone"})
	check(not w.load_checkpoint(JSON.stringify(bad)).ok,"save_detects_side_overlap_not_only_anchor")
	var blocked: Dictionary=fixture(); blocked.terrain=[{"cell":[1,0],"material_id":"core:stone"}]
	var wall=World.new(catalog()); wall.load_checkpoint(JSON.stringify(blocked)); wall.enable_actor_body()
	before=wall.checkpoint_json()
	check(not wall.move_actor_body(Vector2i(900,1024)).ok and wall.checkpoint_json()==before,"motion_into_wall_is_atomic")
	var wet: Dictionary=fixture(); wet.water=[{"cell":[1,0],"units":500}]
	var water=World.new(catalog()); water.load_checkpoint(JSON.stringify(wet)); water.enable_actor_body()
	check(not water.move_actor_body(Vector2i(900,1024)).ok,"same_deep_water_entry_policy")
	var r=load("res://runtime/rule_runtime.gd").new(catalog(),clone)
	r.publish_pack(JSON.stringify({"format":"rw.rules/0.1","modules":[{"id":"user:idle","version":1,"parameters":{},"nodes":[{"id":"yes","op":"bool","config":{"value":true},"inputs":{}}],"effects":[]}]}))
	check(r.configure_clock(8,4).ok and r.advance_tick().ok,"clock_and_fluid_accept_body_world")
	check(clone.rule_view().format=="rw.world/0.3" and clone.actor_body_foot()==Vector2i(-124,1024),"simulation_preserves_fractional_body")
	var out_path: String=OS.get_environment("RULEWEAVER_NATIVE_ACTOR")
	if not out_path.is_empty():
		var out=FileAccess.open(out_path,FileAccess.WRITE)
		check(out!=null,"body_evidence_open")
		if out!=null: out.store_string(clone.checkpoint_json()); out.close()
	finish()
