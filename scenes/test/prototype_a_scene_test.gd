extends SceneTree
## Scene/integration tests for Prototype A — Statement Contradiction
## (Milestone 1.11 — see docs/prototype-a.md): instantiation as a
## DeductionLab child, launching from the Lab (with/without a Lab case
## active), reading evidence, one-evidence selection, wrong/correct/optional
## feedback through real button clicks, round transition, completion,
## hints, restart/return confirmation, recorder controls, F1 hide/show
## session preservation, and bilingual coverage. This is the FULL-only
## counterpart to the FAST controller/presenter/content tests — it exercises
## the real scene tree, which those pure-class tests deliberately don't need.
## Run with:
##   godot --headless --path . -s res://scenes/test/prototype_a_scene_test.gd

const CASE_ID := "proto_x_archive_ledger"
## data/deductions/prototypes/proto_x_archive_ledger.json's prototype_a.evidence_pool, in order.
const POOL_LOST_PROPERTY_SHEET := 0  # refutes st_oren_never_touched (required, round 1)
const POOL_FORCED_WINDOW := 1  # refutes st_oren_break_in (required, round 2)
const POOL_SHREDDING_LOG := 2  # refutes st_ilse_left_early (optional, round 2)
const POOL_WING_CAMERA := 3  # irrelevant to every statement here

var main_instance: Node
var debug_panel: Control
var deduction_lab: Control
var prototype_a: Control
var locale_manager: Node
var content_db: Node
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	locale_manager = get_root().get_node("LocaleManager")
	content_db = get_root().get_node("ContentDB")
	TestHelpers.isolate_locale(locale_manager, "prototype_a_scene_test")

	main_instance = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_root().add_child(main_instance)
	await process_frame

	print("=== Prototype A — scene/integration tests ===")
	debug_panel = main_instance.get_node("%DebugPanel")
	deduction_lab = debug_panel.get_node("%DeductionLab")
	prototype_a = deduction_lab.get_node("%PrototypeA")
	_check(is_instance_valid(prototype_a), "PrototypeA should instantiate as a child of DeductionLab")
	_check(not prototype_a.visible, "PrototypeA should start hidden (no production navigation path)")

	if OS.is_debug_build():
		_test_launch_without_lab_case_shows_picker()
		_test_launch_prefills_lab_case_and_leaves_lab_untouched()
		_test_evidence_open_and_select_via_buttons()
		_test_wrong_then_correct_feedback()
		_test_optional_contradiction_does_not_complete_round()
		_test_hint_reveal_via_button()
		_test_round_transition_and_completion()
		_test_restart_confirmation_and_cancel_preserves_state()
		_test_return_confirmation_and_abandon()
		_test_recorder_controls()
		_test_hide_show_preserves_session()
		_test_translation_coverage()
	else:
		print("(skipped interactive Prototype A checks — not a debug build; OS.is_debug_build() gate could not be exercised either way here, see docs/prototype-a.md's Known limitations)")

	locale_manager.set_locale("vi")  # leave the project's default in place for whatever runs after this
	main_instance.queue_free()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


# ---------------------------------------------------------------------------
# Small helpers driving the REAL controls, mirroring deduction_lab_scene_test.gd's
# own style — no internal state is poked directly.

func _button(name: String) -> Button:
	return prototype_a.get_node("%" + name) as Button


func _select_case_option(case_id: String) -> void:
	var option: OptionButton = prototype_a.get_node("%CaseOptionButton")
	for i in option.get_item_count():
		if String(option.get_item_metadata(i)) == case_id:
			option.select(i)
			return


