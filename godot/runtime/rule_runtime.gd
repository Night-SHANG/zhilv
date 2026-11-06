extends RefCounted
## 受限规则调度与完整模拟检查点；不运行任意GDScript，不依赖在线AI。
const Codec = preload("res://runtime/snapshot_codec.gd")
const WorldCodec = preload("res://runtime/world_codec.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")
const Evaluator = preload("res://runtime/rule_evaluator.gd")
const Library = preload("res://runtime/rule_library.gd")
var _catalog: Dictionary
var _trusted_catalog: Dictionary
var _world
var _program: Dictionary = {}
var _tick: int = 0
var _busy: bool = false

func _init(catalog: Dictionary, world) -> void:
	_catalog = catalog.duplicate(true)
	_trusted_catalog = catalog.duplicate(true)
	_world = world

func _references(program: Dictionary, snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return {"ok": true, "error": ""}
	for entity in snapshot.entities.instances:
		for ref in entity.rules:
			if not program.modules.has(Compiler.key(ref.id, ref.version)):
				return Codec.reject("missing_bound_rule_version")
	return {"ok": true, "error": ""}

func install_pack(text: String) -> Dictionary:
	if _busy:
		return Codec.reject("runtime_busy")
	var candidate: Dictionary = Compiler.compile_text(text, _catalog)
	if not candidate.ok:
		return candidate
	var refs: Dictionary = _references(candidate, _world.rule_view())
	if not refs.ok:
		return refs
	if not _program.is_empty():
		# 旧的整包入口也不能通过先移除版本、再换内容绕过不可变约束。
		for k in _program.modules:
			if not candidate.modules.has(k):
				return Codec.reject("installed_module_removal")
		for k in candidate.modules:
			if _program.modules.has(k) and _program.modules[k].canonical != candidate.modules[k].canonical:
				return Codec.reject("version_content_conflict")
	_program = candidate
	return {"ok": true, "error": ""}

func pack_json() -> String:
	return "{}" if _program.is_empty() else JSON.stringify(_program.source)

func advance(night: Variant, per_instance_budget: Variant = 512, total_budget: Variant = 32768) -> Dictionary:
	if _busy:
		return Codec.reject("runtime_busy")
	if typeof(night) != TYPE_BOOL or typeof(per_instance_budget) != TYPE_INT or per_instance_budget < 1 or per_instance_budget > 4096 or typeof(total_budget) != TYPE_INT or total_budget < 1 or total_budget > 65536:
		return Codec.reject("invalid_context_or_budget")
	if _program.is_empty() or _world.rule_view().is_empty():
		return Codec.reject("runtime_not_ready")
	if _tick >= Codec.MAX_QUANTITY:
		return Codec.reject("tick_limit")
	_busy = true
	var result: Dictionary = _advance(night, per_instance_budget, total_budget)
	_busy = false
	return result

func _advance(night: bool, per_instance_budget: int, total_budget: int) -> Dictionary:
	var snapshot: Dictionary = _world.rule_view()
	var refs: Dictionary = _references(_program, snapshot)
	if not refs.ok:
		return refs
	var view: Dictionary = {"instances": {}, "cells": {}}
	var active: Array = []
	for entity in snapshot.entities.instances:
		view.instances[entity.id] = entity
		if entity.location.kind == "world":
			view.cells[Vector2i(entity.location.cell[0], entity.location.cell[1])] = entity.id
			if not entity.rules.is_empty():
				active.append(entity)
	if active.size() > 256:
		return Codec.reject("active_instance_budget")
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var plans: Array = []
	var errors: Array = []
	var spent: int = 0
	# 全部读取同一步快照；总预算不足时，任何造物都尚未提交。
	for entity in active:
		var evaluation: Dictionary = Evaluator.new().run(_program, entity, view, night, per_instance_budget)
		spent += evaluation.spent
		if spent > total_budget:
			return Codec.reject("total_instruction_budget")
		if not evaluation.ok:
			errors.append({"id": entity.id, "error": evaluation.error, "module": evaluation.module, "node": evaluation.node})
		else:
			plans.append({"id": entity.id, "commands": evaluation.commands})
	var committed: int = 0
	for plan in plans:
		if plan.commands.is_empty():
			continue
		var result: Dictionary = _world.apply_rule_commands(plan.id, plan.commands)
		if result.ok:
			committed += 1
		else:
			errors.append({"id": plan.id, "error": result.error})
	_tick += 1
	return {"ok": true, "error": "", "tick": _tick, "instructions": spent, "committed": committed, "errors": errors}

func checkpoint_json() -> String:
	if _program.is_empty() or _world.rule_view().is_empty():
		return "{}"
	return JSON.stringify({"format": "rw.simulation/0.1", "tick": _tick, "world": _world.rule_view(), "rules": _program.source})

func validate_checkpoint(text: String) -> Dictionary:
	var lexical: String = Codec._lexical_error(text)
	if not lexical.is_empty():
		return Codec.reject(lexical)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return Codec.reject("invalid_simulation_json")
	var d: Variant = parser.data
	if not Codec._shape(d, ["format", "tick", "world", "rules"]) or d.format != "rw.simulation/0.1" or not Codec._integer(d.tick, 0, Codec.MAX_QUANTITY):
		return Codec.reject("simulation_fields")
	var program: Dictionary = Library.compile_dynamic(d.rules, _trusted_catalog)
	if not program.ok:
		return program
	var world: Dictionary = WorldCodec.decode_value(d.world, program.catalog)
	if not world.ok:
		return world
	var refs: Dictionary = _references(program, world.snapshot)
	if not refs.ok:
		return refs
	return {"ok": true, "error": "", "program": program, "world": world.snapshot, "tick": int(d.tick)}

func load_checkpoint(text: String) -> Dictionary:
	if _busy:
		return Codec.reject("runtime_busy")
	var candidate: Dictionary = validate_checkpoint(text)
	if not candidate.ok:
		return candidate
	var prepared: Dictionary = _world._prepare_rule_revision(candidate.program.catalog.rules, candidate.world)
	if not prepared.ok:
		return prepared
	return _adopt_revision(candidate.program, prepared, candidate.tick)

func _prepare_publish(text: String, bindings: Dictionary) -> Dictionary:
	if _busy:
		return Codec.reject("runtime_busy")
	if bindings.size() > 64:
		return Codec.reject("binding_batch_budget")
	var program: Dictionary = Library.merge_text(text, _program, _catalog)
	if not program.ok:
		return program
	return _prepare_bindings(program, bindings)

func _prepare_bindings(program: Dictionary, bindings: Dictionary) -> Dictionary:
	var snapshot: Dictionary = _world.rule_view()
	if snapshot.is_empty():
		return Codec.reject("world_not_loaded")
	for id in bindings:
		if not Codec.identifier(id) or not bindings[id] is Array:
			return Codec.reject("invalid_binding")
		var access: Dictionary = _world._accessible_instance(id)
		if not access.ok:
			return access
		for entity in snapshot.entities.instances:
			if entity.id == id: entity.rules = bindings[id].duplicate(true)
	var prepared: Dictionary = _world._prepare_rule_revision(program.catalog.rules, snapshot)
	if not prepared.ok:
		return prepared
	var refs: Dictionary = _references(program, prepared.snapshot)
	if not refs.ok:
		return refs
	return {"ok":true,"error":"","program":program,"prepared":prepared}

func _adopt_revision(program: Dictionary, prepared: Dictionary, tick: int) -> Dictionary:
	_busy = true
	_world._adopt_rule_revision(prepared)
	_catalog = prepared.catalog.duplicate(true)
	_program = program
	_tick = tick
	_world.reloaded.emit()
	_busy = false
	return {"ok":true,"error":""}

func preview_pack(text: String, bindings: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _prepare_publish(text,bindings)
	if not candidate.ok:
		return candidate
	# 不泄露可修改的已编译程序/世界引用。
	return {"ok":true,"error":"","added":candidate.program.added,"modules":candidate.program.modules.size(),"bindings":bindings.size()}

func publish_pack(text: String, bindings: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _prepare_publish(text,bindings)
	if not candidate.ok:
		return candidate
	return _adopt_revision(candidate.program,candidate.prepared,_tick)

func bind_rules(id: String, refs: Array) -> Dictionary:
	if _busy:
		return Codec.reject("runtime_busy")
	if _program.is_empty():
		return Codec.reject("runtime_not_ready")
	var program: Dictionary = _program.duplicate(true)
	program["catalog"] = _catalog.duplicate(true)
	var candidate: Dictionary = _prepare_bindings(program,{id:refs})
	if not candidate.ok:
		return candidate
	return _adopt_revision(candidate.program,candidate.prepared,_tick)

func export_rule(id: String, version: Variant) -> Dictionary:
	return Library.export_scroll(_program,id,version)

func import_scroll(text: String) -> Dictionary:
	if _busy:
		return Codec.reject("runtime_busy")
	var parsed: Dictionary=Library.read_scroll(text,_catalog)
	if not parsed.ok:
		return parsed
	var result: Dictionary=publish_pack(parsed.text)
	if result.ok: result["entry"] = parsed.entry.duplicate(true)
	return result

func rule_definition(id: String, version: Variant) -> Dictionary:
	if typeof(version)!=TYPE_INT or version<1 or version>2147483647 or not Codec.identifier(id):
		return Codec.reject("invalid_rule_reference")
	if not _program.is_empty():
		for m in _program.source.modules:
			if m.id==id and m.version==version:
				return {"ok":true,"error":"","module":m.duplicate(true)}
	return Codec.reject("missing_rule_version")

func next_rule_version(id: String) -> Dictionary:
	if not Codec.identifier(id) or not id.begins_with("user:"):
		return Codec.reject("reserved_rule_namespace")
	var maximum: int=0
	for version in _catalog.rules.get(id,[]):
		if Codec._integer(version,1,2147483647): maximum=maxi(maximum,int(version))
	if maximum==2147483647:
		return Codec.reject("rule_version_limit")
	return {"ok":true,"error":"","version":maximum+1}
