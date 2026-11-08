extends SceneTree
## 对规则组合的边界/冲突/投影做原生测试，不把纯数据测试当游戏验证。
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")
const TileProjection = preload("res://runtime/terrain_projection.gd")
var passed: int = 0
var failed: int = 0
var catalog: Dictionary
var pack: Dictionary
var baseline: Dictionary

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func fixture(d: Dictionary = {}, p: Dictionary = {}) -> Array:
	var w = World.new(catalog)
	check(w.load_checkpoint(JSON.stringify(baseline if d.is_empty() else d)).ok, "edge_world_load")
	var r = Runtime.new(catalog, w)
	check(r.install_pack(JSON.stringify(pack if p.is_empty() else p)).ok, "edge_pack_install")
	return [w, r]

func node(id: String, op: String, inputs: Dictionary = {}, config: Dictionary = {}) -> Dictionary:
	return {"id":id,"op":op,"inputs":inputs,"config":config}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(1))
	var root: String = OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	catalog = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("rules_catalog.json")))
	var compiled: Dictionary = Compiler.compile_text(FileAccess.get_file_as_string(root.path_join("rules_pack.json")), catalog)
	if not compiled.ok:
		check(false, "compile_edge_fixture")
		finish()
		return
	pack = compiled.source
	var empty_world = World.new(catalog)
	baseline = empty_world.validate_checkpoint(FileAccess.get_file_as_string(root.path_join("rules_world.json"))).snapshot

	# 两个接收者在同一步快照中都看见150水；稳定ID仲裁只允许第一个取100。
	var d: Dictionary = baseline.duplicate(true)
	d.entities.instances[1].state.water_units = 150
	d.entities.instances[2].location.cell = [5,2]
	d.entities.instances[2].rules = [{"id":"user:absorb","version":1},{"id":"user:night_light","version":1}]
	var a: Array = fixture(d)
	var result: Dictionary = a[1].advance(true)
	check(result.ok and result.errors.size() == 1, "competing_transfers_one_failure")
	check(a[0].get_instance("creation:001").state.water_units == 100, "stable_id_wins_competition")
	check(a[0].get_instance("creation:002").state.water_units == 50, "competition_conserves_water")
	check(a[0].get_instance("creation:003").state.water_units == 0 and not a[0].get_instance("creation:003").state.light_on, "loser_plan_is_atomic")
	d.entities.instances.reverse()
	var b: Array = fixture(d)
	b[1].advance(true)
	check(b[0].get_instance("creation:001") == a[0].get_instance("creation:001") and b[0].get_instance("creation:003") == a[0].get_instance("creation:003"), "input_array_order_does_not_choose_winner")

	# 所有查询都读取步初快照；第一个造物移动后，第二个不会在本步看到新位置。
	d = baseline.duplicate(true)
	d.entities.instances[0].rules = [{"id":"user:drift","version":1}]
	d.entities.instances[1].location.cell = [4,3]
	d.entities.instances[1].state.water_units = 0
	d.entities.instances[1].rules = [{"id":"user:absorb","version":1}]
	d.entities.instances[0].state.water_units = 500
	d.entities.instances[2].location.cell = [8,4]
	a = fixture(d)
	a[1].advance(false)
	check(a[0].get_instance("creation:001").location.cell == [3,3] and a[0].get_instance("creation:002").state.water_units == 0, "same_tick_does_not_observe_prior_commit")
	# 下一步读取新位置，然后移动+取水竞争可能按当前邻接条件拒绝；这里验证查询机制，不强造成功。

	# 子模块默认参数可用；调用者无需把默认25写死进执行器。
	var p: Dictionary = pack.duplicate(true)
	for m in p.modules:
		if m.id == "user:absorb":
			for n in m.nodes:
				if n.op == "call":
					n.inputs.erase("amount")
	a = fixture({}, p)
	a[1].advance(false)
	check(a[0].get_instance("creation:001").state.water_units == 25, "submodule_default_parameter")

	# 逻辑组合控制移动：自身水量<常量，与昼夜组合，布尔否定也可复用。
	p = pack.duplicate(true)
	for m in p.modules:
		if m.id == "user:drift":
			m.nodes = [node("water","read_state",{}, {"field":"water_units"}), node("threshold","int",{}, {"value":50}), node("low","lt",{"a":"water","b":"threshold"}), node("night","is_night"), node("day","not",{"value":"night"}), node("gate","and",{"a":"low","b":"day"}), node("move","move",{"when":"gate"},{"dx":1,"dy":0})]
	d = baseline.duplicate(true)
	d.entities.instances[0].rules = [{"id":"user:drift","version":1}]
	d.entities.instances[1].location.cell = [7,2]
	a = fixture(d, p)
	a[1].advance(true)
	check(a[0].get_instance("creation:001").location.cell == [3,2], "combined_false_condition_skips_action")
	a[1].advance(false)
	check(a[0].get_instance("creation:001").location.cell == [4,2], "combined_true_condition_moves")

	# 加法越界必须作为执行失败，且不能提交同一造物前面已经计划的动作。
	p = pack.duplicate(true)
	for m in p.modules:
		if m.id == "user:absorb":
			m.nodes = [node("yes","bool",{}, {"value":true}), node("max","int",{}, {"value":1000000000}), node("sum","add",{"a":"max","b":"max"}), node("call","call",{"when":"yes","amount":"sum"},{"id":"user:transfer","version":1})]
	a = fixture({}, p)
	result = a[1].advance(true)
	check(result.errors.size() == 1 and result.errors[0].error == "arithmetic_range", "bounded_integer_arithmetic")
	check(a[0].get_instance("creation:001").state.water_units == 0 and not a[0].get_instance("creation:001").state.light_on, "arithmetic_failure_has_no_side_effects")

	# 大图、非法端口、调用深度在编译阶段拒绝。
	p = pack.duplicate(true)
	for i in range(65):
		p.modules[0].nodes.append(node("extra" + str(i), "bool", {}, {"value":true}))
	check(not Compiler.compile_value(p, catalog).ok, "node_count_limit")
	p = pack.duplicate(true)
	p.modules[0].parameters = {"when":{"type":"bool","default":true}}
	check(not Compiler.compile_value(p, catalog).ok, "reserved_parameter_name")
	var deep_catalog: Dictionary = catalog.duplicate(true)
	var deep: Dictionary = {"format":"rw.rules/0.1","modules":[]}
	for i in range(9):
		var id: String = "test:chain" + str(i)
		deep_catalog.rules[id] = [1]
		var nodes: Array = [node("yes","bool",{}, {"value":true})]
		var effect: Dictionary = node("effect","set_light",{"when":"yes","value":"yes"}) if i == 8 else node("effect","call",{"when":"yes"},{"id":"test:chain"+str(i+1),"version":1})
		nodes.append(effect)
		deep.modules.append({"id":id,"version":1,"parameters":{},"nodes":nodes,"effects":["effect"]})
	check(not Compiler.compile_value(deep, deep_catalog).ok, "call_depth_limit")

	# 真正TileMapLayer接收自主移动产生的同一个世界提交事件。
	d = baseline.duplicate(true)
	d.entities.instances[0].rules = [{"id":"user:drift","version":1}]
	a = fixture(d)
	var layer := TileMapLayer.new()
	root_node_add(layer)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(8,8)
	var mappings: Dictionary = {}
	var next: int = 0
	for material in catalog.materials:
		var image := Image.create(8,8,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		var atlas := TileSetAtlasSource.new()
		atlas.texture = ImageTexture.create_from_image(image)
		atlas.texture_region_size = Vector2i(8,8)
		atlas.create_tile(Vector2i.ZERO)
		tiles.add_source(atlas, next)
		mappings[material] = next
		next += 1
	layer.tile_set = tiles
	var projection = TileProjection.new()
	check(projection.bind_world(a[0], layer, mappings, Rect2i(0,0,16,16)).ok, "bind_automatic_rule_projection")
	a[1].advance(false)
	check(layer.get_cell_source_id(Vector2i(3,2)) == -1 and layer.get_cell_source_id(Vector2i(3,3)) == mappings["user:reservoir"], "automatic_move_updates_native_map")
	projection.dispose()
	layer.free()
	finish()

func root_node_add(node_to_add: Node) -> void:
	get_root().add_child(node_to_add)

func finish() -> void:
	print("RULE_EDGES_TEST_RESULT: ", passed, " passed; ", failed, " failed")
	quit(0 if failed == 0 else 1)
