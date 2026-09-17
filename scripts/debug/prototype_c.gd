extends Control
## Developer-only Prototype C — Timeline Reconstruction (Milestone 1.13 — see
## docs/prototype-c.md): read a set of objective timeline facts, place the
## five movable events into candidate time slots (two events are already
## fixed and locked), submit the reconstruction for the real
## TimelineEvaluator to check, then use the accepted timeline to decide
## whether one disputed NPC claim is possible — and which established fact
## proves it. Launched from the Deduction Lab's "Launch Prototype C" button,
## never wired through Main.gd — same isolation stance as DebugPanel/
## DeductionLab/PrototypeA/PrototypeB.
##
## Owns exactly one PrototypeCController (see that class's doc for why it —
## unlike A/B — owns no DeductionSession at all) and one DeductionLabRecorder
## (Milestone 1.10, reused unmodified). Every submission goes through
## PrototypeCController, which itself only ever calls the real
## TimelineEvaluator — no constraint-evaluation logic is reimplemented here,
## only rendering, click routing and the Prototype C event vocabulary's
## recorder calls (docs/prototype-c.md, "Recorder events").
##
## Milestone 1.14 (docs/resolution-policy.md): renders the formal-commit
## budget and tier, progressive violation feedback (with the involved events
## marked in text), the verdict + supporting-fact claim form, and the footer's
## Accept Assistance / Resolve with Partner actions. Policy state lives in the
## controller, so dialogs, locale switches and F1 hide/show never reset it.
##
## In a release export, OS.is_debug_build() is false and _ready() returns
## before doing anything else — the same isolation DebugPanel/DeductionLab/
## PrototypeA/PrototypeB already use.
##
## Layout: fixed header, a single expandable %BodyScroll (holding
## AssistancePanel/PlayArea/FeedbackPanel/ClaimPanel/CompletionPanel), and a
## fixed %Footer sibling placed AFTER it — the same Milestone 1.12 structure
## that fixed Prototype A's Continue-button regression, applied here from the
## start.
##
## Hide/show: a permanent child of DeductionLab, never freed or
## re-instantiated — so F1 hiding/showing DebugPanel, or closing/reopening
## the Deduction Lab itself, changes nothing about this script's state.
## "Return to Lab" ends the run (recording prototype_abandoned if incomplete)
## and is gated behind a confirmation when there is progress, exactly like
## PrototypeA.gd's/PrototypeB.gd's own Return button.

## Milestone 1.14.1 ("Prevent Deduction Lab show-through"): lets DeductionLab
## restore its own hidden content the instant this overlay actually closes.
signal closed

var _controller: PrototypeCController
var _recorder: DeductionLabRecorder
var _last_view: Dictionary = {}
var _pending_confirmed_action: Callable = Callable()
## Milestone 1.14.2A: see prototype_a.gd's identical field for the full
## rationale (kept separate from %StatusLabel's own verbatim path message).
var _last_summary_export: Dictionary = {}
## Which flow the shared %ContinueButton currently dismisses: "" (hidden),
## "timeline" (dismiss the Check-Timeline feedback panel) or "claim"
## (acknowledge a resolved final-claim check and complete the prototype).
var _continue_action: String = ""
## Opaque event handles the latest fact-level violation feedback named — the
## event cards are marked in words while the player revises.
var _conflict_event_handles: Array[String] = []

@onready var title_label: Label = %TitleLabel
@onready var non_canon_badge: Label = %NonCanonBadge
@onready var return_button: Button = %ReturnButton
@onready var case_option_button: OptionButton = %CaseOptionButton
@onready var start_button: Button = %StartButton
@onready var restart_button: Button = %RestartButton
@onready var objective_label: Label = %ObjectiveLabel
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel
## The current unit's (timeline or claim) own state only (Milestone 1.14.1) —
## never the run result; see %RunResultLabel.
@onready var resolution_status_label: Label = %ResolutionStatusLabel
## The run-wide resolution result only, always shown separately.
@onready var run_result_label: Label = %RunResultLabel

