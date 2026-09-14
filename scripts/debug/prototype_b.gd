extends Control
## Developer-only Prototype B — Clue Connection (Milestone 1.12 — see
## docs/prototype-b.md): read an investigation question, place the clues that
## jointly establish a deduction into a fixed number of connection slots, and
## submit the connection. Launched from the Deduction Lab's "Launch
## Prototype B" button, never wired through Main.gd — same isolation stance
## as DebugPanel/DeductionLab/PrototypeA.
##
## Owns exactly one PrototypeBController (one fresh, isolated
## DeductionSession per run — NEVER the Deduction Lab's own session, NEVER a
## PrototypeAController's) and one DeductionLabRecorder (Milestone 1.10,
## reused unmodified). Every submission goes through PrototypeBController,
## which itself only ever calls the real DeductionEvaluator/DeductionSession
## — no grading/validation logic is reimplemented here, only rendering, click
## routing and the Prototype B event vocabulary's recorder calls
## (docs/prototype-b.md, "Recorder events").
##
## In a release export, OS.is_debug_build() is false and _ready() returns
## before doing anything else — the same isolation DebugPanel/DeductionLab/
## PrototypeA already use.
##
## Layout: fixed header, a single expandable %BodyScroll (holding PlayArea/
## FeedbackPanel/CompletionPanel), and a fixed %Footer sibling placed AFTER
## it — the same Milestone 1.12 structure that fixed Prototype A's
## Continue-button regression, applied here from the start so Prototype B
## never reproduces it (see docs/prototype-a.md, "Layout").
##
## Hide/show: a permanent child of DeductionLab, never freed or
## re-instantiated — so F1 hiding/showing DebugPanel, or closing/reopening
## the Deduction Lab itself, changes nothing about this script's state.
## "Return to Lab" ends the run (recording prototype_abandoned if incomplete)
## and is gated behind a confirmation when there is progress, exactly like
## PrototypeA.gd's own Return button.

var _controller: PrototypeBController
var _recorder: DeductionLabRecorder
var _last_view: Dictionary = {}
var _pending_confirmed_action: Callable = Callable()

@onready var title_label: Label = %TitleLabel
@onready var non_canon_badge: Label = %NonCanonBadge
@onready var return_button: Button = %ReturnButton
@onready var case_option_button: OptionButton = %CaseOptionButton
@onready var start_button: Button = %StartButton
@onready var restart_button: Button = %RestartButton
@onready var question_label: Label = %QuestionLabel
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel

@onready var body_scroll: ScrollContainer = %BodyScroll
@onready var play_area: HBoxContainer = %PlayArea
@onready var slots_list: VBoxContainer = %SlotsList
@onready var hint_list: VBoxContainer = %HintList
@onready var hint_button: Button = %HintButton
@onready var connect_button: Button = %ConnectButton
@onready var case_file_label: Label = %CaseFileLabel
@onready var evidence_list: VBoxContainer = %EvidenceList

@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var feedback_headline: Label = %FeedbackHeadline
@onready var feedback_deduction_text: Label = %FeedbackDeductionText
@onready var feedback_explanation: Label = %FeedbackExplanation

@onready var completion_panel: PanelContainer = %CompletionPanel
@onready var completion_title_label: Label = %CompletionTitleLabel
@onready var completion_text_label: Label = %CompletionTextLabel
@onready var stats_list: VBoxContainer = %StatsList

