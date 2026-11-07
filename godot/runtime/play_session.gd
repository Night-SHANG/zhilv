extends Node
## 非视觉操作宿主。原生角色/输入与现有探索、规则和水共用一个权威世界。
## 不制作菜单、精灵或样板尚未确认的正式画面；宿主显式start才启用自动帧。
signal changed
signal fault(reason: String)
const Codec = preload("res://runtime/snapshot_codec.gd")
const WC = preload("res://runtime/world_codec.gd")
const Motor = preload("res://runtime/platform_motor.gd")
const TerrainView = preload("res://runtime/terrain_projection.gd")
const Driver = preload("res://runtime/simulation_driver.gd")
var motor: CharacterBody2D
var collision_layer: TileMapLayer
var _projection
var _driver
var _world
var _expedition
var _window: Rect2i
var _left: bool = false
var _right: bool = false
var _jump_held: bool = false
var _jump_queued: bool = false
var _busy: bool = false
var _controls: bool = true
var _last_physics_frame: int = -1

func _init() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)

static func install_input_actions() -> void:
	var bindings: Dictionary = {"rw_move_left":[KEY_A,KEY_LEFT],"rw_move_right":[KEY_D,KEY_RIGHT],"rw_jump":[KEY_SPACE],"rw_pause":[KEY_ESCAPE]}
	for action in bindings:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		for code in bindings[action]:
			var event := InputEventKey.new(); event.physical_keycode = code
			InputMap.action_add_event(action,event)

func bind_session(expedition, world, window: Rect2i) -> Dictionary:
	if _busy or _world != null or not is_inside_tree() or expedition == null or world == null or expedition._world != world or expedition.clock_state().is_empty() or world.rule_view().is_empty():
		return Codec.reject("play_binding")
	if window.size.x < 4 or window.size.y < 4 or window.size.x > 128 or window.size.y > 128:
		return Codec.reject("play_window")
	for cell: Vector2i in world.actor_occupied_cells():
		if not window.has_point(cell): return Codec.reject("play_actor_outside_window")
	var result: Dictionary = world.enable_actor_body()
	if not result.ok: return result
	_world = world; _expedition = expedition; _window = window
	install_input_actions()
	collision_layer = TileMapLayer.new()
	collision_layer.visible = false
	collision_layer.tile_set = _collision_tiles()
	add_child(collision_layer)
	_projection = TerrainView.new()
	var sources: Dictionary = {}
	for id in world.material_ids(): sources[id] = 0
	result = _projection.bind_world(world,collision_layer,sources,window)
	if not result.ok: dispose(); return result
	motor = Motor.new(); add_child(motor)
	result = motor.bind_world(world,window)
	if not result.ok: dispose(); return result
	_driver = Driver.new()
	result = _driver.bind_runtime(expedition,10)
	_driver.set_physics_process(false)
	set_process_unhandled_input(true)
	return result

