class_name PrototypeBPresenter
extends RefCounted
## Builds the Prototype B player view model (Milestone 1.12 — see
## docs/prototype-b.md) from a deduction case_def + PrototypeBController.
## Stateless static helpers, like PrototypeAPresenter/DeductionLabPresenter —
## no autoloads.
##
## build_player_view() is the ONLY place Prototype B's player-facing contract
## is assembled. It is an explicit ALLOW-LIST: the raw case_def is never
## handed to a rendering widget, domain ids never appear (drafts/evidence/
## slots/hint are addressed by opaque handles resolved back ONLY by the
## caller, scripts/debug/prototype_b.gd, immediately before calling a
## controller method), and no question's TARGET claim text/status appears
## until the committed theory is accepted — "resolved_claims" is an entirely
## absent key before that, never merely blank.
##
## Milestone 1.14 (docs/resolution-policy.md): every question is a draft tab
## ("drafts"), always labeled as an unverified draft — the view never says
## whether a draft is correct, only whether it is filled/saved. The
## resolution status is always present; the "assistance" block (the affected
## question plus the base hint ladder's category level) exists only once
## assistance was acknowledged.
##
## build_feedback() maps one controller result to player-facing text: the
## same generic rejection for every invalid theory (never which draft or clue
## on a first failure, never per-clue correctness or a "2 of 3" count), ONE
## affected question from the second failure on, and the authored deduction
## texts/explanations only once a theory — or partner resolution — is
## accepted.

const FEEDBACK_SUCCESS_HEADLINE_KEY := "UI_PROTOTYPE_B_FEEDBACK_SUCCESS_HEADLINE"
const FEEDBACK_REJECTED_KEY := "UI_PROTOTYPE_B_FEEDBACK_THEORY_REJECTED"
const FEEDBACK_GUIDED_KEY := "UI_PROTOTYPE_B_FEEDBACK_GUIDED"
const FEEDBACK_INVALID_KEY := "UI_PROTOTYPE_B_FEEDBACK_INVALID"
const FEEDBACK_DUPLICATE_KEY := "UI_PROTOTYPE_B_FEEDBACK_DUPLICATE"
const FEEDBACK_ALREADY_ACCEPTED_KEY := "UI_PROTOTYPE_B_FEEDBACK_ALREADY_ACCEPTED"
const FEEDBACK_LOCKED_KEY := "UI_RESOLUTION_SUBMISSION_LOCKED"
const FEEDBACK_INTERNAL_ERROR_KEY := "UI_RESOLUTION_INTERNAL_ERROR"
const PARTNER_HEADLINE_KEY := "UI_RESOLUTION_PARTNER_HEADLINE"
const PARTNER_NOTE_KEY := "UI_PROTOTYPE_B_PARTNER_NOTE"
const ASSISTANCE_HEADLINE_KEY := "UI_RESOLUTION_ASSISTANCE_HEADLINE"
const ASSISTANCE_FOCUS_KEY := "UI_PROTOTYPE_B_ASSISTANCE_FOCUS"
## Assistance reuses the target's base hint ladder at this level — the
## compare_categories step. Level 3 names the evidence group itself, which
## assistance must never do.
const ASSISTANCE_LADDER_LEVEL := 2


# ---------------------------------------------------------------------------
# Player view

