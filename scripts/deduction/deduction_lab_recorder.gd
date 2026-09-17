class_name DeductionLabRecorder
extends RefCounted
## Minimal, debug-only local playtest recorder for the Deduction Lab
## (Milestone 1.10 — see docs/deduction-lab.md). Off by default; owned by the
## Lab scene/controller, NOT an autoload, NOT a global analytics system: no
## network calls, no SDK, no player/machine identity. Connects to
## DeductionSession's own signals (docs/deduction-system.md,
## "Instrumentation") rather than reimplementing what "evidence opened" or
## "claim resolved" mean.
##
## The clock and session-id generator are injectable (constructor params) so
## tests get deterministic, controllable sequences instead of depending on
## real wall-clock time — see docs/deduction-lab.md, "Recorder schema".

## The outer envelope schema — session_id/case_id/prototype/locale/
## started_at_utc/events, plus every event's own sequence/elapsed_ms/type/
## source/payload shape. Unchanged since Milestone 1.10; a new event TYPE or
## payload key never requires bumping this on its own (see EVENT_SCHEMA_VERSION).
const SCHEMA_VERSION := 1
## The event VOCABULARY a consumer must know to interpret every event's
## "type" and "payload" correctly — which types exist and what each payload
## key means. Milestone 1.14 replaced Prototype B's round/connection events
## with theory-batch events and added the whole resolution-policy vocabulary;
## Milestone 1.14.1 renamed several of THOSE payload keys and one event type
## for clarity (docs/resolution-policy.md, "Local unit state vs. run
## result"). Both are real vocabulary breaks, so this bumped from 1 to 2 —
## see docs/deduction-lab.md, "Recorder schema", for the full v1/v2 diff. A
## consumer decides how to parse "type"/"payload" from THIS number, never
## from SCHEMA_VERSION, which never changes for a vocabulary-only edit.
const EVENT_SCHEMA_VERSION := 2
const DEFAULT_EXPORT_DIR := "user://deduction_lab_recordings"

const SOURCE_PLAYER_PREVIEW := "player_preview"
const SOURCE_AUTHOR_DEBUG := "author_debug"

const EVENT_SESSION_STARTED := "session_started"
const EVENT_MODE_SWITCHED := "mode_switched"
const EVENT_EVIDENCE_OPENED := "evidence_opened"
const EVENT_HINT_REVEALED := "hint_revealed"
const EVENT_PROOF_COMMITTED := "proof_committed"
const EVENT_CLAIM_RESOLVED := "claim_resolved"
const EVENT_DEDUCTION_UNLOCKED := "deduction_unlocked"
const EVENT_CASE_SOLVED := "case_solved"
const EVENT_SESSION_RESET := "session_reset"

var _clock_fn: Callable
var _id_fn: Callable
var _recording: bool = false
var _events: Array[Dictionary] = []
var _sequence: int = 0
var _start_ticks: int = 0
var _session_id: String = ""
var _case_id: String = ""
var _prototype: String = "deduction_lab"
var _locale: String = ""
var _started_at_utc: String = ""
var _current_source: String = SOURCE_PLAYER_PREVIEW


## `clock_fn` (no args, returns an int/float of monotonic milliseconds —
## defaults to Time.get_ticks_msec) and `id_fn` (no args, returns a String —
## defaults to a locally generated, non-identifying token) are injectable for
## tests; see docs/deduction-lab.md.
func _init(clock_fn: Callable = Callable(), id_fn: Callable = Callable()) -> void:
	_clock_fn = clock_fn if clock_fn.is_valid() else Callable(Time, "get_ticks_msec")
	_id_fn = id_fn if id_fn.is_valid() else Callable(self, "_default_session_id")


func _default_session_id() -> String:
	return "dbg-%d-%d" % [Time.get_unix_time_from_system(), randi() % 1000000]


func is_recording() -> bool:
	return _recording


func get_session_id() -> String:
	return _session_id


func get_events() -> Array[Dictionary]:
	return _events.duplicate(true)


## Which source ("player_preview" or "author_debug") the NEXT session-signal-
## driven event should be tagged with — the UI sets this immediately before
## calling a production API from either mode (see docs/deduction-lab.md,
## "Author debug actions"), since signals alone can't say who triggered them.
func set_current_source(source: String) -> void:
	_current_source = source


func get_current_source() -> String:
	return _current_source


## Starts a fresh recording: clears any previous events, generates a new
## session id, and records the "session_started" event itself. Recording is
## off by default and only begins on an explicit call to this.
func start(case_id: String, prototype: String = "deduction_lab", locale: String = "en") -> void:
	_recording = true
	_events = []
	_sequence = 0
	_case_id = case_id
	_prototype = prototype
	_locale = locale
	_session_id = String(_id_fn.call())
	_started_at_utc = Time.get_datetime_string_from_system(true, false) + "Z"
	_start_ticks = int(_clock_fn.call())
	record(EVENT_SESSION_STARTED, _current_source, {"case_id": case_id})


## Pauses recording (no more events accepted) without discarding what was
## already captured — Export still works afterwards. Call start() again for
## a brand new recording, or clear() to empty the log first.
func stop() -> void:
	_recording = false


