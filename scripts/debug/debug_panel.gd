extends Control
## Developer-only Case Debugger overlay (Milestone 1.8): F1 toggles it.
## Entirely self-contained — unlike GameMenu/EvidenceInventory it is never
## wired up by Main.gd, because nothing else needs to coordinate with it (see
## docs/architecture.md, "Developer tools", and docs/case-debugger.md).
##
## In a release export, OS.is_debug_build() is false and _ready() returns
## before connecting anything or reacting to input, so this scene is dead
## weight (present in the tree, but inert) rather than something that needs
## to be removed from Main.tscn by hand later.
##
## Reads state exclusively through the same public APIs normal gameplay UI
## uses (GameState / ContentDB / Investigation / EventManager / CaseManager /
## ConditionEvaluator / ContentValidator) — no back-door access, and no
## duplicate progression/evaluation logic of its own. Two categories of
## action exist, and every button below is documented as one or the other
## (see docs/case-debugger.md, "Inspection vs. normal-pipeline mutation vs.
## debug override" for the full explanation):
##   - NORMAL-PIPELINE mutation: set/unset flag, add/remove evidence, start
##     case — these call the exact same GameState/CaseManager APIs
##     content-driven gameplay uses, just without a condition check first, so
##     they trigger normal reevaluation (Events may fire, Chapters may
##     complete, UI updates) exactly like real play would.
##   - DEBUG OVERRIDE: location jump (bypasses the destination's condition),
##     manual event trigger (bypasses conditions AND trigger_policy), event
##     trigger-reset (clears the "triggered" marker WITHOUT undoing effects),
##     chapter jump (bypasses the previous chapter's completion), force-
##     complete chapter, and case reset — these intentionally skip a normal
##     prerequisite, and are labeled as such in their own button text/status
##     messages.

const LOG_LIMIT := 50

var _log_lines: Array[String] = []
var _pending_confirmed_action: Callable = Callable()
var _last_inspected_kind: int = -1
var _last_inspected_id: String = ""
var _last_inspected_second_id: String = ""
var _last_producer_kind: int = -1
var _last_producer_id: String = ""

@onready var close_button: Button = %CloseButton
@onready var summary_label: Label = %SummaryLabel
@onready var status_label: Label = %StatusLabel
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog

@onready var state_filter_edit: LineEdit = %StateFilterEdit
@onready var flag_name_edit: LineEdit = %FlagNameEdit
@onready var set_flag_true_button: Button = %SetFlagTrueButton
@onready var set_flag_false_button: Button = %SetFlagFalseButton
@onready var state_list: VBoxContainer = %StateList

@onready var evidence_filter_edit: LineEdit = %EvidenceFilterEdit
@onready var evidence_id_edit: LineEdit = %EvidenceIdEdit
@onready var add_evidence_button: Button = %AddEvidenceButton
@onready var remove_evidence_button: Button = %RemoveEvidenceButton
@onready var evidence_list: VBoxContainer = %EvidenceList

@onready var location_id_edit: LineEdit = %LocationIdEdit
@onready var jump_button: Button = %JumpButton
@onready var location_list: VBoxContainer = %LocationList

@onready var npc_filter_edit: LineEdit = %NpcFilterEdit
@onready var npc_list: VBoxContainer = %NpcList

@onready var event_filter_edit: LineEdit = %EventFilterEdit
@onready var event_id_edit: LineEdit = %EventIdEdit
@onready var trigger_event_button: Button = %TriggerEventButton
@onready var reset_event_button: Button = %ResetEventButton
@onready var event_list: VBoxContainer = %EventList

@onready var case_id_edit: LineEdit = %CaseIdEdit
@onready var start_case_button: Button = %StartCaseButton
@onready var chapter_id_edit: LineEdit = %ChapterIdEdit
@onready var jump_chapter_button: Button = %JumpChapterButton
@onready var complete_chapter_button: Button = %CompleteChapterButton
@onready var reset_button: Button = %ResetButton
@onready var case_chapter_list: VBoxContainer = %CaseChapterList

@onready var inspector_kind_option: OptionButton = %InspectorKindOption
@onready var inspector_id_edit: LineEdit = %InspectorIdEdit
@onready var inspector_second_id_edit: LineEdit = %InspectorSecondIdEdit
@onready var inspector_show_button: Button = %InspectorShowButton
@onready var inspector_condition_tree: VBoxContainer = %InspectorConditionTree
@onready var producer_kind_option: OptionButton = %ProducerKindOption
@onready var producer_id_edit: LineEdit = %ProducerIdEdit
@onready var producer_lookup_button: Button = %ProducerLookupButton
@onready var producer_results: VBoxContainer = %ProducerResults

