class_name DeductionLabController
extends RefCounted
## Scene-owned session host for the debug-only Deduction Lab (Milestone 1.10
## — see docs/deduction-lab.md). Owns exactly ONE active DeductionSession at a
## time, plus the case-switch/reset confirmation flow. Nothing here decides
## deduction outcomes — it only decides WHICH session exists right now and
## whether replacing it needs confirmation first.
##
## Pure and autoload-free, like DeductionEvaluator/DeductionValidator: the
## caller (scripts/debug/deduction_lab.gd) fetches a case definition through
## ContentDB and hands it in as a Dictionary. The controller never resolves a
## case id itself — this is a deliberate, documented deviation from the
## milestone brief's sketch API (`start_case(case_id)` etc.), because
## resolving an id would mean either an autoload reference (hitting the
## documented -s entry-script compile-order trap — see
## .claude/skills/godot-development/references/cli-verification.md) or a
## second content-loading path (forbidden — "no direct JSON loading from the
## UI"). Taking the already-loaded case_def mirrors exactly how
## DeductionEvaluator.commit_attempt() itself is called, and keeps this class
## testable with hand-built fixtures, no scene tree required.
##
## Deliberately NOT an autoload: docs/deduction-system.md's own "no autoload"
## decision for DeductionSession applies unchanged — the Lab is one debug
## scene, not a service many unrelated scenes need. Deliberately not a second
## session implementation either: every mutation goes through DeductionSession
## /DeductionEvaluator's own public API (reset_session() calls session.reset(),
## never a private field poke).

signal session_replaced(case_id: String)
signal switch_requested(case_id: String)
signal switch_cancelled()

const MODE_PLAYER := "player"
const MODE_AUTHOR := "author"

var _case_def: Dictionary = {}
var _session: DeductionSession = null
var _pending_case_def: Dictionary = {}
var _mode: String = MODE_PLAYER


func get_case_def() -> Dictionary:
	return _case_def


func get_case_id() -> String:
	return str(_case_def.get("id", ""))


## The one active session, or null before any case has been started.
func get_session() -> DeductionSession:
	return _session


func get_mode() -> String:
	return _mode


## Toggling mode is display-only: it never touches the session (Milestone
## 1.10 requirement — "toggling Player/Author mode must not mutate the
## session"). Returns false for an unknown mode string, leaving the current
## mode unchanged.
func set_mode(mode: String) -> bool:
	if mode != MODE_PLAYER and mode != MODE_AUTHOR:
		return false
	_mode = mode
	return true


func has_pending_switch() -> bool:
	return not _pending_case_def.is_empty()


func get_pending_case_id() -> String:
	return str(_pending_case_def.get("id", ""))


## "Meaningful progress" (Milestone 1.10 definition): opened evidence,
## revealed hints, submitted attempts (valid or not), resolved claims/
## unlocked deductions, or a solved case — everything DeductionSession itself
## tracks, read only through its own public getters (never a private field).
## Timeline SUBMISSIONS are not part of this: TimelineEvaluator is pure and
## stateless (docs/deduction-system.md, "Instrumentation" — a submission
## event is deferred to a future prototype screen), so DeductionSession has
## no timeline-progress state to read here. See docs/deduction-lab.md,
## "Known limitations".
func has_progress() -> bool:
	return session_has_progress(_session)


static func session_has_progress(session: DeductionSession) -> bool:
	if session == null:
		return false
	if not session.get_opened_evidence_ids().is_empty():
		return true
	if not session.get_attempts().is_empty():
		return true
	if not session.get_resolved_claims().is_empty():
		return true
	for level in session.get_hint_levels().values():
		if int(level) > 0:
			return true
	return session.is_solved()


## Starts (or restarts) `case_def` immediately with a fresh, isolated
## session — no confirmation. Call this directly only when you already know
## that's safe (the very first case, an explicit Reset, or a confirmed
## switch) — a case-selector UI action should go through
## request_case_switch() instead. Returns false for a malformed case_def
## (not a Dictionary, or no non-empty string "id"), leaving any existing
## session untouched.
func start_case(case_def: Dictionary) -> bool:
	if typeof(case_def) != TYPE_DICTIONARY:
		return false
	var case_id: String = str(case_def.get("id", ""))
	if case_id == "":
		return false
	_case_def = case_def
	_session = DeductionSession.new(case_id)
	_pending_case_def = {}
	session_replaced.emit(case_id)
	return true


## The one entry point a "select this case" UI action should call. Switches
## immediately when there is nothing to lose (no session yet, or the current
## one has no meaningful progress); otherwise leaves the current session
## untouched and defers to confirm_case_switch()/cancel_case_switch().
## Returns "switched", "pending_confirmation", or "invalid".
func request_case_switch(case_def: Dictionary) -> String:
	if typeof(case_def) != TYPE_DICTIONARY or str(case_def.get("id", "")) == "":
		return "invalid"
	if not has_progress():
		start_case(case_def)
		return "switched"
	_pending_case_def = case_def
	switch_requested.emit(str(case_def.get("id", "")))
	return "pending_confirmation"


## Applies a pending switch requested by request_case_switch(). Returns false
## when there is nothing pending.
func confirm_case_switch() -> bool:
	if _pending_case_def.is_empty():
		return false
	var case_def: Dictionary = _pending_case_def
	_pending_case_def = {}
	start_case(case_def)
	return true


## Discards a pending switch, leaving the current session EXACTLY as it was
## (no reset, no replacement — session object identity is untouched). Returns
## false when there was nothing pending.
func cancel_case_switch() -> bool:
	if _pending_case_def.is_empty():
		return false
	_pending_case_def = {}
	switch_cancelled.emit()
	return true


## Resets the current session's progress IN PLACE, through DeductionSession's
## own reset() (never a private mutation) — same case, same object identity.
## Returns false when there is no active session.
func reset_session() -> bool:
	if _session == null:
		return false
	_session.reset()
	return true


## In-memory snapshot for tests/UI (e.g. surviving F1 hide/show without ever
## tearing this controller down — in practice the controller simply isn't
## freed, so snapshot()/restore() exist for completeness and for tests, not
## because hide/show needs them). Reuses DeductionSession's own JSON-safe
## round trip (docs/deduction-system.md, "Save/load (deferred)") instead of a
## second serialization format.
func snapshot() -> Dictionary:
	return {
		"case_id": get_case_id(),
		"session": _session.to_dict() if _session != null else {},
		"mode": _mode,
	}


## Restores a snapshot() dictionary. The snapshot only carries the case id,
## not the full definition, so pass `case_def_hint` (matching that id) when
## the caller already has it on hand — otherwise get_case_def() comes back
## as a bare {"id": ...} stand-in until the caller re-fetches and calls
## start_case()/assigns get_case_def() itself. Returns false for a malformed
## snapshot or a session dict that fails DeductionSession.load_dict().
func restore(data: Dictionary, case_def_hint: Dictionary = {}) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var case_id: String = str(data.get("case_id", ""))
	if case_id == "":
		return false
	var restored_session := DeductionSession.new(case_id)
	if not restored_session.load_dict(data.get("session", {})):
		return false
	if not case_def_hint.is_empty() and str(case_def_hint.get("id", "")) == case_id:
		_case_def = case_def_hint
	elif str(_case_def.get("id", "")) != case_id:
		_case_def = {"id": case_id}
	_session = restored_session
	_pending_case_def = {}
	var mode: Variant = data.get("mode", MODE_PLAYER)
	_mode = mode if (mode == MODE_PLAYER or mode == MODE_AUTHOR) else MODE_PLAYER
	return true
