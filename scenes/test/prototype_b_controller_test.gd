extends SceneTree
## Focused tests for PrototypeBController (Milestone 1.12 — see
## docs/prototype-b.md): fresh session per run, isolation from a Deduction
## Lab or Prototype A session, clue selection/removal/replacement, exact
## slot-capacity enforcement, duplicate prevention, order-independence,
## wrong/correct classification through the REAL evaluator, idempotent
## resubmission, round/prototype completion, hints via the REAL base hint
## API, stats/abandonment, and that no DeductionSession mutator is ever
## called directly. Pure/autoload-free — hand-built fixture, no ContentDB
## needed. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_b_controller_test.gd

var controller_script: Variant
var lab_controller_script: Variant
var pa_controller_script: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	controller_script = load("res://scripts/deduction/prototype_b_controller.gd")
	lab_controller_script = load("res://scripts/deduction/deduction_lab_controller.gd")
	pa_controller_script = load("res://scripts/deduction/prototype_a_controller.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeBController — focused tests ===")
	_test_start_creates_fresh_session()
	_test_start_rejects_malformed_or_missing_prototype_b()
	_test_lab_and_prototype_a_sessions_remain_unchanged()
	_test_evidence_open_and_select()
	_test_slot_capacity_enforcement()
	_test_duplicate_selection_rejected()
	_test_remove_and_replace()
	_test_incomplete_selection_cannot_submit()
	_test_selection_order_does_not_matter()
	_test_successful_connection()
	_test_wrong_attempt_preserves_selection()
	_test_evaluator_category_mapping()
	_test_repeated_resolved_submission_is_idempotent()
	_test_two_rounds_complete_the_prototype_with_different_slot_counts()
	_test_acknowledge_result_is_idempotent()
	_test_hints_use_real_base_api()
	_test_stats_and_abandonment()
	_test_no_direct_session_mutation()

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
	controller.start(fixtures.prototype_b_case())
	return controller


func _test_start_creates_fresh_session() -> void:
	var controller = _new_controller()
	_check(controller.get_session() == null, "a fresh controller should have no session before start()")
	_check(controller.start(fixtures.prototype_b_case()), "start() should succeed for well-formed Prototype B content")
	_check(controller.get_session() != null, "start() should create a session")
	_check(controller.get_session().case_id == "fx_pb_case", "the session should carry the case's id")
	_check(not controller.is_completed(), "a fresh run should not be completed")
	_check(controller.get_round_index() == 0 and controller.get_round_count() == 2, "a fresh run should start at round 0 of 2")
	_check(controller.get_slot_count() == 3, "round 1's slot_count should come from content (3), never a hardcoded constant")

	var first_session = controller.get_session()
	_check(controller.start(fixtures.prototype_b_case()), "start() should succeed again (Restart)")
	_check(controller.get_session() != first_session, "Restart must create a brand-new, isolated session object")
	_check(controller.get_session().get_resolved_claims().is_empty(), "Restart must not carry over any resolved claims")
	_check(controller.get_selected_evidence_ids().is_empty(), "Restart must clear any placed clues")


func _test_start_rejects_malformed_or_missing_prototype_b() -> void:
	var controller = _new_controller()
	_check(not controller.start({}), "start() should reject an empty dictionary")
	_check(not controller.start({"id": "no_prototype_b_here"}), "start() should reject a case with no prototype_b layer")
	var no_rounds: Dictionary = fixtures.prototype_b_case()
	no_rounds["prototype_b"] = {"evidence_pool": [], "rounds": []}
	_check(not controller.start(no_rounds), "start() should reject a prototype_b layer with an empty rounds array")
	_check(controller.get_session() == null, "every rejected start() must leave no session behind")