@onready var log_list: VBoxContainer = %LogList


func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		set_process_input(false)
		return

	close_button.pressed.connect(close)
	confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)

	inspector_kind_option.add_item("Event conditions", 0)
	inspector_kind_option.add_item("Topic condition (npc id + topic id)", 1)
	inspector_kind_option.add_item("Destination condition (from here)", 2)
	inspector_kind_option.add_item("NPC presence condition (at here)", 3)
	inspector_kind_option.add_item("Chapter completion conditions", 4)
	inspector_kind_option.select(0)

	producer_kind_option.add_item("Flag", 0)
	producer_kind_option.add_item("Evidence", 1)
	producer_kind_option.add_item("Interaction complete", 2)
	producer_kind_option.select(0)

	set_flag_true_button.pressed.connect(func(): _set_flag_from_field(true))
	set_flag_false_button.pressed.connect(func(): _set_flag_from_field(false))
	add_evidence_button.pressed.connect(_on_add_evidence_pressed)
	remove_evidence_button.pressed.connect(_on_remove_evidence_pressed)
	jump_button.pressed.connect(_on_jump_pressed)
	trigger_event_button.pressed.connect(_on_trigger_event_pressed)
	reset_event_button.pressed.connect(_on_reset_event_pressed)
	start_case_button.pressed.connect(_on_start_case_pressed)
	jump_chapter_button.pressed.connect(_on_jump_chapter_pressed)
	complete_chapter_button.pressed.connect(_on_complete_chapter_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	inspector_show_button.pressed.connect(_on_inspector_show_pressed)
	producer_lookup_button.pressed.connect(_on_producer_lookup_pressed)

	state_filter_edit.text_changed.connect(func(_t): _refresh_if_visible())
	evidence_filter_edit.text_changed.connect(func(_t): _refresh_if_visible())
	npc_filter_edit.text_changed.connect(func(_t): _refresh_if_visible())
	event_filter_edit.text_changed.connect(func(_t): _refresh_if_visible())

	GameState.flag_changed.connect(func(_n, _v): _refresh_if_visible())
	GameState.evidence_added.connect(func(_id): _refresh_if_visible())
	GameState.evidence_removed.connect(func(_id): _refresh_if_visible())
	GameState.location_changed.connect(func(_id): _refresh_if_visible())
	GameState.interaction_seen.connect(func(_key): _refresh_if_visible())
	DialogueManager.dialogue_ended.connect(_refresh_if_visible)
	EventManager.event_triggered.connect(func(_id): _refresh_if_visible())
	CaseManager.chapter_activated.connect(func(_id): _refresh_if_visible())
	CaseManager.chapter_completed.connect(func(_id): _refresh_if_visible())
	CaseManager.case_completed.connect(func(_id): _refresh_if_visible())
	LocaleManager.locale_changed.connect(func(_locale): _refresh_if_visible())


## _input rather than _unhandled_input, to match GameMenu/EvidenceInventory.
## _input runs in reverse tree order and DebugPanel is the last child of
## Main, so as the topmost overlay it is also the first to get a chance at
## Esc — which is the behaviour you want from a stack of overlays.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	status_label.text = ""
	refresh()
	visible = true


func close() -> void:
	visible = false


func _refresh_if_visible() -> void:
	if visible:
		refresh()


# ---------------------------------------------------------------------------
# Report — one render function per tab, all reading through production APIs.
# refresh() re-renders every tab unconditionally rather than only the active
# one: this project's content is small enough that the cost is negligible,
# and it keeps every tab's state honest the instant it's switched to (see
# "Optimize only when something actually needs it," docs/architecture.md).

func refresh() -> void:
	_render_summary()
	_render_state_tab()
	_render_evidence_tab()
	_render_location_tab()
	_render_npc_tab()
	_render_event_tab()
	_render_case_chapter_tab()
	_render_log_tab()
	if _last_inspected_kind != -1:
		_perform_inspect(_last_inspected_kind, _last_inspected_id, _last_inspected_second_id)
	if _last_producer_kind != -1:
		_perform_producer_lookup(_last_producer_kind, _last_producer_id)


func _render_summary() -> void:
	var case_id: String = CaseManager.get_current_case_id()
	var case_text := "—"
	if case_id != "":
		var case_data: Dictionary = ContentDB.get_case(case_id)
		var case_name: String = tr(case_data.get("display_name", case_data.get("title", case_id)))
		var status: String = "COMPLETED" if CaseManager.is_case_complete(case_id) else "ACTIVE"
		case_text = "%s [%s]" % [case_name, status]

	var chapter_id: String = CaseManager.get_current_chapter_id()
	var chapter_text: String = "—" if chapter_id == "" else tr(ContentDB.get_chapter(chapter_id).get("display_name", chapter_id))

	var location_text: String = "—"
	if GameState.current_location != "":
		location_text = tr(Investigation.get_current_location().get("name", GameState.current_location))

	summary_label.text = "Case: %s   |   Chapter: %s   |   Location: %s" % [case_text, chapter_text, location_text]


func _render_state_tab() -> void:
	UiUtil.clear_children(state_list)
	var filter: String = state_filter_edit.text.strip_edges()

	_add_header(state_list, "FLAGS")
	var flag_names: Array = GameState.flags.keys()
	flag_names.sort()
	var shown_any_flag := false
	for flag_name in flag_names:
		if not _matches_filter(String(flag_name), filter):
			continue
		shown_any_flag = true
		_add_flag_checkbox(state_list, String(flag_name))
	if not shown_any_flag:
		_add_line(state_list, "(none match)" if not filter.is_empty() else "(none set yet)")

	_add_header(state_list, "VISITED LOCATIONS")
	_add_line(state_list, ", ".join(GameState.visited_locations) if not GameState.visited_locations.is_empty() else "(none)")

	_add_header(state_list, "SEEN / INTERACTION-COMPLETE MARKERS")
	var markers: Array = GameState.seen_interactions.duplicate()
	markers.sort()
	var shown_any_marker := false
	for marker in markers:
		if not _matches_filter(String(marker), filter):
			continue
		shown_any_marker = true
		_add_line(state_list, String(marker))
	if not shown_any_marker:
		_add_line(state_list, "(none match)" if not filter.is_empty() else "(none yet)")


func _add_flag_checkbox(parent: VBoxContainer, flag_name: String) -> void:
	var check := CheckBox.new()
	check.text = flag_name
	check.button_pressed = GameState.get_flag(flag_name)
	check.toggled.connect(func(pressed: bool): _set_flag(flag_name, pressed))
	parent.add_child(check)


func _render_evidence_tab() -> void:
	UiUtil.clear_children(evidence_list)
	var filter: String = evidence_filter_edit.text.strip_edges()
	var evidence_ids: Array = ContentDB.get_all_evidence().keys()
	evidence_ids.sort()
	var shown_any := false
	for raw_id in evidence_ids:
		var evidence_id: String = String(raw_id)
		var display_name: String = tr(ContentDB.get_evidence(evidence_id).get("name", evidence_id))
		if not (_matches_filter(evidence_id, filter) or _matches_filter(display_name, filter)):
			continue
		shown_any = true
		_add_evidence_checkbox(evidence_list, evidence_id, display_name)
	if not shown_any:
		_add_line(evidence_list, "(none match)")


func _add_evidence_checkbox(parent: VBoxContainer, evidence_id: String, display_name: String) -> void:
	var check := CheckBox.new()
	check.text = "%s — %s" % [evidence_id, display_name]
	check.button_pressed = GameState.has_evidence(evidence_id)
	check.toggled.connect(func(pressed: bool): _set_evidence(evidence_id, pressed))
	parent.add_child(check)


func _render_location_tab() -> void:
	UiUtil.clear_children(location_list)
	var location: Dictionary = Investigation.get_current_location()

	_add_header(location_list, "CURRENT LOCATION")
	_add_line(location_list, "%s (%s)" % [tr(location.get("name", GameState.current_location)), GameState.current_location])

	_add_header(location_list, "DESTINATIONS (from here)")
	var destinations: Array = Investigation.get_all_destinations()
	if destinations.is_empty():
		_add_line(location_list, "(none defined)")
	for destination in destinations:
		_add_destination_line(location_list, destination)

	_add_header(location_list, "VISITED LOCATIONS")
	_add_line(location_list, ", ".join(GameState.visited_locations) if not GameState.visited_locations.is_empty() else "(none)")


func _add_destination_line(parent: VBoxContainer, destination: Dictionary) -> void:
	var location_id: String = destination.get("location_id", "")
	var lock_info: Dictionary = Investigation.explain_destination_lock(location_id)
	var status: String = "LOCKED" if lock_info.get("locked", true) else "AVAILABLE"
	_add_line(parent, "  [%s] %s (%s)" % [status, tr(destination.get("label", location_id)), location_id])
	if lock_info.get("locked", true):
		for condition_line in lock_info.get("conditions", []):
			if not condition_line.get("passed", true):
				_add_line(parent, "      missing: %s" % condition_line.get("description", ""))


## Deliberately no "move NPC" action here (section 13's optional generic
## mover): this project has no generic "where is this NPC" mechanism to set —
## presence is 100% derived, fresh, from each npc entry's own `condition`
## (docs/event-system.md, "Character presence"). "Moving" a character is
## already just editing whatever flag that condition reads, which the State
## tab already covers; a dedicated "move" action would need either a new
## GameState field (a second source of truth the architecture deliberately
## rejected) or content-specific guessing, neither of which this milestone
## should add. See docs/case-debugger.md, "Known limitations."
func _render_npc_tab() -> void:
	UiUtil.clear_children(npc_list)
	var filter: String = npc_filter_edit.text.strip_edges()
	var all_npcs: Array = Investigation.get_all_npcs()
	if all_npcs.is_empty():
		_add_line(npc_list, "(no NPCs defined at this location)")
		return

	var shown_any := false
	for npc in all_npcs:
		var npc_id: String = npc.get("id", "")
		var npc_name: String = tr(ContentDB.get_character(npc_id).get("name", npc_id))
		var npc_matches: bool = _matches_filter(npc_id, filter) or _matches_filter(npc_name, filter)
		var topics_here: Array = Investigation.get_all_topics(npc_id)
		var matching_topics: Array = []
		for topic in topics_here:
			if _matches_filter(String(topic.get("id", "")), filter) or _matches_filter(tr(topic.get("label", "")), filter):
				matching_topics.append(topic)
		if not filter.is_empty() and not npc_matches and matching_topics.is_empty():
			continue

		shown_any = true
		_add_npc_line(npc_list, npc)
		var presence: Dictionary = Investigation.explain_npc_presence(npc)
		if presence.get("locked", true):
			continue
		var topics_to_show: Array = topics_here if (npc_matches or filter.is_empty()) else matching_topics
		for topic in topics_to_show:
			_add_topic_line(npc_list, npc_id, topic)

	if not shown_any:
		_add_line(npc_list, "(none match)")


func _add_npc_line(parent: VBoxContainer, npc: Dictionary) -> void:
	var npc_id: String = npc.get("id", "")
	var presence: Dictionary = Investigation.explain_npc_presence(npc)
	var is_present: bool = not presence.get("locked", true)
	var status: String = "PRESENT" if is_present else "ABSENT"
	_add_line(parent, "[%s] %s (%s)" % [status, tr(ContentDB.get_character(npc_id).get("name", npc_id)), npc_id])
	if not is_present:
		for condition_line in presence.get("conditions", []):
			if not condition_line.get("passed", true):
				_add_line(parent, "      missing: %s" % condition_line.get("description", ""))


func _add_topic_line(parent: VBoxContainer, npc_id: String, topic: Dictionary) -> void:
	var topic_id: String = topic.get("id", "")
	var lock_info: Dictionary = Investigation.explain_topic_lock(npc_id, topic_id)
	var status: String = "LOCKED" if lock_info.get("locked", true) else "AVAILABLE"
	var seen_tag: String = "  (read)" if Investigation.is_topic_seen(npc_id, topic_id) else ""
	_add_line(parent, "  [%s] %s (%s)%s" % [status, tr(topic.get("label", topic_id)), topic_id, seen_tag])
	if lock_info.get("locked", true):
		for condition_line in lock_info.get("conditions", []):
			if not condition_line.get("passed", true):
				_add_line(parent, "      missing: %s" % condition_line.get("description", ""))


func _render_event_tab() -> void:
	UiUtil.clear_children(event_list)
	var filter: String = event_filter_edit.text.strip_edges()
	var event_ids: Array = ContentDB.get_all_event_ids()
	event_ids.sort()
	var shown_any := false
	for raw_id in event_ids:
		var event_id: String = String(raw_id)
		if not _matches_filter(event_id, filter):
			continue
		shown_any = true
		_add_event_line(event_list, event_id)
	if not shown_any:
		_add_line(event_list, "(none match)" if not filter.is_empty() else "(no events defined)")


func _add_event_line(parent: VBoxContainer, event_id: String) -> void:
	var info: Dictionary = EventManager.explain_event(event_id)
	var triggered: bool = info.get("triggered", false)
	var satisfied: bool = info.get("conditions_satisfied", false)
	var status: String = "TRIGGERED" if triggered else ("CONDITIONS MET" if satisfied else "NOT TRIGGERED")
	_add_line(parent, "[%s] %s" % [status, event_id])
	for condition_line in info.get("conditions", []):
		var mark: String = "x" if condition_line.get("passed", false) else " "
		_add_line(parent, "      [%s] %s" % [mark, condition_line.get("description", "")])


## Case/Chapter status — reads only through CaseManager's own public API,
## same "no back-door access" rule every other section here follows. A flat
## case (case_00_sandbox) shows no chapter section at all.
func _render_case_chapter_tab() -> void:
	UiUtil.clear_children(case_chapter_list)
	var case_id: String = CaseManager.get_current_case_id()
	if case_id == "":
		_add_line(case_chapter_list, "(no case active)")
		return

	var case_data: Dictionary = ContentDB.get_case(case_id)
	var case_name: String = tr(case_data.get("display_name", case_data.get("title", case_id)))
	var case_status: String = "COMPLETED" if CaseManager.is_case_complete(case_id) else "ACTIVE"
	_add_line(case_chapter_list, "[%s] %s (%s)" % [case_status, case_name, case_id])

	var chapter_id: String = CaseManager.get_current_chapter_id()
	if chapter_id == "":
		_add_line(case_chapter_list, "  (flat case — no chapter tracking)")
		return

	var chapter_data: Dictionary = ContentDB.get_chapter(chapter_id)
	var chapter_name: String = tr(chapter_data.get("display_name", chapter_id))
	_add_line(case_chapter_list, "  CURRENT CHAPTER: %s (%s)" % [chapter_name, chapter_id])

	var completion: Dictionary = CaseManager.explain_chapter_completion(chapter_id)
	if not completion.get("has_completion_event", false):
		_add_line(case_chapter_list, "      (no completion_event — complete manually via the button above)")
	else:
		_add_line(case_chapter_list, "  COMPLETION CONDITIONS:")
		for condition_line in completion.get("conditions", []):
			var mark: String = "x" if condition_line.get("passed", false) else " "
			_add_line(case_chapter_list, "      [%s] %s" % [mark, condition_line.get("description", "")])

	var next_chapter: String = chapter_data.get("next_chapter", "")
	_add_line(case_chapter_list, "  NEXT: %s" % (next_chapter if next_chapter != "" else "(none — completing this chapter completes the case)"))

	var completed_chapters: Array[String] = CaseManager.get_completed_chapters(case_id)
	_add_line(case_chapter_list, "  COMPLETED CHAPTERS: %s" % (", ".join(completed_chapters) if not completed_chapters.is_empty() else "(none)"))


func _render_log_tab() -> void:
	UiUtil.clear_children(log_list)
	if _log_lines.is_empty():
		_add_line(log_list, "(no debug actions yet this session)")
		return
	for i in range(_log_lines.size() - 1, -1, -1):
		_add_line(log_list, _log_lines[i])


func _add_line(parent: VBoxContainer, text: String, is_header: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_header:
		label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)


func _add_header(parent: VBoxContainer, text: String) -> void:
	_add_line(parent, text, true)


func _matches_filter(text: String, filter: String) -> bool:
	return filter.is_empty() or text.to_lower().contains(filter.to_lower())


## Only inspection/mutation actions log — passive rendering (refresh()) never
## does, per section 26's "do not spam logs for passive inspection."
func _log(message: String) -> void:
	_log_lines.append("[%s] %s" % [Time.get_time_string_from_system(), message])
	if _log_lines.size() > LOG_LIMIT:
		_log_lines.pop_front()
	print("[CaseDebugger] %s" % message)
	if visible:
		_render_log_tab()


# ---------------------------------------------------------------------------
# Actions — see the class doc above for which of these are normal-pipeline
# mutations vs. explicit debug overrides.

func _set_flag(flag_name: String, value: bool) -> void:
	GameState.set_flag(flag_name, value)
	_log("Set flag \"%s\" = %s" % [flag_name, value])
	status_label.text = "Flag \"%s\" is now %s." % [flag_name, value]


func _set_flag_from_field(value: bool) -> void:
	var flag_name := flag_name_edit.text.strip_edges()
	if flag_name.is_empty():
		status_label.text = "Enter a flag name first."
		return
	_set_flag(flag_name, value)


func _set_evidence(evidence_id: String, held: bool) -> void:
	if held:
		GameState.add_evidence(evidence_id)
		_log("Added evidence \"%s\"" % evidence_id)
	else:
		GameState.remove_evidence(evidence_id)
		_log("Removed evidence \"%s\"" % evidence_id)


func _on_add_evidence_pressed() -> void:
	var evidence_id := evidence_id_edit.text.strip_edges()
	if evidence_id.is_empty():
		return
	if ContentDB.get_evidence(evidence_id).is_empty():
		status_label.text = "Unknown evidence id \"%s\"." % evidence_id
		return
	_set_evidence(evidence_id, true)
	status_label.text = "Added evidence \"%s\"." % evidence_id


func _on_remove_evidence_pressed() -> void:
	var evidence_id := evidence_id_edit.text.strip_edges()
	if evidence_id.is_empty():
		return
	_set_evidence(evidence_id, false)
	status_label.text = "Removed evidence \"%s\" (if it was held)." % evidence_id


## Jump is a debugging shortcut, not simulated player progression: it bypasses
## the destination's own `condition` (a teleport for testing), but still goes
## through GameState.go_to_location() — the ONE production API for changing
## location — so visited_locations/location_changed/Event reevaluation all
## still happen exactly as they would from a real Move. See
## docs/case-debugger.md, "Location jump vs. normal player progression."
func _on_jump_pressed() -> void:
	var location_id := location_id_edit.text.strip_edges()
	if location_id.is_empty():
		return
	if ContentDB.get_location(location_id).is_empty():
		status_label.text = "Unknown location id \"%s\"." % location_id
		return
	# The only path in the game that can change location while a dialogue is
	# on screen — Investigation refuses to, and the Menu button is disabled
	# mid-dialogue — so stop it first or the rest of its actions would fire
	# into state it was never written against.
	DialogueManager.stop()
	GameState.go_to_location(location_id)
	_log("Jumped to location \"%s\" (destination condition bypassed)" % location_id)
	status_label.text = "Jumped to \"%s\" (destination condition bypassed)." % location_id


func _on_trigger_event_pressed() -> void:
	var event_id := event_id_edit.text.strip_edges()
	if event_id.is_empty():
		status_label.text = "Enter an event id first."
		return
	if ContentDB.get_event(event_id).is_empty():
		status_label.text = "Unknown event id \"%s\"." % event_id
		return
	_confirm(
		"Manually trigger event \"%s\"?\nThis bypasses its conditions AND trigger_policy — it will run its effects right now regardless of whether they'd normally fire." % event_id,
		func(): _do_trigger_event(event_id)
	)


func _do_trigger_event(event_id: String) -> void:
	if not EventManager.force_trigger(event_id):
		status_label.text = "Unknown event id \"%s\"." % event_id
		return
	_log("Manually triggered event \"%s\" (conditions and trigger_policy bypassed)" % event_id)
	status_label.text = "Triggered event \"%s\" (conditions bypassed)." % event_id


## See EventManager.debug_reset_trigger()'s own doc comment for exactly what
## this does and does not undo — no confirmation dialog: unlike a manual
## trigger it never re-runs effects by itself (only a genuine subsequent
## state change can do that), so it's the least destructive override here.
func _on_reset_event_pressed() -> void:
	var event_id := event_id_edit.text.strip_edges()
	if event_id.is_empty():
		status_label.text = "Enter an event id first."
		return
	if not EventManager.debug_reset_trigger(event_id):
		status_label.text = "Unknown event id \"%s\"." % event_id
		return
	_log("Reset trigger marker for event \"%s\" (effects already run are NOT undone)" % event_id)
	status_label.text = "Reset \"%s\"'s trigger marker (its world-state effects were NOT undone)." % event_id


## Starts (or switches to) any case by id — the same generic path SaveManager
## uses for "New Game", exposed here so any case can be reached without
## replaying up to it. Like Jump/Reset, this can yank state out from under a
## running dialogue, so it stops one first.
func _on_start_case_pressed() -> void:
	var case_id := case_id_edit.text.strip_edges()
	if case_id.is_empty():
		status_label.text = "Enter a case id first."
		return
	if ContentDB.get_case(case_id).is_empty():
		status_label.text = "Unknown case id \"%s\"." % case_id
		return
	DialogueManager.stop()
	CaseManager.start_case(case_id)
	_log("Started case \"%s\"" % case_id)
	status_label.text = "Started case \"%s\"." % case_id


func _on_jump_chapter_pressed() -> void:
	var chapter_id := chapter_id_edit.text.strip_edges()
	if chapter_id.is_empty():
		return
	if not CaseManager.jump_to_chapter(chapter_id):
		status_label.text = "Unknown chapter id \"%s\"." % chapter_id
		return
	_log("Jumped to chapter \"%s\" (entry_effects run; no chapter marked complete)" % chapter_id)
	status_label.text = "Jumped to chapter \"%s\" (entry effects applied; no completion checked)." % chapter_id


func _on_complete_chapter_pressed() -> void:
	var chapter_id: String = CaseManager.get_current_chapter_id()
	if chapter_id == "":
		status_label.text = "No current chapter to complete."
		return
	_confirm(
		"Force-complete the current chapter (\"%s\")?\nThis runs its completion_event through the normal Event pipeline, bypassing the event's own conditions." % chapter_id,
		_do_complete_chapter
	)


func _do_complete_chapter() -> void:
	if not CaseManager.force_complete_current_chapter():
		status_label.text = "No current chapter with a completion_event to force."
		return
	_log("Forced the current chapter to complete")
	status_label.text = "Forced the current chapter to complete."


## Chapter reset is deliberately NOT offered (section 21): there is no
## structurally-enforced boundary for "this flag/evidence/interaction belongs
## to chapter X" (docs/case-system.md, "Event/content scope" — it's a
## flag-naming convention, not something ContentDB/GameState tracks), so a
## partial reset could not reliably clear only that chapter's state without
## either under-clearing (stale progression left behind) or over-clearing
## (unrelated shared state wiped). Reset Case is the one safe, well-defined
## reset boundary this architecture actually has.
func _on_reset_pressed() -> void:
	var case_id: String = CaseManager.get_current_case_id()
	if case_id == "":
		status_label.text = "No case active to reset."
		return
	_confirm(
		"Reset case \"%s\" back to its starting state?\nAll flags, evidence, visited locations, and event/chapter progression will be cleared." % case_id,
		_do_reset_case
	)


func _do_reset_case() -> void:
	DialogueManager.stop()
	CaseManager.reset_case()
	_log("Reset case \"%s\"" % CaseManager.get_current_case_id())
	status_label.text = "Case reset."


func _confirm(message: String, action: Callable) -> void:
	_pending_confirmed_action = action
	confirm_dialog.dialog_text = message
	confirm_dialog.popup_centered()


func _on_confirm_dialog_confirmed() -> void:
	if _pending_confirmed_action.is_valid():
		_pending_confirmed_action.call()
	_pending_confirmed_action = Callable()


# ---------------------------------------------------------------------------
# Condition Inspector — consumes ConditionEvaluator.explain_tree() (the exact
# same evaluator used everywhere else in this project) and formats it as a
# nested box-drawing tree. No condition evaluation logic is reimplemented
# here — this is display formatting only.

func _on_inspector_show_pressed() -> void:
	_perform_inspect(inspector_kind_option.get_selected_id(), inspector_id_edit.text.strip_edges(), inspector_second_id_edit.text.strip_edges())


func _perform_inspect(kind: int, id_a: String, id_b: String) -> void:
	if id_a.is_empty():
		status_label.text = "Enter an id to inspect first."
		return

	var condition = null
	var label: String = ""
	match kind:
		0:  # Event conditions
			if ContentDB.get_event(id_a).is_empty():
				status_label.text = "Unknown event id \"%s\"." % id_a
				return
			condition = ContentDB.get_event(id_a).get("conditions")
			label = "Event \"%s\" conditions" % id_a
		1:  # Topic condition — id_a is the npc id, id_b the topic id
			var found_topic: Dictionary = {}
			for topic in Investigation.get_all_topics(id_a):
				if topic.get("id", "") == id_b:
					found_topic = topic
					break
			if found_topic.is_empty():
				status_label.text = "No topic \"%s\" on npc \"%s\" at the current location." % [id_b, id_a]
				return
			condition = found_topic.get("condition")
			label = "Topic \"%s\" (npc \"%s\") condition" % [id_b, id_a]
		2:  # Destination condition — id_a is the destination's location_id
			var found_destination: Dictionary = {}
			for destination in Investigation.get_all_destinations():
				if destination.get("location_id", "") == id_a:
					found_destination = destination
					break
			if found_destination.is_empty():
				status_label.text = "\"%s\" is not a destination of the current location." % id_a
				return
			condition = found_destination.get("condition")
			label = "Destination \"%s\" condition" % id_a
		3:  # NPC presence condition — id_a is the npc id, at the current location
			var found_npc: Dictionary = {}
			for npc in Investigation.get_all_npcs():
				if npc.get("id", "") == id_a:
					found_npc = npc
					break
			if found_npc.is_empty():
				status_label.text = "\"%s\" is not an npc entry at the current location." % id_a
				return
			condition = found_npc.get("condition")
			label = "NPC \"%s\" presence condition" % id_a
		4:  # Chapter completion conditions — id_a is the chapter id
			var chapter: Dictionary = ContentDB.get_chapter(id_a)
			if chapter.is_empty():
				status_label.text = "Unknown chapter id \"%s\"." % id_a
				return
			var completion_event: String = chapter.get("completion_event", "")
			if completion_event == "":
				status_label.text = "Chapter \"%s\" has no completion_event." % id_a
				return
			condition = ContentDB.get_event(completion_event).get("conditions")
			label = "Chapter \"%s\" completion (event \"%s\") conditions" % [id_a, completion_event]
		_:
			return

	_last_inspected_kind = kind
	_last_inspected_id = id_a
	_last_inspected_second_id = id_b
	_render_condition_tree(label, condition)


func _render_condition_tree(label: String, condition) -> void:
	UiUtil.clear_children(inspector_condition_tree)
	_add_header(inspector_condition_tree, label)
	_append_condition_tree_node(inspector_condition_tree, ConditionEvaluator.explain_tree(condition), "", "")


## Appends one line for `node` (using `line_prefix`, already including this
## line's own branch glyph) plus one recursive call per child (continuing
## from `child_prefix`) — the standard box-drawing tree-printing recursion.
## The root call passes both prefixes empty.
func _append_condition_tree_node(parent: VBoxContainer, node: Dictionary, line_prefix: String, child_prefix: String) -> void:
	var mark: String = "TRUE" if node.get("passed", false) else "FALSE"
	_add_line(parent, "%s%s → %s" % [line_prefix, node.get("description", ""), mark])
	var children: Array = node.get("children", [])
	for i in children.size():
		var is_last: bool = i == children.size() - 1
		var branch: String = "└─ " if is_last else "├─ "
		var continuation: String = "   " if is_last else "│  "
		_append_condition_tree_node(parent, children[i], child_prefix + branch, child_prefix + continuation)


# ---------------------------------------------------------------------------
# Producer / dependency lookup — consumes ContentValidator.find_*_producers()
# (Milestone 1.8), itself built on the exact same three effect-carrying
# places ContentValidator's own dependency-reachability WARNING already
# walks. Existence only, never a reachability guarantee — see
# docs/case-debugger.md, "Known producers," and docs/testing.md, "Progression
# dependency validation."

func _on_producer_lookup_pressed() -> void:
	_perform_producer_lookup(producer_kind_option.get_selected_id(), producer_id_edit.text.strip_edges())


func _perform_producer_lookup(kind: int, id: String) -> void:
	if id.is_empty():
		status_label.text = "Enter a flag/evidence/interaction id first."
		return

	var producers: Array[Dictionary] = []
	var label: String = ""
	match kind:
		0:
			producers = ContentValidator.find_flag_producers(id)
			label = "Known producers of flag \"%s\" becoming true" % id
		1:
			producers = ContentValidator.find_evidence_producers(id)
			label = "Known producers of evidence \"%s\"" % id
		2:
			producers = ContentValidator.find_interaction_producers(id)
			label = "Known producers of interaction_complete \"%s\"" % id
		_:
			return

	_last_producer_kind = kind
	_last_producer_id = id
	_render_producer_results(label, producers)


func _render_producer_results(label: String, producers: Array[Dictionary]) -> void:
	UiUtil.clear_children(producer_results)
	_add_header(producer_results, "%s — %d known producer(s) (existence only, NOT a reachability guarantee)" % [label, producers.size()])
	if producers.is_empty():
		_add_line(producer_results, "(none found in loaded content — this may be permanently unreachable)")
	for producer in producers:
		_add_line(producer_results, "  %s → %s" % [producer.get("source", ""), producer.get("description", "")])
