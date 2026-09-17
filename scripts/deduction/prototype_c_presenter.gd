class_name PrototypeCPresenter
extends RefCounted
## Builds the Prototype C player view model (Milestone 1.13 — see
## docs/prototype-c.md) from a deduction case_def + PrototypeCController.
## Stateless static helpers, like PrototypeAPresenter/PrototypeBPresenter —
## no autoloads.
##
## build_player_view() is the ONLY place Prototype C's player-facing contract
## is assembled. It is an explicit ALLOW-LIST: the raw case_def, raw
## constraint dictionaries/types, the authored ground_truth.solution_timeline
## and the disputed claim's veracity are never exposed. Domain ids never
## appear — timeline events and facts are addressed by opaque handles
## resolved back to real ids ONLY by the caller
## (scripts/debug/prototype_c.gd), immediately before calling a controller
## method. The disputed claim (get_claim_statement_id()) is an ENTIRELY
## ABSENT key until the reconstruction is actually accepted — not merely
## blank — exactly matching DeductionLabPresenter's/PrototypeBPresenter's own
## unresolved-claim gating, and its final contradiction explanation is
## likewise absent until the claim is actually resolved correctly.
##
## Milestone 1.14 (docs/resolution-policy.md): the view always carries the
## localized resolution status; an "assistance" block exists only once the
## CURRENT unit's assistance was acknowledged; the claim offers a verdict
## plus a supporting-fact choice (never which fact is right); and feedback is
## progressive — a broad category first, one known fact later — never the
## correct time, the authored solution or a raw constraint id/type.
##
## build_violation_feedback()/build_claim_feedback() map controller results to
## player-facing text: natural-language facts already shown during briefing
## (never raw constraint ids/types, never the correct placement, never how
## close the player is to the authored solution) and the final explanation
## with the player's OWN accepted time interpolated in, so it stays true for
## whichever valid timeline the player actually built.

const FEEDBACK_INVALID_KEY := "UI_PROTOTYPE_C_FEEDBACK_INVALID"
const FEEDBACK_CATEGORY_KEY := "UI_PROTOTYPE_C_FEEDBACK_CATEGORY"
const FEEDBACK_FACT_KEY := "UI_PROTOTYPE_C_FEEDBACK_FACT"
const FEEDBACK_LOCKED_KEY := "UI_RESOLUTION_SUBMISSION_LOCKED"
const FEEDBACK_INTERNAL_ERROR_KEY := "UI_RESOLUTION_INTERNAL_ERROR"
const CATEGORY_KEYS := {
	"anchor": "UI_PROTOTYPE_C_CATEGORY_ANCHOR",
	"window": "UI_PROTOTYPE_C_CATEGORY_WINDOW",
	"order": "UI_PROTOTYPE_C_CATEGORY_ORDER",
	"overlap": "UI_PROTOTYPE_C_CATEGORY_OVERLAP",
	"travel": "UI_PROTOTYPE_C_CATEGORY_TRAVEL",
}
const PARTNER_TIMELINE_NOTE_KEY := "UI_PROTOTYPE_C_PARTNER_TIMELINE_NOTE"
const PARTNER_CLAIM_NOTE_KEY := "UI_PROTOTYPE_C_PARTNER_CLAIM_NOTE"
const ASSISTANCE_HEADLINE_KEY := "UI_RESOLUTION_ASSISTANCE_HEADLINE"
const ASSISTANCE_PAIR_KEY := "UI_PROTOTYPE_C_ASSISTANCE_PAIR"
const ASSISTANCE_CLAIM_KEY := "UI_PROTOTYPE_C_ASSISTANCE_CLAIM"
const JUSTIFICATION_RESULT_KEY := "UI_PROTOTYPE_C_JUSTIFICATION_RESULT"
## Timeline assistance reuses the case's own hint ladder at this level — the
## "narrow the critical event pair" step, which never states a time.
const ASSISTANCE_LADDER_LEVEL := 4


# ---------------------------------------------------------------------------
# Player view

