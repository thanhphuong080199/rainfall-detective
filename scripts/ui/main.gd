extends Control
## Gameplay root. Pure orchestrator: wires the child UI scenes together via
## signals and holds zero story/game logic of its own. Also enforces that
## InvestigationView can't be interacted with while a dialogue is playing,
## so a click mid-typewriter can't kick off a second, overlapping action.

@onready var investigation_view: Control = %InvestigationView
@onready var dialogue_box: Control = %DialogueBox
@onready var evidence_inventory: Control = %EvidenceInventory
@onready var game_menu: Control = %GameMenu

var _present_target_npc_id: String = ""


func _ready() -> void:
	investigation_view.evidence_button_pressed.connect(func(): evidence_inventory.open("browse"))
	investigation_view.menu_button_pressed.connect(game_menu.open)
	investigation_view.present_requested.connect(_on_present_requested)

	evidence_inventory.evidence_chosen_for_present.connect(_on_evidence_chosen_for_present)

	game_menu.quit_to_title_requested.connect(_on_quit_to_title)

	DialogueManager.dialogue_started.connect(func(_dialogue_id): investigation_view.set_interactive(false))
	DialogueManager.dialogue_ended.connect(func(): investigation_view.set_interactive(true))


func _on_present_requested(npc_id: String) -> void:
	_present_target_npc_id = npc_id
	evidence_inventory.open("select")


func _on_evidence_chosen_for_present(evidence_id: String) -> void:
	Investigation.present(evidence_id, _present_target_npc_id)


func _on_quit_to_title() -> void:
	get_tree().change_scene_to_file("res://scenes/main/TitleScreen.tscn")
