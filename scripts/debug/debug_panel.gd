extends Control
## Developer-only debug overlay (Part D of the content-pipeline work): F1
## toggles it. Entirely self-contained — unlike GameMenu/EvidenceInventory it
## is never wired up by Main.gd, because nothing else needs to coordinate
## with it (see docs/architecture.md, "Developer tools").
##
## In a release export, OS.is_debug_build() is false and _ready() returns
## before connecting anything or reacting to input, so this scene is dead
## weight (present in the tree, but inert) rather than something that needs
## to be removed from Main.tscn by hand later.
##
## Reads state through the same public APIs normal UI uses (GameState /
## ContentDB / Investigation / EventManager) — it has no special back-door
## access, and the actions below (set/unset flag, add/remove evidence, jump
## location, trigger event, reset) call the exact same GameState/
## Investigation/EventManager methods content-driven gameplay would, just
## without going through a condition check first. That last part is the one
## deliberate difference from normal play: jumping to a location skips the
## destination's `condition` (it's a teleport for testing, not a move),
## toggling a flag or evidence doesn't require a dialogue action to have set
## it, and triggering an event bypasses its conditions and trigger_policy —
## see EventManager.force_trigger().

@onready var close_button: Button = %CloseButton
@onready var report_list: VBoxContainer = %ReportList
@onready var flag_name_edit: LineEdit = %FlagNameEdit
@onready var toggle_flag_button: Button = %ToggleFlagButton
@onready var evidence_id_edit: LineEdit = %EvidenceIdEdit
@onready var add_evidence_button: Button = %AddEvidenceButton
@onready var remove_evidence_button: Button = %RemoveEvidenceButton
@onready var location_id_edit: LineEdit = %LocationIdEdit
@onready var jump_button: Button = %JumpButton
@onready var event_id_edit: LineEdit = %EventIdEdit
@onready var trigger_event_button: Button = %TriggerEventButton
@onready var case_id_edit: LineEdit = %CaseIdEdit
@onready var start_case_button: Button = %StartCaseButton
@onready var chapter_id_edit: LineEdit = %ChapterIdEdit
@onready var jump_chapter_button: Button = %JumpChapterButton
@onready var complete_chapter_button: Button = %CompleteChapterButton
@onready var reset_button: Button = %ResetButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		set_process_input(false)
		return

	close_button.pressed.connect(close)
	toggle_flag_button.pressed.connect(_on_toggle_flag_pressed)
	add_evidence_button.pressed.connect(_on_add_evidence_pressed)
	remove_evidence_button.pressed.connect(_on_remove_evidence_pressed)
	jump_button.pressed.connect(_on_jump_pressed)
	trigger_event_button.pressed.connect(_on_trigger_event_pressed)
	start_case_button.pressed.connect(_on_start_case_pressed)
	jump_chapter_button.pressed.connect(_on_jump_chapter_pressed)
	complete_chapter_button.pressed.connect(_on_complete_chapter_pressed)
	reset_button.pressed.connect(_on_reset_pressed)

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
# Report

func refresh() -> void:
	UiUtil.clear_children(report_list)

	_add_line("CASE", true)
	_add_case_lines()

	_add_line("LOCATION", true)
	var location: Dictionary = Investigation.get_current_location()
	_add_line("%s (%s)" % [tr(location.get("name", GameState.current_location)), GameState.current_location])

	_add_line("VISITED LOCATIONS", true)
	_add_line(", ".join(GameState.visited_locations) if not GameState.visited_locations.is_empty() else "(none)")

	_add_line("EVIDENCE", true)
	if GameState.evidence_inventory.is_empty():
		_add_line("(none)")
	for evidence_id in GameState.evidence_inventory:
		var data: Dictionary = ContentDB.get_evidence(evidence_id)
		_add_line("%s — %s" % [evidence_id, tr(data.get("name", "?"))])

	_add_line("FLAGS", true)
	var flag_names: Array = GameState.flags.keys()
	flag_names.sort()
	if flag_names.is_empty():
		_add_line("(none)")
	for flag_name in flag_names:
		_add_line("%s = %s" % [flag_name, GameState.flags[flag_name]])

	_add_line("CHARACTERS (this location)", true)
	var all_npcs: Array = Investigation.get_all_npcs()
	if all_npcs.is_empty():
		_add_line("(no NPCs defined here)")
	for npc in all_npcs:
		_add_npc_line(npc)

	_add_line("DESTINATIONS (this location)", true)
	var destinations: Array = Investigation.get_all_destinations()
	if destinations.is_empty():
		_add_line("(none defined)")
	for destination in destinations:
		_add_destination_line(destination)

	_add_line("EVENTS", true)
	var event_ids: Array = ContentDB.get_all_event_ids()
	if event_ids.is_empty():
		_add_line("(no events defined)")
	for event_id in event_ids:
		_add_event_line(event_id)


