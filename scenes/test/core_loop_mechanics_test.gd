extends SceneTree
## Milestone 1.16 — the prototype controllers' production context and
## snapshots, and ResolutionPolicy's help-only mode (see
## docs/core-loop-sandbox.md, "Mechanics"). Pure and autoload-free, like the
## other controller tests: the real proto_x case is read straight from its
## JSON file, never through ContentDB. Proves the debug defaults are
## untouched (fresh session, every round, authored pool, failure-escalating
## policy) and that the new, opt-in context really shares one session,
## scopes rounds, narrows the pool and never lets failures raise the run
## result — and that every controller round-trips through JSON exactly and
## rejects a malformed snapshot as a whole. FAST and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_mechanics_test.gd

const CASE_PATH := "res://data/deductions/prototypes/proto_x_archive_ledger.json"

var case_def: Dictionary = {}
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	case_def = JSON.parse_string(FileAccess.get_file_as_string(CASE_PATH))
	print("=== Core loop mechanics — controller context & snapshots ===")
	_test_debug_defaults_unchanged()
	_test_context_shares_session_and_scopes_rounds()
	_test_context_rejects_bad_scope()
	_test_evidence_pool_override()
	_test_help_only_policy()
	_test_policy_mode_serialization()
	_test_b_hint_total_counts_own_targets_only()
	_test_a_snapshot_round_trip()
	_test_b_snapshot_round_trip()
	_test_c_snapshot_round_trip()
	_test_snapshots_reject_malformed_data()
	_test_restore_records_nothing()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func _context(session: DeductionSession, round_ids: Array, pool: Array) -> Dictionary:
	var ids: Array[String] = []
	ids.assign(round_ids)
	var evidence: Array[String] = []
	evidence.assign(pool)
	return {"session": session, "round_ids": ids, "evidence_pool": evidence, "failures_escalate_run_result": false}


# ---------------------------------------------------------------------------

func _test_debug_defaults_unchanged() -> void:
	var b := PrototypeBController.new()
	_check(b.start(case_def), "B starts with no context")
	_check(b.get_draft_count() == 2 and b.get_evidence_pool_ids() == DeductionEvaluator.string_array(case_def["prototype_b"]["evidence_pool"]), "debug B still batches every round over the authored pool")
	_check(b.get_policy().failures_escalate_run_result(), "debug B keeps the failure-escalating policy")
	var a := PrototypeAController.new()
	a.start(case_def)
	_check(a.get_round_count() == 2 and a.get_session() != b.get_session(), "debug A still owns its own fresh session over every round")
	var c := PrototypeCController.new()
	c.start(case_def)
	_check(c.get_policy().failures_escalate_run_result(), "debug C keeps the failure-escalating policy")


func _test_context_shares_session_and_scopes_rounds() -> void:
	var session := DeductionSession.new(str(case_def["id"]))
	var b1 := PrototypeBController.new()
	var a1 := PrototypeAController.new()
	_check(b1.start(case_def, null, _context(session, ["round_1"], ["e_door_log", "e_tram_tap", "e_route_note"])), "B starts with a production context")
	_check(a1.start(case_def, null, _context(session, ["round_1"], ["e_lost_property_sheet"])), "A starts with a production context")
	_check(b1.get_session() == session and a1.get_session() == session, "both controllers use the injected session, never a fresh one")
	_check(b1.get_draft_count() == 1 and a1.get_round_count() == 1, "rounds are scoped to the configured subset")
	for evidence_id in ["e_door_log", "e_tram_tap", "e_route_note"]:
		b1.select_evidence(evidence_id)
	var committed: Dictionary = b1.commit_theory()
	_check(committed.get("category", "") == PrototypeBController.RESULT_THEORY_ACCEPTED, "a one-round B commits a single deduction")
	a1.select_statement(2)
	a1.select_evidence("e_lost_property_sheet")
	a1.present_evidence()
	_check(session.is_supported("ded_badge_misused") and session.get_claim_status("st_oren_never_touched") == "refuted", "B's deduction and A's refutation land in the ONE shared session")
	_check(not session.is_supported("ded_break_in_staged"), "the other B round was never committed")
	_check(a1.are_all_rounds_resolved(), "A reports its configured rounds resolved at the formal commit")


func _test_context_rejects_bad_scope() -> void:
	var b := PrototypeBController.new()
	_check(not b.start(case_def, null, {"round_ids": ["round_9"]}), "an unknown round id never becomes a silently smaller run")
	_check(not b.start(case_def, null, {"session": DeductionSession.new("proto_y_lab_sample")}), "a session of another case is refused")
	_check(not b.start(case_def, null, {"session": "not a session"}), "a non-session value is refused")


