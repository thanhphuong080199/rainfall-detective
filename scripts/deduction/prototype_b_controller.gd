class_name PrototypeBController
extends RefCounted
## Interaction-state host for the debug-only Prototype B — Clue Connection
## prototype (Milestone 1.12 — see docs/prototype-b.md). Owns exactly ONE
## fresh, isolated DeductionSession per run (never the Deduction Lab's own
## session, never a PrototypeAController's) plus Prototype-B-specific
## interaction state: current round, the clues currently placed in this
## round's connection slots, submission/failure/replacement counts, and
## prototype completion.
##
## Every submitted connection is classified/committed through the REAL
## DeductionEvaluator/DeductionSession path (the round's own authored
## relation, exactly `slot_count` evidence items) — this class adds zero
## grading logic of its own. Pure and autoload-free, like
## PrototypeAController/DeductionLabController: the caller
## (scripts/debug/prototype_b.gd) fetches case_def via ContentDB and hands it
## in, never resolves a case id itself.
##
## Hints are NOT Prototype-B-owned data, unlike Prototype A: every round
## targets a real "deduction" claim, which the base contract's own hint
## ladders already support (docs/deduction-system.md, "Hint ladders"), so
## this controller simply calls DeductionEvaluator.request_hint() and reads
## DeductionSession.get_hint_level() — never a private mutation, never a
## second hint-state shape.
##
## Optionally wired to a DeductionLabRecorder (Milestone 1.10, reused
## unmodified) passed into start(). This class decides WHAT and WHEN to
## record for the Prototype B event vocabulary; the recorder itself carries
## no Prototype-B-specific code — see docs/prototype-b.md, "Recorder events".

var _case_def: Dictionary = {}
var _rounds: Array[Dictionary] = []
var _session: DeductionSession = null
var _recorder: DeductionLabRecorder = null
var _round_index: int = 0
var _selected_evidence_ids: Array[String] = []
var _submission_count: int = 0
var _failed_attempt_count: int = 0
var _replacement_count: int = 0
var _completed: bool = false
var _clock_fn: Callable
var _start_ticks: int = 0


## `clock_fn` (no args, returns int/float monotonic milliseconds — defaults
## to Time.get_ticks_msec) is injectable for deterministic tests, matching
## PrototypeAController's/DeductionLabRecorder's own convention.
func _init(clock_fn: Callable = Callable()) -> void:
	_clock_fn = clock_fn if clock_fn.is_valid() else Callable(Time, "get_ticks_msec")


# ---------------------------------------------------------------------------
# Lifecycle

## Starts a brand-new run of `case_def` (which must declare a non-empty
## "prototype_b" data layer — see DeductionValidator._validate_prototype_b).
## Calling this again (Restart) discards all previous interaction state and
## creates a fresh, isolated DeductionSession — never reused across runs and
## never a session a Deduction Lab or Prototype A session might also be
## holding. `recorder`, if given, receives this run's telemetry; pass null to
## run unrecorded.
func start(case_def: Dictionary, recorder: DeductionLabRecorder = null) -> bool:
	if typeof(case_def) != TYPE_DICTIONARY:
		return false
	var proto: Variant = case_def.get("prototype_b")
	if typeof(proto) != TYPE_DICTIONARY:
		return false
	var rounds: Array[Dictionary] = DeductionEvaluator.dict_array(proto.get("rounds", []))
	if rounds.is_empty():
		return false

	_case_def = case_def
	_rounds = rounds
	_session = DeductionSession.new(str(case_def.get("id", "")))
	_recorder = recorder
	_round_index = 0
	_selected_evidence_ids = []
	_submission_count = 0
	_failed_attempt_count = 0
	_replacement_count = 0
	_completed = false
	_start_ticks = int(_clock_fn.call())

	if _recorder != null:
		_recorder.record("prototype_started", _recorder.get_current_source(), {"case_id": str(case_def.get("id", ""))})
		_record_round_started()
	return true


func get_case_def() -> Dictionary:
	return _case_def


func get_session() -> DeductionSession:
	return _session


func is_completed() -> bool:
	return _completed


# ---------------------------------------------------------------------------
# Rounds

func get_round_index() -> int:
	return _round_index


func get_round_count() -> int:
	return _rounds.size()


func get_current_round() -> Dictionary:
	return _rounds[_round_index] if _round_index >= 0 and _round_index < _rounds.size() else {}


func get_slot_count() -> int:
	return int(get_current_round().get("slot_count", 0))


func _record_round_started() -> void:
	_recorder.record("round_started", _recorder.get_current_source(), {"round": _round_index})


# ---------------------------------------------------------------------------
# Evidence pool — open (read) vs select (place into a slot) are distinct
# actions, mirroring PrototypeAController's own evidence handling.

func get_evidence_pool_ids() -> Array[String]:
	return DeductionEvaluator.string_array(_case_def.get("prototype_b", {}).get("evidence_pool", []))


