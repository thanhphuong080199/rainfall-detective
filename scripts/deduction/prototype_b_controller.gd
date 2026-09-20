class_name PrototypeBController
extends RefCounted
## Interaction-state host for the debug-only Prototype B — Clue Connection
## prototype (Milestone 1.12 — see docs/prototype-b.md). Owns exactly ONE
## fresh, isolated DeductionSession per run (never the Deduction Lab's own
## session, never a PrototypeAController's) plus Prototype-B-specific
## interaction state: one unverified DRAFT per investigation question (the
## clues currently placed in that question's slots), which draft is active,
## formal-commit/failure/replacement/save counts, and completion.
##
## Milestone 1.14 (docs/resolution-policy.md) — draft and batch commitment.
## Prototype B is the frequent core mechanic, so it gets the strongest
## protection against using the evaluator as an oracle:
##   * editing, saving and switching drafts is FREE and never calls the
##     evaluator — a draft is always "unverified";
##   * "Commit Theory" is the ONE formal commit. It needs every draft
##     complete, classifies every draft side-effect-free with
##     DeductionEvaluator.classify_attempt(), and only if ALL are valid commits
##     each through DeductionEvaluator.commit_attempt(). One invalid draft
##     commits NOTHING, unlocks nothing, preserves every draft and counts one
##     failed formal commit;
##   * feedback never says which draft or clue failed on the first failure; a
##     second failure may name ONE affected question; the third requires
##     assistance (the base hint ladder's category level for that question);
##     after two more, partner resolution commits authored proof sets for the
##     still-invalid drafts — always through the real evaluator.
## Committing exactly the same failed theory again is refused without cost.
##
## Grading is never reimplemented here: every correctness decision comes from
## DeductionEvaluator. Pure and autoload-free, like PrototypeAController/
## DeductionLabController: the caller (scripts/debug/prototype_b.gd) fetches
## case_def via ContentDB and hands it in, never resolves a case id itself.
##
## Hints are NOT Prototype-B-owned data, unlike Prototype A: every question
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

## commit_theory() result categories (never shown raw — PrototypeBPresenter
## maps them). An uncounted action uses DeductionEvaluator.INVALID_INPUT.
const RESULT_THEORY_ACCEPTED := "theory_accepted"
const RESULT_THEORY_REJECTED := "theory_rejected"

const FEEDBACK_COARSE := "coarse"
const FEEDBACK_GUIDED := "guided"

const REASON_NO_RUN := "no_run"
const REASON_ALREADY_ACCEPTED := "already_accepted"
const REASON_INCOMPLETE_DRAFTS := "incomplete_drafts"
const REASON_SUBMISSION_LOCKED := "submission_locked"
const REASON_DUPLICATE_THEORY := "duplicate_failed_theory"
const REASON_PARTNER_UNAVAILABLE := "partner_unavailable"
const REASON_INTERNAL_ERROR := "internal_error"

var _case_def: Dictionary = {}
var _rounds: Array[Dictionary] = []
var _session: DeductionSession = null
var _recorder: DeductionLabRecorder = null
var _policy: ResolutionPolicy = null
var _run_count: int = 0
## One Array[String] of placed evidence ids per question, in authored order.
var _drafts: Array = []
## Draft index -> the normalized (sorted) selection last saved.
var _saved_drafts: Dictionary = {}
var _active_index: int = 0
var _submission_count: int = 0
var _failed_attempt_count: int = 0
var _replacement_count: int = 0
var _drafts_saved_count: int = 0
var _failed_theory_keys: Dictionary = {}
var _last_invalid_indices: Array[int] = []
var _assistance_draft_index: int = -1
var _partner_draft_indices: Array[int] = []
var _theory_accepted: bool = false
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
## Calling this again (Restart) discards every draft and creates a fresh,
## isolated DeductionSession and ResolutionPolicy — recorded as
## "prototype_restarted" before the new run's "prototype_started".
## `recorder`, if given, receives this run's telemetry; pass null to run
## unrecorded.
func start(case_def: Dictionary, recorder: DeductionLabRecorder = null) -> bool:
	if typeof(case_def) != TYPE_DICTIONARY:
		return false
	var proto: Variant = case_def.get("prototype_b")
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
	_drafts = []
	for _i in _rounds.size():
		var empty: Array[String] = []
		_drafts.append(empty)
	_saved_drafts = {}
	_active_index = 0
	_submission_count = 0
	_failed_attempt_count = 0
	_replacement_count = 0
	_drafts_saved_count = 0
	_failed_theory_keys = {}
	_last_invalid_indices = []
	_assistance_draft_index = -1
	_partner_draft_indices = []
	_theory_accepted = false
	_completed = false
	_start_ticks = int(_clock_fn.call())

	if not previous_run.is_empty():
		_record(ResolutionPolicy.EVENT_PROTOTYPE_RESTARTED, previous_run)
	_record("prototype_started", {"case_id": str(case_def.get("id", "")), "run": _run_count, "draft_count": _rounds.size()})
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


