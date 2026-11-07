extends RefCounted
## 受信任的打包关卡装配器。主程序和自动回放使用同一构造路径。
const Codec = preload("res://runtime/snapshot_codec.gd")
const WC = preload("res://runtime/world_codec.gd")
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")
const Expedition = preload("res://runtime/expedition_session.gd")

static func load_scenario(path: String, reverse_water: bool=false) -> Dictionary:
	if not path.begins_with("res://content/") or not path.ends_with(".json") or path.contains(".."):
		return Codec.reject("scenario_path")
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>Codec.MAX_BYTES: return Codec.reject("scenario_unreadable")
	var text: String=file.get_as_text(); file.close()
	var error: String=Codec._lexical_error(text)
	if not error.is_empty(): return Codec.reject(error)
	var parser:=JSON.new()
	if parser.parse(text)!=OK: return Codec.reject("scenario_json")
	var data: Variant=parser.data
	if not Codec._shape(data,["format","definition","catalog","clock","world","rules"]) or data.format!="rw.scenario/0.1":
		return Codec.reject("scenario_fields")
	if not data.world is Dictionary or not data.catalog is Dictionary or not data.clock is Dictionary:
		return Codec.reject("scenario_fields")
	if reverse_water and data.world.get("water") is Array: data.world.water.reverse()
	var normalized: Dictionary=WC.decode_value(data.world,data.catalog)
	if not normalized.ok: return normalized
	var w=World.new(data.catalog)
	var result: Dictionary=w.load_checkpoint(JSON.stringify(normalized.snapshot))
	if not result.ok: return result
	var r=Runtime.new(data.catalog,w)
	var program: Dictionary=Compiler.compile_value(data.rules,data.catalog)
	if not program.ok: return program
	result=r.install_pack(JSON.stringify(program.source))
	if not result.ok: return result
	if not Codec._shape(data.clock,["cycle_ticks","daylight_ticks"]) or not Codec._integer(data.clock.cycle_ticks,2,1000000) or not Codec._integer(data.clock.daylight_ticks,1,int(data.clock.cycle_ticks)-1):
		return Codec.reject("scenario_clock")
	result=r.configure_clock(int(data.clock.cycle_ticks),int(data.clock.daylight_ticks))
	if not result.ok: return result
	var e=Expedition.new(); result=e.attach(r,w,data.definition)
	if not result.ok: return result
	return {"ok":true,"error":"","world":w,"runtime":r,"expedition":e}
