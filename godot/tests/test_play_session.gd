extends SceneTree
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Expedition = preload("res://runtime/expedition_session.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
const Base = preload("res://tests/test_actor_body.gd")
const Play = preload("res://runtime/play_session.gd")
var passed: int=0
var failed: int=0
var observed_play
var reentrant: Dictionary={}
var callback_motion: Dictionary={}
func check(ok: bool,label: String) -> void:
	if ok:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func finish() -> void:
	print("PLAY_SESSION_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
func _initialize() -> void:call_deferred("_run")
func setup() -> Dictionary:
	var data: Dictionary=Base.fixture()
	for x in range(-10,18):data.terrain.append({"cell":[x,1],"material_id":"core:stone"})
	data.water=[{"cell":[8,0],"units":150}]
	var w=World.new(Base.catalog());w.load_checkpoint(JSON.stringify(data))
	var r=Runtime.new(Base.catalog(),w)
	r.publish_pack(JSON.stringify({"format":"rw.rules/0.1","modules":[{"id":"user:idle","version":1,"parameters":{},"nodes":[{"id":"yes","op":"bool","config":{"value":true},"inputs":{}}],"effects":[]}]}))
	r.configure_clock(120,60)
	var e=Expedition.new();e.attach(r,w,{"id":"scenario:platform","version":1,"objectives":[{"id":"goal:walk","type":"visit","requires":[],"cell":[3,0],"lit":false,"max_water":1000}]})
	var p=Play.new();root.add_child(p)
	return {"world":w,"runtime":r,"expedition":e,"play":p,"ok":p.bind_session(e,w,Rect2i(-12,-12,40,36)).ok}
func frames(play,count: int) -> Dictionary:
	for i in range(count):
		await physics_frame
		var result: Dictionary=play.step_frame(1.0/60.0)
		if not result.ok:return result
	return {"ok":true}
func key(action: String,pressed: bool) -> InputEventAction:
	var e:=InputEventAction.new();e.action=action;e.pressed=pressed;e.strength=1.0 if pressed else 0.0;return e
func observe_motion() -> void:
	var m: Dictionary=JSON.parse_string(observed_play.checkpoint_json()).motion
	callback_motion={"velocity_x":int(m.velocity_x),"velocity_y":int(m.velocity_y)}
func guard() -> void:reentrant=observed_play.command({"op":"mine","cell":[0,1]})
func _run() -> void:
	var s: Dictionary=setup();var p=s.play;var w=s.world;var e=s.expedition
	check(s.ok,"play_binding")
	check((await frames(p,10)).ok,"play_initial_physics")
	var old_x: int=w.actor_body_foot().x
	root.push_input(key("rw_move_right",true));await frames(p,8)
	root.push_input(key("rw_move_right",false));await frames(p,3)
	check(w.actor_body_foot().x>old_x,"viewport_delivers_unhandled_native_input")
	var real_key:=InputEventKey.new();real_key.physical_keycode=KEY_A;real_key.pressed=true
	root.push_input(real_key);old_x=w.actor_body_foot().x;await frames(p,5)
	real_key=InputEventKey.new();real_key.physical_keycode=KEY_A;real_key.pressed=false;root.push_input(real_key)
	check(w.actor_body_foot().x<old_x,"physical_A_binding_works")
	p.set_controls_enabled(false);root.push_input(key("rw_move_right",true));old_x=w.actor_body_foot().x;await frames(p,5)
	check(w.actor_body_foot().x==old_x,"editor_input_gate_prevents_walking")
	var edit_checkpoint: String=p.checkpoint_json()
	check(not p.command({"op":"mine","cell":[0,1]}).ok and p.checkpoint_json()==edit_checkpoint,"editor_gate_blocks_world_actions_not_only_walk")
	p.set_controls_enabled(true)
	p.accept_input(key("rw_move_right",true))
	await physics_frame
	p.step_frame(1.0/60.0)
	var checkpoint: String=p.checkpoint_json()
	p.step_frame(1.0/60.0)
	check(p.checkpoint_json()==checkpoint,"duplicate_same_physics_frame_is_not_double_stepped")
	p.accept_input(key("rw_move_right",false))
	p.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(e.clock_state().paused,"focus_loss_pauses_world")
	checkpoint=p.checkpoint_json();await frames(p,5)
	check(p.checkpoint_json()==checkpoint,"focus_pause_stops_all_timing")
	var before_tick: int=e.clock_state().tick
	var before_foot: Vector2i=w.actor_body_foot()
	check(p.single_step().ok and e.clock_state().tick==before_tick+1 and w.actor_body_foot()==before_foot and e.clock_state().paused,"single_step_changes_simulation_not_frozen_body")
	check(not p.command({"op":"mine","cell":[0,1]}).ok,"menu_pause_blocks_world_interaction")
	check(p.set_paused(false).ok and not p.single_step().ok,"single_step_requires_pause")
	# 验证真正的检查点落盘与原生运动状态恢复。
	p.accept_input(key("rw_jump",true));await frames(p,7);p.accept_input(key("rw_jump",false))
	var saved_pose: Vector2i=w.actor_body_foot();var saved_motion: Dictionary=p.motor.motion_value()
	var slot: String="play_"+str(OS.get_process_id());var files=Files.new()
	check(files.save(p,slot).ok,"save_play_with_motion_and_world")
	var saved_text: String=p.checkpoint_json()
	await frames(p,70)
	check(p.motor.is_on_floor(),"standing_before_midair_restore")
	observed_play=p;e.changed.connect(observe_motion)
	check(files.load_into(p,slot).ok,"restore_full_play_checkpoint")
	check(callback_motion==saved_motion,"restore_observers_see_matching_motion_and_world")
	e.changed.disconnect(observe_motion);observed_play=null
	check(w.actor_body_foot()==saved_pose and p.motor.motion_value()==saved_motion,"pose_and_velocity_restored_not_only_grid_cell")
	check(w.total_water_units()==150,"water_preserved_with_player_restore")
	check(p.checkpoint_json()==saved_text,"checkpoint_normalized_roundtrip")
	# 恢复空中速度为0，再立即按跳跃；旧is_on_floor不能授予空中跳。
	var checked: Dictionary=p.validate_checkpoint(saved_text)
	var airborne: Dictionary=p._expedition.checkpoint_value()
	var f: Array=airborne.simulation.world.actor.body_foot
	f[1]-=2048
	var pos:=Vector2i(f[0],f[1]);var cell=load("res://runtime/world_codec.gd").body_cell(pos)
	airborne.simulation.world.actor.cell=[cell.x,cell.y]
	var midair: String=JSON.stringify({"format":"rw.play/0.1","expedition":airborne,"motion":{"velocity_x":0,"velocity_y":0}})
	await frames(p,70)
	check(p.motor.is_on_floor() and p.load_checkpoint(midair).ok,"restore_midair_from_grounded_motor")
	p.accept_input(key("rw_jump",true));await frames(p,1)
	check(p.motor.velocity.y>=0,"stale_floor_cache_cannot_create_air_jump")
	p.accept_input(key("rw_jump",false))
	checkpoint=p.checkpoint_json()
	var bad: Dictionary=p._expedition.checkpoint_value()
	var text: String=JSON.stringify({"format":"rw.play/0.1","expedition":bad,"motion":{"velocity_x":9999999,"velocity_y":0}})
	check(not p.load_checkpoint(text).ok and p.checkpoint_json()==checkpoint,"bad_motion_preserves_everything")
	check(not p.load_checkpoint('{"format":"rw.play/0.1","format":"rw.play/0.1"}').ok,"duplicate_keys_rejected")
	bad=p._expedition.checkpoint_value();bad.completed=["goal:unknown"]
	text=JSON.stringify({"format":"rw.play/0.1","expedition":bad,"motion":{"velocity_x":0,"velocity_y":0}})
	check(not p.load_checkpoint(text).ok and p.checkpoint_json()==checkpoint,"bad_goal_preserves_motion_and_world")
	observed_play=p;p.changed.connect(guard)
	p.set_paused(true)
	check(reentrant.get("error")=="play_busy_or_unbound","callbacks_cannot_reenter_mutation")
	p.changed.disconnect(guard);observed_play=null
	var out_path: String=OS.get_environment("RULEWEAVER_NATIVE_PLAY")
	if not out_path.is_empty():
		var out=FileAccess.open(out_path,FileAccess.WRITE);check(out!=null,"play_evidence_open")
		if out!=null:out.store_string(p.checkpoint_json());out.close()
	for suffix in ["", ".bak", ".tmp"]:
		var path: String=files.slot_path(slot)+suffix
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	p.dispose();p.free();await physics_frame
	var teardown: Dictionary=setup()
	check(teardown.ok,"second_session_binding")
	var live_p=teardown.play
	check(live_p.start().ok,"auto_physics_host_starts")
	var live_x: int=teardown.world.actor_body_foot().x
	root.push_input(key("rw_move_right",true))
	for i in range(15): await physics_frame
	root.push_input(key("rw_move_right",false))
	check(teardown.world.actor_body_foot().x>live_x and teardown.runtime.clock_state().tick>0,"automatic_node_drives_real_input_and_simulation")
	root.push_input(key("rw_pause",true))
	for i in range(2): await physics_frame
	var stopped: String=live_p.checkpoint_json()
	for i in range(5): await physics_frame
	check(live_p.checkpoint_json()==stopped and teardown.runtime.clock_state().paused,"native_pause_action_freezes_auto_host")
	var orphan_world=teardown.world
	var driver_id: int=teardown.play._driver.get_instance_id()
	teardown.play.free()
	await physics_frame
	check(orphan_world.committed.get_connections().is_empty() and orphan_world.reloaded.get_connections().is_empty(),"free_without_explicit_dispose_disconnects_world")
	check(not is_instance_id_valid(driver_id),"detached_driver_is_freed_with_session")
	finish()