## Returns {"view": Dictionary, "handle_map": Dictionary} — see class doc.
## `controller` must have an active session (start() already called). A
## draft's handle maps to its draft index as a String.
static func build_player_view(case_def: Dictionary, controller: PrototypeBController) -> Dictionary:
	var handle_map: Dictionary = {}
	var counters: Dictionary = {}
	var session: DeductionSession = controller.get_session()
	var active_index: int = controller.get_active_draft_index()
	var active_round: Dictionary = controller.get_active_round()
	var active_target: String = str(active_round.get("target", ""))
	var selected_ids: Array[String] = controller.get_selected_evidence_ids()

	var drafts: Array[Dictionary] = []
	var active_draft_handle: String = ""
	var draft_handles: Dictionary = {}
	for i in controller.get_draft_count():
		var handle: String = _next_handle(counters, "Q")
		handle_map[handle] = str(i)
		draft_handles[i] = handle
		if i == active_index:
			active_draft_handle = handle
		drafts.append({
			"handle": handle,
			"number": i + 1,
			"question": _t(controller.get_draft_round(i).get("question", "")),
			"slot_count": controller.get_slot_count(i),
			"filled_count": controller.get_selected_evidence_ids(i).size(),
			"complete": controller.is_draft_complete(i),
			"saved": controller.is_draft_saved(i),
			"active": i == active_index,
		})

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
	for i in controller.get_slot_count():
		var evidence_id: String = selected_ids[i] if i < selected_ids.size() else ""
		slots.append({
			"index": i,
			"filled": evidence_id != "",
			"evidence_handle": handle_by_evidence_id.get(evidence_id, ""),
		})

	var hint: Dictionary = {}
	var ladder_levels: Array[Dictionary] = _ladder_levels(case_def, active_target)
	if not ladder_levels.is_empty() and session != null:
		var revealed_count: int = session.get_hint_level(active_target)
		var revealed_texts: Array[String] = []
		for i in mini(revealed_count, ladder_levels.size()):
			revealed_texts.append(_t(ladder_levels[i].get("text", "")))
		var handle: String = _next_handle(counters, "H")
		handle_map[handle] = active_target
		hint = {
			"handle": handle,
			"levels_revealed": revealed_texts,
			"total_levels": ladder_levels.size(),
			"can_reveal_more": revealed_count < ladder_levels.size(),
		}

	var stats: Dictionary = controller.get_stats()
	var completion_lines: Array[String] = []
	if controller.is_completed():
		completion_lines = ResolutionPresenter.build_completion_lines(controller.get_policy(), int(stats.get("elapsed_ms", 0)), int(stats.get("hints_used", 0)), [
			_t("UI_PROTOTYPE_B_STATS_OPENED") % int(stats.get("opened", 0)),
			_t("UI_PROTOTYPE_B_STATS_REPLACEMENTS") % int(stats.get("replacements", 0)),
			_t("UI_PROTOTYPE_B_STATS_DRAFTS_SAVED") % int(stats.get("drafts_saved", 0)),
		] as Array[String])

	var view: Dictionary = {
		"non_canon": case_def.get("metadata", {}).get("canon", true) == false,
		"case_title": _t(case_def.get("display_name", "")),
		"case_description": _t(case_def.get("description", "")),
		"completed": controller.is_completed(),
		"theory_accepted": controller.is_theory_accepted(),
		"drafts": drafts,
		"active_draft_handle": active_draft_handle,
		"question": _t(active_round.get("question", "")),
		"slot_count": controller.get_slot_count(),
		"slots": slots,
		"can_commit": controller.can_commit_theory(),
		"known_failed_theory": controller.is_known_failed_theory(),
		"evidence": evidence,
		"hint": hint,
		"resolution_status": ResolutionPresenter.build_status(controller.get_policy()),
		"stats": stats,
		"completion_text": _t(case_def.get("prototype_b", {}).get("completion_text", "")) if controller.is_completed() else "",
		"completion_lines": completion_lines,
	}

	if controller.is_theory_accepted():
		var resolved_claims: Array[Dictionary] = []
		for i in controller.get_draft_count():
			var round_def: Dictionary = controller.get_draft_round(i)
			var target: String = str(round_def.get("target", ""))
			var handle: String = _next_handle(counters, "D")
			handle_map[handle] = target
			resolved_claims.append({
				"handle": handle,
				"question": _t(round_def.get("question", "")),
				"text": _t(DeductionEvaluator.find_claim(case_def, target).get("text", "")),
			})
		view["resolved_claims"] = resolved_claims

	var assistance_index: int = controller.get_assistance_draft_index()
	if assistance_index >= 0 and not controller.is_completed():
		var assistance_round: Dictionary = controller.get_draft_round(assistance_index)
		var levels: Array[Dictionary] = _ladder_levels(case_def, str(assistance_round.get("target", "")))
		view["assistance"] = {
			"headline": _t(ASSISTANCE_HEADLINE_KEY),
			"draft_handle": draft_handles.get(assistance_index, ""),
			"focus": _t(ASSISTANCE_FOCUS_KEY) % _t(assistance_round.get("question", "")),
			"category_hint": _t(levels[ASSISTANCE_LADDER_LEVEL - 1].get("text", "")) if levels.size() >= ASSISTANCE_LADDER_LEVEL else "",
		}
	return {"view": view, "handle_map": handle_map}


