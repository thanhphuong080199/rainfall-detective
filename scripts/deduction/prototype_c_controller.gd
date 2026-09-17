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
## Milestone 1.14 (docs/resolution-policy.md): placing/moving/removing and
## reading facts stay free; "Check Timeline" and "Submit Verdict" are the two
## formal commits, each its own ResolutionPolicy unit (the timeline, then the
## claim). An incomplete board, a placement identical to ANY earlier failed
## one, and a verdict+fact pair that already failed are refused without cost.
## Timeline feedback is progressive: the first failure names only a broad
## category (anchor/window/order/overlap/travel), later failures one
## deterministic violated fact and its events, the third requires
## assistance, and after two more a partner timeline — applied only if
## TimelineEvaluator accepts it — finishes the unit. The final claim needs a
## verdict AND one supporting fact from contradiction.supporting_constraint_refs
## (validated by DeductionValidator to be exactly the facts that rule the
## claim out on their own).
##
## Optionally wired to a DeductionLabRecorder (Milestone 1.10, reused
## unmodified) passed into start(). This class decides WHAT and WHEN to
## record for the Prototype C event vocabulary; the recorder itself carries
## no Prototype-C-specific code — see docs/prototype-c.md, "Recorder events".

const UNIT_TIMELINE := 0
const UNIT_CLAIM := 1

const ANSWER_FITS := "fits"
const ANSWER_IMPOSSIBLE := "impossible"

## Timeline-rejection feedback levels ("feedback"."level" on a result).
const FEEDBACK_CATEGORY := "category"
const FEEDBACK_FACT := "fact"
## Claim-rejection feedback levels ("feedback_level" on a claim result).
const FEEDBACK_COARSE := "coarse"
const FEEDBACK_GUIDED := "guided"

## Broad violation categories, by TimelineEvaluator constraint type — the ONLY
## thing a first failed timeline reveals.
const VIOLATION_CATEGORIES := {
	"fixed_time": "anchor", "window": "window", "before": "order", "no_overlap": "overlap", "travel_time": "travel",
}
const PAIR_CONSTRAINT_TYPES := ["before", "no_overlap", "travel_time"]

const REASON_INCOMPLETE := "incomplete_selection"
const REASON_ALREADY_ACCEPTED := "already_accepted"
const REASON_SUBMISSION_LOCKED := "submission_locked"
const REASON_NOT_IN_CLAIM_PHASE := "not_in_claim_phase"
const REASON_MISSING_JUSTIFICATION := "missing_justification"
const REASON_DUPLICATE_CLAIM := "duplicate_failed_claim"
const REASON_PARTNER_UNAVAILABLE := "partner_unavailable"
const REASON_INTERNAL_ERROR := "internal_error"

const PARTNER_SOURCE_AUTHORED := "authored_solution"
const PARTNER_SOURCE_ENUMERATED := "enumerated_candidate"

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
var _failed_placement_keys: Dictionary = {}
var _last_result: Dictionary = {}
var _last_violated_facts: Array[String] = []
var _accepted: bool = false
var _accepted_placements: Dictionary = {}
var _timeline_resolved_by: String = ""
var _partner_explained_fact_ids: Array[String] = []
var _assistance_constraint_id: String = ""
var _claim_answer: String = ""
var _claim_justification_id: String = ""
var _failed_claim_keys: Dictionary = {}
var _claim_attempts: int = 0
var _failed_claim_count: int = 0
var _claim_resolved: bool = false
var _claim_resolved_by: String = ""
var _completed: bool = false
var _policy: ResolutionPolicy = null
var _run_count: int = 0
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
## Calling this again (Restart) discards all previous interaction state and
## the previous ResolutionPolicy — recorded as "prototype_restarted" before the
## new run's "prototype_started". Fixed events are pre-placed at the exact time
## their own authored `fixed_time` timeline constraint declares — read from the
## timeline itself, never duplicated into prototype_c's own data. `recorder`,
## if given, receives this run's telemetry; pass null to run unrecorded.
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

	var previous_run: Dictionary = _previous_run_payload(str(case_def.get("id", "")))
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
	_failed_placement_keys = {}
	_last_result = {}
	_last_violated_facts = []
	_accepted = false
	_accepted_placements = {}
	_timeline_resolved_by = ""
	_partner_explained_fact_ids = []
	_assistance_constraint_id = ""
	_claim_answer = ""
	_claim_justification_id = ""
	_failed_claim_keys = {}
	_claim_attempts = 0
	_failed_claim_count = 0
	_claim_resolved = false
	_claim_resolved_by = ""
	_completed = false
	_policy = ResolutionPolicy.new()
	_run_count += 1
	_recorder = recorder
	_start_ticks = int(_clock_fn.call())

	if not previous_run.is_empty():
		_record(ResolutionPolicy.EVENT_PROTOTYPE_RESTARTED, previous_run)
	_record("prototype_started", {"case_id": str(case_def.get("id", "")), "run": _run_count})
	return true


