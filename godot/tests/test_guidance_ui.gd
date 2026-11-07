extends SceneTree
var passed:int=0
var failed:int=0
var app
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func frames()->void:await process_frame;await process_frame
func finish()->void:
	print("GUIDANCE_UI_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func click(control:Control)->void:
	var p:Vector2=control.get_global_rect().get_center()
	var e:=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true;root.push_input(e)
	e=e.duplicate();e.pressed=false;root.push_input(e);await frames()
func _run()->void:
	root.size=Vector2i(1152,720);app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames()
	check(app.has_method("guidance_state") and app.loom.has_method("preview_graph"),"context_guide_and_preview_controls_exist")
	if not app.has_method("guidance_state") or not app.loom.has_method("preview_graph"):
		app.queue_free();await frames();finish();return
	var before:String=app.workspace_snapshot()
	check(app.guidance_state().stage=="gather","empty_inventory_guides_gathering")
	check(app.workspace_snapshot()==before,"reading_guide_does_not_change_state")
	app.play.set_paused(false)
	for p in [Vector2i(0,-2),Vector2i(-1,-2),Vector2i(1,-2),Vector2i(0,-3),Vector2i(-1,-3),Vector2i(1,-3)]:app.select_tool("mine");app.act_cell(p)
	check(app.guidance_state().stage=="craft","gathered_materials_guide_crafting_not_more_mining")
	app.open_inventory();var v:Dictionary=app.craft_recipe("carrier:vessel");app.craft_recipe("carrier:lamp");app.select_item(v.id);app.open_loom();await frames()
	before=app.workspace_snapshot()
	await click(app.loom.find_child("PreviewRule",true,false))
	check(app.loom.preview_label.text.contains("背包"),"carried_preview_explains_sleeping")
	check(app.workspace_snapshot()==before,"preview_button_changes_no_draft_or_world")
	app.close_loom();app.select_tool("vessel");check(app.act_cell(Vector2i(1,-1)).ok,"place_for_preview")
	check(app.guidance_state().stage=="weave","placed_unbound_container_guides_weaving")
	app.open_loom();await frames();before=app.workspace_snapshot()
	await click(app.loom.find_child("PreviewRule",true,false))
	check(app.loom.preview_label.get_global_rect().end.y<=app.loom.find_child("PreviewRule",true,false).get_global_rect().position.y,"preview_result_stays_visible_above_action_row")
	check(app.loom.preview_label.text.contains("预演") and app.loom.preview_label.text.contains("真实世界未改变"),"preview_result_explicitly_hypothetical")
	check(app.workspace_snapshot()==before,"successful_button_preview_is_read_only")
	check(app.world.get_instance(v.id).rules.is_empty(),"preview_did_not_bind")
	await click(app.loom.find_child("ApplyRule",true,false))
	check(not app.world.get_instance(v.id).rules.is_empty(),"only_apply_publishes")
	check(app.runtime.single_step().ok,"single_real_step")
	app._refresh_hud();check(app._feedback_label.text.contains("上一拍"),"actual_execution_evidence_shown_separately")
	app.loom.document.disconnect_port("take","amount");await frames();before=app.workspace_snapshot()
	await click(app.loom.find_child("PreviewRule",true,false))
	check(app.loom.preview_label.text.contains("未通过"),"bad_draft_explains_rejection")
	check(app.workspace_snapshot()==before,"invalid_draft_preview_keeps_live_progress")
	check(root.get_visible_rect().encloses(app.loom.find_child("ApplyRule",true,false).get_global_rect()),"small_window_apply_remains_visible")
	check(root.get_visible_rect().encloses(app.loom.find_child("PreviewRule",true,false).get_global_rect()),"small_window_preview_remains_visible")
	check(app._status_label.get_global_rect().end.y<=root.size.y,"extra_feedback_does_not_push_toolbar_offscreen")
	app.queue_free();await frames();finish()
