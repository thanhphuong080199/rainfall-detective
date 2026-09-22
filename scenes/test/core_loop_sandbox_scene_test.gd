extends SceneTree
## Milestone 1.17 — sandbox selection and the SECOND sandbox through the real
## scenes and buttons (see docs/core-loop-sandbox.md, "Sandbox selection", and
## docs/testing.md). Starts at TitleScreen.tscn like a player: the debug-build
## Technical Sandbox selector (and its absence in a release build, and its
## collapse with one entry), picking sandbox 2, New Game, briefing, the
## investigation, the Case File, B, the two-round confrontation, the second
## investigation, B again, C and the final claim, the narrative Result,
## Restart and Menu, Continue at a mid-mechanic checkpoint and on a completed
## run, and replacing a resumable save with the OTHER sandbox (confirmed).
## The route itself comes from CoreLoopRouteSimulator (content-derived, API
## level) and is then REPLAYED here only through visible, enabled controls:
## the primary route in Vietnamese, the alternate route (other B2 proof set,
## alternate timeline, optional innocent lie) in English. Also opens the Case
## Debugger's Core Loop tab once, and checks the Deduction Lab is never used.
##
## Needs a real scene tree — FULL only. Proves routing, state and text, not
## pixels (docs/core-loop-sandbox.md, "Manual QA").
##
##   godot --headless --path . -s res://scenes/test/core_loop_sandbox_scene_test.gd

const SAVE_NAME := "core_loop_sandbox_scene_test"
const S := preload("res://scenes/test/core_loop_test_support.gd")

var game_state: Node
var save_manager: Node
var locale_manager: Node
var dialogue_manager: Node
var content_db: Node
var main: Control
var _id_pattern := RegEx.new()
var _key_pattern := RegEx.new()
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	game_state = get_root().get_node("GameState")
	save_manager = get_root().get_node("SaveManager")
	locale_manager = get_root().get_node("LocaleManager")
	dialogue_manager = get_root().get_node("DialogueManager")
	content_db = get_root().get_node("ContentDB")
	TestHelpers.isolate_save(save_manager, SAVE_NAME)
	TestHelpers.isolate_locale(locale_manager, SAVE_NAME)
	_id_pattern.compile("\\b(?:e|st|ded|tl|c|sbx|sby|hyp|exp|concl|ps|q|proto|round|case|chapter|b1|a1|b2|c1)_[a-z0-9_]+\\b")
	_key_pattern.compile("\\b[A-Z][A-Z0-9]*_[A-Z0-9_]{2,}\\b")

	print("=== Core loop — sandbox selection and the second sandbox, real scenes ===")
	_check(_id_pattern.search("see sby_open_hatch") != null and _key_pattern.search("CL_SBY_BRIEFING_TITLE") != null, "sanity: the leak scan catches sandbox-2 ids and keys")
	var primary: Array = _record_route({})
	var alternate: Array = _record_route({"b_paths": {S.B2_2: 1}, "timeline": "alternate", "optional_lies": true})
	_check(not primary.is_empty() and not alternate.is_empty() and primary != alternate, "the simulator recorded two different legal routes to replay")
	save_manager.delete_save()
	locale_manager.set_locale("vi")

	await _test_release_title_has_no_selector()
	await _test_selector_collapses_with_one_entry()
	await _test_select_second_sandbox_and_start()
	await _replay(primary, "vi", true)
	await _test_result_restart_and_debugger()
	locale_manager.set_locale("en")
	await _replay(alternate, "en", false)
	await _test_menu_continue_and_replace_with_other_sandbox()

	save_manager.delete_save()
	locale_manager.set_locale("vi")
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


## Plays sandbox 2 once through the API-level simulator and returns its
## route log (location/interaction/command steps, content ids only).
func _record_route(options: Dictionary) -> Array:
	var support := CoreLoopTestSupport.new(self)
	var runtime: RefCounted = support.new_runtime("record")
	var result: Dictionary = CoreLoopRouteSimulator.new(self).run(S.CASE_2, runtime, options)
	runtime.detach()
	_check(result.get("ok", false), "the route to replay is legal: %s" % result.get("failure", ""))
	return result.get("route", [])


# ---------------------------------------------------------------------------
# Title screen

func _open_title(selector_enabled: bool = true) -> Control:
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	var title: Control = (load("res://scenes/main/TitleScreen.tscn") as PackedScene).instantiate()
	title.sandbox_selector_enabled = selector_enabled
	get_root().add_child(title)
	current_scene = title
	await process_frame
	return title


