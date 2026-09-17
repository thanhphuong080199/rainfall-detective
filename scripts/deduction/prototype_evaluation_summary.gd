class_name PrototypeEvaluationSummary
extends RefCounted
## Milestone 1.14.2A — Prototype Evaluation Instrumentation (see
## docs/prototype-evaluation.md). A pure, autoload-free, stateless summarizer
## — the same "static helper" shape as DeductionLabPresenter/
## ResolutionPresenter — that turns a DeductionLabRecorder export
## (docs/deduction-lab.md, "Recorder schema") into a compact, human-readable
## digest of how a playtester interacted with Prototype A/B/C: submissions,
## incorrect submissions, distinct candidates tried, and how often a
## candidate that already failed was resubmitted anyway (the "blind
## trial-and-error" signal the anti-bruteforce pass, docs/resolution-policy.md,
## is meant to make an inferior strategy).
##
## Purely OBSERVATIONAL: this class only reads an already-captured event log
## after the fact. It never touches GameState, a DeductionSession, a
## ResolutionPolicy or any controller, and calling it can never change what a
## recording contains, what a prototype run does, or what any evaluator
## returns. See docs/prototype-evaluation.md, "Safeguards".
##
## One export can contain more than one RUN — a playtest facilitator starts
## recording once and a player may restart several times in that window
## (docs/deduction-lab.md, "Local playtest recorder") — so summarize() splits
## the event log at "prototype_started" boundaries and returns one entry per
## run.

## Which payload keys, on which event type, identify a "candidate" attempt —
## reusing the exact normalized identity each controller already computes to
## block a repeated failed submission (PrototypeAController._pair_key(),
## PrototypeBController._theory_key(), PrototypeCController._placement_key()/
## _claim_key()) rather than inventing a second notion of "candidate". Small
## and explicit by design (CLAUDE.md: "avoid speculative architecture") — a
## future fourth prototype-style mechanic would add one entry here, not a
## new framework.
const CANDIDATE_SIGNATURE_KEYS := {
	"attempt_submitted": ["statement_id", "evidence_id"],
	"attempt_blocked_duplicate": ["statement_id", "evidence_id"],
	"theory_batch_submitted": ["drafts"],
	"theory_blocked_duplicate": ["drafts"],
	"timeline_submitted": ["placements"],
	"timeline_blocked_duplicate": ["placements"],
	"claim_answered": ["answer", "justification_constraint_id"],
	"claim_blocked_duplicate": ["answer", "justification_constraint_id"],
}

## Recorded the instant a controller refuses to re-evaluate a candidate that
## already failed (Milestone 1.14.2A — previously these attempts were
## invisible to the recorder entirely; see docs/prototype-evaluation.md,
## "What was previously unobservable"). Never affects grading, counts or
## ResolutionPolicy state — the refusal itself is unchanged, pre-existing
## Milestone 1.14 behavior; only the fact that it happened is now recorded.
const DUPLICATE_BLOCK_EVENT_TYPES: Array[String] = [
	"attempt_blocked_duplicate", "theory_blocked_duplicate", "timeline_blocked_duplicate", "claim_blocked_duplicate",
]

## A free (never a formal commit) change to the current candidate — used for
## the "selections or candidate-solution changes" measurement.
const SELECTION_CHANGE_EVENT_TYPES: Array[String] = [
	"evidence_selected", "clue_selected", "clue_removed", "draft_selected", "event_placed", "event_moved", "event_removed", "statement_selected",
]


