class_name PrototypeCController
extends RefCounted
## Interaction-state host for the debug-only Prototype C — Timeline
## Reconstruction prototype (Milestone 1.13 — see docs/prototype-c.md). Owns
## Prototype-C-specific interaction state: the current placement of every
## timeline event (fixed events pre-placed and locked, movable events
## starting empty), the currently selected movable event, submission/failure/
## move counts, opened facts, hint level, and the final-claim phase.
##
## Every submission goes through the REAL, unmodified TimelineEvaluator
## (`TimelineEvaluator.evaluate()` for the reconstruction itself,
## `TimelineEvaluator.is_constraint_satisfied()` for the final claim check) —
## this class adds zero constraint-evaluation logic of its own; it only
## decides what the player has placed and when a submission is allowed. Pure
## and autoload-free, like PrototypeAController/PrototypeBController: the
## caller (scripts/debug/prototype_c.gd) fetches case_def via ContentDB and
## hands it in, never resolves a case id itself.
##
## DECISION: unlike DeductionLabController/PrototypeAController/
## PrototypeBController, this class does NOT own a DeductionSession. Every
## other prototype needs one because DeductionEvaluator.commit_attempt()
## requires one to resolve claims into. Prototype C's two evaluations —
## TimelineEvaluator.evaluate() and TimelineEvaluator.is_constraint_satisfied()
## — are both pure, stateless functions of a case_def and a placement dict;
## nothing is ever "committed" into a session. Reusing DeductionSession only
## for its evidence-opened bookkeeping would not even fit: a timeline
## constraint's "source" can be a STATEMENT id (e.g. a suspect's claimed
## time), not only an evidence id, so mark_evidence_opened() has no shape for
## "the player opened this fact." Interaction-only state — opened facts, hint
## level, moves, submissions — is instead tracked directly here, the same way
## PrototypeAController tracks its own Prototype-A-owned hint state instead of
## forcing it through the base contract.
##
## Optionally wired to a DeductionLabRecorder (Milestone 1.10, reused
## unmodified) passed into start(). This class decides WHAT and WHEN to
## record for the Prototype C event vocabulary; the recorder itself carries
## no Prototype-C-specific code — see docs/prototype-c.md, "Recorder events".

var _case_def: Dictionary = {}
var _proto: Dictionary = {}
var _events_index: Dictionary = {}
var _fixed_events: Array[String] = []
var _movable_events: Array[String] = []
var _all_event_ids: Array[String] = []
var _time_slots: Array[String] = []
var _placements: Dictionary = {}
var _selected_event_id: String = ""
var _opened_fact_ids: Array[String] = []
var _hint_level: int = 0
var _submission_count: int = 0
var _failed_submission_count: int = 0
var _moves_since_submission: int = 0
var _total_moves: int = 0
var _can_resubmit: bool = true
var _last_result: Dictionary = {}
var _accepted: bool = false
var _accepted_placements: Dictionary = {}
var _claim_attempts: int = 0
var _claim_resolved: bool = false
var _completed: bool = false
var _recorder: DeductionLabRecorder = null
var _clock_fn: Callable
var _start_ticks: int = 0


## `clock_fn` (no args, returns int/float monotonic milliseconds — defaults
## to Time.get_ticks_msec) is injectable for deterministic tests, matching
## PrototypeAController's/PrototypeBController's own convention.
func _init(clock_fn: Callable = Callable()) -> void:
	_clock_fn = clock_fn if clock_fn.is_valid() else Callable(Time, "get_ticks_msec")


# ---------------------------------------------------------------------------
# Lifecycle

