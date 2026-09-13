class_name PrototypeAPresenter
extends RefCounted
## Builds the Prototype A player view model (Milestone 1.11 — see
## docs/prototype-a.md) from a deduction case_def + PrototypeAController.
## Stateless static helpers, like DeductionLabPresenter — no autoloads.
##
## build_player_view() is the ONLY place Prototype A's player-facing contract
## is assembled. It is an explicit ALLOW-LIST, exactly like
## DeductionLabPresenter.build_player_view(): the raw case_def is never
## handed to a rendering widget, domain ids never appear (statements/evidence/
## hints are addressed by opaque handles resolved back to real ids ONLY by
## the caller, scripts/debug/prototype_a.gd, immediately before calling a
## controller method), and a statement's "outcome" (required/optional) is
## always "" until the session has actually resolved it — the authored
## classification is never revealed in advance.
##
## build_feedback() maps one evaluator result to player-facing text: a
## generic, case-independent message for each non-winning category
## (never revealing which item would have worked), or the round's own
## authored success_explanations/witness_responses once a submission
## actually resolves a required or optional contradiction.

const FEEDBACK_IRRELEVANT_KEY := "UI_PROTOTYPE_A_FEEDBACK_IRRELEVANT"
const FEEDBACK_INSUFFICIENT_KEY := "UI_PROTOTYPE_A_FEEDBACK_INSUFFICIENT"
const FEEDBACK_COMPATIBLE_KEY := "UI_PROTOTYPE_A_FEEDBACK_COMPATIBLE"
const FEEDBACK_INVALID_KEY := "UI_PROTOTYPE_A_FEEDBACK_INVALID"
const FEEDBACK_SUCCESS_HEADLINE_KEY := "UI_PROTOTYPE_A_FEEDBACK_SUCCESS_HEADLINE"
const FEEDBACK_OPTIONAL_HEADLINE_KEY := "UI_PROTOTYPE_A_FEEDBACK_OPTIONAL_HEADLINE"


# ---------------------------------------------------------------------------
# Player view

## Returns {"view": Dictionary, "handle_map": Dictionary} — see class doc.
## `controller` must have an active session (start() already called).
static func build_player_view(case_def: Dictionary, controller: PrototypeAController) -> Dictionary:
	var handle_map: Dictionary = {}
	var counters: Dictionary = {}
	var session: DeductionSession = controller.get_session()

	var suspects: Array[Dictionary] = []
	for suspect in DeductionEvaluator.dict_array(case_def.get("suspects", [])):
		var handle: String = _next_handle(counters, "S")
		handle_map[handle] = str(suspect.get("id", ""))
		suspects.append({"handle": handle, "name": _t(suspect.get("name", ""))})

	var suspect_name_by_id: Dictionary = {}
	for suspect in DeductionEvaluator.dict_array(case_def.get("suspects", [])):
		suspect_name_by_id[str(suspect.get("id", ""))] = _t(suspect.get("name", ""))

	var pa_round: Dictionary = controller.get_current_round()
	var required: Array[String] = DeductionEvaluator.string_array(pa_round.get("required_refutations", []))
	var optional: Array[String] = DeductionEvaluator.string_array(pa_round.get("optional_refutations", []))
	var resolved_claims: Dictionary = session.get_resolved_claims() if session != null else {}
	var current_statement_id: String = controller.get_current_statement_id()

	var statements: Array[Dictionary] = []
	var current_statement_handle: String = ""
	for claim_id in controller.get_statement_ids():
		var claim: Dictionary = DeductionEvaluator.find_claim(case_def, claim_id)
		var handle: String = _next_handle(counters, "T")
		handle_map[handle] = claim_id
		var status: String = str(resolved_claims.get(claim_id, ""))
		var is_resolved: bool = status != ""
		var outcome: String = ""
		if is_resolved:
			if required.has(claim_id):
				outcome = "required"
			elif optional.has(claim_id):
				outcome = "optional"
		statements.append({
			"handle": handle,
			"text": _t(claim.get("text", "")),
			"speaker": suspect_name_by_id.get(str(claim.get("speaker", "")), ""),
			"resolved": is_resolved,
			"outcome": outcome,
		})
		if claim_id == current_statement_id:
			current_statement_handle = handle

	var selected_evidence_id: String = controller.get_selected_evidence_id()
	var evidence: Array[Dictionary] = []
	var selected_evidence_handle: String = ""
	for evidence_id in controller.get_evidence_pool_ids():
		var item: Dictionary = DeductionEvaluator.find_evidence(case_def, evidence_id)
		var handle: String = _next_handle(counters, "E")
		handle_map[handle] = evidence_id
		var opened: bool = session != null and session.has_opened_evidence(evidence_id)
		evidence.append({
			"handle": handle,
			"name": _t(item.get("name", "")),
			"opened": opened,
			"text": _t(item.get("text", "")) if opened else "",
			"selected": evidence_id == selected_evidence_id,
		})
		if evidence_id == selected_evidence_id:
			selected_evidence_handle = handle

	var hint: Dictionary = {}
	if current_statement_id != "":
		var ladder: Array[String] = controller.get_hint_ladder(current_statement_id)
		if not ladder.is_empty():
			var revealed_count: int = controller.get_hint_level(current_statement_id)
			var revealed_texts: Array[String] = []
			for i in mini(revealed_count, ladder.size()):
				revealed_texts.append(_t(ladder[i]))
			var handle: String = _next_handle(counters, "H")
			handle_map[handle] = current_statement_id
			hint = {
				"handle": handle,
				"levels_revealed": revealed_texts,
				"total_levels": ladder.size(),
				"can_reveal_more": revealed_count < ladder.size(),
			}

	var view: Dictionary = {
		"non_canon": case_def.get("metadata", {}).get("canon", true) == false,
		"case_title": _t(case_def.get("display_name", "")),
		"case_description": _t(case_def.get("description", "")),
		"suspects": suspects,
		"round_index": controller.get_round_index(),
		"round_count": controller.get_round_count(),
		"completed": controller.is_completed(),
		"current_statement_handle": current_statement_handle,
		"statements": statements,
		"evidence": evidence,
		"selected_evidence_handle": selected_evidence_handle,
		"hint": hint,
		"stats": controller.get_stats(),
		"completion_text": _t(case_def.get("prototype_a", {}).get("completion_text", "")) if controller.is_completed() else "",
	}
	return {"view": view, "handle_map": handle_map}


