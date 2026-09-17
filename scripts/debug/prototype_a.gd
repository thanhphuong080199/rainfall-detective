extends Control
## Developer-only Prototype A — Statement Contradiction (Milestone 1.11 — see
## docs/prototype-a.md): the first genuinely playable deduction interaction —
## read testimony, identify a contradictory statement, present exactly one
## piece of evidence against it. Launched from the Deduction Lab's "Launch
## Prototype A" button, never wired through Main.gd — same isolation stance
## as DebugPanel/DeductionLab (docs/case-debugger.md, docs/deduction-lab.md).
##
## Owns exactly one PrototypeAController (one fresh, isolated
## DeductionSession per run — NEVER the Deduction Lab's own session) and one
## DeductionLabRecorder (Milestone 1.10, reused unmodified). Every submission
## goes through PrototypeAController, which itself only ever calls the real
## DeductionEvaluator/DeductionSession — no grading/validation logic is
## reimplemented here, only rendering, click routing and the Prototype A
## event vocabulary's recorder calls (docs/prototype-a.md, "Recorder
## events").
##
## Milestone 1.14 (docs/resolution-policy.md): renders the confrontation's
## credibility/tier status, the assistance panel once assistance is
## acknowledged, and the footer's Accept Assistance / Resolve with Partner
## actions — all from the presenter's view, never from policy internals.
## Policy state lives in the controller, so closing a dialog, switching locale
## or F1 hide/show can never reset a run's attempts.
##
## In a release export, OS.is_debug_build() is false and _ready() returns
## before doing anything else — the same isolation DebugPanel/DeductionLab
## already use, applied again here in case this scene is ever reparented
## elsewhere.
##
## Hide/show: a permanent child of DeductionLab, never freed or
## re-instantiated — so F1 hiding/showing DebugPanel, or closing/reopening
## the Deduction Lab itself, changes nothing about this script's state. The
## active run lives in _controller for as long as this node exists.
## "Return to Lab" is a distinct, deliberate action (this node's OWN visible
## flag) — unlike F1 hide/show, it ends the run (recording prototype_abandoned
## if incomplete) and is gated behind a confirmation when there is progress.

## Milestone 1.14.1 ("Prevent Deduction Lab show-through"): lets DeductionLab
## restore its own hidden content the instant this overlay actually closes —
## whether via Return to Lab or Esc — without DeductionLab having to poll
## `visible` every frame.
signal closed

var _controller: PrototypeAController
var _recorder: DeductionLabRecorder
var _last_view: Dictionary = {}
var _pending_confirmed_action: Callable = Callable()

@onready var title_label: Label = %TitleLabel
@onready var non_canon_badge: Label = %NonCanonBadge
@onready var return_button: Button = %ReturnButton
@onready var case_option_button: OptionButton = %CaseOptionButton
@onready var start_button: Button = %StartButton
@onready var restart_button: Button = %RestartButton
@onready var objective_label: Label = %ObjectiveLabel
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel
## The CURRENT round's own state only (Milestone 1.14.1) — attempts
## remaining, assistance required, etc. Never the run result; see
## %RunResultLabel and ResolutionPresenter.build_status()'s
## "current_status_text"/"run_result_text" split.
@onready var resolution_status_label: Label = %ResolutionStatusLabel
## The run-wide resolution result only, always shown separately from the
## current round's own status so a fresh round is never misread as itself
## Assisted just because an earlier round used help.
@onready var run_result_label: Label = %RunResultLabel

@onready var assistance_panel: PanelContainer = %AssistancePanel
@onready var assistance_headline: Label = %AssistanceHeadline
@onready var assistance_text: Label = %AssistanceText