@onready var footer: VBoxContainer = %Footer
@onready var continue_button: Button = %ContinueButton
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
	connect_button.pressed.connect(_on_connect_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
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
	connect_button.text = tr("UI_PROTOTYPE_B_CONNECT")
	case_file_label.text = tr("UI_PROTOTYPE_B_CASE_FILE")
	continue_button.text = tr("UI_PROTOTYPE_B_CONTINUE")
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
## Recording" through "pressed Start" is how prototype_started/round_started
## get captured at all.
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
	if not started:
		progress_label.text = ""
		question_label.text = ""
		_render_recorder()
		return

	_last_view = PrototypeBPresenter.build_player_view(_controller.get_case_def(), _controller)
	var view: Dictionary = _last_view.get("view", {})
	var badge: String = ("  [%s]" % tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")) if view.get("non_canon", false) else ""
	progress_label.text = "%s%s — %s" % [
		view.get("case_title", ""), badge,
		tr("UI_PROTOTYPE_B_ROUND_LABEL") % [int(view.get("round_index", 0)) + 1, view.get("round_count", 1)],
	]

	if _controller.is_completed():
		_render_completion(view)
		_render_recorder()
		return

	question_label.text = "%s: %s" % [tr("UI_PROTOTYPE_B_QUESTION_LABEL"), view.get("question", "")]
	_render_slots(view)
	_render_evidence(view)
	_render_hints(view)
	connect_button.disabled = not view.get("can_submit", false)
	_render_recorder()


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
			toggle_button.pressed.connect(func(): _on_remove_evidence_pressed(handle))
		else:
			toggle_button.text = tr("UI_PROTOTYPE_B_PLACE_BUTTON")
			toggle_button.disabled = not _controller.has_room()
			toggle_button.pressed.connect(func(): _on_select_evidence_pressed(handle))
		row.add_child(toggle_button)
		evidence_list.add_child(row)


## Opaque-handle resolution: the real evidence id is looked up in the
## presenter's private handle_map ONLY here, at the moment a production API
## is actually called — never carried by the rendered widgets themselves.
## See scripts/deduction/prototype_b_presenter.gd's class doc.
func _resolve(handle: String) -> String:
	return String((_last_view.get("handle_map", {}) as Dictionary).get(handle, ""))


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


func _on_hint_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.reveal_next_hint()
	refresh()


func _on_connect_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.submit_connection()
	_show_feedback(result)
	refresh()


## However long the localized deduction/explanation text is, Continue must
## stay visible and reachable (Milestone 1.12, applied here from the start
## — see PrototypeB.tscn's Fixed-header/ScrollContainer/Fixed-footer
## structure): the body scrolls back to the top and focus moves onto
## Continue itself.
func _show_feedback(result: Dictionary) -> void:
	var feedback: Dictionary = PrototypeBPresenter.build_feedback(_controller.get_case_def(), _controller, result)
	feedback_headline.text = feedback.get("headline", "")
	feedback_headline.visible = String(feedback.get("headline", "")) != ""
	feedback_deduction_text.text = feedback.get("deduction_text", "")
	feedback_deduction_text.visible = String(feedback.get("deduction_text", "")) != ""
	feedback_explanation.text = feedback.get("explanation", "")
	feedback_panel.visible = true
	continue_button.visible = true
	body_scroll.scroll_vertical = 0
	continue_button.grab_focus()


func _on_continue_pressed() -> void:
	feedback_panel.visible = false
	continue_button.visible = false
	_controller.acknowledge_result()
	refresh()


func _render_completion(view: Dictionary) -> void:
	completion_text_label.text = view.get("completion_text", "")
	UiUtil.clear_children(stats_list)
	var stats: Dictionary = view.get("stats", {})
	var total_seconds: int = int(float(stats.get("elapsed_ms", 0)) / 1000.0)
	var time_text: String = "%d:%02d" % [total_seconds / 60, total_seconds % 60]
	for line in [
		tr("UI_PROTOTYPE_B_STATS_TIME") % time_text,
		tr("UI_PROTOTYPE_B_STATS_ATTEMPTS") % int(stats.get("attempts", 0)),
		tr("UI_PROTOTYPE_B_STATS_FAILED") % int(stats.get("failed", 0)),
		tr("UI_PROTOTYPE_B_STATS_OPENED") % int(stats.get("opened", 0)),
		tr("UI_PROTOTYPE_B_STATS_REPLACEMENTS") % int(stats.get("replacements", 0)),
		tr("UI_PROTOTYPE_B_STATS_HINTS") % int(stats.get("hints_used", 0)),
	]:
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


## Reads the case id from the PICKER, not from _controller.get_case_def() —
## deliberately, so the facilitator can start recording BEFORE pressing
## Start, and still capture "prototype_started"/"round_started" (matches
## prototype_a.gd's own rationale).
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


func _on_recorder_export_pressed() -> void:
	var result: Dictionary = _recorder.export_to_file()
	if result.get("success", false):
		_set_status("Exported recording to %s" % result.get("path", ""))
	else:
		_set_status("Export failed: %s" % result.get("error", ""))
	_render_recorder()
