extends SceneTree
## Milestone 1.17 — the core-loop author report (CoreLoopAuthorReport; see
## docs/core-loop-authoring.md, "Inspecting a chapter", and
## docs/case-debugger.md, "Core Loop tab"). Proves it carries the structural
## information an author needs for every core-loop chapter (route, units,
## offer conditions, accepted proof sets, refutations, evidence producers,
## consequences, completion producer), keeps its four kinds apart (validation
## ERROR / WARNING, static info, current-run NOW lines that exist only for the
## active chapter), renders simulation results — and that none of it, nor the
## simulator, ever reaches a player view or a production script. Autoloads, no
## scene tree — FAST and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_author_report_test.gd

const S := preload("res://scenes/test/core_loop_test_support.gd")

var support: CoreLoopTestSupport
var game_state: Node
var save_manager: Node
var content_db: Node
var report: Script
var presenter: Script
var _runtimes: Array = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	support = CoreLoopTestSupport.new(self)
	game_state = support.game_state
	save_manager = support.save_manager
	content_db = get_root().get_node("ContentDB")
	report = load("res://scripts/debug/core_loop_author_report.gd")
	presenter = load("res://scripts/core_loop/core_loop_presenter.gd")
	TestHelpers.isolate_save(save_manager, "core_loop_author_report_test")
	TestHelpers.isolate_locale(get_root().get_node("LocaleManager"), "core_loop_author_report_test")

	print("=== Core loop — author report ===")
	_test_reports_describe_every_chapter()
	_test_current_run_state_only_for_the_active_chapter()
	_test_errors_warnings_and_info_are_distinct()
	_test_simulation_results_are_rendered()
	_test_author_information_never_reaches_player_views()
	_test_author_tooling_stays_out_of_production_code()

	for runtime in _runtimes:
		runtime.detach()
	save_manager.delete_save()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _text(built: Dictionary) -> String:
	return report.format_text(built)


func _kinds(built: Dictionary) -> Dictionary:
	var kinds: Dictionary = {}
	for line in built.get("lines", []):
		kinds[line.get("kind", "")] = int(kinds.get(line.get("kind", ""), 0)) + 1
	return kinds


# ---------------------------------------------------------------------------

func _test_reports_describe_every_chapter() -> void:
	var ids: Array = report.chapter_ids()
	_check(ids.has(S.CHAPTER_ID) and ids.has(S.CHAPTER_2) and not ids.has("test_case_chapter_01"), "the report lists exactly the core-loop chapters: %s" % [ids])
	for chapter_id in [S.CHAPTER_ID, S.CHAPTER_2]:
		var built: Dictionary = report.build(chapter_id)
		var text: String = _text(built)
		var loop: Dictionary = content_db.get_chapter(chapter_id)["core_loop"]
		_check(int(built.get("errors", -1)) == 0 and int(built.get("warnings", -1)) == 0, "%s: a clean chapter reports no errors or warnings" % chapter_id)
		_check(text.contains("%s (case" % chapter_id) and text.contains("canon: false") and text.contains(str(loop["deduction_case"])), "%s: chapter id, canon status and deduction case" % chapter_id)
		var last: int = -1
		for phase in loop["phases"]:
			var at: int = text.find(". %s" % phase["id"])
			_check(at > last, "%s: phase %s listed in route order" % [chapter_id, phase["id"]])
			last = at
		for unit in loop["units"]:
			_check(text.contains("Unit %s: mechanic %s" % [unit["id"], unit["mechanic"]]), "%s: unit %s and its mechanic" % [chapter_id, unit["id"]])
			_check(text.contains("offer condition: %s" % load("res://scripts/core/condition_evaluator.gd").describe(unit["offer_condition"])), "%s: %s's offer condition" % [chapter_id, unit["id"]])
			for outcome in unit["consequences"]:
				_check(text.contains('consequence "%s"' % unit["consequences"][outcome]["id"]), "%s: consequence %s and its effects" % [chapter_id, unit["consequences"][outcome]["id"]])
			if unit["mechanic"] == "clue_connection":
				_check(text.contains("Unit %s: accepted proof set 1 (the case's primary)" % unit["id"]), "%s: %s's accepted proof sets" % [chapter_id, unit["id"]])
				if (unit.get("documented_paths", []) as Array).size() > 1:
					_check(text.contains("Unit %s: accepted proof set 2 (the case's alternate)" % unit["id"]) and text.contains(", documented"), "%s: %s's alternate path and documentation coverage" % [chapter_id, unit["id"]])
			if unit["mechanic"] == "statement_contradiction":
				_check(text.contains("REQUIRED"), "%s: A's required contradiction" % chapter_id)
		for inventory_id in loop["evidence_links"]:
			_check(text.contains("Evidence: %s -> %s" % [inventory_id, loop["evidence_links"][inventory_id]]) and text.contains("acquired via: dialogue"), "%s: linked evidence %s with its acquisition producers" % [chapter_id, inventory_id])
		_check(text.contains('completion_event "%s"' % content_db.get_chapter(chapter_id)["completion_event"]) and text.contains("is produced by: chapter \"%s\" core_loop unit" % chapter_id), "%s: the completion event and the consequence producing it" % chapter_id)
		_check(not _kinds(built).has(report.KIND_STATE) and text.contains("not the active chapter"), "%s: no current-run lines while the chapter is not active" % chapter_id)
		_check(text.contains("legal-path simulation not run here"), "%s: without results the report says how to run the simulation" % chapter_id)
	var second: String = _text(report.build(S.CHAPTER_2))
	_check(second.contains("optional (never a producer)") and second.contains("st_bruno_left_early"), "sandbox 2: the optional innocent lie is reported as optional, never a producer")
	_check(second.contains("consequence \"sby_a1_resolved\"") and second.contains("add evidence sby_shuttle_note"), "sandbox 2: a consequence that also grants evidence is shown with its effect")


