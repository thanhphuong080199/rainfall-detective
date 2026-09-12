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
@onready var detail_short: Label = %DetailShort
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
	close_button.text = tr("UI_CLOSE_ESC")
	present_button.text = tr("UI_PRESENT")
	%FooterHint.text = tr("UI_EVIDENCE_HINT")


func open(mode: String = "browse") -> void:
	_mode = mode
	_selected_evidence_id = ""
	title_label.text = tr("UI_SELECT_EVIDENCE_TO_PRESENT") if mode == "select" else tr("UI_EVIDENCE_TITLE")
	present_button.visible = (mode == "select")
	_refresh_grid()
	_show_details("")
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _refresh_grid() -> void:
	UiUtil.clear_children(slot_grid)
	_slots.clear()

	if GameState.evidence_inventory.is_empty():
		# Otherwise the panel is just blank, which reads as broken rather than
		# as "you haven't found anything yet" — especially in "select" mode,
		# where the player opened it expecting something to hand over.
		var empty_label := Label.new()
		empty_label.text = tr("UI_NO_EVIDENCE_COLLECTED")
		slot_grid.add_child(empty_label)
		return

	for evidence_id in GameState.evidence_inventory:
		var data: Dictionary = ContentDB.get_evidence(evidence_id)
		if data.is_empty():
			continue
		var slot: Button = EvidenceSlotScene.instantiate()
		slot_grid.add_child(slot)
		slot.setup(evidence_id, tr(data.get("name", evidence_id)), data.get("icon_color", "#888888"))
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
		detail_name.text = tr("UI_NO_EVIDENCE_SELECTED")
		detail_short.text = ""
		detail_description.text = ""
		present_button.disabled = true
		return

	detail_visual.set_color_hex(data.get("icon_color", "#888888"))
	detail_visual.set_caption(tr(data.get("name", evidence_id)))
	detail_name.text = tr(data.get("name", evidence_id))
	detail_short.text = tr(data.get("short_description", ""))
	detail_description.text = tr(data.get("detailed_description", ""))
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
