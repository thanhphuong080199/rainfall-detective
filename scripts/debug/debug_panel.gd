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
## ContentDB / Investigation) — it has no special back-door access, and the
## actions below (set/unset flag, add/remove evidence, jump location, reset)
## call the exact same GameState/Investigation methods content-driven
## gameplay would, just without going through a condition check first. That
## last part is the one deliberate difference from normal play: jumping to
## a location skips the destination's `condition` (it's a teleport for
## testing, not a move), and toggling a flag or evidence doesn't require a
## dialogue action to have set it.

@onready var close_button: Button = %CloseButton
@onready var report_list: VBoxContainer = %ReportList
@onready var flag_name_edit: LineEdit = %FlagNameEdit
@onready var toggle_flag_button: Button = %ToggleFlagButton
@onready var evidence_id_edit: LineEdit = %EvidenceIdEdit
@onready var add_evidence_button: Button = %AddEvidenceButton
@onready var remove_evidence_button: Button = %RemoveEvidenceButton
@onready var location_id_edit: LineEdit = %LocationIdEdit
@onready var jump_button: Button = %JumpButton
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
	reset_button.pressed.connect(_on_reset_pressed)

	GameState.flag_changed.connect(func(_n, _v): _refresh_if_visible())
	GameState.evidence_added.connect(func(_id): _refresh_if_visible())
	GameState.evidence_removed.connect(func(_id): _refresh_if_visible())
	GameState.location_changed.connect(func(_id): _refresh_if_visible())
	GameState.interaction_seen.connect(func(_key): _refresh_if_visible())
	DialogueManager.dialogue_ended.connect(_refresh_if_visible)


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

	_add_line("LOCATION", true)
	var location: Dictionary = Investigation.get_current_location()
	_add_line("%s (%s)" % [location.get("name", GameState.current_location), GameState.current_location])

	_add_line("VISITED LOCATIONS", true)
	_add_line(", ".join(GameState.visited_locations) if not GameState.visited_locations.is_empty() else "(none)")

	_add_line("EVIDENCE", true)
	if GameState.evidence_inventory.is_empty():
		_add_line("(none)")
	for evidence_id in GameState.evidence_inventory:
		var data: Dictionary = ContentDB.get_evidence(evidence_id)
		_add_line("%s — %s" % [evidence_id, data.get("name", "?")])

	_add_line("FLAGS", true)
	var flag_names: Array = GameState.flags.keys()
	flag_names.sort()
	if flag_names.is_empty():
		_add_line("(none)")
	for flag_name in flag_names:
		_add_line("%s = %s" % [flag_name, GameState.flags[flag_name]])

	_add_line("TALK TOPICS (this location)", true)
	var npcs: Array = Investigation.get_npcs()
	if npcs.is_empty():
		_add_line("(no NPCs here)")
	for npc in npcs:
		var npc_id: String = npc.get("id", "")
		_add_line(ContentDB.get_character(npc_id).get("name", npc_id) + ":")
		for topic in Investigation.get_all_topics(npc_id):
			_add_topic_line(npc_id, topic)

	_add_line("DESTINATIONS (this location)", true)
	var destinations: Array = Investigation.get_all_destinations()
	if destinations.is_empty():
		_add_line("(none defined)")
	for destination in destinations:
		_add_destination_line(destination)


func _add_topic_line(npc_id: String, topic: Dictionary) -> void:
	var topic_id: String = topic.get("id", "")
	var lock_info: Dictionary = Investigation.explain_topic_lock(npc_id, topic_id)
	var status: String = "LOCKED" if lock_info.get("locked", true) else "AVAILABLE"
	var seen_tag: String = "  (read)" if Investigation.is_topic_seen(npc_id, topic_id) else ""
	_add_line("  [%s] %s (%s)%s" % [status, topic.get("label", topic_id), topic_id, seen_tag])
	if lock_info.get("locked", true):
		for condition_line in lock_info.get("conditions", []):
			if not condition_line.get("passed", true):
				_add_line("      missing: %s" % condition_line.get("description", ""))


func _add_destination_line(destination: Dictionary) -> void:
	var location_id: String = destination.get("location_id", "")
	var lock_info: Dictionary = Investigation.explain_destination_lock(location_id)
	var status: String = "LOCKED" if lock_info.get("locked", true) else "AVAILABLE"
	_add_line("  [%s] %s (%s)" % [status, destination.get("label", location_id), location_id])
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


func _on_reset_pressed() -> void:
	var case_id: String = GameState.get_var("case_id", "case_00_sandbox")
	DialogueManager.stop()
	GameState.start_new_game(case_id)
	status_label.text = "Sandbox state reset (case \"%s\")." % case_id