@onready var play_area: HBoxContainer = %PlayArea
@onready var statement_list: VBoxContainer = %StatementList
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton
@onready var selection_label: Label = %SelectionLabel
@onready var hint_list: VBoxContainer = %HintList
@onready var hint_notice_label: Label = %HintNoticeLabel
## Milestone 1.14.1: lives in the fixed %Footer now (moved out of the
## scrolling %PlayArea/LeftColumn), so Present Evidence — the primary formal
## commit — can never be pushed offscreen by long assistance/feedback text.
## Its visibility still tracks %PlayArea's own, managed explicitly in
## refresh() since it is no longer PlayArea's descendant.
@onready var action_row: HBoxContainer = %ActionRow
@onready var hint_button: Button = %HintButton
@onready var present_button: Button = %PresentButton
@onready var case_file_label: Label = %CaseFileLabel
@onready var evidence_list: VBoxContainer = %EvidenceList

## BodyScroll (Fixed header / Expandable ScrollContainer / Fixed action
## footer — Milestone 1.12's fix for the Continue-button-pushed-offscreen
## regression, see docs/prototype-a.md, "Layout"): AssistancePanel, PlayArea,
## FeedbackPanel and CompletionPanel all live inside this single scrolling
## body, so however long the localized feedback/completion text is, it
## scrolls instead of growing past the visible window. ContinueButton/
## ResolutionActionsRow/CompletionButtonsRow/RecorderRow live in Footer, a
## fixed sibling AFTER BodyScroll in the outer VBox — a VBoxContainer always
## honors a non-expanding sibling's minimum size, so the footer (and therefore
## Continue and the assistance/partner actions) can never be pushed off
## whatever the scrolling body's content demands.
@onready var body_scroll: ScrollContainer = %BodyScroll

@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var feedback_headline: Label = %FeedbackHeadline
@onready var feedback_explanation: Label = %FeedbackExplanation
@onready var feedback_witness_response: Label = %FeedbackWitnessResponse
@onready var feedback_rebuttal: Label = %FeedbackRebuttal
@onready var feedback_partner_note: Label = %FeedbackPartnerNote
@onready var feedback_resolution_notice: Label = %FeedbackResolutionNotice

@onready var completion_panel: PanelContainer = %CompletionPanel
@onready var completion_title_label: Label = %CompletionTitleLabel
@onready var completion_text_label: Label = %CompletionTextLabel
@onready var stats_list: VBoxContainer = %StatsList

@onready var footer: VBoxContainer = %Footer
@onready var continue_button: Button = %ContinueButton
@onready var resolution_actions_row: HBoxContainer = %ResolutionActionsRow
@onready var accept_assistance_button: Button = %AcceptAssistanceButton
@onready var partner_resolve_button: Button = %PartnerResolveButton
@onready var completion_buttons_row: HBoxContainer = %CompletionButtonsRow
@onready var completion_restart_button: Button = %CompletionRestartButton
@onready var completion_export_button: Button = %CompletionExportButton
@onready var completion_return_button: Button = %CompletionReturnButton

@onready var recorder_start_button: Button = %RecorderStartButton
@onready var recorder_stop_button: Button = %RecorderStopButton
@onready var recorder_clear_button: Button = %RecorderClearButton
@onready var recorder_export_button: Button = %RecorderExportButton
@onready var recorder_status_label: Label = %RecorderStatusLabel

