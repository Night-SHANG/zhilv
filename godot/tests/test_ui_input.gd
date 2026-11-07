extends SceneTree
## 通过Viewport投递鼠标/键盘事件，经过Control及现有角色/世界入口。
var passed: int=0
var failed: int=0
var app
func check(value: bool,label: String) -> void:
	if value:passed+=1;print("PASS: ",label)
	else:failed+=1;printerr("FAIL: ",label)
func _initialize() -> void:call_deferred("_run")
func finish() -> void:
	print("UI_INPUT_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
func frames(n: int) -> void:
	for i in n:await physics_frame
	await process_frame
func key(code: Key,pressed: bool) -> void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.pressed=pressed;root.push_input(e)
func mouse(pos: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=pos;motion.global_position=pos;root.push_input(motion)
	var e:=InputEventMouseButton.new();e.position=pos;e.global_position=pos;e.button_index=button;e.pressed=true;root.push_input(e)
	e=e.duplicate();e.pressed=false;root.push_input(e)
func click_control(control: Control) -> void:
	mouse(control.get_global_rect().get_center());await process_frame;await process_frame
func click_cell(cell: Vector2i,button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	mouse(app.viewport_canvas.global_position+app.viewport_canvas.cell_center(cell),button);await process_frame
func walk(target: int) -> bool:
	var desired: int=target*1024+512
	var code: Key=KEY_D if app.world.actor_body_foot().x<desired else KEY_A
	key(code,true)
	for i in 300:
		if abs(app.world.actor_body_foot().x-desired)<110:key(code,false);await frames(1);return true
		await frames(1)
	key(code,false);return false
func button_text(text: String) -> Button:
	for b in app.find_children("*","Button",true,false):
		if b.text==text:return b
	return null
func _run() -> void:
	root.size=Vector2i(1440,900)
	app=load("res://presentation/main.tscn").instantiate();root.add_child(app)
	await frames(3)
	app.new_game("res://content/first_expedition.json");await frames(2)
	check(app.setup_complete,"native_ui_scene_started")
	if not app.setup_complete:finish();return
	await click_control(app._pause_button)
	check(not app.runtime.clock_state().paused,"real_mouse_resumes_exploration")
	await frames(10)
	await click_control(app._tools[3])
	check(app.tool=="vessel","real_hotbar_mouse_selects_vessel")
	await click_cell(Vector2i(1,-1))
	check(app.world.get_instance("creation:vessel").location.kind=="world","canvas_pointer_places_authoritative_creation")
	key(KEY_TAB,true);key(KEY_TAB,false);await frames(2)
	check(app.loom.visible and app.runtime.clock_state().paused,"tab_opens_loom_and_pauses")
	var frozen: String=app.play.checkpoint_json()
	key(KEY_D,true);await frames(10);key(KEY_D,false)
	check(app.play.checkpoint_json()==frozen,"editing_blocks_real_movement_and_simulation")
	app.loom.document.preset("pump",250);await frames(1)
	await click_control(app.loom.find_child("ApplyRule",true,false))
	check(app.world.get_instance("creation:vessel").rules.size()==1,"real_apply_button_publishes_rule")
	key(KEY_TAB,true);key(KEY_TAB,false);await frames(2)
	check(not app.loom.visible and not app.runtime.clock_state().paused,"tab_restores_running_state")
	for i in range(400):
		if app.world.get_instance("creation:vessel").state.water_units>0:break
		await frames(1)
	check(app.world.get_instance("creation:vessel").state.water_units>0,"ui_authored_rule_takes_real_environment_water")
	check(app.save_game("ui_route").ok,"save_mid_pump_with_ui_service")
	var held: int=app.world.get_instance("creation:vessel").state.water_units
	check(app.load_game("ui_route").ok and app.world.get_instance("creation:vessel").state.water_units==held,"ui_reload_preserves_live_pump")
	await click_control(app._pause_button)
	for i in range(2400):
		if app.world.get_instance("creation:vessel").state.water_units>=5000:break
		await frames(1)
	check(app.world.get_instance("creation:vessel").state.water_units>=5000,"real_ui_route_clears_water")
	await click_cell(Vector2i(1,-1),MOUSE_BUTTON_RIGHT)
	check(app.world.get_instance("creation:vessel").location.kind=="inventory","right_click_recovers_same_water_filled_creation")
	await frames(480)
	check(await walk(6),"keyboard_moves_through_drained_passage")
	await click_control(app._tools[4]);await click_cell(Vector2i(9,-1));await frames(12)
	check(app.world.get_instance("creation:lamp").location.kind=="world" and app.world.get_instance("creation:lamp").state.light_on,"hotbar_places_real_logical_light")
	check(await walk(8),"keyboard_reaches_visible_ruins")
	check(app.expedition.status().completed.has("goal:ruins"),"actual_objective_reacts_to_player_light_water")
	check(await walk(-2),"keyboard_returns_to_camp")
	await click_control(button_text("交水 500"))
	check(app.expedition.status().completed==["goal:ruins","goal:irrigate"],"mouse_delivery_completes_existing_goals")
	check(app.world.total_water_units()==6000,"complete_ui_route_conserves_water")
	# 损坏文件、覆盖冲突不能被界面标成成功，也不能改变正在运行的世界。
	app.play.set_paused(true)
	var before: String=app.play.checkpoint_json()
	var bad:=FileAccess.open(app._files.slot_path("ui_bad"),FileAccess.WRITE);bad.store_string("{}");bad.close()
	check(not app.load_game("ui_bad").ok and app.play.checkpoint_json()==before,"bad_ui_save_keeps_current_world")
	app.select_item("creation:vessel")
	var export_path: String="user://ui_overwrite_test.json"
	check(app.export_scroll_to(export_path).ok,"first_export_succeeds")
	var old_text: String=FileAccess.get_file_as_string(export_path)
	check(not app.export_scroll_to(export_path).ok and FileAccess.get_file_as_string(export_path)==old_text,"existing_export_requires_explicit_overwrite")
	DirAccess.remove_absolute(export_path)
	for slot in ["ui_route","ui_bad"]:
		for suffix in ["", ".bak", ".tmp"]:
			var path: String=app._files.slot_path(slot)+suffix
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	var evidence: String=OS.get_environment("RULEWEAVER_NATIVE_UI_PLAY")
	if not evidence.is_empty():
		var file:=FileAccess.open(evidence,FileAccess.WRITE)
		if file!=null:file.store_string(app.play.checkpoint_json());file.close()
	app.queue_free();await process_frame;await process_frame;finish()
