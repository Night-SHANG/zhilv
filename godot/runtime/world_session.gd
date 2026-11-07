extends RefCounted
## 单角色、有限活跃格的权威交互入口；原生角色运动必须提交完整亚格身体占位。
## 本轮使用有界完整快照事务以保证失败不部分提交；大世界增量优化尚未验收。
signal committed(cells: Array)
signal reloaded
const Codec = preload("res://runtime/snapshot_codec.gd")
const WorldCodec = preload("res://runtime/world_codec.gd")
const WaterFlow = preload("res://runtime/water_flow.gd")
const Store = preload("res://runtime/instance_store.gd")
const REACH_SQUARED: int = 16
var _catalog: Dictionary
var _snapshot: Dictionary = {}
var _terrain: Dictionary = {}
var _occupants: Dictionary = {}
var _water: Dictionary = {}
var _store

func _init(catalog: Dictionary) -> void:
	_catalog = catalog.duplicate(true)

func validate_checkpoint(text: String) -> Dictionary:
	return WorldCodec.decode(text, _catalog)

func load_checkpoint(text: String) -> Dictionary:
	var result: Dictionary = validate_checkpoint(text)
	if not result.ok:
		return result
	var next_store = Store.new(_catalog)
	var loaded: Dictionary = next_store.load_checkpoint(JSON.stringify(result.snapshot.entities))
	if not loaded.ok:
		return loaded
	_adopt(result.snapshot, next_store)
	reloaded.emit()
	return {"ok": true, "error": ""}

func _adopt(snapshot: Dictionary, store) -> void:
	_snapshot = snapshot
	_store = store
	_terrain = {}
	_occupants = {}
	_water = {}
	for entry in snapshot.get("water", []):
		_water[Vector2i(entry.cell[0], entry.cell[1])] = entry.units
	for tile in snapshot.terrain:
		_terrain[Vector2i(tile.cell[0], tile.cell[1])] = tile.material_id
	for entity in snapshot.entities.instances:
		if entity.location.kind == "world":
			_occupants[Vector2i(entity.location.cell[0], entity.location.cell[1])] = entity.id

func checkpoint_json() -> String:
	return JSON.stringify(_snapshot)

func actor_cell() -> Vector2i:
	if _snapshot.is_empty():
		return Vector2i.ZERO
	return Vector2i(_snapshot.actor.cell[0], _snapshot.actor.cell[1])

func get_instance(id: String) -> Dictionary:
	return {} if _store == null else _store.get_instance(id)

func stack_count(id: String) -> int:
	return 0 if _store == null else _store.stack_count(id)

func material_at(cell: Vector2i) -> String:
	if _terrain.has(cell):
		return _terrain[cell]
	if _occupants.has(cell):
		return _store.get_instance(_occupants[cell]).material_id
	return ""

func occupied_cells() -> Array:
	return _terrain.keys() + _occupants.keys()

func _actor_at(cell: Vector2i) -> bool:
	return actor_occupied_cells().has(cell)

func _blocks_ray(cell: Vector2i, target: Vector2i) -> bool:
	return cell != target and not material_at(cell).is_empty()

func _access(cell: Vector2i) -> Dictionary:
	if _snapshot.is_empty():
		return Codec.reject("world_not_loaded")
	if not WorldCodec.in_bounds(cell):
		return Codec.reject("coordinate_range")
	var start: Vector2i = actor_cell()
	var delta: Vector2i = cell - start
	if delta.length_squared() > REACH_SQUARED:
		return Codec.reject("out_of_reach")
	return {"ok":true,"error":""} if line_clear(start, cell) else Codec.reject("occluded")

