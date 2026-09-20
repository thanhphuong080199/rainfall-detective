extends SceneTree
## Focused tests for PrototypeEvaluationSummary (Milestone 1.14.2A — see
## docs/prototype-evaluation.md): run-splitting on a DeductionLabRecorder
## export, submission/incorrect/unique-candidate/duplicate-blocked counting
## from hand-built event fixtures (pure, deterministic, no ContentDB needed),
## and a handful of real-controller integration checks proving the
## summarizer reads genuine Prototype A/B/C recorder output correctly and
## that two independently-recorded runs never leak into each other's
## summary. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_evaluation_summary_test.gd

var summary_script: Variant
var recorder_script: Variant
var pa_script: Variant
var pb_script: Variant
var pc_script: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	summary_script = load("res://scripts/deduction/prototype_evaluation_summary.gd")
	recorder_script = load("res://scripts/deduction/deduction_lab_recorder.gd")
	pa_script = load("res://scripts/deduction/prototype_a_controller.gd")
	pb_script = load("res://scripts/deduction/prototype_b_controller.gd")
	pc_script = load("res://scripts/deduction/prototype_c_controller.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeEvaluationSummary — focused tests ===")
	_test_empty_or_malformed_export_returns_no_runs()
	_test_single_completed_run_counts_correctly()
	_test_repeated_duplicate_blocks_do_not_inflate_unique_count()
	_test_abandoned_run_is_flagged_abandoned_not_completed()
	_test_in_progress_run_has_neither_flag()
	_test_multiple_runs_split_at_restart_boundary_without_leaking()
	_test_format_summary_lines_is_deterministic()
	_test_format_stats_line_sorts_keys()
	_test_export_to_file_round_trips_and_is_safe()
	_test_summarize_is_a_pure_read_never_mutates_input()
	# Real-controller integration — proves the summarizer reads genuine
	# Prototype A/B/C recorder output, and that two independently-recorded
	# runs never leak into each other's summary.
	_test_real_prototype_a_run_summarizes_correctly()
	_test_real_prototype_b_run_summarizes_correctly()
	_test_real_prototype_c_run_summarizes_correctly()
	_test_ab_c_recordings_do_not_leak_into_each_other()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


# ---------------------------------------------------------------------------
# Hand-built fixtures — deterministic, no recorder/clock/ContentDB involved.

func _event(sequence: int, elapsed_ms: int, type: String, payload: Dictionary = {}) -> Dictionary:
	return {"sequence": sequence, "elapsed_ms": elapsed_ms, "type": type, "source": "player_preview", "payload": payload}


func _export(prototype: String, session_id: String, events: Array[Dictionary]) -> Dictionary:
	return {
		"schema_version": 1, "event_schema_version": 2, "session_id": session_id, "case_id": "fx_case",
		"prototype": prototype, "locale": "en", "started_at_utc": "2026-01-01T00:00:00Z", "events": events,
	}


func _test_empty_or_malformed_export_returns_no_runs() -> void:
	_check(summary_script.summarize({}).get("total_runs") == 0, "an empty dict should summarize to zero runs")
	_check(summary_script.summarize(_export("clue_connection", "s1", [])).get("total_runs") == 0, "no events at all should summarize to zero runs")
	var no_boundary: Array[Dictionary] = [_event(1, 0, "evidence_opened", {"evidence_id": "e_x"})]
	_check(summary_script.summarize(_export("clue_connection", "s1", no_boundary)).get("total_runs") == 0, "events with no prototype_started boundary should summarize to zero runs (e.g. a Deduction Lab export)")
	_check(summary_script.summarize_latest_run({}) == {}, "summarize_latest_run on an empty export should return {}")


