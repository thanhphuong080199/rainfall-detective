extends SceneTree
## Focused tests for ResolutionPolicy (Milestone 1.14 — see
## docs/resolution-policy.md): the initial Independent state, the Guided/
## Assisted tier rules (failed formal commits and hint levels), the per-unit
## phase machine (three failures -> assistance required -> two assisted
## failures -> partner resolution), one-way tier transitions across units,
## that every rejected action counts nothing, the transition-event contract
## controllers record from, result snapshots, JSON-safe serialization with
## strict restore, and determinism. Pure/autoload-free — no content needed.
## Run with:
##   godot --headless --path . -s res://scenes/test/resolution_policy_test.gd

var policy_script: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	policy_script = load("res://scripts/deduction/resolution_policy.gd")

	print("=== ResolutionPolicy — focused tests ===")
	_test_initial_state_is_independent()
	_test_first_and_second_failures_are_guided()
	_test_third_failure_requires_assistance()
	_test_submission_locked_until_assistance_accepted()
	_test_assistance_acknowledgement()
	_test_two_assisted_failures_offer_partner_resolution()
	_test_partner_resolution()
	_test_success_resolves_unit_and_blocks_further_commits()
	_test_valid_non_resolving_success_is_not_a_penalty()
	_test_hint_levels_raise_tier()
	_test_tier_is_one_way_across_units()
	_test_run_wide_failures_count_toward_tier()
	_test_begin_next_unit_requires_resolution()
	_test_rejected_actions_count_nothing()
	_test_transition_events()
	_test_result_snapshot()
	_test_constants_are_centralized()
	_test_serialization_round_trip()
	_test_load_rejects_malformed_or_backward_state()
	_test_deterministic()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_policy():
	return policy_script.new()


func _fail_times(policy, count: int) -> Dictionary:
	var last: Dictionary = {}
	for i in count:
		last = policy.register_failed_commit()
	return last


func _test_initial_state_is_independent() -> void:
	var policy = _new_policy()
	_check(policy.get_run_resolution_result() == "independent", "a fresh policy should be Independent")
	_check(policy.get_current_unit_phase() == "standard", "a fresh policy should be in the standard phase")
	_check(policy.can_submit(), "a fresh policy should accept a formal commit")
	_check(not policy.requires_assistance() and not policy.can_use_partner_resolution(), "a fresh policy should neither require assistance nor offer partner resolution")
	_check(policy.get_standard_attempts_remaining() == 3 and policy.get_assisted_attempts_remaining() == 2, "a fresh unit should have the full 3 standard / 2 assisted budget")
	_check(policy.get_formal_commit_count() == 0 and policy.get_failed_commit_count() == 0 and policy.get_current_unit_failures() == 0, "a fresh policy should count nothing")
	_check(policy.get_unit_index() == 0 and not policy.is_unit_resolved() and policy.get_unit_resolved_by() == "", "a fresh policy should be on unresolved unit 0")
	_check(not policy.is_unit_assistance_accepted(), "no assistance should be active on a fresh policy")


func _test_first_and_second_failures_are_guided() -> void:
	var policy = _new_policy()
	var first: Dictionary = policy.register_failed_commit()
	_check(first.get("accepted") == true and first.get("reason") == "failed_commit", "the first failure should be accepted as a failed commit")
	_check(first.get("run_resolution_result_before") == "independent" and first.get("run_resolution_result_after") == "guided" and first.get("run_resolution_result_changed") == true, "one failed formal commit should make the run Guided, reported as a tier change")
	_check(policy.get_current_unit_phase() == "standard" and policy.can_submit(), "one failure must not lock submission")
	_check(policy.get_standard_attempts_remaining() == 2, "one failure should leave 2 standard attempts")

	var second: Dictionary = policy.register_failed_commit()
	_check(policy.get_run_resolution_result() == "guided" and second.get("run_resolution_result_changed") == false, "two failed formal commits should stay Guided, with no second tier change")
	_check(policy.get_current_unit_phase() == "standard" and policy.get_standard_attempts_remaining() == 1, "two failures should leave 1 standard attempt and still accept commits")
	_check(second.get("assistance_offered") == false, "assistance must not be offered before the third failure")


