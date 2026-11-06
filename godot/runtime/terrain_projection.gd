extends RefCounted
## 世界数据的只读投影。TileMapLayer坐标为窗口内局部坐标，不承担持久化真相。
## 调用方负责摄像机/图层定位；只允许已审查TileSet，不加载律卷提供的脚本资源。
const Codec = preload("res://runtime/snapshot_codec.gd")
var _world
var _layer: TileMapLayer
var _sources: Dictionary = {}
var _window: Rect2i

func _valid_window(window: Rect2i) -> bool:
	return window.size.x > 0 and window.size.y > 0 and window.size.x <= 1024 and window.size.y <= 1024

func bind_world(world, layer: TileMapLayer, sources: Dictionary, window: Rect2i) -> Dictionary:
	if world == null or not is_instance_valid(layer) or layer.tile_set == null or not _valid_window(window):
		return Codec.reject("invalid_projection_binding")
	for material in world.material_ids():
		var source_id: Variant = sources.get(material)
		if typeof(source_id) != TYPE_INT or not layer.tile_set.has_source(source_id):
			return Codec.reject("missing_visual_mapping")
		var source = layer.tile_set.get_source(source_id)
		if not source is TileSetAtlasSource or not source.has_tile(Vector2i.ZERO):
			return Codec.reject("unsupported_visual_source")
	dispose()
	_world = world
	_layer = layer
	_sources = sources.duplicate()
	_window = window
	_world.committed.connect(_on_committed)
	_world.reloaded.connect(_on_reloaded)
	return rebuild()

func set_window(window: Rect2i) -> Dictionary:
	if not _valid_window(window) or _world == null or not is_instance_valid(_layer):
		return Codec.reject("invalid_projection_window")
	_window = window
	return rebuild()

func rebuild() -> Dictionary:
	if _world == null or not is_instance_valid(_layer):
		return Codec.reject("projection_not_bound")
	_layer.clear()
	for cell: Vector2i in _world.occupied_cells():
		_paint(cell)
	_layer.update_internals()
	return {"ok": true, "error": ""}

func _paint(cell: Vector2i) -> void:
	if not _window.has_point(cell):
		return
	var local_cell: Vector2i = cell - _window.position
	var material: String = _world.material_at(cell)
	if material.is_empty():
		_layer.erase_cell(local_cell)
	else:
		_layer.set_cell(local_cell, _sources[material], Vector2i.ZERO)

func _on_committed(cells: Array) -> void:
	if not is_instance_valid(_layer):
		return
	for cell: Vector2i in cells:
		_paint(cell)
	_layer.update_internals()

func _on_reloaded() -> void:
	rebuild()

func dispose() -> void:
	if _world != null:
		if _world.committed.is_connected(_on_committed):
			_world.committed.disconnect(_on_committed)
		if _world.reloaded.is_connected(_on_reloaded):
			_world.reloaded.disconnect(_on_reloaded)
	_world = null
	_layer = null
	_sources = {}
