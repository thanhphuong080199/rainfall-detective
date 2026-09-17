class_name ResolutionPolicy
extends RefCounted
## Shared resolution policy for the debug-only deduction prototypes
## (Milestone 1.14 — see docs/resolution-policy.md; hardened in Milestone
## 1.14.1 to make the two concepts below unambiguous by name, never just by
## comment). Makes blind trial-and-error an inferior strategy without ever
## creating a hard failure: formal commits are limited per resolution unit,
## repeated failures move the unit into Assisted Mode, and the unit can
## always end through partner resolution.
##
## Two independent layers, deliberately never merged into one ambiguous
## field:
##   * RUN_RESOLUTION_RESULT (independent -> guided -> assisted) describes
##     how the WHOLE RUN was solved. It only ever moves toward "assisted" —
##     nothing (a new unit, a reset selection, a locale switch) can move it
##     back. get_run_resolution_result() is the one accessor for it.
##   * CURRENT_UNIT_PHASE (standard -> assistance_required -> assisted ->
##     partner_available, or -> resolved at any submitting phase) gates what
##     the CURRENT puzzle accepts, together with its own local failure
##     counters (get_current_unit_failures(), get_standard_attempts_remaining(),
##     get_assisted_attempts_remaining()). Controllers call begin_next_unit()
##     once a unit is resolved (Prototype A: each testimony part; Prototype C:
##     the timeline, then the claim justification) — this resets ONLY the
##     local phase/counters. It never touches the run result, and the run
##     result never leaks back into a fresh unit's own phase: a brand-new
##     unit always starts in PHASE_STANDARD with a full local budget and no
##     active assistance, however elevated the run result already is.
##
## A caller that wants to show both to the player MUST read them separately
## (ResolutionPresenter.build_status() returns "current_status_text" — local
## only — and "run_result_text" — run-wide only, worded so a fresh unit is
## never described as itself "Assisted" just because an earlier unit used
## help) — see docs/resolution-policy.md, "Local unit state vs. run result".
##
## Pure, deterministic and autoload-free: no knowledge of statements, evidence,
## deductions or timeline events, no GameState, no recorder. The owning
## controller decides what counts as a formal commit (only a genuinely
## evaluated submission — never an invalid UI action, a duplicate or a
## resubmission of something already resolved), calls the register_*()
## methods, and records telemetry itself from the transition dictionaries they
## return (see transition_events()).

## Snapshot format version for to_dict()/load_dict() (prototype-only
## serialization, never the production save). Bumped to 2 in Milestone 1.14.1
## when "tier"/"phase" were renamed to "run_resolution_result"/
## "current_unit_phase" in the serialized dictionary — a v1 dictionary (if one
## ever existed outside this session) is not something load_dict() accepts.
const FORMAT_VERSION := 2

const TIER_INDEPENDENT := "independent"
const TIER_GUIDED := "guided"
const TIER_ASSISTED := "assisted"
## Least to most assisted — a run's result only ever moves right. Partner
## resolution is a deliberate sub-case of TIER_ASSISTED, not a separate,
## higher level: it always accompanies (never exceeds) the Assisted result —
## see docs/resolution-policy.md, "Run result vs. how a unit resolved".
const TIERS := [TIER_INDEPENDENT, TIER_GUIDED, TIER_ASSISTED]

const PHASE_STANDARD := "standard"
const PHASE_ASSISTANCE_REQUIRED := "assistance_required"
const PHASE_ASSISTED := "assisted"
const PHASE_PARTNER_AVAILABLE := "partner_available"
const PHASE_RESOLVED := "resolved"
const PHASES := [PHASE_STANDARD, PHASE_ASSISTANCE_REQUIRED, PHASE_ASSISTED, PHASE_PARTNER_AVAILABLE, PHASE_RESOLVED]

