extends SceneTree
## Milestone 1.17 — legal-path simulation of every selectable core-loop
## sandbox (see docs/core-loop-authoring.md, "Legal-path simulation", and
## docs/testing.md). Uses CoreLoopRouteSimulator to prove, with the real
## production runtime, that each chapter has a legal route: primary, every
## documented alternate B proof path and an alternate accepted timeline each on
## a FRESH run, the optional innocent lie staying optional, a consequence whose
## effect is already satisfied applying once without duplicating anything, and
## a deliberately broken chapter reporting "no legal route" for the right
## reason. Also proves the simulator only ever used production entry points.
## Not an AI player and not a human playtest. Autoloads, no scene tree — FAST
## and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_simulation_test.gd

const SIMULATOR_PATH := "res://scenes/test/core_loop_route_simulator.gd"

var support: CoreLoopTestSupport
var game_state: Node
var save_manager: Node
var content_db: Node
var case_manager: Node
var _runtimes: Array = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	support = CoreLoopTestSupport.new(self)
	game_state = support.game_state
	save_manager = support.save_manager
	case_manager = support.case_manager
	content_db = get_root().get_node("ContentDB")
	TestHelpers.isolate_save(save_manager, "core_loop_simulation_test")
	TestHelpers.isolate_locale(get_root().get_node("LocaleManager"), "core_loop_simulation_test")

	print("=== Core loop — legal-path simulation ===")
	_test_every_sandbox_has_a_legal_primary_route()
	_test_every_documented_b_path_on_a_fresh_run()
	_test_alternate_timeline_on_a_fresh_run()
	_test_optional_lie_stays_optional()
	_test_already_satisfied_consequence_applies_once()
	_test_simulator_uses_only_production_entry_points()
	_test_broken_chapter_has_no_legal_route()

	for runtime in _runtimes:
		runtime.detach()
	save_manager.delete_save()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _simulate(case_id: String, options: Dictionary = {}) -> Dictionary:
	var runtime: RefCounted = support.new_runtime("sim-%s" % case_id)
	_runtimes.append(runtime)
	var result: Dictionary = CoreLoopRouteSimulator.new(self).run(case_id, runtime, options)
	result["runtime"] = runtime
	return result


func _sandbox_case_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in save_manager.get_sandbox_entries():
		ids.append(str(entry.get("case_id", "")))
	return ids


func _chapter_of(case_id: String) -> Dictionary:
	return content_db.get_chapter(str(content_db.get_case(case_id).get("starting_chapter", "")))


