class_name CoreLoopAuthorReport
extends RefCounted
## Milestone 1.17 — the author-facing report of one core-loop chapter
## (docs/core-loop-authoring.md, "Inspecting a chapter"). DEBUG/AUTHOR TOOLING
## ONLY: rendered by the Case Debugger's "Core Loop" tab (F1, debug builds) and
## printed by the headless report (scenes/test/core_loop_report.gd). It names
## ids, proof paths, conditions and consequence effects on purpose — nothing
## here may ever reach a player view (CoreLoopPresenter never references it;
## core_loop_author_report_test.gd checks both directions).
##
## Reuses, never re-derives: validation findings come from CoreLoopValidator
## (the same rules ContentValidator runs at boot), producers from
## ContentValidator.find_*_producers(), condition text and "why locked" from
## ConditionEvaluator.describe()/explain(), effect text from
## EffectRunner.describe(), route structure from CoreLoopValidator's public
## helpers. Every line carries one KIND so an author can tell apart:
##   error   — a CoreLoopValidator ERROR (the route is broken);
##   warning — a CoreLoopValidator WARNING (a smell);
##   info    — a static authoring observation about the content;
##   state   — the CURRENT run (only when this chapter is the active one and a
##             chapter-run snapshot is given) — changes as you play.
## The legal-path simulation drives the real GameState, so it is never run
## from inside the game: the headless report runs it and passes the results
## in (`simulation`).

const KIND_ERROR := "error"
const KIND_WARNING := "warning"
const KIND_INFO := "info"
const KIND_STATE := "state"
const KIND_TAGS := {KIND_ERROR: "ERROR", KIND_WARNING: "WARN", KIND_INFO: "info", KIND_STATE: "NOW"}


## Every chapter id that declares a core_loop section, sorted.
static func chapter_ids() -> Array[String]:
	var ids: Array[String] = []
	for chapter_id in ContentDB.get_all_chapter_ids():
		if typeof(ContentDB.get_chapter(String(chapter_id)).get("core_loop")) == TYPE_DICTIONARY:
			ids.append(String(chapter_id))
	ids.sort()
	return ids


## {"chapter_id", "errors": int, "warnings": int, "lines": [{"kind",
## "section", "text"}]}. `snapshot` is GameState.chapter_run (dynamic lines
## appear only when it belongs to this chapter AND the chapter is current);
## `simulation` is {"routes": [{"label", "ok", "failure", "steps", "units",
## "phases"}]} from the headless report, or {} when not run.
static func build(chapter_id: String, snapshot: Dictionary = {}, simulation: Dictionary = {}) -> Dictionary:
	var lines: Array[Dictionary] = []
	var chapter: Dictionary = ContentDB.get_chapter(chapter_id)
	var loop: Variant = chapter.get("core_loop")
	if typeof(loop) != TYPE_DICTIONARY:
		_add(lines, KIND_ERROR, "Chapter", 'Chapter "%s" has no core_loop section.' % chapter_id)
		return _result(chapter_id, lines)
	var live: bool = CaseManager.get_current_chapter_id() == chapter_id and str(snapshot.get("chapter_id", "")) == chapter_id
	var case_def: Dictionary = ContentDB.get_deduction_case(str(loop.get("deduction_case", "")))
	var links: Dictionary = loop.get("evidence_links", {}) if typeof(loop.get("evidence_links")) == TYPE_DICTIONARY else {}
	var phase_of: Dictionary = CoreLoopValidator.phase_index_of(loop)
	var produced: Dictionary = CoreLoopValidator.consequence_products(chapter, phase_of)
	var base: Dictionary = _base_producers()

	_section_chapter(lines, chapter_id, chapter, loop, case_def)
	_section_validation(lines, chapter_id, chapter, base)
	_section_route(lines, loop, snapshot, live)
	var units: Array = loop.get("units", [])
	for unit in units:
		if typeof(unit) == TYPE_DICTIONARY:
			_section_unit(lines, unit, loop, case_def, links, base, produced, phase_of, snapshot, live)
	_section_evidence(lines, links, units, case_def, base, produced)
	_section_completion(lines, chapter_id, chapter, live)
	_section_simulation(lines, simulation)
	return _result(chapter_id, lines)