## True once a committed theory (player or partner) resolved every question.
func is_theory_accepted() -> bool:
	return _theory_accepted


# ---------------------------------------------------------------------------
# Drafts — one per investigation question, always available as tabs.

func get_draft_count() -> int:
	return _rounds.size()


func get_active_draft_index() -> int:
	return _active_index


## Switches the active draft tab. Free: never touches the evaluator and never
## changes any draft's content. Records "draft_selected" only on a real change.
func select_draft(index: int) -> bool:
	if index < 0 or index >= _rounds.size():
		return false
	if index != _active_index:
		_active_index = index
		_record("draft_selected", {"draft": index})
	return true


func get_draft_round(index: int) -> Dictionary:
	return _rounds[index] if index >= 0 and index < _rounds.size() else {}


func get_active_round() -> Dictionary:
	return get_draft_round(_active_index)


func get_slot_count(index: int = -1) -> int:
	return int(get_draft_round(_resolve_index(index)).get("slot_count", 0))


func get_selected_evidence_ids(index: int = -1) -> Array[String]:
	var resolved: int = _resolve_index(index)
	if resolved < 0 or resolved >= _drafts.size():
		return []
	return (_drafts[resolved] as Array[String]).duplicate()


## Whether `evidence_id` is placed in the ACTIVE draft.
func is_selected(evidence_id: String) -> bool:
	return get_selected_evidence_ids().has(evidence_id)


func is_draft_complete(index: int = -1) -> bool:
	var resolved: int = _resolve_index(index)
	return get_slot_count(resolved) > 0 and get_selected_evidence_ids(resolved).size() == get_slot_count(resolved)


func are_all_drafts_complete() -> bool:
	for i in _rounds.size():
		if not is_draft_complete(i):
			return false
	return not _rounds.is_empty()


## True while at least one slot of the ACTIVE draft is still empty — the UI
## uses this to disable "Place" once the draft is full.
func has_room() -> bool:
	return get_selected_evidence_ids().size() < get_slot_count()


## Whether the draft's current selection equals its last explicit save.
func is_draft_saved(index: int = -1) -> bool:
	var resolved: int = _resolve_index(index)
	return _saved_drafts.has(resolved) and _saved_drafts[resolved] == _normalized(resolved)


func _can_edit() -> bool:
	return _session != null and not _theory_accepted and not _completed


# ---------------------------------------------------------------------------
# Evidence pool — open (read) vs place (into the active draft) are distinct
# actions, mirroring PrototypeAController's own evidence handling.

func get_evidence_pool_ids() -> Array[String]:
	return DeductionEvaluator.string_array(_case_def.get("prototype_b", {}).get("evidence_pool", []))


## Marks `evidence_id` opened in the session (the sanctioned public
## DeductionSession API for this) — never a private mutation. Records
## "evidence_opened" only the first time.
func open_evidence(evidence_id: String) -> bool:
	if _session == null or not get_evidence_pool_ids().has(evidence_id):
		return false
	if _session.mark_evidence_opened(evidence_id):
		_record("evidence_opened", {"evidence_id": evidence_id})
	return true


## Places `evidence_id` into the active draft's next empty slot. Rejects (no
## state change, nothing recorded) a duplicate within that draft, an id
## outside the pool, a full draft, or any edit once the theory is accepted —
## "the controller rejects over-capacity selection before evaluator
## submission" (docs/prototype-b.md, "Anti-brute-force"). Never evaluates.
func select_evidence(evidence_id: String) -> bool:
	if not _can_edit() or not get_evidence_pool_ids().has(evidence_id) or is_selected(evidence_id):
		return false
	if not has_room():
		return false
	(_drafts[_active_index] as Array[String]).append(evidence_id)
	_record("clue_selected", {"evidence_id": evidence_id, "draft": _active_index})
	return true


