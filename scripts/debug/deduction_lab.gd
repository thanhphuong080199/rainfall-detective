extends Control
## Developer-only Deduction Lab (Milestone 1.10 — see docs/deduction-lab.md):
## a mechanic-neutral shell for inspecting and reading the three non-canon
## prototype deduction cases (X/Y/Z). Launched from the F1 Case Debugger's
## "Deduction Lab" tab, never wired through Main.gd — same isolation stance
## as DebugPanel itself (docs/case-debugger.md).
##
## Owns exactly one DeductionLabController (one active DeductionSession) and
## one DeductionLabRecorder. Everything this scene displays or mutates goes
## through those, DeductionEvaluator, TimelineEvaluator, DeductionValidator
## and DeductionLabPresenter — no deduction/evaluation/validation logic is
## reimplemented here, only rendering and click routing.
##
## In a release export, OS.is_debug_build() is false and _ready() returns
## before doing anything else — the exact same isolation DebugPanel already
## uses, applied again here in case this scene is ever reparented elsewhere.
##
## Hide/show: this node is a permanent child of DebugPanel, never freed or
## re-instantiated by DebugPanel.open()/close() — so hiding/showing the F1
## panel changes nothing about this script's state. The active session lives
## in _controller for as long as this node exists.

const MODE_PLAYER := "player"
const MODE_AUTHOR := "author"

var _controller: DeductionLabController
var _recorder: DeductionLabRecorder
var _last_player_result: Dictionary = {}
var _last_author_view: Dictionary = {}
var _last_validation_errors: Array[String] = []
var _last_validation_warnings: Array[String] = []
var _pending_confirmed_action: Callable = Callable()

@onready var non_canon_badge: Label = %NonCanonBadge
@onready var close_button: Button = %CloseButton
@onready var case_option_button: OptionButton = %CaseOptionButton
@onready var select_case_button: Button = %SelectCaseButton
@onready var reset_button: Button = %ResetButton
@onready var mode_player_button: Button = %ModePlayerButton
@onready var mode_author_button: Button = %ModeAuthorButton
@onready var launch_prototype_a_button: Button = %LaunchPrototypeAButton
@onready var prototype_a: Control = %PrototypeA
## Milestone 1.12: launched the same way as Prototype A — a fresh
## PrototypeBController/DeductionSession, never this Lab's own, never
## Prototype A's. See scripts/debug/prototype_b.gd.
@onready var launch_prototype_b_button: Button = %LaunchPrototypeBButton
@onready var prototype_b: Control = %PrototypeB
## Milestone 1.13: launched the same way as Prototype A/B — a fresh
## PrototypeCController with NO DeductionSession at all (see that class's own
## doc), never this Lab's own session, never Prototype A's or B's. See
## scripts/debug/prototype_c.gd.
@onready var launch_prototype_c_button: Button = %LaunchPrototypeCButton
@onready var prototype_c: Control = %PrototypeC
@onready var status_label: Label = %StatusLabel
@onready var tabs: TabContainer = %Tabs
@onready var author_tab: Control = %AuthorTab

@onready var overview_list: VBoxContainer = %OverviewList
@onready var evidence_search_edit: LineEdit = %EvidenceSearchEdit
@onready var evidence_filter_option: OptionButton = %EvidenceFilterOption
@onready var evidence_list: VBoxContainer = %EvidenceList
@onready var claims_list: VBoxContainer = %ClaimsList
@onready var timeline_list: VBoxContainer = %TimelineList
@onready var hints_list: VBoxContainer = %HintsList

@onready var auto_solve_primary_button: Button = %AutoSolvePrimaryButton
@onready var auto_solve_alternate_button: Button = %AutoSolveAlternateButton
@onready var reveal_next_hint_button: Button = %RevealNextHintButton
@onready var validate_timeline_button: Button = %ValidateTimelineButton
@onready var author_reset_button: Button = %AuthorResetButton
@onready var author_action_status_label: Label = %AuthorActionStatusLabel
@onready var author_list: VBoxContainer = %AuthorList

