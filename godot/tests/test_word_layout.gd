extends SceneTree
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func frames()->void:
	for i in 6:await process_frame
func overlap(graph:GraphEdit)->Array:
	var nodes:Array=[];var result:Array=[]
	for child in graph.get_children():
		if child is GraphNode:nodes.append(child)
	for i in nodes.size():
		for j in range(i+1,nodes.size()):
			if nodes[i].get_global_rect().grow(-1).intersects(nodes[j].get_global_rect().grow(-1)):result.append([str(nodes[i].name),str(nodes[j].name)])
	return result
func _run()->void:
	root.size=Vector2i(1152,720)
	var app=load("res://presentation/main.tscn").instantiate();root.add_child(app);await frames()
	app.new_game("res://content/first_expedition.json");app.open_loom();await frames()
	var panel=app.loom
	panel.document.preset("pump",125);panel.document.expose_constant("rate","rate");await frames();panel.open_advanced();await frames()
	var overlaps:Array=overlap(panel.graph)
	check(overlaps.is_empty(),"parameter_controls_do_not_overlap_other_nodes: "+str(overlaps))
	var rate:GraphNode=panel.graph.get_node("rate");rate.position_offset=Vector2(23,3000);await frames()
	panel.document.set_parameter_default("rate",200);await frames()
	check(panel.graph.get_node("rate").position_offset==Vector2(23,3000),"value_edit_preserves_manual_position")
	var added:Dictionary=panel.document.add("int",{"value":1500000});await frames()
	var spin:SpinBox=panel.graph.get_node(added.id).find_children("*","SpinBox",true,false)[0]
	check(spin.value==1500000,"wide_integer_widget_does_not_silently_clamp")
	panel.document.set_parameter_default("rate",1500000);await frames()
	check(panel.amount.value==1500000,"quick_parameter_widget_preserves_declared_value")
	check(overlap(panel.graph).is_empty(),"new_topology_uses_nonoverlapping_native_arrangement")
	app.queue_free();await frames()
	print("WORD_LAYOUT_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
