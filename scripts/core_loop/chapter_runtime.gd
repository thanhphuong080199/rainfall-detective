class_name ChapterRuntime
extends RefCounted
## The production chapter-run orchestrator (Milestone 1.16 — see
## docs/core-loop-sandbox.md). Owns one active run of a chapter whose JSON
## declares a "core_loop" section: its phase, the ONE DeductionSession every
## B/A unit of the run shares, every resolution unit (CoreLoopUnit), which
## progression consequences have been applied, the run help result, when to
## checkpoint, and the recorder's lifecycle.
##
## Not an autoload and not a UI node: Main.gd owns one instance for the life
## of the gameplay scene. It holds no durable truth of its own — every change
## is written straight into GameState.chapter_run (and the rest of GameState:
## evidence, flags, locations, seen interactions stay exactly where they
## always lived), which SaveManager persists. Whenever GameState is replaced
## wholesale (Continue, Load, New Game, the Case Debugger's reset) the runtime
## rebuilds itself from that snapshot — see _needs_reload().
##
## Reuses, never duplicates: consequences are EffectRunner effect lists; unit
## availability is a ConditionEvaluator condition; chapter completion is still
## CaseManager's (the final consequence sets the flag the chapter's
## completion_event waits for); grading is still only the controllers' real
## DeductionEvaluator/TimelineEvaluator calls. Nothing here names a case,
## evidence, claim, statement or timeline event — all of that is content.
##
## Every command follows the 1.15B transition order: validate against the
## active phase/unit -> evaluate through the unit's controller -> apply newly
## reached outcomes' consequences idempotently -> advance the phase -> write
## one atomic checkpoint -> return feedback -> commit the recorder events.

signal state_changed()
signal run_replaced()
signal phase_changed(phase_id: String)
signal chapter_completed()
signal checkpoint_failed()

const SNAPSHOT_FORMAT := 1
## The only core_loop content format this runtime understands.
const LOOP_FORMAT := 1
const PHASE_KIND_BRIEFING := "briefing"
const PHASE_KIND_UNIT := "unit"
## The implicit terminal phase, entered once every authored phase completed
## AND CaseManager reports the chapter complete.
const PHASE_COMPLETED := "completed"

## Refusal/error reasons — internal, mapped to safe text by CoreLoopPresenter.
const REASON_INACTIVE := "no_active_run"
const REASON_ERROR := "run_error"
const REASON_COMPLETED := "chapter_completed"
const REASON_NOT_BRIEFING := "not_in_briefing"
const REASON_UNKNOWN_UNIT := "unknown_unit"
const REASON_UNIT_NOT_CURRENT := "unit_not_current"
const REASON_UNIT_RESOLVED := "unit_resolved"
const REASON_UNIT_LOCKED := "unit_locked"
const REASON_UNIT_NOT_STARTED := "unit_not_started"
const REASON_UNKNOWN_EVIDENCE := "unknown_evidence"
const REASON_CONTENT_ERROR := "content_error"
const REASON_INVALID_SNAPSHOT := "invalid_snapshot"

var _recorder: ChapterRunRecorder
var _id_fn: Callable

var _active: bool = false
var _error: String = ""
var _chapter_id: String = ""
var _config: Dictionary = {}
var _run_id: String = ""
var _revision: int = 0
var _phase_index: int = 0
var _completed: bool = false
var _session: DeductionSession = null
## unit id -> CoreLoopUnit, only for units the player has opened.
var _units: Dictionary = {}
## consequence id -> {"unit", "outcome", "resolved_by", "phase"}.
var _applied: Dictionary = {}
var _run_help_result: String = ResolutionPolicy.TIER_INDEPENDENT
var _open_unit_id: String = ""
var _case_file_opened: Array[String] = []
var _case_file_pinned: Array[String] = []
## Snapshot changes (draft edits, investigation) not yet written to disk.
var _dirty: bool = false
var _in_command: bool = false
## "<run_id>#<revision>" of the GameState.chapter_run this runtime last loaded
## or wrote. Anything else in GameState means the state was replaced from
## outside (Continue/Load/New Game/debug reset) and the runtime must rebuild.
var _synced_key: String = ""


## `id_fn` (no args, returns a String) generates run ids — injectable for
## deterministic tests. `recorder` defaults to a fresh ChapterRunRecorder.
func _init(id_fn: Callable = Callable(), recorder: ChapterRunRecorder = null) -> void:
	_id_fn = id_fn if id_fn.is_valid() else Callable(ChapterRuntime, "_default_run_id")
	_recorder = recorder if recorder != null else ChapterRunRecorder.new()
	GameState.evidence_added.connect(_on_evidence_added)
	GameState.location_changed.connect(_on_location_changed)
	GameState.interaction_seen.connect(_on_interaction_seen)
	GameState.state_replaced.connect(_on_state_replaced)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


static func _default_run_id() -> String:
	return "run-%d-%06d" % [Time.get_unix_time_from_system(), randi() % 1000000]


## Disconnects from the autoloads — the owner calls this before dropping the
## runtime (Main._exit_tree), so a discarded runtime never observes anything.
func detach() -> void:
	for connection in [
		[GameState.evidence_added, _on_evidence_added], [GameState.location_changed, _on_location_changed],
		[GameState.interaction_seen, _on_interaction_seen], [GameState.state_replaced, _on_state_replaced],
		[DialogueManager.dialogue_ended, _on_dialogue_ended],
	]:
		if (connection[0] as Signal).is_connected(connection[1]):
			(connection[0] as Signal).disconnect(connection[1])


## True when `chapter_id` declares a core_loop section this runtime drives.
static func is_core_loop_chapter(chapter_id: String) -> bool:
	return typeof(ContentDB.get_chapter(chapter_id).get("core_loop")) == TYPE_DICTIONARY


