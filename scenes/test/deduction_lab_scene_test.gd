extends SceneTree
## Scene/integration tests for the Deduction Lab (Milestone 1.10 — see
## docs/deduction-lab.md): instantiation as a DebugPanel child, F1 hide/show
## session preservation, Player/Author mode instantiation, malformed-
## selection safety, and bilingual coverage of the non-canon badge. This is
## the FULL-only counterpart to the FAST controller/presenter/recorder tests
## — it exercises the real scene tree, which those pure-class tests
## deliberately don't need. Run with:
##   godot --headless --path . -s res://scenes/test/deduction_lab_scene_test.gd

var main_instance: Node
var debug_panel: Control
var deduction_lab: Control
var locale_manager: Node
var content_db: Node
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	locale_manager = get_root().get_node("LocaleManager")
	content_db = get_root().get_node("ContentDB")
	TestHelpers.isolate_locale(locale_manager, "deduction_lab_scene_test")

	main_instance = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_root().add_child(main_instance)
	await process_frame

	print("=== Deduction Lab — scene/integration tests ===")
	debug_panel = main_instance.get_node("%DebugPanel")
	_check(is_instance_valid(debug_panel), "DebugPanel should instantiate without error")
	deduction_lab = debug_panel.get_node("%DeductionLab")
	_check(is_instance_valid(deduction_lab), "DeductionLab should instantiate as a child of DebugPanel")
	_check(not deduction_lab.visible, "DeductionLab should start hidden (no production navigation path)")

	if OS.is_debug_build():
		_test_open_close_and_debug_panel_integration()
		_test_prototype_overlay_hides_lab_content()
		_test_case_selection_and_modes()
		_test_author_debug_actions()
		_test_recorder_controls()
		_test_hide_show_preserves_session()
		_test_malformed_selection_does_not_crash()
		_test_translation_coverage()
	else:
		print("(skipped interactive Deduction Lab checks — not a debug build; OS.is_debug_build() gate could not be exercised either way here, see docs/deduction-lab.md's Known limitations)")

	locale_manager.set_locale("vi")  # leave the project's default in place for whatever runs after this
	main_instance.queue_free()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


