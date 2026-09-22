class_name CoreLoopRouteSimulator
extends RefCounted
## Milestone 1.17 — deterministic LEGAL-PATH simulator for core-loop chapter
## content (docs/core-loop-authoring.md, "Legal-path simulation"). Proves that
## at least one valid route exists through a chapter by playing it with the
## real production logic: a fresh run through SaveManager.new_game() and a
## ChapterRuntime, every piece of evidence acquired through a represented
## interaction (Investigation.move_to/examine/talk + DialogueManager
## advance/choose) or a consequence the runtime applied, every unit opened and
## committed through ChapterRuntime.open_unit()/perform() with an AUTHORED
## accepted proof path, until CaseManager completes the chapter and the Result
## view can be built.
##
## What it is NOT: an AI player, a human playtest, or a general quest solver.
## It never searches for answers — B/A answers come from authored proof sets
## (or the unit's "documented_paths"), C from the authored solution timeline
## or another timeline TimelineEvaluator accepts. Acquisition is a small,
## depth-limited backward lookup: "which dialogue in which location grants
## this, and what gates that dialogue?" over the content ContentDB loaded.
## Test/authoring tooling only — never loaded by the player runtime.
##
## Never touches a debug or mutation API: game state and the event/effect
## machinery are only READ; the only calls that change anything are listed in
## ALLOWED_CALLS and recorded in `calls` (core_loop_simulation_test.gd checks
## both the list and this file's source). Every evidence acquisition is
## attributed to the step that caused it, so an injected item shows up as an
## unattributed one.
##
## Like CoreLoopTestSupport, it names no autoload by bare name and load()s the
## class_name scripts that use autoloads (docs/architecture.md, "Known
## limitations": the -s compile-order trap).

const MAX_DEPTH := 5
const MAX_STEPS := 60
const DIALOGUE_GUARD := 60
## Every mutating call this simulator may make — the production entry points
## a player's clicks reach, nothing else.
const ALLOWED_CALLS := [
	"SaveManager.new_game", "ChapterRuntime.reload_from_game_state", "ChapterRuntime.acknowledge_briefing",
	"ChapterRuntime.open_unit", "ChapterRuntime.perform", "ChapterRuntime.dismiss_feedback", "ChapterRuntime.close_unit",
	"Investigation.move_to", "Investigation.examine", "Investigation.talk", "DialogueManager.advance", "DialogueManager.choose",
]

var game_state: Node
var investigation: Node
var dialogue_manager: Node
var save_manager: Node
var case_manager: Node
var content_db: Node

## Ordered log of every step taken — replayable through the real UI.
var route: Array[Dictionary] = []
## Every mutating call made, as "Owner.method" — always within ALLOWED_CALLS.
var calls: Array[String] = []
## {"evidence", "step"} for every acquisition while the simulator ran.
var acquisitions: Array[Dictionary] = []
var failure: String = ""

var _condition: Script
var _runtime: RefCounted
var _step: String = ""
var _opportunities: Array[Dictionary] = []
var _visiting: Dictionary = {}


func _init(tree: SceneTree) -> void:
	game_state = tree.get_root().get_node("GameState")
	investigation = tree.get_root().get_node("Investigation")
	dialogue_manager = tree.get_root().get_node("DialogueManager")
	save_manager = tree.get_root().get_node("SaveManager")
	case_manager = tree.get_root().get_node("CaseManager")
	content_db = tree.get_root().get_node("ContentDB")
	_condition = load("res://scripts/core/condition_evaluator.gd")


## Starts a brand-new run of `case_id` (its core-loop starting chapter) on
## `runtime` and plays it to completion — see advance() for `options`.
func run(case_id: String, runtime: RefCounted, options: Dictionary = {}) -> Dictionary:
	_reset()
	_runtime = runtime
	_call("SaveManager.new_game")
	save_manager.new_game(case_id)
	_call("ChapterRuntime.reload_from_game_state")
	runtime.reload_from_game_state()
	route.append({"kind": "new_game", "case": case_id})
	return advance(runtime, options)


