extends RefCounted
## 保存完整游戏与未发布编辑草稿；复用原PlaySession和CheckpointFiles。
## 先检查整个信封，草稿缺线可以恢复，但恢复绝不等同于发布或执行。
const Codec=preload("res://runtime/snapshot_codec.gd")
const Draft=preload("res://runtime/rule_draft.gd")
const TOOLS=["select","mine","stone","vessel","lamp","collect","release"]
const MAX_DRAFTS:int=64
var _play
var editor:Dictionary
func _init(play, state:Dictionary={}) -> void:
	_play=play
	editor=state.duplicate(true) if not state.is_empty() else empty_editor()
static func empty_editor()->Dictionary:return {"selected":"","tool":"select","drafts":{}}
static func integer_tree(value:Variant)->Variant:
	# 完整原文先经严格整数词法检查；消除Godot JSON将整数解析为float的差异。
	if value is Dictionary:
		var out:Dictionary={}
		for key in value:out[key]=integer_tree(value[key])
		return out
	if value is Array:
		var out:Array=[]
		for child in value:out.append(integer_tree(child))
		return out
	if typeof(value)==TYPE_FLOAT and is_finite(value) and floor(value)==value:return int(value)
	return value
func checkpoint_json()->String:
	if _play==null:return "{}"
	return JSON.stringify({"format":"rw.workspace/0.1","play":integer_tree(JSON.parse_string(_play.checkpoint_json())),"editor":editor})
func validate_checkpoint(text:String)->Dictionary:
	if _play==null:return Codec.reject("workspace_unbound")
	var error:String=Codec._lexical_error(text)
	if not error.is_empty():return Codec.reject(error)
	var parser:=JSON.new()
	if parser.parse(text)!=OK:return Codec.reject("workspace_json")
	var value:Variant=integer_tree(parser.data)
	if not value is Dictionary:return Codec.reject("workspace_fields")
	if value.get("format")=="rw.play/0.1":
		var legacy:Dictionary=_play.validate_checkpoint(text)
		if not legacy.ok:return legacy
		return {"ok":true,"error":"","play_text":text,"editor":empty_editor(),"legacy":true}
	if not Codec._shape(value,["format","play","editor"]) or value.format!="rw.workspace/0.1":return Codec.reject("workspace_fields")
	var play_text:String=JSON.stringify(value.play)
	var checked:Dictionary=_play.validate_checkpoint(play_text)
	if not checked.ok:return checked
	var e:Variant=value.editor
	if not Codec._shape(e,["selected","tool","drafts"]) or not e.selected is String or not e.tool is String or not e.tool in TOOLS or not e.drafts is Dictionary or e.drafts.size()>MAX_DRAFTS:return Codec.reject("workspace_editor_fields")
	var entities:Dictionary={}
	for item in value.play.expedition.simulation.world.entities.instances:entities[item.id]=true
	if not e.selected.is_empty() and not entities.has(e.selected):return Codec.reject("workspace_selected_missing")
	var drafts:Dictionary={}
	for id in e.drafts:
		if not Codec.identifier(id) or not entities.has(id):return Codec.reject("workspace_draft_target_missing")
		var draft=Draft.new()
		var restored:Dictionary=draft.restore(e.drafts[id])
		if not restored.ok:return Codec.reject("workspace_"+restored.error)
		drafts[id]=draft.snapshot()
	return {"ok":true,"error":"","play_text":play_text,"editor":{"selected":e.selected,"tool":e.tool,"drafts":drafts},"legacy":false}
func load_checkpoint(text:String)->Dictionary:
	var checked:Dictionary=validate_checkpoint(text)
	if not checked.ok:return checked
	var prior:Dictionary=editor
	editor=checked.editor.duplicate(true)
	var applied:Dictionary=_play.load_checkpoint(checked.play_text)
	if not applied.ok:editor=prior;return applied
	return {"ok":true,"error":"","legacy":checked.legacy}
