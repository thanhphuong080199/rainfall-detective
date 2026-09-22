class_name ChapterRunRecorder
extends DeductionLabRecorder
## The production chapter run's local, observational event log (Milestone
## 1.16 — see docs/core-loop-sandbox.md, "Recorder"). A DeductionLabRecorder
## in every respect — same envelope, same export, same schema versions, same
## "no network, no identity" stance — with exactly two additions:
##
##   * CONTEXT: every event's payload is stamped with the run id, chapter id
##     and (while a mechanic is being driven) the resolution unit and
##     mechanic, so one export can be read back unambiguously even though the
##     reused prototype controllers record their own events with no idea they
##     are inside a chapter. Keys are only ADDED — never overwriting a key the
##     event already carries — which is why the event vocabulary version does
##     not change (docs/deduction-lab.md, "Recorder schema": additive keys and
##     new event types never bump it).
##   * TRANSACTIONS: between begin_transaction() and commit_transaction(),
##     events are queued instead of logged. ChapterRuntime wraps every command
##     in one, and commits only AFTER the durable checkpoint was written — the
##     1.15B transition order (validate, evaluate, apply, checkpoint, feedback,
##     THEN observe). A failed checkpoint still commits (the log then records
##     the failure too); nothing here can block or change gameplay.
##
## Never gameplay truth: ChapterRuntime never reads anything back from this
## log, and a save never contains it.

const PROTOTYPE_TAG := "core_loop"
const EXPORT_DIR := "user://core_loop_recordings"

## Chapter-level event vocabulary (additive — see class doc).
const EVENT_CHAPTER_STARTED := "chapter_started"
const EVENT_CHAPTER_RESUMED := "chapter_resumed"
const EVENT_CHAPTER_RESTARTED := "chapter_restarted"
const EVENT_CHAPTER_COMPLETED := "chapter_completed"
const EVENT_CHAPTER_ABANDONED := "chapter_abandoned"
const EVENT_PHASE_ENTERED := "phase_entered"
const EVENT_LOCATION_VISITED := "location_visited"
const EVENT_INTERACTION_COMPLETED := "interaction_completed"
const EVENT_EVIDENCE_ACQUIRED := "evidence_acquired"
const EVENT_CASE_FILE_EVIDENCE_OPENED := "case_file_evidence_opened"
const EVENT_MECHANIC_OPENED := "mechanic_opened"
const EVENT_MECHANIC_CLOSED := "mechanic_closed"
const EVENT_UNIT_REFUSED := "unit_command_refused"
const EVENT_PROTOTYPE_RESUMED := "prototype_resumed"
const EVENT_CONSEQUENCE_APPLIED := "consequence_applied"
const EVENT_RUN_HELP_RESULT_CHANGED := "run_help_result_changed"
const EVENT_CHECKPOINT_SAVED := "checkpoint_saved"
const EVENT_CHECKPOINT_FAILED := "checkpoint_failed"
const EVENT_CHECKPOINT_RESTORED := "checkpoint_restored"

var _context: Dictionary = {}
var _unit_context: Dictionary = {}
var _buffering: bool = false
var _pending: Array[Dictionary] = []


## Starts a new recording SEGMENT for a chapter run. A resumed run (after
## Continue, or after the gameplay scene was rebuilt) is a new segment linked
## to the earlier ones by the same run id — this log never survives a
## process on its own (docs/core-loop-sandbox.md, "Recorder").
##
## A restart or a reload inside the SAME gameplay scene keeps appending to the
## current recording (only the run id in the context changes) — one export
## then covers every run the player went through, exactly like a debug
## prototype recording spanning Restarts.
func start_segment(case_id: String, run_id: String, chapter_id: String, locale: String) -> void:
	_context = {"run_id": run_id, "chapter_id": chapter_id}
	_unit_context = {}
	if is_recording():
		return
	_buffering = false
	_pending = []
	start(case_id, PROTOTYPE_TAG, locale)


## Which unit/mechanic subsequent events belong to ({} clears it).
func set_unit_context(unit_id: String, mechanic: String) -> void:
	_unit_context = {} if unit_id == "" else {"unit_id": unit_id, "mechanic": mechanic}


func begin_transaction() -> void:
	_buffering = true


## Logs every queued event in order. `transition_id` (the checkpoint's
## revision, when the command produced one) is stamped onto each so an event
## that mirrors a saved transition can be matched to it.
func commit_transaction(transition_id: int = -1) -> void:
	_buffering = false
	var queued: Array[Dictionary] = _pending
	_pending = []
	for entry in queued:
		var payload: Dictionary = entry["payload"]
		if transition_id >= 0 and not payload.has("transition"):
			payload["transition"] = transition_id
		super.record(str(entry["type"]), str(entry["source"]), payload)


func is_buffering() -> bool:
	return _buffering


func record(event_type: String, source: String, payload: Dictionary = {}) -> void:
	var enriched: Dictionary = payload.duplicate(true)
	for key in _context:
		if not enriched.has(key):
			enriched[key] = _context[key]
	for key in _unit_context:
		if not enriched.has(key):
			enriched[key] = _unit_context[key]
	if _buffering:
		_pending.append({"type": event_type, "source": source, "payload": enriched})
		return
	super.record(event_type, source, enriched)


## Writes the raw log and its PrototypeEvaluationSummary digest side by side
## under `dir_path` (default EXPORT_DIR). Returns {"success", "path",
## "summary_path", "error"} — never raises; a failure is only reported.
func export_with_summary(dir_path: String = "") -> Dictionary:
	var target: String = dir_path if dir_path != "" else EXPORT_DIR
	var raw: Dictionary = export_to_file(target)
	if raw.get("success", false) != true:
		return {"success": false, "path": raw.get("path", ""), "summary_path": "", "error": raw.get("error", "")}
	var summary: Dictionary = PrototypeEvaluationSummary.export_to_file(to_export_dict(), target)
	return {
		"success": summary.get("success", false) == true, "path": raw.get("path", ""),
		"summary_path": summary.get("path", ""), "error": summary.get("error", ""),
	}
