extends SceneTree
## Focused tests for PrototypeCController (Milestone 1.13 — see
## docs/prototype-c.md): fresh interaction state per run, fixed events
## pre-placed and locked, select/place/move/remove for movable events
## (including two events legally sharing a slot), exact submission gating
## (incomplete selections, identical-resubmission blocking), acceptance
## through the REAL TimelineEvaluator rather than exact authored-solution
## equality, optional constraints never blocking acceptance, hints, the final
## claim check (both answers), stats/abandonment, isolation from every other
## prototype's own state, and that this controller never touches a
## DeductionSession at all (see the class doc for why). Pure/autoload-free —
## hand-built fixture, no ContentDB needed. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_c_controller_test.gd

var controller_script: Variant
var lab_controller_script: Variant
var pa_controller_script: Variant
var pb_controller_script: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	controller_script = load("res://scripts/deduction/prototype_c_controller.gd")
	lab_controller_script = load("res://scripts/deduction/deduction_lab_controller.gd")
	pa_controller_script = load("res://scripts/deduction/prototype_a_controller.gd")
	pb_controller_script = load("res://scripts/deduction/prototype_b_controller.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeCController — focused tests ===")
	_test_start_creates_fresh_state()
	_test_start_rejects_malformed_or_missing_prototype_c()
	_test_other_prototype_sessions_remain_unchanged()
	_test_fixed_events_are_locked()
	_test_select_place_move_remove()
	_test_multiple_events_can_share_a_slot()
	_test_incomplete_timeline_cannot_submit()
	_test_invalid_timeline_rejected_and_retained()
	_test_identical_resubmission_blocked_until_a_move()
	_test_authored_and_alternate_placements_both_accepted()
	_test_optional_constraint_never_blocks_acceptance()
	_test_hints()
	_test_final_claim_wrong_then_correct()
	_test_acknowledge_claim_is_idempotent()
	_test_stats_and_abandonment()
	_test_no_deduction_session_dependency()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_controller():
	return controller_script.new()


func _started_controller():
	var controller = _new_controller()
	controller.start(fixtures.prototype_c_case())
	return controller


func _test_start_creates_fresh_state() -> void:
	var controller = _new_controller()
	_check(controller.get_case_def().is_empty(), "a fresh controller should have no case before start()")
	_check(controller.start(fixtures.prototype_c_case()), "start() should succeed for well-formed Prototype C content")
	_check(not controller.get_case_def().is_empty(), "start() should record the case_def")
	_check(not controller.is_completed(), "a fresh run should not be completed")
	_check(controller.is_fixed("t_fixed") and controller.get_placement("t_fixed") == "10:00", "the fixed event should be pre-placed at its own authored fixed_time, read from the timeline itself")
	_check(controller.get_placement("t_a") == "" and controller.get_placement("t_b") == "", "movable events should start unplaced")
	_check(controller.get_unplaced_count() == 2, "two movable events should be unplaced")
	_check(not controller.can_submit(), "an incomplete board cannot submit")
	_check(controller.get_hint_ladder().size() == 4, "the hint ladder should come straight from content")
	_check(not controller.is_accepted(), "a fresh run is not accepted")

	controller.place_event("t_a", "09:00")
	_check(controller.start(fixtures.prototype_c_case()), "start() should succeed again (Restart)")
	_check(controller.get_placement("t_a") == "", "Restart must discard all previous placements")
	_check(controller.get_unplaced_count() == 2, "Restart must return to a fresh, fully-unplaced board")


func _test_start_rejects_malformed_or_missing_prototype_c() -> void:
	var controller = _new_controller()
	_check(not controller.start({}), "start() should reject an empty dictionary")
	_check(not controller.start({"id": "no_prototype_c_here"}), "start() should reject a case with no prototype_c layer")
	var no_slots: Dictionary = fixtures.prototype_c_case()
	no_slots["prototype_c"]["time_slots"] = []
	_check(not controller.start(no_slots), "start() should reject a prototype_c layer with an empty time_slots array")
	_check(controller.get_case_def().is_empty(), "every rejected start() must leave no case behind")


