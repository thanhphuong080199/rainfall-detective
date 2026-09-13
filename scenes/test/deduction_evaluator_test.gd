extends SceneTree
## Focused unit tests for DeductionEvaluator + DeductionSession (Milestone
## 1.9 — see docs/deduction-system.md) against the hand-built fixture in
## deduction_fixtures.gd, never real content. Run with:
##   godot --headless --path . -s res://scenes/test/deduction_evaluator_test.gd
##
## Pins down the result-category contract (valid support/refutation,
## insufficient, irrelevant, compatible-but-not-proof, invalid input), that
## matching is order-independent and accepts alternate proof sets, that
## duplicates never count twice, that a derived deduction unlocks only on an
## explicit commit, hint ladders, deterministic reset and JSON round-trip.
##
## The deduction scripts reference no autoload, but are still load()ed rather
## than named by class_name — the same convention every other test here
## follows (docs/architecture.md, "A Godot quirk this project works around").

var evaluator: Variant
var session_script: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	session_script = load("res://scripts/deduction/deduction_session.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== DeductionEvaluator / DeductionSession — focused tests ===")
	_test_order_independent_matching()
	_test_alternate_proof_set()
	_test_insufficient_evidence()
	_test_irrelevant_evidence()
	_test_compatible_but_not_proof()
	_test_invalid_input()
	_test_duplicate_selection_is_rejected()
	_test_no_derived_deduction_before_commit()
	_test_commit_unlocks_derived_deduction()
	_test_final_conclusion_locked_until_prerequisites()
	_test_refutation_and_rule_out()
	_test_failed_commit_is_recorded_but_changes_nothing()
	_test_hint_ladder()
	_test_deterministic_reset()
	_test_json_round_trip()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_session() -> DeductionSession:
	return session_script.new("fx_case")


func _category(case_def: Dictionary, session: DeductionSession, claim_id: String, relation: String, selection: Variant) -> String:
	return evaluator.classify_attempt(case_def, session, claim_id, relation, selection).get("category", "")


func _test_order_independent_matching() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var first: Dictionary = evaluator.classify_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_away", "e_travel"])
	var shuffled: Dictionary = evaluator.classify_attempt(case_def, session, "ded_misused", "supports", ["e_travel", "e_log", "e_away"])
	_check(first.get("category") == evaluator.VALID_SUPPORT, "the primary proof set should be a valid support")
	_check(shuffled.get("category") == evaluator.VALID_SUPPORT, "selection order must not matter")
	_check(first.get("proof_set_id") == "ps_misused_primary" and shuffled.get("proof_set_id") == "ps_misused_primary", "both orders should match the same authored proof set")
	_check(not first.has("requires") and not String(first.get("reason", "")).contains("e_"), "a result must not reveal the proof set's items")


func _test_alternate_proof_set() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var alternate: Dictionary = evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_photo", "e_travel", "e_log"])
	_check(alternate.get("category") == evaluator.VALID_SUPPORT, "an alternate authored proof set should also be accepted")
	_check(alternate.get("proof_set_id") == "ps_misused_alternate", "the alternate proof should be reported as the alternate proof set")
	_check(session.is_supported("ded_misused"), "committing the alternate proof should resolve the claim")
	# Every item relevant: a valid proof plus corroborating relevant items is tolerated.
	_check(_category(case_def, _new_session(), "ded_misused", "supports", ["e_log", "e_away", "e_travel", "e_photo"]) == evaluator.VALID_SUPPORT, "a valid proof plus other RELEVANT items should still be accepted (documented extra-evidence policy)")


func _test_insufficient_evidence() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	_check(_category(case_def, session, "ded_misused", "supports", ["e_log", "e_travel"]) == evaluator.INSUFFICIENT_EVIDENCE, "a strict subset of a proof set should be insufficient")
	_check(_category(case_def, session, "ded_misused", "supports", ["e_log"]) == evaluator.INSUFFICIENT_EVIDENCE, "one item of a proof set should be insufficient")


