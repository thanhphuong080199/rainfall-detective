class_name PrototypeAController
extends RefCounted
## Interaction-state host for the debug-only Prototype A — Statement
## Contradiction prototype (Milestone 1.11 — see docs/prototype-a.md). Owns
## exactly ONE fresh, isolated DeductionSession per run (never the Deduction
## Lab's own session) plus Prototype-A-specific interaction state: current
## round, current statement, selected evidence, submission/failure counts,
## resolved optional contradictions, hint levels, and prototype completion.
##
## Every submitted contradiction is classified/committed through the REAL
## DeductionEvaluator/DeductionSession path (relation "refutes", exactly one
## evidence item) — this class adds zero grading logic of its own. Pure and
## autoload-free, like DeductionLabController: the caller
## (scripts/debug/prototype_a.gd) fetches case_def via ContentDB and hands it
## in, never resolves a case id itself.
##
## Hints are Prototype-A-owned data (case_def.prototype_a.rounds[].
## hint_ladders), not DeductionSession's hint-level tracking — those methods
## are documented "called by DeductionEvaluator only" and the base contract's
## hint ladders can only target a deduction/conclusion, never a statement.
## Hint progress is tracked here instead, in _hint_levels, which is why this
## controller never calls DeductionSession.advance_hint()/request_hint() —
## doing so would be exactly the "direct mutation of DeductionSession" this
## milestone forbids.
##
## Optionally wired to a DeductionLabRecorder (Milestone 1.10, reused
## unmodified) passed into start(). This class decides WHAT and WHEN to
## record for the Prototype A event vocabulary; the recorder itself carries
## no Prototype-A-specific code — see docs/prototype-a.md, "Recorder events".

const RELATION_REFUTES := "refutes"
const OUTCOME_REQUIRED := "required"
const OUTCOME_OPTIONAL := "optional"
const OUTCOME_UNSUCCESSFUL := "unsuccessful"

var _case_def: Dictionary = {}
var _rounds: Array[Dictionary] = []
var _session: DeductionSession = null
var _recorder: DeductionLabRecorder = null
var _round_index: int = 0
var _statement_index: int = 0
var _selected_evidence_id: String = ""
var _submission_count: int = 0
var _failed_attempt_count: int = 0
var _resolved_optional: Array[String] = []
var _hint_levels: Dictionary = {}
var _viewed_statements: Dictionary = {}
var _completed: bool = false
var _clock_fn: Callable
var _start_ticks: int = 0


## `clock_fn` (no args, returns int/float monotonic milliseconds — defaults
## to Time.get_ticks_msec) is injectable for deterministic tests, matching
## DeductionLabRecorder's own convention.
func _init(clock_fn: Callable = Callable()) -> void:
	_clock_fn = clock_fn if clock_fn.is_valid() else Callable(Time, "get_ticks_msec")


# ---------------------------------------------------------------------------
# Lifecycle

## Starts a brand-new run of `case_def` (which must declare a non-empty
## "prototype_a" data layer — see DeductionValidator._validate_prototype_a).
## Calling this again (Restart) discards all previous interaction state and
## creates a fresh, isolated DeductionSession — never reused across runs and
## never the session a Deduction Lab session might also be holding.
## `recorder`, if given, receives this run's telemetry (see docs/
## prototype-a.md, "Recorder events"); pass null to run unrecorded.
func start(case_def: Dictionary, recorder: DeductionLabRecorder = null) -> bool:
	if typeof(case_def) != TYPE_DICTIONARY:
		return false
	var proto: Variant = case_def.get("prototype_a")
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
	_statement_index = 0
	_selected_evidence_id = ""
	_submission_count = 0
	_failed_attempt_count = 0
	_resolved_optional = []
	_hint_levels = {}
	_viewed_statements = {}
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
# Rounds and statements

func get_round_index() -> int:
	return _round_index


func get_round_count() -> int:
	return _rounds.size()


func get_current_round() -> Dictionary:
	return _rounds[_round_index] if _round_index >= 0 and _round_index < _rounds.size() else {}


func get_statement_ids() -> Array[String]:
	return DeductionEvaluator.string_array(get_current_round().get("statements", []))


func get_statement_index() -> int:
	return _statement_index


func get_current_statement_id() -> String:
	var ids: Array[String] = get_statement_ids()
	return ids[_statement_index] if _statement_index >= 0 and _statement_index < ids.size() else ""


## Moves to `index` within the current round's statement list, recording
## "statement_selected" every time and "statement_viewed" the first time this
## particular statement is reached in this run. Returns false (no state
## change, nothing recorded) for an out-of-range index.
func select_statement(index: int) -> bool:
	var ids: Array[String] = get_statement_ids()
	if index < 0 or index >= ids.size():
		return false
	_statement_index = index
	var statement_id: String = ids[index]
	if _recorder != null:
		_recorder.record("statement_selected", _recorder.get_current_source(), {"statement_id": statement_id})
		if not _viewed_statements.has(statement_id):
			_recorder.record("statement_viewed", _recorder.get_current_source(), {"statement_id": statement_id})
	_viewed_statements[statement_id] = true
	return true


