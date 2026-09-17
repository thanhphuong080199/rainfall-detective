extends SceneTree
## Focused tests for PrototypeCController (Milestone 1.13 — see
## docs/prototype-c.md; resolution policy since Milestone 1.14 — see
## docs/resolution-policy.md): fresh interaction state per run, fixed events
## pre-placed and locked, free select/place/move/remove, exact submission
## gating (incomplete boards, any previously failed placement), acceptance
## through the REAL TimelineEvaluator rather than exact authored-solution
## equality, optional constraints never blocking acceptance, progressive
## violation feedback (category, then one fact), the assistance/partner flow
## (a partner timeline applied only if TimelineEvaluator accepts it), the final
## claim's verdict + supporting-fact requirement (a binary answer alone never
## completes; every legitimate supporting fact is accepted), claim-unit
## assistance/partner resolution, stats/abandonment/restart telemetry,
## isolation from every other prototype's own state, and that this
## controller never touches a DeductionSession at all. Pure/autoload-free —
## hand-built fixture, no ContentDB needed. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_c_controller_test.gd

## Five DISTINCT failing placements for the fixture: two violate only t_a's
## window, three violate t_b's window AND the "t_b after the 10:00 anchor"
## order fact (a pair constraint).
const FAILING_PLACEMENTS := [
	{"t_a": "10:10", "t_b": "10:10"}, {"t_a": "10:25", "t_b": "10:10"},
	{"t_a": "09:00", "t_b": "09:00"}, {"t_a": "09:15", "t_b": "09:15"}, {"t_a": "09:30", "t_b": "09:30"},
]
const VALID_PLACEMENT := {"t_a": "09:00", "t_b": "10:10"}

var controller_script: Variant
var lab_controller_script: Variant
var pa_controller_script: Variant
var pb_controller_script: Variant
var recorder_script: Variant
var timeline: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	controller_script = load("res://scripts/deduction/prototype_c_controller.gd")
	lab_controller_script = load("res://scripts/deduction/deduction_lab_controller.gd")
	pa_controller_script = load("res://scripts/deduction/prototype_a_controller.gd")
	pb_controller_script = load("res://scripts/deduction/prototype_b_controller.gd")
	recorder_script = load("res://scripts/deduction/deduction_lab_recorder.gd")
	timeline = load("res://scripts/deduction/timeline_evaluator.gd")
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
	# Milestone 1.14 — resolution policy (docs/resolution-policy.md).
	_test_moves_and_reading_never_consume_commits()
	_test_any_previously_failed_placement_is_blocked()
	_test_first_failure_reveals_only_a_category()
	_test_second_failure_reveals_one_fact()
	_test_third_failure_enters_assisted()
	_test_assistance_names_a_critical_pair_without_moving_events()
	_test_alternate_valid_timeline_succeeds_after_failures()
	_test_partner_timeline_is_evaluator_validated()
	_test_partner_timeline_never_applies_an_unaccepted_placement()
	_test_hints_raise_tier()
	_test_binary_claim_answer_alone_cannot_complete()
	_test_every_supporting_fact_completes()
	_test_unrelated_supporting_fact_fails_and_timeline_survives()
	_test_claim_feedback_levels_and_duplicates()
	_test_claim_assistance_and_partner_resolution()
	_test_acknowledge_claim_is_idempotent()
	_test_stats_and_abandonment()
	_test_recorder_events_and_restart()
	_test_no_deduction_session_dependency()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_controller():
	return controller_script.new()


func _started_controller(recorder = null, case_def: Dictionary = {}):
	var controller = _new_controller()
	controller.start(case_def if not case_def.is_empty() else fixtures.prototype_c_case(), recorder)
	return controller


func _new_recorder():
	var recorder = recorder_script.new()
	recorder.start("fx_pc_case", "timeline_reconstruction", "en")
	return recorder


func _place(controller, placement: Dictionary) -> void:
	for event_id in placement:
		controller.place_event(event_id, placement[event_id])


func _submit(controller, placement: Dictionary) -> Dictionary:
	_place(controller, placement)
	return controller.submit_timeline()


func _fail_timelines(controller, from_index: int, count: int) -> Dictionary:
	var last: Dictionary = {}
	for i in range(from_index, from_index + count):
		last = _submit(controller, FAILING_PLACEMENTS[i])
	return last