## Failed formal commits a unit accepts before assistance must be acknowledged.
const STANDARD_FAILURE_LIMIT := 3
## Further failed formal commits a unit accepts in Assisted Mode before blind
## submission closes and partner resolution is offered.
const ASSISTED_FAILURE_LIMIT := 2
## Run-wide failed formal commits that make a run at least Guided / Assisted.
const GUIDED_FAILED_COMMITS := 1
const ASSISTED_FAILED_COMMITS := 3
## Hint levels that make a run at least Guided / Assisted.
const GUIDED_HINT_LEVEL := 1
const ASSISTED_HINT_LEVEL := 3

const RESOLVED_BY_PLAYER := "player"
const RESOLVED_BY_PARTNER := "partner"

const REASON_FAILED_COMMIT := "failed_commit"
const REASON_SUCCESSFUL_COMMIT := "successful_commit"
const REASON_HINT := "hint"
const REASON_ASSISTANCE := "assistance"
const REASON_PARTNER := "partner_resolution"

## Stable recorder event types every prototype controller emits for this
## policy (docs/resolution-policy.md, "Recorder events"). The policy itself
## never records anything. EVENT_RUN_RESOLUTION_RESULT_CHANGED is a RUN-WIDE
## escalation and fires at most once per threshold crossed in the whole run;
## EVENT_ASSISTANCE_OFFERED/EVENT_PARTNER_RESOLUTION_OFFERED are LOCAL
## unit-phase transitions and can fire again in a later unit — the two kinds
## are never the same event type, so a consumer never has to guess which one
## a given event represents (Milestone 1.14.1; event_schema_version 2, see
## DeductionLabRecorder).
const EVENT_FORMAL_COMMIT_STARTED := "formal_commit_started"
const EVENT_FORMAL_COMMIT_FAILED := "formal_commit_failed"
const EVENT_FORMAL_COMMIT_SUCCEEDED := "formal_commit_succeeded"
const EVENT_RUN_RESOLUTION_RESULT_CHANGED := "run_resolution_result_changed"
const EVENT_ASSISTANCE_OFFERED := "assistance_offered"
const EVENT_ASSISTANCE_ACCEPTED := "assistance_accepted"
const EVENT_PARTNER_RESOLUTION_OFFERED := "partner_resolution_offered"
const EVENT_PARTNER_RESOLUTION_USED := "partner_resolution_used"
const EVENT_PROTOTYPE_RESTARTED := "prototype_restarted"

## The run-wide result — see the class doc's "RUN_RESOLUTION_RESULT" above.
## Never reset by begin_next_unit().
var _run_resolution_result: String = TIER_INDEPENDENT
## The current unit's phase — see the class doc's "CURRENT_UNIT_PHASE" above.
## Reset to PHASE_STANDARD by begin_next_unit().
var _current_unit_phase: String = PHASE_STANDARD
var _unit_index: int = 0
var _unit_standard_failures: int = 0
var _unit_assisted_failures: int = 0
var _unit_assistance_accepted: bool = false
var _unit_resolved_by: String = ""
var _formal_commits: int = 0
var _failed_commits: int = 0
var _max_hint_level: int = 0
var _assistance_count: int = 0
var _partner_count: int = 0


# ---------------------------------------------------------------------------
# Queries

## The run-wide result (TIER_INDEPENDENT/GUIDED/ASSISTED) — how the WHOLE RUN
## was solved so far, for reporting and completion statistics ONLY. Never
## describes the current unit's own local state; use get_current_unit_phase()
## and the local failure counters for that. Monotonic within a run.
func get_run_resolution_result() -> String:
	return _run_resolution_result


## The CURRENT unit's phase — standard/assistance_required/assisted/
## partner_available/resolved. Reset to PHASE_STANDARD by begin_next_unit();
## never influenced by the run-wide result.
func get_current_unit_phase() -> String:
	return _current_unit_phase


func get_unit_index() -> int:
	return _unit_index