func _test_third_failure_requires_assistance() -> void:
	var policy = _new_policy()
	_fail_times(policy, 2)
	var third: Dictionary = policy.register_failed_commit()
	_check(policy.get_current_unit_phase() == "assistance_required", "the third failure should move the unit to assistance_required")
	_check(policy.get_run_resolution_result() == "assisted" and third.get("run_resolution_result_changed") == true, "three failed formal commits should make the run Assisted")
	_check(third.get("assistance_offered") == true and third.get("partner_offered") == false, "the third failure should offer assistance, not partner resolution")
	_check(policy.requires_assistance() and not policy.can_submit(), "blind commits must stop until assistance is acknowledged")
	_check(policy.get_standard_attempts_remaining() == 0, "no standard attempts should remain")


func _test_submission_locked_until_assistance_accepted() -> void:
	var policy = _new_policy()
	_fail_times(policy, 3)
	var blocked_failure: Dictionary = policy.register_failed_commit()
	_check(blocked_failure.get("accepted") == false and blocked_failure.get("rejection") == "submission_locked", "a failure while assistance is pending must be rejected")
	var blocked_success: Dictionary = policy.register_success()
	_check(blocked_success.get("accepted") == false, "a success while assistance is pending must be rejected")
	_check(policy.get_formal_commit_count() == 3 and policy.get_failed_commit_count() == 3, "rejected commits must not be counted")
	_check(policy.register_partner_resolution().get("accepted") == false, "partner resolution must not be available while assistance is merely pending")


func _test_assistance_acknowledgement() -> void:
	var policy = _new_policy()
	_fail_times(policy, 3)
	var accepted: Dictionary = policy.accept_assistance()
	_check(accepted.get("accepted") == true and accepted.get("reason") == "assistance", "assistance should be accepted once required")
	_check(policy.get_current_unit_phase() == "assisted" and policy.can_submit(), "acknowledging assistance should re-enable submission")
	_check(policy.is_unit_assistance_accepted() and policy.get_assistance_count() == 1, "the unit should record that assistance was accepted")
	_check(policy.get_run_resolution_result() == "assisted" and accepted.get("run_resolution_result_changed") == false, "the tier stays Assisted (already raised by the third failure)")
	_check(policy.accept_assistance().get("accepted") == false, "assistance cannot be accepted twice")
	_check(policy.get_assistance_count() == 1, "a rejected second acceptance must not count")


func _test_two_assisted_failures_offer_partner_resolution() -> void:
	var policy = _new_policy()
	_fail_times(policy, 3)
	policy.accept_assistance()
	var fourth: Dictionary = policy.register_failed_commit()
	_check(fourth.get("accepted") == true and policy.get_current_unit_phase() == "assisted", "the first assisted failure should keep the unit in Assisted Mode")
	_check(policy.get_assisted_attempts_remaining() == 1 and fourth.get("partner_offered") == false, "one assisted attempt should remain, with no partner offer yet")
	var fifth: Dictionary = policy.register_failed_commit()
	_check(policy.get_current_unit_phase() == "partner_available" and fifth.get("partner_offered") == true, "the second assisted failure should offer partner resolution")
	_check(not policy.can_submit() and policy.can_use_partner_resolution(), "blind submission must close once partner resolution is offered")
	_check(policy.register_failed_commit().get("accepted") == false, "no further failures may be counted once blind submission closed")
	_check(policy.get_failed_commit_count() == 5 and policy.get_current_unit_failures() == 5, "exactly 3 standard + 2 assisted failures should have counted")