## Starts a brand-new run of `case_def` (which must declare a non-empty
## "prototype_c" data layer — see DeductionValidator._validate_prototype_c).
## Calling this again (Restart) discards all previous interaction state.
## Fixed events are pre-placed at the exact time their own authored
## `fixed_time` timeline constraint declares — read from the timeline itself,
## never duplicated into prototype_c's own data. `recorder`, if given,
## receives this run's telemetry; pass null to run unrecorded.
func start(case_def: Dictionary, recorder: DeductionLabRecorder = null) -> bool:
	if typeof(case_def) != TYPE_DICTIONARY:
		return false
	var proto: Variant = case_def.get("prototype_c")
	if typeof(proto) != TYPE_DICTIONARY:
		return false
	var fixed_ids: Array[String] = DeductionEvaluator.string_array(proto.get("fixed_events", []))
	var movable_ids: Array[String] = DeductionEvaluator.string_array(proto.get("movable_events", []))
	var slots: Array[String] = DeductionEvaluator.string_array(proto.get("time_slots", []))
	if (fixed_ids.is_empty() and movable_ids.is_empty()) or slots.is_empty():
		return false

	_case_def = case_def
	_proto = proto
	_events_index = TimelineEvaluator.event_index(case_def)
	_fixed_events = fixed_ids
	_movable_events = movable_ids
	_all_event_ids = []
	for event_id in _events_index:
		_all_event_ids.append(str(event_id))
	_time_slots = slots

	_placements = {}
	for event_id in _fixed_events:
		_placements[event_id] = _fixed_time_of(event_id)
	for event_id in _movable_events:
		_placements[event_id] = ""

	_selected_event_id = ""
	_opened_fact_ids = []
	_hint_level = 0
	_submission_count = 0
	_failed_submission_count = 0
	_moves_since_submission = 0
	_total_moves = 0
	_can_resubmit = true
	_last_result = {}
	_accepted = false
	_accepted_placements = {}
	_claim_attempts = 0
	_claim_resolved = false
	_completed = false
	_recorder = recorder
	_start_ticks = int(_clock_fn.call())

	if _recorder != null:
		_recorder.record("prototype_started", _recorder.get_current_source(), {"case_id": str(case_def.get("id", ""))})
	return true


func _fixed_time_of(event_id: String) -> String:
	for constraint in TimelineEvaluator.constraints(_case_def):
		if str(constraint.get("type", "")) == "fixed_time" and str(constraint.get("event", "")) == event_id:
			return str(constraint.get("time", ""))
	return ""


func get_case_def() -> Dictionary:
	return _case_def


func is_completed() -> bool:
	return _completed


# ---------------------------------------------------------------------------
# Events and the board

func get_all_event_ids() -> Array[String]:
	return _all_event_ids.duplicate()


func is_fixed(event_id: String) -> bool:
	return _fixed_events.has(event_id)


func get_time_slots() -> Array[String]:
	return _time_slots.duplicate()


func get_event_duration_minutes(event_id: String) -> int:
	return TimelineEvaluator.parse_minutes((_events_index.get(event_id, {}) as Dictionary).get("duration_minutes"), 0)


func get_placement(event_id: String) -> String:
	return str(_placements.get(event_id, ""))


func get_placements() -> Dictionary:
	return _placements.duplicate()


func get_unplaced_count() -> int:
	var count := 0
	for event_id in _movable_events:
		if get_placement(event_id) == "":
			count += 1
	return count


func can_submit() -> bool:
	return get_unplaced_count() == 0


# ---------------------------------------------------------------------------
# Selecting, placing, moving, removing — keyboard/click accessible: select an
# event (a UI-local "which card is active" concept, also recorded for
# playtest analysis), then place it into a time slot. Calling place_selected()
# again with a different slot MOVES it; calling it with the SAME slot is a
# no-op (nothing recorded, no move counted) — only a genuine change counts as
# a move and re-enables resubmission.

func get_selected_event_id() -> String:
	return _selected_event_id


## Rejects a fixed event (locked, cannot be selected for placement) or an
## unknown id.
func select_event(event_id: String) -> bool:
	if not _movable_events.has(event_id):
		return false
	_selected_event_id = event_id
	if _recorder != null:
		_recorder.record("event_selected", _recorder.get_current_source(), {"event_id": event_id})
	return true