func next_statement() -> bool:
	return select_statement(_statement_index + 1)


func previous_statement() -> bool:
	return select_statement(_statement_index - 1)


# ---------------------------------------------------------------------------
# Evidence — open (read) vs select (choose to present) are distinct actions.

func get_evidence_pool_ids() -> Array[String]:
	return DeductionEvaluator.string_array(_case_def.get("prototype_a", {}).get("evidence_pool", []))


## Marks `evidence_id` opened in the session (the sanctioned public
## DeductionSession API for this, also used by the Deduction Lab) — never a
## private mutation. Records "evidence_opened" only the first time (mirrors
## DeductionSession.mark_evidence_opened()'s own "first time only" contract).
func open_evidence(evidence_id: String) -> bool:
	if _session == null or not get_evidence_pool_ids().has(evidence_id):
		return false
	var first_time: bool = _session.mark_evidence_opened(evidence_id)
	if first_time and _recorder != null:
		_recorder.record("evidence_opened", _recorder.get_current_source(), {"evidence_id": evidence_id})
	return true


## Chooses `evidence_id` as the ONE item that would be presented next — a
## separate action from opening it (the player may open several before
## deciding which to present). Only ever one selection at a time by
## construction (a single String field, never an array).
func select_evidence(evidence_id: String) -> bool:
	if not get_evidence_pool_ids().has(evidence_id):
		return false
	_selected_evidence_id = evidence_id
	if _recorder != null:
		_recorder.record("evidence_selected", _recorder.get_current_source(), {"evidence_id": evidence_id})
	return true


func get_selected_evidence_id() -> String:
	return _selected_evidence_id


func clear_selected_evidence() -> void:
	_selected_evidence_id = ""


# ---------------------------------------------------------------------------
# Presenting evidence — the one proof interaction: current statement + the
# one selected evidence item + relation "refutes", through the real
# DeductionEvaluator.

## Submits the currently selected evidence against the current statement.
## Returns the evaluator's result dict (see DeductionEvaluator.commit_attempt)
## plus "outcome" ("required" | "optional" | "unsuccessful"), "already_resolved"
## and "round_ready" (true once every required refutation in the CURRENT round
## is resolved — the UI should offer "Continue" to advance once this is true).
## Resubmitting an already-resolved claim classifies (never commits) so
## session mutations, submission counts and telemetry are never duplicated.
func present_evidence() -> Dictionary:
	var claim_id: String = get_current_statement_id()
	var evidence_id: String = _selected_evidence_id
	if _session == null or _completed or claim_id == "" or evidence_id == "":
		return {
			"category": DeductionEvaluator.INVALID_INPUT, "reason": "nothing_to_submit", "claim_id": claim_id,
			"relation": RELATION_REFUTES, "newly_resolved": false, "already_resolved": false,
			"outcome": OUTCOME_UNSUCCESSFUL, "round_ready": _all_required_resolved_in_current_round(),
		}

	var already_resolved: bool = _session.get_claim_status(claim_id) != ""
	var result: Dictionary
	if already_resolved:
		result = DeductionEvaluator.classify_attempt(_case_def, _session, claim_id, RELATION_REFUTES, [evidence_id])
		result["newly_resolved"] = false
	else:
		_submission_count += 1
		result = DeductionEvaluator.commit_attempt(_case_def, _session, claim_id, RELATION_REFUTES, [evidence_id])
		if not DeductionEvaluator.is_valid_category(str(result.get("category", ""))):
			_failed_attempt_count += 1

	var category: String = str(result.get("category", ""))
	var pa_round: Dictionary = get_current_round()
	var required: Array[String] = DeductionEvaluator.string_array(pa_round.get("required_refutations", []))
	var optional: Array[String] = DeductionEvaluator.string_array(pa_round.get("optional_refutations", []))
	var outcome: String = OUTCOME_UNSUCCESSFUL
	if DeductionEvaluator.is_valid_category(category):
		if required.has(claim_id):
			outcome = OUTCOME_REQUIRED
		elif optional.has(claim_id):
			outcome = OUTCOME_OPTIONAL

	if not already_resolved and _recorder != null:
		_recorder.record("attempt_submitted", _recorder.get_current_source(), {
			"sequence": _submission_count, "round": _round_index, "statement_id": claim_id,
			"evidence_id": evidence_id, "category": category, "outcome": outcome,
		})

	var newly_resolved: bool = result.get("newly_resolved", false) == true
	if newly_resolved and outcome == OUTCOME_OPTIONAL and not _resolved_optional.has(claim_id):
		_resolved_optional.append(claim_id)
	if newly_resolved and outcome != OUTCOME_UNSUCCESSFUL and _recorder != null:
		_recorder.record("contradiction_resolved", _recorder.get_current_source(), {
			"statement_id": claim_id, "evidence_id": evidence_id, "outcome": outcome,
		})

	_selected_evidence_id = ""
	result["outcome"] = outcome
	result["already_resolved"] = already_resolved
	result["round_ready"] = _all_required_resolved_in_current_round()
	return result