# ---------------------------------------------------------------------------
# Lifecycle

## (Re)builds the runtime from GameState: inactive for a chapter without a
## core_loop; a NEW run (first checkpoint written) when chapter_run is empty;
## otherwise a restored run (nothing replayed — only one "chapter_resumed"
## observation). Emits run_replaced.
func reload_from_game_state() -> void:
	_reset_fields()
	_chapter_id = CaseManager.get_current_chapter_id()
	if is_core_loop_chapter(_chapter_id):
		_active = true
		_config = _build_config(_chapter_id)
		if _config.get("ok", false) != true:
			_fail(REASON_CONTENT_ERROR, "chapter '%s' core_loop is not usable: %s" % [_chapter_id, _config.get("reason", "")])
		elif GameState.chapter_run.is_empty():
			_start_new_run()
		else:
			_resume_run()
	_synced_key = _snapshot_key(GameState.chapter_run)
	run_replaced.emit()


func _start_new_run() -> void:
	_run_id = str(_id_fn.call())
	_session = DeductionSession.new(str(_config["case_def"].get("id", "")))
	_recorder.start_segment(CaseManager.get_current_case_id(), _run_id, _chapter_id, LocaleManager.get_locale())
	_recorder.begin_transaction()
	_recorder.record(ChapterRunRecorder.EVENT_CHAPTER_STARTED, _source(), {"phase": get_phase_id(), "location": GameState.current_location})
	_record_phase_entered()
	_checkpoint("run_created")


func _resume_run() -> void:
	var parsed: Dictionary = _parse_snapshot(_chapter_id, GameState.chapter_run, GameState.evidence_inventory, GameState.seen_interactions, _recorder)
	if parsed.get("ok", false) != true:
		_fail(REASON_INVALID_SNAPSHOT, "chapter run snapshot rejected: %s" % parsed.get("reason", ""))
		return
	_run_id = parsed["run_id"]
	_revision = parsed["revision"]
	_phase_index = parsed["phase_index"]
	_completed = parsed["completed"]
	_session = parsed["session"]
	_units = parsed["units"]
	_applied = parsed["applied"]
	_run_help_result = parsed["run_help_result"]
	_open_unit_id = parsed["open_unit"]
	_case_file_opened = parsed["case_file_opened"]
	_case_file_pinned = parsed["case_file_pinned"]
	_recorder.start_segment(CaseManager.get_current_case_id(), _run_id, _chapter_id, LocaleManager.get_locale())
	_recorder.record(ChapterRunRecorder.EVENT_CHAPTER_RESUMED, _source(), {
		"phase": get_phase_id(), "location": GameState.current_location, "run_help_result": _run_help_result, "open_unit": _open_unit_id,
	})
	_recorder.record(ChapterRunRecorder.EVENT_CHECKPOINT_RESTORED, _source(), {"revision": _revision})
	for unit_id in _units:
		var unit: CoreLoopUnit = _units[unit_id]
		if unit.reached_outcomes().size() < (CoreLoopUnit.OUTCOMES.get(unit.mechanic, []) as Array).size():
			_recorder.set_unit_context(unit_id, unit.mechanic)
			_recorder.record(ChapterRunRecorder.EVENT_PROTOTYPE_RESUMED, _source(), {"case_id": str(_config["case_def"].get("id", ""))})
	_recorder.set_unit_context("", "")


## Writes any unsaved draft/investigation change to disk — the owner calls
## this on quit, return-to-menu and window close. No-op when nothing changed.
func flush(reason: String = "flush") -> void:
	if _active and _error == "" and _is_synced() and _dirty:
		_checkpoint(reason)


## Starts the same case over as a brand-new run (Result screen "Restart", the
## game menu's New Game). The outgoing run is recorded as restarted — and as
## abandoned when it never completed — before it is replaced.
func restart_chapter() -> void:
	var case_id: String = CaseManager.get_current_case_id()
	if _active and _is_synced():
		_recorder.set_unit_context("", "")
		if not _completed:
			_recorder.record(ChapterRunRecorder.EVENT_CHAPTER_ABANDONED, _source(), {"phase": get_phase_id()})
		_recorder.record(ChapterRunRecorder.EVENT_CHAPTER_RESTARTED, _source(), {"previous_completed": _completed})
	SaveManager.new_game(case_id)
	reload_from_game_state()


# ---------------------------------------------------------------------------
# Queries (read-only; presenters and screens use these)

func is_active() -> bool:
	_resync_if_needed()
	return _active


func has_error() -> bool:
	return _error != ""


func get_error() -> String:
	return _error


func is_completed() -> bool:
	return _completed


func get_run_id() -> String:
	return _run_id


func get_chapter_id() -> String:
	return _chapter_id


func get_recorder() -> ChapterRunRecorder:
	return _recorder


func get_session() -> DeductionSession:
	return _session


func get_case_def() -> Dictionary:
	return _config.get("case_def", {})


func get_loop() -> Dictionary:
	return _config.get("loop", {})


func get_revision() -> int:
	return _revision


func get_phase_index() -> int:
	return _phase_index


## The current phase id, or PHASE_COMPLETED once the chapter is done.
func get_phase_id() -> String:
	var phase: Dictionary = get_current_phase()
	return PHASE_COMPLETED if phase.is_empty() else str(phase.get("id", ""))


func get_current_phase() -> Dictionary:
	var phases: Array = _config.get("phases", [])
	return phases[_phase_index] if _phase_index >= 0 and _phase_index < phases.size() else {}


func is_briefing() -> bool:
	return _active and _error == "" and str(get_current_phase().get("kind", "")) == PHASE_KIND_BRIEFING