## Removes `evidence_id` from the active draft, leaving every other placed
## clue (in this and every other draft) untouched.
func remove_evidence(evidence_id: String) -> bool:
	if not _can_edit() or not is_selected(evidence_id):
		return false
	(_drafts[_active_index] as Array[String]).erase(evidence_id)
	_record("clue_removed", {"evidence_id": evidence_id, "draft": _active_index})
	return true


## Swaps `old_evidence_id` for `new_evidence_id` IN THE SAME slot position of
## the active draft, recording both halves.
func replace_evidence(old_evidence_id: String, new_evidence_id: String) -> bool:
	if not _can_edit():
		return false
	var draft: Array[String] = _drafts[_active_index]
	var index: int = draft.find(old_evidence_id)
	if index < 0 or not get_evidence_pool_ids().has(new_evidence_id) or draft.has(new_evidence_id):
		return false
	draft[index] = new_evidence_id
	_replacement_count += 1
	_record("clue_removed", {"evidence_id": old_evidence_id, "draft": _active_index})
	_record("clue_selected", {"evidence_id": new_evidence_id, "draft": _active_index})
	return true


## Explicitly saves the active draft as an "Unverified Draft". Never calls the
## evaluator, never reveals correctness, never unlocks anything and never
## consumes an attempt — it only records "draft_saved" for analysis.
func save_draft() -> bool:
	if not _can_edit():
		return false
	var normalized: Array[String] = _normalized(_active_index)
	_saved_drafts[_active_index] = normalized
	_drafts_saved_count += 1
	_record("draft_saved", {
		"draft": _active_index, "evidence_ids": normalized, "filled": normalized.size(),
		"slot_count": get_slot_count(), "complete": is_draft_complete(),
	})
	return true


# ---------------------------------------------------------------------------
# Commit Theory — the one formal commit.

## True when the current set of drafts matches a theory that already failed —
## committing it again is refused without cost until something changes.
func is_known_failed_theory() -> bool:
	return _failed_theory_keys.has(_theory_key())


func can_commit_theory() -> bool:
	return _can_edit() and are_all_drafts_complete() and _policy.can_submit() and not is_known_failed_theory()


## Commits the whole theory atomically. Returns {"category": theory_accepted |
## theory_rejected | invalid_input, "reason", "accepted", "counted", "partner",
## "resolution" (ResolutionPolicy snapshot)} plus, for a rejection,
## "feedback_level" ("coarse" on the unit's first failure, "guided" after) and
## — ONLY when guided — "affected_draft_index": the first invalid draft in
## authored order. Nothing identifying a failing draft or clue is present on a
## coarse rejection. An accepted theory adds "resolved_targets".
##
## Counts nothing (invalid_input, no evaluator call, no telemetry) for: no
## run, an already-accepted theory, an incomplete draft, a locked policy, or a
## theory identical to one that already failed.
func commit_theory() -> Dictionary:
	if _session == null:
		return _uncounted_result(REASON_NO_RUN)
	if _theory_accepted or _completed:
		return _uncounted_result(REASON_ALREADY_ACCEPTED)
	if not are_all_drafts_complete():
		return _uncounted_result(REASON_INCOMPLETE_DRAFTS)
	if not _policy.can_submit():
		return _uncounted_result(REASON_SUBMISSION_LOCKED)
	var theory_key: String = _theory_key()
	if _failed_theory_keys.has(theory_key):
		# Milestone 1.14.2A: observational only — see PrototypeAController's
		# identical attempt_blocked_duplicate comment.
		_record("theory_blocked_duplicate", {"drafts": _draft_payloads()})
		return _uncounted_result(REASON_DUPLICATE_THEORY)

	_submission_count += 1
	_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_STARTED, {"unit": _policy.get_unit_index(), "sequence": _submission_count, "run_resolution_result": _policy.get_run_resolution_result()})
	_record("theory_batch_submitted", {"sequence": _submission_count, "drafts": _draft_payloads()})

	var categories: Array[String] = []
	var invalid: Array[int] = []
	for i in _rounds.size():
		var round_def: Dictionary = _rounds[i]
		var classified: Dictionary = DeductionEvaluator.classify_attempt(_case_def, _session, str(round_def.get("target", "")), str(round_def.get("relation", "")), get_selected_evidence_ids(i))
		var category: String = str(classified.get("category", ""))
		categories.append(category)
		if not DeductionEvaluator.is_valid_category(category):
			invalid.append(i)

	if not invalid.is_empty():
		_failed_attempt_count += 1
		_failed_theory_keys[theory_key] = true
		_last_invalid_indices = invalid
		var transition: Dictionary = _policy.register_failed_commit()
		_record("theory_batch_rejected", {"sequence": _submission_count, "draft_categories": categories, "invalid_drafts": invalid.duplicate()})
		_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_FAILED, {
			"unit": _policy.get_unit_index(), "sequence": _submission_count, "current_unit_failures": _policy.get_current_unit_failures(),
			"standard_attempts_remaining": _policy.get_standard_attempts_remaining(),
			"assisted_attempts_remaining": _policy.get_assisted_attempts_remaining(),
			"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
		})
		_record_transition(transition)
		var rejected: Dictionary = _result(RESULT_THEORY_REJECTED, "", false, true, transition)
		if _policy.get_current_unit_failures() <= 1:
			rejected["feedback_level"] = FEEDBACK_COARSE
		else:
			rejected["feedback_level"] = FEEDBACK_GUIDED
			rejected["affected_draft_index"] = invalid[0]
		return rejected

	if not _commit_every_draft(ResolutionPolicy.RESOLVED_BY_PLAYER):
		return _uncounted_result(REASON_INTERNAL_ERROR)
	var accepted_transition: Dictionary = _policy.register_success()
	_record("theory_batch_accepted", {"sequence": _submission_count, "resolved_by": ResolutionPolicy.RESOLVED_BY_PLAYER})
	_record(ResolutionPolicy.EVENT_FORMAL_COMMIT_SUCCEEDED, {
		"unit": _policy.get_unit_index(), "sequence": _submission_count,
		"resolved_by": ResolutionPolicy.RESOLVED_BY_PLAYER, "run_resolution_result": _policy.get_run_resolution_result(),
	})
	_record_transition(accepted_transition)
	var accepted: Dictionary = _result(RESULT_THEORY_ACCEPTED, "", true, true, accepted_transition)
	accepted["resolved_targets"] = _targets()
	return accepted


