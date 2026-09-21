extends SceneTree
## Milestone 1.16 — ChapterRuntime contract tests (see docs/core-loop-sandbox.md
## and docs/testing.md). Drives the production orchestrator through the real
## autoloads (GameState/Investigation/DialogueManager/EventManager/
## CaseManager/SaveManager) with the non-canon sandbox chapter: phase
## transitions both ways (locked until the last dependency, then offered),
## idempotent consequences, the single-deduction B, A, the second B, C's two
## units, chapter completion, duplicate refusal, help/partner attribution and
## the help-only run result, fresh-run isolation, recorder non-authority and
## debug/production session isolation. Save/load lives in
## core_loop_save_test.gd; real scenes/buttons in core_loop_scene_test.gd.
## Needs autoloads but no scene tree — FAST and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_runtime_test.gd

var support: CoreLoopTestSupport
var game_state: Node
var save_manager: Node
var case_manager: Node
var _runtimes: Array = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	support = CoreLoopTestSupport.new(self)
	game_state = support.game_state
	save_manager = support.save_manager
	case_manager = support.case_manager
	TestHelpers.isolate_save(save_manager, "core_loop_runtime_test")
	TestHelpers.isolate_locale(get_root().get_node("LocaleManager"), "core_loop_runtime_test")

	print("=== Core loop runtime — contract tests ===")
	_test_entry_case_is_data_driven()
	_test_new_run_starts_in_briefing()
	_test_commands_refused_out_of_phase()
	_test_full_player_route()
	_test_consequences_idempotent_and_attributable()
	_test_single_deduction_b()
	_test_duplicate_candidates_blocked_without_cost()
	_test_help_escalates_result_failures_do_not()
	_test_assistance_and_partner_resolution()
	_test_alternate_proof_path_accepted()
	_test_restart_is_a_fresh_run()
	_test_recorder_is_observational()
	_test_evaluation_summary_reads_production_log()
	_test_debug_prototypes_stay_isolated()
	_test_flat_case_leaves_runtime_inactive()

	for runtime in _runtimes:
		runtime.detach()
	save_manager.delete_save()
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


# ---------------------------------------------------------------------------

func _test_entry_case_is_data_driven() -> void:
	_check(save_manager.get_new_game_case_id() == CoreLoopTestSupport.CASE_ID, "New Game should start the case that declares new_game_entry, got %s" % save_manager.get_new_game_case_id())


func _test_new_run_starts_in_briefing() -> void:
	save_manager.delete_save()
	var runtime: RefCounted = _runtime("brief")
	support.start_new_game(runtime)
	_check(runtime.is_active() and not runtime.has_error(), "the sandbox chapter should activate the runtime (error: %s)" % runtime.get_error())
	_check(runtime.get_phase_id() == "briefing" and runtime.is_briefing(), "a new run starts in the briefing, got %s" % runtime.get_phase_id())
	_check(runtime.get_run_id() == "brief-1", "the run id comes from the injected generator")
	_check(save_manager.has_resumable_save(), "creating the run is itself a checkpoint (1.15B §13.2)")
	_check(str(game_state.chapter_run.get("run_id", "")) == "brief-1", "the snapshot lives in GameState.chapter_run")
	_check(runtime.get_session() != null and runtime.get_session().get_resolved_claims().is_empty(), "a new run owns a fresh shared session")
	var ack: Dictionary = runtime.acknowledge_briefing()
	_check(ack.get("ok", false) and runtime.get_phase_id() == "investigation_1", "acknowledging the briefing enters the first investigation phase")
	_check(not runtime.acknowledge_briefing().get("ok", true), "the briefing cannot be acknowledged twice")


