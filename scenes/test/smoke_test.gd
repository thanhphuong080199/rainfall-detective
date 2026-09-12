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
var event_manager
var case_manager
var locale_manager

var _last_choice_texts: Array = []
var _last_dialogue_id: String = ""
var _fired_events: Array[String] = []
var _activated_chapters: Array[String] = []
var _completed_chapters_seen: Array[String] = []
var _completed_cases: Array[String] = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	game_state = get_root().get_node("GameState")
	content_db = get_root().get_node("ContentDB")
	dialogue_manager = get_root().get_node("DialogueManager")
	investigation = get_root().get_node("Investigation")
	save_manager = get_root().get_node("SaveManager")
	event_manager = get_root().get_node("EventManager")
	case_manager = get_root().get_node("CaseManager")
	locale_manager = get_root().get_node("LocaleManager")

	# Autoload nodes exist as soon as get_node finds them, but their _ready()
	# (where ContentDB actually loads data/*.json) hasn't run yet at this
	# point when the entry point is a custom -s SceneTree script — it runs
	# on the next frame, alongside every other autoload's _ready(). Wait for it.
	await process_frame

	dialogue_manager.choices_shown.connect(func(texts): _last_choice_texts = texts)
	dialogue_manager.dialogue_started.connect(_on_dialogue_started_for_test)
	event_manager.event_triggered.connect(func(event_id): _fired_events.append(event_id))
	case_manager.chapter_activated.connect(func(chapter_id): _activated_chapters.append(chapter_id))
	case_manager.chapter_completed.connect(func(chapter_id): _completed_chapters_seen.append(chapter_id))
	case_manager.case_completed.connect(func(case_id): _completed_cases.append(case_id))

	# Never touch the real save slot: this process writes and reloads a save
	# several times, and a developer running the test should not lose the
	# game they had in progress.
	save_manager.save_path = "user://smoke_test_save.json"
	save_manager.delete_save()
	# Same reasoning as save_path: never touch the real player's persisted
	# language preference.
	locale_manager.settings_path = "user://smoke_test_settings.cfg"

	print("=== Milestone 0 Sandbox — Headless Smoke Test ===")
	_test_content_loaded()
	_test_localization()
	_test_conditions()
	_test_progression_flow()
	# Continues from wherever _test_progression_flow() left off, then leaves
	# behind character_a_moved/mirror_note_ready (both triggered) for
	# _test_save_load() below to carry through a save/reset/load round trip.
	_test_event_system()
	# After the save/load round-trip, because it resets the sandbox: _test_save_load
	# asserts against the state the full progression flow above built up.
	_test_save_load()
	# Milestone 1.6: the Case/Chapter layer, exercised through the Test Case.
	# Resets state via CaseManager.start_case(), so anything after this must
	# not depend on state _test_save_load() left behind — _test_interaction_guards()
	# already resets case_00_sandbox itself for exactly this reason.
	_test_case_system()
	_test_interaction_guards()
	_test_scene_instantiation()
	save_manager.delete_save()
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
	_check(content_db.get_all_event_ids().size() >= 3, "at least 3 events should load")
	_check(not content_db.get_event("character_a_moves_to_hallway").is_empty(), "character_a_moves_to_hallway event should load")
	_check(not content_db.get_case("test_case").is_empty(), "test_case should load")
	_check(content_db.get_all_chapter_ids().size() >= 2, "at least 2 chapters should load")
	_check(not content_db.get_chapter("test_case_chapter_01").is_empty(), "test_case_chapter_01 should load")
	_check(not content_db.get_chapter("test_case_chapter_02").is_empty(), "test_case_chapter_02 should load")

	# ContentValidator (see content_validator.gd) runs automatically in
	# ContentDB._ready() — the real sandbox content must always pass with
	# zero errors (warnings are fine; none expected here either).
	var validation: Dictionary = content_db.get_last_validation_result()
	var validation_errors: Array = validation.get("errors", [])
	_check(validation_errors.is_empty(), "content validation should find zero errors in the sandbox content: %s" % [validation_errors])
	_check(validation.get("warnings", []).is_empty(), "content validation should find zero warnings in the sandbox content: %s" % [validation.get("warnings", [])])