## `export_dict` is a DeductionLabRecorder.to_export_dict() result, or
## anything with the same "events"/"prototype"/"session_id" shape — a JSON
## file round-tripped through JSON.parse_string() works identically. Returns
## {"prototype_type", "session_id", "total_runs", "runs": [per-run summary,
## ...]}. Never raises: a malformed, empty, or non-prototype (e.g. the
## Deduction Lab's own "deduction_lab") export simply returns "total_runs": 0.
static func summarize(export_dict: Dictionary) -> Dictionary:
	var events: Array = export_dict.get("events", []) if typeof(export_dict) == TYPE_DICTIONARY else []
	var runs: Array[Dictionary] = []
	var current_slice: Array[Dictionary] = []
	var slice_has_started := false
	for raw_event in events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw_event
		var is_boundary: bool = str(event.get("type", "")) == "prototype_started"
		if is_boundary and slice_has_started:
			runs.append(_summarize_run(current_slice))
			current_slice = []
		if is_boundary:
			slice_has_started = true
		# Events before the FIRST prototype_started (e.g. session_started,
		# or a non-prototype "deduction_lab" export with no run boundary at
		# all) belong to no run and are dropped, not folded into a spurious
		# empty run.
		if slice_has_started:
			current_slice.append(event)
	if not current_slice.is_empty():
		runs.append(_summarize_run(current_slice))

	# Only a run superseded by a restart can legitimately end without
	# "completed" or "abandoned" ever being recorded for it (Restart never
	# calls abandon() first — see PrototypeAController.start()'s class doc).
	for i in runs.size() - 1:
		runs[i]["superseded_by_restart"] = not (runs[i]["completed"] or runs[i]["abandoned"])

	return {
		"prototype_type": str(export_dict.get("prototype", "")) if typeof(export_dict) == TYPE_DICTIONARY else "",
		"session_id": str(export_dict.get("session_id", "")) if typeof(export_dict) == TYPE_DICTIONARY else "",
		"total_runs": runs.size(),
		"runs": runs,
	}


## Convenience for the common developer need ("what did the run I just
## finished/abandoned look like") — {} if the export has no runs at all.
static func summarize_latest_run(export_dict: Dictionary) -> Dictionary:
	var runs: Array = summarize(export_dict).get("runs", [])
	return runs[runs.size() - 1] if not runs.is_empty() else {}


static func _summarize_run(slice: Array[Dictionary]) -> Dictionary:
	var started_payload: Dictionary = {}
	var completed_payload: Dictionary = {}
	var abandoned_payload: Dictionary = {}
	var submission_count := 0
	var incorrect_count := 0
	var duplicate_blocked_count := 0
	var selection_change_count := 0
	var hint_reveal_count := 0
	var max_hint_level := 0
	var partner_resolution_count := 0
	var last_run_resolution_result := ""
	var last_elapsed_ms := 0
	var candidate_signatures: Dictionary = {}
	var duplicate_repeat_counts: Dictionary = {}

	for event in slice:
		var event_type: String = str(event.get("type", ""))
		var payload: Dictionary = event.get("payload", {})
		last_elapsed_ms = maxi(last_elapsed_ms, int(event.get("elapsed_ms", 0)))

		match event_type:
			"prototype_started":
				if started_payload.is_empty():
					started_payload = payload
			"prototype_completed":
				completed_payload = payload
			"prototype_abandoned":
				abandoned_payload = payload
			"formal_commit_started":
				submission_count += 1
			"formal_commit_failed":
				incorrect_count += 1
			"partner_resolution_used":
				partner_resolution_count += 1
			"hint_revealed":
				hint_reveal_count += 1
				max_hint_level = maxi(max_hint_level, int(payload.get("level", 0)))

		if DUPLICATE_BLOCK_EVENT_TYPES.has(event_type):
			duplicate_blocked_count += 1
		if SELECTION_CHANGE_EVENT_TYPES.has(event_type):
			selection_change_count += 1
		if payload.has("run_resolution_result"):
			last_run_resolution_result = str(payload.get("run_resolution_result"))
		elif payload.has("run_resolution_result_after"):
			last_run_resolution_result = str(payload.get("run_resolution_result_after"))

		var signature: String = _candidate_signature(event_type, payload)
		if signature != "":
			candidate_signatures[signature] = true
			if DUPLICATE_BLOCK_EVENT_TYPES.has(event_type):
				duplicate_repeat_counts[signature] = int(duplicate_repeat_counts.get(signature, 0)) + 1

	var completed: bool = not completed_payload.is_empty()
	var abandoned: bool = not abandoned_payload.is_empty()
	var resolution_summary: Dictionary = completed_payload.get("resolution", abandoned_payload.get("resolution", {}))
	var max_repeat := 0
	for count in duplicate_repeat_counts.values():
		max_repeat = maxi(max_repeat, int(count))

	return {
		"case_id": str(started_payload.get("case_id", "")),
		"run": int(started_payload.get("run", 0)),
		"completed": completed,
		"abandoned": abandoned,
		"duration_ms": last_elapsed_ms,
		"submission_count": submission_count,
		"incorrect_submission_count": incorrect_count,
		"unique_candidate_count": candidate_signatures.size(),
		"duplicate_blocked_count": duplicate_blocked_count,
		"max_repeated_candidate_count": max_repeat,
		"selection_change_count": selection_change_count,
		"hint_reveal_count": hint_reveal_count,
		"max_hint_level": max_hint_level,
		"partner_resolution_count": partner_resolution_count,
		"run_resolution_result": str(resolution_summary.get("run_resolution_result", last_run_resolution_result)),
	}