func _test_commands_refused_out_of_phase() -> void:
	var runtime: RefCounted = _runtime("refuse")
	support.start_new_game(runtime)
	# Briefing: no mechanic can open, nothing reaches an evaluator.
	_check(runtime.open_unit(CoreLoopTestSupport.B1).get("reason", "") == "unit_not_current", "no unit is current during the briefing")
	_check(runtime.perform(CoreLoopTestSupport.B1, "commit_theory").get("ok", true) == false, "a formal command during the briefing is refused")
	runtime.acknowledge_briefing()
	# B1 is current but locked until its LAST required evidence is held.
	_check(runtime.get_unit_status(CoreLoopTestSupport.B1).get("reason", "") == "unit_locked", "B1 stays locked with no evidence")
	support.examine("sbx_archive_lobby", "transit_map")
	support.talk("sbx_archive_lobby", "sbx_mara", "evening")
	_check(runtime.get_unit_status(CoreLoopTestSupport.B1).get("reason", "") == "unit_locked", "B1 stays locked until the door log too is held")
	_check(runtime.open_unit(CoreLoopTestSupport.B1).get("ok", true) == false, "opening a locked unit is a no-op")
	_check(runtime.get_unit(CoreLoopTestSupport.B1) == null, "a refused open never starts the mechanic")
	support.examine("sbx_stacks_wing", "door_terminal")
	_check(runtime.get_unit_status(CoreLoopTestSupport.B1).get("available", false), "B1 is offered once the last dependency is acquired")
	# Future units stay hidden and inactive.
	_check(runtime.open_unit(CoreLoopTestSupport.A1).get("reason", "") == "unit_not_current", "A cannot open during the first investigation")
	_check(runtime.perform(CoreLoopTestSupport.C1, "submit_timeline").get("reason", "") == "unit_not_current", "C cannot be submitted out of order")
	_check(runtime.perform(CoreLoopTestSupport.B1, "commit_theory").get("reason", "") == "unit_not_started", "a unit must be opened before commands reach it")
	runtime.open_unit(CoreLoopTestSupport.B1)
	_check(runtime.perform(CoreLoopTestSupport.B1, "no_such_command").get("reason", "") == "unknown_command", "only whitelisted commands reach the controller")
	_check(runtime.perform(CoreLoopTestSupport.B1, "select_evidence", [3]).get("reason", "") == "bad_arguments", "malformed arguments are refused before the controller")
	var incomplete: Dictionary = runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check(incomplete.get("ok", false) and (incomplete.get("result", {}) as Dictionary).get("counted", true) == false, "an incomplete draft reaches no evaluator and costs nothing")
	_check(runtime.get_unit(CoreLoopTestSupport.B1).get_policy().get_formal_commit_count() == 0, "no formal commit was counted")


