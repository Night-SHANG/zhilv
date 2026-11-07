extends RefCounted
## 受信载体配方只定义物理容器，不枚举玩家的行为组合。
## 复用既有材料、规则与库存；目录的副本不会改变运行时权威定义。
const RECIPES: Dictionary={
	"carrier:vessel":{"name":"储水容器","cost":{"core:stone":4},"material_id":"user:reservoir","capacity_units":6000,"rules":[]},
	"carrier:lamp":{"name":"便携夜灯","cost":{"core:stone":2},"material_id":"user:crystal","capacity_units":1,"rules":[{"id":"core:portable_lamp","version":1}]}
}
static func recipe(id:Variant)->Dictionary:
	if not id is String or not RECIPES.has(id):return {}
	return RECIPES[id].duplicate(true)
static func keys()->Array:return RECIPES.keys()
static func label(entity:Dictionary)->String:
	if entity.is_empty():return "尚未选择造物"
	if entity.id=="creation:plot":return "营地蓄水器"
	var title:String="便携夜灯" if entity.material_id=="user:crystal" else "储水容器"
	if entity.id.begins_with("creation:made_"):return title+" #"+entity.id.trim_prefix("creation:made_")
	return title+" · "+entity.id.get_slice(":",1)
