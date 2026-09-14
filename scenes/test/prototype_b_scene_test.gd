extends SceneTree
## Scene/integration tests for Prototype B — Clue Connection (Milestone 1.12
## — see docs/prototype-b.md): instantiation as a DeductionLab child,
## launching from the Lab (with/without an active Lab case, leaving both the
## Lab and Prototype A untouched), reading evidence, placing/removing/
## replacing clues via real buttons, Connect disabling until every slot is
## filled, wrong/correct feedback, round transition and completion (D1 primary
## AND alternate paths, D3 requiring all three clues), hints via the real
## base API, restart/return confirmation, recorder controls, F1 hide/show
## session preservation, bilingual coverage, and the Milestone 1.12 long-
## feedback layout regression applied to this scene too. This is the
## FULL-only counterpart to the FAST controller/presenter/content tests — it
## exercises the real scene tree, which those pure-class tests deliberately
## don't need. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_b_scene_test.gd

const CASE_ID := "proto_x_archive_ledger"
## data/deductions/prototypes/proto_x_archive_ledger.json's
## prototype_b.evidence_pool, in order.
const POOL_DOOR_LOG := 0  # D1: credential_use_record
const POOL_TRAM_TAP := 1  # D1 primary alibi
const POOL_HARBOR_PHOTO := 2  # D1 alternate alibi
const POOL_ROUTE_NOTE := 3  # D1 travel fact
const POOL_FORCED_WINDOW := 4  # D3
const POOL_LATCH_GUIDE := 5  # D3
const POOL_WINDOW_LATCH := 6  # D3
const POOL_LOST_PROPERTY_SHEET := 7  # distractor — irrelevant to D1/D3

var main_instance: Node
var debug_panel: Control
var deduction_lab: Control
var prototype_a: Control
var prototype_b: Control
var locale_manager: Node
var content_db: Node
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	locale_manager = get_root().get_node("LocaleManager")
	content_db = get_root().get_node("ContentDB")
	TestHelpers.isolate_locale(locale_manager, "prototype_b_scene_test")

	main_instance = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_root().add_child(main_instance)
	await process_frame

	print("=== Prototype B — scene/integration tests ===")
	debug_panel = main_instance.get_node("%DebugPanel")
	deduction_lab = debug_panel.get_node("%DeductionLab")
	prototype_a = deduction_lab.get_node("%PrototypeA")
	prototype_b = deduction_lab.get_node("%PrototypeB")
	_check(is_instance_valid(prototype_b), "PrototypeB should instantiate as a child of DeductionLab")
	_check(not prototype_b.visible, "PrototypeB should start hidden (no production navigation path)")

	if OS.is_debug_build():
		_test_launch_without_lab_case_shows_picker()
		_test_launch_prefills_lab_case_and_leaves_lab_and_prototype_a_untouched()
		_test_evidence_open_place_remove_replace_via_buttons()
		_test_connect_disabled_until_slots_full_then_wrong_then_correct_d1()
		_test_alternate_d1_path()
		_test_d3_requires_all_three_clues_then_completes()
		_test_hint_reveal_via_button()
		_test_restart_confirmation_and_cancel_preserves_state()
		_test_return_confirmation_and_abandon()
		_test_recorder_controls()
		_test_hide_show_preserves_session()
		_test_translation_coverage()
		_test_all_three_cases_launch_and_solve_one_round()
		_test_continue_button_stays_reachable_with_long_feedback()
	else:
		print("(skipped interactive Prototype B checks — not a debug build; OS.is_debug_build() gate could not be exercised either way here, see docs/prototype-b.md's Known limitations)")

	locale_manager.set_locale("vi")  # leave the project's default in place for whatever runs after this
	main_instance.queue_free()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


# ---------------------------------------------------------------------------
# Small helpers driving the REAL controls, mirroring prototype_a_scene_test.gd's
# own style — no internal state is poked directly.

func _button(name: String) -> Button:
	return prototype_b.get_node("%" + name) as Button


func _select_case_option(case_id: String) -> void:
	var option: OptionButton = prototype_b.get_node("%CaseOptionButton")
	for i in option.get_item_count():
		if String(option.get_item_metadata(i)) == case_id:
			option.select(i)
			return


