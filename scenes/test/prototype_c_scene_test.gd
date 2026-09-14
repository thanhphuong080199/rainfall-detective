extends SceneTree
## Scene/integration tests for Prototype C — Timeline Reconstruction
## (Milestone 1.13 — see docs/prototype-c.md): instantiation as a
## DeductionLab child, launching from the Lab (with/without an active Lab
## case, leaving the Lab/Prototype A/Prototype B untouched), fixed events
## shown locked, selecting/placing/moving/removing movable events via real
## buttons, Check disabled until complete, invalid submission with retained
## placements and violation feedback, an alternate valid timeline, hints, the
## final claim check (wrong then correct), completion, restart/return
## confirmation, recorder controls, F1 hide/show session preservation,
## bilingual coverage, all three cases, and the Milestone 1.12 long-feedback
## layout regression applied to this scene too. This is the FULL-only
## counterpart to the FAST controller/presenter/content tests — it exercises
## the real scene tree, which those pure-class tests deliberately don't need.
## Run with:
##   godot --headless --path . -s res://scenes/test/prototype_c_scene_test.gd

const CASE_ID := "proto_x_archive_ledger"
## data/deductions/prototypes/proto_x_archive_ledger.json's timeline.events
## order (also prototype_c.gd's %EventsList/get_all_event_ids() order).
const IDX_MARA_LEAVES := 0
const IDX_CARDIGAN_TAKEN := 1
const IDX_MARA_TRAM_TAP := 2  # fixed
const IDX_BADGE_USED := 3  # fixed
const IDX_WINDOW_FORCED := 4
const IDX_SHREDDING_PICKUP := 5
const IDX_CARDIGAN_RETURNED := 6

const SOLUTION := {
	IDX_MARA_LEAVES: "19:35", IDX_CARDIGAN_TAKEN: "19:48", IDX_WINDOW_FORCED: "20:08",
	IDX_SHREDDING_PICKUP: "20:10", IDX_CARDIGAN_RETURNED: "20:14",
}
const ALTERNATE := {
	IDX_MARA_LEAVES: "19:25", IDX_CARDIGAN_TAKEN: "19:48", IDX_WINDOW_FORCED: "20:08",
	IDX_SHREDDING_PICKUP: "20:10", IDX_CARDIGAN_RETURNED: "20:14",
}

var main_instance: Node
var debug_panel: Control
var deduction_lab: Control
var prototype_a: Control
var prototype_b: Control
var prototype_c: Control
var locale_manager: Node
var content_db: Node
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	locale_manager = get_root().get_node("LocaleManager")
	content_db = get_root().get_node("ContentDB")
	TestHelpers.isolate_locale(locale_manager, "prototype_c_scene_test")

	main_instance = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_root().add_child(main_instance)
	await process_frame

	print("=== Prototype C — scene/integration tests ===")
	debug_panel = main_instance.get_node("%DebugPanel")
	deduction_lab = debug_panel.get_node("%DeductionLab")
	prototype_a = deduction_lab.get_node("%PrototypeA")
	prototype_b = deduction_lab.get_node("%PrototypeB")
	prototype_c = deduction_lab.get_node("%PrototypeC")
	_check(is_instance_valid(prototype_c), "PrototypeC should instantiate as a child of DeductionLab")
	_check(not prototype_c.visible, "PrototypeC should start hidden (no production navigation path)")

	if OS.is_debug_build():
		_test_launch_without_lab_case_shows_picker()
		_test_launch_prefills_lab_case_and_leaves_others_untouched()
		_test_fixed_events_shown_locked()
		_test_select_place_move_remove_via_buttons()
		_test_check_disabled_until_complete_then_invalid_then_retained()
		_test_alternate_valid_timeline_accepted()
		_test_fact_inspection_via_button()
		_test_hint_reveal_via_button()
		_test_claim_wrong_then_correct_then_completes()
		_test_restart_confirmation_and_cancel_preserves_state()
		_test_return_confirmation_and_abandon()
		_test_recorder_controls()
		_test_hide_show_preserves_session()
		_test_translation_coverage()
		_test_all_three_cases_launch_and_accept_solution()
		_test_continue_button_stays_reachable_with_long_feedback()
	else:
		print("(skipped interactive Prototype C checks — not a debug build; OS.is_debug_build() gate could not be exercised either way here, see docs/prototype-c.md's Known limitations)")

	locale_manager.set_locale("vi")  # leave the project's default in place for whatever runs after this
	main_instance.queue_free()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


