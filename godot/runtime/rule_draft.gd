extends RefCounted
## 织律台的非视觉编辑模型。允许中间态缺线；只有运行时完整编译后才能发布。
const Codec = preload("res://runtime/snapshot_codec.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")
var _module: Dictionary = {}

func start(id: String, version: Variant) -> Dictionary:
	if not Codec.identifier(id) or not id.begins_with("user:") or typeof(version)!=TYPE_INT or version<1 or version>2147483647:
		return Codec.reject("draft_identity")
	_module={"id":id,"version":version,"parameters":{},"nodes":[],"effects":[]}
	return {"ok":true,"error":""}

static func _plain(value: Variant) -> bool:
	return _plain_visit(value, 0, [1024])

static func _plain_visit(value: Variant, depth: int, budget: Array) -> bool:
	# 只收有界JSON数据；原生编辑入口不做float/对象/Callable的静默转换。
	budget[0] -= 1
	if depth>10 or budget[0]<0: return false
	match typeof(value):
		TYPE_BOOL, TYPE_INT: return true
		TYPE_STRING: return value.length()<=256
		TYPE_ARRAY:
			if value.size()>Compiler.MAX_NODES: return false
			for item in value:
				if not _plain_visit(item,depth+1,budget): return false
			return true
		TYPE_DICTIONARY:
			if value.size()>Compiler.MAX_NODES: return false
			for key in value:
				if not key is String or key.length()>256 or not _plain_visit(value[key],depth+1,budget): return false
			return true
	return false

func restore(value: Variant) -> Dictionary:
	if not _plain(value) or not Codec._shape(value,["id","version","parameters","nodes","effects"]) or not value.id is String or not value.nodes is Array or not value.parameters is Dictionary or not value.effects is Array:
		return Codec.reject("draft_fields")
	# 用独立草稿完成全部结构检查，失败不覆盖现有编辑内容。
	var staged= get_script().new()
	var result: Dictionary=staged.start(value.id,value.version)
	if not result.ok: return result
	for key in value.parameters:
		var p: Variant=value.parameters[key]
		if not Codec._shape(p,["type","default"]) or not p.type is String: return Codec.reject("parameter_fields")
		result=staged.set_parameter(key,p.type,p.default)
		if not result.ok: return result
	var ids: Dictionary={}
	for n in value.nodes:
		if not n is Dictionary or not n.get("id") is String or ids.has(n.id): return Codec.reject("duplicate_or_invalid_node")
		ids[n.id]=true
		result=staged.upsert_node(n)
		if not result.ok: return result
	result=staged.set_effects(value.effects)
	if not result.ok: return result
	_module=staged.snapshot()
	return {"ok":true,"error":""}

func snapshot() -> Dictionary:
	return _module.duplicate(true)

func pack_json() -> String:
	return JSON.stringify({"format":"rw.rules/0.1","modules":[] if _module.is_empty() else [_module]})

func _node_index(id: String) -> int:
	if _module.is_empty(): return -1
	for i in _module.nodes.size():
		if _module.nodes[i].id==id: return i
	return -1

func upsert_node(value: Variant) -> Dictionary:
	if _module.is_empty(): return Codec.reject("draft_not_started")
	if not _plain(value) or not Codec._shape(value,["id","op","inputs","config"]) or not Compiler.local_id(value.id) or not value.op is String or not value.inputs is Dictionary or not value.config is Dictionary:
		return Codec.reject("draft_node_fields")
	for port in value.inputs:
		if not Compiler.local_id(port) or not Compiler.local_id(value.inputs[port]): return Codec.reject("draft_port_fields")
	var index: int=_node_index(value.id)
	if index<0 and _module.nodes.size()>=Compiler.MAX_NODES: return Codec.reject("node_budget")
	if index<0: _module.nodes.append(value.duplicate(true))
	else: _module.nodes[index]=value.duplicate(true)
	return {"ok":true,"error":""}

func connect_input(target: String, port: String, source: String) -> Dictionary:
	var index: int=_node_index(target)
	if index<0 or _node_index(source)<0 or not Compiler.local_id(port): return Codec.reject("draft_connection_target")
	_module.nodes[index].inputs[port]=source
	return {"ok":true,"error":""}

func disconnect_input(target: String, port: String) -> Dictionary:
	var index: int=_node_index(target)
	if index<0 or not _module.nodes[index].inputs.has(port): return Codec.reject("missing_draft_connection")
	_module.nodes[index].inputs.erase(port)
	return {"ok":true,"error":""}

func remove_node(id: String) -> Dictionary:
	var index: int=_node_index(id)
	if index<0: return Codec.reject("missing_draft_node")
	for n in _module.nodes:
		if n.id!=id and n.inputs.values().has(id): return Codec.reject("referenced_draft_node")
	_module.nodes.remove_at(index)
	_module.effects.erase(id)
	return {"ok":true,"error":""}

func set_parameter(name: String, type: String, value: Variant) -> Dictionary:
	if _module.is_empty(): return Codec.reject("draft_not_started")
	if not Compiler.local_id(name) or name=="when": return Codec.reject("parameter_name")
	if not _module.parameters.has(name) and _module.parameters.size()>=8: return Codec.reject("parameter_budget")
	if (type=="bool" and typeof(value)==TYPE_BOOL) or (type=="int" and typeof(value)==TYPE_INT and value>=-Codec.MAX_QUANTITY and value<=Codec.MAX_QUANTITY):
		_module.parameters[name]={"type":type,"default":value}
		return {"ok":true,"error":""}
	return Codec.reject("parameter_type")

func set_effects(ids: Array) -> Dictionary:
	if _module.is_empty(): return Codec.reject("draft_not_started")
	if ids.size()>16: return Codec.reject("effect_budget")
	var seen: Dictionary={}
	for id in ids:
		if not id is String or _node_index(id)<0 or seen.has(id): return Codec.reject("invalid_draft_effect")
		seen[id]=true
	_module.effects=ids.duplicate()
	return {"ok":true,"error":""}
