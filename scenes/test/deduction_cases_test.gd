extends SceneTree
## Integration test for the three non-canon prototype deduction cases in
## data/deductions/prototypes/ (Milestones 1.9 / 1.9.1 — see
## docs/deduction-prototype-cases.md). Loads them through the real ContentDB
## and drives the real DeductionEvaluator.
##
## Every check is written once, in STRUCTURAL-ROLE terms, and run against all
## three cases: the test looks up "the credential_use_record evidence" or "the
## candidate_exclusive_control deduction" by role, never by a case-specific id.
## That one walkthrough passing for X, Y and Z is itself evidence that the
## three surface stories share one proof graph. Run with:
##   godot --headless --path . -s res://scenes/test/deduction_cases_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]

## The strengthened credential_misuse_v2 proof graph, in role form: claim role
## -> its proof sets' sorted input roles. See docs/deduction-prototype-cases.md,
## "The shared proof graph".
const PROOF_ROLES := {
	"credential_misused": [["credential_use_record", "owner_alibi_primary", "travel_fact"], ["credential_use_record", "owner_alibi_alternate", "travel_fact"]],
	"candidate_had_opportunity": [["credential_custody"]],
	"candidate_exclusive_control": [["credential_custody", "credential_misused", "custody_continuity"]],
	"staging_deduction": [["physical_rule_or_reference", "staging_contradiction", "staging_sign"]],
	"final_conclusion": [["candidate_exclusive_control", "staging_deduction"]],
}
## Documented depth semantics (docs/deduction-system.md, "Inference depth"):
## intermediate deductions <= 2; the conclusion is the synthesis layer.
const CLAIM_DEPTHS := {"credential_misused": 1, "candidate_had_opportunity": 1, "candidate_exclusive_control": 2, "staging_deduction": 1, "final_conclusion": 3}
## Each alternative actor's hypothesis, and the authored fact its elimination
## must (transitively) rest on.
const ELIMINATED_BY := {"hypothesis_owner": "travel_fact", "hypothesis_bystander": "custody_continuity", "hypothesis_outsider": "physical_rule_or_reference"}

var content_db: Node
var evaluator: Variant
var validator: Variant
var timeline: Variant
var session_script: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	validator = load("res://scripts/deduction/deduction_validator.gd")
	timeline = load("res://scripts/deduction/timeline_evaluator.gd")
	session_script = load("res://scripts/deduction/deduction_session.gd")

	print("=== Prototype deduction cases — integration tests ===")
	_test_cases_load_and_validate()
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		if case_def.is_empty():
			continue  # Already reported by _test_cases_load_and_validate.
		_test_shape_and_non_canon(case_def)
		_test_primary_proof_path(case_def)
		_test_alternate_proof_path(case_def)
		_test_conclusion_locked_before_prerequisites(case_def)
		_test_final_proof_sufficiency(case_def)
		_test_removing_exclusive_control_breaks_the_proof(case_def)
		_test_alternative_actors_are_eliminated(case_def)
		_test_evidence_is_independently_discoverable(case_def)
		_test_staging_rule_is_taught(case_def)
		_test_wrong_attempts_are_classified(case_def)
		_test_statements_hypotheses_and_red_herring(case_def)
		_test_role_topology_and_depth(case_def)
		_test_timeline(case_def)
		_test_zone_verified_empty_before_window(case_def)
	_test_cases_are_structurally_equivalent()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


## The id of the entry in `section` with this structural_role.
func _id(case_def: Dictionary, section: String, role: String) -> String:
	for entry in case_def.get(section, []):
		if entry.get("structural_role", "") == role:
			return entry.get("id", "")
	_failures.append('%s has no %s with structural_role "%s"' % [case_def.get("id", ""), section, role])
	return ""


func _e(case_def: Dictionary, role: String) -> String:
	return _id(case_def, "evidence", role)


func _c(case_def: Dictionary, role: String) -> String:
	return _id(case_def, "claims", role)


func _role_of(case_def: Dictionary, item_id: String) -> String:
	for section in ["evidence", "claims"]:
		for entry in case_def.get(section, []):
			if entry.get("id", "") == item_id:
				return entry.get("structural_role", "")
	return ""