## Case/Chapter status (Milestone 1.6) — reads only through CaseManager's own
## public API, same "no back-door access" rule every other section here
## follows. A flat case (case_00_sandbox) shows no chapter section at all.
func _add_case_lines() -> void:
	var case_id: String = CaseManager.get_current_case_id()
	if case_id == "":
		_add_line("(no case active)")
		return

	var case_data: Dictionary = ContentDB.get_case(case_id)
	var case_name: String = tr(case_data.get("display_name", case_data.get("title", case_id)))
	var case_status: String = "COMPLETED" if CaseManager.is_case_complete(case_id) else "ACTIVE"
	_add_line("[%s] %s (%s)" % [case_status, case_name, case_id])

	var chapter_id: String = CaseManager.get_current_chapter_id()
	if chapter_id == "":
		_add_line("  (flat case — no chapter tracking)")
		return

	var chapter_data: Dictionary = ContentDB.get_chapter(chapter_id)
	var chapter_name: String = tr(chapter_data.get("display_name", chapter_id))
	_add_line("  CURRENT CHAPTER: %s (%s)" % [chapter_name, chapter_id])

	var completion: Dictionary = CaseManager.explain_chapter_completion(chapter_id)
	if not completion.get("has_completion_event", false):
		_add_line("      (no completion_event — complete manually via debug tools)")
	else:
		_add_line("  COMPLETION CONDITIONS:")
		for condition_line in completion.get("conditions", []):
			var mark: String = "x" if condition_line.get("passed", false) else " "
			_add_line("      [%s] %s" % [mark, condition_line.get("description", "")])

	var completed_chapters: Array[String] = CaseManager.get_completed_chapters(case_id)
	_add_line("  COMPLETED CHAPTERS: %s" % (", ".join(completed_chapters) if not completed_chapters.is_empty() else "(none)"))


func _add_npc_line(npc: Dictionary) -> void:
	var npc_id: String = npc.get("id", "")
	var presence: Dictionary = Investigation.explain_npc_presence(npc)
	var is_present: bool = not presence.get("locked", true)
	var status: String = "PRESENT" if is_present else "ABSENT"
	_add_line("[%s] %s (%s)" % [status, tr(ContentDB.get_character(npc_id).get("name", npc_id)), npc_id])
	if not is_present:
		for condition_line in presence.get("conditions", []):
			if not condition_line.get("passed", true):
				_add_line("      missing: %s" % condition_line.get("description", ""))
		return
	for topic in Investigation.get_all_topics(npc_id):
		_add_topic_line(npc_id, topic)


func _add_event_line(event_id: String) -> void:
	var info: Dictionary = EventManager.explain_event(event_id)
	var triggered: bool = info.get("triggered", false)
	var satisfied: bool = info.get("conditions_satisfied", false)
	var status: String = "TRIGGERED" if triggered else ("CONDITIONS MET" if satisfied else "NOT TRIGGERED")
	_add_line("[%s] %s" % [status, event_id])
	for condition_line in info.get("conditions", []):
		var mark: String = "x" if condition_line.get("passed", false) else " "
		_add_line("      [%s] %s" % [mark, condition_line.get("description", "")])


func _add_topic_line(npc_id: String, topic: Dictionary) -> void:
	var topic_id: String = topic.get("id", "")
	var lock_info: Dictionary = Investigation.explain_topic_lock(npc_id, topic_id)
	var status: String = "LOCKED" if lock_info.get("locked", true) else "AVAILABLE"
	var seen_tag: String = "  (read)" if Investigation.is_topic_seen(npc_id, topic_id) else ""
	_add_line("  [%s] %s (%s)%s" % [status, tr(topic.get("label", topic_id)), topic_id, seen_tag])
	if lock_info.get("locked", true):
		for condition_line in lock_info.get("conditions", []):
			if not condition_line.get("passed", true):
				_add_line("      missing: %s" % condition_line.get("description", ""))