# ---------------------------------------------------------------------------
# Small helpers driving the REAL controls, mirroring prototype_b_scene_test.gd's
# own style — no internal state is poked directly.

func _button(name: String) -> Button:
	return prototype_c.get_node("%" + name) as Button


func _select_case_option(case_id: String) -> void:
	var option: OptionButton = prototype_c.get_node("%CaseOptionButton")
	for i in option.get_item_count():
		if String(option.get_item_metadata(i)) == case_id:
			option.select(i)
			return


func _start_case(case_id: String) -> void:
	_select_case_option(case_id)
	_button("StartButton").pressed.emit()
	(prototype_c.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()


func _events_row(index: int) -> HBoxContainer:
	var list: VBoxContainer = prototype_c.get_node("%EventsList")
	return list.get_child(index) as HBoxContainer


func _click_select(index: int) -> void:
	var row: HBoxContainer = _events_row(index)
	(row.get_child(1) as Button).pressed.emit()  # [label, Select, (Remove)?]


func _click_remove_in_events(index: int) -> void:
	var row: HBoxContainer = _events_row(index)
	_check(row.get_child_count() == 3, "removing via the events list requires the row to already show a Remove button")
	(row.get_child(2) as Button).pressed.emit()


func _timeline_row_for_slot(time_slot: String) -> HBoxContainer:
	var list: VBoxContainer = prototype_c.get_node("%TimelineList")
	for child in list.get_children():
		var row := child as HBoxContainer
		if (row.get_child(0) as Label).text.begins_with(time_slot):
			return row
	return null


func _click_place_here(time_slot: String) -> void:
	var row: HBoxContainer = _timeline_row_for_slot(time_slot)
	_check(row != null, "there should be a timeline row for slot %s" % time_slot)
	_check(row.get_child_count() >= 2, "a Place Here button should be visible while an event is selected")
	(row.get_child(1) as Button).pressed.emit()


func _select_and_place(event_index: int, time_slot: String) -> void:
	_click_select(event_index)
	_click_place_here(time_slot)


func _place_placement(placement: Dictionary) -> void:
	for event_index in placement:
		_select_and_place(int(event_index), String(placement[event_index]))


func _check_timeline() -> void:
	_button("CheckButton").pressed.emit()


func _continue_after_feedback() -> void:
	_button("ContinueButton").pressed.emit()


func _hint() -> void:
	_button("HintButton").pressed.emit()


func _facts_row(index: int) -> HBoxContainer:
	var list: VBoxContainer = prototype_c.get_node("%FactsList")
	return list.get_child(index) as HBoxContainer


# ---------------------------------------------------------------------------

func _test_launch_without_lab_case_shows_picker() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_check(prototype_c.visible, "launching from the Lab should open Prototype C")
	var option: OptionButton = prototype_c.get_node("%CaseOptionButton")
	_check(option.get_item_count() >= 3, "the case picker should list every deduction case with Prototype C content")
	for i in option.get_item_count():
		var listed_id: String = String(option.get_item_metadata(i))
		_check(typeof(content_db.get_deduction_case(listed_id).get("prototype_c")) == TYPE_DICTIONARY, "every listed case (%s) must actually declare prototype_c content" % listed_id)
	_check(not prototype_c.get_node("%PlayArea").visible, "no run should be active until Start is pressed")
	prototype_c.close()


func _test_launch_prefills_lab_case_and_leaves_others_untouched() -> void:
	deduction_lab.open()
	var lab_option: OptionButton = deduction_lab.get_node("%CaseOptionButton")
	for i in lab_option.get_item_count():
		if String(lab_option.get_item_metadata(i)) == CASE_ID:
			lab_option.select(i)
			break
	(deduction_lab.get_node("%SelectCaseButton") as Button).pressed.emit()
	_check(deduction_lab.get_node("%StatusLabel").text.contains(CASE_ID), "sanity — the Lab should now have proto_x active")

	# Open Prototype A and Prototype B too, and give each a little real
	# progress, so we can prove launching Prototype C afterward leaves both
	# untouched (and closes both, avoiding two overlays at once).
	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	var pa_option: OptionButton = prototype_a.get_node("%CaseOptionButton")
	for i in pa_option.get_item_count():
		if String(pa_option.get_item_metadata(i)) == CASE_ID:
			pa_option.select(i)
			break
	(prototype_a.get_node("%StartButton") as Button).pressed.emit()
	(prototype_a.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	var pa_evidence_list: VBoxContainer = prototype_a.get_node("%EvidenceList")
	var pa_row: HBoxContainer = pa_evidence_list.get_child(0) as HBoxContainer
	(pa_row.get_child(1) as Button).pressed.emit()  # open the first evidence item

	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	var pb_option: OptionButton = prototype_b.get_node("%CaseOptionButton")
	for i in pb_option.get_item_count():
		if String(pb_option.get_item_metadata(i)) == CASE_ID:
			pb_option.select(i)
			break
	(prototype_b.get_node("%StartButton") as Button).pressed.emit()
	(prototype_b.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	var pb_evidence_list: VBoxContainer = prototype_b.get_node("%EvidenceList")
	var pb_row: HBoxContainer = pb_evidence_list.get_child(0) as HBoxContainer
	(pb_row.get_child(pb_row.get_child_count() - 1) as Button).pressed.emit()  # place the first evidence item

	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_check(not prototype_a.visible and not prototype_b.visible, "launching Prototype C should hide Prototype A and Prototype B (avoid overlapping overlays), never reset either")
	var pc_option: OptionButton = prototype_c.get_node("%CaseOptionButton")
	_check(String(pc_option.get_item_metadata(pc_option.selected)) == CASE_ID, "Prototype C's case picker should default to the Lab's currently active case")
	_start_case(CASE_ID)
	prototype_c.close()

	_check((prototype_a.get_node("%EvidenceList") as VBoxContainer).get_child(0).get_child_count() == 2, "Prototype A's own progress (its first evidence item opened) must survive a Prototype C run untouched")
	var pb_row_after: HBoxContainer = pb_evidence_list.get_child(0) as HBoxContainer
	var pb_toggle_after: Button = pb_row_after.get_child(pb_row_after.get_child_count() - 1) as Button
	_check(pb_toggle_after.text == String(TranslationServer.translate("UI_PROTOTYPE_B_REMOVE_BUTTON")), "Prototype B's own progress (its first clue placed) must survive a Prototype C run untouched")


func _test_fixed_events_shown_locked() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	for fixed_index in [IDX_MARA_TRAM_TAP, IDX_BADGE_USED]:
		var row: HBoxContainer = _events_row(fixed_index)
		_check(row.get_child_count() == 1, "a fixed event's row should show only its label, no Select/Remove buttons")
	prototype_c.close()


func _test_select_place_move_remove_via_buttons() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	var unplaced_row: HBoxContainer = _events_row(IDX_MARA_LEAVES)
	_check(unplaced_row.get_child_count() == 2, "an unplaced movable event's row should show a label and a Select button")

	_select_and_place(IDX_MARA_LEAVES, "19:25")
	var placed_row: HBoxContainer = _events_row(IDX_MARA_LEAVES)
	_check(placed_row.get_child_count() == 3, "a placed movable event's row should now also show a Remove button")
	_check((placed_row.get_child(0) as Label).text.contains("19:25"), "the row should show its current placement")

	_select_and_place(IDX_MARA_LEAVES, "19:35")  # move
	_check((_events_row(IDX_MARA_LEAVES).get_child(0) as Label).text.contains("19:35"), "re-selecting and placing at a different slot should move the event")

	_click_remove_in_events(IDX_MARA_LEAVES)
	_check(_events_row(IDX_MARA_LEAVES).get_child_count() == 2, "removing should return the row to its unplaced (Select-only) shape")
	prototype_c.close()


func _test_check_disabled_until_complete_then_invalid_then_retained() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	_check(_button("CheckButton").disabled, "Check Timeline must start disabled with nothing placed")
	_select_and_place(IDX_MARA_LEAVES, "19:25")
	_select_and_place(IDX_CARDIGAN_TAKEN, "19:48")
	_select_and_place(IDX_WINDOW_FORCED, "20:08")
	_select_and_place(IDX_SHREDDING_PICKUP, "20:10")
	_check(_button("CheckButton").disabled, "Check Timeline must stay disabled with one movable event still unplaced")

	# Deliberately wrong: park the cardigan-return event at an early slot
	# instead of its own required window.
	_select_and_place(IDX_CARDIGAN_RETURNED, "19:25")
	_check(not _button("CheckButton").disabled, "Check Timeline should enable once every event is placed, however wrong the combination")
	_check_timeline()
	_check(prototype_c.get_node("%FeedbackPanel").visible, "submitting an invalid timeline should still show feedback")
	var headline: String = (prototype_c.get_node("%FeedbackHeadline") as Label).text
	_check(headline != "" and not headline.to_lower().contains("timeline_inconsistent"), "rejection feedback must be a localized message, never a raw category enum name: got \"%s\"" % headline)
	var violations_list: VBoxContainer = prototype_c.get_node("%FeedbackViolationsList")
	_check(violations_list.get_child_count() >= 1, "at least one violated fact should be listed")
	_continue_after_feedback()
	_check(prototype_c.get_node("%PlayArea").visible, "an invalid timeline must not be accepted or complete the prototype")
	_check((_events_row(IDX_CARDIGAN_RETURNED).get_child(0) as Label).text.contains("19:25"), "a rejected submission must retain every placement exactly, so the player can revise")

	_check(_button("CheckButton").disabled, "identical resubmission must be disabled until a move is made")
	_select_and_place(IDX_CARDIGAN_RETURNED, "20:14")  # now fix it
	_check(not _button("CheckButton").disabled, "a real placement change must re-enable Check Timeline")
	_check_timeline()
	_check((prototype_c.get_node("%FeedbackHeadline") as Label).text != "", "the corrected, fully-valid timeline should be accepted")
	prototype_c.close()


func _test_alternate_valid_timeline_accepted() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_place_placement(ALTERNATE)
	_check_timeline()
	_check(prototype_c.get_node("%FeedbackPanel").visible, "the alternate valid timeline should be accepted too")
	_continue_after_feedback()
	_check(prototype_c.get_node("%ClaimPanel").visible, "accepting any valid timeline (not just the authored one) should enter the claim phase")
	prototype_c.close()


func _test_fact_inspection_via_button() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	var row: HBoxContainer = _facts_row(0)
	_check(row.get_child_count() == 2, "an unopened fact row should show a label and a View button")
	(row.get_child(1) as Button).pressed.emit()
	var opened_row: HBoxContainer = _facts_row(0)
	_check(opened_row.get_child_count() == 1, "an opened fact row should no longer show a View button")
	_check((opened_row.get_child(0) as Label).text != "", "an opened fact should show its text")
	prototype_c.close()


func _test_hint_reveal_via_button() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	var hint_list: VBoxContainer = prototype_c.get_node("%HintList")
	_check(hint_list.get_child_count() == 0, "no hint should be revealed yet")
	_hint()
	_check(hint_list.get_child_count() == 1, "one hint reveal should show exactly one hint line")
	for i in 3:
		_hint()
	_check(hint_list.get_child_count() == 4, "revealing every level should show exactly 4 hint lines")
	_check(_button("HintButton").disabled, "the Hint button should disable once the ladder is exhausted")
	prototype_c.close()


func _test_claim_wrong_then_correct_then_completes() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_place_placement(SOLUTION)
	_check_timeline()
	_continue_after_feedback()

	_check(prototype_c.get_node("%ClaimPanel").visible, "an accepted timeline should show the claim panel")
	var statement_label: Label = prototype_c.get_node("%ClaimStatementLabel")
	_check(statement_label.text != "", "the disputed statement should be shown")
	_check(not prototype_c.get_node("%ContinueButton").visible, "Continue must not be offered before the claim is answered")

	(_button("ClaimFitsButton")).pressed.emit()  # wrong
	var feedback_label: Label = prototype_c.get_node("%ClaimFeedbackLabel")
	_check(feedback_label.visible and feedback_label.text != "", "a wrong \"Fits\" answer should show non-spoiling guidance")
	_check(_button("ClaimFitsButton").visible, "the claim buttons should remain available after a wrong answer, so the player can try again")

	(_button("ClaimImpossibleButton")).pressed.emit()  # correct
	var resolution_label: Label = prototype_c.get_node("%ClaimResolutionLabel")
	_check(resolution_label.visible and resolution_label.text != "", "a correct \"Impossible\" answer should reveal the contradiction explanation")
	_check(resolution_label.text.contains("20:10"), "the explanation should interpolate the actual accepted time for the disputed event")
	_check(_button("ContinueButton").visible, "Continue should now be offered to finish the prototype")

	_continue_after_feedback()
	_check(not prototype_c.get_node("%ClaimPanel").visible, "completing should hide the claim panel")
	_check(prototype_c.get_node("%CompletionPanel").visible, "completing should show the completion panel")
	_check((prototype_c.get_node("%CompletionTextLabel") as Label).text != "", "the completion panel should show the authored completion text")
	var stats_list: VBoxContainer = prototype_c.get_node("%StatsList")
	_check(stats_list.get_child_count() == 7, "the completion panel should show all seven stat lines")
	prototype_c.close()


func _test_restart_confirmation_and_cancel_preserves_state() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_select_and_place(IDX_MARA_LEAVES, "19:25")
	var confirm_dialog: ConfirmationDialog = prototype_c.get_node("%ConfirmDialog")

	_button("RestartButton").pressed.emit()
	_check((_events_row(IDX_MARA_LEAVES).get_child(0) as Label).text.contains("19:25"), "cancelling a restart confirmation must preserve the run exactly")

	confirm_dialog.confirmed.emit()
	_check(_events_row(IDX_MARA_LEAVES).get_child_count() == 2, "confirming Restart should discard progress — the event should be unplaced again")
	prototype_c.close()


func _test_return_confirmation_and_abandon() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	(_button("RecorderStartButton")).pressed.emit()
	_select_and_place(IDX_MARA_LEAVES, "19:25")

	_button("ReturnButton").pressed.emit()
	_check(prototype_c.visible, "returning with meaningful progress must require confirmation, not close immediately")
	(prototype_c.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	_check(not prototype_c.visible, "confirming Return to Lab should close Prototype C")

	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_button("ReturnButton").pressed.emit()
	_check(not prototype_c.visible, "returning with no progress at all should close immediately without a confirmation")


func _test_recorder_controls() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_select_case_option(CASE_ID)

	var status_label: Label = prototype_c.get_node("%RecorderStatusLabel")
	_button("RecorderStartButton").pressed.emit()
	_check(status_label.text.contains("Recording: ON"), 'starting a recording BEFORE the run begins should show "Recording: ON", got "%s"' % status_label.text)

	_start_case(CASE_ID)
	_place_placement(SOLUTION)
	_check_timeline()

	_button("RecorderStopButton").pressed.emit()
	_check(status_label.text.contains("Recording: OFF"), "stopping should show Recording: OFF")
	_check(not status_label.text.contains(" 0 event(s)"), "events captured before Stop should still be reported, got \"%s\"" % status_label.text)

	_button("RecorderExportButton").pressed.emit()
	var export_status: String = (prototype_c.get_node("%StatusLabel") as Label).text
	_check(export_status.contains("Exported recording to"), 'a successful export should report its path, got "%s"' % export_status)

	var exported_path: String = export_status.trim_prefix("Exported recording to ")
	_check(FileAccess.file_exists(exported_path), "the exported file should actually exist")
	var file: FileAccess = FileAccess.open(exported_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("prototype") == "timeline_reconstruction", "the exported recording should be tagged with the Prototype C prototype id, got %s" % [parsed.get("prototype") if typeof(parsed) == TYPE_DICTIONARY else parsed])
	var event_types: Array = []
	for event in (parsed.get("events", []) as Array):
		event_types.append(event.get("type"))
	for expected_type in ["prototype_started", "event_selected", "event_placed", "timeline_submitted", "timeline_accepted"]:
		_check(event_types.has(expected_type), "the exported recording should contain a \"%s\" event, got types %s" % [expected_type, event_types])
	for event in (parsed.get("events", []) as Array):
		var payload_json: String = JSON.stringify(event)
		_check(not payload_json.contains("Mara") and not payload_json.contains("Ilse"), "recorded events must never contain full localized text (a translated name leaking in the payload)")
		if String(event.get("type", "")) == "timeline_submitted":
			var placements: Dictionary = (event.get("payload", {}) as Dictionary).get("placements", {})
			var ids: Array = placements.keys()
			var sorted_copy: Array = ids.duplicate()
			sorted_copy.sort()
			_check(ids == sorted_copy, "timeline_submitted's placement map must be normalized (sorted by event id) for deterministic exported payloads")

	_button("RecorderClearButton").pressed.emit()
	_check(status_label.text.contains("0 event(s)"), "Clear should empty the recorded event list")
	_button("RecorderStopButton").pressed.emit()
	if FileAccess.file_exists(exported_path):
		DirAccess.remove_absolute(exported_path)
	prototype_c.close()


func _test_hide_show_preserves_session() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_select_and_place(IDX_MARA_LEAVES, "19:25")

	debug_panel.close()
	_check(not debug_panel.visible, "closing DebugPanel (F1) should hide it")
	_check(prototype_c.visible, "Prototype C's OWN visible flag must be untouched by DebugPanel.close() — invisibility here is purely inherited from the hidden ancestor")
	debug_panel.open()
	deduction_lab.open()
	_check(prototype_c.visible, "reopening should show Prototype C exactly as it was left")
	_check((_events_row(IDX_MARA_LEAVES).get_child(0) as Label).text.contains("19:25"), "the same placement must still be there after an F1 hide/show round trip")
	prototype_c.close()


func _test_translation_coverage() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	locale_manager.set_locale("en")
	prototype_c.refresh()
	var en_title: String = (prototype_c.get_node("%TitleLabel") as Label).text
	var en_check: String = _button("CheckButton").text
	locale_manager.set_locale("vi")
	prototype_c.refresh()
	var vi_title: String = (prototype_c.get_node("%TitleLabel") as Label).text
	var vi_check: String = _button("CheckButton").text
	_check(en_title == "Prototype C — Timeline Reconstruction", 'the English title should read the translated string, got "%s"' % en_title)
	_check(vi_title != "" and vi_title != en_title, "the Vietnamese title should be non-empty and differ from English")
	_check(vi_check != "" and vi_check != en_check, "the Check Timeline button should also be retranslated")
	prototype_c.close()


## All three cases (X/Y/Z) share one data-driven scene — quickly accept
## round 1's authored solution on Y and Z too, proving the launch/select/
## place/check wiring works generically, not just for X.
func _test_all_three_cases_launch_and_accept_solution() -> void:
	for case_id in ["proto_y_lab_sample", "proto_z_customs_parcel"]:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		var solution: Dictionary = case_def.get("ground_truth", {}).get("solution_timeline", {})
		var movable_ids: Array = case_def.get("prototype_c", {}).get("movable_events", [])
		var all_ids: Array = []
		for event in case_def.get("timeline", {}).get("events", []):
			all_ids.append(str(event.get("id", "")))

		deduction_lab.open()
		(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
		_start_case(case_id)
		for event_id in movable_ids:
			_select_and_place(all_ids.find(event_id), str(solution.get(event_id, "")))
		_check_timeline()
		_check((prototype_c.get_node("%FeedbackHeadline") as Label).text != "", "%s: the authored solution should be accepted" % case_id)
		prototype_c.close()


## Milestone 1.12 regression, applied to Prototype C from the start (it never
## reproduces Prototype A's original bug) — see prototype_a_scene_test.gd's
## own equivalent test for the full rationale on why this checks STRUCTURE
## and BEHAVIOR rather than raw pixel geometry.
func _test_continue_button_stays_reachable_with_long_feedback() -> void:
	var footer: Control = prototype_c.get_node("%Footer")
	var body_scroll: ScrollContainer = prototype_c.get_node("%BodyScroll")
	var continue_button: Button = _button("ContinueButton")

	_check(continue_button.get_parent() == footer, "ContinueButton must live directly in the fixed Footer, never inside the scrolling body")
	_check(footer.get_parent() == body_scroll.get_parent() and footer.get_index() > body_scroll.get_index(), "Footer must be a LATER sibling than BodyScroll, so its minimum size is always honored ahead of the scrolling body")
	for child_name in ["%PlayArea", "%FeedbackPanel", "%ClaimPanel", "%CompletionPanel"]:
		var child: Control = prototype_c.get_node(child_name)
		var current: Node = child.get_parent()
		var is_descendant := false
		while current != null:
			if current == body_scroll:
				is_descendant = true
				break
			current = current.get_parent()
		_check(is_descendant, "%s must live inside the scrolling BodyScroll" % child_name)
	_check(body_scroll.get_v_scroll_bar() != null, "BodyScroll must be able to show a vertical scrollbar")

	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	# Deliberately wrong throughout (every movable event dumped on the same
	# early slot) — keeps the board active (never accepted) across both
	# locale passes, exactly like the invalid-submission path a real player
	# revising a rejected attempt would stay in.
	for event_index in [IDX_MARA_LEAVES, IDX_CARDIGAN_TAKEN, IDX_WINDOW_FORCED, IDX_SHREDDING_PICKUP, IDX_CARDIGAN_RETURNED]:
		_select_and_place(event_index, "19:25")

	var violations_list: VBoxContainer = prototype_c.get_node("%FeedbackViolationsList")
	var synthetic_long: String = "This synthetic sentence exists only to stress the feedback layout. ".repeat(80)

	for locale in ["vi", "en"]:
		locale_manager.set_locale(locale)
		_check_timeline()
		_check(prototype_c.get_node("%FeedbackPanel").visible, "feedback must show after checking (%s)" % locale)
		_check(continue_button.visible, "Continue must be visible with real feedback text (%s)" % locale)
		_check(continue_button.has_focus(), "checking must place keyboard focus on Continue (%s)" % locale)
		_check(continue_button.focus_mode != Control.FOCUS_NONE, "Continue must stay keyboard-focusable (%s)" % locale)

		for extra in 3:
			var label := Label.new()
			label.text = synthetic_long
			violations_list.add_child(label)
		await process_frame
		await process_frame

		_check(continue_button.visible, "Continue must remain visible once feedback content grows far longer than anything authored (%s)" % locale)
		_check(continue_button.get_parent() == footer, "Continue's parentage must not change just because body content grew (%s)" % locale)

		_continue_after_feedback()
		_check(prototype_c.get_node("%PlayArea").visible, "a rejected submission must keep the board active for the next locale pass (%s)" % locale)
		_select_and_place(IDX_CARDIGAN_RETURNED, "19:48" if locale == "vi" else "19:25")  # a real (still wrong) move so the next resubmit isn't blocked

	locale_manager.set_locale("vi")
	prototype_c.close()