func _selection(case_def: Dictionary, evidence_roles: Array, claim_input_roles: Array = []) -> Array[String]:
	var selection: Array[String] = []
	for role in evidence_roles:
		selection.append(_e(case_def, role))
	for role in claim_input_roles:
		selection.append(_c(case_def, role))
	return selection


func _commit(case_def: Dictionary, session: DeductionSession, claim_role: String, relation: String, evidence_roles: Array, claim_input_roles: Array = []) -> Dictionary:
	return evaluator.commit_attempt(case_def, session, _c(case_def, claim_role), relation, _selection(case_def, evidence_roles, claim_input_roles))


func _category(case_def: Dictionary, session: DeductionSession, claim_role: String, relation: String, evidence_roles: Array, claim_input_roles: Array = []) -> String:
	return evaluator.classify_attempt(case_def, session, _c(case_def, claim_role), relation, _selection(case_def, evidence_roles, claim_input_roles)).get("category", "")


func _prove_misuse(case_def: Dictionary, session: DeductionSession) -> Dictionary:
	return _commit(case_def, session, "credential_misused", "supports", ["credential_use_record", "owner_alibi_primary", "travel_fact"])


func _prove_staging(case_def: Dictionary, session: DeductionSession) -> Dictionary:
	return _commit(case_def, session, "staging_deduction", "supports", ["staging_sign", "physical_rule_or_reference", "staging_contradiction"])


func _solve_after_first_step(case_def: Dictionary, session: DeductionSession) -> Dictionary:
	var control: Dictionary = _commit(case_def, session, "candidate_exclusive_control", "supports", ["credential_custody", "custody_continuity"], ["credential_misused"])
	var staged: Dictionary = _prove_staging(case_def, session)
	var final: Dictionary = _commit(case_def, session, "final_conclusion", "supports", [], ["candidate_exclusive_control", "staging_deduction"])
	_check(control.get("category") == evaluator.VALID_SUPPORT, "%s: D1 + custody + continuity should prove exclusive control" % case_def.get("id"))
	_check(staged.get("category") == evaluator.VALID_SUPPORT, "%s: staging sign + taught rule + contradiction should prove staging" % case_def.get("id"))
	return final


func _test_cases_load_and_validate() -> void:
	for case_id in CASE_IDS:
		_check(not content_db.get_deduction_case(case_id).is_empty(), "%s should load through ContentDB" % case_id)
	var result: Dictionary = content_db.get_last_validation_result()
	_check((result.get("errors", []) as Array).is_empty(), "all loaded content, deduction cases included, should validate with zero errors: %s" % [result.get("errors")])


