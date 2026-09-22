class_name CoreLoopValidator
extends RefCounted
## Static validation of a chapter's "core_loop" section (Milestone 1.16 — see
## docs/core-loop-sandbox.md, "Validation"). Run from
## ContentValidator.validate() alongside the shared checks ContentValidator
## already owns (condition keys via _validate_condition, effect vocabulary via
## _validate_effects, translation completeness) — this file only adds what is
## specific to the chapter-run contract, the same split DeductionValidator
## uses for data/deductions/.
##
## Deliberately bounded — a contract checker for this one data shape, not a
## general quest validator or a solver:
##   * references: deduction case, mechanic rounds, evidence links, units,
##     phases, consequences, the owning case, the completion event;
##   * the phase list is a valid linear route (briefing first, each unit's
##     phases contiguous and in outcome order, every unit fully resolved);
##   * every required unit has a resolution path the player is GUARANTEED to
##     hold when it is offered (the offer condition's has_evidence leaves,
##     expanded over all/any, must each cover an authored accepted proof path
##     through evidence_links), and every such evidence item can be acquired;
##   * no unit is offered only by its own or a later consequence (a cycle);
##   * chapter completion is produced by the final phase's consequence and by
##     nothing earlier;
##   * sandbox markers are consistent (a non-canon deduction case can only
##     drive a canon:false chapter of a canon:false case) and no production
##     content points at a debug-only route.
## Milestone 1.17 (multi-chapter hardening, docs/core-loop-sandbox.md,
## "Validation"): evidence a consequence grants counts as acquirable only for
## LATER phases (an acquisition producer that arrives after the unit needs it
## is an error); every required offer-condition leaf needs a producer before
## the unit's phase — "nothing produces it" (only a debug override could) and
## "only another chapter produces it" (chapters never share run state) are told
## apart from a cycle; completion requirements and consequence ids are never
## shared with another chapter; no two B units re-ask one deduction; a unit's
## "documented_paths" must be real, reachable accepted proof paths. Those are
## ERRORS — each makes the route broken. Two smells are WARNINGS: a linked
## evidence item nothing can ever grant, and a consequence that ends a unit but
## unlocks nothing any condition reads.
## Deliberately still not a solver: the legal-path simulator
## (scenes/test/core_loop_route_simulator.gd) proves a route exists, in tests
## and the headless author report, never at boot.

const PROTOTYPE_LAYER := {
	CoreLoopUnit.MECHANIC_CLUE_CONNECTION: "prototype_b",
	CoreLoopUnit.MECHANIC_STATEMENT_CONTRADICTION: "prototype_a",
	CoreLoopUnit.MECHANIC_TIMELINE_RECONSTRUCTION: "prototype_c",
}
## Hard cap on has_evidence alternatives expanded from one offer condition —
## far above anything authored; beyond it the condition is reported instead of
## silently half-checked.
const MAX_ALTERNATIVES := 64


