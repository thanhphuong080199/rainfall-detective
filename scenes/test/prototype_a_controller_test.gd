extends SceneTree
## Focused tests for PrototypeAController (Milestone 1.11 — see
## docs/prototype-a.md): fresh session per run, isolation from a Deduction
## Lab session, statement/evidence navigation, one-evidence-only enforcement,
## required/optional/wrong-attempt classification through the REAL evaluator,
## idempotent resubmission, round/prototype completion, hints, and that no
## DeductionSession mutator is ever called directly. Pure/autoload-free —
## hand-built fixture, no ContentDB needed. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_a_controller_test.gd

var controller_script: Variant
var lab_controller_script: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	# Loaded via load() rather than referenced by class_name, matching every
	# other deduction test in this project (see deduction_cases_test.gd's own
	# header comment for the -s entry-script compile-order reason).
	controller_script = load("res://scripts/deduction/prototype_a_controller.gd")
	lab_controller_script = load("res://scripts/deduction/deduction_lab_controller.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeAController — focused tests ===")
	_test_start_creates_fresh_session()
	_test_start_rejects_malformed_or_missing_prototype_a()
	_test_lab_session_remains_unchanged()
	_test_statement_navigation()
	_test_evidence_open_and_select()
	_test_one_evidence_only_enforcement()
	_test_successful_required_refutation()
	_test_wrong_attempt_does_not_advance()
	_test_evaluator_category_mapping()
	_test_optional_innocent_lie_is_valid_but_not_required()
	_test_repeated_resolved_submission_is_idempotent()
	_test_two_required_contradictions_complete_the_prototype()
	_test_acknowledge_feedback_is_idempotent()
	_test_hints()
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
	controller.start(fixtures.prototype_a_case())
	return controller


func _test_start_creates_fresh_session() -> void:
	var controller = _new_controller()
	_check(controller.get_session() == null, "a fresh controller should have no session before start()")
	_check(controller.start(fixtures.prototype_a_case()), "start() should succeed for well-formed Prototype A content")
	_check(controller.get_session() != null, "start() should create a session")
	_check(controller.get_session().case_id == "fx_pa_case", "the session should carry the case's id")
	_check(not controller.is_completed(), "a fresh run should not be completed")
	_check(controller.get_round_index() == 0 and controller.get_round_count() == 2, "a fresh run should start at round 0 of 2")

	var first_session = controller.get_session()
	_check(controller.start(fixtures.prototype_a_case()), "start() should succeed again (Restart)")
	_check(controller.get_session() != first_session, "Restart must create a brand-new, isolated session object")
	_check(controller.get_session().get_resolved_claims().is_empty(), "Restart must not carry over any resolved claims")


func _test_start_rejects_malformed_or_missing_prototype_a() -> void:
	var controller = _new_controller()
	_check(not controller.start({}), "start() should reject an empty dictionary")
	_check(not controller.start({"id": "no_prototype_a_here"}), "start() should reject a case with no prototype_a layer")
	var no_rounds: Dictionary = fixtures.prototype_a_case()
	no_rounds["prototype_a"] = {"evidence_pool": [], "rounds": []}
	_check(not controller.start(no_rounds), "start() should reject a prototype_a layer with an empty rounds array")
	_check(controller.get_session() == null, "every rejected start() must leave no session behind")


func _test_lab_session_remains_unchanged() -> void:
	var lab_controller = lab_controller_script.new()
	lab_controller.start_case(fixtures.base_case())
	var lab_session = lab_controller.get_session()
	lab_session.mark_evidence_opened("e_log")

	var pa_controller = _started_controller()
	pa_controller.open_evidence("e_a")
	pa_controller.select_evidence("e_b")
	pa_controller.select_statement(1)
	pa_controller.present_evidence()

	_check(lab_controller.get_session() == lab_session, "starting/playing a Prototype A run must not touch the Lab's own controller/session objects")
	_check(lab_session.get_opened_evidence_ids() == ["e_log"], "the Lab's session content must be completely unaffected by a Prototype A run")
	_check(pa_controller.get_session() != lab_session, "PrototypeAController must own a session object distinct from the Lab's")


