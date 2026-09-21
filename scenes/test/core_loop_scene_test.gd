extends SceneTree
## Milestone 1.16 — the production core loop through its REAL scenes and
## buttons (see docs/core-loop-sandbox.md and docs/testing.md). Starts at the
## title screen exactly like a player: New Game -> briefing -> investigation
## driven through InvestigationView's action buttons and the DialogueBox's own
## click handler -> Case File -> the HUD's mechanic entry -> B1, A, B2 and C
## through MechanicScreen's buttons -> the narrative Result screen -> Restart
## / Main menu; Continue from the title screen at several checkpoints
## (investigation, between mechanics, mid-mechanic, Assisted Mode); a
## partner-resolved route; VI and EN; the fixed-footer layout; and a scan of
## every visible string for raw ids, translation keys and run-result badges.
## Never opens F1, the DebugPanel or the Deduction Lab.
##
## Needs a real scene tree (scene changes, input handlers) — FULL only.
## Headless: it proves routing, state and text, not pixels — see
## docs/core-loop-sandbox.md, "Manual QA", for what still needs human eyes.
##
##   godot --headless --path . -s res://scenes/test/core_loop_scene_test.gd

const SAVE_NAME := "core_loop_scene_test"

var game_state: Node
var save_manager: Node
var locale_manager: Node
var dialogue_manager: Node
var main: Control
var _id_pattern := RegEx.new()
var _key_pattern := RegEx.new()
var _forbidden_labels: Array[String] = []
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	game_state = get_root().get_node("GameState")
	save_manager = get_root().get_node("SaveManager")
	locale_manager = get_root().get_node("LocaleManager")
	dialogue_manager = get_root().get_node("DialogueManager")
	TestHelpers.isolate_save(save_manager, SAVE_NAME)
	TestHelpers.isolate_locale(locale_manager, SAVE_NAME)
	locale_manager.set_locale("vi")
	_id_pattern.compile("\\b(?:e|st|ded|tl|c|sbx|hyp|exp|concl|ps|q|proto|round|case|chapter|b1|a1|b2|c1)_[a-z0-9_]+\\b")
	_key_pattern.compile("\\b[A-Z][A-Z0-9]*_[A-Z0-9_]{2,}\\b")
	for locale in ["vi", "en"]:
		locale_manager.set_locale(locale)
		for key in ["UI_RESOLUTION_TIER_INDEPENDENT", "UI_RESOLUTION_TIER_GUIDED", "UI_RESOLUTION_TIER_ASSISTED"]:
			_forbidden_labels.append(TranslationServer.translate(key))
	locale_manager.set_locale("vi")

	print("=== Core loop — production scenes end to end ===")
	# The leak scan must be able to fail: prove it catches each kind of leak.
	_check(_id_pattern.search("see e_door_log") != null and _id_pattern.search("st_oren_never_touched") != null, "sanity: the id pattern catches raw content ids")
	_check(_key_pattern.search("CL_SBX_BRIEFING_TITLE") != null and _key_pattern.search("Oren Tal (visiting researcher)") == null, "sanity: the key pattern catches untranslated keys, not prose")
	await _test_title_new_game_opens_briefing()
	_test_briefing_locales_and_continue()
	await _test_investigation_to_first_deduction()
	await _test_continue_between_mechanics()
	await _test_confrontation()
	await _test_second_deduction_and_mid_mechanic_resume()
	await _test_timeline_and_final_claim()
	_test_result_screen()
	await _test_restart_is_a_clean_run()
	await _test_partner_route_and_assisted_resume()
	await _test_return_to_menu_from_result()

	save_manager.delete_save()
	locale_manager.set_locale("vi")
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


# ---------------------------------------------------------------------------
# Tests