func _start_case(case_id: String) -> void:
	_select_case_option(case_id)
	_button("StartButton").pressed.emit()
	(prototype_b.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()


func _evidence_row(index: int) -> HBoxContainer:
	var list: VBoxContainer = prototype_b.get_node("%EvidenceList")
	return list.get_child(index) as HBoxContainer


## The evidence row's last button is always the Place/Remove toggle.
func _click_toggle_evidence(pool_index: int) -> void:
	var row: HBoxContainer = _evidence_row(pool_index)
	(row.get_child(row.get_child_count() - 1) as Button).pressed.emit()


func _click_open_evidence(pool_index: int) -> void:
	var row: HBoxContainer = _evidence_row(pool_index)
	if row.get_child_count() >= 3:  # label + Open + toggle — Open is only present while unopened.
		(row.get_child(1) as Button).pressed.emit()


func _connect() -> void:
	_button("ConnectButton").pressed.emit()


func _continue_after_feedback() -> void:
	_button("ContinueButton").pressed.emit()


func _hint() -> void:
	_button("HintButton").pressed.emit()


# ---------------------------------------------------------------------------

func _test_launch_without_lab_case_shows_picker() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_check(prototype_b.visible, "launching from the Lab should open Prototype B")
	var option: OptionButton = prototype_b.get_node("%CaseOptionButton")
	_check(option.get_item_count() >= 3, "the case picker should list every deduction case with Prototype B content")
	for i in option.get_item_count():
		var listed_id: String = String(option.get_item_metadata(i))
		_check(typeof(content_db.get_deduction_case(listed_id).get("prototype_b")) == TYPE_DICTIONARY, "every listed case (%s) must actually declare prototype_b content" % listed_id)
	_check(not prototype_b.get_node("%PlayArea").visible, "no run should be active until Start is pressed")
	prototype_b.close()


func _test_launch_prefills_lab_case_and_leaves_lab_and_prototype_a_untouched() -> void:
	deduction_lab.open()
	var lab_option: OptionButton = deduction_lab.get_node("%CaseOptionButton")
	for i in lab_option.get_item_count():
		if String(lab_option.get_item_metadata(i)) == CASE_ID:
			lab_option.select(i)
			break
	(deduction_lab.get_node("%SelectCaseButton") as Button).pressed.emit()
	_check(deduction_lab.get_node("%StatusLabel").text.contains(CASE_ID), "sanity — the Lab should now have proto_x active")

	# Open Prototype A too, and give it a little real progress, so we can
	# prove launching Prototype B afterward leaves IT untouched as well.
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
	_check(not prototype_a.visible, "launching Prototype B should hide Prototype A (avoid two prototype overlays at once), never reset it")
	var pb_option: OptionButton = prototype_b.get_node("%CaseOptionButton")
	_check(String(pb_option.get_item_metadata(pb_option.selected)) == CASE_ID, "Prototype B's case picker should default to the Lab's currently active case")

	_start_case(CASE_ID)
	_click_open_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_TRAM_TAP)
	_click_toggle_evidence(POOL_ROUTE_NOTE)
	_connect()
	_continue_after_feedback()
	prototype_b.close()

	var overview_text := ""
	for child in (deduction_lab.get_node("%OverviewList") as VBoxContainer).get_children():
		if child is Label:
			overview_text += String((child as Label).text)
	_check(overview_text.contains("0/4") or overview_text.contains("IN PROGRESS"), "the Lab's own Overview must still show zero questions resolved — Prototype B resolving a deduction must never leak into the Lab's session: got \"%s\"" % overview_text)

	_check(is_instance_valid(prototype_a.get_node("%EvidenceList")) and (prototype_a.get_node("%EvidenceList") as VBoxContainer).get_child(0).get_child_count() == 2, "Prototype A's own progress (its first evidence item opened) must survive a Prototype B run untouched")


