extends SceneTree
## Focused tests for DeductionLabRecorder (Milestone 1.10 — see
## docs/deduction-lab.md): off-by-default, Start/Stop/Clear, sequence/elapsed-
## time guarantees (via an injected fake clock), session-signal wiring and
## author_debug vs. player_preview source tagging, schema/export correctness,
## safe filenames, and export-failure handling — using a throwaway user://
## directory cleaned up before and after, the same isolation stance
## TestHelpers.isolate_save takes for save files. Run with:
##   godot --headless --path . -s res://scenes/test/deduction_lab_recorder_test.gd

const TEST_EXPORT_DIR := "user://deduction_lab_recorder_test_tmp"

## A minimal controllable clock: advance(ms) moves it forward, now() reads it
## back — lets tests assert exact elapsed_ms values instead of trusting real
## wall-clock time.
class FakeClock:
	var _value: int = 0

	func advance(delta_ms: int) -> void:
		_value += delta_ms

	func now() -> int:
		return _value


var recorder_script: Variant
var session_script: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	recorder_script = load("res://scripts/deduction/deduction_lab_recorder.gd")
	session_script = load("res://scripts/deduction/deduction_session.gd")

	_remove_dir_recursive(TEST_EXPORT_DIR)

	print("=== DeductionLabRecorder — focused tests ===")
	_test_off_by_default()
	_test_start_stop_behavior()
	_test_sequence_and_elapsed_time()
	_test_clear_behavior()
	_test_session_wiring_and_source_tagging()
	_test_session_reset_event()
	_test_schema_and_metadata()
	_test_event_schema_version_matches_vocabulary()
	_test_stable_serialization()
	_test_export_success()
	_test_safe_filename_generation()
	_test_export_failure_handling()

	_remove_dir_recursive(TEST_EXPORT_DIR)
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_recorder(clock: FakeClock = null):
	if clock == null:
		return recorder_script.new()
	return recorder_script.new(Callable(clock, "now"))


func _test_off_by_default() -> void:
	var recorder = _new_recorder()
	_check(not recorder.is_recording(), "a freshly constructed recorder should not be recording")
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {"evidence_id": "e_x"})
	_check(recorder.get_events().is_empty(), "record() must be a no-op while not recording")


func _test_start_stop_behavior() -> void:
	var recorder = _new_recorder()
	recorder.start("case_a")
	_check(recorder.is_recording(), "start() should turn recording on")
	_check(recorder.get_events().size() == 1, "start() should itself record exactly one session_started event")
	_check(recorder.get_events()[0].get("type") == recorder_script.EVENT_SESSION_STARTED, "the first event should be session_started")

	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {"evidence_id": "e_x"})
	_check(recorder.get_events().size() == 2, "record() should append while recording")

	recorder.stop()
	_check(not recorder.is_recording(), "stop() should turn recording off")
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {"evidence_id": "e_y"})
	_check(recorder.get_events().size() == 2, "record() after stop() must be a no-op")
	_check(recorder.get_events().size() == 2, "stop() must not discard events already captured")


func _test_sequence_and_elapsed_time() -> void:
	var clock := FakeClock.new()
	var recorder = _new_recorder(clock)
	recorder.start("case_a")
	clock.advance(50)
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {})
	clock.advance(100)
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {})
	clock.advance(0)
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {})

	var events: Array[Dictionary] = recorder.get_events()
	_check(events.size() == 4, "sanity — 4 events should have been recorded (including session_started)")
	var sequences: Array = []
	var elapsed: Array = []
	for event in events:
		sequences.append(event.get("sequence"))
		elapsed.append(event.get("elapsed_ms"))
	_check(sequences == [1, 2, 3, 4], "sequence numbers should strictly increase from 1: got %s" % [sequences])
	_check(elapsed == [0, 50, 150, 150], "elapsed_ms should track the injected clock exactly: got %s" % [elapsed])
	for i in range(1, elapsed.size()):
		_check(elapsed[i] >= elapsed[i - 1], "elapsed_ms must be non-decreasing")


func _test_clear_behavior() -> void:
	var recorder = _new_recorder()
	recorder.start("case_a")
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {})
	_check(recorder.get_events().size() == 2, "sanity — two events before clear")
	recorder.clear()
	_check(recorder.get_events().is_empty(), "clear() should empty the event log")
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {})
	_check(recorder.get_events()[0].get("sequence") == 1, "clear() should reset the sequence counter back to 1")
	_check(recorder.is_recording(), "clear() should not implicitly stop recording")


