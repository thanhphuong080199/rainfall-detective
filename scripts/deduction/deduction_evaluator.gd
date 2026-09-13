class_name DeductionEvaluator
extends RefCounted
## Stateless, UI-independent deduction service shared by the future
## Prototype A (statement contradiction), B (claim/clue connection) and C
## (timeline reconstruction) screens (Milestone 1.9 — see
## docs/deduction-system.md for the full contract).
##
## Reads an immutable case definition (a plain Dictionary, as ContentDB
## returns it) plus a DeductionSession, and returns structured outcomes —
## never a bare bool, and never the answer itself. Proofs are matched against
## AUTHORED proof sets by id (order-independent), never by comparing
## player-facing text, and there is no inference engine: a claim is proven
## exactly when a selection satisfies one of its explicit proof sets.
##
## Pure apart from the session it is handed — no autoloads — so tests drive it
## with hand-built fixtures, and DeductionValidator shares its helpers.

const VALID_SUPPORT := "valid_support"
const VALID_REFUTATION := "valid_refutation"
const INSUFFICIENT_EVIDENCE := "insufficient_evidence"
const IRRELEVANT_EVIDENCE := "irrelevant_evidence"
const COMPATIBLE_NOT_PROOF := "compatible_not_proof"
const INVALID_INPUT := "invalid_input"

const RELATIONS := ["supports", "refutes", "explains", "rules_out"]
## supports/explains establish a claim; refutes/rules_out establish it is false.
const POSITIVE_RELATIONS := ["supports", "explains"]
const CLAIM_KINDS := ["statement", "hypothesis", "deduction", "explanation", "conclusion"]
## Claim kinds a proof set may use as INPUT once supported — the "derived
## deductions". Only these unlock anything; a conclusion, a refuted statement
## or a ruled-out hypothesis is a terminal finding, never a stepping stone.
const INPUT_KINDS := ["deduction"]


# ---------------------------------------------------------------------------
# Lookups

static func find_claim(case_def: Dictionary, claim_id: String) -> Dictionary:
	return _find_by_id(case_def.get("claims", []), claim_id)


static func find_evidence(case_def: Dictionary, evidence_id: String) -> Dictionary:
	return _find_by_id(case_def.get("evidence", []), evidence_id)


static func status_for_relation(relation: String) -> String:
	if POSITIVE_RELATIONS.has(relation):
		return DeductionSession.STATUS_SUPPORTED
	if RELATIONS.has(relation):
		return DeductionSession.STATUS_REFUTED
	return ""


static func category_for_relation(relation: String) -> String:
	return VALID_SUPPORT if POSITIVE_RELATIONS.has(relation) else VALID_REFUTATION


static func is_valid_category(category: String) -> bool:
	return category == VALID_SUPPORT or category == VALID_REFUTATION


## An evidence item is available once every deduction in its
## "unlock_requires" has been committed as supported (none = from the start).
static func is_evidence_available(case_def: Dictionary, session: DeductionSession, evidence_id: String) -> bool:
	var evidence: Dictionary = find_evidence(case_def, evidence_id)
	if evidence.is_empty():
		return false
	for requirement in string_array(evidence.get("unlock_requires", [])):
		if not session.is_supported(requirement):
			return false
	return true


static func get_available_evidence_ids(case_def: Dictionary, session: DeductionSession) -> Array[String]:
	var ids: Array[String] = []
	for evidence in dict_array(case_def.get("evidence", [])):
		var evidence_id: String = str(evidence.get("id", ""))
		if is_evidence_available(case_def, session, evidence_id):
			ids.append(evidence_id)
	return ids


# ---------------------------------------------------------------------------
# Proof attempts