func _test_evidence_open_place_remove_replace_via_buttons() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	var row: HBoxContainer = _evidence_row(POOL_DOOR_LOG)
	_check(row.get_child_count() == 3, "an unopened evidence row should show a label, an Open button and a Place/Remove toggle")
	_click_open_evidence(POOL_DOOR_LOG)
	var reopened_row: HBoxContainer = _evidence_row(POOL_DOOR_LOG)
	_check(reopened_row.get_child_count() == 2, "an opened evidence row should no longer show an Open button")

	_click_toggle_evidence(POOL_DOOR_LOG)
	var slots_list: VBoxContainer = prototype_b.get_node("%SlotsList")
	_check(slots_list.get_child_count() == 3, "sanity — round 1 has three slot rows")
	_check(not _button("ConnectButton").disabled == false, "Connect should still be disabled with only one of three slots filled")

	_click_toggle_evidence(POOL_TRAM_TAP)
	_click_toggle_evidence(POOL_LOST_PROPERTY_SHEET)  # fills all 3 slots, with a wrong item in the 3rd
	_check(not _button("ConnectButton").disabled, "Connect should enable once every slot is filled, even with a wrong clue placed")

	# Remove the wrong clue and replace it with the correct one.
	_click_toggle_evidence(POOL_LOST_PROPERTY_SHEET)  # now selected -> toggle removes it
	_check(_button("ConnectButton").disabled, "Connect should disable again once a slot is emptied")
	_click_toggle_evidence(POOL_ROUTE_NOTE)
	_check(not _button("ConnectButton").disabled, "Connect should re-enable once the replacement fills the last slot")
	prototype_b.close()


func _test_connect_disabled_until_slots_full_then_wrong_then_correct_d1() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	_check(_button("ConnectButton").disabled, "Connect must start disabled with no clues placed")
	_click_toggle_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_LOST_PROPERTY_SHEET)
	_click_toggle_evidence(POOL_FORCED_WINDOW)  # 3 wrong-for-D1 (but real, in-pool) items
	_check(not _button("ConnectButton").disabled, "Connect should enable once 3 slots are filled, however wrong the combination")
	_connect()
	_check(prototype_b.get_node("%FeedbackPanel").visible, "submitting a wrong connection should still show feedback")
	var wrong_text: String = (prototype_b.get_node("%FeedbackExplanation") as Label).text
	_check(wrong_text != "" and not wrong_text.to_lower().contains("valid_") and not wrong_text.to_lower().contains("irrelevant_evidence"), "wrong-connection feedback must be a localized message, never a raw category enum name: got \"%s\"" % wrong_text)
	_continue_after_feedback()
	_check(prototype_b.get_node("%PlayArea").visible, "a wrong connection must not complete the round or hide the play area")

	# The three wrong clues must still be placed — a failed attempt must never
	# clear the board. Each unopened row is [label, Open, toggle]; the toggle
	# reads "Remove" only while that item is still placed in a slot.
	for pool_index in [POOL_DOOR_LOG, POOL_LOST_PROPERTY_SHEET, POOL_FORCED_WINDOW]:
		var row: HBoxContainer = _evidence_row(pool_index)
		var toggle: Button = row.get_child(row.get_child_count() - 1) as Button
		_check(toggle.text == String(TranslationServer.translate("UI_PROTOTYPE_B_REMOVE_BUTTON")), "after a failed attempt, pool item %d must remain placed (its row should still offer Remove, not Place)" % pool_index)

	# Reconsider: swap the two wrong items for the real D1 primary path.
	_click_toggle_evidence(POOL_LOST_PROPERTY_SHEET)
	_click_toggle_evidence(POOL_FORCED_WINDOW)
	_click_toggle_evidence(POOL_TRAM_TAP)
	_click_toggle_evidence(POOL_ROUTE_NOTE)
	_connect()
	_check((prototype_b.get_node("%FeedbackHeadline") as Label).text != "", "the correct D1 primary path should show a success headline")
	var deduction_text: String = (prototype_b.get_node("%FeedbackDeductionText") as Label).text
	var explanation: String = (prototype_b.get_node("%FeedbackExplanation") as Label).text
	_check(deduction_text != "" and explanation != "", "a correct connection should reveal both the deduction's own text and the round's authored explanation")
	_continue_after_feedback()
	_check(prototype_b.get_node("%PlayArea").visible, "completing round 1 should move to round 2, not finish the prototype")
	prototype_b.close()