func _test_release_title_has_no_selector() -> void:
	var title: Control = await _open_title(false)
	_check(not (title.get_node("%SandboxPanel") as Control).visible and title.get_node("%SandboxList").get_child_count() == 0, "a release build shows no Technical Sandbox selector")
	_check((title.get_node("%ContinueButton") as Button).disabled, "no save: Continue disabled")


func _test_selector_collapses_with_one_entry() -> void:
	var cases: Dictionary = content_db.get_all_cases()
	var selection: Dictionary = cases[S.CASE_2]["sandbox_selection"]
	(cases[S.CASE_2] as Dictionary).erase("sandbox_selection")
	var title: Control = await _open_title()
	_check(not (title.get_node("%SandboxPanel") as Control).visible, "with only one selectable sandbox the selector collapses")
	cases[S.CASE_2]["sandbox_selection"] = selection


func _test_select_second_sandbox_and_start() -> void:
	var title: Control = await _open_title()
	var panel: Control = title.get_node("%SandboxPanel")
	_check(panel.visible and title.get_node("%SandboxList").get_child_count() == 2, "a debug build lists both selectable sandboxes")
	var first: Button = title.get_node("%SandboxList").get_child(0)
	var second: Button = title.get_node("%SandboxList").get_child(1)
	_check(first.text == "● " + TranslationServer.translate("CASE_SBX_ARCHIVE_NAME") and second.text == "○ " + TranslationServer.translate("CASE_SBY_LAB_NAME"), "entries show their localized names in content order, the selected one marked: %s / %s" % [first.text, second.text])
	_check(first.button_pressed and not second.button_pressed, "the release New Game default is preselected")
	_check((title.get_node("%SandboxSummary") as Label).text == TranslationServer.translate("CASE_SBX_ARCHIVE_DESC"), "the selected sandbox's description is shown")
	_click_visible(second)
	_check(second.button_pressed and second.text.begins_with("● ") and first.text.begins_with("○ ") and (title.get_node("%SandboxSummary") as Label).text == TranslationServer.translate("CASE_SBY_LAB_DESC"), "picking the second sandbox selects (and marks) it and shows its description")
	_scan_texts(_texts(title), "title with selector (vi)")
	_click_visible(title.get_node("%NewGameButton"))
	await _await_scene_change()
	main = current_scene as Control
	_check(main != null and main.name == "Main", "New Game runs the normal gameplay scene")
	var runtime: RefCounted = main.get_runtime()
	_check(runtime.get_chapter_id() == S.CHAPTER_2 and runtime.is_briefing() and _screen("BriefingScreen").visible, "the SECOND sandbox starts, in its briefing — through the ordinary New Game route")
	_check(not main.get_node("%DebugPanel").visible, "no F1 / Case Debugger involved")


# ---------------------------------------------------------------------------
# Replaying a recorded route through the real UI

## Replays `route` through visible, enabled controls only. With `quit_mid`
## it quits to the title inside the two-round confrontation (after round 1)
## and resumes with Continue.
func _replay(route: Array, locale: String, quit_mid: bool) -> void:
	var quit_done := false
	var opened_via_case_file := false
	for i in route.size():
		var step: Dictionary = route[i]
		match str(step.get("kind", "")):
			"new_game":
				pass
			"briefing":
				_scan_visible("briefing (%s)" % locale)
				_click_visible(_screen("BriefingScreen").get_node("%ContinueButton"))
			"move":
				await _move_to(str(step["to"]))
			"examine":
				await _examine(str(step["location"]), str(step["point"]), step.get("choices", []))
				_scan_visible("investigation (%s)" % locale)
			"talk":
				await _talk(str(step["location"]), str(step["npc"]), str(step["topic"]), step.get("choices", []))
			"open":
				if _screen("MechanicScreen").visible:
					continue
				if not opened_via_case_file:
					opened_via_case_file = true
					_click_visible(main.get_node("%InvestigationView").get_node("%EvidenceButton"))
					var case_file: Control = _screen("CaseFile")
					_check(case_file.visible and case_file.get_node("%EvidenceList").get_child_count() > 0, "the Case File lists the acquired evidence (%s)" % locale)
					(case_file.get_node("%EvidenceList").get_child(0) as Button).pressed.emit()
					_check((case_file.get_node("%DetailText") as Label).text != "", "reading an item in the Case File shows its detail (%s)" % locale)
					_scan_visible("case file (%s)" % locale)
					_click_visible(case_file.get_node("%OpenUnitButton"))
				else:
					_click_visible(_screen("CoreLoopHud").get_node("%OpenUnitButton"))
				_check(_screen("MechanicScreen").visible and main.get_runtime().get_open_unit_id() == str(step["unit"]), "%s opens from normal gameplay (%s)" % [step["unit"], locale])
				_scan_visible("%s (%s)" % [step["unit"], locale])
			"command":
				await _command_through_ui(step, locale)
			"dismiss":
				var screen: Control = _screen("MechanicScreen")
				_check((screen.get_node("%FeedbackPanel") as Control).visible, "%s shows feedback before Continue (%s)" % [step["unit"], locale])
				_scan_visible("%s feedback (%s)" % [step["unit"], locale])
				_click_visible(screen.get_node("%ContinueButton"))
				if quit_mid and not quit_done and str(step["unit"]) == S.A1_2 and screen.visible:
					quit_done = true
					await _quit_and_continue(locale)
			"close":
				if _screen("MechanicScreen").visible:
					_click_visible(_screen("MechanicScreen").get_node("%ReturnButton"))
	_check(main.get_runtime().is_completed() and _screen("ResultScreen").visible, "the replayed route completes the chapter and opens the Result screen (%s)" % locale)
	_check(_screen("ResultScreen").get_node("%FindingsList").get_child_count() == 5, "the Result narrates all five findings (%s)" % locale)
	_scan_visible("result (%s)" % locale)
	if quit_mid:
		_check(quit_done, "the route was interrupted and resumed with Continue inside the confrontation")


