extends RefCounted
## 有界、纯数据整数水求解器。每格1000单位；不删除微水，不直接持有世界或发信号。
const Codec = preload("res://runtime/snapshot_codec.gd")
const CAPACITY: int = 1000
const MAX_CELLS: int = 4096
const LIMIT: int = 1000000

static func _inside(cell: Vector2i) -> bool:
	return absi(cell.x) <= LIMIT and absi(cell.y) <= LIMIT

static func _order(a: Vector2i, b: Vector2i) -> bool:
	return a.y > b.y or (a.y == b.y and a.x < b.x)

static func _put(water: Dictionary, cell: Vector2i, units: int) -> void:
	if units == 0: water.erase(cell)
	else: water[cell] = units

static func _transfer(water: Dictionary, source: Vector2i, target: Vector2i, units: int) -> void:
	_put(water, source, int(water.get(source, 0)) - units)
	_put(water, target, int(water.get(target, 0)) + units)

static func step(water: Dictionary, blockers: Dictionary, max_cells: Variant = MAX_CELLS, operation_budget: Variant = 65536) -> Dictionary:
	if typeof(max_cells) != TYPE_INT or max_cells < 1 or max_cells > MAX_CELLS or typeof(operation_budget) != TYPE_INT or operation_budget < 1 or operation_budget > 65536:
		return Codec.reject("water_budget_config")
	if water.size() > max_cells or blockers.size() > 20480:
		return Codec.reject("water_cell_budget")
	for cell in blockers:
		if not cell is Vector2i or not _inside(cell) or blockers[cell] != true:
			return Codec.reject("invalid_water_blocker")
	for cell in water:
		if not cell is Vector2i or not _inside(cell) or typeof(water[cell]) != TYPE_INT or water[cell] < 1 or water[cell] > CAPACITY or blockers.has(cell):
			return Codec.reject("invalid_water_cell")
	var next: Dictionary = water.duplicate()
	var positions: Array = water.keys()
	positions.sort_custom(_order)
	var spent: int = 0
	# 自下向上：本步刚落入某格的水不会再次向下移动。
	for cell: Vector2i in positions:
		spent += 1
		if spent > operation_budget: return Codec.reject("water_operation_budget")
		var below: Vector2i = cell + Vector2i.DOWN
		if not _inside(below) or blockers.has(below): continue
		var amount: int = mini(water[cell], CAPACITY - int(next.get(below, 0)))
		if amount > 0: _transfer(next, cell, below, amount)
	# 水平阶段读取固定中间快照，每条边只处理一次；预留出流避免多邻居超支。
	var phase: Dictionary = next.duplicate()
	var remaining: Dictionary = phase.duplicate()
	var edges: Dictionary = {}
	for cell: Vector2i in phase:
		edges[cell] = true
		edges[cell + Vector2i.LEFT] = true
	var ordered: Array = edges.keys()
	ordered.sort_custom(_order)
	for left: Vector2i in ordered:
		spent += 1
		if spent > operation_budget: return Codec.reject("water_operation_budget")
		var right: Vector2i = left + Vector2i.RIGHT
		if not _inside(left) or not _inside(right) or blockers.has(left) or blockers.has(right): continue
		var difference: int = int(phase.get(left, 0)) - int(phase.get(right, 0))
		if absi(difference) < 2: continue
		var source: Vector2i = left if difference > 0 else right
		var target: Vector2i = right if difference > 0 else left
		var below: Vector2i = source + Vector2i.DOWN
		if _inside(below) and not blockers.has(below) and int(phase.get(below, 0)) < CAPACITY: continue
		var amount: int = mini(absi(difference) / 2, mini(int(remaining.get(source, 0)), CAPACITY - int(next.get(target, 0))))
		if amount <= 0: continue
		_transfer(next, source, target, amount)
		remaining[source] = int(remaining.get(source, 0)) - amount
	if next.size() > max_cells: return Codec.reject("water_cell_budget")
	var changed_set: Dictionary = {}
	for cell: Vector2i in water:
		if water[cell] != next.get(cell, 0): changed_set[cell] = true
	for cell: Vector2i in next:
		if next[cell] != water.get(cell, 0): changed_set[cell] = true
	var changed: Array = changed_set.keys()
	changed.sort_custom(_order)
	return {"ok":true,"error":"","water":next,"changed":changed,"operations":spent}