func _test_title_new_game_opens_briefing() -> void:
	save_manager.delete_save()
	var title: Control = (load("res://scenes/main/TitleScreen.tscn") as PackedScene).instantiate()
	get_root().add_child(title)
	current_scene = title
	await process_frame
	_check((title.get_node("%ContinueButton") as Button).disabled, "Continue is disabled with no save")
	var broken := FileAccess.open(save_manager.save_path, FileAccess.WRITE)
	broken.store_string("{ broken")
	broken.close()
	title.queue_free()
	title = (load("res://scenes/main/TitleScreen.tscn") as PackedScene).instantiate()
	get_root().add_child(title)
	current_scene = title
	await process_frame
	_check((title.get_node("%ContinueButton") as Button).disabled and (title.get_node("%StatusLabel") as Label).text == TranslationServer.translate("UI_TITLE_SAVE_UNREADABLE"), "an unreadable save disables Continue with a safe message")
	_click_visible(title.get_node("%NewGameButton"))
	await _await_scene_change()
	_check(FileAccess.file_exists(save_manager.save_path.get_basename() + ".unreadable.json"), "the unreadable save was preserved before being replaced")
	main = current_scene as Control
	_check(main != null and main.name == "Main", "New Game from the title screen opens the gameplay scene")
	var runtime: RefCounted = main.get_runtime()
	_check(runtime.is_active() and runtime.get_phase_id() == "briefing", "the sandbox chapter starts in its briefing")
	_check(_screen("BriefingScreen").visible and not _screen("CoreLoopHud").visible, "the briefing is the screen shown, not the investigation HUD")
	_check(save_manager.has_resumable_save(), "the new run was checkpointed")
	_check(not main.get_node("%DebugPanel").visible, "the production route never shows the DebugPanel")


func _test_briefing_locales_and_continue() -> void:
	var briefing: Control = _screen("BriefingScreen")
	var title_label: Label = briefing.get_node("%TitleLabel")
	var vi_title: String = title_label.text
	_scan_visible("briefing (vi)")
	_click_visible(briefing.get_node("%EnButton"))
	_check(title_label.text != vi_title and title_label.text == TranslationServer.translate("CL_SBX_BRIEFING_TITLE"), "the briefing re-renders in English")
	_scan_visible("briefing (en)")
	_check((briefing.get_node("%NonCanonLabel") as Label).visible, "the briefing marks the chapter as non-canon sandbox content")
	_click_visible(briefing.get_node("%ContinueButton"))
	_check(not briefing.visible and _screen("CoreLoopHud").visible, "Continue leaves the briefing for the investigation")
	_check(main.get_runtime().get_phase_id() == "investigation_1", "the briefing acknowledgement is a phase transition")
	_check((main.get_node("%InvestigationView").get_node("%EvidenceButton") as Button).text == TranslationServer.translate("UI_CORE_LOOP_CASE_FILE_BUTTON"), "the investigation's evidence button opens the Case File")


func _test_investigation_to_first_deduction() -> void:
	var hud: Control = _screen("CoreLoopHud")
	_check(not (hud.get_node("%OpenUnitButton") as Button).visible and (hud.get_node("%UnitHintLabel") as Label).text != "", "the HUD says to keep investigating while B1 is locked")
	# Case File: empty state first.
	_click_visible(main.get_node("%InvestigationView").get_node("%EvidenceButton"))
	var case_file: Control = _screen("CaseFile")
	_check(case_file.visible and _texts(case_file).has(TranslationServer.translate("UI_CORE_LOOP_EVIDENCE_EMPTY")), "the Case File shows an explicit empty state")
	_click_visible(case_file.get_node("%CloseButton"))

	await _examine("LOC_SBX_EXAMINE_TRANSIT_MAP")
	_check((hud.get_node("%NoticeLabel") as Label).text.contains(TranslationServer.translate("DED_PROTO_X_E_ROUTE_NOTE_NAME")), "acquiring evidence shows a Case File notification")
	await _talk("sbx_mara", "LOC_SBX_TOPIC_MARA_EVENING")
	await _move("LOC_SBX_DEST_STACKS_WING")
	await _examine("LOC_SBX_EXAMINE_DOOR_TERMINAL")
	_check(game_state.has_evidence("sbx_door_log") and game_state.has_evidence("sbx_tram_tap") and game_state.has_evidence("sbx_route_note"), "the B1 evidence came from clicking hotspots and an NPC topic")
	_check(save_manager.inspect_save().get("state", {}).get("evidence", []).has("sbx_door_log"), "evidence acquisition was checkpointed when the dialogue ended")

	_click_visible(main.get_node("%InvestigationView").get_node("%EvidenceButton"))
	var first: Button = case_file.get_node("%EvidenceList").get_child(0) as Button
	first.pressed.emit()
	_check((case_file.get_node("%DetailText") as Label).text != "", "selecting an item in the Case File shows its detail")
	_check(main.get_runtime().is_case_file_evidence_opened("sbx_route_note"), "reading it in the Case File is remembered")
	_check((case_file.get_node("%OpenUnitButton") as Button).visible, "the Case File offers the available deduction")
	_scan_visible("case file (en)")
	_click_visible(case_file.get_node("%OpenUnitButton"))
	var screen: Control = _screen("MechanicScreen")
	_check(screen.visible and not case_file.visible, "the Case File opens B1 in the mechanic screen")
	_check(_mechanic_evidence_ids().has("e_route_note") and not _mechanic_evidence_ids().has("e_latch_guide"), "B1 offers only acquired evidence")
	_scan_visible("B1 (en)")
	for evidence_id in CoreLoopTestSupport.B1_PATH:
		_press(screen, "Place_%s" % _handle(evidence_id))
	_check(not (screen.get_node("%PrimaryButton") as Button).disabled, "a complete draft enables the formal commit")
	_click_visible(screen.get_node("%PrimaryButton"))
	_check((screen.get_node("%FeedbackPanel") as Control).visible and (screen.get_node("%ContinueButton") as Button).visible, "resolving B1 shows feedback with Continue")
	_check(not (screen.get_node("%PrimaryButton") as Button).visible, "no further formal commit is offered after resolution")
	_scan_visible("B1 feedback (en)")
	await _check_footer_layout(screen)
	_click_visible(screen.get_node("%ContinueButton"))
	_check(not screen.visible and main.get_runtime().get_phase_id() == "confrontation", "Continue returns to the investigation in the confrontation phase")
	_check((hud.get_node("%ObjectiveLabel") as Label).text.contains(TranslationServer.translate("CL_SBX_OBJECTIVE_CONFRONTATION")), "the HUD shows the new objective")