func _test_full_player_route() -> void:
	var runtime: RefCounted = _runtime("route")
	var phases: Array[String] = []
	runtime.phase_changed.connect(func(phase_id: String) -> void: phases.append(phase_id))
	support.start_new_game(runtime)
	runtime.acknowledge_briefing()
	support.gather_b1_evidence()
	_check(game_state.has_evidence("sbx_door_log") and game_state.has_evidence("sbx_tram_tap") and game_state.has_evidence("sbx_route_note"), "investigation verbs grant the B1 evidence")

	var b1: Dictionary = support.solve_b(runtime, CoreLoopTestSupport.B1, CoreLoopTestSupport.B1_PATH)
	_check(b1.get("ok", false) and b1.get("consequences", []) == ["sbx_b1_resolved"], "B1 resolution applies exactly its consequence: %s" % [b1.get("consequences")])
	_check(runtime.get_session().is_supported("ded_badge_misused"), "B1's deduction is resolved in the SHARED session")
	_check(game_state.get_flag("sbx_confrontation_unlocked"), "B1's consequence unlocks the confrontation")
	_check(runtime.get_phase_id() == "confrontation", "B1 moves the chapter to the confrontation phase")

	_check(runtime.get_unit_status(CoreLoopTestSupport.A1).get("reason", "") == "unit_locked", "A stays locked until Oren has been pressed and the sheet is held")
	support.talk("sbx_stacks_wing", "sbx_oren", "badge")
	_check(runtime.get_unit_status(CoreLoopTestSupport.A1).get("reason", "") == "unit_locked", "A stays locked until the lost-property sheet is held too")
	support.examine("sbx_archive_lobby", "front_desk_log")
	_check(runtime.get_unit_status(CoreLoopTestSupport.A1).get("available", false), "A is offered once both dependencies hold")
	runtime.open_unit(CoreLoopTestSupport.A1)
	var pool: Array[String] = runtime.get_unit(CoreLoopTestSupport.A1).controller.get_evidence_pool_ids()
	_check(pool.has(CoreLoopTestSupport.A1_EVIDENCE) and not pool.has("e_wing_camera") and not pool.has("e_window_latch"), "A offers only ACQUIRED evidence: %s" % [pool])
	var a1: Dictionary = support.solve_a(runtime)
	_check(a1.get("consequences", []) == ["sbx_a1_resolved"], "A resolution applies exactly its consequence")
	_check(runtime.get_session().get_claim_status("st_oren_never_touched") == "refuted", "A's refutation lands in the same shared session")
	_check(runtime.get_session().is_supported("ded_badge_misused"), "A never discarded B1's resolved deduction")
	_check(game_state.get_flag("sbx_window_inspection_unlocked") and runtime.get_phase_id() == "investigation_2", "A opens the window inspection and the second investigation")

	_check(runtime.get_unit_status(CoreLoopTestSupport.B2).get("reason", "") == "unit_locked", "B2 is not offered before its evidence")
	support.gather_b2_evidence()
	_check(game_state.has_evidence("sbx_window_latch") and game_state.has_evidence("sbx_latch_guide"), "A's unlock made the latch and the maintenance office reachable")
	var b2: Dictionary = support.solve_b(runtime, CoreLoopTestSupport.B2, CoreLoopTestSupport.B2_PATH)
	_check(b2.get("consequences", []) == ["sbx_b2_resolved"] and runtime.get_phase_id() == "timeline", "B2 resolves separately and unlocks the timeline")
	_check(runtime.get_unit(CoreLoopTestSupport.B1) != runtime.get_unit(CoreLoopTestSupport.B2), "B1 and B2 are separate resolution units")

	var timeline: Dictionary = support.solve_timeline(runtime)
	_check(timeline.get("consequences", []) == ["sbx_c1_timeline_accepted"] and runtime.get_phase_id() == "final_claim", "an accepted timeline activates the final claim")
	_check(not runtime.is_completed() and not case_manager.is_chapter_complete(CoreLoopTestSupport.CHAPTER_ID), "the chapter is not complete before the final claim")
	var claim: Dictionary = support.solve_claim(runtime)
	_check(claim.get("consequences", []) == ["sbx_c1_claim_accepted"] and claim.get("completed", false), "the final claim completes the chapter")
	_check(runtime.is_completed() and runtime.get_phase_id() == "completed", "the run is in the completed phase")
	_check(case_manager.is_chapter_complete(CoreLoopTestSupport.CHAPTER_ID) and case_manager.is_case_complete(CoreLoopTestSupport.CASE_ID), "chapter/case completion stays CaseManager's, reached through the completion event")
	_check(phases == ["investigation_1", "confrontation", "investigation_2", "timeline", "final_claim", "completed"], "phases advance in the content-defined order: %s" % [phases])
	_check(runtime.get_run_help_result() == "independent", "an unaided run stays Independent")
	_check(runtime.get_findings().size() == 5, "five findings narrate the run")
	_check(runtime.perform(CoreLoopTestSupport.C1, "submit_claim").get("reason", "") == "chapter_completed", "a completed run refuses gameplay commands")
	_check(not game_state.has_evidence("sbx_shredding_log") and not game_state.has_evidence("sbx_harbor_photo"), "optional interactions were never needed to finish")


