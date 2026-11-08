extends PanelContainer
## 真实GraphEdit编辑前端；每一条连线对应RuleDraft的输入引用，不执行宿主代码。
signal apply_requested
signal export_requested
signal word_export_requested(entry: Dictionary)
signal import_requested
signal close_requested
signal message(text: String, bad: bool)
const Style = preload("res://presentation/ui_theme.gd")
const Document = preload("res://presentation/loom_document.gd")
const Codec = preload("res://runtime/snapshot_codec.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")
const Feedback=preload("res://presentation/execution_text.gd")
const TYPES = {"bool":0,"int":1,"ref":2,"cell_ref":3,"effect":4}
const COLORS = {"bool":Color("bb9bd9"),"int":Color("e6ba72"),"ref":Color("9ac490"),"cell_ref":Color("71c9d2"),"effect":Color("f0b17b")}
const TITLES = {"cell_empty":"相邻格可用","terrain_is":"相邻地形匹配","form_material":"凝结地块","recover_material":"回收地块水","param":"公开参数","bool":"开关常量","int":"数值常量","is_night":"是否夜晚","is_ambient_dark":"环境是否昏暗","read_state":"读取自身状态","neighbor":"相邻造物","exists":"造物存在","neighbor_water":"相邻环境水","water_exists":"水源存在","water_units":"读取水量","lt":"小于比较","min":"取较小值","add":"相加","sub":"相减","and":"同时满足","not":"条件取反","set_light":"设置发光","move":"移动一格","take_water":"从造物取水","take_environment_water":"从环境取水","release_environment_water":"排水到环境","call":"调用已发布模块"}
const PORTS = {"when":"执行条件","value":"值 / 条件","a":"输入 A","b":"输入 B","source":"来源","amount":"数量"}
var document=Document.new()
var runtime
var target_id: String=""
var title_label: Label
var state_label: Label
var summary: Label
var validation: Label
var preview_label: Label
var amount: SpinBox
var preset_box: OptionButton
var cards: VBoxContainer
var advanced: Window
var graph: GraphEdit
var palette: OptionButton
var _content_scroll: ScrollContainer
var word_name: LineEdit
var word_choices: OptionButton
var word_status: Label
var word_publish: Button
var word_append: Button
var word_edit: Button
var word_export: Button
var _syncing: bool=false
var _queued: bool=false
var _positions: Dictionary={}
var _node_ports: Dictionary={}
var _graph_structure: Array=[]

