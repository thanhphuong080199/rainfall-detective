extends SceneTree
## Content tests for Prototype B's optional data layer (Milestone 1.12 — see
## docs/prototype-b.md) on the real X/Y/Z prototype deduction cases, loaded
## through ContentDB and driven with the real DeductionEvaluator — exactly
## the pattern prototype_a_content_test.gd already established. Written once,
## in structural-role terms, and run against all three cases so the same
## script proves X, Y and Z share one Prototype B shape. Does NOT re-derive
## checks DeductionValidator/ContentValidator already own (references,
## translation completeness, structural equivalence of the raw signature) —
## see validate_content.gd for those; this file asserts the PLAYER-FACING
## guarantees the milestone actually cares about, plus the audited D1/D3
## target separation from Prototype A (docs/prototype-b.md, "Content audit").
## Run with:
##   godot --headless --path . -s res://scenes/test/prototype_b_content_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]
const D1_ROLE := "credential_misused"
const D3_ROLE := "staging_deduction"

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

	print("=== Prototype B content — X/Y/Z structural-role tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		if case_def.is_empty():
			_failures.append("%s should load through ContentDB" % case_id)
			continue
		_check(typeof(case_def.get("prototype_b")) == TYPE_DICTIONARY, "%s should declare a prototype_b data layer" % case_id)
		_test_exactly_two_rounds_targeting_d1_and_d3(case_def)
		_test_d1_primary_and_alternate_paths_solve_with_three_slots(case_def)
		_test_d3_requires_every_authored_clue(case_def)
		_test_no_proper_subset_resolves_either_target(case_def)
		_test_evidence_pool_available_from_the_start(case_def)
		_test_translations_resolve(case_def)
		_test_prototype_a_target_does_not_solve_prototype_b_d3(case_def)
	_test_prototype_b_structurally_equivalent_across_cases()

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


func _round_for_role(case_def: Dictionary, role: String) -> Dictionary:
	var target_id: String = _id_by_role(case_def, "claims", role)
	for pb_round in case_def.get("prototype_b", {}).get("rounds", []):
		if str(pb_round.get("target", "")) == target_id:
			return pb_round
	_failures.append('%s has no prototype_b round targeting the %s' % [case_def.get("id", ""), role])
	return {}


func _test_exactly_two_rounds_targeting_d1_and_d3(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var rounds: Array = case_def.get("prototype_b", {}).get("rounds", [])
	_check(rounds.size() == 2, "%s: Prototype B should declare exactly two rounds, got %d" % [case_id, rounds.size()])
	var d1_round: Dictionary = _round_for_role(case_def, D1_ROLE)
	var d3_round: Dictionary = _round_for_role(case_def, D3_ROLE)
	_check(not d1_round.is_empty(), "%s: round 1 should target the credential_misused deduction (D1)" % case_id)
	_check(not d3_round.is_empty(), "%s: round 2 should target the staging_deduction (D3)" % case_id)
	_check(str(d1_round.get("relation", "")) == "supports" and str(d3_round.get("relation", "")) == "supports", "%s: both rounds' relation should be \"supports\" (connecting clues INTO a deduction)" % case_id)


## D1's proof sets are 3 items either way (primary: use record + primary
## alibi + travel fact; alternate: use record + alternate alibi + travel
## fact). Round 1's slot_count must be 3, and submitting either full path
## must succeed via the real evaluator.
func _test_d1_primary_and_alternate_paths_solve_with_three_slots(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var target_id: String = _id_by_role(case_def, "claims", D1_ROLE)
	var pb_round: Dictionary = _round_for_role(case_def, D1_ROLE)
	_check(int(pb_round.get("slot_count", 0)) == 3, "%s: D1's round should declare slot_count 3, got %s" % [case_id, pb_round.get("slot_count", 0)])

	var claim: Dictionary = evaluator.find_claim(case_def, target_id)
	var proof_sets: Array = claim.get("proof_sets", [])
	_check(proof_sets.size() >= 2, "%s: D1 should have both a primary and an alternate proof path" % case_id)
	for proof_set in proof_sets:
		var requires: Array = proof_set.get("requires", [])
		_check(requires.size() == 3, "%s: every D1 proof path must have exactly 3 items to match the round's slot_count, got %d for \"%s\"" % [case_id, requires.size(), proof_set.get("id", "")])
		var session = session_script.new(case_id)
		var result: Dictionary = evaluator.commit_attempt(case_def, session, target_id, "supports", requires)
		_check(result.get("category") == evaluator.VALID_SUPPORT, "%s: submitting proof path \"%s\" %s should validly support D1, got %s" % [case_id, proof_set.get("id", ""), requires, result.get("category")])


## D3's single proof set needs all 3 authored clues — none of the three
## 2-item subsets may already resolve it (this is the audited, deliberate
## reason Round 2 uses 3 slots rather than the milestone brief's illustrative
## 2 — see docs/prototype-b.md, "Content audit: why D3 needs 3 slots").
func _test_d3_requires_every_authored_clue(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var target_id: String = _id_by_role(case_def, "claims", D3_ROLE)
	var pb_round: Dictionary = _round_for_role(case_def, D3_ROLE)
	_check(int(pb_round.get("slot_count", 0)) == 3, "%s: D3's round should declare slot_count 3 (an audited departure from the brief's illustrative 2 — see docs/prototype-b.md), got %s" % [case_id, pb_round.get("slot_count", 0)])

	var claim: Dictionary = evaluator.find_claim(case_def, target_id)
	var proof_sets: Array = claim.get("proof_sets", [])
	_check(proof_sets.size() == 1, "%s: D3 should have exactly one authored proof set (no alternate) requiring all 3 clues" % case_id)
	var requires: Array = proof_sets[0].get("requires", [])
	_check(requires.size() == 3, "%s: D3's proof set should require exactly 3 items, got %d" % [case_id, requires.size()])

	var session = session_script.new(case_id)
	var full_result: Dictionary = evaluator.commit_attempt(case_def, session, target_id, "supports", requires)
	_check(full_result.get("category") == evaluator.VALID_SUPPORT, "%s: submitting all 3 authored D3 clues should validly support it, got %s" % [case_id, full_result.get("category")])

	for i in requires.size():
		var pair: Array = requires.duplicate()
		pair.remove_at(i)
		var pair_session = session_script.new(case_id)
		var pair_result: Dictionary = evaluator.commit_attempt(case_def, pair_session, target_id, "supports", pair)
		_check(pair_result.get("category") != evaluator.VALID_SUPPORT, "%s: D3 must NOT be solvable by only 2 of its 3 clues (missing \"%s\") — got %s for %s" % [case_id, requires[i], pair_result.get("category"), pair])


## Anti-brute-force, checked directly against the real evaluator for every
## proper subset of each round's accepted proof — no size-1 or size-2
## selection may ever resolve a 3-slot target (DeductionValidator's own
## _validate_prototype_b_target already enforces this structurally; this
## re-proves it end to end against real content, the same "belt and
## suspenders" relationship prototype_a_content_test.gd has with the base
## validator).
func _test_no_proper_subset_resolves_either_target(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	for role in [D1_ROLE, D3_ROLE]:
		var target_id: String = _id_by_role(case_def, "claims", role)
		var claim: Dictionary = evaluator.find_claim(case_def, target_id)
		for proof_set in claim.get("proof_sets", []):
			var requires: Array = proof_set.get("requires", [])
			for size in range(1, requires.size()):
				for start in requires.size():
					var subset: Array = []
					for offset in size:
						subset.append(requires[(start + offset) % requires.size()])
					if subset.size() != size or subset.size() == requires.size():
						continue
					var session = session_script.new(case_id)
					var result: Dictionary = evaluator.commit_attempt(case_def, session, target_id, "supports", subset)
					_check(result.get("category") != evaluator.VALID_SUPPORT, "%s: a %d-item proper subset %s of proof \"%s\" must never resolve %s (defeats the round's slot count) — got %s" % [case_id, size, subset, proof_set.get("id", ""), role, result.get("category")])


func _test_evidence_pool_available_from_the_start(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session = session_script.new(case_id)
	for evidence_id in evaluator.string_array(case_def.get("prototype_b", {}).get("evidence_pool", [])):
		_check(evaluator.is_evidence_available(case_def, session, evidence_id), "%s: evidence \"%s\" in the Prototype B pool must be available from the start" % [case_id, evidence_id])
	for role in [D1_ROLE, D3_ROLE]:
		var target_id: String = _id_by_role(case_def, "claims", role)
		var claim: Dictionary = evaluator.find_claim(case_def, target_id)
		var pool: Array = evaluator.string_array(case_def.get("prototype_b", {}).get("evidence_pool", []))
		for proof_set in claim.get("proof_sets", []):
			for item_id in proof_set.get("requires", []):
				_check(pool.has(item_id), "%s: accepted proof item \"%s\" for %s must be listed in prototype_b.evidence_pool" % [case_id, item_id, role])


func _test_translations_resolve(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var proto: Dictionary = case_def.get("prototype_b", {})
	var en: Translation = TranslationServer.get_translation_object("en")
	var vi: Translation = TranslationServer.get_translation_object("vi")
	var completion_key: String = str(proto.get("completion_text", ""))
	_check(String(en.get_message(completion_key)) != "" and String(vi.get_message(completion_key)) != "", "%s: completion_text \"%s\" must resolve in both en and vi" % [case_id, completion_key])
	for pb_round in proto.get("rounds", []):
		for field in ["question", "success_explanation"]:
			var key: String = str(pb_round.get(field, ""))
			_check(String(en.get_message(key)) != "" and String(vi.get_message(key)) != "", "%s: round \"%s\" %s key \"%s\" must resolve in both en and vi" % [case_id, pb_round.get("id", ""), field, key])


## The "Important separation from Prototype A" audit, machine-checked: the
## single evidence item that solves Prototype A's round-2 statement target
## (the specific testimony claim) must NOT, alone, resolve Prototype B's
## broader D3 deduction target — they are different claims with different
## proof requirements by construction, but this proves it end to end rather
## than by inspection alone.
func _test_prototype_a_target_does_not_solve_prototype_b_d3(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var proto_a: Dictionary = case_def.get("prototype_a", {})
	var statement_target: String = ""
	for pa_round in proto_a.get("rounds", []):
		for claim_id in evaluator.string_array(pa_round.get("required_refutations", [])):
			if evaluator.find_claim(case_def, claim_id).get("structural_role", "") == "candidate_staging_claim":
				statement_target = claim_id
	_check(statement_target != "", "%s: sanity — Prototype A's staging-related statement target should be found" % case_id)

	var d3_target: String = _id_by_role(case_def, "claims", D3_ROLE)
	_check(statement_target != d3_target, "%s: Prototype A's statement target and Prototype B's D3 target must be DIFFERENT claims" % case_id)

	# The single evidence item that refutes Prototype A's statement (the
	# staging_sign alone — see docs/prototype-a.md, "0.2") must not, alone,
	# support Prototype B's D3.
	var statement_claim: Dictionary = evaluator.find_claim(case_def, statement_target)
	var single_evidence_id: String = ""
	for proof_set in statement_claim.get("proof_sets", []):
		var requires: Array = proof_set.get("requires", [])
		if requires.size() == 1:
			single_evidence_id = requires[0]
	_check(single_evidence_id != "", "%s: sanity — Prototype A's statement target should have a single-evidence proof set" % case_id)

	var session = session_script.new(case_id)
	var result: Dictionary = evaluator.commit_attempt(case_def, session, d3_target, "supports", [single_evidence_id])
	_check(result.get("category") != evaluator.VALID_SUPPORT, "%s: Prototype A's single staging clue (\"%s\") must NOT, alone, solve Prototype B's broader D3 target — got %s" % [case_id, single_evidence_id, result.get("category")])


## The structural-role SHAPE of prototype_b — evidence pool roles, and each
## round's target/relation/slot_count — must be identical across X, Y and Z.
func _test_prototype_b_structurally_equivalent_across_cases() -> void:
	var reference: Array = []
	for line in validator.structural_signature(content_db.get_deduction_case(CASE_IDS[0])):
		if String(line).begins_with("prototype_b:"):
			reference.append(line)
	_check(reference.size() >= 3, "the prototype_b structural signature should describe the evidence pool and both rounds, not be trivially empty")
	for i in range(1, CASE_IDS.size()):
		var other: Array = []
		for line in validator.structural_signature(content_db.get_deduction_case(CASE_IDS[i])):
			if String(line).begins_with("prototype_b:"):
				other.append(line)
		_check(other == reference, "%s's prototype_b shape should exactly match %s's, got %s vs %s" % [CASE_IDS[i], CASE_IDS[0], other, reference])