## True while the current unit accepts a formal commit at all.
func can_submit() -> bool:
	return _current_unit_phase == PHASE_STANDARD or _current_unit_phase == PHASE_ASSISTED


func requires_assistance() -> bool:
	return _current_unit_phase == PHASE_ASSISTANCE_REQUIRED


func can_use_partner_resolution() -> bool:
	return _current_unit_phase == PHASE_PARTNER_AVAILABLE


func is_unit_resolved() -> bool:
	return _current_unit_phase == PHASE_RESOLVED


## "player" or "partner" once the current unit is resolved, "" before.
func get_unit_resolved_by() -> String:
	return _unit_resolved_by


## True from the moment the CURRENT unit's assistance was acknowledged until
## the next unit begins — gates every piece of targeted assistance content. A
## fresh unit (right after begin_next_unit()) always reports false here, even
## when the run result is already Assisted from an earlier unit — assistance
## content never leaks across units.
func is_unit_assistance_accepted() -> bool:
	return _unit_assistance_accepted


## Failed formal commits in the CURRENT unit (standard + assisted). Resets to
## 0 on begin_next_unit() regardless of the run-wide result.
func get_current_unit_failures() -> int:
	return _unit_standard_failures + _unit_assisted_failures


func get_standard_failure_count() -> int:
	return _unit_standard_failures


func get_assisted_failure_count() -> int:
	return _unit_assisted_failures


func get_standard_attempts_remaining() -> int:
	return maxi(STANDARD_FAILURE_LIMIT - _unit_standard_failures, 0)


func get_assisted_attempts_remaining() -> int:
	return maxi(ASSISTED_FAILURE_LIMIT - _unit_assisted_failures, 0)


## Run-wide formal commits (successful and failed), never counting partner
## resolution — that is not the player's commit.
func get_formal_commit_count() -> int:
	return _formal_commits


func get_failed_commit_count() -> int:
	return _failed_commits


func get_max_hint_level() -> int:
	return _max_hint_level


func get_assistance_count() -> int:
	return _assistance_count


func get_partner_resolution_count() -> int:
	return _partner_count


## Recorder/completion payload: run-wide numbers plus the run result id. The
## id is an internal value for analysis — player-facing text always goes
## through ResolutionPresenter.
func get_summary() -> Dictionary:
	return {
		"run_resolution_result": _run_resolution_result,
		"formal_commits": _formal_commits,
		"failed_commits": _failed_commits,
		"max_hint_level": _max_hint_level,
		"assistance_used": _assistance_count,
		"partner_resolutions": _partner_count,
	}


static func run_resolution_result_rank(result: String) -> int:
	return TIERS.find(result)


# ---------------------------------------------------------------------------
# Transitions — every method returns a transition dictionary (see
# _transition()); "accepted": false means nothing changed.

## One genuinely evaluated, unsuccessful formal commit. Rejected (nothing
## counted) while the unit does not accept submissions — locked behind
## assistance, waiting for partner resolution, or already resolved.
func register_failed_commit() -> Dictionary:
	if not can_submit():
		return _rejected(REASON_FAILED_COMMIT, "submission_locked")
	var result_before: String = _run_resolution_result
	var phase_before: String = _current_unit_phase
	_formal_commits += 1
	_failed_commits += 1
	if _current_unit_phase == PHASE_STANDARD:
		_unit_standard_failures += 1
		if _unit_standard_failures >= STANDARD_FAILURE_LIMIT:
			_current_unit_phase = PHASE_ASSISTANCE_REQUIRED
			_raise_run_resolution_result(TIER_ASSISTED)
	else:
		_unit_assisted_failures += 1
		if _unit_assisted_failures >= ASSISTED_FAILURE_LIMIT:
			_current_unit_phase = PHASE_PARTNER_AVAILABLE
	_raise_run_resolution_result(_run_resolution_result_for_failed_commits(_failed_commits))
	return _transition(result_before, phase_before, REASON_FAILED_COMMIT)


