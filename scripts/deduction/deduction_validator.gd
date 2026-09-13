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