# ---------------------------------------------------------------------------
# Feedback — maps one DeductionEvaluator/PrototypeAController result to
# player-facing text. Never shows a raw category enum name.

## `result` is whatever PrototypeAController.present_evidence() returned.
## Returns {"success": bool, "optional": bool, "headline": String,
## "explanation": String, "witness_response": String} — "explanation"/
## "witness_response" are case-authored text (only populated on success);
## every other outcome gets a fixed, generic, non-spoiling message.
static func build_feedback(case_def: Dictionary, result: Dictionary) -> Dictionary:
	var category: String = str(result.get("category", ""))
	var claim_id: String = str(result.get("claim_id", ""))
	var outcome: String = str(result.get("outcome", ""))

	if DeductionEvaluator.is_valid_category(category) and (outcome == "required" or outcome == "optional"):
		var pa_round: Dictionary = _find_round_for_claim(case_def, claim_id)
		var explanations: Variant = pa_round.get("success_explanations", {})
		var responses: Variant = pa_round.get("witness_responses", {})
		return {
			"success": true,
			"optional": outcome == "optional",
			"headline": _t(FEEDBACK_OPTIONAL_HEADLINE_KEY if outcome == "optional" else FEEDBACK_SUCCESS_HEADLINE_KEY),
			"explanation": _t((explanations as Dictionary).get(claim_id, "")) if typeof(explanations) == TYPE_DICTIONARY else "",
			"witness_response": _t((responses as Dictionary).get(claim_id, "")) if typeof(responses) == TYPE_DICTIONARY else "",
		}

	var body_key: String = FEEDBACK_INVALID_KEY
	match category:
		DeductionEvaluator.IRRELEVANT_EVIDENCE:
			body_key = FEEDBACK_IRRELEVANT_KEY
		DeductionEvaluator.INSUFFICIENT_EVIDENCE:
			body_key = FEEDBACK_INSUFFICIENT_KEY
		DeductionEvaluator.COMPATIBLE_NOT_PROOF:
			body_key = FEEDBACK_COMPATIBLE_KEY
	return {"success": false, "optional": false, "headline": "", "explanation": _t(body_key), "witness_response": ""}


static func _find_round_for_claim(case_def: Dictionary, claim_id: String) -> Dictionary:
	for pa_round in DeductionEvaluator.dict_array(case_def.get("prototype_a", {}).get("rounds", [])):
		var explanations: Variant = pa_round.get("success_explanations", {})
		if typeof(explanations) == TYPE_DICTIONARY and (explanations as Dictionary).has(claim_id):
			return pa_round
	return {}


# ---------------------------------------------------------------------------
# Helpers

static func _next_handle(counters: Dictionary, prefix: String) -> String:
	var n: int = counters.get(prefix, 0)
	counters[prefix] = n + 1
	return "%s%d" % [prefix, n]


static func _t(key: Variant) -> String:
	if typeof(key) != TYPE_STRING or key == "":
		return ""
	return String(TranslationServer.translate(key))
