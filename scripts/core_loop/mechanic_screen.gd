extends Control
## The production screen for every core-loop resolution unit (Milestone 1.16
## — see docs/core-loop-sandbox.md, "UI"): one shared shell — fixed header,
## scrolling body, fixed footer holding the formal commit — that renders
## whichever mechanic the unit runs (clue connection, statement
## contradiction, timeline reconstruction + final claim) from
## CoreLoopPresenter's allow-listed view.
##
## Holds NO gameplay truth: every click resolves an opaque handle back to an
## id and calls ChapterRuntime.perform(); the screen then re-renders from the
## runtime. Closing it (Back / Esc) never loses anything — the draft is
## already in the chapter-run snapshot — so it needs no confirmation.
## Pending feedback is part of the unit's durable state too: reopening the
## screen (or loading a save) shows it again until Continue.
##
## Keyboard: every control is a focusable Button; after each re-render focus
## returns to the button with the same role (same node name) or, failing
## that, to the primary action — so a keyboard player never loses their place
## when a list rebuilds.

signal closed()

var _runtime: ChapterRuntime
var _unit_id: String = ""
var _view: Dictionary = {}
var _handles: Dictionary = {}

@onready var title_label: Label = %TitleLabel
@onready var non_canon_badge: Label = %NonCanonBadge
@onready var return_button: Button = %ReturnButton
@onready var prompt_label: Label = %PromptLabel
@onready var status_label: Label = %StatusLabel
@onready var body_scroll: ScrollContainer = %BodyScroll
@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var feedback_headline: Label = %FeedbackHeadline
@onready var feedback_text: Label = %FeedbackText
@onready var assistance_panel: PanelContainer = %AssistancePanel
@onready var assistance_text: Label = %AssistanceText
@onready var hint_panel: PanelContainer = %HintPanel
@onready var hint_list: VBoxContainer = %HintList
@onready var content: VBoxContainer = %Content
@onready var footer: VBoxContainer = %Footer
@onready var hint_button: Button = %HintButton
@onready var primary_button: Button = %PrimaryButton
@onready var assistance_button: Button = %AcceptAssistanceButton
@onready var partner_button: Button = %PartnerButton
@onready var continue_button: Button = %ContinueButton


func _ready() -> void:
	visible = false
	return_button.pressed.connect(close)
	hint_button.pressed.connect(_on_hint_pressed)
	primary_button.pressed.connect(_on_primary_pressed)
	assistance_button.pressed.connect(func() -> void: _command("accept_assistance"))
	partner_button.pressed.connect(func() -> void: _command("resolve_with_partner"))
	continue_button.pressed.connect(_on_continue_pressed)
	LocaleManager.locale_changed.connect(func(_locale: String) -> void: _refresh_if_visible())


func setup(runtime: ChapterRuntime) -> void:
	_runtime = runtime


func get_unit_id() -> String:
	return _unit_id if visible else ""


func open(unit_id: String) -> void:
	_unit_id = unit_id
	visible = true
	body_scroll.scroll_vertical = 0
	refresh()
	_focus_default()


## Leaves the mechanic; the runtime checkpoints the draft on close.
func close() -> void:
	if not visible:
		return
	visible = false
	if _runtime != null:
		_runtime.close_unit()
	_unit_id = ""
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _refresh_if_visible() -> void:
	if visible:
		refresh()


# ---------------------------------------------------------------------------
# Rendering

func refresh() -> void:
	if _runtime == null or _unit_id == "":
		return
	var built: Dictionary = CoreLoopPresenter.build_mechanic(_runtime, _unit_id)
	_view = built.get("view", {})
	_handles = built.get("handle_map", {})
	if _view.is_empty():
		close()
		return
	title_label.text = _view.get("title", "")
	non_canon_badge.text = tr("UI_CORE_LOOP_SANDBOX_BADGE")
	return_button.text = tr("UI_CORE_LOOP_RETURN")
	hint_button.text = tr("UI_CORE_LOOP_HINT_BUTTON")
	assistance_button.text = tr("UI_RESOLUTION_ACCEPT_ASSISTANCE")
	partner_button.text = tr("UI_RESOLUTION_RESOLVE_WITH_PARTNER")
	continue_button.text = tr("UI_CORE_LOOP_CONTINUE")
	var status: Dictionary = _view.get("status", {})
	status_label.text = status.get("current_status_text", "") if not _view.get("resolved", false) else ""

	_render_feedback()
	_render_assistance()
	_render_hints()
	UiUtil.clear_children(content)
	match str(_view.get("mechanic", "")):
		CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
			_render_clue_connection()
		CoreLoopUnit.MECHANIC_STATEMENT_CONTRADICTION:
			_render_confrontation()
		CoreLoopUnit.MECHANIC_TIMELINE_RECONSTRUCTION:
			_render_timeline()
	_render_footer()