## Continues whatever run `runtime` holds (e.g. one just resumed from a save)
## until the chapter completes, `options.stop_at_phase` is entered, or a step
## fails. Options:
##   "b_paths": {unit id: index} — which accepted path each B unit commits
##       (index into its documented_paths, else its authored accepted paths);
##   "timeline": "primary" (authored solution, default) | "alternate" (another
##       timeline the real TimelineEvaluator accepts);
##   "optional_lies": true — also refute A's optional innocent lies first;
##   "early_evidence": [inventory ids] — acquire these right after the
##       briefing (e.g. evidence a later consequence would also grant);
##   "stop_at_phase": phase id — return as soon as that phase is current.
## Returns {"ok", "failure", "chapter_id", "completed", "phases": [ids],
## "units": {unit id: {"mechanic", "path"/"timeline"/"refutations"}},
## "route", "calls", "acquisitions"}.
func advance(runtime: RefCounted, options: Dictionary = {}) -> Dictionary:
	_runtime = runtime
	_build_index()
	var on_evidence := func(evidence_id: String) -> void: acquisitions.append({"evidence": evidence_id, "step": _step})
	game_state.evidence_added.connect(on_evidence)
	var phases: Array[String] = []
	var units: Dictionary = {}
	if not runtime.is_active() or runtime.has_error():
		_fail("the runtime did not start a core-loop run (%s)" % runtime.get_error())
	var steps := 0
	while failure == "" and not runtime.is_completed() and steps < MAX_STEPS:
		steps += 1
		var phase_id: String = runtime.get_phase_id()
		if phases.is_empty() or phases[phases.size() - 1] != phase_id:
			phases.append(phase_id)
		if str(options.get("stop_at_phase", "")) == phase_id:
			break
		if runtime.is_briefing():
			_call("ChapterRuntime.acknowledge_briefing")
			_expect(runtime.acknowledge_briefing(), "acknowledge the briefing")
			route.append({"kind": "briefing"})
			for evidence_id in options.get("early_evidence", []):
				if not _acquire("evidence:%s" % evidence_id, 0):
					_fail("could not acquire early evidence '%s'" % evidence_id)
			continue
		var unit_id: String = runtime.get_current_unit_id()
		var definition: Dictionary = runtime.get_unit_definition(unit_id)
		match str(definition.get("mechanic", "")):
			"clue_connection":
				units[unit_id] = _play_clue_connection(unit_id, definition, options)
			"statement_contradiction":
				units[unit_id] = _play_statement_contradiction(unit_id, definition, options)
			"timeline_reconstruction":
				units[unit_id] = _play_timeline(unit_id, units.get(unit_id, {}), options)
			_:
				_fail("phase '%s' has no playable unit" % phase_id)
	if runtime.is_completed() and (phases.is_empty() or phases[phases.size() - 1] != runtime.get_phase_id()):
		phases.append(runtime.get_phase_id())
	game_state.evidence_added.disconnect(on_evidence)
	var chapter_id: String = runtime.get_chapter_id()
	var stopped: bool = str(options.get("stop_at_phase", "")) != "" and runtime.get_phase_id() == str(options.get("stop_at_phase", ""))
	if failure == "" and not stopped:
		if not runtime.is_completed():
			_fail("the chapter did not complete within %d steps" % MAX_STEPS)
		elif not case_manager.is_chapter_complete(chapter_id):
			_fail("the runtime completed but CaseManager never marked '%s' complete" % chapter_id)
		elif str(load("res://scripts/core_loop/core_loop_presenter.gd").build_result(runtime).get("title", "")) == "":
			_fail("the Result view has no title")
	return {
		"ok": failure == "", "failure": failure, "chapter_id": chapter_id, "completed": runtime.is_completed(),
		"phases": phases, "units": units, "route": route.duplicate(true), "calls": calls.duplicate(),
		"acquisitions": acquisitions.duplicate(true),
	}


# ---------------------------------------------------------------------------
# Mechanics — authored answers through ChapterRuntime.perform() only.

