extends RefCounted
## 有类型、无任意脚本入口的规则图协议。编译只校验数据，不执行世界动作。
const Codec = preload("res://runtime/snapshot_codec.gd")
const MAX_BYTES: int = 262144
const MAX_MODULES: int = 64
const MAX_NODES: int = 64
const MAX_DEPTH: int = 8
const EFFECTS: Array = ["set_light", "move", "take_water", "take_environment_water", "release_environment_water", "form_material", "recover_material", "call"]

static func key(id: String, version: int) -> String:
	return id + "@" + str(version)

static func local_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 32:
		return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true

static func compile_text(text: String, catalog: Dictionary) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return Codec.reject("rule_byte_budget")
	var lexical: String = Codec._lexical_error(text)
	if not lexical.is_empty():
		return Codec.reject(lexical)
	var json := JSON.new()
	if json.parse(text) != OK:
		return Codec.reject("invalid_rule_json")
	return compile_value(json.data, catalog)

static func compile_value(raw: Variant, catalog: Dictionary) -> Dictionary:
	if not catalog.get("rules") is Dictionary or not catalog.get("materials") is Dictionary:
		return Codec.reject("invalid_catalog")
	if not Codec._shape(raw, ["format", "modules"]) or raw.format != "rw.rules/0.1":
		return Codec.reject("rule_pack_fields")
	if not raw.modules is Array or raw.modules.is_empty() or raw.modules.size() > MAX_MODULES:
		return Codec.reject("module_budget")
	var modules: Dictionary = {}
	for item in raw.modules:
		if not Codec._shape(item, ["id", "version", "parameters", "nodes", "effects"]) or not Codec.identifier(item.id) or not Codec._integer(item.version, 1, 2147483647):
			return Codec.reject("module_fields")
		var k: String = key(item.id, int(item.version))
		var versions: Variant = catalog.rules.get(item.id)
		if modules.has(k) or not versions is Array or not Codec.has_version(versions, int(item.version)):
			return Codec.reject("duplicate_or_unregistered_module")
		if not item.parameters is Dictionary or item.parameters.size() > 8 or not item.nodes is Array or item.nodes.is_empty() or item.nodes.size() > MAX_NODES or not item.effects is Array or item.effects.size() > 16:
			return Codec.reject("module_collection_budget")
		var params: Dictionary = {}
		for name in item.parameters:
			var p: Variant = item.parameters[name]
			if not local_id(name) or name == "when" or not Codec._shape(p, ["type", "default"]):
				return Codec.reject("parameter_fields")
			if p.type == "int" and Codec._integer(p.default, -Codec.MAX_QUANTITY, Codec.MAX_QUANTITY):
				params[name] = {"type": "int", "default": int(p.default)}
			elif p.type == "bool" and typeof(p.default) == TYPE_BOOL:
				params[name] = {"type": "bool", "default": p.default}
			else:
				return Codec.reject("parameter_type")
		var nodes: Dictionary = {}
		for n in item.nodes:
			if not Codec._shape(n, ["id", "op", "inputs", "config"]) or not local_id(n.id) or nodes.has(n.id) or not n.op is String or not n.inputs is Dictionary or not n.config is Dictionary:
				return Codec.reject("node_fields_or_duplicate")
			nodes[n.id] = n.duplicate(true)
		modules[k] = {"id": item.id, "version": int(item.version), "parameters": params, "nodes": nodes, "effects": item.effects.duplicate(), "dependencies": []}
	# 先建立所有签名，允许节点/模块以任意顺序保存。
	for k in modules:
		var m: Dictionary = modules[k]
		for id in m.nodes:
			var n: Dictionary = m.nodes[id]
			var sig: Dictionary = signature(n, m, modules, catalog)
			if not sig.ok:
				return {"ok": false, "error": sig.error, "module": k, "node": id}
			n.output = sig.output
			n.expected = sig.inputs
			if n.op == "call":
				m.dependencies.append(key(n.config.id, n.config.version))
			for port in n.inputs:
				if not sig.inputs.has(port) or not local_id(n.inputs[port]):
					return Codec.reject("unknown_port_or_invalid_reference")
			for port in sig.inputs:
				if not n.inputs.has(port) and (n.op != "call" or port == "when"):
					return Codec.reject("missing_input_port")
		for id in m.nodes:
			var n: Dictionary = m.nodes[id]
			for port in n.inputs:
				var source: Variant = m.nodes.get(n.inputs[port])
				if not source is Dictionary or source.output != n.expected[port]:
					return Codec.reject("missing_reference_or_type_mismatch")
		var seen_effects: Dictionary = {}
		for id in m.effects:
			if not id is String or not m.nodes.has(id) or m.nodes[id].output != "effect" or seen_effects.has(id):
				return Codec.reject("invalid_effect_entry")
			seen_effects[id] = true
		for id in m.nodes:
			if m.nodes[id].output == "effect" and not seen_effects.has(id):
				return Codec.reject("unlisted_effect")
		var resolved: Dictionary = {}
		while resolved.size() < m.nodes.size():
			var progressed: bool = false
			for id in m.nodes:
				if resolved.has(id):
					continue
				var ready: bool = true
				for ref in m.nodes[id].inputs.values():
					if not resolved.has(ref):
						ready = false
				if ready:
					resolved[id] = true
					progressed = true
			if not progressed:
				return Codec.reject("data_cycle")
	# 行为调用也是DAG；计算最长调用链，而不只检查直接递归。
	var depths: Dictionary = {}
	while depths.size() < modules.size():
		var progressed: bool = false
		for k in modules:
			if depths.has(k):
				continue
			var depth: int = 1
			var ready: bool = true
			for dep in modules[k].dependencies:
				if not depths.has(dep):
					ready = false
				else:
					depth = maxi(depth, int(depths[dep]) + 1)
			if ready:
				if depth > MAX_DEPTH:
					return Codec.reject("call_depth_budget")
				depths[k] = depth
				progressed = true
		if not progressed:
			return Codec.reject("recursive_call")
	var canonical: Dictionary = {"format": "rw.rules/0.1", "modules": []}
	var keys: Array = modules.keys()
	keys.sort()
	for k in keys:
		var m: Dictionary = modules[k]
		var source: Dictionary = {"id": m.id, "version": m.version, "parameters": m.parameters.duplicate(true), "nodes": [], "effects": m.effects.duplicate()}
		var ids: Array = m.nodes.keys()
		ids.sort()
		for id in ids:
			var n: Dictionary = m.nodes[id]
			source.nodes.append({"id": n.id, "op": n.op, "inputs": n.inputs.duplicate(), "config": n.config.duplicate(true)})
		m.canonical = JSON.stringify(source)
		canonical.modules.append(source)
	if JSON.stringify(canonical).to_utf8_buffer().size() > MAX_BYTES:
		return Codec.reject("rule_byte_budget")
	return {"ok": true, "error": "", "modules": modules, "source": canonical}

