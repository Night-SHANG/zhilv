extends SceneTree
## 创作层合同：发布/绑定/分享直接操作真实运行时，不用假实现替代。
const World = preload("res://runtime/world_session.gd")
const Runtime = preload("res://runtime/rule_runtime.gd")
const Files = preload("res://runtime/checkpoint_files.gd")
var passed: int = 0
var failed: int = 0
var catalog: Dictionary
var world_text: String
var pack_text: String

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func normalize(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = {}
		for k in v: d[k] = normalize(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v: a.append(normalize(x))
		return a
	return int(v) if typeof(v) == TYPE_FLOAT and is_finite(v) and floor(v) == v else v

func fixture() -> Array:
	var w = World.new(catalog)
	check(w.load_checkpoint(world_text).ok, "authoring_world_load")
	var r = Runtime.new(catalog, w)
	check(r.install_pack(pack_text).ok, "authoring_pack_load")
	return [w, r]

func lamp(id: String = "user:crafted", version: int = 1, value: bool = true) -> Dictionary:
	return {"id":id,"version":version,"parameters":{},"nodes":[
		{"id":"on","op":"bool","inputs":{},"config":{"value":true}},
		{"id":"value","op":"bool","inputs":{},"config":{"value":value}},
		{"id":"lamp","op":"set_light","inputs":{"when":"on","value":"value"},"config":{}}
	],"effects":["lamp"]}

func pack(module: Dictionary) -> String:
	return JSON.stringify({"format":"rw.rules/0.1","modules":[module]})

func ref(id: String = "user:crafted", version: int = 1) -> Array:
	return [{"id":id,"version":version}]

func unchanged(r, before: String, result: Dictionary, label: String) -> void:
	check(not result.ok, label)
	check(r.checkpoint_json() == before, label + "_atomic")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var root: String = OS.get_environment("RULEWEAVER_FIXTURE_ROOT")
	catalog = normalize(JSON.parse_string(FileAccess.get_file_as_string(root.path_join("rules_catalog.json"))))
	world_text = FileAccess.get_file_as_string(root.path_join("rules_world.json"))
	pack_text = FileAccess.get_file_as_string(root.path_join("rules_pack.json"))
	var f: Array = fixture()
	var w = f[0]
	var r = f[1]
	check(r.has_method("publish_pack"), "authoring_publish_api_exists")
	if not r.has_method("publish_pack"):
		finish()
		return
	var before: String = r.checkpoint_json()
	var preview: Dictionary = r.preview_pack(pack(lamp()), {"creation:001":ref()})
	check(preview.ok, "preview_new_rule_with_binding")
	check(r.checkpoint_json() == before, "preview_does_not_mutate")
	var result: Dictionary = r.publish_pack(pack(lamp()), {"creation:001":ref()})
	check(result.ok, "publish_unregistered_user_rule: " + str(result.get("error")))
	if not result.ok:
		finish()
		return
	check(r.advance(false).ok and w.get_instance("creation:001").state.light_on, "new_rule_actually_runs")
	check(w.get_instance("creation:001").state.water_units == 0, "replace_binding_removes_old_absorb")
	check(r.publish_pack(pack(lamp())).ok, "identical_reimport_is_idempotent")
	before = r.checkpoint_json()
	unchanged(r, before, r.publish_pack(pack(lamp("user:crafted", 1, false))), "same_version_conflict")
	check(r.publish_pack(pack(lamp("user:crafted", 2, false))).ok, "publish_new_version_without_rebinding")
	check(w.get_instance("creation:001").rules == ref(), "old_instance_pins_version_one")
	check(r.bind_rules("creation:004", ref("user:crafted",2)).ok, "bind_owned_inventory_instance")
	check(w.place("creation:004", Vector2i(1,2)).ok, "place_new_version_instance")
	r.advance(false)
	check(w.get_instance("creation:001").state.light_on and not w.get_instance("creation:004").state.light_on, "versions_coexist_different_behaviors")
	before = r.checkpoint_json()
	unchanged(r,before,r.bind_rules("creation:003",ref()), "occluded_binding_rejected")
	unchanged(r,before,r.bind_rules("missing:object",ref()), "missing_instance_binding_rejected")
	unchanged(r,before,r.bind_rules("creation:001",ref("user:crafted",99)), "missing_bound_version")
	unchanged(r,before,r.bind_rules("creation:001",ref()+ref()), "duplicate_bound_rule")
	unchanged(r,before,r.publish_pack(pack(lamp("user:later")),{"creation:004":ref("user:later"),"missing:object":ref("user:later")}), "batch_binding_failure_preserves_pack_and_world")
	unchanged(r,before,r.publish_pack(pack(lamp("core:untrusted"))), "reserved_namespace_rejected")
	var bad: Dictionary = lamp("user:broken")
	bad.nodes[2].inputs.value = "absent"
	unchanged(r,before,r.publish_pack(pack(bad)), "invalid_graph_cannot_publish")
	unchanged(r,before,r.publish_pack('{"format":"rw.rules/0.1","format":"rw.rules/0.1","modules":[]}'), "duplicate_json_rejected")
	unchanged(r,before,r.publish_pack(pack(lamp("user:float")).replace('"version":1', '"version":1.5')), "fractional_version_rejected")
	check(r.bind_rules("creation:004",[]).ok, "explicit_unbind")
	check(w.get_instance("creation:004").state.water_units == 0, "unbind_keeps_state")

	# 回调在通知时看到已同时采用的新程序和世界，不能重入发布或推进。
	var observed: Dictionary = {}
	var callback: Callable = func():
		observed["checkpoint"] = r.validate_checkpoint(r.checkpoint_json()).ok
		observed["publish"] = r.publish_pack(pack(lamp("user:reentrant")))
		observed["advance"] = r.advance(true)
	w.reloaded.connect(callback)
	check(r.publish_pack(pack(lamp("user:observable")),{"creation:004":ref("user:observable")}).ok, "publish_with_observer")
	w.reloaded.disconnect(callback)
	check(observed.get("checkpoint",false), "observer_never_sees_half_updated_revision")
	check(observed.publish.error == "runtime_busy" and observed.advance.error == "runtime_busy", "publication_reentry_rejected")

	# 行为调用依赖闭包；导出中不包含地形、资源、材料注册权限。
	var exported: Dictionary = r.export_rule("user:absorb",1)
	check(exported.ok, "export_reusable_rule")
	var scroll: Dictionary = normalize(JSON.parse_string(exported.text))
	check(scroll.format == "rw.scroll/0.1" and scroll.rules.modules.size()==2, "export_exact_dependency_closure")
	check(scroll.keys().size()==3 and not scroll.has("world") and not scroll.has("materials"), "scroll_has_no_world_or_material_authority")
	var empty_data: Dictionary = normalize(JSON.parse_string(world_text))
	for e in empty_data.entities.instances: e.rules=[]
	var base: Dictionary = catalog.duplicate(true)
	base.rules={}
	var w2 = World.new(base)
	check(w2.load_checkpoint(JSON.stringify(empty_data)).ok,"fresh_world_without_rule_registry")
	var r2 = Runtime.new(base,w2)
	var original_world: String = w2.checkpoint_json()
	check(r2.import_scroll(exported.text).ok, "import_self_contained_scroll_into_fresh_world")
	check(w2.checkpoint_json()==original_world,"import_does_not_bind_or_execute")
	check(r2.bind_rules("creation:001",ref("user:absorb")).ok, "bind_imported_rule")
	check(r2.advance(false).ok and w2.get_instance("creation:001").state.water_units==100,"imported_dependency_actually_executes")
	check(r2.export_rule("user:absorb",1).text==exported.text,"scroll_deterministic_roundtrip")
	before=r2.checkpoint_json()
	var broken: Dictionary=scroll.duplicate(true)
	broken.rules.modules.remove_at(1)
	unchanged(r2,before,r2.import_scroll(JSON.stringify(broken)),"missing_scroll_dependency_even_if_local_exists")
	broken=scroll.duplicate(true)
	broken.rules.modules.append(lamp("user:smuggled"))
	unchanged(r2,before,r2.import_scroll(JSON.stringify(broken)),"unrelated_scroll_module_rejected")
	broken=scroll.duplicate(true)
	broken.entry.version=9
	unchanged(r2,before,r2.import_scroll(JSON.stringify(broken)),"missing_scroll_entry")
	broken=scroll.duplicate(true)
	broken.materials={}
	unchanged(r2,before,r2.import_scroll(JSON.stringify(broken)),"scroll_cannot_register_materials")
	unchanged(r2,before,r2.import_scroll(" ".repeat(262145)),"scroll_byte_budget")
	unchanged(r2,before,r2.import_scroll('{"format":"rw.scroll/0.1","entry":{},"entry":{},"rules":{}}'),"scroll_duplicate_key")

	# 无预注册的新图和版本，在全新运行时恢复；老存档格式保持不变。
	var files=Files.new()
	var slot: String="authoring_"+str(OS.get_process_id())
	check(files.save(r,slot).ok,"save_dynamic_rule_registry")
	var restored_world=World.new(catalog)
	var restored=Runtime.new(catalog,restored_world)
	check(files.load_into(restored,slot).ok,"restore_dynamic_rules_without_external_preregistration")
	check(restored.checkpoint_json()==r.checkpoint_json(),"dynamic_revision_exact_disk_roundtrip")
	var before_restored: String=restored.checkpoint_json()
	var saved: Dictionary=normalize(JSON.parse_string(before_restored))
	saved.rules.modules[0].nodes[0].op="script"
	unchanged(restored,before_restored,restored.load_checkpoint(JSON.stringify(saved)),"hostile_saved_graph_rejected")
	check(restored.advance(true).ok and restored_world.get_instance("creation:004").state.light_on,"restored_authored_program_runs")
	for suffix in ["", ".bak", ".tmp"]:
		var path: String=files.slot_path(slot)+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var saved_before_extra: String=r.checkpoint_json()
	check(r.publish_pack(pack(lamp("user:temporary"))).ok,"temporary_rule_before_rollback")
	check(r.load_checkpoint(saved_before_extra).ok,"explicit_checkpoint_rollback")
	check(r.next_rule_version("user:temporary").version==1,"restore_does_not_accumulate_unpersisted_registry")
	var without_old: Dictionary=normalize(JSON.parse_string(r.pack_json()))
	for i in range(without_old.modules.size()-1,-1,-1):
		if without_old.modules[i].id=="user:crafted" and without_old.modules[i].version==2:
			without_old.modules.remove_at(i)
	before=r.checkpoint_json()
	unchanged(r,before,r.install_pack(JSON.stringify(without_old)),"legacy_install_cannot_forget_published_version")
	finish()

func finish() -> void:
	print("AUTHORING_TEST_RESULT: ",passed," passed; ",failed," failed")
	quit(0 if failed==0 else 1)