func _render_feedback() -> void:
	var feedback: Dictionary = _view.get("feedback", {})
	feedback_panel.visible = not feedback.is_empty()
	feedback_headline.text = feedback.get("headline", "")
	feedback_headline.visible = feedback_headline.text != ""
	feedback_text.text = "\n\n".join(PackedStringArray(feedback.get("lines", [])))


func _render_assistance() -> void:
	var assistance: Dictionary = _view.get("assistance", {})
	assistance_panel.visible = not assistance.is_empty()
	var parts: Array[String] = []
	for key in ["headline", "focus", "category_hint", "text", "relationship"]:
		if str(assistance.get(key, "")) != "":
			parts.append(str(assistance.get(key, "")))
	assistance_text.text = "\n".join(PackedStringArray(parts))


func _render_hints() -> void:
	UiUtil.clear_children(hint_list)
	var hint: Dictionary = _view.get("hint", {})
	var revealed: Array = hint.get("levels_revealed", [])
	hint_panel.visible = not revealed.is_empty()
	if revealed.is_empty():
		return
	_add_label(hint_list, tr("UI_CORE_LOOP_HINTS_HEADER"), 15)
	for text in revealed:
		_add_label(hint_list, "• %s" % text)


func _render_footer() -> void:
	var feedback_open: bool = not (_view.get("feedback", {}) as Dictionary).is_empty()
	var status: Dictionary = _view.get("status", {})
	var resolved: bool = _view.get("resolved", false)
	var hint: Dictionary = _view.get("hint", {})
	continue_button.visible = feedback_open
	var acting: bool = not feedback_open and not resolved
	hint_button.visible = acting and not hint.is_empty()
	hint_button.disabled = not hint.get("can_reveal_more", false)
	assistance_button.visible = acting and status.get("assistance_required", false) == true
	partner_button.visible = acting and status.get("partner_available", false) == true
	primary_button.visible = acting
	var primary: Array = _primary_action()
	primary_button.text = tr(primary[0])
	primary_button.disabled = not primary[1]


## [label key, enabled, command] for the mechanic's current formal commit.
func _primary_action() -> Array:
	var status: Dictionary = _view.get("status", {})
	match str(_view.get("mechanic", "")):
		CoreLoopUnit.MECHANIC_CLUE_CONNECTION:
			return ["UI_CORE_LOOP_B_COMMIT", _view.get("can_commit", false) == true, "commit_theory"]
		CoreLoopUnit.MECHANIC_STATEMENT_CONTRADICTION:
			var ready: bool = str(_view.get("selected_evidence_handle", "")) != "" and str(_view.get("current_statement_handle", "")) != "" \
				and status.get("can_submit", false) == true and not _current_statement_resolved()
			return ["UI_CORE_LOOP_A_PRESENT", ready, "present_evidence"]
	if _view.get("accepted", false):
		return ["UI_CORE_LOOP_C_SUBMIT", (_view.get("claim", {}) as Dictionary).get("can_submit", false) == true, "submit_claim"]
	return ["UI_CORE_LOOP_C_CHECK", _view.get("can_check", false) == true, "submit_timeline"]


# --- Clue connection (B) ----------------------------------------------------

