extends SceneTree
## Scene/integration tests for Prototype B — Clue Connection (Milestone 1.12
## — see docs/prototype-b.md; draft/batch model since Milestone 1.14 — see
## docs/resolution-policy.md): instantiation as a DeductionLab child,
## launching from the Lab (leaving the Lab and Prototype A untouched), reading
## evidence, placing/removing clues per draft via real buttons, draft tabs that
## retain their content, Save Draft costing nothing, Commit Theory disabled
## until both drafts are complete, a one-correct-one-wrong batch revealing and
## unlocking nothing, progressive non-oracular feedback, the D1 primary AND
## alternate paths, hints, assistance and partner resolution through the
## footer, the completion summary, restart/return confirmation with restart
## recording, recorder export vocabulary, F1 hide/show and locale switches
## preserving drafts and attempts, all three cases, and the Milestone 1.12
## long-feedback layout regression. FULL-only — needs a real scene tree. Run
## with:
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
const POOL_BACK_DOOR_SIGHTING := 8  # distractor — irrelevant to D1/D3

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
		_test_evidence_open_place_remove_via_buttons()
		_test_draft_tabs_retain_content_and_save_costs_nothing()
		_test_commit_disabled_until_both_drafts_complete()
		_test_mixed_batch_commits_neither_and_feedback_is_progressive()
		_test_primary_and_alternate_d1_paths_complete()
		_test_hint_reveal_via_button()
		_test_assistance_partner_and_completion_summary()
		_test_restart_confirmation_cancel_preserves_and_restart_is_recorded()
		_test_return_confirmation_and_abandon()
		_test_recorder_controls()
		_test_hide_show_and_locale_preserve_drafts_and_attempts()
		_test_translation_coverage()
		_test_all_three_cases_launch_and_solve_the_theory()
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
# Small helpers driving the REAL controls — no internal state is poked
# directly.

func _t(key: String) -> String:
	return String(TranslationServer.translate(key))


func _button(name: String) -> Button:
	return prototype_b.get_node("%" + name) as Button


func _label(name: String) -> Label:
	return prototype_b.get_node("%" + name) as Label


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


func _launch_and_start(case_id: String = CASE_ID) -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(case_id)


func _evidence_row(index: int) -> HBoxContainer:
	return (prototype_b.get_node("%EvidenceList") as VBoxContainer).get_child(index) as HBoxContainer


## The evidence row's last button is always the Place/Remove toggle (for the
## ACTIVE draft).
func _click_toggle_evidence(pool_index: int) -> void:
	var row: HBoxContainer = _evidence_row(pool_index)
	(row.get_child(row.get_child_count() - 1) as Button).pressed.emit()


func _click_open_evidence(pool_index: int) -> void:
	var row: HBoxContainer = _evidence_row(pool_index)
	if row.get_child_count() >= 3:  # label + Open + toggle — Open is only present while unopened.
		(row.get_child(1) as Button).pressed.emit()


func _toggle_text(pool_index: int) -> String:
	var row: HBoxContainer = _evidence_row(pool_index)
	return (row.get_child(row.get_child_count() - 1) as Button).text


func _tab(index: int) -> Button:
	return (prototype_b.get_node("%DraftTabsRow") as HBoxContainer).get_child(index) as Button


func _open_tab(index: int) -> void:
	_tab(index).pressed.emit()


func _place_all(pool_indices: Array) -> void:
	for pool_index in pool_indices:
		_click_toggle_evidence(pool_index)


func _commit() -> void:
	_button("CommitTheoryButton").pressed.emit()


func _continue_after_feedback() -> void:
	_button("ContinueButton").pressed.emit()


func _filled_slot_count() -> int:
	var count := 0
	for row in (prototype_b.get_node("%SlotsList") as VBoxContainer).get_children():
		if (row as HBoxContainer).get_child_count() == 2:  # label + Remove
			count += 1
	return count


