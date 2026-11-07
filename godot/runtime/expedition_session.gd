extends RefCounted
## 小型探索会话：目标只检查世界结果，不认识某个吸水器配方。
## 控制器订阅changed；地图投影仍直接订阅WorldSession。此处不另存世界或库存。
signal changed
const Codec = preload("res://runtime/snapshot_codec.gd")
const WorldCodec = preload("res://runtime/world_codec.gd")
var _runtime
var _world
var _definition: Dictionary = {}
var _completed: Array = []
var _world_id: String = ""
var _busy: bool = false

func attach(runtime, world, definition: Variant) -> Dictionary:
	if _busy or runtime == null or world == null or runtime._world != world or runtime.clock_state().is_empty() or world.rule_view().is_empty(): return Codec.reject("invalid_expedition_binding")
	if not Codec._shape(definition,["id","version","objectives"]) or not Codec.identifier(definition.id) or not Codec._integer(definition.version,1,2147483647) or not definition.objectives is Array or definition.objectives.is_empty() or definition.objectives.size()>16:
		return Codec.reject("scenario_definition")
	var normalized: Dictionary=definition.duplicate(true)
	normalized.version=int(normalized.version)
	var ids: Dictionary={}
	for goal in normalized.objectives:
		if not goal is Dictionary or not Codec.identifier(goal.get("id")) or ids.has(goal.id) or not goal.get("requires") is Array:
			return Codec.reject("scenario_goal")
		var required: Dictionary={}
		for dependency in goal.requires:
			if not dependency is String or not ids.has(dependency) or required.has(dependency): return Codec.reject("goal_dependency_order")
			required[dependency]=true
		match goal.get("type"):
			"visit":
				if not Codec._shape(goal,["id","type","requires","cell","lit","max_water"]) or not WorldCodec.cell_valid(goal.cell) or typeof(goal.lit)!=TYPE_BOOL or not Codec._integer(goal.max_water,0,1000): return Codec.reject("visit_goal")
				goal.cell=[int(goal.cell[0]),int(goal.cell[1])]; goal.max_water=int(goal.max_water)
			"deliver":
				if not Codec._shape(goal,["id","type","requires","instance","water_units"]) or not Codec.identifier(goal.instance) or not Codec._integer(goal.water_units,1,Codec.MAX_QUANTITY): return Codec.reject("delivery_goal")
				goal.water_units=int(goal.water_units)
			_:
				return Codec.reject("unknown_goal_type")
		ids[goal.id]=true
	_runtime=runtime; _world=world; _definition=normalized; _completed=[]
	_world_id=world.rule_view().entities.world_id
	return {"ok":true,"error":""}

func _observe() -> void:
	for goal in _definition.objectives:
		if _completed.has(goal.id): continue
		var ready: bool=true
		for dependency in goal.requires:
			if not _completed.has(dependency): ready=false
		if not ready: continue
		var satisfied: bool=false
		if goal.type=="visit":
			var target:=Vector2i(goal.cell[0],goal.cell[1])
			satisfied=_world.actor_cell()==target and _world.water_at(target)<=goal.max_water and _world.water_at(target+Vector2i.UP)<=goal.max_water
			if satisfied and goal.lit: satisfied=_world.has_light_at(target,_runtime.clock_state().night)
		else:
			var entity: Dictionary=_world.get_instance(goal.instance)
			satisfied=not entity.is_empty() and entity.location.kind=="world" and entity.state.water_units>=goal.water_units and _world._accessible_instance(goal.instance).ok
		if satisfied: _completed.append(goal.id)

func observe() -> Dictionary:
	if _busy or _runtime==null: return Codec.reject("expedition_busy_or_unbound")
	_observe()
	return status()

func status() -> Dictionary:
	if _runtime==null: return Codec.reject("expedition_unbound")
	return {"ok":true,"error":"","completed":_completed.duplicate(),"total":_definition.objectives.size(),"clock":_runtime.clock_state(),"water_units":_world.total_water_units()}

func clock_state() -> Dictionary:
	return {} if _runtime==null else _runtime.clock_state()

func advance_tick() -> Dictionary:
	return act({"op":"advance"})

static func _cell(value: Variant) -> bool:
	return WorldCodec.cell_valid(value) and typeof(value[0])==TYPE_INT and typeof(value[1])==TYPE_INT

