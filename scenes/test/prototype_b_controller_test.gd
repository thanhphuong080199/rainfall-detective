extends SceneTree
## Focused tests for PrototypeBController (Milestone 1.12 — see
## docs/prototype-b.md; draft/batch model since Milestone 1.14 — see
## docs/resolution-policy.md): fresh session per run, isolation from a
## Deduction Lab or Prototype A session, two independent unverified drafts,
## clue placement/removal/replacement per draft, exact slot-capacity
## enforcement, duplicate prevention, that editing/saving/switching drafts
## never touches the evaluator, the atomic batch commit (one invalid draft
## commits neither; both valid commit both through the REAL evaluator;
## selection order and alternate proof paths accepted), non-oracular
## feedback levels, identical-theory blocking, the assistance/partner flow,
## hints via the REAL base hint API, stats/abandonment/restart telemetry, and
## that no DeductionSession mutator is ever called directly. Pure/autoload-
## free — hand-built fixture, no ContentDB needed. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_b_controller_test.gd

## Five DISTINCT invalid question-2 drafts (question 1 stays correct) — enough
## to exhaust the standard (3) and assisted (2) budgets without repeating a
## failed theory.
const WRONG_SECOND_DRAFTS := [["e_d", "e_noise"], ["e_e", "e_noise"], ["e_a", "e_d"], ["e_a", "e_e"], ["e_b", "e_d"]]

var controller_script: Variant
var lab_controller_script: Variant
var pa_controller_script: Variant
var recorder_script: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	controller_script = load("res://scripts/deduction/prototype_b_controller.gd")
	lab_controller_script = load("res://scripts/deduction/deduction_lab_controller.gd")
	pa_controller_script = load("res://scripts/deduction/prototype_a_controller.gd")
	recorder_script = load("res://scripts/deduction/deduction_lab_recorder.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeBController — focused tests ===")
	_test_start_creates_fresh_session()
	_test_start_rejects_malformed_or_missing_prototype_b()
	_test_lab_and_prototype_a_sessions_remain_unchanged()
	_test_evidence_open_and_place_in_active_draft()
	_test_slot_capacity_enforcement_per_draft()
	_test_duplicate_selection_rejected()
	_test_remove_and_replace()
	_test_two_independent_drafts()
	_test_draft_editing_saving_and_switching_never_evaluate()
	_test_commit_requires_every_draft_complete()
	_test_one_correct_one_incorrect_commits_neither()
	_test_second_failure_names_only_an_affected_question()
	_test_identical_failed_theory_is_blocked()
	_test_duplicate_theory_telemetry_is_observable_and_inert()
	_test_selection_order_does_not_matter()
	_test_alternate_proof_path_is_accepted()
	_test_successful_batch_commits_both_through_evaluator()
	_test_third_failure_requires_assistance()
	_test_assistance_points_at_an_invalid_draft_without_inserting_clues()
	_test_partner_batch_resolution_uses_real_evaluator()
	_test_partner_resolution_unavailable_before_threshold()
	_test_hints_use_real_base_api_and_raise_tier()
	_test_acknowledge_result_completes_only_after_acceptance()
	_test_stats_and_abandonment()
	_test_restart_is_recorded_as_a_new_run()
	_test_no_direct_session_mutation()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_controller():
	return controller_script.new()


func _started_controller(recorder = null):
	var controller = _new_controller()
	controller.start(fixtures.prototype_b_case(), recorder)
	return controller


func _new_recorder():
	var recorder = recorder_script.new()
	recorder.start("fx_pb_case", "clue_connection", "en")
	return recorder


## Replaces draft `index`'s content with exactly `ids`, through the public API.
func _fill_draft(controller, index: int, ids: Array) -> void:
	controller.select_draft(index)
	for existing in controller.get_selected_evidence_ids():
		controller.remove_evidence(existing)
	for evidence_id in ids:
		controller.select_evidence(evidence_id)


func _fill_correct_first(controller) -> void:
	_fill_draft(controller, 0, ["e_a", "e_b", "e_c"])


