class_name CoreLoopUnit
extends RefCounted
## One production resolution unit of a core-loop chapter (Milestone 1.16 —
## see docs/core-loop-sandbox.md). A thin adapter, not a new mechanic: it
## owns ONE of the existing, unmodified-in-logic prototype controllers
## (PrototypeB/A/CController), configured with the chapter run's production
## context — the SHARED DeductionSession, exactly the rounds the chapter
## assigns, only acquired evidence, and the help-only ResolutionPolicy mode —
## and exposes it through a closed command table.
##
## What it adds on top of the controller:
##   * a WHITELIST of callable controller methods, each tagged with what kind
##     of step it is (free draft edit, formal commit, or help)
##     and its exact argument types — the UI can reach nothing else, and a
##     malformed call is refused before it can raise a script error;
##   * the mechanic OUTCOMES the chapter run maps to consequences
##     ("timeline_accepted", "resolved") read from controller state the
##     instant the evaluator accepts — never from a screen being closed;
##   * the last formal/help result, kept (JSON-safe) until acknowledged, so a
##     reopened or reloaded screen shows the same feedback again instead of
##     silently dropping it.
##
## It never applies a consequence, changes a phase or saves anything —
## ChapterRuntime does all three. Grading stays entirely inside the
## controllers' real DeductionEvaluator/TimelineEvaluator calls.

const MECHANIC_CLUE_CONNECTION := "clue_connection"
const MECHANIC_STATEMENT_CONTRADICTION := "statement_contradiction"
const MECHANIC_TIMELINE_RECONSTRUCTION := "timeline_reconstruction"
const MECHANICS := [MECHANIC_CLUE_CONNECTION, MECHANIC_STATEMENT_CONTRADICTION, MECHANIC_TIMELINE_RECONSTRUCTION]

const OUTCOME_TIMELINE_ACCEPTED := "timeline_accepted"
const OUTCOME_RESOLVED := "resolved"
## Outcomes each mechanic can report, in the order they can happen.
const OUTCOMES := {
	MECHANIC_CLUE_CONNECTION: [OUTCOME_RESOLVED],
	MECHANIC_STATEMENT_CONTRADICTION: [OUTCOME_RESOLVED],
	MECHANIC_TIMELINE_RECONSTRUCTION: [OUTCOME_TIMELINE_ACCEPTED, OUTCOME_RESOLVED],
}

## Command kinds — decide how ChapterRuntime checkpoints after the command.
## ("Continue" on feedback is not a command: see dismiss_feedback().)
const KIND_DRAFT := "draft"
const KIND_FORMAL := "formal"
const KIND_HELP := "help"

## command -> [kind, [argument types...]]. The ONLY controller methods a
## production screen can reach. See each controller for semantics.
const COMMANDS := {
	MECHANIC_CLUE_CONNECTION: {
		"open_evidence": [KIND_DRAFT, [TYPE_STRING]],
		"select_evidence": [KIND_DRAFT, [TYPE_STRING]],
		"remove_evidence": [KIND_DRAFT, [TYPE_STRING]],
		"replace_evidence": [KIND_DRAFT, [TYPE_STRING, TYPE_STRING]],
		"commit_theory": [KIND_FORMAL, []],
		"reveal_next_hint": [KIND_HELP, []],
		"accept_assistance": [KIND_HELP, []],
		"resolve_with_partner": [KIND_HELP, []],
	},
	MECHANIC_STATEMENT_CONTRADICTION: {
		"select_statement": [KIND_DRAFT, [TYPE_INT]],
		"next_statement": [KIND_DRAFT, []],
		"previous_statement": [KIND_DRAFT, []],
		"open_evidence": [KIND_DRAFT, [TYPE_STRING]],
		"select_evidence": [KIND_DRAFT, [TYPE_STRING]],
		"clear_selected_evidence": [KIND_DRAFT, []],
		"present_evidence": [KIND_FORMAL, []],
		"reveal_next_hint": [KIND_HELP, [TYPE_STRING]],
		"accept_assistance": [KIND_HELP, []],
		"resolve_with_partner": [KIND_HELP, []],
	},
	MECHANIC_TIMELINE_RECONSTRUCTION: {
		"select_event": [KIND_DRAFT, [TYPE_STRING]],
		"place_selected": [KIND_DRAFT, [TYPE_STRING]],
		"place_event": [KIND_DRAFT, [TYPE_STRING, TYPE_STRING]],
		"remove_event": [KIND_DRAFT, [TYPE_STRING]],
		"open_fact": [KIND_DRAFT, [TYPE_STRING]],
		"select_claim_answer": [KIND_DRAFT, [TYPE_BOOL]],
		"select_claim_justification": [KIND_DRAFT, [TYPE_STRING]],
		"submit_timeline": [KIND_FORMAL, []],
		"submit_claim": [KIND_FORMAL, []],
		"reveal_next_hint": [KIND_HELP, []],
		"accept_assistance": [KIND_HELP, []],
		"resolve_with_partner": [KIND_HELP, []],
	},
}
## Commands whose returned result is player feedback, kept until acknowledged.
const FEEDBACK_COMMANDS := ["commit_theory", "present_evidence", "submit_timeline", "submit_claim", "resolve_with_partner"]

