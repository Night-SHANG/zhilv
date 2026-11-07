extends RefCounted
## 只有程序绘制的界面样式；系统字体按名称查找，不分发系统字体文件。
const BG = Color("101923")
const PANEL = Color("182631")
const PANEL_ALT = Color("1f303c")
const EDGE = Color("344d5c")
const TEXT = Color("e6e8e1")
const MUTED = Color("8fa9b7")
const GOLD = Color("e6ba72")
const AQUA = Color("71c9d2")
const BAD = Color("f18d82")

static func box(color: Color=PANEL, border: Color=EDGE, radius: int=9, padding: int=12) -> StyleBoxFlat:
	var b:=StyleBoxFlat.new(); b.bg_color=color; b.border_color=border
	b.set_border_width_all(1); b.set_corner_radius_all(radius)
	b.content_margin_left=padding; b.content_margin_right=padding
	b.content_margin_top=padding; b.content_margin_bottom=padding
	return b

static func make() -> Theme:
	var t:=Theme.new(); var f:=SystemFont.new()
	f.font_names=PackedStringArray(["Noto Sans CJK SC","Microsoft YaHei","PingFang SC","WenQuanYi Micro Hei"])
	t.default_font=f; t.default_font_size=16
	for type in ["Label","Button","CheckBox","OptionButton","LineEdit","SpinBox","TextEdit"]:
		t.set_color("font_color",type,TEXT)
	t.set_color("font_disabled_color","Button",MUTED)
	for type in ["Button","OptionButton"]:
		t.set_stylebox("normal",type,box(PANEL_ALT,EDGE,7,9))
		t.set_stylebox("hover",type,box(Color("29414c"),AQUA,7,9))
		t.set_stylebox("pressed",type,box(Color("324a50"),GOLD,7,9))
		t.set_stylebox("disabled",type,box(Color("18212a"),Color("263642"),7,9))
		t.set_stylebox("focus",type,box(Color(0,0,0,0),GOLD,7,2))
	t.set_stylebox("panel","PanelContainer",box())
	t.set_stylebox("normal","LineEdit",box(BG,EDGE,5,8))
	t.set_stylebox("focus","LineEdit",box(BG,AQUA,5,8))
	t.set_stylebox("panel","PopupMenu",box())
	t.set_color("font_color","PopupMenu",TEXT)
	t.set_constant("separation","VBoxContainer",10)
	t.set_constant("separation","HBoxContainer",8)
	return t

static func label(text: String, font_size: int=16, color: Color=TEXT) -> Label:
	var l:=Label.new(); l.text=text; l.add_theme_font_size_override("font_size",font_size); l.add_theme_color_override("font_color",color)
	return l

static func button(text: String, action: Callable) -> Button:
	var b:=Button.new(); b.text=text; b.focus_mode=Control.FOCUS_NONE
	b.pressed.connect(action); return b

static func note(text: String) -> Label:
	var l:=label(text,14,MUTED); l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return l
