extends SceneTree
## 验证GraphEdit的真实端口拖动，而不是直接调用连接回调。
var passed: int=0
var failed: int=0
func check(v: bool,label: String) -> void:
	if v:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("_run")
func frames() -> void:
	await process_frame;await process_frame;await process_frame
func mouse(window: Window,p: Vector2,pressed: bool) -> void:
	var e:=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;window.push_input(e)
func _run() -> void:
	root.size=Vector2i(1440,900)
	var app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames()
	app.open_loom();app.loom.document.preset("lamp");await frames()
	app.loom.document.disconnect_port("light","value");await frames()
	app.loom.open_advanced();await frames()
	var panel=app.loom
	check(panel.advanced.visible and panel.graph is GraphEdit,"real_graph_editor_visible")
	check(not panel.document.validate(app.runtime).ok,"missing_wire_blocks_apply")
	var from: GraphNode=panel.graph.get_node("dark")
	var target: GraphNode=panel.graph.get_node("light")
	var port: int=panel._node_ports.light.find("value")
	var start: Vector2=from.global_position+from.get_output_port_position(0)*panel.graph.zoom
	var end: Vector2=target.global_position+target.get_input_port_position(port)*panel.graph.zoom
	var before: String=app.play.checkpoint_json()
	var motion:=InputEventMouseMotion.new();motion.position=start;motion.global_position=start;panel.advanced.push_input(motion)
	mouse(panel.advanced,start,true)
	for i in range(1,11):
		motion=InputEventMouseMotion.new();motion.position=start.lerp(end,i/10.0);motion.global_position=motion.position;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;motion.relative=(end-start)/10.0;panel.advanced.push_input(motion);await process_frame
	mouse(panel.advanced,end,false);await frames()
	check(panel.document.node("light").inputs.get("value","")=="dark","mouse_drag_connects_typed_native_ports")
	check(panel.document.validate(app.runtime).ok,"native_drag_yields_valid_rule_graph")
	check(app.play.checkpoint_json()==before,"drawing_wires_does_not_change_world")
	check(panel.document.undo().ok and not panel.document.node("light").inputs.has("value"),"undo_reverses_mouse_connection")
	check(panel.document.redo().ok and panel.document.node("light").inputs.value=="dark","redo_restores_mouse_connection")
	panel.advanced.hide();app.close_loom()
	# 文件选择取消必须恢复原暂停状态，不产生隐式导入或世界操作。
	app.play.set_paused(false);app._show_file("import");await frames()
	check(app.runtime.clock_state().paused and not app.play._controls,"file_dialog_gates_and_pauses")
	panel=app._file_dialog;panel.hide();panel.canceled.emit();await frames()
	check(not app.runtime.clock_state().paused and app.play._controls,"cancel_file_dialog_restores_play")
	app.queue_free();await frames()
	print("GRAPH_INPUT_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
