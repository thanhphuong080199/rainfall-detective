extends Control
## Developer-only Prototype B — Clue Connection (Milestone 1.12 — see
## docs/prototype-b.md): read the investigation questions, draft which clues
## jointly establish each deduction into a fixed number of connection slots,
## and commit the whole theory. Launched from the Deduction Lab's "Launch
## Prototype B" button, never wired through Main.gd — same isolation stance
## as DebugPanel/DeductionLab/PrototypeA.
##
## Owns exactly one PrototypeBController (one fresh, isolated
## DeductionSession per run — NEVER the Deduction Lab's own session, NEVER a
## PrototypeAController's) and one DeductionLabRecorder (Milestone 1.10,
## reused unmodified). Every commit goes through PrototypeBController, which
## itself only ever calls the real DeductionEvaluator/DeductionSession — no
## grading/validation logic is reimplemented here, only rendering, click
## routing and the Prototype B event vocabulary's recorder calls
## (docs/prototype-b.md, "Recorder events").
##
## Milestone 1.14 (docs/resolution-policy.md): one draft tab per question,
## always labeled "Unverified Draft"; Save Draft and tab switching are free;
## Commit Theory is the single formal commit (both drafts, atomically). The
## header shows the commit budget and tier, the footer offers Accept
## Assistance / Resolve with Partner once the policy allows them. Policy
## state lives in the controller, so dialogs, locale switches and F1 hide/show
## can never reset attempts.
##
## In a release export, OS.is_debug_build() is false and _ready() returns
## before doing anything else — the same isolation DebugPanel/DeductionLab/
## PrototypeA already use.
##
## Layout: fixed header, a single expandable %BodyScroll (holding
## AssistancePanel/PlayArea/FeedbackPanel/CompletionPanel), and a fixed
## %Footer sibling placed AFTER it — the same Milestone 1.12 structure that
## fixed Prototype A's Continue-button regression, applied here from the start
## so Prototype B never reproduces it (see docs/prototype-a.md, "Layout").
##
## Hide/show: a permanent child of DeductionLab, never freed or
## re-instantiated — so F1 hiding/showing DebugPanel, or closing/reopening
## the Deduction Lab itself, changes nothing about this script's state.
## "Return to Lab" ends the run (recording prototype_abandoned if incomplete)
## and is gated behind a confirmation when there is progress, exactly like
## PrototypeA.gd's own Return button.

## Milestone 1.14.1 ("Prevent Deduction Lab show-through"): lets DeductionLab
## restore its own hidden content the instant this overlay actually closes.
signal closed

var _controller: PrototypeBController
var _recorder: DeductionLabRecorder
var _last_view: Dictionary = {}
var _pending_confirmed_action: Callable = Callable()
## Milestone 1.14.2A: see prototype_a.gd's identical field for the full
## rationale (kept separate from %StatusLabel's own verbatim path message).
var _last_summary_export: Dictionary = {}

@onready var title_label: Label = %TitleLabel
@onready var non_canon_badge: Label = %NonCanonBadge
@onready var return_button: Button = %ReturnButton
@onready var case_option_button: OptionButton = %CaseOptionButton
@onready var start_button: Button = %StartButton
@onready var restart_button: Button = %RestartButton
@onready var question_label: Label = %QuestionLabel
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel
## The current question's own draft/commit state only (Milestone 1.14.1) —
## never the run result; see %RunResultLabel.
@onready var resolution_status_label: Label = %ResolutionStatusLabel
## The run-wide resolution result only, always shown separately.
@onready var run_result_label: Label = %RunResultLabel

@onready var body_scroll: ScrollContainer = %BodyScroll
@onready var assistance_panel: PanelContainer = %AssistancePanel
@onready var assistance_headline: Label = %AssistanceHeadline
@onready var assistance_text: Label = %AssistanceText
@onready var play_area: HBoxContainer = %PlayArea
@onready var draft_tabs_row: HBoxContainer = %DraftTabsRow
@onready var draft_status_label: Label = %DraftStatusLabel
@onready var slots_list: VBoxContainer = %SlotsList
@onready var hint_list: VBoxContainer = %HintList
@onready var hint_notice_label: Label = %HintNoticeLabel
@onready var commit_help_label: Label = %CommitHelpLabel
## Milestone 1.14.1: lives in the fixed %Footer now (moved out of the
## scrolling %PlayArea/LeftColumn), so Commit Theory — the primary formal
## commit — can never be pushed offscreen. Visibility tracks %PlayArea's own,
## managed explicitly in refresh() since it is no longer PlayArea's descendant.
@onready var action_row: HBoxContainer = %ActionRow
@onready var hint_button: Button = %HintButton
@onready var save_draft_button: Button = %SaveDraftButton
@onready var commit_theory_button: Button = %CommitTheoryButton
@onready var case_file_label: Label = %CaseFileLabel
@onready var evidence_list: VBoxContainer = %EvidenceList