func _command_through_ui(step: Dictionary, locale: String) -> void:
	var screen: Control = _screen("MechanicScreen")
	var unit_id: String = str(step["unit"])
	var controller: RefCounted = main.get_runtime().get_unit(unit_id).controller
	var args: Array = step.get("args", [])
	match str(step["command"]):
		"select_evidence":
			var handle: String = _handle(str(args[0]))
			if main.get_runtime().get_unit(unit_id).mechanic == "clue_connection":
				if not controller.get_selected_evidence_ids().has(str(args[0])):
					_press(screen, "Place_%s" % handle)
			elif controller.get_selected_evidence_id() != str(args[0]):
				_press(screen, "Choose_%s" % handle)
		"select_statement":
			_press(screen, "Statement_%d" % int(args[0]))
		"place_event":
			if controller.get_placement(str(args[0])) != str(args[1]):
				_press(screen, "Slot_%s_%s" % [_handle(str(args[0])), str(args[1]).replace(":", "")])
		"select_claim_answer":
			_press(screen, "VerdictImpossible" if args[0] == true else "VerdictFits")
		"select_claim_justification":
			_press(screen, "Support_%s" % _handle(str(args[0])))
		"commit_theory", "present_evidence", "submit_timeline", "submit_claim":
			if unit_id == S.A1_2 and str(step["command"]) == "present_evidence":
				await _check_confrontation_layout(screen, locale)
			_click_visible(screen.get_node("%PrimaryButton"))
		_:
			_check(false, "no UI mapping for command %s" % step["command"])


## The two-round confrontation carries the longest VI/EN text of the second
## sandbox: its commit and Continue stay in the fixed footer, inside 1280x720.
func _check_confrontation_layout(screen: Control, locale: String) -> void:
	await process_frame
	await process_frame
	var footer: Control = screen.get_node("%Footer")
	var body: Control = screen.get_node("%BodyScroll")
	var viewport := Rect2(Vector2.ZERO, get_root().get_visible_rect().size)
	for button_name in ["PrimaryButton", "ContinueButton"]:
		var button: Control = screen.get_node("%" + button_name)
		_check(footer.is_ancestor_of(button) and not body.is_ancestor_of(button), "%s is in the fixed footer (%s)" % [button_name, locale])
	_check(viewport.encloses((screen.get_node("%PrimaryButton") as Control).get_global_rect()), "the confrontation's Present button is inside the 1280x720 viewport (%s): %s in %s, footer %s, body %s, screen %s" % [locale, (screen.get_node("%PrimaryButton") as Control).get_global_rect(), viewport, footer.get_global_rect(), body.get_global_rect(), screen.get_global_rect()])