func _accepted_controller(recorder = null, case_def: Dictionary = {}):
	var controller = _started_controller(recorder, case_def)
	_submit(controller, VALID_PLACEMENT)
	return controller


func _test_start_creates_fresh_state() -> void:
	var controller = _new_controller()
	_check(controller.get_case_def().is_empty() and controller.get_policy() == null, "a fresh controller should have no case/policy before start()")
	_check(controller.start(fixtures.prototype_c_case()), "start() should succeed for well-formed Prototype C content")
	_check(not controller.is_completed() and not controller.is_accepted(), "a fresh run is neither accepted nor completed")
	_check(controller.is_fixed("t_fixed") and controller.get_placement("t_fixed") == "10:00", "the fixed event should be pre-placed at its own authored fixed_time")
	_check(controller.get_placement("t_a") == "" and controller.get_placement("t_b") == "" and controller.get_unplaced_count() == 2, "movable events should start unplaced")
	_check(not controller.can_submit() and controller.get_hint_ladder().size() == 4, "an incomplete board cannot submit; the ladder comes from content")
	_check(controller.get_policy().get_run_resolution_result() == "independent" and controller.get_resolution_unit() == 0, "a fresh run starts Independent on the timeline unit")

	controller.place_event("t_a", "09:00")
	_check(controller.start(fixtures.prototype_c_case()), "start() should succeed again (Restart)")
	_check(controller.get_placement("t_a") == "" and controller.get_unplaced_count() == 2, "Restart must discard all previous placements")


func _test_start_rejects_malformed_or_missing_prototype_c() -> void:
	var controller = _new_controller()
	_check(not controller.start({}), "start() should reject an empty dictionary")
	_check(not controller.start({"id": "no_prototype_c_here"}), "start() should reject a case with no prototype_c layer")
	var no_slots: Dictionary = fixtures.prototype_c_case()
	no_slots["prototype_c"]["time_slots"] = []
	_check(not controller.start(no_slots), "start() should reject an empty time_slots array")
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
	_submit(pc_controller, VALID_PLACEMENT)

	_check(lab_controller.get_session() == lab_session and lab_session.get_opened_evidence_ids() == ["e_log"], "a Prototype C run must leave the Lab's session untouched")
	_check(pa_controller.get_session() == pa_session and pa_session.get_opened_evidence_ids() == ["e_a"], "a Prototype C run must leave Prototype A's session untouched")
	_check(pb_controller.get_selected_evidence_ids() == ["e_a"], "a Prototype C run must leave Prototype B's drafts untouched")


func _test_fixed_events_are_locked() -> void:
	var controller = _started_controller()
	_check(not controller.select_event("t_fixed") and not controller.place_event("t_fixed", "09:00") and not controller.remove_event("t_fixed"), "a fixed event can never be selected, placed or removed")
	_check(controller.get_placement("t_fixed") == "10:00", "the fixed event's locked time must be unaffected")


func _test_select_place_move_remove() -> void:
	var controller = _started_controller()
	_check(controller.select_event("t_a") and controller.get_selected_event_id() == "t_a", "selecting a movable event should succeed")
	_check(controller.place_selected("09:00") and controller.get_placement("t_a") == "09:00", "placing the selected event should succeed")
	_check(controller.place_event("t_a", "09:15") and controller.get_placement("t_a") == "09:15", "placing at a different slot moves the event")
	_check(not controller.place_event("t_a", "09:15"), "placing at the SAME slot again must be a no-op")
	_check(controller.remove_event("t_a") and controller.get_placement("t_a") == "", "removing clears the placement")
	_check(not controller.remove_event("t_a"), "removing an already-unplaced event must fail")
	_check(controller.place_selected("09:00") and controller.get_placement("t_a") == "09:00", "the selection persists across remove/place")
	_check(not controller.place_event("t_a", "not_a_slot"), "placing at a time not in time_slots must fail")
	_check(not _started_controller().place_selected("09:00"), "place_selected with nothing ever selected must fail")


func _test_multiple_events_can_share_a_slot() -> void:
	var controller = _started_controller()
	_check(controller.place_event("t_a", "09:00") and controller.place_event("t_b", "09:00"), "two events may share a slot — only TimelineEvaluator can reject a conflict")


