extends RefCounted

## Named layout slots, on disk and as portable JSON.
##
## A *layout* is the four thumb-unit centres and scales. Layouts get their own
## file (`user://layouts.json`) rather than sharing `config.cfg` with the server
## address: the two used to overwrite each other, because saving the server
## rebuilt the config file from scratch and dropped every layout key with it.
##
## The on-disk document is plain JSON so a layout can be exported from one phone
## and imported on another. `version` guards the format; a document from a newer
## version is refused rather than silently half-read.
##
## Unit centres are fractions of the canvas (x of width, y of height) so a layout
## keeps its proportions on a different screen instead of landing off-screen.
class_name LayoutStore

const PATH := "user://layouts.json"
const FORMAT_VERSION := 1

## Sentinel slot name meaning "the layout currently in effect". Always exists.
const ACTIVE := "__active__"

## JSON value: {"version": 1, "active": "<slot>", "slots": {"<name>": {...}}}
var _doc: Dictionary = {}


func _init() -> void:
	_load()


# ── Disk ─────────────────────────────────────────────────────────────────

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
		# A corrupt or hand-edited file must not take the app down; start clean.
		push_warning("layouts.json unreadable; starting with no saved layouts")
		return
	var doc: Dictionary = parsed
	if int(doc.get("version", 0)) > FORMAT_VERSION:
		push_warning("layouts.json is from a newer Fraypad; ignoring it")
		return
	_doc["version"] = FORMAT_VERSION
	if typeof(doc.get("slots")) == TYPE_DICTIONARY:
		_doc["slots"] = doc["slots"]
	_doc["active"] = str(doc.get("active", ""))


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("could not write " + PATH)
		return
	f.store_string(JSON.stringify(_doc, "  "))
	f.close()


# ── Slots ────────────────────────────────────────────────────────────────

## Every save-slot name, sorted, excluding the built-in active slot.
func slot_names() -> Array:
	var names: Array = _doc["slots"].keys()
	names.erase(ACTIVE)
	names.sort()
	return names


func has_slot(name: String) -> bool:
	return (_doc["slots"] as Dictionary).has(name)


## The stored payload for a slot, or an empty dictionary.
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


## The slot the user last loaded, or "" when they are on the built-in layout.
func active_slot() -> String:
	return str(_doc["active"])


func set_active_slot(name: String) -> void:
	_doc["active"] = name


# ── JSON import / export ─────────────────────────────────────────────────

## A single slot as a standalone, shareable JSON document.
func export_slot(name: String) -> String:
	var out := {
		"version": FORMAT_VERSION,
		"slots": {name: get_slot(name)},
	}
	if _doc["active"] == name:
		out["active"] = name
	return JSON.stringify(out, "  ")


## Every slot as one standalone document, so a whole set moves together.
func export_all() -> String:
	return JSON.stringify({
		"version": FORMAT_VERSION,
		"active": _doc["active"],
		"slots": _doc["slots"],
	}, "  ")


## Merge a JSON document into the store.
##
## Returns a report dictionary: `ok`, `added` (names imported), `error`. An
## unreadable document, a wrong version or a missing `slots` object is reported
## rather than throwing, so the UI can explain what went wrong. Existing slots
## keep their names by gaining a ` (2)`-style suffix rather than being replaced.
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


## `name`, or `name (2)`, `name (3)`… if that name is taken.
func _unique_name(name: String) -> String:
	if name == "":
		name = "Imported"
	if name == ACTIVE:
		name = "Imported"
	if not has_slot(name):
		return name
	var n := 2
	while has_slot("%s (%d)" % [name, n]):
		n += 1
	return "%s (%d)" % [name, n]