func _test_single_completed_run_counts_correctly() -> void:
	var events: Array[Dictionary] = [
		_event(1, 0, "prototype_started", {"case_id": "fx_case", "run": 1}),
		_event(2, 100, "formal_commit_started", {"run_resolution_result": "independent"}),
		_event(3, 100, "attempt_submitted", {"statement_id": "s1", "evidence_id": "e1"}),
		_event(4, 100, "formal_commit_failed", {"run_resolution_result_before": "independent", "run_resolution_result_after": "guided"}),
		_event(5, 200, "hint_revealed", {"level": 1}),
		_event(6, 300, "formal_commit_started", {"run_resolution_result": "guided"}),
		_event(7, 300, "attempt_submitted", {"statement_id": "s1", "evidence_id": "e2"}),
		_event(8, 300, "formal_commit_succeeded", {"run_resolution_result": "guided"}),
		_event(9, 300, "prototype_completed", {"resolution": {"run_resolution_result": "guided", "partner_resolutions": 0}}),
	]
	var run: Dictionary = summary_script.summarize_latest_run(_export("statement_contradiction", "s1", events))
	_check(run.get("case_id") == "fx_case" and run.get("run") == 1, "case_id/run should come from the prototype_started payload")
	_check(run.get("completed") == true and run.get("abandoned") == false, "a run with prototype_completed should be completed, not abandoned")
	_check(run.get("duration_ms") == 300, "duration_ms should be the last event's elapsed_ms")
	_check(run.get("submission_count") == 2, "submission_count should count formal_commit_started, got %s" % run.get("submission_count"))
	_check(run.get("incorrect_submission_count") == 1, "incorrect_submission_count should count formal_commit_failed, got %s" % run.get("incorrect_submission_count"))
	_check(run.get("unique_candidate_count") == 2, "two distinct (statement, evidence) pairs were submitted, got %s" % run.get("unique_candidate_count"))
	_check(run.get("duplicate_blocked_count") == 0, "no blocked-duplicate events were recorded in this trace")
	_check(run.get("hint_reveal_count") == 1 and run.get("max_hint_level") == 1, "one hint at level 1 should be counted")
	_check(run.get("run_resolution_result") == "guided", "the final resolution should be read from prototype_completed's resolution block, got %s" % run.get("run_resolution_result"))


func _test_repeated_duplicate_blocks_do_not_inflate_unique_count() -> void:
	var events: Array[Dictionary] = [
		_event(1, 0, "prototype_started", {"case_id": "fx_case", "run": 1}),
		_event(2, 10, "formal_commit_started", {}),
		_event(3, 10, "attempt_submitted", {"statement_id": "s1", "evidence_id": "e1"}),
		_event(4, 10, "formal_commit_failed", {}),
		_event(5, 20, "attempt_blocked_duplicate", {"statement_id": "s1", "evidence_id": "e1"}),
		_event(6, 30, "attempt_blocked_duplicate", {"statement_id": "s1", "evidence_id": "e1"}),
		_event(7, 40, "attempt_blocked_duplicate", {"statement_id": "s1", "evidence_id": "e1"}),
		_event(8, 50, "attempt_blocked_duplicate", {"statement_id": "s2", "evidence_id": "e9"}),  # a DIFFERENT blocked candidate, repeated once
		_event(9, 60, "attempt_blocked_duplicate", {"statement_id": "s2", "evidence_id": "e9"}),
	]
	var run: Dictionary = summary_script.summarize_latest_run(_export("statement_contradiction", "s1", events))
	_check(run.get("submission_count") == 1, "blocked duplicates are never formal_commit_started, got %s" % run.get("submission_count"))
	_check(run.get("unique_candidate_count") == 2, "the candidate set is exactly {s1,e1} and {s2,e9} — repeats never add a new candidate, got %s" % run.get("unique_candidate_count"))
	_check(run.get("duplicate_blocked_count") == 5, "every blocked attempt should be counted, got %s" % run.get("duplicate_blocked_count"))
	_check(run.get("max_repeated_candidate_count") == 3, "the same {s1,e1} candidate was blocked 3 times — that is the max repeat, got %s" % run.get("max_repeated_candidate_count"))