static func _collision_tiles() -> TileSet:
	var tiles := TileSet.new(); tiles.tile_size = Vector2i(16,16)
	tiles.add_physics_layer(); tiles.set_physics_layer_collision_layer(0,1)
	var image := Image.create(16,16,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	var source := TileSetAtlasSource.new(); source.texture=ImageTexture.create_from_image(image)
	source.texture_region_size=Vector2i(16,16); tiles.add_source(source,0); source.create_tile(Vector2i.ZERO)
	var data: TileData=source.get_tile_data(Vector2i.ZERO,0)
	data.set_collision_polygons_count(0,1)
	data.set_collision_polygon_points(0,0,PackedVector2Array([Vector2(-8,-8),Vector2(8,-8),Vector2(8,8),Vector2(-8,8)]))
	return tiles

func start() -> Dictionary:
	if _world == null: return Codec.reject("play_unbound")
	set_physics_process(true)
	return {"ok":true,"error":""}

func _clear_input() -> void:
	_left=false; _right=false; _jump_held=false; _jump_queued=false

func accept_input(event: InputEvent) -> bool:
	if _world == null or _busy or event == null or event.is_echo(): return false
	if event.is_action_pressed("rw_pause"):
		set_paused(not _expedition.clock_state().paused)
		return true
	if not _controls or _expedition.clock_state().paused: return false
	if event.is_action("rw_move_left"):
		_left=event.is_action_pressed("rw_move_left"); return true
	if event.is_action("rw_move_right"):
		_right=event.is_action_pressed("rw_move_right"); return true
	if event.is_action("rw_jump"):
		var pressed: bool=event.is_action_pressed("rw_jump")
		if pressed and not _jump_held: _jump_queued=true
		_jump_held=pressed; return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if accept_input(event): get_viewport().set_input_as_handled()

func set_controls_enabled(value: bool) -> void:
	_controls=value; _clear_input()

func set_paused(value: Variant) -> Dictionary:
	if _busy or _expedition == null: return Codec.reject("play_busy_or_unbound")
	if typeof(value) != TYPE_BOOL: return Codec.reject("invalid_pause")
	_busy=true
	_clear_input()
	var result: Dictionary=_expedition.act({"op":"pause","value":value})
	if result.ok:
		_driver.reset_accumulator()
		changed.emit()
	_busy=false
	return result

func step_frame(delta: Variant) -> Dictionary:
	if _busy or _world == null: return Codec.reject("play_busy_or_unbound")
	if (typeof(delta)!=TYPE_FLOAT and typeof(delta)!=TYPE_INT) or not is_finite(float(delta)) or delta < 0 or delta > 0.05: return Codec.reject("play_frame_delta")
	if delta==0: return {"ok":true,"error":"","steps":0}
	if not Engine.is_in_physics_frame(): return Codec.reject("play_requires_physics_frame")
	var frame: int=Engine.get_physics_frames()
	if frame==_last_physics_frame: return {"ok":true,"error":"","steps":0,"duplicate_frame":true}
	_last_physics_frame=frame
	if _expedition.clock_state().paused:
		_clear_input(); _driver.reset_accumulator()
		return {"ok":true,"error":"","steps":0}
	_busy=true
	var jump: bool=_jump_queued; _jump_queued=false
	var movement: Dictionary=motor.step_motion(float(delta),int(_right)-int(_left),jump)
	if not movement.ok:
		_busy=false; return movement
	_expedition.observe()
	var result: Dictionary=_driver.process_delta(delta)
	if result.ok:
		result["blocked"]=movement.get("blocked","")
		changed.emit()
	_busy=false
	return result

func command(value: Variant) -> Dictionary:
	if _busy or _world == null: return Codec.reject("play_busy_or_unbound")
	if not _controls: return Codec.reject("play_controls_disabled")
	if _expedition.clock_state().paused: return Codec.reject("play_paused")
	if not value is Dictionary or not value.get("op") in ["mine","build","pickup","place","collect","release","pour"]:
		return Codec.reject("play_command_not_allowed")
	_busy=true
	var result: Dictionary=_expedition.act(value)
	if result.ok: changed.emit()
	_busy=false
	return result

## 制作仅允许在暂停的背包操作中，不开放其他世界命令。
func craft_in_inventory(recipe: Variant) -> Dictionary:
	if _busy or _world == null: return Codec.reject("play_busy_or_unbound")
	if not _expedition.clock_state().paused or _controls: return Codec.reject("craft_requires_inventory_pause")
	_busy=true
	var result: Dictionary=_expedition.act({"op":"craft","recipe":recipe})
	if result.ok: changed.emit()
	_busy=false
	return result

func single_step() -> Dictionary:
	if _busy or _world == null or not _expedition.clock_state().paused: return Codec.reject("play_step_requires_pause")
	_busy=true
	var result: Dictionary=_expedition.act({"op":"single_step"})
	if result.ok: changed.emit()
	_busy=false
	return result

func checkpoint_json() -> String:
	if _world == null: return "{}"
	return JSON.stringify({"format":"rw.play/0.1","expedition":_expedition.checkpoint_value(),"motion":motor.motion_value()})

func validate_checkpoint(text: String) -> Dictionary:
	if _world == null: return Codec.reject("play_unbound")
	var error: String=Codec._lexical_error(text)
	if not error.is_empty(): return Codec.reject(error)
	var parser:=JSON.new()
	if parser.parse(text)!=OK: return Codec.reject("play_json")
	var data: Variant=parser.data
	if not Codec._shape(data,["format","expedition","motion"]) or data.format!="rw.play/0.1" or not Motor.valid_motion(data.motion): return Codec.reject("play_checkpoint_fields")
	var checked: Dictionary=_expedition.validate_checkpoint_value(data.expedition)
	if not checked.ok: return checked
	if checked.simulation.world.format!="rw.world/0.3": return Codec.reject("play_body_missing")
	for cell: Vector2i in WC.actor_cells(checked.simulation.world.actor):
		if not _window.has_point(cell): return Codec.reject("play_actor_outside_window")
	return {"ok":true,"error":"","expedition":checked,"motion":{"velocity_x":int(data.motion.velocity_x),"velocity_y":int(data.motion.velocity_y)}}

func load_checkpoint(text: String) -> Dictionary:
	if _busy or _world == null or _expedition._runtime._busy: return Codec.reject("play_busy_or_unbound")
	var checked: Dictionary=validate_checkpoint(text)
	if not checked.ok: return checked
	_busy=true
	# 先准备无通知速度，使下层恢复通知读取到的新世界和运动检查点一致。
	var previous_motion: Dictionary=motor.motion_value()
	motor.velocity=Vector2(checked.motion.velocity_x,checked.motion.velocity_y)/64.0
	var result: Dictionary=_expedition.adopt_checked_checkpoint(checked.expedition)
	if result.ok:
		motor.restore_motion(checked.motion)
		_clear_input(); _driver.reset_accumulator()
		changed.emit()
	else:
		motor.restore_motion(previous_motion)
	_busy=false
	return result

func _physics_process(delta: float) -> void:
	var result: Dictionary=step_frame(delta)
	if not result.ok:
		set_physics_process(false)
		fault.emit(result.error)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and _world!=null and not _busy: set_paused(true)

func dispose() -> void:
	set_physics_process(false); set_process_unhandled_input(false)
	_clear_input()
	if _projection!=null: _projection.dispose(); _projection=null
	if _driver!=null: _driver.dispose(); _driver.free(); _driver=null
	if is_instance_valid(motor): motor.dispose(); motor.free()
	if is_instance_valid(collision_layer): collision_layer.free()
	motor=null; collision_layer=null; _world=null; _expedition=null

func _exit_tree() -> void:
	dispose()
