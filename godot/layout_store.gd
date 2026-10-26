extends RefCounted
class_name LayoutStore

const PATH := "user://layouts.json"
const FORMAT_VERSION := 1
const ACTIVE := "__active__"

var _doc: Dictionary = {}


func _init() -> void:
	_load()


func _load() -> void:
	_doc = {"version": FORMAT_VERSION, "active": "", "slots": {}}
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var doc: Dictionary = parsed
	if int(doc.get("version", 0)) > FORMAT_VERSION:
		return
	_doc["version"] = FORMAT_VERSION
	if typeof(doc.get("slots")) == TYPE_DICTIONARY:
		_doc["slots"] = doc["slots"]
	_doc["active"] = str(doc.get("active", ""))


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_doc, "  "))
	f.close()


func slot_names() -> Array:
	var names: Array = _doc["slots"].keys()
	names.erase(ACTIVE)
	names.sort()
	return names


func has_slot(name: String) -> bool:
	return (_doc["slots"] as Dictionary).has(name)


func get_slot(name: String) -> Dictionary:
	return (_doc["slots"] as Dictionary).get(name, {})


func set_slot(name: String, payload: Dictionary) -> void:
	(_doc["slots"] as Dictionary)[name] = payload


func erase_slot(name: String) -> bool:
	if not has_slot(name):
		return false
	(_doc["slots"] as Dictionary).erase(name)
	if _doc["active"] == name:
		_doc["active"] = ""
	return true


func active_slot() -> String:
	return str(_doc["active"])


func set_active_slot(name: String) -> void:
	_doc["active"] = name


func export_slot(name: String) -> String:
	var out := {
		"version": FORMAT_VERSION,
		"slots": {name: get_slot(name)},
	}
	if _doc["active"] == name:
		out["active"] = name
	return JSON.stringify(out, "  ")


func export_all() -> String:
	return JSON.stringify({
		"version": FORMAT_VERSION,
		"active": _doc["active"],
		"slots": _doc["slots"],
	}, "  ")


func import_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Not valid JSON.", "added": []}
	var doc: Dictionary = parsed
	if int(doc.get("version", FORMAT_VERSION)) > FORMAT_VERSION:
		return {"ok": false, "error": "Made by a newer Fraypad.", "added": []}
	if typeof(doc.get("slots")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "No layouts in this file.", "added": []}

	var added: Array = []
	for raw_name in (doc["slots"] as Dictionary):
		var name := str(raw_name)
		var payload: Variant = (doc["slots"] as Dictionary)[raw_name]
		if typeof(payload) != TYPE_DICTIONARY:
			continue
		var final := _unique_name(name)
		set_slot(final, payload)
		added.append(final)
	if added.is_empty():
		return {"ok": false, "error": "No usable layouts in this file.", "added": []}
	save()
	return {"ok": true, "error": "", "added": added}


func _unique_name(name: String) -> String:
	if name == "" or name == ACTIVE:
		name = "Imported"
	if not has_slot(name):
		return name
	var n := 2
	while has_slot("%s (%d)" % [name, n]):
		n += 1
	return "%s (%d)" % [name, n]
