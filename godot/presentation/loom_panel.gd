extends PanelContainer
## 真实GraphEdit编辑前端；每一条连线对应RuleDraft的输入引用，不执行宿主代码。
signal apply_requested
signal export_requested
signal import_requested
signal close_requested
signal message(text: String, bad: bool)
const Style = preload("res://presentation/ui_theme.gd")
const Document = preload("res://presentation/loom_document.gd")
const Compiler = preload("res://runtime/rule_compiler.gd")
const TYPES = {"bool":0,"int":1,"ref":2,"cell_ref":3,"effect":4}
const COLORS = {"bool":Color("bb9bd9"),"int":Color("e6ba72"),"ref":Color("9ac490"),"cell_ref":Color("71c9d2"),"effect":Color("f0b17b")}
const TITLES = {"bool":"开关常量","int":"数值常量","is_night":"是否夜晚","is_ambient_dark":"环境是否昏暗","read_state":"读取自身状态","neighbor":"相邻造物","exists":"造物存在","neighbor_water":"相邻环境水","water_exists":"水源存在","water_units":"读取水量","lt":"小于比较","min":"取较小值","add":"相加","sub":"相减","and":"同时满足","not":"条件取反","set_light":"设置发光","move":"移动一格","take_water":"从造物取水","take_environment_water":"从环境取水","release_environment_water":"排水到环境","call":"调用已发布模块"}
const PORTS = {"when":"执行条件","value":"值 / 条件","a":"输入 A","b":"输入 B","source":"来源","amount":"数量"}
var document=Document.new()
var runtime
var target_id: String=""
var title_label: Label
var state_label: Label
var summary: Label
var validation: Label
var amount: SpinBox
var preset_box: OptionButton
var cards: VBoxContainer
var advanced: Window
var graph: GraphEdit
var palette: OptionButton
var _syncing: bool=false
var _queued: bool=false
var _positions: Dictionary={}
var _node_ports: Dictionary={}

func _ready() -> void:
	custom_minimum_size=Vector2(390,0)
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",8);add_child(col)
	var header:=HBoxContainer.new();col.add_child(header)
	title_label=Style.label("织律台",22,Style.GOLD);title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title_label)
	header.add_child(Style.button("收起 Tab",func(): close_requested.emit()))
	state_label=Style.label("储水容器",14);col.add_child(state_label)
	col.add_child(Style.note("世界暂停 · 草稿不会自动改变造物"))
	col.add_child(HSeparator.new())
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.custom_minimum_size.y=120;col.add_child(scroll)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",10);scroll.add_child(content)
	content.add_child(Style.label("起始结构 · 可以拆开重组",14,Style.MUTED))
	var start_row:=HBoxContainer.new();content.add_child(start_row)
	preset_box=OptionButton.new();preset_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for text in ["限量吸水","暗处发光","向右排水","空白规则"]:preset_box.add_item(text)
	start_row.add_child(preset_box);start_row.add_child(Style.button("载入草稿",_preset_selected))
	var rate_row:=HBoxContainer.new();content.add_child(rate_row)
	rate_row.add_child(Style.label("每次取 / 排水",14,Style.MUTED))
	amount=SpinBox.new();amount.min_value=1;amount.max_value=1000;amount.step=1;amount.value=100;amount.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	amount.value_changed.connect(_rate_changed);rate_row.add_child(amount)
	cards=VBoxContainer.new();content.add_child(cards)
	summary=Style.note("");content.add_child(summary)
	col.add_child(HSeparator.new())
	var history:=HBoxContainer.new();col.add_child(history)
	history.add_child(Style.button("撤销",func(): _result(document.undo())))
	history.add_child(Style.button("重做",func(): _result(document.redo())))
	var edit:=Style.button("节点与连线",open_advanced);edit.name="OpenGraph";edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;history.add_child(edit)
	validation=Style.note("先检查，再应用。");validation.custom_minimum_size.y=38;col.add_child(validation)
	var actions:=HBoxContainer.new();col.add_child(actions)
	actions.add_child(Style.button("校验草稿",validate_graph))
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
	var kinds: Array=["pump","lamp","release","blank"]
	_result(document.preset(kinds[preset_box.selected],int(amount.value)))
	_positions.clear()
