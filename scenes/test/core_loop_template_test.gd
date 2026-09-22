extends SceneTree
## Milestone 1.17 — the core-loop chapter TEMPLATE stays a working chapter
## (docs/templates/core_loop_chapter/, docs/core-loop-authoring.md). The
## template lives outside data/ (and under a .gdignore), so ContentDB never
## loads it as real content; this test injects its JSON and strings into the
## running ContentDB/TranslationServer, then proves it is a complete, valid,
## playable THIRD chapter — over the one dummy case no sandbox uses — with no
## code change: ContentValidator reports nothing new, CoreLoopValidator is
## clean, the selector would list it, and the legal-path simulator completes it
## (primary path, documented alternate path, alternate timeline). Everything
## is removed again afterwards. Autoloads, no scene tree — FAST and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_template_test.gd

const TEMPLATE_ROOT := "res://docs/templates/core_loop_chapter"
const TEMPLATE_CASE := "case_tpl_parcel"
const TEMPLATE_CHAPTER := "tpl_chapter_01"
## ContentDB category -> [template sub-folder, getter of the live dictionary].
const CATEGORIES := {
	"cases": "get_all_cases", "chapters": "get_all_chapters", "characters": "get_all_characters", "dialogue": "get_all_dialogues",
	"events": "get_all_events", "evidence": "get_all_evidence", "locations": "get_all_locations",
}

var content_db: Node
var save_manager: Node
var content_validator: Script
var _injected: Array = []  # [live dictionary, id]
var _messages: Array = []  # [Translation, key]
var _runtimes: Array = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	content_db = get_root().get_node("ContentDB")
	save_manager = get_root().get_node("SaveManager")
	content_validator = load("res://scripts/core/content_validator.gd")
	TestHelpers.isolate_save(save_manager, "core_loop_template_test")
	TestHelpers.isolate_locale(get_root().get_node("LocaleManager"), "core_loop_template_test")

	print("=== Core loop — the chapter template is a working chapter ===")
	var baseline: Dictionary = content_validator.validate()
	_check(content_db.get_case(TEMPLATE_CASE).is_empty() and content_db.get_chapter(TEMPLATE_CHAPTER).is_empty(), "the template is NOT loaded as real content (it lives outside data/)")
	_check(FileAccess.file_exists("res://docs/templates/.gdignore"), "the template folder is hidden from Godot's importer (.gdignore), so its strings.csv never becomes a translation resource")
	_inject()
	_test_template_validates_clean(baseline)
	_test_template_demonstrates_the_contract()
	_test_template_is_playable()
	_remove()
	var restored: Dictionary = content_validator.validate()
	_check(restored.get("errors", []) == baseline.get("errors", []) and restored.get("warnings", []) == baseline.get("warnings", []), "removing the template restores the original validation report")

	for runtime in _runtimes:
		runtime.detach()
	save_manager.delete_save()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _inject() -> void:
	var collisions: Array[String] = []
	for folder in CATEGORIES:
		var live: Dictionary = content_db.call(CATEGORIES[folder])
		for path in _json_files(TEMPLATE_ROOT.path_join("data").path_join(folder)):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			var entries: Array = parsed if typeof(parsed) == TYPE_ARRAY else [parsed]
			for entry in entries:
				var id: String = str(entry.get("id", ""))
				if live.has(id):
					collisions.append(id)
				live[id] = entry
				_injected.append([live, id])
	_check(collisions.is_empty() and _injected.size() > 20, "the template's %d entries collide with no real content id: %s" % [_injected.size(), collisions])
	var file := FileAccess.open(TEMPLATE_ROOT.path_join("strings.csv"), FileAccess.READ)
	var header: PackedStringArray = file.get_csv_line()
	_check(header == PackedStringArray(["keys", "en", "vi"]), "the template strings use the project's CSV columns")
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() < 3:
			continue
		for column in [1, 2]:
			var translation: Translation = TranslationServer.get_translation_object(header[column])
			_check(translation.get_message(row[0]) == "", "template key %s is new, not an overwrite" % row[0])
			translation.add_message(row[0], row[column])
			_messages.append([translation, row[0]])


func _remove() -> void:
	for pair in _injected:
		(pair[0] as Dictionary).erase(pair[1])
	for pair in _messages:
		(pair[0] as Translation).erase_message(pair[1])


func _json_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_json_files(dir_path.path_join(sub)))
	for file_name in dir.get_files():
		if file_name.get_extension() == "json":
			out.append(dir_path.path_join(file_name))
	return out


# ---------------------------------------------------------------------------

func _test_template_validates_clean(baseline: Dictionary) -> void:
	var result: Dictionary = content_validator.validate()
	_check((result.get("errors", []) as Array).is_empty(), "the injected template raises no validation error: %s" % [result.get("errors", [])])
	_check(result.get("warnings", []) == baseline.get("warnings", []), "...and no new warning: %s" % [result.get("warnings", [])])
	var built: Dictionary = load("res://scripts/debug/core_loop_author_report.gd").build(TEMPLATE_CHAPTER)
	_check(int(built.get("errors", -1)) == 0 and int(built.get("warnings", -1)) == 0, "the author report of the template is clean")


func _test_template_demonstrates_the_contract() -> void:
	var case_data: Dictionary = content_db.get_case(TEMPLATE_CASE)
	var chapter: Dictionary = content_db.get_chapter(TEMPLATE_CHAPTER)
	var loop: Dictionary = chapter.get("core_loop", {})
	_check((case_data.get("metadata", {}) as Dictionary).get("canon", true) == false and loop.get("canon", true) == false, "non-canon metadata on the case and the chapter")
	_check(typeof(case_data.get("sandbox_selection")) == TYPE_DICTIONARY and not case_data.get("new_game_entry", false), "selectable-sandbox metadata, without claiming the release default")
	_check(save_manager.get_sandbox_entries().any(func(entry: Dictionary) -> bool: return entry.get("case_id", "") == TEMPLATE_CASE), "once in data/, the debug selector would list it — no code change")
	var mechanics: Array = []
	for unit in loop.get("units", []):
		mechanics.append(unit.get("mechanic", ""))
	_check(mechanics == ["clue_connection", "statement_contradiction", "clue_connection", "timeline_reconstruction"], "B, A, B and C units: %s" % [mechanics])
	_check(loop.has("briefing") and loop.has("result") and not (loop.get("evidence_links", {}) as Dictionary).is_empty() and (loop.get("phases", []) as Array).size() == 6, "briefing, result, evidence links and the six-phase route")
	_check(str(content_db.get_event(str(chapter.get("completion_event", ""))).get("id", "")) != "", "a completion event")
	var optional_link: bool = false
	for inventory_id in loop["evidence_links"]:
		var used := false
		for unit in loop["units"]:
			for path in unit.get("documented_paths", []):
				used = used or (path as Array).has(inventory_id)
		optional_link = optional_link or not used
	_check(optional_link, "an optional interaction: linked evidence no required answer needs")


func _test_template_is_playable() -> void:
	var support := CoreLoopTestSupport.new(self)
	for variant in [["primary", {}], ["documented alternate B path", {"b_paths": {"b1_scanner": 1}}], ["alternate timeline", {"timeline": "alternate"}]]:
		var runtime: RefCounted = support.new_runtime("tpl")
		_runtimes.append(runtime)
		var result: Dictionary = CoreLoopRouteSimulator.new(self).run(TEMPLATE_CASE, runtime, variant[1])
		_check(result.get("ok", false) and runtime.get_chapter_id() == TEMPLATE_CHAPTER, "the template has a legal %s route through the unchanged runtime: %s" % [variant[0], result.get("failure", "")])
