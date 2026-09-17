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
## Milestone 1.14 (docs/resolution-policy.md): "Present Evidence" is the
## formal commit of a high-stakes confrontation. A ResolutionPolicy (one per
## run, one resolution unit per testimony part/round) turns each genuinely
## evaluated failure into lost credibility; invalid UI actions, re-presenting a
## pair that already failed, an already-resolved statement, the valid optional
## innocent lie and an alternate valid refutation never cost anything. After
## the third failure presenting locks until assistance is acknowledged; after
## two more, only partner resolution (an authored single-evidence refutation,
## still committed through DeductionEvaluator) can finish the part.
##
## Optionally wired to a DeductionLabRecorder (Milestone 1.10, reused
## unmodified) passed into start(). This class decides WHAT and WHEN to
## record for the Prototype A event vocabulary; the recorder itself carries
## no Prototype-A-specific code — see docs/prototype-a.md, "Recorder events".

const RELATION_REFUTES := "refutes"
const OUTCOME_REQUIRED := "required"
const OUTCOME_OPTIONAL := "optional"
const OUTCOME_UNSUCCESSFUL := "unsuccessful"

## Why an action counted nothing (result "reason", alongside category
## invalid_input) — never shown raw; PrototypeAPresenter maps each to text.
const REASON_NOTHING_TO_SUBMIT := "nothing_to_submit"
const REASON_SUBMISSION_LOCKED := "submission_locked"
const REASON_DUPLICATE_ATTEMPT := "duplicate_failed_attempt"
const REASON_PARTNER_UNAVAILABLE := "partner_unavailable"
const REASON_INTERNAL_ERROR := "internal_error"

var _case_def: Dictionary = {}
var _rounds: Array[Dictionary] = []
var _session: DeductionSession = null
var _recorder: DeductionLabRecorder = null
var _policy: ResolutionPolicy = null
var _run_count: int = 0
var _round_index: int = 0
var _statement_index: int = 0
var _selected_evidence_id: String = ""
var _submission_count: int = 0
var _failed_attempt_count: int = 0
var _failed_pairs: Dictionary = {}
var _resolved_optional: Array[String] = []
var _hint_levels: Dictionary = {}
var _viewed_statements: Dictionary = {}
var _assistance_target_id: String = ""
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
## creates a fresh, isolated DeductionSession and ResolutionPolicy — never
## reused across runs and never the session a Deduction Lab session might also
## be holding. A second start() on the same controller is recorded as
## "prototype_restarted" (with the previous run's outcome) before the new
## run's "prototype_started" — a restart is a new run, never a silent reset.
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

	var previous_run: Dictionary = _previous_run_payload(str(case_def.get("id", "")))
	_case_def = case_def
	_rounds = rounds
	_session = DeductionSession.new(str(case_def.get("id", "")))
	_recorder = recorder
	_policy = ResolutionPolicy.new()
	_run_count += 1
	_round_index = 0
	_statement_index = 0
	_selected_evidence_id = ""
	_submission_count = 0
	_failed_attempt_count = 0
	_failed_pairs = {}
	_resolved_optional = []
	_hint_levels = {}
	_viewed_statements = {}
	_assistance_target_id = ""
	_completed = false
	_start_ticks = int(_clock_fn.call())

	if not previous_run.is_empty():
		_record(ResolutionPolicy.EVENT_PROTOTYPE_RESTARTED, previous_run)
	_record("prototype_started", {"case_id": str(case_def.get("id", "")), "run": _run_count})
	_record_round_started()
	return true


func get_case_def() -> Dictionary:
	return _case_def


func get_session() -> DeductionSession:
	return _session


## The run's ResolutionPolicy (null before start()). Read-only use by the
## presenter/tests — every mutation goes through this controller.
func get_policy() -> ResolutionPolicy:
	return _policy


func get_run_count() -> int:
	return _run_count


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
	_record("statement_selected", {"statement_id": statement_id})
	if not _viewed_statements.has(statement_id):
		_record("statement_viewed", {"statement_id": statement_id})
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
	if _session.mark_evidence_opened(evidence_id):
		_record("evidence_opened", {"evidence_id": evidence_id})
	return true


## Chooses `evidence_id` as the ONE item that would be presented next — a
## separate action from opening it (the player may open several before
## deciding which to present). Only ever one selection at a time by
## construction (a single String field, never an array). Free: never a formal
## commit.
func select_evidence(evidence_id: String) -> bool:
	if not get_evidence_pool_ids().has(evidence_id):
		return false
	_selected_evidence_id = evidence_id
	_record("evidence_selected", {"evidence_id": evidence_id})
	return true