func _test_incomplete_timeline_cannot_submit() -> void:
	var controller = _started_controller()
	controller.place_event("t_a", "09:00")
	var result: Dictionary = controller.submit_timeline()
	_check(result.get("category") == "invalid_input" and result.get("counted") == false, "an incomplete board is refused as invalid_input without counting")
	_check(controller.get_policy().get_formal_commit_count() == 0 and controller.get_stats().get("submissions") == 0, "an incomplete board never consumes a formal commit")
	controller.place_event("t_b", "10:10")
	_check(controller.can_submit() and controller.can_check_timeline(), "a fully placed board can be checked")


func _test_invalid_timeline_rejected_and_retained() -> void:
	var controller = _started_controller()
	var result: Dictionary = _submit(controller, FAILING_PLACEMENTS[0])
	_check(result.get("accepted") == false and result.get("counted") == true, "a timeline violating a required constraint is a counted rejection")
	_check((result.get("violated_required", []) as Array).has("c_a_window"), "the evaluator's own violation list is kept internally")
	_check(controller.get_placement("t_a") == "10:10" and controller.get_placement("t_b") == "10:10", "a rejection must retain every placement exactly")
	_check(not controller.is_accepted(), "the run must not be accepted")


func _test_identical_resubmission_blocked_until_a_move() -> void:
	var controller = _started_controller()
	_submit(controller, FAILING_PLACEMENTS[0])
	_check(not controller.can_resubmit() and not controller.can_check_timeline(), "resubmitting the identical placement must be disabled until something changes")
	var blocked: Dictionary = controller.submit_timeline()
	_check(blocked.get("blocked_duplicate") == true and blocked.get("counted") == false, "a defense-in-depth resubmit reports blocked_duplicate and counts nothing")
	controller.place_event("t_a", "09:00")
	_check(controller.can_resubmit(), "a real placement change re-enables resubmission")
	_check(controller.submit_timeline().get("blocked_duplicate") == false, "a genuinely new placement is not a duplicate")


func _test_authored_and_alternate_placements_both_accepted() -> void:
	_check(_submit(_started_controller(), {"t_a": "09:00", "t_b": "10:10"}).get("accepted") == true, "one valid placement should be accepted")
	_check(_submit(_started_controller(), {"t_a": "09:15", "t_b": "10:25"}).get("accepted") == true, "a DIFFERENT valid placement must also be accepted")


func _test_optional_constraint_never_blocks_acceptance() -> void:
	var result: Dictionary = _submit(_started_controller(), VALID_PLACEMENT)
	_check(result.get("accepted") == true and (result.get("violated_optional", []) as Array).has("c_lie"), "an accepted timeline may still violate the OPTIONAL disputed-claim constraint")


func _test_hints() -> void:
	var controller = _started_controller()
	var hint1: Dictionary = controller.reveal_next_hint()
	_check(hint1.get("available") == true and hint1.get("level") == 1 and controller.get_hint_level() == 1, "the first reveal returns level 1")
	for i in 3:
		controller.reveal_next_hint()
	_check(controller.reveal_next_hint().get("exhausted") == true and controller.get_hint_level() == 4, "asking past the last level reports exhausted")


# ---------------------------------------------------------------------------
# Milestone 1.14 — resolution policy

func _test_moves_and_reading_never_consume_commits() -> void:
	var controller = _started_controller()
	controller.select_event("t_a")
	controller.place_selected("09:00")
	controller.place_event("t_a", "10:40")
	controller.remove_event("t_a")
	controller.open_fact("c_a_window")
	_check(controller.get_policy().get_formal_commit_count() == 0 and controller.get_policy().get_run_resolution_result() == "independent", "placing, moving, removing and reading facts never consume a formal commit or change the tier")


func _test_any_previously_failed_placement_is_blocked() -> void:
	var controller = _started_controller()
	_submit(controller, FAILING_PLACEMENTS[0])
	_submit(controller, FAILING_PLACEMENTS[1])
	_place(controller, FAILING_PLACEMENTS[0])  # move back to the FIRST failed placement
	_check(not controller.can_resubmit(), "returning to ANY earlier failed placement must stay blocked")
	var blocked: Dictionary = controller.submit_timeline()
	_check(blocked.get("blocked_duplicate") == true and blocked.get("counted") == false, "re-checking an earlier failed placement counts nothing")
	_check(controller.get_policy().get_current_unit_failures() == 2, "only the two genuinely new placements counted")


