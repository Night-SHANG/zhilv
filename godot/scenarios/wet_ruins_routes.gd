extends RefCounted
## 三条自动操作回放只用于验收/演示；不是游戏逻辑里的专用“遗迹解法”。
## 世界与目标完全相同，所有操作调用正式创作/交互接口，不直接改存档作弊。
const Codec = preload("res://runtime/snapshot_codec.gd")
const WorldCodec = preload("res://runtime/world_codec.gd")
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")
const Draft = preload("res://runtime/rule_draft.gd")
const Expedition = preload("res://runtime/expedition_session.gd")
const Files = preload("res://runtime/checkpoint_files.gd")

static func setup(reverse_water: bool=false) -> Dictionary:
	return preload("res://runtime/scenario_loader.gd").load_scenario("res://content/wet_ruins.json",reverse_water)

static func _node(id: String,op: String,config: Dictionary={}) -> Dictionary:
	return {"id":id,"op":op,"config":config,"inputs":{}}

static func author_pump(runtime) -> Dictionary:
	var draft=Draft.new()
	var started: Dictionary=draft.start("user:reusable_water_pump",1)
	if not started.ok: return started
	for node in [_node("source","neighbor_water"),_node("available","water_units"),_node("water","read_state",{"field":"water_units"}),_node("capacity","read_state",{"field":"capacity_units"}),_node("room","sub"),_node("rate","int",{"value":250}),_node("limited","min"),_node("amount","min"),_node("zero","int",{"value":0}),_node("can_take","lt"),_node("take","take_environment_water")]:
		var added: Dictionary=draft.upsert_node(node)
		if not added.ok: return added
	for edge in [["available","source","source"],["room","a","capacity"],["room","b","water"],["limited","a","rate"],["limited","b","available"],["amount","a","limited"],["amount","b","room"],["can_take","a","zero"],["can_take","b","amount"],["take","when","can_take"],["take","source","source"],["take","amount","amount"]]:
		var connected: Dictionary=draft.connect_input(edge[0],edge[1],edge[2])
		if not connected.ok: return connected
	var effects: Dictionary=draft.set_effects(["take"])
	if not effects.ok: return effects
	return runtime.publish_pack(draft.pack_json(),{"creation:vessel":[{"id":"user:reusable_water_pump","version":1}]})

static func _walk(e,w,x: int) -> Dictionary:
	for i in range(32):
		if w.actor_cell().x==x: return {"ok":true,"error":""}
		var result: Dictionary=e.act({"op":"move","delta":[signi(x-w.actor_cell().x),0]})
		if not result.ok: return Codec.reject("walk_"+str(w.actor_cell())+"_"+result.error)
	return Codec.reject("walk_step_budget")

static func _wait(e,count: int) -> Dictionary:
	for i in range(count):
		var result: Dictionary=e.act({"op":"advance"})
		if not result.ok: return result
		if not result.get("errors",[]).is_empty(): return Codec.reject("unexpected_rule_failure:"+str(result.errors))
	return {"ok":true,"error":""}

static func _manual_collect(e,w,target: int,from_sump: bool=false) -> Dictionary:
	for i in range(160):
		var held: int=w.get_instance("creation:vessel").state.water_units
		if held>=target: return {"ok":true,"error":""}
		var cells: Array=w.water_cells()
		cells.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y<b.y or (a.y==b.y and a.x<b.x))
		for cell: Vector2i in cells:
			if from_sump and cell.y<1: continue
			if not w._access(cell).ok: continue
			var amount: int=mini(target-held,w.water_at(cell))
			var result: Dictionary=e.act({"op":"collect","id":"creation:vessel","cell":[cell.x,cell.y],"amount":amount})
			if not result.ok: return result
			break
		var advanced: Dictionary=_wait(e,1)
		if not advanced.ok: return advanced
	return Codec.reject("manual_collection_budget")

static func run(route: String,restore_midway: bool=false,reverse_water: bool=false) -> Dictionary:
	if not route in ["manual","drainage","authored"]: return Codec.reject("unknown_demo_route")
	var setup_result: Dictionary=setup(reverse_water)
	if not setup_result.ok: return setup_result
	var w=setup_result.world; var r=setup_result.runtime; var e=setup_result.expedition
	var initial_tiles: int=w.rule_view().terrain.size()
	var result: Dictionary
	# 同一初始环境确实阻挡直接穿行，不把目标标记预设为完成。
	result=_walk(e,w,1)
	if not result.ok: return result
	if e.act({"op":"move","delta":[1,0]}).ok: return Codec.reject("initial_flood_did_not_block")
	result=_walk(e,w,0)
	if not result.ok: return result
	match route:
		"manual":
			result=_manual_collect(e,w,5000)
			if not result.ok: return result
			result=_wait(e,80)
		"drainage":
			result=_walk(e,w,1)
			if not result.ok: return result
			result=e.act({"op":"mine","cell":[1,1]})
			if not result.ok: return result
			result=_wait(e,160)
			if not result.ok: return result
			result=_manual_collect(e,w,500,true)
		"authored":
			result=e.act({"op":"place","id":"creation:vessel","cell":[1,0]})
			if not result.ok: return result
			result=author_pump(r)
			if not result.ok: return result
			for tick in range(256):
				if w.get_instance("creation:vessel").state.water_units>=5000: break
				result=_wait(e,1)
				if not result.ok: return result
				if restore_midway and tick==5:
					var files=Files.new(); var slot: String="ruins_mid_"+str(OS.get_process_id())
					result=files.save(e,slot)
					if not result.ok: return result
					var resumed: Dictionary=setup()
					if not resumed.ok: return resumed
					result=files.load_into(resumed.expedition,slot)
					for suffix in ["", ".bak", ".tmp"]:
						var path: String=files.slot_path(slot)+suffix
						if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
					if not result.ok: return result
					w=resumed.world; r=resumed.runtime; e=resumed.expedition
			if w.get_instance("creation:vessel").state.water_units<5000: return Codec.reject("pump_route_budget")
			result=e.act({"op":"pickup","id":"creation:vessel"})
			if not result.ok: return result
			result=_wait(e,80)
	if not result.ok: return result
	# 普通便携灯本身也是内容规则；目标只看照明、位置和水位，不检查用了哪个图。
	result=_walk(e,w,6)
	if not result.ok: return result
	result=e.act({"op":"place","id":"creation:lamp","cell":[9,-1]})
	if not result.ok: return result
	result=_wait(e,1)
	if not result.ok: return result
	result=_walk(e,w,8)
	if not result.ok: return result
	var visited_lit: bool=w.has_light_at(Vector2i(8,0),r.clock_state().night) and e.status().completed.has("goal:ruins")
	result=_walk(e,w,-2)
	if not result.ok: return result
	result=e.act({"op":"pour","source":"creation:vessel","target":"creation:plot","amount":500})
	if not result.ok: return result
	return {"ok":true,"error":"","route":route,"checkpoint":e.checkpoint_json(),"completed":e.status().completed,"total_water":w.total_water_units(),"plot_water":w.get_instance("creation:plot").state.water_units,"mined":initial_tiles-w.rule_view().terrain.size(),"authored_rule":route=="authored","visited_lit":visited_lit,"ticks":r.clock_state().tick}
