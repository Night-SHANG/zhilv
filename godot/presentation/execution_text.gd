extends RefCounted
## 诊断文案只解释实际报告，不能生成玩法状态或把计划当提交。
const ERRORS:Dictionary={
	"formation_target_occupied":"凝结位置被地形、造物、角色或残水占用",
	"recover_material_mismatch":"相邻格不是指定的可回收材料",
	"material_not_formable":"材料没有受信的凝结能力，不能凭空造出石头",
	"invalid_material_direction":"需要选择相邻的一格，不能斜向或越格操作",
	"rule_move_collision":"移动目标被地形、角色、其他造物或水占用",
	"occupied_cell":"目标格已被占用",
	"insufficient_water_or_capacity":"来源水量不足，或接收容器容量不足",
	"environment_water_or_capacity":"环境水量不足，或目标格已满",
	"solid_water_target":"目标格是实心地形或其他造物",
	"rule_source_not_adjacent":"取水对象不在相邻格",
	"environment_source_not_adjacent":"水源不在相邻格",
	"missing_target_or_invalid_amount":"目标不存在或转移量不是正数",
	"missing_water_cell_or_invalid_amount":"没有找到水源，或取水量不是正数",
	"instruction_budget":"该造物本拍运算超限",
	"total_instruction_budget":"整拍运算超限，本拍全部撤销",
	"water_operation_budget":"水流运算超限，本拍全部撤销",
	"missing_input_port":"存在未连接的输入端口",
	"missing_reference_or_type_mismatch":"连线类型不匹配或引用丢失",
	"data_cycle":"数据连线形成循环",
	"module_collection_budget":"草稿尚无有效节点或超过数量限制",
	"runtime_busy":"世界正在提交状态，请在完成后重试",
	"out_of_reach":"造物距离太远，先走近再试",
	"occluded":"操作路径被墙挡住",
	"arithmetic_range":"数值计算超出允许范围"
}
static func reason(code:String)->String:return ERRORS.get(code,"未执行（"+code+"）")
static func outcome(value:Dictionary)->String:
	match value.get("status",""):
		"carried":return "背包中休眠；放到世界后才会运行"
		"unbound":return "尚未绑定规则；在织律台编织并应用"
		"not_run":return "等待下一拍；旧报告不会用于新规则"
		"waiting":return "条件未满足，本拍没有发出动作"
		"committed":return "本拍已提交 %d 个动作"%value.get("commands",0)
		"blocked":return "整组动作未提交："+reason(value.get("error","unknown"))
		"error":return "求值失败："+reason(value.get("error","unknown"))
		"aborted":return "整拍已撤销："+reason(value.get("error","unknown"))
	return "暂无运行信息"
static func live(value:Dictionary)->String:
	if not value.get("ok",false):return ""
	var historical:bool=value.status in ["waiting","committed","blocked","error","aborted"]
	return ("上一拍 #%d · "%value.tick if historical else "造物 · ")+outcome(value)
static func preview(value:Dictionary)->String:
	if not value.get("ok",false):return "预演未通过："+reason(value.get("error","unknown"))+"。真实世界未改变。"
	var text:String=outcome(value.outcome)
	# 预演中不能出现“已提交”而不说明只发生在副本。
	text=text.replace("本拍已提交","副本中可执行")
	return "预演：%s；水量 %d → %d。\n仅在副本计算，真实世界未改变。"%[text,value.before.state.water_units,value.after.state.water_units]
static func checks(value:Dictionary)->String:
	var lines:Array=["条件求值（不是提交结果）："]
	for check in value.get("checks",[]):
		lines.append("%s / %s：%s"%[check.module,check.node,"满足" if check.enabled else "不满足"])
	return "\n".join(lines)
