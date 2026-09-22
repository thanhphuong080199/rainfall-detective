extends SceneTree
## Milestone 1.17 — TWO core-loop sandboxes through ONE production runtime
## (see docs/core-loop-sandbox.md, "Multiple chapters", and docs/testing.md).
## Proves the architecture is reusable, not just that a second chapter exists:
## no production script names either sandbox; the second chapter's offer
## state follows its own content; switching sandboxes (1 -> 2 and 2 -> 1)
## always starts a genuinely fresh run with nothing leaking (evidence, flags,
## phase, session, hints, failures, help result); units use the active run's
## session only; closing/reopening keeps the current run and only it; one
## chapter's completion never satisfies the other's; the second sandbox
## resumes exactly at eight checkpoints and can still be finished; sandbox 1
## saves stay valid; saves that mix one chapter's run with another case,
## chapter or deduction case are rejected whole; and the save format did not
## change. Autoloads, no scene tree — FAST and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_multi_chapter_test.gd

const SAVE_NAME := "core_loop_multi_chapter_test"
const S := preload("res://scenes/test/core_loop_test_support.gd")

var support: CoreLoopTestSupport
var game_state: Node
var save_manager: Node
var case_manager: Node
var content_db: Node
var investigation: Node
var dialogue_manager: Node
var event_manager: Node
var _runtimes: Array = []
var _fired_events: Array[String] = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	support = CoreLoopTestSupport.new(self)
	game_state = support.game_state
	save_manager = support.save_manager
	case_manager = support.case_manager
	investigation = support.investigation
	dialogue_manager = support.dialogue_manager
	content_db = get_root().get_node("ContentDB")
	event_manager = get_root().get_node("EventManager")
	event_manager.event_triggered.connect(func(event_id: String) -> void: _fired_events.append(event_id))
	TestHelpers.isolate_save(save_manager, SAVE_NAME)
	TestHelpers.isolate_locale(get_root().get_node("LocaleManager"), SAVE_NAME)

	print("=== Core loop — two sandboxes, one runtime ===")
	_test_production_scripts_name_no_sandbox_ids()
	_test_second_sandbox_offer_state_follows_its_content()
	_test_switching_sandboxes_starts_a_fresh_run()
	_test_units_use_only_the_active_runs_session()
	_test_close_and_reopen_preserves_current_run_only()
	_test_completion_never_crosses_chapters()
	_test_second_sandbox_resumes_at_every_boundary()
	_test_first_sandbox_saves_stay_valid()
	_test_mismatched_snapshots_rejected()
	_test_replacing_a_run_with_another_sandbox()
	_test_save_format_unchanged()

	for runtime in _runtimes:
		runtime.detach()
	save_manager.delete_save()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _runtime(prefix: String) -> RefCounted:
	var runtime: RefCounted = support.new_runtime(prefix)
	_runtimes.append(runtime)
	return runtime


func _start(case_id: String, prefix: String) -> RefCounted:
	var runtime: RefCounted = _runtime(prefix)
	save_manager.new_game(case_id)
	runtime.reload_from_game_state()
	return runtime


func _simulator() -> CoreLoopRouteSimulator:
	return CoreLoopRouteSimulator.new(self)


## Plays `runtime`'s run up to (entering) `phase_id` through the simulator.
func _play_to(runtime: RefCounted, phase_id: String, options: Dictionary = {}) -> void:
	var opts: Dictionary = options.duplicate()
	opts["stop_at_phase"] = phase_id
	var result: Dictionary = _simulator().advance(runtime, opts)
	_check(result.get("ok", false) and runtime.get_phase_id() == phase_id, "reached phase %s: %s" % [phase_id, result.get("failure", "")])


func _reload(prefix: String) -> RefCounted:
	save_manager.new_game("case_00_sandbox")
	_check(save_manager.load_game(), "%s: the save loads" % prefix)
	var runtime: RefCounted = _runtime(prefix)
	runtime.reload_from_game_state()
	return runtime


func _durable(runtime: RefCounted) -> Dictionary:
	var snapshot: Dictionary = game_state.chapter_run.duplicate(true)
	snapshot.erase("revision")
	return {
		"chapter": runtime.get_chapter_id(), "phase": runtime.get_phase_id(), "snapshot": snapshot, "flags": game_state.flags.duplicate(),
		"evidence": game_state.evidence_inventory.duplicate(), "seen": game_state.seen_interactions.duplicate(),
		"location": game_state.current_location, "help": runtime.get_run_help_result(),
	}


