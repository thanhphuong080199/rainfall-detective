class_name DeductionValidator
extends RefCounted
## Content checks for data/deductions/*.json (Milestone 1.9 — see
## docs/deduction-system.md, "Content validation"). NOT a separate validation
## entry point: ContentValidator.validate() calls validate_case() and
## validate_structural_equivalence() for every loaded deduction case, so
## findings print as ordinary "[ContentValidator]" errors/warnings and fail
## validate_content.gd's exit code exactly like any other broken reference.
## It lives in its own file only because the deduction contract is large
## enough that folding it into content_validator.gd would bury both.
##
## Pure (no autoloads): every function takes the case dictionary it checks,
## so tests validate hand-built negative fixtures without touching ContentDB.
## Translation-key completeness stays in ContentValidator
## (_validate_translatable needs LocaleManager); collect_text_keys() tells it
## which keys to check.
##
## Like the rest of this project's validation this is not a theorem prover:
## reachability is a fixed-point walk over AUTHORED proof sets and unlock
## requirements, and timeline checks run the authored solution through the
## same TimelineEvaluator the game uses.

const CERTAINTY_VALUES := ["fixed", "estimated", "claimed"]
const STATEMENT_VERACITY := ["true", "mistaken", "deceptive", "incomplete", "unreliable"]
const TRUTH_VALUES := ["true", "false"]
## Hint ladder levels, in required order (level 1 first). See
## docs/deduction-system.md, "Hint ladders".
const HINT_KINDS := ["restate_question", "compare_categories", "evidence_group", "reveal_deduction"]
const QUESTION_STATUSES := ["supported", "refuted"]
## Maximum INTERMEDIATE deduction depth (Milestone 1.9.1 — see
## docs/deduction-system.md, "Inference depth"). Raw evidence is depth 0; a
## `deduction` claim is 1 + the deepest deduction it requires (across all its
## proof sets). Only `deduction` claims can be proof inputs, so only they are
## limited. A `conclusion` is the synthesis/commit layer on top and is exempt
## from the limit, as are statement refutations, hypothesis eliminations and
## explanations — none of them can be an input, so none can lengthen a chain.
## Every claim, whatever its kind, is still checked for cycles, references and
## reachability. So evidence -> D1 -> D2 -> conclusion is valid; a third
## intermediate deduction D3 on top of D2 is not.
const MAX_INFERENCE_DEPTH := 2
const DERIVED_KINDS := ["deduction", "explanation", "conclusion"]


