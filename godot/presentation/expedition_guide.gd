extends RefCounted
## 无副作用引导：根据权威世界和目标推导提示，不另存教程进度，不强制解法。
static func evaluate(world, expedition)->Dictionary:
	var status:Dictionary=expedition.status()
	var goals:Array=expedition.objective_definitions()
	var goal:Dictionary={}
	for item in goals:
		if not status.completed.has(item.id):goal=item;break
	var result:Dictionary={"stage":"freeplay","title":"本段探索目标已完成","detail":"继续挖掘、改写造物或保存律卷；完成目标不会锁住世界。","markers":[],"completed":status.completed.size(),"total":goals.size()}
	if goal.is_empty():return result
	if goal.has("cell"):result.markers.append({"cell":Vector2i(goal.cell[0],goal.cell[1]),"label":"探索目标"})
	match goal.id:
		"goal:high_observatory":
			result.stage="ascent";result.title="凝水造路 · 高处观测点"
			result.detail="回收原容器和灯。用储水凝出台阶，或用石块搭台，照亮并到达 (0,-3)。每块凝水晶封存 500 水，可回收。"
		"goal:lower_archive":
			result.stage="lower";result.title="继续探索 · 下层回廊"
			result.detail="回收或再制作夜灯，挖开 (6,1) 附近地板；照亮并到达下层 (6,2)。"
		"goal:lower_supply":
			result.stage="supply";result.title="建立下层补给点"
			result.detail="把至少装有 1000 单位水的任意容器放到上方储水格 (8,1)。可复用刚才的容器，不必重做。"
		"goal:irrigate":
			result.stage="return";result.title="带水返回营地"
			result.detail="收回装水的容器，回左侧营地交水 500；完成后还能继续探索下层。"
		"goal:ruins":
			_first_section(result,world,goal)
		_:
			result.stage="explore";result.title="继续探索";result.detail="接近地图上的目标标记，观察光照、水位和造物状态。"
	return result
static func _first_section(out:Dictionary,world,goal:Dictionary)->void:
	var vessels:Array=[];var lamps:Array=[]
	for item in world.rule_view().entities.instances:
		if item.id=="creation:plot":continue
		if item.material_id=="user:reservoir":vessels.append(item)
		if item.material_id=="user:crystal":lamps.append(item)
	var needed:int=(4 if vessels.is_empty() else 0)+(2 if lamps.is_empty() else 0)
	if needed>0:
		var stone:int=world.stack_count("core:stone")
		out.stage="gather" if stone<needed else "craft"
		out.title="采集制作材料" if stone<needed else "制作自己的工具"
		out.detail="用 2 挖掘附近石料：还需 %d。按 B 制作；也可自行选择挖沟等解法。"%maxi(0,needed-stone) if stone<needed else "按 B 打开背包：容器需 4 石料，夜灯需 2；每件物品可以独立编织。"
		out.markers=[];return
	var deep:bool=false
	for cell in world.water_cells():
		if cell.y==int(goal.cell[1]) and cell.x>=world.actor_cell().x and cell.x<=int(goal.cell[0]) and world.water_at(cell)>=200:deep=true;break
	if not deep:
		out.stage="explore";out.title="照亮通路，走进遗迹";out.detail="把夜灯放在遗迹附近，再走到标记处；容器可以回收带走。";return
	var placed:bool=false;var bound:bool=false
	for item in vessels:
		if item.location.kind=="world":placed=true;bound=bound or not item.rules.is_empty()
	if not placed:
		out.stage="place";out.title="处理入口积水";out.detail="可在水面上方放置容器并编织吸水；也能手工搬水，或挖开地板排水。"
	elif not bound:
		out.stage="weave";out.title="给造物编织行为";out.detail="选中容器，按 Tab 编辑。先预演一拍，再应用；草稿不会自动运行。"
	else:
		out.stage="running";out.title="观察自己的造物";out.detail="继续探索让规则运行；选中造物可看上一拍结果。没有动作时检查条件、位置和容量。"