func _test_statement_navigation() -> void:
	var controller = _started_controller()
	_check(controller.get_statement_ids() == ["st_true", "st_required1"], "round 1 should list its authored statements in order")
	_check(controller.get_current_statement_id() == "st_true", "a fresh round should start on its first statement")
	_check(controller.get_statement_index() == 0, "the statement index should start at 0")

	_check(controller.next_statement(), "next_statement should succeed within range")
	_check(controller.get_current_statement_id() == "st_required1", "next_statement should advance to the second statement")
	_check(not controller.next_statement(), "next_statement past the end should fail")
	_check(controller.get_current_statement_id() == "st_required1", "a rejected next_statement must not change the current statement")

	_check(controller.previous_statement(), "previous_statement should succeed within range")
	_check(controller.get_current_statement_id() == "st_true", "previous_statement should move back")
	_check(not controller.previous_statement(), "previous_statement before the start should fail")

	_check(not controller.select_statement(5), "select_statement with an out-of-range index should fail")
	_check(controller.select_statement(1), "select_statement with a valid index should succeed")


func _test_evidence_open_and_select() -> void:
	var controller = _started_controller()
	_check(not controller.get_session().has_opened_evidence("e_a"), "evidence should start unopened")
	_check(controller.open_evidence("e_a"), "opening a pool evidence item should succeed")
	_check(controller.get_session().has_opened_evidence("e_a"), "open_evidence should mark it opened in the session")
	_check(not controller.open_evidence("not_in_pool"), "opening an evidence id outside the pool should fail")

	_check(controller.get_selected_evidence_id() == "", "nothing should be selected yet")
	_check(controller.select_evidence("e_b"), "selecting a pool evidence item should succeed")
	_check(controller.get_selected_evidence_id() == "e_b", "select_evidence should record the selection")
	_check(not controller.select_evidence("not_in_pool"), "selecting an evidence id outside the pool should fail")
	_check(controller.get_selected_evidence_id() == "e_b", "a rejected selection must not clear a valid one")

	controller.clear_selected_evidence()
	_check(controller.get_selected_evidence_id() == "", "clear_selected_evidence should clear the selection")


func _test_one_evidence_only_enforcement() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	_check(controller.get_selected_evidence_id() == "e_b", "selecting a second item must REPLACE the first — there is no multi-selection")

	controller.next_statement()  # st_required1
	controller.select_evidence("e_b")
	var result: Dictionary = controller.present_evidence()
	_check(result.get("category") == "valid_refutation", "sanity — e_b alone should refute st_required1")


func _test_successful_required_refutation() -> void:
	var controller = _started_controller()
	controller.next_statement()  # st_required1
	controller.select_evidence("e_b")
	var result: Dictionary = controller.present_evidence()
	_check(result.get("category") == "valid_refutation", "the correct single evidence item should validly refute the required statement")
	_check(result.get("outcome") == "required", "a resolved required refutation should be classified as \"required\"")
	_check(result.get("newly_resolved") == true, "the first successful submission should be newly_resolved")
	_check(result.get("round_ready") == true, "round 1 has exactly one required refutation, so it should be ready after this")
	_check(controller.get_selected_evidence_id() == "", "a submitted selection should be consumed")
	_check(controller.get_session().is_supported("st_required1") == false and controller.get_session().get_claim_status("st_required1") == "refuted", "the statement should resolve as refuted, not supported")


func _test_wrong_attempt_does_not_advance() -> void:
	var controller = _started_controller()
	controller.next_statement()  # st_required1
	controller.select_evidence("e_noise")
	var result: Dictionary = controller.present_evidence()
	_check(result.get("category") == "irrelevant_evidence", "unrelated evidence should be classified as irrelevant")
	_check(result.get("newly_resolved") == false, "a wrong attempt must never resolve the claim")
	_check(result.get("round_ready") == false, "a wrong attempt must never make the round ready to advance")
	_check(controller.get_session().get_claim_status("st_required1") == "", "a wrong attempt must leave the claim unresolved")