@onready var recorder_start_button: Button = %RecorderStartButton
@onready var recorder_stop_button: Button = %RecorderStopButton
@onready var recorder_clear_button: Button = %RecorderClearButton
@onready var recorder_export_button: Button = %RecorderExportButton
@onready var recorder_status_label: Label = %RecorderStatusLabel
@onready var recorder_list: VBoxContainer = %RecorderList

@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		set_process_input(false)
		return

	_controller = DeductionLabController.new()
	_recorder = DeductionLabRecorder.new()

	non_canon_badge.text = tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")
	close_button.pressed.connect(close)
	select_case_button.pressed.connect(_on_select_case_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	mode_player_button.pressed.connect(func(): _on_mode_pressed(MODE_PLAYER))
	mode_author_button.pressed.connect(func(): _on_mode_pressed(MODE_AUTHOR))
	launch_prototype_a_button.pressed.connect(_on_launch_prototype_a_pressed)
	launch_prototype_a_button.text = tr("UI_PROTOTYPE_A_LAUNCH_BUTTON")
	launch_prototype_b_button.pressed.connect(_on_launch_prototype_b_pressed)
	launch_prototype_b_button.text = tr("UI_PROTOTYPE_B_LAUNCH_BUTTON")
	launch_prototype_c_button.pressed.connect(_on_launch_prototype_c_pressed)
	launch_prototype_c_button.text = tr("UI_PROTOTYPE_C_LAUNCH_BUTTON")
	confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)

	evidence_search_edit.text_changed.connect(func(_text): _render_evidence())
	evidence_filter_option.add_item("All", 0)
	evidence_filter_option.add_item("Opened", 1)
	evidence_filter_option.add_item("Unopened", 2)
	evidence_filter_option.select(0)
	evidence_filter_option.item_selected.connect(func(_index): _render_evidence())

	auto_solve_primary_button.pressed.connect(func(): _on_auto_solve_pressed(false))
	auto_solve_alternate_button.pressed.connect(func(): _on_auto_solve_pressed(true))
	reveal_next_hint_button.pressed.connect(_on_author_reveal_hint_pressed)
	validate_timeline_button.pressed.connect(_on_validate_timeline_pressed)
	author_reset_button.pressed.connect(_on_reset_pressed)

	recorder_start_button.pressed.connect(_on_recorder_start_pressed)
	recorder_stop_button.pressed.connect(_on_recorder_stop_pressed)
	recorder_clear_button.pressed.connect(_on_recorder_clear_pressed)
	recorder_export_button.pressed.connect(_on_recorder_export_pressed)

	LocaleManager.locale_changed.connect(func(_locale): _refresh_if_visible())

	_populate_case_options()
	_update_mode_buttons()


## _input (not _unhandled_input) to beat InvestigationView, matching
## DebugPanel's own rationale — and this node is the LAST child of DebugPanel
## (see DebugPanel.tscn), so it gets first refusal on Esc over DebugPanel's
## own close(), the same "topmost overlay wins" stacking rule documented in
## docs/architecture.md.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	status_label.text = ""
	visible = true
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
	for i in ids.size():
		case_option_button.add_item(String(ids[i]))
		case_option_button.set_item_metadata(i, String(ids[i]))


# ---------------------------------------------------------------------------
# Case selection / session lifecycle — every mutation goes through
# DeductionLabController's own confirmation flow, never a direct field poke.

func _on_select_case_pressed() -> void:
	if case_option_button.get_item_count() == 0:
		_set_status("No deduction cases are loaded.")
		return
	var selected_index: int = maxi(case_option_button.selected, 0)
	var case_id: String = String(case_option_button.get_item_metadata(selected_index))
	var case_def: Dictionary = ContentDB.get_deduction_case(case_id)
	if case_def.is_empty():
		_set_status('Unknown case id "%s".' % case_id)
		return

	match _controller.request_case_switch(case_def):
		"switched":
			_on_case_started()
		"pending_confirmation":
			_confirm('Switch to "%s"? The current case has progress that will be lost.' % case_id, _confirm_case_switch)
		"invalid":
			_set_status('Could not start case "%s" (malformed content).' % case_id)
	refresh()


func _confirm_case_switch() -> void:
	_controller.confirm_case_switch()
	_on_case_started()
	refresh()


