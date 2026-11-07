extends SceneTree
const Routes=preload("res://scenarios/wet_ruins_routes.gd")
const Expedition=preload("res://runtime/expedition_session.gd")
const World=preload("res://runtime/world_session.gd")
const Runtime=preload("res://runtime/rule_runtime.gd")
const Flow=preload("res://runtime/water_flow.gd")
const Driver=preload("res://runtime/simulation_driver.gd")
const EnvironmentTests=preload("res://tests/test_environment.gd")
var passed: int=0
var failed: int=0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1; print("PASS: ",label)
	else: failed+=1; printerr("FAIL: ",label)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var first: Dictionary=Routes.setup()
	var second: Dictionary=Routes.setup()
	var other=Expedition.new()
	check(not other.attach(first.runtime,second.world,first.expedition._definition).ok,"expedition_rejects_mismatched_world_runtime")
	var driver=Driver.new()
	check(driver.bind_runtime(first.runtime).ok,"bind_review_driver")
	var legacy: Dictionary=first.runtime.checkpoint_value()
	legacy.erase("clock"); legacy.format="rw.simulation/0.1"
	check(first.runtime.load_checkpoint(JSON.stringify(legacy)).ok and first.runtime.clock_state().is_empty(),"legacy_restore_clears_previous_clock")
	var step: Variant=driver.process_delta(0.1)
	check(step is Dictionary and not step.get("ok",true),"driver_rejects_clock_removed_by_restore")
	driver.free()
	# 多组固定输入、每组30步；每一步容量、占位、总量与字典顺序均应一致。
	var invariants: bool=true
	for seed_value in range(32):
		var rng:=RandomNumberGenerator.new(); rng.seed=seed_value
		var blockers: Dictionary={}
		for x in range(-5,6): blockers[Vector2i(x,6)]=true
		for y in range(-6,7): blockers[Vector2i(-5,y)]=true; blockers[Vector2i(5,y)]=true
		var water: Dictionary={}; var original: int=0
		for y in range(-3,3):
			for x in range(-3,4):
				if rng.randi_range(0,3)==0:
					var units: int=rng.randi_range(1,1000)
					water[Vector2i(x,y)]=units; original+=units
		for tick in range(30):
			var keys: Array=water.keys(); keys.reverse(); var reordered: Dictionary={}
			for key in keys: reordered[key]=water[key]
			var a: Dictionary=Flow.step(water,blockers); var b: Dictionary=Flow.step(reordered,blockers)
			if not a.ok or not b.ok or a.water!=b.water: invariants=false; break
			water=a.water; var total: int=0
			for key in water:
				if blockers.has(key) or water[key]<1 or water[key]>1000: invariants=false
				total+=water[key]
			if total!=original: invariants=false
	check(invariants,"960_seeded_water_steps_preserve_mass_capacity_and_order")
	# 同一步两个通用泵竞争同一环境格，不会按先提交结果重新读取输入。
	var helper=EnvironmentTests.new()
	var fixture: Dictionary=helper.fixture(); var cat: Dictionary=helper.catalog()
	fixture.water[0].units=300
	fixture.terrain=[{"cell":[1,1],"material_id":"core:stone"}]
	var second_pump: Dictionary=fixture.entities.instances[0].duplicate(true)
	second_pump.id="creation:z-pump"; second_pump.location.cell=[2,0]
	fixture.entities.instances.append(second_pump)
	cat.rules={"user:environment_pump":[1]}
	for entity in fixture.entities.instances: entity.rules=[{"id":"user:environment_pump","version":1}]
	var world=World.new(cat); world.load_checkpoint(JSON.stringify(fixture)); var runtime=Runtime.new(cat,world)
	var pack: String=helper.pump_pack()
	check(runtime.install_pack(pack).ok,"publish_same_program_for_competing_pumps")
	runtime.configure_clock(8,4)
	var result: Dictionary=runtime.advance_tick()
	check(result.ok and result.errors.size()==1 and world.get_instance("creation:pump").state.water_units==250 and world.get_instance("creation:z-pump").state.water_units==0 and world.water_at(Vector2i(1,0))==50 and world.total_water_units()==300,"competing_environment_reads_are_snapshot_and_conservative")
	# 同一事务先移走，再把水倒进旧位置，应读取暂存占位而不是旧世界索引。
	fixture=helper.fixture(); fixture.entities.instances[0].state.water_units=100
	world=World.new(cat); world.load_checkpoint(JSON.stringify(fixture))
	result=world.apply_rule_commands("creation:pump",[{"op":"move","dx":-1,"dy":0},{"op":"release_environment_water","dx":1,"dy":0,"amount":25}])
	check(result.ok and world.water_at(Vector2i.ZERO)==25 and world.get_instance("creation:pump").state.water_units==75,"same_transaction_release_uses_staged_position")
	helper.free()
	print("ENVIRONMENT_EDGES_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