## One genuinely evaluated, logically valid formal commit. `resolves_unit` is
## false for a valid commit that does not finish the unit (Prototype A's
## optional innocent lie, or one of several required refutations) — it still
## counts as a formal commit and is never a penalty.
func register_success(resolves_unit: bool = true) -> Dictionary:
	if not can_submit():
		return _rejected(REASON_SUCCESSFUL_COMMIT, "submission_locked")
	var result_before: String = _run_resolution_result
	var phase_before: String = _current_unit_phase
	_formal_commits += 1
	if resolves_unit:
		_current_unit_phase = PHASE_RESOLVED
		_unit_resolved_by = RESOLVED_BY_PLAYER
	return _transition(result_before, phase_before, REASON_SUCCESSFUL_COMMIT)


## A newly revealed hint level (1-4). Levels 1-2 make the run at least Guided,
## 3-4 make it Assisted. Allowed in any phase; never changes the phase.
func register_hint(level: int) -> Dictionary:
	if level < GUIDED_HINT_LEVEL:
		return _rejected(REASON_HINT, "invalid_level")
	var result_before: String = _run_resolution_result
	var phase_before: String = _current_unit_phase
	_max_hint_level = maxi(_max_hint_level, level)
	_raise_run_resolution_result(TIER_ASSISTED if level >= ASSISTED_HINT_LEVEL else TIER_GUIDED)
	return _transition(result_before, phase_before, REASON_HINT)


## The player acknowledges targeted assistance — re-enables submission for
## ASSISTED_FAILURE_LIMIT more failed formal commits.
func accept_assistance() -> Dictionary:
	if _current_unit_phase != PHASE_ASSISTANCE_REQUIRED:
		return _rejected(REASON_ASSISTANCE, "assistance_not_required")
	var result_before: String = _run_resolution_result
	var phase_before: String = _current_unit_phase
	_current_unit_phase = PHASE_ASSISTED
	_unit_assistance_accepted = true
	_assistance_count += 1
	_raise_run_resolution_result(TIER_ASSISTED)
	return _transition(result_before, phase_before, REASON_ASSISTANCE)


## The controller resolved the unit through a partner/system path that went
## through the real evaluator. Only available once blind submission closed.
func register_partner_resolution() -> Dictionary:
	if _current_unit_phase != PHASE_PARTNER_AVAILABLE:
		return _rejected(REASON_PARTNER, "partner_unavailable")
	var result_before: String = _run_resolution_result
	var phase_before: String = _current_unit_phase
	_current_unit_phase = PHASE_RESOLVED
	_unit_resolved_by = RESOLVED_BY_PARTNER
	_partner_count += 1
	_raise_run_resolution_result(TIER_ASSISTED)
	return _transition(result_before, phase_before, REASON_PARTNER)


## Starts the next resolution unit with a fresh failure budget and NO active
## assistance. The run-wide result and every run-wide count are kept exactly —
## this is the one guarantee the whole Milestone 1.14.1 hardening pass exists
## to make explicit: a new unit never inherits the previous unit's local
## phase, failures or assistance target, and the run result never regresses
## either. Only allowed once the current unit is resolved — a controller can
## never reset a live budget this way.
func begin_next_unit() -> bool:
	if _current_unit_phase != PHASE_RESOLVED:
		return false
	_unit_index += 1
	_current_unit_phase = PHASE_STANDARD
	_unit_standard_failures = 0
	_unit_assisted_failures = 0
	_unit_assistance_accepted = false
	_unit_resolved_by = ""
	return true