func _fail_theories(controller, from_index: int, count: int) -> Dictionary:
	var last: Dictionary = {}
	for i in range(from_index, from_index + count):
		_fill_draft(controller, 1, WRONG_SECOND_DRAFTS[i])
		last = controller.commit_theory()
	return last


func _test_start_creates_fresh_session() -> void:
	var controller = _new_controller()
	_check(controller.get_session() == null and controller.get_policy() == null, "a fresh controller should have no session/policy before start()")
	_check(controller.start(fixtures.prototype_b_case()), "start() should succeed for well-formed Prototype B content")
	_check(controller.get_session() != null and controller.get_session().case_id == "fx_pb_case", "start() should create a session carrying the case id")
	_check(controller.get_draft_count() == 2 and controller.get_active_draft_index() == 0, "every investigation question should be a draft, starting on the first")
	_check(controller.get_slot_count(0) == 3 and controller.get_slot_count(1) == 2, "slot counts come from content per question (3 and 2), never a hardcoded constant")
	_check(controller.get_selected_evidence_ids(0).is_empty() and controller.get_selected_evidence_ids(1).is_empty(), "both drafts should start empty")
	_check(not controller.is_completed() and not controller.is_theory_accepted(), "a fresh run is neither accepted nor completed")
	_check(controller.get_policy().get_run_resolution_result() == "independent", "a fresh run starts Independent")

	_fill_correct_first(controller)
	var first_session = controller.get_session()
	_check(controller.start(fixtures.prototype_b_case()), "start() should succeed again (Restart)")
	_check(controller.get_session() != first_session, "Restart must create a brand-new, isolated session object")
	_check(controller.get_selected_evidence_ids(0).is_empty(), "Restart must clear every draft")


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
	_fill_correct_first(pb_controller)
	_fill_draft(pb_controller, 1, ["e_d", "e_e"])
	pb_controller.commit_theory()

	_check(lab_controller.get_session() == lab_session and lab_session.get_opened_evidence_ids() == ["e_log"], "a Prototype B run must leave the Lab's session untouched")
	_check(pa_controller.get_session() == pa_session and pa_session.get_opened_evidence_ids() == ["e_a"], "a Prototype B run must leave Prototype A's session untouched")
	_check(pb_controller.get_session() != lab_session and pb_controller.get_session() != pa_session, "PrototypeBController must own its own session object")


func _test_evidence_open_and_place_in_active_draft() -> void:
	var controller = _started_controller()
	_check(controller.open_evidence("e_a") and controller.get_session().has_opened_evidence("e_a"), "opening a pool item should mark it opened")
	_check(not controller.open_evidence("not_in_pool"), "opening an id outside the pool should fail")
	_check(controller.select_evidence("e_a") and controller.get_selected_evidence_ids() == ["e_a"], "placing should fill the active draft")
	_check(controller.is_selected("e_a"), "is_selected() reports the active draft")
	_check(not controller.select_evidence("not_in_pool"), "placing an id outside the pool should fail")
	controller.select_draft(1)
	_check(not controller.is_selected("e_a") and controller.get_selected_evidence_ids(0) == ["e_a"], "is_selected() follows the active draft; the other draft keeps its content")


func _test_slot_capacity_enforcement_per_draft() -> void:
	var controller = _started_controller()
	_fill_correct_first(controller)
	_check(not controller.has_room() and not controller.select_evidence("e_d"), "a full 3-slot draft must reject a 4th clue before the evaluator ever sees it")
	controller.select_draft(1)
	controller.select_evidence("e_d")
	controller.select_evidence("e_e")
	_check(not controller.select_evidence("e_noise"), "a full 2-slot draft must reject a 3rd clue")
	_check(controller.get_selected_evidence_ids(1).size() == 2 and controller.get_selected_evidence_ids(0).size() == 3, "rejected over-capacity placements change nothing")


func _test_duplicate_selection_rejected() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	_check(not controller.select_evidence("e_a"), "placing the same clue twice in one draft must be rejected")
	controller.select_draft(1)
	_check(controller.select_evidence("e_a"), "the same clue may be drafted into a DIFFERENT question — drafts are independent")