@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var feedback_headline: Label = %FeedbackHeadline
@onready var feedback_deduction_text: Label = %FeedbackDeductionText
@onready var feedback_explanation: Label = %FeedbackExplanation
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

	_controller = PrototypeBController.new()
	_recorder = DeductionLabRecorder.new()

	_apply_static_text()

	return_button.pressed.connect(_on_return_pressed)
	start_button.pressed.connect(_on_start_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	hint_button.pressed.connect(_on_hint_pressed)
	save_draft_button.pressed.connect(_on_save_draft_pressed)
	commit_theory_button.pressed.connect(_on_commit_theory_pressed)
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
	title_label.text = tr("UI_PROTOTYPE_B_TITLE")
	non_canon_badge.text = tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")
	return_button.text = tr("UI_PROTOTYPE_B_RETURN_TO_LAB")
	start_button.text = tr("UI_PROTOTYPE_B_START")
	restart_button.text = tr("UI_PROTOTYPE_B_RESTART")
	hint_button.text = tr("UI_PROTOTYPE_B_HINT")
	hint_notice_label.text = tr(ResolutionPresenter.HINT_NOTICE_KEY)
	commit_help_label.text = tr("UI_PROTOTYPE_B_COMMIT_HELP")
	save_draft_button.text = tr("UI_PROTOTYPE_B_SAVE_DRAFT")
	commit_theory_button.text = tr("UI_PROTOTYPE_B_COMMIT_THEORY")
	case_file_label.text = tr("UI_PROTOTYPE_B_CASE_FILE")
	continue_button.text = tr("UI_PROTOTYPE_B_CONTINUE")
	accept_assistance_button.text = tr("UI_RESOLUTION_ACCEPT_ASSISTANCE")
	partner_resolve_button.text = tr("UI_RESOLUTION_RESOLVE_WITH_PARTNER")
	completion_title_label.text = tr("UI_PROTOTYPE_B_COMPLETE_TITLE")
	completion_restart_button.text = tr("UI_PROTOTYPE_B_RESTART")
	completion_export_button.text = tr("UI_PROTOTYPE_B_RECORDER_EXPORT")
	completion_return_button.text = tr("UI_PROTOTYPE_B_RETURN_TO_LAB")
	recorder_start_button.text = tr("UI_PROTOTYPE_B_RECORDER_START")
	recorder_stop_button.text = tr("UI_PROTOTYPE_B_RECORDER_STOP")
	recorder_clear_button.text = tr("UI_PROTOTYPE_B_RECORDER_CLEAR")
	recorder_export_button.text = tr("UI_PROTOTYPE_B_RECORDER_EXPORT")
	if _controller.get_session() == null:
		status_label.text = tr("UI_PROTOTYPE_B_NO_CASE_SELECTED")


func _on_locale_changed() -> void:
	_apply_static_text()
	_refresh_if_visible()


## _input (not _unhandled_input), and instanced as a child of DeductionLab
## AFTER PrototypeA (see DeductionLab.tscn), so whichever of the two is
## actually open gets first refusal on Esc over DeductionLab's own close() —
## the same "topmost overlay wins" stacking rule already used between
## DebugPanel and DeductionLab (docs/deduction-lab.md, "Opening it").
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_return_pressed()
		get_viewport().set_input_as_handled()


## `preferred_case_def`, when given, pre-selects that case in the picker (the
## Deduction Lab's currently active case) — the facilitator can still change
## it before pressing Start. Never auto-starts.
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
		if typeof(ContentDB.get_deduction_case(case_id).get("prototype_b")) != TYPE_DICTIONARY:
			continue  # Only list cases with a Prototype B data layer.
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
		_set_status(tr("UI_PROTOTYPE_B_NO_CASE_SELECTED"))
		return
	var case_id: String = String(case_option_button.get_item_metadata(maxi(case_option_button.selected, 0)))
	var case_def: Dictionary = ContentDB.get_deduction_case(case_id)
	if typeof(case_def.get("prototype_b")) != TYPE_DICTIONARY:
		_set_status(tr("UI_PROTOTYPE_B_NO_CASE_SELECTED"))
		return
	if _controller.has_progress():
		_confirm(tr("UI_PROTOTYPE_B_CONFIRM_RESTART"), func(): _start_run(case_def))
		return
	_start_run(case_def)


func _on_restart_pressed() -> void:
	var case_def: Dictionary = _controller.get_case_def()
	if case_def.is_empty():
		_set_status(tr("UI_PROTOTYPE_B_NO_CASE_SELECTED"))
		return
	if _controller.has_progress():
		_confirm(tr("UI_PROTOTYPE_B_CONFIRM_RESTART"), func(): _start_run(case_def))
	else:
		_start_run(case_def)


## Deliberately does NOT stop an in-progress recording — matching
## prototype_a.gd's own rationale: a recording spanning "pressed Start
## Recording" through "pressed Start" is how prototype_started gets captured
## at all. A second run on this controller is recorded as prototype_restarted
## by the controller itself.
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
		_confirm(tr("UI_PROTOTYPE_B_CONFIRM_EXIT"), _do_return)
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
# Rendering — every element is rebuilt from PrototypeBPresenter's player
# view, never from the raw case_def.

func refresh() -> void:
	var started: bool = _controller.get_session() != null
	play_area.visible = started and not _controller.is_completed()
	completion_panel.visible = started and _controller.is_completed()
	completion_buttons_row.visible = completion_panel.visible
	action_row.visible = play_area.visible and not feedback_panel.visible
	if not started:
		progress_label.text = ""
		question_label.text = ""
		resolution_status_label.text = ""
		run_result_label.text = ""
		assistance_panel.visible = false
		resolution_actions_row.visible = false
		action_row.visible = false
		_render_recorder()
		return

	_last_view = PrototypeBPresenter.build_player_view(_controller.get_case_def(), _controller)
	var view: Dictionary = _last_view.get("view", {})
	var badge: String = ("  [%s]" % tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")) if view.get("non_canon", false) else ""
	progress_label.text = "%s%s" % [view.get("case_title", ""), badge]
	var status: Dictionary = view.get("resolution_status", {})
	resolution_status_label.text = status.get("current_status_text", "")
	run_result_label.text = status.get("run_result_text", "")
	_render_assistance(view)
	_render_resolution_actions(view)

	if _controller.is_completed():
		question_label.text = ""
		action_row.visible = false
		_render_completion(view)
		_render_recorder()
		return

	var active: Dictionary = _find_by_handle(view.get("drafts", []), view.get("active_draft_handle", ""))
	question_label.text = "%s %d: %s" % [tr("UI_PROTOTYPE_B_QUESTION_LABEL"), int(active.get("number", 1)), view.get("question", "")]
	_render_draft_tabs(view)
	var saved_text: String = tr("UI_PROTOTYPE_B_DRAFT_SAVED_LABEL") if active.get("saved", false) else tr("UI_PROTOTYPE_B_DRAFT_UNSAVED_LABEL")
	draft_status_label.text = "%s (%s)" % [tr("UI_PROTOTYPE_B_DRAFT_STATUS") % [int(active.get("filled_count", 0)), int(active.get("slot_count", 0))], saved_text]
	_render_slots(view)
	_render_evidence(view)
	_render_hints(view)
	commit_theory_button.disabled = not view.get("can_commit", false)
	save_draft_button.disabled = view.get("theory_accepted", false)
	_render_recorder()


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


## Hidden while feedback is open so Continue stays the single, focused next
## step.
func _render_resolution_actions(view: Dictionary) -> void:
	var status: Dictionary = view.get("resolution_status", {})
	var assistance_required: bool = status.get("assistance_required", false)
	var partner_available: bool = status.get("partner_available", false) and not view.get("theory_accepted", false)
	accept_assistance_button.visible = assistance_required
	partner_resolve_button.visible = partner_available
	resolution_actions_row.visible = not _controller.is_completed() and not feedback_panel.visible \
		and (assistance_required or partner_available)


## One button per question draft. The label says which draft is current and
## how many slots are filled — in words, never only by color — and never
## anything about correctness.
func _render_draft_tabs(view: Dictionary) -> void:
	UiUtil.clear_children(draft_tabs_row)
	var focus_handle: String = String((view.get("assistance", {}) as Dictionary).get("draft_handle", ""))
	for draft in view.get("drafts", []):
		var button := Button.new()
		var parts: Array[String] = [tr("UI_PROTOTYPE_B_DRAFT_TAB") % int(draft.get("number", 0))]
		parts.append(tr("UI_PROTOTYPE_B_DRAFT_FILLED") % [int(draft.get("filled_count", 0)), int(draft.get("slot_count", 0))])
		if draft.get("active", false):
			parts.append(tr("UI_PROTOTYPE_B_DRAFT_TAB_CURRENT"))
		if focus_handle != "" and draft.get("handle", "") == focus_handle:
			parts.append(tr("UI_PROTOTYPE_A_PARTNER_FOCUS_LABEL"))
		button.text = " · ".join(parts)
		button.disabled = draft.get("active", false)
		var handle: String = draft.get("handle", "")
		button.pressed.connect(func(): _on_draft_tab_pressed(handle))
		draft_tabs_row.add_child(button)


func _render_slots(view: Dictionary) -> void:
	UiUtil.clear_children(slots_list)
	var evidence_by_handle: Dictionary = {}
	for item in view.get("evidence", []):
		evidence_by_handle[item.get("handle", "")] = item
	for slot in view.get("slots", []):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var slot_prefix: String = tr("UI_PROTOTYPE_B_SLOT_LABEL") % (int(slot.get("index", 0)) + 1)
		if slot.get("filled", false):
			var evidence_handle: String = slot.get("evidence_handle", "")
			var item: Dictionary = evidence_by_handle.get(evidence_handle, {})
			label.text = "%s: %s" % [slot_prefix, item.get("name", "")]
			row.add_child(label)
			if not view.get("theory_accepted", false):
				var remove_button := Button.new()
				remove_button.text = tr("UI_PROTOTYPE_B_REMOVE_BUTTON")
				remove_button.pressed.connect(func(): _on_remove_evidence_pressed(evidence_handle))
				row.add_child(remove_button)
		else:
			label.text = "%s: %s" % [slot_prefix, tr("UI_PROTOTYPE_B_SLOT_EMPTY")]
			row.add_child(label)
		slots_list.add_child(row)


func _render_evidence(view: Dictionary) -> void:
	UiUtil.clear_children(evidence_list)
	var accepted: bool = view.get("theory_accepted", false)
	for item in view.get("evidence", []):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected: bool = item.get("selected", false)
		var opened: bool = item.get("opened", false)
		var prefix: String = "[%s] " % tr("UI_PROTOTYPE_B_PLACED_LABEL") if selected else ""
		var body: String = "%s%s" % [prefix, item.get("name", "")]
		if opened:
			body += "\n%s" % item.get("text", "")
		else:
			body += "  %s" % tr("UI_PROTOTYPE_B_EVIDENCE_UNOPENED")
		label.text = body
		row.add_child(label)

		var handle: String = item.get("handle", "")
		if not opened:
			var open_button := Button.new()
			open_button.text = tr("UI_PROTOTYPE_B_EVIDENCE_OPEN_BUTTON")
			open_button.pressed.connect(func(): _on_open_evidence_pressed(handle))
			row.add_child(open_button)
		var toggle_button := Button.new()
		if selected:
			toggle_button.text = tr("UI_PROTOTYPE_B_REMOVE_BUTTON")
			toggle_button.disabled = accepted
			toggle_button.pressed.connect(func(): _on_remove_evidence_pressed(handle))
		else:
			toggle_button.text = tr("UI_PROTOTYPE_B_PLACE_BUTTON")
			toggle_button.disabled = accepted or not _controller.has_room()
			toggle_button.pressed.connect(func(): _on_select_evidence_pressed(handle))
		row.add_child(toggle_button)
		evidence_list.add_child(row)


func _find_by_handle(entries: Array, handle: String) -> Dictionary:
	for entry in entries:
		if entry.get("handle", "") == handle:
			return entry
	return {}


## Opaque-handle resolution: the real evidence id (or draft index) is looked
## up in the presenter's private handle_map ONLY here, at the moment a
## production API is actually called — never carried by the rendered widgets
## themselves. See scripts/deduction/prototype_b_presenter.gd's class doc.
func _resolve(handle: String) -> String:
	return String((_last_view.get("handle_map", {}) as Dictionary).get(handle, ""))


func _on_draft_tab_pressed(handle: String) -> void:
	var real_index: String = _resolve(handle)
	if not real_index.is_valid_int():
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.select_draft(real_index.to_int())
	refresh()


func _on_open_evidence_pressed(handle: String) -> void:
	var real_id: String = _resolve(handle)
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.open_evidence(real_id)
	refresh()


func _on_select_evidence_pressed(handle: String) -> void:
	var real_id: String = _resolve(handle)
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.select_evidence(real_id)
	refresh()


func _on_remove_evidence_pressed(handle: String) -> void:
	var real_id: String = _resolve(handle)
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.remove_evidence(real_id)
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


## A hint that raises the run's tier says so explicitly in the status line.
func _on_hint_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.reveal_next_hint()
	var notice: String = ResolutionPresenter.build_run_result_notice(result.get("resolution", {}))
	if notice != "":
		_set_status(notice)
	refresh()


## Saving never evaluates anything — the status line says so.
func _on_save_draft_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	if _controller.save_draft():
		_set_status(tr("UI_PROTOTYPE_B_DRAFT_SAVED_STATUS"))
	refresh()


func _on_commit_theory_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.commit_theory()
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


## However long the localized deduction/explanation text is, Continue must
## stay visible and reachable (Milestone 1.12, applied here from the start
## — see PrototypeB.tscn's Fixed-header/ScrollContainer/Fixed-footer
## structure): the body scrolls back to the top and focus moves onto
## Continue itself.
func _show_feedback(result: Dictionary) -> void:
	var feedback: Dictionary = PrototypeBPresenter.build_feedback(_controller.get_case_def(), _controller, result)
	_set_label(feedback_headline, feedback.get("headline", ""))
	_set_label(feedback_deduction_text, feedback.get("deduction_text", ""))
	feedback_explanation.text = feedback.get("explanation", "")
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
	_controller.acknowledge_result()
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
# Recorder controls — same shape as prototype_a.gd's own, tagged with the
# "clue_connection" prototype id (docs/prototype-b.md, "Recorder events").
# Prototype B has no Author/Debug mode, so every recorded event here uses
# SOURCE_PLAYER_PREVIEW.

func _render_recorder() -> void:
	recorder_status_label.text = "Recording: %s — %d event(s) captured (session id: %s)." % [
		"ON" if _recorder.is_recording() else "OFF", _recorder.get_events().size(), _recorder.get_session_id(),
	]
	if not _controller.get_case_def().is_empty():
		# Milestone 1.14.2A: a live, developer-facing digest of THIS run —
		# independent of whether recording is on, since it reads the
		# controller's own get_stats(), never the recorder's event log.
		recorder_status_label.text += "\nStats: %s" % PrototypeEvaluationSummary.format_stats_line(_controller.get_stats())
	if not _last_summary_export.is_empty():
		if _last_summary_export.get("success", false):
			recorder_status_label.text += "\nSummary exported to %s" % _last_summary_export.get("path", "")
		else:
			recorder_status_label.text += "\nSummary export failed: %s" % _last_summary_export.get("error", "")


## Reads the case id from the PICKER, not from _controller.get_case_def() —
## deliberately, so the facilitator can start recording BEFORE pressing
## Start, and still capture "prototype_started" (matches prototype_a.gd's own
## rationale).
func _on_recorder_start_pressed() -> void:
	if case_option_button.get_item_count() == 0:
		_set_status(tr("UI_PROTOTYPE_B_NO_CASE_SELECTED"))
		return
	var case_id: String = String(case_option_button.get_item_metadata(maxi(case_option_button.selected, 0)))
	_recorder.start(case_id, "clue_connection", LocaleManager.get_locale())
	_render_recorder()


func _on_recorder_stop_pressed() -> void:
	_recorder.stop()
	_render_recorder()


func _on_recorder_clear_pressed() -> void:
	_recorder.clear()
	_render_recorder()


## Milestone 1.14.2A: alongside the raw event log, also exports a compact
## evaluation summary (PrototypeEvaluationSummary) to a SEPARATE sibling
## file — see prototype_a.gd's identical handler for the full rationale
## (%StatusLabel's own message stays byte-for-byte unchanged; the summary
## export's outcome is reported through %RecorderStatusLabel instead).
func _on_recorder_export_pressed() -> void:
	var result: Dictionary = _recorder.export_to_file()
	if result.get("success", false):
		_set_status("Exported recording to %s" % result.get("path", ""))
		_last_summary_export = PrototypeEvaluationSummary.export_to_file(_recorder.to_export_dict(), DeductionLabRecorder.DEFAULT_EXPORT_DIR)
	else:
		_set_status("Export failed: %s" % result.get("error", ""))
	_render_recorder()