## Commits every draft through DeductionEvaluator.commit_attempt() after the
## caller already classified all of them valid. Returns false — and marks
## nothing accepted — on an unexpected evaluator disagreement.
func _commit_every_draft(resolved_by: String) -> bool:
	for i in _rounds.size():
		var round_def: Dictionary = _rounds[i]
		var target: String = str(round_def.get("target", ""))
		var committed: Dictionary = DeductionEvaluator.commit_attempt(_case_def, _session, target, str(round_def.get("relation", "")), get_selected_evidence_ids(i))
		if not DeductionEvaluator.is_valid_category(str(committed.get("category", ""))):
			return false
		if committed.get("newly_resolved", false) == true:
			_record("deduction_unlocked", {"target": target, "draft": i, "resolved_by": resolved_by})
	for i in _rounds.size():
		if not _session.is_supported(str(_rounds[i].get("target", ""))):
			return false
	_theory_accepted = true
	return true


## Called when the player dismisses the accepted-theory feedback
## ("Continue"). Completes the prototype only once the theory is accepted —
## otherwise a safe no-op. Idempotent.
func acknowledge_result() -> Dictionary:
	if _completed:
		return {"prototype_completed": true}
	if not _theory_accepted:
		return {"prototype_completed": false}
	_completed = true
	_record("prototype_completed", _stats_with_resolution())
	return {"prototype_completed": true}


# ---------------------------------------------------------------------------
# Assistance and partner resolution (Milestone 1.14).

## Acknowledges the assistance the policy requires after the third failed
## theory. Pins the assistance to the first invalid draft of the latest failed
## theory and switches to that tab — it never inserts a clue.
func accept_assistance() -> Dictionary:
	if _session == null or _completed:
		return {"accepted": false, "resolution": {}}
	var transition: Dictionary = _policy.accept_assistance()
	if transition.get("accepted", false) != true:
		return {"accepted": false, "resolution": _policy.result_snapshot({})}
	_assistance_draft_index = _last_invalid_indices[0] if not _last_invalid_indices.is_empty() else 0
	select_draft(_assistance_draft_index)
	_record(ResolutionPolicy.EVENT_ASSISTANCE_ACCEPTED, {
		"unit": _policy.get_unit_index(), "draft": _assistance_draft_index,
		"target": str(get_draft_round(_assistance_draft_index).get("target", "")),
		"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
	})
	_record_transition(transition)
	return {"accepted": true, "resolution": _policy.result_snapshot(transition)}