func _test_consequences_idempotent_and_attributable() -> void:
	var runtime: RefCounted = _runtime("idem")
	support.play_until(runtime, "b1")
	var applied_before: Dictionary = (game_state.chapter_run.get("applied_consequences", {}) as Dictionary).duplicate(true)
	var flags_before: Dictionary = game_state.flags.duplicate()
	# Re-driving the resolved unit changes nothing: it is no longer current.
	_check(runtime.perform(CoreLoopTestSupport.B1, "commit_theory").get("reason", "") == "unit_not_current", "a resolved B1 accepts no further commands")
	_check(game_state.chapter_run.get("applied_consequences", {}) == applied_before and game_state.flags == flags_before, "nothing is applied twice")
	var entry: Dictionary = applied_before.get("sbx_b1_resolved", {})
	_check(entry.get("unit", "") == CoreLoopTestSupport.B1 and entry.get("outcome", "") == "resolved" and entry.get("resolved_by", "") == "player", "each applied consequence records its producer and attribution: %s" % [entry])
	var producers: Array = load("res://scripts/core/content_validator.gd").find_flag_producers("sbx_confrontation_unlocked")
	_check(producers.size() == 1 and str(producers[0].get("source", "")).contains("b1_badge"), "the Case Debugger can trace the unlock back to B1's consequence: %s" % [producers])


func _test_single_deduction_b() -> void:
	var runtime: RefCounted = _runtime("single")
	support.play_until(runtime, "briefing")
	support.gather_b1_evidence()
	runtime.open_unit(CoreLoopTestSupport.B1)
	var controller: RefCounted = runtime.get_unit(CoreLoopTestSupport.B1).controller
	_check(controller.get_draft_count() == 1 and controller.get_slot_count() == 3, "a production B unit has exactly one question/draft")
	var pool: Array[String] = controller.get_evidence_pool_ids()
	_check(not pool.has("e_latch_guide") and not pool.has("e_window_latch") and pool.has("e_door_log"), "B draws only on acquired evidence: %s" % [pool])
	runtime.close_unit()
	support.examine("sbx_archive_lobby", "noticeboard")
	runtime.open_unit(CoreLoopTestSupport.B1)
	_check(controller.get_evidence_pool_ids().has("e_back_door_sighting"), "evidence acquired while the mechanic was closed joins its pool on reopen")
	support.fill_b(runtime, CoreLoopTestSupport.B1, CoreLoopTestSupport.B1_PATH)
	runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check(runtime.get_session().is_supported("ded_badge_misused") and not runtime.get_session().is_supported("ded_break_in_staged"), "committing B1 resolves ONE deduction, never B2's")


