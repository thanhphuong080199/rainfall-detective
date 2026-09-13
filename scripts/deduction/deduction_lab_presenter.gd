class_name DeductionLabPresenter
extends RefCounted
## Builds the two Deduction Lab view models (Milestone 1.10 — see
## docs/deduction-lab.md) from a deduction case_def + DeductionSession.
## Stateless static helpers, like DeductionEvaluator/DeductionValidator — no
## autoloads, so tests drive it with ContentDB-loaded cases or hand-built
## fixtures alike.
##
## build_player_view() is the ONLY place the Player Preview's data contract is
## assembled. It is an explicit ALLOW-LIST: every field below is deliberately
## chosen and translated (via TranslationServer.translate(), the same
## no-`self` path ContentValidator uses — see docs/localization.md, "Where a
## key is resolved") — the complete raw case_def is never handed to a
## player-facing widget. Domain ids never appear in the returned "view"
## Dictionary at all, not even as translation keys (this project's key
## naming convention echoes ids, e.g. "DED_PROTO_X_E_DOOR_LOG_TEXT" for
## evidence "e_door_log" — a raw key would leak exactly what the allow-list
## exists to hide). Every reference a click handler needs (which evidence to
## open, which hint ladder to reveal) is instead an opaque "handle" (e.g.
## "E3"); the real domain id lives ONLY in the separately-returned
## `handle_map`, which the caller keeps privately and never hands to a
## rendering widget — see docs/deduction-lab.md, "Spoiler boundary".
##
## build_author_view() has no such restriction: Author Inspector is
## explicitly a spoiler/debug view, so it returns raw ids, kinds, veracity,
## proof sets, ground truth and the session's own to_dict() directly.

const PLAYER_ALWAYS_VISIBLE_CLAIM_KINDS := ["statement", "hypothesis"]


# ---------------------------------------------------------------------------
# Player Preview

## Returns {"view": Dictionary, "handle_map": Dictionary}. `view` is the only
## thing that may reach a player-facing widget; `handle_map` (opaque handle ->
## real domain id) is for the caller's own private use (resolving a click back
## to a real id before calling a production API), never for display.
static func build_player_view(case_def: Dictionary, session: DeductionSession) -> Dictionary:
	var handle_map: Dictionary = {}
	var counters: Dictionary = {}

	var suspects: Array[Dictionary] = []
	for suspect in DeductionEvaluator.dict_array(case_def.get("suspects", [])):
		var handle: String = _next_handle(counters, "S")
		handle_map[handle] = str(suspect.get("id", ""))
		suspects.append({"handle": handle, "name": _t(suspect.get("name", ""))})

	var question_status: Dictionary = DeductionEvaluator.get_question_status(case_def, session)
	var resolved_question_ids: Array = question_status.get("resolved", [])
	var questions: Array[Dictionary] = []
	var question_handle_by_id: Dictionary = {}
	for question in DeductionEvaluator.dict_array(case_def.get("questions", [])):
		var question_id: String = str(question.get("id", ""))
		var handle: String = _next_handle(counters, "Q")
		handle_map[handle] = question_id
		question_handle_by_id[question_id] = handle
		questions.append({
			"handle": handle,
			"text": _t(question.get("text", "")),
			"required": question.get("required", false) == true,
			"resolved": resolved_question_ids.has(question_id),
		})

	var available_evidence_ids: Array[String] = DeductionEvaluator.get_available_evidence_ids(case_def, session)
	var evidence_list: Array[Dictionary] = []
	for evidence in DeductionEvaluator.dict_array(case_def.get("evidence", [])):
		var evidence_id: String = str(evidence.get("id", ""))
		if not available_evidence_ids.has(evidence_id):
			continue  # Locked/unavailable evidence content must be absent entirely.
		var handle: String = _next_handle(counters, "E")
		handle_map[handle] = evidence_id
		var opened: bool = session.has_opened_evidence(evidence_id)
		evidence_list.append({
			"handle": handle,
			"name": _t(evidence.get("name", "")),
			"opened": opened,
			"text": _t(evidence.get("text", "")) if opened else "",
			"tags": DeductionEvaluator.string_array(evidence.get("tags", [])).duplicate(),
			"time": str(evidence.get("time", "")) if (opened and evidence.has("time")) else "",
		})

	var suspect_name_by_id: Dictionary = {}
	for suspect in DeductionEvaluator.dict_array(case_def.get("suspects", [])):
		suspect_name_by_id[str(suspect.get("id", ""))] = _t(suspect.get("name", ""))

	var resolved_claims: Dictionary = session.get_resolved_claims()
	var claims: Array[Dictionary] = []
	for claim in DeductionEvaluator.dict_array(case_def.get("claims", [])):
		var claim_id: String = str(claim.get("id", ""))
		var kind: String = str(claim.get("kind", ""))
		var status: String = str(resolved_claims.get(claim_id, ""))
		var always_visible: bool = PLAYER_ALWAYS_VISIBLE_CLAIM_KINDS.has(kind)
		if not always_visible and status == "":
			continue  # An unresolved deduction/explanation/conclusion is a spoiler — absent entirely.
		var handle: String = _next_handle(counters, "C")
		handle_map[handle] = claim_id
		var entry: Dictionary = {
			"handle": handle,
			"kind": kind,
			"text": _t(claim.get("text", "")),
			"status": status if status != "" else "unresolved",
		}
		if kind == "statement":
			entry["speaker"] = suspect_name_by_id.get(str(claim.get("speaker", "")), "")
		claims.append(entry)

	var hints: Array[Dictionary] = []
	for ladder in DeductionEvaluator.dict_array(case_def.get("hints", [])):
		var levels: Array[Dictionary] = DeductionEvaluator.dict_array(ladder.get("levels", []))
		if levels.is_empty():
			continue
		var question_id: String = str(levels[0].get("question", ""))
		var question_handle: String = question_handle_by_id.get(question_id, "")
		if question_handle == "":
			continue  # Malformed content; DeductionValidator already reports this.
		var target_id: String = str(ladder.get("target", ""))
		var handle: String = _next_handle(counters, "H")
		handle_map[handle] = target_id
		var revealed_count: int = session.get_hint_level(target_id)
		var revealed_texts: Array[String] = []
		for i in mini(revealed_count, levels.size()):
			revealed_texts.append(_t(levels[i].get("text", "")))
		hints.append({
			"handle": handle,
			"question_handle": question_handle,
			"levels_revealed": revealed_texts,
			"total_levels": levels.size(),
			"can_reveal_more": revealed_count < levels.size(),
		})

	var timeline: Variant = case_def.get("timeline", {})
	var timeline_events: Array[Dictionary] = []
	if typeof(timeline) == TYPE_DICTIONARY:
		var known_times: Dictionary = {}
		for constraint in DeductionEvaluator.dict_array((timeline as Dictionary).get("constraints", [])):
			if str(constraint.get("type", "")) == "fixed_time" and constraint.get("required", true) != false:
				known_times[str(constraint.get("event", ""))] = str(constraint.get("time", ""))
		for event in DeductionEvaluator.dict_array((timeline as Dictionary).get("events", [])):
			var event_id: String = str(event.get("id", ""))
			var handle: String = _next_handle(counters, "T")
			handle_map[handle] = event_id
			timeline_events.append({
				"handle": handle,
				"label": _t(event.get("label", "")),
				"known_time": known_times.get(event_id, ""),
			})

	var view: Dictionary = {
		"non_canon": case_def.get("metadata", {}).get("canon", true) == false,
		"case_title": _t(case_def.get("display_name", "")),
		"case_description": _t(case_def.get("description", "")),
		"solved": session.is_solved(),
		"questions_resolved": resolved_question_ids.size(),
		"questions_total": questions.size(),
		"suspects": suspects,
		"questions": questions,
		"evidence": evidence_list,
		"claims": claims,
		"hints": hints,
		"timeline": timeline_events,
	}
	return {"view": view, "handle_map": handle_map}