## Classifies a proof attempt WITHOUT changing the session. Tooling and tests
## only — a player-facing screen calls commit_attempt(), so nothing unlocks
## merely because related items happen to be selected.
##
## Deterministic order (see docs/deduction-system.md, "Result categories"):
##   1. INVALID_INPUT — unknown claim/relation, empty selection, a non-string,
##      a DUPLICATE item, an unknown or unselectable id, or an item still locked.
##   2. IRRELEVANT_EVIDENCE — any selected item bears on this claim nowhere
##      (not in any of its proof sets, not in its "compatible" list).
##   3. VALID_SUPPORT / VALID_REFUTATION — the selection contains every item of
##      a proof set with the asserted relation (first authored match wins). Extra
##      items are tolerated only because step 2 already proved them relevant.
##   4. INSUFFICIENT_EVIDENCE — every item belongs to one such proof set, but
##      something is missing.
##   5. COMPATIBLE_NOT_PROOF — everything bears on the claim, but the selection
##      does not establish the asserted relation (an observation consistent with
##      the claim, items split across alternate proofs, or the wrong relation).
## Only the category is reported — never which item is missing or extra.
static func classify_attempt(case_def: Dictionary, session: DeductionSession, claim_id: String, relation: String, selection: Variant) -> Dictionary:
	var claim: Dictionary = find_claim(case_def, claim_id)
	if claim.is_empty():
		return _result(INVALID_INPUT, claim_id, relation, "unknown_claim")
	if session.case_id != "" and session.case_id != str(case_def.get("id", "")):
		return _result(INVALID_INPUT, claim_id, relation, "session_case_mismatch")
	if not RELATIONS.has(relation):
		return _result(INVALID_INPUT, claim_id, relation, "unknown_relation")
	if typeof(selection) != TYPE_ARRAY or (selection as Array).is_empty():
		return _result(INVALID_INPUT, claim_id, relation, "empty_selection")

	var selected: Dictionary = {}
	for item in selection:
		if typeof(item) != TYPE_STRING:
			return _result(INVALID_INPUT, claim_id, relation, "malformed_item")
		if selected.has(item):
			return _result(INVALID_INPUT, claim_id, relation, "duplicate_item")
		selected[item] = true
	for item_id in selected:
		if not find_evidence(case_def, item_id).is_empty():
			if not is_evidence_available(case_def, session, item_id):
				return _result(INVALID_INPUT, claim_id, relation, "locked_item")
			continue
		var input_claim: Dictionary = find_claim(case_def, item_id)
		if input_claim.is_empty():
			return _result(INVALID_INPUT, claim_id, relation, "unknown_item")
		if not INPUT_KINDS.has(str(input_claim.get("kind", ""))):
			return _result(INVALID_INPUT, claim_id, relation, "unselectable_item")
		if not session.is_supported(item_id):
			return _result(INVALID_INPUT, claim_id, relation, "locked_item")

	var proof_sets: Array[Dictionary] = dict_array(claim.get("proof_sets", []))
	var relevant: Dictionary = {}
	for item_id in string_array(claim.get("compatible", [])):
		relevant[item_id] = true
	for proof_set in proof_sets:
		for item_id in string_array(proof_set.get("requires", [])):
			relevant[item_id] = true
	for item_id in selected:
		if not relevant.has(item_id):
			return _result(IRRELEVANT_EVIDENCE, claim_id, relation)

	var is_partial := false
	for proof_set in proof_sets:
		if str(proof_set.get("relation", "")) != relation:
			continue
		var required: Array[String] = string_array(proof_set.get("requires", []))
		if required.is_empty():
			continue  # Malformed; DeductionValidator reports it.
		var contains_all := true
		for item_id in required:
			if not selected.has(item_id):
				contains_all = false
				break
		if contains_all:
			var valid: Dictionary = _result(category_for_relation(relation), claim_id, relation)
			valid["proof_set_id"] = str(proof_set.get("id", ""))
			return valid
		var within := true
		for item_id in selected:
			if not required.has(item_id):
				within = false
				break
		if within:
			is_partial = true
	return _result(INSUFFICIENT_EVIDENCE if is_partial else COMPATIBLE_NOT_PROOF, claim_id, relation)


## The one player-facing way to prove something: classifies the attempt,
## records it (valid or not) in the session, and — only for a valid category —
## resolves the claim, which is what unlocks a derived deduction for later
## proofs. Adds "newly_resolved", "unlocked_deduction",
## "newly_resolved_questions" and "case_solved" to the classify result.
static func commit_attempt(case_def: Dictionary, session: DeductionSession, claim_id: String, relation: String, selection: Variant) -> Dictionary:
	var result: Dictionary = classify_attempt(case_def, session, claim_id, relation, selection)
	var category: String = result.get("category", INVALID_INPUT)
	session.record_attempt(claim_id, relation, category)
	if not is_valid_category(category):
		result["case_solved"] = session.is_solved()
		return result

	var resolved_before: Array[String] = get_question_status(case_def, session).get("resolved", [] as Array[String])
	var status: String = status_for_relation(relation)
	var is_derived: bool = INPUT_KINDS.has(str(find_claim(case_def, claim_id).get("kind", "")))
	if session.resolve_claim(claim_id, status, is_derived):
		result["newly_resolved"] = true
		if is_derived and status == DeductionSession.STATUS_SUPPORTED:
			result["unlocked_deduction"] = claim_id

	var newly_resolved_questions: Array[String] = []
	for question_id in get_question_status(case_def, session).get("resolved", [] as Array[String]):
		if not resolved_before.has(question_id):
			newly_resolved_questions.append(question_id)
	result["newly_resolved_questions"] = newly_resolved_questions
	if is_case_solved(case_def, session):
		session.mark_solved()
	result["case_solved"] = session.is_solved()
	return result


