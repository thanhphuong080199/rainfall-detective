extends Node
## Autoload: DialogueManager
##
## Plays a dialogue tree (loaded from ContentDB by id) one node at a time.
## This is a pure playback engine with no UI code — DialogueBox (the UI
## scene) only listens to these signals and calls start()/advance()/choose().
##
## Node shapes (see docs/content-guide.md for authoring details):
##   line:            {speaker, expression, text, actions?, next?}
##   line w/ choices: {speaker, expression, text, actions?, choices: [
##                        {text, condition?, actions?, next?}, ...
##                     ]}
## "next" (on a line, or on a choice) is a node id, or null/absent to end
## the dialogue. There is deliberately no separate "branch" node type —
## which dialogue tree to play at all is decided one level up, by
## Investigation, via content-data variants (see investigation_manager.gd).

signal dialogue_started(dialogue_id: String)
signal line_shown(character_id: String, expression: String, text: String)
signal choices_shown(choice_texts: Array)
signal dialogue_ended()

var is_active: bool = false

var _dialogue_id: String = ""
var _nodes: Dictionary = {}
var _current_node: Dictionary = {}
var _current_choices: Array = []


func start(dialogue_id: String) -> void:
	if is_active:
		push_warning("DialogueManager.start: '%s' already active, ignoring start('%s')" % [_dialogue_id, dialogue_id])
		return
	var tree: Dictionary = ContentDB.get_dialogue(dialogue_id)
	if tree.is_empty():
		push_error("DialogueManager.start: unknown dialogue '%s'" % dialogue_id)
		return

	_dialogue_id = dialogue_id
	_nodes = tree.get("nodes", {})
	is_active = true
	dialogue_started.emit(dialogue_id)
	_show_node(tree.get("start", ""))


## Called by the UI when the player advances a line that has no (visible) choices.
func advance() -> void:
	if not is_active or not _current_choices.is_empty():
		return
	_show_node(_current_node.get("next", ""))


## Called by the UI with the index of the choice the player picked, as
## indexed into the choice texts most recently sent via choices_shown.
func choose(index: int) -> void:
	if not is_active or index < 0 or index >= _current_choices.size():
		return
	var choice: Dictionary = _current_choices[index]
	_run_actions(choice.get("actions", []))
	_show_node(choice.get("next", ""))


func _show_node(node_id) -> void:
	_current_choices = []
	if node_id == null or node_id == "":
		_end_dialogue()
		return
	if not _nodes.has(node_id):
		push_error("DialogueManager: dialogue '%s' has no node '%s'" % [_dialogue_id, node_id])
		_end_dialogue()
		return

	_current_node = _nodes[node_id]
	_run_actions(_current_node.get("actions", []))

	var speaker: String = _current_node.get("speaker", "")
	var expression: String = _current_node.get("expression", "normal")
	var text: String = _current_node.get("text", "")
	line_shown.emit(speaker, expression, text)

	var raw_choices: Array = _current_node.get("choices", [])
	for choice in raw_choices:
		if typeof(choice) == TYPE_DICTIONARY and ConditionEvaluator.evaluate(choice.get("condition")):
			_current_choices.append(choice)

	if raw_choices.size() > 0 and _current_choices.is_empty():
		push_warning("DialogueManager: every choice was filtered out for node '%s' in '%s' — falling back to 'next'" % [node_id, _dialogue_id])

	if not _current_choices.is_empty():
		var choice_texts: Array = []
		for choice in _current_choices:
			choice_texts.append(choice.get("text", ""))
		choices_shown.emit(choice_texts)


func _run_actions(actions) -> void:
	if typeof(actions) != TYPE_ARRAY:
		return
	for action in actions:
		if typeof(action) != TYPE_DICTIONARY:
			continue
		match action.get("type", ""):
			"set_flag":
				GameState.set_flag(action.get("flag", ""), action.get("value", true))
			"add_evidence":
				GameState.add_evidence(action.get("evidence_id", ""))
			"remove_evidence":
				GameState.remove_evidence(action.get("evidence_id", ""))
			"mark_interaction_complete":
				GameState.mark_seen("custom:%s" % action.get("id", ""))
			_:
				push_warning("DialogueManager: unknown action type '%s'" % [action.get("type", "")])


func _end_dialogue() -> void:
	is_active = false
	_dialogue_id = ""
	_nodes = {}
	_current_node = {}
	_current_choices = []
	dialogue_ended.emit()