func _test_session_wiring_and_source_tagging() -> void:
	var recorder = _new_recorder()
	recorder.start("fx_case")
	var session = session_script.new("fx_case")
	recorder.connect_session(session)

	recorder.set_current_source(recorder_script.SOURCE_PLAYER_PREVIEW)
	session.mark_evidence_opened("e_log")
	recorder.set_current_source(recorder_script.SOURCE_AUTHOR_DEBUG)
	session.resolve_claim("ded_misused", "supported", true)
	session.advance_hint("ded_misused", 1)
	session.record_attempt("ded_misused", "supports", "valid_support")
	session.mark_solved()

	var events: Array[Dictionary] = recorder.get_events()
	var by_type: Dictionary = {}
	for event in events:
		by_type[event.get("type")] = event

	_check(by_type.get("evidence_opened", {}).get("source") == recorder_script.SOURCE_PLAYER_PREVIEW, "an evidence_opened event fired while source=player_preview should be tagged player_preview")
	_check(by_type.get("evidence_opened", {}).get("payload", {}).get("evidence_id") == "e_log", "the evidence_opened payload should carry the real evidence id")
	_check(by_type.get("claim_resolved", {}).get("source") == recorder_script.SOURCE_AUTHOR_DEBUG, "a claim_resolved event fired while source=author_debug should be tagged author_debug — never mistaken for real playtest behavior")
	_check(by_type.get("deduction_unlocked", {}).get("source") == recorder_script.SOURCE_AUTHOR_DEBUG, "deduction_unlocked should also be tagged author_debug here")
	_check(by_type.get("hint_revealed", {}).get("payload", {}).get("level") == 1, "hint_revealed payload should carry the level")
	_check(by_type.get("proof_committed", {}).get("payload", {}).get("category") == "valid_support", "proof_committed payload should carry the category")
	_check(by_type.has("case_solved"), "case_solved should be recorded")

	# Idempotent wiring: connecting the same session again must not double-record.
	recorder.connect_session(session)
	var count_before: int = recorder.get_events().size()
	session.mark_evidence_opened("e_second")
	_check(recorder.get_events().size() == count_before + 1, "reconnecting the same session must not cause double-recording")


func _test_session_reset_event() -> void:
	var recorder = _new_recorder()
	recorder.start("fx_case")
	recorder.record_session_reset()
	var events: Array[Dictionary] = recorder.get_events()
	_check(events[events.size() - 1].get("type") == recorder_script.EVENT_SESSION_RESET, "record_session_reset() should append a session_reset event")


func _test_schema_and_metadata() -> void:
	var recorder = _new_recorder()
	recorder.start("proto_x_archive_ledger", "deduction_lab", "vi")
	var exported: Dictionary = recorder.to_export_dict()
	var keys: Array = exported.keys()
	keys.sort()
	var expected: Array = ["case_id", "event_schema_version", "events", "locale", "prototype", "schema_version", "session_id", "started_at_utc"]
	expected.sort()
	_check(keys == expected, "the export schema should have exactly the documented top-level fields, got %s" % [keys])
	_check(exported.get("schema_version") == 1, "schema_version (the outer envelope) should stay 1")
	_check(exported.get("event_schema_version") == 2, "event_schema_version (the event vocabulary) should be 2 (Milestone 1.14.1 — docs/deduction-lab.md, \"Recorder schema\")")
	_check(exported.get("case_id") == "proto_x_archive_ledger", "case_id should round-trip")
	_check(exported.get("locale") == "vi", "locale should round-trip")
	_check(exported.get("prototype") == "deduction_lab", "prototype should round-trip")
	_check(String(exported.get("session_id", "")) != "", "a session id should be generated")
	_check(String(exported.get("started_at_utc", "")).contains("T"), "started_at_utc should look like an ISO-8601 timestamp: got %s" % exported.get("started_at_utc"))

	# No PII: only the documented fields, and only values this process itself
	# generated (no username, hostname, or email anywhere in the export).
	var serialized: String = JSON.stringify(exported)
	for forbidden in [OS.get_environment("USER"), OS.get_environment("USERNAME")]:
		if forbidden != "":
			_check(not serialized.contains(forbidden), "the export must never contain the OS user name")


