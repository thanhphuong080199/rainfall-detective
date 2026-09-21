extends SceneTree
## Milestone 1.16 — save/load of the production chapter run (see
## docs/core-loop-sandbox.md, "Save/load", and docs/testing.md). Every check
## goes through the real SaveManager file: save -> a NEW ChapterRuntime (what a
## fresh process or the gameplay scene being rebuilt gets) -> load -> assert
## the exact durable and active-mechanic state came back, and that restoring
## replayed nothing (no consequence, no "once" event, no acquisition
## observation). Also: v1 -> v2 migration, unsupported/corrupt files, and
## whole-snapshot rejection of every half-applied state the 1.15B atomicity
## table forbids. Needs autoloads but no scene tree — FAST and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_save_test.gd

const SAVE_NAME := "core_loop_save_test"

var support: CoreLoopTestSupport
var game_state: Node
var save_manager: Node
var event_manager: Node
var _runtimes: Array = []
var _fired_events: Array[String] = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	support = CoreLoopTestSupport.new(self)
	game_state = support.game_state
	save_manager = support.save_manager
	event_manager = get_root().get_node("EventManager")
	event_manager.event_triggered.connect(func(event_id: String) -> void: _fired_events.append(event_id))
	TestHelpers.isolate_save(save_manager, SAVE_NAME)
	TestHelpers.isolate_locale(get_root().get_node("LocaleManager"), SAVE_NAME)

	print("=== Core loop save/load — tests ===")
	_test_resume_at_every_checkpoint()
	_test_draft_and_failure_resume()
	_test_assisted_and_partner_resume()
	_test_timeline_and_claim_resume()
	_test_repeated_load_duplicates_nothing()
	_test_v1_save_migrates()
	_test_unsupported_and_corrupt_files_fail_safely()
	_test_half_applied_snapshots_rejected()
	_test_atomic_write()
	_test_checkpoint_failure_is_not_fatal()

	for runtime in _runtimes:
		runtime.detach()
	save_manager.delete_save()
	DirAccess.remove_absolute(save_manager.save_path.get_basename() + ".unreadable.json")
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _runtime(prefix: String) -> RefCounted:
	var runtime: RefCounted = support.new_runtime(prefix)
	_runtimes.append(runtime)
	return runtime


## Simulates quitting and pressing Continue: the state is wiped (another case
## started), then the file is loaded into a brand-new runtime.
func _reload(prefix: String) -> RefCounted:
	save_manager.new_game("case_00_sandbox")
	var loaded: bool = save_manager.load_game()
	_check(loaded, "%s: the save should load" % prefix)
	var runtime: RefCounted = _runtime(prefix)
	runtime.reload_from_game_state()
	return runtime


func _durable(runtime: RefCounted) -> Dictionary:
	var snapshot: Dictionary = game_state.chapter_run.duplicate(true)
	snapshot.erase("revision")
	return {
		"phase": runtime.get_phase_id(), "snapshot": snapshot, "flags": game_state.flags.duplicate(),
		"evidence": game_state.evidence_inventory.duplicate(), "seen": game_state.seen_interactions.duplicate(),
		"location": game_state.current_location, "help": runtime.get_run_help_result(),
	}


# ---------------------------------------------------------------------------

func _test_resume_at_every_checkpoint() -> void:
	for stop in ["new", "briefing", "b1", "a1", "b2", "timeline", "claim"]:
		var runtime: RefCounted = _runtime("cp-%s" % stop)
		support.play_until(runtime, stop)
		runtime.flush()
		var before: Dictionary = _durable(runtime)
		_fired_events.clear()
		var resumed: RefCounted = _reload("cp-%s-resumed" % stop)
		_check(not resumed.has_error(), "%s: resumed without error (%s)" % [stop, resumed.get_error()])
		var after: Dictionary = _durable(resumed)
		for key in before:
			_check(after[key] == before[key], "%s: %s must survive save/load exactly (%s vs %s)" % [stop, key, before[key], after[key]])
		_check(not _fired_events.has("sbx_chapter_01_complete"), "%s: loading never re-fires the completion event" % stop)
		var types: Array[String] = support.event_types(resumed)
		_check(types.has("chapter_resumed") and types.has("checkpoint_restored"), "%s: a resume is observed once" % stop)
		_check(not types.has("consequence_applied") and not types.has("evidence_acquired") and not types.has("chapter_started"), "%s: restore replays no acquisition/consequence/start: %s" % [stop, types])
		if stop == "claim":
			_check(resumed.is_completed() and resumed.get_phase_id() == "completed", "a completed chapter reopens completed")
			_check(resumed.perform(CoreLoopTestSupport.C1, "submit_claim").get("reason", "") == "chapter_completed", "a restored completed run refuses resubmission")