func _test_continue_between_mechanics() -> void:
	var before: Dictionary = game_state.chapter_run.duplicate(true)
	await _quit_to_title()
	var title: Control = current_scene as Control
	_check(not (title.get_node("%ContinueButton") as Button).disabled, "a valid save enables Continue")
	_click_visible(title.get_node("%ContinueButton"))
	await _await_scene_change()
	main = current_scene as Control
	var runtime: RefCounted = main.get_runtime()
	_check(runtime.get_phase_id() == "confrontation" and _screen("CoreLoopHud").visible, "Continue resumes between mechanics at the confrontation")
	_check((game_state.chapter_run.get("applied_consequences", {}) as Dictionary).keys() == (before.get("applied_consequences", {}) as Dictionary).keys(), "Continue neither loses nor re-applies consequences")
	_check(runtime.get_recorder().get_events().any(func(event: Dictionary) -> bool: return event.get("type", "") == "chapter_resumed"), "the new session's recording starts with a resume observation")


func _test_confrontation() -> void:
	await _move("LOC_SBX_DEST_STACKS_WING")
	await _talk("sbx_oren", "LOC_SBX_TOPIC_OREN_BADGE")
	await _move("LOC_SBX_DEST_LOBBY")
	await _examine("LOC_SBX_EXAMINE_FRONT_DESK_LOG")
	var hud: Control = _screen("CoreLoopHud")
	_check((hud.get_node("%OpenUnitButton") as Button).visible, "the HUD offers the confrontation once Oren was pressed and the sheet is held")
	_click_visible(hud.get_node("%OpenUnitButton"))
	var screen: Control = _screen("MechanicScreen")
	_check(screen.visible, "the HUD opens A")
	_press(screen, "Statement_0")
	_press(screen, "Choose_%s" % _handle("e_tram_tap"))
	_click_visible(screen.get_node("%PrimaryButton"))
	_check((screen.get_node("%FeedbackPanel") as Control).visible and main.get_runtime().get_phase_id() == "confrontation", "a wrong presentation shows feedback and does not advance")
	_click_visible(screen.get_node("%ContinueButton"))
	_check(screen.visible, "Continue after a failure stays in the confrontation")
	_press(screen, "Statement_%d" % CoreLoopTestSupport.A1_STATEMENT_INDEX)
	_press(screen, "Choose_%s" % _handle(CoreLoopTestSupport.A1_EVIDENCE))
	_scan_visible("A (en)")
	_click_visible(screen.get_node("%PrimaryButton"))
	_scan_visible("A feedback (en)")
	_click_visible(screen.get_node("%ContinueButton"))
	_check(not screen.visible and main.get_runtime().get_phase_id() == "investigation_2", "resolving A returns to the second investigation")