func _test_duplicate_candidates_blocked_without_cost() -> void:
	var runtime: RefCounted = _runtime("dup")
	support.play_until(runtime, "briefing")
	support.gather_b1_evidence()
	support.examine("sbx_archive_lobby", "noticeboard")  # optional red herring
	runtime.open_unit(CoreLoopTestSupport.B1)
	support.fill_b(runtime, CoreLoopTestSupport.B1, ["e_door_log", "e_tram_tap", "e_back_door_sighting"])
	var failed: Dictionary = runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	var policy: ResolutionPolicy = runtime.get_unit(CoreLoopTestSupport.B1).get_policy()
	_check((failed.get("result", {}) as Dictionary).get("counted", false) and policy.get_current_unit_failures() == 1, "a new, complete, wrong clue set consumes one local failure")
	support.clear_b(runtime, CoreLoopTestSupport.B1)
	for evidence_id in ["e_back_door_sighting", "e_door_log", "e_tram_tap"]:
		runtime.perform(CoreLoopTestSupport.B1, "select_evidence", [evidence_id])
	var duplicate: Dictionary = runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check((duplicate.get("result", {}) as Dictionary).get("reason", "") == "duplicate_failed_theory" and policy.get_current_unit_failures() == 1, "the same clue set in another order is blocked without cost")
	# A: the same failed statement/evidence pair.
	support.clear_b(runtime, CoreLoopTestSupport.B1)
	support.fill_b(runtime, CoreLoopTestSupport.B1, CoreLoopTestSupport.B1_PATH)
	runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	runtime.dismiss_feedback(CoreLoopTestSupport.B1)
	support.unlock_a1()
	runtime.open_unit(CoreLoopTestSupport.A1)
	runtime.perform(CoreLoopTestSupport.A1, "select_statement", [0])
	runtime.perform(CoreLoopTestSupport.A1, "select_evidence", ["e_tram_tap"])
	runtime.perform(CoreLoopTestSupport.A1, "present_evidence")
	var a_policy: ResolutionPolicy = runtime.get_unit(CoreLoopTestSupport.A1).get_policy()
	runtime.perform(CoreLoopTestSupport.A1, "select_evidence", ["e_tram_tap"])
	var a_duplicate: Dictionary = runtime.perform(CoreLoopTestSupport.A1, "present_evidence")
	_check((a_duplicate.get("result", {}) as Dictionary).get("reason", "") == "duplicate_failed_attempt" and a_policy.get_current_unit_failures() == 1, "the same failed statement/evidence pair is blocked without cost")
	_check(policy.get_current_unit_failures() == 1, "B1's budget was never touched by A")


func _test_help_escalates_result_failures_do_not() -> void:
	var runtime: RefCounted = _runtime("help")
	support.play_until(runtime, "briefing")
	support.gather_b1_evidence()
	support.examine("sbx_archive_lobby", "noticeboard")
	runtime.open_unit(CoreLoopTestSupport.B1)
	for wrong_set in [["e_door_log", "e_tram_tap", "e_back_door_sighting"], ["e_door_log", "e_route_note", "e_back_door_sighting"]]:
		support.clear_b(runtime, CoreLoopTestSupport.B1)
		support.fill_b(runtime, CoreLoopTestSupport.B1, wrong_set)
		runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check(runtime.get_unit(CoreLoopTestSupport.B1).get_policy().get_current_unit_failures() == 2, "two meaningful failures were counted")
	_check(runtime.get_run_help_result() == "independent", "failures alone never escalate the run help result (1.15B §23.4)")
	runtime.perform(CoreLoopTestSupport.B1, "reveal_next_hint")
	_check(runtime.get_run_help_result() == "guided", "a Guided hint makes the run Guided")
	_check(str(game_state.chapter_run.get("run_help_result", "")) == "guided", "the run help result is durable")


func _test_assistance_and_partner_resolution() -> void:
	var runtime: RefCounted = _runtime("partner")
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
	var policy: ResolutionPolicy = runtime.get_unit(CoreLoopTestSupport.B1).get_policy()
	for i in 3:
		support.clear_b(runtime, CoreLoopTestSupport.B1)
		support.fill_b(runtime, CoreLoopTestSupport.B1, wrong_sets[i])
		runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check(policy.requires_assistance() and runtime.get_run_help_result() == "independent", "three failures require assistance without escalating the run result by themselves")
	support.clear_b(runtime, CoreLoopTestSupport.B1)
	support.fill_b(runtime, CoreLoopTestSupport.B1, wrong_sets[3])
	var locked: Dictionary = runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check((locked.get("result", {}) as Dictionary).get("reason", "") == "submission_locked" and policy.get_current_unit_failures() == 3, "while assistance is pending nothing is evaluated or charged")
	runtime.perform(CoreLoopTestSupport.B1, "accept_assistance")
	_check(runtime.get_run_help_result() == "assisted", "accepted assistance makes the run Assisted")
	for i in [3, 4]:
		support.clear_b(runtime, CoreLoopTestSupport.B1)
		support.fill_b(runtime, CoreLoopTestSupport.B1, wrong_sets[i])
		runtime.perform(CoreLoopTestSupport.B1, "commit_theory")
	_check(policy.can_use_partner_resolution(), "two assisted failures offer partner resolution")
	var partner: Dictionary = runtime.perform(CoreLoopTestSupport.B1, "resolve_with_partner")
	_check(partner.get("consequences", []) == ["sbx_b1_resolved"] and runtime.get_phase_id() == "confrontation", "partner resolution prevents a hard lock and applies the same consequence")
	_check((game_state.chapter_run.get("applied_consequences", {}).get("sbx_b1_resolved", {}) as Dictionary).get("resolved_by", "") == "partner", "the consequence is attributed to the partner")
	_check(runtime.get_findings()[0].get("resolved_by", "") == "partner", "the finding carries partner attribution for the narrative summary")
	# The next unit starts with a fresh local budget.
	support.unlock_a1()
	runtime.open_unit(CoreLoopTestSupport.A1)
	var a_policy: ResolutionPolicy = runtime.get_unit(CoreLoopTestSupport.A1).get_policy()
	_check(a_policy.get_current_unit_phase() == "standard" and a_policy.get_current_unit_failures() == 0, "a new unit never inherits the previous unit's failures or assistance")


