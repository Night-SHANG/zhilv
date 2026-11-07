extends SceneTree
## 用编辑操作从零构造图，而不是读取预写好的最终配方。
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
var passed: int=0
var failed: int=0

func check(ok: bool,label: String) -> void:
	if ok:
		passed+=1
		print("PASS: ",label)
	else:
		failed+=1
		printerr("FAIL: ",label)

func _initialize() -> void: call_deferred("_run")

func node(id: String,op: String,config: Dictionary={}) -> Dictionary:
	return {"id":id,"op":op,"inputs":{},"config":config}

func _run() -> void:
	check(ResourceLoader.exists("res://runtime/rule_draft.gd"),"draft_editor_exists")
	if not ResourceLoader.exists("res://runtime/rule_draft.gd"):
		finish()
		return
	var Draft = load("res://runtime/rule_draft.gd")
	var draft = Draft.new()
	check(draft.start("user:my_lamp",1).ok,"start_empty_draft")
	var root: String=OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("rules_catalog.json")))
	var w=World.new(catalog)
	check(w.load_checkpoint(FileAccess.get_file_as_string(root.path_join("rules_world.json"))).ok,"draft_world_load")
	var r=Runtime.new(catalog,w)
	check(r.install_pack(FileAccess.get_file_as_string(root.path_join("rules_pack.json"))).ok,"draft_initial_library")
	var before: String=r.checkpoint_json()
	check(not r.preview_pack(draft.pack_json()).ok,"empty_draft_not_publishable")
	check(draft.upsert_node(node("night","is_night")).ok,"add_sensor")
	check(draft.upsert_node(node("always","bool",{"value":true})).ok,"add_condition")
	check(draft.upsert_node(node("light","set_light")).ok,"add_action")
	check(draft.set_effects(["light"]).ok,"set_action_order")
	check(not r.preview_pack(draft.pack_json()).ok,"incomplete_ports_detected")
	check(draft.connect_input("light","when","always").ok,"wire_condition")
	check(draft.connect_input("light","value","night").ok,"wire_sensor_to_light")
	check(r.preview_pack(draft.pack_json()).ok,"completed_graph_validates")
	check(r.checkpoint_json()==before,"editing_never_mutates_running_world")
	var exported: Dictionary=draft.snapshot()
	exported.nodes.clear()
	check(draft.snapshot().nodes.size()==3,"snapshot_defensive_copy")
	check(not draft.remove_node("night").ok,"referenced_node_removal_rejected")
	var draft_before: String=draft.pack_json()
	check(not draft.connect_input("missing","value","night").ok,"missing_target_rejected")
	check(draft.pack_json()==draft_before,"failed_edit_preserves_draft")
	check(not draft.start("core:privileged",1).ok,"draft_cannot_claim_core_namespace")
	check(draft.pack_json()==draft_before,"invalid_start_preserves_draft")
	check(r.publish_pack(draft.pack_json(),{"creation:001":[{"id":"user:my_lamp","version":1}]}).ok,"publish_created_graph_and_bind")
	check(r.advance(true).ok and w.get_instance("creation:001").state.light_on,"authored_night_lamp_runs")
	check(r.advance(false).ok and not w.get_instance("creation:001").state.light_on,"authored_lamp_turns_off_at_day")

	var next: Dictionary=r.next_rule_version("user:my_lamp")
	check(next.ok and next.version==2,"allocate_next_version")
	var definition: Dictionary=r.rule_definition("user:my_lamp",1)
	var revision: Dictionary=definition.module.duplicate(true)
	revision.version=next.version
	var edit = Draft.new()
	check(edit.restore(revision).ok,"clone_published_graph_as_new_draft")
	check(edit.upsert_node(node("inverse","not")).ok,"add_logic_node")
	check(edit.connect_input("inverse","value","night").ok,"wire_inverse")
	check(edit.connect_input("light","value","inverse").ok,"rewire_existing_input")
	check(r.publish_pack(edit.pack_json(),{"creation:004":[{"id":"user:my_lamp","version":2}]}).ok,"publish_second_version_selected_instance_only")
	check(w.place("creation:004",Vector2i(1,2)).ok,"place_second_version")
	r.advance(false)
	check(not w.get_instance("creation:001").state.light_on and w.get_instance("creation:004").state.light_on,"old_and_new_graphs_independent")
	check(r.rule_definition("user:my_lamp",1).module==definition.module,"original_definition_unchanged")
	definition.module.nodes.clear()
	check(r.rule_definition("user:my_lamp",1).module.nodes.size()==3,"published_definition_defensive_copy")
	check(edit.disconnect_input("light","value").ok,"disconnect_input")
	check(not r.preview_pack(edit.pack_json()).ok,"dangling_graph_cannot_publish")
	check(edit.remove_node("inverse").ok,"remove_unreferenced_node")
	check(edit.connect_input("light","value","night").ok,"repair_draft")
	check(edit.remove_node("light").ok and edit.snapshot().effects.is_empty(),"remove_action_updates_effect_list")
	check(not edit.set_effects(["missing"]).ok,"missing_effect_rejected")

	# 参数化行为封装：以相同编辑器构造子模块，再从另一个图call。
	var child = Draft.new()
	check(child.start("user:brightness",1).ok,"new_behavior_module")
	check(child.set_parameter("enabled","bool",true).ok,"create_boolean_parameter")
	check(child.upsert_node(node("enabled","param",{"name":"enabled"})).ok,"add_parameter_node")
	check(child.upsert_node(node("yes","bool",{"value":true})).ok,"child_condition")
	check(child.upsert_node(node("light","set_light")).ok,"child_action")
	check(child.connect_input("light","when","yes").ok and child.connect_input("light","value","enabled").ok,"child_wiring")
	check(child.set_effects(["light"]).ok and r.publish_pack(child.pack_json()).ok,"publish_parameterized_behavior")
	var parent = Draft.new()
	check(parent.start("user:composed",1).ok,"new_parent_graph")
	parent.upsert_node(node("night","is_night"))
	parent.upsert_node(node("yes","bool",{"value":true}))
	parent.upsert_node(node("call","call",{"id":"user:brightness","version":1}))
	parent.connect_input("call","when","yes")
	parent.connect_input("call","enabled","night")
	parent.set_effects(["call"])
	check(r.publish_pack(parent.pack_json(),{"creation:004":[{"id":"user:composed","version":1}]}).ok,"publish_parent_using_existing_behavior")
	r.advance(true)
	check(w.get_instance("creation:004").state.light_on,"composed_module_executes")
	r.advance(false)
	check(not w.get_instance("creation:004").state.light_on,"call_argument_overrides_default")
	var scroll: Dictionary=r.export_rule("user:composed",1)
	check(scroll.ok and scroll.modules==2,"export_authored_module_closure")
	var files=Files.new()
	var slot: String="draft_"+str(OS.get_process_id())
	check(files.save(r,slot).ok,"save_authored_versions")
	var fresh_world=World.new(catalog)
	var fresh=Runtime.new(catalog,fresh_world)
	check(files.load_into(fresh,slot).ok,"load_authored_versions_in_fresh_runtime")
	check(fresh.checkpoint_json()==r.checkpoint_json(),"all_authored_versions_preserved")
	fresh.advance(true)
	check(fresh_world.get_instance("creation:004").state.light_on,"restored_composition_runs")
	# 可供离线检查独立验证的数据，不依赖测试状态文案。
	var output: String=OS.get_environment("RULEWEAVER_NATIVE_AUTHORING")
	if not output.is_empty():
		var file=FileAccess.open(output,FileAccess.WRITE)
		check(file!=null,"authoring_evidence_open")
		if file!=null:
			file.store_string(fresh.checkpoint_json())
			file.close()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String=files.slot_path(slot)+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	check(not child.set_parameter("when","bool",false).ok,"reserved_parameter_name")
	check(not child.set_parameter("n","int",true).ok,"boolean_not_integer_parameter")
	check(not child.upsert_node(node("bad id","bool",{"value":true})).ok,"bad_node_identifier")
	var non_json: Dictionary=node("obj","bool",{"value":RefCounted.new()})
	check(not child.upsert_node(non_json).ok,"object_not_rule_data")
	check(not child.upsert_node(node("nan","int",{"value":NAN})).ok,"nonfinite_draft_value_rejected")
	var oversized: Array=[]
	for i in 17:
		var leaves: Array=[]
		for j in 64: leaves.append(j)
		oversized.append(leaves)
	var previous_draft: String=child.pack_json()
	check(not child.upsert_node(node("oversize","int",{"value":oversized})).ok,"total_draft_value_budget")
	check(child.pack_json()==previous_draft,"oversized_edit_preserves_draft")
	var malformed: Dictionary=child.snapshot()
	malformed.id=42
	var rejected: Dictionary=child.restore(malformed)
	check(not rejected.get("ok",true),"malformed_draft_id_rejected_without_exception")
	finish()

func finish() -> void:
	print("DRAFT_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