## Selects `case_id` and, if switching away from progress requires
## confirmation, auto-confirms it (simulating a user who always says yes) —
## the confirmation flow ITSELF (cancel preserves state, confirm replaces it)
## is already exhaustively covered by deduction_lab_controller_test.gd; this
## helper just needs to reliably land on `case_id` for the rest of a scene test.
func _select_case(case_id: String) -> void:
	var option: OptionButton = deduction_lab.get_node("%CaseOptionButton")
	for i in option.get_item_count():
		if String(option.get_item_metadata(i)) == case_id:
			option.select(i)
			break
	var select_button: Button = deduction_lab.get_node("%SelectCaseButton")
	select_button.pressed.emit()
	# Auto-confirm unconditionally: _on_confirm_dialog_confirmed() safely no-ops
	# when nothing is actually pending, and popup_centered()'s Window visibility
	# isn't a reliable signal in a headless run.
	(deduction_lab.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()


func _test_open_close_and_debug_panel_integration() -> void:
	# Opening the Lab must not disturb DebugPanel's own tabs/state.
	debug_panel.open()
	_check(debug_panel.visible, "sanity — DebugPanel should open normally with the new tab present")
	var lab_tab_button: Button = debug_panel.get_node("%OpenDeductionLabButton")
	_check(is_instance_valid(lab_tab_button), "DebugPanel should have an Open Deduction Lab button")

	deduction_lab.open()
	_check(deduction_lab.visible, "open() should make the Lab visible")
	var option: OptionButton = deduction_lab.get_node("%CaseOptionButton")
	_check(option.get_item_count() == content_db.get_all_deduction_case_ids().size(), "the case selector should list every loaded deduction case")

	deduction_lab.close()
	_check(not deduction_lab.visible, "close() should hide the Lab")
	deduction_lab.open()


## Milestone 1.14.1 ("Prevent Deduction Lab show-through"): opening any
## Prototype overlay must hide the Lab's OWN content (%DimBackground,
## %CenterPanel) — not merely dim it, and not merely rely on the overlay's
## opaque background — so no Lab text or control can visibly bleed through
## OR receive mouse/keyboard input while hidden, and returning restores the
## Lab's session untouched. See scripts/debug/deduction_lab.gd,
## _set_own_content_visible()/_on_prototype_closed().
func _test_prototype_overlay_hides_lab_content() -> void:
	var center_panel: Control = deduction_lab.get_node("%CenterPanel")
	var dim_background: Control = deduction_lab.get_node("%DimBackground")
	var close_button: Button = deduction_lab.get_node("%CloseButton")
	var prototype_a: Control = deduction_lab.get_node("%PrototypeA")
	var prototype_b: Control = deduction_lab.get_node("%PrototypeB")
	var prototype_c: Control = deduction_lab.get_node("%PrototypeC")

	deduction_lab.open()
	_select_case("proto_x_archive_ledger")
	_check(center_panel.visible and dim_background.visible, "sanity — the Lab's own content is visible before any prototype opens")

	# Realistic scenario: the CloseButton already holds keyboard focus (as it
	# would after a real click) BEFORE the overlay opens.
	close_button.grab_focus()
	_check(close_button.has_focus(), "sanity — grab_focus() should succeed on a visible, focusable control")

	(deduction_lab.get_node("%LaunchPrototypeAButton") as Button).pressed.emit()
	_check(prototype_a.visible, "Prototype A should be open")
	_check(not center_panel.visible and not dim_background.visible, "opening Prototype A must hide the Lab's own content, not merely dim it")
	_check(not close_button.is_visible_in_tree(), "the Lab's CloseButton must not be visible in the tree while hidden behind Prototype A")
	_check(not close_button.has_focus(), "hiding the Lab's own content must release any keyboard focus a now-hidden Lab control held, so Enter/Space can never re-trigger it")
	# Mouse: the overlay's own root blocks every click from ever reaching a
	# hidden Lab control underneath, regardless of that control's own state.
	_check(prototype_a.mouse_filter == Control.MOUSE_FILTER_STOP, "the open Prototype A overlay must consume every click over its full-rect area, never letting one reach a hidden Lab control beneath it")

	# Opening a second prototype from the Lab must close the first (never
	# leaving it interactable behind the new one) and keep the Lab hidden —
	# never flash it visible in between.
	(deduction_lab.get_node("%LaunchPrototypeBButton") as Button).pressed.emit()
	_check(prototype_b.visible and not prototype_a.visible, "launching Prototype B must close Prototype A, never leave both open")
	_check(not center_panel.visible and not dim_background.visible, "the Lab's own content must stay hidden while Prototype B is open")

	prototype_b.close()
	_check(not prototype_b.visible, "sanity — Prototype B closed")
	_check(center_panel.visible and dim_background.visible, "returning from Prototype B must restore the Lab's own content")
	var option: OptionButton = deduction_lab.get_node("%CaseOptionButton")
	_check(String(option.get_item_metadata(maxi(option.selected, 0))) == "proto_x_archive_ledger", "the Lab's session (selected case) must be exactly as it was, never reset by hiding/restoring")

	# F1 hide/show while a prototype is open must not disturb any of this.
	(deduction_lab.get_node("%LaunchPrototypeCButton") as Button).pressed.emit()
	_check(prototype_c.visible and not center_panel.visible, "sanity — Prototype C open, Lab content hidden")
	debug_panel.close()
	debug_panel.open()
	deduction_lab.open()
	_check(prototype_c.visible and not center_panel.visible and not dim_background.visible, "F1 hide/show must not restore the Lab's content while a prototype is still open")
	prototype_c.close()
	_check(center_panel.visible and dim_background.visible, "returning from Prototype C must restore the Lab's own content")


func _test_case_selection_and_modes() -> void:
	_select_case("proto_x_archive_ledger")
	_check(deduction_lab.get_node("%StatusLabel").text.contains("proto_x_archive_ledger"), "starting a case should update the status label")
	var overview_list: VBoxContainer = deduction_lab.get_node("%OverviewList")
	_check(overview_list.get_child_count() > 0, "the Overview tab should render content once a case is active (Player mode)")

	var tabs: TabContainer = deduction_lab.get_node("%Tabs")
	var author_tab: Control = deduction_lab.get_node("%AuthorTab")
	_check(tabs.is_tab_hidden(tabs.get_tab_idx_from_control(author_tab)), "the Author tab should start hidden in Player mode")

	var author_button: Button = deduction_lab.get_node("%ModeAuthorButton")
	author_button.pressed.emit()
	_check(author_button.disabled, "the active mode's button should visibly mark itself active (not color alone — also disabled/labelled)")
	_check(not tabs.is_tab_hidden(tabs.get_tab_idx_from_control(author_tab)), "the Author tab should become visible once Author Inspector mode is active")
	var author_list: VBoxContainer = deduction_lab.get_node("%AuthorList")
	_check(author_list.get_child_count() > 0, "the Author tab should render validation/debug content")
	var validation_text: String = (author_list.get_child(1) as Label).text if author_list.get_child_count() > 1 else ""
	_check(validation_text.contains("0 error(s)"), "a real prototype case should validate with zero errors, shown directly in the Author tab: got \"%s\"" % validation_text)

	var player_button: Button = deduction_lab.get_node("%ModePlayerButton")
	player_button.pressed.emit()
	_check(tabs.is_tab_hidden(tabs.get_tab_idx_from_control(author_tab)), "the Author tab should hide again once Player Preview mode is reactivated")


## Clicks through every Author-only debug action button once, on a fresh
## case, proving the real wiring end to end (button -> handler ->
## DeductionEvaluator/TimelineEvaluator -> refresh) — not just that the
## underlying evaluators behave correctly in isolation (already covered by
## deduction_cases_test.gd/deduction_evaluator_test.gd).
func _test_author_debug_actions() -> void:
	_select_case("proto_z_customs_parcel")
	(deduction_lab.get_node("%ModeAuthorButton") as Button).pressed.emit()

	(deduction_lab.get_node("%ValidateTimelineButton") as Button).pressed.emit()
	var validate_status: String = (deduction_lab.get_node("%AuthorActionStatusLabel") as Label).text
	_check(validate_status.contains("timeline_consistent"), 'VALIDATE AUTHORED TIMELINE should report the real TimelineEvaluator result, got "%s"' % validate_status)

	(deduction_lab.get_node("%RevealNextHintButton") as Button).pressed.emit()
	var hint_status: String = (deduction_lab.get_node("%AuthorActionStatusLabel") as Label).text
	_check(hint_status.contains("Revealed hint level 1"), 'REVEAL NEXT HINT should reveal level 1 via the real DeductionEvaluator.request_hint(), got "%s"' % hint_status)

	(deduction_lab.get_node("%AutoSolvePrimaryButton") as Button).pressed.emit()
	var solve_status: String = (deduction_lab.get_node("%AuthorActionStatusLabel") as Label).text
	_check(solve_status.contains("valid_support"), 'AUTO-SOLVE PRIMARY PROOF should report valid_support categories, got "%s"' % solve_status)
	var overview_author_text: String = _overview_text()
	_check(overview_author_text.contains("Session solved: true"), "auto-solving the primary proof path should actually solve the case, reflected live in the Overview tab")

	(deduction_lab.get_node("%ModePlayerButton") as Button).pressed.emit()


func _test_recorder_controls() -> void:
	var start_button: Button = deduction_lab.get_node("%RecorderStartButton")
	var stop_button: Button = deduction_lab.get_node("%RecorderStopButton")
	var clear_button: Button = deduction_lab.get_node("%RecorderClearButton")
	var export_button: Button = deduction_lab.get_node("%RecorderExportButton")
	var status_label: Label = deduction_lab.get_node("%RecorderStatusLabel")

	start_button.pressed.emit()
	_check(status_label.text.contains("Recording: ON"), 'starting a recording should show "Recording: ON", got "%s"' % status_label.text)
	stop_button.pressed.emit()
	_check(status_label.text.contains("Recording: OFF"), "stopping should show Recording: OFF")
	_check(not status_label.text.contains("0 event(s)"), "events captured before Stop should still be reported")
	clear_button.pressed.emit()
	_check(status_label.text.contains("0 event(s)"), "Clear should empty the recorded event list")

	start_button.pressed.emit()
	export_button.pressed.emit()
	var export_status: String = (deduction_lab.get_node("%StatusLabel") as Label).text
	_check(export_status.contains("Exported recording to"), 'a successful export should report its path in the status line, got "%s"' % export_status)
	stop_button.pressed.emit()

	# This test uses the recorder's real DEFAULT_EXPORT_DIR (a shared, real
	# user:// folder — the point is proving the button's default wiring), so
	# clean up the ONE file it just created rather than leaving a stray
	# artifact behind, and never touch anything else that might already be
	# there (see docs/architecture.md, "Known limitations" on the shared
	# user:// folder).
	var exported_path: String = export_status.trim_prefix("Exported recording to ")
	if FileAccess.file_exists(exported_path):
		DirAccess.remove_absolute(exported_path)


func _find_first_evidence_open_button() -> Button:
	var evidence_list: VBoxContainer = deduction_lab.get_node("%EvidenceList")
	for row in evidence_list.get_children():
		for child in row.get_children():
			if child is Button:
				return child
	return null


func _count_opened_evidence_rows() -> int:
	var evidence_list: VBoxContainer = deduction_lab.get_node("%EvidenceList")
	var count := 0
	for row in evidence_list.get_children():
		for child in row.get_children():
			if child is Label and String((child as Label).text).begins_with("[opened]"):
				count += 1
	return count


func _test_hide_show_preserves_session() -> void:
	_select_case("proto_y_lab_sample")
	var open_button: Button = _find_first_evidence_open_button()
	_check(open_button != null, "at least one unopened evidence item should be rendered to test with")
	if open_button != null:
		open_button.pressed.emit()
	var opened_before: int = _count_opened_evidence_rows()
	_check(opened_before > 0, "opening an evidence item should be reflected in the rendered evidence list")

	debug_panel.close()
	_check(not debug_panel.visible, "closing DebugPanel (F1) should hide it")
	_check(deduction_lab.visible, "the Lab's OWN visible flag must be untouched by DebugPanel.close() — screen invisibility here is purely inherited from the hidden ancestor, not a state change")
	debug_panel.open()
	_check(debug_panel.visible and deduction_lab.visible, "reopening DebugPanel (F1) should show the Lab exactly as it was left")
	_check(_count_opened_evidence_rows() == opened_before, "the same evidence must still be marked opened after an F1 hide/show round trip — the active session was never touched")
	_check(deduction_lab.get_node("%StatusLabel").text.contains("proto_y_lab_sample"), "the active case must still be proto_y_lab_sample after the round trip")


func _test_malformed_selection_does_not_crash() -> void:
	var option: OptionButton = deduction_lab.get_node("%CaseOptionButton")
	option.clear()
	var select_button: Button = deduction_lab.get_node("%SelectCaseButton")
	select_button.pressed.emit()
	_check(is_instance_valid(deduction_lab), "selecting with an empty case list must fail visibly (a status message), not crash the scene")
	_check(deduction_lab.get_node("%StatusLabel").text != "", "a failed/empty selection should leave a visible status message rather than silently doing nothing")


func _test_translation_coverage() -> void:
	locale_manager.set_locale("en")
	deduction_lab.refresh()
	var en_badge: String = deduction_lab.get_node("%NonCanonBadge").text
	locale_manager.set_locale("vi")
	deduction_lab.refresh()
	var vi_badge: String = deduction_lab.get_node("%NonCanonBadge").text
	_check(en_badge == "NON-CANON PROTOTYPE", 'the English non-canon badge should read the translated string, got "%s"' % en_badge)
	_check(vi_badge != "" and vi_badge != en_badge, 'the Vietnamese non-canon badge should be non-empty and differ from English, got "%s"' % vi_badge)

	# Case content itself is DED_PROTO_* keys already covered end to end by
	# deduction_cases_test.gd/ContentValidator — spot-check that the Overview
	# tab actually shows DIFFERENT text per locale, proving the Lab's own
	# rendering path (not just the translation table) is locale-aware.
	locale_manager.set_locale("en")
	deduction_lab.refresh()
	var en_overview: String = _overview_text()
	locale_manager.set_locale("vi")
	deduction_lab.refresh()
	var vi_overview: String = _overview_text()
	_check(en_overview != "" and vi_overview != "" and en_overview != vi_overview, "the Overview tab's rendered text should differ between English and Vietnamese for the same case/session state")


func _overview_text() -> String:
	var overview_list: VBoxContainer = deduction_lab.get_node("%OverviewList")
	var text := ""
	for child in overview_list.get_children():
		if child is Label:
			text += String((child as Label).text)
	return text
