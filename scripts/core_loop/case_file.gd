extends Control
## The production Case File (Milestone 1.16 — see docs/core-loop-sandbox.md,
## "UI"): the evidence the player has ACQUIRED (never anything still hidden),
## each item's detail once read, a persistent pin, what has been established
## so far (only consequences already applied, never future deductions), the
## current objective, and the entry to the mechanic the chapter currently
## offers. Rendered entirely from CoreLoopPresenter.build_case_file(); reading
## and pinning go through ChapterRuntime, so both persist.
##
## Opening it never changes the chapter phase — Case File is navigation, not
## progression (1.15B §5.1).

signal unit_requested(unit_id: String)
signal closed()

var _runtime: ChapterRuntime
var _handles: Dictionary = {}
var _view: Dictionary = {}
var _selected_handle: String = ""

@onready var title_label: Label = %TitleLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var unit_row: HBoxContainer = %UnitRow
@onready var unit_hint_label: Label = %UnitHintLabel
@onready var open_unit_button: Button = %OpenUnitButton
@onready var evidence_header: Label = %EvidenceHeader
@onready var evidence_list: VBoxContainer = %EvidenceList
@onready var detail_title: Label = %DetailTitle
@onready var detail_text: Label = %DetailText
@onready var pin_button: Button = %PinButton
@onready var findings_header: Label = %FindingsHeader
@onready var findings_list: VBoxContainer = %FindingsList
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	open_unit_button.pressed.connect(func() -> void: unit_requested.emit(_runtime.get_current_unit_id()))
	pin_button.pressed.connect(_on_pin_pressed)
	LocaleManager.locale_changed.connect(func(_locale: String) -> void: _refresh_if_visible())


func setup(runtime: ChapterRuntime) -> void:
	_runtime = runtime
	_runtime.state_changed.connect(_refresh_if_visible)


func open() -> void:
	visible = true
	_selected_handle = ""
	refresh()
	var first: Button = evidence_list.get_child(0) as Button if evidence_list.get_child_count() > 0 else null
	if first != null:
		first.grab_focus()
	else:
		close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _refresh_if_visible() -> void:
	if visible:
		refresh()


func refresh() -> void:
	var built: Dictionary = CoreLoopPresenter.build_case_file(_runtime)
	_view = built.get("view", {})
	_handles = built.get("handle_map", {})
	title_label.text = tr("UI_CORE_LOOP_CASE_FILE_TITLE")
	objective_label.text = tr("UI_CORE_LOOP_OBJECTIVE") % _view.get("objective", "")
	evidence_header.text = tr("UI_CORE_LOOP_EVIDENCE_HEADER")
	findings_header.text = tr("UI_CORE_LOOP_FINDINGS_HEADER")
	close_button.text = tr("UI_CORE_LOOP_CLOSE")
	var unit_title: String = _view.get("unit_title", "")
	unit_row.visible = unit_title != ""
	open_unit_button.visible = _view.get("unit_available", false)
	open_unit_button.text = tr("UI_CORE_LOOP_OPEN_UNIT") % unit_title
	unit_hint_label.text = _view.get("unit_hint", "") if not _view.get("unit_available", false) else ""

	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var focus_name: String = focus_owner.name if focus_owner != null and evidence_list.is_ancestor_of(focus_owner) else ""
	UiUtil.clear_children(evidence_list)
	for item in _view.get("evidence", []):
		var handle: String = item.get("handle", "")
		var button := Button.new()
		button.name = "Evidence_%s" % handle
		var tags: Array[String] = []
		if item.get("pinned", false):
			tags.append(tr("UI_CORE_LOOP_PINNED_TAG"))
		if not item.get("opened", false):
			tags.append(tr("UI_CORE_LOOP_UNREAD_TAG"))
		button.text = "%s%s\n%s" % [item.get("name", ""), ("  " + " ".join(tags)) if not tags.is_empty() else "", item.get("short", "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(func() -> void: _select(handle))
		evidence_list.add_child(button)
	if _view.get("empty", true):
		var empty := Label.new()
		empty.text = tr("UI_CORE_LOOP_EVIDENCE_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		evidence_list.add_child(empty)
	if focus_name != "":
		var target: Node = evidence_list.find_child(focus_name, false, false)
		if target is Button:
			(target as Button).grab_focus()
	_render_detail()

	UiUtil.clear_children(findings_list)
	var lines: Array[String] = []
	for text in _view.get("findings", []):
		lines.append("✔ %s" % text)
	if lines.is_empty():
		lines.append(tr("UI_CORE_LOOP_FINDINGS_EMPTY"))
	for line in lines:
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		findings_list.add_child(label)


func _render_detail() -> void:
	var item: Dictionary = {}
	for candidate in _view.get("evidence", []):
		if candidate.get("handle", "") == _selected_handle:
			item = candidate
	pin_button.visible = not item.is_empty()
	if item.is_empty():
		detail_title.text = tr("UI_CORE_LOOP_SELECT_EVIDENCE_PROMPT") if not _view.get("empty", true) else ""
		detail_text.text = ""
		return
	detail_title.text = item.get("name", "")
	detail_text.text = item.get("detail", "")
	pin_button.text = tr("UI_CORE_LOOP_UNPIN" if item.get("pinned", false) else "UI_CORE_LOOP_PIN")


func _select(handle: String) -> void:
	_selected_handle = handle
	var evidence_id: String = str(_handles.get(handle, ""))
	if evidence_id != "":
		_runtime.open_case_file_evidence(evidence_id)  # emits state_changed -> refresh
	refresh()


func _on_pin_pressed() -> void:
	var evidence_id: String = str(_handles.get(_selected_handle, ""))
	if evidence_id == "":
		return
	_runtime.set_case_file_evidence_pinned(evidence_id, not _runtime.is_case_file_evidence_pinned(evidence_id))
	# Pinning reorders the list — keep the same item selected by its new handle.
	refresh()
	for handle in _handles:
		if _handles[handle] == evidence_id:
			_selected_handle = handle
	_render_detail()
	pin_button.grab_focus()
