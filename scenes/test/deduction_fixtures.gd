extends RefCounted
## Hand-built deduction case fixtures for the Milestone 1.9 deduction tests
## (deduction_evaluator_test.gd, timeline_evaluator_test.gd,
## deduction_validation_test.gd). Not a runnable test and not content: these
## dictionaries never reach ContentDB, so a negative fixture can be as broken
## as a test needs without polluting real validation. Text fields hold the
## placeholder "FX" — DeductionValidator only checks that a key is present;
## translation completeness is ContentValidator's job for real content.
##
## Loaded with load() rather than a class_name, so a test never depends on
## the class_name cache having been rebuilt.
##
## base_case() is a miniature of the credential-misuse proof graph, and the
## smallest valid instance of the documented depth rule
## (evidence -> D1 -> D2 -> conclusion; see docs/deduction-system.md,
## "Inference depth"):
##   e_log + e_away + e_travel   --supports-->  ded_misused   (primary, depth 1)
##   e_log + e_photo + e_travel  --supports-->  ded_misused   (alternate, depth 1)
##   ded_misused + e_custody     --supports-->  ded_access    (depth 2)
##   ded_access                  --supports-->  concl         (synthesis layer, depth 3)
##   e_custody                   --refutes-->   st_denial
##   ded_misused                 --rules_out--> hyp_owner     (e_log is merely compatible)
## e_custody is available from the start (Milestone 1.9.1: evidence a deduction
## needs is never gated behind a deduction). e_followup is the one gated item —
## locked behind ded_misused and required by no deduction or conclusion — so
## the generic unlock_requires mechanism stays covered without the "a thought
## made evidence appear" pattern. e_rumor is compatible-but-not-proof for
## ded_misused; e_noise bears on nothing.


static func base_case() -> Dictionary:
	return {
		"id": "fx_case",
		"display_name": "FX",
		"metadata": {"canon": false, "structural_template": "fixture_template_v1"},
		"suspects": [
			{"id": "sus_owner", "name": "FX", "structural_role": "apparent_suspect"},
			{"id": "sus_culprit", "name": "FX", "structural_role": "actual_culprit"},
		],
		"questions": [
			_question("q_owner", "owner_involvement", "ded_misused", "supported"),
			_question("q_access", "access_method", "ded_access", "supported"),
			_question("q_culprit", "culprit", "concl", "supported"),
		],
		"evidence": [
			_evidence("e_log", "credential_use_record", ["access", "time"]),
			_evidence("e_away", "owner_alibi_primary", ["location", "time"]),
			_evidence("e_photo", "owner_alibi_alternate", ["location", "time"]),
			_evidence("e_travel", "travel_fact", ["distance"]),
			_evidence("e_custody", "credential_custody", ["possession"]),
			_evidence("e_followup", "followup_record", ["possession"], ["ded_misused"]),
			_evidence("e_rumor", "rumor", ["location"]),
			_evidence("e_noise", "unrelated", ["scene"]),
		],
		"claims": [
			{
				"id": "ded_misused", "kind": "deduction", "veracity": "true", "required": true, "text": "FX",
				"structural_role": "credential_misused", "compatible": ["e_rumor"],
				"proof_sets": [
					{"id": "ps_misused_primary", "relation": "supports", "requires": ["e_log", "e_away", "e_travel"]},
					{"id": "ps_misused_alternate", "relation": "supports", "requires": ["e_log", "e_photo", "e_travel"]},
				],
			},
			{
				"id": "ded_access", "kind": "deduction", "veracity": "true", "required": true, "text": "FX",
				"structural_role": "candidate_exclusive_control",
				"proof_sets": [{"id": "ps_access", "relation": "supports", "requires": ["ded_misused", "e_custody"]}],
			},
			{
				"id": "concl", "kind": "conclusion", "veracity": "true", "required": true, "text": "FX",
				"structural_role": "final_conclusion",
				"proof_sets": [{"id": "ps_concl", "relation": "supports", "requires": ["ded_access"]}],
			},
			{
				"id": "st_denial", "kind": "statement", "speaker": "sus_culprit", "veracity": "deceptive", "text": "FX",
				"structural_role": "culprit_custody_denial",
				"proof_sets": [{"id": "ps_denial", "relation": "refutes", "requires": ["e_custody"]}],
			},
			{
				"id": "hyp_owner", "kind": "hypothesis", "veracity": "false", "text": "FX",
				"structural_role": "hypothesis_owner", "compatible": ["e_log"],
				"proof_sets": [{"id": "ps_rule_out_owner", "relation": "rules_out", "requires": ["ded_misused"]}],
			},
		],
		"timeline": {
			"events": [
				{"id": "t_leaves", "label": "FX", "actor": "sus_owner", "certainty": "claimed", "structural_role": "owner_departure"},
				{"id": "t_away", "label": "FX", "actor": "sus_owner", "certainty": "fixed", "duration_minutes": 30, "structural_role": "owner_alibi_anchor"},
				{"id": "t_use", "label": "FX", "actor": "", "certainty": "fixed", "structural_role": "credential_use_anchor"},
			],
			"constraints": [
				{"id": "c_use", "type": "fixed_time", "event": "t_use", "time": "10:00", "source": "e_log"},
				{"id": "c_leaves", "type": "window", "event": "t_leaves", "earliest": "09:00", "latest": "09:30", "source": "e_away"},
				{"id": "c_away", "type": "window", "event": "t_away", "earliest": "09:50", "latest": "10:10", "source": "e_away"},
				{"id": "c_order", "type": "before", "events": ["t_leaves", "t_away"], "source": "e_away"},
				{"id": "c_travel", "type": "travel_time", "events": ["t_leaves", "t_away"], "minutes": 25, "source": "e_travel"},
				{"id": "c_claimed", "type": "window", "event": "t_leaves", "earliest": "09:40", "latest": "09:50", "required": false, "source": "st_denial"},
			],
		},
		"hints": [
			_ladder("ded_misused", "q_owner", ["time", "location"], ["e_log", "e_away", "e_travel"], "ded_misused"),
			_ladder("ded_access", "q_access", ["possession"], ["e_custody"], "ded_misused"),
			_ladder("concl", "q_culprit", ["possession", "access"], ["e_custody", "e_log"], "ded_access"),
		],
		"ground_truth": {
			"culprit": "sus_culprit",
			"credential_owner": "sus_owner",
			"conclusion": "concl",
			"summary": "FX",
			"solution_timeline": {"t_leaves": "09:20", "t_away": "09:55", "t_use": "10:00"},
		},
	}