func _test_first_failure_reveals_only_a_category() -> void:
	var controller = _started_controller()
	var result: Dictionary = _submit(controller, FAILING_PLACEMENTS[0])
	var feedback: Dictionary = result.get("feedback", {})
	_check(feedback.get("level") == "category" and feedback.get("category") == "window", "the first failure names only a broad category (a window here), got %s" % [feedback])
	_check(not feedback.has("constraint_id") and not JSON.stringify(feedback).contains("c_a_window"), "the first failure must not name the violated fact")
	_check(controller.get_policy().get_run_resolution_result() == "guided" and result.get("resolution", {}).get("standard_attempts_remaining") == 2, "one failure makes the run Guided with 2 checks left")


func _test_second_failure_reveals_one_fact() -> void:
	var controller = _started_controller()
	_fail_timelines(controller, 0, 1)
	var second: Dictionary = _fail_timelines(controller, 1, 1)
	var feedback: Dictionary = second.get("feedback", {})
	_check(feedback.get("level") == "fact" and feedback.get("constraint_id") == "c_a_window", "the second failure names exactly one violated fact, deterministically, got %s" % [feedback])
	var keys: Array = feedback.keys()
	keys.sort()
	_check(keys == ["category", "constraint_id", "level"], "fact-level feedback carries nothing else — no times, no solution distance, got %s" % [keys])
	_check(controller.constraint_event_ids("c_a_window") == ["t_a"], "the fact's involved events can be highlighted")


func _test_third_failure_enters_assisted() -> void:
	var controller = _started_controller()
	var third: Dictionary = _fail_timelines(controller, 0, 3)
	_check(third.get("resolution", {}).get("assistance_offered") == true and controller.get_policy().requires_assistance(), "the third failed check requires assistance")
	_check(controller.get_policy().get_run_resolution_result() == "assisted", "three failed checks make the run Assisted")
	_place(controller, VALID_PLACEMENT)
	_check(not controller.can_check_timeline(), "checking stays disabled until assistance is acknowledged — even for a valid timeline")
	var locked: Dictionary = controller.submit_timeline()
	_check(locked.get("reason") == "submission_locked" and locked.get("counted") == false and not controller.is_accepted(), "a locked check is refused without counting or accepting")


func _test_assistance_names_a_critical_pair_without_moving_events() -> void:
	var controller = _started_controller()
	_fail_timelines(controller, 0, 3)
	_check(controller.get_assistance_constraint_id() == "", "no assistance target before acknowledgement")
	var before: Dictionary = controller.get_placements()
	_check(controller.accept_assistance().get("accepted") == true, "assistance can be acknowledged after the third failure")
	_check(controller.get_assistance_constraint_id() == "c_b_after_fixed", "assistance prefers the violated PAIR relationship over a single window")
	_check(controller.constraint_event_ids("c_b_after_fixed") == ["t_fixed", "t_b"], "the critical pair is identifiable by its events")
	_check(controller.get_placements() == before, "assistance never moves an event")
	_check(controller.can_check_timeline() == false and controller.get_policy().can_submit(), "checks re-enable (this exact failed placement stays blocked)")


func _test_alternate_valid_timeline_succeeds_after_failures() -> void:
	var controller = _started_controller()
	_fail_timelines(controller, 0, 2)
	var accepted: Dictionary = _submit(controller, {"t_a": "09:30", "t_b": "10:40"})
	_check(accepted.get("accepted") == true and controller.get_timeline_resolved_by() == "player", "any valid timeline succeeds, attributed to the player")
	_check(controller.get_policy().get_run_resolution_result() == "guided" and controller.get_resolution_unit() == 1, "two failures leave the run Guided; the claim unit begins")
	_check(controller.get_policy().get_standard_attempts_remaining() == 3, "the claim unit starts with a fresh commit budget")