## The draft assistance points at — -1 until assistance was acknowledged.
func get_assistance_draft_index() -> int:
	return _assistance_draft_index if _policy != null and _policy.is_unit_assistance_accepted() else -1


## Resolves the theory with the partner once blind submission closed: every
## draft the evaluator already accepts is KEPT exactly as the player built it;
## every invalid draft is replaced by the first authored proof set of that
## question's target that matches its relation and slot count, uses only pool
## evidence and classifies as valid. Everything is then committed through
## DeductionEvaluator.commit_attempt(). Returns the accepted-theory result shape
## with "partner": true and "partner_draft_indices".
func resolve_with_partner() -> Dictionary:
	if _session == null or _theory_accepted or _completed or not _policy.can_use_partner_resolution():
		return _uncounted_result(REASON_PARTNER_UNAVAILABLE)

	var plan: Array = []
	var supplied: Array[int] = []
	for i in _rounds.size():
		var round_def: Dictionary = _rounds[i]
		var current: Array[String] = get_selected_evidence_ids(i)
		var classified: Dictionary = DeductionEvaluator.classify_attempt(_case_def, _session, str(round_def.get("target", "")), str(round_def.get("relation", "")), current)
		if DeductionEvaluator.is_valid_category(str(classified.get("category", ""))):
			plan.append(current)
			continue
		var candidate: Array[String] = _partner_selection(i)
		if candidate.is_empty():
			return _uncounted_result(REASON_INTERNAL_ERROR)
		plan.append(candidate)
		supplied.append(i)

	var previous_drafts: Array = []
	for draft in _drafts:
		previous_drafts.append((draft as Array[String]).duplicate())
	for i in plan.size():
		_drafts[i] = plan[i]
	if not _commit_every_draft(ResolutionPolicy.RESOLVED_BY_PARTNER):
		_drafts = previous_drafts
		return _uncounted_result(REASON_INTERNAL_ERROR)

	_partner_draft_indices = supplied
	var transition: Dictionary = _policy.register_partner_resolution()
	_record(ResolutionPolicy.EVENT_PARTNER_RESOLUTION_USED, {
		"unit": _policy.get_unit_index(), "drafts": _draft_payloads(), "partner_supplied_drafts": supplied.duplicate(),
		"resolved_by": ResolutionPolicy.RESOLVED_BY_PARTNER,
		"run_resolution_result_before": transition.get("run_resolution_result_before", ""), "run_resolution_result_after": transition.get("run_resolution_result_after", ""),
	})
	_record_transition(transition)
	var result: Dictionary = _result(RESULT_THEORY_ACCEPTED, "", true, false, transition)
	result["partner"] = true
	result["partner_draft_indices"] = supplied.duplicate()
	result["resolved_targets"] = _targets()
	return result


## Which drafts the partner supplied in this run's partner resolution ([] if
## none) — lets the presenter explain the partner's connections.
func get_partner_draft_indices() -> Array[int]:
	return _partner_draft_indices.duplicate()


func _partner_selection(index: int) -> Array[String]:
	var round_def: Dictionary = get_draft_round(index)
	var target: String = str(round_def.get("target", ""))
	var relation: String = str(round_def.get("relation", ""))
	var pool: Array[String] = get_evidence_pool_ids()
	for proof_set in DeductionEvaluator.dict_array(DeductionEvaluator.find_claim(_case_def, target).get("proof_sets", [])):
		if str(proof_set.get("relation", "")) != relation:
			continue
		var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
		if requires.size() != get_slot_count(index) or requires.any(func(item: String) -> bool: return not pool.has(item)):
			continue
		var classified: Dictionary = DeductionEvaluator.classify_attempt(_case_def, _session, target, relation, requires)
		if DeductionEvaluator.is_valid_category(str(classified.get("category", ""))):
			return requires
	return []


# ---------------------------------------------------------------------------
# Hints — REUSES the real base hint contract (DeductionEvaluator/
# DeductionSession), never a second, Prototype-B-owned shape.

## Reveals the next hint level for the ACTIVE draft's target through the real
## DeductionEvaluator.request_hint(). A newly revealed level is registered with
## the ResolutionPolicy and its snapshot returned under "resolution".
func reveal_next_hint() -> Dictionary:
	var target: String = str(get_active_round().get("target", ""))
	if _session == null or target == "":
		return {"available": false, "target": target, "level": 0, "exhausted": false, "resolution": {}}
	var hint: Dictionary = DeductionEvaluator.request_hint(_case_def, _session, target)
	var transition: Dictionary = {}
	if hint.get("available", false) and not hint.get("exhausted", false):
		_record("hint_revealed", {"target": target, "draft": _active_index, "level": hint.get("level", 0)})
		transition = _policy.register_hint(int(hint.get("level", 0)))
		_record_transition(transition)
	hint["resolution"] = _policy.result_snapshot(transition)
	return hint