## Plain text, one "[TAG] section: text" line each — the headless report's
## output and the easiest thing to paste into a review.
static func format_text(report: Dictionary) -> String:
	var out: PackedStringArray = []
	out.append("=== Core loop author report: %s — %d error(s), %d warning(s) ===" % [report.get("chapter_id", ""), report.get("errors", 0), report.get("warnings", 0)])
	for line in report.get("lines", []):
		out.append("[%s] %s: %s" % [KIND_TAGS.get(line.get("kind", ""), "?"), line.get("section", ""), line.get("text", "")])
	return "\n".join(out)


# ---------------------------------------------------------------------------
# Sections

static func _section_chapter(lines: Array[Dictionary], chapter_id: String, chapter: Dictionary, loop: Dictionary, case_def: Dictionary) -> void:
	var owner: String = ""
	for case_id in ContentDB.get_all_case_ids():
		var chapters: Variant = ContentDB.get_case(String(case_id)).get("chapters", [])
		if typeof(chapters) == TYPE_ARRAY and (chapters as Array).has(chapter_id):
			owner = String(case_id)
	var owner_data: Dictionary = ContentDB.get_case(owner)
	_add(lines, KIND_INFO, "Chapter", '%s (case "%s") — canon: %s, deduction case "%s" (%s)' % [chapter_id, owner, loop.get("canon", "missing"), loop.get("deduction_case", ""), "non-canon" if (case_def.get("metadata", {}) as Dictionary).get("canon", true) == false else "canon"])
	var selection: Variant = owner_data.get("sandbox_selection")
	var entry: String = "release New Game default" if owner_data.get("new_game_entry", false) == true else "not the New Game default"
	if typeof(selection) == TYPE_DICTIONARY:
		entry += "; debug sandbox selector position %d" % int((selection as Dictionary).get("order", 0))
	_add(lines, KIND_INFO, "Chapter", entry)
	_add(lines, KIND_INFO, "Chapter", "briefing %s / %s, result %s / %s" % [
		(loop.get("briefing", {}) as Dictionary).get("title", ""), (loop.get("briefing", {}) as Dictionary).get("text", ""),
		(loop.get("result", {}) as Dictionary).get("title", ""), (loop.get("result", {}) as Dictionary).get("text", ""),
	])


static func _section_validation(lines: Array[Dictionary], chapter_id: String, chapter: Dictionary, base: Dictionary) -> void:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	CoreLoopValidator.validate_chapter(chapter_id, chapter, base, errors, warnings)
	for message in errors:
		_add(lines, KIND_ERROR, "Validation", message)
	for message in warnings:
		_add(lines, KIND_WARNING, "Validation", message)
	if errors.is_empty() and warnings.is_empty():
		_add(lines, KIND_INFO, "Validation", "CoreLoopValidator: no errors, no warnings (the same rules ContentValidator runs at boot)")


static func _section_route(lines: Array[Dictionary], loop: Dictionary, snapshot: Dictionary, live: bool) -> void:
	var phases: Array = loop.get("phases", [])
	for i in phases.size():
		var phase: Dictionary = phases[i]
		var text: String = "%d. %s" % [i + 1, phase.get("id", "")]
		if str(phase.get("kind", "unit")) == "briefing":
			text += " — briefing"
		else:
			text += " — unit %s completes on %s" % [phase.get("unit", ""), phase.get("completes_on", "")]
		_add(lines, KIND_INFO, "Route", "%s — objective %s" % [text, phase.get("objective", "")])
	_add(lines, KIND_INFO, "Route", "%d. completed — entered when the last phase's consequence fires the chapter's completion_event" % (phases.size() + 1))
	if live:
		var index: int = PrototypeContext.count(snapshot.get("phase_index"))
		_add(lines, KIND_STATE, "Route", 'current phase: %s (index %d) — run %s, revision %s, completed: %s, run help result: %s (stored, never shown to the player)' % [
			snapshot.get("phase_id", ""), index, snapshot.get("run_id", ""), snapshot.get("revision", ""), snapshot.get("completed", false), snapshot.get("run_help_result", ""),
		])
		if str(snapshot.get("open_unit", "")) != "":
			_add(lines, KIND_STATE, "Route", "mechanic open: %s" % snapshot.get("open_unit", ""))
	else:
		_add(lines, KIND_INFO, "Route", "not the active chapter — no current-run state shown")