func _ready() -> void:
	custom_minimum_size=Vector2(390,0)
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",8);add_child(col)
	var header:=HBoxContainer.new();col.add_child(header)
	title_label=Style.label("织律台",22,Style.GOLD);title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title_label)
	header.add_child(Style.button("收起 Tab",func(): close_requested.emit()))
	state_label=Style.label("储水容器",14);col.add_child(state_label)
	col.add_child(Style.note("世界暂停 · 草稿不会自动改变造物"))
	col.add_child(HSeparator.new())
	var scroll:=ScrollContainer.new();_content_scroll=scroll;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.custom_minimum_size.y=120;col.add_child(scroll)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",10);scroll.add_child(content)
	content.add_child(Style.label("起始结构 · 可以拆开重组",14,Style.MUTED))
	var start_row:=HBoxContainer.new();content.add_child(start_row)
	preset_box=OptionButton.new();preset_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for text in ["限量吸水","暗处发光","向右排水","空白规则","向上凝结地块","向上回收地块水"]:preset_box.add_item(text)
	start_row.add_child(preset_box);start_row.add_child(Style.button("载入草稿",_preset_selected))
	var rate_row:=HBoxContainer.new();content.add_child(rate_row)
	rate_row.add_child(Style.label("每次取 / 排水",14,Style.MUTED))
	amount=SpinBox.new();amount.min_value=1;amount.max_value=1000;amount.step=1;amount.value=100;amount.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	amount.value_changed.connect(_rate_changed);rate_row.add_child(amount)
	_build_word_controls(content)
	cards=VBoxContainer.new();content.add_child(cards)
	summary=Style.note("");content.add_child(summary)
	col.add_child(HSeparator.new())
	var history:=HBoxContainer.new();col.add_child(history)
	history.add_child(Style.button("撤销",func(): _result(document.undo())))
	history.add_child(Style.button("重做",func(): _result(document.redo())))
	var edit:=Style.button("节点与连线",open_advanced);edit.name="OpenGraph";edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;history.add_child(edit)
	validation=Style.note("先检查，再应用。");validation.custom_minimum_size.y=38;col.add_child(validation)
	preview_label=validation;preview_label.name="PreviewResult"
	var actions:=HBoxContainer.new();col.add_child(actions)
	actions.add_child(Style.button("校验草稿",validate_graph))
	var trial:=Style.button("预演一拍",preview_graph);trial.name="PreviewRule";actions.add_child(trial)
	var apply:=Style.button("应用到造物",func(): apply_requested.emit());apply.name="ApplyRule";apply.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	apply.add_theme_color_override("font_color",Style.GOLD);actions.add_child(apply)
	var share:=HBoxContainer.new();col.add_child(share)
	share.add_child(Style.button("导出律卷",func(): export_requested.emit()))
	share.add_child(Style.button("导入律卷",func(): import_requested.emit()))
	col.add_child(Style.note("应用替换所选造物的规则；导入不自动绑定。"))
	document.changed.connect(_schedule_refresh)
	_make_advanced()
func configure(r, id: String, display_name: String) -> void:
	runtime=r;target_id=id
	word_name.text="";word_status.text="保存到词条库不应用到造物；追加调用后仍需检查和应用。"
	title_label.text="织律台 · "+display_name
	state_label.text="目标："+id
	var graph_id: String="user:loom_"+id.replace(":","_")
	document.start(graph_id)
	var instance: Dictionary=r._world.get_instance(id)
	if not instance.is_empty() and not instance.rules.is_empty():
		var ref: Dictionary=instance.rules.back()
		var found: Dictionary=r.rule_definition(ref.id,int(ref.version))
		if found.ok: document.load_module(found.module,ref.id if ref.id.begins_with("user:") else graph_id)
	else: document.preset("pump",int(amount.value))
	_positions.clear();_refresh()
func _preset_selected() -> void:
	var kinds: Array=["pump","lamp","release","blank","form","recover"]
	_result(document.preset(kinds[preset_box.selected],int(amount.value)))
	_positions.clear()
func _rate_changed(value: float) -> void:
	if _syncing: return
	var rate: Dictionary=document.node("rate")
	if rate.is_empty(): return
	if rate.op=="param": _result(document.set_parameter_default(rate.config.name,int(value)))
	elif rate.op=="int": _result(document.change_config("rate",{"value":int(value)}))
func _result(result: Dictionary) -> void:
	if not result.ok:message.emit("操作未完成："+_error_text(str(result.error)),true)
func _schedule_refresh() -> void:
	if _queued:return
	_queued=true;call_deferred("_refresh")