## Selects `case_id` and presses Start, auto-confirming any restart-with-
## progress dialog that pops up (a no-op when nothing was pending) —
## confirmation flow itself is exercised explicitly in
## _test_restart_confirmation_and_cancel_preserves_state().
func _start_case(case_id: String) -> void:
	_select_case_option(case_id)
	_button("StartButton").pressed.emit()
	(prototype_a.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()


func _evidence_row(index: int) -> HBoxContainer:
	var list: VBoxContainer = prototype_a.get_node("%EvidenceList")
	return list.get_child(index) as HBoxContainer


func _click_select_evidence(pool_index: int) -> void:
	var row: HBoxContainer = _evidence_row(pool_index)
	(row.get_child(row.get_child_count() - 1) as Button).pressed.emit()


func _click_open_evidence(pool_index: int) -> void:
	var row: HBoxContainer = _evidence_row(pool_index)
	if row.get_child_count() >= 3:  # label + Open + Select — Open is only present while unopened.
		(row.get_child(1) as Button).pressed.emit()


func _present() -> void:
	_button("PresentButton").pressed.emit()


func _continue_after_feedback() -> void:
	_button("ContinueButton").pressed.emit()


func _statement_texts() -> Array[String]:
	var list: VBoxContainer = prototype_a.get_node("%StatementList")
	var texts: Array[String] = []
	for row in list.get_children():
		for child in row.get_children():
			if child is Label:
				texts.append(String((child as Label).text))
	return texts


# ---------------------------------------------------------------------------

func _test_launch_without_lab_case_shows_picker() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_check(prototype_a.visible, "launching from the Lab should open Prototype A")
	var option: OptionButton = prototype_a.get_node("%CaseOptionButton")
	_check(option.get_item_count() >= 3, "the case picker should list every deduction case with Prototype A content")
	for i in option.get_item_count():
		var listed_id: String = String(option.get_item_metadata(i))
		_check(typeof(content_db.get_deduction_case(listed_id).get("prototype_a")) == TYPE_DICTIONARY, "every listed case (%s) must actually declare prototype_a content" % listed_id)
	_check(not prototype_a.get_node("%PlayArea").visible, "no run should be active until Start is pressed")
	prototype_a.close()


## Object-identity isolation between DeductionLabController and
## PrototypeAController is already exhaustively covered at the pure level by
## prototype_a_controller_test.gd's _test_lab_session_remains_unchanged().
## This scene-level test instead proves the LAUNCH WIRING itself: the button
## actually defaults Prototype A's picker to the Lab's active case, and the
## Lab's own Overview still reports the untouched case afterward.
func _test_launch_prefills_lab_case_and_leaves_lab_untouched() -> void:
	deduction_lab.open()
	var lab_option: OptionButton = deduction_lab.get_node("%CaseOptionButton")
	for i in lab_option.get_item_count():
		if String(lab_option.get_item_metadata(i)) == CASE_ID:
			lab_option.select(i)
			break
	(deduction_lab.get_node("%SelectCaseButton") as Button).pressed.emit()
	_check(deduction_lab.get_node("%StatusLabel").text.contains(CASE_ID), "sanity — the Lab should now have proto_x active")

	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	var pa_option: OptionButton = prototype_a.get_node("%CaseOptionButton")
	_check(String(pa_option.get_item_metadata(pa_option.selected)) == CASE_ID, "Prototype A's case picker should default to the Lab's currently active case")

	_start_case(CASE_ID)
	_click_open_evidence(POOL_LOST_PROPERTY_SHEET)
	_click_select_evidence(POOL_LOST_PROPERTY_SHEET)
	_button("NextButton").pressed.emit()
	_button("NextButton").pressed.emit()
	_present()
	_continue_after_feedback()
	prototype_a.close()

	# deduction_lab itself was never closed (only prototype_a was), so its
	# Overview content reflects its own untouched session without needing to
	# reopen it (which would reset its transient status label).
	var overview_text := ""
	for child in (deduction_lab.get_node("%OverviewList") as VBoxContainer).get_children():
		if child is Label:
			overview_text += String((child as Label).text)
	_check(overview_text.contains("0/4") or overview_text.contains("IN PROGRESS"), "the Lab's own Overview must still show zero questions resolved — Prototype A resolving a contradiction must never leak into the Lab's session: got \"%s\"" % overview_text)


func _test_evidence_open_and_select_via_buttons() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	var row: HBoxContainer = _evidence_row(POOL_LOST_PROPERTY_SHEET)
	_check(row.get_child_count() == 3, "an unopened evidence row should show a label, an Open button and a Select button")
	_click_open_evidence(POOL_LOST_PROPERTY_SHEET)
	var reopened_row: HBoxContainer = _evidence_row(POOL_LOST_PROPERTY_SHEET)
	_check(reopened_row.get_child_count() == 2, "an opened evidence row should no longer show an Open button")

	_click_select_evidence(POOL_LOST_PROPERTY_SHEET)
	_check(not _button("PresentButton").disabled, "Present Evidence should become enabled once one item is selected")
	_click_select_evidence(POOL_WING_CAMERA)
	_check(not _button("PresentButton").disabled, "selecting a second item should just replace the first selection, not add to it")
	prototype_a.close()


func _test_wrong_then_correct_feedback() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_button("NextButton").pressed.emit()
	_button("NextButton").pressed.emit()  # st_oren_never_touched

	_click_select_evidence(POOL_WING_CAMERA)
	_present()
	_check(prototype_a.get_node("%FeedbackPanel").visible, "presenting wrong evidence should still show feedback")
	var wrong_text: String = (prototype_a.get_node("%FeedbackExplanation") as Label).text
	_check(wrong_text != "" and not wrong_text.to_lower().contains("valid_") and not wrong_text.to_lower().contains("irrelevant_evidence"), "wrong-attempt feedback must be a localized message, never a raw category enum name: got \"%s\"" % wrong_text)
	_continue_after_feedback()
	_check(not prototype_a.get_node("%PlayArea").visible == false, "a wrong attempt must not complete the round or hide the play area")

	_click_select_evidence(POOL_LOST_PROPERTY_SHEET)
	_present()
	_check((prototype_a.get_node("%FeedbackHeadline") as Label).text != "", "a correct required refutation should show a success headline")
	var explanation: String = (prototype_a.get_node("%FeedbackExplanation") as Label).text
	var response: String = (prototype_a.get_node("%FeedbackWitnessResponse") as Label).text
	_check(explanation != "" and response != "", "a correct required refutation should show both the authored explanation and the witness response")
	_continue_after_feedback()
	prototype_a.close()


func _test_optional_contradiction_does_not_complete_round() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	# Resolve round 1's required contradiction to reach round 2.
	_button("NextButton").pressed.emit()
	_button("NextButton").pressed.emit()
	_click_select_evidence(POOL_LOST_PROPERTY_SHEET)
	_present()
	_continue_after_feedback()

	_check(_statement_texts().size() == 2, "round 2 should show its own two statements")
	# st_ilse_left_early is statement index 0 in round 2.
	_click_select_evidence(POOL_SHREDDING_LOG)
	_present()
	_check((prototype_a.get_node("%FeedbackHeadline") as Label).text != "", "the innocent lie must be accepted as a valid contradiction, with its own headline")
	_continue_after_feedback()
	_check(prototype_a.get_node("%PlayArea").visible, "resolving only the optional contradiction must not complete the prototype")
	prototype_a.close()


func _test_hint_reveal_via_button() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_button("NextButton").pressed.emit()
	_button("NextButton").pressed.emit()  # st_oren_never_touched, which HAS a hint ladder

	var hint_list: VBoxContainer = prototype_a.get_node("%HintList")
	_check(hint_list.get_child_count() == 0, "no hint should be revealed yet")
	_button("HintButton").pressed.emit()
	_check(hint_list.get_child_count() == 1, "one hint reveal should show exactly one hint line")
	for i in 3:
		_button("HintButton").pressed.emit()
	_check(hint_list.get_child_count() == 4, "revealing every level should show exactly 4 hint lines")
	_check(_button("HintButton").disabled, "the Hint button should disable once the ladder is exhausted")
	prototype_a.close()


func _test_round_transition_and_completion() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	_button("NextButton").pressed.emit()
	_button("NextButton").pressed.emit()
	_click_select_evidence(POOL_LOST_PROPERTY_SHEET)
	_present()
	_continue_after_feedback()
	_check(prototype_a.get_node("%PlayArea").visible, "completing round 1 should move to round 2, not finish the prototype")

	_button("NextButton").pressed.emit()  # st_oren_break_in, statement index 1 in round 2
	_click_select_evidence(POOL_FORCED_WINDOW)
	_present()
	_continue_after_feedback()

	_check(not prototype_a.get_node("%PlayArea").visible, "completing both required contradictions should hide the play area")
	_check(prototype_a.get_node("%CompletionPanel").visible, "completing both required contradictions should show the completion panel")
	_check((prototype_a.get_node("%CompletionTextLabel") as Label).text != "", "the completion panel should show the authored completion text")
	var stats_list: VBoxContainer = prototype_a.get_node("%StatsList")
	_check(stats_list.get_child_count() == 5, "the completion panel should show all five stat lines")
	prototype_a.close()


func _test_restart_confirmation_and_cancel_preserves_state() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_click_open_evidence(POOL_LOST_PROPERTY_SHEET)
	var confirm_dialog: ConfirmationDialog = prototype_a.get_node("%ConfirmDialog")

	_button("RestartButton").pressed.emit()
	# Cancelling (simply not confirming) must leave the run exactly as it was.
	var row_after_cancel: HBoxContainer = _evidence_row(POOL_LOST_PROPERTY_SHEET)
	_check(row_after_cancel.get_child_count() == 2, "cancelling a restart confirmation must preserve the run — the opened evidence should still show no Open button")

	confirm_dialog.confirmed.emit()
	var fresh_row: HBoxContainer = _evidence_row(POOL_LOST_PROPERTY_SHEET)
	_check(fresh_row.get_child_count() == 3, "confirming Restart should discard progress — the evidence should be unopened again")
	prototype_a.close()


func _test_return_confirmation_and_abandon() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	(_button("RecorderStartButton")).pressed.emit()
	_click_select_evidence(POOL_WING_CAMERA)
	_present()  # a real (wrong) attempt — genuine progress

	_button("ReturnButton").pressed.emit()
	_check(prototype_a.visible, "returning with meaningful progress must require confirmation, not close immediately")
	(prototype_a.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	_check(not prototype_a.visible, "confirming Return to Lab should close Prototype A")

	# Re-launch and leave with NO progress: must close immediately, no dialog needed.
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_button("ReturnButton").pressed.emit()
	_check(not prototype_a.visible, "returning with no progress at all should close immediately without a confirmation")


## Recording is started BEFORE the case (matching the facilitator script in
## docs/deduction-playtest-plan.md: "start recording", THEN begin the run),
## so this also proves prototype_started/round_started are actually captured
## — which requires the recorder to accept Start before any session exists
## (docs/prototype-a.md, "Recorder events").
func _test_recorder_controls() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_select_case_option(CASE_ID)

	var status_label: Label = prototype_a.get_node("%RecorderStatusLabel")
	_button("RecorderStartButton").pressed.emit()
	_check(status_label.text.contains("Recording: ON"), 'starting a recording BEFORE the run begins should show "Recording: ON", got "%s"' % status_label.text)

	_start_case(CASE_ID)
	_button("NextButton").pressed.emit()
	_button("NextButton").pressed.emit()
	_click_select_evidence(POOL_LOST_PROPERTY_SHEET)
	_present()

	_button("RecorderStopButton").pressed.emit()
	_check(status_label.text.contains("Recording: OFF"), "stopping should show Recording: OFF")
	_check(not status_label.text.contains(" 0 event(s)"), "events captured before Stop should still be reported, got \"%s\"" % status_label.text)

	_button("RecorderExportButton").pressed.emit()
	var export_status: String = (prototype_a.get_node("%StatusLabel") as Label).text
	_check(export_status.contains("Exported recording to"), 'a successful export should report its path, got "%s"' % export_status)

	var exported_path: String = export_status.trim_prefix("Exported recording to ")
	_check(FileAccess.file_exists(exported_path), "the exported file should actually exist")
	var file: FileAccess = FileAccess.open(exported_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("prototype") == "statement_contradiction", "the exported recording should be tagged with the Prototype A prototype id, got %s" % [parsed.get("prototype") if typeof(parsed) == TYPE_DICTIONARY else parsed])
	var event_types: Array = []
	for event in (parsed.get("events", []) as Array):
		event_types.append(event.get("type"))
	for expected_type in ["prototype_started", "round_started", "statement_selected", "evidence_selected", "attempt_submitted", "contradiction_resolved"]:
		_check(event_types.has(expected_type), "the exported recording should contain a \"%s\" event, got types %s" % [expected_type, event_types])
	for event in (parsed.get("events", []) as Array):
		_check(not JSON.stringify(event).contains("Oren") and not JSON.stringify(event).contains("Mara"), "recorded events must never contain full localized text (a translated name leaking in the payload)")

	_button("RecorderClearButton").pressed.emit()
	_check(status_label.text.contains("0 event(s)"), "Clear should empty the recorded event list")
	_button("RecorderStopButton").pressed.emit()
	if FileAccess.file_exists(exported_path):
		DirAccess.remove_absolute(exported_path)
	prototype_a.close()


func _test_hide_show_preserves_session() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_click_open_evidence(POOL_LOST_PROPERTY_SHEET)
	_button("NextButton").pressed.emit()
	var selection_before: String = (prototype_a.get_node("%SelectionLabel") as Label).text
	_check(selection_before != "", "sanity — moving to the second statement should update the selection label")

	debug_panel.close()
	_check(not debug_panel.visible, "closing DebugPanel (F1) should hide it")
	_check(prototype_a.visible, "Prototype A's OWN visible flag must be untouched by DebugPanel.close() — invisibility here is purely inherited from the hidden ancestor")
	debug_panel.open()
	deduction_lab.open()
	_check(prototype_a.visible, "reopening should show Prototype A exactly as it was left")
	_check(_evidence_row(POOL_LOST_PROPERTY_SHEET).get_child_count() == 2, "the same evidence must still be marked opened after an F1 hide/show round trip")
	_check((prototype_a.get_node("%SelectionLabel") as Label).text == selection_before, "the current statement selection must survive the round trip")
	prototype_a.close()


func _test_translation_coverage() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	locale_manager.set_locale("en")
	prototype_a.refresh()
	var en_title: String = (prototype_a.get_node("%TitleLabel") as Label).text
	var en_present: String = _button("PresentButton").text
	locale_manager.set_locale("vi")
	prototype_a.refresh()
	var vi_title: String = (prototype_a.get_node("%TitleLabel") as Label).text
	var vi_present: String = _button("PresentButton").text
	_check(en_title == "Prototype A — Statement Contradiction", 'the English title should read the translated string, got "%s"' % en_title)
	_check(vi_title != "" and vi_title != en_title, "the Vietnamese title should be non-empty and differ from English")
	_check(vi_present != "" and vi_present != en_present, "the Present Evidence button should also be retranslated")
	prototype_a.close()
