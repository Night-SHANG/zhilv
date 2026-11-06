extends RefCounted
## 单角色、有限活跃格的权威交互入口；不是角色物理或可执行玩家脚本。
## 本轮使用有界完整快照事务以保证失败不部分提交；大世界增量优化尚未验收。
signal committed(cells: Array)
signal reloaded
const Codec = preload("res://runtime/snapshot_codec.gd")
const WorldCodec = preload("res://runtime/world_codec.gd")
const Store = preload("res://runtime/instance_store.gd")
const REACH_SQUARED: int = 16
var _catalog: Dictionary
var _snapshot: Dictionary = {}
var _terrain: Dictionary = {}
var _occupants: Dictionary = {}
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
	return cell == actor_cell() or cell == actor_cell() + Vector2i.UP

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
				return Codec.reject("occluded")
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
			return Codec.reject("occluded")
	return {"ok": true, "error": ""}

func _staged_store():
	var stage = Store.new(_catalog)
	stage.load_checkpoint(_store.checkpoint_json())
	return stage

func _commit(stage, terrain: Dictionary, actor: Dictionary, changed: Array) -> Dictionary:
	var tiles: Array = []
	var positions: Array = terrain.keys()
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in positions:
		tiles.append({"cell": [cell.x, cell.y], "material_id": terrain[cell]})
	var candidate: Dictionary = {"format": "rw.world/0.1", "entities": stage.validate_checkpoint(stage.checkpoint_json()).snapshot, "terrain": tiles, "actor": actor}
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
	if _actor_at(cell) or not material_at(cell).is_empty():
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
	if _actor_at(cell) or not material_at(cell).is_empty():
		return Codec.reject("occupied_cell")
	var stage = _staged_store()
	var result: Dictionary = stage.place(id, _snapshot.actor.id, cell)
	if not result.ok:
		return result
	return _commit(stage, _terrain, _snapshot.actor.duplicate(true), [cell])

func step_actor(delta: Vector2i) -> Dictionary:
	if _snapshot.is_empty() or absi(delta.x) + absi(delta.y) != 1:
		return Codec.reject("invalid_grid_step")
	var cell: Vector2i = actor_cell() + delta
	if not WorldCodec.in_bounds(cell) or not WorldCodec.in_bounds(cell + Vector2i.UP):
		return Codec.reject("coordinate_range")
	if not material_at(cell).is_empty() or not material_at(cell + Vector2i.UP).is_empty():
		return Codec.reject("actor_collision")
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