## A second valid placement of base_case()'s timeline, different from the
## authored solution — proof that timelines are checked by constraint, not by
## equality with one sequence.
static func alternate_valid_timeline() -> Dictionary:
	return {"t_leaves": "09:00", "t_away": "10:05", "t_use": "10:00"}


## Finds an entry by id anywhere a test needs to mutate a fixture in place.
static func find(case_def: Dictionary, section: String, entry_id: String) -> Dictionary:
	for entry in case_def.get(section, []):
		if entry.get("id", "") == entry_id:
			return entry
	return {}


static func find_constraint(case_def: Dictionary, constraint_id: String) -> Dictionary:
	for entry in case_def["timeline"]["constraints"]:
		if entry.get("id", "") == constraint_id:
			return entry
	return {}


static func _question(question_id: String, role: String, claim_id: String, status: String) -> Dictionary:
	return {
		"id": question_id, "text": "FX", "required": true, "structural_role": role,
		"resolved_by": [{"claim": claim_id, "status": status}],
	}


static func _evidence(evidence_id: String, role: String, tags: Array, unlock_requires: Array = []) -> Dictionary:
	return {
		"id": evidence_id, "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed",
		"tags": tags, "unlock_requires": unlock_requires, "structural_role": role,
	}


static func _ladder(target: String, question_id: String, categories: Array, evidence: Array, deduction_id: String) -> Dictionary:
	return {
		"target": target,
		"levels": [
			{"level": 1, "kind": "restate_question", "question": question_id, "text": "FX"},
			{"level": 2, "kind": "compare_categories", "categories": categories, "text": "FX"},
			{"level": 3, "kind": "evidence_group", "evidence": evidence, "text": "FX"},
			{"level": 4, "kind": "reveal_deduction", "deduction": deduction_id, "text": "FX"},
		],
	}