func _test_alternate_d1_path() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_click_toggle_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_HARBOR_PHOTO)  # the ALTERNATE alibi, not the primary
	_click_toggle_evidence(POOL_ROUTE_NOTE)
	_connect()
	_check((prototype_b.get_node("%FeedbackHeadline") as Label).text != "", "the D1 ALTERNATE path (photo alibi) must also validly connect")
	_continue_after_feedback()
	_check(prototype_b.get_node("%PlayArea").visible, "sanity — round 1 complete, round 2 not yet")
	prototype_b.close()


func _test_d3_requires_all_three_clues_then_completes() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_click_toggle_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_TRAM_TAP)
	_click_toggle_evidence(POOL_ROUTE_NOTE)
	_connect()
	_continue_after_feedback()  # round 2 now

	_check(_button("ConnectButton").disabled, "round 2 should also start with an empty, disabled Connect")
	_click_toggle_evidence(POOL_FORCED_WINDOW)
	_click_toggle_evidence(POOL_LATCH_GUIDE)
	_check(_button("ConnectButton").disabled, "Connect must stay disabled with only 2 of round 2's 3 slots filled — a single missing clue is enough to block submission")
	_click_toggle_evidence(POOL_WINDOW_LATCH)
	_check(not _button("ConnectButton").disabled, "Connect should enable once all 3 of round 2's slots are filled")
	_connect()
	_check((prototype_b.get_node("%FeedbackHeadline") as Label).text != "", "the correct 3-clue D3 connection should show a success headline")
	_continue_after_feedback()

	_check(not prototype_b.get_node("%PlayArea").visible, "completing both rounds should hide the play area")
	_check(prototype_b.get_node("%CompletionPanel").visible, "completing both rounds should show the completion panel")
	_check((prototype_b.get_node("%CompletionTextLabel") as Label).text != "", "the completion panel should show the authored completion text")
	var stats_list: VBoxContainer = prototype_b.get_node("%StatsList")
	_check(stats_list.get_child_count() == 6, "the completion panel should show all six stat lines")
	prototype_b.close()


func _test_hint_reveal_via_button() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	var hint_list: VBoxContainer = prototype_b.get_node("%HintList")
	_check(hint_list.get_child_count() == 0, "no hint should be revealed yet")
	_hint()
	_check(hint_list.get_child_count() == 1, "one hint reveal should show exactly one hint line")
	for i in 3:
		_hint()
	_check(hint_list.get_child_count() == 4, "revealing every level should show exactly 4 hint lines")
	_check(_button("HintButton").disabled, "the Hint button should disable once the ladder is exhausted")
	prototype_b.close()


func _test_restart_confirmation_and_cancel_preserves_state() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_click_open_evidence(POOL_DOOR_LOG)
	var confirm_dialog: ConfirmationDialog = prototype_b.get_node("%ConfirmDialog")

	_button("RestartButton").pressed.emit()
	var row_after_cancel: HBoxContainer = _evidence_row(POOL_DOOR_LOG)
	_check(row_after_cancel.get_child_count() == 2, "cancelling a restart confirmation must preserve the run — the opened evidence should still show no Open button")

	confirm_dialog.confirmed.emit()
	var fresh_row: HBoxContainer = _evidence_row(POOL_DOOR_LOG)
	_check(fresh_row.get_child_count() == 3, "confirming Restart should discard progress — the evidence should be unopened again")
	prototype_b.close()