## Feedback kinds — which presenter builder renders a kept result.
const FEEDBACK_THEORY := "theory"
const FEEDBACK_CONTRADICTION := "contradiction"
const FEEDBACK_TIMELINE := "timeline"
const FEEDBACK_CLAIM := "claim"

const SNAPSHOT_FORMAT := 1

var unit_id: String = ""
var mechanic: String = ""
var definition: Dictionary = {}
## PrototypeBController | PrototypeAController | PrototypeCController.
var controller: RefCounted = null
## {"open": bool, "kind": FEEDBACK_*, "result": Dictionary (JSON-safe)}, or {}.
var _feedback: Dictionary = {}


## A brand-new unit: builds and start()s its controller. null when the
## definition or case can't support it (ContentValidator rejects that shape
## first, so this is a defensive backstop).
static func create(unit_definition: Dictionary, case_def: Dictionary, session: DeductionSession, recorder: DeductionLabRecorder, evidence_pool: Array[String]) -> CoreLoopUnit:
	var unit := CoreLoopUnit.new()
	if not unit._configure(unit_definition):
		return null
	if not unit.controller.start(case_def, recorder, unit._context(session, evidence_pool)):
		return null
	return unit


## Rebuilds a unit from to_dict() output without recording anything. null
## when the snapshot is malformed or belongs to another mechanic/definition.
static func restore(unit_definition: Dictionary, case_def: Dictionary, session: DeductionSession, recorder: DeductionLabRecorder, evidence_pool: Array[String], snapshot: Variant) -> CoreLoopUnit:
	var unit := CoreLoopUnit.new()
	if not unit._configure(unit_definition) or typeof(snapshot) != TYPE_DICTIONARY:
		return null
	if PrototypeContext.count(snapshot.get("format")) != SNAPSHOT_FORMAT or str(snapshot.get("mechanic", "")) != unit.mechanic:
		return null
	if not unit.controller.restore_snapshot(case_def, snapshot.get("controller"), recorder, unit._context(session, evidence_pool)):
		return null
	var feedback: Variant = snapshot.get("feedback", {})
	if typeof(feedback) != TYPE_DICTIONARY:
		return null
	if not (feedback as Dictionary).is_empty():
		if typeof(feedback.get("open")) != TYPE_BOOL or not [FEEDBACK_THEORY, FEEDBACK_CONTRADICTION, FEEDBACK_TIMELINE, FEEDBACK_CLAIM].has(feedback.get("kind")) \
				or typeof(feedback.get("result")) != TYPE_DICTIONARY:
			return null
		unit._feedback = (feedback as Dictionary).duplicate(true)
	return unit


func to_dict() -> Dictionary:
	return {
		"format": SNAPSHOT_FORMAT,
		"mechanic": mechanic,
		"controller": controller.to_snapshot(),
		"feedback": _feedback.duplicate(true),
	}


## Only acquired evidence is ever offered — refreshed by ChapterRuntime when
## the unit is opened or restored and before every command (evidence can only
## be acquired while the mechanic is closed). No-op for C (no evidence pool).
func set_evidence_pool(evidence_pool: Array[String]) -> void:
	if mechanic != MECHANIC_TIMELINE_RECONSTRUCTION:
		controller.set_evidence_pool(evidence_pool)


# ---------------------------------------------------------------------------
# Outcomes and attribution — what ChapterRuntime maps to consequences.

## Every outcome this unit has reached, in order ("timeline_accepted" before
## "resolved"). Read straight from committed controller state.
func reached_outcomes() -> Array[String]:
	var reached: Array[String] = []
	match mechanic:
		MECHANIC_CLUE_CONNECTION:
			if controller.is_theory_accepted():
				reached.append(OUTCOME_RESOLVED)
		MECHANIC_STATEMENT_CONTRADICTION:
			if controller.are_all_rounds_resolved():
				reached.append(OUTCOME_RESOLVED)
		MECHANIC_TIMELINE_RECONSTRUCTION:
			if controller.is_accepted():
				reached.append(OUTCOME_TIMELINE_ACCEPTED)
			if controller.is_claim_resolved():
				reached.append(OUTCOME_RESOLVED)
	return reached


func has_reached(outcome: String) -> bool:
	return reached_outcomes().has(outcome)


