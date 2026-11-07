extends Control
## 只读世界投影。颜色、比例和装饰不参与碰撞；选择格直接反算到权威坐标。
signal cell_clicked(cell: Vector2i, button: int, shift: bool)
const Style = preload("res://presentation/ui_theme.gd")
var world
var objective_markers:Array=[]
var runtime
var selected_id: String="creation:vessel"
var tool: String="select"
var user_zoom: float=1.0
var _time: float=0.0
var _mouse_cell:=Vector2i.ZERO
var _hover: bool=false
var _font: Font
var _last_foot:=Vector2.ZERO
var _walking: bool=false
var _face: float=1.0

func _ready() -> void:
	clip_contents=true; mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hover=true)
	mouse_exited.connect(func(): _hover=false)
	_font=Style.make().default_font

func zoom_value() -> float:
	return maxf(1.0,minf(size.x/320.0,size.y/230.0))*user_zoom
func camera_origin() -> Vector2:
	return size*Vector2(0.5,0.47)-Vector2(3.3*16.0,0.0)*zoom_value()
func screen_to_cell(point: Vector2) -> Vector2i:
	var p: Vector2=(point-camera_origin())/(zoom_value()*16.0)
	return Vector2i(floori(p.x),floori(p.y))
func cell_center(cell: Vector2i) -> Vector2:
	return camera_origin()+(Vector2(cell)+Vector2(0.5,0.5))*16.0*zoom_value()
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_cell=screen_to_cell(event.position); queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			user_zoom=clampf(user_zoom*(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.1),0.65,1.6)
		else: cell_clicked.emit(screen_to_cell(event.position),event.button_index,event.shift_pressed)
		accept_event()
func _process(delta: float) -> void:
	if world==null: return
	if runtime!=null and not runtime.clock_state().paused: _time+=delta
	var foot:=Vector2(world.actor_body_foot())/64.0
	_walking=absf(foot.x-_last_foot.x)>0.01
	if _walking: _face=signf(foot.x-_last_foot.x)
	_last_foot=foot
	queue_redraw()
func _rect(pos: Vector2,extent: Vector2,color: Color) -> void:
	draw_rect(Rect2(pos,extent),color)
