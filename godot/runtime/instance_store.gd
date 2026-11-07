extends RefCounted
## 实例唯一归属与整数资源账本。此处不执行规则，不负责角色距离/地形碰撞判定。
const Codec = preload("res://runtime/snapshot_codec.gd")
const Inventory = preload("res://vendor/coheronia/inventory.gd")
var _catalog: Dictionary
var _state: Dictionary = {}
var _indices: Dictionary = {}
var _inventory = Inventory.new()

func _init(catalog: Dictionary) -> void:
	_catalog = catalog.duplicate(true)

func validate_checkpoint(text: String) -> Dictionary:
	return Codec.decode(text, _catalog)

func load_checkpoint(text: String) -> Dictionary:
	var result: Dictionary = validate_checkpoint(text)
	if not result.ok:
		return result
	# 所有校验成功之后才替换权威状态；失败时不清空旧世界。
	_state = result.snapshot
	_inventory = Inventory.new()
	_inventory.from_dict(_state.stacks)
	_indices.clear()
	for index in range(_state.instances.size()):
		_indices[_state.instances[index].id] = index
	return {"ok": true, "error": ""}

func checkpoint_json() -> String:
	if _state.is_empty():
		return "{}"
	var out: Dictionary = _state.duplicate(true)
	out.stacks = _inventory.to_dict()
	return JSON.stringify(out)

func _entity(id: String) -> Dictionary:
	if not _indices.has(id):
		return {}
	return _state.instances[_indices[id]]

func get_instance(id: String) -> Dictionary:
	return _entity(id).duplicate(true)

func pickup(id: String, owner: String) -> Dictionary:
	var entity: Dictionary = _entity(id)
	if entity.is_empty() or not Codec.identifier(owner):
		return Codec.reject("missing_instance_or_invalid_owner")
	if entity.location.kind != "world":
		return Codec.reject("not_in_world")
	entity.location = {"kind": "inventory", "owner": owner}
	return {"ok": true, "error": ""}

func place(id: String, owner: String, cell: Vector2i) -> Dictionary:
	var entity: Dictionary = _entity(id)
	if entity.is_empty() or entity.location.kind != "inventory" or entity.location.owner != owner:
		return Codec.reject("not_owned")
	if cell.x < -1000000 or cell.x > 1000000 or cell.y < -1000000 or cell.y > 1000000:
		return Codec.reject("coordinate_range")
	for other in _state.instances:
		if other.location.kind == "world" and Vector2i(other.location.cell[0], other.location.cell[1]) == cell:
			return Codec.reject("occupied_cell")
	entity.location = {"kind": "world", "cell": [cell.x, cell.y]}
	return {"ok": true, "error": ""}

func transfer_water(source_id: String, target_id: String, amount: Variant) -> Dictionary:
	if typeof(amount) != TYPE_INT or amount <= 0 or amount > Codec.MAX_QUANTITY or source_id == target_id:
		return Codec.reject("invalid_transfer")
	var source: Dictionary = _entity(source_id)
	var target: Dictionary = _entity(target_id)
	if source.is_empty() or target.is_empty():
		return Codec.reject("missing_instance")
	if source.state.water_units < amount or target.state.capacity_units - target.state.water_units < amount:
		return Codec.reject("insufficient_water_or_capacity")
	# 先完成全部检查，再同时改变两端；不使用小数水量，不删除微量余水。
	source.state.water_units -= amount
	target.state.water_units += amount
	return {"ok": true, "error": ""}

func stack_count(id: String) -> int:
	return _inventory.count(id)

func change_stack(id: String, delta: Variant) -> Dictionary:
	if _state.is_empty() or typeof(delta) != TYPE_INT or delta == 0 or delta < -Codec.MAX_QUANTITY or delta > Codec.MAX_QUANTITY:
		return Codec.reject("invalid_quantity")
	var material: Variant = _catalog.materials.get(id)
	if not material is Dictionary or material.get("stackable") != true:
		return Codec.reject("not_stackable")
	var next: int = _inventory.count(id) + delta
	if next < 0 or next > Codec.MAX_QUANTITY:
		return Codec.reject("quantity_range")
	if delta > 0:
		_inventory.add(id, delta)
	else:
		_inventory.remove(id, -delta)
	return {"ok": true, "error": ""}

func set_light(id: String, value: Variant) -> Dictionary:
	var entity: Dictionary = _entity(id)
	if entity.is_empty() or typeof(value) != TYPE_BOOL:
		return Codec.reject("invalid_light_change")
	entity.state.light_on = value
	return {"ok": true, "error": ""}

func move_world(id: String, cell: Vector2i) -> Dictionary:
	var entity: Dictionary = _entity(id)
	if entity.is_empty() or entity.location.kind != "world":
		return Codec.reject("not_in_world")
	if cell.x < -1000000 or cell.x > 1000000 or cell.y < -1000000 or cell.y > 1000000:
		return Codec.reject("coordinate_range")
	for other in _state.instances:
		if other.id != id and other.location.kind == "world" and Vector2i(other.location.cell[0], other.location.cell[1]) == cell:
			return Codec.reject("occupied_cell")
	entity.location.cell = [cell.x, cell.y]
	return {"ok": true, "error": ""}

func _change_water(id: String, delta: Variant) -> Dictionary:
	## 仅供世界事务调入；环境一端也必须同步更新，不能向玩家规则暴露凭空加水。
	var entity: Dictionary = _entity(id)
	if entity.is_empty() or typeof(delta) != TYPE_INT or delta < -Codec.MAX_QUANTITY or delta > Codec.MAX_QUANTITY:
		return Codec.reject("invalid_water_change")
	var next: int = entity.state.water_units + delta
	if next < 0 or next > entity.state.capacity_units:
		return Codec.reject("insufficient_water_or_capacity")
	entity.state.water_units = next
	return {"ok":true,"error":""}

func instance_at(cell: Vector2i) -> String:
	for entity in _state.get("instances",[]):
		if entity.location.kind == "world" and Vector2i(entity.location.cell[0],entity.location.cell[1]) == cell:
			return entity.id
	return ""

func _insert_instance(entity: Dictionary) -> Dictionary:
	## 内部制作事务使用；不向玩家规则开放任意实例注入。
	if _state.is_empty():return Codec.reject("store_not_loaded")
	if _state.instances.size()>=4096:return Codec.reject("instance_budget")
	if not Codec.identifier(entity.get("id")) or _indices.has(entity.id):return Codec.reject("invalid_or_duplicate_instance_id")
	var candidate: Dictionary=_state.duplicate(true)
	candidate.stacks=_inventory.to_dict()
	candidate.instances.append(entity.duplicate(true))
	return load_checkpoint(JSON.stringify(candidate))
