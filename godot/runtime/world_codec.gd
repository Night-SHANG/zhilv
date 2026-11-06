extends RefCounted
## 世界信封复用实例协议；所有嵌套数据验证成功后才交给会话提交。
const Codec = preload("res://runtime/snapshot_codec.gd")
const MAX_TERRAIN: int = 16384
const COORD_LIMIT: int = 1000000

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
	if not Codec._shape(d, ["format", "entities", "terrain", "actor"]) or d.format != "rw.world/0.1":
		return Codec.reject("world_format_or_fields")
	var nested: Dictionary = Codec._decode_parsed(d.entities, catalog)
	if not nested.ok:
		return nested
	d.entities = nested.snapshot
	if not Codec._shape(d.actor, ["id", "cell"]) or not Codec.identifier(d.actor.id) or not cell_valid(d.actor.cell):
		return Codec.reject("invalid_actor")
	var foot := Vector2i(int(d.actor.cell[0]), int(d.actor.cell[1]))
	if not in_bounds(foot + Vector2i.UP):
		return Codec.reject("actor_head_outside_bounds")
	d.actor.cell = [foot.x, foot.y]
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
	if occupied.has(foot) or occupied.has(foot + Vector2i.UP):
		return Codec.reject("actor_overlap")
	return {"ok": true, "error": "", "snapshot": d}