func _fixed_time_of(event_id: String) -> String:
	for constraint in TimelineEvaluator.constraints(_case_def):
		if str(constraint.get("type", "")) == "fixed_time" and str(constraint.get("event", "")) == event_id:
			return str(constraint.get("time", ""))
	return ""


func get_case_def() -> Dictionary:
	return _case_def


## The run's ResolutionPolicy (null before start()). Read-only use by the
## presenter/tests — every mutation goes through this controller.
func get_policy() -> ResolutionPolicy:
	return _policy


func get_run_count() -> int:
	return _run_count


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
# no-op (nothing recorded, no move counted). Every one of these is free —
# never a formal commit.

func get_selected_event_id() -> String:
	return _selected_event_id


## Rejects a fixed event (locked, cannot be selected for placement) or an
## unknown id.
func select_event(event_id: String) -> bool:
	if not _movable_events.has(event_id):
		return false
	_selected_event_id = event_id
	_record("event_selected", {"event_id": event_id})
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
	if _accepted or not _movable_events.has(event_id):
		return false
	var previous: String = get_placement(event_id)
	if previous == time_slot:
		return false
	_placements[event_id] = time_slot
	_moves_since_submission += 1
	_total_moves += 1
	if previous == "":
		_record("event_placed", {"event_id": event_id, "time": time_slot})
	else:
		_record("event_moved", {"event_id": event_id, "from": previous, "to": time_slot})
	return true


## Removes `event_id` back to the tray. Rejects a fixed event or an already-
## unplaced one (nothing to remove, nothing recorded).
func remove_event(event_id: String) -> bool:
	if _accepted or not _movable_events.has(event_id):
		return false
	var previous: String = get_placement(event_id)
	if previous == "":
		return false
	_placements[event_id] = ""
	_moves_since_submission += 1
	_total_moves += 1
	_record("event_removed", {"event_id": event_id, "from": previous})
	return true


# ---------------------------------------------------------------------------
# Check Timeline — the timeline unit's formal commit: the real
# TimelineEvaluator against the complete placement map. Never compared to the
# authored ground_truth.solution_timeline.

## False while the current placement is identical to ANY earlier failed
## submission — "identical failed placement cannot be resubmitted until
## something changes" — or once the timeline is accepted.
func can_resubmit() -> bool:
	return not _accepted and not _failed_placement_keys.has(_placement_key())


## Whether "Check Timeline" would be a genuine formal commit right now.
func can_check_timeline() -> bool:
	return can_submit() and can_resubmit() and _policy != null and _policy.can_submit()


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func is_accepted() -> bool:
	return _accepted


## "player" or "partner" once the timeline is accepted, "" before.
func get_timeline_resolved_by() -> String:
	return _timeline_resolved_by