func _test_alternate_proof_path_accepted() -> void:
	var runtime: RefCounted = _runtime("alt")
	support.play_until(runtime, "briefing")
	support.examine("sbx_archive_lobby", "transit_map")
	support.talk("sbx_archive_lobby", "sbx_mara", "evening")
	support.talk("sbx_archive_lobby", "sbx_mara", "dinner_photo")
	support.examine("sbx_stacks_wing", "door_terminal")
	var result: Dictionary = support.solve_b(runtime, CoreLoopTestSupport.B1, CoreLoopTestSupport.B1_ALTERNATE_PATH)
	_check(result.get("consequences", []) == ["sbx_b1_resolved"], "the authored alternate path (harbor photo) resolves B1 too")


func _test_restart_is_a_fresh_run() -> void:
	var runtime: RefCounted = _runtime("restart")
	support.play_until(runtime, "a1")
	var first_run: String = runtime.get_run_id()
	runtime.restart_chapter()
	_check(runtime.get_run_id() != first_run and runtime.get_phase_id() == "briefing", "restart creates a new run in the briefing")
	_check(game_state.evidence_inventory.is_empty() and not game_state.get_flag("sbx_confrontation_unlocked"), "restart leaks no inventory or unlock")
	_check(runtime.get_session().get_resolved_claims().is_empty() and runtime.get_unit(CoreLoopTestSupport.B1) == null, "restart leaks no resolution or mechanic state")
	_check(runtime.get_findings().is_empty() and runtime.get_run_help_result() == "independent", "restart leaks no consequence or help result")
	_check(not case_manager.is_chapter_complete(CoreLoopTestSupport.CHAPTER_ID), "restart leaks no completion")
	var types: Array[String] = support.event_types(runtime)
	_check(types.has("chapter_abandoned") and types.has("chapter_restarted") and types.count("chapter_started") == 2, "the recording notes the abandoned run and the new one: %s" % [types])