func line_clear(start: Vector2i, cell: Vector2i) -> bool:
	var delta: Vector2i = cell - start
	if absi(delta.x) > 64 or absi(delta.y) > 64: return false
	# 保守超覆盖网格线：斜线恰好通过墙角时，两侧障碍都能阻挡。
	var nx: int = absi(delta.x)
	var ny: int = absi(delta.y)
	var sx: int = signi(delta.x)
	var sy: int = signi(delta.y)
	var ix: int = 0
	var iy: int = 0
	var p: Vector2i = start
	while ix < nx or iy < ny:
		var decision: int = (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if decision == 0:
			if _blocks_ray(p + Vector2i(sx, 0), cell) or _blocks_ray(p + Vector2i(0, sy), cell):
				return false
			p += Vector2i(sx, sy)
			ix += 1
			iy += 1
		elif decision < 0:
			p.x += sx
			ix += 1
		else:
			p.y += sy
			iy += 1
		if _blocks_ray(p, cell):
			return false
	return true

func _staged_store():
	var stage = Store.new(_catalog)
	stage.load_checkpoint(_store.checkpoint_json())
	return stage

func _commit(stage, terrain: Dictionary, actor: Dictionary, changed: Array, water_override: Variant = null) -> Dictionary:
	var water: Dictionary = _water if water_override == null else water_override
	var tiles: Array = []
	var positions: Array = terrain.keys()
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in positions:
		tiles.append({"cell": [cell.x, cell.y], "material_id": terrain[cell]})
	var normalized: Dictionary = stage.validate_checkpoint(stage.checkpoint_json())
	if not normalized.ok:
		return normalized
	var candidate: Dictionary = {"format": "rw.world/0.1", "entities": normalized.snapshot, "terrain": tiles, "actor": actor}
	if WorldCodec.has_environment(_snapshot) or water_override != null or actor.has("body_foot"):
		candidate.format = "rw.world/0.3" if actor.has("body_foot") else "rw.world/0.2"
		candidate["water"] = _water_entries(water)
	var valid: Dictionary = validate_checkpoint(JSON.stringify(candidate))
	if not valid.ok:
		return valid
	# 没有 await：完整校验之后才替换所有权威状态与派生索引。
	_adopt(valid.snapshot, stage)
	committed.emit(changed.duplicate())
	return {"ok": true, "error": ""}

func mine(cell: Vector2i) -> Dictionary:
	var access: Dictionary = _access(cell)
	if not access.ok:
		return access
	if not _terrain.has(cell):
		return Codec.reject("not_static_terrain")
	var stage = _staged_store()
	var added: Dictionary = stage.change_stack(_terrain[cell], 1)
	if not added.ok:
		return added
	var tiles: Dictionary = _terrain.duplicate()
	tiles.erase(cell)
	return _commit(stage, tiles, _snapshot.actor.duplicate(true), [cell])

func build(material_id: String, cell: Vector2i) -> Dictionary:
	var access: Dictionary = _access(cell)
	if not access.ok:
		return access
	if _actor_at(cell) or not material_at(cell).is_empty() or water_at(cell) > 0:
		return Codec.reject("occupied_cell")
	if _terrain.size() >= WorldCodec.MAX_TERRAIN:
		return Codec.reject("terrain_budget")
	var stage = _staged_store()
	var removed: Dictionary = stage.change_stack(material_id, -1)
	if not removed.ok:
		return removed
	var tiles: Dictionary = _terrain.duplicate()
	tiles[cell] = material_id
	return _commit(stage, tiles, _snapshot.actor.duplicate(true), [cell])

func pickup(id: String) -> Dictionary:
	var entity: Dictionary = get_instance(id)
	if entity.is_empty() or entity.location.kind != "world":
		return Codec.reject("not_in_world")
	var cell := Vector2i(entity.location.cell[0], entity.location.cell[1])
	var access: Dictionary = _access(cell)
	if not access.ok:
		return access
	var stage = _staged_store()
	var result: Dictionary = stage.pickup(id, _snapshot.actor.id)
	if not result.ok:
		return result
	return _commit(stage, _terrain, _snapshot.actor.duplicate(true), [cell])

func place(id: String, cell: Vector2i) -> Dictionary:
	var access: Dictionary = _access(cell)
	if not access.ok:
		return access
	if _actor_at(cell) or not material_at(cell).is_empty() or water_at(cell) > 0:
		return Codec.reject("occupied_cell")
	var stage = _staged_store()
	var result: Dictionary = stage.place(id, _snapshot.actor.id, cell)
	if not result.ok:
		return result
	return _commit(stage, _terrain, _snapshot.actor.duplicate(true), [cell])

func step_actor(delta: Vector2i) -> Dictionary:
	if _snapshot.is_empty() or absi(delta.x) + absi(delta.y) != 1:
		return Codec.reject("invalid_grid_step")
	if _snapshot.actor.has("body_foot"):
		return move_actor_body(actor_body_foot() + delta * WorldCodec.BODY_UNITS)
	var cell: Vector2i = actor_cell() + delta
	if not WorldCodec.in_bounds(cell) or not WorldCodec.in_bounds(cell + Vector2i.UP):
		return Codec.reject("coordinate_range")
	if not material_at(cell).is_empty() or not material_at(cell + Vector2i.UP).is_empty():
		return Codec.reject("actor_collision")
	if water_at(cell) >= WorldCodec.DEEP_WATER or water_at(cell + Vector2i.UP) >= WorldCodec.DEEP_WATER:
		return Codec.reject("deep_water")
	var actor: Dictionary = _snapshot.actor.duplicate(true)
	actor.cell = [cell.x, cell.y]
	return _commit(_staged_store(), _terrain, actor, [])

func _accessible_instance(id: String) -> Dictionary:
	var entity: Dictionary = get_instance(id)
	if entity.is_empty():
		return Codec.reject("missing_instance")
	if entity.location.kind == "inventory":
		return {"ok": true, "error": ""} if entity.location.owner == _snapshot.actor.id else Codec.reject("not_owned")
	return _access(Vector2i(entity.location.cell[0], entity.location.cell[1]))

func pour_water(source: String, target: String, amount: Variant) -> Dictionary:
	for id in [source, target]:
		var access: Dictionary = _accessible_instance(id)
		if not access.ok:
			return access
	var stage = _staged_store()
	var result: Dictionary = stage.transfer_water(source, target, amount)
	if not result.ok:
		return result
	var changed: Array = []
	for id in [source, target]:
		var entity: Dictionary = stage.get_instance(id)
		if entity.location.kind == "world":
			changed.append(Vector2i(entity.location.cell[0], entity.location.cell[1]))
	return _commit(stage, _terrain, _snapshot.actor.duplicate(true), changed)

func material_ids() -> Array:
	return _catalog.materials.keys()

func rule_view() -> Dictionary:
	# 调用者只能得到副本；运行时不得修改权威世界的数据引用。
	return _snapshot.duplicate(true)

func apply_rule_commands(self_id: String, commands: Variant) -> Dictionary:
	var source: Dictionary = get_instance(self_id)
	if source.is_empty() or source.location.kind != "world":
		return Codec.reject("rule_owner_not_in_world")
	if not commands is Array or commands.size() > 64:
		return Codec.reject("command_budget_or_type")
	if commands.is_empty():
		return {"ok": true, "error": ""}
	var stage = _staged_store()
	var water: Dictionary = _water.duplicate()
	var changed: Array = []
	for command in commands:
		if not command is Dictionary or not command.get("op") is String:
			return Codec.reject("invalid_rule_command")
		var entity: Dictionary = stage.get_instance(self_id)
		var cell := Vector2i(entity.location.cell[0], entity.location.cell[1])
		if not changed.has(cell):
			changed.append(cell)
		var result: Dictionary
		match command.op:
			"set_light":
				if not Codec._shape(command, ["op", "value"]):
					return Codec.reject("light_command_fields")
				result = stage.set_light(self_id, command.value)
			"move":
				if not Codec._shape(command, ["op", "dx", "dy"]) or typeof(command.dx) != TYPE_INT or typeof(command.dy) != TYPE_INT or command.dx < -1 or command.dx > 1 or command.dy < -1 or command.dy > 1 or absi(command.dx) + absi(command.dy) != 1:
					return Codec.reject("invalid_rule_move")
				var target: Vector2i = cell + Vector2i(command.dx, command.dy)
				if _terrain.has(target) or _actor_at(target) or int(water.get(target,0)) > 0:
					return Codec.reject("rule_move_collision")
				result = stage.move_world(self_id, target)
				if not changed.has(target):
					changed.append(target)
			"take_water":
				if not Codec._shape(command, ["op", "source", "amount"]) or not command.source is String:
					return Codec.reject("water_command_fields")
				var donor: Dictionary = stage.get_instance(command.source)
				if donor.is_empty() or donor.location.kind != "world":
					return Codec.reject("rule_source_not_in_world")
				var donor_cell := Vector2i(donor.location.cell[0], donor.location.cell[1])
				var delta: Vector2i = donor_cell - cell
				if absi(delta.x) + absi(delta.y) != 1:
					return Codec.reject("rule_source_not_adjacent")
				result = stage.transfer_water(command.source, self_id, command.amount)
				if not changed.has(donor_cell):
					changed.append(donor_cell)
			"take_environment_water", "release_environment_water":
				if not WorldCodec.has_environment(_snapshot): return Codec.reject("environment_not_enabled")
				var target: Vector2i
				if command.op == "take_environment_water":
					if not Codec._shape(command,["op","cell","amount"]) or not command.cell is Vector2i: return Codec.reject("environment_command_fields")
					target = command.cell
				else:
					if not Codec._shape(command,["op","dx","dy","amount"]) or typeof(command.dx)!=TYPE_INT or typeof(command.dy)!=TYPE_INT or absi(command.dx)+absi(command.dy)!=1: return Codec.reject("environment_command_fields")
					target = cell + Vector2i(command.dx,command.dy)
				var delta: Vector2i = target - cell
				if absi(delta.x)+absi(delta.y)!=1: return Codec.reject("environment_source_not_adjacent")
				result = _exchange_water(stage,water,self_id,target,command.amount,command.op=="take_environment_water")
				if not changed.has(target): changed.append(target)
			_:
				return Codec.reject("forbidden_rule_command")
		if not result.ok:
			return result
	return _commit(stage, _terrain, _snapshot.actor.duplicate(true), changed, water if WorldCodec.has_environment(_snapshot) else null)

func _prepare_rule_revision(versions: Dictionary, snapshot: Dictionary) -> Dictionary:
	## 可信宿主内部接口：规则运行时已完成引用/权限检查；材料能力保持原目录。
	var catalog: Dictionary = _catalog.duplicate(true)
	catalog.rules = versions.duplicate(true)
	var valid: Dictionary = WorldCodec.decode_value(snapshot.duplicate(true), catalog)
	if not valid.ok:
		return valid
	var store = Store.new(catalog)
	var loaded: Dictionary = store.load_checkpoint(JSON.stringify(valid.snapshot.entities))
	if not loaded.ok:
		return loaded
	return {"ok":true,"error":"","catalog":catalog,"snapshot":valid.snapshot,"store":store}

func _adopt_rule_revision(prepared: Dictionary) -> void:
	## 无通知提交。协调者在规则库也替换完成后才发reloaded，避免回调看到半成品。
	_catalog = prepared.catalog.duplicate(true)
	_adopt(prepared.snapshot, prepared.store)

static func _water_entries(water: Dictionary) -> Array:
	var cells: Array = water.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var entries: Array = []
	for cell: Vector2i in cells: entries.append({"cell":[cell.x,cell.y],"units":water[cell]})
	return entries

func water_at(cell: Vector2i) -> int:
	return int(_water.get(cell,0))

func water_cells() -> Array:
	return _water.keys()

func total_water_units() -> int:
	var total: int = 0
	for amount in _water.values(): total += amount
	for entity in _snapshot.get("entities",{}).get("instances",[]): total += entity.state.water_units
	return total

func enable_environment() -> Dictionary:
	if _snapshot.is_empty(): return Codec.reject("world_not_loaded")
	if WorldCodec.has_environment(_snapshot): return {"ok":true,"error":""}
	return _commit(_staged_store(),_terrain,_snapshot.actor.duplicate(true),[],{})

func _exchange_water(stage, water: Dictionary, id: String, cell: Vector2i, amount: Variant, collect: bool) -> Dictionary:
	if typeof(amount) != TYPE_INT or amount < 1 or amount > WorldCodec.CELL_WATER_CAPACITY or not WorldCodec.in_bounds(cell):
		return Codec.reject("invalid_environment_transfer")
	if _terrain.has(cell) or stage.instance_at(cell) != "": return Codec.reject("solid_water_target")
	var units: int = int(water.get(cell,0))
	if (collect and units < amount) or (not collect and units + amount > WorldCodec.CELL_WATER_CAPACITY):
		return Codec.reject("environment_water_or_capacity")
	var change: Dictionary = stage._change_water(id, amount if collect else -amount)
	if not change.ok: return change
	units += -amount if collect else amount
	if units == 0: water.erase(cell)
	else: water[cell] = units
	return {"ok":true,"error":""}

func collect_water(id: String, cell: Vector2i, amount: Variant) -> Dictionary:
	return _manual_water(id,cell,amount,true)

func release_water(id: String, cell: Vector2i, amount: Variant) -> Dictionary:
	return _manual_water(id,cell,amount,false)

func _manual_water(id: String, cell: Vector2i, amount: Variant, collect: bool) -> Dictionary:
	if not WorldCodec.has_environment(_snapshot): return Codec.reject("environment_not_enabled")
	var access: Dictionary = _accessible_instance(id)
	if not access.ok: return access
	access = _access(cell)
	if not access.ok: return access
	var stage = _staged_store()
	var water: Dictionary = _water.duplicate()
	var changed: Dictionary = _exchange_water(stage,water,id,cell,amount,collect)
	if not changed.ok: return changed
	var cells: Array = [cell]
	var entity: Dictionary = stage.get_instance(id)
	if entity.location.kind == "world": cells.append(Vector2i(entity.location.cell[0],entity.location.cell[1]))
	return _commit(stage,_terrain,_snapshot.actor.duplicate(true),cells,water)

func advance_water(operation_budget: Variant = 65536) -> Dictionary:
	if not WorldCodec.has_environment(_snapshot): return Codec.reject("environment_not_enabled")
	var blockers: Dictionary = {}
	for cell: Vector2i in occupied_cells(): blockers[cell] = true
	var result: Dictionary = WaterFlow.step(_water,blockers,WorldCodec.MAX_WATER,operation_budget)
	if not result.ok: return result
	if not result.changed.is_empty():
		var saved: Dictionary = _commit(_staged_store(),_terrain,_snapshot.actor.duplicate(true),result.changed,result.water)
		if not saved.ok: return saved
	return {"ok":true,"error":"","operations":result.operations,"changed":result.changed.size()}

func ambient_dark_at(cell: Vector2i, night: bool) -> bool:
	if night: return true
	for tile: Vector2i in _terrain:
		if tile.x == cell.x and tile.y < cell.y: return true
	return false

func has_light_at(cell: Vector2i, night: bool) -> bool:
	## 逻辑可见性判断，不是GPU光照验收；半径4格，实体和地形遮挡。
	if not ambient_dark_at(cell,night): return true
	for entity in _snapshot.get("entities",{}).get("instances",[]):
		if entity.location.kind != "world" or not entity.state.light_on: continue
		var source := Vector2i(entity.location.cell[0],entity.location.cell[1])
		if (source-cell).length_squared() <= 16 and line_clear(source,cell): return true
	return false

func actor_occupied_cells() -> Array:
	return [] if _snapshot.is_empty() else WorldCodec.actor_cells(_snapshot.actor)

func actor_body_foot() -> Vector2i:
	if _snapshot.is_empty(): return Vector2i.ZERO
	if _snapshot.actor.has("body_foot"):
		return Vector2i(_snapshot.actor.body_foot[0], _snapshot.actor.body_foot[1])
	return actor_cell() * WorldCodec.BODY_UNITS + Vector2i(WorldCodec.BODY_UNITS / 2, WorldCodec.BODY_UNITS)

func enable_actor_body() -> Dictionary:
	if _snapshot.is_empty(): return Codec.reject("world_not_loaded")
	if _snapshot.actor.has("body_foot"): return {"ok":true,"error":""}
	var actor: Dictionary = _snapshot.actor.duplicate(true)
	var foot: Vector2i = actor_body_foot()
	actor["body_foot"] = [foot.x, foot.y]
	return _commit(_staged_store(), _terrain, actor, [], _water)

func move_actor_body(foot: Vector2i) -> Dictionary:
	if _snapshot.is_empty() or not _snapshot.actor.has("body_foot"): return Codec.reject("actor_body_not_enabled")
	var previous: Vector2i = actor_body_foot()
	var delta: Vector2i = foot - previous
	if absi(delta.x) > WorldCodec.BODY_UNITS or absi(delta.y) > WorldCodec.BODY_UNITS: return Codec.reject("body_motion_too_large")
	if foot == previous: return {"ok":true,"error":""}
	var actor: Dictionary = _snapshot.actor.duplicate(true)
	var old_cells: Array = actor_occupied_cells()
	# 原生碰撞之外再做有界扫掠：外部命令不能只校验终点而穿过墙角。
	var samples: int = maxi(1, ceili(float(maxi(absi(delta.x), absi(delta.y))) / 64.0))
	for i in range(1, samples + 1):
		var pos: Vector2i = previous + Vector2i(roundi(float(delta.x) * i / samples), roundi(float(delta.y) * i / samples))
		actor.body_foot = [pos.x, pos.y]
		for cell: Vector2i in WorldCodec.actor_cells(actor):
			if not WorldCodec.in_bounds(cell): return Codec.reject("coordinate_range")
			if not material_at(cell).is_empty(): return Codec.reject("actor_collision")
			if not old_cells.has(cell) and water_at(cell) >= WorldCodec.DEEP_WATER: return Codec.reject("deep_water")
	var anchor: Vector2i = WorldCodec.body_cell(foot)
	actor.cell = [anchor.x, anchor.y]
	actor.body_foot = [foot.x, foot.y]
	return _commit(_staged_store(), _terrain, actor, [])

func instance_at(cell: Vector2i) -> String:
	return str(_occupants.get(cell, ""))
