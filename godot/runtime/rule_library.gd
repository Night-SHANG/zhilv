extends RefCounted
## 只处理规则数据和依赖闭包；沿用现有编译器，不能由律卷扩大原语/材料权限。
const Codec = preload("res://runtime/snapshot_codec.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")

static func parse_bounded(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > Compiler.MAX_BYTES:
		return Codec.reject("rule_byte_budget")
	var lexical: String = Codec._lexical_error(text)
	if not lexical.is_empty():
		return Codec.reject(lexical)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return Codec.reject("invalid_rule_json")
	return {"ok":true,"error":"","value":parser.data}

static func compile_dynamic(raw: Variant, trusted_catalog: Dictionary) -> Dictionary:
	if not Codec._shape(raw,["format","modules"]) or raw.format != "rw.rules/0.1" or not raw.modules is Array or raw.modules.is_empty() or raw.modules.size() > Compiler.MAX_MODULES:
		return Codec.reject("rule_pack_fields_or_budget")
	var catalog: Dictionary = trusted_catalog.duplicate(true)
	if not catalog.get("rules") is Dictionary or not catalog.get("materials") is Dictionary:
		return Codec.reject("invalid_catalog")
	for m in raw.modules:
		if not m is Dictionary or not Codec.identifier(m.get("id")) or not Codec._integer(m.get("version"),1,2147483647):
			return Codec.reject("module_fields")
		var known: Variant = catalog.rules.get(m.id,[])
		if not known is Array:
			return Codec.reject("invalid_catalog")
		# 只允许玩家目录动态扩展；不能凭一份JSON获得受信命名空间。
		if not Codec.has_version(known,int(m.version)):
			if not m.id.begins_with("user:"):
				return Codec.reject("reserved_rule_namespace")
			if not catalog.rules.has(m.id): catalog.rules[m.id]=[]
			catalog.rules[m.id].append(int(m.version))
	var compiled: Dictionary = Compiler.compile_value(raw.duplicate(true),catalog)
	if not compiled.ok:
		return compiled
	compiled["catalog"] = catalog
	return compiled

static func merge_text(text: String, current: Dictionary, catalog: Dictionary) -> Dictionary:
	var parsed: Dictionary = parse_bounded(text)
	if not parsed.ok:
		return parsed
	var raw: Variant = parsed.value
	if not Codec._shape(raw,["format","modules"]) or raw.format != "rw.rules/0.1" or not raw.modules is Array or raw.modules.is_empty() or raw.modules.size()>Compiler.MAX_MODULES:
		return Codec.reject("rule_pack_fields_or_budget")
	var entries: Dictionary = {}
	if not current.is_empty():
		for m in current.source.modules: entries[Compiler.key(m.id,m.version)] = m.duplicate(true)
	var incoming: Dictionary = {}
	for m in raw.modules:
		if not m is Dictionary or not Codec.identifier(m.get("id")) or not Codec._integer(m.get("version"),1,2147483647):
			return Codec.reject("module_fields")
		var k: String = Compiler.key(m.id,int(m.version))
		if incoming.has(k):
			return Codec.reject("duplicate_import_module")
		incoming[k]=true
		entries[k]=m.duplicate(true)
	var combined: Dictionary = compile_dynamic({"format":"rw.rules/0.1","modules":entries.values()},catalog)
	if not combined.ok:
		return combined
	if not current.is_empty():
		for k in incoming:
			if current.modules.has(k) and current.modules[k].canonical != combined.modules[k].canonical:
				return Codec.reject("version_content_conflict")
	combined["added"] = entries.size() - (0 if current.is_empty() else current.modules.size())
	return combined

static func closure(program: Dictionary, id: String, version: int) -> Dictionary:
	var entry: String = Compiler.key(id,version)
	if program.is_empty() or not program.modules.has(entry):
		return Codec.reject("missing_scroll_entry")
	var found: Dictionary = {}
	var pending: Array = [entry]
	while not pending.is_empty():
		var k: String=pending.pop_back()
		if found.has(k): continue
		found[k]=true
		for dep in program.modules[k].dependencies: pending.append(dep)
	var modules: Array=[]
	# 编译器的规范顺序不依赖用户添加节点/模块时的顺序。
	for m in program.source.modules:
		if found.has(Compiler.key(m.id,m.version)): modules.append(m.duplicate(true))
	return {"ok":true,"error":"","pack":{"format":"rw.rules/0.1","modules":modules}}

static func export_scroll(program: Dictionary, id: String, version: Variant) -> Dictionary:
	if not Codec.identifier(id) or typeof(version)!=TYPE_INT or version<1 or version>2147483647:
		return Codec.reject("invalid_rule_reference")
	var result: Dictionary=closure(program,id,version)
	if not result.ok: return result
	var text: String=JSON.stringify({"format":"rw.scroll/0.1","entry":{"id":id,"version":version},"rules":result.pack})
	if text.to_utf8_buffer().size()>Compiler.MAX_BYTES: return Codec.reject("scroll_byte_budget")
	return {"ok":true,"error":"","text":text,"modules":result.pack.modules.size()}

static func read_scroll(text: String, catalog: Dictionary) -> Dictionary:
	var parsed: Dictionary=parse_bounded(text)
	if not parsed.ok: return parsed
	var raw: Variant=parsed.value
	if not Codec._shape(raw,["format","entry","rules"]) or raw.format!="rw.scroll/0.1" or not Codec._shape(raw.entry,["id","version"]) or not Codec.identifier(raw.entry.id) or not Codec._integer(raw.entry.version,1,2147483647):
		return Codec.reject("scroll_fields")
	# 单独编译，不能借目标世界已有依赖掩盖损坏/不完整的律卷。
	var program: Dictionary=compile_dynamic(raw.rules,catalog)
	if not program.ok: return program
	var needed: Dictionary=closure(program,raw.entry.id,int(raw.entry.version))
	if not needed.ok: return needed
	if needed.pack.modules.size()!=program.modules.size(): return Codec.reject("unrelated_scroll_modules")
	return {"ok":true,"error":"","text":JSON.stringify(program.source),"entry":{"id":raw.entry.id,"version":int(raw.entry.version)}}