func _test_partner_timeline_is_evaluator_validated() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_fail_timelines(controller, 0, 3)
	controller.accept_assistance()
	var fifth: Dictionary = _fail_timelines(controller, 3, 2)
	_check(fifth.get("resolution", {}).get("partner_offered") == true and controller.get_policy().can_use_partner_resolution(), "two assisted failures offer partner resolution")
	var partner: Dictionary = controller.resolve_with_partner()
	_check(partner.get("accepted") == true and partner.get("partner") == true and partner.get("counted") == false, "the partner timeline is accepted without counting a player commit")
	_check(timeline.evaluate(fixtures.prototype_c_case(), controller.get_placements()).get("category") == "timeline_consistent", "the applied partner timeline passes the real TimelineEvaluator")
	_check(controller.get_placements() == {"t_fixed": "10:00", "t_a": "09:00", "t_b": "10:10"}, "with no authored solution, the first accepted UI-offered candidate is used")
	_check(partner.get("explained_constraint_ids") == ["c_b_window", "c_b_after_fixed"], "the partner explains the facts the player's last attempt broke")
	_check(controller.get_timeline_resolved_by() == "partner" and controller.get_policy().get_run_resolution_result() == "assisted" and controller.is_claim_phase(), "the timeline is attributed to the partner and the claim phase begins")
	var used: Array = recorder.get_events().filter(func(e): return e.get("type") == "partner_resolution_used")
	_check(used.size() == 1 and used[0].get("payload", {}).get("source") == "enumerated_candidate", "partner resolution is recorded with its validated source")

	var authored_case: Dictionary = fixtures.prototype_c_case()
	authored_case["ground_truth"] = {"solution_timeline": {"t_fixed": "10:00", "t_a": "09:15", "t_b": "10:25"}}
	var authored = _started_controller(null, authored_case)
	_fail_timelines(authored, 0, 3)
	authored.accept_assistance()
	_fail_timelines(authored, 3, 2)
	authored.resolve_with_partner()
	_check(authored.get_placements() == {"t_fixed": "10:00", "t_a": "09:15", "t_b": "10:25"}, "an evaluator-accepted authored solution is preferred")


func _test_partner_timeline_never_applies_an_unaccepted_placement() -> void:
	var bad_solution: Dictionary = fixtures.prototype_c_case()
	bad_solution["ground_truth"] = {"solution_timeline": {"t_fixed": "10:00", "t_a": "09:00", "t_b": "09:00"}}
	var controller = _started_controller(null, bad_solution)
	_fail_timelines(controller, 0, 3)
	controller.accept_assistance()
	_fail_timelines(controller, 3, 2)
	controller.resolve_with_partner()
	_check(controller.get_placements().get("t_b") == "10:10", "an authored solution the evaluator rejects is never applied — a validated candidate is used instead")

	var impossible: Dictionary = fixtures.prototype_c_case()
	impossible["prototype_c"]["time_slots"] = ["09:00", "09:15", "09:30"]  # t_b can never reach its window
	var stuck = _started_controller(null, impossible)
	var wrong: Array = [["09:00", "09:00"], ["09:15", "09:00"], ["09:30", "09:00"], ["09:00", "09:15"], ["09:15", "09:15"]]
	for i in 3:
		_submit(stuck, {"t_a": wrong[i][0], "t_b": wrong[i][1]})
	stuck.accept_assistance()
	for i in range(3, 5):
		_submit(stuck, {"t_a": wrong[i][0], "t_b": wrong[i][1]})
	var refused: Dictionary = stuck.resolve_with_partner()
	_check(refused.get("reason") == "internal_error" and refused.get("accepted") == false and not stuck.is_accepted(), "with no evaluator-accepted placement at all, nothing is applied or accepted")
	_check(stuck.get_policy().can_use_partner_resolution(), "a refused partner resolution leaves the unit open")


func _test_hints_raise_tier() -> void:
	var controller = _started_controller()
	var level1: Dictionary = controller.reveal_next_hint()
	_check(controller.get_policy().get_run_resolution_result() == "guided" and level1.get("resolution", {}).get("run_resolution_result_changed") == true, "hint level 1 makes the run Guided, reported explicitly")
	controller.reveal_next_hint()
	controller.reveal_next_hint()
	_check(controller.get_policy().get_run_resolution_result() == "assisted", "hint level 3 makes the run Assisted")


func _test_binary_claim_answer_alone_cannot_complete() -> void:
	var controller = _accepted_controller()
	var bare: Dictionary = controller.answer_claim(true)
	_check(bare.get("correct") == false and bare.get("counted") == false and bare.get("reason") == "missing_justification", "a verdict without a supporting fact is refused without counting")
	controller.select_claim_answer(true)
	_check(not controller.can_submit_claim(), "Submit Verdict stays disabled until a supporting fact is chosen")
	_check(controller.submit_claim().get("reason") == "missing_justification" and not controller.is_claim_resolved(), "submitting only a verdict never completes")
	_check(not controller.select_claim_justification("c_lie"), "the disputed claim's own hidden constraint is not a selectable fact")
	_check(controller.get_claim_attempts() == 0, "refused claim submissions never count")