func _test_other_prototype_sessions_remain_unchanged() -> void:
	var lab_controller = lab_controller_script.new()
	lab_controller.start_case(fixtures.base_case())
	var lab_session = lab_controller.get_session()
	lab_session.mark_evidence_opened("e_log")

	var pa_controller = pa_controller_script.new()
	pa_controller.start(fixtures.prototype_a_case())
	var pa_session = pa_controller.get_session()
	pa_session.mark_evidence_opened("e_a")

	var pb_controller = pb_controller_script.new()
	pb_controller.start(fixtures.prototype_b_case())
	pb_controller.select_evidence("e_a")

	var pc_controller = _started_controller()
	pc_controller.place_event("t_a", "09:00")
	pc_controller.place_event("t_b", "10:10")
	pc_controller.submit_timeline()

	_check(lab_controller.get_session() == lab_session, "starting/playing a Prototype C run must not touch the Lab's own controller/session objects")
	_check(lab_session.get_opened_evidence_ids() == ["e_log"], "the Lab's session content must be completely unaffected by a Prototype C run")
	_check(pa_controller.get_session() == pa_session and pa_session.get_opened_evidence_ids() == ["e_a"], "a PrototypeAController's own session must be completely unaffected by a Prototype C run")
	_check(pb_controller.get_selected_evidence_ids() == ["e_a"], "a PrototypeBController's own selection must be completely unaffected by a Prototype C run")


func _test_fixed_events_are_locked() -> void:
	var controller = _started_controller()
	_check(not controller.select_event("t_fixed"), "a fixed event can never be selected for placement")
	_check(not controller.place_event("t_fixed", "09:00"), "a fixed event can never be placed")
	_check(not controller.remove_event("t_fixed"), "a fixed event can never be removed")
	_check(controller.get_placement("t_fixed") == "10:00", "the fixed event's locked time must be unaffected by any of the above")


func _test_select_place_move_remove() -> void:
	var controller = _started_controller()
	_check(controller.select_event("t_a"), "selecting a movable event should succeed")
	_check(controller.get_selected_event_id() == "t_a", "the selection should be recorded")
	_check(controller.place_selected("09:00"), "placing the selected event into a valid slot should succeed")
	_check(controller.get_placement("t_a") == "09:00", "the event should now be placed at that slot")

	_check(controller.place_event("t_a", "09:15"), "placing an already-placed event at a DIFFERENT slot should succeed (a move)")
	_check(controller.get_placement("t_a") == "09:15", "the move should update the placement")
	_check(not controller.place_event("t_a", "09:15"), "placing at the SAME slot again must be a no-op")

	_check(controller.remove_event("t_a"), "removing a placed event should succeed")
	_check(controller.get_placement("t_a") == "", "removal should clear the placement")
	_check(not controller.remove_event("t_a"), "removing an already-unplaced event must fail")

	_check(controller.place_selected("09:00"), "selection persists across remove/place — place_selected should still target t_a and succeed")
	_check(controller.get_placement("t_a") == "09:00", "the re-placement should land t_a back on the board")
	_check(not controller.place_event("t_a", "not_a_slot"), "placing at a time not in time_slots must fail")

	var never_selected = _started_controller()
	_check(not never_selected.place_selected("09:00"), "place_selected on a controller where nothing was ever selected must fail")


## "If multiple events may legally share a start time, the UI must allow
## that" (docs/prototype-c.md) — the controller must never block this
## structurally; only TimelineEvaluator, at submission, can reject an actual
## conflict.
func _test_multiple_events_can_share_a_slot() -> void:
	var controller = _started_controller()
	_check(controller.place_event("t_a", "09:00"), "placing the first event should succeed")
	_check(controller.place_event("t_b", "09:00"), "placing a second event at the SAME slot must not be blocked by the controller")
	_check(controller.get_placement("t_a") == "09:00" and controller.get_placement("t_b") == "09:00", "both events should now share that slot")


