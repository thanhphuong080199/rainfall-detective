extends SceneTree
## Negative-path regression coverage (Milestone 1.7, section 18): the paths
## where a bug could let a player skip required progression. Each check
## starts from a fresh case and pokes only the minimum state needed, per
## docs/godot-testing's "small deterministic setup" shape. Run with:
##   godot --headless --path . -s res://scenes/test/negative_progression_test.gd

var game_state: Node
var investigation: Node
var dialogue_manager: Node
var event_manager: Node
var case_manager: Node
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	game_state = get_root().get_node("GameState")
	investigation = get_root().get_node("Investigation")
	dialogue_manager = get_root().get_node("DialogueManager")
	event_manager = get_root().get_node("EventManager")
	case_manager = get_root().get_node("CaseManager")
	await process_frame

	print("=== Negative progression tests ===")
	_test_event_does_not_trigger_without_required_evidence()
	_test_event_does_not_fire_before_hallway_is_unlocked()
	_test_chapter_remains_active_with_partial_completion_conditions()
	_test_destination_remains_locked_before_requirements_satisfied()
	_test_wrong_evidence_presented_does_not_unlock_hallway()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _drain_dialogue() -> void:
	var guard := 0
	while dialogue_manager.is_active and guard < 20:
		dialogue_manager.advance()
		guard += 1
	_check(guard < 20, "dialogue should terminate within a bounded number of steps")


func _test_event_does_not_trigger_without_required_evidence() -> void:
	game_state.start_new_game("case_00_sandbox")
	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.set_flag("hallway_unlocked", true)
	_check(
		not event_manager.is_event_triggered("character_a_moves_to_hallway"),
		"without test_key, character_a_moves_to_hallway must not trigger even though its other conditions are met"
	)
	game_state.add_evidence("test_key")
	_check(
		event_manager.is_event_triggered("character_a_moves_to_hallway"),
		"sanity: the event should trigger once the missing evidence is actually granted"
	)


## Regression for a real soft-lock a developer found via the Case Debugger
## (Milestone 1.8): talking about "about_moving" (marks
## character_a_ready_to_move) and examining the desk (grants test_key) are
## BOTH reachable from the very start, with no dependency on
## hallway_unlocked. Before data/events/test_events.json added a third
## `hallway_unlocked` requirement to character_a_moves_to_hallway, a player
## who did those two things — in either order — without ever presenting the
## key would have character_a leave test_room immediately: the key could
## then never be presented (character_a is no longer there), hallway_unlocked
## would never be set, and test_hallway (where character_a now stands) would
## stay locked forever. See docs/case-debugger.md's discovery note.
func _test_event_does_not_fire_before_hallway_is_unlocked() -> void:
	game_state.start_new_game("case_00_sandbox")
	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.add_evidence("test_key")
	_check(
		not event_manager.is_event_triggered("character_a_moves_to_hallway"),
		"talking about moving and holding the key, in any order, must not move character_a away before hallway_unlocked is set"
	)
	_check(not investigation.get_npc("character_a").is_empty(), "character_a must still be present in test_room so the key can still be presented")

	investigation.present("test_key", "character_a")
	_drain_dialogue()
	_check(game_state.get_flag("hallway_unlocked"), "presenting the key should still be possible, and should unlock the hallway")
	_check(event_manager.is_event_triggered("character_a_moves_to_hallway"), "once hallway_unlocked is also set, the event should now fire")


func _test_chapter_remains_active_with_partial_completion_conditions() -> void:
	case_manager.start_case("test_case")
	# test_case_chapter_01_complete requires all three of: character_a_moved,
	# visited_location:test_hallway, interaction_complete:talked_to_character_a_in_hallway.
	# Satisfy only the first two.
	game_state.set_flag("character_a_moved", true)
	game_state.go_to_location("test_hallway")
	_check(
		not case_manager.is_chapter_complete("test_case_chapter_01"),
		"chapter_01 must remain active while only 2 of its 3 completion conditions are satisfied"
	)
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_01", "chapter_01 should still be current")

	game_state.mark_seen("custom:talked_to_character_a_in_hallway")
	_check(case_manager.is_chapter_complete("test_case_chapter_01"), "chapter_01 should complete once the final condition is also satisfied")


func _test_destination_remains_locked_before_requirements_satisfied() -> void:
	game_state.start_new_game("case_00_sandbox")
	var destination_ids := func() -> Array:
		var ids: Array = []
		for destination in investigation.get_available_destinations():
			ids.append(destination.get("location_id"))
		return ids

	_check(not destination_ids.call().has("test_hallway"), "test_hallway must not be an available destination before hallway_unlocked is set")
	investigation.move_to("test_hallway")
	_check(game_state.current_location == "test_room", "move_to a locked destination must not change location")

	game_state.set_flag("hallway_unlocked", true)
	_check(destination_ids.call().has("test_hallway"), "test_hallway should become available once hallway_unlocked is set")
	investigation.move_to("test_hallway")
	_check(game_state.current_location == "test_hallway", "move_to should succeed once the destination is actually available")


## Presenting evidence that doesn't match a specific present_response must
## fall through to the generic response only, and must not fire the
## key-specific dialogue's own hallway_unlocked action.
func _test_wrong_evidence_presented_does_not_unlock_hallway() -> void:
	game_state.start_new_game("case_00_sandbox")
	game_state.add_evidence("test_note")
	game_state.add_evidence("test_key")

	investigation.present("test_note", "character_a")
	_drain_dialogue()
	_check(not game_state.get_flag("hallway_unlocked"), "presenting unrelated evidence (test_note) must not unlock the hallway")

	investigation.present("test_key", "character_a")
	_drain_dialogue()
	_check(game_state.get_flag("hallway_unlocked"), "presenting the correct evidence (test_key) should unlock the hallway")