@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		set_process_input(false)
		return

	_controller = PrototypeAController.new()
	_recorder = DeductionLabRecorder.new()

	_apply_static_text()

	return_button.pressed.connect(_on_return_pressed)
	start_button.pressed.connect(_on_start_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	previous_button.pressed.connect(_on_previous_pressed)
	next_button.pressed.connect(_on_next_pressed)
	hint_button.pressed.connect(_on_hint_pressed)
	present_button.pressed.connect(_on_present_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	accept_assistance_button.pressed.connect(_on_accept_assistance_pressed)
	partner_resolve_button.pressed.connect(_on_partner_resolve_pressed)
	completion_restart_button.pressed.connect(_on_restart_pressed)
	completion_export_button.pressed.connect(_on_recorder_export_pressed)
	completion_return_button.pressed.connect(_on_return_pressed)
	recorder_start_button.pressed.connect(_on_recorder_start_pressed)
	recorder_stop_button.pressed.connect(_on_recorder_stop_pressed)
	recorder_clear_button.pressed.connect(_on_recorder_clear_pressed)
	recorder_export_button.pressed.connect(_on_recorder_export_pressed)
	confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)

	LocaleManager.locale_changed.connect(func(_locale): _on_locale_changed())

	_populate_case_options()


func _apply_static_text() -> void:
	title_label.text = tr("UI_PROTOTYPE_A_TITLE")
	non_canon_badge.text = tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")
	return_button.text = tr("UI_PROTOTYPE_A_RETURN_TO_LAB")
	start_button.text = tr("UI_PROTOTYPE_A_START")
	restart_button.text = tr("UI_PROTOTYPE_A_RESTART")
	objective_label.text = tr("UI_PROTOTYPE_A_OBJECTIVE")
	previous_button.text = tr("UI_PROTOTYPE_A_PREVIOUS")
	next_button.text = tr("UI_PROTOTYPE_A_NEXT")
	hint_button.text = tr("UI_PROTOTYPE_A_HINT")
	hint_notice_label.text = tr(ResolutionPresenter.HINT_NOTICE_KEY)
	present_button.text = tr("UI_PROTOTYPE_A_PRESENT")
	case_file_label.text = tr("UI_PROTOTYPE_A_CASE_FILE")
	continue_button.text = tr("UI_PROTOTYPE_A_CONTINUE")
	accept_assistance_button.text = tr("UI_RESOLUTION_ACCEPT_ASSISTANCE")
	partner_resolve_button.text = tr("UI_RESOLUTION_RESOLVE_WITH_PARTNER")
	completion_title_label.text = tr("UI_PROTOTYPE_A_COMPLETE_TITLE")
	completion_restart_button.text = tr("UI_PROTOTYPE_A_RESTART")
	completion_export_button.text = tr("UI_PROTOTYPE_A_RECORDER_EXPORT")
	completion_return_button.text = tr("UI_PROTOTYPE_A_RETURN_TO_LAB")
	recorder_start_button.text = tr("UI_PROTOTYPE_A_RECORDER_START")
	recorder_stop_button.text = tr("UI_PROTOTYPE_A_RECORDER_STOP")
	recorder_clear_button.text = tr("UI_PROTOTYPE_A_RECORDER_CLEAR")
	recorder_export_button.text = tr("UI_PROTOTYPE_A_RECORDER_EXPORT")
	if _controller.get_session() == null:
		status_label.text = tr("UI_PROTOTYPE_A_NO_CASE_SELECTED")


func _on_locale_changed() -> void:
	_apply_static_text()
	_refresh_if_visible()


## _input (not _unhandled_input), and instanced as the LAST child of
## DeductionLab (see DeductionLab.tscn), so this gets first refusal on Esc
## over DeductionLab's own close() — the same "topmost overlay wins" stacking
## rule already used between DebugPanel and DeductionLab
## (docs/deduction-lab.md, "Opening it").
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_return_pressed()
		get_viewport().set_input_as_handled()


## `preferred_case_def`, when given, pre-selects that case in the picker
## (the Deduction Lab's currently active case, per the milestone brief) —
## the facilitator can still change it before pressing Start. Never
## auto-starts: starting is always an explicit action, so a fresh,
## intentional PrototypeAController run is what Start actually creates.
func open(preferred_case_def: Dictionary = {}) -> void:
	visible = true
	_populate_case_options()
	if not preferred_case_def.is_empty():
		_select_case_option(str(preferred_case_def.get("id", "")))
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func _refresh_if_visible() -> void:
	if visible:
		refresh()


func _populate_case_options() -> void:
	case_option_button.clear()
	var ids: Array = ContentDB.get_all_deduction_case_ids()
	ids.sort()
	for raw_id in ids:
		var case_id: String = String(raw_id)
		if typeof(ContentDB.get_deduction_case(case_id).get("prototype_a")) != TYPE_DICTIONARY:
			continue  # Only list cases with a Prototype A data layer.
		case_option_button.add_item(case_id)
		case_option_button.set_item_metadata(case_option_button.get_item_count() - 1, case_id)


func _select_case_option(case_id: String) -> void:
	for i in case_option_button.get_item_count():
		if String(case_option_button.get_item_metadata(i)) == case_id:
			case_option_button.select(i)
			return


# ---------------------------------------------------------------------------
# Lifecycle actions — start / restart / return, each going through the same
# has-progress confirmation gate.

func _on_start_pressed() -> void:
	if case_option_button.get_item_count() == 0:
		_set_status(tr("UI_PROTOTYPE_A_NO_CASE_SELECTED"))
		return
	var case_id: String = String(case_option_button.get_item_metadata(maxi(case_option_button.selected, 0)))
	var case_def: Dictionary = ContentDB.get_deduction_case(case_id)
	if typeof(case_def.get("prototype_a")) != TYPE_DICTIONARY:
		_set_status(tr("UI_PROTOTYPE_A_NO_CASE_SELECTED"))
		return
	if _controller.has_progress():
		_confirm(tr("UI_PROTOTYPE_A_CONFIRM_RESTART"), func(): _start_run(case_def))
		return
	_start_run(case_def)


func _on_restart_pressed() -> void:
	var case_def: Dictionary = _controller.get_case_def()
	if case_def.is_empty():
		_set_status(tr("UI_PROTOTYPE_A_NO_CASE_SELECTED"))
		return
	if _controller.has_progress():
		_confirm(tr("UI_PROTOTYPE_A_CONFIRM_RESTART"), func(): _start_run(case_def))
	else:
		_start_run(case_def)


## Deliberately does NOT stop an in-progress recording — unlike the
## Deduction Lab's own case-switch handler, a recording spanning "pressed
## Start Recording" through "pressed Start" is exactly how prototype_started/
## round_started get captured at all (see docs/prototype-a.md, "Recorder
## events", and the facilitator script in docs/deduction-playtest-plan.md).
## The facilitator can still Stop/Clear explicitly for a fresh boundary. A
## second run on this controller is recorded as prototype_restarted by the
## controller itself.
func _start_run(case_def: Dictionary) -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.start(case_def, _recorder)
	feedback_panel.visible = false
	continue_button.visible = false
	body_scroll.scroll_vertical = 0
	_set_status("")
	refresh()


func _on_return_pressed() -> void:
	if _controller.get_session() != null and not _controller.is_completed() and _controller.has_progress():
		_confirm(tr("UI_PROTOTYPE_A_CONFIRM_EXIT"), _do_return)
	else:
		_do_return()


func _do_return() -> void:
	if _controller.get_session() != null and not _controller.is_completed():
		_controller.abandon()
	close()


func _set_status(message: String) -> void:
	status_label.text = message


func _confirm(message: String, action: Callable) -> void:
	_pending_confirmed_action = action
	confirm_dialog.dialog_text = message
	confirm_dialog.popup_centered()


func _on_confirm_dialog_confirmed() -> void:
	if _pending_confirmed_action.is_valid():
		_pending_confirmed_action.call()
	_pending_confirmed_action = Callable()


# ---------------------------------------------------------------------------
# Rendering — every element is rebuilt from PrototypeAPresenter's player view,
# never from the raw case_def.

func refresh() -> void:
	var started: bool = _controller.get_session() != null
	play_area.visible = started and not _controller.is_completed()
	completion_panel.visible = started and _controller.is_completed()
	completion_buttons_row.visible = completion_panel.visible
	action_row.visible = play_area.visible and not feedback_panel.visible
	if not started:
		progress_label.text = ""
		resolution_status_label.text = ""
		run_result_label.text = ""
		assistance_panel.visible = false
		resolution_actions_row.visible = false
		action_row.visible = false
		_render_recorder()
		return

	_last_view = PrototypeAPresenter.build_player_view(_controller.get_case_def(), _controller)
	var view: Dictionary = _last_view.get("view", {})
	var badge: String = ("  [%s]" % tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")) if view.get("non_canon", false) else ""
	progress_label.text = "%s%s — %s" % [
		view.get("case_title", ""), badge,
		tr("UI_PROTOTYPE_A_ROUND_LABEL") % [int(view.get("round_index", 0)) + 1, view.get("round_count", 1)],
	]
	var status: Dictionary = view.get("resolution_status", {})
	resolution_status_label.text = status.get("current_status_text", "")
	run_result_label.text = status.get("run_result_text", "")
	_render_assistance(view)
	_render_resolution_actions(view)

	if _controller.is_completed():
		action_row.visible = false
		_render_completion(view)
		_render_recorder()
		return

	_render_statements(view)
	_render_evidence(view)
	_render_hints(view)
	_render_selection_label(view)
	present_button.disabled = String(view.get("selected_evidence_handle", "")) == "" or not status.get("can_submit", false)
	previous_button.disabled = _controller.get_statement_index() <= 0
	next_button.disabled = _controller.get_statement_index() >= _controller.get_statement_ids().size() - 1
	_render_recorder()


## Only rendered once the view actually carries an "assistance" block — the
## presenter omits it entirely until assistance was acknowledged.
func _render_assistance(view: Dictionary) -> void:
	var assistance: Dictionary = view.get("assistance", {})
	assistance_panel.visible = not assistance.is_empty()
	if assistance.is_empty():
		return
	assistance_headline.text = assistance.get("headline", "")
	var lines: Array[String] = [String(assistance.get("focus", ""))]
	if String(assistance.get("category_hint", "")) != "":
		lines.append(String(assistance.get("category_hint", "")))
	assistance_text.text = "\n".join(lines)


## The footer's Accept Assistance / Resolve with Partner row. Hidden while
## feedback is open so Continue stays the single, focused next step.
func _render_resolution_actions(view: Dictionary) -> void:
	var status: Dictionary = view.get("resolution_status", {})
	var assistance_required: bool = status.get("assistance_required", false)
	var partner_available: bool = status.get("partner_available", false)
	accept_assistance_button.visible = assistance_required
	partner_resolve_button.visible = partner_available
	resolution_actions_row.visible = not _controller.is_completed() and not feedback_panel.visible \
		and (assistance_required or partner_available)


func _render_statements(view: Dictionary) -> void:
	UiUtil.clear_children(statement_list)
	var statements: Array = view.get("statements", [])
	var current_handle: String = view.get("current_statement_handle", "")
	var focus_handle: String = String((view.get("assistance", {}) as Dictionary).get("statement_handle", ""))
	for i in statements.size():
		var statement: Dictionary = statements[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_current: bool = statement.get("handle", "") == current_handle
		var prefix := "> " if is_current else "  "
		if focus_handle != "" and statement.get("handle", "") == focus_handle:
			prefix += "[%s] " % tr("UI_PROTOTYPE_A_PARTNER_FOCUS_LABEL")
		if statement.get("resolved", false):
			prefix += "[%s] " % (tr("UI_PROTOTYPE_A_FEEDBACK_OPTIONAL_HEADLINE") if statement.get("outcome", "") == "optional" else tr("UI_PROTOTYPE_A_FEEDBACK_SUCCESS_HEADLINE"))
		var speaker: String = statement.get("speaker", "")
		label.text = "%s%s%s" % [prefix, ("(%s) " % speaker) if speaker != "" else "", statement.get("text", "")]
		row.add_child(label)
		if not is_current:
			var view_button := Button.new()
			view_button.text = tr("UI_PROTOTYPE_A_SELECT_BUTTON")
			view_button.pressed.connect(func(): _on_select_statement_pressed(i))
			row.add_child(view_button)
		statement_list.add_child(row)


func _on_select_statement_pressed(index: int) -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.select_statement(index)
	refresh()


func _on_previous_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.previous_statement()
	refresh()


func _on_next_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.next_statement()
	refresh()


func _render_evidence(view: Dictionary) -> void:
	UiUtil.clear_children(evidence_list)
	for evidence in view.get("evidence", []):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var opened: bool = evidence.get("opened", false)
		var selected: bool = evidence.get("selected", false)
		var prefix: String = "[%s] " % tr("UI_PROTOTYPE_A_SELECTED_LABEL") if selected else ""
		var body: String = "%s%s" % [prefix, evidence.get("name", "")]
		if opened:
			body += "\n%s" % evidence.get("text", "")
		else:
			body += "  (%s)" % tr("UI_PROTOTYPE_A_EVIDENCE_UNOPENED")
		label.text = body
		row.add_child(label)

		var handle: String = evidence.get("handle", "")
		if not opened:
			var open_button := Button.new()
			open_button.text = tr("UI_PROTOTYPE_A_EVIDENCE_OPEN_BUTTON")
			open_button.pressed.connect(func(): _on_open_evidence_pressed(handle))
			row.add_child(open_button)
		var select_button := Button.new()
		select_button.text = tr("UI_PROTOTYPE_A_SELECTED_LABEL") if selected else tr("UI_PROTOTYPE_A_SELECT_BUTTON")
		select_button.disabled = selected
		select_button.pressed.connect(func(): _on_select_evidence_pressed(handle))
		row.add_child(select_button)
		evidence_list.add_child(row)


## Opaque-handle resolution: the real evidence/statement id is looked up in
## the presenter's private handle_map ONLY here, at the moment a production
## API is actually called — never carried by the rendered widgets themselves.
## See scripts/deduction/prototype_a_presenter.gd's class doc.
func _on_open_evidence_pressed(handle: String) -> void:
	var real_id: String = String((_last_view.get("handle_map", {}) as Dictionary).get(handle, ""))
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.open_evidence(real_id)
	refresh()


func _on_select_evidence_pressed(handle: String) -> void:
	var real_id: String = String((_last_view.get("handle_map", {}) as Dictionary).get(handle, ""))
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.select_evidence(real_id)
	refresh()


func _render_hints(view: Dictionary) -> void:
	UiUtil.clear_children(hint_list)
	var hint: Dictionary = view.get("hint", {})
	hint_button.disabled = hint.is_empty() or not hint.get("can_reveal_more", false)
	for text in hint.get("levels_revealed", []):
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "• %s" % text
		hint_list.add_child(label)


## A hint that raises the run's tier says so explicitly in the status line —
## never a silent tier change.
func _on_hint_pressed() -> void:
	var statement_id: String = _controller.get_current_statement_id()
	if statement_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.reveal_next_hint(statement_id)
	var notice: String = ResolutionPresenter.build_run_result_notice(result.get("resolution", {}))
	if notice != "":
		_set_status(notice)
	refresh()


## The "confirmation view" (docs/prototype-a.md, "Playable flow"): the
## currently selected statement and evidence, shown together so the player
## reviews both before pressing Present Evidence.
func _render_selection_label(view: Dictionary) -> void:
	var statement: Dictionary = _find_by_handle(view.get("statements", []), view.get("current_statement_handle", ""))
	var evidence: Dictionary = _find_by_handle(view.get("evidence", []), view.get("selected_evidence_handle", ""))
	var evidence_name: String = evidence.get("name", "") if not evidence.is_empty() else tr("UI_PROTOTYPE_A_NONE_SELECTED")
	selection_label.text = "%s:\n\u201c%s\u201d\n\n%s: %s" % [
		tr("UI_PROTOTYPE_A_STATEMENT_LABEL"), statement.get("text", ""), tr("UI_PROTOTYPE_A_CASE_FILE"), evidence_name,
	]


func _find_by_handle(entries: Array, handle: String) -> Dictionary:
	for entry in entries:
		if entry.get("handle", "") == handle:
			return entry
	return {}


func _on_present_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.present_evidence()
	_show_feedback(result)
	refresh()


func _on_accept_assistance_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.accept_assistance()
	_set_status(ResolutionPresenter.build_run_result_notice(result.get("resolution", {})))
	body_scroll.scroll_vertical = 0
	refresh()


func _on_partner_resolve_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.resolve_with_partner()
	_show_feedback(result)
	refresh()


## However long the localized explanation/witness_response text is, Continue
## must stay visible and reachable (Milestone 1.12): the body scrolls back to
## the top so the player sees the headline first, and focus moves onto
## Continue itself — reachable by keyboard immediately, and a sensible resting
## place for focus the instant feedback appears (see PrototypeA.tscn's
## Fixed-header/ScrollContainer/Fixed-footer structure, docs/prototype-a.md).
func _show_feedback(result: Dictionary) -> void:
	var feedback: Dictionary = PrototypeAPresenter.build_feedback(_controller.get_case_def(), result)
	_set_label(feedback_headline, feedback.get("headline", ""))
	feedback_explanation.text = feedback.get("explanation", "")
	_set_label(feedback_witness_response, feedback.get("witness_response", ""))
	_set_label(feedback_rebuttal, feedback.get("rebuttal", ""))
	_set_label(feedback_partner_note, feedback.get("partner_note", ""))
	_set_label(feedback_resolution_notice, feedback.get("resolution_notice", ""))
	feedback_panel.visible = true
	continue_button.visible = true
	body_scroll.scroll_vertical = 0
	continue_button.grab_focus()


func _set_label(label: Label, text: String) -> void:
	label.text = text
	label.visible = text != ""


func _on_continue_pressed() -> void:
	feedback_panel.visible = false
	continue_button.visible = false
	_controller.acknowledge_feedback()
	refresh()
	if accept_assistance_button.is_visible_in_tree():
		accept_assistance_button.grab_focus()
	elif partner_resolve_button.is_visible_in_tree():
		partner_resolve_button.grab_focus()


func _render_completion(view: Dictionary) -> void:
	completion_text_label.text = view.get("completion_text", "")
	UiUtil.clear_children(stats_list)
	for line in view.get("completion_lines", []):
		var label := Label.new()
		label.text = line
		stats_list.add_child(label)


# ---------------------------------------------------------------------------
# Recorder controls — same shape as deduction_lab.gd's own, tagged with the
# "statement_contradiction" prototype id (docs/prototype-a.md, "Recorder
# events"). Prototype A has no Author/Debug mode, so every recorded event
# here uses SOURCE_PLAYER_PREVIEW.

func _render_recorder() -> void:
	recorder_status_label.text = "Recording: %s — %d event(s) captured (session id: %s)." % [
		"ON" if _recorder.is_recording() else "OFF", _recorder.get_events().size(), _recorder.get_session_id(),
	]


## Reads the case id from the PICKER, not from _controller.get_case_def() —
## deliberately, so the facilitator can start recording BEFORE pressing
## Start, and still capture "prototype_started"/"round_started" (see
## docs/prototype-a.md, "Recorder events"; the facilitator script in
## docs/deduction-playtest-plan.md starts recording before the run begins).
func _on_recorder_start_pressed() -> void:
	if case_option_button.get_item_count() == 0:
		_set_status(tr("UI_PROTOTYPE_A_NO_CASE_SELECTED"))
		return
	var case_id: String = String(case_option_button.get_item_metadata(maxi(case_option_button.selected, 0)))
	_recorder.start(case_id, "statement_contradiction", LocaleManager.get_locale())
	_render_recorder()


func _on_recorder_stop_pressed() -> void:
	_recorder.stop()
	_render_recorder()


func _on_recorder_clear_pressed() -> void:
	_recorder.clear()
	_render_recorder()


func _on_recorder_export_pressed() -> void:
	var result: Dictionary = _recorder.export_to_file()
	if result.get("success", false):
		_set_status("Exported recording to %s" % result.get("path", ""))
	else:
		_set_status("Export failed: %s" % result.get("error", ""))
	_render_recorder()
