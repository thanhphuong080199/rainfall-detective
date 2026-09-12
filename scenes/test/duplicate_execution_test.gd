extends SceneTree
## Regression coverage for accidental duplicate execution (Milestone 1.7,
## section 15) — the specific failure class this project's condition/effect
## reuse makes possible: an event, a chapter completion, or a case completion
## firing its effects more than once because something re-evaluates state
## after it already fired. Each check drives real GameState/EventManager/
## CaseManager primitives directly rather than full dialogue, per
## docs/godot-testing's "small deterministic setup" shape. Run with:
##   godot --headless --path . -s res://scenes/test/duplicate_execution_test.gd
##
## Manually forcing an event twice via EventManager.force_trigger() is NOT
## tested here as a "bug" — force_trigger is a documented developer bypass
## (see docs/event-system.md, "Developer tools") that deliberately skips
## trigger_policy, so calling it twice deliberately double-firing is that
## tool working as designed, not a regression in normal/automatic
## progression. What's tested below is real automatic progression:
## reevaluation, chapter transitions, and case completion.

var game_state: Node
var event_manager: Node
var case_manager: Node
var _fired_events: Array[String] = []
var _activated_chapters: Array[String] = []
var _completed_chapters: Array[String] = []
var _completed_cases: Array[String] = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	game_state = get_root().get_node("GameState")
	event_manager = get_root().get_node("EventManager")
	case_manager = get_root().get_node("CaseManager")
	await process_frame

	event_manager.event_triggered.connect(func(id): _fired_events.append(id))
	case_manager.chapter_activated.connect(func(id): _activated_chapters.append(id))
	case_manager.chapter_completed.connect(func(id): _completed_chapters.append(id))
	case_manager.case_completed.connect(func(id): _completed_cases.append(id))

	print("=== Duplicate-execution regression tests ===")
	_test_event_does_not_refire_under_repeated_reevaluation()
	_test_chapter_completion_fires_exactly_once()
	_test_case_completion_fires_exactly_once()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _test_event_does_not_refire_under_repeated_reevaluation() -> void:
	_fired_events.clear()
	game_state.start_new_game("case_00_sandbox")
	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.set_flag("hallway_unlocked", true)
	game_state.add_evidence("test_key")
	_check(_fired_events.count("character_a_moves_to_hallway") == 1, "the event should have fired exactly once on real trigger")

	for i in 10:
		game_state.set_flag("dup_exec_probe", i % 2 == 0)

	_check(
		_fired_events.count("character_a_moves_to_hallway") == 1,
		"ten additional unrelated reevaluation passes must not push a 'once' event's fire count past 1"
	)


## Completes test_case_chapter_01 via direct GameState pokes (the same
## primitives the real dialogue/effects would have produced), then provokes
## extra reevaluation passes to prove the completion — and the chapter_02
## activation it causes — each happened exactly once.
func _test_chapter_completion_fires_exactly_once() -> void:
	_completed_chapters.clear()
	_activated_chapters.clear()
	case_manager.start_case("test_case")
	game_state.set_flag("character_a_moved", true)
	game_state.go_to_location("test_hallway")
	game_state.mark_seen("custom:talked_to_character_a_in_hallway")

	_check(case_manager.is_chapter_complete("test_case_chapter_01"), "chapter_01 should have completed once its real completion_event fired")
	_check(_completed_chapters.count("test_case_chapter_01") == 1, "chapter_completed should have fired exactly once for chapter_01")
	_check(_activated_chapters.count("test_case_chapter_02") == 1, "chapter_activated should have fired exactly once for chapter_02")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_02", "chapter_02 should now be current")

	# Redundant reevaluation: re-affirm the same already-true conditions and
	# poke unrelated state — none of this may re-complete chapter_01 or
	# re-activate chapter_02.
	game_state.set_flag("character_a_moved", true)
	game_state.go_to_location("test_room")
	game_state.go_to_location("test_hallway")
	game_state.set_flag("dup_exec_probe_b", true)

	_check(_completed_chapters.count("test_case_chapter_01") == 1, "further reevaluation must not re-complete chapter_01")
	_check(_activated_chapters.count("test_case_chapter_02") == 1, "further reevaluation must not re-activate chapter_02")
	_check(game_state.get_flag("test_case_chapter_02_active"), "chapter_02's entry_effects should still show as having run")


func _test_case_completion_fires_exactly_once() -> void:
	_completed_cases.clear()
	_completed_chapters.clear()
	case_manager.start_case("test_case")
	# Drive straight to chapter_02 (its own entry_effects already set
	# test_case_chapter_02_active), then satisfy its own completion condition.
	game_state.set_flag("character_a_moved", true)
	game_state.go_to_location("test_hallway")
	game_state.mark_seen("custom:talked_to_character_a_in_hallway")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_02", "setup should have reached chapter_02")

	game_state.mark_seen("custom:chapter_02_debrief_done")
	_check(case_manager.is_case_complete("test_case"), "the case should complete once chapter_02's completion_event fires")
	_check(_completed_cases.count("test_case") == 1, "case_completed should have fired exactly once")

	# Redundant reevaluation after full completion must not re-fire anything.
	game_state.mark_seen("custom:chapter_02_debrief_done")  # already seen; a genuine no-op
	game_state.set_flag("dup_exec_probe_c", true)
	game_state.set_flag("dup_exec_probe_c", false)

	_check(_completed_cases.count("test_case") == 1, "further reevaluation after full completion must not re-fire case_completed")
	_check(_completed_chapters.count("test_case_chapter_02") == 1, "further reevaluation must not re-fire chapter_completed for chapter_02")