@onready var body_scroll: ScrollContainer = %BodyScroll
@onready var assistance_panel: PanelContainer = %AssistancePanel
@onready var assistance_headline: Label = %AssistanceHeadline
@onready var assistance_text: Label = %AssistanceText
@onready var play_area: HBoxContainer = %PlayArea
@onready var timeline_list: VBoxContainer = %TimelineList
@onready var hint_list: VBoxContainer = %HintList
@onready var hint_notice_label: Label = %HintNoticeLabel
## Milestone 1.14.1: HintButton/CheckButton live in the fixed %Footer now
## (moved out of the scrolling %PlayArea/LeftColumn), so Check Timeline — a
## primary formal commit — can never be pushed offscreen. Visibility tracks
## %PlayArea's own, managed explicitly in refresh().
@onready var action_row: HBoxContainer = %ActionRow
@onready var hint_button: Button = %HintButton
@onready var check_button: Button = %CheckButton
@onready var events_list: VBoxContainer = %EventsList
@onready var facts_list: VBoxContainer = %FactsList

@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var feedback_headline: Label = %FeedbackHeadline
@onready var feedback_violations_list: VBoxContainer = %FeedbackViolationsList
@onready var feedback_resolution_notice: Label = %FeedbackResolutionNotice

@onready var claim_panel: PanelContainer = %ClaimPanel
@onready var claim_statement_label: Label = %ClaimStatementLabel
@onready var claim_instructions_label: Label = %ClaimInstructionsLabel
@onready var claim_buttons_row: HBoxContainer = %ClaimButtonsRow
@onready var claim_fits_button: Button = %ClaimFitsButton
@onready var claim_impossible_button: Button = %ClaimImpossibleButton
@onready var justification_label: Label = %JustificationLabel
@onready var justification_list: VBoxContainer = %JustificationList
## Milestone 1.14.1: lives in the fixed %Footer now (moved out of the
## scrolling %ClaimPanel), so Submit Verdict — the claim unit's formal
## commit — can never be pushed offscreen. No longer a %ClaimPanel
## descendant, so its visibility is managed explicitly (refresh()/
## _render_claim()) instead of inheriting the panel's own visible flag.
@onready var claim_submit_button: Button = %ClaimSubmitButton
@onready var claim_feedback_label: Label = %ClaimFeedbackLabel
@onready var claim_resolution_label: Label = %ClaimResolutionLabel

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

	_controller = PrototypeCController.new()
	_recorder = DeductionLabRecorder.new()

	_apply_static_text()

	return_button.pressed.connect(_on_return_pressed)
	start_button.pressed.connect(_on_start_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	hint_button.pressed.connect(_on_hint_pressed)
	check_button.pressed.connect(_on_check_pressed)
	claim_fits_button.pressed.connect(func(): _on_claim_answer_selected(false))
	claim_impossible_button.pressed.connect(func(): _on_claim_answer_selected(true))
	claim_submit_button.pressed.connect(_on_claim_submit_pressed)
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
	title_label.text = tr("UI_PROTOTYPE_C_TITLE")
	non_canon_badge.text = tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")
	return_button.text = tr("UI_PROTOTYPE_C_RETURN_TO_LAB")
	start_button.text = tr("UI_PROTOTYPE_C_START")
	restart_button.text = tr("UI_PROTOTYPE_C_RESTART")
	hint_button.text = tr("UI_PROTOTYPE_C_HINT")
	hint_notice_label.text = tr(ResolutionPresenter.HINT_NOTICE_KEY)
	check_button.text = tr("UI_PROTOTYPE_C_CHECK_BUTTON")
	continue_button.text = tr("UI_PROTOTYPE_C_CONTINUE")
	claim_instructions_label.text = tr("UI_PROTOTYPE_C_CLAIM_INSTRUCTIONS")
	justification_label.text = tr("UI_PROTOTYPE_C_JUSTIFICATION_LABEL")
	claim_submit_button.text = tr("UI_PROTOTYPE_C_CLAIM_SUBMIT_BUTTON")
	accept_assistance_button.text = tr("UI_RESOLUTION_ACCEPT_ASSISTANCE")
	partner_resolve_button.text = tr("UI_RESOLUTION_RESOLVE_WITH_PARTNER")
	completion_title_label.text = tr("UI_PROTOTYPE_C_COMPLETE_TITLE")
	completion_restart_button.text = tr("UI_PROTOTYPE_C_RESTART")
	completion_export_button.text = tr("UI_PROTOTYPE_C_RECORDER_EXPORT")
	completion_return_button.text = tr("UI_PROTOTYPE_C_RETURN_TO_LAB")
	recorder_start_button.text = tr("UI_PROTOTYPE_C_RECORDER_START")
	recorder_stop_button.text = tr("UI_PROTOTYPE_C_RECORDER_STOP")
	recorder_clear_button.text = tr("UI_PROTOTYPE_C_RECORDER_CLEAR")
	recorder_export_button.text = tr("UI_PROTOTYPE_C_RECORDER_EXPORT")
	if _controller.get_case_def().is_empty():
		status_label.text = tr("UI_PROTOTYPE_C_NO_CASE_SELECTED")


func _on_locale_changed() -> void:
	_apply_static_text()
	_refresh_if_visible()


## _input (not _unhandled_input), instanced as a child of DeductionLab AFTER
## PrototypeA/PrototypeB (see DeductionLab.tscn) — the same "topmost overlay
## wins" stacking rule already used between DebugPanel/DeductionLab/
## PrototypeA/PrototypeB.
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
		if typeof(ContentDB.get_deduction_case(case_id).get("prototype_c")) != TYPE_DICTIONARY:
			continue  # Only list cases with a Prototype C data layer.
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
		_set_status(tr("UI_PROTOTYPE_C_NO_CASE_SELECTED"))
		return
	var case_id: String = String(case_option_button.get_item_metadata(maxi(case_option_button.selected, 0)))
	var case_def: Dictionary = ContentDB.get_deduction_case(case_id)
	if typeof(case_def.get("prototype_c")) != TYPE_DICTIONARY:
		_set_status(tr("UI_PROTOTYPE_C_NO_CASE_SELECTED"))
		return
	if _controller.has_progress():
		_confirm(tr("UI_PROTOTYPE_C_CONFIRM_RESTART"), func(): _start_run(case_def))
		return
	_start_run(case_def)


func _on_restart_pressed() -> void:
	var case_def: Dictionary = _controller.get_case_def()
	if case_def.is_empty():
		_set_status(tr("UI_PROTOTYPE_C_NO_CASE_SELECTED"))
		return
	if _controller.has_progress():
		_confirm(tr("UI_PROTOTYPE_C_CONFIRM_RESTART"), func(): _start_run(case_def))
	else:
		_start_run(case_def)


## Deliberately does NOT stop an in-progress recording — matching
## prototype_a.gd's/prototype_b.gd's own rationale: a recording spanning
## "pressed Start Recording" through "pressed Start" is how prototype_started
## gets captured at all. A second run on this controller is recorded as
## prototype_restarted by the controller itself.
func _start_run(case_def: Dictionary) -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.start(case_def, _recorder)
	feedback_panel.visible = false
	claim_feedback_label.visible = false
	claim_resolution_label.visible = false
	continue_button.visible = false
	_continue_action = ""
	_conflict_event_handles = []
	body_scroll.scroll_vertical = 0
	_set_status("")
	refresh()


func _on_return_pressed() -> void:
	if not _controller.get_case_def().is_empty() and not _controller.is_completed() and _controller.has_progress():
		_confirm(tr("UI_PROTOTYPE_C_CONFIRM_EXIT"), _do_return)
	else:
		_do_return()


func _do_return() -> void:
	if not _controller.get_case_def().is_empty() and not _controller.is_completed():
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
# Rendering — every element is rebuilt from PrototypeCPresenter's player
# view, never from the raw case_def.

func refresh() -> void:
	var started: bool = not _controller.get_case_def().is_empty()
	play_area.visible = started and not _controller.is_accepted() and not _controller.is_completed()
	claim_panel.visible = started and _controller.is_accepted() and not _controller.is_completed()
	completion_panel.visible = started and _controller.is_completed()
	completion_buttons_row.visible = completion_panel.visible
	action_row.visible = play_area.visible and not feedback_panel.visible
	claim_submit_button.visible = false  # _render_claim() turns this on only while the claim is unresolved.
	if not started:
		objective_label.text = ""
		progress_label.text = ""
		resolution_status_label.text = ""
		run_result_label.text = ""
		assistance_panel.visible = false
		resolution_actions_row.visible = false
		action_row.visible = false
		_render_recorder()
		return

	_last_view = PrototypeCPresenter.build_player_view(_controller.get_case_def(), _controller)
	var view: Dictionary = _last_view.get("view", {})
	var badge: String = ("  [%s]" % tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")) if view.get("non_canon", false) else ""
	objective_label.text = view.get("objective", "")
	progress_label.text = "%s%s" % [view.get("case_title", ""), badge]
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

	if _controller.is_accepted():
		action_row.visible = false
		_render_claim(view)
		_render_recorder()
		return

	_render_timeline(view)
	_render_events(view)
	_render_facts(view)
	_render_hints(view)
	check_button.disabled = not view.get("can_check", false)
	_render_recorder()


func _render_assistance(view: Dictionary) -> void:
	var assistance: Dictionary = view.get("assistance", {})
	assistance_panel.visible = not assistance.is_empty()
	if assistance.is_empty():
		return
	assistance_headline.text = assistance.get("headline", "")
	var lines: Array[String] = []
	for key in ["relationship", "text"]:
		if String(assistance.get(key, "")) != "":
			lines.append(String(assistance.get(key, "")))
	assistance_text.text = "\n".join(lines)


## Hidden while feedback is open so Continue stays the single, focused next
## step.
func _render_resolution_actions(view: Dictionary) -> void:
	var status: Dictionary = view.get("resolution_status", {})
	var assistance_required: bool = status.get("assistance_required", false)
	var partner_available: bool = status.get("partner_available", false)
	accept_assistance_button.visible = assistance_required
	partner_resolve_button.visible = partner_available
	resolution_actions_row.visible = not _controller.is_completed() and not feedback_panel.visible \
		and (assistance_required or partner_available)


## Every distinct time point actually in play — the authored candidate slots
## plus wherever the two fixed events are locked — sorted chronologically, so
## the board reads as one merged timeline axis rather than two disconnected
## lists.
func _display_times(view: Dictionary) -> Array[String]:
	var times: Dictionary = {}
	for slot in view.get("time_slots", []):
		times[slot] = true
	for item in view.get("events", []):
		var placement: String = item.get("placement", "")
		if placement != "":
			times[placement] = true
	var out: Array[String] = []
	for t in times:
		out.append(String(t))
	out.sort()
	return out


func _render_timeline(view: Dictionary) -> void:
	UiUtil.clear_children(timeline_list)
	var selected_handle: String = ""
	for item in view.get("events", []):
		if item.get("selected", false):
			selected_handle = item.get("handle", "")
	for time_slot in _display_times(view):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# A row stacking several events carries one Remove button per event;
		# without a floor the wrapping label collapses to one character per
		# line (found in Milestone 1.14 visual QA). The row scrolls instead.
		label.custom_minimum_size = Vector2(180, 0)
		var here: Array = []
		for item in view.get("events", []):
			if item.get("placement", "") == time_slot:
				here.append(item)
		if here.is_empty():
			label.text = "%s — %s" % [time_slot, tr("UI_PROTOTYPE_C_SLOT_EMPTY")]
			row.add_child(label)
			if selected_handle != "":
				var place_button := Button.new()
				place_button.text = tr("UI_PROTOTYPE_C_PLACE_BUTTON")
				place_button.pressed.connect(func(): _on_place_here_pressed(time_slot))
				row.add_child(place_button)
		else:
			var names: Array[String] = []
			for item in here:
				names.append(item.get("label", ""))
			label.text = "%s — %s" % [time_slot, ", ".join(names)]
			row.add_child(label)
			if selected_handle != "":
				var place_button := Button.new()
				place_button.text = tr("UI_PROTOTYPE_C_PLACE_BUTTON")
				place_button.pressed.connect(func(): _on_place_here_pressed(time_slot))
				row.add_child(place_button)
			for item in here:
				if item.get("fixed", false):
					continue
				var remove_button := Button.new()
				remove_button.text = "%s %s" % [tr("UI_PROTOTYPE_C_REMOVE_BUTTON"), item.get("label", "")]
				var handle: String = item.get("handle", "")
				remove_button.pressed.connect(func(): _on_remove_event_pressed(handle))
				row.add_child(remove_button)
		timeline_list.add_child(row)


## Event cards are marked IN WORDS when the latest fact-level feedback named
## them ("conflict") or assistance points at them ("partner focus") — never
## only by color.
func _render_events(view: Dictionary) -> void:
	UiUtil.clear_children(events_list)
	var focus_handles: Array = (view.get("assistance", {}) as Dictionary).get("event_handles", [])
	for item in view.get("events", []):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var duration: int = item.get("duration_minutes", 0)
		var duration_suffix: String = (" (%d min)" % duration) if duration > 0 else ""
		var handle: String = item.get("handle", "")
		var markers: String = ""
		if _conflict_event_handles.has(handle):
			markers += "[%s] " % tr("UI_PROTOTYPE_C_CONFLICT_LABEL")
		if focus_handles.has(handle):
			markers += "[%s] " % tr("UI_PROTOTYPE_A_PARTNER_FOCUS_LABEL")
		if item.get("fixed", false):
			label.text = "%s%s%s — %s [%s]" % [markers, item.get("label", ""), duration_suffix, item.get("placement", ""), tr("UI_PROTOTYPE_C_LOCKED_LABEL")]
			row.add_child(label)
		else:
			var prefix: String = "[%s] " % tr("UI_PROTOTYPE_C_SELECTED_LABEL") if item.get("selected", false) else ""
			var placement: String = item.get("placement", "")
			var placement_text: String = placement if placement != "" else tr("UI_PROTOTYPE_C_SLOT_EMPTY")
			label.text = "%s%s%s%s — %s" % [markers, prefix, item.get("label", ""), duration_suffix, placement_text]
			row.add_child(label)
			var select_button := Button.new()
			select_button.text = tr("UI_PROTOTYPE_C_SELECT_BUTTON")
			select_button.pressed.connect(func(): _on_select_event_pressed(handle))
			row.add_child(select_button)
			if placement != "":
				var remove_button := Button.new()
				remove_button.text = tr("UI_PROTOTYPE_C_REMOVE_BUTTON")
				remove_button.pressed.connect(func(): _on_remove_event_pressed(handle))
				row.add_child(remove_button)
		events_list.add_child(row)


func _render_facts(view: Dictionary) -> void:
	UiUtil.clear_children(facts_list)
	for item in view.get("facts", []):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var opened: bool = item.get("opened", false)
		label.text = item.get("text", "") if opened else tr("UI_PROTOTYPE_C_FACT_UNOPENED")
		row.add_child(label)
		if not opened:
			var handle: String = item.get("handle", "")
			var open_button := Button.new()
			open_button.text = tr("UI_PROTOTYPE_C_FACT_OPEN_BUTTON")
			open_button.pressed.connect(func(): _on_open_fact_pressed(handle))
			row.add_child(open_button)
		facts_list.add_child(row)


func _render_hints(view: Dictionary) -> void:
	UiUtil.clear_children(hint_list)
	var hint: Dictionary = view.get("hint", {})
	hint_button.disabled = hint.is_empty() or not hint.get("can_reveal_more", false)
	for text in hint.get("levels_revealed", []):
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "• %s" % text
		hint_list.add_child(label)


## Opaque-handle resolution: the real id is looked up in the presenter's
## private handle_map ONLY here, at the moment a production API is actually
## called — never carried by the rendered widgets themselves.
func _resolve(handle: String) -> String:
	return String((_last_view.get("handle_map", {}) as Dictionary).get(handle, ""))


func _on_select_event_pressed(handle: String) -> void:
	var real_id: String = _resolve(handle)
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.select_event(real_id)
	refresh()


func _on_place_here_pressed(time_slot: String) -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.place_selected(time_slot)
	refresh()


func _on_remove_event_pressed(handle: String) -> void:
	var real_id: String = _resolve(handle)
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.remove_event(real_id)
	refresh()


func _on_open_fact_pressed(handle: String) -> void:
	var real_id: String = _resolve(handle)
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.open_fact(real_id)
	refresh()


## A hint that raises the run's tier says so explicitly in the status line.
func _on_hint_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.reveal_next_hint()
	var notice: String = ResolutionPresenter.build_run_result_notice(result.get("resolution", {}))
	if notice != "":
		_set_status(notice)
	refresh()


## However long the localized fact/explanation text is, Continue must stay
## visible and reachable (Milestone 1.12's fix, applied here from the start —
## see PrototypeC.tscn's Fixed-header/ScrollContainer/Fixed-footer structure):
## the body scrolls back to the top and focus moves onto Continue itself.
func _on_check_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.submit_timeline()
	if result.get("blocked_duplicate", false):
		refresh()
		return
	_show_violation_feedback(PrototypeCPresenter.build_violation_feedback(_controller.get_case_def(), _controller, result))
	refresh()


func _show_violation_feedback(feedback: Dictionary) -> void:
	UiUtil.clear_children(feedback_violations_list)
	_conflict_event_handles = []
	if feedback.get("accepted", false):
		feedback_headline.text = tr("UI_RESOLUTION_PARTNER_HEADLINE") if feedback.get("partner", false) else tr("UI_PROTOTYPE_C_FEEDBACK_SUCCESS_HEADLINE")
	else:
		feedback_headline.text = feedback.get("message", "")
	var lines: Array[String] = []
	if feedback.get("accepted", false) and feedback.get("partner", false):
		lines.append(String(feedback.get("message", "")))
	for violation in feedback.get("violations", []):
		lines.append("• %s" % violation.get("text", ""))
		if not feedback.get("accepted", false):
			for handle in violation.get("event_handles", []):
				_conflict_event_handles.append(String(handle))
	for line in lines:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = line
		feedback_violations_list.add_child(label)
	feedback_resolution_notice.text = feedback.get("resolution_notice", "")
	feedback_resolution_notice.visible = feedback_resolution_notice.text != ""
	feedback_panel.visible = true
	continue_button.visible = true
	_continue_action = "timeline"
	body_scroll.scroll_vertical = 0
	continue_button.grab_focus()


func _on_continue_pressed() -> void:
	feedback_panel.visible = false
	continue_button.visible = false
	if _continue_action == "claim":
		_controller.acknowledge_claim()
	_continue_action = ""
	refresh()
	if accept_assistance_button.is_visible_in_tree():
		accept_assistance_button.grab_focus()
	elif partner_resolve_button.is_visible_in_tree():
		partner_resolve_button.grab_focus()


func _on_accept_assistance_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.accept_assistance()
	_set_status(ResolutionPresenter.build_run_result_notice(result.get("resolution", {})))
	body_scroll.scroll_vertical = 0
	refresh()


func _on_partner_resolve_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var in_claim_phase: bool = _controller.is_accepted()
	var result: Dictionary = _controller.resolve_with_partner()
	if in_claim_phase:
		var feedback: Dictionary = PrototypeCPresenter.build_claim_feedback(_controller.get_case_def(), _controller, result)
		claim_feedback_label.visible = not feedback.get("correct", false) and String(feedback.get("guidance", "")) != ""
		claim_feedback_label.text = feedback.get("guidance", "")
	else:
		_show_violation_feedback(PrototypeCPresenter.build_violation_feedback(_controller.get_case_def(), _controller, result))
	refresh()


# ---------------------------------------------------------------------------
# Final claim — a verdict plus the established fact that justifies it.

func _render_claim(view: Dictionary) -> void:
	var claim: Dictionary = view.get("claim", {})
	claim_statement_label.text = claim.get("statement_text", "")
	var resolved: bool = view.get("claim_resolved", false)
	for control in [claim_instructions_label, claim_buttons_row, justification_label, justification_list, claim_submit_button]:
		(control as Control).visible = not resolved
	claim_resolution_label.visible = resolved
	if resolved:
		claim_feedback_label.visible = false
		var resolution: Dictionary = view.get("resolution", {})
		var lines: Array[String] = []
		for key in ["partner_note", "explanation", "justification"]:
			if String(resolution.get(key, "")) != "":
				lines.append(String(resolution.get(key, "")))
		claim_resolution_label.text = "\n\n".join(lines)
		continue_button.visible = true
		_continue_action = "claim"
		body_scroll.scroll_vertical = 0
		return

	var selected_prefix: String = "[%s] " % tr("UI_PROTOTYPE_C_SELECTED_LABEL")
	claim_fits_button.text = "%s%s" % [selected_prefix if claim.get("fits_selected", false) else "", tr("UI_PROTOTYPE_C_CLAIM_FITS_BUTTON")]
	claim_impossible_button.text = "%s%s" % [selected_prefix if claim.get("impossible_selected", false) else "", tr("UI_PROTOTYPE_C_CLAIM_IMPOSSIBLE_BUTTON")]
	UiUtil.clear_children(justification_list)
	for option in claim.get("justification_options", []):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected: bool = option.get("selected", false)
		label.text = "%s%s" % [selected_prefix if selected else "", option.get("text", "")]
		row.add_child(label)
		var select_button := Button.new()
		select_button.text = tr("UI_PROTOTYPE_C_SELECTED_LABEL") if selected else tr("UI_PROTOTYPE_C_SELECT_BUTTON")
		select_button.disabled = selected
		var handle: String = option.get("handle", "")
		select_button.pressed.connect(func(): _on_justification_selected(handle))
		row.add_child(select_button)
		justification_list.add_child(row)
	claim_submit_button.disabled = not claim.get("can_submit", false)


func _on_claim_answer_selected(chose_impossible: bool) -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.select_claim_answer(chose_impossible)
	refresh()


func _on_justification_selected(handle: String) -> void:
	var real_id: String = _resolve(handle)
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.select_claim_justification(real_id)
	refresh()


func _on_claim_submit_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.submit_claim()
	var feedback: Dictionary = PrototypeCPresenter.build_claim_feedback(_controller.get_case_def(), _controller, result)
	var lines: Array[String] = []
	for key in ["guidance", "resolution_notice"]:
		if String(feedback.get(key, "")) != "":
			lines.append(String(feedback.get(key, "")))
	claim_feedback_label.text = "\n".join(lines)
	claim_feedback_label.visible = not feedback.get("correct", false) and not lines.is_empty()
	refresh()


# ---------------------------------------------------------------------------
# Completion

func _render_completion(view: Dictionary) -> void:
	completion_text_label.text = view.get("completion_text", "")
	UiUtil.clear_children(stats_list)
	for line in view.get("completion_lines", []):
		var label := Label.new()
		label.text = line
		stats_list.add_child(label)


# ---------------------------------------------------------------------------
# Recorder controls — same shape as prototype_a.gd's/prototype_b.gd's own,
# tagged with the "timeline_reconstruction" prototype id (docs/prototype-c.md,
# "Recorder events"). Prototype C has no Author/Debug mode, so every recorded
# event here uses SOURCE_PLAYER_PREVIEW.

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
## Start, and still capture "prototype_started" (matches prototype_a.gd's/
## prototype_b.gd's own rationale).
func _on_recorder_start_pressed() -> void:
	if case_option_button.get_item_count() == 0:
		_set_status(tr("UI_PROTOTYPE_C_NO_CASE_SELECTED"))
		return
	var case_id: String = String(case_option_button.get_item_metadata(maxi(case_option_button.selected, 0)))
	_recorder.start(case_id, "timeline_reconstruction", LocaleManager.get_locale())
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