func _test_lab_and_prototype_a_sessions_remain_unchanged() -> void:
	var lab_controller = lab_controller_script.new()
	lab_controller.start_case(fixtures.base_case())
	var lab_session = lab_controller.get_session()
	lab_session.mark_evidence_opened("e_log")

	var pa_controller = pa_controller_script.new()
	pa_controller.start(fixtures.prototype_a_case())
	var pa_session = pa_controller.get_session()
	pa_session.mark_evidence_opened("e_a")

	var pb_controller = _started_controller()
	pb_controller.open_evidence("e_a")
	pb_controller.select_evidence("e_a")
	pb_controller.select_evidence("e_b")
	pb_controller.select_evidence("e_c")
	pb_controller.submit_connection()

	_check(lab_controller.get_session() == lab_session, "starting/playing a Prototype B run must not touch the Lab's own controller/session objects")
	_check(lab_session.get_opened_evidence_ids() == ["e_log"], "the Lab's session content must be completely unaffected by a Prototype B run")
	_check(pa_controller.get_session() == pa_session and pa_session.get_opened_evidence_ids() == ["e_a"], "a PrototypeAController's own session must be completely unaffected by a Prototype B run")
	_check(pb_controller.get_session() != lab_session and pb_controller.get_session() != pa_session, "PrototypeBController must own a session object distinct from both the Lab's and Prototype A's")


func _test_evidence_open_and_select() -> void:
	var controller = _started_controller()
	_check(not controller.get_session().has_opened_evidence("e_a"), "evidence should start unopened")
	_check(controller.open_evidence("e_a"), "opening a pool evidence item should succeed")
	_check(controller.get_session().has_opened_evidence("e_a"), "open_evidence should mark it opened in the session")
	_check(not controller.open_evidence("not_in_pool"), "opening an evidence id outside the pool should fail")

	_check(controller.get_selected_evidence_ids().is_empty(), "nothing should be selected yet")
	_check(controller.select_evidence("e_a"), "selecting a pool evidence item should succeed")
	_check(controller.get_selected_evidence_ids() == ["e_a"], "select_evidence should record the placement")
	_check(not controller.select_evidence("not_in_pool"), "selecting an evidence id outside the pool should fail")
	_check(controller.get_selected_evidence_ids() == ["e_a"], "a rejected selection must not disturb a valid one")


func _test_slot_capacity_enforcement() -> void:
	var controller = _started_controller()
	_check(controller.get_slot_count() == 3, "sanity — round 1 has 3 slots")
	_check(controller.has_room(), "a fresh round should have room")
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_c")
	_check(controller.get_selected_evidence_ids().size() == 3, "three selections should fill all three slots")
	_check(not controller.has_room(), "a full round should report no room")
	_check(not controller.select_evidence("e_d"), "selecting a 4th item once the round is full must be rejected — over-capacity selection is blocked before the evaluator ever sees it")
	_check(controller.get_selected_evidence_ids().size() == 3, "a rejected over-capacity selection must not change the placed set")


func _test_duplicate_selection_rejected() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	_check(not controller.select_evidence("e_a"), "selecting the same evidence id twice must be rejected — duplicate selection is impossible")
	_check(controller.get_selected_evidence_ids() == ["e_a"], "a rejected duplicate must not change the placed set")


func _test_remove_and_replace() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	_check(controller.remove_evidence("e_a"), "removing a placed clue should succeed")
	_check(controller.get_selected_evidence_ids() == ["e_b"], "remove_evidence must only remove the named clue, leaving the rest untouched")
	_check(not controller.remove_evidence("e_noise"), "removing an unplaced clue should fail")

	controller.select_evidence("e_a")
	controller.select_evidence("e_c")
	_check(controller.get_selected_evidence_ids().size() == 3, "sanity — all three slots filled again")
	_check(controller.replace_evidence("e_a", "e_d"), "replace_evidence should succeed for a placed clue and an unplaced pool item")
	var after_replace: Array = controller.get_selected_evidence_ids()
	_check(after_replace.has("e_d") and not after_replace.has("e_a") and after_replace.size() == 3, "replace_evidence must swap exactly one clue, keeping the other two and the slot count unchanged")
	_check(not controller.replace_evidence("e_a", "e_noise"), "replace_evidence must fail when the OLD clue isn't actually placed")
	_check(not controller.replace_evidence("e_b", "e_d"), "replace_evidence must fail when the NEW clue is already placed")


func _test_incomplete_selection_cannot_submit() -> void:
	var controller = _started_controller()
	_check(not controller.can_submit(), "an empty selection cannot submit")
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	_check(not controller.can_submit(), "a selection short of slot_count cannot submit")
	var result: Dictionary = controller.submit_connection()
	_check(result.get("category") == "invalid_input", "submitting an incomplete selection must be rejected as invalid_input, not sent to the evaluator")
	_check(controller.get_session().get_attempts().is_empty(), "a rejected incomplete submission must not touch the session's attempt log")
	controller.select_evidence("e_c")
	_check(controller.can_submit(), "a full selection should now allow submission")