## Acquires, through interactions only, everything `unit_id` needs for the
## chosen answer (see advance() for `options`) and its offer condition —
## without opening it. True once the runtime offers the unit. Public so tests
## can stop a simulated run just before (or inside) a unit.
func prepare_unit(runtime: RefCounted, unit_id: String, options: Dictionary = {}) -> bool:
	_runtime = runtime
	if _opportunities.is_empty():
		_build_index()
	for evidence_id in _needed_evidence(unit_id, runtime.get_unit_definition(unit_id), options):
		if evidence_id == "":
			_fail("unit '%s' needs evidence the chapter does not link" % unit_id)
			return false
		if not _acquire("evidence:%s" % evidence_id, 0):
			_fail("unit '%s': could not acquire '%s'" % [unit_id, evidence_id])
			return false
	if runtime.get_unit_status(unit_id).get("available", false) != true:
		_satisfy(runtime.get_unit_definition(unit_id).get("offer_condition"), game_state.current_location, 0)
	return runtime.get_unit_status(unit_id).get("available", false) == true


## Inventory evidence the chosen answer uses: the B unit's chosen path; the A
## unit's single refuting item per required (and, with "optional_lies", per
## optional) statement; nothing for C.
func _needed_evidence(unit_id: String, definition: Dictionary, options: Dictionary) -> Array:
	match str(definition.get("mechanic", "")):
		"clue_connection":
			var paths: Array = _b_paths(definition)
			var index: int = int((options.get("b_paths", {}) as Dictionary).get(unit_id, 0))
			return paths[index] if index >= 0 and index < paths.size() else [""]
		"statement_contradiction":
			var needed: Array = []
			for entry in _refutation_plan(definition, options):
				needed.append(entry["evidence"])
			return needed
	return []


func _play_clue_connection(unit_id: String, definition: Dictionary, options: Dictionary) -> Dictionary:
	var paths: Array = _b_paths(definition)
	var index: int = int((options.get("b_paths", {}) as Dictionary).get(unit_id, 0))
	if index < 0 or index >= paths.size():
		_fail("unit '%s' has no accepted path #%d (it has %d)" % [unit_id, index, paths.size()])
		return {}
	var path: Array = paths[index]  # inventory evidence ids
	if not prepare_unit(_runtime, unit_id, options) or not _open(unit_id):
		return {}
	for evidence_id in path:
		_perform(unit_id, "select_evidence", [_linked(evidence_id)])
	var result: Dictionary = _perform(unit_id, "commit_theory")
	if (result.get("result", {}) as Dictionary).get("accepted", false) != true:
		return _fail("unit '%s': the authored path %s was not accepted (%s)" % [unit_id, path, result.get("result")])
	_finish(unit_id)
	return {"mechanic": "clue_connection", "path": path, "path_index": index}


## [{"claim", "evidence" (inventory id, "" when unlinked), "optional"}] for
## every required refutation of the unit's rounds, plus optional ones when
## options.optional_lies — each refuted by its authored single-evidence proof.
func _refutation_plan(definition: Dictionary, options: Dictionary) -> Array[Dictionary]:
	var case_def: Dictionary = _runtime.get_case_def()
	var layer: Dictionary = case_def.get("prototype_a", {})
	var pool: Array = layer.get("evidence_pool", [])
	var wanted: Array = definition.get("rounds", [])
	var plan: Array[Dictionary] = []
	for proto_round in layer.get("rounds", []):
		if not wanted.has(str(proto_round.get("id", ""))):
			continue
		if options.get("optional_lies", false) == true:
			for claim_id in proto_round.get("optional_refutations", []):
				plan.append({"claim": str(claim_id), "evidence": _refuting_inventory_evidence(case_def, str(claim_id), pool), "optional": true})
		for claim_id in proto_round.get("required_refutations", []):
			plan.append({"claim": str(claim_id), "evidence": _refuting_inventory_evidence(case_def, str(claim_id), pool), "optional": false})
	return plan