func _on_case_started() -> void:
	# A fresh case deserves a fresh recording boundary — stop (never discard)
	# any recording that spanned the previous case before rewiring.
	if _recorder.is_recording():
		_recorder.stop()
	_recorder.connect_session(_controller.get_session())
	_set_status('Started "%s".' % _controller.get_case_id())


func _on_reset_pressed() -> void:
	if _controller.get_session() == null:
		_set_status("No case selected yet.")
		return
	if not _controller.has_progress():
		_do_reset()
		return
	_confirm('Reset "%s"? All progress will be lost.' % _controller.get_case_id(), _do_reset)


func _do_reset() -> void:
	_controller.reset_session()
	if _recorder.is_recording():
		_recorder.set_current_source(_source_for_mode(_controller.get_mode()))
		_recorder.record_session_reset()
	_set_status("Session reset.")
	refresh()


## Launches Prototype A (Milestone 1.11) using the Lab's currently active
## case as a convenience default — the facilitator can still change it before
## pressing Start there. Uses a FRESH PrototypeAController/DeductionSession,
## never this Lab's own _controller/session: Prototype A must never reuse an
## Author Inspector session that may already be auto-solved, and playing it
## must never mutate this Lab's own session. See scripts/debug/prototype_a.gd.
func _on_launch_prototype_a_pressed() -> void:
	prototype_b.close()  # avoid two prototype overlays visible at once; hiding never discards prototype_b's own progress
	prototype_c.close()  # ditto for prototype_c's own progress
	prototype_a.open(_controller.get_case_def() if _controller.get_session() != null else {})


## Milestone 1.12: launches Prototype B using the Lab's currently active case
## as a convenience default — the facilitator can still change it before
## pressing Start there. Uses a FRESH PrototypeBController/DeductionSession,
## never this Lab's own _controller/session and never a PrototypeAController's
## — see scripts/debug/prototype_b.gd.
func _on_launch_prototype_b_pressed() -> void:
	prototype_a.close()  # avoid two prototype overlays visible at once; hiding never discards prototype_a's own progress
	prototype_c.close()  # ditto for prototype_c's own progress
	prototype_b.open(_controller.get_case_def() if _controller.get_session() != null else {})


## Milestone 1.13: launches Prototype C using the Lab's currently active case
## as a convenience default — the facilitator can still change it before
## pressing Start there. Uses a FRESH PrototypeCController (no DeductionSession
## at all — see scripts/deduction/prototype_c_controller.gd's class doc),
## never this Lab's own _controller/session and never a PrototypeAController's
## or PrototypeBController's — see scripts/debug/prototype_c.gd.
func _on_launch_prototype_c_pressed() -> void:
	prototype_a.close()  # avoid two prototype overlays visible at once; hiding never discards prototype_a's own progress
	prototype_b.close()  # ditto for prototype_b's own progress
	prototype_c.open(_controller.get_case_def() if _controller.get_session() != null else {})


func _on_mode_pressed(mode: String) -> void:
	_controller.set_mode(mode)
	if _recorder.is_recording():
		_recorder.set_current_source(_source_for_mode(mode))
		_recorder.record_mode_switched(mode)
	refresh()


func _source_for_mode(mode: String) -> String:
	return DeductionLabRecorder.SOURCE_AUTHOR_DEBUG if mode == MODE_AUTHOR else DeductionLabRecorder.SOURCE_PLAYER_PREVIEW


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
# Rendering — every tab is rebuilt from DeductionLabPresenter's view models,
# never from the raw case_def.

func refresh() -> void:
	non_canon_badge.text = tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")
	launch_prototype_a_button.text = tr("UI_PROTOTYPE_A_LAUNCH_BUTTON")
	launch_prototype_b_button.text = tr("UI_PROTOTYPE_B_LAUNCH_BUTTON")
	launch_prototype_c_button.text = tr("UI_PROTOTYPE_C_LAUNCH_BUTTON")
	if _controller.get_session() != null:
		var case_def: Dictionary = _controller.get_case_def()
		var session: DeductionSession = _controller.get_session()
		_last_player_result = DeductionLabPresenter.build_player_view(case_def, session)
		_last_validation_errors = []
		_last_validation_warnings = []
		DeductionValidator.validate_case(case_def, _last_validation_errors, _last_validation_warnings)
		_last_author_view = DeductionLabPresenter.build_author_view(case_def, session, _last_validation_errors, _last_validation_warnings)
	else:
		_last_player_result = {}
		_last_author_view = {}

	_render_overview()
	_render_evidence()
	_render_claims()
	_render_timeline()
	_render_hints()
	_render_author_tab()
	_render_recorder_tab()
	_update_mode_buttons()


