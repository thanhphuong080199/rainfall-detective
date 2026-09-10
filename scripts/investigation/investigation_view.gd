extends Control
## Base gameplay layer: shows the current location and lets the player
## Examine / Talk / Present / Move. Renders entirely from Investigation +
## ContentDB queries — it holds no story data of its own. "Present" doesn't
## open the inventory directly; it emits present_requested and lets Main.gd
## (the orchestrator) coordinate with the EvidenceInventory overlay, so this
## scene never needs a direct reference to that one.
##
## The action list is a stack-less "current view" rather than a menu stack:
## _mode (+ _mode_npc_id) says which of the four lists is on screen, and
## _render_current() rebuilds exactly that one. Anything that changes game
## state re-renders the view the player is actually looking at, instead of
## kicking them back to the root list.

signal evidence_button_pressed()
signal menu_button_pressed()
signal present_requested(npc_id: String)

@onready var background_visual: Control = %BackgroundVisual
@onready var location_label: Label = %LocationLabel
@onready var evidence_button: Button = %EvidenceButton
@onready var menu_button: Button = %MenuButton
@onready var action_list: VBoxContainer = %ActionList

var _mode: String = "main"
var _mode_npc_id: String = ""
## Mirrors the last set_interactive() call. _render_current() rebuilds the
## action buttons from scratch, so it has to re-apply this afterwards —
## otherwise every mid-dialogue state change (a flag being set, evidence
## being picked up) silently handed the player a fresh set of *enabled*
## buttons while the dialogue was still on screen.
var _is_interactive: bool = true


func _ready() -> void:
	evidence_button.pressed.connect(func(): evidence_button_pressed.emit())
	menu_button.pressed.connect(func(): menu_button_pressed.emit())
	GameState.location_changed.connect(_on_location_changed)
	GameState.flag_changed.connect(func(_flag_name, _value): _render_current())
	GameState.evidence_added.connect(func(_evidence_id): _render_current())
	GameState.evidence_removed.connect(func(_evidence_id): _render_current())
	GameState.interaction_seen.connect(func(_key): _render_current())
	DialogueManager.dialogue_ended.connect(_render_current)
	_render_current()


func set_interactive(is_interactive: bool) -> void:
	_is_interactive = is_interactive
	_apply_interactive()


func _apply_interactive() -> void:
	modulate.a = 1.0 if _is_interactive else 0.5
	evidence_button.disabled = not _is_interactive
	menu_button.disabled = not _is_interactive
	_set_buttons_disabled(action_list, not _is_interactive)


func _set_buttons_disabled(node: Node, is_disabled: bool) -> void:
	for child in node.get_children():
		if child is BaseButton:
			child.disabled = is_disabled
		_set_buttons_disabled(child, is_disabled)


## Changing location always drops back to the root list — the NPC/topic/
## destination lists all describe the location the player just left.
func _on_location_changed(_location_id: String) -> void:
	_mode = "main"
	_mode_npc_id = ""
	_render_current()


## Rebuilds whichever list is currently on screen.
func _render_current() -> void:
	match _mode:
		"npc_menu":
			_render_npc_menu(_mode_npc_id)
		"topics":
			_render_topics(_mode_npc_id)
		"destinations":
			_render_destinations()
		_:
			_render_main()


func _add_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	action_list.add_child(label)


func _add_action_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	action_list.add_child(button)


## Every _render_* below ends by re-applying the interactive state, because
## the buttons they just created default to enabled.
func _render_main() -> void:
	_mode = "main"
	_mode_npc_id = ""
	UiUtil.clear_children(action_list)

	var location: Dictionary = Investigation.get_current_location()
	location_label.text = location.get("name", GameState.current_location)
	background_visual.set_color_hex(location.get("background_color", "#333333"))

	_add_section_label("Examine")
	for point in Investigation.get_examine_points():
		var point_id: String = point.get("id", "")
		_add_action_button(point.get("label", point_id), _on_examine_pressed.bind(point_id))

	_add_section_label("Characters")
	for npc in Investigation.get_npcs():
		var npc_id: String = npc.get("id", "")
		var character: Dictionary = ContentDB.get_character(npc_id)
		_add_action_button(character.get("name", npc_id), _render_npc_menu.bind(npc_id))

	_add_section_label("Move")
	_add_action_button("Go somewhere else...", _render_destinations)
	_apply_interactive()


func _on_examine_pressed(point_id: String) -> void:
	Investigation.examine(point_id)


func _render_npc_menu(npc_id: String) -> void:
	_mode = "npc_menu"
	_mode_npc_id = npc_id
	UiUtil.clear_children(action_list)
	var character: Dictionary = ContentDB.get_character(npc_id)
	_add_section_label(character.get("name", npc_id))
	_add_action_button("Talk", _render_topics.bind(npc_id))
	_add_action_button("Present Evidence", _on_present_pressed.bind(npc_id))
	_add_action_button("< Back", _render_main)
	_apply_interactive()


func _on_present_pressed(npc_id: String) -> void:
	present_requested.emit(npc_id)


func _render_topics(npc_id: String) -> void:
	_mode = "topics"
	_mode_npc_id = npc_id
	UiUtil.clear_children(action_list)
	var character: Dictionary = ContentDB.get_character(npc_id)
	_add_section_label("Talk to " + character.get("name", npc_id))

	var topics: Array = Investigation.get_topics(npc_id)
	if topics.is_empty():
		_add_section_label("(nothing to talk about yet)")
	for topic in topics:
		var topic_id: String = topic.get("id", "")
		var label: String = topic.get("label", topic_id)
		if Investigation.is_topic_seen(npc_id, topic_id):
			label += " (read)"
		_add_action_button(label, _on_topic_pressed.bind(npc_id, topic_id))

	_add_action_button("< Back", _render_npc_menu.bind(npc_id))
	_apply_interactive()


func _on_topic_pressed(npc_id: String, topic_id: String) -> void:
	Investigation.talk(npc_id, topic_id)


func _render_destinations() -> void:
	_mode = "destinations"
	_mode_npc_id = ""
	UiUtil.clear_children(action_list)
	_add_section_label("Move to...")

	for destination in Investigation.get_available_destinations():
		var location_id: String = destination.get("location_id", "")
		_add_action_button(destination.get("label", location_id), _on_destination_pressed.bind(location_id))

	_add_action_button("< Back", _render_main)
	_apply_interactive()


func _on_destination_pressed(location_id: String) -> void:
	Investigation.move_to(location_id)