## What a controller attaches to an action's result (under "resolution") so
## feedback can describe exactly what THAT action did to the budget and run
## result, even after the policy moves on. `transition` is whatever
## register_*()/accept_assistance() returned; pass {} for an action that
## counted nothing.
func result_snapshot(transition: Dictionary) -> Dictionary:
	return {
		"counted": transition.get("accepted", false) == true,
		"reason": transition.get("reason", ""),
		"run_resolution_result_before": transition.get("run_resolution_result_before", _run_resolution_result),
		"run_resolution_result_after": transition.get("run_resolution_result_after", _run_resolution_result),
		"run_resolution_result_changed": transition.get("run_resolution_result_changed", false) == true,
		"current_unit_phase_after": transition.get("current_unit_phase_after", _current_unit_phase),
		"assistance_offered": transition.get("assistance_offered", false) == true,
		"partner_offered": transition.get("partner_offered", false) == true,
		"current_unit_failures": get_current_unit_failures(),
		"standard_attempts_remaining": get_standard_attempts_remaining(),
		"assisted_attempts_remaining": get_assisted_attempts_remaining(),
	}


## The recorder events a transition implies, in a fixed order:
## run_resolution_result_changed (a RUN-WIDE escalation), assistance_offered,
## partner_resolution_offered (both LOCAL unit-phase transitions — see the
## class doc's EVENT_* constants). Returned as [{"type", "payload"}] so the
## CONTROLLER records them (adding its own unit/prototype context) — the
## policy never touches a recorder.
static func transition_events(transition: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if transition.get("accepted", false) != true:
		return events
	if transition.get("run_resolution_result_changed", false) == true:
		events.append({"type": EVENT_RUN_RESOLUTION_RESULT_CHANGED, "payload": {
			"from": transition.get("run_resolution_result_before", ""), "to": transition.get("run_resolution_result_after", ""), "reason": transition.get("reason", ""),
		}})
	if transition.get("assistance_offered", false) == true:
		events.append({"type": EVENT_ASSISTANCE_OFFERED, "payload": {"run_resolution_result": transition.get("run_resolution_result_after", "")}})
	if transition.get("partner_offered", false) == true:
		events.append({"type": EVENT_PARTNER_RESOLUTION_OFFERED, "payload": {"run_resolution_result": transition.get("run_resolution_result_after", "")}})
	return events


# ---------------------------------------------------------------------------
# Serialization — prototype snapshots and tests only; no production save.

func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"run_resolution_result": _run_resolution_result,
		"current_unit_phase": _current_unit_phase,
		"unit_index": _unit_index,
		"unit_standard_failures": _unit_standard_failures,
		"unit_assisted_failures": _unit_assisted_failures,
		"unit_assistance_accepted": _unit_assistance_accepted,
		"unit_resolved_by": _unit_resolved_by,
		"formal_commits": _formal_commits,
		"failed_commits": _failed_commits,
		"max_hint_level": _max_hint_level,
		"assistance_count": _assistance_count,
		"partner_resolution_count": _partner_count,
	}


