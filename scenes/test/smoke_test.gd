extends SceneTree
## Headless end-to-end verification for Milestone 0. Run with:
##   godot --headless --path . -s res://scenes/test/smoke_test.gd
## Exits 0 and prints ALL TESTS PASSED if every check passes, exits 1 and
## lists failures otherwise (grep output for "FAIL:"/"SCRIPT ERROR" — Godot
## does not reliably reflect script errors in the process exit code).
##
## Drives GameState/ContentDB/DialogueManager/Investigation/SaveManager
## directly, exercising the exact flow from docs/architecture.md's
## Verification section, since a headless run can't click real buttons.
## Autoloads are fetched via get_root().get_node() rather than by bare name
## — a script run as the -s entry point doesn't get the usual compile-time
## autoload name resolution that every *other* script in this project gets
## (see docs/architecture.md, "A Godot quirk this project works around").

var game_state
var content_db
var dialogue_manager
var investigation
var save_manager

var _last_choice_texts: Array = []
var _last_dialogue_id: String = ""
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	game_state = get_root().get_node("GameState")
	content_db = get_root().get_node("ContentDB")
	dialogue_manager = get_root().get_node("DialogueManager")
	investigation = get_root().get_node("Investigation")
	save_manager = get_root().get_node("SaveManager")

	# Autoload nodes exist as soon as get_node finds them, but their _ready()
	# (where ContentDB actually loads data/*.json) hasn't run yet at this
	# point when the entry point is a custom -s SceneTree script — it runs
	# on the next frame, alongside every other autoload's _ready(). Wait for it.
	await process_frame

	dialogue_manager.choices_shown.connect(func(texts): _last_choice_texts = texts)
	dialogue_manager.dialogue_started.connect(_on_dialogue_started_for_test)

	print("=== Milestone 0 Sandbox — Headless Smoke Test ===")
	_test_content_loaded()
	_test_progression_flow()
	_test_save_load()
	_test_scene_instantiation()
	_finish()