func _play_statement_contradiction(unit_id: String, definition: Dictionary, options: Dictionary) -> Dictionary:
	var plan: Array[Dictionary] = _refutation_plan(definition, options)
	if not prepare_unit(_runtime, unit_id, options) or not _open(unit_id):
		return {}
	var controller: RefCounted = _runtime.get_unit(unit_id).controller
	var refuted: Array[Dictionary] = []
	var guard := 0
	while failure == "" and not _runtime.get_unit(unit_id).has_reached("resolved") and guard < 20:
		guard += 1
		var statements: Array = controller.get_statement_ids()
		var todo: Array[Dictionary] = []
		for entry in plan:
			if statements.has(entry["claim"]) and _runtime.get_session().get_claim_status(entry["claim"]) == "":
				todo.append(entry)
		if todo.is_empty():
			return _fail("unit '%s': round %d has no statement left to refute" % [unit_id, controller.get_round_index()])
		var entry: Dictionary = todo[0]
		_perform(unit_id, "select_statement", [statements.find(entry["claim"])])
		_perform(unit_id, "select_evidence", [_linked(entry["evidence"])])
		var result: Dictionary = _perform(unit_id, "present_evidence")
		var outcome: String = str((result.get("result", {}) as Dictionary).get("outcome", ""))
		var expected: String = "optional" if entry["optional"] else "required"
		if outcome != expected:
			return _fail("unit '%s': refuting '%s' with '%s' gave '%s', expected '%s'" % [unit_id, entry["claim"], entry["evidence"], outcome, expected])
		refuted.append({"claim": entry["claim"], "evidence": entry["evidence"], "outcome": outcome})
		_call("ChapterRuntime.dismiss_feedback")
		_runtime.dismiss_feedback(unit_id)
		route.append({"kind": "dismiss", "unit": unit_id})
	_call("ChapterRuntime.close_unit")
	_runtime.close_unit()
	route.append({"kind": "close", "unit": unit_id})
	return {"mechanic": "statement_contradiction", "refutations": refuted}


func _play_timeline(unit_id: String, so_far: Dictionary, options: Dictionary) -> Dictionary:
	var played: Dictionary = so_far.duplicate(true)
	played["mechanic"] = "timeline_reconstruction"
	if not _open(unit_id):
		return played
	var controller: RefCounted = _runtime.get_unit(unit_id).controller
	var case_def: Dictionary = _runtime.get_case_def()
	if not controller.is_accepted():
		var placement: Dictionary = _timeline_for(case_def, str(options.get("timeline", "primary")))
		if placement.is_empty():
			return _fail("unit '%s': no %s timeline to place" % [unit_id, options.get("timeline", "primary")])
		for event_id in placement:
			_perform(unit_id, "place_event", [event_id, placement[event_id]])
		var result: Dictionary = _perform(unit_id, "submit_timeline")
		if not controller.is_accepted():
			return _fail("unit '%s': the %s timeline was rejected (%s)" % [unit_id, options.get("timeline", "primary"), result.get("result")])
		played["timeline"] = placement
		_call("ChapterRuntime.dismiss_feedback")
		_runtime.dismiss_feedback(unit_id)
		route.append({"kind": "dismiss", "unit": unit_id})
		return played
	var contradiction: Dictionary = (case_def.get("prototype_c", {}) as Dictionary).get("contradiction", {})
	var support: String = str((contradiction.get("supporting_constraint_refs", []) as Array).front()) if not (contradiction.get("supporting_constraint_refs", []) as Array).is_empty() else ""
	_perform(unit_id, "select_claim_answer", [true])
	_perform(unit_id, "select_claim_justification", [support])
	_perform(unit_id, "submit_claim")
	if not controller.is_claim_resolved():
		return _fail("unit '%s': the final claim (impossible + '%s') was not accepted" % [unit_id, support])
	played["claim_support"] = support
	_call("ChapterRuntime.dismiss_feedback")
	_runtime.dismiss_feedback(unit_id)
	route.append({"kind": "dismiss", "unit": unit_id})
	return played