func _test_partner_resolution() -> void:
	var policy = _new_policy()
	_fail_times(policy, 3)
	policy.accept_assistance()
	_fail_times(policy, 2)
	var partner: Dictionary = policy.register_partner_resolution()
	_check(partner.get("accepted") == true and partner.get("reason") == "partner_resolution", "partner resolution should be accepted once offered")
	_check(policy.is_unit_resolved() and policy.get_unit_resolved_by() == "partner", "partner resolution should resolve the unit, attributed to the partner")
	_check(policy.get_run_resolution_result() == "assisted" and policy.get_partner_resolution_count() == 1, "partner resolution should leave the run Assisted and be counted")
	_check(policy.get_formal_commit_count() == 5, "partner resolution must never count as the player's own formal commit")
	_check(policy.register_partner_resolution().get("accepted") == false, "partner resolution cannot be used twice on one unit")


func _test_success_resolves_unit_and_blocks_further_commits() -> void:
	var policy = _new_policy()
	var success: Dictionary = policy.register_success()
	_check(success.get("accepted") == true and success.get("run_resolution_result_changed") == false, "an immediate success should be accepted without changing the tier")
	_check(policy.get_run_resolution_result() == "independent", "zero failures, zero hints, no assistance should stay Independent")
	_check(policy.is_unit_resolved() and policy.get_unit_resolved_by() == "player", "a resolving success should resolve the unit, attributed to the player")
	_check(policy.get_formal_commit_count() == 1 and policy.get_failed_commit_count() == 0, "the success should count as one formal commit")
	_check(policy.register_failed_commit().get("accepted") == false, "submitting against an already-resolved unit must not count")
	_check(policy.register_success().get("accepted") == false and policy.get_formal_commit_count() == 1, "a repeated success on a resolved unit must not count")


func _test_valid_non_resolving_success_is_not_a_penalty() -> void:
	var policy = _new_policy()
	var optional: Dictionary = policy.register_success(false)
	_check(optional.get("accepted") == true and policy.get_current_unit_phase() == "standard", "a valid commit that doesn't finish the unit keeps it open")
	_check(policy.get_run_resolution_result() == "independent" and policy.get_standard_attempts_remaining() == 3, "a valid non-resolving commit (e.g. an optional innocent lie) must never cost an attempt or a tier")
	_check(policy.get_formal_commit_count() == 1 and policy.get_failed_commit_count() == 0, "it still counts as a formal commit, never a failure")


func _test_hint_levels_raise_tier() -> void:
	var policy = _new_policy()
	var level1: Dictionary = policy.register_hint(1)
	_check(level1.get("accepted") == true and policy.get_run_resolution_result() == "guided" and level1.get("run_resolution_result_changed") == true, "hint level 1 should make the run Guided")
	_check(policy.register_hint(2).get("run_resolution_result_changed") == false and policy.get_run_resolution_result() == "guided", "hint level 2 should keep the run Guided")
	var level3: Dictionary = policy.register_hint(3)
	_check(policy.get_run_resolution_result() == "assisted" and level3.get("run_resolution_result_changed") == true, "hint level 3 should make the run Assisted")
	_check(policy.get_current_unit_phase() == "standard" and policy.can_submit(), "hints must never change the unit phase or lock submission")
	_check(policy.get_max_hint_level() == 3, "the highest hint level should be tracked")
	_check(policy.register_hint(0).get("accepted") == false, "an invalid hint level must be rejected")

	var direct = _new_policy()
	direct.register_hint(4)
	_check(direct.get_run_resolution_result() == "assisted", "hint level 4 should make the run Assisted directly")


func _test_tier_is_one_way_across_units() -> void:
	var policy = _new_policy()
	policy.register_hint(3)
	policy.register_success()
	_check(policy.begin_next_unit(), "a resolved unit should allow the next unit to begin")
	_check(policy.get_run_resolution_result() == "assisted", "a new unit must never lower the run's tier")
	var later: Dictionary = policy.register_hint(1)
	_check(policy.get_run_resolution_result() == "assisted" and later.get("run_resolution_result_changed") == false, "a lower-tier trigger must never move the tier backward")
	policy.register_success()
	_check(policy.get_run_resolution_result() == "assisted", "a clean success on a later unit must never move the tier backward")