func _test_return_confirmation_and_abandon() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	(_button("RecorderStartButton")).pressed.emit()
	_click_toggle_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_LOST_PROPERTY_SHEET)
	_click_toggle_evidence(POOL_FORCED_WINDOW)
	_connect()  # a real (wrong) attempt — genuine progress

	_button("ReturnButton").pressed.emit()
	_check(prototype_b.visible, "returning with meaningful progress must require confirmation, not close immediately")
	(prototype_b.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	_check(not prototype_b.visible, "confirming Return to Lab should close Prototype B")

	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_button("ReturnButton").pressed.emit()
	_check(not prototype_b.visible, "returning with no progress at all should close immediately without a confirmation")


func _test_recorder_controls() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_select_case_option(CASE_ID)

	var status_label: Label = prototype_b.get_node("%RecorderStatusLabel")
	_button("RecorderStartButton").pressed.emit()
	_check(status_label.text.contains("Recording: ON"), 'starting a recording BEFORE the run begins should show "Recording: ON", got "%s"' % status_label.text)

	_start_case(CASE_ID)
	_click_toggle_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_TRAM_TAP)
	_click_toggle_evidence(POOL_ROUTE_NOTE)
	_connect()

	_button("RecorderStopButton").pressed.emit()
	_check(status_label.text.contains("Recording: OFF"), "stopping should show Recording: OFF")
	_check(not status_label.text.contains(" 0 event(s)"), "events captured before Stop should still be reported, got \"%s\"" % status_label.text)

	_button("RecorderExportButton").pressed.emit()
	var export_status: String = (prototype_b.get_node("%StatusLabel") as Label).text
	_check(export_status.contains("Exported recording to"), 'a successful export should report its path, got "%s"' % export_status)

	var exported_path: String = export_status.trim_prefix("Exported recording to ")
	_check(FileAccess.file_exists(exported_path), "the exported file should actually exist")
	var file: FileAccess = FileAccess.open(exported_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("prototype") == "clue_connection", "the exported recording should be tagged with the Prototype B prototype id, got %s" % [parsed.get("prototype") if typeof(parsed) == TYPE_DICTIONARY else parsed])
	var event_types: Array = []
	for event in (parsed.get("events", []) as Array):
		event_types.append(event.get("type"))
	for expected_type in ["prototype_started", "round_started", "clue_selected", "connection_submitted", "connection_result", "deduction_unlocked"]:
		_check(event_types.has(expected_type), "the exported recording should contain a \"%s\" event, got types %s" % [expected_type, event_types])
	for event in (parsed.get("events", []) as Array):
		var payload_json: String = JSON.stringify(event)
		_check(not payload_json.contains("Oren") and not payload_json.contains("Mara"), "recorded events must never contain full localized text (a translated name leaking in the payload)")
		if String(event.get("type", "")) == "connection_submitted":
			var evidence_ids: Array = (event.get("payload", {}) as Dictionary).get("evidence_ids", [])
			var sorted_copy: Array = evidence_ids.duplicate()
			sorted_copy.sort()
			_check(evidence_ids == sorted_copy, "connection_submitted's evidence_ids must be normalized (sorted) for deterministic exported payloads")

	_button("RecorderClearButton").pressed.emit()
	_check(status_label.text.contains("0 event(s)"), "Clear should empty the recorded event list")
	_button("RecorderStopButton").pressed.emit()
	if FileAccess.file_exists(exported_path):
		DirAccess.remove_absolute(exported_path)
	prototype_b.close()


func _test_hide_show_preserves_session() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_click_open_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_TRAM_TAP)

	debug_panel.close()
	_check(not debug_panel.visible, "closing DebugPanel (F1) should hide it")
	_check(prototype_b.visible, "Prototype B's OWN visible flag must be untouched by DebugPanel.close() — invisibility here is purely inherited from the hidden ancestor")
	debug_panel.open()
	deduction_lab.open()
	_check(prototype_b.visible, "reopening should show Prototype B exactly as it was left")
	_check(_evidence_row(POOL_DOOR_LOG).get_child_count() == 2, "the same evidence must still be marked opened after an F1 hide/show round trip")
	_check(prototype_b.get_node("%SlotsList").get_child_count() == 3, "sanity — slots list still rendered after the round trip")
	prototype_b.close()


