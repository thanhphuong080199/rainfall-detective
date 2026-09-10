extends Control
## Evidence inventory / "court record" screen. One reusable scene, two modes:
##   "browse" — just look through discovered evidence.
##   "select" — pick one item to hand to Investigation.present() (the Present
##              button appears; picking an item and confirming closes the
##              inventory and emits evidence_chosen_for_present).
## Only evidence currently in GameState.evidence_inventory is ever shown.

signal closed()
signal evidence_chosen_for_present(evidence_id: String)

const EvidenceSlotScene := preload("res://scenes/evidence/EvidenceSlot.tscn")

@onready var title_label: Label = %TitleLabel
@onready var slot_grid: GridContainer = %SlotGrid
@onready var detail_visual: Control = %DetailVisual
@onready var detail_name: Label = %DetailName
@onready var detail_description: Label = %DetailDescription
@onready var present_button: Button = %PresentButton
@onready var close_button: Button = %CloseButton

var _mode: String = "browse"
var _selected_evidence_id: String = ""
var _slots: Dictionary = {}


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	present_button.pressed.connect(_on_present_pressed)


func open(mode: String = "browse") -> void:
	_mode = mode
	_selected_evidence_id = ""
	title_label.text = "Select Evidence to Present" if mode == "select" else "Evidence"
	present_button.visible = (mode == "select")
	_refresh_grid()
	_show_details("")
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _refresh_grid() -> void:
	for child in slot_grid.get_children():
		child.queue_free()
	_slots.clear()

	for evidence_id in GameState.evidence_inventory:
		var data: Dictionary = ContentDB.get_evidence(evidence_id)
		if data.is_empty():
			continue
		var slot: Button = EvidenceSlotScene.instantiate()
		slot_grid.add_child(slot)
		slot.setup(evidence_id, data.get("name", evidence_id), data.get("icon_color", "#888888"))
		slot.evidence_selected.connect(_on_slot_selected)
		_slots[evidence_id] = slot


func _on_slot_selected(evidence_id: String) -> void:
	_selected_evidence_id = evidence_id
	for id in _slots:
		_slots[id].set_selected(id == evidence_id)
	_show_details(evidence_id)


func _show_details(evidence_id: String) -> void:
	var data: Dictionary = ContentDB.get_evidence(evidence_id)
	if data.is_empty():
		detail_visual.set_color(Color(0.3, 0.3, 0.3))
		detail_visual.set_caption("")
		detail_name.text = "No evidence selected"
		detail_description.text = ""
		present_button.disabled = true
		return

	detail_visual.set_color_hex(data.get("icon_color", "#888888"))
	detail_visual.set_caption(data.get("name", evidence_id))
	detail_name.text = data.get("name", evidence_id)
	detail_description.text = data.get("detailed_description", "")
	present_button.disabled = false


func _on_present_pressed() -> void:
	if _selected_evidence_id == "":
		return
	var evidence_id := _selected_evidence_id
	close()
	evidence_chosen_for_present.emit(evidence_id)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
