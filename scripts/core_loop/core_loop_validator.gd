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
## Every finding is an ERROR: each one makes the playable route broken, not
## merely smelly.

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
static func validate_chapter(chapter_id: String, chapter: Dictionary, base_producers: Dictionary, errors: Array[String]) -> void:
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
	if units.is_empty() or phase_of.is_empty():
		return
	_validate_resolution_paths(units, case_def, links, base_producers, ctx, errors)
	_validate_offer_order(chapter, units, phase_of, base_producers, ctx, errors)
	_validate_completion(chapter_id, chapter, loop, units, ctx, errors)


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
## actually be acquired.
static func _validate_resolution_paths(units: Dictionary, case_def: Dictionary, links: Dictionary, base_producers: Dictionary, ctx: String, errors: Array[String]) -> void:
	var acquirable: Dictionary = {}  # deduction evidence id -> true when linked AND granted somewhere
	for inventory_id in links:
		if (base_producers.get("evidence", {}) as Dictionary).has(inventory_id):
			acquirable[links[inventory_id]] = true
	for unit_id in units:
		var definition: Dictionary = units[unit_id]
		var mechanic: String = str(definition.get("mechanic", ""))
		if mechanic == CoreLoopUnit.MECHANIC_TIMELINE_RECONSTRUCTION:
			continue  # Needs no evidence; DeductionValidator proves prototype_c solvable.
		var unit_ctx: String = '%s unit "%s"' % [ctx, unit_id]
		var groups: Array = _requirement_groups(definition, mechanic, case_def)
		if groups.is_empty():
			errors.append('%s has no authored accepted proof path within its prototype pool' % unit_ctx)
			continue
		if not _groups_satisfied(groups, acquirable):
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


## A unit offered only through a flag/interaction that nothing but its own or
## a LATER phase's consequence produces can never be opened.
static func _validate_offer_order(chapter: Dictionary, units: Dictionary, phase_of: Dictionary, base_producers: Dictionary, ctx: String, errors: Array[String]) -> void:
	var produced_at: Dictionary = {}  # "flag:x"/"interaction:y" -> earliest phase index producing it
	for entry in consequences_of(chapter):
		var index: int = int(phase_of.get("%s|%s" % [entry["unit"], entry["outcome"]], 1 << 30))
		var flags: Dictionary = {}
		var evidence: Dictionary = {}
		var interactions: Dictionary = {}
		ContentValidator._collect_effect_targets((entry["consequence"] as Dictionary).get("effects", []), flags, evidence, interactions)
		for flag in flags:
			produced_at["flag:%s" % flag] = mini(int(produced_at.get("flag:%s" % flag, 1 << 30)), index)
		for interaction in interactions:
			produced_at["interaction:%s" % interaction] = mini(int(produced_at.get("interaction:%s" % interaction, 1 << 30)), index)
	for unit_id in units:
		var first_phase: int = 1 << 30
		for key in phase_of:
			if (key as String).begins_with("%s|" % unit_id):
				first_phase = mini(first_phase, int(phase_of[key]))
		var flags: Dictionary = {}
		var evidence: Dictionary = {}
		var interactions: Dictionary = {}
		ContentValidator._collect_condition_requirements((units[unit_id] as Dictionary).get("offer_condition"), flags, evidence, interactions)
		for flag in flags:
			if not (base_producers.get("flags", {}) as Dictionary).has(flag) and int(produced_at.get("flag:%s" % flag, 1 << 30)) >= first_phase:
				errors.append('%s unit "%s" is offered only once flag "%s" is set, but only its own or a later phase\'s consequence sets it — a dependency cycle' % [ctx, unit_id, flag])
		for interaction in interactions:
			if not (base_producers.get("interactions", {}) as Dictionary).has(interaction) and int(produced_at.get("interaction:%s" % interaction, 1 << 30)) >= first_phase:
				errors.append('%s unit "%s" is offered only once interaction "%s" completes, but only its own or a later phase\'s consequence marks it — a dependency cycle' % [ctx, unit_id, interaction])


## The chapter's completion_event must be produced by the FINAL phase's
## consequence — and by no earlier one, or CaseManager would complete the
## chapter while the route still has phases left.
static func _validate_completion(chapter_id: String, chapter: Dictionary, loop: Dictionary, units: Dictionary, ctx: String, errors: Array[String]) -> void:
	var event: Dictionary = ContentDB.get_event(str(chapter.get("completion_event", "")))
	if event.is_empty():
		errors.append('%s needs a chapter completion_event — the final consequence has nothing to complete' % ctx)
		return
	var required_flags: Dictionary = {}
	var required_evidence: Dictionary = {}
	var required_interactions: Dictionary = {}
	ContentValidator._collect_condition_requirements(event.get("conditions"), required_flags, required_evidence, required_interactions)
	if required_flags.is_empty() and required_interactions.is_empty():
		errors.append('%s completion_event "%s" requires no flag or interaction — it could fire before the chapter\'s route is finished' % [ctx, event.get("id", "")])
		return
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