func _test_selection_order_does_not_matter() -> void:
	var forward = _started_controller()
	forward.select_evidence("e_a")
	forward.select_evidence("e_b")
	forward.select_evidence("e_c")
	var forward_result: Dictionary = forward.submit_connection()

	var backward = _started_controller()
	backward.select_evidence("e_c")
	backward.select_evidence("e_b")
	backward.select_evidence("e_a")
	var backward_result: Dictionary = backward.submit_connection()

	_check(forward_result.get("category") == "valid_support" and backward_result.get("category") == "valid_support", "sanity — both selection orders should resolve the same target")
	_check(forward_result.get("category") == backward_result.get("category"), "the placement ORDER of clues into slots must never affect correctness")


func _test_successful_connection() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_c")
	var result: Dictionary = controller.submit_connection()
	_check(result.get("category") == "valid_support", "the correct three clues should validly connect to the target deduction")
	_check(result.get("newly_resolved") == true, "the first successful submission should be newly_resolved")
	_check(result.get("round_ready") == true, "round 1 should be ready to advance once its target is resolved")
	_check(controller.get_session().is_supported("ded_first"), "the deduction should now be supported in the session — unlocked through the real commit path")


func _test_wrong_attempt_preserves_selection() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_noise")
	var result: Dictionary = controller.submit_connection()
	_check(result.get("category") == "irrelevant_evidence", "a selection including an irrelevant item should be classified as irrelevant")
	_check(result.get("newly_resolved") == false, "a wrong attempt must never resolve the claim")
	_check(result.get("round_ready") == false, "a wrong attempt must never make the round ready to advance")
	_check(controller.get_selected_evidence_ids() == ["e_a", "e_b", "e_noise"], "after a failed attempt the placed clues must remain exactly as they were, so the player can reconsider and replace just one")
	_check(controller.get_session().get_claim_status("ded_first") == "", "a wrong attempt must leave the claim unresolved")


func _test_evaluator_category_mapping() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_d")  # round 2's items, not part of ded_first's proof at all
	controller.select_evidence("e_e")
	controller.select_evidence("e_a")
	var result: Dictionary = controller.submit_connection()
	_check(result.get("category") == "irrelevant_evidence", "e_d/e_e (round 2's items) are irrelevant to round 1's target, so a full-but-wrong selection should read as irrelevant_evidence")


func _test_repeated_resolved_submission_is_idempotent() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_c")
	var first: Dictionary = controller.submit_connection()
	_check(first.get("newly_resolved") == true, "sanity — the first submission should resolve the claim")
	var attempts_before: int = controller.get_session().get_attempts().size()

	var second: Dictionary = controller.submit_connection()
	_check(second.get("category") == "valid_support", "resubmitting the same valid selection should still classify as valid")
	_check(second.get("already_resolved") == true, "a resubmission on an already-resolved target must be flagged as such")
	_check(second.get("newly_resolved") == false, "a resubmission must never be newly_resolved a second time")
	_check(controller.get_session().get_attempts().size() == attempts_before, "resubmitting an already-resolved target must not append a new attempt to the session log (no session mutation)")


func _test_two_rounds_complete_the_prototype_with_different_slot_counts() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_c")
	controller.submit_connection()
	var advance1: Dictionary = controller.acknowledge_result()
	_check(advance1.get("round_completed") == true and advance1.get("prototype_completed") == false, "completing round 1 should advance, not finish, the prototype")
	_check(controller.get_round_index() == 1, "acknowledge_result should move to round 2")
	_check(controller.get_selected_evidence_ids().is_empty(), "advancing rounds must clear the placed clues for a fresh set of slots")
	_check(controller.get_slot_count() == 2, "round 2's slot_count (2) should differ from round 1's (3), read from content each time")
	_check(not controller.is_completed(), "the prototype must not be complete after only one round")

	controller.select_evidence("e_d")
	controller.select_evidence("e_e")
	var result: Dictionary = controller.submit_connection()
	_check(result.get("round_ready") == true, "round 2's target is now resolved")
	var advance2: Dictionary = controller.acknowledge_result()
	_check(advance2.get("round_completed") == true and advance2.get("prototype_completed") == true, "completing the SECOND round should complete the whole prototype")
	_check(controller.is_completed(), "is_completed() should now be true")