func _test_abandoned_run_is_flagged_abandoned_not_completed() -> void:
	var events: Array[Dictionary] = [
		_event(1, 0, "prototype_started", {"case_id": "fx_case", "run": 1}),
		_event(2, 50, "evidence_opened", {"evidence_id": "e1"}),
		_event(3, 80, "prototype_abandoned", {"resolution": {"run_resolution_result": "independent"}}),
	]
	var run: Dictionary = summary_script.summarize_latest_run(_export("statement_contradiction", "s1", events))
	_check(run.get("abandoned") == true and run.get("completed") == false, "prototype_abandoned should mark abandoned, never completed")
	_check(run.get("duration_ms") == 80, "duration_ms should reach the abandon point")


func _test_in_progress_run_has_neither_flag() -> void:
	var events: Array[Dictionary] = [
		_event(1, 0, "prototype_started", {"case_id": "fx_case", "run": 1}),
		_event(2, 40, "evidence_opened", {"evidence_id": "e1"}),
	]
	var run: Dictionary = summary_script.summarize_latest_run(_export("statement_contradiction", "s1", events))
	_check(run.get("completed") == false and run.get("abandoned") == false, "a run with neither prototype_completed nor prototype_abandoned should show as still in progress")
	_check(run.get("duration_ms") == 40, "duration_ms should reflect however far the in-progress run has gone")


func _test_multiple_runs_split_at_restart_boundary_without_leaking() -> void:
	var events: Array[Dictionary] = [
		_event(1, 0, "prototype_started", {"case_id": "fx_case", "run": 1}),
		_event(2, 10, "formal_commit_started", {}),
		_event(3, 10, "attempt_submitted", {"statement_id": "s1", "evidence_id": "e1"}),
		_event(4, 10, "formal_commit_failed", {}),
		_event(5, 20, "prototype_restarted", {"previous_run": 1, "previous_completed": false}),
		_event(6, 20, "prototype_started", {"case_id": "fx_case", "run": 2}),
		_event(7, 30, "formal_commit_started", {}),
		_event(8, 30, "attempt_submitted", {"statement_id": "s3", "evidence_id": "e3"}),
		_event(9, 30, "formal_commit_succeeded", {}),
		_event(10, 30, "prototype_completed", {"resolution": {"run_resolution_result": "independent"}}),
	]
	var summary: Dictionary = summary_script.summarize(_export("statement_contradiction", "s1", events))
	_check(summary.get("total_runs") == 2, "a restart mid-recording should split the export into two runs, got %s" % summary.get("total_runs"))
	var runs: Array = summary.get("runs", [])
	_check(runs[0].get("run") == 1 and runs[1].get("run") == 2, "runs should keep their own run numbers in order")
	_check(runs[0].get("completed") == false and runs[0].get("abandoned") == false and runs[0].get("superseded_by_restart") == true, "the first run never completed or was abandoned — it was superseded by a restart")
	_check(runs[1].get("completed") == true, "the second run finished normally")
	_check(runs[0].get("submission_count") == 1 and runs[0].get("unique_candidate_count") == 1, "the first run's own counts must not include the second run's events")
	_check(runs[1].get("submission_count") == 1 and runs[1].get("incorrect_submission_count") == 0, "the second run's own counts must not include the first run's failure")
	_check(not (runs[1] as Dictionary).has("superseded_by_restart"), "the LAST (still-active) run is never marked superseded_by_restart")


func _test_format_summary_lines_is_deterministic() -> void:
	var summary: Dictionary = summary_script.summarize(_export("clue_connection", "s1", [
		_event(1, 0, "prototype_started", {"case_id": "fx_case", "run": 1}),
		_event(2, 10, "prototype_completed", {"resolution": {"run_resolution_result": "independent"}}),
	]))
	var first: Array[String] = summary_script.format_summary_lines(summary)
	var second: Array[String] = summary_script.format_summary_lines(summary)
	_check(first == second, "formatting the same summary twice should produce identical lines")
	_check(first.size() == 2, "one header line plus one line per run, got %d" % first.size())
	_check(first[0].contains("clue_connection"), "the header line should name the prototype type")