func _test_irrelevant_evidence() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	_check(_category(case_def, session, "ded_misused", "supports", ["e_noise"]) == evaluator.IRRELEVANT_EVIDENCE, "an item that bears on the claim nowhere should be irrelevant")
	_check(_category(case_def, session, "ded_misused", "supports", ["e_log", "e_away", "e_travel", "e_noise"]) == evaluator.IRRELEVANT_EVIDENCE, "padding a valid proof with an irrelevant item must NOT pass — no 'select everything' exploit")


func _test_compatible_but_not_proof() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	_check(_category(case_def, session, "ded_misused", "supports", ["e_rumor"]) == evaluator.COMPATIBLE_NOT_PROOF, "an authored compatible observation should be compatible-but-not-proof")
	_check(_category(case_def, session, "ded_misused", "supports", ["e_away", "e_photo"]) == evaluator.COMPATIBLE_NOT_PROOF, "relevant items split across two alternate proofs should be compatible-but-not-proof, not insufficient")
	_check(_category(case_def, session, "ded_misused", "refutes", ["e_log", "e_away", "e_travel"]) == evaluator.COMPATIBLE_NOT_PROOF, "the right items with the wrong relation should not prove anything")
	_check(_category(case_def, session, "hyp_owner", "supports", ["e_log"]) == evaluator.COMPATIBLE_NOT_PROOF, "an observation ('the badge was used') must not prove its premature interpretation ('the owner did it')")


func _test_invalid_input() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var reasons := {
		"unknown_claim": evaluator.classify_attempt(case_def, session, "no_such_claim", "supports", ["e_log"]),
		"unknown_relation": evaluator.classify_attempt(case_def, session, "ded_misused", "proves", ["e_log"]),
		"empty_selection": evaluator.classify_attempt(case_def, session, "ded_misused", "supports", []),
		"malformed_item": evaluator.classify_attempt(case_def, session, "ded_misused", "supports", [42]),
		"unknown_item": evaluator.classify_attempt(case_def, session, "ded_misused", "supports", ["e_ghost"]),
		"unselectable_item": evaluator.classify_attempt(case_def, session, "ded_access", "supports", ["st_denial"]),
		"locked_item": evaluator.classify_attempt(case_def, session, "ded_access", "supports", ["e_followup"]),
		"session_case_mismatch": evaluator.classify_attempt(case_def, session_script.new("other_case"), "ded_misused", "supports", ["e_log"]),
	}
	for reason in reasons:
		var result: Dictionary = reasons[reason]
		_check(result.get("category") == evaluator.INVALID_INPUT and result.get("reason") == reason, "expected invalid_input/%s, got %s/%s" % [reason, result.get("category"), result.get("reason")])
	_check(_category(case_def, session, "ded_misused", "supports", "e_log") == evaluator.INVALID_INPUT, "a non-array selection should be invalid input")


func _test_duplicate_selection_is_rejected() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var result: Dictionary = evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_log", "e_away", "e_travel"])
	_check(result.get("category") == evaluator.INVALID_INPUT and result.get("reason") == "duplicate_item", "a duplicated item must be rejected, never counted twice")
	_check(not session.is_supported("ded_misused"), "a duplicate-item attempt must not resolve the claim even though its distinct items form a proof")


func _test_no_derived_deduction_before_commit() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var preview: Dictionary = evaluator.classify_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_away", "e_travel"])
	_check(preview.get("category") == evaluator.VALID_SUPPORT, "sanity: the selection is a valid proof")
	_check(not session.is_supported("ded_misused"), "classifying a valid selection must not unlock the deduction")
	_check(session.get_attempts().is_empty(), "classifying must not record an attempt")
	_check(not evaluator.is_evidence_available(case_def, session, "e_followup"), "evidence locked behind the deduction must stay locked until a commit")
	_check(evaluator.is_evidence_available(case_def, session, "e_custody"), "ungated custody evidence must be available before any deduction is committed")
	_check(_category(case_def, session, "ded_access", "supports", ["ded_misused", "e_custody"]) == evaluator.INVALID_INPUT, "an uncommitted deduction must not be usable as an input")