func get_selected_evidence_id() -> String:
	return _selected_evidence_id


func clear_selected_evidence() -> void:
	_selected_evidence_id = ""


## True once the current statement + selected evidence pair was already
## presented and failed in this run — re-presenting it is refused without
## costing credibility (the UI never has to rely on the player noticing).
func is_known_failed_pair() -> bool:
	return _failed_pairs.has(_pair_key(get_current_statement_id(), _selected_evidence_id))


func can_present() -> bool:
	return _session != null and not _completed and get_current_statement_id() != "" and _selected_evidence_id != "" \
		and _policy.can_submit()


# ---------------------------------------------------------------------------
# Presenting evidence — the formal commit: current statement + the one
# selected evidence item + relation "refutes", through the real
# DeductionEvaluator.

## Submits the currently selected evidence against the current statement.
## Returns the evaluator's result dict (see DeductionEvaluator.commit_attempt)
## plus "outcome" ("required" | "optional" | "unsuccessful"),
## "already_resolved", "round_ready" (true once every required refutation in
## the CURRENT round is resolved), "counted" (whether this was a formal
## commit at all), "evidence_id", "partner" (false) and "resolution" (the
## ResolutionPolicy snapshot of what this action did — see
## ResolutionPolicy.result_snapshot()).
##
## Counts nothing (category invalid_input, "counted": false, no session
## mutation, no attempt telemetry) for: no statement/evidence selected, a
## completed run, a locked policy (assistance pending or partner resolution
## offered), or a statement+evidence pair that already failed. Resubmitting an
## already-resolved claim classifies (never commits) so session mutations,
## submission counts, credibility and telemetry are never duplicated.
func present_evidence() -> Dictionary:
	var claim_id: String = get_current_statement_id()
	var evidence_id: String = _selected_evidence_id
	if _session == null or _completed or claim_id == "" or evidence_id == "":
		return _uncounted_result(claim_id, evidence_id, REASON_NOTHING_TO_SUBMIT)

	if _session.get_claim_status(claim_id) != "":
		var reclassified: Dictionary = DeductionEvaluator.classify_attempt(_case_def, _session, claim_id, RELATION_REFUTES, [evidence_id])
		reclassified["newly_resolved"] = false
		_selected_evidence_id = ""
		return _decorate(reclassified, claim_id, evidence_id, true, false, {})

	if not _policy.can_submit():
		return _uncounted_result(claim_id, evidence_id, REASON_SUBMISSION_LOCKED)
	var pair_key: String = _pair_key(claim_id, evidence_id)
	if _failed_pairs.has(pair_key):
		return _uncounted_result(claim_id, evidence_id, REASON_DUPLICATE_ATTEMPT)

	_submission_count += 1
	_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_STARTED, {
		"unit": _round_index, "sequence": _submission_count, "statement_id": claim_id, "evidence_id": evidence_id,
		"run_resolution_result": _policy.get_run_resolution_result(),
	})
	var result: Dictionary = DeductionEvaluator.commit_attempt(_case_def, _session, claim_id, RELATION_REFUTES, [evidence_id])
	var category: String = str(result.get("category", ""))
	var outcome: String = _outcome_for(claim_id, category)
	_record("attempt_submitted", {
		"sequence": _submission_count, "round": _round_index, "statement_id": claim_id,
		"evidence_id": evidence_id, "category": category, "outcome": outcome,
	})

	var transition: Dictionary
	if DeductionEvaluator.is_valid_category(category):
		var newly_resolved: bool = result.get("newly_resolved", false) == true
		if newly_resolved and outcome == OUTCOME_OPTIONAL and not _resolved_optional.has(claim_id):
			_resolved_optional.append(claim_id)
		if newly_resolved and outcome != OUTCOME_UNSUCCESSFUL:
			_record("contradiction_resolved", {
				"statement_id": claim_id, "evidence_id": evidence_id, "outcome": outcome,
				"resolved_by": ResolutionPolicy.RESOLVED_BY_PLAYER,
			})
		transition = _policy.register_success(_all_required_resolved_in_current_round())
		_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_SUCCEEDED, {
			"unit": _round_index, "sequence": _submission_count, "outcome": outcome,
			"unit_resolved": _policy.is_unit_resolved(), "resolved_by": ResolutionPolicy.RESOLVED_BY_PLAYER,
			"run_resolution_result": _policy.get_run_resolution_result(),
		})
	else:
		_failed_attempt_count += 1
		_failed_pairs[pair_key] = true
		transition = _policy.register_failed_commit()
		_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_FAILED, {
			"unit": _round_index, "sequence": _submission_count, "category": category,
			"current_unit_failures": _policy.get_current_unit_failures(),
			"credibility_remaining": _policy.get_standard_attempts_remaining(),
			"assisted_attempts_remaining": _policy.get_assisted_attempts_remaining(),
			"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
		})
	_record_transition(transition)

	_selected_evidence_id = ""
	return _decorate(result, claim_id, evidence_id, false, true, transition)


