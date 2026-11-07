extends RefCounted
## 显示层的草稿模型。模板只是可拆改的便捷组装；发布仍由同一个运行时验证。
signal changed
const Draft = preload("res://runtime/rule_draft.gd")
const Codec = preload("res://runtime/snapshot_codec.gd")
var draft = Draft.new()
var _undo: Array=[]
var _redo: Array=[]
var dirty: bool=false
var _counter: int=0

func start(id: String) -> Dictionary:
	var result: Dictionary=draft.start(id,1)
	if result.ok: _undo.clear(); _redo.clear(); dirty=false; changed.emit()
	return result

func snapshot() -> Dictionary: return draft.snapshot()
func node(id: String) -> Dictionary:
	for n in snapshot().get("nodes",[]):
		if n.id==id: return n
	return {}
func _remember(before: Dictionary) -> void:
	_undo.append(before)
	if _undo.size()>64: _undo.pop_front()
	_redo.clear(); dirty=true; changed.emit()
func _finish(before: Dictionary,result: Dictionary) -> Dictionary:
	if result.ok: _remember(before)
	return result
func add(op: String, config: Dictionary={}) -> Dictionary:
	var before: Dictionary=snapshot()
	if before.is_empty(): return Codec.reject("draft_not_started")
	_counter+=1
	var id: String="node_"+str(_counter)
	while not node(id).is_empty(): _counter+=1; id="node_"+str(_counter)
	var result: Dictionary=draft.upsert_node({"id":id,"op":op,"config":config.duplicate(true),"inputs":{}})
	if result.ok:
		if op in ["set_light","move","take_water","take_environment_water","release_environment_water","call"]:
			var effects: Array=snapshot().effects; effects.append(id)
			result=draft.set_effects(effects)
		if not result.ok: draft.restore(before)
		else: result["id"]=id
	return _finish(before,result)
func change_config(id: String, config: Dictionary) -> Dictionary:
	var before: Dictionary=snapshot(); var n: Dictionary=node(id)
	if n.is_empty(): return Codec.reject("missing_draft_node")
	n.config=config.duplicate(true)
	return _finish(before,draft.upsert_node(n))
func connect_nodes(target: String,port: String,source: String) -> Dictionary:
	var before: Dictionary=snapshot()
	return _finish(before,draft.connect_input(target,port,source))
func disconnect_port(target: String,port: String) -> Dictionary:
	var before: Dictionary=snapshot()
	return _finish(before,draft.disconnect_input(target,port))
func remove(id: String) -> Dictionary:
	var before: Dictionary=snapshot()
	return _finish(before,draft.remove_node(id))
func undo() -> Dictionary:
	if _undo.is_empty(): return Codec.reject("undo_empty")
	var old: Dictionary=_undo.back(); var current: Dictionary=snapshot()
	var result: Dictionary=draft.restore(old)
	if result.ok: _undo.pop_back(); _redo.append(current); dirty=true; changed.emit()
	return result
func redo() -> Dictionary:
	if _redo.is_empty(): return Codec.reject("redo_empty")
	var old: Dictionary=_redo.back(); var current: Dictionary=snapshot()
	var result: Dictionary=draft.restore(old)
	if result.ok: _redo.pop_back(); _undo.append(current); dirty=true; changed.emit()
	return result
func load_module(m: Dictionary, id: String) -> Dictionary:
	var candidate: Dictionary=m.duplicate(true); candidate.id=id; candidate.version=1
	var result: Dictionary=draft.restore(candidate)
	if result.ok: _undo.clear(); _redo.clear(); dirty=false; changed.emit()
	return result
func _n(id: String,op: String,inputs: Dictionary={},config: Dictionary={}) -> Dictionary:
	return {"id":id,"op":op,"inputs":inputs,"config":config}
func preset(kind: String, rate: int=100) -> Dictionary:
	var before: Dictionary=snapshot()
	if before.is_empty() or rate<1 or rate>1000: return Codec.reject("preset_invalid")
	var nodes: Array=[]; var effects: Array=[]
	match kind:
		"pump":
			nodes=[_n("source","neighbor_water"),_n("available","water_units",{"source":"source"}),_n("water","read_state",{},{"field":"water_units"}),_n("capacity","read_state",{},{"field":"capacity_units"}),_n("room","sub",{"a":"capacity","b":"water"}),_n("rate","int",{},{"value":rate}),_n("limited","min",{"a":"rate","b":"available"}),_n("amount","min",{"a":"limited","b":"room"}),_n("zero","int",{},{"value":0}),_n("can_take","lt",{"a":"zero","b":"amount"}),_n("take","take_environment_water",{"when":"can_take","source":"source","amount":"amount"})]
			effects=["take"]
		"lamp":
			nodes=[_n("always","bool",{},{"value":true}),_n("dark","is_ambient_dark"),_n("light","set_light",{"when":"always","value":"dark"})]; effects=["light"]
		"release":
			nodes=[_n("rate","int",{},{"value":rate}),_n("water","read_state",{},{"field":"water_units"}),_n("amount","min",{"a":"rate","b":"water"}),_n("zero","int",{},{"value":0}),_n("ready","lt",{"a":"zero","b":"amount"}),_n("release","release_environment_water",{"when":"ready","amount":"amount"},{"dx":1,"dy":0})]; effects=["release"]
		"blank": pass
		_: return Codec.reject("unknown_preset")
	var candidate: Dictionary={"id":before.id,"version":before.version,"parameters":{},"nodes":nodes,"effects":effects}
	return _finish(before,draft.restore(candidate))
func candidate(runtime) -> Dictionary:
	var module: Dictionary=snapshot()
	if module.is_empty(): return Codec.reject("draft_not_started")
	var version: Dictionary=runtime.next_rule_version(module.id)
	if not version.ok: return version
	module.version=version.version
	return {"ok":true,"error":"","module":module,"text":JSON.stringify({"format":"rw.rules/0.1","modules":[module]})}
func validate(runtime) -> Dictionary:
	var c: Dictionary=candidate(runtime)
	return c if not c.ok else runtime.preview_pack(c.text)
func mark_saved() -> void:
	dirty=false; changed.emit()