func _test_incomplete_timeline_cannot_submit() -> void:
	var controller = _started_controller()
	_check(not controller.can_submit(), "an empty board cannot submit")
	controller.place_event("t_a", "09:00")
	_check(not controller.can_submit(), "a board missing one movable event still cannot submit")
	var result: Dictionary = controller.submit_timeline()
	_check(result.get("category") == "invalid_input", "submitting an incomplete board must be rejected as invalid_input, not sent to the evaluator")
	controller.place_event("t_b", "10:10")
	_check(controller.can_submit(), "a fully-placed board should now allow submission")


func _test_invalid_timeline_rejected_and_retained() -> void:
	var controller = _started_controller()
	controller.place_event("t_a", "10:10")  # outside t_a's own window
	controller.place_event("t_b", "10:10")
	var result: Dictionary = controller.submit_timeline()
	_check(result.get("accepted") == false, "a timeline violating a required constraint must not be accepted")
	_check((result.get("violated_required", []) as Array).has("c_a_window"), "the violated required fact should be named")
	_check(controller.get_placement("t_a") == "10:10" and controller.get_placement("t_b") == "10:10", "a rejected submission must retain every placement exactly, so the player can revise")
	_check(not controller.is_accepted(), "the run must not be marked accepted")


func _test_identical_resubmission_blocked_until_a_move() -> void:
	var controller = _started_controller()
	controller.place_event("t_a", "10:10")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()
	_check(not controller.can_resubmit(), "resubmitting the identical placement must be disabled until something changes")
	var blocked: Dictionary = controller.submit_timeline()
	_check(blocked.get("blocked_duplicate") == true, "a defense-in-depth resubmit call should report blocked_duplicate")

	controller.place_event("t_a", "09:00")
	_check(controller.can_resubmit(), "a real placement change must re-enable resubmission")
	var changed: Dictionary = controller.submit_timeline()
	_check(changed.get("blocked_duplicate") == false, "a genuinely new placement must not be treated as a duplicate")


## Correctness is judged by the REAL TimelineEvaluator against every required
## constraint — never by comparing to one exact authored sequence.
func _test_authored_and_alternate_placements_both_accepted() -> void:
	var first = _started_controller()
	first.place_event("t_a", "09:00")
	first.place_event("t_b", "10:10")
	var first_result: Dictionary = first.submit_timeline()
	_check(first_result.get("accepted") == true, "one valid placement should be accepted")

	var second = _started_controller()
	second.place_event("t_a", "09:15")
	second.place_event("t_b", "10:25")
	var second_result: Dictionary = second.submit_timeline()
	_check(second_result.get("accepted") == true, "a DIFFERENT valid placement must also be accepted — success is not exact-equality with one sequence")


func _test_optional_constraint_never_blocks_acceptance() -> void:
	var controller = _started_controller()
	controller.place_event("t_a", "09:00")
	controller.place_event("t_b", "10:10")
	var result: Dictionary = controller.submit_timeline()
	_check(result.get("accepted") == true, "an accepted timeline may still violate an OPTIONAL constraint (the disputed claim)")
	_check((result.get("violated_optional", []) as Array).has("c_lie"), "the violated optional constraint should still be reported (never counted as a failure)")


func _test_hints() -> void:
	var controller = _started_controller()
	_check(controller.get_hint_level() == 0, "no hint level should be revealed yet")
	var hint1: Dictionary = controller.reveal_next_hint()
	_check(hint1.get("available") == true and hint1.get("level") == 1, "the first reveal should return level 1")
	_check(controller.get_hint_level() == 1, "the controller should track its own hint level")
	for i in 3:
		controller.reveal_next_hint()
	var exhausted: Dictionary = controller.reveal_next_hint()
	_check(exhausted.get("exhausted") == true, "asking past the last level should report exhausted")
	_check(controller.get_hint_level() == 4, "the level should stay at the maximum once exhausted")