func _all_required_resolved_in_current_round() -> bool:
	if _session == null:
		return false
	for claim_id in DeductionEvaluator.string_array(get_current_round().get("required_refutations", [])):
		if _session.get_claim_status(claim_id) != DeductionSession.STATUS_REFUTED:
			return false
	return true


## Called when the player dismisses post-submission feedback ("Continue").
## Advances to the next round (a fresh resolution unit — full credibility, the
## run's tier kept), or completes the prototype, ONLY if the current round's
## required refutations are now all resolved — otherwise a safe no-op
## (dismissing feedback after a wrong attempt, or after resolving only an
## optional contradiction, never advances anything). Idempotent: calling this
## again after an advance already happened checks the NEW current round's
## requirements, which are not yet met, so it no-ops.
func acknowledge_feedback() -> Dictionary:
	if _completed:
		return {"round_completed": false, "prototype_completed": true}
	if not _all_required_resolved_in_current_round():
		return {"round_completed": false, "prototype_completed": false}

	_record("round_completed", {"round": _round_index, "resolved_by": _policy.get_unit_resolved_by(), "run_resolution_result": _policy.get_run_resolution_result()})
	if _round_index + 1 < _rounds.size():
		_round_index += 1
		_statement_index = 0
		_selected_evidence_id = ""
		_assistance_target_id = ""
		_policy.begin_next_unit()
		_record_round_started()
		return {"round_completed": true, "prototype_completed": false}

	_completed = true
	_record("prototype_completed", _stats_with_resolution())
	return {"round_completed": true, "prototype_completed": true}


func _record_round_started() -> void:
	_record("round_started", {"round": _round_index})


# ---------------------------------------------------------------------------
# Assistance and partner resolution (Milestone 1.14).

## Acknowledges the targeted assistance the policy requires after the third
## failed presentation in this part. Re-enables presenting for the policy's
## assisted budget, and pins the assistance target: the first still-unresolved
## required refutation of the current round. Returns {"accepted": bool,
## "resolution": snapshot}; a no-op when assistance isn't required.
func accept_assistance() -> Dictionary:
	if _session == null or _completed:
		return {"accepted": false, "resolution": {}}
	var transition: Dictionary = _policy.accept_assistance()
	if transition.get("accepted", false) != true:
		return {"accepted": false, "resolution": _policy.result_snapshot({})}
	_assistance_target_id = _first_unresolved_required_id()
	_record(ResolutionPolicy.EVENT_ASSISTANCE_ACCEPTED, {
		"unit": _round_index, "statement_id": _assistance_target_id,
		"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
	})
	_record_transition(transition)
	return {"accepted": true, "resolution": _policy.result_snapshot(transition)}


## The statement assistance points at — "" until this part's assistance has
## actually been acknowledged (the presenter's only source for it).
func get_assistance_target_id() -> String:
	return _assistance_target_id if _policy != null and _policy.is_unit_assistance_accepted() else ""