# ---------------------------------------------------------------------------
# Author Inspector — deliberately unfiltered; see class doc above.

## `errors`/`warnings` should already be scoped to THIS case (the caller runs
## DeductionValidator.validate_case(case_def, errors, warnings) itself, since
## that's a pure static call with no autoload involved — never re-filtered
## from a global ContentValidator.validate() result here).
static func build_author_view(case_def: Dictionary, session: DeductionSession, errors: Array[String] = [], warnings: Array[String] = []) -> Dictionary:
	var suspects: Array[Dictionary] = []
	for suspect in DeductionEvaluator.dict_array(case_def.get("suspects", [])):
		suspects.append({
			"id": suspect.get("id", ""), "name": _t(suspect.get("name", "")),
			"structural_role": suspect.get("structural_role", ""),
		})

	var evidence: Array[Dictionary] = []
	for item in DeductionEvaluator.dict_array(case_def.get("evidence", [])):
		var evidence_id: String = str(item.get("id", ""))
		evidence.append({
			"id": evidence_id, "name": _t(item.get("name", "")), "text": _t(item.get("text", "")),
			"source": item.get("source", ""), "certainty": item.get("certainty", ""), "time": item.get("time", ""),
			"tags": item.get("tags", []), "misleading": item.get("misleading", false) == true,
			"unlock_requires": item.get("unlock_requires", []), "structural_role": item.get("structural_role", ""),
			"opened": session.has_opened_evidence(evidence_id),
			"available": DeductionEvaluator.is_evidence_available(case_def, session, evidence_id),
		})

	var claims: Array[Dictionary] = []
	for claim in DeductionEvaluator.dict_array(case_def.get("claims", [])):
		var claim_id: String = str(claim.get("id", ""))
		claims.append({
			"id": claim_id, "kind": claim.get("kind", ""), "veracity": claim.get("veracity", ""),
			"required": claim.get("required", false) == true, "speaker": claim.get("speaker", ""),
			"lie_motive": claim.get("lie_motive", ""), "text": _t(claim.get("text", "")),
			"structural_role": claim.get("structural_role", ""),
			"compatible": claim.get("compatible", []), "proof_sets": claim.get("proof_sets", []),
			"depth": DeductionValidator.claim_depth(case_def, claim_id),
			"status": session.get_claim_status(claim_id),
		})

	return {
		"case_id": case_def.get("id", ""),
		"metadata": case_def.get("metadata", {}),
		"suspects": suspects,
		"evidence": evidence,
		"claims": claims,
		"questions": case_def.get("questions", []).duplicate(true),
		"hints": case_def.get("hints", []).duplicate(true),
		"timeline": (case_def.get("timeline", {}) as Dictionary).duplicate(true) if typeof(case_def.get("timeline", {})) == TYPE_DICTIONARY else {},
		"ground_truth": (case_def.get("ground_truth", {}) as Dictionary).duplicate(true) if typeof(case_def.get("ground_truth", {})) == TYPE_DICTIONARY else {},
		"session": session.to_dict(),
		"validation_errors": errors.duplicate(),
		"validation_warnings": warnings.duplicate(),
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
