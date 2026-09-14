extends Control
## Developer-only Prototype C — Timeline Reconstruction (Milestone 1.13 — see
## docs/prototype-c.md): read a set of objective timeline facts, place the
## five movable events into candidate time slots (two events are already
## fixed and locked), submit the reconstruction for the real
## TimelineEvaluator to check, then use the accepted timeline to decide
## whether one disputed NPC claim is possible. Launched from the Deduction
## Lab's "Launch Prototype C" button, never wired through Main.gd — same
## isolation stance as DebugPanel/DeductionLab/PrototypeA/PrototypeB.
##
## Owns exactly one PrototypeCController (see that class's doc for why it —
## unlike A/B — owns no DeductionSession at all) and one DeductionLabRecorder
## (Milestone 1.10, reused unmodified). Every submission goes through
## PrototypeCController, which itself only ever calls the real
## TimelineEvaluator — no constraint-evaluation logic is reimplemented here,
## only rendering, click routing and the Prototype C event vocabulary's
## recorder calls (docs/prototype-c.md, "Recorder events").
##
## In a release export, OS.is_debug_build() is false and _ready() returns
## before doing anything else — the same isolation DebugPanel/DeductionLab/
## PrototypeA/PrototypeB already use.
##
## Layout: fixed header, a single expandable %BodyScroll (holding PlayArea/
## FeedbackPanel/ClaimPanel/CompletionPanel), and a fixed %Footer sibling
## placed AFTER it — the same Milestone 1.12 structure that fixed Prototype
## A's Continue-button regression, applied here from the start.
##
## Hide/show: a permanent child of DeductionLab, never freed or
## re-instantiated — so F1 hiding/showing DebugPanel, or closing/reopening
## the Deduction Lab itself, changes nothing about this script's state.
## "Return to Lab" ends the run (recording prototype_abandoned if incomplete)
## and is gated behind a confirmation when there is progress, exactly like
## PrototypeA.gd's/PrototypeB.gd's own Return button.

var _controller: PrototypeCController
var _recorder: DeductionLabRecorder
var _last_view: Dictionary = {}
var _pending_confirmed_action: Callable = Callable()
## Which flow the shared %ContinueButton currently dismisses: "" (hidden),
## "timeline" (dismiss the Check-Timeline feedback panel) or "claim"
## (acknowledge a resolved final-claim check and complete the prototype).
var _continue_action: String = ""

@onready var title_label: Label = %TitleLabel
@onready var non_canon_badge: Label = %NonCanonBadge
@onready var return_button: Button = %ReturnButton
@onready var case_option_button: OptionButton = %CaseOptionButton
@onready var start_button: Button = %StartButton
@onready var restart_button: Button = %RestartButton
@onready var objective_label: Label = %ObjectiveLabel
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel

@onready var body_scroll: ScrollContainer = %BodyScroll
@onready var play_area: HBoxContainer = %PlayArea
@onready var timeline_list: VBoxContainer = %TimelineList
@onready var hint_list: VBoxContainer = %HintList
@onready var hint_button: Button = %HintButton
@onready var check_button: Button = %CheckButton
@onready var events_list: VBoxContainer = %EventsList
@onready var facts_list: VBoxContainer = %FactsList

@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var feedback_headline: Label = %FeedbackHeadline
@onready var feedback_violations_list: VBoxContainer = %FeedbackViolationsList