func _test_run_wide_failures_count_toward_tier() -> void:
	var policy = _new_policy()
	_fail_times(policy, 2)
	policy.register_success()
	policy.begin_next_unit()
	_check(policy.get_unit_index() == 1 and policy.get_current_unit_phase() == "standard", "the next unit should start in the standard phase")
	_check(policy.get_current_unit_failures() == 0 and policy.get_standard_attempts_remaining() == 3, "the next unit should get a fresh failure budget")
	_check(policy.get_run_resolution_result() == "guided", "sanity — two earlier failures keep the run Guided")
	policy.register_failed_commit()
	_check(policy.get_run_resolution_result() == "assisted", "the third failed formal commit of the RUN should make it Assisted even in a new unit")
	_check(policy.get_current_unit_phase() == "standard" and policy.can_submit(), "the unit's own budget still decides when assistance is required")


func _test_begin_next_unit_requires_resolution() -> void:
	var policy = _new_policy()
	_check(not policy.begin_next_unit(), "an unresolved unit must never be skipped")
	_fail_times(policy, 3)
	_check(not policy.begin_next_unit(), "a unit waiting for assistance must never be reset into a fresh budget")
	_check(policy.get_current_unit_phase() == "assistance_required" and policy.get_unit_index() == 0, "a refused begin_next_unit must change nothing")


func _test_rejected_actions_count_nothing() -> void:
	var policy = _new_policy()
	_check(policy.accept_assistance().get("accepted") == false, "assistance cannot be accepted when not required")
	_check(policy.register_partner_resolution().get("accepted") == false, "partner resolution cannot be used before it is offered")
	_check(policy.to_dict() == _new_policy().to_dict(), "rejected actions must leave the policy exactly as fresh")


func _test_transition_events() -> void:
	var policy = _new_policy()
	var first_events: Array = policy_script.transition_events(policy.register_failed_commit())
	_check(first_events.size() == 1 and first_events[0].get("type") == "run_resolution_result_changed", "the first failure should emit exactly one run_resolution_result_changed event, got %s" % [first_events])
	_check(first_events[0].get("payload", {}).get("from") == "independent" and first_events[0].get("payload", {}).get("to") == "guided", "the tier change payload should carry from/to")
	policy.register_failed_commit()
	var third_events: Array = policy_script.transition_events(policy.register_failed_commit())
	var third_types: Array = third_events.map(func(e): return e.get("type"))
	_check(third_types == ["run_resolution_result_changed", "assistance_offered"], "the third failure should emit tier change then assistance_offered, got %s" % [third_types])
	policy.accept_assistance()
	policy.register_failed_commit()
	var fifth_types: Array = policy_script.transition_events(policy.register_failed_commit()).map(func(e): return e.get("type"))
	_check(fifth_types == ["partner_resolution_offered"], "the second assisted failure should emit partner_resolution_offered only, got %s" % [fifth_types])
	_check(policy_script.transition_events(policy.register_failed_commit()).is_empty(), "a rejected transition must emit no events")


func _test_result_snapshot() -> void:
	var policy = _new_policy()
	var snapshot: Dictionary = policy.result_snapshot(policy.register_failed_commit())
	_check(snapshot.get("counted") == true and snapshot.get("reason") == "failed_commit", "a counted failure's snapshot should say so")
	_check(snapshot.get("current_unit_phase_after") == "standard" and snapshot.get("standard_attempts_remaining") == 2 and snapshot.get("current_unit_failures") == 1, "the snapshot should carry the budget right after the action")
	var nothing: Dictionary = policy.result_snapshot({})
	_check(nothing.get("counted") == false and nothing.get("run_resolution_result_changed") == false, "an empty transition's snapshot should count nothing")