func _test_every_supporting_fact_completes() -> void:
	for ref in ["c_b_window", "c_b_after_fixed"]:
		var controller = _accepted_controller()
		controller.select_claim_answer(true)
		controller.select_claim_justification(ref)
		_check(controller.can_submit_claim(), "sanity — verdict and fact selected")
		var result: Dictionary = controller.submit_claim()
		_check(result.get("correct") == true and controller.is_claim_resolved() and controller.get_claim_resolved_by() == "player", "\"Impossible\" justified by %s must be accepted — every legitimate supporting fact counts" % ref)
		_check(controller.get_selected_justification_id() == ref, "the accepted justification is kept for the explanation")


func _test_unrelated_supporting_fact_fails_and_timeline_survives() -> void:
	var controller = _accepted_controller()
	var placements: Dictionary = controller.get_placements()
	var unrelated: Dictionary = controller.answer_claim(true, "c_a_window")
	_check(unrelated.get("correct") == false and unrelated.get("counted") == true, "the right verdict with an unrelated fact is a counted failure")
	_check(controller.is_claim_phase() and controller.is_accepted() and controller.get_placements() == placements, "a failed justification keeps the accepted timeline exactly")
	var fits: Dictionary = controller.answer_claim(false, "c_b_window")
	_check(fits.get("correct") == false, "\"Fits\" must fail when every accepted timeline contradicts the claim — even with a relevant fact")
	_check(controller.get_policy().get_current_unit_failures() == 2 and controller.get_policy().get_unit_index() == 1, "claim failures count in the claim unit's own budget")


func _test_claim_feedback_levels_and_duplicates() -> void:
	var controller = _accepted_controller()
	var first: Dictionary = controller.answer_claim(true, "c_a_window")
	_check(first.get("feedback_level") == "coarse" and not first.has("verdict_correct"), "the first claim failure says nothing about which part was wrong")
	var duplicate: Dictionary = controller.answer_claim(true, "c_a_window")
	_check(duplicate.get("reason") == "duplicate_failed_claim" and duplicate.get("counted") == false, "the identical failed verdict+fact is refused at no cost")
	var second: Dictionary = controller.answer_claim(false, "c_b_window")
	_check(second.get("feedback_level") == "guided" and second.get("verdict_correct") == false, "the second claim failure may say the verdict is off")
	var third: Dictionary = controller.answer_claim(true, "c_a_window" if false else "c_a_window")
	_check(third.get("reason") == "duplicate_failed_claim", "sanity — still a duplicate")


func _test_claim_assistance_and_partner_resolution() -> void:
	var extended: Dictionary = fixtures.prototype_c_case()
	extended["timeline"]["constraints"].insert(3, {"id": "c_a_before_fixed", "type": "before", "events": ["t_a", "t_fixed"], "source": "e_noise"})
	extended["prototype_c"]["visible_constraint_facts"]["c_a_before_fixed"] = "FX"
	var recorder = _new_recorder()
	var controller = _accepted_controller(recorder, extended)
	for pair in [[true, "c_a_window"], [false, "c_b_window"], [false, "c_a_window"]]:
		controller.answer_claim(pair[0], pair[1])
	_check(controller.get_policy().requires_assistance(), "three claim failures require assistance")
	controller.select_claim_answer(true)
	controller.select_claim_justification("c_b_window")
	_check(not controller.can_submit_claim() and controller.submit_claim().get("reason") == "submission_locked", "the correct answer is locked until assistance is acknowledged")
	controller.accept_assistance()
	_check(controller.get_assistance_constraint_id() == "c_lie" and controller.get_claim_event_ids() == ["t_b"], "claim assistance points at the event the claim is about — never the answer")
	for pair in [[false, "c_b_after_fixed"], [true, "c_a_before_fixed"]]:
		controller.answer_claim(pair[0], pair[1])
	_check(controller.get_policy().can_use_partner_resolution(), "two assisted claim failures offer partner resolution")
	var partner: Dictionary = controller.resolve_with_partner()
	_check(partner.get("correct") == true and partner.get("partner") == true and controller.is_claim_resolved(), "partner resolution resolves the claim")
	_check(controller.get_claim_resolved_by() == "partner" and controller.get_selected_claim_answer() == "impossible" and controller.get_selected_justification_id() == "c_b_window", "the partner picks the correct verdict and the first authored supporting fact")
	_check(controller.acknowledge_claim().get("prototype_completed") == true, "partner resolution still completes the prototype — no hard failure")
	var used: Array = recorder.get_events().filter(func(e): return e.get("type") == "partner_resolution_used")
	_check(used.size() == 1 and used[0].get("payload", {}).get("unit") == 1 and used[0].get("payload", {}).get("justification_constraint_id") == "c_b_window", "claim partner resolution is recorded with its justification")