func _test_commit_unlocks_derived_deduction() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var unlocked: Array[String] = []
	session.deduction_unlocked.connect(func(claim_id: String) -> void: unlocked.append(claim_id))

	var result: Dictionary = evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_away", "e_travel"])
	_check(result.get("newly_resolved") == true and result.get("unlocked_deduction") == "ded_misused", "a valid commit should resolve and unlock the deduction")
	_check(result.get("newly_resolved_questions") == ["q_owner"], "the commit should report the question it resolved")
	_check(evaluator.is_evidence_available(case_def, session, "e_followup"), "evidence gated on the deduction should unlock")
	_check(unlocked == ["ded_misused"], "deduction_unlocked should fire exactly once")

	var again: Dictionary = evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_photo", "e_travel"])
	_check(again.get("category") == evaluator.VALID_SUPPORT and again.get("newly_resolved") == false, "re-proving a resolved claim is valid but resolves nothing new")
	_check(unlocked.size() == 1, "re-proving must not fire deduction_unlocked again")

	var access: Dictionary = evaluator.commit_attempt(case_def, session, "ded_access", "supports", ["e_custody", "ded_misused"])
	_check(access.get("category") == evaluator.VALID_SUPPORT and session.is_supported("ded_access"), "the committed deduction should now work as an input to the next step")


func _test_final_conclusion_locked_until_prerequisites() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var solved: Array[String] = []
	session.case_solved.connect(func(case_id: String) -> void: solved.append(case_id))

	_check(_category(case_def, session, "concl", "supports", ["ded_access"]) == evaluator.INVALID_INPUT, "the conclusion must be locked before its deduction is proven")
	_check(_category(case_def, session, "concl", "supports", ["e_log", "e_away", "e_travel"]) == evaluator.IRRELEVANT_EVIDENCE, "raw evidence can never prove the conclusion")
	evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_away", "e_travel"])
	_check(_category(case_def, session, "concl", "supports", ["ded_access"]) == evaluator.INVALID_INPUT, "the conclusion must stay locked with only the first step proven")
	_check(not evaluator.is_case_solved(case_def, session), "the case must not be solved yet")
	evaluator.commit_attempt(case_def, session, "ded_access", "supports", ["ded_misused", "e_custody"])
	var final: Dictionary = evaluator.commit_attempt(case_def, session, "concl", "supports", ["ded_access"])
	_check(final.get("category") == evaluator.VALID_SUPPORT and final.get("case_solved") == true, "the conclusion should resolve once its prerequisites are proven, solving the case")
	_check(final.get("unlocked_deduction") == "", "a conclusion is terminal — it unlocks no input")
	_check((evaluator.get_question_status(case_def, session).get("required_unresolved") as Array).is_empty(), "every required question should be resolved")
	evaluator.commit_attempt(case_def, session, "concl", "supports", ["ded_access"])
	_check(solved == ["fx_case"], "case_solved should fire exactly once")


func _test_refutation_and_rule_out() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_away", "e_travel"])
	var refuted: Dictionary = evaluator.commit_attempt(case_def, session, "st_denial", "refutes", ["e_custody"])
	_check(refuted.get("category") == evaluator.VALID_REFUTATION and session.get_claim_status("st_denial") == "refuted", "a contradiction should be a valid refutation")
	_check(refuted.get("unlocked_deduction") == "", "refuting a statement proves it false; it unlocks no deduction")
	var ruled_out: Dictionary = evaluator.commit_attempt(case_def, session, "hyp_owner", "rules_out", ["ded_misused"])
	_check(ruled_out.get("category") == evaluator.VALID_REFUTATION and session.get_claim_status("hyp_owner") == "refuted", "eliminating a hypothesis should be a valid refutation")
	_check(not evaluator.is_case_solved(case_def, session), "refuting claims does not by itself prove guilt or solve the case")