## Returns {"view": Dictionary, "handle_map": Dictionary} — see class doc.
## `controller` must have an active run (start() already called).
static func build_player_view(case_def: Dictionary, controller: PrototypeCController) -> Dictionary:
	var handle_map: Dictionary = {}
	var counters: Dictionary = {}
	var proto: Dictionary = case_def.get("prototype_c", {})

	var events_index: Dictionary = TimelineEvaluator.event_index(case_def)
	var events: Array[Dictionary] = []
	var handle_by_event_id: Dictionary = {}
	var selected_id: String = controller.get_selected_event_id()
	for event_id in controller.get_all_event_ids():
		var event: Dictionary = events_index.get(event_id, {})
		var handle: String = _next_handle(counters, "V")
		handle_map[handle] = event_id
		handle_by_event_id[event_id] = handle
		events.append({
			"handle": handle,
			"label": _t(event.get("label", "")),
			"duration_minutes": controller.get_event_duration_minutes(event_id),
			"fixed": controller.is_fixed(event_id),
			"placement": controller.get_placement(event_id),
			"selected": event_id == selected_id,
		})

	var facts: Array[Dictionary] = []
	var fact_handle_by_id: Dictionary = {}
	for constraint_id in controller.get_fact_ids():
		var opened: bool = controller.has_opened_fact(constraint_id)
		var handle: String = _next_handle(counters, "F")
		handle_map[handle] = constraint_id
		fact_handle_by_id[constraint_id] = handle
		facts.append({
			"handle": handle,
			"opened": opened,
			"text": _t(proto.get("visible_constraint_facts", {}).get(constraint_id, "")) if opened else "",
		})

	var hint: Dictionary = {}
	var ladder: Array[String] = controller.get_hint_ladder()
	if not ladder.is_empty():
		var revealed_count: int = controller.get_hint_level()
		var revealed_texts: Array[String] = []
		for i in mini(revealed_count, ladder.size()):
			revealed_texts.append(_t(ladder[i]))
		# No handle/handle_map entry: reveal_next_hint() takes no argument (a
		# single flat ladder per case, unlike A/B's per-claim hint targets),
		# so there is no real id here worth resolving or hiding.
		hint = {
			"levels_revealed": revealed_texts,
			"total_levels": ladder.size(),
			"can_reveal_more": revealed_count < ladder.size(),
		}

	var stats: Dictionary = controller.get_stats()
	var completion_lines: Array[String] = []
	if controller.is_completed():
		completion_lines = ResolutionPresenter.build_completion_lines(controller.get_policy(), int(stats.get("elapsed_ms", 0)), int(stats.get("hints_used", 0)), [
			_t("UI_PROTOTYPE_C_STATS_SUBMISSIONS") % int(stats.get("submissions", 0)),
			_t("UI_PROTOTYPE_C_STATS_FAILED") % int(stats.get("failed", 0)),
			_t("UI_PROTOTYPE_C_STATS_CLAIM_ATTEMPTS") % int(stats.get("claim_attempts", 0)),
			_t("UI_PROTOTYPE_C_STATS_MOVES") % int(stats.get("moves", 0)),
			_t("UI_PROTOTYPE_C_STATS_FACTS_OPENED") % int(stats.get("facts_opened", 0)),
		] as Array[String])

	var view: Dictionary = {
		"non_canon": case_def.get("metadata", {}).get("canon", true) == false,
		"case_title": _t(case_def.get("display_name", "")),
		"case_description": _t(case_def.get("description", "")),
		"objective": _t(proto.get("objective", "")),
		"completed": controller.is_completed(),
		"accepted": controller.is_accepted(),
		"events": events,
		"time_slots": controller.get_time_slots(),
		"unplaced_count": controller.get_unplaced_count(),
		"can_submit": controller.can_submit(),
		"can_resubmit": controller.can_resubmit(),
		"can_check": controller.can_check_timeline(),
		"facts": facts,
		"hint": hint,
		"resolution_status": ResolutionPresenter.build_status(controller.get_policy()),
		"stats": stats,
		"completion_text": _t(proto.get("completion_text", "")) if controller.is_completed() else "",
		"completion_lines": completion_lines,
	}

	if controller.is_accepted():
		var claim_id: String = controller.get_claim_statement_id()
		var claim: Dictionary = DeductionEvaluator.find_claim(case_def, claim_id)
		var claim_handle: String = _next_handle(counters, "C")
		handle_map[claim_handle] = claim_id
		var options: Array[Dictionary] = []
		for constraint_id in controller.get_fact_ids():
			options.append({
				"handle": fact_handle_by_id.get(constraint_id, ""),
				"text": _t(proto.get("visible_constraint_facts", {}).get(constraint_id, "")),
				"selected": constraint_id == controller.get_selected_justification_id(),
			})
		view["claim"] = {
			"handle": claim_handle,
			"statement_text": _t(claim.get("text", "")),
			"fits_selected": controller.get_selected_claim_answer() == PrototypeCController.ANSWER_FITS,
			"impossible_selected": controller.get_selected_claim_answer() == PrototypeCController.ANSWER_IMPOSSIBLE,
			"justification_options": options,
			"can_submit": controller.can_submit_claim(),
		}
		view["claim_phase"] = controller.is_claim_phase()
		view["claim_resolved"] = controller.is_claim_resolved()
		view["claim_attempts"] = controller.get_claim_attempts()
		if controller.is_claim_resolved():
			var justification_text: String = _t(proto.get("visible_constraint_facts", {}).get(controller.get_selected_justification_id(), ""))
			view["resolution"] = {
				"explanation": _build_contradiction_explanation(case_def, controller),
				"justification": _t(JUSTIFICATION_RESULT_KEY) % justification_text,
				"partner_note": _t(PARTNER_CLAIM_NOTE_KEY) if controller.get_claim_resolved_by() == ResolutionPolicy.RESOLVED_BY_PARTNER else "",
			}

	var assistance_id: String = controller.get_assistance_constraint_id()
	if assistance_id != "" and not controller.is_completed():
		var event_ids: Array[String] = controller.constraint_event_ids(assistance_id)
		var event_handles: Array[String] = []
		var labels: Array[String] = []
		for event_id in event_ids:
			event_handles.append(String(handle_by_event_id.get(event_id, "")))
			labels.append(_t((events_index.get(event_id, {}) as Dictionary).get("label", "")))
		if controller.get_resolution_unit() == PrototypeCController.UNIT_TIMELINE:
			view["assistance"] = {
				"headline": _t(ASSISTANCE_HEADLINE_KEY),
				"text": _t(ladder[ASSISTANCE_LADDER_LEVEL - 1]) if ladder.size() >= ASSISTANCE_LADDER_LEVEL else "",
				"relationship": _t(ASSISTANCE_PAIR_KEY) % " ↔ ".join(labels),
				"event_handles": event_handles,
			}
		else:
			view["assistance"] = {
				"headline": _t(ASSISTANCE_HEADLINE_KEY),
				"text": _t(ASSISTANCE_CLAIM_KEY) % " / ".join(labels),
				"relationship": "",
				"event_handles": event_handles,
			}

	return {"view": view, "handle_map": handle_map}