## Bilingual localization (Milestone: VI default, EN supported — see
## docs/localization.md). Verifies LocaleManager actually loaded
## localization/strings.csv into real TranslationServer Translation objects,
## that content fields hold translation keys (not literal text) resolving
## correctly in both locales, that switching locale updates an
## already-instantiated screen (not just a screen rendered after the
## switch — the load-bearing behavior the whole design depends on, and the
## one a raw headless probe first disproved for a bare Control.text query
## before this project settled on explicit tr() calls everywhere), and that
## a translation missing from a locale is reported exactly like any other
## broken content reference.
func _test_localization() -> void:
	game_state.start_new_game("case_00_sandbox")
	locale_manager.set_locale("vi")
	_check(locale_manager.get_locale() == "vi", "vi should be settable and is this project's default locale")
	_check(locale_manager.get_known_keys().size() > 50, "the localization CSV should have loaded a meaningful number of keys")

	_check(TranslationServer.translate("UI_SAVE") == "Lưu", "a static UI key should resolve to Vietnamese in the vi locale")
	var char_a_name_key: String = content_db.get_character("character_a").get("name", "")
	_check(char_a_name_key != "Character A", "character name fields should hold a translation key, not literal English text")
	_check(TranslationServer.translate(char_a_name_key) == "Nhân Vật A", "a content-driven key should resolve correctly in the vi locale")

	locale_manager.set_locale("en")
	_check(locale_manager.get_locale() == "en", "set_locale should switch to another supported locale")
	_check(TranslationServer.translate("UI_SAVE") == "Save", "the same key should resolve to English after switching locale")
	_check(TranslationServer.translate(char_a_name_key) == "Character A", "a content-driven key should resolve correctly in the en locale too")

	locale_manager.set_locale("fr")
	_check(locale_manager.get_locale() == "en", "an unsupported locale should be rejected (fail closed), not silently applied")

	# Persistence: a player's language preference is a ConfigFile setting,
	# independent of GameState/save (docs/architecture.md already documents
	# why settings and save games are separate files).
	var config := ConfigFile.new()
	_check(config.load(locale_manager.settings_path) == OK, "set_locale should have written the settings file")
	_check(config.get_value("localization", "locale", "") == "en", "the persisted locale should match the last set_locale call")

	# UI reactivity: an already-rendered screen must reflect a locale change,
	# not just a screen instantiated after it.
	locale_manager.set_locale("vi")
	var main_instance: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_root().add_child(main_instance)
	var action_list: VBoxContainer = main_instance.get_node("%InvestigationView").get_node("%ActionList")
	var found_vi_label := false
	for child in action_list.get_children():
		if child is Label and child.text == "Khám xét":
			found_vi_label = true
	_check(found_vi_label, "a freshly instantiated InvestigationView should render the vi locale's 'Examine' section label")

	locale_manager.set_locale("en")
	var found_en_label := false
	for child in action_list.get_children():
		if child is Label and child.text == "Examine":
			found_en_label = true
	_check(found_en_label, "switching locale must re-render an already-visible InvestigationView, not just future ones")
	main_instance.queue_free()

	# ContentValidator: a translation key missing from a locale is caught the
	# same way any other broken content reference is — never silently shown
	# as raw key text with no report. Loaded via load() rather than the bare
	# class_name (see the -s entry-point compile-order note at the top of
	# this file / docs/architecture.md's "Known limitations") since
	# ContentValidator itself references ContentDB and now LocaleManager by
	# bare autoload name.
	var validator = load("res://scripts/core/content_validator.gd")
	var missing_errors: Array[String] = []
	validator._validate_translatable("THIS_KEY_DOES_NOT_EXIST_ANYWHERE", "probe", missing_errors)
	_check(missing_errors.size() == 2, "a key missing from both locales should be reported once per missing locale")
	var real_key_errors: Array[String] = []
	validator._validate_translatable("UI_SAVE", "probe", real_key_errors)
	_check(real_key_errors.is_empty(), "a real, fully-translated key should not be reported as missing")

	locale_manager.set_locale("vi")  # leave the project's default in place for whatever runs after this