func _test_remove_and_replace() -> void:
	var controller = _started_controller()
	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	_check(controller.remove_evidence("e_a") and controller.get_selected_evidence_ids() == ["e_b"], "remove_evidence removes only the named clue")
	_check(not controller.remove_evidence("e_noise"), "removing an unplaced clue should fail")
	controller.select_evidence("e_a")
	controller.select_evidence("e_c")
	_check(controller.replace_evidence("e_a", "e_d"), "replace_evidence should swap a placed clue for an unplaced pool item")
	var after: Array = controller.get_selected_evidence_ids()
	_check(after.has("e_d") and not after.has("e_a") and after.size() == 3, "replace keeps the other clues and the slot count")
	_check(not controller.replace_evidence("e_a", "e_noise") and not controller.replace_evidence("e_b", "e_d"), "replace fails for an unplaced old clue or an already placed new clue")


func _test_two_independent_drafts() -> void:
	var controller = _started_controller()
	_fill_correct_first(controller)
	controller.select_draft(1)
	controller.select_evidence("e_d")
	_check(controller.get_active_draft_index() == 1, "select_draft switches the active tab")
	_check(controller.get_selected_evidence_ids(0) == ["e_a", "e_b", "e_c"], "switching tabs must retain the first draft exactly")
	controller.select_draft(0)
	controller.remove_evidence("e_c")
	_check(controller.get_selected_evidence_ids(1) == ["e_d"], "editing one draft must never touch the other")
	_check(not controller.select_draft(5) and controller.get_active_draft_index() == 0, "an out-of-range tab is rejected")


func _test_draft_editing_saving_and_switching_never_evaluate() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_fill_correct_first(controller)
	_check(controller.save_draft(), "saving a draft should succeed")
	_check(controller.is_draft_saved(0), "a just-saved draft reports saved")
	controller.replace_evidence("e_c", "e_noise")
	_check(not controller.is_draft_saved(0), "editing after a save reports unsaved changes")
	controller.select_draft(1)
	controller.select_evidence("e_d")
	controller.save_draft()
	controller.select_draft(0)

	_check(controller.get_session().get_attempts().is_empty(), "drafting/saving/switching must never reach DeductionEvaluator.commit_attempt()")
	_check(controller.get_session().get_resolved_claims().is_empty(), "no deduction may unlock from drafting alone")
	_check(controller.get_session().get_hint_levels().is_empty(), "drafting must never advance a hint")
	_check(controller.get_policy().get_formal_commit_count() == 0 and controller.get_policy().get_run_resolution_result() == "independent", "drafting must never consume an attempt or change the tier")
	var saved: Array = recorder.get_events().filter(func(e): return e.get("type") == "draft_saved")
	_check(saved.size() == 2 and saved[0].get("payload", {}).get("evidence_ids") == ["e_a", "e_b", "e_c"], "each save should record a normalized draft_saved event, got %s" % [saved])
	var types: Array = recorder.get_events().map(func(e): return e.get("type"))
	_check(not types.has("formal_commit_started") and not types.has("theory_batch_submitted"), "drafting must record no commit telemetry")


func _test_commit_requires_every_draft_complete() -> void:
	var controller = _started_controller()
	_fill_correct_first(controller)
	_check(not controller.can_commit_theory(), "Commit Theory must be disabled while any draft is incomplete")
	var result: Dictionary = controller.commit_theory()
	_check(result.get("category") == "invalid_input" and result.get("reason") == "incomplete_drafts" and result.get("counted") == false, "an incomplete theory must be refused without counting")
	_check(controller.get_session().get_attempts().is_empty() and controller.get_policy().get_formal_commit_count() == 0, "a refused incomplete commit must not reach the evaluator")
	_fill_draft(controller, 1, ["e_d", "e_e"])
	_check(controller.can_commit_theory(), "Commit Theory enables once every draft is complete")