func _refresh() -> void:
	_queued=false
	if not is_inside_tree():return
	_syncing=true
	preview_label.text="草稿可预演；只有应用后才会改变正式行为。"
	preview_label.tooltip_text=""
	var m: Dictionary=document.snapshot()
	for child in cards.get_children():cards.remove_child(child);child.queue_free()
	var groups: Array=[[],[],[]]
	for n in m.get("nodes",[]):
		var title: String=TITLES.get(n.op,n.op)
		if n.op in ["set_light","move","take_water","take_environment_water","release_environment_water","form_material","recover_material","call"]:groups[2].append(title)
		elif n.op in ["lt","min","add","sub","and","not","exists","water_exists","cell_empty","terrain_is"]:groups[1].append(title)
		else:groups[0].append(title)
	for index in 3:
		var card:=PanelContainer.new();card.add_theme_stylebox_override("panel",Style.box(Style.BG,Style.EDGE,8,10));cards.add_child(card)
		var text_col:=VBoxContainer.new();card.add_child(text_col)
		text_col.add_child(Style.label(["01  感知与输入","02  判断与计算","03  改变世界"][index],16,[Style.AQUA,Color("bb9bd9"),Style.GOLD][index]))
		var labels: Array=[]
		for t in groups[index]:
			if not labels.has(t):labels.append(t)
		text_col.add_child(Style.note(" · ".join(labels) if not labels.is_empty() else "尚无节点，在高级编辑器中添加。"))
	var rate: Dictionary=document.node("rate")
	amount.editable=not rate.is_empty() and (rate.op=="int" or (rate.op=="param" and m.parameters.get(rate.config.get("name",""),{}).get("type")=="int"))
	if amount.editable:
		var number: int=rate.config.value if rate.op=="int" else m.parameters[rate.config.name].default
		amount.min_value=mini(1,number);amount.max_value=maxi(1000,number);amount.value=number
	_refresh_word_list()
	summary.text="%d 个节点  ·  %d 个动作  ·  %s"%[m.get("nodes",[]).size(),m.get("effects",[]).size(),"草稿有修改" if document.dirty else "与已载入内容一致"]
	validation.text="编辑只影响草稿；应用前会完整检查类型和依赖。"
	if is_instance_valid(advanced) and advanced.visible: _rebuild_graph()
	_syncing=false
func validate_graph() -> void:
	if runtime==null:return
	validation.tooltip_text=""
	var result: Dictionary=document.validate(runtime)
	validation.text="规则校验通过。应用后开始使用新版本。" if result.ok else "规则未通过："+_error_text(result.error)
	validation.add_theme_color_override("font_color",Style.AQUA if result.ok else Style.BAD)
func preview_graph() -> Dictionary:
	if runtime==null:return {"ok":false,"error":"runtime_not_ready"}
	var candidate:Dictionary=document.candidate(runtime)
	var result:Dictionary=candidate
	if candidate.ok:
		result=runtime.preview_rule_tick(target_id,candidate.text,{"id":candidate.module.id,"version":candidate.module.version})
	preview_label.text=Feedback.preview(result)
	preview_label.tooltip_text=Feedback.checks(result.get("outcome",{})) if result.ok else ""
	var failed:bool=not result.ok or result.get("outcome",{}).get("status","") in ["blocked","error","aborted"]
	preview_label.add_theme_color_override("font_color",Style.BAD if failed else Style.AQUA)
	return result
func _error_text(code: String) -> String:
	return {"reserved_rule_namespace":"不能使用这个名称，请填写 user:英文名","parameter_already_exists":"参数名已存在，请换一个名称","parameter_name":"参数名需为英文、数字或下划线，不能使用 when","parameter_budget":"已达到八个公开参数上限","node_budget":"组合后超过当前节点数量上限","effect_budget":"组合后超过当前动作数量上限","expose_requires_constant":"只能将数值或开关常量公开为参数","missing_rule_version":"找不到这个词条版本","missing_input_port":"存在未连接的输入端口","missing_reference_or_type_mismatch":"连线类型不匹配或引用已丢失","data_cycle":"数据连线形成循环","module_collection_budget":"空白规则尚无有效节点","referenced_draft_node":"该节点仍被引用，请先断开连线","version_content_conflict":"旧版本不可覆盖，请发布新版本"}.get(code,code)