func _quit_and_continue(locale: String) -> void:
	var draft_round: int = main.get_runtime().get_unit(S.A1_2).controller.get_round_index()
	_click_visible(main.get_node("%InvestigationView").get_node("%MenuButton"))
	_click_visible(main.get_node("%GameMenu").get_node("%QuitButton"))
	await _await_scene_change()
	var title: Control = current_scene as Control
	_check(title.name == "TitleScreen" and not (title.get_node("%ContinueButton") as Button).disabled, "quitting mid-confrontation leaves a resumable save (%s)" % locale)
	_check((title.get_node("%SavedRunLabel") as Label).text.contains(TranslationServer.translate("CASE_SBY_LAB_NAME")), "the title screen names the saved sandbox run")
	_click_visible(title.get_node("%ContinueButton"))
	await _await_scene_change()
	main = current_scene as Control
	var runtime: RefCounted = main.get_runtime()
	_check(runtime.get_chapter_id() == S.CHAPTER_2 and _screen("MechanicScreen").visible and runtime.get_open_unit_id() == S.A1_2, "Continue resumes the SECOND sandbox with the confrontation open, without asking which sandbox")
	_check(runtime.get_unit(S.A1_2).controller.get_round_index() == draft_round, "the confrontation resumes in the same testimony round")


func _test_result_restart_and_debugger() -> void:
	# The Case Debugger's Core Loop tab — author-only, opened explicitly.
	var panel: Control = main.get_node("%DebugPanel")
	panel.open()
	var list: Node = panel.get_node("%CoreLoopList")
	var texts: Array[String] = []
	for child in list.get_children():
		texts.append((child as Label).text)
	var joined: String = "\n".join(PackedStringArray(texts))
	_check(joined.contains(S.CHAPTER_2) and joined.contains("[NOW] current phase: completed") and joined.contains("APPLIED"), "the Case Debugger's Core Loop tab reports the active (completed) run")
	panel.close()
	var lab: Control = panel.get("deduction_lab")
	_check(not lab.visible and (lab.get("_controller") as RefCounted).get_session() == null, "the Deduction Lab was never opened and never held a session on the production route")
	var result: Control = _screen("ResultScreen")
	var old_run: String = main.get_runtime().get_run_id()
	_click_visible(result.get_node("%RestartButton"))
	var dialog: ConfirmationDialog = result.get_node("%ConfirmDialog")
	_check(dialog.visible, "restart asks for confirmation")
	dialog.confirmed.emit()
	dialog.hide()
	await process_frame
	var runtime: RefCounted = main.get_runtime()
	_check(runtime.get_chapter_id() == S.CHAPTER_2 and runtime.is_briefing() and runtime.get_run_id() != old_run and game_state.evidence_inventory.is_empty(), "restart starts the SAME sandbox again as a clean run")


func _test_menu_continue_and_replace_with_other_sandbox() -> void:
	_click_visible(_screen("ResultScreen").get_node("%MenuButton"))
	await _await_scene_change()
	var title: Control = current_scene as Control
	_check(title.name == "TitleScreen" and (title.get_node("%SavedRunLabel") as Label).text.contains(TranslationServer.translate("CASE_SBY_LAB_NAME")), "Menu returns to the title, which names the completed sandbox-2 run")
	_click_visible(title.get_node("%ContinueButton"))
	await _await_scene_change()
	main = current_scene as Control
	_check(main.get_runtime().get_chapter_id() == S.CHAPTER_2 and main.get_runtime().is_completed() and _screen("ResultScreen").visible, "Continue on the completed sandbox-2 run reopens its Result screen")
	_click_visible(_screen("ResultScreen").get_node("%MenuButton"))
	await _await_scene_change()
	title = current_scene as Control
	# Now start the OTHER sandbox over the resumable save: confirmation first.
	_click_visible(title.get_node("%SandboxList").get_child(0))
	_click_visible(title.get_node("%NewGameButton"))
	var dialog: ConfirmationDialog = title.get_node("%ConfirmDialog")
	_check(dialog.visible and dialog.dialog_text.contains(TranslationServer.translate("CASE_SBX_ARCHIVE_NAME")), "starting another sandbox over a resumable save asks first, naming it: %s" % dialog.dialog_text)
	_check(save_manager.get_saved_case_id() == S.CASE_2, "nothing is replaced before confirming")
	dialog.confirmed.emit()
	dialog.hide()
	await _await_scene_change()
	main = current_scene as Control
	var runtime: RefCounted = main.get_runtime()
	_check(runtime.get_chapter_id() == S.CHAPTER_ID and runtime.is_briefing() and save_manager.get_saved_case_id() == S.CASE_ID, "confirming starts sandbox 1 as a clean replacement run")
	_check(game_state.evidence_inventory.is_empty() and runtime.get_findings().is_empty(), "nothing of sandbox 2 leaks into the replacement run")
	_scan_visible("sandbox 1 briefing after replacement (en)")


# ---------------------------------------------------------------------------
# Driving helpers — real controls only (shared shape with core_loop_scene_test.gd).