## The unit's candidate paths as INVENTORY evidence ids: its documented_paths
## when present, else every authored accepted proof path mapped back through
## evidence_links (skipping any with an unlinked item).
func _b_paths(definition: Dictionary) -> Array:
	var documented: Variant = definition.get("documented_paths")
	if typeof(documented) == TYPE_ARRAY and not (documented as Array).is_empty():
		return (documented as Array).duplicate(true)
	var out: Array = []
	for accepted in load("res://scripts/core_loop/core_loop_validator.gd").accepted_paths(definition, _runtime.get_case_def()):
		var mapped: Array = []
		for deduction_id in accepted:
			var inventory_id: String = _inventory_for(str(deduction_id))
			if inventory_id == "":
				mapped.clear()
				break
			mapped.append(inventory_id)
		if not mapped.is_empty():
			out.append(mapped)
	return out


func _refuting_inventory_evidence(case_def: Dictionary, claim_id: String, pool: Array) -> String:
	for claim in case_def.get("claims", []):
		if str(claim.get("id", "")) != claim_id:
			continue
		for proof_set in claim.get("proof_sets", []):
			var requires: Array = proof_set.get("requires", [])
			if str(proof_set.get("relation", "")) == "refutes" and requires.size() == 1 and pool.has(requires[0]):
				var inventory_id: String = _inventory_for(str(requires[0]))
				if inventory_id != "":
					return inventory_id
	return ""


## "primary": the authored solution (movable events only). "alternate": the
## first OTHER placement the real TimelineEvaluator accepts over the unit's
## candidate slots.
func _timeline_for(case_def: Dictionary, which: String) -> Dictionary:
	var proto: Dictionary = case_def.get("prototype_c", {})
	var truth: Dictionary = (case_def.get("ground_truth", {}) as Dictionary).get("solution_timeline", {})
	var primary: Dictionary = {}
	for event_id in proto.get("movable_events", []):
		primary[str(event_id)] = str(truth.get(event_id, ""))
	if which != "alternate":
		return primary
	for accepted in load("res://scripts/deduction/deduction_validator.gd").enumerate_accepted_prototype_c_timelines(case_def):
		var candidate: Dictionary = {}
		for event_id in proto.get("movable_events", []):
			candidate[str(event_id)] = str(accepted.get(event_id, ""))
		if candidate != primary:
			return candidate
	return {}


# ---------------------------------------------------------------------------
# Acquisition — represented interactions only.

## Every (location, interaction) that plays a dialogue, with what that
## dialogue can produce and the choice path to it: {"location", "kind":
## "examine"|"talk", "point", "variant", "npc", "topic", "dialogue",
## "produces": {key: [steps]}}. Content order, so the choice is deterministic.
func _build_index() -> void:
	_opportunities = []
	var location_ids: Array = content_db.get_all_location_ids()
	location_ids.sort()
	for location_id in location_ids:
		var location: Dictionary = content_db.get_location(String(location_id))
		for point in location.get("examine_points", []):
			var variants: Array = point.get("variants", [])
			for i in variants.size():
				_opportunities.append({
					"location": String(location_id), "kind": "examine", "point": str(point.get("id", "")), "variant": i,
					"dialogue": str(variants[i].get("dialogue_id", "")), "produces": _dialogue_products(str(variants[i].get("dialogue_id", ""))),
				})
		for npc in location.get("npcs", []):
			for topic in npc.get("topics", []):
				_opportunities.append({
					"location": String(location_id), "kind": "talk", "npc": str(npc.get("id", "")), "topic": str(topic.get("id", "")),
					"dialogue": str(topic.get("dialogue_id", "")), "produces": _dialogue_products(str(topic.get("dialogue_id", ""))),
				})