## The unit the current phase is about ("" for briefing/completed).
func get_current_unit_id() -> String:
	return str(get_current_phase().get("unit", ""))


func get_unit_definition(unit_id: String) -> Dictionary:
	return (_config.get("units", {}) as Dictionary).get(unit_id, {})


## The live unit (null until first opened). Presenters read it; every
## mutation goes through perform().
func get_unit(unit_id: String) -> CoreLoopUnit:
	return _units.get(unit_id)


func get_open_unit_id() -> String:
	return _open_unit_id


## The highest help level actually used anywhere in this run — stored and
## recorded, never shown to the player as a grade (1.15B, "Run result").
func get_run_help_result() -> String:
	return _run_help_result


## {"available": bool, "reason": REASON_*|""} — whether `unit_id` can be
## opened right now. A unit is offered only while its phase is current and its
## content-authored offer_condition holds.
func get_unit_status(unit_id: String) -> Dictionary:
	if not _active:
		return _status(false, REASON_INACTIVE)
	if _error != "":
		return _status(false, REASON_ERROR)
	if _completed:
		return _status(false, REASON_COMPLETED)
	var definition: Dictionary = get_unit_definition(unit_id)
	if definition.is_empty():
		return _status(false, REASON_UNKNOWN_UNIT)
	if unit_id != get_current_unit_id():
		var unit: CoreLoopUnit = _units.get(unit_id)
		var resolved: bool = unit != null and unit.has_reached(CoreLoopUnit.OUTCOME_RESOLVED)
		return _status(false, REASON_UNIT_RESOLVED if resolved else REASON_UNIT_NOT_CURRENT)
	if not ConditionEvaluator.evaluate(definition.get("offer_condition")):
		return _status(false, REASON_UNIT_LOCKED)
	return _status(true, "")


## Applied consequences in the order they happened — the player-safe
## "findings" the Case File and Result screen narrate. Each entry:
## {"unit": id, "outcome": id, "summary": translation key, "resolved_by"}.
func get_findings() -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	for phase in _config.get("phases", []):
		var unit_id: String = str(phase.get("unit", ""))
		if unit_id == "":
			continue
		var consequence: Dictionary = _consequence(unit_id, str(phase.get("completes_on", "")))
		var applied: Dictionary = _applied.get(str(consequence.get("id", "")), {})
		if applied.is_empty():
			continue
		findings.append({
			"unit": unit_id, "outcome": str(applied.get("outcome", "")), "summary": str(consequence.get("summary", "")),
			"resolved_by": str(applied.get("resolved_by", "")),
		})
	return findings


func is_consequence_applied(consequence_id: String) -> bool:
	return _applied.has(consequence_id)


## Inventory evidence ids the player holds, in acquisition order.
func get_acquired_evidence() -> Array[String]:
	return GameState.evidence_inventory.duplicate()


func is_case_file_evidence_opened(evidence_id: String) -> bool:
	return _case_file_opened.has(evidence_id)


func is_case_file_evidence_pinned(evidence_id: String) -> bool:
	return _case_file_pinned.has(evidence_id)


# ---------------------------------------------------------------------------
# Commands

## Leaves the briefing phase. Refused anywhere else.
func acknowledge_briefing() -> Dictionary:
	var refusal: String = _command_refusal()
	if refusal != "":
		return _refused(refusal)
	if not is_briefing():
		return _refused(REASON_NOT_BRIEFING)
	_begin_command()
	_recorder.record("briefing_acknowledged", _source(), {"phase": get_phase_id()})
	_phase_index += 1
	_record_phase_entered()
	_advance_phases()
	_checkpoint("briefing_acknowledged")
	_end_command()
	phase_changed.emit(get_phase_id())
	state_changed.emit()
	return {"ok": true, "reason": ""}


## Opens (creating on first use) the current phase's unit. Refused — before
## any evaluator is touched — for a unit that isn't current or isn't offered
## yet; the reason is safe to show through CoreLoopPresenter.
func open_unit(unit_id: String) -> Dictionary:
	var refusal: String = _command_refusal()
	if refusal != "":
		return _refused(refusal)
	var status: Dictionary = get_unit_status(unit_id)
	if status.get("available", false) != true:
		_recorder.record(ChapterRunRecorder.EVENT_UNIT_REFUSED, _source(), {"unit_id": unit_id, "command": "open", "reason": status.get("reason", "")})
		return _refused(str(status.get("reason", "")))
	_begin_command()
	_recorder.set_unit_context(unit_id, str(get_unit_definition(unit_id).get("mechanic", "")))
	var created: bool = false
	if not _units.has(unit_id):
		var unit: CoreLoopUnit = CoreLoopUnit.create(get_unit_definition(unit_id), get_case_def(), _session, _recorder, _evidence_pool_for(unit_id, GameState.evidence_inventory))
		if unit == null:
			_end_command()
			_fail(REASON_CONTENT_ERROR, "unit '%s' could not start" % unit_id)
			return _refused(REASON_CONTENT_ERROR)
		_units[unit_id] = unit
		created = true
	else:
		# Evidence acquired since the unit was last open joins its pool now.
		(_units[unit_id] as CoreLoopUnit).set_evidence_pool(_evidence_pool_for(unit_id, GameState.evidence_inventory))
	_open_unit_id = unit_id
	_recorder.record(ChapterRunRecorder.EVENT_MECHANIC_OPENED, _source(), {"created": created})
	if created:
		_checkpoint("unit_created")
	else:
		_write_snapshot()
		_dirty = true
	_end_command()
	state_changed.emit()
	return {"ok": true, "reason": ""}


