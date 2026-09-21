class_name PrototypeContext
extends RefCounted
## Small, stateless helpers shared by the three prototype controllers'
## Milestone 1.16 production context and snapshot code (see
## docs/core-loop-sandbox.md). Pure and autoload-free, like the controllers
## themselves: no grading, no content lookups beyond the dictionaries handed
## in. Kept deliberately tiny — the controllers' own run-clock/telemetry
## plumbing is still NOT unified (docs/prototype-evaluation.md, "Duplication").


## The authored rounds of a prototype layer, or only `context.round_ids` of
## them, in authored order. Returns [] when a requested id doesn't exist —
## never a silently smaller run.
static func scoped_rounds(proto: Dictionary, context: Dictionary) -> Array[Dictionary]:
	var all_rounds: Array[Dictionary] = DeductionEvaluator.dict_array(proto.get("rounds", []))
	var wanted: Array[String] = DeductionEvaluator.string_array(context.get("round_ids", []))
	if wanted.is_empty():
		return all_rounds
	var scoped: Array[Dictionary] = []
	for proto_round in all_rounds:
		if wanted.has(str(proto_round.get("id", ""))):
			scoped.append(proto_round)
	if scoped.size() != wanted.size():
		scoped.clear()
	return scoped


## `context.session` when given (it must belong to this case), otherwise a
## fresh, isolated DeductionSession — the debug prototypes' original
## behavior. null for a session of another case or a non-session value.
static func session_for(case_def: Dictionary, context: Dictionary) -> DeductionSession:
	var case_id: String = str(case_def.get("id", ""))
	var shared: Variant = context.get("session")
	if shared == null:
		return DeductionSession.new(case_id)
	if not (shared is DeductionSession):
		return null
	var session: DeductionSession = shared
	if session.case_id != "" and session.case_id != case_id:
		return null
	return session


## The ResolutionPolicy mode a context asks for (default: the debug
## semantics, where failed commits raise the run result).
static func failures_escalate(context: Dictionary) -> bool:
	return context.get("failures_escalate_run_result", true) != false


## Keys of a Dictionary used as a set, sorted — deterministic snapshot output.
static func sorted_keys(set_dict: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in set_dict:
		keys.append(str(key))
	keys.sort()
	return keys


static func key_set(keys: Variant) -> Dictionary:
	var out: Dictionary = {}
	for key in DeductionEvaluator.string_array(keys):
		out[key] = true
	return out


static func is_string_list(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for entry in value:
		if typeof(entry) != TYPE_STRING:
			return false
	return true


## A non-negative whole number from snapshot data (JSON numbers arrive as
## float), or -1 when missing or malformed.
static func count(value: Variant) -> int:
	return TimelineEvaluator.parse_minutes(value, -1) if value != null else -1
