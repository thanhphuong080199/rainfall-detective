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
## Milestone 1.14 (docs/resolution-policy.md): the view also carries the
## credibility/tier status ("resolution_status", localized, no raw enum ids)
## and — ONLY once assistance has actually been acknowledged — an "assistance"
## block naming the statement to focus on plus a category-level hint. The
## assistance key is entirely absent before that, never merely blank.
##
## build_feedback() maps one controller result to player-facing text: a
## generic, case-independent message for each non-winning category (never
## revealing which item would have worked) plus a generic rebuttal and the
## credibility consequence, or the round's own authored success_explanations/
## witness_responses once a submission — or partner resolution — actually
## resolves a required or optional contradiction.

const FEEDBACK_IRRELEVANT_KEY := "UI_PROTOTYPE_A_FEEDBACK_IRRELEVANT"
const FEEDBACK_INSUFFICIENT_KEY := "UI_PROTOTYPE_A_FEEDBACK_INSUFFICIENT"
const FEEDBACK_COMPATIBLE_KEY := "UI_PROTOTYPE_A_FEEDBACK_COMPATIBLE"
const FEEDBACK_INVALID_KEY := "UI_PROTOTYPE_A_FEEDBACK_INVALID"
const FEEDBACK_DUPLICATE_KEY := "UI_PROTOTYPE_A_FEEDBACK_DUPLICATE"
const FEEDBACK_LOCKED_KEY := "UI_RESOLUTION_SUBMISSION_LOCKED"
const FEEDBACK_INTERNAL_ERROR_KEY := "UI_RESOLUTION_INTERNAL_ERROR"
const FEEDBACK_SUCCESS_HEADLINE_KEY := "UI_PROTOTYPE_A_FEEDBACK_SUCCESS_HEADLINE"
const FEEDBACK_OPTIONAL_HEADLINE_KEY := "UI_PROTOTYPE_A_FEEDBACK_OPTIONAL_HEADLINE"
const PARTNER_HEADLINE_KEY := "UI_RESOLUTION_PARTNER_HEADLINE"
const PARTNER_NOTE_KEY := "UI_PROTOTYPE_A_PARTNER_NOTE"
const REBUTTAL_KEY := "UI_PROTOTYPE_A_REBUTTAL"
const CREDIBILITY_KEY := "UI_PROTOTYPE_A_CREDIBILITY"
const ASSISTANCE_HEADLINE_KEY := "UI_RESOLUTION_ASSISTANCE_HEADLINE"
const ASSISTANCE_FOCUS_KEY := "UI_PROTOTYPE_A_ASSISTANCE_FOCUS"
const STATS_OPTIONAL_KEY := "UI_PROTOTYPE_A_STATS_OPTIONAL"
## Assistance reuses the target's own authored hint ladder at this level — the
## category-narrowing step. Level 3+ names the evidence itself, which
## assistance must never do.
const ASSISTANCE_LADDER_LEVEL := 2


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

	var pa_round: Dictionary = controller.get_current_round()
	var required: Array[String] = DeductionEvaluator.string_array(pa_round.get("required_refutations", []))
	var optional: Array[String] = DeductionEvaluator.string_array(pa_round.get("optional_refutations", []))
	var resolved_claims: Dictionary = session.get_resolved_claims() if session != null else {}
	var current_statement_id: String = controller.get_current_statement_id()
	var assistance_target_id: String = controller.get_assistance_target_id()

	var statements: Array[Dictionary] = []
	var current_statement_handle: String = ""
	var assistance_statement: Dictionary = {}
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
		var entry: Dictionary = {
			"handle": handle,
			"text": _t(claim.get("text", "")),
			"speaker": _speaker_name(case_def, claim),
			"resolved": is_resolved,
			"outcome": outcome,
		}
		statements.append(entry)
		if claim_id == current_statement_id:
			current_statement_handle = handle
		if assistance_target_id != "" and claim_id == assistance_target_id:
			assistance_statement = entry

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

	var stats: Dictionary = controller.get_stats()
	var completion_lines: Array[String] = []
	if controller.is_completed():
		completion_lines = ResolutionPresenter.build_completion_lines(controller.get_policy(), int(stats.get("elapsed_ms", 0)), int(stats.get("hints_used", 0)), [
			_t(STATS_OPTIONAL_KEY) % int(stats.get("optional_found", 0)),
		] as Array[String])

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
		"resolution_status": ResolutionPresenter.build_status(controller.get_policy(), CREDIBILITY_KEY),
		"stats": stats,
		"completion_text": _t(case_def.get("prototype_a", {}).get("completion_text", "")) if controller.is_completed() else "",
		"completion_lines": completion_lines,
	}

	if not assistance_statement.is_empty() and not controller.is_completed():
		var ladder: Array[String] = controller.get_hint_ladder(assistance_target_id)
		view["assistance"] = {
			"headline": _t(ASSISTANCE_HEADLINE_KEY),
			"statement_handle": assistance_statement.get("handle", ""),
			"focus": _t(ASSISTANCE_FOCUS_KEY) % [assistance_statement.get("speaker", ""), assistance_statement.get("text", "")],
			"category_hint": _t(ladder[ASSISTANCE_LADDER_LEVEL - 1]) if ladder.size() >= ASSISTANCE_LADDER_LEVEL else "",
		}
	return {"view": view, "handle_map": handle_map}