## The player left the mechanic screen. Its draft is already in the snapshot;
## this also writes it to disk (drafts are checkpointed on close, 1.15B §13.2).
func close_unit() -> void:
	if _open_unit_id == "" or not _active or not _is_synced():
		_open_unit_id = ""
		return
	_begin_command()
	_recorder.set_unit_context(_open_unit_id, str(get_unit_definition(_open_unit_id).get("mechanic", "")))
	_recorder.record(ChapterRunRecorder.EVENT_MECHANIC_CLOSED, _source(), {"feedback_open": _units.has(_open_unit_id) and (_units[_open_unit_id] as CoreLoopUnit).is_feedback_open()})
	_open_unit_id = ""
	_checkpoint("mechanic_closed")
	_end_command()
	state_changed.emit()


## Runs one whitelisted mechanic command on the current phase's unit and maps
## what it reached to progression. Returns {"ok", "reason", "kind", "result"
## (the controller's own result), "consequences" (ids applied by THIS
## command), "phase_changed", "completed"}.
func perform(unit_id: String, command: String, args: Array = []) -> Dictionary:
	var refusal: String = _unit_command_refusal(unit_id)
	if refusal != "":
		return _refused(refusal)
	var unit: CoreLoopUnit = _units[unit_id]
	unit.set_evidence_pool(_evidence_pool_for(unit_id, GameState.evidence_inventory))
	_begin_command()
	_recorder.set_unit_context(unit_id, unit.mechanic)
	var outcome: Dictionary = unit.perform(command, args)
	if outcome.get("ok", false) != true:
		_recorder.record(ChapterRunRecorder.EVENT_UNIT_REFUSED, _source(), {"command": command, "reason": outcome.get("reason", "")})
		_end_command()
		return _refused(str(outcome.get("reason", "")))

	var applied_now: Array[String] = _apply_reached_consequences(unit)
	# Before advancing: a chapter_completed observation must already carry the
	# help this very command used (e.g. a partner-resolved final claim).
	_update_run_help_result()
	var phase_before: int = _phase_index
	_advance_phases()
	if _error != "":
		# Content defect found mid-command (see _advance_phases): nothing of
		# this half-finished transition is checkpointed.
		_end_command()
		state_changed.emit()
		return _refused(REASON_CONTENT_ERROR)
	var kind: String = str(outcome.get("kind", ""))
	if kind == CoreLoopUnit.KIND_FORMAL or kind == CoreLoopUnit.KIND_HELP or not applied_now.is_empty() or _phase_index != phase_before:
		_checkpoint(command)
	else:
		_write_snapshot()
		_dirty = true
	_end_command()
	if _phase_index != phase_before:
		phase_changed.emit(get_phase_id())
	if _completed and _phase_index != phase_before:
		chapter_completed.emit()
	state_changed.emit()
	return {
		"ok": true, "reason": "", "kind": kind, "result": outcome.get("result"), "consequences": applied_now,
		"phase_changed": _phase_index != phase_before, "completed": _completed,
	}


## "Continue" on the unit's shown feedback. Allowed after the unit's own
## outcome (feedback of a just-resolved unit must still be dismissable).
func dismiss_feedback(unit_id: String) -> Dictionary:
	_resync_if_needed()
	if not _active or _error != "":
		return _refused(REASON_ERROR if _active else REASON_INACTIVE)
	var unit: CoreLoopUnit = _units.get(unit_id)
	if unit == null:
		return _refused(REASON_UNIT_NOT_STARTED)
	_begin_command()
	_recorder.set_unit_context(unit_id, unit.mechanic)
	unit.dismiss_feedback()
	_checkpoint("feedback_acknowledged")
	_end_command()
	state_changed.emit()
	return {"ok": true, "reason": ""}


## The Case File's "read this evidence": remembered for the run and — for
## evidence linked to the chapter's deduction case — marked opened in the
## shared session, so the mechanics show it as already read.
func open_case_file_evidence(evidence_id: String) -> Dictionary:
	var refusal: String = _command_refusal(true)
	if refusal != "":
		return _refused(refusal)
	if not GameState.has_evidence(evidence_id):
		return _refused(REASON_UNKNOWN_EVIDENCE)
	if _case_file_opened.has(evidence_id):
		return {"ok": true, "reason": ""}
	_begin_command()
	_case_file_opened.append(evidence_id)
	var linked: String = str((_config.get("evidence_links", {}) as Dictionary).get(evidence_id, ""))
	if linked != "":
		_session.mark_evidence_opened(linked)
	_recorder.record(ChapterRunRecorder.EVENT_CASE_FILE_EVIDENCE_OPENED, _source(), {"evidence_id": evidence_id})
	_write_snapshot()
	_dirty = true
	_end_command()
	state_changed.emit()
	return {"ok": true, "reason": ""}


## Pins/unpins an acquired evidence item in the Case File (free, persistent).
func set_case_file_evidence_pinned(evidence_id: String, pinned: bool) -> Dictionary:
	var refusal: String = _command_refusal(true)
	if refusal != "":
		return _refused(refusal)
	if not GameState.has_evidence(evidence_id):
		return _refused(REASON_UNKNOWN_EVIDENCE)
	if pinned == _case_file_pinned.has(evidence_id):
		return {"ok": true, "reason": ""}
	_begin_command()
	if pinned:
		_case_file_pinned.append(evidence_id)
	else:
		_case_file_pinned.erase(evidence_id)
	_recorder.record("case_file_evidence_pinned", _source(), {"evidence_id": evidence_id, "pinned": pinned})
	_write_snapshot()
	_dirty = true
	_end_command()
	state_changed.emit()
	return {"ok": true, "reason": ""}


