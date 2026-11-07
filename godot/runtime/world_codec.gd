extends RefCounted
## 世界信封复用实例协议；所有嵌套数据验证成功后才交给会话提交。
const Codec = preload("res://runtime/snapshot_codec.gd")
const MAX_TERRAIN: int = 16384
const COORD_LIMIT: int = 1000000
const MAX_WATER: int = 4096
const CELL_WATER_CAPACITY: int = 1000
const DEEP_WATER: int = 200
const BODY_UNITS: int = 1024
const BODY_HALF_WIDTH: int = 320
const BODY_HEIGHT: int = 1792

static func has_environment(snapshot: Dictionary) -> bool:
	return snapshot.get("format") in ["rw.world/0.2", "rw.world/0.3"]

static func body_cell(foot: Vector2i) -> Vector2i:
	return Vector2i(floori(float(foot.x) / BODY_UNITS), floori(float(foot.y - 1) / BODY_UNITS))

static func actor_cells(actor: Dictionary) -> Array:
	if not actor.has("body_foot"):
		var cell := Vector2i(actor.cell[0], actor.cell[1])
		return [cell + Vector2i.UP, cell]
	var point: Array = actor.body_foot
	var lo := Vector2i(floori(float(point[0] - BODY_HALF_WIDTH) / BODY_UNITS), floori(float(point[1] - BODY_HEIGHT) / BODY_UNITS))
	var hi := Vector2i(floori(float(point[0] + BODY_HALF_WIDTH - 1) / BODY_UNITS), floori(float(point[1] - 1) / BODY_UNITS))
	var cells: Array = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1): cells.append(Vector2i(x, y))
	return cells

static func body_foot_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Codec._integer(value[0], -COORD_LIMIT * BODY_UNITS, (COORD_LIMIT + 1) * BODY_UNITS) and Codec._integer(value[1], -COORD_LIMIT * BODY_UNITS, (COORD_LIMIT + 1) * BODY_UNITS)


static func cell_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Codec._integer(value[0], -COORD_LIMIT, COORD_LIMIT) and Codec._integer(value[1], -COORD_LIMIT, COORD_LIMIT)

static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= -COORD_LIMIT and cell.x <= COORD_LIMIT and cell.y >= -COORD_LIMIT and cell.y <= COORD_LIMIT

static func decode(text: String, catalog: Dictionary) -> Dictionary:
	var lexical: String = Codec._lexical_error(text)
	if not lexical.is_empty():
		return Codec.reject(lexical)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return Codec.reject("invalid_json")
	return decode_value(parser.data, catalog)

static func decode_value(d: Variant, catalog: Dictionary) -> Dictionary:
	# 内部入口：原文词法闸门由外层信封统一执行。
	if not d is Dictionary:
		return Codec.reject("world_format_or_fields")
	var environment: bool = has_environment(d)
	var fields: Array = ["format", "entities", "terrain", "actor"]
	if environment: fields.append("water")
	if not Codec._shape(d, fields) or not d.format in ["rw.world/0.1", "rw.world/0.2", "rw.world/0.3"]:
		return Codec.reject("world_format_or_fields")
	var nested: Dictionary = Codec._decode_parsed(d.entities, catalog)
	if not nested.ok:
		return nested
	d.entities = nested.snapshot
	var actor_fields: Array = ["id", "cell"]
	if d.format == "rw.world/0.3": actor_fields.append("body_foot")
	if not Codec._shape(d.actor, actor_fields) or not Codec.identifier(d.actor.id) or not cell_valid(d.actor.cell):
		return Codec.reject("invalid_actor")
	var foot := Vector2i(int(d.actor.cell[0]), int(d.actor.cell[1]))
	if not in_bounds(foot + Vector2i.UP):
		return Codec.reject("actor_head_outside_bounds")
	d.actor.cell = [foot.x, foot.y]
	if d.format == "rw.world/0.3":
		if not body_foot_valid(d.actor.body_foot): return Codec.reject("invalid_body_foot")
		var exact_foot := Vector2i(int(d.actor.body_foot[0]), int(d.actor.body_foot[1]))
		if body_cell(exact_foot) != foot: return Codec.reject("actor_body_anchor_mismatch")
		d.actor.body_foot = [exact_foot.x, exact_foot.y]
	var body_cells: Array = actor_cells(d.actor)
	for cell: Vector2i in body_cells:
		if not in_bounds(cell): return Codec.reject("actor_body_outside_bounds")
	if not d.terrain is Array or d.terrain.size() > MAX_TERRAIN:
		return Codec.reject("terrain_budget_or_type")
	var occupied: Dictionary = {}
	for tile in d.terrain:
		if not Codec._shape(tile, ["cell", "material_id"]) or not cell_valid(tile.cell) or not Codec.identifier(tile.material_id):
			return Codec.reject("invalid_tile")
		var material: Variant = catalog.materials.get(tile.material_id)
		if not material is Dictionary or material.get("stackable") != true:
			return Codec.reject("invalid_terrain_material")
		var cell := Vector2i(int(tile.cell[0]), int(tile.cell[1]))
		if occupied.has(cell):
			return Codec.reject("duplicate_terrain_cell")
		occupied[cell] = true
		tile.cell = [cell.x, cell.y]
	for entity in d.entities.instances:
		if entity.location.kind == "world":
			var cell := Vector2i(entity.location.cell[0], entity.location.cell[1])
			if occupied.has(cell):
				return Codec.reject("terrain_instance_overlap")
			occupied[cell] = true
		elif entity.location.owner != d.actor.id:
			return Codec.reject("unknown_inventory_owner")
	for cell: Vector2i in body_cells:
		if occupied.has(cell): return Codec.reject("actor_overlap")
	if environment:
		if not d.water is Array or d.water.size() > MAX_WATER:
			return Codec.reject("water_collection_budget")
		var water_cells: Dictionary = {}
		for entry in d.water:
			if not Codec._shape(entry, ["cell", "units"]) or not cell_valid(entry.cell) or not Codec._integer(entry.units, 1, CELL_WATER_CAPACITY):
				return Codec.reject("invalid_water_entry")
			var cell := Vector2i(int(entry.cell[0]), int(entry.cell[1]))
			if occupied.has(cell) or water_cells.has(cell):
				return Codec.reject("water_overlap")
			water_cells[cell] = true
			entry.cell = [cell.x, cell.y]
			entry.units = int(entry.units)
		d.water.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.cell[1] < b.cell[1] or (a.cell[1] == b.cell[1] and a.cell[0] < b.cell[0]))
	return {"ok": true, "error": "", "snapshot": d}