func _make_advanced() -> void:
	advanced=Window.new();advanced.title="织律台 · 节点与连线";advanced.size=Vector2i(1080,680);advanced.min_size=Vector2i(760,500)
	advanced.transient=true;advanced.exclusive=true;advanced.visible=false;advanced.theme=Style.make();add_child(advanced)
	advanced.close_requested.connect(func():advanced.hide())
	var root:=VBoxContainer.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);advanced.add_child(root)
	var bar:=HBoxContainer.new();root.add_child(bar)
	palette=OptionButton.new();palette.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for op in TITLES:
		if op=="param": continue # 只能从已定义的常量公开，避免新建无签名参数。
		palette.add_item(TITLES[op]);palette.set_item_metadata(palette.item_count-1,op)
	bar.add_child(palette);var add_button:=Style.button("添加节点",_add_node);add_button.name="AddNode";bar.add_child(add_button)
	bar.add_child(Style.button("撤销",func():_result(document.undo())))
	bar.add_child(Style.button("校验",validate_graph));bar.add_child(Style.button("完成编辑",func():advanced.hide()))
	graph=GraphEdit.new();graph.size_flags_vertical=Control.SIZE_EXPAND_FILL;graph.right_disconnects=true;graph.minimap_enabled=false
	graph.show_arrange_button=true;graph.zoom_min=0.35;graph.zoom=0.68;graph.add_theme_stylebox_override("panel",Style.box(Style.BG,Style.EDGE,0,0));root.add_child(graph)
	graph.connection_request.connect(_connect);graph.disconnection_request.connect(_disconnect)
	graph.delete_nodes_request.connect(_delete)
	root.add_child(Style.note("拖动端口连线；右键断线；选中节点后 Delete 删除。未连接输入会阻止发布。动作按创建顺序执行。"))
func open_advanced() -> void:
	advanced.popup_centered(Vector2i(1080,680));_rebuild_graph()
func _default_config(op: String) -> Dictionary:
	match op:
		"int":return {"value":100}
		"bool":return {"value":true}
		"read_state":return {"field":"water_units"}
		"neighbor":return {"material":""}
		"cell_empty":return {"dx":0,"dy":-1}
		"terrain_is","form_material","recover_material":return {"dx":0,"dy":-1,"material":"core:water_crystal"}
		"move","release_environment_water":return {"dx":1,"dy":0}
		"call":
			if runtime!=null and not runtime._program.source.modules.is_empty():
				var m: Dictionary=runtime._program.source.modules[0];return {"id":m.id,"version":m.version}
	return {}
func _add_node() -> void:
	var op: String=palette.get_item_metadata(palette.selected)
	_result(document.add(op,_default_config(op)))
func _sig(n: Dictionary) -> Dictionary:
	return Compiler.signature(n.duplicate(true),document.snapshot(),runtime._program.modules,runtime._catalog)
func _connect(from: StringName,_fp: int,to: StringName,tp: int) -> void:
	var ports: Array=_node_ports.get(String(to),[])
	if tp>=0 and tp<ports.size():_result(document.connect_nodes(String(to),ports[tp],String(from)))
func _disconnect(_from: StringName,_fp: int,to: StringName,tp: int) -> void:
	var ports: Array=_node_ports.get(String(to),[])
	if tp>=0 and tp<ports.size():_result(document.disconnect_port(String(to),ports[tp]))
func _delete(ids: Array[StringName]) -> void:
	for id in ids:_result(document.remove(String(id)))
