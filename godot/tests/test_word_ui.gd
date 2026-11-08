extends SceneTree
## 使用现有Control按钮/输入与真实世界；不把界面截图当交互证明。
var passed:int=0
var failed:int=0
var app
func check(value:bool,label:String)->void:
	if value:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func frames()->void:await process_frame;await process_frame;await process_frame
func click(control:Control,window:Window=root)->void:
	var p:Vector2=control.get_global_rect().get_center()
	if window!=root:p+=Vector2(window.position)
	window=root
	var motion:=InputEventMouseMotion.new();motion.position=p;motion.global_position=p;window.push_input(motion)
	await process_frame
	var event:=InputEventMouseButton.new();event.position=p;event.global_position=p;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;window.push_input(event)
	event=event.duplicate();event.pressed=false;window.push_input(event);await frames()
func finish()->void:
	print("WORD_UI_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func _run()->void:
	root.size=Vector2i(1152,720)
	app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames()
	app.new_game("res://content/first_expedition.json");app.open_loom();await frames()
	var panel=app.loom
	check(panel.has_method("publish_word_named"),"word_library_controls_exist")
	if not panel.has_method("publish_word_named"):app.queue_free();await frames();finish();return
	panel.document.preset("pump",125);await frames();panel.open_advanced();await frames()
	for child in panel.graph.get_children():
		if child is GraphNode and child.name!="rate":child.position_offset+=Vector2(3000,0)
	var rate:GraphNode=panel.graph.get_node("rate");rate.position_offset=Vector2(25,25);panel.graph.scroll_offset=Vector2.ZERO;await frames()
	var button:Button=rate.find_child("ExposeConstant",true,false)
	check(button!=null,"constant_node_exposure_control_exists")
	if button==null:app.queue_free();await frames();finish();return
	await click(button,panel.advanced)
	check(panel.document.node("rate").op=="param" and panel.document.snapshot().parameters.rate.default==125,"native_button_exposes_typed_parameter")
	if panel.document.node("rate").op!="param":app.queue_free();await frames();finish();return
	check(panel.amount.value==125,"simple_rate_widget_reads_parameter_default")
	panel.advanced.hide();panel.word_name.text="user:water_pump"
	var before:String=app.world.checkpoint_json();var bindings:Array=app.world.get_instance("creation:vessel").rules
	panel._content_scroll.ensure_control_visible(panel.word_publish);await frames()
	await click(panel.word_publish)
	check(app.runtime.rule_definition("user:water_pump",1).ok,"native_button_publishes_named_word")
	check(app.world.checkpoint_json()==before and app.world.get_instance("creation:vessel").rules==bindings,"publishing_library_is_not_apply")
	check(panel.word_choices.item_count>=1,"published_word_discoverable")
	check(panel.has_method("edit_selected_word"),"library_copy_and_export_controls_exist")
	if not panel.has_method("edit_selected_word"):app.queue_free();await frames();finish();return
	var original_graph:Dictionary=panel.document.snapshot()
	panel._content_scroll.ensure_control_visible(panel.word_edit);await frames();await click(panel.word_edit)
	check(panel.document.snapshot().id=="user:water_pump" and app.world.checkpoint_json()==before,"native_copy_edit_does_not_rebind")
	panel.document.undo();await frames()
	check(panel.document.snapshot()==original_graph,"copy_edit_can_be_undone")
	panel._content_scroll.ensure_control_visible(panel.word_export);await frames();await click(panel.word_export)
	check(app._file_dialog.visible and app._file_dialog.file_mode==FileDialog.FILE_MODE_SAVE_FILE,"library_export_uses_save_dialog")
	app._file_dialog.hide();app._on_file_selected("user://word_ui_export016.json");await frames()
	var scroll:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://word_ui_export016.json"))
	check(scroll.get("entry",{}).get("id")=="user:water_pump" and app.world.get_instance("creation:vessel").rules==bindings,"export_unbound_word_not_selected_object_rule")
	DirAccess.remove_absolute("user://word_ui_export016.json")
	panel.document.preset("blank");await frames()
	panel._content_scroll.ensure_control_visible(panel.word_append);await frames();await click(panel.word_append)
	var calls:Array=panel.document.snapshot().nodes.filter(func(n):return n.op=="call")
	check(calls.size()==1,"native_append_creates_real_call_node")
	if calls.is_empty():app.queue_free();await frames();finish();return
	check(panel.document.validate(app.runtime).ok,"appended_call_typed_valid")
	var id:String=calls[0].id;var arg:String=calls[0].inputs.rate
	panel.document.change_config(arg,{"value":75});await frames()
	await click(panel.find_child("ApplyRule",true,false))
	check(app.world.get_instance("creation:vessel").rules.size()==1,"native_apply_binds_composed_program")
	var ref:Dictionary=app.world.get_instance("creation:vessel").rules[0]
	check(app.runtime.rule_definition(ref.id,int(ref.version)).module.nodes.any(func(n):return n.op=="call" and n.config.id=="user:water_pump"),"bound_program_calls_saved_word")
	check(root.get_visible_rect().encloses(panel.find_child("ApplyRule",true,false).get_global_rect()),"small_window_apply_visible")
	panel.word_name.text="core:forbidden";panel._content_scroll.ensure_control_visible(panel.word_publish);await frames()
	var pack:String=app.runtime.pack_json();await click(panel.word_publish)
	check(app.runtime.pack_json()==pack and panel.word_status.text.contains("不能"),"bad_name_has_error_without_world_changes")
	check(app.save_game("words_ui016").ok,"save_word_library_and_composed_draft")
	check(app.load_game("words_ui016").ok,"load_word_library")
	app.open_loom();await frames()
	check(app.runtime.rule_definition("user:water_pump",1).ok and app.loom.word_choices.item_count>=1,"word_list_rebuilt_from_restored_runtime")
	check(app.loom.document.node(id).config.id=="user:water_pump","composed_draft_survives_reload")
	# 参数化草稿自身在工作区中保存；未应用默认值不修改已发布版本。
	app.loom.document.preset("pump",300);app.loom.document.expose_constant("rate","flow");await frames()
	check(app.save_game("words_param016").ok and app.load_game("words_param016").ok,"parameter_draft_disk_roundtrip")
	app.open_loom();await frames()
	check(app.loom.document.snapshot().parameters.flow.default==300 and app.loom.document.node("rate").op=="param","parameter_signature_and_binding_restored")
	check(app.runtime.rule_definition("user:water_pump",1).module.parameters.rate.default==125,"unpublished_defaults_do_not_change_library")
	for slot in ["words_ui016","words_param016"]:
		for suffix in ["", ".bak", ".tmp"]:
			var path:String=app._files.slot_path(slot)+suffix
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	app.queue_free();await frames();finish()