static func _candidate_signature(event_type: String, payload: Dictionary) -> String:
	var keys: Array = CANDIDATE_SIGNATURE_KEYS.get(event_type, [])
	if keys.is_empty():
		return ""
	var parts: PackedStringArray = []
	for key in keys:
		parts.append(JSON.stringify(payload.get(key)))
	return "|".join(parts)


## Human-readable, deterministic-order lines for a status label or console —
## a developer/analysis tool, like every other Deduction Lab debug surface,
## so this is never localized.
static func format_summary_lines(summary: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("Prototype: %s   Session: %s   Runs: %d" % [summary.get("prototype_type", ""), summary.get("session_id", ""), summary.get("total_runs", 0)])
	for run in (summary.get("runs", []) as Array):
		var state: String = "completed" if run.get("completed", false) else ("abandoned" if run.get("abandoned", false) else ("restarted without finishing" if run.get("superseded_by_restart", false) else "in progress"))
		lines.append(
			"Run %d [%s]: %s — %dms, %d submission(s) (%d incorrect), %d unique candidate(s), %d duplicate block(s) (max repeat %d), %d selection change(s), hints %d (max level %d), resolution=%s" % [
				run.get("run", 0), run.get("case_id", ""), state,
				run.get("duration_ms", 0), run.get("submission_count", 0), run.get("incorrect_submission_count", 0),
				run.get("unique_candidate_count", 0), run.get("duplicate_blocked_count", 0), run.get("max_repeated_candidate_count", 0),
				run.get("selection_change_count", 0), run.get("hint_reveal_count", 0), run.get("max_hint_level", 0),
				run.get("run_resolution_result", ""),
			]
		)
	return lines


## A compact "key=value, key=value" line for a controller's OWN live
## get_stats() dict — independent of the recorder, so it works even while
## recording is off. Sorted keys for deterministic output (tests, diffing).
static func format_stats_line(stats: Dictionary) -> String:
	var keys: Array = stats.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s=%s" % [key, stats[key]])
	return ", ".join(parts)


## Writes summarize(export_dict) as pretty-printed JSON, mirroring
## DeductionLabRecorder.export_to_file()'s own filename-safety and
## {"success", "path", "error"} result shape exactly, so a caller can treat
## both exports identically. Never raises.
static func export_to_file(export_dict: Dictionary, dir_path: String) -> Dictionary:
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(dir_path)
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		return {"success": false, "path": "", "error": "could not create export directory %s (%s)" % [dir_path, error_string(make_dir_error)]}

	var summary: Dictionary = summarize(export_dict)
	var filename: String = "%s_%s_summary.json" % [
		_sanitize_filename_part(str(export_dict.get("session_id", ""))), _sanitize_filename_part(str(export_dict.get("case_id", ""))),
	]
	var full_path: String = dir_path.path_join(filename)
	var file: FileAccess = FileAccess.open(full_path, FileAccess.WRITE)
	if file == null:
		return {"success": false, "path": full_path, "error": "could not open %s for writing (%s)" % [full_path, error_string(FileAccess.get_open_error())]}
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	return {"success": true, "path": full_path, "error": ""}


## Same safe-filename rule as DeductionLabRecorder._sanitize_filename_part()
## (kept as its own small copy rather than a shared dependency — see
## docs/prototype-evaluation.md, "Why this duplicates one tiny helper").
static func _sanitize_filename_part(raw: String) -> String:
	var out := ""
	for character in raw:
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			out += character
		else:
			out += "_"
	return out if out != "" else "x"
