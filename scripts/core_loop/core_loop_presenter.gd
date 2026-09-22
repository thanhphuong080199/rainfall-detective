class_name CoreLoopPresenter
extends RefCounted
## Player-safe, localized view models for the production core-loop screens
## (Milestone 1.16 — see docs/core-loop-sandbox.md, "UI"). Stateless static
## helpers, like the prototype presenters it builds on.
##
## An ALLOW-LIST, never a pass-through: every view below is assembled from
## explicitly chosen, already-translated fields. Content ids never appear —
## evidence, statements, events and facts are addressed by the opaque handles
## the prototype presenters already produce (resolved back only by the
## screen, immediately before a runtime command). On top of what those
## presenters already withhold (veracity, proof sets, ground truth, raw
## constraints, unresolved claim text), this layer also drops what is fine in
## a debug prototype but not in the product: run-result labels and "this run
## is now Assisted" notices (1.15B: the run help result is stored, never
## shown as a grade or badge), completion statistics, and case descriptions.

## Keys of a prototype player view that may reach a production mechanic
## screen. Anything a presenter adds later stays out until listed here.
const MECHANIC_VIEW_KEYS := [
	"question", "slot_count", "slots", "can_commit", "known_failed_theory", "evidence", "hint", "theory_accepted", "resolved_claims",
	"statements", "current_statement_handle", "selected_evidence_handle", "round_index", "round_count",
	"objective", "accepted", "events", "time_slots", "unplaced_count", "can_submit", "can_resubmit", "can_check", "facts",
	"claim", "claim_phase", "claim_resolved", "resolution", "assistance",
]
## The unit-local status fields a production screen may show (never the run
## result).
const STATUS_KEYS := [
	"current_status_text", "can_submit", "assistance_required", "assistance_active", "partner_available", "resolved_by_partner",
	"standard_attempts_remaining", "assisted_attempts_remaining",
]

const REFUSAL_KEYS := {
	ChapterRuntime.REASON_UNIT_LOCKED: "UI_CORE_LOOP_UNIT_LOCKED",
	ChapterRuntime.REASON_UNIT_NOT_CURRENT: "UI_CORE_LOOP_UNIT_NOT_YET",
	ChapterRuntime.REASON_UNIT_RESOLVED: "UI_CORE_LOOP_UNIT_DONE",
	ChapterRuntime.REASON_COMPLETED: "UI_CORE_LOOP_CHAPTER_DONE",
}


# ---------------------------------------------------------------------------
# Investigation HUD and briefing

## {"visible", "objective", "unit_title", "unit_available", "unit_hint",
## "error"}.
static func build_hud(runtime: ChapterRuntime) -> Dictionary:
	if runtime == null or not runtime.is_active():
		return {"visible": false}
	if runtime.has_error():
		return {"visible": true, "objective": "", "unit_title": "", "unit_available": false, "unit_hint": "", "error": _t("UI_CORE_LOOP_ERROR")}
	var phase: Dictionary = runtime.get_current_phase()
	var unit_id: String = runtime.get_current_unit_id()
	var status: Dictionary = runtime.get_unit_status(unit_id) if unit_id != "" else {}
	return {
		"visible": true,
		"objective": _t(phase.get("objective", "")) if not runtime.is_completed() else _t("UI_CORE_LOOP_CHAPTER_DONE"),
		"unit_title": _t(runtime.get_unit_definition(unit_id).get("title", "")) if unit_id != "" else "",
		"unit_available": status.get("available", false) == true,
		"unit_hint": refusal_text(str(status.get("reason", ""))) if unit_id != "" and status.get("available", false) != true else "",
		"error": "",
	}


static func build_briefing(runtime: ChapterRuntime) -> Dictionary:
	var loop: Dictionary = runtime.get_loop()
	var briefing: Dictionary = loop.get("briefing", {})
	return {
		"title": _t(briefing.get("title", "")),
		"text": _t(briefing.get("text", "")),
		"objective": _t(runtime.get_current_phase().get("objective", "")),
		"non_canon": loop.get("canon", true) == false,
	}


## Safe, generic text for a refused command — never names what is missing.
static func refusal_text(reason: String) -> String:
	return _t(refusal_key(reason))


static func refusal_key(reason: String) -> String:
	return str(REFUSAL_KEYS.get(reason, "UI_CORE_LOOP_UNIT_UNAVAILABLE"))


# ---------------------------------------------------------------------------
# Case File