## Question 1 = D1 primary path; question 2 = the given pool indices.
func _draft_theory(second: Array) -> void:
	_open_tab(0)
	_place_all([POOL_DOOR_LOG, POOL_TRAM_TAP, POOL_ROUTE_NOTE])
	_open_tab(1)
	_place_all(second)


# ---------------------------------------------------------------------------

func _test_launch_without_lab_case_shows_picker() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_check(prototype_b.visible, "launching from the Lab should open Prototype B")
	var option: OptionButton = prototype_b.get_node("%CaseOptionButton")
	_check(option.get_item_count() >= 3, "the case picker should list every deduction case with Prototype B content")
	for i in option.get_item_count():
		_check(typeof(content_db.get_deduction_case(String(option.get_item_metadata(i))).get("prototype_b")) == TYPE_DICTIONARY, "every listed case must declare prototype_b content")
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

	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	var pa_option: OptionButton = prototype_a.get_node("%CaseOptionButton")
	for i in pa_option.get_item_count():
		if String(pa_option.get_item_metadata(i)) == CASE_ID:
			pa_option.select(i)
			break
	(prototype_a.get_node("%StartButton") as Button).pressed.emit()
	(prototype_a.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	var pa_row: HBoxContainer = (prototype_a.get_node("%EvidenceList") as VBoxContainer).get_child(0) as HBoxContainer
	(pa_row.get_child(1) as Button).pressed.emit()  # open the first evidence item

	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_check(not prototype_a.visible, "launching Prototype B should hide Prototype A, never reset it")
	var pb_option: OptionButton = prototype_b.get_node("%CaseOptionButton")
	_check(String(pb_option.get_item_metadata(pb_option.selected)) == CASE_ID, "Prototype B's case picker should default to the Lab's active case")

	_start_case(CASE_ID)
	_draft_theory([POOL_FORCED_WINDOW, POOL_LATCH_GUIDE, POOL_WINDOW_LATCH])
	_commit()
	_continue_after_feedback()
	_check(prototype_b.get_node("%CompletionPanel").visible, "a correct first theory completes the prototype")
	prototype_b.close()

	var overview_text := ""
	for child in (deduction_lab.get_node("%OverviewList") as VBoxContainer).get_children():
		if child is Label:
			overview_text += String((child as Label).text)
	_check(overview_text.contains("0/4") or overview_text.contains("IN PROGRESS"), "the Lab's own Overview must still show zero questions resolved: got \"%s\"" % overview_text)
	_check((prototype_a.get_node("%EvidenceList") as VBoxContainer).get_child(0).get_child_count() == 2, "Prototype A's own progress must survive a Prototype B run untouched")


func _test_evidence_open_place_remove_via_buttons() -> void:
	_launch_and_start()
	_check(_evidence_row(POOL_DOOR_LOG).get_child_count() == 3, "an unopened evidence row shows a label, Open and Place")
	_click_open_evidence(POOL_DOOR_LOG)
	_check(_evidence_row(POOL_DOOR_LOG).get_child_count() == 2, "an opened row no longer shows Open")
	_click_toggle_evidence(POOL_DOOR_LOG)
	_check((prototype_b.get_node("%SlotsList") as VBoxContainer).get_child_count() == 3 and _filled_slot_count() == 1, "question 1 has three slots, one filled")
	_check(_toggle_text(POOL_DOOR_LOG) == _t("UI_PROTOTYPE_B_REMOVE_BUTTON"), "a placed clue offers Remove")
	_click_toggle_evidence(POOL_DOOR_LOG)
	_check(_filled_slot_count() == 0 and _toggle_text(POOL_DOOR_LOG) == _t("UI_PROTOTYPE_B_PLACE_BUTTON"), "Remove empties the slot")
	prototype_b.close()


func _test_draft_tabs_retain_content_and_save_costs_nothing() -> void:
	_launch_and_start()
	var status: Label = _label("ResolutionStatusLabel")
	var tabs: HBoxContainer = prototype_b.get_node("%DraftTabsRow")
	_check(tabs.get_child_count() == 2 and _tab(0).disabled and not _tab(1).disabled, "both questions are tabs; the current one is marked (disabled)")
	_check(_tab(0).text.contains(_t("UI_PROTOTYPE_B_DRAFT_TAB_CURRENT")), "the current tab is marked in words, not only by color")
	_check(_label("DraftStatusLabel").text.contains(_t("UI_PROTOTYPE_B_DRAFT_STATUS") % [0, 3]), "the draft is labeled as an Unverified Draft, got \"%s\"" % _label("DraftStatusLabel").text)

	_place_all([POOL_DOOR_LOG, POOL_TRAM_TAP])
	_open_tab(1)
	_check((prototype_b.get_node("%SlotsList") as VBoxContainer).get_child_count() == 3 and _filled_slot_count() == 0, "question 2 shows its own empty slots")
	_check(_toggle_text(POOL_DOOR_LOG) == _t("UI_PROTOTYPE_B_PLACE_BUTTON"), "clues placed in question 1 are not placed in question 2")
	_click_toggle_evidence(POOL_FORCED_WINDOW)
	_open_tab(0)
	_check(_filled_slot_count() == 2 and _toggle_text(POOL_TRAM_TAP) == _t("UI_PROTOTYPE_B_REMOVE_BUTTON"), "switching back retains question 1's draft exactly")

	_button("SaveDraftButton").pressed.emit()
	_check(_label("StatusLabel").text == _t("UI_PROTOTYPE_B_DRAFT_SAVED_STATUS"), "saving confirms the draft stays unverified")
	_check(_label("DraftStatusLabel").text.contains(_t("UI_PROTOTYPE_B_DRAFT_SAVED_LABEL")), "the draft now shows as saved")
	_check(status.text.contains("3/3") and not status.text.contains(_t("UI_RESOLUTION_TIER_INDEPENDENT")), "saving and switching never consume an attempt, and the current-unit status never mentions the run result, got \"%s\"" % status.text)
	_check(_label("RunResultLabel").text.contains(_t("UI_RESOLUTION_TIER_INDEPENDENT")), "the separate run-result line should say Independent, got \"%s\"" % _label("RunResultLabel").text)
	_check(not prototype_b.get_node("%FeedbackPanel").visible, "saving never produces correctness feedback")
	prototype_b.close()


func _test_commit_disabled_until_both_drafts_complete() -> void:
	_launch_and_start()
	_check(_button("CommitTheoryButton").disabled, "Commit Theory starts disabled")
	_place_all([POOL_DOOR_LOG, POOL_TRAM_TAP, POOL_ROUTE_NOTE])
	_check(_button("CommitTheoryButton").disabled, "one complete draft is not enough to commit")
	_open_tab(1)
	_place_all([POOL_FORCED_WINDOW, POOL_LATCH_GUIDE])
	_check(_button("CommitTheoryButton").disabled, "question 2 with 2 of 3 clues still blocks committing")
	_click_toggle_evidence(POOL_WINDOW_LATCH)
	_check(not _button("CommitTheoryButton").disabled, "Commit Theory enables once every slot of every draft is filled")
	prototype_b.close()


func _test_mixed_batch_commits_neither_and_feedback_is_progressive() -> void:
	_launch_and_start()
	_draft_theory([POOL_FORCED_WINDOW, POOL_LATCH_GUIDE, POOL_LOST_PROPERTY_SHEET])  # D1 right, D3 wrong
	var status: Label = _label("ResolutionStatusLabel")
	var q1: String = _t("DED_PROTO_X_PROTOB_Q1")
	var q2: String = _t("DED_PROTO_X_PROTOB_Q2")
	var d1_text: String = _t("DED_PROTO_X_DED_BADGE_MISUSED_TEXT")

	_commit()
	_check(prototype_b.get_node("%FeedbackPanel").visible, "a rejected theory shows feedback")
	_check(_label("FeedbackExplanation").text == _t("UI_PROTOTYPE_B_FEEDBACK_THEORY_REJECTED"), "the first rejection is generic — it must not say which draft failed, got \"%s\"" % _label("FeedbackExplanation").text)
	_check(not _label("FeedbackDeductionText").visible and not _label("FeedbackHeadline").visible, "a rejected theory reveals no deduction headline or text")
	_check(not JSON.stringify([_label("FeedbackExplanation").text, _label("FeedbackResolutionNotice").text]).contains(d1_text), "the correct draft's deduction must not unlock either")
	_continue_after_feedback()
	_check(prototype_b.get_node("%PlayArea").visible and not prototype_b.get_node("%CompletionPanel").visible, "a rejected theory completes nothing")
	_check(status.text.contains("2/3"), "one failed theory should cost one commit, got \"%s\"" % status.text)
	_check(_label("RunResultLabel").text.contains(_t("UI_RESOLUTION_TIER_GUIDED")), "one failed theory should make the separate run-result line say Guided, got \"%s\"" % _label("RunResultLabel").text)
	_open_tab(0)
	_check(_filled_slot_count() == 3, "the correct draft is preserved exactly after a rejection")
	_open_tab(1)
	_check(_filled_slot_count() == 3 and _toggle_text(POOL_LOST_PROPERTY_SHEET) == _t("UI_PROTOTYPE_B_REMOVE_BUTTON"), "the wrong draft is preserved too, so the player can reconsider one clue")
	_check(_button("CommitTheoryButton").disabled, "the identical failed theory cannot be re-committed")

	_click_toggle_evidence(POOL_LATCH_GUIDE)
	_click_toggle_evidence(POOL_BACK_DOOR_SIGHTING)  # still wrong
	_check(not _button("CommitTheoryButton").disabled, "a changed theory can be committed again")
	_commit()
	var guided: String = _label("FeedbackExplanation").text
	_check(guided.contains(q2) and not guided.contains(q1), "the second rejection names only the affected question, got \"%s\"" % guided)
	_check(not guided.contains(_t("DED_PROTO_X_E_WINDOW_LATCH_NAME")) and not guided.contains(_t("DED_PROTO_X_E_LATCH_GUIDE_NAME")), "guided feedback must never name a needed clue")
	_continue_after_feedback()
	prototype_b.close()


func _test_primary_and_alternate_d1_paths_complete() -> void:
	for d1 in [[POOL_DOOR_LOG, POOL_TRAM_TAP, POOL_ROUTE_NOTE], [POOL_DOOR_LOG, POOL_HARBOR_PHOTO, POOL_ROUTE_NOTE]]:
		_launch_and_start()
		_open_tab(0)
		_place_all(d1)
		_open_tab(1)
		_place_all([POOL_WINDOW_LATCH, POOL_FORCED_WINDOW, POOL_LATCH_GUIDE])  # order never matters
		_commit()
		_check(_label("FeedbackHeadline").text == _t("UI_PROTOTYPE_B_FEEDBACK_SUCCESS_HEADLINE"), "D1 path %s + D3 should be accepted" % [d1])
		_check(_label("FeedbackDeductionText").text.contains(_t("DED_PROTO_X_DED_BADGE_MISUSED_TEXT")) and _label("FeedbackDeductionText").text.contains(_t("DED_PROTO_X_DED_BREAK_IN_STAGED_TEXT")), "an accepted theory reveals BOTH deductions")
		_continue_after_feedback()
		_check(prototype_b.get_node("%CompletionPanel").visible and (prototype_b.get_node("%StatsList") as VBoxContainer).get_child_count() == 10, "completion shows the 10-line summary")
		prototype_b.close()


func _test_hint_reveal_via_button() -> void:
	_launch_and_start()
	var hint_list: VBoxContainer = prototype_b.get_node("%HintList")
	_check(hint_list.get_child_count() == 0 and _label("HintNoticeLabel").text == _t("UI_RESOLUTION_HINT_NOTICE"), "no hint yet, and the tier effect of hints is stated up front")
	_button("HintButton").pressed.emit()
	_check(hint_list.get_child_count() == 1, "one reveal shows one line")
	_check(_label("StatusLabel").text == _t("UI_RESOLUTION_NOTICE_TIER_CHANGED") % _t("UI_RESOLUTION_TIER_GUIDED"), "a hint that raises the tier says so explicitly")
	for i in 3:
		_button("HintButton").pressed.emit()
	_check(hint_list.get_child_count() == 4 and _button("HintButton").disabled, "all four levels, then the Hint button disables")
	_open_tab(1)
	_check(hint_list.get_child_count() == 0 and not _button("HintButton").disabled, "question 2 has its own ladder")
	prototype_b.close()


func _test_assistance_partner_and_completion_summary() -> void:
	_launch_and_start()
	_draft_theory([POOL_FORCED_WINDOW, POOL_LATCH_GUIDE, POOL_LOST_PROPERTY_SHEET])
	var status: Label = _label("ResolutionStatusLabel")
	# Every change keeps question 2 wrong and never repeats a failed theory.
	var actions_row: Control = prototype_b.get_node("%ResolutionActionsRow")
	# Question 2 drafts: {forced, latch guide, lost property} -> {forced, lost
	# property, window latch} -> {lost property, window latch, latch guide}.
	var edits: Array = [[], [POOL_LATCH_GUIDE, POOL_WINDOW_LATCH], [POOL_FORCED_WINDOW, POOL_LATCH_GUIDE]]
	for edit in edits:
		_place_all(edit)
		_commit()
		_check(not actions_row.visible, "resolution actions stay hidden while feedback is open")
		_continue_after_feedback()
	_check(status.text.contains(_t("UI_RESOLUTION_STATUS_ASSISTANCE_REQUIRED")), "three failures require assistance, got \"%s\"" % status.text)
	_check(actions_row.visible and _button("AcceptAssistanceButton").visible and not _button("PartnerResolveButton").visible, "the footer offers Accept Assistance")
	_click_toggle_evidence(POOL_LOST_PROPERTY_SHEET)
	_click_toggle_evidence(POOL_FORCED_WINDOW)  # now the CORRECT D3 trio
	_check(_button("CommitTheoryButton").disabled, "committing is locked until assistance is acknowledged — even for a correct theory")
	_click_toggle_evidence(POOL_FORCED_WINDOW)
	_click_toggle_evidence(POOL_LOST_PROPERTY_SHEET)  # back to the third failed theory

	_open_tab(0)
	_button("AcceptAssistanceButton").pressed.emit()
	_check(_tab(1).disabled, "assistance opens the affected question's draft")
	_check(prototype_b.get_node("%AssistancePanel").visible and _label("AssistanceText").text.contains(_t("DED_PROTO_X_PROTOB_Q2")), "the assistance panel names the affected question")
	_check(_label("AssistanceText").text.contains(_t("DED_PROTO_X_HINT_STAGED_2")) and not _label("AssistanceText").text.contains(_t("DED_PROTO_X_HINT_STAGED_3")), "assistance reuses the ladder's category level, never the evidence group")
	_check(_filled_slot_count() == 3, "assistance never inserts or removes a clue")

	# -> {window latch, latch guide, back door} -> {window latch, back door, forced}.
	for edit in [[POOL_LOST_PROPERTY_SHEET, POOL_BACK_DOOR_SIGHTING], [POOL_LATCH_GUIDE, POOL_FORCED_WINDOW]]:
		_place_all(edit)
		_commit()
		_continue_after_feedback()
	_check(actions_row.visible and _button("PartnerResolveButton").visible and _button("CommitTheoryButton").disabled, "two assisted failures close blind commits and offer the partner")

	_button("PartnerResolveButton").pressed.emit()
	_check(_label("FeedbackHeadline").text == _t("UI_RESOLUTION_PARTNER_HEADLINE"), "partner resolution is clearly labeled")
	_check(_label("FeedbackPartnerNote").visible and _label("FeedbackPartnerNote").text.contains(_t("DED_PROTO_X_E_WINDOW_LATCH_NAME")), "the partner note explains the connection it made")
	_check(_label("FeedbackDeductionText").text.contains(_t("DED_PROTO_X_DED_BREAK_IN_STAGED_TEXT")), "partner resolution still reveals and explains the deductions")
	_continue_after_feedback()
	_check(prototype_b.get_node("%CompletionPanel").visible, "partner resolution completes the prototype — no hard failure")
	var lines: Array = []
	for child in (prototype_b.get_node("%StatsList") as VBoxContainer).get_children():
		lines.append((child as Label).text)
	_check(lines.size() == 10, "the completion summary shows 10 lines, got %s" % [lines])
	_check(lines.has(_t("UI_RESOLUTION_STATS_TIER") % _t("UI_RESOLUTION_TIER_ASSISTED")) and lines.has(_t("UI_RESOLUTION_STATS_PARTNER") % _t("UI_RESOLUTION_YES")), "the summary reports Assisted and partner resolution, got %s" % [lines])
	_check(lines.has(_t("UI_RESOLUTION_STATS_FORMAL_COMMITS") % 5) and lines.has(_t("UI_RESOLUTION_STATS_FAILED_COMMITS") % 5), "the partner's commit is never counted as the player's, got %s" % [lines])
	prototype_b.close()


func _test_restart_confirmation_cancel_preserves_and_restart_is_recorded() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_select_case_option(CASE_ID)
	_button("RecorderStartButton").pressed.emit()
	_start_case(CASE_ID)
	_draft_theory([POOL_FORCED_WINDOW, POOL_LATCH_GUIDE, POOL_LOST_PROPERTY_SHEET])
	_commit()
	_continue_after_feedback()
	var status: Label = _label("ResolutionStatusLabel")

	_button("RestartButton").pressed.emit()  # not confirming is a cancel
	_check(status.text.contains("2/3") and _filled_slot_count() == 3, "cancelling a restart preserves the drafts and attempts")
	(prototype_b.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	_check(status.text.contains("3/3") and _filled_slot_count() == 0, "confirming Restart starts a fresh run")

	var types: Array = _export_event_types()
	_check(types.has("prototype_restarted") and types.has("theory_batch_rejected"), "the export records the rejected batch and the restart, got %s" % [types])
	prototype_b.close()


func _test_return_confirmation_and_abandon() -> void:
	_launch_and_start()
	_click_toggle_evidence(POOL_DOOR_LOG)  # an unsubmitted draft is real progress
	_button("ReturnButton").pressed.emit()
	_check(prototype_b.visible, "returning with a drafted clue must require confirmation")
	(prototype_b.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	_check(not prototype_b.visible, "confirming Return closes Prototype B")
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_start_case(CASE_ID)
	_button("ReturnButton").pressed.emit()
	_check(not prototype_b.visible, "returning with no progress closes immediately")


func _test_recorder_controls() -> void:
	deduction_lab.open()
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_select_case_option(CASE_ID)
	var status_label: Label = prototype_b.get_node("%RecorderStatusLabel")
	_button("RecorderStartButton").pressed.emit()
	_check(status_label.text.contains("Recording: ON"), "recording can start before the run")
	_start_case(CASE_ID)
	_draft_theory([POOL_WINDOW_LATCH, POOL_LATCH_GUIDE, POOL_FORCED_WINDOW])
	_button("SaveDraftButton").pressed.emit()
	_commit()

	_button("RecorderStopButton").pressed.emit()
	_check(status_label.text.contains("Recording: OFF") and not status_label.text.contains(" 0 event(s)"), "stopping keeps captured events")
	_button("RecorderExportButton").pressed.emit()
	var export_status: String = _label("StatusLabel").text
	var exported_path: String = export_status.trim_prefix("Exported recording to ")
	_check(export_status.begins_with("Exported recording to") and FileAccess.file_exists(exported_path), "a successful export reports an existing path")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(exported_path))
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("prototype") == "clue_connection" and parsed.get("schema_version") == 1 and parsed.get("event_schema_version") == 2, "the export keeps the clue_connection id, schema_version 1 and declares event_schema_version 2")
	var types: Array = []
	for event in (parsed.get("events", []) as Array):
		types.append(event.get("type"))
		var payload_json: String = JSON.stringify(event)
		_check(not payload_json.contains("Oren") and not payload_json.contains("Mara"), "recorded events never contain localized text")
		if String(event.get("type", "")) == "theory_batch_submitted":
			for draft in (event.get("payload", {}) as Dictionary).get("drafts", []):
				var ids: Array = draft.get("evidence_ids", [])
				var sorted_copy: Array = ids.duplicate()
				sorted_copy.sort()
				_check(ids == sorted_copy, "theory_batch_submitted evidence_ids are normalized (sorted)")
	for expected_type in ["prototype_started", "clue_selected", "draft_selected", "draft_saved", "formal_commit_started", "theory_batch_submitted", "theory_batch_accepted", "formal_commit_succeeded", "deduction_unlocked"]:
		_check(types.has(expected_type), "the export should contain \"%s\", got %s" % [expected_type, types])
	for retired_v1_type in ["round_started", "connection_submitted", "connection_result", "round_completed", "resolution_tier_changed"]:
		_check(not types.has(retired_v1_type), "the export must never emit the retired v1 event type \"%s\", got %s" % [retired_v1_type, types])
	_button("RecorderClearButton").pressed.emit()
	_check(status_label.text.contains("0 event(s)"), "Clear empties the log")
	if FileAccess.file_exists(exported_path):
		DirAccess.remove_absolute(exported_path)
	prototype_b.close()


func _test_hide_show_and_locale_preserve_drafts_and_attempts() -> void:
	_launch_and_start()
	_draft_theory([POOL_FORCED_WINDOW, POOL_LATCH_GUIDE, POOL_LOST_PROPERTY_SHEET])
	_commit()
	_continue_after_feedback()
	var status: Label = _label("ResolutionStatusLabel")

	debug_panel.close()
	_check(prototype_b.visible, "Prototype B's own visible flag is untouched by DebugPanel.close()")
	debug_panel.open()
	deduction_lab.open()
	_check(status.text.contains("2/3") and _filled_slot_count() == 3, "F1 hide/show preserves drafts and attempts")

	locale_manager.set_locale("en")
	_check(status.text.contains("Formal commits before assistance: 2/3"), "a locale switch re-renders without resetting attempts, got \"%s\"" % status.text)
	locale_manager.set_locale("vi")
	_check(status.text.contains("2/3"), "switching back keeps the attempt count")
	prototype_b.close()


func _test_translation_coverage() -> void:
	_launch_and_start()
	locale_manager.set_locale("en")
	var en_title: String = _label("TitleLabel").text
	var en_commit: String = _button("CommitTheoryButton").text
	var en_tab: String = _tab(0).text
	locale_manager.set_locale("vi")
	_check(en_title == "Prototype B — Clue Connection" and en_commit == "Commit Theory", "EN title/commit read the translated strings, got \"%s\" / \"%s\"" % [en_title, en_commit])
	_check(_label("TitleLabel").text != en_title and _button("CommitTheoryButton").text != en_commit and _tab(0).text != en_tab, "VI retranslates the title, commit button and draft tabs")
	_check(_button("SaveDraftButton").text == _t("UI_PROTOTYPE_B_SAVE_DRAFT") and _label("CommitHelpLabel").text == _t("UI_PROTOTYPE_B_COMMIT_HELP"), "save/commit help are localized")
	prototype_b.close()


## All three cases (X/Y/Z) share one data-driven scene — solve the whole
## theory on Y and Z too.
func _test_all_three_cases_launch_and_solve_the_theory() -> void:
	for case_id in ["proto_y_lab_sample", "proto_z_customs_parcel"]:
		_launch_and_start(case_id)
		_open_tab(0)
		_place_all([0, 1, 3])
		_open_tab(1)
		_place_all([4, 5, 6])
		_commit()
		_check(_label("FeedbackHeadline").text == _t("UI_PROTOTYPE_B_FEEDBACK_SUCCESS_HEADLINE"), "%s: the D1 primary + D3 theory should be accepted" % case_id)
		_continue_after_feedback()
		_check(prototype_b.get_node("%CompletionPanel").visible, "%s: completes" % case_id)
		prototype_b.close()


## Milestone 1.12 regression, applied to Prototype B from the start — see
## prototype_a_scene_test.gd's equivalent for why this checks STRUCTURE and
## BEHAVIOR rather than raw pixel geometry.
func _test_continue_button_stays_reachable_with_long_feedback() -> void:
	var footer: Control = prototype_b.get_node("%Footer")
	var body_scroll: ScrollContainer = prototype_b.get_node("%BodyScroll")
	var continue_button: Button = _button("ContinueButton")
	_check(continue_button.get_parent() == footer and prototype_b.get_node("%ResolutionActionsRow").get_parent() == footer, "Continue and the assistance/partner actions live in the fixed Footer")
	_check(footer.get_parent() == body_scroll.get_parent() and footer.get_index() > body_scroll.get_index(), "Footer is a later sibling than BodyScroll")
	# Milestone 1.14.1: Commit Theory — the primary formal commit — must also
	# live in the fixed Footer, never inside the scrolling body.
	_check(_button("CommitTheoryButton").get_parent() == prototype_b.get_node("%ActionRow") and prototype_b.get_node("%ActionRow").get_parent() == footer, "Commit Theory must live in the fixed Footer's ActionRow")
	var current_action_row: Node = _button("CommitTheoryButton").get_parent()
	var is_in_scroll := false
	while current_action_row != null:
		if current_action_row == body_scroll:
			is_in_scroll = true
			break
		current_action_row = current_action_row.get_parent()
	_check(not is_in_scroll, "Commit Theory must NOT be a descendant of the scrolling BodyScroll")
	for child_name in ["%AssistancePanel", "%PlayArea", "%FeedbackPanel", "%CompletionPanel"]:
		var current: Node = prototype_b.get_node(child_name).get_parent()
		var is_descendant := false
		while current != null:
			if current == body_scroll:
				is_descendant = true
				break
			current = current.get_parent()
		_check(is_descendant, "%s must live inside the scrolling BodyScroll" % child_name)
	_check(prototype_b.get_node("%FeedbackPanel").get_index() < prototype_b.get_node("%PlayArea").get_index(), "FeedbackPanel must be the body's first section, so resetting the scroll shows the feedback — not the play area (Milestone 1.14 visual QA)")

	_launch_and_start()
	_draft_theory([POOL_FORCED_WINDOW, POOL_LATCH_GUIDE, POOL_LOST_PROPERTY_SHEET])
	var synthetic_long: String = "This synthetic sentence exists only to stress the feedback layout. ".repeat(80)
	var second_edits: Array = [[], [POOL_LATCH_GUIDE, POOL_WINDOW_LATCH]]
	var locales: Array = ["vi", "en"]
	for i in locales.size():
		locale_manager.set_locale(locales[i])
		_place_all(second_edits[i])
		_commit()
		_check(prototype_b.get_node("%FeedbackPanel").visible and continue_button.visible and continue_button.has_focus(), "feedback shows with Continue visible and focused (%s)" % locales[i])
		_label("FeedbackExplanation").text = synthetic_long
		_label("FeedbackResolutionNotice").text = synthetic_long
		await process_frame
		await process_frame
		_check(continue_button.visible and continue_button.get_parent() == footer, "Continue stays visible in the footer with far-too-long feedback (%s)" % locales[i])
		_continue_after_feedback()
	locale_manager.set_locale("vi")
	prototype_b.close()


func _export_event_types() -> Array:
	_button("RecorderExportButton").pressed.emit()
	var exported_path: String = _label("StatusLabel").text.trim_prefix("Exported recording to ")
	var types: Array = []
	if FileAccess.file_exists(exported_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(exported_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			for event in (parsed.get("events", []) as Array):
				types.append(event.get("type"))
		DirAccess.remove_absolute(exported_path)
	_button("RecorderStopButton").pressed.emit()
	_button("RecorderClearButton").pressed.emit()
	return types