## Places the currently selected event into `time_slot`. Deliberately does
## NOT reject a slot another event already occupies — "if multiple events may
## legally share a start time, the UI must allow that" (docs/prototype-c.md);
## only TimelineEvaluator, at submission, can reject an actual conflict.
func place_selected(time_slot: String) -> bool:
	if _selected_event_id == "" or not _time_slots.has(time_slot):
		return false
	return _place(_selected_event_id, time_slot)


## Direct placement for a click-based UI that selects and places in one
## action; also updates the current selection to `event_id`.
func place_event(event_id: String, time_slot: String) -> bool:
	if not _time_slots.has(time_slot):
		return false
	_selected_event_id = event_id
	return _place(event_id, time_slot)


func _place(event_id: String, time_slot: String) -> bool:
	if not _movable_events.has(event_id):
		return false
	var previous: String = get_placement(event_id)
	if previous == time_slot:
		return false
	_placements[event_id] = time_slot
	_can_resubmit = true
	_moves_since_submission += 1
	_total_moves += 1
	if _recorder != null:
		if previous == "":
			_recorder.record("event_placed", _recorder.get_current_source(), {"event_id": event_id, "time": time_slot})
		else:
			_recorder.record("event_moved", _recorder.get_current_source(), {"event_id": event_id, "from": previous, "to": time_slot})
	return true


## Removes `event_id` back to the tray. Rejects a fixed event or an already-
## unplaced one (nothing to remove, nothing recorded).
func remove_event(event_id: String) -> bool:
	if not _movable_events.has(event_id):
		return false
	var previous: String = get_placement(event_id)
	if previous == "":
		return false
	_placements[event_id] = ""
	_can_resubmit = true
	_moves_since_submission += 1
	_total_moves += 1
	if _recorder != null:
		_recorder.record("event_removed", _recorder.get_current_source(), {"event_id": event_id, "from": previous})
	return true


# ---------------------------------------------------------------------------
# Submitting the reconstruction — the one correctness check: the real
# TimelineEvaluator against the complete placement map. Never compared to the
# authored ground_truth.solution_timeline.

func can_resubmit() -> bool:
	return _can_resubmit or _submission_count == 0


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func is_accepted() -> bool:
	return _accepted


## Submits the complete placement to TimelineEvaluator.evaluate(). Returns the
## evaluator's result dict plus "accepted" (bool) and "blocked_duplicate"
## (true when this call changed nothing because the placement is identical to
## the last real submission — the UI should keep this disabled instead of
## relying solely on this guard, but this is checked here too, in depth,
## exactly like PrototypeBController's own submission gate). An incomplete
## selection is rejected here too, as INVALID_INPUT, without consuming a
## submission.
func submit_timeline() -> Dictionary:
	if not can_submit():
		return {
			"category": TimelineEvaluator.INVALID_INPUT, "reason": "incomplete_selection",
			"violated_required": [] as Array[String], "violated_optional": [] as Array[String],
			"accepted": false, "blocked_duplicate": false,
		}
	if not can_resubmit():
		var blocked: Dictionary = _last_result.duplicate(true)
		blocked["accepted"] = _accepted
		blocked["blocked_duplicate"] = true
		return blocked

	_submission_count += 1
	var result: Dictionary = TimelineEvaluator.evaluate(_case_def, _placements)
	var accepted_now: bool = str(result.get("category", "")) == TimelineEvaluator.CONSISTENT
	if not accepted_now:
		_failed_submission_count += 1

	if _recorder != null:
		var violated_required: Array = result.get("violated_required", [])
		_recorder.record("timeline_submitted", _recorder.get_current_source(), {
			"sequence": _submission_count, "placements": _normalized_placements(),
			"moves_since_previous": _moves_since_submission, "facts_opened": _opened_fact_ids.size(),
			"category": str(result.get("category", "")), "violation_count": violated_required.size(),
		})
		if accepted_now:
			_recorder.record("timeline_accepted", _recorder.get_current_source(), {"sequence": _submission_count})
		else:
			_recorder.record("timeline_rejected", _recorder.get_current_source(), {"sequence": _submission_count, "violation_count": violated_required.size()})
			_recorder.record("violation_shown", _recorder.get_current_source(), {"violated_required": (violated_required as Array).duplicate()})

	_moves_since_submission = 0
	_can_resubmit = false
	result["accepted"] = accepted_now
	result["blocked_duplicate"] = false
	_last_result = result.duplicate(true)
	if accepted_now:
		_accepted = true
		_accepted_placements = _placements.duplicate()
	return result