func _b_units(chapter: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for unit in chapter.get("core_loop", {}).get("units", []):
		if unit.get("mechanic", "") == "clue_connection":
			out.append(unit)
	return out


func _sorted(values: Array) -> Array:
	var copy: Array = values.duplicate()
	copy.sort()
	return copy


# ---------------------------------------------------------------------------

func _test_every_sandbox_has_a_legal_primary_route() -> void:
	var case_ids: Array[String] = _sandbox_case_ids()
	_check(case_ids.size() >= 2, "at least two selectable sandboxes exist to simulate: %s" % [case_ids])
	for case_id in case_ids:
		var chapter: Dictionary = _chapter_of(case_id)
		var result: Dictionary = _simulate(case_id)
		_check(result.get("ok", false), "%s: a legal primary route exists — %s" % [case_id, result.get("failure", "")])
		var expected: Array = []
		for phase in chapter.get("core_loop", {}).get("phases", []):
			expected.append(str(phase.get("id", "")))
		expected.append("completed")
		_check(result.get("phases", []) == expected, "%s: every required phase advanced in order: %s" % [case_id, result.get("phases")])
		var runtime: RefCounted = result["runtime"]
		_check(case_manager.is_chapter_complete(str(chapter.get("id", ""))), "%s: CaseManager marked the chapter complete" % case_id)
		_check(runtime.get_findings().size() == expected.size() - 2, "%s: one finding per required phase consequence" % case_id)
		_check(runtime.get_run_help_result() == "independent", "%s: the simulated route used no help" % case_id)
		var unattributed: Array = (result.get("acquisitions", []) as Array).filter(func(entry: Dictionary) -> bool:
			var step: String = str(entry.get("step", ""))
			return not (step.begins_with("examine ") or step.begins_with("talk ") or step.begins_with("command ")))
		_check(unattributed.is_empty() and not (result.get("acquisitions", []) as Array).is_empty(), "%s: every piece of evidence came from an interaction or an applied consequence — none injected: %s" % [case_id, unattributed])
		print("  route %s: %d steps, units %s" % [case_id, (result.get("route", []) as Array).size(), (result.get("units", {}) as Dictionary).keys()])


func _test_every_documented_b_path_on_a_fresh_run() -> void:
	var exercised: int = 0
	for case_id in _sandbox_case_ids():
		for unit in _b_units(_chapter_of(case_id)):
			var paths: Array = unit.get("documented_paths", [])
			for i in range(1, paths.size()):
				exercised += 1
				var result: Dictionary = _simulate(case_id, {"b_paths": {unit["id"]: i}})
				var played: Dictionary = (result.get("units", {}) as Dictionary).get(unit["id"], {})
				_check(result.get("ok", false) and played.get("path", []) == paths[i], "%s/%s: documented alternate path #%d resolves on a fresh run — %s" % [case_id, unit["id"], i + 1, result.get("failure", "")])
				var committed: Array = (result["runtime"] as RefCounted).get_unit(unit["id"]).controller.get_selected_evidence_ids()
				var links: Dictionary = _chapter_of(case_id)["core_loop"]["evidence_links"]
				var expected: Array = (paths[i] as Array).map(func(inventory_id: String) -> String: return str(links[inventory_id]))
				_check(_sorted(committed) == _sorted(expected), "%s/%s: the ALTERNATE clue set is what the evaluator accepted: %s" % [case_id, unit["id"], committed])
	_check(exercised >= 2, "both sandboxes document an alternate B path that got exercised (%d)" % exercised)


func _test_alternate_timeline_on_a_fresh_run() -> void:
	for case_id in _sandbox_case_ids():
		var primary: Dictionary = _simulate(case_id)
		var alternate: Dictionary = _simulate(case_id, {"timeline": "alternate"})
		var primary_tl: Dictionary = {}
		var alternate_tl: Dictionary = {}
		for unit_id in primary.get("units", {}):
			primary_tl = primary["units"][unit_id].get("timeline", primary_tl)
		for unit_id in alternate.get("units", {}):
			alternate_tl = alternate["units"][unit_id].get("timeline", alternate_tl)
		_check(alternate.get("ok", false) and not alternate_tl.is_empty() and alternate_tl != primary_tl, "%s: an alternate timeline the real evaluator accepts completes the chapter too — %s" % [case_id, alternate.get("failure", "")])


func _test_optional_lie_stays_optional() -> void:
	for case_id in _sandbox_case_ids():
		var chapter: Dictionary = _chapter_of(case_id)
		var deduction: Dictionary = content_db.get_deduction_case(str(chapter["core_loop"]["deduction_case"]))
		var has_optional := false
		for unit in chapter["core_loop"]["units"]:
			if unit.get("mechanic", "") != "statement_contradiction":
				continue
			for proto_round in deduction["prototype_a"]["rounds"]:
				if (unit.get("rounds", []) as Array).has(proto_round["id"]) and not (proto_round.get("optional_refutations", []) as Array).is_empty():
					has_optional = true
		if not has_optional:
			continue
		var plain: Dictionary = _simulate(case_id)
		var with_lie: Dictionary = _simulate(case_id, {"optional_lies": true})
		var outcomes: Array = []
		for unit_id in with_lie.get("units", {}):
			for refutation in with_lie["units"][unit_id].get("refutations", []):
				outcomes.append(refutation.get("outcome", ""))
		_check(with_lie.get("ok", false) and outcomes.has("optional"), "%s: the optional innocent lie can be exposed in the confrontation — %s" % [case_id, with_lie.get("failure", "")])
		_check(plain.get("ok", false), "%s: ...and the chapter completes WITHOUT ever exposing it (it is never required)" % case_id)
		var runtime: RefCounted = with_lie["runtime"]
		_check(runtime.get_findings().size() == (plain["runtime"] as RefCounted).get_findings().size(), "%s: exposing the optional lie applies no extra consequence" % case_id)
	var multi_round := false
	for case_id in _sandbox_case_ids():
		for unit in _chapter_of(case_id)["core_loop"]["units"]:
			multi_round = multi_round or (unit.get("mechanic", "") == "statement_contradiction" and (unit.get("rounds", []) as Array).size() > 1)
	_check(multi_round, "at least one sandbox's confrontation spans more than one testimony round")


func _test_already_satisfied_consequence_applies_once() -> void:
	# A consequence that grants evidence the player may already have picked up
	# through optional exploration: find one in the real content, then play it
	# both ways.
	for case_id in _sandbox_case_ids():
		var chapter: Dictionary = _chapter_of(case_id)
		for unit in chapter["core_loop"]["units"]:
			for outcome in unit.get("consequences", {}):
				var consequence: Dictionary = unit["consequences"][outcome]
				for effect in consequence.get("effects", []):
					if effect.get("type", "") != "add_evidence":
						continue
					var evidence_id: String = str(effect.get("evidence_id", ""))
					var early: Dictionary = _simulate(case_id, {"early_evidence": [evidence_id]})
					var late: Dictionary = _simulate(case_id)
					_check(early.get("ok", false) and late.get("ok", false), "%s: both routes around '%s' complete" % [case_id, evidence_id])
					var early_applied: Dictionary = _consequence_event(early["runtime"], str(consequence.get("id", "")))
					var late_applied: Dictionary = _consequence_event(late["runtime"], str(consequence.get("id", "")))
					_check(int(early_applied.get("already_satisfied_effects", -1)) >= 1, "%s: '%s' was already held, so consequence '%s' records an already-satisfied effect: %s" % [case_id, evidence_id, consequence.get("id", ""), early_applied])
					_check(int(late_applied.get("already_satisfied_effects", -1)) == 0, "%s: without the detour the consequence grants '%s' itself" % [case_id, evidence_id])
					var acquired: int = (early["runtime"] as RefCounted).get_recorder().get_events().filter(func(event: Dictionary) -> bool:
						return event.get("type", "") == "evidence_acquired" and event.get("payload", {}).get("evidence_id", "") == evidence_id).size()
					_check(acquired == 1 and game_state.evidence_inventory.count(evidence_id) <= 1, "%s: the already-held '%s' is never granted or observed twice" % [case_id, evidence_id])
					return
	_check(false, "some sandbox consequence grants evidence another interaction can also provide (the idempotent path to exercise)")


func _consequence_event(runtime: RefCounted, consequence_id: String) -> Dictionary:
	for event in runtime.get_recorder().get_events():
		if event.get("type", "") == "consequence_applied" and event.get("payload", {}).get("consequence", "") == consequence_id:
			return event["payload"]
	return {}


func _test_simulator_uses_only_production_entry_points() -> void:
	var result: Dictionary = _simulate(_sandbox_case_ids()[1] if _sandbox_case_ids().size() > 1 else _sandbox_case_ids()[0], {"optional_lies": true, "timeline": "alternate"})
	var allowed: Array = CoreLoopRouteSimulator.ALLOWED_CALLS
	var outside: Array = (result.get("calls", []) as Array).filter(func(call_name: String) -> bool: return not allowed.has(call_name))
	_check(outside.is_empty() and (result.get("calls", []) as Array).has("ChapterRuntime.perform"), "every mutating call is a production entry point: %s" % [outside])
	var source: String = FileAccess.get_file_as_string(SIMULATOR_PATH)
	for forbidden in [
		"force_trigger", "force_complete", "jump_to_chapter", "debug_reset", "reset_case", "add_evidence(", "remove_evidence(", "set_flag(",
		"mark_seen(", "go_to_location(", "load_from_dict(", "set_chapter_run(", "EffectRunner", "DeductionEvaluator.commit", "resolve_claim(",
		"start_case(", "DeductionLab",
	]:
		_check(not source.contains(forbidden), "the simulator never calls a debug/auto-solve or direct-mutation API (%s)" % forbidden)


func _test_broken_chapter_has_no_legal_route() -> void:
	# Negative fixture: cut the only dialogue that grants one piece of the first
	# B unit's documented path. The simulator must fail at THAT phase, for THAT
	# reason — and the static validator must agree.
	var case_id: String = _sandbox_case_ids()[0]
	var chapter: Dictionary = _chapter_of(case_id)
	var first_b: Dictionary = _b_units(chapter)[0]
	var target_evidence: String = str((first_b.get("documented_paths", [[]]) as Array)[0].back())
	var producers: Array = load("res://scripts/core/content_validator.gd").find_evidence_producers(target_evidence)
	_check(producers.size() == 1 and str(producers[0].get("source", "")).begins_with("dialogue"), "fixture sanity: '%s' has exactly one dialogue producer" % target_evidence)
	var dialogue_id: String = str(producers[0]["source"]).get_slice('"', 1)
	var dialogues: Dictionary = content_db.get_all_dialogues()
	var original: Dictionary = (dialogues[dialogue_id] as Dictionary).duplicate(true)
	var broken: Dictionary = original.duplicate(true)
	for node_id in broken["nodes"]:
		(broken["nodes"][node_id] as Dictionary).erase("actions")
	dialogues[dialogue_id] = broken
	var result: Dictionary = _simulate(case_id)
	var validation: Dictionary = load("res://scripts/core/content_validator.gd").validate()
	dialogues[dialogue_id] = original
	_check(not result.get("ok", true) and str(result.get("failure", "")).contains(target_evidence) and str(result.get("failure", "")).contains("investigation_1"), "a chapter whose required evidence has no producer has NO legal route, reported at the right phase: %s" % result.get("failure", ""))
	_check((validation.get("errors", []) as Array).any(func(message: String) -> bool: return message.contains(str(first_b["id"]))), "the static validator reports the same broken unit")
	_check(_simulate(case_id).get("ok", false), "restoring the content restores the legal route")