func _render_clue_connection() -> void:
	prompt_label.text = _view.get("question", "")
	var columns := _add_columns()
	var left: VBoxContainer = columns[0]
	var right: VBoxContainer = columns[1]
	var slots: Array = _view.get("slots", [])
	var filled: int = slots.filter(func(slot: Dictionary) -> bool: return slot.get("filled", false)).size()
	_add_label(left, tr("UI_CORE_LOOP_B_SLOTS") % [filled, slots.size()], 16)
	var names: Dictionary = {}
	for item in _view.get("evidence", []):
		names[item.get("handle", "")] = item.get("name", "")
	var editable: bool = not _view.get("theory_accepted", false) and (_view.get("feedback", {}) as Dictionary).is_empty()
	for slot in slots:
		var row := _add_row(left)
		var slot_label: String = tr("UI_CORE_LOOP_B_SLOT") % (int(slot.get("index", 0)) + 1)
		if slot.get("filled", false):
			var handle: String = slot.get("evidence_handle", "")
			_add_label(row, "%s %s" % [slot_label, names.get(handle, "")], 0, true)
			if editable:
				_add_button(row, tr("UI_CORE_LOOP_REMOVE"), "SlotRemove_%s" % handle, func() -> void: _command("remove_evidence", [_resolve(handle)]))
		else:
			_add_label(row, "%s %s" % [slot_label, tr("UI_CORE_LOOP_B_SLOT_EMPTY")], 0, true)
	_add_label(left, tr("UI_CORE_LOOP_B_DRAFT_NOTE"))
	for claim in _view.get("resolved_claims", []):
		_add_label(left, "✔ %s" % claim.get("text", ""))

	_add_label(right, tr("UI_CORE_LOOP_B_POOL"), 16)
	var room: bool = filled < slots.size()
	for item in _view.get("evidence", []):
		var handle: String = item.get("handle", "")
		var row := _add_row(right)
		var text: String = item.get("name", "")
		if item.get("selected", false):
			text = "[%s] %s" % [tr("UI_CORE_LOOP_PLACED_TAG"), text]
		if item.get("opened", false):
			text += "\n" + str(item.get("text", ""))
		_add_label(row, text, 0, true)
		if not item.get("opened", false):
			_add_button(row, tr("UI_CORE_LOOP_READ"), "Read_%s" % handle, func() -> void: _command("open_evidence", [_resolve(handle)]))
		if editable:
			if item.get("selected", false):
				_add_button(row, tr("UI_CORE_LOOP_REMOVE"), "Remove_%s" % handle, func() -> void: _command("remove_evidence", [_resolve(handle)]))
			else:
				var place := _add_button(row, tr("UI_CORE_LOOP_PLACE"), "Place_%s" % handle, func() -> void: _command("select_evidence", [_resolve(handle)]))
				place.disabled = not room
	if (_view.get("evidence", []) as Array).is_empty():
		_add_label(right, tr("UI_CORE_LOOP_EVIDENCE_EMPTY"))


# --- Statement contradiction (A) ------------------------------------------

func _render_confrontation() -> void:
	prompt_label.text = tr("UI_CORE_LOOP_A_PROMPT")
	var columns := _add_columns()
	var left: VBoxContainer = columns[0]
	var right: VBoxContainer = columns[1]
	var editable: bool = not _view.get("resolved", false) and (_view.get("feedback", {}) as Dictionary).is_empty()
	_add_label(left, tr("UI_CORE_LOOP_A_TESTIMONY"), 16)
	var statements: Array = _view.get("statements", [])
	for i in statements.size():
		var statement: Dictionary = statements[i]
		var current: bool = statement.get("handle", "") == _view.get("current_statement_handle", "")
		# The authored statement already opens with its speaker's name.
		var text: String = str(statement.get("text", ""))
		if statement.get("resolved", false):
			text += "  " + tr("UI_CORE_LOOP_A_REFUTED")
		var button := _add_button(left, ("▶ " if current else "") + text, "Statement_%d" % i, func() -> void: _command("select_statement", [i]))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not editable
		if current:
			button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))

	_add_label(right, tr("UI_CORE_LOOP_A_EVIDENCE"), 16)
	var selected_name: String = ""
	for item in _view.get("evidence", []):
		var handle: String = item.get("handle", "")
		if item.get("selected", false):
			selected_name = item.get("name", "")
		var row := _add_row(right)
		var text: String = ("[%s] " % tr("UI_CORE_LOOP_CHOSEN_TAG") if item.get("selected", false) else "") + str(item.get("name", ""))
		if item.get("opened", false):
			text += "\n" + str(item.get("text", ""))
		_add_label(row, text, 0, true)
		if not item.get("opened", false):
			_add_button(row, tr("UI_CORE_LOOP_READ"), "Read_%s" % handle, func() -> void: _command("open_evidence", [_resolve(handle)]))
		if editable and not item.get("selected", false):
			_add_button(row, tr("UI_CORE_LOOP_A_SELECT"), "Choose_%s" % handle, func() -> void: _command("select_evidence", [_resolve(handle)]))
	if (_view.get("evidence", []) as Array).is_empty():
		_add_label(right, tr("UI_CORE_LOOP_EVIDENCE_EMPTY"))
	_add_label(right, tr("UI_CORE_LOOP_A_SELECTED") % selected_name if selected_name != "" else tr("UI_CORE_LOOP_A_NONE_SELECTED"))