static func validate_case(case_def: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var ctx: String = 'Deduction case "%s"' % str(case_def.get("id", ""))
	_require_text(case_def.get("display_name"), "%s display_name" % ctx, errors)
	_validate_metadata(case_def, ctx, errors)
	_validate_ids(case_def, ctx, errors)
	_validate_suspects(case_def, ctx, errors)
	_validate_evidence(case_def, ctx, errors)
	_validate_claims(case_def, ctx, errors, warnings)
	_validate_questions(case_def, ctx, errors)
	_validate_timeline(case_def, ctx, errors)
	_validate_hints(case_def, ctx, errors)
	_validate_ground_truth(case_def, ctx, errors)
	_validate_dependency_graph(case_def, ctx, errors, warnings)
	_validate_prototype_a(case_def, ctx, errors, warnings)
	_validate_prototype_b(case_def, ctx, errors, warnings)
	_validate_prototype_c(case_def, ctx, errors, warnings)


# ---------------------------------------------------------------------------
# Shape, ids, metadata

static func _validate_metadata(case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var metadata: Variant = case_def.get("metadata")
	if typeof(metadata) != TYPE_DICTIONARY:
		errors.append('%s has no "metadata" object — it must at least declare "canon": true/false' % ctx)
		return
	if typeof(metadata.get("canon")) != TYPE_BOOL:
		errors.append('%s metadata.canon must be true or false (prototype content must say it is non-canon)' % ctx)
	if metadata.has("structural_template") and typeof(metadata.get("structural_template")) != TYPE_STRING:
		errors.append('%s metadata.structural_template must be a string' % ctx)


## One id namespace per case: suspects, questions, evidence, claims, proof
## sets, timeline events and constraints. Proof sets reference evidence and
## claims by bare id, so an evidence item and a claim sharing an id would make
## a reference ambiguous — that's why this is one namespace, not seven.
static func _validate_ids(case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for section in ["suspects", "questions", "evidence", "claims"]:
		var raw: Variant = case_def.get(section)
		if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
			errors.append('%s "%s" must be a non-empty array' % [ctx, section])
			continue
		for entry in raw:
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append('%s "%s" has a malformed (non-object) entry' % [ctx, section])
				continue
			_register_id(entry.get("id"), section, ctx, seen, errors)
			if section == "claims":
				for proof_set in _dicts(entry.get("proof_sets", [])):
					_register_id(proof_set.get("id"), "proof_sets", ctx, seen, errors)
	for section in ["events", "constraints"]:
		for entry in _dicts(_timeline(case_def).get(section, [])):
			_register_id(entry.get("id"), "timeline %s" % section, ctx, seen, errors)


static func _register_id(raw_id: Variant, section: String, ctx: String, seen: Dictionary, errors: Array[String]) -> void:
	if typeof(raw_id) != TYPE_STRING or raw_id == "":
		errors.append('%s has an entry in "%s" with no "id"' % [ctx, section])
		return
	if seen.has(raw_id):
		errors.append('%s defines id "%s" more than once (in %s and %s) — ids must be unique within a deduction case' % [ctx, raw_id, seen[raw_id], section])
		return
	seen[raw_id] = section


static func _template(case_def: Dictionary) -> String:
	var metadata: Variant = case_def.get("metadata", {})
	if typeof(metadata) != TYPE_DICTIONARY or typeof(metadata.get("structural_template")) != TYPE_STRING:
		return ""
	return metadata.get("structural_template")


## A case that declares metadata.structural_template must give every suspect,
## question, evidence item, claim and timeline event a structural_role, unique
## within its category — the vocabulary validate_structural_equivalence()
## compares cases in.
static func _check_role(entry: Dictionary, label: String, ctx: String, template: String, roles_seen: Dictionary, errors: Array[String]) -> void:
	if template == "":
		return
	var role: Variant = entry.get("structural_role")
	var entry_id: String = str(entry.get("id", ""))
	if typeof(role) != TYPE_STRING or role == "":
		errors.append('%s %s "%s" has no structural_role (required because metadata.structural_template is "%s")' % [ctx, label, entry_id, template])
		return
	if roles_seen.has(role):
		errors.append('%s %s "%s" reuses structural_role "%s" (already used by "%s")' % [ctx, label, entry_id, role, roles_seen[role]])
		return
	roles_seen[role] = entry_id


# ---------------------------------------------------------------------------
# Entities

static func _validate_suspects(case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var roles: Dictionary = {}
	for suspect in _dicts(case_def.get("suspects", [])):
		_require_text(suspect.get("name"), '%s suspect "%s" name' % [ctx, suspect.get("id", "")], errors)
		_check_role(suspect, "suspect", ctx, _template(case_def), roles, errors)


static func _validate_evidence(case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var roles: Dictionary = {}
	for evidence in _dicts(case_def.get("evidence", [])):
		var evidence_ctx: String = '%s evidence "%s"' % [ctx, evidence.get("id", "")]
		_require_text(evidence.get("name"), "%s name" % evidence_ctx, errors)
		_require_text(evidence.get("text"), "%s text" % evidence_ctx, errors)
		if typeof(evidence.get("source")) != TYPE_STRING or evidence.get("source") == "":
			errors.append('%s has no "source" (provenance)' % evidence_ctx)
		if not CERTAINTY_VALUES.has(evidence.get("certainty")):
			errors.append('%s certainty must be one of %s' % [evidence_ctx, ", ".join(CERTAINTY_VALUES)])
		if evidence.has("time") and TimelineEvaluator.parse_time(evidence.get("time")) < 0:
			errors.append('%s time "%s" is not a valid HH:MM time' % [evidence_ctx, evidence.get("time")])
		if not _is_string_array(evidence.get("tags", [])):
			errors.append('%s tags must be an array of strings' % evidence_ctx)
		if not _is_string_array(evidence.get("unlock_requires", [])):
			errors.append('%s unlock_requires must be an array of deduction ids' % evidence_ctx)
		for requirement in DeductionEvaluator.string_array(evidence.get("unlock_requires", [])):
			if _claim_kind(case_def, requirement) != "deduction":
				errors.append('%s unlock_requires references "%s", which is not a deduction in this case' % [evidence_ctx, requirement])
		if evidence.get("misleading", false) == true and not _is_explained(case_def, str(evidence.get("id", ""))):
			errors.append('%s is marked misleading but no "explains" proof set uses it — every red herring needs a truthful explanation' % evidence_ctx)
		_check_role(evidence, "evidence", ctx, _template(case_def), roles, errors)


static func _is_explained(case_def: Dictionary, evidence_id: String) -> bool:
	for claim in _dicts(case_def.get("claims", [])):
		for proof_set in _dicts(claim.get("proof_sets", [])):
			if proof_set.get("relation") == "explains" and DeductionEvaluator.string_array(proof_set.get("requires", [])).has(evidence_id):
				return true
	return false


static func _validate_claims(case_def: Dictionary, ctx: String, errors: Array[String], warnings: Array[String]) -> void:
	var roles: Dictionary = {}
	for claim in _dicts(case_def.get("claims", [])):
		var claim_id: String = str(claim.get("id", ""))
		var claim_ctx: String = '%s claim "%s"' % [ctx, claim_id]
		var kind: String = str(claim.get("kind", ""))
		var veracity: String = str(claim.get("veracity", ""))
		_require_text(claim.get("text"), "%s text" % claim_ctx, errors)
		_check_role(claim, "claim", ctx, _template(case_def), roles, errors)
		if not DeductionEvaluator.CLAIM_KINDS.has(kind):
			errors.append('%s has unknown kind "%s" — supported kinds are %s' % [claim_ctx, kind, ", ".join(DeductionEvaluator.CLAIM_KINDS)])
			# Still check its proof sets' references: a typo'd kind must not
			# hide a broken graph behind the kind error.
			_validate_proof_sets(case_def, claim, claim_ctx, errors, warnings)
			continue
		if kind == "statement":
			if not STATEMENT_VERACITY.has(veracity):
				errors.append('%s veracity must be one of %s (ground truth for a statement)' % [claim_ctx, ", ".join(STATEMENT_VERACITY)])
			if _find(case_def, "suspects", str(claim.get("speaker", ""))).is_empty():
				errors.append('%s speaker "%s" is not a suspect in this case' % [claim_ctx, claim.get("speaker", "")])
		elif not TRUTH_VALUES.has(veracity):
			errors.append('%s veracity must be "true" or "false" (ground truth for a %s)' % [claim_ctx, kind])
		elif DERIVED_KINDS.has(kind) and veracity != "true":
			errors.append('%s is a %s but its veracity is "%s" — derived claims must be true' % [claim_ctx, kind, veracity])
		if claim.has("required") and typeof(claim.get("required")) != TYPE_BOOL:
			errors.append('%s required must be true or false' % claim_ctx)
		if not _is_string_array(claim.get("compatible", [])):
			errors.append('%s compatible must be an array of ids' % claim_ctx)
		for item_id in DeductionEvaluator.string_array(claim.get("compatible", [])):
			if not _is_input_item(case_def, item_id):
				errors.append('%s compatible references undefined evidence or deduction "%s"' % [claim_ctx, item_id])
		_validate_proof_sets(case_def, claim, claim_ctx, errors, warnings)


static func _validate_proof_sets(case_def: Dictionary, claim: Dictionary, claim_ctx: String, errors: Array[String], warnings: Array[String]) -> void:
	var kind: String = str(claim.get("kind", ""))
	var veracity: String = str(claim.get("veracity", ""))
	var raw_sets: Variant = claim.get("proof_sets", [])
	if typeof(raw_sets) != TYPE_ARRAY:
		errors.append('%s proof_sets must be an array' % claim_ctx)
		return
	if DERIVED_KINDS.has(kind) and (raw_sets as Array).is_empty():
		errors.append('%s is a %s with no proof sets — a derived claim must be provable' % [claim_ctx, kind])
	var has_positive := false
	var has_negative := false
	var seen_shapes: Dictionary = {}
	for proof_set in _dicts(raw_sets):
		var set_ctx: String = '%s proof set "%s"' % [claim_ctx, proof_set.get("id", "")]
		var relation: String = str(proof_set.get("relation", ""))
		if not DeductionEvaluator.RELATIONS.has(relation):
			errors.append('%s uses invalid relation "%s" — supported relations are %s' % [set_ctx, relation, ", ".join(DeductionEvaluator.RELATIONS)])
			continue
		if DeductionEvaluator.CLAIM_KINDS.has(kind) and not _relation_allowed(kind, veracity, relation):
			errors.append('%s: relation "%s" is not allowed on a %s whose veracity is "%s" (it would contradict the ground truth)' % [set_ctx, relation, kind, veracity])
		if DeductionEvaluator.POSITIVE_RELATIONS.has(relation):
			has_positive = true
		else:
			has_negative = true
		var requires: Variant = proof_set.get("requires")
		if typeof(requires) != TYPE_ARRAY or (requires as Array).is_empty():
			errors.append('%s is an empty proof set — "requires" must list at least one evidence or deduction id' % set_ctx)
			continue
		var listed: Dictionary = {}
		for item in requires:
			if typeof(item) != TYPE_STRING:
				errors.append('%s has a non-string entry in "requires"' % set_ctx)
				continue
			if listed.has(item):
				errors.append('%s lists "%s" more than once' % [set_ctx, item])
			listed[item] = true
			if not _is_input_item(case_def, item):
				if _claim_kind(case_def, item) != "":
					errors.append('%s uses claim "%s" as an input, but only deduction claims can be inputs' % [set_ctx, item])
				else:
					errors.append('%s references undefined evidence or deduction "%s"' % [set_ctx, item])
			elif kind == "conclusion" and _claim_kind(case_def, item) != "deduction":
				errors.append('%s uses raw evidence "%s" — a conclusion may only combine proven deductions' % [set_ctx, item])
		var shape_items: Array = listed.keys()
		shape_items.sort()
		var shape: String = "%s:%s" % [relation, ",".join(PackedStringArray(shape_items))]
		if seen_shapes.has(shape):
			warnings.append('%s duplicates proof set "%s" (same relation and items)' % [set_ctx, seen_shapes[shape]])
		seen_shapes[shape] = str(proof_set.get("id", ""))
	if has_positive and has_negative:
		errors.append('%s has both establishing (supports/explains) and negating (refutes/rules_out) proof sets — the ground truth cannot be both' % claim_ctx)


## Relation/kind/veracity compatibility: a proof may only establish what the
## ground truth says is so. See docs/deduction-system.md, "Relations".
static func _relation_allowed(kind: String, veracity: String, relation: String) -> bool:
	match relation:
		"supports":
			if kind == "statement":
				return veracity == "true" or veracity == "incomplete"
			return kind != "explanation" and veracity == "true"
		"explains":
			return kind == "explanation" and veracity == "true"
		"refutes":
			return kind == "statement" and (veracity == "mistaken" or veracity == "deceptive")
		"rules_out":
			return kind == "hypothesis" and veracity == "false"
	return false


static func _validate_questions(case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var roles: Dictionary = {}
	var has_required := false
	for question in _dicts(case_def.get("questions", [])):
		var question_ctx: String = '%s question "%s"' % [ctx, question.get("id", "")]
		_require_text(question.get("text"), "%s text" % question_ctx, errors)
		_check_role(question, "question", ctx, _template(case_def), roles, errors)
		if question.get("required", false) == true:
			has_required = true
		var resolved_by: Variant = question.get("resolved_by")
		if typeof(resolved_by) != TYPE_ARRAY or (resolved_by as Array).is_empty():
			errors.append('%s has no "resolved_by" entries — nothing can ever resolve it' % question_ctx)
			continue
		for entry in resolved_by:
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append('%s has a malformed resolved_by entry' % question_ctx)
				continue
			if _claim_kind(case_def, str(entry.get("claim", ""))) == "":
				errors.append('%s resolved_by references unknown claim "%s"' % [question_ctx, entry.get("claim", "")])
			if not QUESTION_STATUSES.has(entry.get("status")):
				errors.append('%s resolved_by status must be "supported" or "refuted"' % question_ctx)
	if not has_required:
		errors.append('%s has no required question — it could never be solved' % ctx)


static func _validate_timeline(case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	if not case_def.has("timeline"):
		return
	if typeof(case_def.get("timeline")) != TYPE_DICTIONARY:
		errors.append('%s timeline must be an object' % ctx)
		return
	var events: Dictionary = TimelineEvaluator.event_index(case_def)
	var roles: Dictionary = {}
	for event in _dicts(_timeline(case_def).get("events", [])):
		var event_ctx: String = '%s timeline event "%s"' % [ctx, event.get("id", "")]
		_require_text(event.get("label"), "%s label" % event_ctx, errors)
		_check_role(event, "timeline event", ctx, _template(case_def), roles, errors)
		var actor: String = str(event.get("actor", ""))
		if actor != "" and _find(case_def, "suspects", actor).is_empty():
			errors.append('%s actor "%s" is not a suspect in this case' % [event_ctx, actor])
		if not CERTAINTY_VALUES.has(event.get("certainty")):
			errors.append('%s certainty must be one of %s' % [event_ctx, ", ".join(CERTAINTY_VALUES)])
		if TimelineEvaluator.parse_minutes(event.get("duration_minutes"), 0) < 0:
			errors.append('%s duration_minutes must be a non-negative whole number' % event_ctx)
	for constraint in TimelineEvaluator.constraints(case_def):
		_validate_constraint(case_def, constraint, events, ctx, errors)


static func _validate_constraint(case_def: Dictionary, constraint: Dictionary, events: Dictionary, ctx: String, errors: Array[String]) -> void:
	var constraint_ctx: String = '%s timeline constraint "%s"' % [ctx, constraint.get("id", "")]
	var type: String = str(constraint.get("type", ""))
	if not TimelineEvaluator.CONSTRAINT_TYPES.has(type):
		errors.append('%s has unknown type "%s" — supported types are %s' % [constraint_ctx, type, ", ".join(TimelineEvaluator.CONSTRAINT_TYPES)])
		return
	var ids: Array[String] = TimelineEvaluator.constraint_event_ids(constraint)
	var expected_count: int = 1 if TimelineEvaluator.SINGLE_EVENT_TYPES.has(type) else 2
	if ids.size() != expected_count or (expected_count == 2 and ids[0] == ids[1]):
		errors.append('%s must reference %s' % [constraint_ctx, '"event"' if expected_count == 1 else 'two different ids in "events"'])
	for event_id in ids:
		if not events.has(event_id):
			errors.append('%s references unknown timeline event "%s"' % [constraint_ctx, event_id])
	match type:
		"fixed_time":
			if TimelineEvaluator.parse_time(constraint.get("time")) < 0:
				errors.append('%s time is not a valid HH:MM time' % constraint_ctx)
		"window":
			var earliest: int = TimelineEvaluator.parse_time(constraint.get("earliest"))
			var latest: int = TimelineEvaluator.parse_time(constraint.get("latest"))
			if earliest < 0 or latest < 0:
				errors.append('%s earliest/latest must be valid HH:MM times' % constraint_ctx)
			elif earliest > latest:
				errors.append('%s is an invalid time window: earliest %s is after latest %s' % [constraint_ctx, constraint.get("earliest"), constraint.get("latest")])
		"before":
			if TimelineEvaluator.parse_minutes(constraint.get("min_gap_minutes"), 0) < 0:
				errors.append('%s min_gap_minutes must be a non-negative whole number' % constraint_ctx)
		"travel_time":
			if TimelineEvaluator.parse_minutes(constraint.get("minutes"), -1) < 0:
				errors.append('%s minutes must be a non-negative whole number' % constraint_ctx)
	if constraint.has("required") and typeof(constraint.get("required")) != TYPE_BOOL:
		errors.append('%s required must be true or false' % constraint_ctx)
	var source: String = str(constraint.get("source", ""))
	if find_item_kind(case_def, source) == "":
		errors.append('%s source "%s" is not an evidence item or claim in this case' % [constraint_ctx, source])
	elif constraint.get("required", true) != false:
		var claim: Dictionary = DeductionEvaluator.find_claim(case_def, source)
		if claim.get("veracity", "") == "mistaken" or claim.get("veracity", "") == "deceptive":
			errors.append('%s is required but comes from %s statement "%s" — a false statement can only back an optional constraint' % [constraint_ctx, claim.get("veracity", ""), source])


static func _validate_hints(case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var tags: Dictionary = {}
	for evidence in _dicts(case_def.get("evidence", [])):
		for tag in DeductionEvaluator.string_array(evidence.get("tags", [])):
			tags[tag] = true
	var targets: Dictionary = {}
	for ladder in _dicts(case_def.get("hints", [])):
		var target: String = str(ladder.get("target", ""))
		var ladder_ctx: String = '%s hint ladder for "%s"' % [ctx, target]
		if _claim_kind(case_def, target) == "":
			errors.append('%s targets unknown claim "%s"' % [ladder_ctx, target])
		if targets.has(target):
			errors.append('%s is defined more than once' % ladder_ctx)
		targets[target] = true
		var levels: Array[Dictionary] = _dicts(ladder.get("levels", []))
		if levels.size() != HINT_KINDS.size():
			errors.append('%s must have exactly %d levels (%s)' % [ladder_ctx, HINT_KINDS.size(), ", ".join(HINT_KINDS)])
		for i in mini(levels.size(), HINT_KINDS.size()):
			_validate_hint_level(case_def, levels[i], i, tags, ladder_ctx, errors)
	for claim in _dicts(case_def.get("claims", [])):
		var kind: String = str(claim.get("kind", ""))
		if claim.get("required", false) == true and (kind == "deduction" or kind == "conclusion") and not targets.has(str(claim.get("id", ""))):
			errors.append('%s required %s "%s" has no hint ladder' % [ctx, kind, claim.get("id", "")])


static func _validate_hint_level(case_def: Dictionary, level: Dictionary, index: int, tags: Dictionary, ladder_ctx: String, errors: Array[String]) -> void:
	var level_ctx: String = "%s level %d" % [ladder_ctx, index + 1]
	if TimelineEvaluator.parse_minutes(level.get("level"), -1) != index + 1:
		errors.append('%s must declare "level": %d' % [level_ctx, index + 1])
	if level.get("kind") != HINT_KINDS[index]:
		errors.append('%s kind must be "%s"' % [level_ctx, HINT_KINDS[index]])
		return
	_require_text(level.get("text"), "%s text" % level_ctx, errors)
	match HINT_KINDS[index]:
		"restate_question":
			if _find(case_def, "questions", str(level.get("question", ""))).is_empty():
				errors.append('%s references unknown question "%s"' % [level_ctx, level.get("question", "")])
		"compare_categories":
			var categories: Array[String] = DeductionEvaluator.string_array(level.get("categories", []))
			if categories.is_empty():
				errors.append('%s must list at least one category' % level_ctx)
			for category in categories:
				if not tags.has(category):
					errors.append('%s references category "%s", which no evidence in this case is tagged with' % [level_ctx, category])
		"evidence_group":
			var group: Array[String] = DeductionEvaluator.string_array(level.get("evidence", []))
			if group.is_empty():
				errors.append('%s must list at least one evidence id' % level_ctx)
			for evidence_id in group:
				if DeductionEvaluator.find_evidence(case_def, evidence_id).is_empty():
					errors.append('%s references unknown evidence "%s"' % [level_ctx, evidence_id])
		"reveal_deduction":
			var deduction_id: String = str(level.get("deduction", ""))
			var kind: String = _claim_kind(case_def, deduction_id)
			if kind == "conclusion":
				errors.append('%s reveals the final conclusion "%s" — level 4 may only reveal an intermediate deduction' % [level_ctx, deduction_id])
			elif kind != "deduction":
				errors.append('%s references unknown deduction "%s"' % [level_ctx, deduction_id])


static func _validate_ground_truth(case_def: Dictionary, ctx: String, errors: Array[String]) -> void:
	var truth: Variant = case_def.get("ground_truth")
	if typeof(truth) != TYPE_DICTIONARY:
		errors.append('%s has no ground_truth object (culprit, credential_owner, conclusion, summary, solution_timeline)' % ctx)
		return
	_require_text(truth.get("summary"), "%s ground_truth summary" % ctx, errors)
	for field in ["culprit", "credential_owner"]:
		if _find(case_def, "suspects", str(truth.get(field, ""))).is_empty():
			errors.append('%s ground_truth.%s "%s" is not a suspect in this case' % [ctx, field, truth.get(field, "")])
	if _claim_kind(case_def, str(truth.get("conclusion", ""))) != "conclusion":
		errors.append('%s ground_truth.conclusion "%s" is not a conclusion claim in this case' % [ctx, truth.get("conclusion", "")])
	if TimelineEvaluator.event_index(case_def).is_empty():
		return
	var outcome: Dictionary = TimelineEvaluator.evaluate(case_def, truth.get("solution_timeline"))
	if outcome.get("category") == TimelineEvaluator.INVALID_INPUT:
		errors.append('%s ground_truth.solution_timeline is not a complete, well-formed placement of every timeline event (%s)' % [ctx, outcome.get("reason", "")])
		return
	for constraint_id in outcome.get("violated_required", []):
		errors.append('%s ground_truth.solution_timeline violates its own required timeline constraint "%s"' % [ctx, constraint_id])


# ---------------------------------------------------------------------------
# Dependency graph: cycles, depth, reachability

static func _validate_dependency_graph(case_def: Dictionary, ctx: String, errors: Array[String], warnings: Array[String]) -> void:
	var cycles: Array[Array] = find_dependency_cycles(case_def)
	for cycle in cycles:
		var path: String = " -> ".join(PackedStringArray(cycle + [cycle[0]]))
		var evidence_in_cycle: String = ""
		for node_id in cycle:
			if not DeductionEvaluator.find_evidence(case_def, str(node_id)).is_empty():
				evidence_in_cycle = str(node_id)
				break
		if evidence_in_cycle != "":
			errors.append('%s has a circular clue unlock: evidence "%s" is locked behind a deduction that requires that same evidence (%s)' % [ctx, evidence_in_cycle, path])
		else:
			errors.append('%s has a deduction dependency cycle (%s)' % [ctx, path])
	if cycles.is_empty():
		var depths: Dictionary = inference_depths(case_def)
		for claim_id in depths:
			if depths[claim_id] > MAX_INFERENCE_DEPTH:
				errors.append('%s intermediate deduction "%s" is at depth %d, above the maximum intermediate deduction depth of %d (evidence = 0; a deduction = 1 + its deepest deduction input; only a conclusion may build on a depth-%d deduction)' % [ctx, claim_id, depths[claim_id], MAX_INFERENCE_DEPTH, MAX_INFERENCE_DEPTH])
	_warn_deduction_gated_required_evidence(case_def, ctx, warnings)

	var reach: Dictionary = compute_reachability(case_def)
	var supported: Dictionary = reach.get("supported", {})
	var refuted: Dictionary = reach.get("refuted", {})
	for claim in _dicts(case_def.get("claims", [])):
		var claim_id: String = str(claim.get("id", ""))
		if supported.has(claim_id) or refuted.has(claim_id):
			continue
		if claim.get("required", false) == true:
			errors.append('%s required claim "%s" is unreachable — no authored proof set can ever be satisfied from the case\'s evidence' % [ctx, claim_id])
		elif not _dicts(claim.get("proof_sets", [])).is_empty():
			warnings.append('%s claim "%s" has proof sets but none can ever be satisfied' % [ctx, claim_id])
	for evidence in _dicts(case_def.get("evidence", [])):
		if not (reach.get("evidence", {}) as Dictionary).has(str(evidence.get("id", ""))):
			warnings.append('%s evidence "%s" can never be unlocked' % [ctx, evidence.get("id", "")])
	for question in _dicts(case_def.get("questions", [])):
		if question.get("required", false) != true:
			continue
		var resolvable := false
		for entry in _dicts(question.get("resolved_by", [])):
			var target: Dictionary = supported if entry.get("status") == "supported" else refuted
			if target.has(str(entry.get("claim", ""))):
				resolvable = true
		if not resolvable:
			errors.append('%s required question "%s" has no valid resolution path — none of its resolved_by claims can reach the listed status' % [ctx, question.get("id", "")])
	var truth: Variant = case_def.get("ground_truth", {})
	if typeof(truth) == TYPE_DICTIONARY and _claim_kind(case_def, str(truth.get("conclusion", ""))) == "conclusion" and not supported.has(str(truth.get("conclusion", ""))):
		errors.append('%s ground_truth.conclusion "%s" can never be proven' % [ctx, truth.get("conclusion", "")])


## WARNING, not error: the generic `unlock_requires` contract stays for future
## use, but a private deduction must not make a pre-existing record or clue
## appear in the world. When evidence is locked behind a deduction AND a
## deduction or conclusion then requires that evidence, the derived claim is a
## descendant of the gate (it can only be proven after the gate unlocks) — the
## "resolve D1 -> custody log appears -> D1 + custody log proves D2" pattern.
## Such evidence must be independently discoverable, or its discovery must be
## represented by an explicit investigation action (not built yet). See
## docs/deduction-system.md, "Evidence availability".
static func _warn_deduction_gated_required_evidence(case_def: Dictionary, ctx: String, warnings: Array[String]) -> void:
	for evidence in _dicts(case_def.get("evidence", [])):
		var gates: Array[String] = DeductionEvaluator.string_array(evidence.get("unlock_requires", []))
		if gates.is_empty():
			continue
		var evidence_id: String = str(evidence.get("id", ""))
		for claim in _dicts(case_def.get("claims", [])):
			var kind: String = str(claim.get("kind", ""))
			if kind != "deduction" and kind != "conclusion":
				continue
			for proof_set in _dicts(claim.get("proof_sets", [])):
				if DeductionEvaluator.string_array(proof_set.get("requires", [])).has(evidence_id):
					warnings.append('%s evidence "%s" is locked behind deduction(s) %s and then required by %s "%s" — a private deduction must not make evidence appear; make it independently discoverable, or represent its discovery with an explicit investigation action before production use' % [ctx, evidence_id, ", ".join(gates), kind, claim.get("id", "")])
					break


## Directed graph over this case's evidence and claims: a claim points at
## every item any of its proof sets requires; an evidence item points at the
## deductions its unlock_requires names.
static func dependency_graph(case_def: Dictionary) -> Dictionary:
	var graph: Dictionary = {}
	for evidence in _dicts(case_def.get("evidence", [])):
		graph[str(evidence.get("id", ""))] = DeductionEvaluator.string_array(evidence.get("unlock_requires", []))
	for claim in _dicts(case_def.get("claims", [])):
		var edges: Array[String] = []
		for proof_set in _dicts(claim.get("proof_sets", [])):
			for item_id in DeductionEvaluator.string_array(proof_set.get("requires", [])):
				if not edges.has(item_id):
					edges.append(item_id)
		graph[str(claim.get("id", ""))] = edges
	return graph


## Every distinct cycle (as an ordered id list), deterministic in authored
## order. ANY cycle is an error, even one an alternate proof set could route
## around: prototype cases must be clean DAGs so three isomorphic cases stay
## comparable (see docs/deduction-system.md, "Content validation").
static func find_dependency_cycles(case_def: Dictionary) -> Array[Array]:
	var graph: Dictionary = dependency_graph(case_def)
	var state: Dictionary = {}
	var stack: Array[String] = []
	var cycles: Array[Array] = []
	var seen_keys: Dictionary = {}
	for node_id in graph:
		if state.get(node_id, 0) == 0:
			_visit(node_id, graph, state, stack, cycles, seen_keys)
	return cycles


static func _visit(node_id: String, graph: Dictionary, state: Dictionary, stack: Array[String], cycles: Array[Array], seen_keys: Dictionary) -> void:
	state[node_id] = 1
	stack.append(node_id)
	for next_id in graph.get(node_id, []):
		if not graph.has(next_id):
			continue
		var next_state: int = state.get(next_id, 0)
		if next_state == 0:
			_visit(next_id, graph, state, stack, cycles, seen_keys)
		elif next_state == 1:
			var cycle: Array = stack.slice(stack.find(next_id))
			var key_parts: Array = cycle.duplicate()
			key_parts.sort()
			var key: String = ",".join(PackedStringArray(key_parts))
			if not seen_keys.has(key):
				seen_keys[key] = true
				cycles.append(cycle)
	stack.pop_back()
	state[node_id] = 2


## Intermediate deduction id -> depth (the values MAX_INFERENCE_DEPTH limits):
## 1 when every proof set uses only evidence, else 1 + the deepest deduction
## input across ALL its proof sets. Only meaningful when there are no cycles.
static func inference_depths(case_def: Dictionary) -> Dictionary:
	var depths: Dictionary = {}
	for claim in _dicts(case_def.get("claims", [])):
		if claim.get("kind") == "deduction":
			_depth(case_def, str(claim.get("id", "")), depths, {})
	return depths


## Depth of ONE proof set: 1 + the deepest deduction it requires (evidence
## counts as 0). For any claim kind — this is how a conclusion's synthesis
## depth (e.g. 3 for evidence -> D1 -> D2 -> conclusion) and the depth of
## alternate proof paths are reported, even though only intermediate
## deductions are limited. Only meaningful when there are no cycles.
static func proof_set_depth(case_def: Dictionary, proof_set: Dictionary) -> int:
	var depth := 1
	var memo: Dictionary = {}
	for item_id in DeductionEvaluator.string_array(proof_set.get("requires", [])):
		if _claim_kind(case_def, item_id) == "deduction":
			depth = maxi(depth, 1 + _depth(case_def, item_id, memo, {}))
	return depth


## Depth of any claim: the deepest of its proof sets (0 when it has none).
static func claim_depth(case_def: Dictionary, claim_id: String) -> int:
	var depth := 0
	for proof_set in _dicts(DeductionEvaluator.find_claim(case_def, claim_id).get("proof_sets", [])):
		depth = maxi(depth, proof_set_depth(case_def, proof_set))
	return depth


static func _depth(case_def: Dictionary, claim_id: String, memo: Dictionary, visiting: Dictionary) -> int:
	if memo.has(claim_id):
		return memo[claim_id]
	if visiting.has(claim_id):
		return 0
	visiting[claim_id] = true
	var depth := 1
	for proof_set in _dicts(DeductionEvaluator.find_claim(case_def, claim_id).get("proof_sets", [])):
		for item_id in DeductionEvaluator.string_array(proof_set.get("requires", [])):
			if _claim_kind(case_def, item_id) == "deduction":
				depth = maxi(depth, 1 + _depth(case_def, item_id, memo, visiting))
	visiting.erase(claim_id)
	memo[claim_id] = depth
	return depth


## Fixed-point walk: what could a player with every available item eventually
## prove? {"evidence": {id: true}, "supported": {id: true}, "refuted": {id: true}}.
## Bounded: each pass adds at least one item or stops.
static func compute_reachability(case_def: Dictionary) -> Dictionary:
	var evidence_list: Array[Dictionary] = _dicts(case_def.get("evidence", []))
	var claims: Array[Dictionary] = _dicts(case_def.get("claims", []))
	var available: Dictionary = {}
	var supported: Dictionary = {}
	var refuted: Dictionary = {}
	var changed := true
	while changed:
		changed = false
		for evidence in evidence_list:
			var evidence_id: String = str(evidence.get("id", ""))
			if available.has(evidence_id):
				continue
			var unlocked := true
			for requirement in DeductionEvaluator.string_array(evidence.get("unlock_requires", [])):
				if not supported.has(requirement):
					unlocked = false
			if unlocked:
				available[evidence_id] = true
				changed = true
		for claim in claims:
			var claim_id: String = str(claim.get("id", ""))
			for proof_set in _dicts(claim.get("proof_sets", [])):
				var status: String = DeductionEvaluator.status_for_relation(str(proof_set.get("relation", "")))
				var target: Dictionary = supported if status == DeductionSession.STATUS_SUPPORTED else refuted
				var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
				if status == "" or target.has(claim_id) or requires.is_empty():
					continue
				var satisfiable := true
				for item_id in requires:
					var is_ready: bool = available.has(item_id) or (supported.has(item_id) and _claim_kind(case_def, item_id) == "deduction")
					if not is_ready:
						satisfiable = false
						break
				if satisfiable:
					target[claim_id] = true
					changed = true
	return {"evidence": available, "supported": supported, "refuted": refuted}


# ---------------------------------------------------------------------------
# Prototype A (Milestone 1.11) — optional per-case data layer under
# case_def["prototype_a"]: {evidence_pool, rounds: [{id, statements,
# required_refutations, optional_refutations, success_explanations,
# witness_responses, hint_ladders, ...}], completion_text}. See
# docs/prototype-a.md. Absent entirely on a case with no Prototype A content
# (e.g. the hand-built fixtures) — this whole section is then a no-op.
##
## Deliberately does NOT reuse case_def["hints"] (those ladders may only
## target a "deduction"/"conclusion" claim — see _validate_hints/
## _validate_hint_level above) — a Prototype A round's required refutation is
## always a "statement", so its hint ladder is Prototype-A-owned data
## (round.hint_ladders), validated here instead.
##
## Local variables below are named "entry"/"pa_round" rather than "round" to
## avoid shadowing GDScript's builtin round() function.

const PROTOTYPE_A_HINT_LEVELS := 4

static func _validate_prototype_a(case_def: Dictionary, ctx: String, errors: Array[String], warnings: Array[String]) -> void:
	var proto: Variant = case_def.get("prototype_a")
	if proto == null:
		return
	if typeof(proto) != TYPE_DICTIONARY:
		errors.append('%s prototype_a must be an object' % ctx)
		return
	var pa_ctx: String = "%s prototype_a" % ctx

	var pool_ids: Dictionary = {}
	var raw_pool: Variant = proto.get("evidence_pool")
	if not _is_string_array(raw_pool):
		errors.append('%s evidence_pool must be an array of evidence ids' % pa_ctx)
		raw_pool = []
	for evidence_id in DeductionEvaluator.string_array(raw_pool):
		var evidence: Dictionary = DeductionEvaluator.find_evidence(case_def, evidence_id)
		if evidence.is_empty():
			errors.append('%s evidence_pool references undefined evidence "%s"' % [pa_ctx, evidence_id])
		elif not (evidence.get("unlock_requires", []) as Array).is_empty():
			errors.append('%s evidence_pool item "%s" has unlock_requires — every Prototype A evidence item must be available from the start' % [pa_ctx, evidence_id])
		pool_ids[evidence_id] = true

	_require_text(proto.get("completion_text"), "%s completion_text" % pa_ctx, errors)

	var raw_rounds: Variant = proto.get("rounds")
	if typeof(raw_rounds) != TYPE_ARRAY or (raw_rounds as Array).is_empty():
		errors.append('%s must declare a non-empty "rounds" array' % pa_ctx)
		return

	var seen_round_ids: Dictionary = {}
	var seen_targets: Dictionary = {}  # claim id -> round context, across ALL rounds (a claim may be a target in only one round)
	var total_required := 0
	for i in (raw_rounds as Array).size():
		var pa_round: Variant = (raw_rounds as Array)[i]
		var round_ctx: String = "%s round %d" % [pa_ctx, i + 1]
		if typeof(pa_round) != TYPE_DICTIONARY:
			errors.append('%s is not an object' % round_ctx)
			continue

		var round_id: String = str(pa_round.get("id", ""))
		if round_id == "":
			errors.append('%s has no "id"' % round_ctx)
		elif seen_round_ids.has(round_id):
			errors.append('%s duplicates round id "%s" (already used by round %d)' % [round_ctx, round_id, seen_round_ids[round_id]])
		else:
			seen_round_ids[round_id] = i + 1

		var statement_ids: Dictionary = {}
		var raw_statements: Variant = pa_round.get("statements")
		if not _is_string_array(raw_statements) or (raw_statements as Array).is_empty():
			errors.append('%s must declare a non-empty "statements" array of claim ids' % round_ctx)
			raw_statements = []
		for claim_id in DeductionEvaluator.string_array(raw_statements):
			var claim: Dictionary = DeductionEvaluator.find_claim(case_def, claim_id)
			if claim.is_empty():
				errors.append('%s references undefined claim "%s"' % [round_ctx, claim_id])
			elif str(claim.get("kind", "")) != "statement":
				errors.append('%s statement "%s" is not a statement claim (kind=%s) — Prototype A only cross-examines statements' % [round_ctx, claim_id, claim.get("kind", "")])
			statement_ids[claim_id] = true

		var required: Array[String] = DeductionEvaluator.string_array(pa_round.get("required_refutations"))
		if not _is_string_array(pa_round.get("required_refutations")) or required.is_empty():
			errors.append('%s must declare a non-empty "required_refutations" array' % round_ctx)
		var optional: Array[String] = DeductionEvaluator.string_array(pa_round.get("optional_refutations", []))
		if pa_round.has("optional_refutations") and not _is_string_array(pa_round.get("optional_refutations")):
			errors.append('%s optional_refutations must be an array of claim ids' % round_ctx)

		for claim_id in required + optional:
			if not statement_ids.has(claim_id):
				errors.append('%s targets "%s", which is not one of this round\'s statements' % [round_ctx, claim_id])
			if seen_targets.has(claim_id):
				errors.append('%s targets "%s" a second time (already targeted in %s) — a claim may only be a refutation target in one round' % [round_ctx, claim_id, seen_targets[claim_id]])
			else:
				seen_targets[claim_id] = round_ctx

		for claim_id in required:
			total_required += 1
			_validate_prototype_a_target(case_def, claim_id, pool_ids, round_ctx, errors)
		for claim_id in optional:
			_validate_prototype_a_target(case_def, claim_id, pool_ids, round_ctx, errors)

		# Every displayed statement that is actually false must have a fair,
		# authored outcome (required or optional); every targeted statement
		# must actually BE false — a true/incomplete statement structurally
		# can't have a refutes proof set (_relation_allowed above), but a
		# content author could still mis-list one as a target by id.
		for claim_id in statement_ids:
			var claim: Dictionary = DeductionEvaluator.find_claim(case_def, claim_id)
			var veracity: String = str(claim.get("veracity", ""))
			var is_false_statement: bool = veracity == "deceptive" or veracity == "mistaken"
			var is_targeted: bool = required.has(claim_id) or optional.has(claim_id)
			if is_false_statement and not is_targeted:
				errors.append('%s statement "%s" is false (veracity=%s) but has no accepted outcome — list it in required_refutations or optional_refutations' % [round_ctx, claim_id, veracity])
			elif is_targeted and not is_false_statement:
				errors.append('%s statement "%s" is configured as a refutation target but its veracity is "%s" — only a mistaken/deceptive statement may be refuted' % [round_ctx, claim_id, veracity])

		var explanations: Variant = pa_round.get("success_explanations")
		if typeof(explanations) != TYPE_DICTIONARY:
			errors.append('%s success_explanations must be an object mapping claim id -> translation key' % round_ctx)
			explanations = {}
		var responses: Variant = pa_round.get("witness_responses")
		if typeof(responses) != TYPE_DICTIONARY:
			errors.append('%s witness_responses must be an object mapping claim id -> translation key' % round_ctx)
			responses = {}
		var ladders: Variant = pa_round.get("hint_ladders", {})
		if typeof(ladders) != TYPE_DICTIONARY:
			errors.append('%s hint_ladders must be an object mapping claim id -> an array of %d translation keys' % [round_ctx, PROTOTYPE_A_HINT_LEVELS])
			ladders = {}

		for claim_id in required + optional:
			if not (explanations as Dictionary).has(claim_id):
				errors.append('%s is missing a success_explanations entry for "%s"' % [round_ctx, claim_id])
			else:
				_require_text((explanations as Dictionary).get(claim_id), '%s success_explanations["%s"]' % [round_ctx, claim_id], errors)
			if not (responses as Dictionary).has(claim_id):
				errors.append('%s is missing a witness_responses entry for "%s"' % [round_ctx, claim_id])
			else:
				_require_text((responses as Dictionary).get(claim_id), '%s witness_responses["%s"]' % [round_ctx, claim_id], errors)
		for claim_id in required:
			var ladder: Variant = (ladders as Dictionary).get(claim_id)
			if typeof(ladder) != TYPE_ARRAY or (ladder as Array).size() != PROTOTYPE_A_HINT_LEVELS:
				errors.append('%s required refutation "%s" needs a hint_ladders entry with exactly %d levels' % [round_ctx, claim_id, PROTOTYPE_A_HINT_LEVELS])
				continue
			for level_index in (ladder as Array).size():
				_require_text((ladder as Array)[level_index], '%s hint_ladders["%s"] level %d' % [round_ctx, claim_id, level_index + 1], errors)

	if total_required != 2:
		warnings.append('%s has %d required contradiction(s) across all rounds; the milestone target is exactly 2 for a 5-10 minute session' % [pa_ctx, total_required])


## A required or optional refutation target must be solvable with EXACTLY one
## evidence item (Prototype A never submits more than one), and that item
## must be listed in evidence_pool so the player can actually reach it.
static func _validate_prototype_a_target(case_def: Dictionary, claim_id: String, pool_ids: Dictionary, round_ctx: String, errors: Array[String]) -> void:
	var claim: Dictionary = DeductionEvaluator.find_claim(case_def, claim_id)
	if claim.is_empty():
		return  # Already reported as an undefined reference.
	var single_evidence_ids: Dictionary = {}
	for proof_set in _dicts(claim.get("proof_sets", [])):
		if str(proof_set.get("relation", "")) != "refutes":
			continue
		var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
		if requires.size() == 1 and not DeductionEvaluator.find_evidence(case_def, requires[0]).is_empty():
			single_evidence_ids[requires[0]] = true
	if single_evidence_ids.is_empty():
		errors.append('%s required refutation "%s" has no single-evidence refutes proof set — Prototype A can only submit exactly one evidence item per attempt' % [round_ctx, claim_id])
		return
	for evidence_id in single_evidence_ids:
		if not pool_ids.has(evidence_id):
			errors.append('%s "%s" is solvable with evidence "%s", which is missing from prototype_a.evidence_pool' % [round_ctx, claim_id, evidence_id])


## [[key, context], ...] additional translation keys Prototype A's optional
## data layer introduces — success_explanations, witness_responses,
## hint_ladders and completion_text. Called from ContentValidator alongside
## collect_text_keys() (see docs/deduction-system.md, "Content validation").
static func collect_prototype_a_text_keys(case_def: Dictionary) -> Array[Array]:
	var keys: Array[Array] = []
	var proto: Variant = case_def.get("prototype_a")
	if typeof(proto) != TYPE_DICTIONARY:
		return keys
	var ctx: String = 'Deduction case "%s" prototype_a' % str(case_def.get("id", ""))
	keys.append([proto.get("completion_text", ""), "%s completion_text" % ctx])
	for pa_round in _dicts(proto.get("rounds", [])):
		var round_id: String = str(pa_round.get("id", ""))
		var round_ctx: String = '%s round "%s"' % [ctx, round_id]
		var explanations: Variant = pa_round.get("success_explanations", {})
		if typeof(explanations) == TYPE_DICTIONARY:
			for claim_id in (explanations as Dictionary):
				keys.append([(explanations as Dictionary)[claim_id], '%s success_explanations["%s"]' % [round_ctx, claim_id]])
		var responses: Variant = pa_round.get("witness_responses", {})
		if typeof(responses) == TYPE_DICTIONARY:
			for claim_id in (responses as Dictionary):
				keys.append([(responses as Dictionary)[claim_id], '%s witness_responses["%s"]' % [round_ctx, claim_id]])
		var ladders: Variant = pa_round.get("hint_ladders", {})
		if typeof(ladders) == TYPE_DICTIONARY:
			for claim_id in (ladders as Dictionary):
				var levels: Variant = (ladders as Dictionary)[claim_id]
				if typeof(levels) == TYPE_ARRAY:
					for level_index in (levels as Array).size():
						keys.append([(levels as Array)[level_index], '%s hint_ladders["%s"] level %d' % [round_ctx, claim_id, level_index + 1]])
	return keys


## Appended to structural_signature() (see below) when a case declares
## prototype_a, so validate_structural_equivalence() enforces the same
## round/target/evidence-pool SHAPE across X/Y/Z automatically — no separate
## comparison entry point. Roles only, never ids or translation keys: a round
## is compared by index (round ids are case-specific strings, e.g. "round_1",
## and are not assumed to match across cases).
static func _prototype_a_signature_lines(case_def: Dictionary, role_of: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var proto: Variant = case_def.get("prototype_a")
	if typeof(proto) != TYPE_DICTIONARY:
		return lines
	lines.append("prototype_a:evidence_pool=%s" % _roles(proto.get("evidence_pool", []), role_of))
	var rounds: Array[Dictionary] = _dicts(proto.get("rounds", []))
	lines.append("prototype_a:round_count=%d" % rounds.size())
	for i in rounds.size():
		var pa_round: Dictionary = rounds[i]
		var explanations: Variant = pa_round.get("success_explanations", {})
		var responses: Variant = pa_round.get("witness_responses", {})
		var ladders: Variant = pa_round.get("hint_ladders", {})
		var explanation_targets: Array = (explanations as Dictionary).keys() if typeof(explanations) == TYPE_DICTIONARY else []
		var response_targets: Array = (responses as Dictionary).keys() if typeof(responses) == TYPE_DICTIONARY else []
		var hint_targets: Array = (ladders as Dictionary).keys() if typeof(ladders) == TYPE_DICTIONARY else []
		lines.append("prototype_a:round=%d:statements=%s:required=%s:optional=%s:explanation_targets=%s:response_targets=%s:hint_targets=%s" % [
			i, _roles(pa_round.get("statements", []), role_of), _roles(pa_round.get("required_refutations", []), role_of),
			_roles(pa_round.get("optional_refutations", []), role_of), _roles(explanation_targets, role_of),
			_roles(response_targets, role_of), _roles(hint_targets, role_of),
		])
	return lines


# ---------------------------------------------------------------------------
# Prototype B (Milestone 1.12) — optional per-case data layer under
# case_def["prototype_b"]: {evidence_pool, rounds: [{id, question, target,
# relation, slot_count, success_explanation}], completion_text}. See
# docs/prototype-b.md. Absent entirely on a case with no Prototype B content
# (e.g. the hand-built fixtures) — this whole section is then a no-op.
##
## Deliberately REUSES case_def["hints"]/DeductionEvaluator.request_hint()
## for hint progress, unlike _validate_prototype_a above: every Prototype B
## round targets a real "deduction" claim, which the base hint contract
## already supports (_validate_hints requires a ladder for every required
## deduction) — see docs/prototype-b.md, "Hints". So there is no
## Prototype-B-owned hint shape to validate here.
##
## Local variables below are named "entry"/"pb_round" rather than "round" to
## avoid shadowing GDScript's builtin round() function.

## A player must never win a round with a single clue — see docs/prototype-b.md,
## "Anti-brute-force rule".
const PROTOTYPE_B_MIN_SLOT_COUNT := 2

static func _validate_prototype_b(case_def: Dictionary, ctx: String, errors: Array[String], warnings: Array[String]) -> void:
	var proto: Variant = case_def.get("prototype_b")
	if proto == null:
		return
	if typeof(proto) != TYPE_DICTIONARY:
		errors.append('%s prototype_b must be an object' % ctx)
		return
	var pb_ctx: String = "%s prototype_b" % ctx

	var pool_ids: Dictionary = {}
	var raw_pool: Variant = proto.get("evidence_pool")
	if not _is_string_array(raw_pool):
		errors.append('%s evidence_pool must be an array of evidence ids' % pb_ctx)
		raw_pool = []
	for evidence_id in DeductionEvaluator.string_array(raw_pool):
		var evidence: Dictionary = DeductionEvaluator.find_evidence(case_def, evidence_id)
		if evidence.is_empty():
			errors.append('%s evidence_pool references undefined evidence "%s"' % [pb_ctx, evidence_id])
		elif not (evidence.get("unlock_requires", []) as Array).is_empty():
			errors.append('%s evidence_pool item "%s" has unlock_requires — every Prototype B evidence item must be available from the start' % [pb_ctx, evidence_id])
		pool_ids[evidence_id] = true

	_require_text(proto.get("completion_text"), "%s completion_text" % pb_ctx, errors)

	var raw_rounds: Variant = proto.get("rounds")
	if typeof(raw_rounds) != TYPE_ARRAY or (raw_rounds as Array).is_empty():
		errors.append('%s must declare a non-empty "rounds" array' % pb_ctx)
		return

	# Prototype B must target a broader DEDUCTION, never the same claim
	# Prototype A cross-examines as a statement — see docs/prototype-b.md,
	# "Separation from Prototype A".
	var prototype_a_targets: Dictionary = {}
	var proto_a: Variant = case_def.get("prototype_a")
	if typeof(proto_a) == TYPE_DICTIONARY:
		for pa_round in _dicts((proto_a as Dictionary).get("rounds", [])):
			for claim_id in DeductionEvaluator.string_array(pa_round.get("required_refutations", [])) + DeductionEvaluator.string_array(pa_round.get("optional_refutations", [])):
				prototype_a_targets[claim_id] = true

	var seen_round_ids: Dictionary = {}
	var seen_targets: Dictionary = {}  # claim id -> round context, across ALL rounds
	for i in (raw_rounds as Array).size():
		var pb_round: Variant = (raw_rounds as Array)[i]
		var round_ctx: String = "%s round %d" % [pb_ctx, i + 1]
		if typeof(pb_round) != TYPE_DICTIONARY:
			errors.append('%s is not an object' % round_ctx)
			continue

		var round_id: String = str(pb_round.get("id", ""))
		if round_id == "":
			errors.append('%s has no "id"' % round_ctx)
		elif seen_round_ids.has(round_id):
			errors.append('%s duplicates round id "%s" (already used by round %d)' % [round_ctx, round_id, seen_round_ids[round_id]])
		else:
			seen_round_ids[round_id] = i + 1

		_require_text(pb_round.get("question"), "%s question" % round_ctx, errors)
		_require_text(pb_round.get("success_explanation"), "%s success_explanation" % round_ctx, errors)

		var target: String = str(pb_round.get("target", ""))
		var target_claim: Dictionary = DeductionEvaluator.find_claim(case_def, target)
		if target_claim.is_empty():
			errors.append('%s references undefined target claim "%s"' % [round_ctx, target])
			continue
		if str(target_claim.get("kind", "")) != "deduction":
			errors.append('%s target "%s" is a %s, not a deduction — Prototype B may only connect clues into a DEDUCTION, never a statement, hypothesis, explanation or the final conclusion' % [round_ctx, target, target_claim.get("kind", "")])
			continue
		if prototype_a_targets.has(target):
			errors.append('%s target "%s" is also a Prototype A statement-contradiction target — Prototype B must target a broader deduction claim, never the same claim Prototype A cross-examines' % [round_ctx, target])
		if seen_targets.has(target):
			errors.append('%s targets "%s" a second time (already targeted in %s) — a claim may only be a Prototype B round target once' % [round_ctx, target, seen_targets[target]])
		else:
			seen_targets[target] = round_ctx

		var relation: String = str(pb_round.get("relation", ""))
		if not DeductionEvaluator.RELATIONS.has(relation):
			errors.append('%s relation "%s" is not a valid relation — supported relations are %s' % [round_ctx, relation, ", ".join(DeductionEvaluator.RELATIONS)])
			continue

		var slot_count: int = TimelineEvaluator.parse_minutes(pb_round.get("slot_count"), -1)
		if slot_count < PROTOTYPE_B_MIN_SLOT_COUNT:
			errors.append('%s slot_count must be a whole number of at least %d (a single clue must never be enough to connect) — got %s' % [round_ctx, PROTOTYPE_B_MIN_SLOT_COUNT, pb_round.get("slot_count")])
			continue

		_validate_prototype_b_target(case_def, target, target_claim, relation, slot_count, pool_ids, round_ctx, errors)


## The target must have at least one proof set whose relation and item COUNT
## exactly match the round's (relation, slot_count) — "proof cardinality
## inconsistent with visible slots" — made only of evidence already in
## evidence_pool (never a derived deduction: Prototype B only ever selects
## evidence — see docs/prototype-b.md), and no PROPER SUBSET of that accepted
## set may itself already resolve the target ("valid proper subset that would
## make a larger connection redundant" / "single-evidence shortcut" — the
## anti-brute-force rule, checked here with the real evaluator against every
## non-empty proper subset, bounded since slot_count is always small).
static func _validate_prototype_b_target(case_def: Dictionary, target: String, target_claim: Dictionary, relation: String, slot_count: int, pool_ids: Dictionary, round_ctx: String, errors: Array[String]) -> void:
	var matching_sets: Array[Dictionary] = []
	for proof_set in _dicts(target_claim.get("proof_sets", [])):
		if str(proof_set.get("relation", "")) != relation:
			continue
		var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
		if requires.size() == slot_count:
			matching_sets.append(proof_set)
	if matching_sets.is_empty():
		errors.append('%s target "%s" has no %s proof set with exactly %d required item(s) — proof cardinality must match the visible slot count, or the round could never be won' % [round_ctx, target, relation, slot_count])
		return

	var fresh_session := DeductionSession.new(str(case_def.get("id", "")))
	for proof_set in matching_sets:
		var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
		for item_id in requires:
			if _claim_kind(case_def, item_id) == "deduction":
				errors.append('%s target "%s" accepted proof set "%s" requires "%s", which is a deduction — Prototype B rounds may only require EVIDENCE items, never a derived deduction as a selectable clue' % [round_ctx, target, proof_set.get("id", ""), item_id])
			elif DeductionEvaluator.find_evidence(case_def, item_id).is_empty():
				errors.append('%s target "%s" accepted proof set "%s" references undefined evidence "%s"' % [round_ctx, target, proof_set.get("id", ""), item_id])
			elif not pool_ids.has(item_id):
				errors.append('%s target "%s" is solvable with evidence "%s", which is missing from prototype_b.evidence_pool' % [round_ctx, target, item_id])
		if requires.size() <= 6:  # bounded — 2^6-2 = 62 subsets, cheap; real rounds are 2-4 items
			for subset in _proper_subsets(requires):
				var result: Dictionary = DeductionEvaluator.classify_attempt(case_def, fresh_session, target, relation, subset)
				if DeductionEvaluator.is_valid_category(str(result.get("category", ""))):
					errors.append('%s target "%s" accepted proof set "%s" has a smaller subset %s that ALREADY resolves it — a player could submit fewer clues than the round\'s slot_count and still win, defeating the anti-brute-force rule' % [round_ctx, target, proof_set.get("id", ""), subset])


## Every non-empty PROPER subset of `items` (excludes both the empty set and
## the full set), as a bitmask enumeration — cheap for the small (2-6 item)
## lists a Prototype B proof set actually has.
static func _proper_subsets(items: Array[String]) -> Array:
	var subsets: Array = []
	var n: int = items.size()
	for mask in range(1, (1 << n) - 1):
		var subset: Array[String] = []
		for bit in n:
			if mask & (1 << bit) != 0:
				subset.append(items[bit])
		subsets.append(subset)
	return subsets


## [[key, context], ...] additional translation keys Prototype B's optional
## data layer introduces — round questions, success explanations and
## completion_text. Called from ContentValidator alongside collect_text_keys()
## (see docs/deduction-system.md, "Content validation").
static func collect_prototype_b_text_keys(case_def: Dictionary) -> Array[Array]:
	var keys: Array[Array] = []
	var proto: Variant = case_def.get("prototype_b")
	if typeof(proto) != TYPE_DICTIONARY:
		return keys
	var ctx: String = 'Deduction case "%s" prototype_b' % str(case_def.get("id", ""))
	keys.append([proto.get("completion_text", ""), "%s completion_text" % ctx])
	for pb_round in _dicts(proto.get("rounds", [])):
		var round_ctx: String = '%s round "%s"' % [ctx, pb_round.get("id", "")]
		keys.append([pb_round.get("question", ""), "%s question" % round_ctx])
		keys.append([pb_round.get("success_explanation", ""), "%s success_explanation" % round_ctx])
	return keys


## Appended to structural_signature() (see below) when a case declares
## prototype_b, so validate_structural_equivalence() enforces the same
## round/target/slot-count SHAPE across X/Y/Z automatically. Roles only,
## never ids or translation keys: a round is compared by index.
static func _prototype_b_signature_lines(case_def: Dictionary, role_of: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var proto: Variant = case_def.get("prototype_b")
	if typeof(proto) != TYPE_DICTIONARY:
		return lines
	lines.append("prototype_b:evidence_pool=%s" % _roles(proto.get("evidence_pool", []), role_of))
	var rounds: Array[Dictionary] = _dicts(proto.get("rounds", []))
	lines.append("prototype_b:round_count=%d" % rounds.size())
	for i in rounds.size():
		var pb_round: Dictionary = rounds[i]
		lines.append("prototype_b:round=%d:target=%s:relation=%s:slot_count=%d" % [
			i, role_of.get(str(pb_round.get("target", "")), ""), pb_round.get("relation", ""),
			TimelineEvaluator.parse_minutes(pb_round.get("slot_count"), -1),
		])
	return lines


# ---------------------------------------------------------------------------
# Prototype C (Milestone 1.13) — optional per-case data layer under
# case_def["prototype_c"]: {fixed_events, movable_events, time_slots,
# objective, visible_constraint_facts, contradiction, hint_ladder,
# completion_text}. See docs/prototype-c.md. Absent entirely on a case with
# no Prototype C content (e.g. the hand-built fixtures) — this whole section
# is then a no-op.
##
## Deliberately adds ZERO new timeline constraint vocabulary and ZERO new
## grading logic: every check below either cross-references the case's own
## `timeline` section (already validated by _validate_timeline/
## _validate_constraint above) or runs the exact same TimelineEvaluator the
## game runs, via enumerate_accepted_prototype_c_timelines() — never a
## private re-implementation of constraint semantics.

static func _find_timeline_constraint(case_def: Dictionary, constraint_id: String) -> Dictionary:
	for constraint in TimelineEvaluator.constraints(case_def):
		if str(constraint.get("id", "")) == constraint_id:
			return constraint
	return {}


## Every UI-offered placement (movable events assigned from the case's own
## authored `time_slots`, fixed events pinned to their authored `fixed_time`
## constraint) that TimelineEvaluator.evaluate() accepts. Bounded by
## construction — the offered domain is the small, finite candidate list
## authored specifically for the Prototype C UI (docs/prototype-c.md,
## "Candidate time-slot domain"), never searched, widened or solved for.
## Returns [] when prototype_c is absent or malformed enough that no
## placement could even be built.
static func enumerate_accepted_prototype_c_timelines(case_def: Dictionary) -> Array[Dictionary]:
	var accepted: Array[Dictionary] = []
	var proto: Variant = case_def.get("prototype_c")
	if typeof(proto) != TYPE_DICTIONARY:
		return accepted
	var movable_ids: Array[String] = DeductionEvaluator.string_array(proto.get("movable_events", []))
	var slots: Array[String] = DeductionEvaluator.string_array(proto.get("time_slots", []))
	if movable_ids.is_empty() or slots.is_empty():
		return accepted

	var fixed_placement: Dictionary = {}
	for event_id in DeductionEvaluator.string_array(proto.get("fixed_events", [])):
		for constraint in TimelineEvaluator.constraints(case_def):
			if str(constraint.get("type", "")) == "fixed_time" and str(constraint.get("event", "")) == event_id:
				fixed_placement[event_id] = str(constraint.get("time", ""))

	var total: int = 1
	for _i in movable_ids.size():
		total *= slots.size()
	for combo_index in total:
		var placement: Dictionary = fixed_placement.duplicate()
		var remainder: int = combo_index
		for event_id in movable_ids:
			placement[event_id] = slots[remainder % slots.size()]
			remainder = remainder / slots.size()
		var result: Dictionary = TimelineEvaluator.evaluate(case_def, placement)
		if str(result.get("category", "")) == TimelineEvaluator.CONSISTENT:
			accepted.append(placement)
	return accepted


## Visible facts that, ON THEIR OWN, make the disputed claim impossible
## (Milestone 1.14's temporal justification — docs/prototype-c.md, "Final
## claim justification"): the fact is satisfiable on the board, yet no
## placement of the events it and the claim reference satisfies both. Fixed
## events sit at their authored fixed_time (they are locked on the board);
## every other referenced event ranges over the case's own candidate
## time_slots — the same bounded domain the rest of Prototype C uses, never
## searched beyond it. Only facts sharing an event with the claim are
## enumerated at all, and at most |time_slots|^3 placements per fact (a pair
## fact plus a single-event claim), so this is cheap enough for the always-on
## validator, unlike enumerate_accepted_prototype_c_timelines() below. Every
## check goes through TimelineEvaluator.is_constraint_satisfied() — no private
## constraint semantics.
static func prototype_c_facts_ruling_out_claim(case_def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var proto: Variant = case_def.get("prototype_c")
	if typeof(proto) != TYPE_DICTIONARY:
		return out
	var contradiction: Variant = proto.get("contradiction")
	var facts: Variant = proto.get("visible_constraint_facts")
	var slots: Array[String] = DeductionEvaluator.string_array(proto.get("time_slots", []))
	if typeof(contradiction) != TYPE_DICTIONARY or typeof(facts) != TYPE_DICTIONARY or slots.is_empty():
		return out
	var claim_constraint: Dictionary = _find_timeline_constraint(case_def, str((contradiction as Dictionary).get("constraint_ref", "")))
	if claim_constraint.is_empty():
		return out

	var events: Dictionary = TimelineEvaluator.event_index(case_def)
	var fixed_starts: Dictionary = {}
	for event_id in DeductionEvaluator.string_array(proto.get("fixed_events", [])):
		for constraint in TimelineEvaluator.constraints(case_def):
			if str(constraint.get("type", "")) == "fixed_time" and str(constraint.get("event", "")) == event_id:
				fixed_starts[event_id] = TimelineEvaluator.parse_time(constraint.get("time"))
	var claim_events: Array[String] = TimelineEvaluator.constraint_event_ids(claim_constraint)

	for fact_id in (facts as Dictionary):
		var fact: Dictionary = _find_timeline_constraint(case_def, str(fact_id))
		var fact_events: Array[String] = TimelineEvaluator.constraint_event_ids(fact)
		if fact.is_empty() or not fact_events.any(func(event_id: String) -> bool: return claim_events.has(event_id)):
			continue
		var free: Array[String] = []
		for event_id in fact_events + claim_events:
			if not fixed_starts.has(event_id) and not free.has(event_id):
				free.append(event_id)
		if free.size() > 3:
			continue
		var fact_satisfiable := false
		var jointly_satisfiable := false
		for combo_index in int(pow(slots.size(), free.size())):
			var starts: Dictionary = fixed_starts.duplicate()
			var remainder: int = combo_index
			for event_id in free:
				starts[event_id] = TimelineEvaluator.parse_time(slots[remainder % slots.size()])
				remainder = remainder / slots.size()
			if not TimelineEvaluator.is_constraint_satisfied(fact, starts, events):
				continue
			fact_satisfiable = true
			if TimelineEvaluator.is_constraint_satisfied(claim_constraint, starts, events):
				jointly_satisfiable = true
				break
		if fact_satisfiable and not jointly_satisfiable:
			out.append(str(fact_id))
	return out


static func _validate_prototype_c(case_def: Dictionary, ctx: String, errors: Array[String], warnings: Array[String]) -> void:
	var proto: Variant = case_def.get("prototype_c")
	if proto == null:
		return
	if typeof(proto) != TYPE_DICTIONARY:
		errors.append('%s prototype_c must be an object' % ctx)
		return
	var pc_ctx: String = "%s prototype_c" % ctx

	var events: Dictionary = TimelineEvaluator.event_index(case_def)
	var fixed_ids: Array[String] = DeductionEvaluator.string_array(proto.get("fixed_events"))
	var movable_ids: Array[String] = DeductionEvaluator.string_array(proto.get("movable_events"))
	if not _is_string_array(proto.get("fixed_events")) or fixed_ids.is_empty():
		errors.append('%s must declare a non-empty "fixed_events" array of timeline event ids' % pc_ctx)
	if not _is_string_array(proto.get("movable_events")) or movable_ids.size() < 2:
		errors.append('%s must declare a "movable_events" array of at least 2 timeline event ids' % pc_ctx)

	var seen_ids: Dictionary = {}
	for event_id in fixed_ids + movable_ids:
		if not events.has(event_id):
			errors.append('%s references undefined timeline event "%s"' % [pc_ctx, event_id])
		elif seen_ids.has(event_id):
			errors.append('%s lists timeline event "%s" in both fixed_events and movable_events (or twice in one) — every event must be exactly one or the other' % [pc_ctx, event_id])
		else:
			seen_ids[event_id] = true
	for event_id in events:
		if not seen_ids.has(event_id):
			errors.append('%s does not place timeline event "%s" in either fixed_events or movable_events' % [pc_ctx, event_id])

	for event_id in fixed_ids:
		var fixed_time_constraints := 0
		for constraint in TimelineEvaluator.constraints(case_def):
			if str(constraint.get("type", "")) == "fixed_time" and str(constraint.get("event", "")) == event_id:
				fixed_time_constraints += 1
		if fixed_time_constraints != 1:
			errors.append('%s fixed event "%s" must have exactly one fixed_time timeline constraint (found %d) — a fixed event\'s locked time is always read from its own constraint, never authored twice' % [pc_ctx, event_id, fixed_time_constraints])
	for event_id in movable_ids:
		for constraint in TimelineEvaluator.constraints(case_def):
			if str(constraint.get("type", "")) == "fixed_time" and str(constraint.get("event", "")) == event_id:
				errors.append('%s movable event "%s" has its own fixed_time constraint — a movable event can never be pinned to one exact time' % [pc_ctx, event_id])

	var raw_slots: Variant = proto.get("time_slots")
	var slots: Array[String] = DeductionEvaluator.string_array(raw_slots)
	if not _is_string_array(raw_slots) or slots.is_empty():
		errors.append('%s must declare a non-empty "time_slots" array of "HH:MM" strings' % pc_ctx)
	var seen_slots: Dictionary = {}
	for slot in slots:
		if TimelineEvaluator.parse_time(slot) < 0:
			errors.append('%s time_slots entry "%s" is not a valid HH:MM time' % [pc_ctx, slot])
		elif seen_slots.has(slot):
			errors.append('%s duplicates time_slots entry "%s"' % [pc_ctx, slot])
		else:
			seen_slots[slot] = true
	# Crossing midnight: every movable event must be able to occupy any
	# candidate slot without its own duration running past 23:59 — the
	# single-day model has no next-day wraparound (docs/deduction-system.md,
	# "Known limitations").
	for slot in slots:
		var start: int = TimelineEvaluator.parse_time(slot)
		if start < 0:
			continue
		for event_id in movable_ids:
			var duration: int = TimelineEvaluator.parse_minutes((events.get(event_id, {}) as Dictionary).get("duration_minutes"), 0)
			if start + maxi(duration, 0) > 1439:
				errors.append('%s candidate time "%s" would let event "%s" (duration %d min) cross midnight, which this single-day model cannot represent' % [pc_ctx, slot, event_id, duration])

	_require_text(proto.get("objective"), "%s objective" % pc_ctx, errors)
	_require_text(proto.get("completion_text"), "%s completion_text" % pc_ctx, errors)

	var required_constraint_ids: Dictionary = {}
	for constraint in TimelineEvaluator.constraints(case_def):
		if constraint.get("required", true) != false:
			required_constraint_ids[str(constraint.get("id", ""))] = true

	var facts: Variant = proto.get("visible_constraint_facts")
	if typeof(facts) != TYPE_DICTIONARY:
		errors.append('%s visible_constraint_facts must be an object mapping a required constraint id -> translation key' % pc_ctx)
		facts = {}
	for constraint_id in required_constraint_ids:
		if not (facts as Dictionary).has(constraint_id):
			errors.append('%s required timeline constraint "%s" has no visible_constraint_facts entry — a required constraint must never be a hidden author-only rule' % [pc_ctx, constraint_id])
	for constraint_id in (facts as Dictionary):
		var constraint: Dictionary = _find_timeline_constraint(case_def, str(constraint_id))
		if constraint.is_empty():
			errors.append('%s visible_constraint_facts references undefined timeline constraint "%s"' % [pc_ctx, constraint_id])
		elif not required_constraint_ids.has(str(constraint_id)):
			errors.append('%s visible_constraint_facts entry "%s" names an OPTIONAL constraint — only required (objectively true) constraints may be shown as facts; an optional constraint (e.g. a claimed time) must stay hidden' % [pc_ctx, constraint_id])
		else:
			_require_text((facts as Dictionary).get(constraint_id), '%s visible_constraint_facts["%s"]' % [pc_ctx, constraint_id], errors)

	var contradiction: Variant = proto.get("contradiction")
	if typeof(contradiction) != TYPE_DICTIONARY:
		errors.append('%s must declare a "contradiction" object' % pc_ctx)
		contradiction = {}
	var claim_id: String = str((contradiction as Dictionary).get("claim", ""))
	var claim: Dictionary = DeductionEvaluator.find_claim(case_def, claim_id)
	if claim.is_empty():
		errors.append('%s contradiction.claim references undefined claim "%s"' % [pc_ctx, claim_id])
	elif str(claim.get("kind", "")) != "statement":
		errors.append('%s contradiction.claim "%s" is a %s, not a statement — the final claim check disputes an NPC STATEMENT, never a hypothesis, deduction, explanation or the conclusion' % [pc_ctx, claim_id, claim.get("kind", "")])

	var constraint_ref: String = str((contradiction as Dictionary).get("constraint_ref", ""))
	var contradiction_constraint: Dictionary = _find_timeline_constraint(case_def, constraint_ref)
	if contradiction_constraint.is_empty():
		errors.append('%s contradiction.constraint_ref references undefined timeline constraint "%s"' % [pc_ctx, constraint_ref])
	else:
		if contradiction_constraint.get("required", true) != false:
			errors.append('%s contradiction.constraint_ref "%s" must be an OPTIONAL constraint — a required constraint is already a known fact every accepted timeline satisfies, so it could never be the "impossible" claim' % [pc_ctx, constraint_ref])
		if str(contradiction_constraint.get("source", "")) != claim_id and claim_id != "":
			errors.append('%s contradiction.constraint_ref "%s" is sourced from "%s", not from contradiction.claim "%s" — the hypothetical constraint must represent that same claim' % [pc_ctx, constraint_ref, contradiction_constraint.get("source", ""), claim_id])
		if (facts as Dictionary).has(constraint_ref):
			errors.append('%s contradiction.constraint_ref "%s" must not also appear in visible_constraint_facts — the disputed claim stays hidden until the timeline is accepted' % [pc_ctx, constraint_ref])

	# Milestone 1.14 — the final verdict needs a temporal justification
	# (docs/prototype-c.md, "Final claim justification"): every listed fact must
	# be selectable, bear on the claim, and ON ITS OWN rule the claim out; every
	# visible fact that does so must be listed, so no valid justification is
	# ever rejected.
	var refs_raw: Variant = (contradiction as Dictionary).get("supporting_constraint_refs")
	var refs: Array[String] = DeductionEvaluator.string_array(refs_raw)
	if not _is_string_array(refs_raw) or refs.is_empty():
		errors.append('%s contradiction.supporting_constraint_refs must be a non-empty array of visible fact constraint ids — the final verdict needs at least one temporal justification the player can select' % pc_ctx)
	var claim_event_ids: Array[String] = TimelineEvaluator.constraint_event_ids(contradiction_constraint)
	var structurally_valid_refs: Array[String] = []
	for ref in refs:
		if structurally_valid_refs.has(ref):
			errors.append('%s contradiction.supporting_constraint_refs lists "%s" more than once' % [pc_ctx, ref])
		elif ref == constraint_ref:
			errors.append('%s contradiction.supporting_constraint_refs must not list the disputed claim\'s own constraint "%s" — a justification is an established fact, never the claim itself' % [pc_ctx, ref])
		elif not (facts as Dictionary).has(ref):
			errors.append('%s contradiction.supporting_constraint_refs entry "%s" is not a visible_constraint_facts entry — a justification must be a fact the player can actually read and select' % [pc_ctx, ref])
		elif not TimelineEvaluator.constraint_event_ids(_find_timeline_constraint(case_def, ref)).any(func(event_id: String) -> bool: return claim_event_ids.has(event_id)):
			errors.append('%s contradiction.supporting_constraint_refs entry "%s" shares no timeline event with the disputed claim — on its own it cannot bear on that claim at all' % [pc_ctx, ref])
		else:
			structurally_valid_refs.append(ref)
	if not contradiction_constraint.is_empty() and not refs.is_empty():
		var ruling_out: Array[String] = prototype_c_facts_ruling_out_claim(case_def)
		for ref in structurally_valid_refs:
			if not ruling_out.has(ref):
				errors.append('%s contradiction.supporting_constraint_refs entry "%s" does not, on its own, rule out the disputed claim anywhere in the candidate time-slot domain — it does not genuinely participate in the contradiction' % [pc_ctx, ref])
		for fact_id in ruling_out:
			if not refs.has(fact_id):
				errors.append('%s contradiction.supporting_constraint_refs omits "%s", a visible fact that on its own rules out the disputed claim — every genuinely valid justification must be accepted' % [pc_ctx, fact_id])

	var ladder: Variant = proto.get("hint_ladder")
	if typeof(ladder) != TYPE_ARRAY or (ladder as Array).size() != PROTOTYPE_A_HINT_LEVELS:
		errors.append('%s hint_ladder must be an array of exactly %d translation keys' % [pc_ctx, PROTOTYPE_A_HINT_LEVELS])
	else:
		for level_index in (ladder as Array).size():
			_require_text((ladder as Array)[level_index], '%s hint_ladder level %d' % [pc_ctx, level_index + 1], errors)

	# DELIBERATELY NOT run here: "at least one UI-offered timeline is
	# accepted" and "every accepted timeline makes the claim impossible" are
	# real, important checks, but enumerating the full candidate domain
	# (movable_events.size()-many nested loops over time_slots) through the
	# real TimelineEvaluator costs about half a second per case — cheap once,
	# but ContentValidator.validate() (and therefore this function) runs on
	# EVERY ContentDB load, including every other focused test's boot, so
	# baking it in here would slow down the entire FAST/FULL suite, not just
	# Prototype C's own tests. Milestone 1.13 explicitly allows this: "may be
	# a bounded test/content-validation helper." So it lives instead in
	# enumerate_accepted_prototype_c_timelines() (below), a public helper
	# called directly, once, by prototype_c_content_test.gd — same real
	# TimelineEvaluator, same bounded domain, just not on every boot.


## [[key, context], ...] additional translation keys Prototype C's optional
## data layer introduces — objective, every visible_constraint_facts value,
## the contradiction explanation, the hint ladder and completion_text. Called
## from ContentValidator alongside collect_text_keys() (see
## docs/deduction-system.md, "Content validation").
static func collect_prototype_c_text_keys(case_def: Dictionary) -> Array[Array]:
	var keys: Array[Array] = []
	var proto: Variant = case_def.get("prototype_c")
	if typeof(proto) != TYPE_DICTIONARY:
		return keys
	var ctx: String = 'Deduction case "%s" prototype_c' % str(case_def.get("id", ""))
	keys.append([proto.get("objective", ""), "%s objective" % ctx])
	keys.append([proto.get("completion_text", ""), "%s completion_text" % ctx])
	var facts: Variant = proto.get("visible_constraint_facts", {})
	if typeof(facts) == TYPE_DICTIONARY:
		for constraint_id in (facts as Dictionary):
			keys.append([(facts as Dictionary)[constraint_id], '%s visible_constraint_facts["%s"]' % [ctx, constraint_id]])
	var contradiction: Variant = proto.get("contradiction", {})
	if typeof(contradiction) == TYPE_DICTIONARY:
		keys.append([(contradiction as Dictionary).get("explanation", ""), "%s contradiction.explanation" % ctx])
	var ladder: Variant = proto.get("hint_ladder", [])
	if typeof(ladder) == TYPE_ARRAY:
		for level_index in (ladder as Array).size():
			keys.append([(ladder as Array)[level_index], "%s hint_ladder level %d" % [ctx, level_index + 1]])
	return keys


## Appended to structural_signature() (see below) when a case declares
## prototype_c, so validate_structural_equivalence() enforces the same
## fixed/movable-role, fact-shape and contradiction SHAPE across X/Y/Z
## automatically. Roles and constraint TYPES only, never ids, times or
## translation keys.
static func _prototype_c_signature_lines(case_def: Dictionary, role_of: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var proto: Variant = case_def.get("prototype_c")
	if typeof(proto) != TYPE_DICTIONARY:
		return lines
	lines.append("prototype_c:fixed=%s" % _roles(proto.get("fixed_events", []), role_of))
	lines.append("prototype_c:movable=%s" % _roles(proto.get("movable_events", []), role_of))
	lines.append("prototype_c:slot_count=%d" % DeductionEvaluator.string_array(proto.get("time_slots", [])).size())

	var fact_types: Array = []
	var facts: Variant = proto.get("visible_constraint_facts", {})
	if typeof(facts) == TYPE_DICTIONARY:
		for constraint_id in (facts as Dictionary):
			fact_types.append(str(_find_timeline_constraint(case_def, str(constraint_id)).get("type", "")))
	fact_types.sort()
	lines.append("prototype_c:fact_constraint_types=[%s]" % ",".join(PackedStringArray(fact_types)))

	var contradiction: Variant = proto.get("contradiction", {})
	if typeof(contradiction) == TYPE_DICTIONARY:
		var claim_role: String = role_of.get(str((contradiction as Dictionary).get("claim", "")), "")
		var constraint_type: String = str(_find_timeline_constraint(case_def, str((contradiction as Dictionary).get("constraint_ref", ""))).get("type", ""))
		lines.append("prototype_c:contradiction_claim_role=%s:constraint_type=%s" % [claim_role, constraint_type])
		var support_types: Array = []
		for ref in DeductionEvaluator.string_array((contradiction as Dictionary).get("supporting_constraint_refs", [])):
			support_types.append(str(_find_timeline_constraint(case_def, ref).get("type", "")))
		support_types.sort()
		lines.append("prototype_c:supporting_fact_types=[%s]" % ",".join(PackedStringArray(support_types)))
	return lines


# ---------------------------------------------------------------------------
# Structural equivalence

## A case's proof-graph shape in role terms only — no ids, no text — as a
## sorted list of entries. Two cases with the same structural_template must
## produce identical signatures: same roles, same claim kinds and ground
## truth, same proof sets (relation + input roles), same unlocks, question
## resolutions, timeline constraint shapes and hint ladders.
static func structural_signature(case_def: Dictionary) -> Array[String]:
	var role_of: Dictionary = {}
	for section in ["suspects", "questions", "evidence", "claims"]:
		for entry in _dicts(case_def.get(section, [])):
			role_of[str(entry.get("id", ""))] = str(entry.get("structural_role", ""))
	for event in _dicts(_timeline(case_def).get("events", [])):
		role_of[str(event.get("id", ""))] = str(event.get("structural_role", ""))

	var signature: Array[String] = []
	var is_acyclic: bool = find_dependency_cycles(case_def).is_empty()
	for suspect in _dicts(case_def.get("suspects", [])):
		signature.append("suspect:%s" % role_of.get(str(suspect.get("id", "")), ""))
	for evidence in _dicts(case_def.get("evidence", [])):
		signature.append("evidence:%s:certainty=%s:misleading=%s:unlock=%s" % [
			evidence.get("structural_role", ""), evidence.get("certainty", ""), evidence.get("misleading", false) == true,
			_roles(evidence.get("unlock_requires", []), role_of),
		])
	for claim in _dicts(case_def.get("claims", [])):
		var claim_role: String = str(claim.get("structural_role", ""))
		signature.append("claim:%s:kind=%s:veracity=%s:required=%s:speaker=%s:compatible=%s" % [
			claim_role, claim.get("kind", ""), claim.get("veracity", ""), claim.get("required", false) == true,
			role_of.get(str(claim.get("speaker", "")), ""), _roles(claim.get("compatible", []), role_of),
		])
		for proof_set in _dicts(claim.get("proof_sets", [])):
			# depth= makes alternate proof paths and conclusions compare by
			# inference depth too, not just by input roles.
			var depth: int = proof_set_depth(case_def, proof_set) if is_acyclic else -1
			signature.append("proof:%s:%s:%s:depth=%d" % [claim_role, proof_set.get("relation", ""), _roles(proof_set.get("requires", []), role_of), depth])
	for question in _dicts(case_def.get("questions", [])):
		var resolutions: Array = []
		for entry in _dicts(question.get("resolved_by", [])):
			resolutions.append("%s/%s" % [role_of.get(str(entry.get("claim", "")), ""), entry.get("status", "")])
		resolutions.sort()
		signature.append("question:%s:required=%s:resolved_by=[%s]" % [question.get("structural_role", ""), question.get("required", false) == true, ",".join(PackedStringArray(resolutions))])
	for event in _dicts(_timeline(case_def).get("events", [])):
		signature.append("timeline_event:%s:actor=%s:certainty=%s" % [event.get("structural_role", ""), role_of.get(str(event.get("actor", "")), ""), event.get("certainty", "")])
	for constraint in TimelineEvaluator.constraints(case_def):
		var event_roles: Array = []
		for event_id in TimelineEvaluator.constraint_event_ids(constraint):
			event_roles.append(role_of.get(event_id, ""))
		if constraint.get("type") != "before":
			event_roles.sort()
		signature.append("constraint:%s:events=[%s]:required=%s:source=%s" % [
			constraint.get("type", ""), ",".join(PackedStringArray(event_roles)), constraint.get("required", true) != false,
			role_of.get(str(constraint.get("source", "")), ""),
		])
	for ladder in _dicts(case_def.get("hints", [])):
		var level_shapes: Array = []
		for level in _dicts(ladder.get("levels", [])):
			var refs: Array = []
			for key in ["question", "deduction"]:
				if level.has(key):
					refs.append(role_of.get(str(level.get(key)), ""))
			for evidence_id in DeductionEvaluator.string_array(level.get("evidence", [])):
				refs.append(role_of.get(evidence_id, ""))
			for category in DeductionEvaluator.string_array(level.get("categories", [])):
				refs.append("#" + category)
			refs.sort()
			level_shapes.append("%s(%s)" % [level.get("kind", ""), ",".join(PackedStringArray(refs))])
		signature.append("hint:%s:%s" % [role_of.get(str(ladder.get("target", "")), ""), "|".join(PackedStringArray(level_shapes))])
	var truth: Variant = case_def.get("ground_truth", {})
	if typeof(truth) == TYPE_DICTIONARY:
		signature.append("ground_truth:culprit=%s:credential_owner=%s:conclusion=%s" % [
			role_of.get(str(truth.get("culprit", "")), ""), role_of.get(str(truth.get("credential_owner", "")), ""),
			role_of.get(str(truth.get("conclusion", "")), ""),
		])
	signature.append_array(_prototype_a_signature_lines(case_def, role_of))
	signature.append_array(_prototype_b_signature_lines(case_def, role_of))
	signature.append_array(_prototype_c_signature_lines(case_def, role_of))
	signature.sort()
	return signature


## Groups cases by metadata.structural_template and reports every case whose
## signature differs from the group's first case (by id order), naming the
## missing and unexpected entries.
static func validate_structural_equivalence(cases: Array, errors: Array[String]) -> void:
	var groups: Dictionary = {}
	for case_def in cases:
		if typeof(case_def) != TYPE_DICTIONARY or _template(case_def) == "":
			continue
		if not groups.has(_template(case_def)):
			groups[_template(case_def)] = []
		(groups[_template(case_def)] as Array).append(case_def)
	var templates: Array = groups.keys()
	templates.sort()
	for template in templates:
		var group: Array = groups[template]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
		var reference: Dictionary = group[0]
		var reference_counts: Dictionary = _counts(structural_signature(reference))
		for i in range(1, group.size()):
			var other: Dictionary = group[i]
			var other_counts: Dictionary = _counts(structural_signature(other))
			var missing: Array[String] = _difference(reference_counts, other_counts)
			var unexpected: Array[String] = _difference(other_counts, reference_counts)
			if missing.is_empty() and unexpected.is_empty():
				continue
			errors.append('Deduction case "%s" is not structurally equivalent to "%s" (structural_template "%s") — missing: %s; unexpected: %s' % [
				other.get("id", ""), reference.get("id", ""), template, _summarize(missing), _summarize(unexpected),
			])


# ---------------------------------------------------------------------------
# Translation keys (checked by ContentValidator)

## [[key, context], ...] for every player-facing field in a deduction case.
static func collect_text_keys(case_def: Dictionary) -> Array[Array]:
	var ctx: String = 'Deduction case "%s"' % str(case_def.get("id", ""))
	var keys: Array[Array] = [
		[case_def.get("display_name", ""), "%s display_name" % ctx],
		[case_def.get("description", ""), "%s description" % ctx],
	]
	for suspect in _dicts(case_def.get("suspects", [])):
		keys.append([suspect.get("name", ""), '%s suspect "%s" name' % [ctx, suspect.get("id", "")]])
	for question in _dicts(case_def.get("questions", [])):
		keys.append([question.get("text", ""), '%s question "%s" text' % [ctx, question.get("id", "")]])
	for evidence in _dicts(case_def.get("evidence", [])):
		keys.append([evidence.get("name", ""), '%s evidence "%s" name' % [ctx, evidence.get("id", "")]])
		keys.append([evidence.get("text", ""), '%s evidence "%s" text' % [ctx, evidence.get("id", "")]])
	for claim in _dicts(case_def.get("claims", [])):
		keys.append([claim.get("text", ""), '%s claim "%s" text' % [ctx, claim.get("id", "")]])
	for event in _dicts(_timeline(case_def).get("events", [])):
		keys.append([event.get("label", ""), '%s timeline event "%s" label' % [ctx, event.get("id", "")]])
	for ladder in _dicts(case_def.get("hints", [])):
		for level in _dicts(ladder.get("levels", [])):
			keys.append([level.get("text", ""), '%s hint "%s" level %s text' % [ctx, ladder.get("target", ""), level.get("level", "?")]])
	var truth: Variant = case_def.get("ground_truth", {})
	if typeof(truth) == TYPE_DICTIONARY:
		keys.append([truth.get("summary", ""), "%s ground_truth summary" % ctx])
	return keys


# ---------------------------------------------------------------------------
# Helpers

static func _require_text(value: Variant, context: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or value == "":
		errors.append("%s is missing (a translation key is required)" % context)


static func _dicts(value: Variant) -> Array[Dictionary]:
	return DeductionEvaluator.dict_array(value)


static func _timeline(case_def: Dictionary) -> Dictionary:
	var timeline: Variant = case_def.get("timeline", {})
	return timeline if typeof(timeline) == TYPE_DICTIONARY else {}


static func _find(case_def: Dictionary, section: String, entry_id: String) -> Dictionary:
	for entry in _dicts(case_def.get(section, [])):
		if str(entry.get("id", "")) == entry_id:
			return entry
	return {}


static func _claim_kind(case_def: Dictionary, claim_id: String) -> String:
	return str(DeductionEvaluator.find_claim(case_def, claim_id).get("kind", ""))


## Evidence, or a deduction claim — the only things a proof set may require.
static func _is_input_item(case_def: Dictionary, item_id: String) -> bool:
	return not DeductionEvaluator.find_evidence(case_def, item_id).is_empty() or _claim_kind(case_def, item_id) == "deduction"


## "evidence", "claim", or "" — for a constraint's source reference.
static func find_item_kind(case_def: Dictionary, item_id: String) -> String:
	if not DeductionEvaluator.find_evidence(case_def, item_id).is_empty():
		return "evidence"
	return "claim" if _claim_kind(case_def, item_id) != "" else ""


static func _is_string_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for entry in value:
		if typeof(entry) != TYPE_STRING:
			return false
	return true


static func _roles(ids: Variant, role_of: Dictionary) -> String:
	var roles: Array = []
	for item_id in DeductionEvaluator.string_array(ids):
		roles.append(role_of.get(item_id, "?"))
	roles.sort()
	return "[%s]" % ",".join(PackedStringArray(roles))


static func _counts(entries: Array[String]) -> Dictionary:
	var counts: Dictionary = {}
	for entry in entries:
		counts[entry] = counts.get(entry, 0) + 1
	return counts


static func _difference(from_counts: Dictionary, minus_counts: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry in from_counts:
		for i in from_counts[entry] - minus_counts.get(entry, 0):
			out.append(entry)
	out.sort()
	return out


static func _summarize(entries: Array[String]) -> String:
	if entries.is_empty():
		return "(none)"
	var shown: Array[String] = entries.slice(0, 6)
	var text: String = ", ".join(PackedStringArray(shown))
	return text if entries.size() <= 6 else "%s (+%d more)" % [text, entries.size() - 6]