func _update_mode_buttons() -> void:
	var mode: String = _controller.get_mode() if _controller != null else MODE_PLAYER
	mode_player_button.text = "Player Preview%s" % (" [ACTIVE]" if mode == MODE_PLAYER else "")
	mode_author_button.text = "Author Inspector%s" % (" [ACTIVE]" if mode == MODE_AUTHOR else "")
	mode_player_button.disabled = mode == MODE_PLAYER
	mode_author_button.disabled = mode == MODE_AUTHOR
	var author_tab_index: int = tabs.get_tab_idx_from_control(author_tab)
	if author_tab_index >= 0:
		tabs.set_tab_hidden(author_tab_index, mode != MODE_AUTHOR)


func _render_overview() -> void:
	UiUtil.clear_children(overview_list)
	if _controller.get_session() == null:
		_add_line(overview_list, 'No case selected yet — pick one above and press "Start / Switch".')
		return
	if _controller.get_mode() == MODE_AUTHOR:
		_render_overview_author()
	else:
		_render_overview_player()


func _render_overview_player() -> void:
	var view: Dictionary = _last_player_result.get("view", {})
	var badge: String = ("  [%s]" % tr("UI_DEDUCTION_LAB_NON_CANON_BADGE")) if view.get("non_canon", false) else ""
	_add_header(overview_list, "%s%s" % [view.get("case_title", ""), badge])
	_add_line(overview_list, view.get("case_description", ""))
	_add_line(overview_list, "Status: %s   Questions resolved: %d/%d" % [
		"SOLVED" if view.get("solved", false) else "IN PROGRESS", view.get("questions_resolved", 0), view.get("questions_total", 0),
	])
	_add_header(overview_list, "SUSPECTS")
	for suspect in view.get("suspects", []):
		_add_line(overview_list, "  %s" % suspect.get("name", ""))
	_add_header(overview_list, "QUESTIONS")
	for question in view.get("questions", []):
		_add_line(overview_list, "  [%s] %s" % ["RESOLVED" if question.get("resolved", false) else "OPEN", question.get("text", "")])


func _render_overview_author() -> void:
	var case_id: String = _last_author_view.get("case_id", "")
	_add_header(overview_list, "Case id: %s" % case_id)
	_add_line(overview_list, "Session solved: %s" % _controller.get_session().is_solved())
	_add_header(overview_list, "SUSPECTS (id — structural_role — name)")
	for suspect in _last_author_view.get("suspects", []):
		_add_line(overview_list, "  %s — %s — %s" % [suspect.get("id", ""), suspect.get("structural_role", ""), suspect.get("name", "")])
	_add_header(overview_list, "QUESTIONS")
	for question in _last_author_view.get("questions", []):
		_add_line(overview_list, "  %s (required=%s): %s" % [question.get("id", ""), question.get("required", false), question.get("text", "")])


func _matches_evidence_filter(name: String, opened: bool, search: String, filter_index: int) -> bool:
	if search != "" and not String(name).to_lower().contains(search):
		return false
	if filter_index == 1 and not opened:
		return false
	if filter_index == 2 and opened:
		return false
	return true


