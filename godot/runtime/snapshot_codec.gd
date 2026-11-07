extends RefCounted
## rw.instances/0.1 的原生校验器。只支持已定义的储水实例切片，不是通用脚本沙箱。
const MAX_BYTES: int = 1048576
const MAX_QUANTITY: int = 1000000000

static func reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

static func _shape(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func identifier(value: Variant) -> bool:
	if not value is String:
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_.-]*:[A-Za-z0-9_.-]{1,64}\\z")
	return regex.search(value) != null

static func has_version(versions: Array, version: int) -> bool:
	# Array.has按Variant类型比较；JSON版本是float，原生注册版本是int。
	for candidate in versions:
		if _integer(candidate, 1, 2147483647) and int(candidate) == version:
			return true
	return false

static func _integer(value: Variant, lo: int, hi: int) -> bool:
	# Godot JSON 将数字解码为 float；词法层先拒绝小数/指数，随后检查数值范围。
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and value >= lo and value <= hi and floor(float(value)) == float(value)

static func _lexical_error(text: String) -> String:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return "byte_budget"
	var frames: Array = []
	var i: int = 0
	var previous: String = ""
	var integer_token := RegEx.new()
	integer_token.compile("^-?(0|[1-9][0-9]*)$")
	while i < text.length():
		var c: String = text.substr(i, 1)
		if c in [" ", "\t", "\r", "\n"]:
			i += 1
			continue
		if c == '"':
			var start: int = i
			i += 1
			var escaped: bool = false
			var closed: bool = false
			while i < text.length():
				var ch: String = text.substr(i, 1)
				if ch.unicode_at(0) < 32:
					return "string_control_character"
				if escaped:
					escaped = false
				elif ch == "\\":
					escaped = true
				elif ch == '"':
					closed = true
					i += 1
					break
				i += 1
			if not closed:
				return "unterminated_string"
			var next: int = i
			while next < text.length() and text.substr(next, 1) in [" ", "\t", "\r", "\n"]:
				next += 1
			if next < text.length() and text.substr(next, 1) == ":":
				if frames.is_empty() or not frames[-1]["object"]:
					return "key_outside_object"
				var key_parser := JSON.new()
				if key_parser.parse(text.substr(start, i - start)) != OK:
					return "invalid_key"
				var key: Variant = key_parser.data
				if frames[-1]["keys"].has(key):
					return "duplicate_key"
				frames[-1]["keys"][key] = true
			previous = '"'
			continue
		if c == "{" or c == "[":
			frames.append({"object": c == "{", "keys": {}})
			if frames.size() > 16:
				return "depth_budget"
		elif c == "}" or c == "]":
			if frames.is_empty() or previous == ",":
				return "invalid_close_or_trailing_comma"
			frames.pop_back()
		elif c == "-" or c in "0123456789":
			var start: int = i
			while i < text.length() and not text.substr(i, 1) in [" ", "\t", "\r", "\n", ",", ":", "]", "}"]:
				i += 1
			var token: String = text.substr(start, i - start)
			if token.length() > 11 or integer_token.search(token) == null:
				return "integer_syntax"
			previous = "number"
			continue
		previous = c
		i += 1
	return ""

static func decode(text: String, catalog: Dictionary) -> Dictionary:
	var lexical: String = _lexical_error(text)
	if not lexical.is_empty():
		return reject(lexical)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return reject("invalid_json")
	return _decode_parsed(parser.data, catalog)

static func _decode_parsed(d: Variant, catalog: Dictionary) -> Dictionary:
	# 内部入口：调用方已对完整原始文本执行词法/大小/深度校验。
	# 不把Godot解析后的float重新写成JSON再校验，保持整数传输约束。
	if catalog.get("format") != "rw.catalog/0.1" or not catalog.get("materials") is Dictionary or not catalog.get("rules") is Dictionary:
		return reject("invalid_catalog")
	if not _shape(d, ["format", "world_id", "stacks", "instances"]):
		return reject("checkpoint_fields")
	if d.format != "rw.instances/0.1":
		return reject("unsupported_format")
	if not identifier(d.world_id):
		return reject("invalid_world_id")
	if not d.stacks is Dictionary or d.stacks.size() > 1024 or not d.instances is Array or d.instances.size() > 4096:
		return reject("collection_budget_or_type")
	for id in d.stacks:
		var material: Variant = catalog.materials.get(id)
		if not identifier(id) or not material is Dictionary or material.get("stackable") != true:
			return reject("invalid_stack_material")
		if not _integer(d.stacks[id], 1, MAX_QUANTITY):
			return reject("invalid_stack_quantity")
		d.stacks[id] = int(d.stacks[id])
	var ids: Dictionary = {}
	var cells: Dictionary = {}
	for entity in d.instances:
		if not _shape(entity, ["id", "material_id", "rules", "state", "location"]):
			return reject("instance_fields")
		if not identifier(entity.id) or ids.has(entity.id):
			return reject("invalid_or_duplicate_instance_id")
		ids[entity.id] = true
		var material: Variant = catalog.materials.get(entity.material_id)
		if not identifier(entity.material_id) or not material is Dictionary or material.get("stackable") != false or material.get("state") != "reservoir/0.1":
			return reject("invalid_instance_material")
		if not entity.rules is Array or entity.rules.size() > 16:
			return reject("rule_budget_or_type")
		var used_rules: Dictionary = {}
		for ref in entity.rules:
			if not _shape(ref, ["id", "version"]) or not identifier(ref.id) or not _integer(ref.version, 1, 2147483647):
				return reject("invalid_rule_reference")
			var versions: Variant = catalog.rules.get(ref.id)
			if not versions is Array or not has_version(versions, int(ref.version)) or used_rules.has(ref.id):
				return reject("missing_or_duplicate_rule")
			used_rules[ref.id] = true
			ref.version = int(ref.version)
		var state: Variant = entity.state
		if not _shape(state, ["water_units", "capacity_units", "light_on"]):
			return reject("state_fields")
		if not _integer(state.capacity_units, 1, MAX_QUANTITY) or not _integer(state.water_units, 0, int(state.capacity_units)) or typeof(state.light_on) != TYPE_BOOL:
			return reject("invalid_state_value")
		state.capacity_units = int(state.capacity_units)
		state.water_units = int(state.water_units)
		var loc: Variant = entity.location
		if not loc is Dictionary:
			return reject("invalid_location")
		if loc.get("kind") == "world":
			if not _shape(loc, ["kind", "cell"]) or not loc.cell is Array or loc.cell.size() != 2:
				return reject("world_location_fields")
			if not _integer(loc.cell[0], -1000000, 1000000) or not _integer(loc.cell[1], -1000000, 1000000):
				return reject("coordinate_range")
			var pos := Vector2i(int(loc.cell[0]), int(loc.cell[1]))
			if cells.has(pos):
				return reject("occupied_cell")
			cells[pos] = true
			loc.cell = [pos.x, pos.y]
		elif loc.get("kind") == "inventory":
			if not _shape(loc, ["kind", "owner"]) or not identifier(loc.owner):
				return reject("inventory_location_fields")
		else:
			return reject("unsupported_location")
	return {"ok": true, "error": "", "snapshot": d}
