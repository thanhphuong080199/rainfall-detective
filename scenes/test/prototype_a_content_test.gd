extends SceneTree
## Content tests for Prototype A's optional data layer (Milestone 1.11 — see
## docs/prototype-a.md) on the real X/Y/Z prototype deduction cases, loaded
## through ContentDB and driven with the real DeductionEvaluator — exactly
## the pattern deduction_cases_test.gd already established for the base
## proof graph, extended here to case_def["prototype_a"]. Written once, in
## structural-role terms, and run against all three cases so the same script
## proves X, Y and Z share one Prototype A shape. Does NOT re-derive checks
## DeductionValidator/ContentValidator already own (references, translation
## completeness, single-evidence solvability, structural equivalence of the
## raw signature) — see validate_content.gd for those; this file asserts the
## PLAYER-FACING guarantees the milestone actually cares about. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_a_content_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]
const REQUIRED_ROLES := ["candidate_custody_denial", "candidate_staging_claim"]
const OPTIONAL_ROLE := "bystander_innocent_lie"
const TRUE_ROLE := "owner_alibi_statement"
const INCOMPLETE_ROLE := "owner_incomplete_statement"

var content_db: Node
var evaluator: Variant
var validator: Variant
var session_script: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	validator = load("res://scripts/deduction/deduction_validator.gd")
	session_script = load("res://scripts/deduction/deduction_session.gd")

	print("=== Prototype A content — X/Y/Z structural-role tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		if case_def.is_empty():
			_failures.append("%s should load through ContentDB" % case_id)
			continue
		_check(typeof(case_def.get("prototype_a")) == TYPE_DICTIONARY, "%s should declare a prototype_a data layer" % case_id)
		_test_role_coverage(case_def)
		_test_each_target_solvable_with_one_evidence_in_pool(case_def)
		_test_evidence_pool_available_from_the_start(case_def)
		_test_true_and_incomplete_statements_cannot_be_refuted(case_def)
		_test_completion_and_hint_translations_resolve(case_def)
	_test_prototype_a_structurally_equivalent_across_cases()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _id_by_role(case_def: Dictionary, section: String, role: String) -> String:
	for entry in case_def.get(section, []):
		if entry.get("structural_role", "") == role:
			return entry.get("id", "")
	_failures.append('%s has no %s with structural_role "%s"' % [case_def.get("id", ""), section, role])
	return ""


func _role_of_claim(case_def: Dictionary, claim_id: String) -> String:
	return str(evaluator.find_claim(case_def, claim_id).get("structural_role", ""))


func _all_round_data(case_def: Dictionary) -> Dictionary:
	var statements: Array = []
	var required: Array = []
	var optional: Array = []
	for pa_round in case_def.get("prototype_a", {}).get("rounds", []):
		statements.append_array(pa_round.get("statements", []))
		required.append_array(pa_round.get("required_refutations", []))
		optional.append_array(pa_round.get("optional_refutations", []))
	return {"statements": statements, "required": required, "optional": optional}


func _test_role_coverage(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var data: Dictionary = _all_round_data(case_def)
	var statement_roles: Array = (data["statements"] as Array).map(func(id: String) -> String: return _role_of_claim(case_def, id))
	var required_roles: Array = (data["required"] as Array).map(func(id: String) -> String: return _role_of_claim(case_def, id))
	var optional_roles: Array = (data["optional"] as Array).map(func(id: String) -> String: return _role_of_claim(case_def, id))

	_check(statement_roles.has(TRUE_ROLE), "%s: a true statement should appear in the testimony" % case_id)
	_check(statement_roles.has(INCOMPLETE_ROLE), "%s: an incomplete-but-true statement should appear" % case_id)
	_check(statement_roles.has(OPTIONAL_ROLE), "%s: the bystander's innocent lie should appear, as an optional contradiction" % case_id)
	_check((data["required"] as Array).size() == 2, "%s: there should be exactly two required contradictions across all rounds, got %d" % [case_id, (data["required"] as Array).size()])
	for role in REQUIRED_ROLES:
		_check(required_roles.has(role), "%s: the required contradictions should include the %s" % [case_id, role])
	_check(optional_roles == [OPTIONAL_ROLE], "%s: the only optional contradiction should be the bystander's innocent lie, got roles %s" % [case_id, optional_roles])
	_check((data["required"] as Array).size() + (data["optional"] as Array).size() < (data["statements"] as Array).size() * 2, "sanity")


## Every required/optional target must have at least one single-evidence
## refutes proof set, and submitting exactly that one item must actually
## succeed via the real evaluator — and that accepted item must be reachable
## from prototype_a.evidence_pool.
func _test_each_target_solvable_with_one_evidence_in_pool(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var pool: Array = evaluator.string_array(case_def.get("prototype_a", {}).get("evidence_pool", []))
	var data: Dictionary = _all_round_data(case_def)
	for claim_id in (data["required"] as Array) + (data["optional"] as Array):
		var claim: Dictionary = evaluator.find_claim(case_def, claim_id)
		var single_evidence_ids: Array = []
		for proof_set in claim.get("proof_sets", []):
			if proof_set.get("relation") != "refutes":
				continue
			var requires: Array = proof_set.get("requires", [])
			if requires.size() == 1 and not evaluator.find_evidence(case_def, requires[0]).is_empty():
				single_evidence_ids.append(requires[0])
		_check(not single_evidence_ids.is_empty(), "%s: claim \"%s\" (%s) needs at least one single-evidence refutes proof set for Prototype A" % [case_id, claim_id, _role_of_claim(case_def, claim_id)])
		for evidence_id in single_evidence_ids:
			_check(pool.has(evidence_id), "%s: accepted evidence \"%s\" for \"%s\" must be listed in prototype_a.evidence_pool" % [case_id, evidence_id, claim_id])
			var session = session_script.new(case_id)
			var result: Dictionary = evaluator.commit_attempt(case_def, session, claim_id, "refutes", [evidence_id])
			_check(result.get("category") == evaluator.VALID_REFUTATION, "%s: presenting \"%s\" alone against \"%s\" should be a valid refutation, got %s" % [case_id, evidence_id, claim_id, result.get("category")])


func _test_evidence_pool_available_from_the_start(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session = session_script.new(case_id)
	for evidence_id in evaluator.string_array(case_def.get("prototype_a", {}).get("evidence_pool", [])):
		_check(evaluator.is_evidence_available(case_def, session, evidence_id), "%s: evidence \"%s\" in the Prototype A pool must be available from the start (no required clue may be locked)" % [case_id, evidence_id])


## The true and incomplete statements must never be listed as refutation
## targets, and attempting to refute either with its own supporting evidence
## must never succeed (the engine enforces this structurally — see
## _relation_allowed — this proves it end to end for real content).
func _test_true_and_incomplete_statements_cannot_be_refuted(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var data: Dictionary = _all_round_data(case_def)
	for role in [TRUE_ROLE, INCOMPLETE_ROLE]:
		var claim_id: String = _id_by_role(case_def, "claims", role)
		_check(not (data["required"] as Array).has(claim_id) and not (data["optional"] as Array).has(claim_id), "%s: the %s must never be configured as a refutation target" % [case_id, role])
		var claim: Dictionary = evaluator.find_claim(case_def, claim_id)
		var supporting_evidence: Array = []
		for proof_set in claim.get("proof_sets", []):
			supporting_evidence.append_array(proof_set.get("requires", []))
		if not supporting_evidence.is_empty():
			var session = session_script.new(case_id)
			var result: Dictionary = evaluator.commit_attempt(case_def, session, claim_id, "refutes", [supporting_evidence[0]])
			_check(result.get("category") != evaluator.VALID_REFUTATION, "%s: the %s must never be validly \"refuted\" by any evidence" % [case_id, role])


func _test_completion_and_hint_translations_resolve(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var proto: Dictionary = case_def.get("prototype_a", {})
	var en: Translation = TranslationServer.get_translation_object("en")
	var vi: Translation = TranslationServer.get_translation_object("vi")
	var completion_key: String = str(proto.get("completion_text", ""))
	_check(String(en.get_message(completion_key)) != "" and String(vi.get_message(completion_key)) != "", "%s: completion_text \"%s\" must resolve in both en and vi" % [case_id, completion_key])
	for pa_round in proto.get("rounds", []):
		for claim_id in pa_round.get("hint_ladders", {}):
			for level_key in pa_round.get("hint_ladders", {}).get(claim_id, []):
				_check(String(en.get_message(level_key)) != "" and String(vi.get_message(level_key)) != "", "%s: hint level key \"%s\" must resolve in both en and vi" % [case_id, level_key])


## The structural-role SHAPE of prototype_a — evidence pool roles, and each
## round's statement/required/optional/hint-target roles — must be identical
## across X, Y and Z, exactly like the base credential_misuse_v2 graph.
## Filters structural_signature() (which already includes these lines, see
## DeductionValidator._prototype_a_signature_lines) down to just the
## "prototype_a:" entries, so a divergence here is unambiguous about WHICH
## layer regressed.
func _test_prototype_a_structurally_equivalent_across_cases() -> void:
	var reference: Array = []
	for line in validator.structural_signature(content_db.get_deduction_case(CASE_IDS[0])):
		if String(line).begins_with("prototype_a:"):
			reference.append(line)
	_check(reference.size() >= 4, "the prototype_a structural signature should describe the evidence pool and both rounds, not be trivially empty")
	for i in range(1, CASE_IDS.size()):
		var other: Array = []
		for line in validator.structural_signature(content_db.get_deduction_case(CASE_IDS[i])):
			if String(line).begins_with("prototype_a:"):
				other.append(line)
		_check(other == reference, "%s's prototype_a shape should exactly match %s's, got %s vs %s" % [CASE_IDS[i], CASE_IDS[0], other, reference])