## "partner" when the partner resolved (any part of) what produced `outcome`,
## "player" otherwise, "" when not reached — the attribution stored with the
## applied consequence and shown (as narrative, never a badge) on the result.
func resolved_by(outcome: String) -> String:
	if not has_reached(outcome):
		return ""
	if mechanic == MECHANIC_TIMELINE_RECONSTRUCTION:
		return controller.get_timeline_resolved_by() if outcome == OUTCOME_TIMELINE_ACCEPTED else controller.get_claim_resolved_by()
	var policy: ResolutionPolicy = controller.get_policy()
	return ResolutionPolicy.RESOLVED_BY_PARTNER if policy.get_partner_resolution_count() > 0 else ResolutionPolicy.RESOLVED_BY_PLAYER


## The highest help level this unit actually used (help-only policy mode —
## failures never raise it). ChapterRuntime takes the maximum over units.
func help_result() -> String:
	return controller.get_policy().get_run_resolution_result()


func get_policy() -> ResolutionPolicy:
	return controller.get_policy()


# ---------------------------------------------------------------------------
# Commands

## Runs one whitelisted controller command. Returns {"ok": bool, "reason":
## String, "kind": KIND_*, "result": Variant}. Refuses (ok false, nothing
## touched) an unknown command or wrong argument types.
func perform(command: String, args: Array = []) -> Dictionary:
	var spec: Variant = (COMMANDS.get(mechanic, {}) as Dictionary).get(command)
	if spec == null:
		return {"ok": false, "reason": "unknown_command", "kind": "", "result": null}
	var arg_types: Array = spec[1]
	if args.size() != arg_types.size():
		return {"ok": false, "reason": "bad_arguments", "kind": spec[0], "result": null}
	for i in args.size():
		if typeof(args[i]) != arg_types[i]:
			return {"ok": false, "reason": "bad_arguments", "kind": spec[0], "result": null}

	var feedback_kind: String = _feedback_kind_for(command)
	var result: Variant = controller.callv(command, args)
	if FEEDBACK_COMMANDS.has(command) and typeof(result) == TYPE_DICTIONARY:
		_feedback = {"open": true, "kind": feedback_kind, "result": _json_safe(result)}
	return {"ok": true, "reason": "", "kind": spec[0], "result": result}


func is_feedback_open() -> bool:
	return _feedback.get("open", false) == true


## {"kind", "result"} of the feedback currently shown, or {} when none.
func get_open_feedback() -> Dictionary:
	return {"kind": _feedback.get("kind", ""), "result": _feedback.get("result", {})} if is_feedback_open() else {}


## The player dismissed the feedback ("Continue"). Also runs the controller's
## own acknowledgement (moves A to its next configured round, marks a finished
## mechanic completed) — each is a safe no-op when there is nothing to
## acknowledge. Never grades or resolves anything.
func dismiss_feedback() -> void:
	_feedback["open"] = false
	match mechanic:
		MECHANIC_CLUE_CONNECTION:
			controller.acknowledge_result()
		MECHANIC_STATEMENT_CONTRADICTION:
			controller.acknowledge_feedback()
		MECHANIC_TIMELINE_RECONSTRUCTION:
			controller.acknowledge_claim()


# ---------------------------------------------------------------------------
# Private

func _configure(unit_definition: Dictionary) -> bool:
	definition = unit_definition.duplicate(true)
	unit_id = str(definition.get("id", ""))
	mechanic = str(definition.get("mechanic", ""))
	match mechanic:
		MECHANIC_CLUE_CONNECTION:
			controller = PrototypeBController.new()
		MECHANIC_STATEMENT_CONTRADICTION:
			controller = PrototypeAController.new()
		MECHANIC_TIMELINE_RECONSTRUCTION:
			controller = PrototypeCController.new()
		_:
			return false
	return unit_id != ""


## The production context every controller of this unit runs with.
func _context(session: DeductionSession, evidence_pool: Array[String]) -> Dictionary:
	var context: Dictionary = {"failures_escalate_run_result": false}
	match mechanic:
		MECHANIC_CLUE_CONNECTION:
			context["session"] = session
			context["round_ids"] = [str(definition.get("round", ""))]
			context["evidence_pool"] = evidence_pool
		MECHANIC_STATEMENT_CONTRADICTION:
			context["session"] = session
			context["round_ids"] = DeductionEvaluator.string_array(definition.get("rounds", []))
			context["evidence_pool"] = evidence_pool
	return context


func _feedback_kind_for(command: String) -> String:
	match mechanic:
		MECHANIC_CLUE_CONNECTION:
			return FEEDBACK_THEORY
		MECHANIC_STATEMENT_CONTRADICTION:
			return FEEDBACK_CONTRADICTION
	# C's partner resolution resolves whichever unit is current BEFORE the call.
	if command == "submit_claim" or (command == "resolve_with_partner" and controller.is_accepted()):
		return FEEDBACK_CLAIM
	return FEEDBACK_TIMELINE


## The exact shape a save/load round trip produces (numbers as float, typed
## arrays as plain arrays) — stored that way from the start, so feedback
## rendered before and after a reload is built from identical data.
static func _json_safe(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