## Contract test (Milestone 1.14.1, docs/deduction-lab.md "Recorder schema"):
## the declared event_schema_version must actually agree with the event
## vocabulary a real prototype run emits through this recorder — never bump
## one without the other, and never let a retired v1 event type or payload
## key slip back in. Drives a real PrototypeAController failure through this
## recorder and inspects the exported dict directly, not just the version
## number in isolation.
func _test_event_schema_version_matches_vocabulary() -> void:
	var recorder = _new_recorder()
	recorder.start("fx_pa_case", "statement_contradiction", "en")
	var controller = load("res://scripts/deduction/prototype_a_controller.gd").new()
	var fixtures = load("res://scenes/test/deduction_fixtures.gd")
	controller.start(fixtures.prototype_a_case(), recorder)
	controller.select_statement(1)  # st_required1
	controller.select_evidence("e_c")  # wrong for st_required1 — a genuine failed formal commit
	controller.present_evidence()

	var exported: Dictionary = recorder.to_export_dict()
	_check(exported.get("event_schema_version") == 2, "the exported recording should declare event_schema_version 2, got %s" % exported.get("event_schema_version"))
	var types: Array = []
	var failed_commit_payload: Dictionary = {}
	for event in (exported.get("events", []) as Array):
		types.append(event.get("type"))
		if event.get("type") == "formal_commit_failed":
			failed_commit_payload = event.get("payload", {})
	_check(types.has("run_resolution_result_changed"), "a v2 export should use the renamed run_resolution_result_changed event type, got %s" % [types])
	_check(not types.has("resolution_tier_changed"), "a v2 export must never emit the retired v1 event type resolution_tier_changed, got %s" % [types])
	_check(failed_commit_payload.has("run_resolution_result_before") and failed_commit_payload.has("run_resolution_result_after"), "v2 formal_commit_failed payloads should carry run_resolution_result_before/after, got %s" % [failed_commit_payload])
	_check(not failed_commit_payload.has("tier_before") and not failed_commit_payload.has("tier_after"), "v2 formal_commit_failed payloads must never carry the retired v1 tier_before/tier_after keys, got %s" % [failed_commit_payload])


func _test_stable_serialization() -> void:
	var clock := FakeClock.new()
	var recorder = _new_recorder(clock)
	recorder.start("case_a")
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {"evidence_id": "e_x"})
	var first: String = JSON.stringify(recorder.to_export_dict())
	var second: String = JSON.stringify(recorder.to_export_dict())
	_check(first == second, "serializing the same recorder state twice should produce identical JSON")


func _test_export_success() -> void:
	var recorder = _new_recorder()
	recorder.start("proto_y_lab_sample")
	recorder.record("evidence_opened", recorder_script.SOURCE_PLAYER_PREVIEW, {"evidence_id": "e_x"})
	var result: Dictionary = recorder.export_to_file(TEST_EXPORT_DIR)
	_check(result.get("success") == true, "export_to_file should report success: %s" % [result])
	_check(FileAccess.file_exists(result.get("path", "")), "the exported file should actually exist at the reported path")

	var file: FileAccess = FileAccess.open(result.get("path", ""), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("case_id") == "proto_y_lab_sample", "the exported file should contain valid JSON matching to_export_dict()")


func _test_safe_filename_generation() -> void:
	var recorder = recorder_script.new(Callable(), Callable(func() -> String: return "../../evil/../id"))
	recorder.start("weird case/name!.json")
	var result: Dictionary = recorder.export_to_file(TEST_EXPORT_DIR)
	_check(result.get("success") == true, "export should still succeed despite unsafe characters in the case id/session id")
	var path: String = String(result.get("path", ""))
	_check(path.begins_with(TEST_EXPORT_DIR), "the exported file must stay inside the requested export directory (no path traversal): got %s" % path)
	_check(not path.contains(".."), "the exported file path must never contain \"..\"")
	_check(FileAccess.file_exists(path), "the safely-named file should exist")


func _test_export_failure_handling() -> void:
	var blocked_path: String = TEST_EXPORT_DIR.path_join("blocked_by_a_file")
	DirAccess.make_dir_recursive_absolute(TEST_EXPORT_DIR)
	var blocker: FileAccess = FileAccess.open(blocked_path, FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()

	var recorder = _new_recorder()
	recorder.start("case_a")
	# blocked_path already exists as a FILE, so trying to use it as the export
	# DIRECTORY must fail cleanly rather than crash or silently overwrite it.
	var result: Dictionary = recorder.export_to_file(blocked_path)
	_check(result.get("success") == false, "exporting into a path blocked by an existing file should fail, not crash")
	_check(String(result.get("error", "")) != "", "a failed export should explain why")


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
