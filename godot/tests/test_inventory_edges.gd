extends SceneTree
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func frames()->void:await process_frame;await process_frame
func _run()->void:
	root.size=Vector2i(1152,720)
	var app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames()
	app.new_game("res://content/first_expedition.json");await frames()
	var baseline:String=app.play.checkpoint_json()
	check(not app.craft_recipe("carrier:vessel").ok and baseline==app.play.checkpoint_json(),"app_craft_requires_open_inventory")
	check(not app.play.craft_in_inventory("carrier:vessel").ok and baseline==app.play.checkpoint_json(),"play_craft_requires_paused_control_gate")
	app.open_inventory();await frames()
	var one:Dictionary=app.craft_recipe("carrier:vessel");var two:Dictionary=app.craft_recipe("carrier:vessel")
	check(one.ok and two.ok and one.id!=two.id,"multiple_carriers_created")
	check(app.inventory.item_list.item_count==4,"list_contains_each_independent_instance")
	app.select_item(one.id);app.open_loom();await frames()
	check(not app.inventory.visible and app.loom.visible and not app.play._controls,"exclusive_edit_panels")
	check(app.loom.document.preset("pump",50).ok and app.apply_draft().ok,"first_carrier_rule_published")
	app.select_item(two.id);app.loom.document.preset("pump",75);check(app.apply_draft().ok,"second_carrier_rule_published")
	var first:Dictionary=app.world.get_instance(one.id);var second:Dictionary=app.world.get_instance(two.id)
	check(first.rules[0].id!=second.rules[0].id,"same_material_distinct_behavior_identity")
	app.select_item(one.id);check(app.loom.document.node("rate").config.value==50,"select_first_restores_its_draft")
	app.loom.document.change_config("rate",{"value":125});app.open_inventory();await frames()
	app.select_item(two.id);app.open_loom();await frames()
	check(app.loom.document.node("rate").config.value==75,"second_draft_unaffected_by_first_edit")
	check(app.save_game("inventory_edges014").ok,"save_multiple_drafts")
	check(app.load_game("inventory_edges014").ok,"reload_multiple_drafts")
	app.select_item(one.id);app.open_loom();await frames()
	check(app.loom.document.node("rate").config.value==125,"first_unpublished_change_restored")
	check(app.world.get_instance(one.id).rules==first.rules and app.world.get_instance(two.id).rules==second.rules,"draft_reload_does_not_rebind_either_carrier")
	app.close_loom();app.open_inventory();await frames()
	check(app.runtime.clock_state().paused,"panel_switch_keeps_prior_pause")
	# 原生低层命令不获得脚本制作权限；界面暂停期间仍不能挖地。
	var frozen:String=app.play.checkpoint_json()
	check(not app.play.command({"op":"craft","recipe":"carrier:lamp"}).ok and not app.act_cell(Vector2i(0,1)).ok and frozen==app.play.checkpoint_json(),"inventory_does_not_bypass_world_gate")
	check(app.has_method("preferred_load_slot"),"legacy_slot_selection_available")
	if not app.has_method("preferred_load_slot"):
		app.queue_free();await frames();print("INVENTORY_EDGES_TEST_RESULT: ",passed," passed; ",failed," failed");quit(1);return
	check(app._files.save(app.play,"compat_old014").ok,"legacy_slot_fixture_saved")
	check(app.preferred_load_slot("compat_new014","compat_old014")=="compat_old014","absent_new_slot_offers_legacy")
	var corrupt:=FileAccess.open(app._files.slot_path("compat_new014"),FileAccess.WRITE);corrupt.store_string("broken");corrupt.close()
	check(app.preferred_load_slot("compat_new014","compat_old014")=="compat_new014","corrupt_new_save_never_silently_falls_back")
	var before_load:String=app.workspace_snapshot()
	check(not app.load_game("compat_new014").ok and app.workspace_snapshot()==before_load,"corrupt_workspace_preserves_editor_and_world")
	check(app.load_game("compat_old014").ok and app._draft_cache.is_empty(),"legacy_ui_load_preserves_world_without_inventing_drafts")
	for slot in ["inventory_edges014","compat_old014","compat_new014"]:
		for suffix in ["", ".bak", ".tmp"]:
			var path:String=app._files.slot_path(slot)+suffix
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	app.queue_free();await frames()
	print("INVENTORY_EDGES_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
