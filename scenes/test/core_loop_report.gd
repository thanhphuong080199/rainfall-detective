extends SceneTree
## Milestone 1.17 — the HEADLESS core-loop author report (see
## docs/core-loop-authoring.md, "Inspecting a chapter"). For every core-loop
## chapter (or only the ids given after "--"), runs the legal-path simulator
## on fresh runs — the primary route, every documented alternate B path, an
## alternate accepted timeline and the optional innocent lies — then prints
## CoreLoopAuthorReport's full report with those results. The same report,
## minus the simulation (which would replace the live run), is the Case
## Debugger's "Core Loop" tab.
##
## An authoring tool, like validate_content.gd — not part of FAST/FULL (the
## simulation itself is covered by core_loop_simulation_test.gd). Exits 1 when
## any reported chapter has a validation error or no legal route. Uses a
## throwaway save/settings file.
##
##   godot --headless --path . -s res://scenes/test/core_loop_report.gd
##   godot --headless --path . -s res://scenes/test/core_loop_report.gd -- sby_chapter_01

var _runtimes: Array = []


func _initialize() -> void:
	await process_frame
	var save_manager: Node = get_root().get_node("SaveManager")
	var content_db: Node = get_root().get_node("ContentDB")
	TestHelpers.isolate_save(save_manager, "core_loop_report")
	TestHelpers.isolate_locale(get_root().get_node("LocaleManager"), "core_loop_report")
	var report_script: Script = load("res://scripts/debug/core_loop_author_report.gd")
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	var failed := false
	for chapter_id in report_script.chapter_ids():
		if not wanted.is_empty() and not wanted.has(chapter_id):
			continue
		var case_id: String = _owner_case(content_db, chapter_id)
		var routes: Array = _simulate_all(content_db, case_id, content_db.get_chapter(chapter_id))
		var report: Dictionary = report_script.build(chapter_id, {}, {"routes": routes})
		print(report_script.format_text(report))
		print("")
		failed = failed or int(report.get("errors", 0)) > 0
	for runtime in _runtimes:
		runtime.detach()
	save_manager.delete_save()
	quit(1 if failed else 0)


func _owner_case(content_db: Node, chapter_id: String) -> String:
	for case_id in content_db.get_all_case_ids():
		if (content_db.get_case(String(case_id)).get("chapters", []) as Array).has(chapter_id):
			return String(case_id)
	return ""


## One fresh simulated run per route variant the content supports.
func _simulate_all(content_db: Node, case_id: String, chapter: Dictionary) -> Array:
	var variants: Array = [["primary route", {}]]
	var has_optional := false
	var deduction: Dictionary = content_db.get_deduction_case(str(chapter["core_loop"].get("deduction_case", "")))
	for unit in chapter["core_loop"].get("units", []):
		var paths: Array = unit.get("documented_paths", [])
		for i in range(1, paths.size()):
			variants.append(["%s documented path #%d" % [unit.get("id", ""), i + 1], {"b_paths": {unit.get("id", ""): i}}])
		if unit.get("mechanic", "") == "statement_contradiction":
			for proto_round in deduction.get("prototype_a", {}).get("rounds", []):
				has_optional = has_optional or ((unit.get("rounds", []) as Array).has(proto_round.get("id", "")) and not (proto_round.get("optional_refutations", []) as Array).is_empty())
	variants.append(["alternate accepted timeline", {"timeline": "alternate"}])
	if has_optional:
		variants.append(["optional innocent lie exposed", {"optional_lies": true}])
	var routes: Array = []
	for variant in variants:
		var runtime: RefCounted = CoreLoopTestSupport.new(self).new_runtime("report")
		_runtimes.append(runtime)
		var result: Dictionary = CoreLoopRouteSimulator.new(self).run(case_id, runtime, variant[1])
		routes.append({
			"label": variant[0], "ok": result.get("ok", false), "failure": result.get("failure", ""),
			"steps": (result.get("route", []) as Array).size(), "units": result.get("units", {}), "phases": result.get("phases", []),
		})
	return routes