func _remember_position(n: GraphNode) -> void:_positions[String(n.name)]=n.position_offset
func _rebuild_graph() -> void:
	if runtime==null:return
	var structure: Array=[document.snapshot().id]
	for data in document.snapshot().get("nodes",[]):
		var signature: Dictionary=_sig(data)
		structure.append([data.id,data.op,signature.get("inputs",{}),data.config if data.op=="call" else {}])
	var arrange: bool=structure!=_graph_structure
	_graph_structure=structure.duplicate(true)
	for child in graph.get_children():
		if child is GraphNode:
			_positions[String(child.name)]=child.position_offset;graph.remove_child(child);child.queue_free()
	graph.clear_connections();_node_ports.clear()
	var m: Dictionary=document.snapshot();var i: int=0
	var levels: Dictionary={};var depths: Dictionary={}
	for iteration in m.get("nodes",[]).size()+1:
		for data in m.get("nodes",[]):
			if levels.has(data.id):continue
			var level: int=0;var ready: bool=true
			for ref in data.inputs.values():
				if not levels.has(ref):ready=false
				else:level=maxi(level,levels[ref]+1)
			if ready:levels[data.id]=level

	for data in m.get("nodes",[]):
		var sig: Dictionary=_sig(data)
		if not sig.ok:sig={"output":"effect","inputs":{}}
		var n:=GraphNode.new();n.name=data.id;n.title=TITLES.get(data.op,data.op)+" · "+data.id
		var level: int=levels.get(data.id,0);var rank: int=depths.get(level,0);depths[level]=rank+1
		n.custom_minimum_size=Vector2(220,0);n.position_offset=_positions.get(data.id,Vector2(level*270,rank*160)+Vector2(40,85));i+=1
		n.add_theme_stylebox_override("panel",Style.box(Style.PANEL,Style.EDGE,6,8))
		n.add_theme_stylebox_override("panel_selected",Style.box(Style.PANEL,Style.AQUA,6,8))
		n.add_theme_stylebox_override("titlebar",Style.box(Style.PANEL_ALT,Style.EDGE,6,8))
		graph.add_child(n);n.position_offset_changed.connect(_remember_position.bind(n))
		var ports: Array=sig.inputs.keys();_node_ports[data.id]=ports
		var rows: int=maxi(1,ports.size())
		for row in rows:
			var line:=Style.label(PORTS.get(ports[row],ports[row]) if row<ports.size() else "输出",14);line.custom_minimum_size.y=26;n.add_child(line)
			var input_type: String=sig.inputs[ports[row]] if row<ports.size() else "bool"
			n.set_slot(row,row<ports.size(),TYPES.get(input_type,0),COLORS.get(input_type,Style.AQUA),row==0 and sig.output!="effect",TYPES.get(sig.output,4),COLORS.get(sig.output,Style.GOLD))
		_config_ui(n,data)
	for data in m.get("nodes",[]):
		for port in data.inputs:
			var idx: int=_node_ports.get(data.id,[]).find(port)
			if idx>=0 and graph.has_node(NodePath(data.inputs[port])):graph.connect_node(data.inputs[port],0,data.id,idx)
	# 原生自动排列按真实节点尺寸布局；只在拓扑/签名改变时执行，不打乱数值编辑时的手工位置。
	if arrange: graph.call_deferred("arrange_nodes")