## key ("evidence:x"/"flag:x"/"interaction:x") -> the shortest step list that
## makes the dialogue run the effect producing it: "advance" or ["choose",
## raw choice index].
func _dialogue_products(dialogue_id: String) -> Dictionary:
	var tree: Dictionary = content_db.get_dialogue(dialogue_id)
	var nodes: Dictionary = tree.get("nodes", {})
	var products: Dictionary = {}
	var queue: Array = [[str(tree.get("start", "")), []]]
	var seen: Dictionary = {}
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var node_id: String = item[0]
		if node_id == "" or seen.has(node_id) or not nodes.has(node_id):
			continue
		seen[node_id] = true
		var node: Dictionary = nodes[node_id]
		_record_products(node.get("actions", []), item[1], products)
		var choices: Array = node.get("choices", [])
		if choices.is_empty():
			var next: Variant = node.get("next")
			if next != null:
				queue.append([str(next), (item[1] as Array) + ["advance"]])
			continue
		for i in choices.size():
			var path: Array = (item[1] as Array) + [["choose", i]]
			_record_products(choices[i].get("actions", []), path, products)
			if choices[i].get("next") != null:
				queue.append([str(choices[i].get("next")), path])
	return products


func _record_products(effects: Array, path: Array, products: Dictionary) -> void:
	for effect in effects:
		var key: String = ""
		match str(effect.get("type", "")):
			"add_evidence":
				key = "evidence:%s" % effect.get("evidence_id", "")
			"set_flag":
				if effect.get("value", true) == true:
					key = "flag:%s" % effect.get("flag", "")
			"mark_interaction_complete":
				key = "interaction:%s" % effect.get("id", "")
		if key != "" and not products.has(key):
			products[key] = path.duplicate(true)


func _acquire(key: String, depth: int) -> bool:
	if _holds(key):
		return true
	if depth > MAX_DEPTH or _visiting.has(key):
		return false
	_visiting[key] = true
	for opportunity in _opportunities:
		if (opportunity["produces"] as Dictionary).has(key) and _try(opportunity, key, depth):
			break
	_visiting.erase(key)
	return _holds(key)


## Satisfies a gating condition through interactions ("not" and equals:false
## can only be checked, never produced).
func _satisfy(condition: Variant, location_id: String, depth: int) -> bool:
	if condition == null or _condition.evaluate(condition):
		return true
	if typeof(condition) != TYPE_DICTIONARY or depth > MAX_DEPTH:
		return false
	if condition.has("all"):
		for sub in condition.get("all", []):
			if not _satisfy(sub, location_id, depth + 1):
				return false
		return _go_to(location_id, depth) and _condition.evaluate(condition)
	if condition.has("any"):
		for sub in condition.get("any", []):
			if _satisfy(sub, location_id, depth + 1):
				return true
		return false
	if condition.has("flag"):
		return condition.get("equals", true) == true and _acquire("flag:%s" % condition.get("flag", ""), depth + 1)
	if condition.has("has_evidence"):
		return _acquire("evidence:%s" % condition.get("has_evidence", ""), depth + 1)
	if condition.has("interaction_complete"):
		return _acquire("interaction:%s" % condition.get("interaction_complete", ""), depth + 1)
	if condition.has("visited_location"):
		return _go_to(str(condition.get("visited_location", "")), depth)
	if condition.has("examined"):
		if not _go_to(location_id, depth):
			return false
		_interact({"location": location_id, "kind": "examine", "point": str(condition.get("examined", ""))}, [])
		return _condition.evaluate(condition)
	return false


func _try(opportunity: Dictionary, key: String, depth: int) -> bool:
	var location_id: String = opportunity["location"]
	var location: Dictionary = content_db.get_location(location_id)
	var gates: Array = []
	if opportunity["kind"] == "talk":
		for npc in location.get("npcs", []):
			if str(npc.get("id", "")) == opportunity["npc"]:
				gates.append(npc.get("condition"))
				for topic in npc.get("topics", []):
					if str(topic.get("id", "")) == opportunity["topic"]:
						gates.append(topic.get("condition"))
	else:
		for point in location.get("examine_points", []):
			if str(point.get("id", "")) == opportunity["point"]:
				gates.append(point.get("variants", [])[opportunity["variant"]].get("condition"))
	for gate in gates:
		if not _satisfy(gate, location_id, depth + 1):
			return false
	if not _go_to(location_id, depth):
		return false
	for gate in gates:
		if not _condition.evaluate(gate):
			return false
	if opportunity["kind"] == "examine" and _selected_variant(location, opportunity["point"]) != opportunity["variant"]:
		return false
	_interact(opportunity, (opportunity["produces"] as Dictionary)[key])
	return _holds(key)