func _current_statement_resolved() -> bool:
	for statement in _view.get("statements", []):
		if statement.get("handle", "") == _view.get("current_statement_handle", ""):
			return statement.get("resolved", false) == true
	return false


# --- Timeline reconstruction and final claim (C) -------------------------

func _render_timeline() -> void:
	prompt_label.text = _view.get("objective", "")
	var columns := _add_columns()
	var left: VBoxContainer = columns[0]
	var right: VBoxContainer = columns[1]
	var accepted: bool = _view.get("accepted", false)
	var editable: bool = not accepted and (_view.get("feedback", {}) as Dictionary).is_empty()
	var highlighted: Array = (_view.get("assistance", {}) as Dictionary).get("event_handles", [])

	_add_label(left, tr("UI_CORE_LOOP_C_EVENTS"), 16)
	if not accepted and int(_view.get("unplaced_count", 0)) > 0:
		_add_label(left, tr("UI_CORE_LOOP_C_UNPLACED_COUNT") % int(_view.get("unplaced_count", 0)))
	for event in _view.get("events", []):
		var handle: String = event.get("handle", "")
		var placement: String = event.get("placement", "")
		var header: String = str(event.get("label", ""))
		if int(event.get("duration_minutes", 0)) > 0:
			header += " " + tr("UI_CORE_LOOP_C_DURATION") % int(event.get("duration_minutes", 0))
		if highlighted.has(handle):
			header = "★ " + header
		if event.get("fixed", false):
			header += "  " + tr("UI_CORE_LOOP_C_FIXED") % placement
		else:
			header += "  " + (tr("UI_CORE_LOOP_C_PLACED") % placement if placement != "" else tr("UI_CORE_LOOP_C_UNPLACED"))
		_add_label(left, header, 0, true)
		if event.get("fixed", false) or not editable:
			continue
		var row := _add_row(left)
		for slot in _view.get("time_slots", []):
			var slot_time: String = str(slot)
			var slot_button := _add_button(row, slot_time, "Slot_%s_%s" % [handle, slot_time.replace(":", "")], func() -> void: _command("place_event", [_resolve(handle), slot_time]))
			slot_button.disabled = placement == slot_time
		if placement != "":
			_add_button(row, tr("UI_CORE_LOOP_REMOVE"), "Unplace_%s" % handle, func() -> void: _command("remove_event", [_resolve(handle)]))

	_add_label(right, tr("UI_CORE_LOOP_C_FACTS"), 16)
	for fact in _view.get("facts", []):
		var handle: String = fact.get("handle", "")
		if fact.get("opened", false):
			_add_label(right, "• %s" % fact.get("text", ""), 0, true)
		else:
			var row := _add_row(right)
			_add_label(row, tr("UI_CORE_LOOP_C_FACT_CLOSED"), 0, true)
			_add_button(row, tr("UI_CORE_LOOP_READ"), "Fact_%s" % handle, func() -> void: _command("open_fact", [_resolve(handle)]))
	if accepted:
		_render_claim(right)