static func signature(n: Dictionary, m: Dictionary, modules: Dictionary, catalog: Dictionary) -> Dictionary:
	var c: Dictionary = n.config
	var output: String = ""
	var inputs: Dictionary = {}
	match n.op:
		"bool", "int":
			if not Codec._shape(c, ["value"]):
				return Codec.reject("constant_fields")
			if n.op == "bool" and typeof(c.value) != TYPE_BOOL:
				return Codec.reject("constant_type")
			if n.op == "int":
				if not Codec._integer(c.value, -Codec.MAX_QUANTITY, Codec.MAX_QUANTITY):
					return Codec.reject("constant_range")
				c.value = int(c.value)
			output = n.op
		"param":
			if not Codec._shape(c, ["name"]) or not c.name is String or not m.parameters.has(c.name):
				return Codec.reject("unknown_parameter")
			output = m.parameters[c.name].type
		"read_state":
			if not Codec._shape(c, ["field"]) or not c.field in ["water_units", "capacity_units", "light_on"]:
				return Codec.reject("unknown_state_field")
			output = "bool" if c.field == "light_on" else "int"
		"neighbor":
			if not Codec._shape(c, ["material"]) or not c.material is String or (c.material != "" and not catalog.materials.has(c.material)):
				return Codec.reject("unknown_neighbor_material")
			output = "ref"
		"cell_empty", "terrain_is", "form_material", "recover_material":
			var fields: Array = ["dx","dy"]
			if n.op != "cell_empty": fields.append("material")
			if not Codec._shape(c,fields) or not Codec._integer(c.dx,-1,1) or not Codec._integer(c.dy,-1,1) or absi(int(c.dx))+absi(int(c.dy))!=1: return Codec.reject("invalid_material_direction")
			c.dx=int(c.dx); c.dy=int(c.dy)
			if n.op != "cell_empty":
				if not Codec.identifier(c.material) or not catalog.materials.has(c.material): return Codec.reject("unknown_terrain_material")
				var material: Variant = catalog.materials[c.material]
				if not material is Dictionary or material.get("stackable")!=true: return Codec.reject("invalid_terrain_material")
				if n.op in ["form_material","recover_material"] and Codec.bound_water_cost(material)<=0: return Codec.reject("material_not_formable")
			output="bool" if n.op in ["cell_empty","terrain_is"] else "effect"
			if output=="effect": inputs={"when":"bool"}
		"move", "release_environment_water":
			if not Codec._shape(c, ["dx", "dy"]) or not Codec._integer(c.dx, -1, 1) or not Codec._integer(c.dy, -1, 1) or absi(int(c.dx)) + absi(int(c.dy)) != 1:
				return Codec.reject("invalid_move_step")
			c.dx = int(c.dx)
			c.dy = int(c.dy)
			inputs = {"when": "bool"}
			if n.op == "release_environment_water": inputs["amount"] = "int"
			output = "effect"
		"call":
			if not Codec._shape(c, ["id", "version"]) or not Codec.identifier(c.id) or not Codec._integer(c.version, 1, 2147483647):
				return Codec.reject("call_fields")
			c.version = int(c.version)
			var target: String = key(c.id, c.version)
			if not modules.has(target):
				return Codec.reject("missing_call_version")
			inputs = {"when": "bool"}
			for name in modules[target].parameters:
				inputs[name] = modules[target].parameters[name].type
			output = "effect"
		_:
			if not c.is_empty():
				return Codec.reject("unexpected_node_config")
			match n.op:
				"is_night", "is_ambient_dark":
					output = "bool"
				"exists":
					output = "bool"
					inputs = {"value": "ref"}
				"not":
					output = "bool"
					inputs = {"value": "bool"}
				"and":
					output = "bool"
					inputs = {"a": "bool", "b": "bool"}
				"lt", "add", "sub", "min":
					output = "bool" if n.op == "lt" else "int"
					inputs = {"a": "int", "b": "int"}
				"set_light":
					output = "effect"
					inputs = {"when": "bool", "value": "bool"}
				"neighbor_water":
					output = "cell_ref"
				"water_exists", "water_units":
					output = "bool" if n.op == "water_exists" else "int"
					inputs = {"source":"cell_ref"}
				"take_environment_water":
					output = "effect"
					inputs = {"when":"bool","source":"cell_ref","amount":"int"}
				"take_water":
					output = "effect"
					inputs = {"when": "bool", "source": "ref", "amount": "int"}
				_:
					return Codec.reject("unknown_primitive")
	return {"ok": true, "output": output, "inputs": inputs}