## Submits the complete placement to TimelineEvaluator.evaluate(). Returns the
## evaluator's result dict plus "accepted", "blocked_duplicate", "counted",
## "partner" (false) and "resolution" (ResolutionPolicy snapshot); a rejection
## adds "feedback": {"level": "category" | "fact", "category": anchor/window/
## order/overlap/travel, and — ONLY at the fact level — "constraint_id"}, chosen
## deterministically as the first violated visible fact in authored order.
##
## Counts nothing for: an incomplete board (INVALID_INPUT), an already
## accepted timeline, a locked policy, or a placement identical to an earlier
## failed one ("blocked_duplicate": true, returning that earlier result).
func submit_timeline() -> Dictionary:
	if _accepted:
		return _uncounted_timeline_result(REASON_ALREADY_ACCEPTED)
	if not can_submit():
		return _uncounted_timeline_result(REASON_INCOMPLETE)
	if not _policy.can_submit():
		return _uncounted_timeline_result(REASON_SUBMISSION_LOCKED)
	if not can_resubmit():
		var blocked: Dictionary = _last_result.duplicate(true)
		blocked["accepted"] = false
		blocked["blocked_duplicate"] = true
		blocked["counted"] = false
		blocked["resolution"] = _policy.result_snapshot({})
		return blocked

	_submission_count += 1
	_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_STARTED, {"unit": UNIT_TIMELINE, "sequence": _submission_count, "run_resolution_result": _policy.get_run_resolution_result()})
	var result: Dictionary = TimelineEvaluator.evaluate(_case_def, _placements)
	var accepted_now: bool = str(result.get("category", "")) == TimelineEvaluator.CONSISTENT
	var violated_required: Array = result.get("violated_required", [])
	_record("timeline_submitted", {
		"sequence": _submission_count, "placements": _normalized_placements(),
		"moves_since_previous": _moves_since_submission, "facts_opened": _opened_fact_ids.size(),
		"category": str(result.get("category", "")), "violation_count": violated_required.size(),
	})
	_moves_since_submission = 0

	var transition: Dictionary
	if accepted_now:
		_accepted = true
		_accepted_placements = _placements.duplicate()
		_timeline_resolved_by = ResolutionPolicy.RESOLVED_BY_PLAYER
		_record("timeline_accepted", {"sequence": _submission_count, "resolved_by": ResolutionPolicy.RESOLVED_BY_PLAYER})
		transition = _policy.register_success()
		_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_SUCCEEDED, {
			"unit": UNIT_TIMELINE, "sequence": _submission_count, "resolved_by": ResolutionPolicy.RESOLVED_BY_PLAYER, "run_resolution_result": _policy.get_run_resolution_result(),
		})
	else:
		_failed_submission_count += 1
		_failed_placement_keys[_placement_key()] = true
		_last_violated_facts = _visible_fact_ids(violated_required)
		_record("timeline_rejected", {"sequence": _submission_count, "violation_count": violated_required.size()})
		_record("violation_shown", {"violated_required": violated_required.duplicate()})
		transition = _policy.register_failed_commit()
		_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_FAILED, {
			"unit": UNIT_TIMELINE, "sequence": _submission_count, "current_unit_failures": _policy.get_current_unit_failures(),
			"standard_attempts_remaining": _policy.get_standard_attempts_remaining(),
			"assisted_attempts_remaining": _policy.get_assisted_attempts_remaining(),
			"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
		})
		result["feedback"] = _violation_feedback()
	_record_transition(transition, UNIT_TIMELINE)

	result["accepted"] = accepted_now
	result["blocked_duplicate"] = false
	result["counted"] = true
	result["partner"] = false
	result["resolution"] = _policy.result_snapshot(transition)
	_last_result = result.duplicate(true)
	if accepted_now:
		_policy.begin_next_unit()
	return result


## Progressive, non-oracular feedback for the failure just registered: only a
## broad category on the unit's first failure, one deterministic fact after.
func _violation_feedback() -> Dictionary:
	var first: String = _last_violated_facts[0] if not _last_violated_facts.is_empty() else ""
	var feedback: Dictionary = {
		"level": FEEDBACK_CATEGORY if _policy.get_current_unit_failures() <= 1 else FEEDBACK_FACT,
		"category": str(VIOLATION_CATEGORIES.get(_constraint_type(first), "")),
	}
	if feedback["level"] == FEEDBACK_FACT and first != "":
		feedback["constraint_id"] = first
	return feedback