func _test_evidence_pool_override() -> void:
	var a := PrototypeAController.new()
	a.start(case_def, null, _context(DeductionSession.new(str(case_def["id"])), ["round_1"], ["e_tram_tap"]))
	var only_tram: Array[String] = ["e_tram_tap"]
	_check(a.get_evidence_pool_ids() == only_tram, "the pool is exactly the context's (acquired) evidence")
	_check(not a.select_evidence("e_lost_property_sheet"), "evidence outside the pool can't be selected")
	a.select_evidence("e_tram_tap")
	var grown: Array[String] = ["e_tram_tap", "e_lost_property_sheet"]
	a.set_evidence_pool(grown)
	_check(a.get_selected_evidence_id() == "e_tram_tap" and a.get_evidence_pool_ids() == grown, "a growing pool keeps the current selection")
	var shrunk: Array[String] = ["e_lost_property_sheet"]
	a.set_evidence_pool(shrunk)
	_check(a.get_selected_evidence_id() == "", "a selection that left the pool is cleared, never presented behind the player's back")


func _test_help_only_policy() -> void:
	var policy := ResolutionPolicy.new(false)
	for i in 3:
		policy.register_failed_commit()
	_check(policy.requires_assistance() and policy.get_run_resolution_result() == "independent", "help-only: three failures gate assistance but never raise the result")
	policy.accept_assistance()
	_check(policy.get_run_resolution_result() == "assisted", "help-only: accepted assistance raises it")
	var hinted := ResolutionPolicy.new(false)
	hinted.register_failed_commit()
	_check(hinted.get_run_resolution_result() == "independent", "help-only: a failure alone stays Independent")
	hinted.register_hint(1)
	_check(hinted.get_run_resolution_result() == "guided", "help-only: a level-1 hint makes it Guided")
	var debug := ResolutionPolicy.new()
	debug.register_failed_commit()
	_check(debug.get_run_resolution_result() == "guided", "debug semantics unchanged: one failure is Guided")


func _test_policy_mode_serialization() -> void:
	var policy := ResolutionPolicy.new(false)
	for i in 3:
		policy.register_failed_commit()
	var restored := ResolutionPolicy.new()
	_check(restored.load_dict(_json(policy.to_dict())) and not restored.failures_escalate_run_result(), "the mode round-trips (a help-only Independent result with 3 failures is valid)")
	_check(restored.to_dict() == policy.to_dict(), "a restored help-only policy serializes identically")
	var legacy: Dictionary = ResolutionPolicy.new().to_dict()
	legacy.erase("failures_escalate_run_result")
	var from_legacy := ResolutionPolicy.new(false)
	_check(from_legacy.load_dict(legacy) and from_legacy.failures_escalate_run_result(), "a dictionary without the key restores with the original semantics")
	var inconsistent: Dictionary = ResolutionPolicy.new().to_dict()
	inconsistent["failed_commits"] = 3
	inconsistent["formal_commits"] = 3
	_check(not ResolutionPolicy.new().load_dict(inconsistent), "in escalating mode, a result lower than its failures imply is still rejected")


func _test_b_hint_total_counts_own_targets_only() -> void:
	var session := DeductionSession.new(str(case_def["id"]))
	var b1 := PrototypeBController.new()
	var b2 := PrototypeBController.new()
	b1.start(case_def, null, _context(session, ["round_1"], []))
	b2.start(case_def, null, _context(session, ["round_2"], []))
	b1.reveal_next_hint()
	b1.reveal_next_hint()
	b2.reveal_next_hint()
	_check(int(b1.get_stats()["hints_used"]) == 2 and int(b2.get_stats()["hints_used"]) == 1, "each unit counts only its own targets' hints in a shared session")


func _test_a_snapshot_round_trip() -> void:
	var session := DeductionSession.new(str(case_def["id"]))
	var a := PrototypeAController.new()
	var context: Dictionary = _context(session, ["round_1"], ["e_tram_tap", "e_lost_property_sheet"])
	a.start(case_def, null, context)
	a.select_statement(1)
	a.select_evidence("e_tram_tap")
	a.present_evidence()  # wrong -> one failure + failed pair
	a.reveal_next_hint("st_oren_never_touched")
	a.select_statement(2)
	a.select_evidence("e_tram_tap")
	var restored := PrototypeAController.new()
	_check(restored.restore_snapshot(case_def, _json(a.to_snapshot()), null, context), "A restores from a JSON round trip")
	_check(_json(restored.to_snapshot()) == _json(a.to_snapshot()), "A's restored snapshot is identical")
	_check(restored.get_selected_evidence_id() == "e_tram_tap" and restored.get_current_statement_id() == "st_oren_never_touched", "selection survives")
	restored.select_statement(1)
	restored.select_evidence("e_tram_tap")
	_check(restored.is_known_failed_pair() and restored.present_evidence().get("reason", "") == PrototypeAController.REASON_DUPLICATE_ATTEMPT, "the failed pair is still blocked after restore")
	_check(restored.get_policy().get_current_unit_failures() == 1 and restored.get_hint_level("st_oren_never_touched") == 1, "budget and hint level survive")