## Exports the recording and its evaluation summary — observational only; a
## failure is returned, never raised, and changes nothing about the run.
func export_recording(dir_path: String = "") -> Dictionary:
	return _recorder.export_with_summary(dir_path)


# ---------------------------------------------------------------------------
# Snapshot

func to_dict() -> Dictionary:
	var units: Dictionary = {}
	for unit_id in _units:
		units[unit_id] = (_units[unit_id] as CoreLoopUnit).to_dict()
	return {
		"format": SNAPSHOT_FORMAT,
		"run_id": _run_id,
		"revision": _revision,
		"chapter_id": _chapter_id,
		"deduction_case": str(get_case_def().get("id", "")),
		"phase_index": _phase_index,
		"phase_id": get_phase_id(),
		"completed": _completed,
		"session": _session.to_dict() if _session != null else {},
		"units": units,
		"applied_consequences": _applied.duplicate(true),
		"run_help_result": _run_help_result,
		"open_unit": _open_unit_id,
		"case_file": {"opened": _case_file_opened.duplicate(), "pinned": _case_file_pinned.duplicate()},
	}


## Full validation of a SAVE's chapter run, without touching GameState or the
## live runtime — what SaveManager.inspect_save() runs before accepting a
## file. `state` is a migrated save "state" dictionary. {"ok", "reason"}.
static func validate_snapshot(state: Dictionary) -> Dictionary:
	var snapshot: Variant = state.get("chapter_run", {})
	if typeof(snapshot) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "chapter_run is not an object"}
	if (snapshot as Dictionary).is_empty():
		return {"ok": true, "reason": ""}
	var variables: Variant = state.get("variables", {})
	var chapter_id: String = str((variables as Dictionary).get("current_chapter", "")) if typeof(variables) == TYPE_DICTIONARY else ""
	var evidence: Array[String] = DeductionEvaluator.string_array(state.get("evidence", []))
	var seen: Array[String] = DeductionEvaluator.string_array(state.get("seen_interactions", []))
	var parsed: Dictionary = _parse_snapshot(chapter_id, snapshot, evidence, seen, null)
	return {"ok": parsed.get("ok", false) == true, "reason": str(parsed.get("reason", ""))}


# ---------------------------------------------------------------------------
# Private — configuration

## Resolves a chapter's core_loop into lookups: {"ok", "reason", "loop",
## "case_def", "phases": Array[Dictionary], "units": id -> definition,
## "evidence_links": inventory id -> deduction evidence id}. Structural
## problems are also ContentValidator errors (CoreLoopValidator); this is the
## runtime's own defensive backstop.
static func _build_config(chapter_id: String) -> Dictionary:
	var loop: Variant = ContentDB.get_chapter(chapter_id).get("core_loop")
	if typeof(loop) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "no core_loop"}
	if PrototypeContext.count((loop as Dictionary).get("format")) != LOOP_FORMAT:
		return {"ok": false, "reason": "unsupported core_loop format"}
	var case_def: Dictionary = ContentDB.get_deduction_case(str(loop.get("deduction_case", "")))
	if case_def.is_empty():
		return {"ok": false, "reason": "unknown deduction_case"}
	var units: Dictionary = {}
	for definition in DeductionEvaluator.dict_array(loop.get("units", [])):
		if not CoreLoopUnit.MECHANICS.has(str(definition.get("mechanic", ""))) or str(definition.get("id", "")) == "":
			return {"ok": false, "reason": "malformed unit"}
		units[str(definition.get("id", ""))] = definition
	var phases: Array[Dictionary] = DeductionEvaluator.dict_array(loop.get("phases", []))
	if phases.is_empty():
		return {"ok": false, "reason": "no phases"}
	for phase in phases:
		if str(phase.get("kind", PHASE_KIND_UNIT)) == PHASE_KIND_BRIEFING:
			continue
		var definition: Dictionary = units.get(str(phase.get("unit", "")), {})
		if definition.is_empty() or _consequence_in(definition, str(phase.get("completes_on", ""))).is_empty():
			return {"ok": false, "reason": "phase '%s' has no completing consequence" % phase.get("id", "")}
	var links: Variant = loop.get("evidence_links", {})
	return {
		"ok": true, "reason": "", "loop": loop, "case_def": case_def, "phases": phases, "units": units,
		"evidence_links": links if typeof(links) == TYPE_DICTIONARY else {},
	}


static func _consequence_in(unit_definition: Dictionary, outcome: String) -> Dictionary:
	var consequences: Variant = unit_definition.get("consequences", {})
	if typeof(consequences) != TYPE_DICTIONARY or typeof((consequences as Dictionary).get(outcome)) != TYPE_DICTIONARY:
		return {}
	return (consequences as Dictionary)[outcome]


func _consequence(unit_id: String, outcome: String) -> Dictionary:
	return _consequence_in(get_unit_definition(unit_id), outcome)


## The mechanic's authored pool, narrowed to deduction evidence the player
## actually holds (inventory ids mapped through evidence_links), authored
## order. C has no pool.
static func _pool_for(config: Dictionary, unit_id: String, inventory: Array) -> Array[String]:
	var definition: Dictionary = (config.get("units", {}) as Dictionary).get(unit_id, {})
	var layer: String = {"clue_connection": "prototype_b", "statement_contradiction": "prototype_a"}.get(str(definition.get("mechanic", "")), "")
	var pool: Array[String] = []
	if layer == "":
		return pool
	var held: Dictionary = {}
	var links: Dictionary = config.get("evidence_links", {})
	for evidence_id in inventory:
		var linked: String = str(links.get(str(evidence_id), ""))
		if linked != "":
			held[linked] = true
	for deduction_evidence_id in DeductionEvaluator.string_array((config["case_def"] as Dictionary).get(layer, {}).get("evidence_pool", [])):
		if held.has(deduction_evidence_id):
			pool.append(deduction_evidence_id)
	return pool