## The condition mini-language's edge cases, which content authors hit far
## more often than they hit the happy path: a mistyped key must NOT silently
## unlock content, and explain() must not claim both halves of an `any` are
## missing when only one is needed.
func _test_conditions() -> void:
	game_state.start_new_game("case_00_sandbox")
	var evaluator = load("res://scripts/core/condition_evaluator.gd")

	_check(evaluator.evaluate(null), "a null condition should always pass")
	_check(not evaluator.evaluate({"has_evidnce": "test_key"}), "a mistyped condition key should fail CLOSED, not unlock content")
	_check(not evaluator.evaluate({}), "an empty condition object should fail closed")
	_check(not evaluator.evaluate("has_evidence:test_key"), "a non-object condition should fail closed")
	_check(not evaluator.evaluate({"all": "not-an-array"}), "a non-array \"all\" should fail closed")
	_check(evaluator.evaluate({"flag": "hallway_unlocked", "equals": false}), "\"equals\" should still be a recognized modifier, not an unknown key")

	# explain(): a top-level `all` is flattened (each part really is
	# required), an `any` stays one line that spells out the alternatives.
	var all_lines: Array = evaluator.explain({"all": [{"has_evidence": "test_key"}, {"has_evidence": "test_badge"}]})
	_check(all_lines.size() == 2, "explain() should list each part of an \"all\" separately")
	var any_lines: Array = evaluator.explain({"any": [{"has_evidence": "test_key"}, {"has_evidence": "test_note"}]})
	_check(any_lines.size() == 1, "explain() should keep an \"any\" as a single entry rather than listing both halves as missing")
	_check(
		String(any_lines[0].get("description", "")).contains(" OR "),
		"an \"any\" explanation should spell out the alternatives"
	)

	# Non-boolean flags must never reach get_flag()'s bool return type.
	game_state.flags["not_a_bool"] = "yes"
	_check(not game_state.get_flag("not_a_bool"), "a non-boolean flag should be reported and treated as the default")
	game_state.flags.erase("not_a_bool")

	# A flag explicitly set to false must still be recorded, so the debug
	# panel can list it and a save can round-trip it.
	game_state.set_flag("explicitly_false", false)
	_check(game_state.flags.has("explicitly_false"), "setting a flag to false should still record it")

	# Two checks in one object: evaluate() honours whichever comes first in
	# its own fixed precedence order (KEYS) and silently drops the rest, so
	# the validator has to reject the shape rather than let it read as "and".
	game_state.add_evidence("test_key")
	_check(
		not evaluator.evaluate({"has_evidence": "test_key", "flag": "definitely_not_set"}),
		"evaluate() resolves \"flag\" before \"has_evidence\" and drops the rest — exactly why the validator rejects the shape"
	)
	var validator = load("res://scripts/core/content_validator.gd")
	var stacked_errors: Array[String] = []
	validator._validate_condition({"has_evidence": "test_key", "flag": "x"}, "probe", stacked_errors)
	_check(stacked_errors.size() == 1, "stacking two checks in one condition should be a validation error")
	_check(
		String(stacked_errors[0] if not stacked_errors.is_empty() else "").contains('only check "flag"'),
		"the error should name the check that would actually win, not the first key in the object"
	)
	var composite_errors: Array[String] = []
	validator._validate_condition({"all": [{"flag": "a"}], "has_evidence": "test_key"}, "probe", composite_errors)
	_check(not composite_errors.is_empty(), "mixing a composite and a leaf check in one object should also be rejected")
	var unreachable_warnings: Array[String] = []
	validator._validate_dialogue_reachability("probe", {
		"start": "n1",
		"nodes": {"n1": {"next": "n2"}, "n2": {}, "orphan": {}},
	}, unreachable_warnings)
	_check(unreachable_warnings.size() == 1, "an unreachable dialogue node should be reported once")
	_check(
		String(unreachable_warnings[0] if not unreachable_warnings.is_empty() else "").contains("orphan"),
		"the unreachable-node warning should name the orphaned node"
	)
	game_state.remove_evidence("test_key")


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