## Resolves every still-unresolved required refutation of the current round
## with an AUTHORED single-evidence "refutes" proof set from the pool — each
## checked with DeductionEvaluator.classify_attempt() first, then committed
## through DeductionEvaluator.commit_attempt(), never by mutating the session.
## Only available once the policy closed blind submission. Returns the same
## shape as present_evidence() for the first resolved statement, with
## "partner": true and "partner_steps" ([{claim_id, evidence_id}]). An
## unexpected evaluator disagreement returns category invalid_input with
## reason internal_error and marks nothing resolved by the policy.
func resolve_with_partner() -> Dictionary:
	if _session == null or _completed or not _policy.can_use_partner_resolution():
		return _uncounted_result(get_current_statement_id(), "", REASON_PARTNER_UNAVAILABLE)

	var steps: Array[Dictionary] = []
	for claim_id in DeductionEvaluator.string_array(get_current_round().get("required_refutations", [])):
		if _session.get_claim_status(claim_id) != "":
			continue
		var evidence_id: String = _partner_evidence_for(claim_id)
		if evidence_id == "":
			return _uncounted_result(claim_id, "", REASON_INTERNAL_ERROR)
		steps.append({"claim_id": claim_id, "evidence_id": evidence_id})
	if steps.is_empty():
		return _uncounted_result(get_current_statement_id(), "", REASON_INTERNAL_ERROR)

	var first_result: Dictionary = {}
	for step in steps:
		var committed: Dictionary = DeductionEvaluator.commit_attempt(_case_def, _session, step["claim_id"], RELATION_REFUTES, [step["evidence_id"]])
		if not DeductionEvaluator.is_valid_category(str(committed.get("category", ""))):
			return _uncounted_result(step["claim_id"], step["evidence_id"], REASON_INTERNAL_ERROR)
		_record("contradiction_resolved", {
			"statement_id": step["claim_id"], "evidence_id": step["evidence_id"], "outcome": OUTCOME_REQUIRED,
			"resolved_by": ResolutionPolicy.RESOLVED_BY_PARTNER,
		})
		if first_result.is_empty():
			first_result = committed
	if not _all_required_resolved_in_current_round():
		return _uncounted_result(get_current_statement_id(), "", REASON_INTERNAL_ERROR)

	var transition: Dictionary = _policy.register_partner_resolution()
	_record(ResolutionPolicy.EVENT_PARTNER_RESOLUTION_USED, {
		"unit": _round_index, "resolutions": steps.duplicate(true), "resolved_by": ResolutionPolicy.RESOLVED_BY_PARTNER,
		"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
	})
	_record_transition(transition)
	_selected_evidence_id = ""

	var result: Dictionary = _decorate(first_result, steps[0]["claim_id"], steps[0]["evidence_id"], false, false, transition)
	result["partner"] = true
	result["partner_steps"] = steps.duplicate(true)
	return result


## The first authored single-evidence "refutes" proof set for `claim_id` whose
## item is in the evidence pool AND that the real evaluator classifies as a
## valid refutation right now — "" if none (the validator guarantees one for
## every required target).
func _partner_evidence_for(claim_id: String) -> String:
	var pool: Array[String] = get_evidence_pool_ids()
	for proof_set in DeductionEvaluator.dict_array(DeductionEvaluator.find_claim(_case_def, claim_id).get("proof_sets", [])):
		if str(proof_set.get("relation", "")) != RELATION_REFUTES:
			continue
		var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
		if requires.size() != 1 or not pool.has(requires[0]):
			continue
		var classified: Dictionary = DeductionEvaluator.classify_attempt(_case_def, _session, claim_id, RELATION_REFUTES, requires)
		if DeductionEvaluator.is_valid_category(str(classified.get("category", ""))):
			return requires[0]
	return ""


func _first_unresolved_required_id() -> String:
	for claim_id in DeductionEvaluator.string_array(get_current_round().get("required_refutations", [])):
		if _session != null and _session.get_claim_status(claim_id) == "":
			return claim_id
	return ""


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
## {"available": false, ...} when this claim has no ladder at all. A newly
## revealed level is registered with the ResolutionPolicy (levels 1-2 make the
## run at least Guided, 3-4 Assisted) and its snapshot returned under
## "resolution", so the UI can say so explicitly.
func reveal_next_hint(claim_id: String) -> Dictionary:
	var ladder: Array[String] = get_hint_ladder(claim_id)
	if ladder.is_empty() or _policy == null:
		return {"available": false, "level": 0, "text_key": "", "exhausted": false, "resolution": {}}
	var current: int = get_hint_level(claim_id)
	var is_exhausted: bool = current >= ladder.size()
	var next_level: int = mini(current + 1, ladder.size())
	var transition: Dictionary = {}
	if not is_exhausted:
		_hint_levels[claim_id] = next_level
		_record("hint_revealed", {"statement_id": claim_id, "level": next_level})
		transition = _policy.register_hint(next_level)
		_record_transition(transition)
	return {
		"available": true, "level": next_level, "text_key": ladder[next_level - 1], "exhausted": is_exhausted,
		"resolution": _policy.result_snapshot(transition),
	}


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
	return _submission_count > 0 or not _session.get_opened_evidence_ids().is_empty() or not _hint_levels.is_empty() \
		or _policy.get_partner_resolution_count() > 0