func _all_required_resolved_in_current_round() -> bool:
	if _session == null:
		return false
	for claim_id in DeductionEvaluator.string_array(get_current_round().get("required_refutations", [])):
		if _session.get_claim_status(claim_id) != DeductionSession.STATUS_REFUTED:
			return false
	return true


## Called when the player dismisses post-submission feedback ("Continue").
## Advances to the next round, or completes the prototype, ONLY if the
## current round's required refutations are now all resolved — otherwise a
## safe no-op (dismissing feedback after a wrong attempt, or after resolving
## only an optional contradiction, never advances anything). Idempotent:
## calling this again after an advance already happened checks the NEW
## current round's requirements, which are not yet met, so it no-ops.
func acknowledge_feedback() -> Dictionary:
	if _completed:
		return {"round_completed": false, "prototype_completed": true}
	if not _all_required_resolved_in_current_round():
		return {"round_completed": false, "prototype_completed": false}

	if _recorder != null:
		_recorder.record("round_completed", _recorder.get_current_source(), {"round": _round_index})
	if _round_index + 1 < _rounds.size():
		_round_index += 1
		_statement_index = 0
		if _recorder != null:
			_record_round_started()
		return {"round_completed": true, "prototype_completed": false}

	_completed = true
	if _recorder != null:
		_recorder.record("prototype_completed", _recorder.get_current_source(), get_stats())
	return {"round_completed": true, "prototype_completed": true}


func _record_round_started() -> void:
	_recorder.record("round_started", _recorder.get_current_source(), {"round": _round_index})


# ---------------------------------------------------------------------------
# Hints — Prototype-A-owned data and progress; see class doc above for why
# this never touches DeductionSession's hint machinery.

## The current statement's hint ladder (an array of up to 4 translation
## keys), or an empty array if this statement has none (true/incomplete
## statements and optional lies never get a ladder in the authored content —
## only required refutations do).
func get_hint_ladder(claim_id: String) -> Array[String]:
	return DeductionEvaluator.string_array(get_current_round().get("hint_ladders", {}).get(claim_id, []))


func get_hint_level(claim_id: String) -> int:
	return int(_hint_levels.get(claim_id, 0))


## Reveals the next hint level for `claim_id`, or repeats the last one
## ("exhausted": true) once the ladder is used up. Returns
## {"available": false, ...} when this claim has no ladder at all.
func reveal_next_hint(claim_id: String) -> Dictionary:
	var ladder: Array[String] = get_hint_ladder(claim_id)
	if ladder.is_empty():
		return {"available": false, "level": 0, "text_key": "", "exhausted": false}
	var current: int = get_hint_level(claim_id)
	var is_exhausted: bool = current >= ladder.size()
	var next_level: int = mini(current + 1, ladder.size())
	if not is_exhausted:
		_hint_levels[claim_id] = next_level
		if _recorder != null:
			_recorder.record("hint_revealed", _recorder.get_current_source(), {"statement_id": claim_id, "level": next_level})
	return {"available": true, "level": next_level, "text_key": ladder[next_level - 1], "exhausted": is_exhausted}


func _hints_used_total() -> int:
	var total := 0
	for level in _hint_levels.values():
		total += int(level)
	return total


# ---------------------------------------------------------------------------
# Progress and stats

## Any interaction that would be a shame to silently discard — used to decide
## whether leaving/restarting needs a confirmation, and whether abandoning is
## worth recording. Mirrors DeductionLabController.session_has_progress()'s
## "read only public state" stance, extended with Prototype-A's own state.
func has_progress() -> bool:
	if _session == null:
		return false
	return _submission_count > 0 or not _session.get_opened_evidence_ids().is_empty() or not _hint_levels.is_empty()


func get_stats() -> Dictionary:
	return {
		"elapsed_ms": maxi(int(_clock_fn.call()) - _start_ticks, 0),
		"submissions": _submission_count,
		"incorrect": _failed_attempt_count,
		"optional_found": _resolved_optional.size(),
		"hints_used": _hints_used_total(),
	}


func get_resolved_optional_ids() -> Array[String]:
	return _resolved_optional.duplicate()


## Records "prototype_abandoned" (with the current stats) if there was any
## progress worth noting and the run never completed. Safe to call more than
## once or on a completed/fresh run — both are no-ops.
func abandon() -> void:
	if _completed or _recorder == null or not has_progress():
		return
	_recorder.record("prototype_abandoned", _recorder.get_current_source(), get_stats())