func _test_format_stats_line_sorts_keys() -> void:
	_check(summary_script.format_stats_line({"b": 1, "a": 2}) == "a=2, b=1", "format_stats_line should sort keys deterministically")


func _test_export_to_file_round_trips_and_is_safe() -> void:
	var dir_path: String = "user://prototype_evaluation_summary_test_tmp"
	_remove_dir_recursive(dir_path)
	var export_dict: Dictionary = _export("timeline_reconstruction", "weird/session!.id", [
		_event(1, 0, "prototype_started", {"case_id": "weird case", "run": 1}),
		_event(2, 10, "prototype_completed", {"resolution": {"run_resolution_result": "assisted"}}),
	])
	var result: Dictionary = summary_script.export_to_file(export_dict, dir_path)
	_check(result.get("success") == true, "export_to_file should succeed: %s" % [result])
	var path: String = String(result.get("path", ""))
	_check(path.begins_with(dir_path) and not path.contains(".."), "the summary file must stay inside the requested directory: got %s" % path)
	_check(FileAccess.file_exists(path), "the exported summary file should exist")

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("total_runs") == 1, "the exported file should contain the summarize() output as JSON")
	_check(parsed.get("runs", [])[0].get("run_resolution_result") == "assisted", "the exported JSON should round-trip run data correctly")
	_remove_dir_recursive(dir_path)


func _test_summarize_is_a_pure_read_never_mutates_input() -> void:
	var export_dict: Dictionary = _export("clue_connection", "s1", [
		_event(1, 0, "prototype_started", {"case_id": "fx_case", "run": 1}),
	])
	var before: String = JSON.stringify(export_dict)
	summary_script.summarize(export_dict)
	summary_script.summarize(export_dict)
	var after: String = JSON.stringify(export_dict)
	_check(before == after, "summarize() must never mutate the export dict it was given")


# ---------------------------------------------------------------------------
# Real-controller integration — proves the summarizer works on genuine
# recorder output and that A/B/C recordings never leak into each other.

func _new_recorder(case_id: String, prototype: String):
	var recorder = recorder_script.new()
	recorder.start(case_id, prototype, "en")
	return recorder


func _test_real_prototype_a_run_summarizes_correctly() -> void:
	var recorder = _new_recorder("fx_pa_case", "statement_contradiction")
	var controller = pa_script.new()
	controller.start(fixtures.prototype_a_case(), recorder)
	controller.select_statement(1)
	controller.select_evidence("e_c")  # wrong for st_required1 — a genuine failure
	controller.present_evidence()
	controller.select_evidence("e_c")  # identical pair again — must be blocked
	controller.present_evidence()

	var run: Dictionary = summary_script.summarize_latest_run(recorder.to_export_dict())
	_check(run.get("case_id") == "fx_pa_case", "the summarized run should carry the real case id")
	_check(run.get("submission_count") == 1, "exactly one genuine formal commit happened, got %s" % run.get("submission_count"))
	_check(run.get("incorrect_submission_count") == 1, "that one commit failed, got %s" % run.get("incorrect_submission_count"))
	_check(run.get("duplicate_blocked_count") == 1, "the resubmission should be observed as a blocked duplicate, got %s" % run.get("duplicate_blocked_count"))
	_check(run.get("unique_candidate_count") == 1, "the blocked resubmission is the SAME candidate, not a new one, got %s" % run.get("unique_candidate_count"))
	_check(run.get("completed") == false, "this run was never finished")