func _test_second_deduction_and_mid_mechanic_resume() -> void:
	locale_manager.set_locale("vi")
	await _move("LOC_SBX_DEST_STACKS_WING")
	await _examine("LOC_SBX_EXAMINE_FORCED_WINDOW")
	await _examine("LOC_SBX_EXAMINE_WINDOW_LATCH")
	await _move("LOC_SBX_DEST_LOBBY")
	await _move("LOC_SBX_DEST_MAINTENANCE_OFFICE")
	await _examine("LOC_SBX_EXAMINE_REPAIR_SHELF")
	_click_visible(_screen("CoreLoopHud").get_node("%OpenUnitButton"))
	var screen: Control = _screen("MechanicScreen")
	_press(screen, "Place_%s" % _handle("e_forced_window"))
	_press(screen, "Place_%s" % _handle("e_latch_guide"))
	_scan_visible("B2 draft (vi)")
	# Quit with the mechanic open: the draft and the open screen must come back.
	await _quit_to_title()
	_click_visible((current_scene as Control).get_node("%ContinueButton"))
	await _await_scene_change()
	main = current_scene as Control
	screen = _screen("MechanicScreen")
	_check(screen.visible and main.get_runtime().get_open_unit_id() == CoreLoopTestSupport.B2, "Continue reopens the mechanic that was open")
	var draft: Array[String] = main.get_runtime().get_unit(CoreLoopTestSupport.B2).controller.get_selected_evidence_ids()
	_check(draft.size() == 2 and draft.has("e_forced_window") and draft.has("e_latch_guide"), "the partial B2 draft survives quit/Continue: %s" % [draft])
	_press(screen, "Place_%s" % _handle("e_window_latch"))
	_click_visible(screen.get_node("%PrimaryButton"))
	_click_visible(screen.get_node("%ContinueButton"))
	_check(main.get_runtime().get_phase_id() == "timeline", "B2 unlocks the timeline")


func _test_timeline_and_final_claim() -> void:
	_click_visible(_screen("CoreLoopHud").get_node("%OpenUnitButton"))
	var screen: Control = _screen("MechanicScreen")
	_check(screen.visible, "the HUD opens the timeline")
	for event_id in CoreLoopTestSupport.C1_TIMELINE:
		_press(screen, "Slot_%s_%s" % [_handle(event_id), (CoreLoopTestSupport.C1_TIMELINE[event_id] as String).replace(":", "")])
	_scan_visible("C timeline (vi)")
	_click_visible(screen.get_node("%PrimaryButton"))
	_check((screen.get_node("%FeedbackPanel") as Control).visible and main.get_runtime().get_phase_id() == "final_claim", "an accepted timeline shows feedback and enters the final claim")
	_click_visible(screen.get_node("%ContinueButton"))
	_check(screen.visible, "the final claim continues on the same screen")
	_check((screen.get_node("%PrimaryButton") as Button).disabled, "the verdict cannot be submitted without a verdict and a supporting fact")
	_press(screen, "VerdictImpossible")
	_check((screen.get_node("%PrimaryButton") as Button).disabled, "a verdict alone is not enough")
	_press(screen, "Support_%s" % _handle(CoreLoopTestSupport.C1_CLAIM_SUPPORT))
	_scan_visible("C claim (vi)")
	_click_visible(screen.get_node("%PrimaryButton"))
	_check(main.get_runtime().is_completed(), "the accepted final claim completes the chapter")
	_check(screen.visible and (screen.get_node("%FeedbackPanel") as Control).visible and not _screen("ResultScreen").visible, "the verdict's explanation is shown before the Result screen (visual QA regression)")
	_scan_visible("C claim feedback (vi)")
	_click_visible(screen.get_node("%ContinueButton"))
	_check(not screen.visible and _screen("ResultScreen").visible, "Continue after the final claim opens the Result screen")