func _test_evaluator_category_mapping() -> void:
	var controller = _started_controller()
	controller.next_statement()  # st_required1

	controller.select_evidence("e_a")  # relevant to a DIFFERENT claim (st_true), irrelevant here
	_check(controller.present_evidence().get("category") == "irrelevant_evidence", "evidence relevant to another statement should be irrelevant here")

	controller.previous_statement()  # st_true
	controller.select_evidence("e_a")
	var true_result: Dictionary = controller.present_evidence()
	_check(true_result.get("category") == "compatible_not_proof", "refuting a TRUE statement must never succeed, even with its own supporting evidence")
	_check(controller.get_session().get_claim_status("st_true") == "", "a true statement must never resolve as refuted")

	controller.present_evidence()
	_check(true, "sanity — presenting with nothing selected should not crash")


func _test_optional_innocent_lie_is_valid_but_not_required() -> void:
	var controller = _started_controller()
	controller.next_statement()
	controller.select_evidence("e_b")
	controller.present_evidence()
	controller.acknowledge_feedback()  # advance to round 2

	_check(controller.get_current_round().get("id") == "round_2", "sanity — should now be in round 2")
	controller.select_evidence("e_d")  # st_optional is statement index 0 in round 2
	var result: Dictionary = controller.present_evidence()
	_check(result.get("category") == "valid_refutation", "the innocent lie must be logically valid, never rejected as wrong")
	_check(result.get("outcome") == "optional", "the innocent lie's outcome must be classified as optional, never required")
	_check(result.get("round_ready") == false, "resolving only the optional contradiction must not complete round 2 (the required one is still open)")
	_check(controller.get_resolved_optional_ids() == ["st_optional"], "the resolved optional contradiction should be tracked")


func _test_repeated_resolved_submission_is_idempotent() -> void:
	var controller = _started_controller()
	controller.next_statement()
	controller.select_evidence("e_b")
	var first: Dictionary = controller.present_evidence()
	_check(first.get("newly_resolved") == true, "sanity — the first submission should resolve the claim")
	var attempts_before: int = controller.get_session().get_attempts().size()

	controller.select_evidence("e_b")
	var second: Dictionary = controller.present_evidence()
	_check(second.get("category") == "valid_refutation", "resubmitting the same valid evidence should still classify as valid")
	_check(second.get("already_resolved") == true, "a resubmission on an already-resolved claim must be flagged as such")
	_check(second.get("newly_resolved") == false, "a resubmission must never be newly_resolved a second time")
	_check(controller.get_session().get_attempts().size() == attempts_before, "resubmitting an already-resolved claim must not append a new attempt to the session log (no session mutation)")


func _test_two_required_contradictions_complete_the_prototype() -> void:
	var controller = _started_controller()
	controller.next_statement()
	controller.select_evidence("e_b")
	controller.present_evidence()
	var advance1: Dictionary = controller.acknowledge_feedback()
	_check(advance1.get("round_completed") == true and advance1.get("prototype_completed") == false, "completing round 1 should advance, not finish, the prototype")
	_check(controller.get_round_index() == 1, "acknowledge_feedback should move to round 2")
	_check(not controller.is_completed(), "the prototype must not be complete after only one required contradiction")

	controller.select_statement(1)  # st_required2
	controller.select_evidence("e_c")
	var result: Dictionary = controller.present_evidence()
	_check(result.get("outcome") == "required", "the second required contradiction should also classify as required")
	_check(result.get("round_ready") == true, "round 2's required refutation is now resolved")
	var advance2: Dictionary = controller.acknowledge_feedback()
	_check(advance2.get("round_completed") == true and advance2.get("prototype_completed") == true, "completing the SECOND round's required contradiction should complete the whole prototype")
	_check(controller.is_completed(), "is_completed() should now be true")