## Interpolates the player's own accepted time(s) into the authored
## explanation — "%s" placeholders are filled, in order, with the accepted
## placement of each event the contradiction constraint references, so the
## explanation stays true for whichever valid timeline the player built, not
## only the authored one.
static func _build_contradiction_explanation(case_def: Dictionary, controller: PrototypeCController) -> String:
	var contradiction: Dictionary = case_def.get("prototype_c", {}).get("contradiction", {})
	var template: String = _t(contradiction.get("explanation", ""))
	var event_ids: Array[String] = controller.constraint_event_ids(str(contradiction.get("constraint_ref", "")))
	var args: Array = []
	for event_id in event_ids:
		args.append(controller.get_accepted_time(event_id))
	return template % args if not args.is_empty() else template


# ---------------------------------------------------------------------------
# Violation feedback — maps a submit_timeline()/resolve_with_partner() result
# to natural-language facts already shown during briefing. Never a raw
# constraint id/type, never the correct placement, never an optional (hidden)
# constraint.

## Returns {"accepted", "blocked_duplicate", "invalid", "partner", "message",
## "violations": [{"text", "event_handles": [...]}], "resolution_notice"}.
## A first rejection lists NO fact (only the broad category in "message"); a
## later rejection lists exactly one; a partner timeline lists the facts the
## player's last attempt violated, now satisfied.
static func build_violation_feedback(case_def: Dictionary, controller: PrototypeCController, result: Dictionary) -> Dictionary:
	var feedback: Dictionary = {
		"accepted": result.get("accepted", false) == true,
		"blocked_duplicate": result.get("blocked_duplicate", false) == true,
		"invalid": false, "partner": result.get("partner", false) == true, "violations": [], "message": "",
		"resolution_notice": ResolutionPresenter.build_commit_notice(result.get("resolution", {})),
	}
	var category: String = str(result.get("category", ""))
	if category == TimelineEvaluator.INVALID_INPUT:
		var message_key: String = FEEDBACK_INVALID_KEY
		match str(result.get("reason", "")):
			PrototypeCController.REASON_SUBMISSION_LOCKED, PrototypeCController.REASON_PARTNER_UNAVAILABLE:
				message_key = FEEDBACK_LOCKED_KEY
			PrototypeCController.REASON_INTERNAL_ERROR:
				message_key = FEEDBACK_INTERNAL_ERROR_KEY
		feedback["invalid"] = true
		feedback["message"] = _t(message_key)
		return feedback

	if feedback["accepted"]:
		if feedback["partner"]:
			feedback["message"] = _t(PARTNER_TIMELINE_NOTE_KEY)
			feedback["violations"] = _fact_entries(case_def, controller, DeductionEvaluator.string_array(result.get("explained_constraint_ids", [])))
		return feedback

	var detail: Dictionary = result.get("feedback", {})
	if str(detail.get("level", "")) == PrototypeCController.FEEDBACK_FACT and str(detail.get("constraint_id", "")) != "":
		feedback["message"] = _t(FEEDBACK_FACT_KEY)
		feedback["violations"] = _fact_entries(case_def, controller, [str(detail.get("constraint_id", ""))] as Array[String])
	else:
		feedback["message"] = _t(FEEDBACK_CATEGORY_KEY) % _t(CATEGORY_KEYS.get(str(detail.get("category", "")), ""))
	return feedback