## {"view": {"objective", "unit_title", "unit_available", "unit_hint",
## "evidence": [{"handle", "name", "short", "detail" (only once opened),
## "opened", "pinned"}], "empty", "findings": [String]}, "handle_map"}.
## Only ACQUIRED evidence is listed; pinned items first, then acquisition
## order. Findings are only consequences already applied.
static func build_case_file(runtime: ChapterRuntime) -> Dictionary:
	var hud: Dictionary = build_hud(runtime)
	var handle_map: Dictionary = {}
	var evidence: Array[Dictionary] = []
	var ordered: Array[String] = []
	for evidence_id in runtime.get_acquired_evidence():
		if runtime.is_case_file_evidence_pinned(evidence_id):
			ordered.append(evidence_id)
	for evidence_id in runtime.get_acquired_evidence():
		if not ordered.has(evidence_id):
			ordered.append(evidence_id)
	for i in ordered.size():
		var evidence_id: String = ordered[i]
		var data: Dictionary = ContentDB.get_evidence(evidence_id)
		var handle: String = "CF%d" % i
		handle_map[handle] = evidence_id
		var opened: bool = runtime.is_case_file_evidence_opened(evidence_id)
		evidence.append({
			"handle": handle, "name": _t(data.get("name", "")), "short": _t(data.get("short_description", "")),
			"detail": _t(data.get("detailed_description", "")) if opened else "", "opened": opened,
			"pinned": runtime.is_case_file_evidence_pinned(evidence_id),
		})
	return {
		"view": {
			"objective": hud.get("objective", ""), "unit_title": hud.get("unit_title", ""), "unit_available": hud.get("unit_available", false),
			"unit_hint": hud.get("unit_hint", ""), "evidence": evidence, "empty": evidence.is_empty(), "findings": build_findings(runtime),
		},
		"handle_map": handle_map,
	}


## Narrative lines for every applied consequence, in route order; a partner-
## resolved finding says so in words (a narrative note, never a badge).
static func build_findings(runtime: ChapterRuntime) -> Array[String]:
	var lines: Array[String] = []
	for finding in runtime.get_findings():
		var line: String = _t(finding.get("summary", ""))
		if finding.get("resolved_by", "") == ResolutionPolicy.RESOLVED_BY_PARTNER:
			line += " " + _t("UI_CORE_LOOP_FINDING_PARTNER")
		lines.append(line)
	return lines


# ---------------------------------------------------------------------------
# Mechanic screen

## {"view": {"mechanic", "title", "resolved", "timeline_accepted", "status":
## {...STATUS_KEYS}, "feedback": {"headline", "lines": [String]} | {},
## ...MECHANIC_VIEW_KEYS}, "handle_map"} for the unit's current state.
static func build_mechanic(runtime: ChapterRuntime, unit_id: String) -> Dictionary:
	var unit: CoreLoopUnit = runtime.get_unit(unit_id)
	if unit == null:
		return {"view": {}, "handle_map": {}}
	var case_def: Dictionary = runtime.get_case_def()
	var built: Dictionary
	match unit.mechanic:
		CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
			built = PrototypeBPresenter.build_player_view(case_def, unit.controller)
		CoreLoopUnit.MECHANIC_STATEMENT_CONTRADICTION:
			built = PrototypeAPresenter.build_player_view(case_def, unit.controller)
		_:
			built = PrototypeCPresenter.build_player_view(case_def, unit.controller)
	var source: Dictionary = built.get("view", {})
	var view: Dictionary = {}
	for key in MECHANIC_VIEW_KEYS:
		if source.has(key):
			view[key] = source[key]
	var status: Dictionary = {}
	var raw_status: Dictionary = source.get("resolution_status", {})
	for key in STATUS_KEYS:
		if raw_status.has(key):
			status[key] = raw_status[key]
	view["status"] = status
	view["mechanic"] = unit.mechanic
	view["title"] = _t(unit.definition.get("title", ""))
	view["resolved"] = unit.has_reached(CoreLoopUnit.OUTCOME_RESOLVED)
	view["timeline_accepted"] = unit.has_reached(CoreLoopUnit.OUTCOME_TIMELINE_ACCEPTED)
	view["hint_note"] = _t("UI_CORE_LOOP_HINT_NOTE")
	view["feedback"] = build_feedback(runtime, unit_id)
	return {"view": view, "handle_map": built.get("handle_map", {})}