# ---------------------------------------------------------------------------
# Feedback — maps one PrototypeAController result to player-facing text.
# Never shows a raw category enum name.

## `result` is whatever PrototypeAController.present_evidence() or
## resolve_with_partner() returned. Returns {"success", "optional", "partner",
## "headline", "explanation", "witness_response", "rebuttal", "partner_note",
## "resolution_notice"} — "explanation"/"witness_response"/"partner_note" are
## case-authored (only populated on success); every other outcome gets fixed,
## generic, non-spoiling text: the evaluator-category message, a rebuttal
## that names no evidence, and the credibility/tier consequence.
static func build_feedback(case_def: Dictionary, result: Dictionary) -> Dictionary:
	var category: String = str(result.get("category", ""))
	var claim_id: String = str(result.get("claim_id", ""))
	var outcome: String = str(result.get("outcome", ""))
	var is_partner: bool = result.get("partner", false) == true
	var snapshot: Dictionary = result.get("resolution", {})
	var feedback: Dictionary = {
		"success": false, "optional": false, "partner": false, "headline": "", "explanation": "",
		"witness_response": "", "rebuttal": "", "partner_note": "",
		"resolution_notice": ResolutionPresenter.build_commit_notice(snapshot, CREDIBILITY_KEY),
	}

	if DeductionEvaluator.is_valid_category(category) and (outcome == "required" or outcome == "optional"):
		var pa_round: Dictionary = _find_round_for_claim(case_def, claim_id)
		var explanations: Variant = pa_round.get("success_explanations", {})
		var responses: Variant = pa_round.get("witness_responses", {})
		feedback["success"] = true
		feedback["optional"] = outcome == "optional"
		feedback["partner"] = is_partner
		if is_partner:
			feedback["headline"] = _t(PARTNER_HEADLINE_KEY)
			var evidence: Dictionary = DeductionEvaluator.find_evidence(case_def, str(result.get("evidence_id", "")))
			feedback["partner_note"] = _t(PARTNER_NOTE_KEY) % _t(evidence.get("name", ""))
		else:
			feedback["headline"] = _t(FEEDBACK_OPTIONAL_HEADLINE_KEY if outcome == "optional" else FEEDBACK_SUCCESS_HEADLINE_KEY)
		feedback["explanation"] = _t((explanations as Dictionary).get(claim_id, "")) if typeof(explanations) == TYPE_DICTIONARY else ""
		feedback["witness_response"] = _t((responses as Dictionary).get(claim_id, "")) if typeof(responses) == TYPE_DICTIONARY else ""
		return feedback

	var body_key: String = FEEDBACK_INVALID_KEY
	match str(result.get("reason", "")):
		PrototypeAController.REASON_DUPLICATE_ATTEMPT:
			body_key = FEEDBACK_DUPLICATE_KEY
		PrototypeAController.REASON_SUBMISSION_LOCKED, PrototypeAController.REASON_PARTNER_UNAVAILABLE:
			body_key = FEEDBACK_LOCKED_KEY
		PrototypeAController.REASON_INTERNAL_ERROR:
			body_key = FEEDBACK_INTERNAL_ERROR_KEY
		_:
			match category:
				DeductionEvaluator.IRRELEVANT_EVIDENCE:
					body_key = FEEDBACK_IRRELEVANT_KEY
				DeductionEvaluator.INSUFFICIENT_EVIDENCE:
					body_key = FEEDBACK_INSUFFICIENT_KEY
				DeductionEvaluator.COMPATIBLE_NOT_PROOF:
					body_key = FEEDBACK_COMPATIBLE_KEY
	feedback["explanation"] = _t(body_key)
	if snapshot.get("counted", false) == true and snapshot.get("reason", "") == ResolutionPolicy.REASON_FAILED_COMMIT:
		feedback["rebuttal"] = _t(REBUTTAL_KEY) % _speaker_name(case_def, DeductionEvaluator.find_claim(case_def, claim_id))
	return feedback


static func _find_round_for_claim(case_def: Dictionary, claim_id: String) -> Dictionary:
	for pa_round in DeductionEvaluator.dict_array(case_def.get("prototype_a", {}).get("rounds", [])):
		var explanations: Variant = pa_round.get("success_explanations", {})
		if typeof(explanations) == TYPE_DICTIONARY and (explanations as Dictionary).has(claim_id):
			return pa_round
	return {}


# ---------------------------------------------------------------------------
# Helpers

static func _speaker_name(case_def: Dictionary, claim: Dictionary) -> String:
	var speaker_id: String = str(claim.get("speaker", ""))
	for suspect in DeductionEvaluator.dict_array(case_def.get("suspects", [])):
		if str(suspect.get("id", "")) == speaker_id:
			return _t(suspect.get("name", ""))
	return ""


static func _next_handle(counters: Dictionary, prefix: String) -> String:
	var n: int = counters.get(prefix, 0)
	counters[prefix] = n + 1
	return "%s%d" % [prefix, n]


static func _t(key: Variant) -> String:
	if typeof(key) != TYPE_STRING or key == "":
		return ""
	return String(TranslationServer.translate(key))