static func _section_unit(lines: Array[Dictionary], unit: Dictionary, loop: Dictionary, case_def: Dictionary, links: Dictionary, base: Dictionary, produced: Dictionary, phase_of: Dictionary, snapshot: Dictionary, live: bool) -> void:
	var unit_id: String = str(unit.get("id", ""))
	var section: String = "Unit %s" % unit_id
	var mechanic: String = str(unit.get("mechanic", ""))
	var first_phase: int = 1 << 30
	for key in phase_of:
		if (key as String).begins_with("%s|" % unit_id):
			first_phase = mini(first_phase, int(phase_of[key]))
	_add(lines, KIND_INFO, section, "mechanic %s, title %s, first phase #%d" % [mechanic, unit.get("title", ""), first_phase + 1])
	_add(lines, KIND_INFO, section, "offer condition: %s" % ConditionEvaluator.describe(unit.get("offer_condition")))
	if live:
		var phases: Array[Dictionary] = DeductionEvaluator.dict_array(loop.get("phases", []))
		var index: int = PrototypeContext.count(snapshot.get("phase_index"))
		var current: bool = index >= 0 and index < phases.size() and str(phases[index].get("unit", "")) == unit_id
		var holds: bool = ConditionEvaluator.evaluate(unit.get("offer_condition"))
		var units: Dictionary = snapshot.get("units", {}) if typeof(snapshot.get("units")) == TYPE_DICTIONARY else {}
		if not current:
			_add(lines, KIND_STATE, section, "not offered — its phase is not current (%s)" % ("already opened this run" if units.has(unit_id) else "not reached or already past"))
		elif holds:
			_add(lines, KIND_STATE, section, "OFFERED now — the HUD/Case File show it")
		else:
			var missing: Array[String] = []
			for condition_line in ConditionEvaluator.explain(unit.get("offer_condition")):
				if not condition_line.get("passed", true):
					missing.append(str(condition_line.get("description", "")))
			_add(lines, KIND_STATE, section, "LOCKED — missing: %s" % ", ".join(missing))

	match mechanic:
		CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
			_describe_b(lines, section, unit, case_def, links, base, produced, first_phase)
		CoreLoopUnit.MECHANIC_STATEMENT_CONTRADICTION:
			_describe_a(lines, section, unit, case_def, links)
		_:
			var proto: Dictionary = case_def.get("prototype_c", {})
			_add(lines, KIND_INFO, section, "timeline: %d movable + %d fixed events over %d candidate slots; the final claim is \"%s\", ruled out by %s" % [
				(proto.get("movable_events", []) as Array).size(), (proto.get("fixed_events", []) as Array).size(), (proto.get("time_slots", []) as Array).size(),
				(proto.get("contradiction", {}) as Dictionary).get("claim", ""), (proto.get("contradiction", {}) as Dictionary).get("supporting_constraint_refs", []),
			])
			_add(lines, KIND_INFO, section, "accepted timelines are graded by TimelineEvaluator (any placement satisfying every required constraint) — the simulator exercises the authored solution and an alternate")

	var consequences: Dictionary = unit.get("consequences", {}) if typeof(unit.get("consequences")) == TYPE_DICTIONARY else {}
	var applied: Dictionary = snapshot.get("applied_consequences", {}) if live and typeof(snapshot.get("applied_consequences")) == TYPE_DICTIONARY else {}
	for outcome in consequences:
		var consequence: Dictionary = consequences[outcome] if typeof(consequences[outcome]) == TYPE_DICTIONARY else {}
		var effects: Array[String] = []
		for effect in consequence.get("effects", []):
			effects.append(EffectRunner.describe(effect))
		_add(lines, KIND_INFO, section, 'on %s -> consequence "%s" (summary %s): %s' % [outcome, consequence.get("id", ""), consequence.get("summary", ""), "; ".join(effects) if not effects.is_empty() else "(no effects)"])
		if live:
			var entry: Dictionary = applied.get(str(consequence.get("id", "")), {})
			_add(lines, KIND_STATE, section, ('consequence "%s" APPLIED (resolved by %s, during phase %s)' % [consequence.get("id", ""), entry.get("resolved_by", ""), entry.get("phase", "")]) if not entry.is_empty() else 'consequence "%s" not applied yet' % consequence.get("id", ""))