func _test_current_run_state_only_for_the_active_chapter() -> void:
	var runtime: RefCounted = support.new_runtime("report-live")
	_runtimes.append(runtime)
	save_manager.new_game(S.CASE_2)
	runtime.reload_from_game_state()
	runtime.acknowledge_briefing()
	var locked: String = _text(report.build(S.CHAPTER_2, game_state.chapter_run))
	_check(locked.contains("[NOW] Route: current phase: investigation_1") and locked.contains("[NOW] Unit b1_staging: LOCKED — missing: has evidence"), "the active chapter shows its current phase and why the unit is locked:\n%s" % locked.left(0))
	var simulator := CoreLoopRouteSimulator.new(self)
	simulator.prepare_unit(runtime, S.B1_2)
	_check(_text(report.build(S.CHAPTER_2, game_state.chapter_run)).contains("[NOW] Unit b1_staging: OFFERED now"), "once its evidence is held the unit shows as offered")
	support.solve_b(runtime, S.B1_2, S.B1_2_PATH)
	var after: String = _text(report.build(S.CHAPTER_2, game_state.chapter_run))
	_check(after.contains('consequence "sby_b1_resolved" APPLIED (resolved by player') and after.contains('consequence "sby_a1_resolved" not applied yet'), "applied and not-yet-applied consequences are told apart")
	_check(not _kinds(report.build(S.CHAPTER_ID, game_state.chapter_run)).has(report.KIND_STATE), "another chapter's report never shows this run's state")


func _test_errors_warnings_and_info_are_distinct() -> void:
	var chapters: Dictionary = content_db.get_all_chapters()
	var original: Dictionary = (chapters[S.CHAPTER_2] as Dictionary).duplicate(true)
	var broken: Dictionary = original.duplicate(true)
	for unit in broken["core_loop"]["units"]:
		if unit["id"] == S.A1_2:
			unit["offer_condition"]["all"].append({"flag": "sby_only_a_debugger_sets_this"})
	chapters[S.CHAPTER_2] = broken
	var with_error: Dictionary = report.build(S.CHAPTER_2)
	var smelly: Dictionary = original.duplicate(true)
	for unit in smelly["core_loop"]["units"]:
		if unit["id"] == S.B2_2:
			unit["consequences"]["resolved"]["effects"] = [{"type": "set_flag", "flag": "sby_nobody_reads_this", "value": true}]
	chapters[S.CHAPTER_2] = smelly
	var with_warning: Dictionary = report.build(S.CHAPTER_2)
	chapters[S.CHAPTER_2] = original
	_check(int(with_error.get("errors", 0)) >= 1 and _text(with_error).contains("[ERROR] Validation:") and _text(with_error).contains("only a debug override could"), "a validation ERROR is reported as an error")
	_check(int(with_warning.get("errors", -1)) >= 0 and int(with_warning.get("warnings", 0)) >= 1 and _text(with_warning).contains("[WARN] Validation:"), "a validation WARNING is reported as a warning, separately")
	var kinds: Dictionary = _kinds(report.build(S.CHAPTER_2))
	_check(kinds.keys().all(func(kind: String) -> bool: return [report.KIND_ERROR, report.KIND_WARNING, report.KIND_INFO, report.KIND_STATE].has(kind)) and kinds.has(report.KIND_INFO), "every line has exactly one of the four kinds: %s" % [kinds])


