extends SceneTree
## Scene/integration tests for Prototype C — Timeline Reconstruction
## (Milestone 1.13 — see docs/prototype-c.md; resolution policy since
## Milestone 1.14 — see docs/resolution-policy.md): instantiation as a
## DeductionLab child, launching from the Lab (leaving the Lab/Prototype A/
## Prototype B untouched), fixed events shown locked, selecting/placing/
## moving/removing movable events via real buttons, Check disabled until
## complete, progressive violation feedback with retained placements, an
## alternate valid timeline, facts, hints, assistance and partner resolution
## for both the timeline and the claim, the verdict + supporting-fact claim
## form, the completion summary, restart/return confirmation with restart
## recording, recorder export vocabulary, F1 hide/show and locale switches
## preserving attempts, all three cases, and the Milestone 1.12 long-feedback
## layout regression. FULL-only — needs a real scene tree. Run with:
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
const MOVABLE := [IDX_MARA_LEAVES, IDX_CARDIGAN_TAKEN, IDX_WINDOW_FORCED, IDX_SHREDDING_PICKUP, IDX_CARDIGAN_RETURNED]
const SLOTS := ["19:25", "19:35", "19:48", "20:08", "20:10", "20:14"]

const SOLUTION := {
	IDX_MARA_LEAVES: "19:35", IDX_CARDIGAN_TAKEN: "19:48", IDX_WINDOW_FORCED: "20:08",
	IDX_SHREDDING_PICKUP: "20:10", IDX_CARDIGAN_RETURNED: "20:14",
}
const ALTERNATE := {
	IDX_MARA_LEAVES: "19:25", IDX_CARDIGAN_TAKEN: "19:48", IDX_WINDOW_FORCED: "20:08",
	IDX_SHREDDING_PICKUP: "20:10", IDX_CARDIGAN_RETURNED: "20:14",
}
## prototype_c.visible_constraint_facts keys, in authored order.
const FACT_KEYS := [
	"DED_PROTO_X_PROTOC_FACT_BADGE_TIME", "DED_PROTO_X_PROTOC_FACT_TRAM_TIME", "DED_PROTO_X_PROTOC_FACT_MARA_LEAVES",
	"DED_PROTO_X_PROTOC_FACT_MARA_TRAVEL", "DED_PROTO_X_PROTOC_FACT_CARDIGAN_TAKEN", "DED_PROTO_X_PROTOC_FACT_CARDIGAN_RETURNED",
	"DED_PROTO_X_PROTOC_FACT_WINDOW_AFTER_ENTRY", "DED_PROTO_X_PROTOC_FACT_WINDOW_HEARD",
	"DED_PROTO_X_PROTOC_FACT_WINDOW_NOT_DURING_ERRAND", "DED_PROTO_X_PROTOC_FACT_SHREDDING_WINDOW",
]
const SUPPORTING_FACT_KEY := "DED_PROTO_X_PROTOC_FACT_SHREDDING_WINDOW"

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
		_test_check_disabled_until_complete_then_category_feedback_then_retained()
		_test_alternate_valid_timeline_accepted()
		_test_fact_inspection_via_button()
		_test_hint_reveal_via_button()
		_test_claim_requires_verdict_and_justification_then_completes()
		_test_timeline_and_claim_assistance_and_partner_via_buttons()
		_test_restart_confirmation_cancel_preserves_and_restart_is_recorded()
		_test_return_confirmation_and_abandon()
		_test_recorder_controls()
		_test_hide_show_and_locale_preserve_attempts()
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
# Small helpers driving the REAL controls — no internal state is poked
# directly.

func _t(key: String) -> String:
	return String(TranslationServer.translate(key))


func _button(name: String) -> Button:
	return prototype_c.get_node("%" + name) as Button


func _label(name: String) -> Label:
	return prototype_c.get_node("%" + name) as Label


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


func _launch_and_start(case_id: String = CASE_ID) -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(case_id)


func _events_row(index: int) -> HBoxContainer:
	return (prototype_c.get_node("%EventsList") as VBoxContainer).get_child(index) as HBoxContainer


func _click_select(index: int) -> void:
	(_events_row(index).get_child(1) as Button).pressed.emit()  # [label, Select, (Remove)?]


