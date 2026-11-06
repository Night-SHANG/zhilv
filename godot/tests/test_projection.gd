extends SceneTree
## 程序生成的中性测试图块，仅检查原生TileMapLayer同步，不是美术样板。
const World = preload("res://runtime/world_session.gd")
const Projection = preload("res://runtime/terrain_projection.gd")
var passed: int = 0
var failed: int = 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var fixture_root: String = OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_root.path_join("catalog.json")))
	var text: String = FileAccess.get_file_as_string(fixture_root.path_join("world_checkpoint.json"))
	var w = World.new(catalog)
	check(w.load_checkpoint(text).ok, "projection_fixture_load")
	var layer := TileMapLayer.new()
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(16, 16)
	for id in range(2):
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		var atlas := TileSetAtlasSource.new()
		atlas.texture = ImageTexture.create_from_image(image)
		atlas.texture_region_size = Vector2i(16, 16)
		atlas.create_tile(Vector2i.ZERO)
		tiles.add_source(atlas, id)
	layer.tile_set = tiles
	root.add_child(layer)
	var p = Projection.new()
	var sources: Dictionary = {"core:stone": 0, "user:reservoir": 1}
	var window := Rect2i(-8, 0, 16, 8)
	check(p.bind_world(w, layer, sources, window).ok, "bind_real_tilemap")
	check(layer.get_cell_source_id(Vector2i(9, 3)) == 0, "terrain_projected")
	check(layer.get_cell_source_id(Vector2i(11, 2)) == 1, "creation_projected")
	check(w.mine(Vector2i(1, 3)).ok and layer.get_cell_source_id(Vector2i(9, 3)) == -1, "mine_updates_native_tilemap")
	check(w.build("core:stone", Vector2i(1, 3)).ok and layer.get_cell_source_id(Vector2i(9, 3)) == 0, "build_updates_native_tilemap")
	check(w.pickup("creation:001").ok and layer.get_cell_source_id(Vector2i(11, 2)) == -1, "pickup_removes_native_tile")
	check(w.place("creation:001", Vector2i(1, 2)).ok and layer.get_cell_source_id(Vector2i(9, 2)) == 1, "place_updates_native_tile")
	check(not w.build("core:stone", Vector2i(1, 2)).ok and layer.get_cell_source_id(Vector2i(9, 2)) == 1, "failed_command_keeps_projection")
	check(w.load_checkpoint(text).ok and layer.get_cell_source_id(Vector2i(9, 2)) == -1 and layer.get_cell_source_id(Vector2i(11, 2)) == 1, "reload_rebuilds_projection")
	check(not p.bind_world(w, layer, {"core:stone": 0}, window).ok, "missing_mapping_rejected")
	check(not p.bind_world(w, layer, {"core:stone": 9, "user:reservoir": 1}, window).ok, "invalid_tileset_source_rejected")
	check(w.pickup("creation:001").ok and layer.get_cell_source_id(Vector2i(11, 2)) == -1, "failed_rebind_preserves_old_binding")
	check(not p.set_window(Rect2i(0, 0, 0, 8)).ok, "empty_window_rejected")
	check(not p.set_window(Rect2i(0, 0, 65536, 8)).ok, "oversized_window_rejected")
	check(p.set_window(Rect2i(500, 0, 16, 8)).ok and layer.get_used_cells().is_empty(), "outside_window_not_rendered")
	var far: Dictionary = JSON.parse_string(text)
	far.actor.cell[0] += 100000
	for tile in far.terrain:
		tile.cell[0] += 100000
	far.entities.instances[0].location.cell[0] += 100000
	check(w.load_checkpoint(JSON.stringify(far)).ok, "large_logical_coordinate_load")
	check(p.set_window(Rect2i(100000, 0, 16, 8)).ok and layer.get_cell_source_id(Vector2i(1, 3)) == 0, "large_coordinate_uses_small_local_tile_coordinate")
	p.dispose()
	check(w.mine(Vector2i(100001, 3)).ok and layer.get_cell_source_id(Vector2i(1, 3)) == 0, "dispose_disconnects_projection")
	layer.free()
	print("PROJECTION_TEST_RESULT: ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