func _test_one_correct_one_incorrect_commits_neither() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_fill_correct_first(controller)
	_fill_draft(controller, 1, ["e_d", "e_noise"])
	var result: Dictionary = controller.commit_theory()
	_check(result.get("category") == "theory_rejected" and result.get("counted") == true and result.get("accepted") == false, "a theory with one invalid draft is a counted, rejected formal commit")
	_check(controller.get_session().get_resolved_claims().is_empty(), "a rejected batch must unlock NEITHER deduction — not even the correct one")
	_check(controller.get_session().get_attempts().is_empty(), "a rejected batch must be classified side-effect-free, never committed")
	_check(controller.get_selected_evidence_ids(0) == ["e_a", "e_b", "e_c"] and controller.get_selected_evidence_ids(1) == ["e_d", "e_noise"], "a rejected batch must preserve both drafts exactly")
	_check(controller.get_policy().get_current_unit_failures() == 1 and controller.get_policy().get_run_resolution_result() == "guided", "one failed batch counts one failure and makes the run Guided")
	_check(result.get("feedback_level") == "coarse" and not result.has("affected_draft_index"), "the first failure must not identify which draft failed")
	var serialized: String = JSON.stringify(result)
	for leak in ["e_a", "e_b", "e_c", "e_d", "e_noise", "ded_first", "ded_second", "irrelevant_evidence", "valid_support"]:
		_check(not serialized.contains("\"%s\"" % leak), "the rejection result must not carry \"%s\" (no per-draft or per-clue correctness)" % leak)
	var rejected: Array = recorder.get_events().filter(func(e): return e.get("type") == "theory_batch_rejected")
	_check(rejected.size() == 1 and rejected[0].get("payload", {}).get("invalid_drafts") == [1], "telemetry (analysis only) should record which draft failed")


func _test_second_failure_names_only_an_affected_question() -> void:
	var controller = _started_controller()
	_fill_correct_first(controller)
	_fail_theories(controller, 0, 1)
	var second: Dictionary = _fail_theories(controller, 1, 1)
	_check(second.get("feedback_level") == "guided" and second.get("affected_draft_index") == 1, "the second failure may name the affected question (question 2 here)")
	var keys: Array = second.keys()
	keys.sort()
	_check(keys == ["accepted", "affected_draft_index", "category", "counted", "feedback_level", "partner", "reason", "resolution"], "guided feedback carries only the affected question — never clue-level detail, got %s" % [keys])

	var both_wrong = _started_controller()
	_fill_draft(both_wrong, 0, ["e_a", "e_b", "e_noise"])
	_fill_draft(both_wrong, 1, ["e_d", "e_noise"])
	both_wrong.commit_theory()
	_fill_draft(both_wrong, 1, ["e_e", "e_noise"])
	_check(both_wrong.commit_theory().get("affected_draft_index") == 0, "with several invalid drafts the FIRST in authored order is named, deterministically")


func _test_identical_failed_theory_is_blocked() -> void:
	var controller = _started_controller()
	_fill_correct_first(controller)
	_fill_draft(controller, 1, ["e_d", "e_noise"])
	controller.commit_theory()
	_check(controller.is_known_failed_theory() and not controller.can_commit_theory(), "the identical failed theory must be disabled")
	var repeat: Dictionary = controller.commit_theory()
	_check(repeat.get("reason") == "duplicate_failed_theory" and repeat.get("counted") == false, "re-committing an identical failed theory must be refused without cost")
	_check(controller.get_policy().get_current_unit_failures() == 1, "the refused duplicate must not count")
	controller.select_draft(1)
	controller.replace_evidence("e_noise", "e_e")
	_check(controller.can_commit_theory(), "changing any connection re-enables Commit Theory")


## Milestone 1.14.2A: the blocked duplicate is now OBSERVABLE (previously
## silently dropped) — purely additive, and must never change the reason/
## counted-ness a caller sees.
func _test_duplicate_theory_telemetry_is_observable_and_inert() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_fill_correct_first(controller)
	_fill_draft(controller, 1, ["e_d", "e_noise"])
	controller.commit_theory()
	var repeat: Dictionary = controller.commit_theory()

	var blocked_events: Array = recorder.get_events().filter(func(e): return e.get("type") == "theory_blocked_duplicate")
	_check(blocked_events.size() == 1, "the blocked duplicate theory should be recorded exactly once, got %d" % blocked_events.size())
	_check((blocked_events[0].get("payload", {}).get("drafts", []) as Array).size() == 2, "the blocked-duplicate payload should carry every draft's normalized identity")

	var unrecorded = _started_controller()
	_fill_correct_first(unrecorded)
	_fill_draft(unrecorded, 1, ["e_d", "e_noise"])
	unrecorded.commit_theory()
	var repeat_unrecorded: Dictionary = unrecorded.commit_theory()
	_check(JSON.stringify(repeat_unrecorded) == JSON.stringify(repeat), "attaching a recorder must never change what commit_theory() returns for a blocked duplicate")