@onready var claim_panel: PanelContainer = %ClaimPanel
@onready var claim_statement_label: Label = %ClaimStatementLabel
@onready var claim_buttons_row: HBoxContainer = %ClaimButtonsRow
@onready var claim_fits_button: Button = %ClaimFitsButton
@onready var claim_impossible_button: Button = %ClaimImpossibleButton
@onready var claim_feedback_label: Label = %ClaimFeedbackLabel
@onready var claim_resolution_label: Label = %ClaimResolutionLabel

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

	_controller = PrototypeCController.new()
	_recorder = DeductionLabRecorder.new()

	_apply_static_text()

	return_button.pressed.connect(_on_return_pressed)
	start_button.pressed.connect(_on_start_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	hint_button.pressed.connect(_on_hint_pressed)
	check_button.pressed.connect(_on_check_pressed)
	claim_fits_button.pressed.connect(func(): _on_claim_answered(false))
	claim_impossible_button.pressed.connect(func(): _on_claim_answered(true))
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
	title_label.text = tr("UI_PROTOTYPE_C_TITLE")
	non_canon_badge.text = tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")
	return_button.text = tr("UI_PROTOTYPE_C_RETURN_TO_LAB")
	start_button.text = tr("UI_PROTOTYPE_C_START")
	restart_button.text = tr("UI_PROTOTYPE_C_RESTART")
	hint_button.text = tr("UI_PROTOTYPE_C_HINT")
	check_button.text = tr("UI_PROTOTYPE_C_CHECK_BUTTON")
	continue_button.text = tr("UI_PROTOTYPE_C_CONTINUE")
	claim_fits_button.text = tr("UI_PROTOTYPE_C_CLAIM_FITS_BUTTON")
	claim_impossible_button.text = tr("UI_PROTOTYPE_C_CLAIM_IMPOSSIBLE_BUTTON")
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
## "pressed Start Recording" through "pressed Start" is how
## prototype_started/round_started get captured at all.
func _start_run(case_def: Dictionary) -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.start(case_def, _recorder)
	feedback_panel.visible = false
	claim_feedback_label.visible = false
	claim_resolution_label.visible = false
	continue_button.visible = false
	_continue_action = ""
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
	if not started:
		objective_label.text = ""
		progress_label.text = ""
		_render_recorder()
		return

	_last_view = PrototypeCPresenter.build_player_view(_controller.get_case_def(), _controller)
	var view: Dictionary = _last_view.get("view", {})
	var badge: String = ("  [%s]" % tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")) if view.get("non_canon", false) else ""
	objective_label.text = view.get("objective", "")
	progress_label.text = "%s%s" % [view.get("case_title", ""), badge]

	if _controller.is_completed():
		_render_completion(view)
		_render_recorder()
		return

	if _controller.is_accepted():
		_render_claim(view)
		_render_recorder()
		return

	_render_timeline(view)
	_render_events(view)
	_render_facts(view)
	_render_hints(view)
	check_button.disabled = not view.get("can_submit", false) or not view.get("can_resubmit", true)
	_render_recorder()


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


func _render_events(view: Dictionary) -> void:
	UiUtil.clear_children(events_list)
	for item in view.get("events", []):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var duration: int = item.get("duration_minutes", 0)
		var duration_suffix: String = (" (%d min)" % duration) if duration > 0 else ""
		var handle: String = item.get("handle", "")
		if item.get("fixed", false):
			label.text = "%s%s — %s [%s]" % [item.get("label", ""), duration_suffix, item.get("placement", ""), tr("UI_PROTOTYPE_C_LOCKED_LABEL")]
			row.add_child(label)
		else:
			var prefix: String = "[%s] " % tr("UI_PROTOTYPE_C_SELECTED_LABEL") if item.get("selected", false) else ""
			var placement: String = item.get("placement", "")
			var placement_text: String = placement if placement != "" else tr("UI_PROTOTYPE_C_SLOT_EMPTY")
			label.text = "%s%s%s — %s" % [prefix, item.get("label", ""), duration_suffix, placement_text]
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


func _on_hint_pressed() -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.reveal_next_hint()
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
	var feedback: Dictionary = PrototypeCPresenter.build_violation_feedback(_controller.get_case_def(), _controller, result)
	_show_violation_feedback(feedback)
	refresh()


func _show_violation_feedback(feedback: Dictionary) -> void:
	UiUtil.clear_children(feedback_violations_list)
	if feedback.get("accepted", false):
		feedback_headline.text = tr("UI_PROTOTYPE_C_FEEDBACK_SUCCESS_HEADLINE")
	elif feedback.get("invalid", false):
		feedback_headline.text = feedback.get("message", "")
	else:
		feedback_headline.text = tr("UI_PROTOTYPE_C_VIOLATIONS_LABEL")
		for violation in feedback.get("violations", []):
			var label := Label.new()
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.text = "• %s" % violation.get("text", "")
			feedback_violations_list.add_child(label)
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


# ---------------------------------------------------------------------------
# Final claim check

func _render_claim(view: Dictionary) -> void:
	var claim: Dictionary = view.get("claim", {})
	claim_statement_label.text = claim.get("statement_text", "")
	var resolved: bool = view.get("claim_resolved", false)
	claim_buttons_row.visible = not resolved
	claim_resolution_label.visible = resolved
	if resolved:
		claim_resolution_label.text = view.get("resolution", {}).get("explanation", "")
		continue_button.visible = true
		_continue_action = "claim"
		body_scroll.scroll_vertical = 0


func _on_claim_answered(chose_impossible: bool) -> void:
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	var result: Dictionary = _controller.answer_claim(chose_impossible)
	var feedback: Dictionary = PrototypeCPresenter.build_claim_feedback(result)
	claim_feedback_label.visible = not feedback.get("correct", false)
	claim_feedback_label.text = feedback.get("guidance", "")
	refresh()


# ---------------------------------------------------------------------------
# Completion

func _render_completion(view: Dictionary) -> void:
	completion_text_label.text = view.get("completion_text", "")
	UiUtil.clear_children(stats_list)
	var stats: Dictionary = view.get("stats", {})
	var total_seconds: int = int(float(stats.get("elapsed_ms", 0)) / 1000.0)
	var time_text: String = "%d:%02d" % [total_seconds / 60, total_seconds % 60]
	for line in [
		tr("UI_PROTOTYPE_C_STATS_TIME") % time_text,
		tr("UI_PROTOTYPE_C_STATS_SUBMISSIONS") % int(stats.get("submissions", 0)),
		tr("UI_PROTOTYPE_C_STATS_FAILED") % int(stats.get("failed", 0)),
		tr("UI_PROTOTYPE_C_STATS_MOVES") % int(stats.get("moves", 0)),
		tr("UI_PROTOTYPE_C_STATS_FACTS_OPENED") % int(stats.get("facts_opened", 0)),
		tr("UI_PROTOTYPE_C_STATS_HINTS") % int(stats.get("hints_used", 0)),
		tr("UI_PROTOTYPE_C_STATS_CLAIM_ATTEMPTS") % int(stats.get("claim_attempts", 0)),
	]:
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


func _on_recorder_export_pressed() -> void:
	var result: Dictionary = _recorder.export_to_file()
	if result.get("success", false):
		_set_status("Exported recording to %s" % result.get("path", ""))
	else:
		_set_status("Export failed: %s" % result.get("error", ""))
	_render_recorder()
