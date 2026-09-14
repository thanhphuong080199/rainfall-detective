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


## Minimal, self-contained fixture for Milestone 1.11's Prototype A
## (PrototypeAController/PrototypeAPresenter — see docs/prototype-a.md). NOT
## a full DeductionValidator-clean case (no questions/timeline/hints/
## ground_truth) — those classes never read those sections, so this only
## carries what they actually touch: suspects, evidence, statement claims and
## a prototype_a data layer. Two rounds, matching the real X/Y/Z shape:
##   round_1: st_true (true, supported by e_a) + st_required1 (required lie,
##            refuted by e_b alone)
##   round_2: st_optional (innocent lie, refuted by e_d alone) + st_required2
##            (required lie, refuted by e_c alone)
## e_noise bears on nothing (an irrelevant-evidence distractor).
static func prototype_a_case() -> Dictionary:
	return {
		"id": "fx_pa_case",
		"display_name": "FX",
		"description": "FX",
		"metadata": {"canon": false},
		"suspects": [
			{"id": "sus_a", "name": "FX"},
			{"id": "sus_b", "name": "FX"},
		],
		"evidence": [
			{"id": "e_a", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_b", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_c", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_d", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_noise", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
		],
		"claims": [
			{
				"id": "st_true", "kind": "statement", "speaker": "sus_a", "veracity": "true", "text": "FX",
				"proof_sets": [{"id": "ps_true", "relation": "supports", "requires": ["e_a"]}],
			},
			{
				"id": "st_required1", "kind": "statement", "speaker": "sus_b", "veracity": "deceptive", "text": "FX",
				"proof_sets": [{"id": "ps_required1", "relation": "refutes", "requires": ["e_b"]}],
			},
			{
				"id": "st_optional", "kind": "statement", "speaker": "sus_a", "veracity": "deceptive", "lie_motive": "unrelated_to_crime", "text": "FX",
				"proof_sets": [{"id": "ps_optional", "relation": "refutes", "requires": ["e_d"]}],
			},
			{
				"id": "st_required2", "kind": "statement", "speaker": "sus_b", "veracity": "deceptive", "text": "FX",
				"proof_sets": [{"id": "ps_required2", "relation": "refutes", "requires": ["e_c"]}],
			},
		],
		"prototype_a": {
			"evidence_pool": ["e_a", "e_b", "e_c", "e_d", "e_noise"],
			"rounds": [
				{
					"id": "round_1",
					"statements": ["st_true", "st_required1"],
					"required_refutations": ["st_required1"],
					"optional_refutations": [],
					"success_explanations": {"st_required1": "FX"},
					"witness_responses": {"st_required1": "FX"},
					"hint_ladders": {"st_required1": ["FX", "FX", "FX", "FX"]},
				},
				{
					"id": "round_2",
					"statements": ["st_optional", "st_required2"],
					"required_refutations": ["st_required2"],
					"optional_refutations": ["st_optional"],
					"success_explanations": {"st_required2": "FX", "st_optional": "FX"},
					"witness_responses": {"st_required2": "FX", "st_optional": "FX"},
					"hint_ladders": {"st_required2": ["FX", "FX", "FX", "FX"]},
				},
			],
			"completion_text": "FX",
		},
	}


## Minimal, self-contained fixture for Milestone 1.12's Prototype B
## (PrototypeBController/PrototypeBPresenter — see docs/prototype-b.md). NOT
## a full DeductionValidator-clean case (no suspects/questions/timeline/
## ground_truth) — those classes never read those sections, so this only
## carries what they actually touch: evidence, deduction claims with proof
## sets, a base hint ladder for each (Prototype B REUSES the real hint
## contract — see docs/prototype-b.md, "Hints", unlike Prototype A's own
## fixture) and a prototype_b data layer. Two rounds, DELIBERATELY with
## different slot counts, proving the controller reads slot_count from
## content rather than hardcoding it:
##   round_1: ded_first (3-slot deduction, requires e_a + e_b + e_c)
##   round_2: ded_second (2-slot deduction, requires e_d + e_e)
## e_noise bears on nothing (an irrelevant-evidence distractor).
static func prototype_b_case() -> Dictionary:
	return {
		"id": "fx_pb_case",
		"display_name": "FX",
		"description": "FX",
		"metadata": {"canon": false},
		"evidence": [
			{"id": "e_a", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_b", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_c", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_d", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_e", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
			{"id": "e_noise", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
		],
		"claims": [
			{
				"id": "ded_first", "kind": "deduction", "veracity": "true", "required": true, "text": "FX first deduction",
				"proof_sets": [{"id": "ps_first", "relation": "supports", "requires": ["e_a", "e_b", "e_c"]}],
			},
			{
				"id": "ded_second", "kind": "deduction", "veracity": "true", "required": true, "text": "FX second deduction",
				"proof_sets": [{"id": "ps_second", "relation": "supports", "requires": ["e_d", "e_e"]}],
			},
		],
		"hints": [
			_ladder("ded_first", "q_first", ["scene"], ["e_a", "e_b", "e_c"], "ded_first"),
			_ladder("ded_second", "q_second", ["scene"], ["e_d", "e_e"], "ded_second"),
		],
		"prototype_b": {
			"evidence_pool": ["e_a", "e_b", "e_c", "e_d", "e_e", "e_noise"],
			"rounds": [
				{
					"id": "round_1", "question": "FX", "target": "ded_first", "relation": "supports",
					"slot_count": 3, "success_explanation": "FX",
				},
				{
					"id": "round_2", "question": "FX", "target": "ded_second", "relation": "supports",
					"slot_count": 2, "success_explanation": "FX",
				},
			],
			"completion_text": "FX",
		},
	}


## Minimal, self-contained fixture for Milestone 1.13's Prototype C
## (PrototypeCController/PrototypeCPresenter — see docs/prototype-c.md). NOT a
## full DeductionValidator-clean case (no suspects/questions/hints/
## ground_truth) — those classes never read those sections, so this only
## carries what they actually touch: a timeline with one fixed and two
## movable events, two required window facts, one optional (disputed-claim)
## window constraint, and a prototype_c data layer. t_a's window (09:00-09:30)
## and t_b's window (10:10-10:40) each admit THREE of the six candidate time
## slots, so a test has a real choice of valid placements for each —
## t_a=09:00/09:15/09:30, t_b=10:10/10:25/10:40, none of which satisfy
## c_lie's disjoint claimed window (09:00-09:20 on t_b) — every accepted
## placement in this fixture already contradicts the claim, matching the real
## X/Y/Z content's own shape.
static func prototype_c_case() -> Dictionary:
	return {
		"id": "fx_pc_case",
		"display_name": "FX",
		"description": "FX",
		"metadata": {"canon": false},
		"suspects": [{"id": "sus_a", "name": "FX"}],
		"claims": [
			{
				"id": "st_lie", "kind": "statement", "speaker": "sus_a", "veracity": "deceptive", "text": "FX",
				"proof_sets": [{"id": "ps_lie", "relation": "refutes", "requires": ["e_noise"]}],
			},
		],
		"evidence": [
			{"id": "e_noise", "name": "FX", "text": "FX", "source": "fixture", "certainty": "fixed", "tags": ["scene"]},
		],
		"timeline": {
			"events": [
				{"id": "t_fixed", "label": "FX", "actor": "", "certainty": "fixed", "structural_role": "anchor"},
				{"id": "t_a", "label": "FX", "actor": "", "certainty": "estimated", "structural_role": "first"},
				{"id": "t_b", "label": "FX", "actor": "", "certainty": "estimated", "duration_minutes": 5, "structural_role": "second"},
			],
			"constraints": [
				{"id": "c_fixed", "type": "fixed_time", "event": "t_fixed", "time": "10:00", "source": "e_noise"},
				{"id": "c_a_window", "type": "window", "event": "t_a", "earliest": "09:00", "latest": "09:30", "source": "e_noise"},
				{"id": "c_b_window", "type": "window", "event": "t_b", "earliest": "10:10", "latest": "10:40", "source": "e_noise"},
				{"id": "c_lie", "type": "window", "event": "t_b", "earliest": "09:00", "latest": "09:20", "required": false, "source": "st_lie"},
			],
		},
		"prototype_c": {
			"fixed_events": ["t_fixed"],
			"movable_events": ["t_a", "t_b"],
			"time_slots": ["09:00", "09:15", "09:30", "10:10", "10:25", "10:40"],
			"objective": "FX",
			"visible_constraint_facts": {"c_a_window": "FX", "c_b_window": "FX"},
			"contradiction": {"claim": "st_lie", "constraint_ref": "c_lie", "explanation": "FX %s"},
			"hint_ladder": ["FX", "FX", "FX", "FX"],
			"completion_text": "FX",
		},
	}


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
