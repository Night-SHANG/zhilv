extends RefCounted
## 单写者检查点：同一文件保存实例、归属和库存。无多进程锁/断电耐久保证。
const Codec = preload("res://runtime/snapshot_codec.gd")
const ROOT: String = "user://checkpoints"

func slot_path(slot: String) -> String:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-]{1,64}\\z")
	if regex.search(slot) == null:
		return ""
	return ROOT.path_join(slot + ".json")

func _read(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Codec.reject("missing_or_unreadable")
	if file.get_length() > Codec.MAX_BYTES:
		file.close()
		return Codec.reject("byte_budget")
	var text: String = file.get_as_text()
	file.close()
	return {"ok": true, "text": text}

func save(store, slot: String) -> Dictionary:
	var path: String = slot_path(slot)
	if path.is_empty():
		return Codec.reject("invalid_slot")
	var text: String = store.checkpoint_json()
	if not store.validate_checkpoint(text).ok:
		return Codec.reject("invalid_snapshot")
	if DirAccess.make_dir_recursive_absolute(ROOT) != OK:
		return Codec.reject("cannot_create_directory")
	if FileAccess.file_exists(path):
		var existing: Dictionary = _read(path)
		if not existing.ok or not store.validate_checkpoint(existing.text).ok:
			return Codec.reject("refuse_overwrite_invalid_primary")
	var tmp: String = path + ".tmp"
	var bak: String = path + ".bak"
	var file = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return Codec.reject("cannot_write_temp")
	file.store_string(text)
	file.flush()
	file.close()
	var written: Dictionary = _read(tmp)
	if not written.ok or written.text != text or not store.validate_checkpoint(written.text).ok:
		return Codec.reject("temp_verification_failed")
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak) and DirAccess.remove_absolute(bak) != OK:
			return Codec.reject("cannot_replace_backup")
		if DirAccess.rename_absolute(path, bak) != OK:
			return Codec.reject("cannot_backup_primary")
	if DirAccess.rename_absolute(tmp, path) != OK:
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(bak, path)
		return Codec.reject("cannot_commit_temp")
	return {"ok": true, "error": ""}

func load_into(store, slot: String, allow_backup: bool = false) -> Dictionary:
	var path: String = slot_path(slot)
	if path.is_empty():
		return Codec.reject("invalid_slot")
	var primary: Dictionary = _read(path)
	if primary.ok:
		var result: Dictionary = store.load_checkpoint(primary.text)
		if result.ok:
			return {"ok": true, "error": "", "recovered": false}
	if allow_backup:
		var backup: Dictionary = _read(path + ".bak")
		if backup.ok and store.load_checkpoint(backup.text).ok:
			# 恢复只改变内存，不覆盖损坏主文件；调用方可保存到新槽位。
			return {"ok": true, "error": "", "recovered": true}
	return Codec.reject("no_valid_checkpoint")
