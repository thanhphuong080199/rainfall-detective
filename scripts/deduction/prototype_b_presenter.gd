class_name PrototypeBPresenter
extends RefCounted
## Builds the Prototype B player view model (Milestone 1.12 — see
## docs/prototype-b.md) from a deduction case_def + PrototypeBController.
## Stateless static helpers, like PrototypeAPresenter/DeductionLabPresenter —
## no autoloads.
##
## build_player_view() is the ONLY place Prototype B's player-facing contract
## is assembled. It is an explicit ALLOW-LIST: the raw case_def is never
## handed to a rendering widget, domain ids never appear (evidence/slots/hint
## are addressed by opaque handles resolved back to real ids ONLY by the
## caller, scripts/debug/prototype_b.gd, immediately before calling a
## controller method), and the round's TARGET claim's text/status is entirely
## absent from the view until the session has actually resolved it — the
## deduction, its relation, and its proof set are never revealed in advance.
## Only the CURRENT round's question/slots/hint ever appear; a future round's
## content is invisible until the player actually reaches it.
##
## build_feedback() maps one evaluator result to player-facing text: a
## generic, case-independent message for each non-winning category (never
## revealing which clue was missing, wrong, or extra), or the round's own
## authored success_explanation plus the now-revealed deduction's own
## (already-translated) statement once a submission actually resolves it.

const FEEDBACK_SUCCESS_HEADLINE_KEY := "UI_PROTOTYPE_B_FEEDBACK_SUCCESS_HEADLINE"
const FEEDBACK_IRRELEVANT_KEY := "UI_PROTOTYPE_B_FEEDBACK_IRRELEVANT"
const FEEDBACK_INSUFFICIENT_KEY := "UI_PROTOTYPE_B_FEEDBACK_INSUFFICIENT"
const FEEDBACK_COMPATIBLE_KEY := "UI_PROTOTYPE_B_FEEDBACK_COMPATIBLE"
const FEEDBACK_INVALID_KEY := "UI_PROTOTYPE_B_FEEDBACK_INVALID"


# ---------------------------------------------------------------------------
# Player view