func _test_acknowledge_result_is_idempotent() -> void:
	var controller = _started_controller()
	var before: Dictionary = controller.acknowledge_result()
	_check(before.get("round_completed") == false, "acknowledge_result with nothing resolved yet must be a safe no-op")
	_check(controller.get_round_index() == 0, "a no-op acknowledge must not change the round")

	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_c")
	controller.submit_connection()
	controller.acknowledge_result()
	_check(controller.get_round_index() == 1, "sanity — should have advanced to round 2")
	var repeat: Dictionary = controller.acknowledge_result()
	_check(repeat.get("round_completed") == false, "calling acknowledge_result again without new progress must not advance a second time")
	_check(controller.get_round_index() == 1, "a repeated acknowledge must not skip ahead")


## Prototype B reuses the REAL base hint contract (unlike Prototype A) — see
## docs/prototype-b.md, "Hints".
func _test_hints_use_real_base_api() -> void:
	var controller = _started_controller()
	_check(controller.get_hint_level() == 0, "no hint level should be revealed yet")

	var hint1: Dictionary = controller.reveal_next_hint()
	_check(hint1.get("available") == true and hint1.get("level") == 1, "the first reveal should return level 1")
	_check(controller.get_hint_level() == 1, "the controller should read the level straight from the session, never a private copy")
	_check(controller.get_session().get_hint_level("ded_first") == 1, "the revealed level must actually live on DeductionSession — no Prototype-B-owned hint state")

	for i in 3:
		controller.reveal_next_hint()
	var exhausted: Dictionary = controller.reveal_next_hint()
	_check(exhausted.get("exhausted") == true, "asking past the last level should report exhausted")
	_check(controller.get_hint_level() == 4, "the level should stay at the maximum once exhausted")


func _test_stats_and_abandonment() -> void:
	var recorder: DeductionLabRecorder = load("res://scripts/deduction/deduction_lab_recorder.gd").new()
	var controller = _new_controller()
	controller.start(fixtures.prototype_b_case(), recorder)
	recorder.start("fx_pb_case", "clue_connection", "en")

	_check(controller.get_stats().get("attempts") == 0, "a fresh run should report zero attempts")
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_noise")
	controller.submit_connection()  # wrong
	controller.remove_evidence("e_noise")
	controller.select_evidence("e_c")
	controller.submit_connection()  # correct
	controller.reveal_next_hint()
	var stats: Dictionary = controller.get_stats()
	_check(stats.get("attempts") == 2, "both the wrong and the correct submission should count")
	_check(stats.get("failed") == 1, "exactly one submission should count as failed")
	_check(stats.get("opened") == 0, "no evidence was opened in this run")
	_check(stats.get("hints_used") == 1, "one hint reveal should be counted, read from the session")

	_check(controller.has_progress(), "sanity — there should be progress after all this")
	controller.abandon()
	_check(recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with real progress and no completion should record prototype_abandoned")

	var fresh_recorder: DeductionLabRecorder = load("res://scripts/deduction/deduction_lab_recorder.gd").new()
	var fresh_controller = _new_controller()
	fresh_controller.start(fixtures.prototype_b_case(), fresh_recorder)
	fresh_recorder.start("fx_pb_case", "clue_connection", "en")
	fresh_controller.abandon()
	_check(not fresh_recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with no progress at all must not record anything")


## Cheap but valuable structural guarantee: the controller must resolve
## claims, record attempts and advance hints ONLY through DeductionEvaluator
## (which itself calls these), never by calling these DeductionSession
## mutators directly — see docs/deduction-system.md's "Called by
## DeductionEvaluator only" section on DeductionSession itself.
func _test_no_direct_session_mutation() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/deduction/prototype_b_controller.gd")
	for forbidden in ["_session.resolve_claim(", "_session.record_attempt(", "_session.advance_hint(", "_session.mark_solved("]:
		_check(not source.contains(forbidden), "prototype_b_controller.gd must never call DeductionSession.%s directly — only DeductionEvaluator may" % forbidden.trim_suffix("("))