## Numeric-only statistics (never text that could leak content).
## "submissions"/"incorrect" are this run's formal commits / failed formal
## commits; the resolution tier itself is reported separately (see
## get_policy() and the "resolution" block of prototype_completed).
func get_stats() -> Dictionary:
	return {
		"elapsed_ms": maxi(int(_clock_fn.call()) - _start_ticks, 0),
		"submissions": _submission_count,
		"incorrect": _failed_attempt_count,
		"optional_found": _resolved_optional.size(),
		"hints_used": _hints_used_total(),
		"assistance_used": _policy.get_assistance_count() if _policy != null else 0,
		"partner_resolutions": _policy.get_partner_resolution_count() if _policy != null else 0,
	}


func get_resolved_optional_ids() -> Array[String]:
	return _resolved_optional.duplicate()


## Records "prototype_abandoned" (with the current stats) if there was any
## progress worth noting and the run never completed. Safe to call more than
## once or on a completed/fresh run — both are no-ops.
func abandon() -> void:
	if _completed or _recorder == null or not has_progress():
		return
	_record("prototype_abandoned", _stats_with_resolution())


# ---------------------------------------------------------------------------
# Private

func _record(event_type: String, payload: Dictionary) -> void:
	if _recorder != null:
		_recorder.record(event_type, _recorder.get_current_source(), payload)


func _record_transition(transition: Dictionary) -> void:
	for event in ResolutionPolicy.transition_events(transition):
		var payload: Dictionary = (event["payload"] as Dictionary).duplicate()
		payload["unit"] = _round_index
		_record(str(event["type"]), payload)


func _stats_with_resolution() -> Dictionary:
	var payload: Dictionary = get_stats()
	payload["resolution"] = _policy.get_summary() if _policy != null else {}
	return payload


## {} for the very first start(); otherwise the outgoing run's outcome, used as
## the "prototype_restarted" payload.
func _previous_run_payload(next_case_id: String) -> Dictionary:
	if _session == null or _policy == null:
		return {}
	return {
		"case_id": next_case_id, "previous_case_id": str(_case_def.get("id", "")), "previous_run": _run_count,
		"previous_completed": _completed, "previous_run_resolution_result": _policy.get_run_resolution_result(),
		"previous_formal_commits": _policy.get_formal_commit_count(), "previous_failed_commits": _policy.get_failed_commit_count(),
	}


func _outcome_for(claim_id: String, category: String) -> String:
	if not DeductionEvaluator.is_valid_category(category):
		return OUTCOME_UNSUCCESSFUL
	var pa_round: Dictionary = get_current_round()
	if DeductionEvaluator.string_array(pa_round.get("required_refutations", [])).has(claim_id):
		return OUTCOME_REQUIRED
	if DeductionEvaluator.string_array(pa_round.get("optional_refutations", [])).has(claim_id):
		return OUTCOME_OPTIONAL
	return OUTCOME_UNSUCCESSFUL


func _pair_key(claim_id: String, evidence_id: String) -> String:
	return "%s|%s" % [claim_id, evidence_id]


func _decorate(result: Dictionary, claim_id: String, evidence_id: String, already_resolved: bool, counted: bool, transition: Dictionary) -> Dictionary:
	result["claim_id"] = claim_id
	result["outcome"] = _outcome_for(claim_id, str(result.get("category", "")))
	result["already_resolved"] = already_resolved
	result["round_ready"] = _all_required_resolved_in_current_round()
	result["counted"] = counted
	result["evidence_id"] = evidence_id
	result["partner"] = false
	result["resolution"] = _policy.result_snapshot(transition) if _policy != null else {}
	return result


func _uncounted_result(claim_id: String, evidence_id: String, reason: String) -> Dictionary:
	return {
		"category": DeductionEvaluator.INVALID_INPUT, "reason": reason, "claim_id": claim_id,
		"relation": RELATION_REFUTES, "newly_resolved": false, "already_resolved": false,
		"outcome": OUTCOME_UNSUCCESSFUL, "round_ready": _all_required_resolved_in_current_round(),
		"counted": false, "evidence_id": evidence_id, "partner": false,
		"resolution": _policy.result_snapshot({}) if _policy != null else {},
	}