func _click_remove_in_events(index: int) -> void:
	var row: HBoxContainer = _events_row(index)
	_check(row.get_child_count() == 3, "removing via the events list requires a Remove button")
	(row.get_child(2) as Button).pressed.emit()


func _timeline_row_for_slot(time_slot: String) -> HBoxContainer:
	for child in (prototype_c.get_node("%TimelineList") as VBoxContainer).get_children():
		var row := child as HBoxContainer
		if (row.get_child(0) as Label).text.begins_with(time_slot):
			return row
	return null


func _click_place_here(time_slot: String) -> void:
	var row: HBoxContainer = _timeline_row_for_slot(time_slot)
	_check(row != null and row.get_child_count() >= 2, "a Place Here button should be visible for slot %s while an event is selected" % time_slot)
	if row != null and row.get_child_count() >= 2:
		(row.get_child(1) as Button).pressed.emit()


func _select_and_place(event_index: int, time_slot: String) -> void:
	_click_select(event_index)
	_click_place_here(time_slot)


func _place_placement(placement: Dictionary) -> void:
	for event_index in placement:
		_select_and_place(int(event_index), String(placement[event_index]))


func _place_all_at(time_slot: String) -> void:
	for event_index in MOVABLE:
		_select_and_place(event_index, time_slot)


func _check_timeline() -> void:
	_button("CheckButton").pressed.emit()


func _continue_after_feedback() -> void:
	_button("ContinueButton").pressed.emit()


func _facts_row(index: int) -> HBoxContainer:
	return (prototype_c.get_node("%FactsList") as VBoxContainer).get_child(index) as HBoxContainer


func _select_justification(fact_key: String) -> void:
	var text: String = _t(fact_key)
	for row in (prototype_c.get_node("%JustificationList") as VBoxContainer).get_children():
		if ((row as HBoxContainer).get_child(0) as Label).text.ends_with(text):
			((row as HBoxContainer).get_child(1) as Button).pressed.emit()
			return
	_check(false, "there should be a justification row for %s" % fact_key)


func _submit_claim(impossible: bool, fact_key: String) -> void:
	_button("ClaimImpossibleButton" if impossible else "ClaimFitsButton").pressed.emit()
	_select_justification(fact_key)
	_button("ClaimSubmitButton").pressed.emit()


func _violation_lines() -> Array:
	return (prototype_c.get_node("%FeedbackViolationsList") as VBoxContainer).get_children().map(func(child): return (child as Label).text)


# ---------------------------------------------------------------------------

