extends SceneTree
## Content-validation tests for DeductionValidator (Milestone 1.9 — see
## docs/deduction-system.md, "Content validation"). Each negative fixture is
## deduction_fixtures.gd's clean base case with exactly one thing broken, and
## asserts the validator names that problem — proving the checks catch real
## mistakes rather than passing clean content vacuously. Also asserts the real
## data/deductions content produces zero deduction errors/warnings through
## ContentValidator. Run with:
##   godot --headless --path . -s res://scenes/test/deduction_validation_test.gd

var content_db: Node
var validator: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame
	validator = load("res://scripts/deduction/deduction_validator.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== DeductionValidator — content-validation tests ===")
	_test_base_fixture_is_clean()
	_test_duplicate_id()
	_test_missing_evidence_reference()
	_test_invalid_relation_and_empty_proof_set()
	_test_duplicate_items_in_proof_set()
	_test_dependency_cycle()
	_test_circular_clue_unlock()
	_test_unreachable_required_deduction()
	_test_unresolved_required_question()
	_test_invalid_timeline_reference()
	_test_invalid_time_window()
	_test_solution_violates_own_constraints()
	_test_missing_ground_truth()
	_test_missing_hint_references()
	_test_inference_depth_semantics()
	_test_third_intermediate_layer_fails()
	_test_conclusion_graph_is_still_checked()
	_test_kind_change_cannot_bypass_graph_checks()
	_test_deduction_gated_required_evidence_warning()
	_test_red_herring_needs_explanation()
	_test_ground_truth_consistency()
	_test_missing_canon_metadata()
	_test_missing_structural_role()
	_test_structural_equivalence()
	_test_real_content_is_clean()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _validate(case_def: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	validator.validate_case(case_def, errors, warnings)
	return {"errors": errors, "warnings": warnings}


func _expect_error(case_def: Dictionary, fragment: String, message: String) -> void:
	var errors: Array = _validate(case_def).get("errors", [])
	_check(errors.any(func(error: String) -> bool: return error.contains(fragment)), "%s — expected an error containing '%s', got %s" % [message, fragment, errors])


func _claim(case_def: Dictionary, claim_id: String) -> Dictionary:
	return fixtures.find(case_def, "claims", claim_id)


func _test_base_fixture_is_clean() -> void:
	var result: Dictionary = _validate(fixtures.base_case())
	_check((result.get("errors") as Array).is_empty(), "the base fixture must validate with zero errors: %s" % [result.get("errors")])
	_check((result.get("warnings") as Array).is_empty(), "the base fixture must validate with zero warnings: %s" % [result.get("warnings")])


func _test_duplicate_id() -> void:
	var case_def: Dictionary = fixtures.base_case()
	case_def["evidence"].append(fixtures._evidence("ded_misused", "duplicate_role", ["time"]))
	_expect_error(case_def, 'defines id "ded_misused" more than once', "an evidence id colliding with a claim id")


func _test_missing_evidence_reference() -> void:
	var case_def: Dictionary = fixtures.base_case()
	_claim(case_def, "ded_access")["proof_sets"][0]["requires"].append("e_ghost")
	_expect_error(case_def, 'references undefined evidence or deduction "e_ghost"', "a proof set referencing undefined evidence")


func _test_invalid_relation_and_empty_proof_set() -> void:
	var case_def: Dictionary = fixtures.base_case()
	_claim(case_def, "ded_misused")["proof_sets"][0]["relation"] = "proves"
	_expect_error(case_def, 'uses invalid relation "proves"', "an unknown relation type")
	case_def = fixtures.base_case()
	_claim(case_def, "ded_misused")["proof_sets"][1]["requires"] = []
	_expect_error(case_def, "is an empty proof set", "a proof set with no items")


func _test_duplicate_items_in_proof_set() -> void:
	var case_def: Dictionary = fixtures.base_case()
	_claim(case_def, "ded_misused")["proof_sets"][0]["requires"] = ["e_log", "e_log", "e_away", "e_travel"]
	_expect_error(case_def, 'lists "e_log" more than once', "a proof set listing the same item twice")


func _test_dependency_cycle() -> void:
	var case_def: Dictionary = fixtures.base_case()
	_claim(case_def, "ded_misused")["proof_sets"][0]["requires"].append("ded_access")
	_expect_error(case_def, "deduction dependency cycle", "two deductions requiring each other")


func _test_circular_clue_unlock() -> void:
	var case_def: Dictionary = fixtures.base_case()
	fixtures.find(case_def, "evidence", "e_log")["unlock_requires"] = ["ded_misused"]
	_expect_error(case_def, "circular clue unlock", "a clue locked behind the deduction that needs it")
	_expect_error(case_def, 'required claim "ded_misused" is unreachable', "a circular unlock also makes the deduction unreachable")


## With only evidence and deductions as inputs, an unreachable deduction
## always has a root cause somewhere upstream; this proves the downstream
## consequence is reported too, so a required step never silently dead-ends.
func _test_unreachable_required_deduction() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var misused: Dictionary = _claim(case_def, "ded_misused")
	misused["proof_sets"] = []
	misused["required"] = false
	_expect_error(case_def, 'required claim "ded_access" is unreachable', "a required deduction whose prerequisite can never be proven")
	_expect_error(case_def, 'required question "q_owner" has no valid resolution path', "the question depending on it has no path either")


func _test_unresolved_required_question() -> void:
	var case_def: Dictionary = fixtures.base_case()
	fixtures.find(case_def, "questions", "q_owner")["resolved_by"] = [{"claim": "hyp_owner", "status": "supported"}]
	var errors: Array = _validate(case_def).get("errors", [])
	_check(errors.size() == 1 and String(errors[0]).contains('required question "q_owner" has no valid resolution path'), "a question only resolvable by supporting a false hypothesis should be exactly one error: %s" % [errors])


func _test_invalid_timeline_reference() -> void:
	var case_def: Dictionary = fixtures.base_case()
	fixtures.find_constraint(case_def, "c_use")["event"] = "t_ghost"
	_expect_error(case_def, 'references unknown timeline event "t_ghost"', "a constraint naming an undefined timeline event")


func _test_invalid_time_window() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var window: Dictionary = fixtures.find_constraint(case_def, "c_leaves")
	window["earliest"] = "09:40"
	window["latest"] = "09:10"
	_expect_error(case_def, "is an invalid time window", "a window whose earliest is after its latest")
	case_def = fixtures.base_case()
	fixtures.find_constraint(case_def, "c_use")["time"] = "25:00"
	_expect_error(case_def, "time is not a valid HH:MM time", "a fixed time outside the day")


func _test_solution_violates_own_constraints() -> void:
	var case_def: Dictionary = fixtures.base_case()
	case_def["ground_truth"]["solution_timeline"]["t_leaves"] = "09:40"
	_expect_error(case_def, 'violates its own required timeline constraint "c_travel"', "an authored solution breaking its own travel-time constraint")
	case_def = fixtures.base_case()
	case_def["ground_truth"]["solution_timeline"].erase("t_use")
	_expect_error(case_def, "is not a complete, well-formed placement", "an authored solution missing an event")


func _test_missing_ground_truth() -> void:
	var case_def: Dictionary = fixtures.base_case()
	case_def.erase("ground_truth")
	_expect_error(case_def, "has no ground_truth object", "a case with no ground truth")
	case_def = fixtures.base_case()
	case_def["ground_truth"]["culprit"] = "sus_nobody"
	_expect_error(case_def, 'ground_truth.culprit "sus_nobody" is not a suspect', "a ground-truth culprit who isn't a suspect")


func _test_missing_hint_references() -> void:
	var case_def: Dictionary = fixtures.base_case()
	case_def["hints"][0]["levels"][2]["evidence"] = ["e_ghost"]
	_expect_error(case_def, 'references unknown evidence "e_ghost"', "a hint pointing at undefined evidence")
	case_def = fixtures.base_case()
	case_def["hints"][0]["levels"][0]["question"] = "q_ghost"
	_expect_error(case_def, 'references unknown question "q_ghost"', "a hint restating an undefined question")
	case_def = fixtures.base_case()
	case_def["hints"][0]["levels"][1]["categories"] = ["astrology"]
	_expect_error(case_def, 'references category "astrology"', "a hint comparing a category no evidence has")
	case_def = fixtures.base_case()
	case_def["hints"].remove_at(1)
	_expect_error(case_def, 'required deduction "ded_access" has no hint ladder', "a required deduction without a hint ladder")
	case_def = fixtures.base_case()
	case_def["hints"][2]["levels"][3]["deduction"] = "concl"
	_expect_error(case_def, "reveals the final conclusion", "a level-4 hint that gives away the final conclusion")
	case_def = fixtures.base_case()
	(case_def["hints"][0]["levels"] as Array).pop_back()
	_expect_error(case_def, "must have exactly 4 levels", "a ladder missing its last level")


func _depth_errors(case_def: Dictionary) -> Array:
	return (_validate(case_def).get("errors", []) as Array).filter(func(error: String) -> bool: return error.contains("maximum intermediate deduction depth"))


func _deduction(claim_id: String, kind: String, requires: Array, role: String) -> Dictionary:
	return {
		"id": claim_id, "kind": kind, "veracity": "true", "text": "FX", "structural_role": role,
		"proof_sets": [{"id": "ps_" + claim_id, "relation": "supports", "requires": requires}],
	}


## docs/deduction-system.md, "Inference depth": evidence = 0, a deduction =
## 1 + its deepest deduction input, max intermediate depth 2, and a conclusion
## is a synthesis layer exempt from the limit. The base fixture is exactly
## evidence -> D1 -> D2 -> conclusion.
func _test_inference_depth_semantics() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var depths: Dictionary = validator.inference_depths(case_def)
	_check(depths.get("ded_misused") == 1, "evidence -> D1 should be intermediate depth 1: %s" % [depths])
	_check(depths.get("ded_access") == 2, "evidence -> D1 -> D2 should be intermediate depth 2: %s" % [depths])
	_check(not depths.has("concl"), "a conclusion is the synthesis layer, not an intermediate deduction: %s" % [depths])
	_check(validator.claim_depth(case_def, "concl") == 3, "evidence -> D1 -> D2 -> conclusion should report synthesis depth 3")
	_check(_depth_errors(case_def).is_empty(), "evidence -> D1, evidence -> D1 -> D2 and a conclusion on D2 must all pass the depth rule: %s" % [_depth_errors(case_def)])
	var signature: Array[String] = validator.structural_signature(case_def)
	_check(signature.has("proof:final_conclusion:supports:[candidate_exclusive_control]:depth=3") and signature.has("proof:credential_misused:supports:[credential_use_record,owner_alibi_alternate,travel_fact]:depth=1"), "the structural signature should record each proof set's depth, so alternate paths and conclusions compare by depth too")


func _test_third_intermediate_layer_fails() -> void:
	var case_def: Dictionary = fixtures.base_case()
	case_def["claims"].append(_deduction("ded_deep", "deduction", ["ded_access"], "too_deep"))
	_expect_error(case_def, 'intermediate deduction "ded_deep" is at depth 3, above the maximum intermediate deduction depth of 2', "evidence -> D1 -> D2 -> D3 where D3 is another intermediate deduction")
	_check(_depth_errors(case_def).size() == 1, "only the third intermediate layer should be reported, not D1 or D2: %s" % [_depth_errors(case_def)])


## The depth exemption must not exempt a conclusion from graph soundness.
func _test_conclusion_graph_is_still_checked() -> void:
	var cyclic: Dictionary = fixtures.base_case()
	_claim(cyclic, "ded_misused")["proof_sets"][0]["requires"].append("concl")
	var errors: Array = _validate(cyclic).get("errors", [])
	_check(errors.any(func(error: String) -> bool: return error.contains("dependency cycle") and error.contains("concl")), "a cycle running through the conclusion should be reported: %s" % [errors])

	var dangling: Dictionary = fixtures.base_case()
	_claim(dangling, "concl")["proof_sets"][0]["requires"].append("ded_ghost")
	_expect_error(dangling, 'references undefined evidence or deduction "ded_ghost"', "a conclusion referencing an undefined deduction")

	var unreachable: Dictionary = fixtures.base_case()
	var dead_end: Dictionary = _deduction("ded_dead", "deduction", [], "dead_end")
	dead_end["proof_sets"] = []
	unreachable["claims"].append(dead_end)
	_claim(unreachable, "concl")["proof_sets"][0]["requires"].append("ded_dead")
	_expect_error(unreachable, 'required claim "concl" is unreachable', "a conclusion depending on a deduction that can never be proven")
	_expect_error(unreachable, 'ground_truth.conclusion "concl" can never be proven', "the ground-truth conclusion is reported unprovable too")


## Relabelling a claim's kind can move it out of the depth limit, but never out
## of reference, input-kind, cycle or reachability checks.
func _test_kind_change_cannot_bypass_graph_checks() -> void:
	var legit: Dictionary = fixtures.base_case()
	legit["claims"].append(_deduction("concl_extra", "conclusion", ["ded_access"], "second_synthesis"))
	_check((_validate(legit).get("errors") as Array).is_empty(), "a second conclusion synthesising D2 is a valid terminal claim: %s" % [_validate(legit).get("errors")])

	var relabelled: Dictionary = fixtures.base_case()
	relabelled["claims"].append(_deduction("ded_deep", "conclusion", ["ded_access"], "too_deep"))
	relabelled["claims"].append(_deduction("ded_deeper", "deduction", ["ded_deep"], "deeper"))
	_expect_error(relabelled, 'uses claim "ded_deep" as an input, but only deduction claims can be inputs', "a third layer relabelled as a conclusion but still used as an input")
	var relabelled_warnings: Array = _validate(relabelled).get("warnings", [])
	_check(relabelled_warnings.any(func(warning: String) -> bool: return warning.contains('claim "ded_deeper" has proof sets but none can ever be satisfied')), "what builds on the relabelled claim can never be proven: %s" % [relabelled_warnings])

	var as_explanation: Dictionary = fixtures.base_case()
	_claim(as_explanation, "ded_misused")["kind"] = "explanation"
	_expect_error(as_explanation, 'uses claim "ded_misused" as an input', "an intermediate deduction relabelled as an explanation while D2 still needs it")
	_expect_error(as_explanation, 'required claim "concl" is unreachable', "relabelling D1 must make everything built on it unreachable, not silently pass")

	var raw_conclusion: Dictionary = fixtures.base_case()
	_claim(raw_conclusion, "ded_misused")["kind"] = "conclusion"
	_expect_error(raw_conclusion, 'uses raw evidence "e_log" — a conclusion may only combine proven deductions', "a deduction relabelled as a conclusion still may not use raw evidence")

	var cyclic: Dictionary = fixtures.base_case()
	_claim(cyclic, "ded_access")["kind"] = "conclusion"
	_claim(cyclic, "ded_misused")["proof_sets"][0]["requires"].append("ded_access")
	_expect_error(cyclic, "dependency cycle", "a cycle through a claim relabelled as a conclusion")

	var typo: Dictionary = fixtures.base_case()
	_claim(typo, "ded_access")["kind"] = "Deduction"
	_claim(typo, "ded_access")["proof_sets"][0]["requires"].append("e_ghost")
	_expect_error(typo, 'has unknown kind "Deduction"', "a typo'd claim kind")
	_expect_error(typo, 'references undefined evidence or deduction "e_ghost"', "a typo'd kind must not hide the claim's broken proof-set references")


## docs/deduction-system.md, "Evidence availability": evidence gated behind a
## deduction and then required by a deduction/conclusion is the "a thought made
## a record appear" pattern — a warning (the generic contract stays).
func _test_deduction_gated_required_evidence_warning() -> void:
	var gated: Dictionary = fixtures.base_case()
	fixtures.find(gated, "evidence", "e_custody")["unlock_requires"] = ["ded_misused"]
	var result: Dictionary = _validate(gated)
	var warnings: Array = result.get("warnings", [])
	_check(warnings.size() == 1 and String(warnings[0]).contains('evidence "e_custody" is locked behind deduction(s) ded_misused and then required by deduction "ded_access"'), "custody evidence gated on D1 and required by D2 should produce exactly that warning: %s" % [warnings])
	_check((result.get("errors") as Array).is_empty(), "deduction-gated evidence is a warning, not an error — the generic unlock contract is kept: %s" % [result.get("errors")])
	var ungated: Dictionary = fixtures.base_case()
	_check(fixtures.find(ungated, "evidence", "e_followup").get("unlock_requires") == ["ded_misused"] and (_validate(ungated).get("warnings") as Array).is_empty(), "gated evidence that no deduction or conclusion requires (the fixture's e_followup) must not warn")


func _test_red_herring_needs_explanation() -> void:
	var case_def: Dictionary = fixtures.base_case()
	fixtures.find(case_def, "evidence", "e_noise")["misleading"] = true
	_expect_error(case_def, "is marked misleading but no \"explains\" proof set uses it", "a red herring with no truthful explanation")


func _test_ground_truth_consistency() -> void:
	var case_def: Dictionary = fixtures.base_case()
	_claim(case_def, "st_denial")["proof_sets"][0]["relation"] = "supports"
	_expect_error(case_def, 'relation "supports" is not allowed on a statement whose veracity is "deceptive"', "a proof establishing a lie as true")
	case_def = fixtures.base_case()
	_claim(case_def, "hyp_owner")["proof_sets"].append({"id": "ps_owner_support", "relation": "supports", "requires": ["e_log"]})
	_expect_error(case_def, "has both establishing (supports/explains) and negating", "a claim that is both provable and disprovable")
	case_def = fixtures.base_case()
	fixtures.find_constraint(case_def, "c_claimed")["required"] = true
	_expect_error(case_def, "is required but comes from deceptive statement", "a required constraint resting on a lie")


func _test_missing_canon_metadata() -> void:
	var case_def: Dictionary = fixtures.base_case()
	case_def["metadata"].erase("canon")
	_expect_error(case_def, "metadata.canon must be true or false", "a case that doesn't declare whether it is canon")


func _test_missing_structural_role() -> void:
	var case_def: Dictionary = fixtures.base_case()
	fixtures.find(case_def, "evidence", "e_travel").erase("structural_role")
	_expect_error(case_def, 'evidence "e_travel" has no structural_role', "an evidence item missing its structural role")


func _test_structural_equivalence() -> void:
	var reference: Dictionary = fixtures.base_case()
	var twin: Dictionary = fixtures.base_case()
	twin["id"] = "fx_case_b"
	var errors: Array[String] = []
	validator.validate_structural_equivalence([twin, reference], errors)
	_check(errors.is_empty(), "two cases with the same roles and graph shape should be equivalent: %s" % [errors])

	var missing_role: Dictionary = fixtures.base_case()
	missing_role["id"] = "fx_case_c"
	fixtures.find(missing_role, "evidence", "e_travel")["structural_role"] = "renamed_travel_fact"
	errors = []
	validator.validate_structural_equivalence([reference, missing_role], errors)
	_check(errors.size() == 1 and errors[0].contains("not structurally equivalent") and errors[0].contains("travel_fact"), "a case missing a role the other has should be reported, naming the role: %s" % [errors])

	var no_alternate: Dictionary = fixtures.base_case()
	no_alternate["id"] = "fx_case_d"
	(_claim(no_alternate, "ded_misused")["proof_sets"] as Array).pop_back()
	errors = []
	validator.validate_structural_equivalence([reference, no_alternate], errors)
	_check(errors.size() == 1 and errors[0].contains("proof:credential_misused"), "a case dropping the alternate proof path should be reported as a proof-graph difference: %s" % [errors])


func _test_real_content_is_clean() -> void:
	_check(content_db.get_all_deduction_case_ids().size() == 3, "exactly the three prototype deduction cases should load")
	var result: Dictionary = content_db.get_last_validation_result()
	var deduction_errors: Array = (result.get("errors", []) as Array).filter(func(message: String) -> bool: return message.contains("Deduction case"))
	var deduction_warnings: Array = (result.get("warnings", []) as Array).filter(func(message: String) -> bool: return message.contains("Deduction case"))
	_check(deduction_errors.is_empty(), "real deduction content should have zero validation errors: %s" % [deduction_errors])
	_check(deduction_warnings.is_empty(), "real deduction content should have zero validation warnings: %s" % [deduction_warnings])