func _test_selection_order_does_not_matter() -> void:
	var controller = _started_controller()
	_fill_draft(controller, 0, ["e_c", "e_b", "e_a"])
	_fill_draft(controller, 1, ["e_e", "e_d"])
	_check(controller.commit_theory().get("accepted") == true, "placement order must never affect correctness")


func _test_alternate_proof_path_is_accepted() -> void:
	var controller = _started_controller()
	_fill_draft(controller, 0, ["e_a", "e_b", "e_f"])
	_fill_draft(controller, 1, ["e_d", "e_e"])
	var result: Dictionary = controller.commit_theory()
	_check(result.get("accepted") == true and controller.get_policy().get_failed_commit_count() == 0, "an alternate valid proof path must be accepted and never count as a failure")


func _test_successful_batch_commits_both_through_evaluator() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_fill_correct_first(controller)
	_fill_draft(controller, 1, ["e_d", "e_e"])
	var result: Dictionary = controller.commit_theory()
	_check(result.get("category") == "theory_accepted" and result.get("accepted") == true and result.get("counted") == true, "a fully valid theory is accepted")
	_check(controller.get_session().is_supported("ded_first") and controller.get_session().is_supported("ded_second"), "both deductions must be committed")
	_check(controller.get_session().get_attempts().size() == 2, "each deduction must go through DeductionEvaluator.commit_attempt() exactly once")
	_check(controller.is_theory_accepted() and controller.get_policy().get_run_resolution_result() == "independent", "a first-try theory with no hints stays Independent")
	_check(not controller.select_evidence("e_noise") and not controller.save_draft(), "an accepted theory can no longer be edited")
	var again: Dictionary = controller.commit_theory()
	_check(again.get("reason") == "already_accepted" and again.get("counted") == false and controller.get_session().get_attempts().size() == 2, "re-committing an accepted theory counts nothing and never recommits")
	var types: Array = recorder.get_events().map(func(e): return e.get("type"))
	for expected in ["formal_commit_started", "theory_batch_submitted", "theory_batch_accepted", "formal_commit_succeeded", "deduction_unlocked"]:
		_check(types.has(expected), "an accepted theory should record %s, got %s" % [expected, types])
	var unlocked: Array = recorder.get_events().filter(func(e): return e.get("type") == "deduction_unlocked")
	_check(unlocked.size() == 2 and unlocked.all(func(e): return e.get("payload", {}).get("resolved_by") == "player"), "both unlocks should be attributed to the player")


func _test_third_failure_requires_assistance() -> void:
	var controller = _started_controller()
	_fill_correct_first(controller)
	var third: Dictionary = _fail_theories(controller, 0, 3)
	_check(third.get("resolution", {}).get("assistance_offered") == true, "the third failed theory should offer assistance")
	_check(controller.get_policy().requires_assistance() and controller.get_policy().get_run_resolution_result() == "assisted", "three failed theories enter Assisted Mode")
	_fill_draft(controller, 1, ["e_d", "e_e"])
	_check(not controller.can_commit_theory(), "Commit Theory stays disabled until assistance is acknowledged — even for a correct theory")
	var locked: Dictionary = controller.commit_theory()
	_check(locked.get("reason") == "submission_locked" and locked.get("counted") == false, "a locked commit is refused without counting")
	_check(controller.get_session().get_resolved_claims().is_empty(), "a locked commit never reaches the evaluator")