func _test_b_snapshot_round_trip() -> void:
	var session := DeductionSession.new(str(case_def["id"]))
	var b := PrototypeBController.new()
	var context: Dictionary = _context(session, ["round_1"], ["e_door_log", "e_tram_tap", "e_route_note", "e_back_door_sighting"])
	b.start(case_def, null, context)
	for evidence_id in ["e_door_log", "e_tram_tap", "e_back_door_sighting"]:
		b.select_evidence(evidence_id)
	b.commit_theory()
	b.remove_evidence("e_back_door_sighting")
	var restored := PrototypeBController.new()
	_check(restored.restore_snapshot(case_def, _json(b.to_snapshot()), null, context), "B restores from a JSON round trip")
	_check(_json(restored.to_snapshot()) == _json(b.to_snapshot()), "B's restored snapshot is identical")
	restored.select_evidence("e_back_door_sighting")
	_check(restored.is_known_failed_theory(), "the failed theory signature survives")
	restored.remove_evidence("e_back_door_sighting")
	restored.select_evidence("e_route_note")
	_check(restored.commit_theory().get("category", "") == PrototypeBController.RESULT_THEORY_ACCEPTED, "a restored B continues exactly like the original")


func _test_c_snapshot_round_trip() -> void:
	var c := PrototypeCController.new()
	c.start(case_def, null, {"failures_escalate_run_result": false})
	c.place_event("tl_mara_leaves", "19:25")
	c.open_fact("c_mara_travel")
	var restored := PrototypeCController.new()
	_check(restored.restore_snapshot(case_def, _json(c.to_snapshot()), null, {"failures_escalate_run_result": false}), "a partial C restores")
	_check(restored.get_placement("tl_mara_leaves") == "19:25" and restored.has_opened_fact("c_mara_travel") and restored.get_placement("tl_badge_used") == "20:06", "placements, fixed anchors and facts survive")
	var solution: Dictionary = {"tl_mara_leaves": "19:35", "tl_cardigan_taken": "19:48", "tl_window_forced": "20:08", "tl_shredding_pickup": "20:10", "tl_cardigan_returned": "20:14"}
	for event_id in solution:
		c.place_event(event_id, solution[event_id])
	c.submit_timeline()
	c.select_claim_answer(false)
	var accepted := PrototypeCController.new()
	_check(accepted.restore_snapshot(case_def, _json(c.to_snapshot()), null, {}), "an accepted C restores")
	_check(accepted.is_accepted() and accepted.is_claim_phase() and accepted.get_selected_claim_answer() == "fits", "the accepted timeline and claim draft survive")
	_check(_json(accepted.to_snapshot()) == _json(c.to_snapshot()), "C's restored snapshot is identical")


func _test_snapshots_reject_malformed_data() -> void:
	var session := DeductionSession.new(str(case_def["id"]))
	var b := PrototypeBController.new()
	var context: Dictionary = _context(session, ["round_1"], ["e_door_log"])
	b.start(case_def, null, context)
	var good: Dictionary = _json(b.to_snapshot())
	var cases: Dictionary = {
		"wrong format": func(s: Dictionary) -> void: s["format"] = 99,
		"another case": func(s: Dictionary) -> void: s["case_id"] = "proto_y_lab_sample",
		"negative count": func(s: Dictionary) -> void: s["submission_count"] = -2,
		"over-full draft": func(s: Dictionary) -> void: s["drafts"] = [["a", "b", "c", "d"]],
		"malformed policy": func(s: Dictionary) -> void: s["policy"]["current_unit_phase"] = "limbo",
		"unknown round": func(s: Dictionary) -> void: s["round_ids"] = ["round_9"],
	}
	for label in cases:
		var broken: Dictionary = good.duplicate(true)
		(cases[label] as Callable).call(broken)
		var target := PrototypeBController.new()
		_check(not target.restore_snapshot(case_def, broken, null, context) and target.get_session() == null, "B rejects %s and stays untouched" % label)
	var c := PrototypeCController.new()
	c.start(case_def)
	var c_good: Dictionary = _json(c.to_snapshot())
	var c_cases: Dictionary = {
		"moved fixed event": func(s: Dictionary) -> void: s["placements"]["tl_badge_used"] = "19:25",
		"time outside the slots": func(s: Dictionary) -> void: s["placements"]["tl_mara_leaves"] = "03:00",
		"accepted without an accepted placement": func(s: Dictionary) -> void: s["accepted"] = true; s["timeline_resolved_by"] = "player",
		"resolved claim before the timeline": func(s: Dictionary) -> void: s["claim_resolved"] = true; s["claim_resolved_by"] = "player",
	}
	for label in c_cases:
		var broken: Dictionary = c_good.duplicate(true)
		(c_cases[label] as Callable).call(broken)
		var target := PrototypeCController.new()
		_check(not target.restore_snapshot(case_def, broken) and target.get_case_def().is_empty(), "C rejects %s and stays untouched" % label)


func _test_restore_records_nothing() -> void:
	var recorder := DeductionLabRecorder.new()
	recorder.start(str(case_def["id"]), "test")
	var a := PrototypeAController.new()
	a.start(case_def, recorder)
	a.select_statement(1)
	var count: int = recorder.get_events().size()
	var restored := PrototypeAController.new()
	restored.restore_snapshot(case_def, _json(a.to_snapshot()), recorder, {})
	_check(recorder.get_events().size() == count, "restoring a controller records nothing — restoring progress is not progress happening again")