func _rate_changed(value: float) -> void:
	if not _syncing and not document.node("rate").is_empty():_result(document.change_config("rate",{"value":int(value)}))
func _result(result: Dictionary) -> void:
	if not result.ok:message.emit("操作未完成："+str(result.error),true)
func _schedule_refresh() -> void:
	if _queued:return
	_queued=true;call_deferred("_refresh")
func _refresh() -> void:
	_queued=false
	if not is_inside_tree():return
	_syncing=true
	var m: Dictionary=document.snapshot()
	for child in cards.get_children():cards.remove_child(child);child.queue_free()
	var groups: Array=[[],[],[]]
	for n in m.get("nodes",[]):
		var title: String=TITLES.get(n.op,n.op)
		if n.op in ["set_light","move","take_water","take_environment_water","release_environment_water","call"]:groups[2].append(title)
		elif n.op in ["lt","min","add","sub","and","not","exists","water_exists"]:groups[1].append(title)
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
	amount.editable=not rate.is_empty()
	if not rate.is_empty():amount.value=rate.config.value
	summary.text="%d 个节点  ·  %d 个动作  ·  %s"%[m.get("nodes",[]).size(),m.get("effects",[]).size(),"草稿有修改" if document.dirty else "与已载入内容一致"]
	validation.text="编辑只影响草稿；应用前会完整检查类型和依赖。"
	if is_instance_valid(advanced) and advanced.visible: _rebuild_graph()
	_syncing=false
func validate_graph() -> void:
	if runtime==null:return
	var result: Dictionary=document.validate(runtime)
	validation.text="规则校验通过。应用后开始使用新版本。" if result.ok else "规则未通过："+_error_text(result.error)
	validation.add_theme_color_override("font_color",Style.AQUA if result.ok else Style.BAD)
func _error_text(code: String) -> String:
	return {"missing_input_port":"存在未连接的输入端口","missing_reference_or_type_mismatch":"连线类型不匹配或引用已丢失","data_cycle":"数据连线形成循环","module_collection_budget":"空白规则尚无有效节点","referenced_draft_node":"该节点仍被引用，请先断开连线","version_content_conflict":"旧版本不可覆盖，请发布新版本"}.get(code,code)
func _make_advanced() -> void:
	advanced=Window.new();advanced.title="织律台 · 节点与连线";advanced.size=Vector2i(1080,680);advanced.min_size=Vector2i(760,500)
	advanced.transient=true;advanced.exclusive=true;advanced.visible=false;advanced.theme=Style.make();add_child(advanced)
	advanced.close_requested.connect(func():advanced.hide())
	var root:=VBoxContainer.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);advanced.add_child(root)
	var bar:=HBoxContainer.new();root.add_child(bar)
	palette=OptionButton.new();palette.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for op in TITLES:palette.add_item(TITLES[op]);palette.set_item_metadata(palette.item_count-1,op)
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
func _config_ui(n: GraphNode,data: Dictionary) -> void:
	var id: String=data.id
	match data.op:
		"int":
			var spin:=SpinBox.new();spin.min_value=-1000000;spin.max_value=1000000;spin.step=1;spin.value=data.config.value;n.add_child(spin)
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
		"call":
			var o:=OptionButton.new();var modules: Array=runtime._program.source.modules.duplicate(true)
			for j in modules.size():
				var m: Dictionary=modules[j];o.add_item(m.id+" · v"+str(m.version))
				if m.id==data.config.id and m.version==data.config.version:o.select(j)
			n.add_child(o)
			o.item_selected.connect(func(idx: int):_result(document.change_config(id,{"id":modules[idx].id,"version":modules[idx].version})))
		"neighbor":n.add_child(Style.note("匹配任意相邻造物"))
func _exit_tree() -> void:
	if document.changed.is_connected(_schedule_refresh):document.changed.disconnect(_schedule_refresh)