## Event ids -> "HH:MM", sorted by event id — the deterministic, exported
## payload shape (docs/prototype-c.md, "Recorder events").
func _normalized_placements() -> Dictionary:
	var ids: Array[String] = _all_event_ids.duplicate()
	ids.sort()
	var out: Dictionary = {}
	for event_id in ids:
		out[event_id] = get_placement(event_id)
	return out


# ---------------------------------------------------------------------------
# Objective timeline facts — player-visible natural-language readouts of the
# REQUIRED constraints only (docs/prototype-c.md). "Opening" one is tracked
# for the anti-brute-force / reading-vs-guessing metrics; the fact text
# itself is always true and never gated behind anything else.

func get_fact_ids() -> Array[String]:
	var ids: Array[String] = []
	for constraint_id in (_proto.get("visible_constraint_facts", {}) as Dictionary):
		ids.append(str(constraint_id))
	return ids


func has_opened_fact(constraint_id: String) -> bool:
	return _opened_fact_ids.has(constraint_id)


func open_fact(constraint_id: String) -> bool:
	if not get_fact_ids().has(constraint_id) or _opened_fact_ids.has(constraint_id):
		return false
	_opened_fact_ids.append(constraint_id)
	if _recorder != null:
		_recorder.record("timeline_fact_opened", _recorder.get_current_source(), {"constraint_id": constraint_id})
	return true


## Event ids a violated (or any) constraint references — used by the
## presenter to highlight the involved event cards without exposing the raw
## constraint dictionary itself.
func constraint_event_ids(constraint_id: String) -> Array[String]:
	for constraint in TimelineEvaluator.constraints(_case_def):
		if str(constraint.get("id", "")) == constraint_id:
			return TimelineEvaluator.constraint_event_ids(constraint)
	return []


# ---------------------------------------------------------------------------
# Hints — Prototype-C-owned data (case_def.prototype_c.hint_ladder), one flat
# 4-level ladder per case (there is only ever one puzzle, not several rounds).
## See the class doc above for why this is never routed through a
## DeductionSession/DeductionEvaluator hint call.

func get_hint_ladder() -> Array[String]:
	return DeductionEvaluator.string_array(_proto.get("hint_ladder", []))


func get_hint_level() -> int:
	return _hint_level


## Reveals the next hint level, or repeats the last one ("exhausted": true)
## once the ladder is used up. Mirrors PrototypeAController.reveal_next_hint()'s
## contract exactly.
func reveal_next_hint() -> Dictionary:
	var ladder: Array[String] = get_hint_ladder()
	if ladder.is_empty():
		return {"available": false, "level": 0, "text_key": "", "exhausted": false}
	var is_exhausted: bool = _hint_level >= ladder.size()
	var next_level: int = mini(_hint_level + 1, ladder.size())
	if not is_exhausted:
		_hint_level = next_level
		if _recorder != null:
			_recorder.record("hint_revealed", _recorder.get_current_source(), {"level": next_level})
	return {"available": true, "level": next_level, "text_key": ladder[next_level - 1], "exhausted": is_exhausted}


# ---------------------------------------------------------------------------
# Final claim check — reveals one disputed NPC statement only once the
# reconstruction is accepted, and evaluates its compatibility with the
# ACCEPTED placement through TimelineEvaluator.is_constraint_satisfied() —
# the exact same constraint semantics used for the reconstruction itself,
# never a private re-implementation.