func act(command: Variant) -> Dictionary:
	if _busy or _runtime==null or _runtime._busy: return Codec.reject("expedition_busy_or_unbound")
	if not command is Dictionary or not command.get("op") is String: return Codec.reject("invalid_player_command")
	var expected: Dictionary={"move":["op","delta"],"mine":["op","cell"],"build":["op","cell","material"],"pickup":["op","id"],"place":["op","id","cell"],"collect":["op","id","cell","amount"],"release":["op","id","cell","amount"],"pour":["op","source","target","amount"],"advance":["op"],"single_step":["op"],"pause":["op","value"]}
	if not expected.has(command.op) or not Codec._shape(command,expected[command.op]): return Codec.reject("player_command_fields")
	for key in ["cell","delta"]:
		if command.has(key) and not _cell(command[key]): return Codec.reject("invalid_player_cell")
	for key in ["id","source","target","material"]:
		if command.has(key) and not Codec.identifier(command[key]): return Codec.reject("invalid_player_id")
	if command.has("amount") and (typeof(command.amount)!=TYPE_INT or command.amount<1 or command.amount>Codec.MAX_QUANTITY): return Codec.reject("invalid_player_amount")
	_busy=true
	var result: Dictionary
	match command.op:
		"move": result=_world.step_actor(Vector2i(command.delta[0],command.delta[1]))
		"mine": result=_world.mine(Vector2i(command.cell[0],command.cell[1]))
		"build": result=_world.build(command.material,Vector2i(command.cell[0],command.cell[1]))
		"pickup": result=_world.pickup(command.id)
		"place": result=_world.place(command.id,Vector2i(command.cell[0],command.cell[1]))
		"collect": result=_world.collect_water(command.id,Vector2i(command.cell[0],command.cell[1]),command.amount)
		"release": result=_world.release_water(command.id,Vector2i(command.cell[0],command.cell[1]),command.amount)
		"pour": result=_world.pour_water(command.source,command.target,command.amount)
		"advance": result=_runtime.advance_tick()
		"single_step": result=_runtime.single_step()
		"pause": result=_runtime.set_paused(command.value)
	if result.ok:
		_observe()
		result["completed"]=_completed.duplicate()
		changed.emit()
	_busy=false
	return result

func checkpoint_value() -> Dictionary:
	if _runtime==null: return {}
	return {"format":"rw.expedition/0.1","scenario_id":_definition.id,"scenario_version":_definition.version,"completed":_completed.duplicate(),"simulation":_runtime.checkpoint_value()}

func checkpoint_json() -> String:
	return JSON.stringify(checkpoint_value())

func validate_checkpoint(text: String) -> Dictionary:
	if _runtime==null: return Codec.reject("expedition_unbound")
	var error: String=Codec._lexical_error(text)
	if not error.is_empty(): return Codec.reject(error)
	var parser:=JSON.new()
	if parser.parse(text)!=OK: return Codec.reject("expedition_json")
	return validate_checkpoint_value(parser.data)

func validate_checkpoint_value(d: Variant) -> Dictionary:
	if _runtime==null: return Codec.reject("expedition_unbound")
	if not Codec._shape(d,["format","scenario_id","scenario_version","completed","simulation"]) or d.format!="rw.expedition/0.1" or d.scenario_id!=_definition.id or not Codec._integer(d.scenario_version,1,2147483647) or int(d.scenario_version)!=_definition.version or not d.completed is Array or d.completed.size()>16:
		return Codec.reject("expedition_fields")
	var accepted: Array=[]
	for goal in _definition.objectives:
		if not d.completed.has(goal.id): continue
		for dependency in goal.requires:
			if not accepted.has(dependency): return Codec.reject("completed_missing_dependency")
		accepted.append(goal.id)
	if accepted.size()!=d.completed.size(): return Codec.reject("invalid_completed_goals")
	var simulation: Dictionary=_runtime.validate_checkpoint_value(d.simulation)
	if not simulation.ok: return simulation
	if simulation.clock.is_empty() or simulation.world.entities.world_id!=_world_id: return Codec.reject("expedition_world_or_clock")
	return {"ok":true,"error":"","completed":accepted,"simulation":simulation}

func load_checkpoint(text: String) -> Dictionary:
	if _busy or _runtime==null or _runtime._busy: return Codec.reject("expedition_busy_or_unbound")
	var checked: Dictionary=validate_checkpoint(text)
	if not checked.ok: return checked
	return adopt_checked_checkpoint(checked)

func adopt_checked_checkpoint(checked: Dictionary) -> Dictionary:
	# 内部协调接口；调用方必须已经通过完整信封验证。
	if _busy or _runtime==null or _runtime._busy: return Codec.reject("expedition_busy_or_unbound")
	var simulation: Dictionary=checked.simulation
	var prepared: Dictionary=_world._prepare_rule_revision(simulation.program.catalog.rules,simulation.world)
	if not prepared.ok: return prepared
	_busy=true
	_completed=checked.completed.duplicate()
	_runtime._adopt_revision(simulation.program,prepared,simulation.tick,simulation.clock)
	changed.emit()
	_busy=false
	return {"ok":true,"error":""}