func _evidence_pool_for(unit_id: String, inventory: Array) -> Array[String]:
	return _pool_for(_config, unit_id, inventory)


# ---------------------------------------------------------------------------
# Private — restore/validation (one code path for both)

## Parses and cross-validates a chapter-run snapshot against content and the
## rest of the save's state. Everything the 1.15B atomicity table forbids is
## rejected here: a consumed failure without its signature (the controllers'
## own restore), a resolved unit without its applied consequence (and the
## reverse), a phase that doesn't match what was applied, a unit that exists
## before its phase, a completed run whose chapter isn't marked complete, a
## run help result lower than the help the units actually used.
static func _parse_snapshot(chapter_id: String, snapshot: Dictionary, inventory: Array, seen: Array, recorder: ChapterRunRecorder) -> Dictionary:
	if PrototypeContext.count(snapshot.get("format")) != SNAPSHOT_FORMAT:
		return _parse_error("unsupported snapshot format")
	if str(snapshot.get("chapter_id", "")) != chapter_id or chapter_id == "":
		return _parse_error("snapshot belongs to another chapter")
	var config: Dictionary = _build_config(chapter_id)
	if config.get("ok", false) != true:
		return _parse_error("chapter content unusable: %s" % config.get("reason", ""))
	var case_def: Dictionary = config["case_def"]
	if str(snapshot.get("deduction_case", "")) != str(case_def.get("id", "")):
		return _parse_error("snapshot belongs to another deduction case")
	var run_id: Variant = snapshot.get("run_id", "")
	var revision: int = PrototypeContext.count(snapshot.get("revision"))
	var phase_index: int = PrototypeContext.count(snapshot.get("phase_index"))
	var phases: Array[Dictionary] = config["phases"]
	if not (run_id is String) or run_id == "" or revision < 0 or phase_index < 0 or phase_index > phases.size():
		return _parse_error("malformed run identity or phase")
	var completed: Variant = snapshot.get("completed", false)
	if typeof(completed) != TYPE_BOOL or completed != (phase_index == phases.size()):
		return _parse_error("completed flag disagrees with the phase")
	if completed and not seen.has(CaseManager.chapter_completion_marker(chapter_id)):
		return _parse_error("completed run but the chapter is not marked complete")

	var session := DeductionSession.new(str(case_def.get("id", "")))
	if not session.load_dict(snapshot.get("session")) or session.case_id != str(case_def.get("id", "")):
		return _parse_error("malformed deduction session")

	var raw_units: Variant = snapshot.get("units", {})
	if typeof(raw_units) != TYPE_DICTIONARY:
		return _parse_error("malformed units")
	var units: Dictionary = {}
	for unit_id in raw_units:
		var definition: Dictionary = (config["units"] as Dictionary).get(str(unit_id), {})
		if definition.is_empty():
			return _parse_error("unknown unit '%s'" % unit_id)
		if _first_phase_of(phases, str(unit_id)) > phase_index:
			return _parse_error("unit '%s' exists before its phase" % unit_id)
		var unit: CoreLoopUnit = CoreLoopUnit.restore(definition, case_def, session, recorder, _pool_for(config, str(unit_id), inventory), raw_units[unit_id])
		if unit == null:
			return _parse_error("unit '%s' snapshot rejected" % unit_id)
		units[str(unit_id)] = unit

	var raw_applied: Variant = snapshot.get("applied_consequences", {})
	if typeof(raw_applied) != TYPE_DICTIONARY:
		return _parse_error("malformed applied consequences")
	var applied: Dictionary = {}
	for consequence_id in raw_applied:
		var entry: Variant = raw_applied[consequence_id]
		if typeof(entry) != TYPE_DICTIONARY:
			return _parse_error("malformed applied consequence")
		var unit_id: String = str(entry.get("unit", ""))
		var outcome: String = str(entry.get("outcome", ""))
		var consequence: Dictionary = _consequence_in((config["units"] as Dictionary).get(unit_id, {}), outcome)
		if str(consequence.get("id", "")) != str(consequence_id):
			return _parse_error("applied consequence '%s' is not the one content defines" % consequence_id)
		var unit: CoreLoopUnit = units.get(unit_id)
		if unit == null or not unit.has_reached(outcome):
			return _parse_error("consequence '%s' applied without its producing resolution" % consequence_id)
		if not ["", ResolutionPolicy.RESOLVED_BY_PLAYER, ResolutionPolicy.RESOLVED_BY_PARTNER].has(entry.get("resolved_by", "")):
			return _parse_error("malformed attribution")
		applied[str(consequence_id)] = (entry as Dictionary).duplicate(true)
	for unit_id in units:
		for outcome in (units[unit_id] as CoreLoopUnit).reached_outcomes():
			var consequence: Dictionary = _consequence_in((config["units"] as Dictionary)[unit_id], outcome)
			if not consequence.is_empty() and not applied.has(str(consequence.get("id", ""))):
				return _parse_error("unit '%s' reached '%s' but its consequence was never applied" % [unit_id, outcome])

	for i in phases.size():
		var phase: Dictionary = phases[i]
		if str(phase.get("kind", PHASE_KIND_UNIT)) == PHASE_KIND_BRIEFING:
			continue
		var consequence: Dictionary = _consequence_in((config["units"] as Dictionary)[str(phase.get("unit", ""))], str(phase.get("completes_on", "")))
		var is_applied: bool = applied.has(str(consequence.get("id", "")))
		if (i < phase_index) != is_applied:
			return _parse_error("phase '%s' does not match what was applied" % phase.get("id", ""))

	var help: Variant = snapshot.get("run_help_result", "")
	if not (help is String and ResolutionPolicy.TIERS.has(help)):
		return _parse_error("malformed run help result")
	for unit_id in units:
		if ResolutionPolicy.run_resolution_result_rank((units[unit_id] as CoreLoopUnit).help_result()) > ResolutionPolicy.run_resolution_result_rank(help):
			return _parse_error("run help result lower than the help actually used")

	var open_unit: Variant = snapshot.get("open_unit", "")
	if not (open_unit is String) or (open_unit != "" and not units.has(open_unit)):
		return _parse_error("malformed open unit")
	var case_file: Variant = snapshot.get("case_file", {})
	if typeof(case_file) != TYPE_DICTIONARY or not PrototypeContext.is_string_list(case_file.get("opened", [])) or not PrototypeContext.is_string_list(case_file.get("pinned", [])):
		return _parse_error("malformed case file state")

	return {
		"ok": true, "reason": "", "run_id": run_id, "revision": revision, "phase_index": phase_index, "completed": completed,
		"session": session, "units": units, "applied": applied, "run_help_result": help, "open_unit": open_unit,
		"case_file_opened": DeductionEvaluator.string_array(case_file.get("opened", [])),
		"case_file_pinned": DeductionEvaluator.string_array(case_file.get("pinned", [])),
	}


