extends SceneTree
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Expedition = preload("res://runtime/expedition_session.gd")
const Base = preload("res://tests/test_actor_body.gd")
var passed: int=0
var failed: int=0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1; print("PASS: ",label)
	else: failed+=1; printerr("FAIL: ",label)
func finish() -> void:
	print("PLATFORM_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
func _initialize() -> void: call_deferred("_run")
func setup(wall: bool=false,roof: bool=false) -> Dictionary:
	var data: Dictionary=Base.fixture()
	for x in range(-10,18): data.terrain.append({"cell":[x,1],"material_id":"core:stone"})
	if wall:
		for y in range(-3,1):data.terrain.append({"cell":[6,y],"material_id":"core:stone"})
	if roof:data.terrain.append({"cell":[0,-3],"material_id":"core:stone"})
	var w=World.new(Base.catalog());w.load_checkpoint(JSON.stringify(data))
	var r=Runtime.new(Base.catalog(),w)
	r.publish_pack(JSON.stringify({"format":"rw.rules/0.1","modules":[{"id":"user:idle","version":1,"parameters":{},"nodes":[{"id":"yes","op":"bool","config":{"value":true},"inputs":{}}],"effects":[]}]}))
	r.configure_clock(120,60)
	var e=Expedition.new();e.attach(r,w,{"id":"scenario:platform","version":1,"objectives":[{"id":"goal:walk","type":"visit","requires":[],"cell":[3,0],"lit":false,"max_water":1000}]})
	var Play=load("res://runtime/play_session.gd");var play=Play.new();root.add_child(play)
	var bound: Dictionary=play.bind_session(e,w,Rect2i(-12,-12,40,36))
	return {"world":w,"runtime":r,"expedition":e,"play":play,"ok":bound.ok,"error":bound.get("error","")}
func frames(play,count: int) -> Dictionary:
	var result: Dictionary={"ok":true}
	for i in range(count):
		await physics_frame
		result=play.step_frame(1.0/60.0)
		if not result.ok:return result
	return result
func event(action: String,pressed: bool) -> InputEventAction:
	var e:=InputEventAction.new();e.action=action;e.pressed=pressed;e.strength=1.0 if pressed else 0.0;return e
func _run() -> void:
	check(ResourceLoader.exists("res://runtime/play_session.gd"),"native_play_session_exists")
	if failed>0:finish();return
	var s: Dictionary=setup();var p=s.play;var w=s.world
	check(s.ok,"bind_authoritative_world_to_physics: "+s.error)
	check(p.motor is CharacterBody2D and p.collision_layer is TileMapLayer,"uses_real_native_character_and_tile_collisions")
	check((await frames(p,15)).ok and p.motor.is_on_floor(),"gravity_lands_on_native_floor")
	check(w.actor_cell()==Vector2i(0,0),"landed_pose_matches_authoritative_anchor")
	check(p.accept_input(event("rw_move_right",true)),"accept_native_action_event")
	check((await frames(p,30)).ok and w.actor_cell().x>=2,"held_input_moves_continuously")
	p.accept_input(event("rw_move_right",false))
	var stationary: int=w.actor_body_foot().x
	await frames(p,10)
	check(w.actor_body_foot().x==stationary,"release_stops_without_stuck_key")
	check(s.expedition.status().completed.has("goal:walk"),"walking_updates_existing_expedition_goal")
	var standing: int=w.actor_body_foot().y
	p.accept_input(event("rw_jump",true));await frames(p,8)
	check(w.actor_body_foot().y<standing-400 and p.motor.velocity.y<0,"jump_uses_actual_physics_not_grid_teleport")
	p.accept_input(event("rw_jump",false));await frames(p,80)
	check(p.motor.is_on_floor() and abs(w.actor_body_foot().y-standing)<=2,"jump_returns_to_floor")
	p.accept_input(event("rw_jump",true));await frames(p,100)
	check(p.motor.is_on_floor(),"holding_jump_does_not_auto_bounce")
	p.accept_input(event("rw_jump",false))
	var pause_before: String=p.checkpoint_json()
	check(p.set_paused(true).ok,"pause_session")
	pause_before=p.checkpoint_json()
	p.accept_input(event("rw_move_left",true));await frames(p,12)
	check(p.checkpoint_json()==pause_before,"pause_freezes_motion_clock_and_rules")
	check(p.set_paused(false).ok,"resume_session")
	stationary=w.actor_body_foot().x;await frames(p,10)
	check(w.actor_body_foot().x==stationary,"paused_key_does_not_leak_on_resume")
	check(not p.step_frame(-1.0).ok and not p.step_frame(NAN).ok,"invalid_delta_rejected")
	var foot: Vector2i=w.actor_cell()
	check(p.command({"op":"mine","cell":[foot.x,1]}).ok,"mine_through_same_interaction_interface")
	await frames(p,18)
	check(w.actor_body_foot().y>standing+200,"mining_floor_removes_native_support")
	p.dispose();p.free()
	await physics_frame
	var s2: Dictionary=setup(true);p=s2.play;w=s2.world
	await frames(p,10);p.accept_input(event("rw_move_right",true));await frames(p,100)
	check(p.motor.is_on_wall() and w.actor_body_foot().x<6*1024-300,"wall_stops_native_character")
	check(not p.command({"op":"move","delta":[1,0]}).ok,"play_commands_cannot_bypass_motor")
	p.dispose();p.free();await physics_frame
	var s3: Dictionary=setup(false,true);p=s3.play;w=s3.world
	await frames(p,10);p.accept_input(event("rw_jump",true));await frames(p,8)
	check(w.actor_body_foot().y>=-2*1024+1792,"ceiling_stops_head")
	p.dispose();p.free();await physics_frame
	finish()