## Event ids -> "HH:MM", sorted by event id — the deterministic, exported
## payload shape (docs/prototype-c.md, "Recorder events"), and the identity
## used for duplicate-failure blocking.
func _normalized_placements() -> Dictionary:
	var ids: Array[String] = _all_event_ids.duplicate()
	ids.sort()
	var out: Dictionary = {}
	for event_id in ids:
		out[event_id] = get_placement(event_id)
	return out


func _placement_key() -> String:
	return JSON.stringify(_normalized_placements())


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
	_record("timeline_fact_opened", {"constraint_id": constraint_id})
	return true


## Event ids a violated (or any) constraint references — used by the
## presenter to highlight the involved event cards without exposing the raw
## constraint dictionary itself.
func constraint_event_ids(constraint_id: String) -> Array[String]:
	return TimelineEvaluator.constraint_event_ids(_find_constraint(constraint_id))


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
## once the ladder is used up. A newly revealed level is registered with the
## ResolutionPolicy and its snapshot returned under "resolution".
func reveal_next_hint() -> Dictionary:
	var ladder: Array[String] = get_hint_ladder()
	if ladder.is_empty() or _policy == null:
		return {"available": false, "level": 0, "text_key": "", "exhausted": false, "resolution": {}}
	var is_exhausted: bool = _hint_level >= ladder.size()
	var next_level: int = mini(_hint_level + 1, ladder.size())
	var transition: Dictionary = {}
	if not is_exhausted:
		_hint_level = next_level
		_record("hint_revealed", {"level": next_level})
		transition = _policy.register_hint(next_level)
		_record_transition(transition, _policy.get_unit_index())
	return {
		"available": true, "level": next_level, "text_key": ladder[next_level - 1], "exhausted": is_exhausted,
		"resolution": _policy.result_snapshot(transition),
	}


# ---------------------------------------------------------------------------
# Assistance and partner resolution (Milestone 1.14).

## Which unit the policy is on: UNIT_TIMELINE until the timeline is accepted,
## then UNIT_CLAIM.
func get_resolution_unit() -> int:
	return _policy.get_unit_index() if _policy != null else UNIT_TIMELINE


## Acknowledges the assistance the policy requires. For the timeline unit it
## pins the critical constraint of the latest failed timeline (the first
## violated PAIR fact — before/no_overlap/travel_time — else the first
## violated fact); for the claim unit, the disputed claim's own constraint. It
## never moves an event and never selects an answer.
func accept_assistance() -> Dictionary:
	if _case_def.is_empty() or _completed:
		return {"accepted": false, "resolution": {}}
	var transition: Dictionary = _policy.accept_assistance()
	if transition.get("accepted", false) != true:
		return {"accepted": false, "resolution": _policy.result_snapshot({})}
	var unit: int = _policy.get_unit_index()
	_assistance_constraint_id = _critical_violation_id() if unit == UNIT_TIMELINE else _contradiction_ref()
	_record(ResolutionPolicy.EVENT_ASSISTANCE_ACCEPTED, {
		"unit": unit, "constraint_id": _assistance_constraint_id,
		"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
	})
	_record_transition(transition, unit)
	return {"accepted": true, "resolution": _policy.result_snapshot(transition)}


## The constraint assistance points at — "" until the CURRENT unit's
## assistance has been acknowledged.
func get_assistance_constraint_id() -> String:
	return _assistance_constraint_id if _policy != null and _policy.is_unit_assistance_accepted() else ""


func _critical_violation_id() -> String:
	for constraint_id in _last_violated_facts:
		if PAIR_CONSTRAINT_TYPES.has(_constraint_type(constraint_id)):
			return constraint_id
	return _last_violated_facts[0] if not _last_violated_facts.is_empty() else ""