func _test_recorder_is_observational() -> void:
	var runtime: RefCounted = _runtime("rec")
	support.play_until(runtime, "b1")
	var recorder: RefCounted = runtime.get_recorder()
	var types: Array[String] = support.event_types(runtime)
	var applied_at: int = types.find("consequence_applied")
	var checkpoint_after: int = types.find("checkpoint_saved", applied_at)
	_check(applied_at >= 0 and checkpoint_after > applied_at, "a consequence is recorded before the checkpoint that persisted it")
	var formal: Dictionary = {}
	for event in recorder.get_events():
		if str(event.get("type", "")) == "formal_commit_succeeded":
			formal = event.get("payload", {})
	_check(formal.get("unit_id", "") == CoreLoopTestSupport.B1 and formal.get("mechanic", "") == "clue_connection" and formal.get("run_id", "") == runtime.get_run_id(), "controller events carry run/unit/mechanic context: %s" % [formal])
	var snapshot_before: Dictionary = game_state.chapter_run.duplicate(true)
	recorder.stop()
	recorder.clear()
	_check(game_state.chapter_run == snapshot_before and runtime.get_phase_id() == "confrontation", "clearing the recording changes nothing about the run")
	# A FILE where the export directory should be: creating it must fail.
	var blocker := FileAccess.open("user://core_loop_runtime_test_blocker", FileAccess.WRITE)
	blocker.store_string("x")
	blocker.close()
	var export: Dictionary = runtime.export_recording("user://core_loop_runtime_test_blocker/recordings")
	_check(export.get("success", true) == false and runtime.get_phase_id() == "confrontation", "a failed export is reported and changes nothing: %s" % [export])
	DirAccess.remove_absolute("user://core_loop_runtime_test_blocker")
	support.unlock_a1()
	_check(support.solve_a(runtime).get("consequences", []) == ["sbx_a1_resolved"], "gameplay continues with the recorder stopped")


func _test_evaluation_summary_reads_production_log() -> void:
	var runtime: RefCounted = _runtime("summary")
	support.play_until(runtime, "claim")
	var export: Dictionary = runtime.get_recorder().to_export_dict()
	_check(export.get("prototype", "") == "core_loop" and int(export.get("schema_version", 0)) == 1 and int(export.get("event_schema_version", 0)) == 2, "the production log keeps the versioned recorder envelope")
	var summary: Dictionary = load("res://scripts/deduction/prototype_evaluation_summary.gd").summarize(export)
	var units: Array = []
	for run in summary.get("runs", []):
		units.append(run.get("unit_id", ""))
	_check(units == [CoreLoopTestSupport.B1, CoreLoopTestSupport.A1, CoreLoopTestSupport.B2, CoreLoopTestSupport.C1], "the existing summarizer yields one run per resolution unit: %s" % [units])
	var chapter: Dictionary = summary.get("chapter", {})
	_check(chapter.get("completed", false) and (chapter.get("consequences_applied", []) as Array).size() == 5, "the chapter block records completion and every consequence: %s" % [chapter])
	_check(chapter.get("run_help_result", "") == "independent" and int(chapter.get("checkpoints_failed", -1)) == 0, "the chapter block records the help result and checkpoint health")


func _test_debug_prototypes_stay_isolated() -> void:
	var runtime: RefCounted = _runtime("iso")
	support.play_until(runtime, "b1")
	var case_def: Dictionary = runtime.get_case_def()
	var debug_controller := PrototypeBController.new()
	debug_controller.start(case_def)
	for i in 2:
		for evidence_id in CoreLoopTestSupport.B2_PATH if i == 1 else CoreLoopTestSupport.B1_PATH:
			debug_controller.select_draft(i)
			debug_controller.select_evidence(evidence_id)
	debug_controller.commit_theory()
	_check(debug_controller.is_theory_accepted() and debug_controller.get_session() != runtime.get_session(), "a debug prototype still owns its own fresh session and batch commit")
	_check(not runtime.get_session().is_supported("ded_break_in_staged"), "a debug run never leaks into the production session")
	_check(debug_controller.get_policy().failures_escalate_run_result(), "debug prototypes keep their original policy semantics")
	_check(runtime.get_unit(CoreLoopTestSupport.B1).get_policy().failures_escalate_run_result() == false, "production units use the help-only policy")


func _test_flat_case_leaves_runtime_inactive() -> void:
	var runtime: RefCounted = _runtime("flat")
	save_manager.new_game("case_00_sandbox")
	runtime.reload_from_game_state()
	_check(not runtime.is_active() and game_state.chapter_run.is_empty(), "a case without a core_loop chapter never activates the runtime")
	_check(runtime.open_unit(CoreLoopTestSupport.B1).get("reason", "") == "no_active_run", "commands on an inactive runtime are refused")