func _config_ui(n: GraphNode,data: Dictionary) -> void:
	var id: String=data.id
	match data.op:
		"int":
			var spin:=SpinBox.new();spin.min_value=-Codec.MAX_QUANTITY;spin.max_value=Codec.MAX_QUANTITY;spin.step=1;spin.value=data.config.value;n.add_child(spin)
			spin.value_changed.connect(func(v: float):_result(document.change_config(id,{"value":int(v)})))
		"bool":
			var b:=CheckBox.new();b.text="真 / 开启";b.button_pressed=data.config.value;n.add_child(b)
			b.toggled.connect(func(v: bool):_result(document.change_config(id,{"value":v})))
		"read_state":
			var o:=OptionButton.new();var values: Array=["water_units","capacity_units","light_on"]
			for name in ["自身水量","容器容量","发光状态"]:o.add_item(name)
			o.select(maxi(0,values.find(data.config.field)));n.add_child(o)
			o.item_selected.connect(func(idx: int):_result(document.change_config(id,{"field":values[idx]})))
		"move","release_environment_water":
			var o:=OptionButton.new();var values: Array=[Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]
			for name in ["向右","向左","向上","向下"]:o.add_item(name)
			o.select(maxi(0,values.find(Vector2i(data.config.dx,data.config.dy))));n.add_child(o)
			o.item_selected.connect(func(idx: int):_result(document.change_config(id,{"dx":values[idx].x,"dy":values[idx].y})))
		"cell_empty","terrain_is","form_material","recover_material":
			var direction:=OptionButton.new();var directions:Array=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
			for name in ["向上","向右","向下","向左"]:direction.add_item(name)
			direction.select(maxi(0,directions.find(Vector2i(data.config.dx,data.config.dy))));n.add_child(direction)
			direction.item_selected.connect(func(index:int):
				var config:Dictionary=document.node(id).config.duplicate(true);config.dx=directions[index].x;config.dy=directions[index].y
				_result(document.change_config(id,config)))
			if data.op!="cell_empty":
				var material_box:=OptionButton.new();var materials:Array=[]
				for material_id in runtime._catalog.materials:
					var definition:Dictionary=runtime._catalog.materials[material_id]
					if definition.get("stackable")!=true:continue
					if data.op!="terrain_is" and Codec.bound_water_cost(definition)<=0:continue
					materials.append(material_id);material_box.add_item("凝水晶 · 500 水" if material_id=="core:water_crystal" else material_id)
				material_box.select(maxi(0,materials.find(data.config.material)));material_box.disabled=materials.is_empty();n.add_child(material_box)
				material_box.item_selected.connect(func(index:int):
					var config:Dictionary=document.node(id).config.duplicate(true);config.material=materials[index]
					_result(document.change_config(id,config)))
				n.add_child(Style.note("凝结扣除封存水；回收返还。目标/容量失败时整组不提交。"))
		"call":
			var o:=OptionButton.new();var modules: Array=runtime._program.source.modules.duplicate(true)
			for j in modules.size():
				var m: Dictionary=modules[j];o.add_item(m.id+" · v"+str(m.version))
				if m.id==data.config.id and m.version==data.config.version:o.select(j)
			n.add_child(o)
			o.item_selected.connect(func(idx: int):_result(document.change_call_target(runtime,id,modules[idx].id,modules[idx].version)))
			var target: Dictionary=runtime.rule_definition(data.config.get("id",""),data.config.get("version",0))
			if target.ok:
				for parameter in target.module.parameters:
					var spec: Dictionary=target.module.parameters[parameter]
					n.add_child(Style.note("%s · %s · 未连线默认 %s"%[parameter,spec.type,str(spec.default)]))
		"param":
			var parameter: String=data.config.get("name","")
			var spec: Dictionary=document.snapshot().parameters.get(parameter,{})
			if spec.is_empty(): n.add_child(Style.note("参数签名缺失"));return
			n.add_child(Style.label(parameter+" · "+spec.type,14,Style.GOLD))
			if spec.type=="int":
				var spin:=SpinBox.new();spin.min_value=-Codec.MAX_QUANTITY;spin.max_value=Codec.MAX_QUANTITY;spin.step=1;spin.value=spec.default;n.add_child(spin)
				spin.value_changed.connect(func(v:float):_result(document.set_parameter_default(parameter,int(v))))
			else:
				var toggle:=CheckBox.new();toggle.text="默认开启";toggle.button_pressed=spec.default;n.add_child(toggle)
				toggle.toggled.connect(func(v:bool):_result(document.set_parameter_default(parameter,v)))
			n.add_child(Style.button("还原为常量",func():_result(document.internalize_parameter(parameter))))
		"neighbor":n.add_child(Style.note("匹配任意相邻造物"))
	if data.op in ["int","bool"]:
		var row:=HBoxContainer.new();n.add_child(row)
		var name_edit:=LineEdit.new();name_edit.name="ParameterName";name_edit.text=id;name_edit.placeholder_text="参数英文名";name_edit.max_length=32;name_edit.custom_minimum_size.x=90;name_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(name_edit)
		var expose:=Style.button("公开参数",func():_result(document.expose_constant(id,name_edit.text)))
		expose.name="ExposeConstant";row.add_child(expose)

