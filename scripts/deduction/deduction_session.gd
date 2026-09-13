class_name DeductionSession
extends RefCounted
## Mutable player progress for ONE deduction case (Milestone 1.9 — see
## docs/deduction-system.md). Deliberately separate from the immutable case
## definition (a plain Dictionary from ContentDB.get_deduction_case()): the
## definition says what is provable, this says what the player has proven.
##
## Holds no logic about WHY a claim resolves — DeductionEvaluator decides that
## and calls the record_*/resolve_* methods below. UI code should never call
## those directly, only DeductionEvaluator.commit_attempt()/request_hint(), so a
## claim can only ever resolve through an explicit, validated commitment.
##
## Signals are the local playtest-instrumentation contract (see
## docs/deduction-playtest-plan.md, "Instrumentation"): plain Godot signals, no
## recording sink, no network. They fire only for real transitions — never
## from load_dict(), mirroring how CaseManager never re-runs entry effects on
## load.
##
## Not an autoload and not yet persisted through SaveManager — see
## docs/deduction-system.md, "Save/load (deferred)". to_dict()/load_dict() are
## JSON-safe so that integration is a wiring job, not a format change.

signal evidence_opened(evidence_id: String)
signal proof_committed(claim_id: String, relation: String, category: String)
signal claim_resolved(claim_id: String, status: String)
signal deduction_unlocked(claim_id: String)
signal hint_revealed(target_id: String, level: int)
signal case_solved(case_id: String)

const FORMAT_VERSION := 1
const STATUS_SUPPORTED := "supported"
const STATUS_REFUTED := "refuted"

var case_id: String = ""

var _claim_status: Dictionary = {}
var _hint_levels: Dictionary = {}
var _opened_evidence: Array[String] = []
var _attempts: Array[Dictionary] = []
var _is_solved: bool = false


func _init(p_case_id: String = "") -> void:
	case_id = p_case_id


## Clears all progress (keeps case_id). Deterministic: a reset session's
## to_dict() equals a freshly constructed one's.
func reset() -> void:
	_claim_status = {}
	_hint_levels = {}
	_opened_evidence = []
	_attempts = []
	_is_solved = false


func get_claim_status(claim_id: String) -> String:
	return _claim_status.get(claim_id, "")


func is_supported(claim_id: String) -> bool:
	return get_claim_status(claim_id) == STATUS_SUPPORTED


func get_resolved_claims() -> Dictionary:
	return _claim_status.duplicate()


func has_opened_evidence(evidence_id: String) -> bool:
	return _opened_evidence.has(evidence_id)


## Every evidence id opened so far, in the order opened. Read-only snapshot —
## mirrors get_resolved_claims()/get_attempts() below (Milestone 1.10: the
## Deduction Lab's "meaningful progress" check reads this instead of
## reimplementing what "opened" means).
func get_opened_evidence_ids() -> Array[String]:
	return _opened_evidence.duplicate()


## target_id -> current hint level (1-4), for every target with at least one
## hint revealed. Read-only snapshot, same rationale as get_opened_evidence_ids().
func get_hint_levels() -> Dictionary:
	return _hint_levels.duplicate()


## For a future UI to report "the player looked at this item". Returns true
## the first time. Opening evidence never affects what is provable.
func mark_evidence_opened(evidence_id: String) -> bool:
	if _opened_evidence.has(evidence_id):
		return false
	_opened_evidence.append(evidence_id)
	evidence_opened.emit(evidence_id)
	return true


func get_hint_level(target_id: String) -> int:
	return _hint_levels.get(target_id, 0)


## Every commit attempt so far, valid or not — {"claim", "relation",
## "category"} — in order. The "blind submissions" playtest metric reads this.
func get_attempts() -> Array[Dictionary]:
	return _attempts.duplicate(true)


func is_solved() -> bool:
	return _is_solved


# ---------------------------------------------------------------------------
# Called by DeductionEvaluator only.

func record_attempt(claim_id: String, relation: String, category: String) -> void:
	_attempts.append({"claim": claim_id, "relation": relation, "category": category})
	proof_committed.emit(claim_id, relation, category)


## Returns true when this newly resolved the claim. A claim resolves at most
## once: a second valid commit (e.g. an alternate proof) changes nothing.
## `is_derived` marks a claim other proofs may use as input once supported.
func resolve_claim(claim_id: String, status: String, is_derived: bool) -> bool:
	if _claim_status.has(claim_id):
		return false
	_claim_status[claim_id] = status
	claim_resolved.emit(claim_id, status)
	if is_derived and status == STATUS_SUPPORTED:
		deduction_unlocked.emit(claim_id)
	return true


func advance_hint(target_id: String, level: int) -> void:
	_hint_levels[target_id] = level
	hint_revealed.emit(target_id, level)


func mark_solved() -> bool:
	if _is_solved:
		return false
	_is_solved = true
	case_solved.emit(case_id)
	return true


# ---------------------------------------------------------------------------
# Serialization

func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"case_id": case_id,
		"claim_status": _claim_status.duplicate(),
		"hint_levels": _hint_levels.duplicate(),
		"opened_evidence": _opened_evidence.duplicate(),
		"attempts": _attempts.duplicate(true),
		"solved": _is_solved,
	}


## Restores from to_dict() output (possibly after a JSON round trip, where
## numbers come back as floats). Rejects anything malformed as a whole —
## returns false and leaves the session reset rather than half-loaded. Emits
## no signals: restoring progress is not the progress happening again.
func load_dict(data: Variant) -> bool:
	reset()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var claim_status: Variant = data.get("claim_status", {})
	var hint_levels: Variant = data.get("hint_levels", {})
	var opened: Variant = data.get("opened_evidence", [])
	var attempts: Variant = data.get("attempts", [])
	if typeof(claim_status) != TYPE_DICTIONARY or typeof(hint_levels) != TYPE_DICTIONARY \
			or typeof(opened) != TYPE_ARRAY or typeof(attempts) != TYPE_ARRAY:
		return false

	var restored_status: Dictionary = {}
	for claim_id in claim_status:
		var status: Variant = claim_status[claim_id]
		if typeof(claim_id) != TYPE_STRING or not (status is String and (status == STATUS_SUPPORTED or status == STATUS_REFUTED)):
			return false
		restored_status[claim_id] = status
	var restored_hints: Dictionary = {}
	for target_id in hint_levels:
		var level: int = TimelineEvaluator.parse_minutes(hint_levels[target_id], -1)
		if typeof(target_id) != TYPE_STRING or level < 0:
			return false
		restored_hints[target_id] = level
	var restored_opened: Array[String] = []
	for evidence_id in opened:
		if typeof(evidence_id) != TYPE_STRING:
			return false
		restored_opened.append(evidence_id)
	var restored_attempts: Array[Dictionary] = []
	for attempt in attempts:
		if typeof(attempt) != TYPE_DICTIONARY:
			return false
		restored_attempts.append({
			"claim": str(attempt.get("claim", "")),
			"relation": str(attempt.get("relation", "")),
			"category": str(attempt.get("category", "")),
		})

	case_id = str(data.get("case_id", case_id))
	_claim_status = restored_status
	_hint_levels = restored_hints
	_opened_evidence = restored_opened
	_attempts = restored_attempts
	_is_solved = data.get("solved", false) == true
	return true
