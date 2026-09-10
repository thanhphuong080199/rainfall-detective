extends Control
## Base gameplay layer: shows the current location and lets the player
## Examine / Talk / Present / Move. Renders entirely from Investigation +
## ContentDB queries — it holds no story data of its own. "Present" doesn't
## open the inventory directly; it emits present_requested and lets Main.gd
## (the orchestrator) coordinate with the EvidenceInventory overlay, so this
## scene never needs a direct reference to that one.

signal evidence_button_pressed()
signal menu_button_pressed()
signal present_requested(npc_id: String)

@onready var background_visual: Control = %BackgroundVisual
@onready var location_label: Label = %LocationLabel
@onready var evidence_button: Button = %EvidenceButton
@onready var menu_button: Button = %MenuButton
@onready var action_list: VBoxContainer = %ActionList

var _current_mode: String = "main"


func _ready() -> void:
	evidence_button.pressed.connect(func(): evidence_button_pressed.emit())
	menu_button.pressed.connect(func(): menu_button_pressed.emit())
	GameState.location_changed.connect(func(_location_id): _render_main())
	GameState.flag_changed.connect(func(_flag_name, _value): _refresh_if_main())
	GameState.evidence_added.connect(func(_evidence_id): _refresh_if_main())
	DialogueManager.dialogue_ended.connect(_render_main)
	_render_main()


func set_interactive(is_interactive: bool) -> void:
	modulate.a = 1.0 if is_interactive else 0.5
	evidence_button.disabled = not is_interactive
	menu_button.disabled = not is_interactive
	_set_buttons_disabled(action_list, not is_interactive)


func _set_buttons_disabled(node: Node, is_disabled: bool) -> void:
	for child in node.get_children():
		if child is BaseButton:
			child.disabled = is_disabled
		_set_buttons_disabled(child, is_disabled)


func _refresh_if_main() -> void:
	if _current_mode == "main":
		_render_main()


func _clear_action_list() -> void:
	for child in action_list.get_children():
		child.queue_free()


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


func _render_main() -> void:
	_current_mode = "main"
	_clear_action_list()

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
		_add_action_button(character.get("name", npc_id), _on_npc_pressed.bind(npc_id))

	_add_section_label("Move")
	_add_action_button("Go somewhere else...", _render_destinations)


func _on_examine_pressed(point_id: String) -> void:
	Investigation.examine(point_id)


func _on_npc_pressed(npc_id: String) -> void:
	_render_npc_menu(npc_id)


func _render_npc_menu(npc_id: String) -> void:
	_current_mode = "npc_menu"
	_clear_action_list()
	var character: Dictionary = ContentDB.get_character(npc_id)
	_add_section_label(character.get("name", npc_id))
	_add_action_button("Talk", _render_topics.bind(npc_id))
	_add_action_button("Present Evidence", _on_present_pressed.bind(npc_id))
	_add_action_button("< Back", _render_main)


func _on_present_pressed(npc_id: String) -> void:
	present_requested.emit(npc_id)


func _render_topics(npc_id: String) -> void:
	_current_mode = "topics"
	_clear_action_list()
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


func _on_topic_pressed(npc_id: String, topic_id: String) -> void:
	Investigation.talk(npc_id, topic_id)


func _render_destinations() -> void:
	_current_mode = "destinations"
	_clear_action_list()
	_add_section_label("Move to...")

	for destination in Investigation.get_available_destinations():
		var location_id: String = destination.get("location_id", "")
		_add_action_button(destination.get("label", location_id), _on_destination_pressed.bind(location_id))

	_add_action_button("< Back", _render_main)


func _on_destination_pressed(location_id: String) -> void:
	Investigation.move_to(location_id)