func _test_final_claim_wrong_then_correct() -> void:
	var controller = _started_controller()
	controller.place_event("t_a", "09:00")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()
	_check(controller.is_claim_phase(), "an accepted timeline should enter the claim phase")
	_check(controller.get_claim_statement_id() == "st_lie", "the claim id should come from the authored contradiction")

	var wrong: Dictionary = controller.answer_claim(false)  # "Fits the timeline"
	_check(wrong.get("correct") == false, "\"Fits the timeline\" must be wrong — the accepted placement never satisfies the disputed window")
	_check(wrong.get("resolved") == false, "a wrong answer must not resolve the claim")
	_check(controller.is_claim_phase(), "the claim phase must remain open after a wrong answer")
	_check(controller.get_placement("t_a") == "09:00" and controller.get_placement("t_b") == "10:10", "a wrong claim answer must preserve the accepted timeline exactly")

	var correct: Dictionary = controller.answer_claim(true)  # "Impossible"
	_check(correct.get("correct") == true, "\"Impossible\" must be correct")
	_check(correct.get("resolved") == true, "a correct answer must resolve the claim")
	_check(controller.is_claim_resolved(), "is_claim_resolved() should now be true")
	_check(controller.get_claim_attempts() == 2, "both attempts (wrong and correct) should be counted")
	_check(not controller.is_completed(), "resolving the claim alone must not complete the prototype — acknowledge_claim() does that")


func _test_acknowledge_claim_is_idempotent() -> void:
	var controller = _started_controller()
	var early: Dictionary = controller.acknowledge_claim()
	_check(early.get("prototype_completed") == false, "acknowledging before the claim is resolved must be a safe no-op")

	controller.place_event("t_a", "09:00")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()
	controller.answer_claim(true)
	var first: Dictionary = controller.acknowledge_claim()
	_check(first.get("prototype_completed") == true, "acknowledging a resolved claim should complete the prototype")
	_check(controller.is_completed(), "is_completed() should now be true")
	var second: Dictionary = controller.acknowledge_claim()
	_check(second.get("prototype_completed") == true, "acknowledging again on an already-completed run must stay a safe no-op, not an error")


func _test_stats_and_abandonment() -> void:
	var recorder: DeductionLabRecorder = load("res://scripts/deduction/deduction_lab_recorder.gd").new()
	var controller = _new_controller()
	controller.start(fixtures.prototype_c_case(), recorder)
	recorder.start("fx_pc_case", "timeline_reconstruction", "en")

	_check(controller.get_stats().get("submissions") == 0, "a fresh run should report zero submissions")
	controller.place_event("t_a", "10:10")  # wrong window
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()  # rejected
	controller.place_event("t_a", "09:00")  # fix it
	controller.submit_timeline()  # accepted
	controller.reveal_next_hint()
	var stats: Dictionary = controller.get_stats()
	_check(stats.get("submissions") == 2, "both the rejected and accepted submissions should count")
	_check(stats.get("failed") == 1, "exactly one submission should count as failed")
	_check(stats.get("moves") >= 3, "every placement/move/removal across the run should be counted")
	_check(stats.get("hints_used") == 1, "one hint reveal should be counted")
	_check(stats.get("facts_opened") == 0, "no fact was opened in this run")

	controller.answer_claim(false)
	_check(controller.get_stats().get("claim_attempts") == 1, "a claim attempt should be counted even when wrong")
	_check(controller.has_progress(), "sanity — there should be progress after all this")
	controller.abandon()
	_check(recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with real progress and no completion should record prototype_abandoned")

	var fresh_recorder: DeductionLabRecorder = load("res://scripts/deduction/deduction_lab_recorder.gd").new()
	var fresh_controller = _new_controller()
	fresh_controller.start(fixtures.prototype_c_case(), fresh_recorder)
	fresh_recorder.start("fx_pc_case", "timeline_reconstruction", "en")
	fresh_controller.abandon()
	_check(not fresh_recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with no progress at all must not record anything")


## Cheap but valuable structural guarantee: PrototypeCController is the one
## prototype controller that owns NO DeductionSession at all (see the class
## doc for why) — grading is entirely TimelineEvaluator's job. The class doc
## itself discusses DeductionSession by name (explaining the decision), so
## this checks for actual USE — a typed field or an instantiation — not the
## bare word.
func _test_no_deduction_session_dependency() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/deduction/prototype_c_controller.gd")
	for forbidden in ["DeductionSession.new(", ": DeductionSession", "get_session("]:
		_check(not source.contains(forbidden), "prototype_c_controller.gd must never use DeductionSession (found %s) — every check goes through TimelineEvaluator instead" % forbidden)