## Milestone 1.5: events react to GameState changes that investigation
## content already produces, reusing the exact ConditionEvaluator/EffectRunner
## investigation content itself uses — no separate condition/effect language.
## Continues from exactly where _test_progression_flow() left off (test_room,
## character_a present, test_key + test_badge held, hallway_unlocked true)
## rather than resetting, so this also proves events fire correctly off state
## real gameplay actions built up, not just hand-set flags.
func _test_event_system() -> void:
	_check(game_state.current_location == "test_room", "event test should continue from where the progression flow left off")
	_check(not event_manager.is_event_triggered("character_a_moves_to_hallway"), "character_a_moves_to_hallway should not have triggered yet")
	_check(_topic_ids("character_a").has("greeting"), "character_a should still be present in test_room before the move event fires")

	# The event's other condition (has_evidence: test_key) is already true —
	# talking to this topic is the last missing piece, so the event (and its
	# chained follow-up) fires mid-dialogue, from this one player action.
	investigation.talk("character_a", "about_moving")
	_drain_dialogue()

	_check(event_manager.is_event_triggered("character_a_moves_to_hallway"), "character_a_moves_to_hallway should have triggered")
	_check(game_state.get_flag("character_a_moved"), "the event's effect should have set character_a_moved")
	_check(_fired_events.has("character_a_moves_to_hallway"), "event_triggered should have fired for character_a_moves_to_hallway")

	# Event chain: mirror_note_ready's only condition is character_a_moved,
	# so it fires automatically in the same evaluation pass — no further
	# player action in between the two.
	_check(event_manager.is_event_triggered("mirror_note_ready"), "mirror_note_ready should chain-trigger once character_a_moved is set")
	_check(_fired_events.has("mirror_note_ready"), "event_triggered should have fired for the chained mirror_note_ready event")

	# Character presence: driven entirely by content/condition (two npc
	# entries for character_a, complementary conditions on one flag), not by
	# any story-specific code.
	_check(not _topic_ids("character_a").has("greeting"), "character_a should no longer be present in test_room after moving")
	investigation.move_to("test_hallway")
	_check(_topic_ids("character_a").has("greeting_hallway"), "character_a should now be present in test_hallway")

	# Event-driven content change: the mirror's examine response changed too,
	# ahead of the older examined-based before/after variants.
	investigation.examine("mirror")
	_check(_last_dialogue_id == "examine_mirror_note_ready", "the mirror should show the event-unlocked variant")
	_drain_dialogue()

	# The new interaction the moved character offers.
	investigation.talk("character_a", "greeting_hallway")
	_drain_dialogue()
	_check(game_state.has_seen("custom:talked_to_character_a_in_hallway"), "talking to character_a in the hallway should be reachable and run its own effects")

	investigation.move_to("test_room")

	# A "once" event must not refire on further unrelated state changes.
	var once_fires_before: int = _fired_events.count("character_a_moves_to_hallway")
	game_state.set_flag("event_test_probe", true)
	_check(_fired_events.count("character_a_moves_to_hallway") == once_fires_before, "a 'once' event must not refire on unrelated state changes")

	# Manual trigger (DebugPanel): runs through the exact same pipeline,
	# bypassing conditions — proven here against an event whose conditions
	# are not currently met.
	_check(not event_manager.is_event_triggered("test_repeatable_pulse"), "test_repeatable_pulse should not be triggered yet")
	_check(event_manager.force_trigger("test_repeatable_pulse"), "force_trigger should succeed for a known event id")
	_check(game_state.has_seen("custom:test_repeatable_pulse_ran"), "force_trigger should run the event's real effects")
	_check(not event_manager.force_trigger("no_such_event"), "force_trigger should fail for an unknown event id")

	# Repeatable trigger policy: fires again on a false->true transition, but
	# not on every unrelated change while its own condition stays satisfied.
	var repeat_fires_before: int = _fired_events.count("test_repeatable_pulse")
	game_state.set_flag("pulse_flag", true)
	_check(_fired_events.count("test_repeatable_pulse") == repeat_fires_before + 1, "repeatable event should fire on a false->true transition")
	game_state.set_flag("event_test_probe", false)  # unrelated change while pulse_flag stays true
	_check(_fired_events.count("test_repeatable_pulse") == repeat_fires_before + 1, "repeatable event must not refire while its own condition stays satisfied")
	game_state.set_flag("pulse_flag", false)
	game_state.set_flag("pulse_flag", true)
	_check(_fired_events.count("test_repeatable_pulse") == repeat_fires_before + 2, "repeatable event should fire again once its condition goes false then true")