func _test_result_screen() -> void:
	var result: Control = _screen("ResultScreen")
	var findings: Node = result.get_node("%FindingsList")
	_check(findings.get_child_count() == 5, "the result narrates all five findings")
	var joined: String = "\n".join(PackedStringArray(_texts(result)))
	for label in _forbidden_labels:
		_check(not joined.contains(label), "the result shows no run-result label \"%s\"" % label)
	_scan_visible("result (vi)")
	locale_manager.set_locale("en")
	_scan_visible("result (en)")
	_click_visible(result.get_node("%ExportButton"))
	_check((result.get_node("%StatusLabel") as Label).text != "", "exporting the evaluation log reports its outcome")


func _test_restart_is_a_clean_run() -> void:
	var result: Control = _screen("ResultScreen")
	var old_run: String = main.get_runtime().get_run_id()
	_click_visible(result.get_node("%RestartButton"))
	var dialog: ConfirmationDialog = result.get_node("%ConfirmDialog")
	_check(dialog.visible, "restarting asks for confirmation first")
	dialog.confirmed.emit()
	dialog.hide()
	await process_frame
	var runtime: RefCounted = main.get_runtime()
	_check(runtime.get_run_id() != old_run and runtime.get_phase_id() == "briefing" and _screen("BriefingScreen").visible, "restart starts a genuinely new run at the briefing")
	_check(game_state.evidence_inventory.is_empty() and runtime.get_findings().is_empty() and runtime.get_session().get_resolved_claims().is_empty(), "the new run inherits nothing")


func _test_partner_route_and_assisted_resume() -> void:
	_click_visible(_screen("BriefingScreen").get_node("%ContinueButton"))
	await _examine("LOC_SBX_EXAMINE_TRANSIT_MAP")
	await _examine("LOC_SBX_EXAMINE_NOTICEBOARD")
	await _examine("LOC_SBX_EXAMINE_FRONT_DESK_LOG")
	await _talk("sbx_mara", "LOC_SBX_TOPIC_MARA_EVENING")
	await _move("LOC_SBX_DEST_STACKS_WING")
	await _examine("LOC_SBX_EXAMINE_DOOR_TERMINAL")
	await _examine("LOC_SBX_EXAMINE_FORCED_WINDOW")
	_click_visible(_screen("CoreLoopHud").get_node("%OpenUnitButton"))
	var screen: Control = _screen("MechanicScreen")
	var wrong_sets: Array = [
		["e_door_log", "e_tram_tap", "e_back_door_sighting"], ["e_door_log", "e_route_note", "e_back_door_sighting"],
		["e_tram_tap", "e_route_note", "e_back_door_sighting"], ["e_door_log", "e_tram_tap", "e_lost_property_sheet"],
		["e_door_log", "e_route_note", "e_forced_window"],
	]
	_click_visible(screen.get_node("%HintButton"))
	_check((screen.get_node("%HintPanel") as Control).visible, "a revealed hint is shown")
	for i in 3:
		_submit_b_set(screen, wrong_sets[i])
	var primary: Button = screen.get_node("%PrimaryButton")
	_check((screen.get_node("%AcceptAssistanceButton") as Button).visible and (not primary.visible or primary.disabled), "after three failures assistance must be accepted before submitting again")
	_click_visible(screen.get_node("%AcceptAssistanceButton"))
	_check((screen.get_node("%AssistancePanel") as Control).visible, "accepted assistance is shown")
	_scan_visible("assisted B1 (vi)")
	# Quit in Assisted Mode, Continue, finish the budget, partner-resolve.
	await _quit_to_title()
	_click_visible((current_scene as Control).get_node("%ContinueButton"))
	await _await_scene_change()
	main = current_scene as Control
	screen = _screen("MechanicScreen")
	var policy: ResolutionPolicy = main.get_runtime().get_unit(CoreLoopTestSupport.B1).get_policy()
	_check(screen.visible and policy.get_current_unit_phase() == "assisted" and (screen.get_node("%AssistancePanel") as Control).visible, "Continue restores Assisted Mode on the reopened mechanic")
	for i in [3, 4]:
		_submit_b_set(screen, wrong_sets[i])
	_check((screen.get_node("%PartnerButton") as Button).visible, "two assisted failures offer partner resolution")
	_click_visible(screen.get_node("%PartnerButton"))
	_check((screen.get_node("%FeedbackPanel") as Control).visible, "the partner explains the connection")
	_click_visible(screen.get_node("%ContinueButton"))
	_check(main.get_runtime().get_phase_id() == "confrontation", "partner resolution prevents a hard lock")
	_click_visible(main.get_node("%InvestigationView").get_node("%EvidenceButton"))
	var joined: String = "\n".join(PackedStringArray(_texts(_screen("CaseFile"))))
	_check(joined.contains(TranslationServer.translate("UI_CORE_LOOP_FINDING_PARTNER")), "the Case File narrates the partner's help in words")
	for label in _forbidden_labels:
		_check(not joined.contains(label), "the Case File shows no run-result label \"%s\"" % label)
	_click_visible(_screen("CaseFile").get_node("%CloseButton"))
	_check(main.get_runtime().get_run_help_result() == "assisted", "the run help result is stored internally as Assisted")


