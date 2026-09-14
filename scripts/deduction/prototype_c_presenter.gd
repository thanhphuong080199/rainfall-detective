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
## build_violation_feedback()/build_claim_feedback() map controller results to
## player-facing text: natural-language facts already shown during briefing
## (never raw constraint ids/types, never the correct placement, never how
## close the player is to the authored solution) and the final explanation
## with the player's OWN accepted time interpolated in, so it stays true for
## whichever valid timeline the player actually built.

const FEEDBACK_INVALID_KEY := "UI_PROTOTYPE_C_FEEDBACK_INVALID"


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
	for constraint_id in controller.get_fact_ids():
		var opened: bool = controller.has_opened_fact(constraint_id)
		var handle: String = _next_handle(counters, "F")
		handle_map[handle] = constraint_id
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
		"facts": facts,
		"hint": hint,
		"stats": controller.get_stats(),
		"completion_text": _t(proto.get("completion_text", "")) if controller.is_completed() else "",
	}

	if controller.is_accepted():
		var claim_id: String = controller.get_claim_statement_id()
		var claim: Dictionary = DeductionEvaluator.find_claim(case_def, claim_id)
		var claim_handle: String = _next_handle(counters, "C")
		handle_map[claim_handle] = claim_id
		view["claim"] = {"handle": claim_handle, "statement_text": _t(claim.get("text", ""))}
		view["claim_phase"] = controller.is_claim_phase()
		view["claim_resolved"] = controller.is_claim_resolved()
		view["claim_attempts"] = controller.get_claim_attempts()
		if controller.is_claim_resolved():
			view["resolution"] = {"explanation": _build_contradiction_explanation(case_def, controller)}

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
# Violation feedback — maps a submit_timeline() result to natural-language
# facts already shown during briefing. Never a raw constraint id/type, never
# the correct placement, never an optional (hidden) constraint.

## Returns {"accepted": bool, "blocked_duplicate": bool, "invalid": bool,
## "violations": [{"handle", "text", "event_handles": [...]}]}. `result` is
## whatever PrototypeCController.submit_timeline() returned.
static func build_violation_feedback(case_def: Dictionary, controller: PrototypeCController, result: Dictionary) -> Dictionary:
	var category: String = str(result.get("category", ""))
	if category == TimelineEvaluator.INVALID_INPUT:
		return {"accepted": false, "blocked_duplicate": false, "invalid": true, "violations": [], "message": _t(FEEDBACK_INVALID_KEY)}

	var proto: Dictionary = case_def.get("prototype_c", {})
	var facts: Dictionary = proto.get("visible_constraint_facts", {})
	var handle_map: Dictionary = {}
	var counters: Dictionary = {}
	var event_handle_by_id: Dictionary = {}
	for event_id in controller.get_all_event_ids():
		var handle: String = _next_handle(counters, "V")
		handle_map[handle] = event_id
		event_handle_by_id[event_id] = handle

	var violations: Array[Dictionary] = []
	for constraint_id in result.get("violated_required", []):
		if not facts.has(constraint_id):
			continue  # An optional/author-only constraint is never surfaced here.
		var event_ids: Array[String] = controller.constraint_event_ids(str(constraint_id))
		var event_handles: Array[String] = []
		for event_id in event_ids:
			event_handles.append(String(event_handle_by_id.get(event_id, "")))
		violations.append({"text": _t(facts.get(constraint_id, "")), "event_handles": event_handles})

	return {
		"accepted": result.get("accepted", false), "blocked_duplicate": result.get("blocked_duplicate", false),
		"invalid": false, "violations": violations, "message": "",
	}


# ---------------------------------------------------------------------------
# Final claim feedback

## `result` is whatever PrototypeCController.answer_claim() returned. Returns
## {"correct": bool, "resolved": bool, "guidance": String} — "guidance" is a
## static, non-spoiling nudge shown only on a wrong "Fits" answer; the actual
## contradiction explanation is exposed only via build_player_view()'s
## "resolution" key once the claim is genuinely resolved.
static func build_claim_feedback(result: Dictionary) -> Dictionary:
	return {
		"correct": result.get("correct", false),
		"resolved": result.get("resolved", false),
		"guidance": "" if result.get("correct", false) else _t("UI_PROTOTYPE_C_CLAIM_WRONG_FEEDBACK"),
	}


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