func get_claim_statement_id() -> String:
	return str((_proto.get("contradiction", {}) as Dictionary).get("claim", ""))


func _contradiction_constraint() -> Dictionary:
	var ref: String = str((_proto.get("contradiction", {}) as Dictionary).get("constraint_ref", ""))
	for constraint in TimelineEvaluator.constraints(_case_def):
		if str(constraint.get("id", "")) == ref:
			return constraint
	return {}


func is_claim_phase() -> bool:
	return _accepted and not _claim_resolved


func is_claim_resolved() -> bool:
	return _claim_resolved


func get_claim_attempts() -> int:
	return _claim_attempts


## `chose_impossible` is the player's answer (true = "Impossible", false =
## "Fits the timeline"). Compatibility is decided by whether the ACCEPTED
## timeline satisfies the disputed constraint — true for every case's
## content, "Impossible" is always the correct answer, but this is computed
## generically rather than hardcoded, so a future case's content is checked
## the same way. Returns {"correct": bool, "resolved": bool}; a call before
## acceptance or after resolution is a safe no-op ({"correct": false,
## "resolved": is_claim_resolved()}).
func answer_claim(chose_impossible: bool) -> Dictionary:
	if not _accepted or _claim_resolved:
		return {"correct": false, "resolved": _claim_resolved}
	_claim_attempts += 1
	var starts: Dictionary = {}
	for event_id in _accepted_placements:
		starts[event_id] = TimelineEvaluator.parse_time(_accepted_placements[event_id])
	var claim_fits: bool = TimelineEvaluator.is_constraint_satisfied(_contradiction_constraint(), starts, _events_index)
	var correct: bool = chose_impossible == (not claim_fits)
	if _recorder != null:
		_recorder.record("claim_answered", _recorder.get_current_source(), {
			"attempt": _claim_attempts, "answer": "impossible" if chose_impossible else "fits", "correct": correct,
		})
	if correct:
		_claim_resolved = true
		if _recorder != null:
			_recorder.record("contradiction_resolved", _recorder.get_current_source(), {"attempt": _claim_attempts})
	return {"correct": correct, "resolved": _claim_resolved}


## The accepted placement's actual "HH:MM" for `event_id` — used by the
## presenter to interpolate the real time into the contradiction explanation,
## so it stays true for whichever valid timeline the player actually built.
func get_accepted_time(event_id: String) -> String:
	return str(_accepted_placements.get(event_id, ""))


## Called when the player dismisses the resolved-claim feedback ("Continue").
## Completes the prototype only if the claim is actually resolved — otherwise
## a safe no-op. Idempotent, like PrototypeBController.acknowledge_result().
func acknowledge_claim() -> Dictionary:
	if _completed:
		return {"prototype_completed": true}
	if not _claim_resolved:
		return {"prototype_completed": false}
	_completed = true
	if _recorder != null:
		_recorder.record("prototype_completed", _recorder.get_current_source(), get_stats())
	return {"prototype_completed": true}


# ---------------------------------------------------------------------------
# Progress and stats

func has_progress() -> bool:
	return _submission_count > 0 or _total_moves > 0 or not _opened_fact_ids.is_empty() \
		or _hint_level > 0 or _claim_attempts > 0


func get_stats() -> Dictionary:
	return {
		"elapsed_ms": maxi(int(_clock_fn.call()) - _start_ticks, 0),
		"submissions": _submission_count,
		"failed": _failed_submission_count,
		"moves": _total_moves,
		"facts_opened": _opened_fact_ids.size(),
		"hints_used": _hint_level,
		"claim_attempts": _claim_attempts,
	}


## Records "prototype_abandoned" (with the current stats) if there was any
## progress worth noting and the run never completed. Safe to call more than
## once or on a completed/fresh run — both are no-ops.
func abandon() -> void:
	if _completed or _recorder == null or not has_progress():
		return
	_recorder.record("prototype_abandoned", _recorder.get_current_source(), get_stats())