func _selected_variant(location: Dictionary, point_id: String) -> int:
	for point in location.get("examine_points", []):
		if str(point.get("id", "")) == point_id:
			var variants: Array = point.get("variants", [])
			for i in variants.size():
				if _condition.evaluate(variants[i].get("condition")):
					return i
	return -1


## Plays one interaction through Investigation, then the dialogue along
## `path` (and on to its end), exactly as clicks would.
func _interact(opportunity: Dictionary, path: Array) -> void:
	var step: Dictionary = {"kind": opportunity["kind"], "location": opportunity["location"], "choices": []}
	var dialogue_id: String
	if opportunity["kind"] == "talk":
		step["npc"] = opportunity["npc"]
		step["topic"] = opportunity["topic"]
		_step = "talk %s/%s/%s" % [opportunity["location"], opportunity["npc"], opportunity["topic"]]
		_call("Investigation.talk")
		investigation.talk(opportunity["npc"], opportunity["topic"])
		dialogue_id = str(opportunity.get("dialogue", ""))
	else:
		step["point"] = opportunity["point"]
		_step = "examine %s/%s" % [opportunity["location"], opportunity["point"]]
		var location: Dictionary = content_db.get_location(opportunity["location"])
		var chosen: int = _selected_variant(location, opportunity["point"])
		for point in location.get("examine_points", []):
			if str(point.get("id", "")) == opportunity["point"] and chosen >= 0:
				dialogue_id = str(point.get("variants", [])[chosen].get("dialogue_id", ""))
		_call("Investigation.examine")
		investigation.examine(opportunity["point"])
	var nodes: Dictionary = content_db.get_dialogue(dialogue_id).get("nodes", {})
	var node_id: String = str(content_db.get_dialogue(dialogue_id).get("start", ""))
	var remaining: Array = path.duplicate()
	var guard := 0
	while dialogue_manager.is_active and guard < DIALOGUE_GUARD:
		guard += 1
		var node: Dictionary = nodes.get(node_id, {})
		var raw: Array = node.get("choices", [])
		if raw.is_empty():
			if not remaining.is_empty() and typeof(remaining[0]) == TYPE_STRING:
				remaining.pop_front()
			node_id = str(node.get("next", "")) if node.get("next") != null else ""
			_call("DialogueManager.advance")
			dialogue_manager.advance()
			continue
		var raw_index: int = -1
		if not remaining.is_empty() and typeof(remaining[0]) == TYPE_ARRAY:
			raw_index = int(remaining.pop_front()[1])
		var filtered: Array[int] = []
		for i in raw.size():
			if _condition.evaluate(raw[i].get("condition")):
				filtered.append(i)
		var pick: int = filtered.find(raw_index) if raw_index >= 0 else 0
		if pick < 0:
			pick = 0
		(step["choices"] as Array).append(pick)
		node_id = str(raw[filtered[pick]].get("next", "")) if raw[filtered[pick]].get("next") != null else ""
		_call("DialogueManager.choose")
		dialogue_manager.choose(pick)
	route.append(step)
	_step = ""


## Walks the destination graph from the current location: edges whose
## condition holds first; failing that, the shortest raw path, satisfying each
## blocked hop's condition on the way.
func _go_to(location_id: String, depth: int) -> bool:
	if game_state.current_location == location_id:
		return true
	var path: Array[String] = _location_path(game_state.current_location, location_id, true)
	if path.is_empty():
		path = _location_path(game_state.current_location, location_id, false)
	if path.is_empty():
		return false
	for next in path:
		for destination in content_db.get_location(game_state.current_location).get("destinations", []):
			if str(destination.get("location_id", "")) == next and not _satisfy(destination.get("condition"), game_state.current_location, depth + 1):
				return false
		_step = "move %s" % next
		_call("Investigation.move_to")
		investigation.move_to(next)
		route.append({"kind": "move", "to": next})
		_step = ""
		if game_state.current_location != next:
			return false
	return true