func _screen(node_name: String) -> Control:
	return main.get_node("%" + node_name) as Control


func _click_visible(node: Node) -> void:
	var button: Button = node as Button
	var clickable: bool = button != null and button.is_visible_in_tree() and not button.disabled
	_check(clickable, "button %s should be visible and enabled when pressed" % (node.name if node != null else "<null>"))
	if clickable:
		button.pressed.emit()


func _press(root: Node, node_name: String) -> void:
	var button: Button = root.find_child(node_name, true, false) as Button
	var clickable: bool = button != null and button.is_visible_in_tree() and not button.disabled
	_check(clickable, "button %s should exist, be visible and enabled" % node_name)
	if clickable:
		button.pressed.emit()


func _action_list() -> Node:
	return main.get_node("%InvestigationView").get_node("%ActionList")


func _press_action(label: String) -> bool:
	for child in _action_list().get_children():
		if child is Button and ((child as Button).text == label or (child as Button).text.begins_with(label)) and not (child as Button).disabled:
			(child as Button).pressed.emit()
			return true
	return false


func _to_main_list() -> void:
	for i in 3:
		if not _press_action(TranslationServer.translate("UI_BACK")):
			return


## Advances the dialogue through the DialogueBox's own mouse handler, picking
## the recorded choice buttons when choices are on screen.
func _finish_dialogue(choices: Array) -> void:
	var box: Control = main.get_node("%DialogueBox")
	var choices_box: Control = box.get_node("%ChoicesBox")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var queue: Array = choices.duplicate()
	var guard := 0
	if dialogue_manager.is_active:
		# Milestone 1.17 visual QA: the HUD used to draw under the translucent
		# dialogue panel, overlapping its text.
		_check(not _screen("CoreLoopHud").visible, "the core-loop HUD is hidden while a dialogue is on screen")
	while dialogue_manager.is_active and guard < 60:
		guard += 1
		if choices_box.visible and choices_box.get_child_count() > 0:
			var pick: int = int(queue.pop_front()) if not queue.is_empty() else 0
			_click_visible(choices_box.get_child(pick))
		else:
			box._gui_input(click)
		await process_frame


func _location() -> Dictionary:
	return content_db.get_location(game_state.current_location)


func _examine(location_id: String, point_id: String, choices: Array) -> void:
	_check(game_state.current_location == location_id, "the route examines where the player is (%s)" % location_id)
	var label: String = ""
	for point in _location().get("examine_points", []):
		if point.get("id", "") == point_id:
			label = str(point.get("label", ""))
	_to_main_list()
	_check(_press_action(TranslationServer.translate(label)), "examine %s is offered" % point_id)
	await _finish_dialogue(choices)
	_check(_screen("CoreLoopHud").visible, "the HUD is back once the dialogue ends")


func _talk(location_id: String, npc_id: String, topic_id: String, choices: Array) -> void:
	_check(game_state.current_location == location_id, "the route talks where the player is (%s)" % location_id)
	var label: String = ""
	for npc in _location().get("npcs", []):
		for topic in npc.get("topics", []):
			if npc.get("id", "") == npc_id and topic.get("id", "") == topic_id:
				label = str(topic.get("label", ""))
	_to_main_list()
	_check(_press_action(TranslationServer.translate(str(content_db.get_character(npc_id).get("name", "")))), "%s is present" % npc_id)
	_press_action(TranslationServer.translate("UI_TALK"))
	_check(_press_action(TranslationServer.translate(label)), "topic %s/%s is offered" % [npc_id, topic_id])
	await _finish_dialogue(choices)
	_to_main_list()


func _move_to(location_id: String) -> void:
	var label: String = ""
	for destination in _location().get("destinations", []):
		if destination.get("location_id", "") == location_id:
			label = str(destination.get("label", ""))
	_to_main_list()
	_press_action(TranslationServer.translate("UI_GO_SOMEWHERE_ELSE"))
	_check(_press_action(TranslationServer.translate(label)), "the way to %s is offered" % location_id)
	await process_frame
	_check(game_state.current_location == location_id, "moved to %s" % location_id)


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


func _scan_texts(texts: Array[String], context: String) -> void:
	var leaks: Array[String] = []
	for text in texts:
		if _id_pattern.search(text) != null or _key_pattern.search(text) != null:
			leaks.append(text)
	_check(leaks.is_empty(), "%s: no ids or untranslated keys on screen: %s" % [context, leaks])


func _scan_visible(context: String) -> void:
	_scan_texts(_texts(main), context)