## Every {"unit", "outcome", "consequence"} a chapter's core_loop declares —
## shared with ContentValidator's dependency analysis and the Case Debugger's
## "known producers" so consequence effects are first-class producers.
static func consequences_of(chapter: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var loop: Variant = chapter.get("core_loop")
	if typeof(loop) != TYPE_DICTIONARY:
		return out
	for unit in DeductionEvaluator.dict_array((loop as Dictionary).get("units", [])):
		var consequences: Variant = unit.get("consequences", {})
		if typeof(consequences) != TYPE_DICTIONARY:
			continue
		for outcome in consequences:
			if typeof(consequences[outcome]) == TYPE_DICTIONARY:
				out.append({"unit": str(unit.get("id", "")), "outcome": str(outcome), "consequence": consequences[outcome]})
	return out


## Every translation key the section references, as [key, context] pairs, for
## ContentValidator's missing-translation check.
static func collect_text_keys(chapter_id: String, chapter: Dictionary) -> Array[Array]:
	var keys: Array[Array] = []
	var loop: Variant = chapter.get("core_loop")
	if typeof(loop) != TYPE_DICTIONARY:
		return keys
	var ctx: String = 'Chapter "%s" core_loop' % chapter_id
	for section in ["briefing", "result"]:
		var block: Variant = loop.get(section, {})
		if typeof(block) == TYPE_DICTIONARY:
			for field in ["title", "text"]:
				keys.append([block.get(field, ""), "%s %s %s" % [ctx, section, field]])
	for unit in DeductionEvaluator.dict_array(loop.get("units", [])):
		keys.append([unit.get("title", ""), '%s unit "%s" title' % [ctx, unit.get("id", "")]])
	for entry in consequences_of(chapter):
		keys.append([(entry["consequence"] as Dictionary).get("summary", ""), '%s unit "%s" consequence "%s" summary' % [ctx, entry["unit"], entry["outcome"]]])
	for phase in DeductionEvaluator.dict_array(loop.get("phases", [])):
		keys.append([phase.get("objective", ""), '%s phase "%s" objective' % [ctx, phase.get("id", "")]])
	return keys


## Validates one chapter's core_loop. `base_producers` is {"flags", "evidence",
## "interactions"} -> Dictionary sets of everything a NON-core-loop effect
## (dialogue, event, chapter entry) can produce — see
## ContentValidator._collect_effect_targets_everywhere(..., false).
static func validate_chapter(chapter_id: String, chapter: Dictionary, base_producers: Dictionary, errors: Array[String], warnings: Array[String] = []) -> void:
	var loop: Variant = chapter.get("core_loop")
	if loop == null:
		return
	var ctx: String = 'Chapter "%s" core_loop' % chapter_id
	if typeof(loop) != TYPE_DICTIONARY:
		errors.append("%s must be an object" % ctx)
		return
	if PrototypeContext.count((loop as Dictionary).get("format")) != ChapterRuntime.LOOP_FORMAT:
		errors.append('%s format must be %d' % [ctx, ChapterRuntime.LOOP_FORMAT])
		return

	var case_def: Dictionary = ContentDB.get_deduction_case(str(loop.get("deduction_case", "")))
	if case_def.is_empty():
		errors.append('%s deduction_case "%s" is not a known deduction case' % [ctx, loop.get("deduction_case", "")])
		return
	_validate_markers(chapter_id, loop, case_def, ctx, errors)
	_validate_debug_free(loop, ctx, errors)
	for section in ["briefing", "result"]:
		if typeof(loop.get(section)) != TYPE_DICTIONARY:
			errors.append('%s must declare a "%s" object with a title and text' % [ctx, section])
	var links: Dictionary = _validate_links(loop, case_def, ctx, errors)
	var units: Dictionary = _validate_units(chapter_id, loop, case_def, ctx, errors)
	var phase_of: Dictionary = _validate_phases(loop, units, ctx, errors)
	_validate_consequence_ids_unique(chapter_id, chapter, ctx, errors)
	if units.is_empty() or phase_of.is_empty():
		return
	var produced: Dictionary = consequence_products(chapter, phase_of)
	var first_phase: Dictionary = _first_phases(units, phase_of)
	var elsewhere: Dictionary = _other_chapter_products(chapter_id)
	_validate_resolution_paths(units, case_def, links, base_producers, produced, first_phase, ctx, errors)
	_validate_documented_paths(units, case_def, links, base_producers, produced, first_phase, ctx, errors)
	_validate_offer_order(units, base_producers, produced, elsewhere, first_phase, loop, ctx, errors)
	_validate_completion(chapter_id, chapter, loop, units, elsewhere, ctx, errors)
	_validate_unit_targets(units, case_def, ctx, errors)
	_validate_link_producers(links, base_producers, produced, ctx, warnings)
	_validate_consequences_consumed(loop, units, links, ctx, warnings)


## Expands a condition into the alternative sets of evidence ids it
## guarantees (has_evidence leaves over "all"/"any"); any other leaf, and
## "not", guarantees no evidence. [{}] for no condition. [] only when the
## expansion would exceed MAX_ALTERNATIVES.
static func evidence_alternatives(condition: Variant) -> Array[Dictionary]:
	var none: Array[Dictionary] = [{}]
	if typeof(condition) != TYPE_DICTIONARY:
		return none
	if condition.has("has_evidence"):
		var single: Array[Dictionary] = [{str(condition.get("has_evidence", "")): true}]
		return single
	if condition.has("all") and typeof(condition.get("all")) == TYPE_ARRAY:
		var product: Array[Dictionary] = [{}]
		for sub in condition.get("all"):
			var next: Array[Dictionary] = []
			for left in product:
				for right in evidence_alternatives(sub):
					var merged: Dictionary = left.duplicate()
					merged.merge(right)
					next.append(merged)
			if next.size() > MAX_ALTERNATIVES:
				var overflow: Array[Dictionary] = []
				return overflow
			product = next
		return product
	if condition.has("any") and typeof(condition.get("any")) == TYPE_ARRAY:
		var union: Array[Dictionary] = []
		for sub in condition.get("any"):
			var alternatives: Array[Dictionary] = evidence_alternatives(sub)
			if alternatives.is_empty():
				return alternatives
			union.append_array(alternatives)
		if union.size() > MAX_ALTERNATIVES:
			union.clear()
		return union if not (condition.get("any") as Array).is_empty() else none
	return none


# ---------------------------------------------------------------------------
# Private

static func _validate_markers(chapter_id: String, loop: Dictionary, case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var canon: Variant = loop.get("canon")
	if typeof(canon) != TYPE_BOOL:
		errors.append('%s must declare "canon": true or false' % ctx)
		return
	var deduction_canon: bool = (case_def.get("metadata", {}) as Dictionary).get("canon", true) != false
	if not deduction_canon and canon:
		errors.append('%s is marked canon but drives the non-canon deduction case "%s" — sandbox content must declare "canon": false' % [ctx, case_def.get("id", "")])
	var owners: Array[String] = []
	for case_id in ContentDB.get_all_case_ids():
		if (ContentDB.get_case(String(case_id)).get("chapters", []) as Array).has(chapter_id):
			owners.append(String(case_id))
	if owners.size() != 1:
		errors.append('%s must belong to exactly one case\'s "chapters" list (found %d) — otherwise New Game can never reach it' % [ctx, owners.size()])
		return
	var owner: Dictionary = ContentDB.get_case(owners[0])
	var owner_canon: bool = (owner.get("metadata", {}) as Dictionary).get("canon", true) != false
	if not canon and owner_canon:
		errors.append('%s is non-canon but its case "%s" does not declare metadata.canon: false' % [ctx, owners[0]])


## Production content must never route through debug-only tooling: no scene
## or script paths anywhere in the section (mechanics are chosen by a closed
## vocabulary, never by path).
static func _validate_debug_free(value: Variant, ctx: String, errors: Array[String]) -> void:
	match typeof(value):
		TYPE_STRING:
			if (value as String).begins_with("res://") or (value as String).begins_with("user://"):
				errors.append('%s references the path "%s" — production content may not name scenes or scripts (Deduction Lab/DebugPanel are debug-only)' % [ctx, value])
		TYPE_DICTIONARY:
			for key in value:
				_validate_debug_free(value[key], ctx, errors)
		TYPE_ARRAY:
			for entry in value:
				_validate_debug_free(entry, ctx, errors)


## inventory evidence id -> deduction evidence id, for well-formed links.
static func _validate_links(loop: Dictionary, case_def: Dictionary, ctx: String, errors: Array[String]) -> Dictionary:
	var links: Dictionary = {}
	var raw: Variant = loop.get("evidence_links", {})
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append('%s evidence_links must be an object' % ctx)
		return links
	var targets: Dictionary = {}
	for evidence_id in raw:
		var target: Variant = raw[evidence_id]
		if ContentDB.get_evidence(str(evidence_id)).is_empty():
			errors.append('%s evidence_links references unknown evidence "%s"' % [ctx, evidence_id])
			continue
		if not (target is String) or DeductionEvaluator.find_evidence(case_def, target).is_empty():
			errors.append('%s evidence_links maps "%s" to "%s", which is not evidence of deduction case "%s"' % [ctx, evidence_id, target, case_def.get("id", "")])
			continue
		if targets.has(target):
			errors.append('%s evidence_links maps both "%s" and "%s" to "%s"' % [ctx, targets[target], evidence_id, target])
			continue
		targets[target] = evidence_id
		links[str(evidence_id)] = target
	return links


## unit id -> definition, for units whose own shape is valid.
static func _validate_units(chapter_id: String, loop: Dictionary, case_def: Dictionary, ctx: String, errors: Array[String]) -> Dictionary:
	var units: Dictionary = {}
	var raw: Variant = loop.get("units")
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		errors.append('%s must declare a non-empty "units" array' % ctx)
		return units
	var consequence_ids: Dictionary = {}
	for definition in DeductionEvaluator.dict_array(raw):
		var unit_id: String = str(definition.get("id", ""))
		var unit_ctx: String = '%s unit "%s"' % [ctx, unit_id]
		if unit_id == "" or units.has(unit_id):
			errors.append('%s has a unit with a missing or duplicate id "%s"' % [ctx, unit_id])
			continue
		var mechanic: String = str(definition.get("mechanic", ""))
		if not CoreLoopUnit.MECHANICS.has(mechanic):
			errors.append('%s mechanic "%s" is not a production mechanic — supported: %s' % [unit_ctx, mechanic, ", ".join(CoreLoopUnit.MECHANICS)])
			continue
		var layer: Variant = case_def.get(PROTOTYPE_LAYER[mechanic])
		if typeof(layer) != TYPE_DICTIONARY:
			errors.append('%s needs deduction case "%s" to declare "%s"' % [unit_ctx, case_def.get("id", ""), PROTOTYPE_LAYER[mechanic]])
			continue
		if not _validate_unit_rounds(definition, mechanic, layer, unit_ctx, errors):
			continue
		var consequences: Variant = definition.get("consequences", {})
		if typeof(consequences) != TYPE_DICTIONARY or not (consequences as Dictionary).has(CoreLoopUnit.OUTCOME_RESOLVED):
			errors.append('%s must declare a "resolved" consequence — a required unit with no consequence produces no progression' % unit_ctx)
			continue
		var ok := true
		for outcome in consequences:
			var consequence: Variant = consequences[outcome]
			if not (CoreLoopUnit.OUTCOMES[mechanic] as Array).has(outcome):
				errors.append('%s declares a consequence for "%s", which %s never produces' % [unit_ctx, outcome, mechanic])
				ok = false
				continue
			var consequence_id: String = str((consequence as Dictionary).get("id", "")) if typeof(consequence) == TYPE_DICTIONARY else ""
			if consequence_id == "" or consequence_ids.has(consequence_id):
				errors.append('%s consequence "%s" has a missing or duplicate id "%s"' % [unit_ctx, outcome, consequence_id])
				ok = false
				continue
			consequence_ids[consequence_id] = true
		if ok:
			units[unit_id] = definition
	return units


static func _validate_unit_rounds(definition: Dictionary, mechanic: String, layer: Dictionary, unit_ctx: String, errors: Array[String]) -> bool:
	var round_ids: Array[String] = []
	for proto_round in DeductionEvaluator.dict_array(layer.get("rounds", [])):
		round_ids.append(str(proto_round.get("id", "")))
	match mechanic:
		CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
			if not round_ids.has(str(definition.get("round", ""))):
				errors.append('%s round "%s" is not a prototype_b round' % [unit_ctx, definition.get("round", "")])
				return false
		CoreLoopUnit.MECHANIC_STATEMENT_CONTRADICTION:
			var wanted: Variant = definition.get("rounds")
			if not PrototypeContext.is_string_list(wanted) or (wanted as Array).is_empty():
				errors.append('%s must list its prototype_a "rounds"' % unit_ctx)
				return false
			var seen: Dictionary = {}
			for round_id in wanted:
				if not round_ids.has(round_id) or seen.has(round_id):
					errors.append('%s round "%s" is unknown or repeated' % [unit_ctx, round_id])
					return false
				seen[round_id] = true
	return true


## phase index of each unit's LAST phase, keyed "unit|outcome" -> index; {} on
## a broken route.
static func _validate_phases(loop: Dictionary, units: Dictionary, ctx: String, errors: Array[String]) -> Dictionary:
	var phase_of: Dictionary = {}
	var raw: Variant = loop.get("phases")
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		errors.append('%s must declare a non-empty "phases" array' % ctx)
		return phase_of
	var phases: Array[Dictionary] = DeductionEvaluator.dict_array(raw)
	var seen_ids: Dictionary = {}
	var last_unit: String = ""
	var closed_units: Dictionary = {}
	var broken := false
	for i in phases.size():
		var phase: Dictionary = phases[i]
		var phase_id: String = str(phase.get("id", ""))
		var phase_ctx: String = '%s phase "%s"' % [ctx, phase_id]
		if phase_id == "" or seen_ids.has(phase_id):
			errors.append('%s has a phase with a missing or duplicate id "%s"' % [ctx, phase_id])
			broken = true
			continue
		seen_ids[phase_id] = true
		var kind: String = str(phase.get("kind", ChapterRuntime.PHASE_KIND_UNIT))
		if kind == ChapterRuntime.PHASE_KIND_BRIEFING:
			if i != 0:
				errors.append('%s is a briefing but not the first phase — a briefing can only open the chapter' % phase_ctx)
				broken = true
			continue
		if kind != ChapterRuntime.PHASE_KIND_UNIT:
			errors.append('%s kind "%s" is unknown' % [phase_ctx, kind])
			broken = true
			continue
		var unit_id: String = str(phase.get("unit", ""))
		var outcome: String = str(phase.get("completes_on", ""))
		if not units.has(unit_id):
			errors.append('%s references unknown or invalid unit "%s"' % [phase_ctx, unit_id])
			broken = true
			continue
		var outcomes: Array = CoreLoopUnit.OUTCOMES[str(units[unit_id].get("mechanic", ""))]
		if not outcomes.has(outcome) or not (units[unit_id].get("consequences", {}) as Dictionary).has(outcome):
			errors.append('%s completes_on "%s", which unit "%s" has no consequence for' % [phase_ctx, outcome, unit_id])
			broken = true
			continue
		if closed_units.has(unit_id) or phase_of.has("%s|%s" % [unit_id, outcome]):
			errors.append('%s returns to unit "%s" after another unit — a unit\'s phases must be contiguous and never repeat an outcome' % [phase_ctx, unit_id])
			broken = true
			continue
		if last_unit != "" and last_unit != unit_id:
			closed_units[last_unit] = true
		for earlier in outcomes.slice(0, outcomes.find(outcome)):
			if not phase_of.has("%s|%s" % [unit_id, earlier]) and (units[unit_id].get("consequences", {}) as Dictionary).has(earlier):
				errors.append('%s completes on "%s" before the "%s" phase — e.g. the final claim can never come before the timeline is accepted' % [phase_ctx, outcome, earlier])
				broken = true
		phase_of["%s|%s" % [unit_id, outcome]] = i
		last_unit = unit_id
	for unit_id in units:
		if not phase_of.has("%s|%s" % [unit_id, CoreLoopUnit.OUTCOME_RESOLVED]):
			errors.append('%s unit "%s" is never fully resolved by any phase — it is unreachable or leaves the chapter unfinishable' % [ctx, unit_id])
			broken = true
	if broken:
		phase_of.clear()
	return phase_of


## Every unit must have an authored accepted path the player is guaranteed to
## hold whenever the unit is offered — and a path whose every item can
## actually be acquired BEFORE the unit's phase: granted by normal play
## (dialogue/event/chapter-entry effects) or by an EARLIER phase's
## consequence. Evidence only a same-or-later consequence grants arrives after
## the unit needs it.
static func _validate_resolution_paths(units: Dictionary, case_def: Dictionary, links: Dictionary, base_producers: Dictionary, produced: Dictionary, first_phase: Dictionary, ctx: String, errors: Array[String]) -> void:
	for unit_id in units:
		var definition: Dictionary = units[unit_id]
		var mechanic: String = str(definition.get("mechanic", ""))
		if mechanic == CoreLoopUnit.MECHANIC_TIMELINE_RECONSTRUCTION:
			continue  # Needs no evidence; DeductionValidator proves prototype_c solvable.
		var unit_ctx: String = '%s unit "%s"' % [ctx, unit_id]
		var acquirable: Dictionary = {}  # deduction evidence id -> true when linked AND available before the unit
		var late: Dictionary = {}  # deduction evidence id -> true when linked but granted only at/after the unit
		for inventory_id in links:
			var key: String = "evidence:%s" % inventory_id
			if available_before(key, int(first_phase[unit_id]), base_producers, produced):
				acquirable[links[inventory_id]] = true
			elif produced.has(key):
				late[links[inventory_id]] = true
		var groups: Array = _requirement_groups(definition, mechanic, case_def)
		if groups.is_empty():
			errors.append('%s has no authored accepted proof path within its prototype pool' % unit_ctx)
			continue
		if not _groups_satisfied(groups, acquirable):
			if _groups_satisfied(groups, acquirable.merged(late)):
				errors.append('%s needs evidence that only a consequence of its own or a later phase grants — the acquisition producer arrives after the unit requires it' % unit_ctx)
			else:
				errors.append('%s has no accepted proof path made only of evidence the player can acquire (linked in evidence_links AND granted by some add_evidence effect)' % unit_ctx)
			continue
		var alternatives: Array[Dictionary] = evidence_alternatives(definition.get("offer_condition"))
		if alternatives.is_empty():
			errors.append('%s offer_condition expands to more than %d evidence alternatives — simplify it' % [unit_ctx, MAX_ALTERNATIVES])
			continue
		for held_inventory in alternatives:
			var held: Dictionary = {}
			for inventory_id in held_inventory:
				if links.has(inventory_id):
					held[links[inventory_id]] = true
			if not _groups_satisfied(groups, held):
				errors.append('%s can be offered holding only %s, which covers no accepted proof path — the player could open it with no way to resolve it' % [unit_ctx, held_inventory.keys()])
				break


## An author's claim that specific clue sets resolve a clue_connection unit
## ("documented_paths": inventory evidence ids) — read by the legal-path
## simulator and the author report. Each must be an authored accepted proof
## path of the unit's round (mapped through evidence_links) whose every item
## is acquirable before the unit's phase; otherwise the documentation promises
## a route the player can't take.
static func _validate_documented_paths(units: Dictionary, case_def: Dictionary, links: Dictionary, base_producers: Dictionary, produced: Dictionary, first_phase: Dictionary, ctx: String, errors: Array[String]) -> void:
	for unit_id in units:
		var definition: Dictionary = units[unit_id]
		if not definition.has("documented_paths"):
			continue
		var unit_ctx: String = '%s unit "%s"' % [ctx, unit_id]
		var raw: Variant = definition.get("documented_paths")
		if str(definition.get("mechanic", "")) != CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
			errors.append('%s documented_paths is only supported on clue_connection units' % unit_ctx)
			continue
		if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
			errors.append('%s documented_paths must be a non-empty array of evidence id lists' % unit_ctx)
			continue
		var accepted: Array = accepted_paths(definition, case_def)
		for i in (raw as Array).size():
			var path: Variant = raw[i]
			if not PrototypeContext.is_string_list(path) or (path as Array).is_empty():
				errors.append('%s documented path %d must be a non-empty list of evidence ids' % [unit_ctx, i + 1])
				continue
			var mapped: Array[String] = []
			var unlinked: Array[String] = []
			var unreachable: Array[String] = []
			for inventory_id in path:
				if not links.has(inventory_id):
					unlinked.append(inventory_id)
					continue
				mapped.append(str(links[inventory_id]))
				if not available_before("evidence:%s" % inventory_id, int(first_phase[unit_id]), base_producers, produced):
					unreachable.append(inventory_id)
			if not unlinked.is_empty():
				errors.append('%s documented path %d names %s, which evidence_links does not link' % [unit_ctx, i + 1, unlinked])
			elif not accepted.any(func(candidate: Array) -> bool: return same_set(candidate, mapped)):
				errors.append('%s documented path %d %s is not an authored accepted proof path of its round — it documents an answer the evaluator rejects' % [unit_ctx, i + 1, path])
			elif not unreachable.is_empty():
				errors.append('%s documented path %d is not reachable: %s cannot be acquired before the unit is offered' % [unit_ctx, i + 1, unreachable])


## What resolving a unit takes, as requirement GROUPS: every group must be
## met by at least one of its alternative paths (each an Array[String] of
## deduction evidence ids). B: one group — the authored proof sets matching
## the round's relation and slot count, inside prototype_b's pool. A: one
## group per required refutation of its rounds — that statement's
## single-evidence "refutes" proof sets inside prototype_a's pool. [] when
## some group has no path at all.
static func _requirement_groups(definition: Dictionary, mechanic: String, case_def: Dictionary) -> Array:
	var groups: Array = []
	var layer: Dictionary = case_def.get(PROTOTYPE_LAYER[mechanic], {})
	var pool: Array[String] = DeductionEvaluator.string_array(layer.get("evidence_pool", []))
	var round_ids: Array[String] = DeductionEvaluator.string_array(definition.get("rounds", []))
	if mechanic == CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
		round_ids = [str(definition.get("round", ""))]
	for proto_round in DeductionEvaluator.dict_array(layer.get("rounds", [])):
		if not round_ids.has(str(proto_round.get("id", ""))):
			continue
		if mechanic == CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
			var target: String = str(proto_round.get("target", ""))
			groups.append(_paths_for(case_def, target, str(proto_round.get("relation", "")), int(proto_round.get("slot_count", 0)), pool))
		else:
			for claim_id in DeductionEvaluator.string_array(proto_round.get("required_refutations", [])):
				groups.append(_paths_for(case_def, claim_id, "refutes", 1, pool))
	for group in groups:
		if (group as Array).is_empty():
			return []
	return groups


static func _paths_for(case_def: Dictionary, claim_id: String, relation: String, size: int, pool: Array[String]) -> Array:
	var paths: Array = []
	for proof_set in DeductionEvaluator.dict_array(DeductionEvaluator.find_claim(case_def, claim_id).get("proof_sets", [])):
		var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
		if str(proof_set.get("relation", "")) == relation and requires.size() == size and requires.all(func(item: String) -> bool: return pool.has(item)):
			paths.append(requires)
	return paths


static func _groups_satisfied(groups: Array, held: Dictionary) -> bool:
	for group in groups:
		if not (group as Array).any(func(path: Array) -> bool: return path.all(func(item: String) -> bool: return held.has(item))):
			return false
	return true


## Every REQUIRED leaf of a unit's offer_condition (top level or inside "all")
## needs a producer before the unit's first phase: normal play, or an earlier
## phase's consequence. Otherwise the unit — and every phase after it — is
## unreachable, and the message says why: only its own or a later
## consequence produces it (a cycle); only ANOTHER chapter's consequence does
## (chapters never share run state — a case starts from a fresh GameState); or
## nothing does (only a debug override could ever satisfy it).
static func _validate_offer_order(units: Dictionary, base_producers: Dictionary, produced: Dictionary, elsewhere: Dictionary, first_phase: Dictionary, loop: Dictionary, ctx: String, errors: Array[String]) -> void:
	var phases: Array[Dictionary] = DeductionEvaluator.dict_array(loop.get("phases", []))
	for unit_id in units:
		var index: int = int(first_phase[unit_id])
		var phase_id: String = str(phases[index].get("id", "")) if index < phases.size() else ""
		var flags: Dictionary = {}
		var evidence: Dictionary = {}
		var interactions: Dictionary = {}
		ContentValidator._collect_condition_requirements((units[unit_id] as Dictionary).get("offer_condition"), flags, evidence, interactions)
		var keys: Array[String] = []
		for flag in flags:
			keys.append("flag:%s" % flag)
		for evidence_id in evidence:
			keys.append("evidence:%s" % evidence_id)
		for interaction in interactions:
			keys.append("interaction:%s" % interaction)
		for key in keys:
			if available_before(key, index, base_producers, produced):
				continue
			var what: String = _describe_key(key)
			if produced.has(key):
				errors.append('%s unit "%s" is offered only once %s, but only its own or a later phase\'s consequence produces it — a dependency cycle' % [ctx, unit_id, what])
			elif elsewhere.has(key):
				errors.append('%s unit "%s" is offered only once %s, which only chapter "%s"\'s consequence produces — chapters never share run state, so phase "%s" is unreachable' % [ctx, unit_id, what, elsewhere[key], phase_id])
			else:
				errors.append('%s unit "%s" can never be offered: nothing in content produces %s (only a debug override could), so phase "%s" is unreachable' % [ctx, unit_id, what, phase_id])


## The chapter's completion_event must be produced by the FINAL phase's
## consequence — and by no earlier one, or CaseManager would complete the
## chapter while the route still has phases left.
static func _validate_completion(chapter_id: String, chapter: Dictionary, loop: Dictionary, units: Dictionary, elsewhere: Dictionary, ctx: String, errors: Array[String]) -> void:
	var event: Dictionary = ContentDB.get_event(str(chapter.get("completion_event", "")))
	if event.is_empty():
		errors.append('%s needs a chapter completion_event — the final consequence has nothing to complete' % ctx)
		return
	for other_id in ContentDB.get_all_chapters():
		if String(other_id) != chapter_id and str(ContentDB.get_chapter(String(other_id)).get("completion_event", "")) == str(event.get("id", "")):
			errors.append('%s shares completion_event "%s" with chapter "%s" — completing one would complete (or pre-fire and block) the other' % [ctx, event.get("id", ""), other_id])
	var required_flags: Dictionary = {}
	var required_evidence: Dictionary = {}
	var required_interactions: Dictionary = {}
	ContentValidator._collect_condition_requirements(event.get("conditions"), required_flags, required_evidence, required_interactions)
	if required_flags.is_empty() and required_interactions.is_empty():
		errors.append('%s completion_event "%s" requires no flag or interaction — it could fire before the chapter\'s route is finished' % [ctx, event.get("id", "")])
		return
	for key in _keys_of(required_flags, "flag") + _keys_of(required_interactions, "interaction"):
		if elsewhere.has(key):
			errors.append('%s completion_event "%s" needs %s, which chapter "%s"\'s consequence also produces — one chapter\'s completion must never satisfy another\'s' % [ctx, event.get("id", ""), _describe_key(key), elsewhere[key]])
	var phases: Array[Dictionary] = DeductionEvaluator.dict_array(loop.get("phases", []))
	var final_phase: Dictionary = phases[phases.size() - 1]
	var final_key: String = "%s|%s" % [final_phase.get("unit", ""), final_phase.get("completes_on", "")]
	for entry in consequences_of(chapter):
		var flags: Dictionary = {}
		var evidence: Dictionary = {}
		var interactions: Dictionary = {}
		ContentValidator._collect_effect_targets((entry["consequence"] as Dictionary).get("effects", []), flags, evidence, interactions)
		var produces_completion: bool = required_flags.keys().any(func(flag: Variant) -> bool: return flags.has(flag)) \
			or required_interactions.keys().any(func(interaction: Variant) -> bool: return interactions.has(interaction))
		var is_final: bool = "%s|%s" % [entry["unit"], entry["outcome"]] == final_key
		if is_final:
			for flag in required_flags:
				if not flags.has(flag):
					errors.append('%s final consequence never sets flag "%s", which completion_event "%s" requires — the chapter can never complete' % [ctx, flag, event.get("id", "")])
			for interaction in required_interactions:
				if not interactions.has(interaction):
					errors.append('%s final consequence never marks "%s", which completion_event "%s" requires — the chapter can never complete' % [ctx, interaction, event.get("id", "")])
		elif produces_completion:
			errors.append('%s consequence of unit "%s" (%s) already produces part of completion_event "%s" before the final phase' % [ctx, entry["unit"], entry["outcome"], event.get("id", "")])


## No two clue_connection units of one chapter may target the same deduction:
## the run shares ONE session, so the later unit would re-ask a deduction the
## session already holds — never an accidental second resolution, but never a
## real question either.
static func _validate_unit_targets(units: Dictionary, case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var seen: Dictionary = {}  # target claim id -> unit id
	var rounds: Dictionary = {}
	for proto_round in DeductionEvaluator.dict_array((case_def.get(PROTOTYPE_LAYER[CoreLoopUnit.MECHANIC_CLUE_CONNECTION], {}) as Dictionary).get("rounds", [])):
		rounds[str(proto_round.get("id", ""))] = proto_round
	for unit_id in units:
		var definition: Dictionary = units[unit_id]
		if str(definition.get("mechanic", "")) != CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
			continue
		var target: String = str((rounds.get(str(definition.get("round", "")), {}) as Dictionary).get("target", ""))
		if seen.has(target):
			errors.append('%s units "%s" and "%s" both ask for deduction "%s" — a later B unit must target a deduction the shared session has not resolved yet' % [ctx, seen[target], unit_id, target])
		else:
			seen[target] = unit_id


## Consequence ids are the attribution key in saves, recordings and the Case
## Debugger — unique across EVERY core-loop chapter, not only within one.
static func _validate_consequence_ids_unique(chapter_id: String, chapter: Dictionary, ctx: String, errors: Array[String]) -> void:
	var others: Dictionary = {}  # consequence id -> chapter id
	for other_id in ContentDB.get_all_chapters():
		if String(other_id) == chapter_id:
			continue
		for entry in consequences_of(ContentDB.get_chapter(String(other_id))):
			others[str((entry["consequence"] as Dictionary).get("id", ""))] = String(other_id)
	for entry in consequences_of(chapter):
		var consequence_id: String = str((entry["consequence"] as Dictionary).get("id", ""))
		if consequence_id != "" and others.has(consequence_id):
			errors.append('%s consequence id "%s" is also used by chapter "%s" — attribution in saves, recordings and the Case Debugger would be ambiguous' % [ctx, consequence_id, others[consequence_id]])


## WARNING: an evidence_links entry nothing can ever grant (no add_evidence in
## normal play and none in this chapter's consequences) is a dead link.
static func _validate_link_producers(links: Dictionary, base_producers: Dictionary, produced: Dictionary, ctx: String, warnings: Array[String]) -> void:
	for inventory_id in links:
		var key: String = "evidence:%s" % inventory_id
		if not (base_producers.get("evidence", {}) as Dictionary).has(inventory_id) and not produced.has(key):
			warnings.append('%s links evidence "%s", but nothing can ever grant it (no add_evidence producer) — a dead link' % [ctx, inventory_id])


## WARNING: a consequence that ends a unit and moves the route to ANOTHER unit
## should visibly change the investigation (1.15B: B1 unlocks the
## confrontation, A opens new evidence/interaction/location). One whose
## effects produce nothing any condition in content reads, and no linked
## evidence, unlocks nothing — the phase changes but the world does not.
## (C's timeline_accepted leads to the same unit's final claim and is exempt;
## the final consequence is checked against the completion event instead.)
static func _validate_consequences_consumed(loop: Dictionary, units: Dictionary, links: Dictionary, ctx: String, warnings: Array[String]) -> void:
	var referenced: Dictionary = {}
	ContentValidator.for_each_content_condition(func(condition: Variant) -> void: _collect_references(condition, referenced))
	var phases: Array[Dictionary] = DeductionEvaluator.dict_array(loop.get("phases", []))
	for i in phases.size() - 1:
		var unit_id: String = str(phases[i].get("unit", ""))
		var next_unit: String = str(phases[i + 1].get("unit", ""))
		if unit_id == "" or next_unit == unit_id or not units.has(unit_id):
			continue
		var consequence: Dictionary = ((units[unit_id] as Dictionary).get("consequences", {}) as Dictionary).get(str(phases[i].get("completes_on", "")), {})
		var flags: Dictionary = {}
		var evidence: Dictionary = {}
		var interactions: Dictionary = {}
		ContentValidator._collect_effect_targets(consequence.get("effects", []), flags, evidence, interactions)
		var used: bool = evidence.keys().any(func(evidence_id: Variant) -> bool: return links.has(evidence_id) or referenced.has("evidence:%s" % evidence_id))
		for key in _keys_of(flags, "flag") + _keys_of(interactions, "interaction"):
			used = used or referenced.has(key)
		if not used:
			warnings.append('%s consequence "%s" ends unit "%s" but unlocks nothing any condition reads — the phase advances while the investigation stays the same' % [ctx, consequence.get("id", ""), unit_id])


# ---------------------------------------------------------------------------
# Shared analysis helpers — public so the author report reuses them instead of
# re-deriving the route (scripts/debug/core_loop_author_report.gd).

## "flag:x" / "evidence:y" / "interaction:z" -> the EARLIEST phase index whose
## consequence produces it, for this chapter's own consequences.
static func consequence_products(chapter: Dictionary, phase_of: Dictionary) -> Dictionary:
	var produced: Dictionary = {}
	for entry in consequences_of(chapter):
		var index: int = int(phase_of.get("%s|%s" % [entry["unit"], entry["outcome"]], 1 << 30))
		var flags: Dictionary = {}
		var evidence: Dictionary = {}
		var interactions: Dictionary = {}
		ContentValidator._collect_effect_targets((entry["consequence"] as Dictionary).get("effects", []), flags, evidence, interactions)
		for key in _keys_of(flags, "flag") + _keys_of(evidence, "evidence") + _keys_of(interactions, "interaction"):
			produced[key] = mini(int(produced.get(key, 1 << 30)), index)
	return produced


## True when `key` is produced by normal play (base producers) or by a
## consequence of a phase strictly before `phase_index`.
static func available_before(key: String, phase_index: int, base_producers: Dictionary, produced: Dictionary) -> bool:
	var parts: PackedStringArray = key.split(":", true, 1)
	var bucket: String = {"flag": "flags", "evidence": "evidence", "interaction": "interactions"}.get(parts[0], "")
	if (base_producers.get(bucket, {}) as Dictionary).has(parts[1]):
		return true
	return int(produced.get(key, 1 << 30)) < phase_index


## The authored accepted proof paths (deduction evidence ids) of a B unit's
## round — relation and slot count matching, inside prototype_b's pool.
static func accepted_paths(definition: Dictionary, case_def: Dictionary) -> Array:
	var layer: Dictionary = case_def.get(PROTOTYPE_LAYER[CoreLoopUnit.MECHANIC_CLUE_CONNECTION], {})
	for proto_round in DeductionEvaluator.dict_array(layer.get("rounds", [])):
		if str(proto_round.get("id", "")) == str(definition.get("round", "")):
			return _paths_for(case_def, str(proto_round.get("target", "")), str(proto_round.get("relation", "")), int(proto_round.get("slot_count", 0)), DeductionEvaluator.string_array(layer.get("evidence_pool", [])))
	return []


static func same_set(a: Array, b: Array) -> bool:
	return a.size() == b.size() and a.all(func(item: Variant) -> bool: return b.has(item))


## "unit|outcome" -> phase index for a well-formed route, {} otherwise — the
## same structure validate_chapter() builds, without reporting anything.
static func phase_index_of(loop: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var phases: Array[Dictionary] = DeductionEvaluator.dict_array(loop.get("phases", []))
	for i in phases.size():
		if str(phases[i].get("kind", ChapterRuntime.PHASE_KIND_UNIT)) == ChapterRuntime.PHASE_KIND_UNIT:
			out["%s|%s" % [phases[i].get("unit", ""), phases[i].get("completes_on", "")]] = i
	return out


static func _first_phases(units: Dictionary, phase_of: Dictionary) -> Dictionary:
	var first: Dictionary = {}
	for unit_id in units:
		first[unit_id] = 1 << 30
		for key in phase_of:
			if (key as String).begins_with("%s|" % unit_id):
				first[unit_id] = mini(int(first[unit_id]), int(phase_of[key]))
	return first


## Everything OTHER core-loop chapters' consequences produce: key -> chapter id.
static func _other_chapter_products(chapter_id: String) -> Dictionary:
	var out: Dictionary = {}
	for other_id in ContentDB.get_all_chapters():
		if String(other_id) == chapter_id:
			continue
		for key in consequence_products(ContentDB.get_chapter(String(other_id)), {}):
			out[key] = String(other_id)
	return out


## Every flag/evidence/interaction a condition mentions anywhere — inside
## "any" and "not" too (a READ, unlike _collect_condition_requirements).
static func _collect_references(condition: Variant, out: Dictionary) -> void:
	if typeof(condition) != TYPE_DICTIONARY:
		return
	for key in ["all", "any"]:
		if typeof(condition.get(key)) == TYPE_ARRAY:
			for sub in condition.get(key):
				_collect_references(sub, out)
	if condition.has("not"):
		_collect_references(condition.get("not"), out)
	if condition.has("flag"):
		out["flag:%s" % condition.get("flag", "")] = true
	if condition.has("has_evidence"):
		out["evidence:%s" % condition.get("has_evidence", "")] = true
	if condition.has("interaction_complete"):
		out["interaction:%s" % condition.get("interaction_complete", "")] = true


static func _keys_of(set_dict: Dictionary, kind: String) -> Array[String]:
	var keys: Array[String] = []
	for id in set_dict:
		keys.append("%s:%s" % [kind, id])
	return keys


static func _describe_key(key: String) -> String:
	var parts: PackedStringArray = key.split(":", true, 1)
	match parts[0]:
		"flag":
			return 'flag "%s" is set' % parts[1]
		"evidence":
			return 'evidence "%s" is held' % parts[1]
	return 'interaction "%s" completes' % parts[1]