func _test_acknowledge_claim_is_idempotent() -> void:
	var controller = _started_controller()
	_check(controller.acknowledge_claim().get("prototype_completed") == false, "acknowledging before the claim is resolved is a safe no-op")
	_submit(controller, VALID_PLACEMENT)
	controller.answer_claim(true, "c_b_window")
	_check(controller.acknowledge_claim().get("prototype_completed") == true and controller.is_completed(), "acknowledging a resolved claim completes the prototype")
	_check(controller.acknowledge_claim().get("prototype_completed") == true, "a repeated acknowledge stays a safe no-op")


func _test_stats_and_abandonment() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_check(controller.get_stats().get("submissions") == 0, "a fresh run reports zero submissions")
	_submit(controller, FAILING_PLACEMENTS[0])
	controller.place_event("t_a", "09:00")
	controller.submit_timeline()
	controller.reveal_next_hint()
	var stats: Dictionary = controller.get_stats()
	_check(stats.get("submissions") == 2 and stats.get("failed") == 1 and stats.get("moves") >= 3 and stats.get("hints_used") == 1, "timeline stats are tracked")
	controller.answer_claim(false, "c_b_window")
	_check(controller.get_stats().get("claim_attempts") == 1, "a counted claim attempt is tracked even when wrong")
	for key in controller.get_stats():
		_check(typeof(controller.get_stats()[key]) == TYPE_INT, "stats.%s must be numeric" % key)
	controller.abandon()
	_check(recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with progress records prototype_abandoned")
	var fresh_recorder = _new_recorder()
	_started_controller(fresh_recorder).abandon()
	_check(not fresh_recorder.get_events().any(func(e): return e.get("type") == "prototype_abandoned"), "abandon() with no progress records nothing")


func _test_recorder_events_and_restart() -> void:
	var recorder = _new_recorder()
	var controller = _started_controller(recorder)
	_submit(controller, FAILING_PLACEMENTS[0])
	controller.place_event("t_a", "09:00")
	controller.submit_timeline()
	controller.answer_claim(true, "c_a_window")
	controller.answer_claim(true, "c_b_window")
	controller.acknowledge_claim()
	var types: Array = recorder.get_events().map(func(e): return e.get("type"))
	for expected in ["formal_commit_started", "formal_commit_failed", "formal_commit_succeeded", "run_resolution_result_changed", "timeline_rejected", "timeline_accepted", "claim_answered", "claim_justification_result", "contradiction_resolved", "prototype_completed"]:
		_check(types.has(expected), "the run should record %s, got %s" % [expected, types])
	var justification: Array = recorder.get_events().filter(func(e): return e.get("type") == "claim_justification_result")
	_check(justification.size() == 2 and justification[0].get("payload", {}).get("justification_valid") == false and justification[1].get("payload", {}).get("correct") == true, "each claim justification result is recorded")
	var answered: Array = recorder.get_events().filter(func(e): return e.get("type") == "claim_answered")
	_check(answered[0].get("payload", {}).get("justification_constraint_id") == "c_a_window", "claim_answered records the selected justification fact")
	var completed: Array = recorder.get_events().filter(func(e): return e.get("type") == "prototype_completed")
	_check(completed[0].get("payload", {}).get("resolution", {}).get("run_resolution_result") == "guided", "the completion payload carries the resolution summary")

	controller.start(fixtures.prototype_c_case(), recorder)
	var restarted: Array = recorder.get_events().filter(func(e): return e.get("type") == "prototype_restarted")
	_check(restarted.size() == 1 and restarted[0].get("payload", {}).get("previous_completed") == true, "a restart is recorded with the previous run's outcome")
	_check(controller.get_run_count() == 2 and controller.get_policy().get_formal_commit_count() == 0, "a restart is a new run with a fresh policy")


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