func _test_shape_and_non_canon(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	_check(case_def.get("metadata", {}).get("canon") == false, "%s must be marked non-canon" % case_id)
	_check(case_def.get("metadata", {}).get("prototype") == true, "%s must be marked as prototype content" % case_id)
	var kinds: Dictionary = {}
	var required_deductions := 0
	for claim in case_def.get("claims", []):
		kinds[claim.get("kind")] = kinds.get(claim.get("kind"), 0) + 1
		if claim.get("kind") == "deduction" and claim.get("required", false) == true:
			required_deductions += 1
	# Milestone 1.9.1 counts: +1 evidence for custody continuity, +1 for the
	# separate taught physical rule, +1 non-required opportunity-only deduction.
	_check((case_def.get("suspects") as Array).size() == 3, "%s should have 3 suspects" % case_id)
	_check((case_def.get("evidence") as Array).size() == 11, "%s should have 11 evidence items" % case_id)
	_check(kinds.get("statement", 0) == 5, "%s should have 5 statements" % case_id)
	_check(kinds.get("deduction", 0) == 4 and required_deductions == 3, "%s should have 3 required intermediate deductions plus 1 opportunity-only distractor" % case_id)
	_check(kinds.get("conclusion", 0) == 1, "%s should have exactly 1 final conclusion" % case_id)
	_check((case_def.get("timeline", {}).get("events", []) as Array).size() == 7, "%s should have 7 timeline events" % case_id)
	var fixed_anchors: int = (case_def["timeline"]["constraints"] as Array).filter(func(constraint: Dictionary) -> bool: return constraint.get("type") == "fixed_time").size()
	_check(fixed_anchors == 2, "%s should have exactly 2 fixed temporal anchors" % case_id)
	for target in ["credential_misused", "candidate_exclusive_control", "staging_deduction", "final_conclusion"]:
		var hint: Dictionary = evaluator.request_hint(case_def, session_script.new(case_id), _c(case_def, target))
		_check(hint.get("available") == true and hint.get("kind") == "restate_question", "%s: the %s hint ladder should start by restating a question" % [case_id, target])


func _test_primary_proof_path(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session: DeductionSession = session_script.new(case_id)
	var first: Dictionary = _prove_misuse(case_def, session)
	var misused: Dictionary = evaluator.find_claim(case_def, _c(case_def, "credential_misused"))
	_check(first.get("category") == evaluator.VALID_SUPPORT, "%s: use record + primary alibi + travel fact should prove the credential was misused" % case_id)
	_check(first.get("proof_set_id") == misused["proof_sets"][0]["id"], "%s: that should match the first (primary) authored proof set" % case_id)
	_check(first.get("unlocked_deduction") == misused["id"], "%s: the first deduction should unlock on commit" % case_id)
	var final: Dictionary = _solve_after_first_step(case_def, session)
	_check(final.get("category") == evaluator.VALID_SUPPORT and final.get("case_solved") == true, "%s: the primary path should solve the case" % case_id)
	_check((evaluator.get_question_status(case_def, session).get("unresolved") as Array).is_empty(), "%s: every question should be resolved by the primary path" % case_id)
	_check(session.get_attempts().size() == 4, "%s: the primary path should take exactly four commits with no failed attempt" % case_id)


func _test_alternate_proof_path(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session: DeductionSession = session_script.new(case_id)
	var first: Dictionary = _commit(case_def, session, "credential_misused", "supports", ["credential_use_record", "owner_alibi_alternate", "travel_fact"])
	var misused: Dictionary = evaluator.find_claim(case_def, _c(case_def, "credential_misused"))
	_check(first.get("category") == evaluator.VALID_SUPPORT, "%s: the alternate alibi should also prove misuse" % case_id)
	_check(first.get("proof_set_id") == misused["proof_sets"][1]["id"], "%s: that should match the alternate authored proof set" % case_id)
	_check(_solve_after_first_step(case_def, session).get("case_solved") == true, "%s: the alternate path should also solve the case" % case_id)


func _test_conclusion_locked_before_prerequisites(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session: DeductionSession = session_script.new(case_id)
	var early: Dictionary = _commit(case_def, session, "final_conclusion", "supports", [], ["candidate_exclusive_control", "staging_deduction"])
	_check(early.get("category") == evaluator.INVALID_INPUT and early.get("reason") == "locked_item", "%s: the conclusion must be locked at the start" % case_id)
	_check(_commit(case_def, session, "final_conclusion", "supports", ["staging_sign", "staging_contradiction"]).get("category") == evaluator.IRRELEVANT_EVIDENCE, "%s: raw evidence must never prove the conclusion" % case_id)
	_check(_commit(case_def, session, "candidate_exclusive_control", "supports", ["credential_custody", "custody_continuity"], ["credential_misused"]).get("reason") == "locked_item", "%s: exclusive control can't be proven before misuse is (the misuse deduction is an uncommitted input)" % case_id)
	_prove_misuse(case_def, session)
	_prove_staging(case_def, session)
	var partial: Dictionary = _commit(case_def, session, "final_conclusion", "supports", [], ["candidate_exclusive_control", "staging_deduction"])
	_check(partial.get("reason") == "locked_item" and not session.is_solved(), "%s: the conclusion must stay locked until exclusive control is proven too" % case_id)
	_check(session.get_claim_status(_c(case_def, "final_conclusion")) == "", "%s: no failed attempt may resolve the conclusion" % case_id)


## Access, opportunity, staging or a proven lie must never be enough to name
## the actor; only D2's exclusive control (+ D3) resolves the conclusion.
func _test_final_proof_sufficiency(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session: DeductionSession = session_script.new(case_id)
	_prove_misuse(case_def, session)
	_check(_category(case_def, session, "candidate_exclusive_control", "supports", ["credential_custody"], ["credential_misused"]) == evaluator.INSUFFICIENT_EVIDENCE, "%s: custody (access/opportunity) + D1 without the continuity record is not exclusive control" % case_id)
	_check(_category(case_def, session, "candidate_exclusive_control", "supports", ["custody_continuity"], ["credential_misused"]) == evaluator.INSUFFICIENT_EVIDENCE, "%s: the continuity record + D1 without custody is not exclusive control" % case_id)
	_check(_category(case_def, session, "candidate_exclusive_control", "supports", ["credential_custody", "custody_continuity"]) == evaluator.INSUFFICIENT_EVIDENCE, "%s: exclusive-control evidence without D1 (that the credential was misused) is insufficient" % case_id)
	var opportunity: Dictionary = _commit(case_def, session, "candidate_had_opportunity", "supports", ["credential_custody"])
	_check(opportunity.get("category") == evaluator.VALID_SUPPORT, "%s: the opportunity-only deduction is true and provable" % case_id)
	_check(_category(case_def, session, "candidate_exclusive_control", "supports", ["custody_continuity"], ["credential_misused", "candidate_had_opportunity"]) == evaluator.COMPATIBLE_NOT_PROOF, "%s: the opportunity deduction can't stand in for the custody record" % case_id)
	_prove_staging(case_def, session)

	_check(_category(case_def, session, "final_conclusion", "supports", [], ["staging_deduction"]) == evaluator.INSUFFICIENT_EVIDENCE, "%s: staging alone cannot identify who acted" % case_id)
	_check(_category(case_def, session, "final_conclusion", "supports", [], ["candidate_had_opportunity", "staging_deduction"]) == evaluator.COMPATIBLE_NOT_PROOF, "%s: opportunity + staging cannot identify who acted" % case_id)
	_check(_category(case_def, session, "final_conclusion", "supports", [], ["credential_misused", "candidate_had_opportunity", "staging_deduction"]) == evaluator.COMPATIBLE_NOT_PROOF, "%s: D1 + an opportunity-only claim + D3 cannot resolve the conclusion" % case_id)
	var proven: Array[String] = [_c(case_def, "credential_misused"), _c(case_def, "candidate_had_opportunity"), _c(case_def, "staging_deduction")]
	var accepted: Array = []
	for mask in range(1, 1 << proven.size()):
		var selection: Array[String] = []
		for i in proven.size():
			if mask & (1 << i):
				selection.append(proven[i])
		if evaluator.is_valid_category(evaluator.classify_attempt(case_def, session, _c(case_def, "final_conclusion"), "supports", selection).get("category", "")):
			accepted.append(selection)
	_check(accepted.is_empty(), "%s: no combination of the proven deductions other than exclusive control may resolve the conclusion: %s" % [case_id, accepted])

	_check(_commit(case_def, session, "candidate_custody_denial", "refutes", ["credential_custody"]).get("category") == evaluator.VALID_REFUTATION, "%s: the candidate's denial is provably a lie" % case_id)
	var lie_as_input: Dictionary = evaluator.classify_attempt(case_def, session, _c(case_def, "final_conclusion"), "supports", [_c(case_def, "candidate_custody_denial"), _c(case_def, "staging_deduction")])
	_check(lie_as_input.get("category") == evaluator.INVALID_INPUT and lie_as_input.get("reason") == "unselectable_item", "%s: a proven lie is not an input — lying alone can't identify the actor" % case_id)
	_check(session.get_claim_status(_c(case_def, "final_conclusion")) == "", "%s: none of those attempts may resolve the conclusion" % case_id)

	_check(_commit(case_def, session, "candidate_exclusive_control", "supports", ["credential_custody", "custody_continuity"], ["credential_misused"]).get("category") == evaluator.VALID_SUPPORT, "%s: the complete exclusive-control proof is accepted" % case_id)
	var final: Dictionary = _commit(case_def, session, "final_conclusion", "supports", [], ["candidate_exclusive_control", "staging_deduction"])
	_check(final.get("category") == evaluator.VALID_SUPPORT and session.get_claim_status(_c(case_def, "final_conclusion")) == "supported", "%s: the complete strengthened proof resolves the conclusion" % case_id)


func _without_evidence(case_def: Dictionary, roles: Array) -> Dictionary:
	var copy: Dictionary = case_def.duplicate(true)
	copy["evidence"] = (copy["evidence"] as Array).filter(func(evidence: Dictionary) -> bool: return not roles.has(evidence.get("structural_role", "")))
	return copy


func _provable(case_def: Dictionary, claim_id: String) -> bool:
	return (validator.compute_reachability(case_def).get("supported", {}) as Dictionary).has(claim_id)


## Removing the exclusive-control evidence (or D2's proof) must leave the
## conclusion unprovable, while non-load-bearing items (an alternate alibi, the
## red herring) must not — so the check can't pass vacuously.
func _test_removing_exclusive_control_breaks_the_proof(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var final_id: String = _c(case_def, "final_conclusion")
	_check(_provable(case_def, final_id), "%s: sanity — the unmodified case proves its conclusion" % case_id)
	for role in ["custody_continuity", "credential_custody", "physical_rule_or_reference"]:
		_check(not _provable(_without_evidence(case_def, [role]), final_id), "%s: without %s the conclusion must be unprovable" % [case_id, role])
	var no_control: Dictionary = case_def.duplicate(true)
	for claim in no_control["claims"]:
		if claim.get("structural_role") == "candidate_exclusive_control":
			claim["proof_sets"] = []
	_check(not _provable(no_control, final_id), "%s: without the exclusive-control deduction the conclusion must be unprovable, even with opportunity + staging proven" % case_id)
	_check(_provable(_without_evidence(case_def, ["owner_alibi_alternate"]), final_id) and _provable(_without_evidence(case_def, ["red_herring"]), final_id), "%s: the alternate alibi and the red herring are not load-bearing" % case_id)
	_check(not _provable(_without_evidence(case_def, ["owner_alibi_primary", "owner_alibi_alternate"]), final_id), "%s: without any owner alibi the conclusion must be unprovable" % case_id)


## Every input role a claim's proof sets rest on, transitively through
## deductions and across alternate proof sets.
func _grounds(case_def: Dictionary, claim_id: String, out: Dictionary = {}) -> Dictionary:
	for proof_set in evaluator.find_claim(case_def, claim_id).get("proof_sets", []):
		for item_id in proof_set.get("requires", []):
			if out.has(_role_of(case_def, item_id)):
				continue
			out[_role_of(case_def, item_id)] = true
			if not evaluator.find_claim(case_def, item_id).is_empty():
				_grounds(case_def, item_id, out)
	return out


func _test_alternative_actors_are_eliminated(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var refutable: Dictionary = validator.compute_reachability(case_def).get("refuted", {})
	for hypothesis_role in ELIMINATED_BY:
		var hypothesis_id: String = _c(case_def, hypothesis_role)
		_check(refutable.has(hypothesis_id) and _grounds(case_def, hypothesis_id).has(ELIMINATED_BY[hypothesis_role]), "%s: %s must be eliminable, and its elimination must rest on %s" % [case_id, hypothesis_role, ELIMINATED_BY[hypothesis_role]])
	var conclusion_grounds: Dictionary = _grounds(case_def, _c(case_def, "final_conclusion"))
	for role in ["travel_fact", "custody_continuity", "credential_custody", "physical_rule_or_reference"]:
		_check(conclusion_grounds.has(role), "%s: the final conclusion must rest on %s (it eliminates an alternative actor)" % [case_id, role])
	var truth: Dictionary = case_def.get("ground_truth", {})
	_check(_id(case_def, "suspects", "actual_culprit") == truth.get("culprit") and _id(case_def, "suspects", "apparent_suspect") == truth.get("credential_owner"), "%s: ground truth should name the actual culprit and the credential owner by role" % case_id)


func _test_evidence_is_independently_discoverable(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var all_ids: Array[String] = []
	var gated: Array[String] = []
	for evidence in case_def.get("evidence", []):
		all_ids.append(evidence.get("id", ""))
		if not (evidence.get("unlock_requires", []) as Array).is_empty():
			gated.append(evidence.get("id", ""))
	_check(gated.is_empty(), "%s: no evidence may be locked behind a deduction: %s" % [case_id, gated])
	var session: DeductionSession = session_script.new(case_id)
	var before: Array[String] = evaluator.get_available_evidence_ids(case_def, session)
	_check(before == all_ids, "%s: every evidence item, custody and continuity included, must be available from the start" % case_id)
	_check(_prove_misuse(case_def, session).get("unlocked_deduction") == _c(case_def, "credential_misused") and evaluator.get_available_evidence_ids(case_def, session) == before, "%s: committing D1 unlocks the deduction but must not make any evidence appear" % case_id)
	var reach: Dictionary = validator.compute_reachability(case_def)
	_check(validator.find_dependency_cycles(case_def).is_empty() and (reach.get("evidence") as Dictionary).size() == all_ids.size(), "%s: the graph must be acyclic with every evidence item reachable" % case_id)
	for role in ["candidate_exclusive_control", "staging_deduction", "final_conclusion"]:
		_check((reach.get("supported") as Dictionary).has(_c(case_def, role)), "%s: descendant claim %s must stay reachable" % [case_id, role])


func _test_staging_rule_is_taught(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session: DeductionSession = session_script.new(case_id)
	_check(_category(case_def, session, "staging_deduction", "supports", ["staging_sign", "staging_contradiction"]) == evaluator.INSUFFICIENT_EVIDENCE, "%s: the contradiction without the taught rule must not prove staging" % case_id)
	_check(_category(case_def, session, "staging_deduction", "supports", ["physical_rule_or_reference", "staging_contradiction"]) == evaluator.INSUFFICIENT_EVIDENCE, "%s: the rule + contradiction without the staging sign must not prove staging" % case_id)
	_check(_category(case_def, session, "candidate_staging_claim", "refutes", ["staging_contradiction"]) == evaluator.INSUFFICIENT_EVIDENCE, "%s: refuting the staging story needs the taught rule too" % case_id)
	var rule: Dictionary = evaluator.find_evidence(case_def, _e(case_def, "physical_rule_or_reference"))
	_check(rule.get("tags", []) == ["physics"] and rule.get("certainty") == "fixed", "%s: the physical rule is its own fixed, in-case reference item" % case_id)


func _test_wrong_attempts_are_classified(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session: DeductionSession = session_script.new(case_id)
	_check(_commit(case_def, session, "credential_misused", "supports", ["credential_use_record", "travel_fact"]).get("category") == evaluator.INSUFFICIENT_EVIDENCE, "%s: the use record + travel fact without an alibi is insufficient" % case_id)
	_check(_commit(case_def, session, "credential_misused", "supports", ["credential_use_record", "owner_alibi_primary", "travel_fact", "red_herring"]).get("category") == evaluator.IRRELEVANT_EVIDENCE, "%s: padding the proof with the red herring is irrelevant" % case_id)
	_check(_commit(case_def, session, "credential_misused", "supports", ["owner_alibi_primary", "owner_alibi_alternate"]).get("category") == evaluator.COMPATIBLE_NOT_PROOF, "%s: two alibis without the use record are compatible, not proof" % case_id)
	_check(_commit(case_def, session, "hypothesis_owner", "supports", ["credential_use_record"]).get("category") == evaluator.COMPATIBLE_NOT_PROOF, "%s: 'the credential was used' must not prove 'its owner did it'" % case_id)
	var duplicate: Dictionary = evaluator.commit_attempt(case_def, session, _c(case_def, "credential_misused"), "supports", [_e(case_def, "credential_use_record"), _e(case_def, "credential_use_record"), _e(case_def, "owner_alibi_primary"), _e(case_def, "travel_fact")])
	_check(duplicate.get("reason") == "duplicate_item", "%s: a duplicated item is invalid input" % case_id)
	_check(session.get_resolved_claims().is_empty(), "%s: none of those attempts may resolve anything" % case_id)


func _test_statements_hypotheses_and_red_herring(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session: DeductionSession = session_script.new(case_id)
	_check(_commit(case_def, session, "hypothesis_bystander", "rules_out", ["red_herring_explanation"]).get("category") == evaluator.INSUFFICIENT_EVIDENCE, "%s: explaining the red herring alone doesn't eliminate the bystander yet" % case_id)
	_prove_misuse(case_def, session)
	_solve_after_first_step(case_def, session)

	var expectations := [
		["owner_alibi_statement", "supports", ["owner_alibi_primary"], [], evaluator.VALID_SUPPORT, "the owner's truthful statement is supported"],
		["owner_incomplete_statement", "refutes", ["credential_custody"], [], evaluator.COMPATIBLE_NOT_PROOF, "the owner's incomplete statement can't be proven false"],
		["owner_incomplete_statement", "supports", ["credential_custody"], [], evaluator.VALID_SUPPORT, "the owner's incomplete statement is true as far as it goes"],
		["candidate_custody_denial", "refutes", ["credential_custody"], [], evaluator.VALID_REFUTATION, "the candidate's custody denial is refuted"],
		["candidate_staging_claim", "refutes", ["physical_rule_or_reference", "staging_contradiction"], [], evaluator.VALID_REFUTATION, "the candidate's intrusion story is refuted by the taught rule + contradiction"],
		["candidate_staging_claim", "supports", ["staging_sign"], [], evaluator.COMPATIBLE_NOT_PROOF, "the staged sign is compatible with the candidate's story but doesn't prove it"],
		["bystander_innocent_lie", "refutes", ["red_herring_explanation"], [], evaluator.VALID_REFUTATION, "the bystander's innocent lie is refuted"],
		["red_herring_explained", "explains", ["red_herring", "red_herring_explanation"], [], evaluator.VALID_SUPPORT, "the red herring has a truthful explanation"],
		["hypothesis_owner", "rules_out", [], ["credential_misused"], evaluator.VALID_REFUTATION, "the owner hypothesis is eliminated"],
		["hypothesis_bystander", "rules_out", ["red_herring"], [], evaluator.COMPATIBLE_NOT_PROOF, "the red herring alone can't eliminate the bystander"],
		["hypothesis_bystander", "rules_out", ["red_herring_explanation"], ["candidate_exclusive_control"], evaluator.VALID_REFUTATION, "the bystander hypothesis is eliminated"],
		["hypothesis_outsider", "rules_out", [], ["staging_deduction"], evaluator.VALID_REFUTATION, "the outsider hypothesis is eliminated"],
	]
	for expectation in expectations:
		var result: Dictionary = _commit(case_def, session, expectation[0], expectation[1], expectation[2], expectation[3])
		_check(result.get("category") == expectation[4], "%s: %s (got %s)" % [case_id, expectation[5], result.get("category")])
	var lie: Dictionary = evaluator.find_claim(case_def, _c(case_def, "bystander_innocent_lie"))
	_check(lie.get("veracity") == "deceptive" and lie.get("lie_motive") == "unrelated_to_crime", "%s: the bystander's lie must be marked as unrelated to the crime" % case_id)
	_check(evaluator.find_evidence(case_def, _e(case_def, "red_herring")).get("misleading") == true, "%s: the red herring must be marked misleading" % case_id)
	_check(evaluator.find_claim(case_def, _c(case_def, "owner_incomplete_statement")).get("veracity") == "incomplete", "%s: the owner's incomplete statement must be marked incomplete, not false" % case_id)


## Role-by-role topology, proof-set cardinality and depth — the parity the
## signature comparison implies, spelled out so a divergence names the claim.
func _test_role_topology_and_depth(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	for claim_role in PROOF_ROLES:
		var claim: Dictionary = evaluator.find_claim(case_def, _c(case_def, claim_role))
		var actual: Array = []
		var depths: Array = []
		for proof_set in claim.get("proof_sets", []):
			var roles: Array = []
			for item_id in proof_set.get("requires", []):
				roles.append(_role_of(case_def, item_id))
			roles.sort()
			actual.append(roles)
			depths.append(validator.proof_set_depth(case_def, proof_set))
		_check(actual == PROOF_ROLES[claim_role], "%s: %s proof sets should be %s, got %s" % [case_id, claim_role, PROOF_ROLES[claim_role], actual])
		_check(depths.all(func(depth: int) -> bool: return depth == CLAIM_DEPTHS[claim_role]), "%s: every %s proof path (primary and alternate) should be depth %d, got %s" % [case_id, claim_role, CLAIM_DEPTHS[claim_role], depths])
	_check((validator.inference_depths(case_def).values() as Array).max() == validator.MAX_INFERENCE_DEPTH, "%s: the deepest intermediate deduction should sit exactly at the documented maximum" % case_id)


func _test_timeline(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var solution: Dictionary = case_def["ground_truth"]["solution_timeline"]
	var result: Dictionary = timeline.evaluate(case_def, solution)
	_check(result.get("category") == timeline.CONSISTENT, "%s: the authored solution timeline should be consistent: %s" % [case_id, result])
	var lie_id: String = _c(case_def, "bystander_innocent_lie")
	var lie_constraints: Array = (case_def["timeline"]["constraints"] as Array).filter(func(constraint: Dictionary) -> bool: return constraint.get("source") == lie_id)
	_check(lie_constraints.size() == 1 and (result.get("violated_optional") as Array).has(lie_constraints[0].get("id")), "%s: the true timeline should contradict the bystander's claimed time" % case_id)

	var departure: String = _timeline_event(case_def, "owner_departure")
	var alternate: Dictionary = solution.duplicate()
	alternate[departure] = _shift(solution[departure], -5)
	_check(alternate != solution and timeline.evaluate(case_def, alternate).get("category") == timeline.CONSISTENT, "%s: a different placement allowed by the evidence (owner leaving 5 minutes earlier) must also be accepted" % case_id)

	var anchor: String = _timeline_event(case_def, "credential_use_anchor")
	var broken: Dictionary = solution.duplicate()
	broken[anchor] = _shift(solution[anchor], 1)
	_check(timeline.evaluate(case_def, broken).get("category") == timeline.INCONSISTENT, "%s: moving a fixed anchor must make the timeline inconsistent" % case_id)


func _timeline_event(case_def: Dictionary, role: String) -> String:
	for event in case_def["timeline"]["events"]:
		if event.get("structural_role") == role:
			return event.get("id", "")
	_failures.append('%s has no timeline event with structural_role "%s"' % [case_def.get("id", ""), role])
	return ""


func _shift(time: String, minutes: int) -> String:
	var total: int = timeline.parse_time(time) + minutes
	return "%02d:%02d" % [total / 60, total % 60]


## Milestone 1.10, Phase 0.5 regression: R3's zone-closure evidence used to
## say only "nobody else enters or leaves" during a monitored window, which
## is consistent with a third party having already been inside the zone
## BEFORE the window started (never recorded entering or leaving it at all)
## — an unexplained alternative to the candidate that neither the camera log
## nor the old proof-obligation tables actually ruled out. See
## docs/deduction-prototype-cases.md, "0.1 What Milestone 1.10 audited and
## closed". The fix is text-only (localization/strings.csv): the
## custody_continuity evidence now states the last-seen check itself finds
## the zone empty of people, immediately before the camera's window begins,
## so an already-inside actor is no longer a viable unexplained alternative.
func _test_zone_verified_empty_before_window(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var evidence: Dictionary = evaluator.find_evidence(case_def, _e(case_def, "custody_continuity"))
	var text_key: String = str(evidence.get("text", ""))
	var en_translation: Translation = TranslationServer.get_translation_object("en")
	var vi_translation: Translation = TranslationServer.get_translation_object("vi")
	var en_text: String = String(en_translation.get_message(text_key)) if en_translation != null else ""
	var vi_text: String = String(vi_translation.get_message(text_key)) if vi_translation != null else ""
	_check(en_text.to_lower().contains("empty"), '%s: the zone-closure evidence ("%s") English text must state the zone was found EMPTY of people before the monitored window begins, not just that nobody crossed the entrance during it — got: %s' % [case_id, text_key, en_text])
	_check(vi_text.contains("trống"), '%s: the zone-closure evidence ("%s") Vietnamese text must state the zone was found empty ("trống") before the monitored window begins — got: %s' % [case_id, text_key, vi_text])
	# The empty-zone fact must be independently available (never unlocked by
	# the conclusion it helps prove) — see docs/deduction-system.md,
	# "Evidence availability".
	_check((evidence.get("unlock_requires", []) as Array).is_empty(), "%s: the zone-closure evidence must have no unlock_requires — the empty-zone fact must be independently available from the start" % case_id)


func _test_cases_are_structurally_equivalent() -> void:
	var reference: Array[String] = validator.structural_signature(content_db.get_deduction_case(CASE_IDS[0]))
	_check(reference.size() > 50, "the structural signature should describe the whole proof graph, not be trivially empty")
	for i in range(1, CASE_IDS.size()):
		var other: Array[String] = validator.structural_signature(content_db.get_deduction_case(CASE_IDS[i]))
		_check(other == reference, "%s should have exactly the same structural signature as %s" % [CASE_IDS[i], CASE_IDS[0]])
	var cases: Array = []
	for case_id in CASE_IDS:
		cases.append(content_db.get_deduction_case(case_id))
	var errors: Array[String] = []
	validator.validate_structural_equivalence(cases, errors)
	_check(errors.is_empty() and cases.all(func(case_def: Dictionary) -> bool: return case_def.get("metadata", {}).get("structural_template") == "credential_misuse_v2"), "all three cases should share credential_misuse_v2 with no equivalence errors: %s" % [errors])