func _render_claim(parent: VBoxContainer) -> void:
	var claim: Dictionary = _view.get("claim", {})
	if claim.is_empty():
		return
	parent.add_child(HSeparator.new())
	_add_label(parent, tr("UI_CORE_LOOP_C_CLAIM_HEADER"), 16)
	_add_label(parent, str(claim.get("statement_text", "")), 0, true)
	var resolution: Dictionary = _view.get("resolution", {})
	if not resolution.is_empty():
		for key in ["explanation", "justification", "partner_note"]:
			if str(resolution.get(key, "")) != "":
				_add_label(parent, str(resolution.get(key, "")), 0, true)
		return
	var editable: bool = (_view.get("feedback", {}) as Dictionary).is_empty()
	var verdicts := _add_row(parent)
	var fits := _add_button(verdicts, ("● " if claim.get("fits_selected", false) else "") + tr("UI_CORE_LOOP_C_FITS"), "VerdictFits", func() -> void: _command("select_claim_answer", [false]))
	var impossible := _add_button(verdicts, ("● " if claim.get("impossible_selected", false) else "") + tr("UI_CORE_LOOP_C_IMPOSSIBLE"), "VerdictImpossible", func() -> void: _command("select_claim_answer", [true]))
	fits.disabled = not editable
	impossible.disabled = not editable
	_add_label(parent, tr("UI_CORE_LOOP_C_SUPPORT"))
	for option in claim.get("justification_options", []):
		var handle: String = option.get("handle", "")
		var button := _add_button(parent, ("● " if option.get("selected", false) else "○ ") + str(option.get("text", "")), "Support_%s" % handle, func() -> void: _command("select_claim_justification", [_resolve(handle)]))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not editable


# ---------------------------------------------------------------------------
# Commands

func _resolve(handle: String) -> String:
	return str(_handles.get(handle, ""))


func _command(command: String, args: Array = []) -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var focus_name: String = focus_owner.name if focus_owner != null and is_ancestor_of(focus_owner) else ""
	for arg in args:
		if typeof(arg) == TYPE_STRING and arg == "":
			return  # A stale handle — never send a guessed id.
	_runtime.perform(_unit_id, command, args)
	refresh()
	_restore_focus(focus_name)


func _on_primary_pressed() -> void:
	var primary: Array = _primary_action()
	if primary[1]:
		_command(str(primary[2]))
		body_scroll.scroll_vertical = 0
		if continue_button.visible:
			continue_button.grab_focus()


func _on_hint_pressed() -> void:
	var hint: Dictionary = _view.get("hint", {})
	if _view.get("mechanic", "") == CoreLoopUnit.MECHANIC_STATEMENT_CONTRADICTION:
		_command("reveal_next_hint", [_resolve(str(hint.get("handle", "")))])
	else:
		_command("reveal_next_hint")


func _on_continue_pressed() -> void:
	var was_resolved: bool = _view.get("resolved", false)
	_runtime.dismiss_feedback(_unit_id)
	if was_resolved or _runtime.is_completed() or _runtime.get_current_unit_id() != _unit_id:
		close()
		return
	refresh()
	_focus_default()


# ---------------------------------------------------------------------------
# Small builders

func _add_columns() -> Array[VBoxContainer]:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	content.add_child(columns)
	var out: Array[VBoxContainer] = []
	for i in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 6)
		columns.add_child(column)
		out.append(column)
	return out


func _add_row(parent: Container) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


func _add_label(parent: Container, text: String, font_size: int = 0, expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(120, 0)
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	if expand or parent is VBoxContainer:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _add_button(parent: Container, text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.name = node_name
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _restore_focus(focus_name: String) -> void:
	if not visible:
		return
	if continue_button.visible:
		continue_button.grab_focus()
		return
	if focus_name != "":
		var target: Node = find_child(focus_name, true, false)
		if target is Button and (target as Button).is_visible_in_tree() and not (target as Button).disabled:
			(target as Button).grab_focus()
			return
	_focus_default()


func _focus_default() -> void:
	for candidate in [continue_button, primary_button, assistance_button, partner_button]:
		if candidate.is_visible_in_tree() and not candidate.disabled:
			candidate.grab_focus()
			return
	for child in content.find_children("*", "Button", true, false):
		if (child as Button).is_visible_in_tree() and not (child as Button).disabled:
			(child as Button).grab_focus()
			return
	return_button.grab_focus()