## Resolves the CURRENT unit with the partner once blind submission closed:
## the timeline (a placement TimelineEvaluator accepts — the authored solution,
## else the first accepted UI-offered candidate) or the claim (the correct
## verdict with the first authored supporting fact). Returns a result shaped
## like submit_timeline()/answer_claim() with "partner": true.
func resolve_with_partner() -> Dictionary:
	if _case_def.is_empty() or _completed or not _policy.can_use_partner_resolution():
		return _uncounted_timeline_result(REASON_PARTNER_UNAVAILABLE) if not _accepted else _uncounted_claim_result(REASON_PARTNER_UNAVAILABLE)
	if not _accepted:
		return _resolve_timeline_with_partner()
	return _resolve_claim_with_partner()


func _resolve_timeline_with_partner() -> Dictionary:
	var candidate: Dictionary = _partner_timeline()
	if candidate.is_empty():
		return _uncounted_timeline_result(REASON_INTERNAL_ERROR)
	var result: Dictionary = TimelineEvaluator.evaluate(_case_def, candidate["placements"])
	if str(result.get("category", "")) != TimelineEvaluator.CONSISTENT:
		return _uncounted_timeline_result(REASON_INTERNAL_ERROR)

	_placements = (candidate["placements"] as Dictionary).duplicate()
	_accepted = true
	_accepted_placements = _placements.duplicate()
	_timeline_resolved_by = ResolutionPolicy.RESOLVED_BY_PARTNER
	_partner_explained_fact_ids = _last_violated_facts.duplicate()
	var transition: Dictionary = _policy.register_partner_resolution()
	_record(ResolutionPolicy.EVENT_PARTNER_RESOLUTION_USED, {
		"unit": UNIT_TIMELINE, "placements": _normalized_placements(), "source": candidate["source"],
		"resolved_by": ResolutionPolicy.RESOLVED_BY_PARTNER,
		"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
	})
	_record("timeline_accepted", {"sequence": _submission_count, "resolved_by": ResolutionPolicy.RESOLVED_BY_PARTNER})
	_record_transition(transition, UNIT_TIMELINE)

	result["accepted"] = true
	result["blocked_duplicate"] = false
	result["counted"] = false
	result["partner"] = true
	result["explained_constraint_ids"] = _partner_explained_fact_ids.duplicate()
	result["resolution"] = _policy.result_snapshot(transition)
	_last_result = result.duplicate(true)
	_policy.begin_next_unit()
	return result


## The authored solution when TimelineEvaluator accepts it; otherwise the
## first UI-offered placement the evaluator accepts. {} if neither exists.
func _partner_timeline() -> Dictionary:
	var placement: Dictionary = {}
	for event_id in _fixed_events:
		placement[event_id] = _fixed_time_of(event_id)
	var solution: Variant = (_case_def.get("ground_truth", {}) as Dictionary).get("solution_timeline", {})
	var complete: bool = typeof(solution) == TYPE_DICTIONARY
	for event_id in _movable_events:
		var time: String = str((solution as Dictionary).get(event_id, "")) if complete else ""
		complete = complete and _time_slots.has(time)
		placement[event_id] = time
	if complete and str(TimelineEvaluator.evaluate(_case_def, placement).get("category", "")) == TimelineEvaluator.CONSISTENT:
		return {"placements": placement, "source": PARTNER_SOURCE_AUTHORED}
	var accepted: Array[Dictionary] = DeductionValidator.enumerate_accepted_prototype_c_timelines(_case_def)
	if not accepted.is_empty():
		return {"placements": accepted[0], "source": PARTNER_SOURCE_ENUMERATED}
	return {}


## Which facts the player's last failed timeline violated — what a partner
## timeline explains it now satisfies ([] unless the partner resolved it).
func get_partner_explained_fact_ids() -> Array[String]:
	return _partner_explained_fact_ids.duplicate() if _timeline_resolved_by == ResolutionPolicy.RESOLVED_BY_PARTNER else []