static func _describe_b(lines: Array[Dictionary], section: String, unit: Dictionary, case_def: Dictionary, links: Dictionary, base: Dictionary, produced: Dictionary, first_phase: int) -> void:
	var round_def: Dictionary = {}
	for proto_round in DeductionEvaluator.dict_array((case_def.get("prototype_b", {}) as Dictionary).get("rounds", [])):
		if str(proto_round.get("id", "")) == str(unit.get("round", "")):
			round_def = proto_round
	_add(lines, KIND_INFO, section, 'prototype_b %s: deduction "%s" (%s, %d slots) — ONE question, committed alone (production B is never the debug batch)' % [unit.get("round", ""), round_def.get("target", ""), round_def.get("relation", ""), int(round_def.get("slot_count", 0))])
	var documented: Array = unit.get("documented_paths", []) if typeof(unit.get("documented_paths")) == TYPE_ARRAY else []
	var reverse: Dictionary = {}
	for inventory_id in links:
		reverse[links[inventory_id]] = inventory_id
	var paths: Array = CoreLoopValidator.accepted_paths(unit, case_def)
	for i in paths.size():
		var inventory: Array[String] = []
		var reachable := true
		for deduction_id in paths[i]:
			var inventory_id: String = str(reverse.get(deduction_id, ""))
			inventory.append(inventory_id if inventory_id != "" else "%s(unlinked)" % deduction_id)
			reachable = reachable and inventory_id != "" and CoreLoopValidator.available_before("evidence:%s" % inventory_id, first_phase, base, produced)
		var is_documented: bool = documented.any(func(path: Variant) -> bool: return typeof(path) == TYPE_ARRAY and CoreLoopValidator.same_set(path, inventory))
		_add(lines, KIND_INFO, section, "accepted proof set %d%s: %s — %s%s" % [
			i + 1, " (the case's primary)" if i == 0 else " (the case's alternate)", inventory, "acquirable before the unit" if reachable else "NOT acquirable before the unit",
			", documented" if is_documented else ", undocumented",
		])
	if paths.size() > 1 and documented.size() < paths.size():
		_add(lines, KIND_INFO, section, "%d of %d accepted proof sets are documented — the simulator derives the rest from proof sets" % [documented.size(), paths.size()])
	if not documented.is_empty():
		_add(lines, KIND_INFO, section, "documented path #1 is the simulator's primary route: %s" % [documented[0]])


static func _describe_a(lines: Array[Dictionary], section: String, unit: Dictionary, case_def: Dictionary, links: Dictionary) -> void:
	var layer: Dictionary = case_def.get("prototype_a", {})
	var pool: Array = layer.get("evidence_pool", [])
	var reverse: Dictionary = {}
	for inventory_id in links:
		reverse[links[inventory_id]] = inventory_id
	for proto_round in DeductionEvaluator.dict_array(layer.get("rounds", [])):
		if not (unit.get("rounds", []) as Array).has(str(proto_round.get("id", ""))):
			continue
		for key in ["required_refutations", "optional_refutations"]:
			for claim_id in DeductionEvaluator.string_array(proto_round.get(key, [])):
				var refuting: Array[String] = []
				for proof_set in DeductionEvaluator.dict_array(DeductionEvaluator.find_claim(case_def, claim_id).get("proof_sets", [])):
					var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
					if str(proof_set.get("relation", "")) == "refutes" and requires.size() == 1 and pool.has(requires[0]):
						refuting.append(str(reverse.get(requires[0], "%s(unlinked)" % requires[0])))
				_add(lines, KIND_INFO, section, '%s %s: "%s" refuted by %s%s' % [
					proto_round.get("id", ""), "REQUIRED" if key == "required_refutations" else "optional (never a producer)", claim_id, refuting,
					"" if key == "required_refutations" else " — exposing it applies no consequence",
				])


static func _section_evidence(lines: Array[Dictionary], links: Dictionary, units: Array, case_def: Dictionary, base: Dictionary, produced: Dictionary) -> void:
	var roles: Dictionary = {}  # deduction evidence id -> role text
	var layer_a: Dictionary = case_def.get("prototype_a", {})
	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		for path in CoreLoopValidator.accepted_paths(unit, case_def):
			for deduction_id in path:
				roles[deduction_id] = "used by an accepted B proof set"
		for proto_round in DeductionEvaluator.dict_array(layer_a.get("rounds", [])):
			if str(unit.get("mechanic", "")) != CoreLoopUnit.MECHANIC_STATEMENT_CONTRADICTION or not (unit.get("rounds", []) as Array).has(str(proto_round.get("id", ""))):
				continue
			for key in ["required_refutations", "optional_refutations"]:
				for claim_id in DeductionEvaluator.string_array(proto_round.get(key, [])):
					for proof_set in DeductionEvaluator.dict_array(DeductionEvaluator.find_claim(case_def, claim_id).get("proof_sets", [])):
						var requires: Array[String] = DeductionEvaluator.string_array(proof_set.get("requires", []))
						if str(proof_set.get("relation", "")) == "refutes" and requires.size() == 1 and not roles.has(requires[0]):
							roles[requires[0]] = "refutes %s A statement" % ("a required" if key == "required_refutations" else "an optional")
	for inventory_id in links:
		var producers: Array[String] = []
		for producer in ContentValidator.find_evidence_producers(str(inventory_id)):
			producers.append(str(producer.get("source", "")))
		var role: String = str(roles.get(links[inventory_id], "distractor (in no accepted answer of any unit)"))
		var kind: String = KIND_INFO if not producers.is_empty() else KIND_WARNING
		_add(lines, kind, "Evidence", '%s -> %s (%s); acquired via: %s' % [inventory_id, links[inventory_id], role, "; ".join(producers) if not producers.is_empty() else "NOTHING grants it"])


