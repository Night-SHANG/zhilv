extends Control
## 第一段可操作探索界面。只协调既有服务，不通过显示状态或按钮直接改世界。
const Loader = preload("res://runtime/scenario_loader.gd")
const Play = preload("res://runtime/play_session.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
const Canvas = preload("res://presentation/world_canvas.gd")
const Loom = preload("res://presentation/loom_panel.gd")
const Style = preload("res://presentation/ui_theme.gd")
const Codec = preload("res://runtime/snapshot_codec.gd")
const Recipes=preload("res://runtime/creation_recipes.gd")
const InventoryPanel=preload("res://presentation/inventory_panel.gd")
const Guide=preload("res://presentation/expedition_guide.gd")
const Feedback=preload("res://presentation/execution_text.gd")
const Workspace=preload("res://presentation/workspace_checkpoint.gd")
const DEFAULT_SLOT: String="first_expedition_014"
const DEFAULT_SCENARIO: String="res://content/fresh_expedition.json"
const WINDOW = Rect2i(-8,-8,24,20)
const NAMES = {"creation:vessel":"储水容器","creation:lamp":"便携夜灯","creation:plot":"营地蓄水器"}
const TOOLS = ["select","mine","stone","vessel","lamp","collect","release"]
const TOOL_NAMES = ["1  查看","2  挖掘","3  石块","4  容器","5  夜灯","6  取水","7  排水"]
var setup_complete: bool=false
var world
var runtime
var expedition
var play
var viewport_canvas
var loom
var inventory
var selected_id: String=""
var tool: String="select"
var _shell: VBoxContainer
var _body: HBoxContainer
var _pause_button: Button
var _clock_label: Label
var _objective_label: Label
var _inventory_label: Label
var _status_label: Label
var _feedback_label: Label
var _tools: Array=[]
var _file_dialog: FileDialog
var _confirm: ConfirmationDialog
var _pending: Callable
var _file_mode: String=""
var _word_export_entry: Dictionary={}
var _prior_editor_pause: bool=true
var _prior_dialog_pause: bool=true
var _draft_cache: Dictionary={}
var _draft_target: String=""
var _last_status: String=""
var _ui_accum: float=0
var _files=Files.new()
var _saved_paused: bool=true

func _ready() -> void:
	theme=Style.make();set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().gui_embed_subwindows=true
	get_window().min_size=Vector2i(1050,680)
	_build_ui()
	var result: Dictionary=new_game()
	if not result.ok:_notify("启动失败："+result.error,true)
	else:
		print("RULEWEAVER_APP_READY")
		_notify("先继续探索，用 2 挖掘头顶六块石料；B 打开背包制作容器和夜灯。")
func _build_ui() -> void:
	var background:=ColorRect.new();background.color=Style.BG;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	_shell=VBoxContainer.new();_shell.name="Shell";_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_shell.add_theme_constant_override("separation",0);add_child(_shell)
	var header:=PanelContainer.new();header.add_theme_stylebox_override("panel",Style.box(Style.BG,Style.EDGE,0,14));_shell.add_child(header)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",16);header.add_child(row)
	row.add_child(Style.label("织律",29,Style.GOLD))
	var brand:=VBoxContainer.new();brand.add_theme_constant_override("separation",0);row.add_child(brand)
	brand.add_child(Style.label("RULEWEAVER",12,Style.MUTED));brand.add_child(Style.label("v0.17 · 开发构建",12,Style.MUTED))
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(spacer)
	_clock_label=Style.label("第 1 日 · 白昼",14);row.add_child(_clock_label)
	_pause_button=Style.button("开始探索",_toggle_pause);_pause_button.name="PauseButton";row.add_child(_pause_button)
	row.add_child(Style.button("单步",func():_report(play.single_step(),"环境推进一拍")))
	row.add_child(Style.button("F5 存档",func():_report(save_game(),"世界与造物已保存")))
	row.add_child(Style.button("F9 读档",_ask_load))
	row.add_child(Style.button("新探索",func():_ask("重新开始这段探索？未保存的世界进度会丢失，磁盘存档保留。",func():_report(new_game(),"已开始新的探索"))))
	_body=HBoxContainer.new();_body.size_flags_vertical=Control.SIZE_EXPAND_FILL;_body.add_theme_constant_override("separation",8);_shell.add_child(_body)
	var left:=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.add_theme_constant_override("separation",0);_body.add_child(left)
	viewport_canvas=Canvas.new();viewport_canvas.name="WorldCanvas";viewport_canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL;viewport_canvas.custom_minimum_size=Vector2(520,350);left.add_child(viewport_canvas)
	viewport_canvas.cell_clicked.connect(_on_world_click)
	var objectives:=PanelContainer.new();objectives.add_theme_stylebox_override("panel",Style.box(Style.PANEL,Style.EDGE,0,14));left.add_child(objectives)
	var objective_col:=VBoxContainer.new();objective_col.add_theme_constant_override("separation",5);objectives.add_child(objective_col)
	_objective_label=Style.label("探索目标",16,Style.GOLD);_objective_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;objective_col.add_child(_objective_label)
	_inventory_label=Style.label("",14,Style.MUTED);_inventory_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;objective_col.add_child(_inventory_label)
	_feedback_label=Style.note("");_feedback_label.name="ExecutionFeedback";objective_col.add_child(_feedback_label)
	loom=Loom.new();loom.name="LoomPanel";loom.visible=false;_body.add_child(loom)
	loom.apply_requested.connect(func():_report(apply_draft(),"规则已应用到所选造物；关闭织律台后继续探索"))
	loom.close_requested.connect(close_loom)
	loom.export_requested.connect(func():_show_file("export"))
	loom.word_export_requested.connect(func(entry:Dictionary):
		_word_export_entry=entry.duplicate(true);_show_file("export_word"))
	loom.import_requested.connect(func():_show_file("import"))
	loom.message.connect(_notify)
	inventory=InventoryPanel.new();inventory.name="InventoryPanel";inventory.visible=false;_body.add_child(inventory)
	inventory.close_requested.connect(close_inventory)
	inventory.selected.connect(select_item)
	inventory.craft_requested.connect(func(id:String):_report(craft_recipe(id),"制作完成：已选中新造物"))
	inventory.place_requested.connect(func():
		var item:Dictionary=world.get_instance(selected_id)
		if item.is_empty():return
		var value:String="lamp" if item.material_id=="user:crystal" else "vessel"
		close_inventory();select_tool(value))
	inventory.edit_requested.connect(func():open_loom())
	var toolbar:=PanelContainer.new();toolbar.add_theme_stylebox_override("panel",Style.box(Style.BG,Style.EDGE,0,12));_shell.add_child(toolbar)
	var tools_col:=VBoxContainer.new();tools_col.add_theme_constant_override("separation",7);toolbar.add_child(tools_col)
	var tools_row:=HBoxContainer.new();tools_col.add_child(tools_row)
	for i in TOOLS.size():
		var value: String=TOOLS[i]
		var b:=Style.button(TOOL_NAMES[i],func():select_tool(value));b.toggle_mode=true;b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;tools_row.add_child(b);_tools.append(b)
	var edit_button:=Style.button("Tab  织律台",func():close_loom() if loom.visible else open_loom());edit_button.add_theme_color_override("font_color",Style.GOLD);tools_row.add_child(edit_button)
	tools_row.add_child(Style.button("B 背包",func():close_inventory() if inventory.visible else open_inventory()))
	var deliver:=Style.button("交水 500",func():_report(deliver_water(),"已向营地蓄水器交付 500 单位水"));deliver.name="DeliverWater";tools_row.add_child(deliver)
	_status_label=Style.label("",14,Style.MUTED);_status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status_label.custom_minimum_size.y=23;tools_col.add_child(_status_label)
	_file_dialog=FileDialog.new();_file_dialog.title="律卷文件";_file_dialog.access=FileDialog.ACCESS_FILESYSTEM;_file_dialog.filters=PackedStringArray(["*.json ; 织律律卷"]);_file_dialog.size=Vector2i(900,600);add_child(_file_dialog)
	_file_dialog.file_selected.connect(_on_file_selected);_file_dialog.canceled.connect(_close_file)
	_confirm=ConfirmationDialog.new();_confirm.title="确认操作";_confirm.ok_button_text="继续";_confirm.cancel_button_text="取消";_confirm.size=Vector2i(520,180);add_child(_confirm)
	_confirm.confirmed.connect(_confirmed);_confirm.canceled.connect(func():_pending=Callable();_restore_dialog_pause())
func new_game(path:String=DEFAULT_SCENARIO) -> Dictionary:
	var setup: Dictionary=Loader.load_scenario(path)
	if not setup.ok:return setup
	if play!=null:play.dispose();play.queue_free();play=null
	world=setup.world;runtime=setup.runtime;expedition=setup.expedition
	play=Play.new();add_child(play)
	var result: Dictionary=play.bind_session(expedition,world,WINDOW)
	if not result.ok:return result
	play.fault.connect(func(reason: String):_notify("模拟已停止："+reason,true))
	play.set_paused(true);play.start()
	viewport_canvas.world=world;viewport_canvas.runtime=runtime
	selected_id="";tool="select";_draft_target="";_draft_cache.clear();loom.advanced.hide();loom.visible=false;inventory.visible=false
	var items:Array=player_items()
	if not items.is_empty():selected_id=items[0].id
	if not world.get_instance("creation:vessel").is_empty():selected_id="creation:vessel"
	setup_complete=true;_refresh_hud();return {"ok":true,"error":""}
func _process(delta: float) -> void:
	if not setup_complete:return
	_ui_accum+=delta
	if _ui_accum>=0.1:_ui_accum=0;_refresh_hud()
func _refresh_hud() -> void:
	if not setup_complete:return
	var clock: Dictionary=runtime.clock_state()
	_clock_label.text="第 %d 日 · %s"%[int(clock.tick/clock.cycle_ticks)+1,"夜晚" if clock.night else "白昼"]
	_pause_button.text="继续探索" if clock.paused else "暂停  Esc"
	_pause_button.disabled=loom.visible or inventory.visible or _file_dialog.visible or _confirm.visible
	var guidance:Dictionary=guidance_state()
	_objective_label.text="%d / %d · %s\n%s"%[guidance.completed,guidance.total,guidance.title,guidance.detail]
	viewport_canvas.objective_markers=guidance.markers
	var items:Array=player_items()
	var item: Dictionary=world.get_instance(selected_id)
	var detail: String="B 打开背包制作与选择造物"
	if not item.is_empty():
		detail="%s · 水量 %d / %d · %s"%[Recipes.label(item),item.state.water_units,item.state.capacity_units,"背包中" if item.location.kind=="inventory" else "世界中"]
	_inventory_label.text="石块 %d   |   %s"%[world.stack_count("core:stone"),detail]+("   |   地块封水 %d"%world.bound_water_units() if world.bound_water_units()>0 else "")
	var feedback:Dictionary=runtime.execution_feedback(selected_id) if not item.is_empty() else {}
	_feedback_label.text=Feedback.live(feedback)
	_feedback_label.visible=not _feedback_label.text.is_empty()
	_feedback_label.tooltip_text=Feedback.checks(feedback)
	viewport_canvas.selected_id=selected_id;viewport_canvas.tool=tool
	for i in _tools.size():_tools[i].set_pressed_no_signal(TOOLS[i]==tool)
	if inventory.visible:inventory.refresh(items,selected_id,world.stack_count("core:stone"),item)
	if loom.visible and not item.is_empty():loom.state_label.text="%s  ·  储水 %d / %d"%[Recipes.label(item),item.state.water_units,item.state.capacity_units]
func select_item(id: String) -> void:
	if not setup_complete or world.get_instance(id).is_empty():return
	if loom.visible and _draft_target!="":_draft_cache[_draft_target]=loom.document.snapshot()
	selected_id=id
	if loom.visible:_configure_loom()
	_refresh_hud()
func select_tool(value: String) -> void:
	if not value in TOOLS:return
	tool=value
	if value in ["vessel","collect","release"]:
		var id:String=_pick_material("user:reservoir")
		if not id.is_empty():select_item(id)
		else:selected_id=""
	elif value=="lamp":
		var id:String=_pick_material("user:crystal")
		if not id.is_empty():select_item(id)
		else:selected_id=""
	_refresh_hud()
	_notify({"select":"点击造物查看，E 打开所选造物的织律台。右键可收回造物。","mine":"左键挖掘地形。地板被挖开后，水和角色都会下落。","stone":"左键放置石块；占位、积水和距离限制仍生效。","vessel":"左键放置容器，右键收回。可在积水上方放置，再编织取水规则。","lamp":"左键放置夜灯，右键收回。目标格需要真实逻辑照明。","collect":"点击附近的水，将最多 250 单位装入容器。按住 Shift 加大到 1000。","release":"点击空格，将容器里的水排回环境；容量不足时正常拒绝。"}.get(value,""))
func _on_world_click(cell: Vector2i,button: int,shift: bool) -> void:
	_report(act_cell(cell,button,shift),"操作完成")
func act_cell(cell: Vector2i,button: int=MOUSE_BUTTON_LEFT,shift: bool=false) -> Dictionary:
	if not setup_complete:return Codec.reject("play_unbound")
	if loom.visible or inventory.visible or _file_dialog.visible or _confirm.visible:return Codec.reject("play_controls_disabled")
	var occupant: String=world.instance_at(cell)
	if button==MOUSE_BUTTON_LEFT and tool=="select":
		if not occupant.is_empty():select_item(occupant);return {"ok":true,"error":"","message":"已选择 "+Recipes.label(world.get_instance(occupant))}
		return {"ok":true,"error":"","message":"此格游离水 %d，地块封存水 %d。敲碎凝水晶会释放水，不掉落重复资源。"%[world.water_at(cell),world.material_water_cost(world.material_at(cell))]}
	var pos: Array=[cell.x,cell.y]
	if button==MOUSE_BUTTON_RIGHT:
		if not occupant.is_empty():return play.command({"op":"pickup","id":occupant})
		return Codec.reject("no_creation_here")
	match tool:
		"mine":return play.command({"op":"mine","cell":pos})
		"stone":return play.command({"op":"build","cell":pos,"material":"core:stone"})
		"vessel","lamp":
			if selected_id.is_empty():return Codec.reject("no_carried_tool")
			return play.command({"op":"place","cell":pos,"id":selected_id})
		"collect","release":
			var item: Dictionary=world.get_instance(selected_id)
			if item.is_empty():return Codec.reject("no_carried_tool")
			var quantity: int=1000 if shift else 250
			if tool=="collect":quantity=mini(quantity,mini(world.water_at(cell),item.state.capacity_units-item.state.water_units))
			else:quantity=mini(quantity,mini(item.state.water_units,1000-world.water_at(cell)))
			if quantity<=0:return Codec.reject("no_water_or_capacity")
			return play.command({"op":"collect" if tool=="collect" else "release","cell":pos,"id":selected_id,"amount":quantity})
	return Codec.reject("unknown_tool")
func _configure_loom() -> void:
	loom.configure(runtime,selected_id,Recipes.label(world.get_instance(selected_id)))
	if _draft_cache.has(selected_id):loom.document.load_module(_draft_cache[selected_id],_draft_cache[selected_id].id)
	_draft_target=selected_id
func open_loom() -> void:
	if not setup_complete or loom.visible:return
	if world.get_instance(selected_id).is_empty():_notify("先用 B 制作并选择一件造物，再编织规则。",true);return
	if inventory.visible:
		inventory.visible=false
	else:_prior_editor_pause=runtime.clock_state().paused
	play.set_paused(true);play.set_controls_enabled(false)
	loom.visible=true
	if _draft_target!=selected_id:_configure_loom()
	_refresh_hud();_notify("编织时世界暂停。草稿可随 F5 保存，只有点击应用才改变行为。")
func close_loom() -> void:
	if not loom.visible:return
	_draft_cache[selected_id]=loom.document.snapshot()
	loom.advanced.hide();loom.visible=false;play.set_controls_enabled(true);play.set_paused(_prior_editor_pause)
	_refresh_hud();_notify("未应用草稿保留；按 F5 可与世界一起保存。")
func player_items()->Array:
	if world==null:return []
	var view:Dictionary=world.rule_view();var items:Array=[]
	for item in view.entities.instances:
		if item.location.kind=="inventory" and item.location.owner==view.actor.id:items.append(item)
	items.sort_custom(func(a:Dictionary,b:Dictionary):return a.id<b.id)
	return items
func _pick_material(material:String)->String:
	var chosen:Dictionary=world.get_instance(selected_id)
	if not chosen.is_empty() and chosen.material_id==material and chosen.id!="creation:plot":return selected_id
	for item in player_items():
		if item.material_id==material:return item.id
	return ""
func open_inventory()->void:
	if not setup_complete or inventory.visible or _file_dialog.visible or _confirm.visible:return
	if loom.visible:
		_draft_cache[selected_id]=loom.document.snapshot();loom.advanced.hide();loom.visible=false
	else:_prior_editor_pause=runtime.clock_state().paused
	play.set_paused(true);play.set_controls_enabled(false);inventory.visible=true
	_refresh_hud();_notify("背包中每件造物独立。制作只消耗列出的材料，不复制已有水或规则。")
func close_inventory()->void:
	if not inventory.visible:return
	inventory.visible=false;play.set_controls_enabled(true);play.set_paused(_prior_editor_pause);_refresh_hud()
func craft_recipe(id:Variant)->Dictionary:
	if not setup_complete or not inventory.visible:return Codec.reject("open_inventory_first")
	var result:Dictionary=play.craft_in_inventory(id)
	if result.ok:selected_id=result.id;_refresh_hud()
	return result
func deliver_water()->Dictionary:
	if not setup_complete or loom.visible or inventory.visible:return Codec.reject("play_controls_disabled")
	var id:String=_pick_material("user:reservoir")
	if id.is_empty():return Codec.reject("no_carried_tool")
	return play.command({"op":"pour","source":id,"target":"creation:plot","amount":500})
func _editor_value()->Dictionary:
	var drafts:Dictionary=_draft_cache.duplicate(true)
	if loom.visible and not selected_id.is_empty():drafts[selected_id]=loom.document.snapshot()
	return {"selected":selected_id,"tool":tool,"drafts":drafts}
func workspace_snapshot()->String:
	return Workspace.new(play,_editor_value()).checkpoint_json()
func apply_draft() -> Dictionary:
	if not setup_complete or not loom.visible:return Codec.reject("open_loom_first")
	var c: Dictionary=loom.document.candidate(runtime)
	if not c.ok:return c
	var bindings: Dictionary={selected_id:[{"id":c.module.id,"version":c.module.version}]}
	var result: Dictionary=runtime.publish_pack(c.text,bindings)
	if result.ok:loom.document.mark_saved();_draft_cache[selected_id]=loom.document.snapshot();_refresh_hud()
	else:loom.validate_graph()
	return result
func save_game(slot: String=DEFAULT_SLOT) -> Dictionary:
	if not setup_complete:return Codec.reject("play_unbound")
	return _files.save(Workspace.new(play,_editor_value()),slot)
func load_game(slot: String=DEFAULT_SLOT, backup: bool=false) -> Dictionary:
	if not setup_complete:return Codec.reject("play_unbound")
	var workspace=Workspace.new(play)
	var result: Dictionary=_files.load_into(workspace,slot,backup)
	if result.ok:
		loom.advanced.hide();loom.visible=false;inventory.visible=false
		_draft_cache=workspace.editor.drafts.duplicate(true);selected_id=workspace.editor.selected;tool=workspace.editor.tool
		_draft_target="";play.set_controls_enabled(true)
		play.set_paused(true);_refresh_hud()
	return result
func export_scroll_to(path: String, overwrite: bool=false, entry: Dictionary={}) -> Dictionary:
	var ref: Dictionary=entry.duplicate(true)
	if ref.is_empty():
		var item: Dictionary=world.get_instance(selected_id)
		if item.is_empty() or item.rules.is_empty():return Codec.reject("no_published_rule")
		ref=item.rules.back().duplicate(true)
	if not Codec._shape(ref,["id","version"]) or not Codec.identifier(ref.id) or typeof(ref.version)!=TYPE_INT:return Codec.reject("invalid_rule_reference")
	if not path.ends_with(".json") or path.begins_with("res://"):return Codec.reject("scroll_path")
	if FileAccess.file_exists(path) and not overwrite:return Codec.reject("file_exists")
	var result: Dictionary=runtime.export_rule(ref.id,ref.version)
	if not result.ok:return result
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return Codec.reject("scroll_write_failed")
	file.store_string(result.text);file.flush();file.close()
	if FileAccess.get_file_as_string(path)!=result.text:return Codec.reject("scroll_verification_failed")
	return {"ok":true,"error":""}
func import_scroll_from(path: String) -> Dictionary:
	if not path.ends_with(".json"):return Codec.reject("scroll_path")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return Codec.reject("scroll_unreadable")
	if file.get_length()>262144:file.close();return Codec.reject("scroll_byte_budget")
	var text: String=file.get_as_text();file.close()
	return runtime.import_scroll(text)
func _show_file(mode: String) -> void:
	_prior_dialog_pause=runtime.clock_state().paused;play.set_paused(true);play.set_controls_enabled(false)
	_file_mode=mode;_file_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE if mode in ["export","export_word"] else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title="导出已发布律卷" if mode in ["export","export_word"] else "导入律卷（不自动绑定）"
	if mode!="export_word":_word_export_entry.clear()
	if mode in ["export","export_word"]:_file_dialog.current_file="ruleweaver_scroll.json"
	_file_dialog.popup_centered(Vector2i(900,600))
func _close_file() -> void:_restore_dialog_pause()
func _on_file_selected(path: String) -> void:
	var result: Dictionary=export_scroll_to(path,true,_word_export_entry) if _file_mode in ["export","export_word"] else import_scroll_from(path)
	if result.ok and _file_mode=="import":
		var m: Dictionary=runtime.rule_definition(result.entry.id,int(result.entry.version))
		if m.ok:
			loom.document.load_module(m.module,m.module.id if m.module.id.begins_with("user:") else "user:imported_rule")
	_report(result,"律卷已导出" if _file_mode in ["export","export_word"] else "已导入到草稿；尚未绑定。检查后点击应用。")
	_restore_dialog_pause()
func _restore_dialog_pause() -> void:
	if not setup_complete:return
	play.set_controls_enabled(not loom.visible and not inventory.visible)
	play.set_paused(true if loom.visible or inventory.visible else _prior_dialog_pause)
	_refresh_hud()
func _ask(text: String,action: Callable) -> void:
	_prior_dialog_pause=runtime.clock_state().paused;play.set_paused(true);play.set_controls_enabled(false)
	_pending=action;_confirm.dialog_text=text;_confirm.popup_centered()
func _confirmed() -> void:
	var action: Callable=_pending;_pending=Callable()
	_restore_dialog_pause()
	if action.is_valid():action.call()
func preferred_load_slot(primary:String=DEFAULT_SLOT,legacy:String="first_expedition_013")->String:
	# 新槽位损坏时保留它的恢复路径，不用旧进度悄悄掩盖失败。
	for suffix in ["", ".bak"]:
		if FileAccess.file_exists(_files.slot_path(primary)+suffix):return primary
	for suffix in ["", ".bak"]:
		if FileAccess.file_exists(_files.slot_path(legacy)+suffix):return legacy
	return primary
func _ask_load() -> void:
	var slot:String=preferred_load_slot()
	var prompt:String="载入存档将替换当前世界与未应用的草稿。继续？"
	if slot!=DEFAULT_SLOT:prompt="发现 v0.13 旧进度。载入后可继续游玩，再按 F5 另存 v0.14；旧文件不会覆盖。继续？"
	_ask(prompt,func():
		var result: Dictionary=load_game(slot)
		_report(result,"已载入。世界暂停，点击继续探索。")
		if not result.ok:_ask("主存档不可用。尝试读取上一份备份？不会覆盖损坏文件。",func():_report(load_game(slot,true),"已从备份恢复；请另存新槽位。")))
func _toggle_pause() -> void:
	if not setup_complete or loom.visible or inventory.visible:return
	_report(play.set_paused(not runtime.clock_state().paused),"世界已暂停" if not runtime.clock_state().paused else "继续探索")
	_refresh_hud()
func _input(event: InputEvent) -> void:
	if not setup_complete or event.is_echo() or _file_dialog.visible or _confirm.visible or loom.advanced.visible:return
	if event is InputEventKey and event.pressed:
		var focused: Control=get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:return
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_B:
			close_inventory() if inventory.visible else open_inventory();get_viewport().set_input_as_handled()
		elif key==KEY_TAB or key==KEY_E:
			close_loom() if loom.visible else open_loom();get_viewport().set_input_as_handled()
		elif key==KEY_ESCAPE and inventory.visible:
			close_inventory();get_viewport().set_input_as_handled()
		elif key==KEY_ESCAPE and loom.visible:
			close_loom();get_viewport().set_input_as_handled()
		elif key==KEY_F5:_report(save_game(),"世界与规则已保存");get_viewport().set_input_as_handled()
		elif key==KEY_F9:_ask_load();get_viewport().set_input_as_handled()
		elif key>=KEY_1 and key<=KEY_7 and not loom.visible and not inventory.visible:select_tool(TOOLS[key-KEY_1]);get_viewport().set_input_as_handled()
func _report(result: Dictionary,success: String) -> void:
	if result.ok:_notify(result.get("message",success))
	else:_notify(_error(result.get("error","unknown")),true)
func _error(code: String) -> String:
	return {"no_carried_tool":"没有这种造物。按 B 制作或选择一件随身造物。","craft_missing_materials":"材料不足，世界与背包未改变。","unknown_recipe":"没有这种受信载体配方。","open_inventory_first":"请先打开背包制作。","workspace_selected_missing":"存档中的选中造物不存在，当前进度未改变。","play_paused":"世界已暂停。先点击继续探索，再操作地形与物品。","play_controls_disabled":"界面正在编辑或选择文件；先关闭面板再操作世界。","out_of_reach":"距离太远，请走近一些（最多 4 格）。","occluded":"被墙体挡住了，不能隔墙操作。","occupied_cell":"这里有地形、角色、造物或残水；等待水流离开，或先用取水工具清理。","not_in_inventory":"造物已经在世界里，请右键收回后再放置。","no_creation_here":"这个格子没有可收回的造物。","no_water_or_capacity":"没有可转移的水，或容器／格子容量已满。","no_published_rule":"所选造物还没有已发布的规则，请先在织律台应用。","referenced_draft_node":"节点仍被其他节点引用，请先断开连线。","no_valid_checkpoint":"没有找到可用存档，当前世界保持不变。","missing_input_port":"规则还有未连接的端口，未应用任何修改。","missing_reference_or_type_mismatch":"规则连线的类型不匹配，未应用任何修改。","data_cycle":"规则图形成循环，不能发布。","version_content_conflict":"同一规则版本不能覆盖，请以新版本发布。","insufficient_water":"水量不足，操作未改变世界。","no_terrain":"这里没有可挖掘的地形。"}.get(code,"操作未完成（"+code+"）；世界保持原状态。")
func _notify(text: String,bad: bool=false) -> void:
	_last_status=text
	if is_instance_valid(_status_label):_status_label.text=text;_status_label.add_theme_color_override("font_color",Style.BAD if bad else Style.MUTED)
func _exit_tree() -> void:
	if play!=null and is_instance_valid(play):play.dispose()

func guidance_state()->Dictionary:
	return Guide.evaluate(world,expedition)
