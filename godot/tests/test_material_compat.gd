extends SceneTree
const Loader=preload("res://runtime/scenario_loader.gd")
const Play=preload("res://runtime/play_session.gd")
const Workspace=preload("res://presentation/workspace_checkpoint.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("_run")
func _run()->void:
	var setup:Dictionary=Loader.load_scenario("res://content/fresh_expedition.json")
	check(setup.ok,"current_scene_loads")
	var play=Play.new();root.add_child(play)
	check(play.bind_session(setup.expedition,setup.world,Rect2i(-8,-8,24,20)).ok,"native_play_bind");play.set_paused(true)
	var folder:String=OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	if folder.is_empty():folder=ProjectSettings.globalize_path("res://../fixtures")
	var text:String=FileAccess.get_file_as_string(folder.path_join("legacy_v016_workspace.json"))
	var old:Variant=Workspace.integer_tree(JSON.parse_string(text))
	check(old is Dictionary and old.get("format")=="rw.workspace/0.1","actual_v016_output_fixture")
	var workspace=Workspace.new(play);var result:Dictionary=workspace.load_checkpoint(text)
	check(result.ok,"actual_v016_workspace_accepted")
	if not result.ok:play.dispose();play.queue_free();finish();return
	var current:Dictionary=Workspace.integer_tree(JSON.parse_string(workspace.checkpoint_json()))
	check(current.play.expedition.scenario_version==3,"next_save_declares_v3")
	check(current.play.expedition.completed==old.play.expedition.completed and current.play.expedition.completed.size()==4,"no_free_fifth_goal")
	check(current.play.expedition.simulation==old.play.expedition.simulation,"world_clock_and_program_unchanged")
	check(current.editor==old.editor and current.play.motion==old.play.motion,"editor_and_motion_preserved")
	check(setup.world.total_water_units()==6000 and setup.world.bound_water_units()==0,"no_resource_injected")
	check(workspace.load_checkpoint(workspace.checkpoint_json()).ok,"new_roundtrip")
	for mode in ["future_goal","version","duplicate","world"]:
		var invalid:Dictionary=old.duplicate(true)
		match mode:
			"future_goal":invalid.play.expedition.completed.append("goal:high_observatory")
			"version":invalid.play.expedition.scenario_version=99
			"duplicate":invalid.play.expedition.completed.append("goal:ruins")
			"world":invalid.play.expedition.simulation.world.entities.world_id="world:other"
		var before:String=workspace.checkpoint_json()
		check(not workspace.load_checkpoint(JSON.stringify(invalid)).ok and workspace.checkpoint_json()==before,"atomic_reject_"+mode)
	var classic:Dictionary=Loader.load_scenario("res://content/first_expedition.json")
	check(classic.ok and not classic.runtime._catalog.materials.has("core:water_crystal"),"legacy_scene_keeps_original_capabilities")
	play.dispose();play.queue_free();await process_frame;finish()
func finish()->void:
	print("MATERIAL_COMPAT_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