## Nothing may mutate progression state while a dialogue is on screen. The
## examine case is the one that actually bit: a rejected examine still marked
## the point as examined, so its evidence-granting "before" variant was
## skipped forever afterwards.
func _test_interaction_guards() -> void:
	game_state.start_new_game("case_00_sandbox")

	investigation.examine("desk")
	_check(dialogue_manager.is_active, "the desk examine dialogue should be playing")

	investigation.examine("window")
	_check(
		not investigation.is_examine_point_seen("window"),
		"an examine rejected because a dialogue is already playing must not mark the point as examined"
	)
	_check(not game_state.has_evidence("test_note"), "a rejected examine must not grant its evidence either")

	investigation.talk("character_a", "greeting")
	_check(
		not investigation.is_topic_seen("character_a", "greeting"),
		"a talk rejected because a dialogue is already playing must not mark the topic as read"
	)

	var location_before: String = game_state.current_location
	investigation.move_to("test_hallway")
	_check(game_state.current_location == location_before, "move_to must not change location mid-dialogue")

	_drain_dialogue()

	# ...and once the dialogue is over, the same calls work normally again.
	investigation.examine("window")
	_drain_dialogue()
	_check(investigation.is_examine_point_seen("window"), "the same examine should work once the dialogue has ended")
	_check(game_state.has_evidence("test_note"), "and should grant its evidence")

	# An unknown dialogue id must not mark anything as seen either.
	_check(not dialogue_manager.start("no_such_dialogue"), "start() should report failure for an unknown dialogue id")

	# DialogueManager.stop() is the escape hatch the debug tools use before
	# yanking game state out from under a running dialogue.
	dialogue_manager.start("character_a_greeting")
	_check(dialogue_manager.is_active, "a dialogue should be running before stop()")
	dialogue_manager.stop()
	_check(not dialogue_manager.is_active, "stop() should end the active dialogue")
	_check(not dialogue_manager.start("no_such_dialogue"), "stop() should leave the manager ready for a new start")
	investigation.examine("desk")
	_check(dialogue_manager.is_active, "the verbs should work again after stop()")
	_drain_dialogue()


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

	# Section 15's actual point: a "once" event that already triggered before
	# save/reset/load must not fire again just because reload re-evaluates
	# every event against the restored (still-satisfying) state.
	_check(event_manager.is_event_triggered("character_a_moves_to_hallway"), "the triggered event's state should survive save/reset/load")
	_check(game_state.get_flag("character_a_moved"), "character_a_moved should survive save/reset/load")
	_check(_fired_events.count("character_a_moves_to_hallway") == 1, "a 'once' event whose conditions are still satisfied must not fire again after loading")
	_check(not _topic_ids("character_a").has("greeting"), "character_a should still be gone from test_room after loading (character_a_moved persisted)")


