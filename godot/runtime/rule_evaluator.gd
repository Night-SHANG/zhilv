extends RefCounted
## 只读快照求值；本对象绝不持有WorldSession，也不修改世界。
const Codec = preload("res://runtime/snapshot_codec.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")
var _modules: Dictionary
var _entity: Dictionary
var _cells: Dictionary
var _instances: Dictionary
var _water: Dictionary
var _roofs: Dictionary
var _night: bool
var _budget: int
var _spent: int = 0
var _error: String = ""
var _commands: Array = []
var _checks: Array = []
var _module: String = ""
var _node: String = ""

func run(program: Dictionary, entity: Dictionary, view: Dictionary, night: bool, budget: int) -> Dictionary:
	_modules = program.modules
	_entity = entity
	_cells = view.cells
	_instances = view.instances
	_water = view.get("water",{})
	_roofs = view.get("roofs",{})
	_night = night
	_budget = budget
	_spent = 0
	_error = ""
	_commands = []
	_checks = []
	var refs: Array = entity.rules.duplicate(true)
	refs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for ref in refs:
		_execute(Compiler.key(ref.id, ref.version), {}, 1)
		if not _error.is_empty():
			break
	return {"ok": _error.is_empty(), "error": _error, "commands": _commands if _error.is_empty() else [], "spent": _spent, "module": _module, "node": _node, "checks": _checks.duplicate(true)}

func _spend(module_key: String, node_id: String) -> bool:
	_module = module_key
	_node = node_id
	_spent += 1
	if _spent > _budget:
		_error = "instruction_budget"
	return _error.is_empty()

func _execute(module_key: String, overrides: Dictionary, depth: int) -> void:
	if not _error.is_empty():
		return
	if depth > Compiler.MAX_DEPTH or not _modules.has(module_key):
		_error = "call_depth_or_missing_module"
		return
	var m: Dictionary = _modules[module_key]
	var parameters: Dictionary = {}
	for name in m.parameters:
		parameters[name] = overrides.get(name, m.parameters[name].default)
	var cache: Dictionary = {}
	for id in m.effects:
		if not _spend(module_key, id):
			return
		var n: Dictionary = m.nodes[id]
		var when: Variant = _value(module_key, n.inputs.when, parameters, cache)
		if not _error.is_empty():
			return
		# 只保留有界条件求值证据；enabled表示形成计划，不代表已经提交。
		if _checks.size() < 64:
			_checks.append({"module":module_key,"node":id,"op":n.op,"enabled":bool(when)})
		if not when:
			continue
		var args: Dictionary = {}
		for port in n.inputs:
			if port != "when":
				args[port] = _value(module_key, n.inputs[port], parameters, cache)
		if not _error.is_empty():
			return
		match n.op:
			"set_light":
				_commands.append({"op": "set_light", "value": args.value})
			"move":
				_commands.append({"op": "move", "dx": n.config.dx, "dy": n.config.dy})
			"take_water":
				if args.source == "" or args.amount <= 0:
					_error = "missing_target_or_invalid_amount"
					return
				_commands.append({"op": "take_water", "source": args.source, "amount": args.amount})
			"take_environment_water":
				if not args.source is Vector2i or args.amount <= 0:
					_error = "missing_water_cell_or_invalid_amount"
					return
				_commands.append({"op":"take_environment_water","cell":args.source,"amount":args.amount})
			"release_environment_water":
				if args.amount <= 0:
					_error = "invalid_water_amount"
					return
				_commands.append({"op":"release_environment_water","dx":n.config.dx,"dy":n.config.dy,"amount":args.amount})
			"call":
				_execute(Compiler.key(n.config.id, n.config.version), args, depth + 1)
		if _commands.size() > 64:
			_error = "command_budget"
		if not _error.is_empty():
			return

func _value(module_key: String, id: String, parameters: Dictionary, cache: Dictionary) -> Variant:
	if not _error.is_empty():
		return null
	if cache.has(id):
		return cache[id]
	if not _spend(module_key, id):
		return null
	var n: Dictionary = _modules[module_key].nodes[id]
	var args: Dictionary = {}
	for port in n.inputs:
		args[port] = _value(module_key, n.inputs[port], parameters, cache)
	if not _error.is_empty():
		return null
	var value: Variant = null
	match n.op:
		"bool", "int":
			value = n.config.value
		"param":
			value = parameters[n.config.name]
		"is_night":
			value = _night
		"is_ambient_dark":
			value = _night or int(_roofs.get(int(_entity.location.cell[0]),1000001)) < int(_entity.location.cell[1])
		"neighbor_water":
			value = null
			var cell := Vector2i(_entity.location.cell[0],_entity.location.cell[1])
			for offset in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
				if int(_water.get(cell+offset,0)) > 0:
					value = cell+offset
					break
		"water_exists":
			value = args.source is Vector2i
		"water_units":
			value = int(_water.get(args.source,0)) if args.source is Vector2i else 0
		"read_state":
			value = _entity.state[n.config.field]
		"neighbor":
			value = ""
			var cell := Vector2i(_entity.location.cell[0], _entity.location.cell[1])
			# 固定相邻查询顺序，不依赖字典遍历、帧率或随机数。
			for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var other: String = _cells.get(cell + offset, "")
				if other != "" and (n.config.material == "" or _instances[other].material_id == n.config.material):
					value = other
					break
		"exists":
			value = args.value != ""
		"not":
			value = not args.value
		"and":
			value = args.a and args.b
		"lt":
			value = args.a < args.b
		"min":
			value = mini(args.a,args.b)
		"add", "sub":
			value = args.a + args.b if n.op == "add" else args.a - args.b
			if value < -Codec.MAX_QUANTITY or value > Codec.MAX_QUANTITY:
				_error = "arithmetic_range"
		_:
			_error = "non_value_node"
	cache[id] = value
	return value