func _go(location_id: String) -> void:
	if game_state.current_location == location_id:
		return
	if location_id != "sby_cold_store" and game_state.current_location != "sby_cold_store":
		investigation.move_to("sby_cold_store")
	investigation.move_to(location_id)


func _drain() -> void:
	var guard := 0
	while dialogue_manager.is_active and guard < 40:
		dialogue_manager.advance()
		guard += 1


func _examine(location_id: String, point_id: String) -> void:
	_go(location_id)
	investigation.examine(point_id)
	_drain()


func _talk(location_id: String, npc_id: String, topic_id: String) -> void:
	_go(location_id)
	investigation.talk(npc_id, topic_id)
	_drain()


func _reason(runtime: RefCounted, unit_id: String) -> String:
	return str(runtime.get_unit_status(unit_id).get("reason", "")) if runtime.get_unit_status(unit_id).get("available", false) != true else "available"


# ---------------------------------------------------------------------------

## Every id either sandbox's content defines (cases, chapters, units,
## consequences, evidence, locations, characters, dialogue, events, flags,
## interactions, deduction case + its evidence/claims/timeline) must be absent
## from every production script — reusable runtime code is content-agnostic.
func _test_production_scripts_name_no_sandbox_ids() -> void:
	var ids: Dictionary = {}
	var case_ids: Array = []
	for entry in save_manager.get_sandbox_entries():
		case_ids.append(str(entry.get("case_id", "")))
	_check(case_ids.has(S.CASE_ID) and case_ids.has(S.CASE_2), "every selectable sandbox is scanned (a new one is picked up from content): %s" % [case_ids])
	for case_id in case_ids:
		_collect_sandbox_ids(str(case_id), ids)
	var files: Array[String] = []
	_collect_scripts("res://scripts", files)
	var hits: Array[String] = []
	for path in files:
		var source: String = TestHelpers.code_only(FileAccess.get_file_as_string(path))
		for id in ids:
			var pattern := RegEx.new()
			pattern.compile("(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % String(id))
			if pattern.search(source) != null:
				hits.append("%s names %s" % [path, id])
	_check(ids.size() > 150 and files.size() > 40, "scan sanity: %d sandbox ids over %d production scripts" % [ids.size(), files.size()])
	_check(hits.is_empty(), "no production script's CODE names a sandbox/case-specific id: %s" % [hits])
	_check(TestHelpers.code_only("var a := \"e_door_log\"  # e_route_note\n## e_tram_tap") == "var a := \"e_door_log\"  \n", "scan sanity: comments are stripped, string literals are kept")
	print("  id scan: %d sandbox ids x %d scripts under res://scripts — %d hits" % [ids.size(), files.size(), hits.size()])


func _collect_sandbox_ids(case_id: String, ids: Dictionary) -> void:
	var case_data: Dictionary = content_db.get_case(case_id)
	ids[case_id] = true
	for flag in case_data.get("initial_flags", {}):
		ids[flag] = true
	var locations: Array[String] = [str(case_data.get("start_location", ""))]
	var i := 0
	while i < locations.size():
		var location: Dictionary = content_db.get_location(locations[i])
		ids[locations[i]] = true
		for destination in location.get("destinations", []):
			if not locations.has(str(destination.get("location_id", ""))):
				locations.append(str(destination.get("location_id", "")))
		var dialogue_ids: Array[String] = []
		for npc in location.get("npcs", []):
			ids[str(npc.get("id", ""))] = true
			for topic in npc.get("topics", []):
				dialogue_ids.append(str(topic.get("dialogue_id", "")))
			for response in npc.get("present_responses", []):
				dialogue_ids.append(str(response.get("dialogue_id", "")))
		for point in location.get("examine_points", []):
			for variant in point.get("variants", []):
				dialogue_ids.append(str(variant.get("dialogue_id", "")))
		for dialogue_id in dialogue_ids:
			ids[dialogue_id] = true
			for node in content_db.get_dialogue(dialogue_id).get("nodes", {}).values():
				for effect in node.get("actions", []):
					ids[str(effect.get("evidence_id", effect.get("id", effect.get("flag", ""))))] = true
				for choice in node.get("choices", []):
					for effect in choice.get("actions", []):
						ids[str(effect.get("evidence_id", effect.get("id", effect.get("flag", ""))))] = true
		i += 1
	for chapter_id in case_data.get("chapters", []):
		var chapter: Dictionary = content_db.get_chapter(str(chapter_id))
		ids[str(chapter_id)] = true
		ids[str(chapter.get("completion_event", ""))] = true
		var loop: Dictionary = chapter.get("core_loop", {})
		for inventory_id in loop.get("evidence_links", {}):
			ids[inventory_id] = true
			ids[str(loop["evidence_links"][inventory_id])] = true
		for unit in loop.get("units", []):
			ids[str(unit.get("id", ""))] = true
			for outcome in unit.get("consequences", {}):
				ids[str(unit["consequences"][outcome].get("id", ""))] = true
		var deduction: Dictionary = content_db.get_deduction_case(str(loop.get("deduction_case", "")))
		ids[str(deduction.get("id", ""))] = true
		for section in ["evidence", "claims", "suspects"]:
			for entry in deduction.get(section, []):
				ids[str(entry.get("id", ""))] = true
		for entry in deduction.get("timeline", {}).get("events", []) + deduction.get("timeline", {}).get("constraints", []):
			ids[str(entry.get("id", ""))] = true
	ids.erase("")


func _collect_scripts(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		_collect_scripts(dir_path.path_join(sub), out)
	for file_name in dir.get_files():
		if file_name.get_extension() == "gd":
			out.append(dir_path.path_join(file_name))


func _test_second_sandbox_offer_state_follows_its_content() -> void:
	var runtime: RefCounted = _start(S.CASE_2, "offer")
	_check(runtime.is_active() and runtime.get_chapter_id() == S.CHAPTER_2 and runtime.is_briefing(), "the second sandbox starts in its own briefing")
	_check(runtime.open_unit(S.B1_2).get("reason", "") == "unit_not_current", "nothing opens during the briefing")
	runtime.acknowledge_briefing()
	_check(_reason(runtime, S.B1_2) == "unit_locked", "B1 is locked with no evidence")
	_examine("sby_cold_store", "hatch_tabs")
	_check(not game_state.has_evidence("sby_hatch_tabs"), "the retaining tabs stay locked until the hatch itself was examined (examined-gated interaction)")
	_examine("sby_cold_store", "vent_hatch")
	_examine("sby_cold_store", "hatch_tabs")
	_check(_reason(runtime, S.B1_2) == "unit_locked", "B1 stays locked until its LAST piece (the NPC-held diagram) is acquired")
	_talk("sby_workshop", "sby_bruno", "vent_repairs")
	_check(_reason(runtime, S.B1_2) == "available", "B1 is offered once hatch, tabs and diagram are held")
	_check(runtime.open_unit(S.A1_2).get("reason", "") == "unit_not_current" and runtime.perform(S.B2_2, "commit_theory").get("reason", "") == "unit_not_current" \
		and runtime.perform(S.C1_2, "submit_timeline").get("reason", "") == "unit_not_current", "later units refuse commands before their phase")
	support.solve_b(runtime, S.B1_2, S.B1_2_PATH)
	_check(runtime.get_phase_id() == "confrontation" and runtime.get_session().is_supported("ded_hatch_staged"), "B1 resolves the STAGING deduction first (the reverse of sandbox 1's order)")
	_check(_reason(runtime, S.A1_2) == "unit_locked", "A stays locked until Priya is pressed and the sheet is held")
	_talk("sby_cold_store", "sby_priya", "confront")
	_check(_reason(runtime, S.A1_2) == "unit_locked", "pressing Priya alone does not offer A")
	_go("sby_front_office")
	_check(investigation.get_npc("sby_teodor").is_empty(), "Teodor is absent before the confrontation (NPC presence gated by content)")
	_talk("sby_workshop", "sby_bruno", "laundry")
	_check(_reason(runtime, S.A1_2) == "available", "A is offered once both dependencies hold")
	runtime.open_unit(S.A1_2)
	var controller: RefCounted = runtime.get_unit(S.A1_2).controller
	_check(controller.get_round_count() == 2, "the confrontation spans two testimony rounds")
	runtime.perform(S.A1_2, "select_statement", [2])
	runtime.perform(S.A1_2, "select_evidence", ["e_coat_rack_sheet"])
	var first: Dictionary = runtime.perform(S.A1_2, "present_evidence")
	_check(first.get("consequences", []) == [] and runtime.get_phase_id() == "confrontation", "refuting round 1 alone resolves nothing yet")
	runtime.dismiss_feedback(S.A1_2)
	_check(controller.get_round_index() == 1 and controller.get_statement_ids().has("st_bruno_left_early"), "Continue moves to round 2, exposing the optional innocent lie")
	runtime.perform(S.A1_2, "select_statement", [controller.get_statement_ids().find("st_priya_vent_entry")])
	runtime.perform(S.A1_2, "select_evidence", ["e_open_hatch"])
	var second: Dictionary = runtime.perform(S.A1_2, "present_evidence")
	_check(second.get("consequences", []) == ["sby_a1_resolved"] and runtime.get_phase_id() == "investigation_2", "the required contradiction of round 2 resolves A — the optional lie was never needed")
	_check(runtime.get_session().get_claim_status("st_bruno_left_early") == "", "the optional lie stays unresolved")
	runtime.dismiss_feedback(S.A1_2)
	runtime.close_unit()
	_go("sby_front_office")
	_check(not investigation.get_npc("sby_teodor").is_empty() and game_state.has_evidence("sby_shuttle_note"), "A's consequence brings Teodor back and files the shuttle timetable")


func _test_switching_sandboxes_starts_a_fresh_run() -> void:
	for order in [[S.CASE_ID, S.CASE_2], [S.CASE_2, S.CASE_ID]]:
		var first_case: String = order[0]
		var second_case: String = order[1]
		var runtime: RefCounted = _start(first_case, "switch-%s" % first_case)
		_play_to(runtime, "confrontation")
		var a_unit: String = runtime.get_current_unit_id()
		_simulator().prepare_unit(runtime, a_unit)
		runtime.open_unit(a_unit)
		runtime.perform(a_unit, "select_statement", [0])
		var wrong: String = str(runtime.get_unit(a_unit).controller.get_evidence_pool_ids()[0])
		runtime.perform(a_unit, "select_evidence", [wrong])
		runtime.perform(a_unit, "present_evidence")
		var ladder: Array = runtime.get_unit(a_unit).controller.get_statement_ids()
		runtime.perform(a_unit, "reveal_next_hint", [str(ladder[ladder.size() - 1])])
		var old_session: DeductionSession = runtime.get_session()
		var old_run: String = runtime.get_run_id()
		_check(runtime.get_unit(a_unit).get_policy().get_current_unit_failures() == 1 and runtime.get_run_help_result() == "guided" and not old_session.get_resolved_claims().is_empty(), "%s: the outgoing run has resolutions, a hint and a failure to leak" % first_case)
		# New Game into the OTHER sandbox, over the same runtime (as the title screen does).
		save_manager.new_game(second_case)
		_check(runtime.is_active(), "%s -> %s: the runtime follows the replaced state" % [first_case, second_case])
		var chapter_2: String = str(content_db.get_case(second_case).get("starting_chapter", ""))
		_check(runtime.get_chapter_id() == chapter_2 and runtime.is_briefing() and runtime.get_run_id() != old_run, "%s -> %s: a new run of the new chapter, in its briefing" % [first_case, second_case])
		var session: DeductionSession = runtime.get_session()
		var deduction_id: String = str(content_db.get_chapter(chapter_2)["core_loop"]["deduction_case"])
		_check(session != old_session and session.case_id == deduction_id and session.get_resolved_claims().is_empty() and session.get_hint_levels().is_empty() and session.get_opened_evidence_ids().is_empty(), "%s -> %s: a FRESH session for the new deduction case" % [first_case, second_case])
		_check(runtime.get_unit(a_unit) == null and runtime.get_findings().is_empty() and runtime.get_run_help_result() == "independent", "%s -> %s: no unit, failure, hint, consequence or help result carries over" % [first_case, second_case])
		_check(game_state.evidence_inventory.is_empty() and game_state.seen_interactions.is_empty(), "%s -> %s: no evidence or interaction carries over" % [first_case, second_case])
		var initial: Array = (content_db.get_case(second_case).get("initial_flags", {}) as Dictionary).keys()
		_check(game_state.flags.keys().all(func(flag: String) -> bool: return initial.has(flag)) and game_state.flags.values().all(func(value: bool) -> bool: return not value), "%s -> %s: only the new case's own (false) flags exist" % [first_case, second_case])
		_check(str(save_manager.inspect_save().get("state", {}).get("chapter_run", {}).get("chapter_id", "")) == chapter_2, "%s -> %s: the new run's first checkpoint replaced the save" % [first_case, second_case])


func _test_units_use_only_the_active_runs_session() -> void:
	var runtime: RefCounted = _start(S.CASE_2, "session")
	_play_to(runtime, "investigation_2")
	_simulator().prepare_unit(runtime, S.B2_2)
	runtime.open_unit(S.B2_2)
	for unit_id in [S.B1_2, S.A1_2, S.B2_2]:
		_check(runtime.get_unit(unit_id).controller.get_session() == runtime.get_session(), "%s uses the run's own shared session" % unit_id)
	_check(runtime.get_session().is_supported("ded_hatch_staged") and runtime.get_session().get_claim_status("st_priya_vent_entry") == "refuted", "B1's deduction and A's refutations live in that one session")
	_check(runtime.get_unit(S.B2_2).reached_outcomes().is_empty() and not runtime.get_session().is_supported("ded_card_misused"), "resolving B1 never resolved the later B unit")
	var debug_b := PrototypeBController.new()
	debug_b.start(runtime.get_case_def())
	_check(debug_b.get_session() != runtime.get_session() and debug_b.get_session().get_resolved_claims().is_empty(), "a debug prototype over the same case still gets its own fresh session")


func _test_close_and_reopen_preserves_current_run_only() -> void:
	var runtime: RefCounted = _start(S.CASE_2, "reopen")
	_play_to(runtime, "investigation_2")
	_simulator().prepare_unit(runtime, S.B2_2)
	runtime.open_unit(S.B2_2)
	support.fill_b(runtime, S.B2_2, ["e_cold_room_log", "e_shuttle_note"])
	runtime.close_unit()
	runtime.open_unit(S.B2_2)
	var draft: Array = runtime.get_unit(S.B2_2).controller.get_selected_evidence_ids()
	_check(draft.size() == 2 and draft.has("e_cold_room_log") and draft.has("e_shuttle_note"), "closing and reopening keeps the draft: %s" % [draft])
	runtime.close_unit()
	save_manager.new_game(S.CASE_ID)
	runtime.is_active()
	save_manager.new_game(S.CASE_2)
	runtime.is_active()
	_check(runtime.get_unit(S.B2_2) == null and runtime.is_briefing(), "the draft belonged to that run only — a new run of the same sandbox starts clean")


func _test_completion_never_crosses_chapters() -> void:
	_fired_events.clear()
	var first: Dictionary = _simulator().run(S.CASE_ID, _runtime("complete-1"))
	_check(first.get("ok", false) and case_manager.is_chapter_complete(S.CHAPTER_ID), "sandbox 1 completes")
	_check(not case_manager.is_chapter_complete(S.CHAPTER_2) and not _fired_events.has("sby_chapter_01_complete"), "completing sandbox 1 never satisfies sandbox 2's completion event")
	var runtime: RefCounted = _runtime("complete-2")
	var second: Dictionary = _simulator().run(S.CASE_2, runtime)
	_check(second.get("ok", false) and case_manager.is_chapter_complete(S.CHAPTER_2) and not case_manager.is_chapter_complete(S.CHAPTER_ID), "sandbox 2 completes in its own run, with no trace of sandbox 1's completion")
	var applied: Array = runtime.get_recorder().get_events().filter(func(event: Dictionary) -> bool: return event.get("type", "") == "consequence_applied" and event.get("payload", {}).get("run_id", "") == runtime.get_run_id())
	var ids: Dictionary = {}
	for event in applied:
		ids[event["payload"]["consequence"]] = true
	_check(applied.size() == 5 and ids.size() == 5, "each of sandbox 2's five consequences applied exactly once (%d events)" % applied.size())
	_check(_fired_events.count("sby_chapter_01_complete") == 1, "sandbox 2's completion event fired exactly once")


func _test_second_sandbox_resumes_at_every_boundary() -> void:
	var boundaries: Array[String] = ["investigation", "b_draft", "after_b", "inside_a", "after_a", "inside_c", "before_claim", "completed"]
	for boundary in boundaries:
		var runtime: RefCounted = _start(S.CASE_2, "resume-%s" % boundary)
		_drive_second_sandbox_to(runtime, boundary)
		runtime.flush()
		var before: Dictionary = _durable(runtime)
		_fired_events.clear()
		var resumed: RefCounted = _reload("resume-%s-loaded" % boundary)
		var after: Dictionary = _durable(resumed)
		for key in before:
			_check(after[key] == before[key], "%s: %s survives save/load exactly (%s vs %s)" % [boundary, key, before[key], after[key]])
		var types: Array[String] = support.event_types(resumed)
		_check(types.has("chapter_resumed") and not types.has("consequence_applied") and not types.has("evidence_acquired") and not _fired_events.has("sby_chapter_01_complete"), "%s: restoring replays nothing: %s" % [boundary, types])
		_check_boundary_detail(resumed, boundary)
		var again: RefCounted = _reload("resume-%s-again" % boundary)
		_check(_durable(again) == after, "%s: a second load is identical — nothing reapplied" % boundary)
		var finish: Dictionary = _simulator().advance(again)
		_check(finish.get("ok", false) and again.is_completed(), "%s: the resumed run can still be finished — %s" % [boundary, finish.get("failure", "")])
		_check((game_state.chapter_run.get("applied_consequences", {}) as Dictionary).size() == 5, "%s: finishing after a resume applies every consequence exactly once" % boundary)


func _drive_second_sandbox_to(runtime: RefCounted, boundary: String) -> void:
	match boundary:
		"investigation":
			_play_to(runtime, "investigation_1")
			_examine("sby_cold_store", "vent_hatch")
		"b_draft":
			_play_to(runtime, "investigation_1")
			_simulator().prepare_unit(runtime, S.B1_2)
			runtime.open_unit(S.B1_2)
			support.fill_b(runtime, S.B1_2, S.B1_2_PATH.slice(0, 2))
			runtime.close_unit()
		"after_b":
			_play_to(runtime, "confrontation")
		"inside_a":
			_play_to(runtime, "confrontation")
			_simulator().prepare_unit(runtime, S.A1_2)
			runtime.open_unit(S.A1_2)
			runtime.perform(S.A1_2, "select_statement", [2])
			runtime.perform(S.A1_2, "select_evidence", ["e_coat_rack_sheet"])
			runtime.perform(S.A1_2, "present_evidence")
			runtime.dismiss_feedback(S.A1_2)
			runtime.perform(S.A1_2, "select_statement", [1])
			runtime.perform(S.A1_2, "select_evidence", ["e_open_hatch"])
			runtime.close_unit()
		"after_a":
			_play_to(runtime, "investigation_2")
		"inside_c":
			_play_to(runtime, "timeline")
			runtime.open_unit(S.C1_2)
			runtime.perform(S.C1_2, "place_event", ["tl_teodor_leaves", "20:40"])
			runtime.perform(S.C1_2, "place_event", ["tl_hatch_forced", "21:14"])
			runtime.close_unit()
		"before_claim":
			_play_to(runtime, "final_claim")
		"completed":
			_check(_simulator().advance(runtime).get("ok", false), "completed: the run finishes")


func _check_boundary_detail(runtime: RefCounted, boundary: String) -> void:
	_check(runtime.get_chapter_id() == S.CHAPTER_2 and not runtime.has_error(), "%s: Continue restores the SECOND sandbox (%s)" % [boundary, runtime.get_error()])
	match boundary:
		"b_draft":
			var draft: Array = runtime.get_unit(S.B1_2).controller.get_selected_evidence_ids()
			_check(draft.size() == 2 and draft.has(S.B1_2_PATH[0]) and draft.has(S.B1_2_PATH[1]), "b_draft: the partial clue set is back: %s" % [draft])
		"inside_a":
			var controller: RefCounted = runtime.get_unit(S.A1_2).controller
			_check(controller.get_round_index() == 1 and controller.get_current_statement_id() == "st_priya_vent_entry" and controller.get_selected_evidence_id() == "e_open_hatch", "inside_a: round 2 with its selected statement and evidence is back")
			_check(runtime.get_session().get_claim_status("st_priya_never_borrowed") == "refuted" and runtime.get_phase_id() == "confrontation", "inside_a: round 1's refutation is kept without resolving the unit")
		"inside_c":
			var controller: RefCounted = runtime.get_unit(S.C1_2).controller
			_check(controller.get_placement("tl_teodor_leaves") == "20:40" and controller.get_placement("tl_hatch_forced") == "21:14" and controller.get_placement("tl_bin_out") == "", "inside_c: the partial placements are back")
		"before_claim":
			var controller: RefCounted = runtime.get_unit(S.C1_2).controller
			_check(runtime.get_phase_id() == "final_claim" and controller.is_accepted() and controller.is_claim_phase(), "before_claim: the accepted timeline is locked in and the final claim is next")
		"completed":
			_check(runtime.is_completed() and runtime.perform(S.C1_2, "submit_claim").get("reason", "") == "chapter_completed", "completed: reopens completed and refuses resubmission")


func _test_first_sandbox_saves_stay_valid() -> void:
	for stop in ["b1", "claim"]:
		var runtime: RefCounted = _runtime("sbx-%s" % stop)
		support.play_until(runtime, stop)
		runtime.flush()
		var before: Dictionary = _durable(runtime)
		var resumed: RefCounted = _reload("sbx-%s-loaded" % stop)
		_check(_durable(resumed) == before and resumed.get_chapter_id() == S.CHAPTER_ID, "sandbox 1 (%s): its saves still load exactly, into sandbox 1" % stop)


func _test_mismatched_snapshots_rejected() -> void:
	var runtime: RefCounted = _start(S.CASE_2, "mismatch")
	_play_to(runtime, "confrontation")
	runtime.flush()
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_manager.save_path))
	var mutations: Dictionary = {
		"the save's case does not own the run's chapter": func(state: Dictionary) -> void: state["variables"]["case_id"] = S.CASE_ID,
		"the run claims another chapter": func(state: Dictionary) -> void: state["chapter_run"]["chapter_id"] = S.CHAPTER_ID,
		"another case and chapter around this chapter's run": func(state: Dictionary) -> void: state["variables"]["case_id"] = S.CASE_ID; state["variables"]["current_chapter"] = S.CHAPTER_ID,
		"the run claims another deduction case": func(state: Dictionary) -> void: state["chapter_run"]["deduction_case"] = "proto_x_archive_ledger",
		"a unit snapshot grafted from the other sandbox": func(state: Dictionary) -> void: state["chapter_run"]["units"][S.B1] = state["chapter_run"]["units"][S.B1_2],
	}
	for label in mutations:
		var payload: Dictionary = valid.duplicate(true)
		(mutations[label] as Callable).call(payload["state"])
		_write_save(payload)
		var before: Dictionary = game_state.get_save_dict().duplicate(true)
		_check(save_manager.inspect_save().get("reason", "") == "invalid_chapter_run" and not save_manager.has_resumable_save(), "%s: rejected as a whole" % label)
		_check(not save_manager.load_game() and game_state.get_save_dict() == before, "%s: never partially loaded" % label)
	_write_save(valid)
	_check(save_manager.has_resumable_save(), "the unmodified save is still valid (the mutations above are what broke it)")