func _render_evidence() -> void:
	UiUtil.clear_children(evidence_list)
	if _controller == null or _controller.get_session() == null:
		_add_line(evidence_list, "No case selected yet.")
		return
	var search: String = evidence_search_edit.text.strip_edges().to_lower()
	var filter_index: int = evidence_filter_option.selected

	if _controller.get_mode() == MODE_AUTHOR:
		for item in _last_author_view.get("evidence", []):
			if not _matches_evidence_filter(item.get("name", ""), item.get("opened", false), search, filter_index):
				continue
			var extra: String = ""
			if item.get("time", "") != "":
				extra += ", time=%s" % item.get("time", "")
			if item.get("misleading", false):
				extra += ", MISLEADING"
			if not (item.get("unlock_requires", []) as Array).is_empty():
				extra += ", unlock_requires=%s" % [item.get("unlock_requires", [])]
			_add_line(evidence_list, "[%s] %s (%s) — %s — source=%s, certainty=%s%s" % [
				"OPENED" if item.get("opened", false) else "unopened", item.get("id", ""), item.get("structural_role", ""),
				item.get("name", ""), item.get("source", ""), item.get("certainty", ""), extra,
			])
			if item.get("opened", false):
				_add_line(evidence_list, "      %s" % item.get("text", ""))
	else:
		for item in _last_player_result.get("view", {}).get("evidence", []):
			if not _matches_evidence_filter(item.get("name", ""), item.get("opened", false), search, filter_index):
				continue
			_render_player_evidence_row(item)


func _render_player_evidence_row(item: Dictionary) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var opened: bool = item.get("opened", false)
	var body: String = "[%s] %s" % ["opened" if opened else "unopened", item.get("name", "")]
	if opened:
		body += "\n%s" % item.get("text", "")
	label.text = body
	row.add_child(label)
	if not opened:
		var open_button := Button.new()
		open_button.text = "Open"
		var handle: String = item.get("handle", "")
		open_button.pressed.connect(func(): _on_open_evidence_pressed(handle))
		row.add_child(open_button)
	evidence_list.add_child(row)


## `handle` is an OPAQUE token from the Player Preview contract — the real
## evidence id is resolved ONLY through the presenter's private handle_map,
## never carried by the view widgets themselves. See
## scripts/deduction/deduction_lab_presenter.gd's class doc.
func _on_open_evidence_pressed(handle: String) -> void:
	var real_id: String = String((_last_player_result.get("handle_map", {}) as Dictionary).get(handle, ""))
	if real_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	_controller.get_session().mark_evidence_opened(real_id)
	refresh()


func _render_claims() -> void:
	UiUtil.clear_children(claims_list)
	if _controller == null or _controller.get_session() == null:
		_add_line(claims_list, "No case selected yet.")
		return
	if _controller.get_mode() == MODE_AUTHOR:
		for claim in _last_author_view.get("claims", []):
			var status: String = claim.get("status", "")
			_add_line(claims_list, "[%s] %s (%s, veracity=%s, depth=%d%s) — %s" % [
				status if status != "" else "unresolved", claim.get("id", ""), claim.get("kind", ""),
				claim.get("veracity", ""), claim.get("depth", 0), ", required" if claim.get("required", false) else "",
				claim.get("text", ""),
			])
			for proof_set in claim.get("proof_sets", []):
				_add_line(claims_list, "      proof_set %s: %s %s" % [proof_set.get("id", ""), proof_set.get("relation", ""), proof_set.get("requires", [])])
			if not (claim.get("compatible", []) as Array).is_empty():
				_add_line(claims_list, "      compatible (not proof): %s" % [claim.get("compatible", [])])
	else:
		for claim in _last_player_result.get("view", {}).get("claims", []):
			var speaker: String = (" (%s)" % claim.get("speaker", "")) if claim.has("speaker") else ""
			_add_line(claims_list, "[%s] %s%s — %s" % [String(claim.get("status", "unresolved")).to_upper(), String(claim.get("kind", "")).capitalize(), speaker, claim.get("text", "")])


func _render_timeline() -> void:
	UiUtil.clear_children(timeline_list)
	if _controller == null or _controller.get_session() == null:
		_add_line(timeline_list, "No case selected yet.")
		return
	if _controller.get_mode() == MODE_AUTHOR:
		var timeline: Dictionary = _last_author_view.get("timeline", {})
		for event in timeline.get("events", []):
			_add_line(timeline_list, "%s (%s) actor=%s certainty=%s" % [event.get("id", ""), event.get("label", ""), event.get("actor", ""), event.get("certainty", "")])
		_add_header(timeline_list, "CONSTRAINTS")
		for constraint in timeline.get("constraints", []):
			_add_line(timeline_list, str(constraint))
		_add_header(timeline_list, "AUTHORED SOLUTION")
		_add_line(timeline_list, str(_last_author_view.get("ground_truth", {}).get("solution_timeline", {})))
	else:
		for event in _last_player_result.get("view", {}).get("timeline", []):
			var known_time: String = event.get("known_time", "")
			_add_line(timeline_list, "%s — %s" % [event.get("label", ""), known_time if known_time != "" else "time not yet known"])


