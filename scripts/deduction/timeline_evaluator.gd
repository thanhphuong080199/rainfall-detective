class_name TimelineEvaluator
extends RefCounted
## Stateless, UI-independent checker for a deduction case's authored timeline
## constraints (Milestone 1.9 — see docs/deduction-system.md, "Timeline
## reconstruction"). A submitted timeline is one "HH:MM" start time per
## authored timeline event, and it is accepted when it satisfies every
## REQUIRED constraint — never by comparing it to one exact sequence, so any
## placement the evidence genuinely allows is accepted.
##
## Deliberately a fixed set of named constraint types evaluated directly, not
## a constraint solver: it only answers "does THIS placement satisfy the
## authored constraints", the same way ConditionEvaluator only answers "is
## THIS condition true right now".
##
## Pure — reads only the dictionaries it is handed (no autoloads, no
## GameState) — so DeductionValidator checks a case's authored solution with
## this exact code, and tests can feed it hand-built fixtures.
##
## Times are "HH:MM" on a single day; there is no midnight wrap-around (see
## docs/deduction-system.md, "Known limitations").

const CONSISTENT := "timeline_consistent"
const INCONSISTENT := "timeline_inconsistent"
const INVALID_INPUT := "invalid_input"

## Every constraint type evaluate() understands. DeductionValidator reads this
## so the two can't drift apart (the same KEYS pattern ConditionEvaluator uses).
const CONSTRAINT_TYPES := ["fixed_time", "window", "before", "no_overlap", "travel_time"]
## Constraint types that name one event ("event") vs. an ordered pair ("events").
const SINGLE_EVENT_TYPES := ["fixed_time", "window"]
const PAIR_EVENT_TYPES := ["before", "no_overlap", "travel_time"]


## Minutes after midnight for an "HH:MM" string, or -1 when malformed.
static func parse_time(value: Variant) -> int:
	if typeof(value) != TYPE_STRING:
		return -1
	var parts: PackedStringArray = (value as String).split(":")
	if parts.size() != 2 or parts[0].length() != 2 or parts[1].length() != 2:
		return -1
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var hours: int = parts[0].to_int()
	var minutes: int = parts[1].to_int()
	if hours < 0 or hours > 23 or minutes < 0 or minutes > 59:
		return -1
	return hours * 60 + minutes


## A non-negative whole number of minutes from a JSON field (JSON numbers
## arrive as float), `default_value` when absent, or -1 when malformed.
static func parse_minutes(value: Variant, default_value: int = 0) -> int:
	if value == null:
		return default_value
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1
	var number: float = value
	if number < 0.0 or number != floorf(number):
		return -1
	return int(number)


## id -> event dictionary for the case's timeline events.
static func event_index(case_def: Dictionary) -> Dictionary:
	var index: Dictionary = {}
	for event in _dict_array(_timeline(case_def).get("events", [])):
		index[str(event.get("id", ""))] = event
	return index


static func constraints(case_def: Dictionary) -> Array[Dictionary]:
	return _dict_array(_timeline(case_def).get("constraints", []))