func _on_dialogue_started_for_test(dialogue_id: String) -> void:
	_last_choice_texts = []
	_last_dialogue_id = dialogue_id


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_pass_count, _failures.size()])
	if _failures.is_empty():
		print("ALL TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			print("FAIL: ", failure)
		quit(1)


func _test_content_loaded() -> void:
	_check(not content_db.get_character("character_a").is_empty(), "character_a should load")
	_check(not content_db.get_character("character_b").is_empty(), "character_b should load")
	_check(content_db.get_all_evidence_ids().size() >= 3, "at least 3 evidence items should load")
	_check(not content_db.get_location("test_room").is_empty(), "test_room should load")
	_check(not content_db.get_location("test_hallway").is_empty(), "test_hallway should load")
	_check(not content_db.get_case("case_00_sandbox").is_empty(), "case_00_sandbox should load")

	# ContentValidator (see content_validator.gd) runs automatically in
	# ContentDB._ready() — the real sandbox content must always pass with
	# zero errors (warnings are fine; none expected here either).
	var validation: Dictionary = content_db.get_last_validation_result()
	var validation_errors: Array = validation.get("errors", [])
	_check(validation_errors.is_empty(), "content validation should find zero errors in the sandbox content: %s" % [validation_errors])
	_check(validation.get("warnings", []).is_empty(), "content validation should find zero warnings in the sandbox content: %s" % [validation.get("warnings", [])])


func _test_progression_flow() -> void:
	game_state.start_new_game("case_00_sandbox")
	_check(game_state.current_location == "test_room", "new game should start in test_room")
	_check(game_state.evidence_inventory.is_empty(), "new game should start with no evidence")
	_check(not game_state.get_flag("hallway_unlocked"), "hallway_unlocked should start false")

	# Part E: "explain locked content" — both the about_key topic and the
	# hallway destination should report why they're locked, before anything
	# has happened.
	var key_topic_lock: Dictionary = investigation.explain_topic_lock("character_a", "about_key")
	_check(key_topic_lock.get("locked", false), "about_key topic should be locked at game start")
	_check(not key_topic_lock.get("conditions", []).is_empty(), "a locked topic should report at least one condition")
	var hallway_lock: Dictionary = investigation.explain_destination_lock("test_hallway")
	_check(hallway_lock.get("locked", false), "test_hallway destination should be locked at game start")
	_check(not hallway_lock.get("conditions", []).is_empty(), "a locked destination should report at least one condition")

	# Talk topics are auto-marked "seen" the first time Investigation.talk()
	# plays them (B3's completed/read state) — exercise the real verb here,
	# not just DialogueManager.start() directly, to prove that wiring works.
	_check(not investigation.is_topic_seen("character_a", "greeting"), "greeting topic should not be seen before it's been talked about")
	investigation.talk("character_a", "greeting")
	_check(dialogue_manager.is_active, "Investigation.talk should start the greeting dialogue")
	_drain_dialogue()
	_check(investigation.is_topic_seen("character_a", "greeting"), "greeting topic should be marked seen after talking")

	# Talk (before examining the desk): both choices should be offered.
	dialogue_manager.start("character_a_greeting")
	_check(dialogue_manager.is_active, "greeting dialogue should start")
	_check(_last_choice_texts.size() == 2, "greeting should offer 2 choices before the desk is examined")
	_drain_dialogue()
	_check(not dialogue_manager.is_active, "dialogue should end after a terminal choice")

	# Examine: obtain evidence + set a flag from a plain line node's actions.
	investigation.examine("desk")
	_check(dialogue_manager.is_active, "examining the desk should start a dialogue")
	_drain_dialogue()
	_check(game_state.has_evidence("test_key"), "examining the desk should grant test_key")
	_check(game_state.get_flag("desk_examined"), "examining the desk should set desk_examined")

	# `any` condition: about_evidence unlocks once EITHER test_key or test_note is held.
	_check(_topic_ids("character_a").has("about_evidence"), "about_evidence topic should unlock once ANY of test_key/test_note is held")

	# Talk again: the desk question should have disappeared (equals:false condition).
	dialogue_manager.start("character_a_greeting")
	_check(_last_choice_texts.size() == 1, "the 'ask about desk' choice should disappear once desk_examined is true")
	_drain_dialogue()

	# Examine again: should resolve to the "after" variant, no duplicate evidence.
	investigation.examine("desk")
	_drain_dialogue()
	_check(game_state.evidence_inventory.count("test_key") == 1, "examining the desk twice should not duplicate evidence")

	# A second examine point, for a second evidence item.
	investigation.examine("window")
	_drain_dialogue()
	_check(game_state.has_evidence("test_note"), "examining the window should grant test_note")

	# Present (specific match): should fire the node-level action that unlocks the hallway.
	investigation.present("test_key", "character_a")
	_check(dialogue_manager.is_active, "presenting test_key should start a dialogue")
	_drain_dialogue()
	_check(game_state.get_flag("hallway_unlocked"), "presenting test_key to character_a should unlock the hallway")
	_check(_topic_ids("character_a").has("about_key"), "about_key topic should unlock after presenting the key")
	_check(_destination_ids().has("test_hallway"), "test_hallway should become an available destination")

	# Present (generic fallback): no specific response exists for test_note.
	investigation.present("test_note", "character_a")
	_drain_dialogue()

	# Move, and move back, to prove the destination works both directions.
	investigation.move_to("test_hallway")
	_check(game_state.current_location == "test_hallway", "move_to should change the current location")
	investigation.move_to("test_room")
	_check(game_state.current_location == "test_room", "move_to should work in reverse too")
	investigation.move_to("test_hallway")
	_check(
		game_state.visited_locations.has("test_room") and game_state.visited_locations.has("test_hallway"),
		"both locations should be marked visited"
	)

	investigation.examine("shelf")
	_drain_dialogue()
	_check(game_state.has_evidence("test_badge"), "examining the shelf should grant test_badge")

	# `examined` condition + auto-tracked "seen" state: a flavor-only examine
	# point (no evidence) that changes its response after the first look,
	# without needing an evidence-gated variant.
	_check(not investigation.is_examine_point_seen("mirror"), "mirror should not be marked seen before it's been examined")
	investigation.examine("mirror")
	_check(_last_dialogue_id == "examine_mirror_before", "first mirror examine should play the before variant")
	_drain_dialogue()
	_check(investigation.is_examine_point_seen("mirror"), "mirror should be marked seen after the first examine")
	investigation.examine("mirror")
	_check(_last_dialogue_id == "examine_mirror_after", "repeated mirror examine should play the after variant via the 'examined' condition")
	_drain_dialogue()

	investigation.present("test_badge", "character_b")
	_drain_dialogue()
	investigation.present("test_note", "character_b")
	_drain_dialogue()

	# Composite `all` condition: needs both test_key AND test_badge.
	_check(_topic_ids("character_b").has("clue"), "character_b's clue topic should unlock once both key and badge are held")

	# `interaction_complete` condition: character_a's about_character_b topic
	# (back in test_room) unlocks once the "met_character_b" effect has fired
	# — set by a mark_interaction_complete action in character_b_greeting.
	_check(not investigation.is_topic_seen("character_b", "greeting"), "character_b's greeting should not be seen yet")
	investigation.talk("character_b", "greeting")
	_drain_dialogue()
	_check(investigation.is_topic_seen("character_b", "greeting"), "character_b's greeting should be marked seen after talking")
	_check(game_state.has_seen("custom:met_character_b"), "mark_interaction_complete should record 'met_character_b'")

	investigation.move_to("test_room")
	_check(_topic_ids("character_a").has("about_hallway_trip"), "about_hallway_trip topic should unlock once test_hallway has been visited")
	_check(_topic_ids("character_a").has("about_character_b"), "about_character_b topic should unlock once met_character_b is complete")

	# Play one of the newly unlocked topics for real, and confirm it gets
	# marked seen like any other topic.
	investigation.talk("character_a", "about_hallway_trip")
	_drain_dialogue()
	_check(investigation.is_topic_seen("character_a", "about_hallway_trip"), "about_hallway_trip should be marked seen after talking")

	# `remove_evidence` effect: a dedicated test-only dialogue tree (never
	# reachable through any location) exercises the action wiring directly,
	# the same way character_a_greeting is started directly above.
	_check(game_state.has_evidence("test_note"), "should still hold test_note before the remove_evidence test")
	dialogue_manager.start("test_effects_remove_evidence")
	_drain_dialogue()
	_check(not game_state.has_evidence("test_note"), "remove_evidence action should remove test_note")


func _topic_ids(npc_id: String) -> Array:
	var ids: Array = []
	for topic in investigation.get_topics(npc_id):
		ids.append(topic.get("id"))
	return ids


func _destination_ids() -> Array:
	var ids: Array = []
	for destination in investigation.get_available_destinations():
		ids.append(destination.get("location_id"))
	return ids


## Advances/chooses through a dialogue until it ends, always picking the
## first available choice when there is one. Bounded so a content bug that
## creates a real infinite loop fails the test instead of hanging forever.
func _drain_dialogue() -> void:
	var guard := 0
	while dialogue_manager.is_active and guard < 50:
		var had_choices := not _last_choice_texts.is_empty()
		_last_choice_texts = []
		if had_choices:
			dialogue_manager.choose(0)
		else:
			dialogue_manager.advance()
		guard += 1
	_check(guard < 50, "dialogue should terminate within a bounded number of steps")


func _test_save_load() -> void:
	var expected_location: String = game_state.current_location
	var expected_evidence: Array = game_state.evidence_inventory.duplicate()
	var expected_flags: Dictionary = game_state.flags.duplicate()
	var expected_seen: Array = game_state.seen_interactions.duplicate()

	_check(save_manager.save_game(), "save_game should succeed")
	_check(save_manager.has_save(), "has_save should be true after saving")

	game_state.start_new_game("case_00_sandbox")
	_check(game_state.current_location == "test_room", "start_new_game should reset the location")
	_check(game_state.evidence_inventory.is_empty(), "start_new_game should clear evidence")
	_check(game_state.seen_interactions.is_empty(), "start_new_game should clear seen_interactions")
	_check(not investigation.is_topic_seen("character_a", "greeting"), "a fresh game should not have any topic marked seen")

	_check(save_manager.load_game(), "load_game should succeed")
	_check(game_state.current_location == expected_location, "loaded location should match what was saved")
	_check(game_state.evidence_inventory == expected_evidence, "loaded evidence should match what was saved")
	for flag_name in expected_flags:
		_check(
			game_state.get_flag(flag_name) == expected_flags[flag_name],
			"loaded flag '%s' should match its saved value" % flag_name
		)
	_check(game_state.seen_interactions.size() == expected_seen.size(), "loaded seen_interactions should match what was saved")
	for seen_key in expected_seen:
		_check(game_state.has_seen(seen_key), "loaded seen_interactions should still include '%s'" % seen_key)
	_check(investigation.is_topic_seen("character_a", "greeting"), "loaded state should still show the greeting topic as seen")
	# is_examine_point_seen() is scoped to GameState.current_location (test_room
	# after loading), but the mirror was examined in test_hallway — check the
	# composite key directly rather than through that location-scoped helper.
	_check(game_state.has_seen("examine:test_hallway:mirror"), "loaded state should still show the mirror examine point as seen")


func _test_scene_instantiation() -> void:
	var main_instance: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_root().add_child(main_instance)
	_check(is_instance_valid(main_instance), "Main.tscn should instantiate without error")

	var title_instance: Node = (load("res://scenes/main/TitleScreen.tscn") as PackedScene).instantiate()
	get_root().add_child(title_instance)
	_check(is_instance_valid(title_instance), "TitleScreen.tscn should instantiate without error")

	var dialogue_box: Control = main_instance.get_node("%DialogueBox")
	_check(dialogue_box.mouse_filter == Control.MOUSE_FILTER_STOP, "DialogueBox root should STOP mouse input")
	_check(
		dialogue_box.get_node("Box").mouse_filter == Control.MOUSE_FILTER_PASS,
		"DialogueBox's Box panel should PASS input through to the root (click-anywhere-to-advance)"
	)

	var evidence_inventory: Control = main_instance.get_node("%EvidenceInventory")
	_check(evidence_inventory.mouse_filter == Control.MOUSE_FILTER_STOP, "EvidenceInventory root should STOP mouse input while open")

	var game_menu: Control = main_instance.get_node("%GameMenu")
	_check(game_menu.mouse_filter == Control.MOUSE_FILTER_STOP, "GameMenu root should STOP mouse input while open")

	var debug_panel: Control = main_instance.get_node("%DebugPanel")
	_check(is_instance_valid(debug_panel), "DebugPanel should instantiate without error")
	_check(not debug_panel.visible, "DebugPanel should start hidden")
	if OS.is_debug_build():
		debug_panel.open()
		_check(debug_panel.visible, "DebugPanel.open() should show the panel in a debug build")
		debug_panel.close()
		_check(not debug_panel.visible, "DebugPanel.close() should hide the panel again")

	main_instance.queue_free()
	title_instance.queue_free()