func _test_assistance_points_at_an_invalid_draft_without_inserting_clues() -> void:
	var controller = _started_controller()
	_fill_correct_first(controller)
	_fail_theories(controller, 0, 3)
	controller.select_draft(0)
	_check(controller.get_assistance_draft_index() == -1, "no assistance target before acknowledgement")
	var before_second: Array = controller.get_selected_evidence_ids(1)
	var accepted: Dictionary = controller.accept_assistance()
	_check(accepted.get("accepted") == true, "assistance can be acknowledged after the third failure")
	_check(controller.get_assistance_draft_index() == 1 and controller.get_active_draft_index() == 1, "assistance focuses (and opens) the invalid question's draft")
	_check(controller.get_selected_evidence_ids(1) == before_second and controller.get_selected_evidence_ids(0).size() == 3, "assistance must never insert or remove a clue")
	_check(controller.get_session().get_hint_levels().is_empty(), "assistance reads the hint ladder's content; it never advances the player's own hint levels")
	_check(controller.get_policy().can_submit(), "acknowledging assistance re-enables committing")


func _test_partner_batch_resolution_uses_real_evaluator() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_fill_correct_first(controller)
	_fail_theories(controller, 0, 3)
	controller.accept_assistance()
	var fifth: Dictionary = _fail_theories(controller, 3, 2)
	_check(fifth.get("resolution", {}).get("partner_offered") == true and controller.get_policy().can_use_partner_resolution(), "two assisted failures offer partner resolution")
	_check(not controller.can_commit_theory(), "blind commits close once partner resolution is offered")

	var partner: Dictionary = controller.resolve_with_partner()
	_check(partner.get("accepted") == true and partner.get("partner") == true and partner.get("counted") == false, "partner resolution accepts the theory without counting a player commit")
	_check(partner.get("partner_draft_indices") == [1], "the partner supplies only the invalid draft")
	_check(controller.get_selected_evidence_ids(0) == ["e_a", "e_b", "e_c"], "the player's valid draft must be kept exactly as built")
	_check(controller.get_selected_evidence_ids(1) == ["e_d", "e_e"], "the partner fills the invalid draft with the authored proof set")
	_check(controller.get_session().is_supported("ded_first") and controller.get_session().is_supported("ded_second"), "both deductions resolve")
	_check(controller.get_session().get_attempts().size() == 2, "partner resolution commits through DeductionEvaluator.commit_attempt(), never a direct mutation")
	_check(controller.get_policy().get_unit_resolved_by() == "partner" and controller.get_stats().get("partner_resolutions") == 1 and controller.get_stats().get("attempts") == 5, "the theory is attributed to the partner and the player's 5 commits stay as they were")
	var used: Array = recorder.get_events().filter(func(e): return e.get("type") == "partner_resolution_used")
	_check(used.size() == 1 and used[0].get("payload", {}).get("partner_supplied_drafts") == [1], "partner resolution is recorded with the drafts it supplied")
	var unlocked: Array = recorder.get_events().filter(func(e): return e.get("type") == "deduction_unlocked")
	_check(unlocked.all(func(e): return e.get("payload", {}).get("resolved_by") == "partner"), "partner unlocks are attributed to the partner")
	_check(controller.acknowledge_result().get("prototype_completed") == true, "partner resolution still completes the prototype — no hard failure")


func _test_partner_resolution_unavailable_before_threshold() -> void:
	var controller = _started_controller()
	_check(controller.resolve_with_partner().get("reason") == "partner_unavailable", "partner resolution is refused on a fresh run")
	_fill_correct_first(controller)
	_fail_theories(controller, 0, 3)
	_check(controller.resolve_with_partner().get("reason") == "partner_unavailable", "partner resolution is refused while assistance is merely pending")
	_check(controller.get_session().get_resolved_claims().is_empty() and controller.get_session().get_attempts().is_empty(), "a refused partner resolution touches nothing")