func _test_draft_and_failure_resume() -> void:
	var runtime: RefCounted = _runtime("draft")
	support.play_until(runtime, "briefing")
	support.gather_b1_evidence()
	support.examine("sbx_archive_lobby", "noticeboard")
	runtime.open_unit(CoreLoopTestSupport.B1)
	support.fill_b(runtime, CoreLoopTestSupport.B1, ["e_door_log", "e_tram_tap"])
	runtime.perform(CoreLoopTestSupport.B1, "open_evidence", ["e_route_note"])
	runtime.close_unit()  # drafts are checkpointed on close
	var resumed: RefCounted = _reload("draft-resumed")
	var controller: RefCounted = resumed.get_unit(CoreLoopTestSupport.B1).controller
	var expected_draft: Array[String] = ["e_door_log", "e_tram_tap"]
	_check(controller.get_selected_evidence_ids() == expected_draft, "a partial B draft comes back exactly: %s" % [controller.get_selected_evidence_ids()])
	_check(resumed.get_session().has_opened_evidence("e_route_note"), "opened evidence survives")

	resumed.open_unit(CoreLoopTestSupport.B1)
	resumed.perform(CoreLoopTestSupport.B1, "select_evidence", ["e_back_door_sighting"])
	resumed.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check(resumed.get_unit(CoreLoopTestSupport.B1).is_feedback_open(), "the failure's feedback is shown")
	var again: RefCounted = _reload("failure-resumed")
	var unit: RefCounted = again.get_unit(CoreLoopTestSupport.B1)
	_check(unit.get_policy().get_current_unit_failures() == 1, "a consumed failure is not refunded by save/load")
	_check(unit.is_feedback_open() and str(unit.get_open_feedback().get("kind", "")) == "theory", "the pending failure feedback is restored, not dropped")
	_check(again.get_open_unit_id() == CoreLoopTestSupport.B1, "the open mechanic is restored for exact resume")
	var resumed_summary: Dictionary = load("res://scripts/deduction/prototype_evaluation_summary.gd").summarize(again.get_recorder().to_export_dict())
	var resumed_runs: Array = resumed_summary.get("runs", [])
	_check(resumed_runs.size() == 1 and resumed_runs[0].get("resumed", false) and resumed_runs[0].get("unit_id", "") == CoreLoopTestSupport.B1, "a unit resumed in a new recording segment is still summarized, marked resumed: %s" % [resumed_runs])
	var duplicate: Dictionary = again.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check((duplicate.get("result", {}) as Dictionary).get("reason", "") == "duplicate_failed_theory" and unit.get_policy().get_current_unit_failures() == 1, "the failed signature survives: the same set is still blocked free")


func _test_assisted_and_partner_resume() -> void:
	var runtime: RefCounted = _runtime("assist")
	support.play_until(runtime, "briefing")
	support.gather_b1_evidence()
	support.examine("sbx_archive_lobby", "noticeboard")
	support.examine("sbx_archive_lobby", "front_desk_log")
	runtime.open_unit(CoreLoopTestSupport.B1)
	var wrong_sets: Array = [
		["e_door_log", "e_tram_tap", "e_back_door_sighting"], ["e_door_log", "e_route_note", "e_back_door_sighting"],
		["e_tram_tap", "e_route_note", "e_back_door_sighting"], ["e_door_log", "e_tram_tap", "e_lost_property_sheet"],
		["e_door_log", "e_route_note", "e_lost_property_sheet"],
	]
	for i in 3:
		support.clear_b(runtime, CoreLoopTestSupport.B1)
		support.fill_b(runtime, CoreLoopTestSupport.B1, wrong_sets[i])
		runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	runtime.perform(CoreLoopTestSupport.B1, "accept_assistance")
	var assisted: RefCounted = _reload("assisted-resumed")
	var policy: ResolutionPolicy = assisted.get_unit(CoreLoopTestSupport.B1).get_policy()
	_check(policy.get_current_unit_phase() == "assisted" and policy.get_assisted_attempts_remaining() == 2, "Assisted Mode and its remaining budget survive")
	_check(assisted.get_unit(CoreLoopTestSupport.B1).controller.get_assistance_draft_index() == 0, "the surfaced assistance survives")
	_check(assisted.get_run_help_result() == "assisted", "the run help result survives")
	for i in [3, 4]:
		support.clear_b(assisted, CoreLoopTestSupport.B1)
		support.fill_b(assisted, CoreLoopTestSupport.B1, wrong_sets[i])
		assisted.perform(CoreLoopTestSupport.B1, "commit_theory")
	assisted.perform(CoreLoopTestSupport.B1, "resolve_with_partner")
	var partnered: RefCounted = _reload("partner-resumed")
	_check(partnered.get_phase_id() == "confrontation", "a partner resolution resumes at the next phase, never as unresolved B1")
	_check(partnered.get_findings()[0].get("resolved_by", "") == "partner", "partner attribution survives")
	_check(partnered.get_session().is_supported("ded_badge_misused"), "the partner's accepted deduction survives")


