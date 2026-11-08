extends "res://tests/test_material_form.gd"
const Runtime=preload("res://runtime/rule_runtime.gd")
func n(id:String,op:String,inputs:Dictionary={},config:Dictionary={})->Dictionary:return {"id":id,"op":op,"inputs":inputs,"config":config}
func module(id:String,form:bool=true)->Dictionary:
	var config:Dictionary={"dx":1,"dy":0}
	if not form:config["material"]="core:water_crystal"
	return {"id":id,"version":1,"parameters":{},"nodes":[n("ready","cell_empty" if form else "terrain_is",{},config),n("act","form_material" if form else "recover_material",{"when":"ready"},{"dx":1,"dy":0,"material":"core:water_crystal"})],"effects":["act"]}
func pack(m:Dictionary)->String:return JSON.stringify({"format":"rw.rules/0.1","modules":[m]})
func bind(r,m:Dictionary,id:String="creation:caster")->Dictionary:return r.publish_pack(pack(m),{id:[{"id":m.id,"version":m.version}]})
func finish()->void:
	print("MATERIAL_RULES_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func _run()->void:
	var w=World.new(catalog());w.load_checkpoint(JSON.stringify(snapshot()));var r=Runtime.new(catalog(),w)
	check(bind(r,module("user:form")).ok,"typed_material_nodes_compile")
	if failed:finish();return
	check(r.advance(false).ok and w.material_at(Vector2i(1,0))=="core:water_crystal" and w.total_water_units()==1500,"rule_forms_authoritative_solid")
	check(r.advance(false).ok and r.execution_feedback("creation:caster").status=="waiting","occupied_query_waits")
	check(bind(r,module("user:recover",false)).ok and r.advance(false).ok,"typed_recovery")
	check(w.get_instance("creation:caster").state.water_units==1500 and w.material_at(Vector2i(1,0)).is_empty(),"same_water_returns")
	check(r.advance(false).ok and r.execution_feedback("creation:caster").status=="waiting","missing_target_waits")
	for mode in ["unknown","stone","diagonal","missing","port","type"]:
		var bad:Dictionary=module("user:bad")
		match mode:
			"unknown":bad.nodes[1].config.material="core:unknown"
			"stone":bad.nodes[1].config.material="core:stone"
			"diagonal":bad.nodes[0].config.dy=1
			"missing":bad.nodes[1].config.erase("material")
			"port":bad.nodes[1].inputs["amount"]="ready"
			"type":bad.nodes[0]=n("ready","int",{},{"value":1})
		var old:String=r.checkpoint_json()
		check(not r.publish_pack(pack(bad)).ok and r.checkpoint_json()==old,"reject_"+mode)
	var builder:Dictionary={"id":"user:builder","version":1,"parameters":{},"nodes":[n("yes","bool",{},{"value":true}),n("move","move",{"when":"yes"},{"dx":1,"dy":0}),n("form","form_material",{"when":"yes"},{"dx":0,"dy":1,"material":"core:water_crystal"}),n("lamp","set_light",{"when":"yes","value":"yes"})],"effects":["move","form","lamp"]}
	check(bind(r,builder).ok,"generic_mobile_builder_composition")
	check(r.advance(false).ok and w.get_instance("creation:caster").location.cell==[1,0] and w.material_at(Vector2i(1,1))=="core:water_crystal","builder_step1")
	check(r.advance(false).ok and w.get_instance("creation:caster").location.cell==[2,0] and w.material_at(Vector2i(2,1))=="core:water_crystal","builder_step2")
	check(w.get_instance("creation:caster").state.light_on and w.total_water_units()==1500,"composed_ledger")
	check(r.advance(false).ok and w.get_instance("creation:caster").state.water_units==0,"last_cost_exact")
	var pos:Array=w.get_instance("creation:caster").location.cell.duplicate()
	check(r.advance(false).ok and r.execution_feedback("creation:caster").status=="blocked" and w.get_instance("creation:caster").location.cell==pos,"empty_builder_no_partial_move")
	var saved:String=r.checkpoint_json();var fresh=World.new(catalog());fresh.load_checkpoint(JSON.stringify(snapshot()));var rr=Runtime.new(catalog(),fresh)
	check(rr.load_checkpoint(saved).ok and fresh.total_water_units()==1500 and fresh.material_at(Vector2i(2,1))=="core:water_crystal","world_and_program_reload")
	var conflict:Dictionary=snapshot();conflict.actor.cell=[1,-2];var other:Dictionary=conflict.entities.instances[0].duplicate(true);other.id="creation:other";other.location.cell=[2,0];conflict.entities.instances.append(other)
	w=World.new(catalog());w.load_checkpoint(JSON.stringify(conflict));r=Runtime.new(catalog(),w)
	bind(r,module("user:first"));var left:Dictionary=module("user:second");left.nodes[0].config.dx=-1;left.nodes[1].config.dx=-1
	check(bind(r,left,"creation:other").ok and r.advance(false).ok,"two_formers_share_snapshot")
	check(w.get_instance("creation:caster").state.water_units==1000 and w.get_instance("creation:other").state.water_units==1500 and w.total_water_units()==3000,"only_winner_pays")
	check(r.execution_feedback("creation:other").status=="blocked","true_condition_is_not_commit")
	r.configure_clock(100,50);r.set_paused(true)
	var recovery:Dictionary=module("user:preview_recover",false);var before:String=r.checkpoint_json()
	var trial:Dictionary=r.preview_rule_tick("creation:caster",pack(recovery),{"id":recovery.id,"version":1})
	check(trial.ok and trial.total_before==3000 and trial.total_after==3000 and trial.after.state.water_units==1500,"preview_accounts_for_bound_water")
	check(r.checkpoint_json()==before,"preview_does_not_mutate_real_world")
	var out:String=OS.get_environment("RULEWEAVER_NATIVE_MATERIAL")
	if not out.is_empty():
		var f:=FileAccess.open(out,FileAccess.WRITE);check(f!=null,"material_evidence_open")
		if f!=null:f.store_string(saved);f.close()
	finish()