## Event ids a constraint refers to, in authored order ("before" is ordered:
## the first id must come first).
static func constraint_event_ids(constraint: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var type: String = str(constraint.get("type", ""))
	if SINGLE_EVENT_TYPES.has(type):
		ids.append(str(constraint.get("event", "")))
	elif PAIR_EVENT_TYPES.has(type):
		var pair: Variant = constraint.get("events", [])
		if typeof(pair) == TYPE_ARRAY:
			for event_id in pair:
				ids.append(str(event_id))
	return ids


## Checks a submitted timeline. `placements` maps EVERY authored timeline
## event id to an "HH:MM" start time. Returns
## {"category": CONSISTENT | INCONSISTENT | INVALID_INPUT,
##  "reason": String (only for INVALID_INPUT),
##  "violated_required": Array[String], "violated_optional": Array[String]}.
## Only violated REQUIRED constraints make a timeline inconsistent; optional
## ones (e.g. a suspect's claimed time) are reported so a caller can show
## "this contradicts what X said" without it counting as a wrong answer.
static func evaluate(case_def: Dictionary, placements: Variant) -> Dictionary:
	if typeof(placements) != TYPE_DICTIONARY:
		return _result(INVALID_INPUT, "not_a_dictionary")
	var events: Dictionary = event_index(case_def)
	var starts: Dictionary = {}
	for event_id in placements:
		if typeof(event_id) != TYPE_STRING or not events.has(event_id):
			return _result(INVALID_INPUT, "unknown_event")
		var minutes: int = parse_time(placements[event_id])
		if minutes < 0:
			return _result(INVALID_INPUT, "bad_time")
		starts[event_id] = minutes
	for event_id in events:
		if not starts.has(event_id):
			return _result(INVALID_INPUT, "missing_event")

	var violated_required: Array[String] = []
	var violated_optional: Array[String] = []
	for constraint in constraints(case_def):
		if is_constraint_satisfied(constraint, starts, events):
			continue
		if constraint.get("required", true) == false:
			violated_optional.append(str(constraint.get("id", "")))
		else:
			violated_required.append(str(constraint.get("id", "")))
	var result: Dictionary = _result(CONSISTENT if violated_required.is_empty() else INCONSISTENT, "")
	result["violated_required"] = violated_required
	result["violated_optional"] = violated_optional
	return result


## One constraint against resolved start minutes. A malformed constraint
## (unknown type, bad reference, bad time) is never satisfied — it fails
## closed, like an unknown condition key; DeductionValidator reports it.
##
## Semantics (an event occupies [start, start + duration_minutes]):
##   fixed_time  {event, time}                  start == time
##   window      {event, earliest, latest}      earliest <= start <= latest
##   before      {events: [a, b], min_gap_minutes?}   end(a) + gap <= start(b)
##   no_overlap  {events: [a, b]}               the two intervals share no time
##                                               (two instants at the same minute overlap)
##   travel_time {events: [a, b], minutes}      whichever happens first, the other
##                                               starts at least `minutes` after it ends
static func is_constraint_satisfied(constraint: Dictionary, starts: Dictionary, events: Dictionary) -> bool:
	var ids: Array[String] = constraint_event_ids(constraint)
	for event_id in ids:
		if not starts.has(event_id) or not events.has(event_id):
			return false
	match str(constraint.get("type", "")):
		"fixed_time":
			var time: int = parse_time(constraint.get("time"))
			return time >= 0 and starts[ids[0]] == time
		"window":
			var earliest: int = parse_time(constraint.get("earliest"))
			var latest: int = parse_time(constraint.get("latest"))
			if earliest < 0 or latest < 0:
				return false
			return earliest <= starts[ids[0]] and starts[ids[0]] <= latest
		"before":
			var gap: int = parse_minutes(constraint.get("min_gap_minutes"), 0)
			if ids.size() != 2 or gap < 0:
				return false
			return _end(ids[0], starts, events) + gap <= starts[ids[1]]
		"no_overlap":
			if ids.size() != 2:
				return false
			if starts[ids[0]] == starts[ids[1]]:
				return false
			return _end(ids[0], starts, events) <= starts[ids[1]] or _end(ids[1], starts, events) <= starts[ids[0]]
		"travel_time":
			var travel: int = parse_minutes(constraint.get("minutes"), -1)
			if ids.size() != 2 or travel < 0:
				return false
			var first: String = ids[0] if starts[ids[0]] <= starts[ids[1]] else ids[1]
			var second: String = ids[1] if first == ids[0] else ids[0]
			return _end(first, starts, events) + travel <= starts[second]
	return false


static func _end(event_id: String, starts: Dictionary, events: Dictionary) -> int:
	var duration: int = parse_minutes((events[event_id] as Dictionary).get("duration_minutes"), 0)
	return starts[event_id] + maxi(duration, 0)


static func _timeline(case_def: Dictionary) -> Dictionary:
	var timeline: Variant = case_def.get("timeline", {})
	return timeline if typeof(timeline) == TYPE_DICTIONARY else {}


static func _dict_array(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry in value:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append(entry)
	return out


static func _result(category: String, reason: String) -> Dictionary:
	var empty_required: Array[String] = []
	var empty_optional: Array[String] = []
	return {"category": category, "reason": reason, "violated_required": empty_required, "violated_optional": empty_optional}
