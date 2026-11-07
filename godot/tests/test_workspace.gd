extends SceneTree
const Loader=preload("res://runtime/scenario_loader.gd")
const Play=preload("res://runtime/play_session.gd")
const Files=preload("res://runtime/checkpoint_files.gd")
const Draft=preload("res://runtime/rule_draft.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func finish()->void:
	print("WORKSPACE_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func _run()->void:
	check(FileAccess.file_exists("res://presentation/workspace_checkpoint.gd"),"workspace_persistence_exists")
	if not FileAccess.file_exists("res://presentation/workspace_checkpoint.gd"):finish();return
	var Workspace=load("res://presentation/workspace_checkpoint.gd")
	var setup:Dictionary=Loader.load_scenario("res://content/first_expedition.json")
	var play=Play.new();root.add_child(play)
	check(play.bind_session(setup.expedition,setup.world,Rect2i(-8,-8,24,20)).ok,"workspace_play_bound")
	play.set_paused(true)
	var d=Draft.new();d.start("user:unfinished",1)
	d.upsert_node({"id":"lamp","op":"set_light","inputs":{},"config":{}});d.set_effects(["lamp"])
	var editor:Dictionary={"selected":"creation:vessel","tool":"vessel","drafts":{"creation:vessel":d.snapshot()}}
	var ws=Workspace.new(play,editor)
	var text:String=ws.checkpoint_json()
	check(ws.validate_checkpoint(text).ok,"incomplete_draft_valid_workspace_not_published")
	var before:String=play.checkpoint_json()
	check(setup.world.get_instance("creation:vessel").rules.is_empty(),"draft_does_not_bind_or_execute")
	var files=Files.new()
	check(files.save(ws,"test_workspace014").ok,"workspace_disk_save")
	var empty=Workspace.new(play)
	check(files.load_into(empty,"test_workspace014").ok,"workspace_disk_restore")
	check(empty.editor==editor,"draft_nodes_selection_and_tool_restored")
	check(play.checkpoint_json()==before,"draft_restore_preserves_world")
	check(empty.load_checkpoint(before).ok and empty.editor.drafts.is_empty(),"legacy_play_import_clears_editor_only")
	check(empty.load_checkpoint(text).ok,"reload_workspace_after_legacy")
	for mode in ["missing_selected","missing_draft_target","malformed_draft","bad_tool","extra_field","wrong_format","fraction","too_many_drafts"]:
		var bad:Dictionary=Workspace.integer_tree(JSON.parse_string(text))
		match mode:
			"missing_selected":bad.editor.selected="creation:missing"
			"missing_draft_target":bad.editor.drafts["creation:missing"]=d.snapshot()
			"malformed_draft":bad.editor.drafts["creation:vessel"]["extra"]=true
			"bad_tool":bad.editor.tool="run_system_script"
			"extra_field":bad["extra"]=true
			"wrong_format":bad.format="rw.workspace/99"
			"fraction":bad.editor.drafts["creation:vessel"].version=1.5
			"too_many_drafts":
				for i in 65:bad.editor.drafts["creation:other_%d"%i]=d.snapshot()
		var old:Dictionary=empty.editor.duplicate(true)
		check(not empty.load_checkpoint(JSON.stringify(bad)).ok,"reject_"+mode)
		check(play.checkpoint_json()==before and empty.editor==old,"atomic_"+mode)
	check(not empty.load_checkpoint(text.replace('"format":','"format":"rw.workspace/0.1","format":')).ok,"duplicate_json_keys_rejected")
	# 草稿结构可以缺线，但携带任何对象、脚本或超限树都不能保存。
	var invalid:Dictionary=editor.duplicate(true);invalid.drafts["creation:vessel"].nodes[0].config["payload"]=null
	var unsafe=Workspace.new(play,invalid)
	check(not unsafe.validate_checkpoint(unsafe.checkpoint_json()).ok,"unsupported_draft_values_rejected")
	for suffix in ["", ".bak", ".tmp"]:
		var path:String=files.slot_path("test_workspace014")+suffix
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	play.dispose();play.queue_free();await process_frame;finish()