func _test_real_prototype_b_run_summarizes_correctly() -> void:
	var recorder = _new_recorder("fx_pb_case", "clue_connection")
	var controller = pb_script.new()
	controller.start(fixtures.prototype_b_case(), recorder)
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_c")
	controller.select_draft(1)
	controller.select_evidence("e_d")
	controller.select_evidence("e_noise")  # an incomplete/incorrect theory
	controller.commit_theory()
	controller.commit_theory()  # identical failed theory again — must be blocked

	var run: Dictionary = summary_script.summarize_latest_run(recorder.to_export_dict())
	_check(run.get("submission_count") == 1, "exactly one genuine formal commit happened, got %s" % run.get("submission_count"))
	_check(run.get("incorrect_submission_count") == 1, "that commit was rejected, got %s" % run.get("incorrect_submission_count"))
	_check(run.get("duplicate_blocked_count") == 1, "the identical resubmission should be observed as a blocked duplicate, got %s" % run.get("duplicate_blocked_count"))
	_check(run.get("unique_candidate_count") == 1, "only one distinct theory was ever actually submitted, got %s" % run.get("unique_candidate_count"))


func _test_real_prototype_c_run_summarizes_correctly() -> void:
	var recorder = _new_recorder("fx_pc_case", "timeline_reconstruction")
	var controller = pc_script.new()
	controller.start(fixtures.prototype_c_case(), recorder)
	controller.place_event("t_a", "10:10")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()  # a known-failing placement (window violation)
	controller.submit_timeline()  # identical placement again — must be blocked

	var run: Dictionary = summary_script.summarize_latest_run(recorder.to_export_dict())
	_check(run.get("submission_count") == 1, "exactly one genuine formal commit happened, got %s" % run.get("submission_count"))
	_check(run.get("incorrect_submission_count") == 1, "that commit failed, got %s" % run.get("incorrect_submission_count"))
	_check(run.get("duplicate_blocked_count") == 1, "the identical resubmission should be observed as a blocked duplicate, got %s" % run.get("duplicate_blocked_count"))
	_check(run.get("unique_candidate_count") == 1, "only one distinct placement was ever actually submitted, got %s" % run.get("unique_candidate_count"))


func _test_ab_c_recordings_do_not_leak_into_each_other() -> void:
	var recorder_a = _new_recorder("fx_pa_case", "statement_contradiction")
	var controller_a = pa_script.new()
	controller_a.start(fixtures.prototype_a_case(), recorder_a)
	controller_a.select_evidence("e_a")
	controller_a.present_evidence()

	var recorder_c = _new_recorder("fx_pc_case", "timeline_reconstruction")
	var controller_c = pc_script.new()
	controller_c.start(fixtures.prototype_c_case(), recorder_c)
	controller_c.place_event("t_a", "09:00")
	controller_c.place_event("t_b", "10:10")
	controller_c.submit_timeline()

	var summary_a: Dictionary = summary_script.summarize(recorder_a.to_export_dict())
	var summary_c: Dictionary = summary_script.summarize(recorder_c.to_export_dict())
	_check(summary_a.get("prototype_type") == "statement_contradiction" and summary_c.get("prototype_type") == "timeline_reconstruction", "each export must keep its own prototype tag")
	_check(summary_a.get("session_id") != summary_c.get("session_id"), "two independently started recorders must never share a session id")
	var events_a: Array = recorder_a.get_events()
	var events_c: Array = recorder_c.get_events()
	_check(not events_a.any(func(e): return String(e.get("payload", {}).get("case_id", "")) == "fx_pc_case"), "Prototype A's recorder must never see Prototype C's case id")
	_check(not events_c.any(func(e): return String(e.get("payload", {}).get("case_id", "")) == "fx_pa_case"), "Prototype C's recorder must never see Prototype A's case id")
	_check(summary_a.get("runs", [])[0].get("submission_count") == 1 and summary_c.get("runs", [])[0].get("submission_count") == 1, "each summary must reflect only its own run's submissions")


func _remove_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full: String = path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