static func _first_phase_of(phases: Array[Dictionary], unit_id: String) -> int:
	for i in phases.size():
		if str(phases[i].get("unit", "")) == unit_id:
			return i
	return phases.size()


static func _parse_error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


# ---------------------------------------------------------------------------
# Private — progression

## Applies every newly reached outcome's consequence exactly once, through
## EffectRunner (the project's one effect vocabulary). The applied set is
## persisted, so a reload never runs a consequence again.
func _apply_reached_consequences(unit: CoreLoopUnit) -> Array[String]:
	var applied_now: Array[String] = []
	for outcome in unit.reached_outcomes():
		var consequence: Dictionary = _consequence(unit.unit_id, outcome)
		var consequence_id: String = str(consequence.get("id", ""))
		if consequence_id == "" or _applied.has(consequence_id):
			continue
		var effects: Array = consequence.get("effects", [])
		var already_satisfied: int = _count_satisfied_effects(effects)
		_applied[consequence_id] = {"unit": unit.unit_id, "outcome": outcome, "resolved_by": unit.resolved_by(outcome), "phase": get_phase_id()}
		EffectRunner.run(effects)
		_recorder.record(ChapterRunRecorder.EVENT_CONSEQUENCE_APPLIED, _source(), {
			"consequence": consequence_id, "outcome": outcome, "resolved_by": unit.resolved_by(outcome),
			"effect_count": effects.size(), "already_satisfied_effects": already_satisfied,
		})
		applied_now.append(consequence_id)
	return applied_now


## How many of a consequence's effects would change nothing (the target is
## already unlocked) — recorded as a diagnostic, never altering behavior.
static func _count_satisfied_effects(effects: Array) -> int:
	var count := 0
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		match str(effect.get("type", "")):
			"set_flag":
				if GameState.flags.has(str(effect.get("flag", ""))) and GameState.get_flag(str(effect.get("flag", ""))) == (effect.get("value", true) == true):
					count += 1
			"add_evidence":
				if GameState.has_evidence(str(effect.get("evidence_id", ""))):
					count += 1
			"mark_interaction_complete":
				if GameState.has_seen("custom:%s" % effect.get("id", "")):
					count += 1
	return count


## Moves past every phase whose completing consequence is applied. After the
## last authored phase, the run is complete only once CaseManager agrees the
## chapter completed (its completion_event fired from the final consequence);
## otherwise the content is broken — fail loudly, never mutate around it.
func _advance_phases() -> void:
	var phases: Array = _config.get("phases", [])
	while not _completed and _phase_index < phases.size():
		var phase: Dictionary = phases[_phase_index]
		if str(phase.get("kind", PHASE_KIND_UNIT)) == PHASE_KIND_BRIEFING:
			return
		var consequence: Dictionary = _consequence(str(phase.get("unit", "")), str(phase.get("completes_on", "")))
		if not _applied.has(str(consequence.get("id", ""))):
			return
		_phase_index += 1
		if _phase_index < phases.size():
			_record_phase_entered()
	if _phase_index >= phases.size() and not _completed:
		if not CaseManager.is_chapter_complete(_chapter_id):
			_fail(REASON_CONTENT_ERROR, "chapter '%s' finished every phase but its completion_event never fired" % _chapter_id)
			return
		_completed = true
		_open_unit_id = ""
		_recorder.set_unit_context("", "")
		_recorder.record(ChapterRunRecorder.EVENT_CHAPTER_COMPLETED, _source(), {
			"run_help_result": _run_help_result, "findings": get_findings().size(),
		})


func _update_run_help_result() -> void:
	var best: int = ResolutionPolicy.run_resolution_result_rank(_run_help_result)
	for unit in _units.values():
		best = maxi(best, ResolutionPolicy.run_resolution_result_rank((unit as CoreLoopUnit).help_result()))
	if best > ResolutionPolicy.run_resolution_result_rank(_run_help_result):
		var previous: String = _run_help_result
		_run_help_result = ResolutionPolicy.TIERS[best]
		_recorder.record(ChapterRunRecorder.EVENT_RUN_HELP_RESULT_CHANGED, _source(), {"from": previous, "to": _run_help_result})


func _record_phase_entered() -> void:
	_recorder.record(ChapterRunRecorder.EVENT_PHASE_ENTERED, _source(), {"phase": get_phase_id(), "phase_index": _phase_index})