func _render_hints() -> void:
	UiUtil.clear_children(hints_list)
	if _controller == null or _controller.get_session() == null:
		_add_line(hints_list, "No case selected yet.")
		return
	if _controller.get_mode() == MODE_AUTHOR:
		for ladder in _last_author_view.get("hints", []):
			_add_header(hints_list, "Target: %s" % ladder.get("target", ""))
			for level in ladder.get("levels", []):
				_add_line(hints_list, "  L%s [%s]: %s" % [level.get("level", ""), level.get("kind", ""), level.get("text", "")])
	else:
		for hint in _last_player_result.get("view", {}).get("hints", []):
			var revealed: Array = hint.get("levels_revealed", [])
			_add_header(hints_list, "Hint ladder (%d/%d revealed)" % [revealed.size(), hint.get("total_levels", 0)])
			for text in revealed:
				_add_line(hints_list, "  %s" % text)
			if hint.get("can_reveal_more", false):
				var reveal_button := Button.new()
				reveal_button.text = "Reveal next hint"
				var handle: String = hint.get("handle", "")
				reveal_button.pressed.connect(func(): _on_reveal_hint_pressed(handle))
				hints_list.add_child(reveal_button)


## Same opaque-handle rule as evidence — see _on_open_evidence_pressed().
func _on_reveal_hint_pressed(handle: String) -> void:
	var target_id: String = String((_last_player_result.get("handle_map", {}) as Dictionary).get(handle, ""))
	if target_id == "":
		return
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_PLAYER_PREVIEW)
	DeductionEvaluator.request_hint(_controller.get_case_def(), _controller.get_session(), target_id)
	refresh()


func _render_author_tab() -> void:
	UiUtil.clear_children(author_list)
	if _controller == null or _controller.get_session() == null:
		_add_line(author_list, "No case selected yet.")
		return
	_add_header(author_list, "VALIDATION STATUS")
	_add_line(author_list, "%d error(s), %d warning(s)" % [_last_validation_errors.size(), _last_validation_warnings.size()])
	for message in _last_validation_errors:
		_add_line(author_list, "ERROR: %s" % message)
	for message in _last_validation_warnings:
		_add_line(author_list, "WARNING: %s" % message)
	_add_header(author_list, "METADATA")
	_add_line(author_list, str(_last_author_view.get("metadata", {})))
	_add_header(author_list, "GROUND TRUTH")
	_add_line(author_list, str(_last_author_view.get("ground_truth", {})))
	_add_header(author_list, "SESSION STATE (raw, DeductionSession.to_dict())")
	_add_line(author_list, str(_last_author_view.get("session", {})))


# ---------------------------------------------------------------------------
# Author-only debug actions — every one calls the REAL production API
# (DeductionEvaluator/TimelineEvaluator), never a reimplementation.

## Generic across any case sharing the credential_misuse_v2 template (or any
## future template): repeatedly commits each still-unresolved
## deduction/conclusion's PRIMARY (first) or ALTERNATE (last, when one
## exists) authored proof set, in a bounded fixed-point pass, until nothing
## more becomes provable — never hand-picks a case-specific claim id, so this
## stays neutral between whatever content X/Y/Z (or a future case) define.
func _on_auto_solve_pressed(use_alternate: bool) -> void:
	if _controller.get_session() == null:
		return
	var case_def: Dictionary = _controller.get_case_def()
	var session: DeductionSession = _controller.get_session()
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_AUTHOR_DEBUG)

	var attempts_log: Array[String] = []
	var progressed := true
	while progressed:
		progressed = false
		for claim in case_def.get("claims", []):
			var claim_id: String = str(claim.get("id", ""))
			var kind: String = str(claim.get("kind", ""))
			if (kind != "deduction" and kind != "conclusion") or session.get_claim_status(claim_id) != "":
				continue
			var proof_sets: Array = claim.get("proof_sets", [])
			if proof_sets.is_empty():
				continue
			var chosen_index: int = (proof_sets.size() - 1) if (use_alternate and proof_sets.size() > 1) else 0
			var proof_set: Dictionary = proof_sets[chosen_index]
			var result: Dictionary = DeductionEvaluator.commit_attempt(case_def, session, claim_id, str(proof_set.get("relation", "")), proof_set.get("requires", []))
			attempts_log.append("%s -> %s" % [claim_id, result.get("category", "")])
			if DeductionEvaluator.is_valid_category(result.get("category", "")):
				progressed = true

	author_action_status_label.text = "Auto-solve (%s): %s" % ["alternate" if use_alternate else "primary", ", ".join(attempts_log)]
	refresh()