## Milestone 1.6: Case/Chapter progression, exercised end-to-end through the
## Test Case (two chapters, chapter-scoped content, case completion) —
## including save/load mid-chapter, developer tools, and that a flat case
## (case_00_sandbox) is entirely unaffected. See docs/case-system.md.
func _test_case_system() -> void:
	case_manager.start_case("test_case")
	_check(case_manager.get_current_case_id() == "test_case", "start_case should set the current case id")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_01", "start_case should activate the case's starting_chapter")
	_check(_activated_chapters.has("test_case_chapter_01"), "chapter_activated should fire for the starting chapter")
	_check(not case_manager.is_chapter_complete("test_case_chapter_01"), "chapter_01 should not be complete at case start")

	var explain_info: Dictionary = case_manager.explain_chapter_completion("test_case_chapter_01")
	_check(explain_info.get("has_completion_event", false), "chapter_01 should report it has a completion_event")
	_check(not explain_info.get("conditions_satisfied", true), "chapter_01's completion conditions should not be satisfied at case start")
	_check(not explain_info.get("conditions", []).is_empty(), "explain_chapter_completion should report a condition breakdown")

	# Partial chapter_01 progress, then a save/reset/load round trip mid-chapter.
	investigation.examine("desk")
	_drain_dialogue()
	investigation.present("test_key", "character_a")
	_drain_dialogue()
	_check(game_state.get_flag("hallway_unlocked"), "presenting the key should still unlock the hallway inside the Test Case")
	_check(not case_manager.is_chapter_complete("test_case_chapter_01"), "chapter_01 should still be incomplete before its full conditions are met")

	_check(save_manager.save_game(), "mid-chapter-1 save should succeed")
	case_manager.start_case("test_case")  # simulate "quit to title, start fresh"
	_check(save_manager.load_game(), "mid-chapter-1 load should succeed")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_01", "loading should restore the current chapter")
	_check(game_state.has_evidence("test_key"), "loading should restore evidence held mid-chapter")
	_check(game_state.get_flag("hallway_unlocked"), "loading should restore flags set mid-chapter")
	_check(not case_manager.is_chapter_complete("test_case_chapter_01"), "loading should not mark an incomplete chapter complete")

	# Finish chapter_01's real completion conditions: character_a moves to the
	# hallway (the existing SHARED event from Milestone 1.5), the player
	# follows, and talks to them there. chapter_01's own completion_event
	# reuses ConditionEvaluator/EventManager as-is — no case-specific
	# condition-evaluation logic exists anywhere in this pass.
	investigation.talk("character_a", "about_moving")
	_drain_dialogue()
	_check(game_state.get_flag("character_a_moved"), "the shared event system should still move character_a inside the Test Case")
	investigation.move_to("test_hallway")
	investigation.talk("character_a", "greeting_hallway")
	_drain_dialogue()

	_check(case_manager.is_chapter_complete("test_case_chapter_01"), "chapter_01 should be complete once its completion_event has fired")
	_check(_completed_chapters_seen.has("test_case_chapter_01"), "chapter_completed should fire for chapter_01")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_02", "completing chapter_01 should activate chapter_02")
	_check(_activated_chapters.has("test_case_chapter_02"), "chapter_activated should fire for chapter_02")
	_check(game_state.get_flag("test_case_chapter_02_active"), "chapter_02's entry_effects should run when it becomes current")
	_check(not case_manager.is_case_complete("test_case"), "the case should not be complete after only chapter_01")

	# The chapter-scoped topic must not have been reachable before chapter_02
	# activated it — see the scope-flag condition on it in
	# data/locations/test_hallway.json (section 11's "event/content scope").
	_check(_topic_ids("character_b").has("chapter_02_debrief"), "the chapter-2-scoped topic should be available once chapter_02 is active")

	# Save/load mid-chapter-2.
	_check(save_manager.save_game(), "mid-chapter-2 save should succeed")
	case_manager.start_case("test_case")
	_check(save_manager.load_game(), "mid-chapter-2 load should succeed")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_02", "loading should restore chapter_02 as current")
	_check(case_manager.is_chapter_complete("test_case_chapter_01"), "loading should not un-complete a chapter that already completed")
	_check(_completed_chapters_seen.count("test_case_chapter_01") == 1, "a completed chapter must not re-fire chapter_completed after loading")

	# Complete chapter_02 -> case completion.
	investigation.talk("character_b", "chapter_02_debrief")
	_drain_dialogue()
	_check(case_manager.is_chapter_complete("test_case_chapter_02"), "chapter_02 should complete once its own completion_event fires")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_02", "a chapter with no next_chapter should stay current rather than point at a nonexistent chapter")
	_check(case_manager.is_case_complete("test_case"), "the case should complete once its final chapter completes")
	_check(_completed_cases.has("test_case"), "case_completed should fire once the final chapter completes")
	_check(game_state.get_flag("test_case_complete"), "the completion event's own effects should still run")
	var completed: Array[String] = case_manager.get_completed_chapters("test_case")
	_check(completed.size() == 2 and completed.has("test_case_chapter_01") and completed.has("test_case_chapter_02"), "get_completed_chapters should list both chapters once the case is done")

	# A flat case (no chapters/starting_chapter) must be entirely unaffected —
	# this is the backward-compatibility guarantee case_00_sandbox relies on.
	case_manager.start_case("case_00_sandbox")
	_check(case_manager.get_current_case_id() == "case_00_sandbox", "start_case should work for a flat case too")
	_check(case_manager.get_current_chapter_id() == "", "a flat case should never populate current_chapter")
	_check(not case_manager.force_complete_current_chapter(), "force_complete_current_chapter should fail gracefully with no current chapter")

	_test_case_debug_tools()