# ---------------------------------------------------------------------------
# Questions

## {"resolved": Array[String], "unresolved": Array[String],
##  "required_unresolved": Array[String]}, in authored order. A question is
## resolved once ANY of its "resolved_by" {claim, status} entries holds.
static func get_question_status(case_def: Dictionary, session: DeductionSession) -> Dictionary:
	var resolved: Array[String] = []
	var unresolved: Array[String] = []
	var required_unresolved: Array[String] = []
	for question in dict_array(case_def.get("questions", [])):
		var question_id: String = str(question.get("id", ""))
		var is_resolved := false
		for entry in dict_array(question.get("resolved_by", [])):
			if session.get_claim_status(str(entry.get("claim", ""))) == str(entry.get("status", "")):
				is_resolved = true
				break
		if is_resolved:
			resolved.append(question_id)
		else:
			unresolved.append(question_id)
			if question.get("required", false) == true:
				required_unresolved.append(question_id)
	return {"resolved": resolved, "unresolved": unresolved, "required_unresolved": required_unresolved}


## Solved once every required question is resolved (a case with no required
## question is never solved — DeductionValidator rejects that shape).
static func is_case_solved(case_def: Dictionary, session: DeductionSession) -> bool:
	var has_required := false
	for question in dict_array(case_def.get("questions", [])):
		if question.get("required", false) == true:
			has_required = true
			break
	return has_required and (get_question_status(case_def, session).get("required_unresolved", []) as Array).is_empty()


# ---------------------------------------------------------------------------
# Hints

## Reveals the next authored hint level for `target_id` (a claim with a hint
## ladder) — the ONLY call that hands a caller answer-bearing information, and
## only what the author configured for that level. Level 4 names an
## intermediate deduction as information; it does not commit it. Asking past
## the last level repeats it with "exhausted": true. Returns
## {"available": false, ...} when the target has no ladder.
static func request_hint(case_def: Dictionary, session: DeductionSession, target_id: String) -> Dictionary:
	var levels: Array[Dictionary] = []
	for ladder in dict_array(case_def.get("hints", [])):
		if str(ladder.get("target", "")) == target_id:
			levels = dict_array(ladder.get("levels", []))
			break
	if levels.is_empty():
		return {"available": false, "target": target_id, "level": 0, "exhausted": false}
	var current: int = session.get_hint_level(target_id)
	var is_exhausted: bool = current >= levels.size()
	var next_level: int = mini(current + 1, levels.size())
	if not is_exhausted:
		session.advance_hint(target_id, next_level)
	var hint: Dictionary = levels[next_level - 1].duplicate(true)
	hint["available"] = true
	hint["target"] = target_id
	hint["level"] = next_level
	hint["exhausted"] = is_exhausted
	return hint


# ---------------------------------------------------------------------------
# Timeline

## Convenience pass-through so a prototype screen needs one service, not two.
static func evaluate_timeline(case_def: Dictionary, placements: Variant) -> Dictionary:
	return TimelineEvaluator.evaluate(case_def, placements)


# ---------------------------------------------------------------------------
# Shared helpers (also used by DeductionValidator)

static func dict_array(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry in value:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append(entry)
	return out


static func string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry in value:
		if typeof(entry) == TYPE_STRING:
			out.append(entry)
	return out


static func _find_by_id(entries: Variant, entry_id: String) -> Dictionary:
	for entry in dict_array(entries):
		if str(entry.get("id", "")) == entry_id:
			return entry
	return {}


static func _result(category: String, claim_id: String, relation: String, reason: String = "") -> Dictionary:
	var no_questions: Array[String] = []
	return {
		"category": category,
		"claim_id": claim_id,
		"relation": relation,
		"reason": reason,
		"proof_set_id": "",
		"newly_resolved": false,
		"unlocked_deduction": "",
		"newly_resolved_questions": no_questions,
		"case_solved": false,
	}