func _test_timeline_and_claim_resume() -> void:
	var runtime: RefCounted = _runtime("tl")
	support.play_until(runtime, "b2")
	runtime.open_unit(CoreLoopTestSupport.C1)
	runtime.perform(CoreLoopTestSupport.C1, "place_event", ["tl_mara_leaves", "19:35"])
	runtime.perform(CoreLoopTestSupport.C1, "place_event", ["tl_window_forced", "20:10"])
	runtime.perform(CoreLoopTestSupport.C1, "open_fact", ["c_badge_time"])
	runtime.close_unit()
	var partial: RefCounted = _reload("tl-partial")
	var controller: RefCounted = partial.get_unit(CoreLoopTestSupport.C1).controller
	_check(controller.get_placement("tl_mara_leaves") == "19:35" and controller.get_placement("tl_window_forced") == "20:10" and controller.get_placement("tl_cardigan_taken") == "", "partial placements come back exactly")
	_check(controller.has_opened_fact("c_badge_time"), "opened facts come back")
	partial.open_unit(CoreLoopTestSupport.C1)
	support.place_timeline(partial, CoreLoopTestSupport.C1_TIMELINE)
	partial.perform(CoreLoopTestSupport.C1, "submit_timeline")
	partial.perform(CoreLoopTestSupport.C1, "select_claim_answer", [true])
	partial.close_unit()
	var claim_phase: RefCounted = _reload("tl-claim")
	var restored: RefCounted = claim_phase.get_unit(CoreLoopTestSupport.C1).controller
	_check(claim_phase.get_phase_id() == "final_claim" and restored.is_accepted() and restored.is_claim_phase(), "an accepted timeline reopens in the final-claim phase")
	_check(restored.get_accepted_time("tl_window_forced") == "20:08", "the accepted timeline is locked in as placed")
	_check(restored.get_selected_claim_answer() == "impossible" and restored.get_selected_justification_id() == "", "the partial verdict survives")
	_check(restored.get_policy().get_current_unit_phase() == "standard" and restored.get_policy().get_current_unit_failures() == 0, "the claim has its own fresh local budget")


func _test_repeated_load_duplicates_nothing() -> void:
	var runtime: RefCounted = _runtime("repeat")
	support.play_until(runtime, "a1")
	runtime.flush()
	var first: Dictionary = {}
	for i in 3:
		var resumed: RefCounted = _reload("repeat-%d" % i)
		var state: Dictionary = _durable(resumed)
		if i == 0:
			first = state
		_check(state == first, "load #%d is identical to the first" % (i + 1))
	_check(game_state.evidence_inventory.count("sbx_door_log") == 1, "repeated loads never duplicate an acquisition")
	_check((game_state.chapter_run.get("applied_consequences", {}) as Dictionary).size() == 2, "repeated loads never duplicate a consequence")


func _test_v1_save_migrates() -> void:
	save_manager.new_game("case_00_sandbox")
	var v1_state: Dictionary = game_state.get_save_dict()
	v1_state.erase("chapter_run")
	_write_save({"version": 1, "state": v1_state})
	var inspection: Dictionary = save_manager.inspect_save()
	_check(inspection.get("ok", false) and inspection.get("version", 0) == 1, "a pre-1.16 (v1) save is still supported: %s" % [inspection])
	_check(save_manager.load_game() and game_state.chapter_run.is_empty(), "a v1 save migrates to 'no active chapter run'")
	var runtime: RefCounted = _runtime("v1")
	runtime.reload_from_game_state()
	_check(not runtime.is_active(), "a migrated v1 save never activates the core-loop runtime")
	_write_save({"state": v1_state})
	_check(save_manager.inspect_save().get("ok", false), "a save with no version field is treated as v1")