func _build_word_controls(content: VBoxContainer) -> void:
	content.add_child(Style.label("自创词条 · 保存一次，反复组合",14,Style.GOLD))
	var save_row:=HBoxContainer.new();content.add_child(save_row)
	word_name=LineEdit.new();word_name.name="WordName";word_name.placeholder_text="user:water_pump";word_name.max_length=96;word_name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;save_row.add_child(word_name)
	word_publish=Style.button("存为词条",func():publish_word_named());word_publish.name="PublishWord";save_row.add_child(word_publish)
	var use_row:=HBoxContainer.new();content.add_child(use_row)
	word_choices=OptionButton.new();word_choices.name="WordLibrary";word_choices.fit_to_longest_item=false;word_choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL;use_row.add_child(word_choices)
	word_append=Style.button("追加调用",func():append_selected_word());word_append.name="AppendWord";use_row.add_child(word_append)
	var library_actions:=HBoxContainer.new();content.add_child(library_actions)
	word_edit=Style.button("编辑所选副本",func():edit_selected_word());word_edit.name="EditWordCopy";word_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;library_actions.add_child(word_edit)
	word_export=Style.button("导出所选词条",func():
		if word_choices.selected>=0:word_export_requested.emit(word_choices.get_item_metadata(word_choices.selected).duplicate(true)))
	word_export.name="ExportWord";library_actions.add_child(word_export)
	word_status=Style.note("在节点编辑中公开常量参数。存为词条不会应用到造物。")
	content.add_child(word_status)

func _refresh_word_list() -> void:
	if word_choices==null or runtime==null: return
	var previous: Variant=word_choices.get_item_metadata(word_choices.selected) if word_choices.selected>=0 else null
	word_choices.clear()
	for m in runtime._program.get("source",{}).get("modules",[]):
		if not m.id.begins_with("user:"): continue
		var index: int=word_choices.item_count
		word_choices.add_item(m.id+" · v"+str(m.version))
		var ref: Dictionary={"id":m.id,"version":m.version}
		word_choices.set_item_metadata(index,ref)
		if ref==previous: word_choices.select(index)
	word_append.disabled=word_choices.item_count==0
	word_choices.disabled=word_choices.item_count==0
	word_edit.disabled=word_choices.item_count==0;word_export.disabled=word_choices.item_count==0

func publish_word_named() -> Dictionary:
	if runtime==null: return Codec.reject("runtime_not_ready")
	var id: String=word_name.text.strip_edges()
	var result: Dictionary=document.publish_word(runtime,id)
	word_status.text=("已保存 %s · v%d；尚未应用到造物。"%[result.entry.id,result.entry.version]) if result.ok else "不能保存："+_error_text(result.error)
	word_status.add_theme_color_override("font_color",Style.AQUA if result.ok else Style.BAD)
	if result.ok:
		_refresh_word_list()
		for i in word_choices.item_count:
			if word_choices.get_item_metadata(i)==result.entry: word_choices.select(i)
	return result

func append_selected_word() -> Dictionary:
	if runtime==null or word_choices.selected<0: return Codec.reject("missing_rule_version")
	var ref: Dictionary=word_choices.get_item_metadata(word_choices.selected)
	var result: Dictionary=document.append_word(runtime,ref.id,ref.version)
	word_status.text="已追加调用及独立参数输入；检查后再应用。" if result.ok else "不能追加："+_error_text(result.error)
	word_status.add_theme_color_override("font_color",Style.AQUA if result.ok else Style.BAD)
	return result

func edit_selected_word() -> Dictionary:
	if runtime==null or word_choices.selected<0:return Codec.reject("missing_rule_version")
	var ref: Dictionary=word_choices.get_item_metadata(word_choices.selected)
	var result: Dictionary=document.edit_word(runtime,ref.id,ref.version)
	if result.ok:
		word_name.text=ref.id;_positions.clear()
	word_status.text="已载入可编辑副本；旧版本和原造物不变，可撤销。" if result.ok else "不能载入："+_error_text(result.error)
	word_status.add_theme_color_override("font_color",Style.AQUA if result.ok else Style.BAD)
	return result

func _exit_tree() -> void:
	if document.changed.is_connected(_schedule_refresh):document.changed.disconnect(_schedule_refresh)