## Empties the event log and resets the sequence counter. Does not change
## whether recording is currently on — a Clear mid-recording simply starts
## the sequence over from the same session metadata.
func clear() -> void:
	_events = []
	_sequence = 0


## No-ops while not recording. Sequence numbers strictly increase from 1;
## elapsed_ms is however far the injected clock has moved since start() —
## non-decreasing as long as the clock itself is (exactly the contract
## Time.get_ticks_msec() already gives in production).
func record(event_type: String, source: String, payload: Dictionary = {}) -> void:
	if not _recording:
		return
	_sequence += 1
	var elapsed_ms: int = maxi(int(_clock_fn.call()) - _start_ticks, 0)
	_events.append({
		"sequence": _sequence,
		"elapsed_ms": elapsed_ms,
		"type": event_type,
		"source": source,
		"payload": payload.duplicate(true),
	})


func record_mode_switched(mode: String) -> void:
	record(EVENT_MODE_SWITCHED, _current_source, {"mode": mode})


func record_session_reset() -> void:
	record(EVENT_SESSION_RESET, _current_source, {})


# ---------------------------------------------------------------------------
# Session wiring — connects to the REAL DeductionSession signals; no deduction
# logic of any kind is reimplemented here.

## Idempotent: connecting the same session twice is a no-op, so a caller that
## reconnects defensively (e.g. after a snapshot/restore) can never end up
## double-recording every event.
func connect_session(session: DeductionSession) -> void:
	if session == null or session.evidence_opened.is_connected(_on_evidence_opened):
		return
	session.evidence_opened.connect(_on_evidence_opened)
	session.proof_committed.connect(_on_proof_committed)
	session.claim_resolved.connect(_on_claim_resolved)
	session.deduction_unlocked.connect(_on_deduction_unlocked)
	session.hint_revealed.connect(_on_hint_revealed)
	session.case_solved.connect(_on_case_solved)


func _on_evidence_opened(evidence_id: String) -> void:
	record(EVENT_EVIDENCE_OPENED, _current_source, {"evidence_id": evidence_id})


func _on_proof_committed(claim_id: String, relation: String, category: String) -> void:
	record(EVENT_PROOF_COMMITTED, _current_source, {"claim_id": claim_id, "relation": relation, "category": category})


func _on_claim_resolved(claim_id: String, status: String) -> void:
	record(EVENT_CLAIM_RESOLVED, _current_source, {"claim_id": claim_id, "status": status})


func _on_deduction_unlocked(claim_id: String) -> void:
	record(EVENT_DEDUCTION_UNLOCKED, _current_source, {"claim_id": claim_id})


func _on_hint_revealed(target_id: String, level: int) -> void:
	record(EVENT_HINT_REVEALED, _current_source, {"target_id": target_id, "level": level})


func _on_case_solved(case_id: String) -> void:
	record(EVENT_CASE_SOLVED, _current_source, {"case_id": case_id})


# ---------------------------------------------------------------------------
# Export

## The documented versioned schema (docs/deduction-lab.md, "Recorder schema").
## "schema_version" is the outer envelope (unchanged, 1); "event_schema_version"
## is the event vocabulary a consumer must match against before interpreting
## any event's "type"/"payload" (2 — see the EVENT_SCHEMA_VERSION constant).
func to_export_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"event_schema_version": EVENT_SCHEMA_VERSION,
		"session_id": _session_id,
		"case_id": _case_id,
		"prototype": _prototype,
		"locale": _locale,
		"started_at_utc": _started_at_utc,
		"events": _events.duplicate(true),
	}


## Writes to_export_dict() as pretty-printed JSON under `dir_path` (default:
## DEFAULT_EXPORT_DIR, a documented user:// folder), creating it if needed.
## Never raises — filesystem errors come back as {"success": false, ...} so
## the caller can report them instead of crashing.
func export_to_file(dir_path: String = "") -> Dictionary:
	var target_dir: String = dir_path if dir_path != "" else DEFAULT_EXPORT_DIR
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(target_dir)
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		return {"success": false, "path": "", "error": "could not create export directory %s (%s)" % [target_dir, error_string(make_dir_error)]}

	var filename: String = "%s_%s.json" % [_sanitize_filename_part(_session_id), _sanitize_filename_part(_case_id)]
	var full_path: String = target_dir.path_join(filename)
	var file: FileAccess = FileAccess.open(full_path, FileAccess.WRITE)
	if file == null:
		return {"success": false, "path": full_path, "error": "could not open %s for writing (%s)" % [full_path, error_string(FileAccess.get_open_error())]}
	file.store_string(JSON.stringify(to_export_dict(), "\t"))
	file.close()
	return {"success": true, "path": full_path, "error": ""}


## Keeps a filename safe across platforms: only letters, digits, "_" and "-"
## survive: everything else (including path separators) becomes "_".
static func _sanitize_filename_part(raw: String) -> String:
	var out := ""
	for character in raw:
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			out += character
		else:
			out += "_"
	return out if out != "" else "x"