func _resolve_claim_with_partner() -> Dictionary:
	var justification: String = ""
	for ref in get_supporting_constraint_ids():
		if get_fact_ids().has(ref):
			justification = ref
			break
	if justification == "":
		return _uncounted_claim_result(REASON_INTERNAL_ERROR)
	_claim_answer = ANSWER_FITS if _claim_fits() else ANSWER_IMPOSSIBLE
	_claim_justification_id = justification
	_claim_resolved = true
	_claim_resolved_by = ResolutionPolicy.RESOLVED_BY_PARTNER
	var transition: Dictionary = _policy.register_partner_resolution()
	_record(ResolutionPolicy.EVENT_PARTNER_RESOLUTION_USED, {
		"unit": UNIT_CLAIM, "answer": _claim_answer, "justification_constraint_id": justification,
		"resolved_by": ResolutionPolicy.RESOLVED_BY_PARTNER,
		"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
	})
	_record("contradiction_resolved", {"attempt": _claim_attempts, "resolved_by": ResolutionPolicy.RESOLVED_BY_PARTNER})
	_record_transition(transition, UNIT_CLAIM)
	return {"correct": true, "resolved": true, "counted": false, "partner": true, "reason": "", "resolution": _policy.result_snapshot(transition)}


# ---------------------------------------------------------------------------
# Final claim — reveals one disputed NPC statement only once the
# reconstruction is accepted. The player must choose a verdict AND the one
# established fact that justifies it; compatibility is always decided by
# TimelineEvaluator.is_constraint_satisfied() against the ACCEPTED placement.

func get_claim_statement_id() -> String:
	return str((_proto.get("contradiction", {}) as Dictionary).get("claim", ""))


## The authored facts that, on their own, rule the claim out (validated by
## DeductionValidator.prototype_c_facts_ruling_out_claim()).
func get_supporting_constraint_ids() -> Array[String]:
	return DeductionEvaluator.string_array((_proto.get("contradiction", {}) as Dictionary).get("supporting_constraint_refs", []))


func _contradiction_ref() -> String:
	return str((_proto.get("contradiction", {}) as Dictionary).get("constraint_ref", ""))


func _contradiction_constraint() -> Dictionary:
	return _find_constraint(_contradiction_ref())


## The event(s) the disputed claim is about — for claim-unit assistance.
func get_claim_event_ids() -> Array[String]:
	return TimelineEvaluator.constraint_event_ids(_contradiction_constraint())


func is_claim_phase() -> bool:
	return _accepted and not _claim_resolved


func is_claim_resolved() -> bool:
	return _claim_resolved


func get_claim_resolved_by() -> String:
	return _claim_resolved_by


func get_claim_attempts() -> int:
	return _claim_attempts


## Free selection of a verdict — never a formal commit on its own.
func select_claim_answer(chose_impossible: bool) -> bool:
	if not is_claim_phase():
		return false
	_claim_answer = ANSWER_IMPOSSIBLE if chose_impossible else ANSWER_FITS
	return true


## Free selection of the supporting fact — must be a player-visible fact.
func select_claim_justification(constraint_id: String) -> bool:
	if not is_claim_phase() or not get_fact_ids().has(constraint_id):
		return false
	_claim_justification_id = constraint_id
	return true


## "" | "fits" | "impossible" — the selected (or, once resolved, accepted)
## verdict.
func get_selected_claim_answer() -> String:
	return _claim_answer


## The selected (or, once resolved, accepted) supporting fact id.
func get_selected_justification_id() -> String:
	return _claim_justification_id


func can_submit_claim() -> bool:
	return is_claim_phase() and _claim_answer != "" and _claim_justification_id != "" and _policy.can_submit() \
		and not _failed_claim_keys.has(_claim_key(_claim_answer, _claim_justification_id))


## Submits the currently selected verdict + supporting fact.
func submit_claim() -> Dictionary:
	if _claim_answer == "":
		return _uncounted_claim_result(REASON_MISSING_JUSTIFICATION)
	return answer_claim(_claim_answer == ANSWER_IMPOSSIBLE, _claim_justification_id)


