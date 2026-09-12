extends SceneTree
## Save/load regression suite (Milestone 1.7, section 16) — isolated from the
## narrative walkthrough in smoke_test.gd (which already covers a save/load
## round trip as one step of a longer flow). Uses its own throwaway user://
## save file (see TestHelpers.isolate_save) and drives state via direct
## GameState/EventManager/CaseManager primitives rather than full dialogue,
## per docs/godot-testing's "small deterministic setup" shape. Run with:
##   godot --headless --path . -s res://scenes/test/save_load_regression_test.gd

var game_state: Node
var save_manager: Node
var event_manager: Node
var case_manager: Node
var _fired_events: Array[String] = []
var _activated_chapters: Array[String] = []
var _completed_chapters: Array[String] = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	game_state = get_root().get_node("GameState")
	save_manager = get_root().get_node("SaveManager")
	event_manager = get_root().get_node("EventManager")
	case_manager = get_root().get_node("CaseManager")
	await process_frame

	TestHelpers.isolate_save(save_manager, "save_load_regression_test")
	event_manager.event_triggered.connect(func(id): _fired_events.append(id))
	case_manager.chapter_activated.connect(func(id): _activated_chapters.append(id))
	case_manager.chapter_completed.connect(func(id): _completed_chapters.append(id))

	print("=== Save/Load regression tests ===")
	_test_exact_state_round_trip()
	_test_triggered_event_survives_load_without_refiring()
	_test_chapter_transition_survives_load_without_rerunning_effects()

	save_manager.delete_save()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


## Everything GameState.get_save_dict() persists (see docs/architecture.md's
## "Save/load: what actually round-trips"): location, visited locations,
## evidence, flags, variables (case/chapter id), and seen_interactions
## (topic/examine "seen" state included).
func _test_exact_state_round_trip() -> void:
	case_manager.start_case("test_case")
	game_state.add_evidence("test_key")
	game_state.add_evidence("test_badge")
	game_state.set_flag("hallway_unlocked", true)
	game_state.go_to_location("test_hallway")
	game_state.mark_seen("topic:character_a:greeting")
	game_state.mark_seen("examine:test_hallway:mirror")

	var expected_location: String = game_state.current_location
	var expected_visited: Array = game_state.visited_locations.duplicate()
	var expected_evidence: Array = game_state.evidence_inventory.duplicate()
	var expected_flags: Dictionary = game_state.flags.duplicate()
	var expected_seen: Array = game_state.seen_interactions.duplicate()
	var expected_chapter: String = case_manager.get_current_chapter_id()

	_check(save_manager.save_game(), "save_game should succeed")

	# Mutate/reset runtime state completely before loading, so a successful
	# restore can only be explained by the save file, not leftover memory.
	case_manager.start_case("case_00_sandbox")
	_check(case_manager.get_current_chapter_id() == "", "sanity: case_00_sandbox should have no current chapter before load")

	_check(save_manager.load_game(), "load_game should succeed")
	_check(game_state.current_location == expected_location, "loaded current_location should match what was saved")
	_check(game_state.visited_locations == expected_visited, "loaded visited_locations should match what was saved")
	_check(game_state.evidence_inventory == expected_evidence, "loaded evidence_inventory should match what was saved")
	for flag_name in expected_flags:
		_check(game_state.get_flag(flag_name) == expected_flags[flag_name], "loaded flag '%s' should match its saved value" % flag_name)
	_check(game_state.seen_interactions.size() == expected_seen.size(), "loaded seen_interactions should have the same size as what was saved")
	for seen_key in expected_seen:
		_check(game_state.has_seen(seen_key), "loaded seen_interactions should still include '%s'" % seen_key)
	_check(case_manager.get_current_chapter_id() == expected_chapter, "loaded current_chapter should match what was saved")
	_check(case_manager.get_current_case_id() == "test_case", "loaded case_id should match what was saved")


## Section 12/16: a "once" event that already triggered before save/load must
## not fire again just because loading re-evaluates every event against the
## restored (still-satisfying) state.
func _test_triggered_event_survives_load_without_refiring() -> void:
	game_state.start_new_game("case_00_sandbox")
	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.set_flag("hallway_unlocked", true)
	game_state.add_evidence("test_key")
	_check(event_manager.is_event_triggered("character_a_moves_to_hallway"), "sanity: the event should be triggered before saving")
	var fires_before_save: int = _fired_events.count("character_a_moves_to_hallway")

	_check(save_manager.save_game(), "save_game should succeed")
	game_state.start_new_game("test_case")  # discard in-memory state entirely
	_check(save_manager.load_game(), "load_game should succeed")

	_check(event_manager.is_event_triggered("character_a_moves_to_hallway"), "the triggered event's state should survive save/reset/load")
	_check(game_state.get_flag("character_a_moved"), "the event's own effect (character_a_moved) should survive save/reset/load")
	_check(
		_fired_events.count("character_a_moves_to_hallway") == fires_before_save,
		"loading a save whose condition is still satisfied must not refire an already-triggered 'once' event"
	)


## Section 15/16: loading a save that landed mid-chapter-2 must restore
## current_chapter directly, without re-running chapter_02's entry_effects or
## re-firing chapter_01's completion — see docs/case-system.md, "Case/Chapter
## runtime state" ("no entry_effects re-run" on load).
func _test_chapter_transition_survives_load_without_rerunning_effects() -> void:
	case_manager.start_case("test_case")
	game_state.set_flag("character_a_moved", true)
	game_state.go_to_location("test_hallway")
	game_state.mark_seen("custom:talked_to_character_a_in_hallway")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_02", "setup should have reached chapter_02 before saving")

	var chapter_02_activations_before: int = _activated_chapters.count("test_case_chapter_02")
	var chapter_01_completions_before: int = _completed_chapters.count("test_case_chapter_01")

	_check(save_manager.save_game(), "mid-chapter-2 save should succeed")
	case_manager.start_case("case_00_sandbox")
	_check(save_manager.load_game(), "mid-chapter-2 load should succeed")

	_check(case_manager.get_current_chapter_id() == "test_case_chapter_02", "loading should restore chapter_02 as current")
	_check(case_manager.is_chapter_complete("test_case_chapter_01"), "loading should not un-complete chapter_01")
	_check(game_state.get_flag("test_case_chapter_02_active"), "loading should restore chapter_02's scope flag from the saved flags, not by rerunning entry_effects")
	_check(
		_activated_chapters.count("test_case_chapter_02") == chapter_02_activations_before,
		"loading a save must not re-emit chapter_activated for the chapter it restores"
	)
	_check(
		_completed_chapters.count("test_case_chapter_01") == chapter_01_completions_before,
		"loading a save must not re-emit chapter_completed for an already-completed chapter"
	)