## Developer tools (Milestone 1.6, F1 panel): jump_to_chapter and
## force_complete_current_chapter must reuse the real progression pipeline
## rather than duplicating it — see case_manager.gd's class doc.
func _test_case_debug_tools() -> void:
	case_manager.start_case("test_case")
	_check(not case_manager.jump_to_chapter("no_such_chapter"), "jump_to_chapter should fail for an unknown chapter id")

	_check(case_manager.jump_to_chapter("test_case_chapter_02"), "jump_to_chapter should succeed for a known chapter id")
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_02", "jump_to_chapter should update the current chapter")
	_check(game_state.get_flag("test_case_chapter_02_active"), "jump_to_chapter should still run the target chapter's entry_effects")
	_check(not case_manager.is_chapter_complete("test_case_chapter_01"), "jumping past chapter_01 must not mark it complete — it's a teleport, not real progression")

	# force_complete_current_chapter forces the completion event through
	# EventManager.force_trigger(), which bypasses conditions entirely (same
	# as any other manually-triggered event) — so this must succeed even
	# though chapter_02's real completion condition was never satisfied here.
	_check(case_manager.force_complete_current_chapter(), "force_complete_current_chapter should succeed for a chapter with a completion_event")
	_check(case_manager.is_chapter_complete("test_case_chapter_02"), "force_complete_current_chapter should really complete the chapter, not just pretend to")
	_check(case_manager.is_case_complete("test_case"), "forcing the final chapter should still complete the case")

	case_manager.reset_case()
	_check(case_manager.get_current_chapter_id() == "test_case_chapter_01", "reset_case should restart the case from its starting_chapter")
	_check(not case_manager.is_chapter_complete("test_case_chapter_01"), "reset_case should clear chapter completion state")
	_check(not case_manager.is_case_complete("test_case"), "reset_case should clear case completion state")


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

	var investigation_view: Control = main_instance.get_node("%InvestigationView")
	investigation_view.set_interactive(false)
	# Re-rendering the action list (which happens on every flag/evidence
	# change, including ones fired by dialogue actions mid-dialogue) must not
	# hand the player a fresh set of ENABLED buttons.
	game_state.set_flag("smoke_test_render_probe", true)
	var enabled_after_rerender := 0
	for child in investigation_view.get_node("%ActionList").get_children():
		if child is BaseButton and not child.disabled:
			enabled_after_rerender += 1
	_check(
		enabled_after_rerender == 0,
		"re-rendering while not interactive must not re-enable the action buttons (%d were enabled)" % enabled_after_rerender
	)
	investigation_view.set_interactive(true)

	var evidence_inventory: Control = main_instance.get_node("%EvidenceInventory")
	_check(evidence_inventory.mouse_filter == Control.MOUSE_FILTER_STOP, "EvidenceInventory root should STOP mouse input while open")

	var game_menu: Control = main_instance.get_node("%GameMenu")
	_check(game_menu.mouse_filter == Control.MOUSE_FILTER_STOP, "GameMenu root should STOP mouse input while open")

	# Rebuilding a list must not leave the previous (queue_free'd but still
	# in-tree, still clickable, still bound to their old indices) buttons
	# alongside the new ones for the rest of the frame.
	var choices_box: Node = dialogue_box.get_node("%ChoicesBox")
	dialogue_box._show_choices(["A", "B", "C"])
	dialogue_box._show_choices(["X"])
	_check(
		choices_box.get_child_count() == 1,
		"rebuilding the choice list should leave exactly the new buttons (got %d)" % choices_box.get_child_count()
	)

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