## Marks `evidence_id` opened in the session (the sanctioned public
## DeductionSession API for this) — never a private mutation. Records
## "evidence_opened" only the first time.
func open_evidence(evidence_id: String) -> bool:
	if _session == null or not get_evidence_pool_ids().has(evidence_id):
		return false
	var first_time: bool = _session.mark_evidence_opened(evidence_id)
	if first_time and _recorder != null:
		_recorder.record("evidence_opened", _recorder.get_current_source(), {"evidence_id": evidence_id})
	return true


func get_selected_evidence_ids() -> Array[String]:
	return _selected_evidence_ids.duplicate()


func is_selected(evidence_id: String) -> bool:
	return _selected_evidence_ids.has(evidence_id)


## Places `evidence_id` into the next empty slot. Rejects (returns false, no
## state change, nothing recorded) a duplicate selection, an id outside the
## evidence pool, or a selection already at the round's slot_count — "the
## controller rejects over-capacity selection before evaluator submission"
## (docs/prototype-b.md, "Anti-brute-force"). Use replace_evidence() to swap
## one placed clue for another without clearing the rest.
func select_evidence(evidence_id: String) -> bool:
	if not get_evidence_pool_ids().has(evidence_id) or is_selected(evidence_id):
		return false
	if _selected_evidence_ids.size() >= get_slot_count():
		return false
	_selected_evidence_ids.append(evidence_id)
	if _recorder != null:
		_recorder.record("clue_selected", _recorder.get_current_source(), {"evidence_id": evidence_id})
	return true


## Removes `evidence_id` from its slot, leaving every other placed clue
## untouched — "after a failed attempt, keep the selected clues in place so
## the player can reconsider and replace one clue" (docs/prototype-b.md).
func remove_evidence(evidence_id: String) -> bool:
	if not is_selected(evidence_id):
		return false
	_selected_evidence_ids.erase(evidence_id)
	if _recorder != null:
		_recorder.record("clue_removed", _recorder.get_current_source(), {"evidence_id": evidence_id})
	return true


## Swaps `old_evidence_id` for `new_evidence_id` IN THE SAME slot position —
## "replace a selected clue without clearing everything" — as one combined
## remove+select, recording both events. A no-op (returns false) if
## `old_evidence_id` isn't currently placed, or `new_evidence_id` is invalid/
## already placed.
func replace_evidence(old_evidence_id: String, new_evidence_id: String) -> bool:
	var index: int = _selected_evidence_ids.find(old_evidence_id)
	if index < 0 or not get_evidence_pool_ids().has(new_evidence_id) or is_selected(new_evidence_id):
		return false
	_selected_evidence_ids[index] = new_evidence_id
	_replacement_count += 1
	if _recorder != null:
		_recorder.record("clue_removed", _recorder.get_current_source(), {"evidence_id": old_evidence_id})
		_recorder.record("clue_selected", _recorder.get_current_source(), {"evidence_id": new_evidence_id})
	return true


func can_submit() -> bool:
	return get_slot_count() > 0 and _selected_evidence_ids.size() == get_slot_count()


## True while at least one slot is still empty — the UI uses this to disable
## "Place" on unselected evidence rows once every slot is already filled,
## rather than letting select_evidence() simply reject the click silently.
func has_room() -> bool:
	return _selected_evidence_ids.size() < get_slot_count()


# ---------------------------------------------------------------------------
# Submitting a connection — the one proof interaction: the round's privately
# authored target + relation + the placed evidence ids, through the real
# DeductionEvaluator. Selection order never affects correctness (the
# evaluator matches by set membership, not by slot order).

## Submits the currently placed clues against the current round's target.
## Returns the evaluator's result dict (see DeductionEvaluator.commit_attempt)
## plus "already_resolved" and "round_ready" (true once the CURRENT round's
## target is resolved — the UI should offer "Continue" once this is true).
## Resubmitting an already-resolved target classifies (never commits), so
## session mutations, submission counts and telemetry are never duplicated —
## "repeated submission of an already-resolved round must be idempotent."
## A short-of-capacity submission is rejected here too (defense in depth
## behind the UI's own Connect-button-disabled gate) as INVALID_INPUT,
## without touching the session.
func submit_connection() -> Dictionary:
	var pb_round: Dictionary = get_current_round()
	var target: String = str(pb_round.get("target", ""))
	var relation: String = str(pb_round.get("relation", ""))
	if _session == null or _completed or target == "" or not can_submit():
		return {
			"category": DeductionEvaluator.INVALID_INPUT, "reason": "incomplete_selection", "claim_id": target,
			"relation": relation, "newly_resolved": false, "already_resolved": false,
			"round_ready": _current_round_resolved(),
		}

	var already_resolved: bool = _session.get_claim_status(target) != ""
	var selection: Array[String] = _selected_evidence_ids.duplicate()
	var result: Dictionary
	if already_resolved:
		result = DeductionEvaluator.classify_attempt(_case_def, _session, target, relation, selection)
		result["newly_resolved"] = false
	else:
		_submission_count += 1
		result = DeductionEvaluator.commit_attempt(_case_def, _session, target, relation, selection)
		if not DeductionEvaluator.is_valid_category(str(result.get("category", ""))):
			_failed_attempt_count += 1

	if not already_resolved and _recorder != null:
		var normalized: Array[String] = selection.duplicate()
		normalized.sort()  # deterministic exported payloads — see docs/prototype-b.md, "Recorder events".
		_recorder.record("connection_submitted", _recorder.get_current_source(), {
			"sequence": _submission_count, "round": _round_index, "target": target,
			"evidence_ids": normalized, "count": normalized.size(), "category": str(result.get("category", "")),
		})
		_recorder.record("connection_result", _recorder.get_current_source(), {"target": target, "category": str(result.get("category", ""))})

	var newly_resolved: bool = result.get("newly_resolved", false) == true
	if newly_resolved and _recorder != null:
		_recorder.record("deduction_unlocked", _recorder.get_current_source(), {"target": target})

	result["already_resolved"] = already_resolved
	result["round_ready"] = _current_round_resolved()
	return result


