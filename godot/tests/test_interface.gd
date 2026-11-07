extends SceneTree
var passed: int=0
var failed: int=0
func check(value: bool, label: String) -> void:
	if value: passed+=1; print("PASS: ",label)
	else: failed+=1; printerr("FAIL: ",label)
func _initialize() -> void: call_deferred("_run")
func finish() -> void:
	print("INTERFACE_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
func _run() -> void:
	check(ResourceLoader.exists("res://presentation/main.tscn"),"launchable_main_scene_exists")
	if failed: finish(); return
	root.size=Vector2i(1440,900)
	var scene=load("res://presentation/main.tscn").instantiate(); root.add_child(scene)
	await process_frame
	scene.new_game("res://content/first_expedition.json")
	check(scene.setup_complete,"main_uses_real_session")
	if not scene.setup_complete: scene.queue_free(); await process_frame; finish(); return
	check(scene.world.total_water_units()==6000,"initial_world_water_is_not_visual_fake")
	check(scene.play.motor is CharacterBody2D,"visible_actor_uses_existing_native_motor")
	check(scene.runtime.clock_state().paused,"startup_waits_for_player")
	check(scene.get_node_or_null("Shell")!=null,"main_ui_exists")
	scene.select_item("creation:vessel")
	var before: String=scene.play.checkpoint_json()
	scene.open_loom()
	await process_frame; await process_frame
	check(scene._status_label.get_global_rect().end.y<=root.size.y,"editor_keeps_toolbar_visible")
	check(scene.loom.amount.value==scene.loom.document.node("rate").config.value,"rate_display_matches_exact_units")
	check(scene.loom.visible and not scene.play._controls,"loom_gates_world_controls")
	scene.loom.amount.get_line_edit().grab_focus()
	var typing:=InputEventKey.new();typing.physical_keycode=KEY_E;typing.pressed=true
	root.push_input(typing)
	check(scene.loom.visible,"typing_in_parameter_does_not_toggle_loom")
	scene.loom.amount.get_line_edit().release_focus()
	check(scene.loom.document.preset("pump",125).ok,"pump_is_composed_as_editable_nodes")
	await process_frame; await process_frame
	check(scene.loom.amount.value==125,"rate_widget_does_not_round_125_to_126")
	check(scene.play.checkpoint_json()==before,"draft_edits_do_not_change_world")
	check(scene.loom.document.validate(scene.runtime).ok,"draft_uses_runtime_compiler")
	check(scene.apply_draft().ok,"apply_publishes_and_binds_selected_creation")
	var refs: Array=scene.world.get_instance("creation:vessel").rules
	check(refs.size()==1 and refs[0].id.begins_with("user:"),"bound_rule_is_user_program")
	check(scene.world.get_instance("creation:vessel").state.water_units==0,"binding_preserves_water")
	var v1: int=refs[0].version
	check(scene.loom.document.change_config("rate",{"value":75}).ok,"edit_numeric_node_config")
	check(scene.loom.document.undo().ok and scene.loom.document.node("rate").config.value==125,"undo_restores_graph")
	check(scene.loom.document.redo().ok and scene.loom.document.node("rate").config.value==75,"redo_restores_edit")
	check(scene.apply_draft().ok and scene.world.get_instance("creation:vessel").rules[0].version>v1,"second_apply_keeps_immutable_version")
	check(scene.runtime.rule_definition(refs[0].id,v1).ok,"previous_version_is_preserved")
	var saved_rule: String=scene.runtime.pack_json()
	check(scene.loom.document.disconnect_port("take","amount").ok,"missing_wire_allowed_in_draft")
	check(not scene.apply_draft().ok and scene.runtime.pack_json()==saved_rule,"invalid_graph_cannot_modify_published_rules")
	check(scene.loom.document.undo().ok,"undo_invalid_edit")
	root.size=Vector2i(1152,720)
	await process_frame; await process_frame
	check(scene._status_label.get_global_rect().end.y<=root.size.y,"small_window_keeps_controls_visible")
	root.size=Vector2i(1440,900)
	scene.close_loom()
	check(not scene.loom.visible and scene.runtime.clock_state().paused,"closing_preserves_prior_pause")
	check(scene.play._controls,"world_controls_restored")
	check(scene.save_game("ui_test").ok,"save_via_actual_ui_service")
	check(scene.load_game("ui_test").ok,"reload_real_play_checkpoint")
	check(scene.world.total_water_units()==6000,"ui_save_load_conserves_resources")
	var pos: Vector2i=Vector2i(2,0)
	check(scene.viewport_canvas.screen_to_cell(scene.viewport_canvas.cell_center(pos))==pos,"pointer_transform_roundtrip")
	scene.viewport_canvas.size=Vector2(640,480)
	check(scene.viewport_canvas.screen_to_cell(scene.viewport_canvas.cell_center(pos))==pos,"pointer_transform_after_resize")
	var file: String="user://ui_scroll_test.json"
	check(scene.export_scroll_to(file).ok,"export_current_rule_scroll")
	var bound: Array=scene.world.get_instance("creation:vessel").rules
	check(scene.import_scroll_from(file).ok and scene.world.get_instance("creation:vessel").rules==bound,"import_does_not_rebind")
	DirAccess.remove_absolute(file)
	var Files=load("res://runtime/checkpoint_files.gd"); var files=Files.new()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String=files.slot_path("ui_test")+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	scene.queue_free(); await process_frame; await process_frame
	finish()