func _test_failed_commit_is_recorded_but_changes_nothing() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var categories: Array[String] = []
	session.proof_committed.connect(func(_claim: String, _relation: String, category: String) -> void: categories.append(category))
	var result: Dictionary = evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_travel"])
	_check(result.get("category") == evaluator.INSUFFICIENT_EVIDENCE and result.get("newly_resolved") == false, "a failed commit must not resolve")
	_check(session.get_resolved_claims().is_empty(), "a failed commit must leave no resolved claims")
	_check(session.get_attempts().size() == 1 and categories == [evaluator.INSUFFICIENT_EVIDENCE], "a failed commit is still recorded (blind-submission metric) and emits proof_committed with its category")


func _test_hint_ladder() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var revealed: Array[int] = []
	session.hint_revealed.connect(func(_target: String, level: int) -> void: revealed.append(level))
	var kinds: Array[String] = []
	for i in 4:
		var hint: Dictionary = evaluator.request_hint(case_def, session, "ded_misused")
		kinds.append(String(hint.get("kind", "")))
		_check(hint.get("level") == i + 1 and hint.get("exhausted") == false, "hint %d should be the next level, not exhausted" % (i + 1))
	_check(kinds == ["restate_question", "compare_categories", "evidence_group", "reveal_deduction"], "hints should progress through the four authored levels in order")
	var repeat: Dictionary = evaluator.request_hint(case_def, session, "ded_misused")
	_check(repeat.get("level") == 4 and repeat.get("exhausted") == true, "asking past the last level should repeat it, marked exhausted")
	_check(revealed == [1, 2, 3, 4], "hint_revealed should fire once per NEW level only")
	_check(not session.is_supported("ded_misused"), "a level-4 reveal is information only — it must not commit the deduction")
	_check(evaluator.request_hint(case_def, session, "st_denial").get("available") == false, "a claim with no ladder should report no hint available")


func _test_deterministic_reset() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	var fresh: Dictionary = _new_session().to_dict()
	_play_scripted_sequence(case_def, session)
	var played: Dictionary = session.to_dict()
	session.reset()
	_check(session.to_dict() == fresh, "reset() should return a session to exactly the fresh state")
	_check(not evaluator.is_evidence_available(case_def, session, "e_followup"), "reset should re-lock gated evidence")
	_play_scripted_sequence(case_def, session)
	_check(session.to_dict() == played, "replaying the same attempts after reset should reproduce the same state exactly")


func _test_json_round_trip() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session := _new_session()
	_play_scripted_sequence(case_def, session)
	var text: String = JSON.stringify(session.to_dict())
	var restored := _new_session()
	var signals: Array[int] = [0]
	restored.deduction_unlocked.connect(func(_id: String) -> void: signals[0] += 1)
	_check(restored.load_dict(JSON.parse_string(text)), "a JSON round-tripped session should load")
	_check(restored.get_resolved_claims() == session.get_resolved_claims(), "resolved claims should survive a JSON round trip")
	_check(restored.get_hint_level("ded_misused") == 2, "hint levels should survive a JSON round trip as integers")
	_check(restored.get_attempts() == session.get_attempts(), "the attempt log should survive a JSON round trip")
	_check(evaluator.is_evidence_available(case_def, restored, "e_followup"), "a restored session should unlock the same evidence")
	_check(signals[0] == 0, "loading must not re-emit deduction_unlocked")
	_check(not restored.load_dict({"claim_status": {"ded_misused": "maybe"}}), "a malformed session should be rejected")
	_check(restored.get_resolved_claims().is_empty(), "a rejected load should leave the session reset, not half-loaded")


func _play_scripted_sequence(case_def: Dictionary, session: DeductionSession) -> void:
	evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_noise"])
	evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_away", "e_travel"])
	evaluator.request_hint(case_def, session, "ded_misused")
	evaluator.request_hint(case_def, session, "ded_misused")
	evaluator.commit_attempt(case_def, session, "st_denial", "refutes", ["e_custody"])
	session.mark_evidence_opened("e_log")