func _test_replacing_a_run_with_another_sandbox() -> void:
	var runtime: RefCounted = _start(S.CASE_2, "replace")
	_play_to(runtime, "confrontation")
	runtime.flush()
	_check(save_manager.get_saved_case_id() == S.CASE_2, "the save belongs to the second sandbox")
	save_manager.new_game(S.CASE_ID)
	runtime.is_active()
	var saved: Dictionary = save_manager.inspect_save()
	_check(saved.get("ok", false) and save_manager.get_saved_case_id() == S.CASE_ID and str(saved["state"]["chapter_run"]["phase_id"]) == "briefing", "starting the other sandbox writes a clean replacement run, never a merge")


func _test_save_format_unchanged() -> void:
	_check(load("res://scripts/save/save_manager.gd").SAVE_VERSION == 2 and load("res://scripts/core_loop/chapter_runtime.gd").SNAPSHOT_FORMAT == 1, "no save/snapshot version bump — the persisted contract did not change")
	var runtime: RefCounted = _start(S.CASE_2, "keys")
	var keys: Array = game_state.chapter_run.keys()
	keys.sort()
	_check(keys == ["applied_consequences", "case_file", "chapter_id", "completed", "deduction_case", "format", "open_unit", "phase_id", "phase_index", "revision", "run_help_result", "run_id", "session", "units"], "the chapter-run snapshot has exactly the 1.16 fields: %s" % [keys])
	_check(runtime.is_active(), "sanity")


func _write_save(payload: Dictionary) -> void:
	var file := FileAccess.open(save_manager.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