func _test_unsupported_and_corrupt_files_fail_safely() -> void:
	var runtime: RefCounted = _runtime("corrupt")
	support.play_until(runtime, "b1")
	var before: Dictionary = game_state.get_save_dict().duplicate(true)
	_write_save({"version": 99, "state": before})
	_check(save_manager.inspect_save().get("reason", "") == "unsupported_version" and not save_manager.has_resumable_save(), "a newer, unsupported save is not resumable")
	_check(not save_manager.load_game() and game_state.get_save_dict() == before, "loading it fails without touching GameState")
	var file := FileAccess.open(save_manager.save_path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	_check(save_manager.inspect_save().get("reason", "") == "corrupt" and not save_manager.load_game(), "a corrupt file never loads")
	_check(game_state.get_save_dict() == before, "a failed load leaves the in-memory game untouched")
	var backup: String = save_manager.preserve_unreadable_save()
	_check(backup != "" and FileAccess.get_file_as_string(backup) == "{ not json", "an unreadable save is preserved for diagnosis before New Game overwrites it")


func _test_half_applied_snapshots_rejected() -> void:
	var runtime: RefCounted = _runtime("half")
	support.play_until(runtime, "b1")
	runtime.flush()
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_manager.save_path))
	var mutations: Dictionary = {
		"resolved unit without its applied consequence": func(run: Dictionary) -> void: (run["applied_consequences"] as Dictionary).clear(),
		"applied consequence without its producing resolution": func(run: Dictionary) -> void: run["applied_consequences"]["sbx_a1_resolved"] = {"unit": "a1_denial", "outcome": "resolved", "resolved_by": "player"},
		"phase ahead of what was applied": func(run: Dictionary) -> void: run["phase_index"] = 3,
		"completed flag without the chapter marked complete": func(run: Dictionary) -> void: run["phase_index"] = 6; run["completed"] = true,
		"consumed failure count out of range": func(run: Dictionary) -> void: run["units"]["b1_badge"]["controller"]["policy"]["unit_standard_failures"] = -1,
		"unknown unit": func(run: Dictionary) -> void: run["units"]["nope"] = run["units"]["b1_badge"],
		"run help result lower than the help used": func(run: Dictionary) -> void: run["units"]["b1_badge"]["controller"]["policy"]["max_hint_level"] = 3; run["units"]["b1_badge"]["controller"]["policy"]["run_resolution_result"] = "assisted",
		"partner attribution without a partner-capable value": func(run: Dictionary) -> void: run["applied_consequences"]["sbx_b1_resolved"]["resolved_by"] = "someone",
		"snapshot of another chapter": func(run: Dictionary) -> void: run["chapter_id"] = "test_case_chapter_01",
	}
	for label in mutations:
		var payload: Dictionary = valid.duplicate(true)
		(mutations[label] as Callable).call(payload["state"]["chapter_run"])
		_write_save(payload)
		var before: Dictionary = game_state.get_save_dict().duplicate(true)
		_check(save_manager.inspect_save().get("reason", "") == "invalid_chapter_run", "%s: rejected as a whole" % label)
		_check(not save_manager.load_game() and game_state.get_save_dict() == before, "%s: never partially loaded" % label)
	_write_save(valid)
	_check(save_manager.has_resumable_save(), "the unmodified file is still valid (the mutations above are what broke it)")


func _test_atomic_write() -> void:
	var runtime: RefCounted = _runtime("atomic")
	support.play_until(runtime, "briefing")
	_check(not FileAccess.file_exists(save_manager.save_path + ".tmp"), "no temporary file is left behind by a checkpoint")
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_manager.save_path))
	_check(typeof(payload) == TYPE_DICTIONARY and int(payload.get("version", 0)) == 2, "checkpoints write the current (v2) format")


func _test_checkpoint_failure_is_not_fatal() -> void:
	var runtime: RefCounted = _runtime("nosave")
	support.play_until(runtime, "briefing")
	support.gather_b1_evidence()
	var failed: Array[bool] = [false]
	runtime.checkpoint_failed.connect(func() -> void: failed[0] = true)
	var real_path: String = save_manager.save_path
	var blocker := FileAccess.open("user://core_loop_save_test_blocker", FileAccess.WRITE)
	blocker.store_string("x")
	blocker.close()
	save_manager.save_path = "user://core_loop_save_test_blocker/save.json"
	var result: Dictionary = support.solve_b(runtime, CoreLoopTestSupport.B1, CoreLoopTestSupport.B1_PATH)
	save_manager.save_path = real_path
	DirAccess.remove_absolute("user://core_loop_save_test_blocker")
	_check(failed[0] and support.event_types(runtime).has("checkpoint_failed"), "a failed checkpoint is signalled and recorded")
	_check(result.get("consequences", []) == ["sbx_b1_resolved"] and runtime.get_phase_id() == "confrontation", "gameplay continues from the in-memory run after a failed write")


func _write_save(payload: Dictionary) -> void:
	var file := FileAccess.open(save_manager.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
