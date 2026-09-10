extends Control
## Pure view over DialogueManager: shows/hides itself based on
## dialogue_started/dialogue_ended, and only ever calls
## DialogueManager.advance()/choose() in response to player input. Holds no
## story logic and never reads ContentDB directly except to resolve a
## character's display name/portrait color for the line currently on screen.

const CHARS_PER_SECOND := 40.0

@onready var portrait_visual: Control = %PortraitVisual
@onready var speaker_label: Label = %SpeakerLabel
@onready var dialogue_text: Label = %DialogueText
@onready var advance_hint: Label = %AdvanceHint
@onready var choices_box: VBoxContainer = %ChoicesBox

var _full_text: String = ""
var _typewriter_progress: float = 0.0
var _is_typing: bool = false
var _pending_choice_texts: Array = []


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.line_shown.connect(_on_line_shown)
	DialogueManager.choices_shown.connect(_on_choices_shown)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _process(delta: float) -> void:
	if not _is_typing:
		return
	_typewriter_progress += CHARS_PER_SECOND * delta
	var shown_count := int(_typewriter_progress)
	if shown_count >= _full_text.length():
		_complete_typewriter()
	else:
		dialogue_text.visible_characters = shown_count


func _on_dialogue_started(_dialogue_id: String) -> void:
	visible = true
	choices_box.visible = false
	advance_hint.visible = false


func _on_line_shown(character_id: String, expression: String, text: String) -> void:
	choices_box.visible = false
	advance_hint.visible = false
	_pending_choice_texts = []

	if character_id == "":
		speaker_label.text = ""
		portrait_visual.visible = false
	else:
		var character: Dictionary = ContentDB.get_character(character_id)
		var expressions: Dictionary = character.get("expressions", {})
		speaker_label.text = character.get("name", character_id)
		portrait_visual.visible = true
		portrait_visual.set_color_hex(expressions.get(expression, expressions.get("normal", "#888888")))
		portrait_visual.set_caption(expression)

	_full_text = text
	dialogue_text.text = text
	dialogue_text.visible_characters = 0
	_typewriter_progress = 0.0
	_is_typing = true


func _on_choices_shown(choice_texts: Array) -> void:
	_pending_choice_texts = choice_texts


func _on_dialogue_ended() -> void:
	visible = false


func _complete_typewriter() -> void:
	_is_typing = false
	dialogue_text.visible_characters = -1
	if _pending_choice_texts.is_empty():
		advance_hint.visible = true
	else:
		_show_choices(_pending_choice_texts)


func _show_choices(choice_texts: Array) -> void:
	for child in choices_box.get_children():
		child.queue_free()
	for i in choice_texts.size():
		var choice_button := Button.new()
		choice_button.text = choice_texts[i]
		choice_button.pressed.connect(_on_choice_pressed.bind(i))
		choices_box.add_child(choice_button)
	choices_box.visible = true


func _on_choice_pressed(index: int) -> void:
	DialogueManager.choose(index)


## Skips the typewriter if still typing; otherwise advances to the next
## line. Does nothing while choices are on screen — the player must click
## one of the choice buttons, which resolve through _on_choice_pressed.
func _try_advance() -> void:
	if _is_typing:
		_complete_typewriter()
	elif not choices_box.visible:
		DialogueManager.advance()


## Click anywhere on the box (except on an actual choice button, which
## intercepts its own click first) to advance. Relies on Label defaulting
## to MOUSE_FILTER_IGNORE and the "Box" panel being explicitly set to PASS
## in the scene, so the click falls through to this root Control.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept"):
		_try_advance()
		get_viewport().set_input_as_handled()