func _test_hints_use_real_base_api_and_raise_tier() -> void:
	var controller = _started_controller()
	var hint1: Dictionary = controller.reveal_next_hint()
	_check(hint1.get("available") == true and hint1.get("level") == 1 and hint1.get("target") == "ded_first", "the hint targets the active draft's deduction through the real API")
	_check(controller.get_session().get_hint_level("ded_first") == 1 and controller.get_hint_level() == 1, "the level lives on DeductionSession — no private hint state")
	_check(controller.get_policy().get_run_resolution_result() == "guided" and hint1.get("resolution", {}).get("run_resolution_result_changed") == true, "hint level 1 makes the run Guided, reported explicitly")
	controller.select_draft(1)
	_check(controller.get_hint_level() == 0 and controller.get_hint_level(0) == 1, "each draft reads its own target's hint level")
	controller.reveal_next_hint()
	controller.reveal_next_hint()
	controller.reveal_next_hint()
	_check(controller.get_policy().get_run_resolution_result() == "assisted", "hint level 3 makes the run Assisted")
	controller.reveal_next_hint()
	_check(controller.reveal_next_hint().get("exhausted") == true and controller.get_hint_level() == 4, "asking past the last level reports exhausted")


func _test_acknowledge_result_completes_only_after_acceptance() -> void:
	var controller = _started_controller()
	_check(controller.acknowledge_result().get("prototype_completed") == false, "acknowledging before acceptance is a safe no-op")
	_fill_correct_first(controller)
	_fill_draft(controller, 1, ["e_d", "e_noise"])
	controller.commit_theory()
	_check(controller.acknowledge_result().get("prototype_completed") == false and not controller.is_completed(), "dismissing a rejection never completes anything")
	_fill_draft(controller, 1, ["e_d", "e_e"])
	controller.commit_theory()
	_check(controller.acknowledge_result().get("prototype_completed") == true and controller.is_completed(), "acknowledging an accepted theory completes the prototype")
	_check(controller.acknowledge_result().get("prototype_completed") == true, "a repeated acknowledge stays a safe no-op")


func _test_stats_and_abandonment() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_check(controller.get_stats().get("attempts") == 0, "a fresh run should report zero formal commits")
	_fill_correct_first(controller)
	controller.save_draft()
	_fill_draft(controller, 1, ["e_d", "e_noise"])
	controller.commit_theory()
	controller.replace_evidence("e_noise", "e_e")
	controller.commit_theory()
	controller.reveal_next_hint()
	var stats: Dictionary = controller.get_stats()
	_check(stats.get("attempts") == 2 and stats.get("failed") == 1, "two formal theory commits, one failed")
	_check(stats.get("replacements") == 1 and stats.get("drafts_saved") == 1 and stats.get("hints_used") == 1, "replacements, saves and hints are tracked")
	for key in stats:
		_check(typeof(stats[key]) == TYPE_INT, "stats.%s must be numeric" % key)

	var abandoned = _started_controller(recorder)
	abandoned.select_evidence("e_a")
	_check(abandoned.has_progress(), "an unsubmitted draft counts as progress")
	abandoned.abandon()
	_check(recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with progress should record prototype_abandoned")

	var fresh_recorder = _new_recorder()
	var fresh = _started_controller(fresh_recorder)
	fresh.abandon()
	_check(not fresh_recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with no progress records nothing")


func _test_restart_is_recorded_as_a_new_run() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_fill_correct_first(controller)
	_fail_theories(controller, 0, 1)
	controller.start(fixtures.prototype_b_case(), recorder)
	var restarted: Array = recorder.get_events().filter(func(e): return e.get("type") == "prototype_restarted")
	_check(restarted.size() == 1 and restarted[0].get("payload", {}).get("previous_failed_commits") == 1, "a restart is recorded with the previous run's outcome")
	_check(controller.get_run_count() == 2 and controller.get_policy().get_current_unit_failures() == 0, "a restart is a new run with a fresh policy")


## Cheap but valuable structural guarantee: the controller must resolve
## claims, record attempts and advance hints ONLY through DeductionEvaluator
## (which itself calls these), never by calling these DeductionSession
## mutators directly — see docs/deduction-system.md's "Called by
## DeductionEvaluator only" section on DeductionSession itself.
func _test_no_direct_session_mutation() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/deduction/prototype_b_controller.gd")
	for forbidden in ["_session.resolve_claim(", "_session.record_attempt(", "_session.advance_hint(", "_session.mark_solved("]:
		_check(not source.contains(forbidden), "prototype_b_controller.gd must never call DeductionSession.%s directly — only DeductionEvaluator may" % forbidden.trim_suffix("("))