func _location_path(from: String, to: String, passable_only: bool) -> Array[String]:
	var previous: Dictionary = {from: ""}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == to:
			break
		for destination in content_db.get_location(current).get("destinations", []):
			var next: String = str(destination.get("location_id", ""))
			if previous.has(next) or (passable_only and not _condition.evaluate(destination.get("condition"))):
				continue
			previous[next] = current
			queue.append(next)
	var path: Array[String] = []
	if not previous.has(to):
		return path
	var cursor: String = to
	while cursor != from:
		path.push_front(cursor)
		cursor = previous[cursor]
	return path


func _holds(key: String) -> bool:
	var parts: PackedStringArray = key.split(":", true, 1)
	match parts[0]:
		"evidence":
			return game_state.has_evidence(parts[1])
		"flag":
			return game_state.get_flag(parts[1])
	return game_state.has_seen("custom:%s" % parts[1])


# ---------------------------------------------------------------------------
# Runtime commands

func _open(unit_id: String) -> bool:
	var status: Dictionary = _runtime.get_unit_status(unit_id)
	if status.get("available", false) != true:
		var offer: Variant = _runtime.get_unit_definition(unit_id).get("offer_condition")
		_satisfy(offer, game_state.current_location, 0)
		status = _runtime.get_unit_status(unit_id)
	if status.get("available", false) != true:
		_fail("unit '%s' is not offered (%s) after acquiring its evidence: %s" % [unit_id, status.get("reason", ""), _condition.describe(_runtime.get_unit_definition(unit_id).get("offer_condition"))])
		return false
	_call("ChapterRuntime.open_unit")
	var opened: Dictionary = _runtime.open_unit(unit_id)
	route.append({"kind": "open", "unit": unit_id})
	if opened.get("ok", false) != true:
		_fail("opening unit '%s' was refused: %s" % [unit_id, opened.get("reason", "")])
		return false
	return true


func _perform(unit_id: String, command: String, args: Array = []) -> Dictionary:
	_step = "command %s/%s" % [unit_id, command]
	_call("ChapterRuntime.perform")
	var result: Dictionary = _runtime.perform(unit_id, command, args)
	route.append({"kind": "command", "unit": unit_id, "command": command, "args": args.duplicate()})
	_step = ""
	if result.get("ok", false) != true:
		_fail("command %s on '%s' was refused: %s" % [command, unit_id, result.get("reason", "")])
	return result


func _finish(unit_id: String) -> void:
	_call("ChapterRuntime.dismiss_feedback")
	_runtime.dismiss_feedback(unit_id)
	route.append({"kind": "dismiss", "unit": unit_id})
	_call("ChapterRuntime.close_unit")
	_runtime.close_unit()
	route.append({"kind": "close", "unit": unit_id})


func _expect(result: Dictionary, what: String) -> void:
	if result.get("ok", false) != true:
		_fail("%s was refused: %s" % [what, result.get("reason", "")])


func _linked(inventory_id: String) -> String:
	return str((_runtime.get_loop().get("evidence_links", {}) as Dictionary).get(inventory_id, ""))


func _inventory_for(deduction_id: String) -> String:
	var links: Dictionary = _runtime.get_loop().get("evidence_links", {})
	for inventory_id in links:
		if str(links[inventory_id]) == deduction_id:
			return str(inventory_id)
	return ""


func _call(name: String) -> void:
	calls.append(name)


func _fail(reason: String) -> Dictionary:
	if failure == "":
		failure = "%s (phase %s)" % [reason, _runtime.get_phase_id() if _runtime != null else "?"]
	return {}


func _reset() -> void:
	route = []
	calls = []
	acquisitions = []
	failure = ""
	_step = ""
	_visiting = {}