## The claim unit's formal commit. `chose_impossible` is the verdict (true =
## "Impossible", false = "Fits the timeline"); `justification_id` must be a
## visible fact. Correct only when the verdict matches the accepted timeline
## (decided by TimelineEvaluator.is_constraint_satisfied(), never hardcoded)
## AND the fact is one of contradiction.supporting_constraint_refs. A binary
## verdict alone can never complete.
##
## Returns {"correct", "resolved", "counted", "partner", "reason",
## "resolution"}; a counted failure adds "feedback_level" ("coarse" first,
## "guided" after) and — ONLY when guided — "verdict_correct". Counts nothing
## (and records nothing) outside the claim phase, without a justification,
## while locked, or for a verdict+fact pair that already failed. The accepted
## timeline is never touched.
func answer_claim(chose_impossible: bool, justification_id: String = "") -> Dictionary:
	if not is_claim_phase():
		return _uncounted_claim_result(REASON_NOT_IN_CLAIM_PHASE)
	if justification_id == "" or not get_fact_ids().has(justification_id):
		return _uncounted_claim_result(REASON_MISSING_JUSTIFICATION)
	if not _policy.can_submit():
		return _uncounted_claim_result(REASON_SUBMISSION_LOCKED)
	var answer: String = ANSWER_IMPOSSIBLE if chose_impossible else ANSWER_FITS
	var key: String = _claim_key(answer, justification_id)
	if _failed_claim_keys.has(key):
		return _uncounted_claim_result(REASON_DUPLICATE_CLAIM)

	_claim_attempts += 1
	_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_STARTED, {"unit": UNIT_CLAIM, "sequence": _claim_attempts, "run_resolution_result": _policy.get_run_resolution_result()})
	var verdict_correct: bool = chose_impossible == (not _claim_fits())
	var justification_valid: bool = get_supporting_constraint_ids().has(justification_id)
	var correct: bool = verdict_correct and justification_valid
	_record("claim_answered", {
		"attempt": _claim_attempts, "answer": answer, "justification_constraint_id": justification_id, "correct": correct,
	})
	_record("claim_justification_result", {
		"attempt": _claim_attempts, "justification_constraint_id": justification_id,
		"verdict_correct": verdict_correct, "justification_valid": justification_valid, "correct": correct,
	})

	var transition: Dictionary
	if correct:
		_claim_answer = answer
		_claim_justification_id = justification_id
		_claim_resolved = true
		_claim_resolved_by = ResolutionPolicy.RESOLVED_BY_PLAYER
		_record("contradiction_resolved", {"attempt": _claim_attempts, "resolved_by": ResolutionPolicy.RESOLVED_BY_PLAYER})
		transition = _policy.register_success()
		_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_SUCCEEDED, {
			"unit": UNIT_CLAIM, "sequence": _claim_attempts, "resolved_by": ResolutionPolicy.RESOLVED_BY_PLAYER, "run_resolution_result": _policy.get_run_resolution_result(),
		})
	else:
		_failed_claim_count += 1
		_failed_claim_keys[key] = true
		transition = _policy.register_failed_commit()
		_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_FAILED, {
			"unit": UNIT_CLAIM, "sequence": _claim_attempts, "current_unit_failures": _policy.get_current_unit_failures(),
			"standard_attempts_remaining": _policy.get_standard_attempts_remaining(),
			"assisted_attempts_remaining": _policy.get_assisted_attempts_remaining(),
			"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
		})
	_record_transition(transition, UNIT_CLAIM)

	var result: Dictionary = {
		"correct": correct, "resolved": _claim_resolved, "counted": true, "partner": false, "reason": "",
		"resolution": _policy.result_snapshot(transition),
	}
	if not correct:
		result["feedback_level"] = FEEDBACK_COARSE if _policy.get_current_unit_failures() <= 1 else FEEDBACK_GUIDED
		if result["feedback_level"] == FEEDBACK_GUIDED:
			result["verdict_correct"] = verdict_correct
	return result


func _claim_fits() -> bool:
	var starts: Dictionary = {}
	for event_id in _accepted_placements:
		starts[event_id] = TimelineEvaluator.parse_time(_accepted_placements[event_id])
	return TimelineEvaluator.is_constraint_satisfied(_contradiction_constraint(), starts, _events_index)