## The unit's pending feedback as {"headline", "lines", "success"}, or {} —
## rebuilt from the kept (JSON-safe) result each time, so it re-renders in the
## current locale and is identical before and after a reload.
static func build_feedback(runtime: ChapterRuntime, unit_id: String) -> Dictionary:
	var unit: CoreLoopUnit = runtime.get_unit(unit_id)
	if unit == null or not unit.is_feedback_open():
		return {}
	var open: Dictionary = unit.get_open_feedback()
	var result: Dictionary = _without_run_result_notice(open.get("result", {}))
	var case_def: Dictionary = runtime.get_case_def()
	var lines: Array[String] = []
	var headline: String = ""
	var success: bool = false
	match str(open.get("kind", "")):
		CoreLoopUnit.FEEDBACK_THEORY:
			var feedback: Dictionary = PrototypeBPresenter.build_feedback(case_def, unit.controller, result)
			headline = feedback.get("headline", "")
			success = feedback.get("success", false) == true
			lines = _non_empty([feedback.get("deduction_text", ""), feedback.get("explanation", ""), feedback.get("partner_note", ""), feedback.get("resolution_notice", "")])
		CoreLoopUnit.FEEDBACK_CONTRADICTION:
			var feedback: Dictionary = PrototypeAPresenter.build_feedback(case_def, result)
			headline = feedback.get("headline", "")
			success = feedback.get("success", false) == true
			lines = _non_empty([feedback.get("witness_response", ""), feedback.get("explanation", ""), feedback.get("rebuttal", ""), feedback.get("partner_note", ""), feedback.get("resolution_notice", "")])
		CoreLoopUnit.FEEDBACK_TIMELINE:
			var feedback: Dictionary = PrototypeCPresenter.build_violation_feedback(case_def, unit.controller, result)
			success = feedback.get("accepted", false) == true
			headline = _t("UI_CORE_LOOP_TIMELINE_ACCEPTED" if success else "UI_CORE_LOOP_TIMELINE_REJECTED")
			var texts: Array = [feedback.get("message", "")]
			for violation in feedback.get("violations", []):
				texts.append("• %s" % violation.get("text", ""))
			texts.append(feedback.get("resolution_notice", ""))
			lines = _non_empty(texts)
		CoreLoopUnit.FEEDBACK_CLAIM:
			var feedback: Dictionary = PrototypeCPresenter.build_claim_feedback(case_def, unit.controller, result)
			success = feedback.get("correct", false) == true
			headline = _t("UI_CORE_LOOP_CLAIM_ACCEPTED" if success else "UI_CORE_LOOP_CLAIM_REJECTED")
			var resolution: Dictionary = PrototypeCPresenter.build_player_view(case_def, unit.controller).get("view", {}).get("resolution", {})
			lines = _non_empty([resolution.get("explanation", "") if success else "", resolution.get("justification", "") if success else "", resolution.get("partner_note", "") if success else "", feedback.get("guidance", ""), feedback.get("resolution_notice", "")])
	return {"headline": headline, "lines": lines, "success": success}


# ---------------------------------------------------------------------------
# Result

## Narrative summary only (1.15B §2): title, the chapter's result text and
## the causal chain of findings. No score, rank, count, time or
## Independent/Guided/Assisted label — the run help result stays in the save
## and the recording.
static func build_result(runtime: ChapterRuntime) -> Dictionary:
	var result: Dictionary = runtime.get_loop().get("result", {})
	return {
		"title": _t(result.get("title", "")),
		"text": _t(result.get("text", "")),
		"findings": build_findings(runtime),
		"non_canon": runtime.get_loop().get("canon", true) == false,
	}


# ---------------------------------------------------------------------------
# Helpers

## The production product never announces "this run is now Guided/Assisted"
## mid-mechanic — that notice is a debug-prototype affordance. The budget
## lines (attempts left, assistance required, partner available) remain.
static func _without_run_result_notice(result: Dictionary) -> Dictionary:
	var copy: Dictionary = result.duplicate(true)
	if typeof(copy.get("resolution")) == TYPE_DICTIONARY:
		(copy["resolution"] as Dictionary)["run_resolution_result_changed"] = false
	return copy


static func _non_empty(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		if typeof(value) == TYPE_STRING and value != "":
			out.append(value)
	return out


static func _t(key: Variant) -> String:
	if typeof(key) != TYPE_STRING or key == "":
		return ""
	return String(TranslationServer.translate(key))