## Restores from to_dict() output (numbers may come back as floats after a JSON
## round trip). Rejects anything malformed or internally inconsistent as a
## whole — including a run result lower than its own counts imply — and
## leaves the policy fresh instead.
func load_dict(data: Variant) -> bool:
	_reset()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var result: Variant = data.get("run_resolution_result")
	var phase: Variant = data.get("current_unit_phase")
	var resolved_by: Variant = data.get("unit_resolved_by", "")
	var assistance_accepted: Variant = data.get("unit_assistance_accepted", false)
	if not (result is String and TIERS.has(result)) or not (phase is String and PHASES.has(phase)):
		return false
	if not (resolved_by is String and ["", RESOLVED_BY_PLAYER, RESOLVED_BY_PARTNER].has(resolved_by)) or typeof(assistance_accepted) != TYPE_BOOL:
		return false
	var counts: Dictionary = {}
	for key in ["unit_index", "unit_standard_failures", "unit_assisted_failures", "formal_commits", "failed_commits", "max_hint_level", "assistance_count", "partner_resolution_count"]:
		var parsed: int = _parse_count(data.get(key))
		if parsed < 0:
			return false
		counts[key] = parsed
	if counts["unit_standard_failures"] > STANDARD_FAILURE_LIMIT or counts["unit_assisted_failures"] > ASSISTED_FAILURE_LIMIT:
		return false
	if counts["failed_commits"] > counts["formal_commits"] or counts["unit_standard_failures"] + counts["unit_assisted_failures"] > counts["failed_commits"]:
		return false
	if (phase == PHASE_RESOLVED) != (resolved_by != ""):
		return false

	var minimum_rank: int = run_resolution_result_rank(_run_resolution_result_for_failed_commits(counts["failed_commits"]))
	if counts["max_hint_level"] >= ASSISTED_HINT_LEVEL or counts["assistance_count"] > 0 or counts["partner_resolution_count"] > 0:
		minimum_rank = run_resolution_result_rank(TIER_ASSISTED)
	elif counts["max_hint_level"] >= GUIDED_HINT_LEVEL:
		minimum_rank = maxi(minimum_rank, run_resolution_result_rank(TIER_GUIDED))
	if run_resolution_result_rank(result) < minimum_rank:
		return false

	_run_resolution_result = result
	_current_unit_phase = phase
	_unit_index = counts["unit_index"]
	_unit_standard_failures = counts["unit_standard_failures"]
	_unit_assisted_failures = counts["unit_assisted_failures"]
	_unit_assistance_accepted = assistance_accepted
	_unit_resolved_by = resolved_by
	_formal_commits = counts["formal_commits"]
	_failed_commits = counts["failed_commits"]
	_max_hint_level = counts["max_hint_level"]
	_assistance_count = counts["assistance_count"]
	_partner_count = counts["partner_resolution_count"]
	return true


# ---------------------------------------------------------------------------
# Private

func _reset() -> void:
	_run_resolution_result = TIER_INDEPENDENT
	_current_unit_phase = PHASE_STANDARD
	_unit_index = 0
	_unit_standard_failures = 0
	_unit_assisted_failures = 0
	_unit_assistance_accepted = false
	_unit_resolved_by = ""
	_formal_commits = 0
	_failed_commits = 0
	_max_hint_level = 0
	_assistance_count = 0
	_partner_count = 0


func _raise_run_resolution_result(result: String) -> void:
	if run_resolution_result_rank(result) > run_resolution_result_rank(_run_resolution_result):
		_run_resolution_result = result


static func _run_resolution_result_for_failed_commits(failed_commits: int) -> String:
	if failed_commits >= ASSISTED_FAILED_COMMITS:
		return TIER_ASSISTED
	if failed_commits >= GUIDED_FAILED_COMMITS:
		return TIER_GUIDED
	return TIER_INDEPENDENT


func _transition(result_before: String, phase_before: String, reason: String) -> Dictionary:
	return {
		"accepted": true,
		"reason": reason,
		"rejection": "",
		"run_resolution_result_before": result_before,
		"run_resolution_result_after": _run_resolution_result,
		"run_resolution_result_changed": result_before != _run_resolution_result,
		"current_unit_phase_before": phase_before,
		"current_unit_phase_after": _current_unit_phase,
		"assistance_offered": phase_before != PHASE_ASSISTANCE_REQUIRED and _current_unit_phase == PHASE_ASSISTANCE_REQUIRED,
		"partner_offered": phase_before != PHASE_PARTNER_AVAILABLE and _current_unit_phase == PHASE_PARTNER_AVAILABLE,
	}


func _rejected(reason: String, rejection: String) -> Dictionary:
	var transition: Dictionary = _transition(_run_resolution_result, _current_unit_phase, reason)
	transition["accepted"] = false
	transition["rejection"] = rejection
	return transition


## A non-negative whole number from to_dict() output (JSON numbers arrive as
## float), or -1 when missing or malformed.
static func _parse_count(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1
	var number: float = value
	if number < 0.0 or number != floorf(number):
		return -1
	return int(number)
