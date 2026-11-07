extends SceneTree
## 预演必须使用现有规则与世界事务，不能对正式世界施加任何变更。
const World=preload("res://runtime/world_session.gd")
const Runtime=preload("res://runtime/rule_runtime.gd")
const Document=preload("res://presentation/loom_document.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func finish()->void:
	print("DIAGNOSTICS_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func setup()->Dictionary:
	var catalog:Dictionary={"format":"rw.catalog/0.1","materials":{"core:stone":{"stackable":true},"user:reservoir":{"stackable":false,"state":"reservoir/0.1"}},"rules":{}}
	var w=World.new(catalog)
	var data:Dictionary={"format":"rw.world/0.2","actor":{"id":"player:local","cell":[-2,0]},"terrain":[{"cell":[1,1],"material_id":"core:stone"},{"cell":[2,0],"material_id":"core:stone"}],"water":[{"cell":[1,0],"units":600}],"entities":{"format":"rw.instances/0.1","world_id":"world:diagnostic","stacks":{},"instances":[{"id":"creation:pump","material_id":"user:reservoir","rules":[],"state":{"water_units":0,"capacity_units":1000,"light_on":false},"location":{"kind":"world","cell":[0,0]}}]}}
	check(w.load_checkpoint(JSON.stringify(data)).ok,"fixture_valid")
	var r=Runtime.new(catalog,w)
	var d=Document.new();d.start("user:test");d.preset("pump",250)
	var c:Dictionary=d.candidate(r)
	check(r.publish_pack(c.text,{}).ok and r.configure_clock(8,4).ok,"fixture_program_and_clock")
	return {"w":w,"r":r,"d":d}
func _run()->void:
	var s:Dictionary=setup();var w=s.w;var r=s.r;var d=s.d
	check(r.has_method("preview_rule_tick") and r.has_method("execution_feedback"),"bounded_preview_and_execution_feedback_exist")
	if not r.has_method("preview_rule_tick") or not r.has_method("execution_feedback"):finish();return
	var c:Dictionary=d.candidate(r);var ref:Dictionary={"id":c.module.id,"version":c.module.version}
	var before:String=r.checkpoint_json()
	var preview:Dictionary=r.preview_rule_tick("creation:pump",c.text,ref)
	check(preview.ok and preview.preview and preview.outcome.status=="committed","dry_run_reports_real_success")
	check(preview.before.state.water_units==0 and preview.after.state.water_units==250,"dry_run_reports_candidate_resource_delta")
	check(preview.total_before==600 and preview.total_after==600,"preview_conserves_candidate_water")
	check(r.checkpoint_json()==before and w.get_instance("creation:pump").rules.is_empty(),"dry_run_never_publishes_binds_ticks_or_changes_live_world")
	check(not r.rule_definition(ref.id,ref.version).ok,"dry_run_does_not_install_dynamic_version")
	preview.after.state.water_units=999
	check(w.get_instance("creation:pump").state.water_units==0,"preview_result_has_no_mutable_world_reference")
	check(r.execution_feedback("creation:pump").status=="unbound","live_unbound_status_is_not_preview_success")
	check(r.publish_pack(c.text,{"creation:pump":[ref]}).ok,"explicit_apply_is_separate")
	check(r.execution_feedback("creation:pump").status=="not_run","published_rule_waits_for_real_step")
	check(r.advance_tick().ok,"real_tick")
	var f:Dictionary=r.execution_feedback("creation:pump")
	check(f.status=="committed" and f.commands==1 and f.tick==1,"last_step_report_matches_commit")
	check(f.checks.size()==1 and f.checks[0].node=="take" and f.checks[0].enabled,"condition_trace_has_origin_and_boolean")
	f.checks[0].enabled=false
	check(r.execution_feedback("creation:pump").checks[0].enabled,"feedback_returns_copy")
	r.advance_tick();r.advance_tick();r.advance_tick()
	check(r.execution_feedback("creation:pump").status=="waiting" and not r.execution_feedback("creation:pump").checks[0].enabled,"dry_source_is_waiting_not_failed")
	before=r.checkpoint_json()
	check(not r.single_step(1,1).ok and r.checkpoint_json()==before,"failed_budget_preserves_world")
	check(r.execution_feedback("creation:pump").status=="aborted","aborted_step_does_not_reuse_old_success")
	# 拾取走实际世界入口；背包造物不能被预演假装放置。
	check(w.pickup("creation:pump").ok,"pickup_real_instance")
	check(r.execution_feedback("creation:pump").status=="carried","carried_instance_is_sleeping")
	c=d.candidate(r);ref={"id":c.module.id,"version":c.module.version};before=r.checkpoint_json()
	preview=r.preview_rule_tick("creation:pump",c.text,ref)
	check(preview.ok and preview.outcome.status=="carried" and preview.before.state==preview.after.state,"carried_preview_does_not_run_own_rules")
	check(r.checkpoint_json()==before,"carried_preview_has_no_live_side_effect")
	check(not r.preview_rule_tick("creation:missing",c.text,ref).ok,"missing_target_rejected")
	d.disconnect_port("take","amount");c=d.candidate(r)
	check(not r.preview_rule_tick("creation:pump",c.text,ref).ok and r.checkpoint_json()==before,"bad_draft_preview_preserves_world")
	# 动作失败时整个造物事务拒绝，不能把前面的发光动作说成已提交。
	var b:Dictionary=setup();var bd=b.d;var br=b.r;var bw=b.w
	bd.preset("lamp");bd.add("move",{"dx":1,"dy":0});bd.connect_nodes("node_1","when","always")
	c=bd.candidate(br);ref={"id":c.module.id,"version":c.module.version}
	check(br.publish_pack(c.text,{"creation:pump":[ref]}).ok,"blocked_multi_action_program_installed")
	check(br.advance_tick().ok,"blocked_instance_does_not_abort_entire_world")
	f=br.execution_feedback("creation:pump")
	check(f.status=="blocked" and f.error=="rule_move_collision","command_failure_explained")
	check(not bw.get_instance("creation:pump").state.light_on,"blocked_transaction_did_not_partially_apply_light")
	before=br.checkpoint_json();c=bd.candidate(br);ref={"id":c.module.id,"version":c.module.version}
	preview=br.preview_rule_tick("creation:pump",c.text,ref)
	check(preview.ok and preview.outcome.status=="blocked" and br.checkpoint_json()==before,"blocked_dry_run_distinguished_from_success")
	check(br.load_checkpoint(before).ok and br.execution_feedback("creation:pump").status=="not_run","reload_clears_stale_execution_report")
	br._busy=true
	check(not br.preview_rule_tick("creation:pump",c.text,ref).ok,"preview_reentry_rejected");br._busy=false
	# 多造物争用同一快照：预演也要包含其他对象，不能只在空世界测试自己。
	var race:Dictionary=setup();var rw=race.w;var rr=race.r;var rd=race.d
	var state:Dictionary=rw.rule_view();state.actor.cell=[1,-2]
	state.terrain=state.terrain.filter(func(t):return t.cell!=[2,0])
	state.entities.instances[0].id="creation:a"
	var other:Dictionary=state.entities.instances[0].duplicate(true);other.id="creation:z";other.location.cell=[2,0]
	state.entities.instances.append(other)
	check(rw.load_checkpoint(JSON.stringify(state)).ok,"two_competing_pumps_fixture")
	rd.change_config("rate",{"value":400});c=rd.candidate(rr);ref={"id":c.module.id,"version":c.module.version}
	check(rr.publish_pack(c.text,{"creation:a":[ref],"creation:z":[ref]}).ok,"two_pumps_share_same_program")
	c=rd.candidate(rr);ref={"id":c.module.id,"version":c.module.version};before=rr.checkpoint_json()
	var signals:Array=[];var receiver:Callable=func(_cells):signals.append(true)
	rw.committed.connect(receiver)
	preview=rr.preview_rule_tick("creation:z",c.text,ref)
	check(preview.ok and preview.outcome.status=="blocked" and preview.after.state.water_units==0,"preview_includes_competing_actor_and_rejects_loser")
	check(rr.checkpoint_json()==before and signals.is_empty(),"conflict_preview_emits_no_live_commit")
	check(preview==rr.preview_rule_tick("creation:z",c.text,ref),"same_preview_input_reproduces_same_result")
	var feedback_before:Dictionary=rr.execution_feedback("creation:z")
	check(not rr.preview_rule_tick("creation:z",c.text,ref,1,1).ok,"preview_global_budget_failure_reported")
	check(rr.checkpoint_json()==before and rr.execution_feedback("creation:z")==feedback_before,"failed_preview_preserves_live_report_and_world")
	rw.committed.disconnect(receiver)
	finish()