func _test_return_to_menu_from_result() -> void:
	var runtime: RefCounted = main.get_runtime()
	# Finish this run quickly through the runtime so the Result screen shows.
	var support := CoreLoopTestSupport.new(self)
	support.unlock_a1()
	support.solve_a(runtime)
	support.gather_b2_evidence()
	support.solve_b(runtime, CoreLoopTestSupport.B2, CoreLoopTestSupport.B2_PATH)
	support.solve_timeline(runtime)
	support.solve_claim(runtime)
	main.call("_show_current_screen")
	var result: Control = _screen("ResultScreen")
	_check(result.visible, "a completed run shows the Result screen")
	_click_visible(result.get_node("%MenuButton"))
	await _await_scene_change()
	var title: Control = current_scene as Control
	_check(title.name == "TitleScreen" and not (title.get_node("%ContinueButton") as Button).disabled, "Return to menu goes to the title screen, where the completed run can be continued")
	_click_visible(title.get_node("%ContinueButton"))
	await _await_scene_change()
	main = current_scene as Control
	_check(_screen("ResultScreen").visible and main.get_runtime().is_completed(), "Continue on a completed chapter reopens its Result screen")


# ---------------------------------------------------------------------------
# Driving helpers — real controls only.

func _screen(node_name: String) -> Control:
	return main.get_node("%" + node_name) as Control


## Presses a button only the way a player could: it must be on screen and
## enabled (a hidden button's signal would still fire, masking a routing bug).
func _click_visible(node: Node) -> void:
	var button: Button = node as Button
	var clickable: bool = button != null and button.is_visible_in_tree() and not button.disabled
	_check(clickable, "button %s should be visible and enabled when pressed" % (node.name if node != null else "<null>"))
	if clickable:
		button.pressed.emit()


func _press(root: Node, node_name: String) -> void:
	var button: Button = root.find_child(node_name, true, false) as Button
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "button %s should exist, be visible and enabled" % node_name)
	if button != null and button.is_visible_in_tree() and not button.disabled:
		button.pressed.emit()


func _action_list() -> Node:
	return main.get_node("%InvestigationView").get_node("%ActionList")


func _press_action(label: String) -> bool:
	for child in _action_list().get_children():
		if child is Button and ((child as Button).text == label or (child as Button).text.begins_with(label)):
			(child as Button).pressed.emit()
			return true
	return false


func _to_main_list() -> void:
	for i in 3:
		if not _press_action(TranslationServer.translate("UI_BACK")):
			return


## Advances the dialogue through the DialogueBox's own mouse handler.
func _finish_dialogue() -> void:
	var box: Control = main.get_node("%DialogueBox")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var guard := 0
	while dialogue_manager.is_active and guard < 40:
		box._gui_input(click)
		await process_frame
		guard += 1


func _examine(label_key: String) -> void:
	_to_main_list()
	_check(_press_action(TranslationServer.translate(label_key)), "examine %s should be offered" % label_key)
	await _finish_dialogue()


func _talk(npc_id: String, topic_key: String) -> void:
	_to_main_list()
	_check(_press_action(TranslationServer.translate(get_root().get_node("ContentDB").get_character(npc_id).get("name", ""))), "%s should be present" % npc_id)
	_press_action(TranslationServer.translate("UI_TALK"))
	_check(_press_action(TranslationServer.translate(topic_key)), "topic %s should be offered" % topic_key)
	await _finish_dialogue()
	_to_main_list()