# ---------------------------------------------------------------------------
# Private — checkpoints and guards

func _write_snapshot() -> void:
	_revision += 1
	GameState.set_chapter_run(to_dict())
	_synced_key = _snapshot_key(GameState.chapter_run)


## One atomic checkpoint: the snapshot (and everything else GameState holds)
## written in a single SaveManager.save_game(). A failed write is recorded and
## signalled — gameplay continues; the in-memory run stays authoritative.
func _checkpoint(reason: String) -> bool:
	_write_snapshot()
	_dirty = false
	var ok: bool = SaveManager.save_game()
	_recorder.record(ChapterRunRecorder.EVENT_CHECKPOINT_SAVED if ok else ChapterRunRecorder.EVENT_CHECKPOINT_FAILED, _source(), {"reason": reason, "revision": _revision})
	if not _in_command:
		_recorder.commit_transaction(_revision)
	if not ok:
		checkpoint_failed.emit()
	return ok


func _begin_command() -> void:
	_in_command = true
	_recorder.begin_transaction()


func _end_command() -> void:
	_in_command = false
	_recorder.commit_transaction(_revision)
	_recorder.set_unit_context("", "")


## "" when a run-level command may proceed, else why not. Case File reading is
## still allowed on a completed run (`allow_completed`).
func _command_refusal(allow_completed: bool = false) -> String:
	_resync_if_needed()
	if not _active:
		return REASON_INACTIVE
	if _error != "":
		return REASON_ERROR
	if _completed and not allow_completed:
		return REASON_COMPLETED
	return ""


func _unit_command_refusal(unit_id: String) -> String:
	var refusal: String = _command_refusal()
	if refusal != "":
		return refusal
	if get_unit_definition(unit_id).is_empty():
		return REASON_UNKNOWN_UNIT
	if unit_id != get_current_unit_id():
		return REASON_UNIT_NOT_CURRENT
	if not _units.has(unit_id):
		return REASON_UNIT_NOT_STARTED
	return ""


func _is_synced() -> bool:
	return _snapshot_key(GameState.chapter_run) == _synced_key


static func _snapshot_key(snapshot: Dictionary) -> String:
	return "%s#%d" % [str(snapshot.get("run_id", "")), PrototypeContext.count(snapshot.get("revision"))]


func _needs_reload() -> bool:
	var chapter_id: String = CaseManager.get_current_chapter_id()
	var wants_active: bool = is_core_loop_chapter(chapter_id)
	if wants_active != _active:
		return true
	if not _active:
		return false
	return chapter_id != _chapter_id or not _is_synced()


func _resync_if_needed() -> void:
	if not _in_command and _needs_reload():
		reload_from_game_state()


func _reset_fields() -> void:
	_active = false
	_error = ""
	_chapter_id = ""
	_config = {}
	_run_id = ""
	_revision = 0
	_phase_index = 0
	_completed = false
	_session = null
	_units = {}
	_applied = {}
	_run_help_result = ResolutionPolicy.TIER_INDEPENDENT
	_open_unit_id = ""
	_case_file_opened = []
	_case_file_pinned = []
	_dirty = false
	_in_command = false
	_synced_key = ""


## A content or snapshot defect that makes required progression impossible:
## loud in debug/CI (push_error), a safe generic message in the UI, and the
## run is frozen rather than mutated around the defect.
func _fail(reason: String, detail: String) -> void:
	_error = reason
	push_error("ChapterRuntime: %s" % detail)
	if _recorder.is_buffering():
		_recorder.commit_transaction(_revision)


func _source() -> String:
	return DeductionLabRecorder.SOURCE_PLAYER_PREVIEW


static func _status(available: bool, reason: String) -> Dictionary:
	return {"available": available, "reason": reason}


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "kind": "", "result": null, "consequences": [], "phase_changed": false, "completed": false}


# ---------------------------------------------------------------------------
# Observation of normal investigation (never a correctness oracle, never
# replayed on restore — only while this runtime is in sync with GameState).

func _observing() -> bool:
	return _active and _error == "" and _run_id != "" and _is_synced()


func _queue_observation(event_type: String, payload: Dictionary) -> void:
	if not _in_command and not _recorder.is_buffering():
		_recorder.begin_transaction()
	_recorder.record(event_type, _source(), payload)


func _on_evidence_added(evidence_id: String) -> void:
	if not _observing():
		return
	_queue_observation(ChapterRunRecorder.EVENT_EVIDENCE_ACQUIRED, {"evidence_id": evidence_id, "location": GameState.current_location})
	_dirty = true
	if not _in_command and not DialogueManager.is_active:
		_checkpoint("evidence_acquired")


func _on_location_changed(location_id: String) -> void:
	if not _observing() or _in_command:
		return
	_queue_observation(ChapterRunRecorder.EVENT_LOCATION_VISITED, {"location": location_id})
	_checkpoint("location_changed")


func _on_interaction_seen(key: String) -> void:
	if not _observing() or key.begins_with("chapter_complete:") or key.begins_with("case_complete:"):
		return
	_queue_observation(ChapterRunRecorder.EVENT_INTERACTION_COMPLETED, {"key": key})
	_dirty = true


## Evidence and interactions picked up during a dialogue are checkpointed when
## it ends — a checkpoint mid-dialogue would persist half of its actions.
func _on_dialogue_ended() -> void:
	if _observing() and not _in_command and _dirty:
		_checkpoint("interaction")


## Deferred: CaseManager.start_case() replaces GameState and only THEN
## activates the chapter, so the reload waits until the whole replacement is
## done. perform()/queries resync immediately anyway if anything runs first.
func _on_state_replaced() -> void:
	_resync_if_needed.call_deferred()