static func _fact_entries(case_def: Dictionary, controller: PrototypeCController, constraint_ids: Array[String]) -> Array[Dictionary]:
	var facts: Dictionary = case_def.get("prototype_c", {}).get("visible_constraint_facts", {})
	var event_handle_by_id: Dictionary = {}
	var counters: Dictionary = {}
	for event_id in controller.get_all_event_ids():
		event_handle_by_id[event_id] = _next_handle(counters, "V")
	var entries: Array[Dictionary] = []
	for constraint_id in constraint_ids:
		if not facts.has(constraint_id):
			continue  # An optional/author-only constraint is never surfaced here.
		var event_handles: Array[String] = []
		for event_id in controller.constraint_event_ids(constraint_id):
			event_handles.append(String(event_handle_by_id.get(event_id, "")))
		entries.append({"text": _t(facts.get(constraint_id, "")), "event_handles": event_handles})
	return entries


# ---------------------------------------------------------------------------
# Final claim feedback

## `result` is whatever PrototypeCController.answer_claim()/submit_claim()/
## resolve_with_partner() returned. Returns {"correct", "resolved", "partner",
## "guidance", "resolution_notice"}: a first wrong answer gets one generic
## nudge; from the second, whether the VERDICT or the supporting FACT is off —
## never which fact is right. The explanation itself is exposed only via
## build_player_view()'s "resolution" key once the claim is resolved.
static func build_claim_feedback(case_def: Dictionary, controller: PrototypeCController, result: Dictionary) -> Dictionary:
	var feedback: Dictionary = {
		"correct": result.get("correct", false) == true,
		"resolved": result.get("resolved", false) == true,
		"partner": result.get("partner", false) == true,
		"guidance": "",
		"resolution_notice": ResolutionPresenter.build_commit_notice(result.get("resolution", {})),
	}
	if feedback["correct"]:
		return feedback
	match str(result.get("reason", "")):
		PrototypeCController.REASON_MISSING_JUSTIFICATION:
			feedback["guidance"] = _t("UI_PROTOTYPE_C_CLAIM_NEEDS_JUSTIFICATION")
		PrototypeCController.REASON_DUPLICATE_CLAIM:
			feedback["guidance"] = _t("UI_PROTOTYPE_C_CLAIM_DUPLICATE")
		PrototypeCController.REASON_SUBMISSION_LOCKED, PrototypeCController.REASON_PARTNER_UNAVAILABLE:
			feedback["guidance"] = _t(FEEDBACK_LOCKED_KEY)
		PrototypeCController.REASON_INTERNAL_ERROR:
			feedback["guidance"] = _t(FEEDBACK_INTERNAL_ERROR_KEY)
		"":
			if result.get("feedback_level", "") == PrototypeCController.FEEDBACK_GUIDED and result.has("verdict_correct"):
				feedback["guidance"] = _t("UI_PROTOTYPE_C_CLAIM_WRONG_JUSTIFICATION" if result.get("verdict_correct", false) == true else "UI_PROTOTYPE_C_CLAIM_WRONG_VERDICT")
			else:
				feedback["guidance"] = _t("UI_PROTOTYPE_C_CLAIM_WRONG_FEEDBACK")
	return feedback


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