func _add_destination_line(destination: Dictionary) -> void:
	var location_id: String = destination.get("location_id", "")
	var lock_info: Dictionary = Investigation.explain_destination_lock(location_id)
	var status: String = "LOCKED" if lock_info.get("locked", true) else "AVAILABLE"
	_add_line("  [%s] %s (%s)" % [status, tr(destination.get("label", location_id)), location_id])
	if lock_info.get("locked", true):
		for condition_line in lock_info.get("conditions", []):
			if not condition_line.get("passed", true):
				_add_line("      missing: %s" % condition_line.get("description", ""))


func _add_line(text: String, is_header: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_header:
		label.add_theme_font_size_override("font_size", 14)
	report_list.add_child(label)


# ---------------------------------------------------------------------------
# Actions

func _on_toggle_flag_pressed() -> void:
	var flag_name := flag_name_edit.text.strip_edges()
	if flag_name.is_empty():
		status_label.text = "Enter a flag name first."
		return
	GameState.set_flag(flag_name, not GameState.get_flag(flag_name))
	status_label.text = "Flag \"%s\" is now %s." % [flag_name, GameState.get_flag(flag_name)]


func _on_add_evidence_pressed() -> void:
	var evidence_id := evidence_id_edit.text.strip_edges()
	if evidence_id.is_empty():
		return
	if ContentDB.get_evidence(evidence_id).is_empty():
		status_label.text = "Unknown evidence id \"%s\"." % evidence_id
		return
	GameState.add_evidence(evidence_id)
	status_label.text = "Added evidence \"%s\"." % evidence_id


func _on_remove_evidence_pressed() -> void:
	var evidence_id := evidence_id_edit.text.strip_edges()
	if evidence_id.is_empty():
		return
	GameState.remove_evidence(evidence_id)
	status_label.text = "Removed evidence \"%s\" (if it was held)." % evidence_id


func _on_jump_pressed() -> void:
	var location_id := location_id_edit.text.strip_edges()
	if location_id.is_empty():
		return
	if ContentDB.get_location(location_id).is_empty():
		status_label.text = "Unknown location id \"%s\"." % location_id
		return
	# These two actions are the only way in the game to change location or
	# reset the case while a dialogue is on screen (Investigation refuses to,
	# and the Menu button is disabled mid-dialogue). Abort it first, or the
	# rest of that dialogue's actions would go on firing into state it was
	# never written against.
	DialogueManager.stop()
	GameState.go_to_location(location_id)
	status_label.text = "Jumped to \"%s\" (destination conditions bypassed)." % location_id


func _on_trigger_event_pressed() -> void:
	var event_id := event_id_edit.text.strip_edges()
	if event_id.is_empty():
		status_label.text = "Enter an event id first."
		return
	if not EventManager.force_trigger(event_id):
		status_label.text = "Unknown event id \"%s\"." % event_id
		return
	status_label.text = "Triggered event \"%s\" (conditions bypassed)." % event_id


## Starts (or switches to) any case by id — the same generic path SaveManager
## uses for "New Game", exposed here so the Test Case (or any future case)
## can be reached without changing the title screen's default. Like the
## location jump/reset below, this can yank state out from under a running
## dialogue, so it stops one first.
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
	status_label.text = "Started case \"%s\"." % case_id


func _on_jump_chapter_pressed() -> void:
	var chapter_id := chapter_id_edit.text.strip_edges()
	if chapter_id.is_empty():
		return
	if not CaseManager.jump_to_chapter(chapter_id):
		status_label.text = "Unknown chapter id \"%s\"." % chapter_id
		return
	status_label.text = "Jumped to chapter \"%s\" (entry effects applied; no completion checked)." % chapter_id


func _on_complete_chapter_pressed() -> void:
	if not CaseManager.force_complete_current_chapter():
		status_label.text = "No current chapter with a completion_event to force."
		return
	status_label.text = "Forced the current chapter to complete."


func _on_reset_pressed() -> void:
	var case_id: String = GameState.get_var("case_id", "case_00_sandbox")
	DialogueManager.stop()
	CaseManager.start_case(case_id)
	status_label.text = "Case reset (case \"%s\")." % case_id