func _test_launch_without_lab_case_shows_picker() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_check(prototype_c.visible, "launching from the Lab should open Prototype C")
	var option: OptionButton = prototype_c.get_node("%CaseOptionButton")
	_check(option.get_item_count() >= 3, "the case picker should list every deduction case with Prototype C content")
	for i in option.get_item_count():
		_check(typeof(content_db.get_deduction_case(String(option.get_item_metadata(i))).get("prototype_c")) == TYPE_DICTIONARY, "every listed case must declare prototype_c content")
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

	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	var pa_option: OptionButton = prototype_a.get_node("%CaseOptionButton")
	for i in pa_option.get_item_count():
		if String(pa_option.get_item_metadata(i)) == CASE_ID:
			pa_option.select(i)
			break
	(prototype_a.get_node("%StartButton") as Button).pressed.emit()
	(prototype_a.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	var pa_row: HBoxContainer = (prototype_a.get_node("%EvidenceList") as VBoxContainer).get_child(0) as HBoxContainer
	(pa_row.get_child(1) as Button).pressed.emit()

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
	(pb_row.get_child(pb_row.get_child_count() - 1) as Button).pressed.emit()

	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_check(not prototype_a.visible and not prototype_b.visible, "launching Prototype C should hide A and B, never reset either")
	var pc_option: OptionButton = prototype_c.get_node("%CaseOptionButton")
	_check(String(pc_option.get_item_metadata(pc_option.selected)) == CASE_ID, "Prototype C's case picker should default to the Lab's active case")
	_start_case(CASE_ID)
	prototype_c.close()

	_check((prototype_a.get_node("%EvidenceList") as VBoxContainer).get_child(0).get_child_count() == 2, "Prototype A's own progress must survive a Prototype C run untouched")
	var pb_row_after: HBoxContainer = pb_evidence_list.get_child(0) as HBoxContainer
	_check((pb_row_after.get_child(pb_row_after.get_child_count() - 1) as Button).text == _t("UI_PROTOTYPE_B_REMOVE_BUTTON"), "Prototype B's own draft must survive a Prototype C run untouched")


func _test_fixed_events_shown_locked() -> void:
	_launch_and_start()
	for fixed_index in [IDX_MARA_TRAM_TAP, IDX_BADGE_USED]:
		_check(_events_row(fixed_index).get_child_count() == 1, "a fixed event's row shows only its label")
	prototype_c.close()


func _test_select_place_move_remove_via_buttons() -> void:
	_launch_and_start()
	_check(_events_row(IDX_MARA_LEAVES).get_child_count() == 2, "an unplaced movable event shows a label and Select")
	_select_and_place(IDX_MARA_LEAVES, "19:25")
	_check(_events_row(IDX_MARA_LEAVES).get_child_count() == 3 and (_events_row(IDX_MARA_LEAVES).get_child(0) as Label).text.contains("19:25"), "a placed event shows its placement and Remove")
	_select_and_place(IDX_MARA_LEAVES, "19:35")
	_check((_events_row(IDX_MARA_LEAVES).get_child(0) as Label).text.contains("19:35"), "placing at a different slot moves the event")
	_click_remove_in_events(IDX_MARA_LEAVES)
	_check(_events_row(IDX_MARA_LEAVES).get_child_count() == 2, "removing returns the row to its unplaced shape")
	_check(_label("ResolutionStatusLabel").text.contains("3/3"), "placing, moving and removing never consume a check")
	prototype_c.close()


func _test_check_disabled_until_complete_then_category_feedback_then_retained() -> void:
	_launch_and_start()
	_check(_button("CheckButton").disabled, "Check Timeline starts disabled")
	_select_and_place(IDX_MARA_LEAVES, "19:25")
	_select_and_place(IDX_CARDIGAN_TAKEN, "19:48")
	_select_and_place(IDX_WINDOW_FORCED, "20:08")
	_select_and_place(IDX_SHREDDING_PICKUP, "20:10")
	_check(_button("CheckButton").disabled, "Check Timeline stays disabled with an event unplaced")
	_select_and_place(IDX_CARDIGAN_RETURNED, "19:25")  # deliberately wrong
	_check(not _button("CheckButton").disabled, "Check Timeline enables once every event is placed")
	_check_timeline()
	_check(prototype_c.get_node("%FeedbackPanel").visible, "an invalid timeline shows feedback")
	var headline: String = _label("FeedbackHeadline").text
	_check(headline.begins_with(_t("UI_PROTOTYPE_C_FEEDBACK_CATEGORY").left(12)) and not headline.contains("timeline_inconsistent"), "the first rejection names only a category, got \"%s\"" % headline)
	_check(_violation_lines().is_empty(), "the first rejection must not list any fact")
	_check(_label("FeedbackResolutionNotice").visible and _label("FeedbackResolutionNotice").text.contains("2/3"), "the first rejection states the remaining checks")
	_continue_after_feedback()
	_check(prototype_c.get_node("%PlayArea").visible and (_events_row(IDX_CARDIGAN_RETURNED).get_child(0) as Label).text.contains("19:25"), "a rejected submission retains every placement")
	_check(_button("CheckButton").disabled, "identical resubmission is disabled until a move is made")
	_select_and_place(IDX_CARDIGAN_RETURNED, "20:14")
	_check(not _button("CheckButton").disabled, "a real change re-enables Check Timeline")
	_check_timeline()
	_check(_label("FeedbackHeadline").text == _t("UI_PROTOTYPE_C_FEEDBACK_SUCCESS_HEADLINE"), "the corrected timeline is accepted")
	prototype_c.close()


func _test_alternate_valid_timeline_accepted() -> void:
	_launch_and_start()
	_place_placement(ALTERNATE)
	_check_timeline()
	_check(_label("FeedbackHeadline").text == _t("UI_PROTOTYPE_C_FEEDBACK_SUCCESS_HEADLINE"), "the alternate valid timeline is accepted too")
	_continue_after_feedback()
	_check(prototype_c.get_node("%ClaimPanel").visible, "accepting any valid timeline enters the claim phase")
	prototype_c.close()


func _test_fact_inspection_via_button() -> void:
	_launch_and_start()
	_check(_facts_row(0).get_child_count() == 2, "an unopened fact shows a label and View")
	(_facts_row(0).get_child(1) as Button).pressed.emit()
	_check(_facts_row(0).get_child_count() == 1 and (_facts_row(0).get_child(0) as Label).text != "", "an opened fact shows its text")
	prototype_c.close()


func _test_hint_reveal_via_button() -> void:
	_launch_and_start()
	var hint_list: VBoxContainer = prototype_c.get_node("%HintList")
	_check(hint_list.get_child_count() == 0 and _label("HintNoticeLabel").text == _t("UI_RESOLUTION_HINT_NOTICE"), "no hint yet; the tier effect of hints is stated up front")
	_button("HintButton").pressed.emit()
	_check(hint_list.get_child_count() == 1 and _label("StatusLabel").text == _t("UI_RESOLUTION_NOTICE_TIER_CHANGED") % _t("UI_RESOLUTION_TIER_GUIDED"), "a hint that raises the tier says so")
	for i in 3:
		_button("HintButton").pressed.emit()
	_check(hint_list.get_child_count() == 4 and _button("HintButton").disabled, "all four levels, then Hint disables")
	prototype_c.close()


func _test_claim_requires_verdict_and_justification_then_completes() -> void:
	_launch_and_start()
	_place_placement(SOLUTION)
	_check_timeline()
	_continue_after_feedback()
	_check(prototype_c.get_node("%ClaimPanel").visible and _label("ClaimStatementLabel").text != "", "an accepted timeline shows the disputed claim")
	_check(_button("ClaimSubmitButton").disabled, "Submit Verdict starts disabled")
	_check((prototype_c.get_node("%JustificationList") as VBoxContainer).get_child_count() == FACT_KEYS.size(), "every visible fact is offered as a justification")

	_button("ClaimImpossibleButton").pressed.emit()
	_check(_button("ClaimImpossibleButton").text.begins_with("[") and _button("ClaimSubmitButton").disabled, "a verdict alone is marked selected (in words) but cannot be submitted")
	_select_justification("DED_PROTO_X_PROTOC_FACT_BADGE_TIME")
	_check(not _button("ClaimSubmitButton").disabled, "verdict + fact enables Submit Verdict")
	_button("ClaimSubmitButton").pressed.emit()  # right verdict, unrelated fact
	_check(_label("ClaimFeedbackLabel").visible and _label("ClaimFeedbackLabel").text.contains(_t("UI_PROTOTYPE_C_CLAIM_WRONG_FEEDBACK")), "an unrelated supporting fact fails with the generic nudge")
	_check(not _label("ClaimResolutionLabel").visible and prototype_c.get_node("%ClaimPanel").visible, "a failed justification keeps the claim phase and the accepted timeline")
	_check(_button("ClaimSubmitButton").disabled, "the identical failed verdict+fact cannot be resubmitted")

	_select_justification(SUPPORTING_FACT_KEY)
	_button("ClaimSubmitButton").pressed.emit()
	_check(_label("ClaimResolutionLabel").visible and _label("ClaimResolutionLabel").text.contains("20:10"), "the correct verdict + fact reveals the explanation with the accepted time")
	_check(_label("ClaimResolutionLabel").text.contains(_t(SUPPORTING_FACT_KEY)), "the explanation quotes the player's supporting fact")
	_check(_button("ContinueButton").visible, "Continue is offered")
	_continue_after_feedback()
	_check(prototype_c.get_node("%CompletionPanel").visible and (prototype_c.get_node("%StatsList") as VBoxContainer).get_child_count() == 12, "completion shows the 12-line summary")
	var lines: Array = (prototype_c.get_node("%StatsList") as VBoxContainer).get_children().map(func(c): return (c as Label).text)
	_check(lines.has(_t("UI_RESOLUTION_STATS_FORMAL_COMMITS") % 3) and lines.has(_t("UI_RESOLUTION_STATS_TIER") % _t("UI_RESOLUTION_TIER_GUIDED")), "the summary counts timeline + claim commits and the Guided tier, got %s" % [lines])
	prototype_c.close()


func _test_timeline_and_claim_assistance_and_partner_via_buttons() -> void:
	_launch_and_start()
	var status: Label = _label("ResolutionStatusLabel")
	var actions_row: Control = prototype_c.get_node("%ResolutionActionsRow")
	for i in 3:
		_place_all_at(SLOTS[i])
		_check_timeline()
		if i == 1:
			_check(_violation_lines().size() == 1, "the second rejection lists exactly one fact, got %s" % [_violation_lines()])
			_check(FACT_KEYS.any(func(key): return String(_violation_lines()[0]).contains(_t(key))) if _violation_lines().size() == 1 else false, "that line is an authored fact")
		_check(not actions_row.visible, "resolution actions stay hidden while feedback is open")
		_continue_after_feedback()
		if i == 1:
			var conflict_marked := false
			for index in MOVABLE:
				if (_events_row(index).get_child(0) as Label).text.contains(_t("UI_PROTOTYPE_C_CONFLICT_LABEL")):
					conflict_marked = true
			_check(conflict_marked, "the fact's involved events are marked in words on the board")
	_check(status.text.contains(_t("UI_RESOLUTION_STATUS_ASSISTANCE_REQUIRED")) and _button("CheckButton").disabled, "three rejections require assistance and lock checking")
	_check(actions_row.visible and _button("AcceptAssistanceButton").visible and not _button("PartnerResolveButton").visible, "the footer offers Accept Assistance")

	_button("AcceptAssistanceButton").pressed.emit()
	_check(prototype_c.get_node("%AssistancePanel").visible and _label("AssistanceText").text.contains(_t("DED_PROTO_X_PROTOC_HINT_4")), "timeline assistance shows the critical relationship and the ladder's level-4 pointer")
	_check((_events_row(IDX_CARDIGAN_RETURNED).get_child(0) as Label).text.contains(SLOTS[2]), "assistance never moves an event")
	for i in range(3, 5):
		_place_all_at(SLOTS[i])
		_check_timeline()
		_continue_after_feedback()
	_check(_button("PartnerResolveButton").visible and _button("CheckButton").disabled, "two assisted rejections offer the partner and close blind checks")

	_button("PartnerResolveButton").pressed.emit()
	_check(_label("FeedbackHeadline").text == _t("UI_RESOLUTION_PARTNER_HEADLINE"), "the partner timeline is clearly labeled")
	_check(_violation_lines().size() >= 2 and String(_violation_lines()[0]) == _t("UI_PROTOTYPE_C_PARTNER_TIMELINE_NOTE"), "the partner explains which established facts now hold, got %s" % [_violation_lines()])
	_continue_after_feedback()
	_check(prototype_c.get_node("%ClaimPanel").visible and not prototype_c.get_node("%AssistancePanel").visible, "the claim phase begins without carried-over assistance")
	# Milestone 1.14.1: the claim unit is a fresh resolution unit — its own
	# status must show a full budget and never itself read "Assisted", while
	# the separate run-result line still explains the run stayed Assisted,
	# reached during the (now-finished) timeline unit.
	_check(status.text.contains("3/3") and not status.text.contains(_t("UI_RESOLUTION_TIER_ASSISTED")), "the claim unit must start with a full budget and never itself read Assisted, got \"%s\"" % status.text)
	_check(_label("RunResultLabel").text == _t("UI_RESOLUTION_RUN_RESULT_FROM_EARLIER") % _t("UI_RESOLUTION_TIER_ASSISTED"), "the separate run-result line must still say Assisted, noting it was reached earlier, got \"%s\"" % _label("RunResultLabel").text)

	# Three wrong claims (never the supporting fact), then assistance.
	for entry in [[false, 0], [false, 1], [true, 2]]:
		_submit_claim(entry[0], FACT_KEYS[entry[1]])
	_check(status.text.contains(_t("UI_RESOLUTION_STATUS_ASSISTANCE_REQUIRED")) and _button("AcceptAssistanceButton").visible, "three wrong claims require assistance")
	_button("AcceptAssistanceButton").pressed.emit()
	_check(prototype_c.get_node("%AssistancePanel").visible and _label("AssistanceText").text.contains(_t("DED_PROTO_X_TL_SHREDDING_PICKUP_LABEL")), "claim assistance names the event the claim is about")
	_check(not _label("AssistanceText").text.contains(_t(SUPPORTING_FACT_KEY)), "claim assistance never names the supporting fact")
	for entry in [[true, 3], [true, 4]]:
		_submit_claim(entry[0], FACT_KEYS[entry[1]])
	_check(_button("PartnerResolveButton").visible and _button("ClaimSubmitButton").disabled, "two assisted claim failures offer the partner")

	_button("PartnerResolveButton").pressed.emit()
	var resolution: String = _label("ClaimResolutionLabel").text
	_check(_label("ClaimResolutionLabel").visible and resolution.contains(_t("UI_PROTOTYPE_C_PARTNER_CLAIM_NOTE")) and resolution.contains(_t(SUPPORTING_FACT_KEY)), "partner claim resolution is labeled and explains the temporal justification, got \"%s\"" % resolution)
	_continue_after_feedback()
	var lines: Array = (prototype_c.get_node("%StatsList") as VBoxContainer).get_children().map(func(c): return (c as Label).text)
	_check(lines.has(_t("UI_RESOLUTION_STATS_TIER") % _t("UI_RESOLUTION_TIER_ASSISTED")) and lines.has(_t("UI_RESOLUTION_STATS_PARTNER") % _t("UI_RESOLUTION_YES")), "the summary reports Assisted and partner resolution, got %s" % [lines])
	_check(lines.has(_t("UI_RESOLUTION_STATS_FORMAL_COMMITS") % 10) and lines.has(_t("UI_RESOLUTION_STATS_FAILED_COMMITS") % 10), "10 player commits, all failed — the partner's two resolutions are never counted as the player's, got %s" % [lines])
	prototype_c.close()


func _test_restart_confirmation_cancel_preserves_and_restart_is_recorded() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_select_case_option(CASE_ID)
	_button("RecorderStartButton").pressed.emit()
	_start_case(CASE_ID)
	_place_all_at(SLOTS[0])
	_check_timeline()
	_continue_after_feedback()
	var status: Label = _label("ResolutionStatusLabel")
	_button("RestartButton").pressed.emit()  # not confirming is a cancel
	_check(status.text.contains("2/3") and (_events_row(IDX_MARA_LEAVES).get_child(0) as Label).text.contains(SLOTS[0]), "cancelling a restart preserves placements and attempts")
	(prototype_c.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	_check(status.text.contains("3/3") and _events_row(IDX_MARA_LEAVES).get_child_count() == 2, "confirming Restart starts a fresh run")

	_button("RecorderExportButton").pressed.emit()
	var exported_path: String = _label("StatusLabel").text.trim_prefix("Exported recording to ")
	var types: Array = []
	if FileAccess.file_exists(exported_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(exported_path))
		for event in ((parsed as Dictionary).get("events", []) as Array):
			types.append(event.get("type"))
		DirAccess.remove_absolute(exported_path)
	_check(types.has("prototype_restarted") and types.has("formal_commit_failed"), "the export records the failed check and the restart, got %s" % [types])
	_button("RecorderStopButton").pressed.emit()
	_button("RecorderClearButton").pressed.emit()
	prototype_c.close()


func _test_return_confirmation_and_abandon() -> void:
	_launch_and_start()
	_select_and_place(IDX_MARA_LEAVES, "19:25")
	_button("ReturnButton").pressed.emit()
	_check(prototype_c.visible, "returning with progress requires confirmation")
	(prototype_c.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	_check(not prototype_c.visible, "confirming Return closes Prototype C")
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_button("ReturnButton").pressed.emit()
	_check(not prototype_c.visible, "returning with no progress closes immediately")


func _test_recorder_controls() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_select_case_option(CASE_ID)
	var status_label: Label = prototype_c.get_node("%RecorderStatusLabel")
	_button("RecorderStartButton").pressed.emit()
	_check(status_label.text.contains("Recording: ON"), "recording can start before the run")
	_start_case(CASE_ID)
	_place_placement(SOLUTION)
	_check_timeline()
	_continue_after_feedback()
	_submit_claim(true, SUPPORTING_FACT_KEY)

	_button("RecorderStopButton").pressed.emit()
	_check(status_label.text.contains("Recording: OFF") and not status_label.text.contains(" 0 event(s)"), "stopping keeps captured events")
	_button("RecorderExportButton").pressed.emit()
	var export_status: String = _label("StatusLabel").text
	var exported_path: String = export_status.trim_prefix("Exported recording to ")
	_check(export_status.begins_with("Exported recording to") and FileAccess.file_exists(exported_path), "a successful export reports an existing path")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(exported_path))
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("prototype") == "timeline_reconstruction" and parsed.get("schema_version") == 1 and parsed.get("event_schema_version") == 2, "the export keeps its prototype id, schema_version 1 and declares event_schema_version 2")
	var types: Array = []
	for event in (parsed.get("events", []) as Array):
		types.append(event.get("type"))
		var payload_json: String = JSON.stringify(event)
		_check(not payload_json.contains("Mara") and not payload_json.contains("Ilse"), "recorded events never contain localized text")
		if String(event.get("type", "")) == "timeline_submitted":
			var ids: Array = ((event.get("payload", {}) as Dictionary).get("placements", {}) as Dictionary).keys()
			var sorted_copy: Array = ids.duplicate()
			sorted_copy.sort()
			_check(ids == sorted_copy, "timeline_submitted's placement map is normalized")
	for expected_type in ["prototype_started", "event_selected", "event_placed", "formal_commit_started", "timeline_submitted", "timeline_accepted", "formal_commit_succeeded", "claim_answered", "claim_justification_result", "contradiction_resolved"]:
		_check(types.has(expected_type), "the export should contain \"%s\", got %s" % [expected_type, types])
	_check(not types.has("resolution_tier_changed"), "the export must never emit the retired v1 event type resolution_tier_changed, got %s" % [types])
	_button("RecorderClearButton").pressed.emit()
	_check(status_label.text.contains("0 event(s)"), "Clear empties the log")
	if FileAccess.file_exists(exported_path):
		DirAccess.remove_absolute(exported_path)
	prototype_c.close()


func _test_hide_show_and_locale_preserve_attempts() -> void:
	_launch_and_start()
	_place_all_at(SLOTS[0])
	_check_timeline()
	_continue_after_feedback()
	var status: Label = _label("ResolutionStatusLabel")
	debug_panel.close()
	_check(prototype_c.visible, "Prototype C's own visible flag is untouched by DebugPanel.close()")
	debug_panel.open()
	deduction_lab.open()
	_check(status.text.contains("2/3") and (_events_row(IDX_MARA_LEAVES).get_child(0) as Label).text.contains(SLOTS[0]), "F1 hide/show preserves placements and attempts")
	locale_manager.set_locale("en")
	_check(status.text.contains("Formal commits before assistance: 2/3"), "a locale switch re-renders without resetting attempts, got \"%s\"" % status.text)
	locale_manager.set_locale("vi")
	_check(status.text.contains("2/3"), "switching back keeps the attempt count")
	prototype_c.close()


func _test_translation_coverage() -> void:
	_launch_and_start()
	locale_manager.set_locale("en")
	var en_title: String = _label("TitleLabel").text
	var en_check: String = _button("CheckButton").text
	var en_submit: String = _button("ClaimSubmitButton").text
	locale_manager.set_locale("vi")
	_check(en_title == "Prototype C — Timeline Reconstruction" and en_submit == "Submit Verdict", "EN strings resolve, got \"%s\" / \"%s\"" % [en_title, en_submit])
	_check(_label("TitleLabel").text != en_title and _button("CheckButton").text != en_check and _button("ClaimSubmitButton").text != en_submit, "VI retranslates title, check and submit")
	prototype_c.close()


func _test_all_three_cases_launch_and_accept_solution() -> void:
	for case_id in ["proto_y_lab_sample", "proto_z_customs_parcel"]:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		var solution: Dictionary = case_def.get("ground_truth", {}).get("solution_timeline", {})
		var all_ids: Array = []
		for event in case_def.get("timeline", {}).get("events", []):
			all_ids.append(str(event.get("id", "")))
		_launch_and_start(case_id)
		for event_id in case_def.get("prototype_c", {}).get("movable_events", []):
			_select_and_place(all_ids.find(event_id), str(solution.get(event_id, "")))
		_check_timeline()
		_check(_label("FeedbackHeadline").text == _t("UI_PROTOTYPE_C_FEEDBACK_SUCCESS_HEADLINE"), "%s: the authored solution is accepted" % case_id)
		_continue_after_feedback()
		var support_key: String = str(case_def.get("prototype_c", {}).get("visible_constraint_facts", {}).get(str(case_def.get("prototype_c", {}).get("contradiction", {}).get("supporting_constraint_refs", [""])[0]), ""))
		_submit_claim(true, support_key)
		_check(_label("ClaimResolutionLabel").visible, "%s: \"Impossible\" with its supporting fact resolves the claim" % case_id)
		prototype_c.close()


## Milestone 1.12 regression, applied to Prototype C from the start — see
## prototype_a_scene_test.gd's equivalent for why this checks STRUCTURE and
## BEHAVIOR rather than raw pixel geometry.
func _test_continue_button_stays_reachable_with_long_feedback() -> void:
	var footer: Control = prototype_c.get_node("%Footer")
	var body_scroll: ScrollContainer = prototype_c.get_node("%BodyScroll")
	var continue_button: Button = _button("ContinueButton")
	_check(continue_button.get_parent() == footer and prototype_c.get_node("%ResolutionActionsRow").get_parent() == footer, "Continue and the assistance/partner actions live in the fixed Footer")
	_check(footer.get_parent() == body_scroll.get_parent() and footer.get_index() > body_scroll.get_index(), "Footer is a later sibling than BodyScroll")
	# Milestone 1.14.1: Check Timeline and Submit Verdict — the two primary
	# formal commits — must also live in the fixed Footer, never inside the
	# scrolling body.
	_check(_button("CheckButton").get_parent() == prototype_c.get_node("%ActionRow") and prototype_c.get_node("%ActionRow").get_parent() == footer, "Check Timeline must live in the fixed Footer's ActionRow")
	_check(_button("ClaimSubmitButton").get_parent() == footer, "Submit Verdict must live directly in the fixed Footer")
	for primary_button in [_button("CheckButton"), _button("ClaimSubmitButton")]:
		var current_primary: Node = primary_button.get_parent()
		var in_scroll := false
		while current_primary != null:
			if current_primary == body_scroll:
				in_scroll = true
				break
			current_primary = current_primary.get_parent()
		_check(not in_scroll, "%s must NOT be a descendant of the scrolling BodyScroll" % primary_button.name)
	for child_name in ["%AssistancePanel", "%PlayArea", "%FeedbackPanel", "%ClaimPanel", "%CompletionPanel"]:
		var current: Node = prototype_c.get_node(child_name).get_parent()
		var is_descendant := false
		while current != null:
			if current == body_scroll:
				is_descendant = true
				break
			current = current.get_parent()
		_check(is_descendant, "%s must live inside the scrolling BodyScroll" % child_name)
	var feedback_index: int = prototype_c.get_node("%FeedbackPanel").get_index()
	_check(feedback_index < prototype_c.get_node("%PlayArea").get_index() and feedback_index < prototype_c.get_node("%ClaimPanel").get_index(), "FeedbackPanel must be the body's first section, so resetting the scroll shows the feedback — not the board (Milestone 1.14 visual QA)")

	_launch_and_start()
	var violations_list: VBoxContainer = prototype_c.get_node("%FeedbackViolationsList")
	var synthetic_long: String = "This synthetic sentence exists only to stress the feedback layout. ".repeat(80)
	var locales: Array = ["vi", "en"]
	for i in locales.size():
		locale_manager.set_locale(locales[i])
		_place_all_at(SLOTS[i])
		_check_timeline()
		_check(prototype_c.get_node("%FeedbackPanel").visible and continue_button.visible and continue_button.has_focus(), "feedback shows with Continue visible and focused (%s)" % locales[i])
		for extra in 3:
			var label := Label.new()
			label.text = synthetic_long
			violations_list.add_child(label)
		_label("FeedbackResolutionNotice").text = synthetic_long
		await process_frame
		await process_frame
		_check(continue_button.visible and continue_button.get_parent() == footer, "Continue stays visible in the footer with far-too-long feedback (%s)" % locales[i])
		_continue_after_feedback()
		_check(prototype_c.get_node("%PlayArea").visible, "a rejected submission keeps the board active (%s)" % locales[i])
	locale_manager.set_locale("vi")
	prototype_c.close()