# ---------------------------------------------------------------------------
# Feedback — maps one PrototypeBController result to player-facing text.

## `result` is whatever PrototypeBController.commit_theory() or
## resolve_with_partner() returned. Returns {"success", "partner", "headline",
## "deduction_text", "explanation", "partner_note", "resolution_notice"}.
static func build_feedback(case_def: Dictionary, controller: PrototypeBController, result: Dictionary) -> Dictionary:
	var feedback: Dictionary = {
		"success": false, "partner": false, "headline": "", "deduction_text": "", "explanation": "", "partner_note": "",
		"resolution_notice": ResolutionPresenter.build_commit_notice(result.get("resolution", {})),
	}
	var category: String = str(result.get("category", ""))

	if category == PrototypeBController.RESULT_THEORY_ACCEPTED:
		var is_partner: bool = result.get("partner", false) == true
		feedback["success"] = true
		feedback["partner"] = is_partner
		feedback["headline"] = _t(PARTNER_HEADLINE_KEY if is_partner else FEEDBACK_SUCCESS_HEADLINE_KEY)
		var deduction_lines: Array[String] = []
		var explanation_lines: Array[String] = []
		for i in controller.get_draft_count():
			var round_def: Dictionary = controller.get_draft_round(i)
			deduction_lines.append(_t(DeductionEvaluator.find_claim(case_def, str(round_def.get("target", ""))).get("text", "")))
			explanation_lines.append(_t(round_def.get("success_explanation", "")))
		feedback["deduction_text"] = "\n\n".join(deduction_lines)
		feedback["explanation"] = "\n\n".join(explanation_lines)
		if is_partner:
			var notes: Array[String] = []
			for index in result.get("partner_draft_indices", []):
				var names: Array[String] = []
				for evidence_id in controller.get_selected_evidence_ids(int(index)):
					names.append(_t(DeductionEvaluator.find_evidence(case_def, evidence_id).get("name", "")))
				notes.append(_t(PARTNER_NOTE_KEY) % [_t(controller.get_draft_round(int(index)).get("question", "")), ", ".join(names)])
			feedback["partner_note"] = "\n".join(notes)
		return feedback

	if category == PrototypeBController.RESULT_THEORY_REJECTED:
		var lines: Array[String] = [_t(FEEDBACK_REJECTED_KEY)]
		if result.get("feedback_level", "") == PrototypeBController.FEEDBACK_GUIDED and result.has("affected_draft_index"):
			var affected: Dictionary = controller.get_draft_round(int(result.get("affected_draft_index", 0)))
			lines.append(_t(FEEDBACK_GUIDED_KEY) % _t(affected.get("question", "")))
		feedback["explanation"] = "\n".join(lines)
		return feedback

	var body_key: String = FEEDBACK_INVALID_KEY
	match str(result.get("reason", "")):
		PrototypeBController.REASON_DUPLICATE_THEORY:
			body_key = FEEDBACK_DUPLICATE_KEY
		PrototypeBController.REASON_ALREADY_ACCEPTED:
			body_key = FEEDBACK_ALREADY_ACCEPTED_KEY
		PrototypeBController.REASON_SUBMISSION_LOCKED, PrototypeBController.REASON_PARTNER_UNAVAILABLE:
			body_key = FEEDBACK_LOCKED_KEY
		PrototypeBController.REASON_INTERNAL_ERROR:
			body_key = FEEDBACK_INTERNAL_ERROR_KEY
	feedback["explanation"] = _t(body_key)
	return feedback


# ---------------------------------------------------------------------------
# Helpers

static func _ladder_levels(case_def: Dictionary, target: String) -> Array[Dictionary]:
	for ladder in DeductionEvaluator.dict_array(case_def.get("hints", [])):
		if str(ladder.get("target", "")) == target:
			return DeductionEvaluator.dict_array(ladder.get("levels", []))
	return []


static func _next_handle(counters: Dictionary, prefix: String) -> String:
	var n: int = counters.get(prefix, 0)
	counters[prefix] = n + 1
	return "%s%d" % [prefix, n]


static func _t(key: Variant) -> String:
	if typeof(key) != TYPE_STRING or key == "":
		return ""
	return String(TranslationServer.translate(key))