func get_hint_level(index: int = -1) -> int:
	var target: String = str(get_draft_round(_resolve_index(index)).get("target", ""))
	return _session.get_hint_level(target) if _session != null and target != "" else 0


# ---------------------------------------------------------------------------
# Progress and stats

## Any interaction that would be a shame to silently discard — including
## unsubmitted drafts, since assembling a theory is real, deliberate work.
func has_progress() -> bool:
	if _session == null:
		return false
	for draft in _drafts:
		if not (draft as Array).is_empty():
			return true
	return _submission_count > 0 or _drafts_saved_count > 0 or not _session.get_opened_evidence_ids().is_empty() \
		or not _session.get_hint_levels().is_empty()


## Numeric-only statistics. "attempts"/"failed" are this run's formal theory
## commits / failed ones; the tier is reported separately.
func get_stats() -> Dictionary:
	return {
		"elapsed_ms": maxi(int(_clock_fn.call()) - _start_ticks, 0),
		"attempts": _submission_count,
		"failed": _failed_attempt_count,
		"opened": _session.get_opened_evidence_ids().size() if _session != null else 0,
		"replacements": _replacement_count,
		"drafts_saved": _drafts_saved_count,
		"hints_used": _hints_used_total(),
		"assistance_used": _policy.get_assistance_count() if _policy != null else 0,
		"partner_resolutions": _policy.get_partner_resolution_count() if _policy != null else 0,
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
	_record("prototype_abandoned", _stats_with_resolution())


# ---------------------------------------------------------------------------
# Private

func _resolve_index(index: int) -> int:
	return _active_index if index < 0 else index


func _normalized(index: int) -> Array[String]:
	var ids: Array[String] = get_selected_evidence_ids(index)
	ids.sort()  # deterministic, order-independent — see docs/prototype-b.md, "Recorder events".
	return ids


func _theory_key() -> String:
	var parts: PackedStringArray = []
	for i in _rounds.size():
		parts.append("%d:%s" % [i, ",".join(_normalized(i))])
	return "|".join(parts)


func _draft_payloads() -> Array[Dictionary]:
	var payloads: Array[Dictionary] = []
	for i in _rounds.size():
		payloads.append({"draft": i, "target": str(_rounds[i].get("target", "")), "evidence_ids": _normalized(i)})
	return payloads


func _targets() -> Array[String]:
	var targets: Array[String] = []
	for round_def in _rounds:
		targets.append(str(round_def.get("target", "")))
	return targets


func _record(event_type: String, payload: Dictionary) -> void:
	if _recorder != null:
		_recorder.record(event_type, _recorder.get_current_source(), payload)


func _record_transition(transition: Dictionary) -> void:
	for event in ResolutionPolicy.transition_events(transition):
		var payload: Dictionary = (event["payload"] as Dictionary).duplicate()
		payload["unit"] = _policy.get_unit_index()
		_record(str(event["type"]), payload)


func _stats_with_resolution() -> Dictionary:
	var payload: Dictionary = get_stats()
	payload["resolution"] = _policy.get_summary() if _policy != null else {}
	return payload


func _previous_run_payload(next_case_id: String) -> Dictionary:
	if _session == null or _policy == null:
		return {}
	return {
		"case_id": next_case_id, "previous_case_id": str(_case_def.get("id", "")), "previous_run": _run_count,
		"previous_completed": _completed, "previous_run_resolution_result": _policy.get_run_resolution_result(),
		"previous_formal_commits": _policy.get_formal_commit_count(), "previous_failed_commits": _policy.get_failed_commit_count(),
	}


func _result(category: String, reason: String, accepted: bool, counted: bool, transition: Dictionary) -> Dictionary:
	return {
		"category": category, "reason": reason, "accepted": accepted, "counted": counted, "partner": false,
		"resolution": _policy.result_snapshot(transition) if _policy != null else {},
	}


func _uncounted_result(reason: String) -> Dictionary:
	return _result(DeductionEvaluator.INVALID_INPUT, reason, false, false, {})