func _glow(center: Vector2,color: Color,radius: float) -> void:
	for i in range(8,0,-1): draw_circle(center,radius*float(i)/8.0,Color(color,0.018+0.006*float(8-i)))
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("111e2b"))
	if world==null: return
	var night: bool=runtime.clock_state().night if runtime!=null else false
	# 多层冷色洞壁；装饰不会伪装成可挖掘前景地形。
	for i in range(12):
		var c:=Color("152c3a").lerp(Color("0b151e"),float(i)/11.0)
		draw_rect(Rect2(0,size.y*i/12.0,size.x,size.y/12.0+1),c)
	var origin: Vector2=camera_origin(); var z: float=zoom_value()
	draw_set_transform(origin,0,Vector2(z,z))
	# 透视退后的石砌墙、柱廊与苔藓只作为背景。
	for y in range(-5,4):
		for x in range(-4,11):
			var c:=Color("1b2e3b") if (x+y)%3 else Color("1e3441")
			draw_rect(Rect2(x*16+1,y*16+1,14,14),c)
	for x in [-2,3,8]:
		_rect(Vector2(x*16-5,-65),Vector2(8,80),Color("223947"))
		_rect(Vector2(x*16-7,-64),Vector2(12,4),Color("2c4855"))
		for yy in range(-60,16,12): draw_line(Vector2(x*16-5,yy),Vector2(x*16+3,yy),Color("172a37"),1)
	# 右侧遗迹地标与左侧交水器的位置对应真实任务对象。
	var arch:=Vector2(8.5*16,-8)
	draw_rect(Rect2(arch+Vector2(-15,-45),Vector2(30,55)),Color("132737"))
	draw_arc(arch+Vector2(0,-31),14,PI,TAU,20,Color("3c626f"),3)
	for side in [-1,1]: _rect(arch+Vector2(side*14-2,-31),Vector2(4,47),Color("34515c"))
	draw_polyline(PackedVector2Array([arch+Vector2(0,-32),arch+Vector2(7,-20),arch+Vector2(0,-8),arch+Vector2(-7,-20),arch+Vector2(0,-32)]),Color("69b7c5"),1,true)
	_glow(arch+Vector2(0,-20),Style.AQUA,26)
	var snapshot: Dictionary=world.rule_view()
	for tile in snapshot.terrain:
		var cell:=Vector2i(tile.cell[0],tile.cell[1]); var p:=Vector2(cell)*16
		var variation: float=float(posmod(cell.x*31+cell.y*17,7))/45.0
		var base:=Color("455663").lightened(variation)
		if cell.y>=3: base=Color("34424c").lightened(variation)
		if cell.x<1: base=base.lerp(Color("78674e"),0.3)
		_rect(p,Vector2(16,16),Color("1c2933"))
		_rect(p+Vector2(0.5,0.5),Vector2(15,14),base)
		draw_line(p+Vector2(1,1),p+Vector2(15,1),base.lightened(0.16),1)
		draw_line(p+Vector2(3,9),p+Vector2(9,9),base.darkened(0.13),0.8)
		if posmod(cell.x+cell.y*3,4)==0: draw_line(p+Vector2(11,2),p+Vector2(10,6),base.darkened(0.3),1)
		if world.material_at(cell+Vector2i.UP).is_empty() and cell.y>=1:
			_rect(p,Vector2(16,1.5),Color("6d806a"))
			for xx in [3,9,13]: draw_line(p+Vector2(xx,0),p+Vector2(xx-1,-2),Color("75916b"),0.7)
	# 低成本可重复的藤条，只装饰洞顶。
	for x in [-3,0,4,9]:
		var start:=Vector2(x*16+6,-64)
		for j in range(6+posmod(x,3)):
			var p:=start+Vector2(sin(float(j)*0.8+x)*2,j*4)
			draw_line(p,p+Vector2(0,4),Color("527261"),0.7)
			draw_line(p,p+Vector2(3 if j%2 else -3,2),Color("688465"),1.5)
	# 所有水面高度都来自整数账本，波纹不改变体积。
	for water in snapshot.get("water",[]):
		var cell:=Vector2i(water.cell[0],water.cell[1]); var height: float=float(water.units)/1000.0*16.0
		var p:=Vector2(cell)*16+Vector2(0,16-height)
		draw_rect(Rect2(p,Vector2(16,height)),Color(0.12,0.49,0.65,0.78))
		if world.water_at(cell+Vector2i.UP)==0:
			draw_line(p,p+Vector2(16,0),Color("9cdae0"),0.8)
			var ripple: float=sin(_time*2.2+cell.x*1.7)*1.1
			draw_line(p+Vector2(3,2+ripple),p+Vector2(11,2+ripple),Color(0.54,0.85,0.88,0.45),0.6)
	for e in snapshot.entities.instances:
		if e.location.kind!="world": continue
		var p:=Vector2(e.location.cell[0],e.location.cell[1])*16
		if e.material_id=="user:crystal":
			if e.state.light_on: _glow(p+Vector2(8,8),Style.GOLD,36)
			_rect(p+Vector2(4,2),Vector2(8,12),Color("c69856")); _rect(p+Vector2(5,4),Vector2(6,8),Style.GOLD if e.state.light_on else Color("384854"))
			draw_arc(p+Vector2(8,2),3,PI,TAU,8,Color("d4bd89"),1)
		else:
			_rect(p+Vector2(1,2),Vector2(14,13),Color("39586a")); _rect(p+Vector2(2,3),Vector2(12,10),Color("293f4d"))
			var h: float=8.0*e.state.water_units/maxf(1,e.state.capacity_units)
			_rect(p+Vector2(3,12-h),Vector2(10,h),Color("51b5c7"))
			draw_rect(Rect2(p+Vector2(1,2),Vector2(14,13)),Color("9daea7"),false,1)
			for xx in [3,12]: draw_circle(p+Vector2(xx,4),0.8,Style.GOLD)
			if not e.rules.is_empty():
				var active: Color=Style.AQUA if e.state.water_units<e.state.capacity_units else Style.GOLD
				draw_circle(p+Vector2(8,0),1.8,active)
		if e.id==selected_id: draw_rect(Rect2(p-Vector2.ONE,Vector2(18,18)),Style.GOLD,false,0.7)
	# 探险者：状态驱动位置，部件变换驱动步态，没有第二套角色坐标。
	var foot:=Vector2(world.actor_body_foot())/64.0
	var gait: float=sin(_time*18.0)*2.0 if _walking else 0.0
	_glow(foot+Vector2(0,-13),Color("d8a665"),20)
	_rect(foot+Vector2(-5,-7+gait),Vector2(4,7),Color("172634"))
	_rect(foot+Vector2(1,-7-gait),Vector2(4,7),Color("172634"))
	_rect(foot+Vector2(-6,-2+gait),Vector2(6,2),Color("b7a382"))
	_rect(foot+Vector2(1,-2-gait),Vector2(6,2),Color("b7a382"))
	draw_colored_polygon(PackedVector2Array([foot+Vector2(-4,-21),foot+Vector2(4,-21),foot+Vector2(7,-7),foot+Vector2(-7,-7)]),Color("c39962"))
	_rect(foot+Vector2(-5*_face-3,-20),Vector2(5,10),Color("6e5143"))
	_rect(foot+Vector2(-3,-27),Vector2(7,7),Color("e5c5a3")); _rect(foot+Vector2(-4,-28),Vector2(9,3),Color("523c36"))
	_rect(foot+Vector2(3*_face,-25),Vector2(1,1),Color("222d34"))
	draw_line(foot+Vector2(-4,-20),foot+Vector2(5,-20),Style.AQUA,2)
	draw_line(foot+Vector2(-4,-20),foot+Vector2(-9*_face,-16+sin(_time*3)),Style.AQUA,1.5)
	# 标记只读来自当前目标；不会生成物品、移动角色或替玩家完成任务。
	for marker in objective_markers:
		var point:=Vector2(marker.cell)*16
		draw_rect(Rect2(point+Vector2.ONE,Vector2(14,14)),Color(Style.GOLD,0.15))
		draw_rect(Rect2(point+Vector2.ONE,Vector2(14,14)),Style.GOLD,false,0.8)
		draw_line(point+Vector2(5,8),point+Vector2(11,8),Style.GOLD,0.7)
		draw_line(point+Vector2(8,5),point+Vector2(8,11),Style.GOLD,0.7)
	# 光标不影响状态；权限失败时只显示提示。
	if _hover:
		var c: Color=Style.AQUA if world._access(_mouse_cell).ok else Style.BAD
		draw_rect(Rect2(Vector2(_mouse_cell)*16,Vector2(16,16)),Color(c,0.08))
		draw_rect(Rect2(Vector2(_mouse_cell)*16,Vector2(16,16)),c,false,0.65)
	draw_set_transform(Vector2.ZERO)
	if _font!=null:
		draw_string(_font,Vector2(24,32),"湿暗遗迹",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Style.TEXT)
		draw_string(_font,Vector2(25,56),"让你创造的规则，改变眼前的世界。",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Style.MUTED)
		var caption: String="滚轮缩放  ·  A / D 移动  ·  空格跳跃"
		draw_string(_font,Vector2(24,size.y-22),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Style.MUTED)
		if _hover:
			var desc: String="格子 (%d, %d)  ·  水量 %d"%[_mouse_cell.x,_mouse_cell.y,world.water_at(_mouse_cell)]
			draw_string(_font,Vector2(24,size.y-45),desc,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Style.AQUA)