func _test_translation_coverage() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)

	locale_manager.set_locale("en")
	prototype_b.refresh()
	var en_title: String = (prototype_b.get_node("%TitleLabel") as Label).text
	var en_connect: String = _button("ConnectButton").text
	locale_manager.set_locale("vi")
	prototype_b.refresh()
	var vi_title: String = (prototype_b.get_node("%TitleLabel") as Label).text
	var vi_connect: String = _button("ConnectButton").text
	_check(en_title == "Prototype B — Clue Connection", 'the English title should read the translated string, got "%s"' % en_title)
	_check(vi_title != "" and vi_title != en_title, "the Vietnamese title should be non-empty and differ from English")
	_check(vi_connect != "" and vi_connect != en_connect, "the Connect Clues button should also be retranslated")
	prototype_b.close()


## All three cases (X/Y/Z) share one data-driven scene — quickly solve
## round 1 on Y and Z too, proving the launch/pick/place/connect wiring
## works generically, not just for X.
func _test_all_three_cases_launch_and_solve_one_round() -> void:
	for entry in [
		{"case_id": "proto_y_lab_sample", "pool_indices": [0, 1, 3]},  # cold_room_log, gym_scan, shuttle_note
		{"case_id": "proto_z_customs_parcel", "pool_indices": [0, 1, 3]},  # seal_registry, ferry_gate, port_map_note
	]:
		deduction_lab.open()
		(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
		_start_case(str(entry["case_id"]))
		for pool_index in (entry["pool_indices"] as Array):
			_click_toggle_evidence(int(pool_index))
		_connect()
		_check((prototype_b.get_node("%FeedbackHeadline") as Label).text != "", "%s: round 1 should be solvable with its own D1 primary path" % entry["case_id"])
		_continue_after_feedback()
		_check(prototype_b.get_node("%PlayArea").visible, "%s: round 1 complete, round 2 not yet" % entry["case_id"])
		prototype_b.close()


## Milestone 1.12 regression, applied to Prototype B from the start (it never
## reproduces Prototype A's original bug) — see prototype_a_scene_test.gd's
## own equivalent test for the full rationale on why this checks STRUCTURE
## and BEHAVIOR rather than raw pixel geometry.
func _test_continue_button_stays_reachable_with_long_feedback() -> void:
	var footer: Control = prototype_b.get_node("%Footer")
	var body_scroll: ScrollContainer = prototype_b.get_node("%BodyScroll")
	var continue_button: Button = _button("ContinueButton")

	_check(continue_button.get_parent() == footer, "ContinueButton must live directly in the fixed Footer, never inside the scrolling body")
	_check(footer.get_parent() == body_scroll.get_parent() and footer.get_index() > body_scroll.get_index(), "Footer must be a LATER sibling than BodyScroll, so its minimum size is always honored ahead of the scrolling body")
	for child_name in ["%PlayArea", "%FeedbackPanel", "%CompletionPanel"]:
		var child: Control = prototype_b.get_node(child_name)
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
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_click_toggle_evidence(POOL_DOOR_LOG)
	_click_toggle_evidence(POOL_TRAM_TAP)
	_click_toggle_evidence(POOL_ROUTE_NOTE)

	var explanation_label: Label = prototype_b.get_node("%FeedbackExplanation")
	var deduction_label: Label = prototype_b.get_node("%FeedbackDeductionText")
	var synthetic_long: String = "This synthetic sentence exists only to stress the feedback layout. ".repeat(80)

	for locale in ["vi", "en"]:
		locale_manager.set_locale(locale)
		_connect()  # 2nd locale pass reclassifies an already-resolved target and still shows feedback
		_check(prototype_b.get_node("%FeedbackPanel").visible, "feedback must show after connecting (%s)" % locale)
		_check(continue_button.visible, "Continue must be visible with real feedback text (%s)" % locale)
		_check(continue_button.has_focus(), "connecting must place keyboard focus on Continue (%s)" % locale)
		_check(continue_button.focus_mode != Control.FOCUS_NONE, "Continue must stay keyboard-focusable (%s)" % locale)

		explanation_label.text = synthetic_long
		deduction_label.text = synthetic_long
		await process_frame
		await process_frame

		_check(continue_button.visible, "Continue must remain visible once feedback text grows far longer than anything authored (%s)" % locale)
		_check(continue_button.get_parent() == footer, "Continue's parentage must not change just because body content grew (%s)" % locale)

	locale_manager.set_locale("vi")
	prototype_b.close()