func _test_simulation_results_are_rendered() -> void:
	var built: Dictionary = report.build(S.CHAPTER_2, {}, {"routes": [
		{"label": "primary route", "ok": true, "steps": 54, "phases": ["briefing", "completed"], "units": {"b1_staging": {"mechanic": "clue_connection", "path": ["sby_open_hatch"]}}},
		{"label": "broken variant", "ok": false, "failure": "could not acquire 'x'", "steps": 3, "units": {}, "phases": []},
	]})
	var text: String = _text(built)
	_check(text.contains("[info] Simulation: primary route: OK — 54 steps") and text.contains("b1_staging (clue_connection)"), "a successful route and its chosen answers are shown")
	_check(text.contains("[ERROR] Simulation: broken variant: NO LEGAL ROUTE — could not acquire 'x'") and int(built.get("errors", 0)) == 1, "a route with no legal path is an error")


## Everything distinctive the report prints — ids, proof-path and consequence
## vocabulary, its kind tags — must be absent from every player view of a run
## played through several phases.
func _test_author_information_never_reaches_player_views() -> void:
	var tokens: Array[String] = ["offer condition", "proof set", "documented", "[NOW]", "[ERROR]", "[WARN]", "consequence", "LOCKED —"]
	var loop: Dictionary = content_db.get_chapter(S.CHAPTER_2)["core_loop"]
	for unit in loop["units"]:
		tokens.append(str(unit["id"]))
		for outcome in unit["consequences"]:
			tokens.append(str(unit["consequences"][outcome]["id"]))
	for inventory_id in loop["evidence_links"]:
		tokens.append(str(inventory_id))
		tokens.append(str(loop["evidence_links"][inventory_id]))
	for flag in content_db.get_case(S.CASE_2)["initial_flags"]:
		tokens.append(str(flag))
	var runtime: RefCounted = support.new_runtime("report-views")
	_runtimes.append(runtime)
	var simulator := CoreLoopRouteSimulator.new(self)
	save_manager.new_game(S.CASE_2)
	runtime.reload_from_game_state()
	var leaks: Array[String] = []
	for phase_id in ["investigation_1", "confrontation", "investigation_2", "timeline", "final_claim"]:
		simulator.advance(runtime, {"stop_at_phase": phase_id})
		var unit_id: String = runtime.get_current_unit_id()
		simulator.prepare_unit(runtime, unit_id)
		runtime.open_unit(unit_id)
		var views: Array = [presenter.build_hud(runtime), presenter.build_briefing(runtime), presenter.build_case_file(runtime).get("view", {}), presenter.build_mechanic(runtime, unit_id).get("view", {})]
		for view in views:
			for text in _strings(view):
				for token in tokens:
					if text.contains(token):
						leaks.append("%s: %s in \"%s\"" % [phase_id, token, text])
		runtime.close_unit()
	simulator.advance(runtime)
	for text in _strings(presenter.build_result(runtime)):
		for token in tokens:
			if text.contains(token):
				leaks.append("result: %s in \"%s\"" % [token, text])
	_check(runtime.is_completed(), "the views were sampled across the whole route")
	_check(leaks.is_empty(), "no author-report information reaches a player view: %s" % [leaks.slice(0, 5)])


func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	match typeof(value):
		TYPE_STRING:
			out.append(value)
		TYPE_DICTIONARY:
			for key in value:
				out.append_array(_strings(value[key]))
		TYPE_ARRAY:
			for entry in value:
				out.append_array(_strings(entry))
	return out


func _test_author_tooling_stays_out_of_production_code() -> void:
	var production: Array[String] = []
	for dir_path in ["res://scripts/core", "res://scripts/core_loop", "res://scripts/ui", "res://scripts/investigation", "res://scripts/dialogue", "res://scripts/evidence", "res://scripts/save", "res://scripts/cases", "res://scripts/events", "res://scripts/deduction"]:
		for file_name in DirAccess.get_files_at(dir_path):
			if file_name.get_extension() == "gd":
				production.append(dir_path.path_join(file_name))
	var offenders: Array[String] = []
	for path in production:
		var source: String = TestHelpers.code_only(FileAccess.get_file_as_string(path))
		for token in ["CoreLoopAuthorReport", "CoreLoopRouteSimulator", "core_loop_author_report", "core_loop_route_simulator", "res://scenes/test", "res://scenes/debug", "res://scripts/debug", "%DebugPanel", "%DeductionLab"]:
			if source.contains(token):
				offenders.append("%s -> %s" % [path, token])
	_check(production.size() > 30 and offenders.is_empty(), "no production script references the author report, the simulator, test scenes or debug scenes: %s" % [offenders])
	var panel: String = FileAccess.get_file_as_string("res://scripts/debug/debug_panel.gd")
	var guard: int = panel.find("if not OS.is_debug_build():")
	_check(guard > 0 and guard < panel.find("core_loop_chapter_option.item_selected.connect"), "the Case Debugger (and its Core Loop tab) stays inert in release builds")
	var title: String = FileAccess.get_file_as_string("res://scripts/ui/title_screen.gd")
	_check(title.contains("var sandbox_selector_enabled: bool = OS.is_debug_build()"), "the title screen's sandbox selector defaults to debug builds only")