func _test_constants_are_centralized() -> void:
	_check(policy_script.STANDARD_FAILURE_LIMIT == 3 and policy_script.ASSISTED_FAILURE_LIMIT == 2, "the default limits should be 3 standard + 2 assisted failures")
	for path in ["res://scripts/deduction/prototype_a_controller.gd", "res://scripts/deduction/prototype_b_controller.gd", "res://scripts/deduction/prototype_c_controller.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		# "ResolutionPolicy.new(" rather than "...new()": since Milestone 1.16 the
		# controllers pass the policy mode (help-only in production) — still
		# their own policy, constructed by them.
		_check(source.contains("ResolutionPolicy.new("), "%s should own a ResolutionPolicy" % path)
		_check(not source.contains("FAILURE_LIMIT :=") and not source.contains("FAILURE_LIMIT ="), "%s must not redefine the failure limits — they live only in ResolutionPolicy" % path)
		_check(not source.contains("extends Node"), "%s must stay a pure RefCounted helper" % path)


func _test_serialization_round_trip() -> void:
	var policy = _new_policy()
	_fail_times(policy, 3)
	policy.accept_assistance()
	policy.register_failed_commit()
	policy.register_hint(2)
	var restored = _new_policy()
	var json_copy: Variant = JSON.parse_string(JSON.stringify(policy.to_dict()))
	_check(restored.load_dict(json_copy), "a JSON round trip of to_dict() should load")
	_check(restored.to_dict() == policy.to_dict(), "a restored policy should serialize identically: %s vs %s" % [restored.to_dict(), policy.to_dict()])
	var original_next: Dictionary = policy.register_failed_commit()
	var restored_next: Dictionary = restored.register_failed_commit()
	_check(original_next == restored_next and restored.can_use_partner_resolution(), "a restored policy should continue exactly like the original")


func _test_load_rejects_malformed_or_backward_state() -> void:
	var base: Dictionary = _new_policy().to_dict()
	var cases: Array = []
	cases.append(["not a dictionary", "nope"])
	var bad_tier: Dictionary = base.duplicate(); bad_tier["run_resolution_result"] = "expert"; cases.append(["unknown tier", bad_tier])
	var bad_phase: Dictionary = base.duplicate(); bad_phase["current_unit_phase"] = "limbo"; cases.append(["unknown phase", bad_phase])
	var negative: Dictionary = base.duplicate(); negative["formal_commits"] = -1; cases.append(["negative count", negative])
	var over_limit: Dictionary = base.duplicate(); over_limit["unit_standard_failures"] = 4; over_limit["failed_commits"] = 4; over_limit["formal_commits"] = 4; over_limit["run_resolution_result"] = "assisted"; cases.append(["standard failures over the limit", over_limit])
	var backward: Dictionary = base.duplicate(); backward["failed_commits"] = 2; backward["formal_commits"] = 2; cases.append(["a tier lower than its own failures imply", backward])
	var backward_hint: Dictionary = base.duplicate(); backward_hint["max_hint_level"] = 3; backward_hint["run_resolution_result"] = "guided"; cases.append(["a tier lower than its hint level implies", backward_hint])
	var resolved_nobody: Dictionary = base.duplicate(); resolved_nobody["current_unit_phase"] = "resolved"; cases.append(["a resolved unit with no resolver", resolved_nobody])
	for entry in cases:
		var policy = _new_policy()
		policy.register_hint(4)
		_check(not policy.load_dict(entry[1]), "load_dict must reject %s" % entry[0])
		_check(policy.to_dict() == base, "a rejected load must leave the policy fresh, not half-loaded (%s)" % entry[0])


func _test_deterministic() -> void:
	var a = _new_policy()
	var b = _new_policy()
	var script: Array = ["fail", "hint2", "fail", "fail", "accept", "fail", "fail", "partner", "next", "fail", "success"]
	var a_log: Array = []
	var b_log: Array = []
	for step in script:
		a_log.append(_apply(a, step))
		b_log.append(_apply(b, step))
	_check(a_log == b_log and a.to_dict() == b.to_dict(), "identical action sequences must produce identical transitions and state")


func _apply(policy, step: String) -> Variant:
	match step:
		"fail":
			return policy.register_failed_commit()
		"hint2":
			return policy.register_hint(2)
		"accept":
			return policy.accept_assistance()
		"partner":
			return policy.register_partner_resolution()
		"next":
			return policy.begin_next_unit()
		"success":
			return policy.register_success()
	return null
