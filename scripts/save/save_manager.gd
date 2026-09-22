extends Node
## Autoload: SaveManager
##
## Reads/writes a single, human-readable JSON save file under user://.
## Owns the save-format version — GameState itself has no opinion on file
## format, it only hands over/accepts a plain state dictionary.
##
## Milestone 1.16 (docs/core-loop-sandbox.md, "Save/load"): the format gained
## GameState.chapter_run (the production chapter run's durable snapshot), so
## SAVE_VERSION is 2. Every load now goes through inspect_save() first — read,
## parse, migrate, validate the WHOLE file (the chapter run included, through
## ChapterRuntime.validate_snapshot()) — and only a file that passes every
## check ever reaches GameState.load_from_dict(): an unsupported or corrupted
## save never partially loads. Writes are atomic (a temporary file renamed
## over the real one), so a crash mid-write can't leave a half-written save.

## Emitted after load_game() successfully replaced GameState.
signal state_restored()
## Emitted after new_game() started `case_id` from scratch.
signal new_game_started(case_id: String)

const DEFAULT_SAVE_PATH := "user://save_game.json"
## Version 2 (Milestone 1.16) adds "state.chapter_run". Version 1 (every save
## before it) is migrated on load by treating the missing field as "no active
## core-loop run" — the only supported migration; nothing older ever existed.
const SAVE_VERSION := 2
const MIN_SUPPORTED_VERSION := 1
## What New Game starts when no case declares "new_game_entry": true — the
## original Milestone 0 behavior, kept for every caller that relied on it.
const DEFAULT_NEW_GAME_CASE := "case_00_sandbox"

## inspect_save() failure reasons — internal diagnostics, never shown raw to
## the player (the title screen maps any failure to one safe message).
const REASON_MISSING := "missing"
const REASON_UNREADABLE := "unreadable"
const REASON_CORRUPT := "corrupt"
const REASON_UNSUPPORTED_VERSION := "unsupported_version"
const REASON_INVALID_STATE := "invalid_state"
const REASON_INVALID_CHAPTER_RUN := "invalid_chapter_run"

## The slot every method below reads and writes. A variable rather than a
## constant purely so automated tests can point at a throwaway file instead
## of stomping the player's real save; gameplay never changes it.
var save_path: String = DEFAULT_SAVE_PATH


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## True only for a save that load_game() would actually accept — what the
## title screen's Continue button is gated on (a present-but-broken file is
## NOT resumable).
func has_resumable_save() -> bool:
	return inspect_save().get("ok", false) == true


## Reads, parses, migrates and fully validates the save WITHOUT touching
## GameState. Returns {"ok": bool, "reason": String (one of REASON_*, "" when
## ok), "version": int (the file's own version, -1 if unknown), "state":
## Dictionary (the migrated state, only when ok)}.
func inspect_save() -> Dictionary:
	if not has_save():
		return _inspection(false, REASON_MISSING, -1)
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return _inspection(false, REASON_UNREADABLE, -1)
	var text := file.get_as_text()
	file.close()

	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _inspection(false, REASON_CORRUPT, -1)
	var payload: Variant = parser.data
	if typeof(payload) != TYPE_DICTIONARY or typeof((payload as Dictionary).get("state")) != TYPE_DICTIONARY:
		return _inspection(false, REASON_CORRUPT, -1)

	# A file with no "version" predates the field being written consistently
	# and can only be version 1.
	var raw_version: Variant = (payload as Dictionary).get("version", MIN_SUPPORTED_VERSION)
	var version: int = int(raw_version) if typeof(raw_version) in [TYPE_INT, TYPE_FLOAT] and float(raw_version) == floorf(float(raw_version)) else -1
	if version < MIN_SUPPORTED_VERSION or version > SAVE_VERSION:
		return _inspection(false, REASON_UNSUPPORTED_VERSION, version)

	var state: Dictionary = ((payload as Dictionary).get("state") as Dictionary).duplicate(true)
	if version == 1:
		state["chapter_run"] = {}  # v1 -> v2: no chapter run existed yet.
	if not _is_state_well_formed(state):
		return _inspection(false, REASON_INVALID_STATE, version)
	var chapter_run: Variant = state.get("chapter_run", {})
	if typeof(chapter_run) != TYPE_DICTIONARY:
		return _inspection(false, REASON_INVALID_CHAPTER_RUN, version)
	if not (chapter_run as Dictionary).is_empty():
		var validation: Dictionary = ChapterRuntime.validate_snapshot(state)
		if validation.get("ok", false) != true:
			push_warning("SaveManager: the save's chapter run is invalid (%s) — it will not be loaded" % validation.get("reason", ""))
			return _inspection(false, REASON_INVALID_CHAPTER_RUN, version)

	var result: Dictionary = _inspection(true, "", version)
	result["state"] = state
	return result


func save_game() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"state": GameState.get_save_dict(),
	}
	# Write-then-rename: the real save is only ever replaced by a complete
	# file, never truncated and half-rewritten in place.
	var temp_path: String = save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager.save_game: could not open %s for writing (error %s)" % [temp_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	var rename_error: Error = DirAccess.rename_absolute(temp_path, save_path)
	if rename_error != OK:
		push_error("SaveManager.save_game: could not move %s into place (%s)" % [temp_path, error_string(rename_error)])
		DirAccess.remove_absolute(temp_path)
		return false
	return true


