extends SceneTree
## Focused, independent tests for EventManager, using the real shared events
## in data/events/test_events.json but driven by direct GameState pokes
## instead of full dialogue playback — small deterministic setups, per
## docs/godot-testing. Complements (does not replace) smoke_test.gd's
## _test_event_system(), which proves the same system fires correctly off
## state real gameplay actions build up. Run with:
##   godot --headless --path . -s res://scenes/test/events_test.gd
##
## Each _test_* function starts from a fresh case so these checks are order-
## independent (see docs/godot-testing's "Test independence").

var game_state: Node
var event_manager: Node
var investigation: Node
var case_manager: Node
var _fired_events: Array[String] = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	game_state = get_root().get_node("GameState")
	event_manager = get_root().get_node("EventManager")
	investigation = get_root().get_node("Investigation")
	case_manager = get_root().get_node("CaseManager")
	await process_frame

	event_manager.event_triggered.connect(func(event_id): _fired_events.append(event_id))

	print("=== EventManager — focused tests ===")
	_test_conditions_false_no_trigger()
	_test_conditions_become_true_triggers()
	_test_once_fires_exactly_once_under_reevaluation()
	_test_event_chain_fires_in_one_pass()
	_test_chapter_scoped_content_does_not_leak_into_unrelated_case()
	_test_debug_reset_trigger()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


## Section 18's literal example, at the Event layer: without the required
## evidence, the event must not trigger even once its other condition is met.
func _test_conditions_false_no_trigger() -> void:
	_fired_events.clear()
	game_state.start_new_game("case_00_sandbox")
	_check(not event_manager.is_event_triggered("character_a_moves_to_hallway"), "should start untriggered")

	game_state.mark_seen("custom:character_a_ready_to_move")
	_check(
		not event_manager.is_event_triggered("character_a_moves_to_hallway"),
		"character_a_moves_to_hallway must not trigger while it's still missing has_evidence:test_key"
	)


func _test_conditions_become_true_triggers() -> void:
	_fired_events.clear()
	game_state.start_new_game("case_00_sandbox")
	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.set_flag("hallway_unlocked", true)
	game_state.add_evidence("test_key")
	_check(
		event_manager.is_event_triggered("character_a_moves_to_hallway"),
		"character_a_moves_to_hallway should trigger the moment its last missing condition becomes true"
	)
	_check(game_state.get_flag("character_a_moved"), "the event's own effect should have run")


func _test_once_fires_exactly_once_under_reevaluation() -> void:
	_fired_events.clear()
	game_state.start_new_game("case_00_sandbox")
	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.set_flag("hallway_unlocked", true)
	game_state.add_evidence("test_key")
	var fires_after_trigger: int = _fired_events.count("character_a_moves_to_hallway")
	_check(fires_after_trigger == 1, "the event should have fired exactly once so far")

	# Provoke several more evaluation passes via unrelated state changes,
	# with the event's own conditions still fully satisfied throughout.
	game_state.set_flag("events_test_probe_a", true)
	game_state.go_to_location("test_hallway")
	game_state.go_to_location("test_room")
	game_state.set_flag("events_test_probe_a", false)

	_check(
		_fired_events.count("character_a_moves_to_hallway") == fires_after_trigger,
		"a 'once' event must not refire across any number of unrelated reevaluation passes"
	)


## Section 13: a representative, isolated event-chain regression — one
## event's effect (character_a_moved) is the exact condition another event
## (mirror_note_ready) needs, and both must resolve in the SAME evaluation
## pass, from one state change, with no further action in between.
func _test_event_chain_fires_in_one_pass() -> void:
	_fired_events.clear()
	game_state.start_new_game("case_00_sandbox")
	_check(not event_manager.is_event_triggered("mirror_note_ready"), "mirror_note_ready should start untriggered")

	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.set_flag("hallway_unlocked", true)
	game_state.add_evidence("test_key")  # the single state change that satisfies BOTH events in the chain

	_check(event_manager.is_event_triggered("character_a_moves_to_hallway"), "the chain's first event should have fired")
	_check(event_manager.is_event_triggered("mirror_note_ready"), "the chain's second event should have fired in the same pass, with no further player action")
	_check(_fired_events.count("character_a_moves_to_hallway") == 1, "the chain must not have fired the first event more than once")
	_check(_fired_events.count("mirror_note_ready") == 1, "the chain must not have fired the second event more than once")


## Section 12: a chapter-scoped topic must stay unreachable outside the case/
## chapter that scopes it (data/locations/test_hallway.json's
## chapter_02_debrief topic requires test_case_chapter_02_active — see
## docs/case-system.md, "Event/content scope"). Runs the flat sandbox case
## through equivalent state (character_a moved, hallway visited) to prove
## the scope flag — not incidental state — is what's actually gating it.
func _test_chapter_scoped_content_does_not_leak_into_unrelated_case() -> void:
	case_manager.start_case("case_00_sandbox")
	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.add_evidence("test_key")
	game_state.go_to_location("test_hallway")
	game_state.mark_seen("custom:talked_to_character_a_in_hallway")

	var topic_ids: Array = []
	for topic in investigation.get_topics("character_b"):
		topic_ids.append(topic.get("id"))
	_check(
		not topic_ids.has("chapter_02_debrief"),
		"the chapter-2-scoped topic must not leak into case_00_sandbox even after replicating chapter_01's exact completion state"
	)


## Milestone 1.8 (Case Debugger): debug_reset_trigger() clears the "has
## triggered" marker WITHOUT undoing the event's own already-run effect, and
## does not spuriously refire while the event's own condition is still
## unsatisfied — only a genuine subsequent transition fires it again.
func _test_debug_reset_trigger() -> void:
	_fired_events.clear()
	game_state.start_new_game("case_00_sandbox")
	game_state.mark_seen("custom:character_a_ready_to_move")
	game_state.set_flag("hallway_unlocked", true)
	game_state.add_evidence("test_key")
	_check(event_manager.is_event_triggered("character_a_moves_to_hallway"), "sanity: the event should have fired once from real state")
	_check(_fired_events.count("character_a_moves_to_hallway") == 1, "sanity: fired exactly once so far")

	game_state.remove_evidence("test_key")  # its condition is no longer satisfied
	_check(event_manager.debug_reset_trigger("character_a_moves_to_hallway"), "debug_reset_trigger should succeed for a known event id")
	_check(not event_manager.is_event_triggered("character_a_moves_to_hallway"), "resetting should clear the triggered marker")
	_check(game_state.get_flag("character_a_moved"), "resetting the trigger marker must NOT undo the event's own already-run effect")
	_check(_fired_events.count("character_a_moves_to_hallway") == 1, "reset alone must not refire the event while its condition is still unsatisfied")

	game_state.add_evidence("test_key")  # a genuine second transition to satisfied
	_check(event_manager.is_event_triggered("character_a_moves_to_hallway"), "the event should be able to trigger again after reset once its condition is satisfied a second time")
	_check(_fired_events.count("character_a_moves_to_hallway") == 2, "the event should fire a second time after reset plus a real subsequent transition")

	_check(not event_manager.debug_reset_trigger("no_such_event"), "debug_reset_trigger should fail cleanly for an unknown event id")
