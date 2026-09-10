extends Button
## One clickable evidence entry in the EvidenceInventory grid: a colored
## placeholder icon with the evidence name as its caption.

signal evidence_selected(evidence_id: String)

var evidence_id: String = ""

@onready var visual: Control = $Visual


func setup(id: String, display_name: String, icon_color: String) -> void:
	evidence_id = id
	visual.set_color_hex(icon_color)
	visual.set_caption(display_name)


func set_selected(is_selected: bool) -> void:
	set_pressed_no_signal(is_selected)


func _pressed() -> void:
	evidence_selected.emit(evidence_id)