func _claim_key(answer: String, justification_id: String) -> String:
	return "%s|%s" % [answer, justification_id]


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
	_record("prototype_completed", _stats_with_resolution())
	return {"prototype_completed": true}


# ---------------------------------------------------------------------------
# Progress and stats

func has_progress() -> bool:
	return _submission_count > 0 or _total_moves > 0 or not _opened_fact_ids.is_empty() \
		or _hint_level > 0 or _claim_attempts > 0 or (_policy != null and _policy.get_partner_resolution_count() > 0)


## Numeric-only statistics; the resolution tier is reported separately.
func get_stats() -> Dictionary:
	return {
		"elapsed_ms": maxi(int(_clock_fn.call()) - _start_ticks, 0),
		"submissions": _submission_count,
		"failed": _failed_submission_count,
		"moves": _total_moves,
		"facts_opened": _opened_fact_ids.size(),
		"hints_used": _hint_level,
		"claim_attempts": _claim_attempts,
		"assistance_used": _policy.get_assistance_count() if _policy != null else 0,
		"partner_resolutions": _policy.get_partner_resolution_count() if _policy != null else 0,
	}


## Records "prototype_abandoned" (with the current stats) if there was any
## progress worth noting and the run never completed. Safe to call more than
## once or on a completed/fresh run — both are no-ops.
func abandon() -> void:
	if _completed or _recorder == null or not has_progress():
		return
	_record("prototype_abandoned", _stats_with_resolution())


# ---------------------------------------------------------------------------
# Private

func _find_constraint(constraint_id: String) -> Dictionary:
	for constraint in TimelineEvaluator.constraints(_case_def):
		if str(constraint.get("id", "")) == constraint_id:
			return constraint
	return {}


func _constraint_type(constraint_id: String) -> String:
	return str(_find_constraint(constraint_id).get("type", ""))


func _visible_fact_ids(constraint_ids: Array) -> Array[String]:
	var facts: Array[String] = get_fact_ids()
	var out: Array[String] = []
	for constraint_id in constraint_ids:
		if facts.has(str(constraint_id)):
			out.append(str(constraint_id))
	return out


func _record(event_type: String, payload: Dictionary) -> void:
	if _recorder != null:
		_recorder.record(event_type, _recorder.get_current_source(), payload)


func _record_transition(transition: Dictionary, unit: int) -> void:
	for event in ResolutionPolicy.transition_events(transition):
		var payload: Dictionary = (event["payload"] as Dictionary).duplicate()
		payload["unit"] = unit
		_record(str(event["type"]), payload)


func _stats_with_resolution() -> Dictionary:
	var payload: Dictionary = get_stats()
	payload["resolution"] = _policy.get_summary() if _policy != null else {}
	return payload


func _previous_run_payload(next_case_id: String) -> Dictionary:
	if _case_def.is_empty() or _policy == null:
		return {}
	return {
		"case_id": next_case_id, "previous_case_id": str(_case_def.get("id", "")), "previous_run": _run_count,
		"previous_completed": _completed, "previous_run_resolution_result": _policy.get_run_resolution_result(),
		"previous_formal_commits": _policy.get_formal_commit_count(), "previous_failed_commits": _policy.get_failed_commit_count(),
	}


func _uncounted_timeline_result(reason: String) -> Dictionary:
	var empty_required: Array[String] = []
	var empty_optional: Array[String] = []
	return {
		"category": TimelineEvaluator.INVALID_INPUT, "reason": reason,
		"violated_required": empty_required, "violated_optional": empty_optional,
		"accepted": _accepted, "blocked_duplicate": false, "counted": false, "partner": false,
		"resolution": _policy.result_snapshot({}) if _policy != null else {},
	}


func _uncounted_claim_result(reason: String) -> Dictionary:
	return {
		"correct": false, "resolved": _claim_resolved, "counted": false, "partner": false, "reason": reason,
		"resolution": _policy.result_snapshot({}) if _policy != null else {},
	}