func load_game() -> bool:
	var inspection: Dictionary = inspect_save()
	if inspection.get("ok", false) != true:
		var reason: String = inspection.get("reason", "")
		if reason == REASON_MISSING:
			push_warning("SaveManager.load_game: no save file at %s" % save_path)
		else:
			push_error("SaveManager.load_game: the save at %s cannot be loaded (%s)" % [save_path, reason])
		return false
	GameState.load_from_dict(inspection.get("state", {}))
	state_restored.emit()
	return true


## Copies an existing save that cannot be loaded to a sibling
## "<save>.unreadable.json" file (replacing any earlier copy) so it survives
## a New Game overwriting the slot — kept for diagnosis, never loaded.
## Returns the copy's path, or "" when there was nothing to keep.
func preserve_unreadable_save() -> String:
	if not has_save() or has_resumable_save():
		return ""
	var backup_path: String = save_path.get_basename() + ".unreadable.json"
	if DirAccess.copy_absolute(save_path, backup_path) != OK:
		return ""
	return backup_path


## Starts a fresh game for the given case, discarding current in-memory
## state. Does not touch the save file on disk — the player must explicitly
## Save afterwards if they want to overwrite it (a production core-loop
## chapter checkpoints its own new run, see ChapterRuntime). Routed through
## CaseManager.start_case() rather than GameState.start_new_game() directly
## so any case — chapter-based or flat — gets its chapter state (if any)
## initialized the same way; see docs/case-system.md, "Case initialization".
func new_game(case_id: String = DEFAULT_NEW_GAME_CASE) -> void:
	CaseManager.start_case(case_id)
	new_game_started.emit(case_id)


## The case the title screen's New Game starts: the (only — ContentValidator
## rejects more than one) case whose JSON declares "new_game_entry": true,
## else DEFAULT_NEW_GAME_CASE. Data-driven so a future real case replaces the
## sandbox as the entry point with a JSON edit, never a script change.
func get_new_game_case_id() -> String:
	var case_ids: Array = ContentDB.get_all_case_ids()
	case_ids.sort()
	for case_id in case_ids:
		if ContentDB.get_case(String(case_id)).get("new_game_entry", false) == true:
			return String(case_id)
	return DEFAULT_NEW_GAME_CASE


## Milestone 1.17: what the debug-build title screen's Technical Sandbox
## selector offers — every case whose JSON declares "sandbox_selection" and
## is marked non-canon, ordered by its "order" (ties and malformed entries are
## ContentValidator errors; here they only sort by id / are skipped). The
## release New Game case (get_new_game_case_id()) is listed first when it is
## not itself selectable, so the selector can always return to the default.
## Each entry: {"case_id", "name", "description" (translation keys),
## "default": bool}. Content-driven: no case id is named here.
func get_sandbox_entries() -> Array[Dictionary]:
	var selectable: Array[Dictionary] = []
	for raw_id in ContentDB.get_all_case_ids():
		var case_id: String = String(raw_id)
		var data: Dictionary = ContentDB.get_case(case_id)
		var selection: Variant = data.get("sandbox_selection")
		var metadata: Variant = data.get("metadata", {})
		if typeof(selection) != TYPE_DICTIONARY or typeof(metadata) != TYPE_DICTIONARY or (metadata as Dictionary).get("canon", true) != false:
			continue
		selectable.append({"case_id": case_id, "order": PrototypeContext.count((selection as Dictionary).get("order"))})
	selectable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["order"] < b["order"] or (a["order"] == b["order"] and a["case_id"] < b["case_id"]))
	var default_id: String = get_new_game_case_id()
	var ordered: Array[String] = []
	if not selectable.any(func(entry: Dictionary) -> bool: return entry["case_id"] == default_id):
		ordered.append(default_id)
	for entry in selectable:
		ordered.append(str(entry["case_id"]))
	var entries: Array[Dictionary] = []
	for case_id in ordered:
		var data: Dictionary = ContentDB.get_case(case_id)
		entries.append({
			"case_id": case_id, "name": str(data.get("display_name", data.get("title", ""))),
			"description": str(data.get("description", "")), "default": case_id == default_id,
		})
	return entries


## The case a SAVE belongs to (its "variables.case_id"), or "" when there is
## no loadable save — lets the title screen say which run Continue resumes
## without loading anything.
func get_saved_case_id() -> String:
	var inspection: Dictionary = inspect_save()
	if inspection.get("ok", false) != true:
		return ""
	var variables: Variant = (inspection.get("state", {}) as Dictionary).get("variables", {})
	return str((variables as Dictionary).get("case_id", "")) if typeof(variables) == TYPE_DICTIONARY else ""


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


## Structural check of everything GameState.load_from_dict() reads: a field
## that is present must have the right JSON type (absent fields keep the
## lenient defaults every pre-1.16 save already relied on).
func _is_state_well_formed(state: Dictionary) -> bool:
	var expected := {
		"current_location": TYPE_STRING, "visited_locations": TYPE_ARRAY, "evidence": TYPE_ARRAY,
		"flags": TYPE_DICTIONARY, "variables": TYPE_DICTIONARY, "seen_interactions": TYPE_ARRAY,
	}
	for key in expected:
		if state.has(key) and typeof(state[key]) != expected[key]:
			return false
	for key in ["visited_locations", "evidence", "seen_interactions"]:
		for entry in state.get(key, []):
			if typeof(entry) != TYPE_STRING:
				return false
	return true


func _inspection(ok: bool, reason: String, version: int) -> Dictionary:
	return {"ok": ok, "reason": reason, "version": version, "state": {}}