## Returns {"view": Dictionary, "handle_map": Dictionary} — see class doc.
## `controller` must have an active session (start() already called).
static func build_player_view(case_def: Dictionary, controller: PrototypeBController) -> Dictionary:
	var handle_map: Dictionary = {}
	var counters: Dictionary = {}
	var session: DeductionSession = controller.get_session()
	var pb_round: Dictionary = controller.get_current_round()
	var target: String = str(pb_round.get("target", ""))
	var slot_count: int = controller.get_slot_count()
	var selected_ids: Array[String] = controller.get_selected_evidence_ids()

	var evidence: Array[Dictionary] = []
	var handle_by_evidence_id: Dictionary = {}
	for evidence_id in controller.get_evidence_pool_ids():
		var item: Dictionary = DeductionEvaluator.find_evidence(case_def, evidence_id)
		var handle: String = _next_handle(counters, "E")
		handle_map[handle] = evidence_id
		handle_by_evidence_id[evidence_id] = handle
		var opened: bool = session != null and session.has_opened_evidence(evidence_id)
		evidence.append({
			"handle": handle,
			"name": _t(item.get("name", "")),
			"opened": opened,
			"text": _t(item.get("text", "")) if opened else "",
			"selected": selected_ids.has(evidence_id),
		})

	var slots: Array[Dictionary] = []
	for i in slot_count:
		var evidence_id: String = selected_ids[i] if i < selected_ids.size() else ""
		slots.append({
			"index": i,
			"filled": evidence_id != "",
			"evidence_handle": handle_by_evidence_id.get(evidence_id, ""),
		})

	var is_resolved: bool = session != null and target != "" and session.get_claim_status(target) != ""
	var resolved_claim: Dictionary = {}
	if is_resolved:
		var claim: Dictionary = DeductionEvaluator.find_claim(case_def, target)
		var handle: String = _next_handle(counters, "D")
		handle_map[handle] = target
		resolved_claim = {"handle": handle, "text": _t(claim.get("text", ""))}

	var hint: Dictionary = {}
	if target != "" and session != null:
		var levels: Array[Dictionary] = []
		for ladder in DeductionEvaluator.dict_array(case_def.get("hints", [])):
			if str(ladder.get("target", "")) == target:
				levels = DeductionEvaluator.dict_array(ladder.get("levels", []))
				break
		if not levels.is_empty():
			var revealed_count: int = session.get_hint_level(target)
			var revealed_texts: Array[String] = []
			for i in mini(revealed_count, levels.size()):
				revealed_texts.append(_t(levels[i].get("text", "")))
			var handle: String = _next_handle(counters, "H")
			handle_map[handle] = target
			hint = {
				"handle": handle,
				"levels_revealed": revealed_texts,
				"total_levels": levels.size(),
				"can_reveal_more": revealed_count < levels.size(),
			}

	var view: Dictionary = {
		"non_canon": case_def.get("metadata", {}).get("canon", true) == false,
		"case_title": _t(case_def.get("display_name", "")),
		"case_description": _t(case_def.get("description", "")),
		"round_index": controller.get_round_index(),
		"round_count": controller.get_round_count(),
		"completed": controller.is_completed(),
		"question": _t(pb_round.get("question", "")),
		"slot_count": slot_count,
		"slots": slots,
		"can_submit": controller.can_submit(),
		"evidence": evidence,
		"resolved": is_resolved,
		"resolved_claim": resolved_claim,
		"hint": hint,
		"stats": controller.get_stats(),
		"completion_text": _t(case_def.get("prototype_b", {}).get("completion_text", "")) if controller.is_completed() else "",
	}
	return {"view": view, "handle_map": handle_map}


# ---------------------------------------------------------------------------
# Feedback — maps one DeductionEvaluator/PrototypeBController result to
# player-facing text. Never shows a raw category enum name, never reveals
# which clue was missing/wrong/extra, and never reveals the accepted proof
# set — only a genuine success reveals case-authored text.

## `result` is whatever PrototypeBController.submit_connection() returned.
## `controller` supplies the current round's authored success_explanation and
## the now-provable target claim's own (translated) text — read ONLY when
## `result` is actually a success, so nothing leaks on a failed attempt.
## Returns {"success": bool, "headline": String, "deduction_text": String,
## "explanation": String} — "deduction_text"/"explanation" are case-authored
## text, populated only on success; every other outcome gets a fixed,
## generic, non-spoiling message.
static func build_feedback(case_def: Dictionary, controller: PrototypeBController, result: Dictionary) -> Dictionary:
	var category: String = str(result.get("category", ""))
	if DeductionEvaluator.is_valid_category(category):
		var pb_round: Dictionary = controller.get_current_round()
		var target: String = str(pb_round.get("target", ""))
		var claim: Dictionary = DeductionEvaluator.find_claim(case_def, target)
		return {
			"success": true,
			"headline": _t(FEEDBACK_SUCCESS_HEADLINE_KEY),
			"deduction_text": _t(claim.get("text", "")),
			"explanation": _t(pb_round.get("success_explanation", "")),
		}

	var body_key: String = FEEDBACK_INVALID_KEY
	match category:
		DeductionEvaluator.IRRELEVANT_EVIDENCE:
			body_key = FEEDBACK_IRRELEVANT_KEY
		DeductionEvaluator.INSUFFICIENT_EVIDENCE:
			body_key = FEEDBACK_INSUFFICIENT_KEY
		DeductionEvaluator.COMPATIBLE_NOT_PROOF:
			body_key = FEEDBACK_COMPATIBLE_KEY
	return {"success": false, "headline": "", "deduction_text": "", "explanation": _t(body_key)}


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