func _test_acknowledge_feedback_is_idempotent() -> void:
	var controller = _started_controller()
	var before: Dictionary = controller.acknowledge_feedback()
	_check(before.get("round_completed") == false, "acknowledge_feedback with nothing resolved yet must be a safe no-op")
	_check(controller.get_round_index() == 0, "a no-op acknowledge must not change the round")

	controller.next_statement()
	controller.select_evidence("e_b")
	controller.present_evidence()
	controller.acknowledge_feedback()
	_check(controller.get_round_index() == 1, "sanity — should have advanced to round 2")
	var repeat: Dictionary = controller.acknowledge_feedback()
	_check(repeat.get("round_completed") == false, "calling acknowledge_feedback again without new progress must not advance a second time")
	_check(controller.get_round_index() == 1, "a repeated acknowledge must not skip ahead")


func _test_hints() -> void:
	var controller = _started_controller()
	_check(controller.get_hint_ladder("st_true").is_empty(), "a true statement (no required refutation) should have no hint ladder")
	_check(controller.get_hint_level("st_required1") == 0, "no hint level should be revealed yet")

	var hint1: Dictionary = controller.reveal_next_hint("st_required1")
	_check(hint1.get("available") == true and hint1.get("level") == 1, "the first reveal should return level 1")
	_check(controller.get_hint_level("st_required1") == 1, "the controller should track the revealed level")

	for i in 3:
		controller.reveal_next_hint("st_required1")
	var exhausted: Dictionary = controller.reveal_next_hint("st_required1")
	_check(exhausted.get("exhausted") == true, "asking past the last level should report exhausted")
	_check(controller.get_hint_level("st_required1") == 4, "the level should stay at the maximum once exhausted")

	var none: Dictionary = controller.reveal_next_hint("st_true")
	_check(none.get("available") == false, "a statement with no ladder should report unavailable")


func _test_stats_and_abandonment() -> void:
	var recorded_events: Array[Dictionary] = []
	var recorder: DeductionLabRecorder = load("res://scripts/deduction/deduction_lab_recorder.gd").new()
	var controller = _new_controller()
	controller.start(fixtures.prototype_a_case(), recorder)
	recorder.start("fx_pa_case", "statement_contradiction", "en")

	_check(controller.get_stats().get("submissions") == 0, "a fresh run should report zero submissions")
	controller.next_statement()
	controller.select_evidence("e_noise")
	controller.present_evidence()  # wrong
	controller.select_evidence("e_b")
	controller.present_evidence()  # correct
	controller.reveal_next_hint("st_required1")
	var stats: Dictionary = controller.get_stats()
	_check(stats.get("submissions") == 2, "both the wrong and the correct submission should count")
	_check(stats.get("incorrect") == 1, "exactly one submission should count as incorrect")
	_check(stats.get("hints_used") == 1, "one hint reveal should be counted")

	_check(not controller.has_progress() == false, "sanity — there should be progress after all this")
	controller.abandon()
	_check(recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with real progress and no completion should record prototype_abandoned")

	var fresh_recorder: DeductionLabRecorder = load("res://scripts/deduction/deduction_lab_recorder.gd").new()
	var fresh_controller = _new_controller()
	fresh_controller.start(fixtures.prototype_a_case(), fresh_recorder)
	fresh_recorder.start("fx_pa_case", "statement_contradiction", "en")
	fresh_controller.abandon()
	_check(not fresh_recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with no progress at all must not record anything")


## Cheap but valuable structural guarantee: the controller must resolve
## claims, record attempts and advance hints ONLY through DeductionEvaluator
## (which itself calls these), never by calling these DeductionSession
## mutators directly — see docs/deduction-system.md's "Called by
## DeductionEvaluator only" section on DeductionSession itself.
func _test_no_direct_session_mutation() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/deduction/prototype_a_controller.gd")
	for forbidden in ["_session.resolve_claim(", "_session.record_attempt(", "_session.advance_hint(", "_session.mark_solved("]:
		_check(not source.contains(forbidden), "prototype_a_controller.gd must never call DeductionSession.%s directly — only DeductionEvaluator may" % forbidden.trim_suffix("("))