func _current_round_resolved() -> bool:
	if _session == null:
		return false
	var target: String = str(get_current_round().get("target", ""))
	return target != "" and _session.is_supported(target)


## Called when the player dismisses post-submission feedback ("Continue").
## Advances to the next round, or completes the prototype, ONLY if the
## current round's target is now resolved — otherwise a safe no-op
## (dismissing feedback after a wrong attempt never advances anything).
## Idempotent: calling this again after an advance already happened checks
## the NEW current round's target, which is not yet resolved, so it no-ops.
## Placed clues are cleared for the next round (fresh slots).
func acknowledge_result() -> Dictionary:
	if _completed:
		return {"round_completed": false, "prototype_completed": true}
	if not _current_round_resolved():
		return {"round_completed": false, "prototype_completed": false}

	if _recorder != null:
		_recorder.record("round_completed", _recorder.get_current_source(), {"round": _round_index})
	_selected_evidence_ids = []
	if _round_index + 1 < _rounds.size():
		_round_index += 1
		if _recorder != null:
			_record_round_started()
		return {"round_completed": true, "prototype_completed": false}

	_completed = true
	if _recorder != null:
		_recorder.record("prototype_completed", _recorder.get_current_source(), get_stats())
	return {"round_completed": true, "prototype_completed": true}


# ---------------------------------------------------------------------------
# Hints — REUSES the real base hint contract (DeductionEvaluator/
# DeductionSession), never a second, Prototype-B-owned shape. See the class
# doc above for why this differs from PrototypeAController.

## Reveals the next hint level for the current round's target through the
## real DeductionEvaluator.request_hint()/DeductionSession — see
## docs/deduction-system.md, "Hint ladders". Records "hint_revealed" only for
## a genuinely new level (never a repeat of an already-exhausted ladder).
func reveal_next_hint() -> Dictionary:
	var target: String = str(get_current_round().get("target", ""))
	if _session == null or target == "":
		return {"available": false, "target": target, "level": 0, "exhausted": false}
	var hint: Dictionary = DeductionEvaluator.request_hint(_case_def, _session, target)
	if hint.get("available", false) and not hint.get("exhausted", false) and _recorder != null:
		_recorder.record("hint_revealed", _recorder.get_current_source(), {"target": target, "level": hint.get("level", 0)})
	return hint


func get_hint_level() -> int:
	var target: String = str(get_current_round().get("target", ""))
	return _session.get_hint_level(target) if _session != null and target != "" else 0


# ---------------------------------------------------------------------------
# Progress and stats

## Any interaction that would be a shame to silently discard — used to decide
## whether leaving/restarting needs a confirmation, and whether abandoning is
## worth recording. Mirrors PrototypeAController.has_progress()'s "read only
## public state" stance, extended with currently-placed (not yet submitted)
## clues, since assembling a connection is real, deliberate work here.
func has_progress() -> bool:
	if _session == null:
		return false
	return _submission_count > 0 or not _selected_evidence_ids.is_empty() \
		or not _session.get_opened_evidence_ids().is_empty() or not _session.get_hint_levels().is_empty()


func get_stats() -> Dictionary:
	return {
		"elapsed_ms": maxi(int(_clock_fn.call()) - _start_ticks, 0),
		"attempts": _submission_count,
		"failed": _failed_attempt_count,
		"opened": _session.get_opened_evidence_ids().size() if _session != null else 0,
		"replacements": _replacement_count,
		"hints_used": _hints_used_total(),
	}


## Reads DeductionSession's own hint-level snapshot rather than tracking a
## second count — see the class doc's "Hints" section.
func _hints_used_total() -> int:
	if _session == null:
		return 0
	var total := 0
	for level in _session.get_hint_levels().values():
		total += int(level)
	return total


## Records "prototype_abandoned" (with the current stats) if there was any
## progress worth noting and the run never completed. Safe to call more than
## once or on a completed/fresh run — both are no-ops.
func abandon() -> void:
	if _completed or _recorder == null or not has_progress():
		return
	_recorder.record("prototype_abandoned", _recorder.get_current_source(), get_stats())