static func _section_completion(lines: Array[Dictionary], chapter_id: String, chapter: Dictionary, live: bool) -> void:
	var event_id: String = str(chapter.get("completion_event", ""))
	var event: Dictionary = ContentDB.get_event(event_id)
	_add(lines, KIND_INFO, "Completion", 'completion_event "%s" waits for: %s' % [event_id, ConditionEvaluator.describe(event.get("conditions"))])
	var flags: Dictionary = {}
	var evidence: Dictionary = {}
	var interactions: Dictionary = {}
	ContentValidator._collect_condition_requirements(event.get("conditions"), flags, evidence, interactions)
	for flag in flags:
		var sources: Array[String] = []
		for producer in ContentValidator.find_flag_producers(str(flag)):
			sources.append(str(producer.get("source", "")))
		_add(lines, KIND_INFO, "Completion", 'flag "%s" is produced by: %s' % [flag, "; ".join(sources) if not sources.is_empty() else "NOTHING"])
	for interaction in interactions:
		var sources: Array[String] = []
		for producer in ContentValidator.find_interaction_producers(str(interaction)):
			sources.append(str(producer.get("source", "")))
		_add(lines, KIND_INFO, "Completion", 'interaction "%s" is produced by: %s' % [interaction, "; ".join(sources) if not sources.is_empty() else "NOTHING"])
	if live:
		_add(lines, KIND_STATE, "Completion", "chapter complete (CaseManager): %s" % CaseManager.is_chapter_complete(chapter_id))


static func _section_simulation(lines: Array[Dictionary], simulation: Dictionary) -> void:
	var routes: Array = simulation.get("routes", [])
	if routes.is_empty():
		_add(lines, KIND_INFO, "Simulation", "legal-path simulation not run here (it drives the real GameState and would replace the current run) — run: godot --headless --path . -s res://scenes/test/core_loop_report.gd")
		return
	for route in routes:
		var kind: String = KIND_INFO if route.get("ok", false) else KIND_ERROR
		var summary: String = "OK — %d steps, phases %s" % [route.get("steps", 0), route.get("phases", [])] if route.get("ok", false) else "NO LEGAL ROUTE — %s" % route.get("failure", "")
		_add(lines, kind, "Simulation", "%s: %s" % [route.get("label", ""), summary])
		for unit_id in route.get("units", {}):
			var played: Dictionary = route["units"][unit_id]
			var detail: Variant = played.get("path", played.get("refutations", played.get("timeline", "")))
			_add(lines, KIND_INFO, "Simulation", "  %s (%s): %s" % [unit_id, played.get("mechanic", ""), detail])


# ---------------------------------------------------------------------------

static func _base_producers() -> Dictionary:
	var flags: Dictionary = {}
	var evidence: Dictionary = {}
	var interactions: Dictionary = {}
	ContentValidator._collect_effect_targets_everywhere(flags, evidence, interactions, false)
	return {"flags": flags, "evidence": evidence, "interactions": interactions}


static func _add(lines: Array[Dictionary], kind: String, section: String, text: String) -> void:
	lines.append({"kind": kind, "section": section, "text": text})


static func _result(chapter_id: String, lines: Array[Dictionary]) -> Dictionary:
	var errors := 0
	var warnings := 0
	for line in lines:
		errors += 1 if line["kind"] == KIND_ERROR else 0
		warnings += 1 if line["kind"] == KIND_WARNING else 0
	return {"chapter_id": chapter_id, "errors": errors, "warnings": warnings, "lines": lines}
