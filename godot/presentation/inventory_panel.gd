extends PanelContainer
## 界面仅显示权威库存的副本。制作、选中、放置均由应用层调用原服务。
signal close_requested
signal selected(id: String)
signal craft_requested(recipe: String)
signal place_requested
signal edit_requested
const Style=preload("res://presentation/ui_theme.gd")
const Recipes=preload("res://runtime/creation_recipes.gd")
var item_list: ItemList
var recipe_buttons: Dictionary={}
var place_button: Button
var edit_button: Button
var _materials: Label
var _detail: Label
var _signature: String=""
func _ready()->void:
	custom_minimum_size.x=390
	size_flags_horizontal=Control.SIZE_FILL
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	var col:=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;col.add_theme_constant_override("separation",9);scroll.add_child(col)
	var heading:=HBoxContainer.new();col.add_child(heading)
	var title:=Style.label("背包 · 制作",22,Style.GOLD);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
	heading.add_child(Style.button("收起 B",func():close_requested.emit()))
	col.add_child(Style.note("打开背包时世界暂停；每件造物保留独立规则与水量。"))
	_materials=Style.label("石块 0",16);col.add_child(_materials)
	item_list=ItemList.new();item_list.name="CreationItems";item_list.custom_minimum_size=Vector2(340,145);item_list.add_theme_font_size_override("font_size",14);item_list.add_theme_stylebox_override("panel",Style.box(Style.BG));col.add_child(item_list)
	item_list.item_selected.connect(func(index:int):selected.emit(item_list.get_item_metadata(index)))
	_detail=Style.note("还没有造物。先用挖掘工具采集头顶石块，再制作载体。");_detail.custom_minimum_size.y=46;col.add_child(_detail)
	var actions:=HBoxContainer.new();col.add_child(actions)
	place_button=Style.button("选中并放置",func():place_requested.emit());place_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(place_button)
	edit_button=Style.button("编织选中造物",func():edit_requested.emit());actions.add_child(edit_button)
	col.add_child(HSeparator.new());col.add_child(Style.label("制作载体",18,Style.GOLD))
	for id in Recipes.keys():
		var recipe:Dictionary=Recipes.recipe(id)
		var row:=HBoxContainer.new();col.add_child(row)
		var text:=Style.label("%s  ·  石块 %d"%[recipe.name,recipe.cost["core:stone"]],15);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
		var recipe_id:String=id
		var button:=Style.button("制作",func():craft_requested.emit(recipe_id));button.name="Craft_"+id.get_slice(":",1);row.add_child(button);recipe_buttons[id]=button
	col.add_child(Style.note("配方只制作承载规则的物体，不限定行为组合。制作后可在织律台改写规则。"))
	col.add_child(Style.note("F5 同时保存世界、选中造物及未应用的草稿；载入草稿不会自动发布。"))
func refresh(items:Array,selected_id:String,stone:int,world_item:Dictionary={}) -> void:
	_materials.text="石块 %d   |   随身造物 %d"%[stone,items.size()]
	var signature:String=JSON.stringify(items)
	if signature!=_signature:
		_signature=signature;item_list.clear()
		for entity in items:
			var i:int=item_list.add_item("%s   %d / %d"%[Recipes.label(entity),entity.state.water_units,entity.state.capacity_units])
			item_list.set_item_metadata(i,entity.id)
			item_list.set_item_tooltip(i,entity.id+"\n每件物体独立保存水量和规则版本")
	item_list.deselect_all()
	var chosen:Dictionary={}
	for i in items.size():
		if items[i].id==selected_id:item_list.select(i);chosen=items[i];break
	if chosen.is_empty():
		_detail.text="还没有随身造物。先挖掘头顶石块，再制作载体。" if items.is_empty() else "点击列表选择一件随身造物。"
		if not world_item.is_empty():_detail.text="当前选中 %s，已放在世界中。右键收回后可再次放置。"%Recipes.label(world_item)
	else:
		var rules:Array=[]
		for ref in chosen.rules:rules.append(ref.id+"@"+str(ref.version))
		_detail.text="%s\n规则：%s"%[Recipes.label(chosen),"尚未编织" if rules.is_empty() else ", ".join(rules)]
	place_button.disabled=chosen.is_empty();edit_button.disabled=chosen.is_empty()
	for id in recipe_buttons:recipe_buttons[id].disabled=stone<int(Recipes.recipe(id).cost["core:stone"])