const DESTINATION_LOCATIONS := {
	"LOC_SBX_DEST_STACKS_WING": "sbx_stacks_wing", "LOC_SBX_DEST_LOBBY": "sbx_archive_lobby",
	"LOC_SBX_DEST_MAINTENANCE_OFFICE": "sbx_maintenance_office",
}


func _move(destination_key: String) -> void:
	if game_state.current_location == DESTINATION_LOCATIONS.get(destination_key, ""):
		return
	_to_main_list()
	_press_action(TranslationServer.translate("UI_GO_SOMEWHERE_ELSE"))
	_check(_press_action(TranslationServer.translate(destination_key)), "destination %s should be offered" % destination_key)
	await process_frame


func _quit_to_title() -> void:
	_click_visible(main.get_node("%InvestigationView").get_node("%MenuButton"))
	var menu: Control = main.get_node("%GameMenu")
	_click_visible(menu.get_node("%QuitButton"))
	await _await_scene_change()
	main = null


func _await_scene_change() -> void:
	await process_frame
	await process_frame
	await process_frame


func _handle(id: String) -> String:
	var handles: Dictionary = _screen("MechanicScreen").get("_handles")
	for handle in handles:
		if handles[handle] == id:
			return str(handle)
	return "<no handle for %s>" % id


func _mechanic_evidence_ids() -> Array:
	return (_screen("MechanicScreen").get("_handles") as Dictionary).values()


func _submit_b_set(screen: Control, evidence_ids: Array) -> void:
	for handle in (screen.get("_handles") as Dictionary).keys():
		var remove: Button = screen.find_child("SlotRemove_%s" % handle, true, false) as Button
		if remove != null:
			remove.pressed.emit()
	for evidence_id in evidence_ids:
		_press(screen, "Place_%s" % _handle(evidence_id))
	_click_visible(screen.get_node("%PrimaryButton"))
	_click_visible(screen.get_node("%ContinueButton"))


## Every visible Label/Button string under `root`.
func _texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node in root.find_children("*", "Control", true, false):
		var control: Control = node
		if not control.is_visible_in_tree():
			continue
		if control is Label:
			out.append((control as Label).text)
		elif control is Button:
			out.append((control as Button).text)
	return out


## No raw content id, untranslated key or run-result badge on screen.
func _scan_visible(context: String) -> void:
	var leaks: Array[String] = []
	for text in _texts(main):
		if _id_pattern.search(text) != null or _key_pattern.search(text) != null:
			leaks.append(text)
		for label in _forbidden_labels:
			if text == label or text.contains(": %s" % label):
				leaks.append(text)
	_check(leaks.is_empty(), "%s: no ids, keys or run-result labels on screen: %s" % [context, leaks])


## The formal commit and Continue live in the fixed footer, never inside the
## scrolling body, and stay inside the 1280x720 viewport even with feedback
## far longer than anything authored.
func _check_footer_layout(screen: Control) -> void:
	var footer: Control = screen.get_node("%Footer")
	var body: Control = screen.get_node("%BodyScroll")
	for button_name in ["PrimaryButton", "ContinueButton", "HintButton", "AcceptAssistanceButton", "PartnerButton"]:
		var button: Control = screen.get_node("%" + button_name)
		_check(footer.is_ancestor_of(button) and not body.is_ancestor_of(button), "%s lives in the fixed footer" % button_name)
	_check(footer.get_index() > body.get_index(), "the footer comes after the scrolling body")
	var text: Label = screen.get_node("%FeedbackText")
	var original: String = text.text
	text.text = "A deliberately overlong feedback line for the layout check. ".repeat(120)
	await process_frame
	await process_frame
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_root().get_visible_rect().size)
	var continue_button: Button = screen.get_node("%ContinueButton")
	_check(viewport.size == Vector2(1280, 720), "tests run at the project's 1280x720 viewport (got %s)" % viewport.size)
	_check(viewport.encloses(continue_button.get_global_rect()), "Continue stays inside the viewport with very long feedback: %s" % continue_button.get_global_rect())
	_check((screen.get_node("%BodyScroll") as ScrollContainer).get_v_scroll_bar().max_value > (screen.get_node("%BodyScroll") as ScrollContainer).size.y, "the long text really overflowed into the scrolling body (sanity)")
	text.text = original