func _on_author_reveal_hint_pressed() -> void:
	if _controller.get_session() == null:
		return
	var case_def: Dictionary = _controller.get_case_def()
	var session: DeductionSession = _controller.get_session()
	_recorder.set_current_source(DeductionLabRecorder.SOURCE_AUTHOR_DEBUG)
	for ladder in case_def.get("hints", []):
		var target: String = str(ladder.get("target", ""))
		var levels: Array = ladder.get("levels", [])
		if session.get_hint_level(target) < levels.size():
			var hint: Dictionary = DeductionEvaluator.request_hint(case_def, session, target)
			author_action_status_label.text = 'Revealed hint level %s for "%s": %s' % [hint.get("level", ""), target, hint.get("text", "")]
			refresh()
			return
	author_action_status_label.text = "Every hint ladder is already exhausted."


func _on_validate_timeline_pressed() -> void:
	if _controller.get_session() == null:
		return
	var case_def: Dictionary = _controller.get_case_def()
	var solution: Variant = case_def.get("ground_truth", {}).get("solution_timeline", {})
	var result: Dictionary = TimelineEvaluator.evaluate(case_def, solution)
	author_action_status_label.text = "Authored timeline validation: %s (violated_required=%s, violated_optional=%s)" % [
		result.get("category", ""), result.get("violated_required", []), result.get("violated_optional", []),
	]
	if _recorder.is_recording():
		_recorder.set_current_source(DeductionLabRecorder.SOURCE_AUTHOR_DEBUG)
		_recorder.record("timeline_validated", DeductionLabRecorder.SOURCE_AUTHOR_DEBUG, {
			"category": result.get("category", ""), "violated_required": result.get("violated_required", []), "violated_optional": result.get("violated_optional", []),
		})


# ---------------------------------------------------------------------------
# Recorder tab

func _render_recorder_tab() -> void:
	UiUtil.clear_children(recorder_list)
	recorder_status_label.text = "Recording: %s — %d event(s) captured (session id: %s)." % [
		"ON" if _recorder.is_recording() else "OFF", _recorder.get_events().size(), _recorder.get_session_id(),
	]
	for event in _recorder.get_events():
		_add_line(recorder_list, "#%d [%dms] %s (%s) %s" % [
			event.get("sequence", 0), event.get("elapsed_ms", 0), event.get("type", ""), event.get("source", ""), JSON.stringify(event.get("payload", {})),
		])


func _on_recorder_start_pressed() -> void:
	if _controller.get_session() == null:
		_set_status("Select a case before recording.")
		return
	_recorder.connect_session(_controller.get_session())
	_recorder.start(_controller.get_case_id(), "deduction_lab", LocaleManager.get_locale())
	_render_recorder_tab()


func _on_recorder_stop_pressed() -> void:
	_recorder.stop()
	_render_recorder_tab()


func _on_recorder_clear_pressed() -> void:
	_recorder.clear()
	_render_recorder_tab()


func _on_recorder_export_pressed() -> void:
	var result: Dictionary = _recorder.export_to_file()
	if result.get("success", false):
		_set_status("Exported recording to %s" % result.get("path", ""))
	else:
		_set_status("Export failed: %s" % result.get("error", ""))
	_render_recorder_tab()


# ---------------------------------------------------------------------------
# Small list-building helpers (mirrors debug_panel.gd's own — no shared
# helper exists beyond UiUtil.clear_children; see that script's own copy).

func _add_line(parent: VBoxContainer, text: String, is_header: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_header:
		label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)


func _add_header(parent: VBoxContainer, text: String) -> void:
	_add_line(parent, text, true)
