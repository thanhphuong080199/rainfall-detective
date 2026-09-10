extends Control
## Reusable placeholder "art": a solid color swatch with a caption label on
## top. Stands in for portraits, location backgrounds, and evidence icons
## until real art exists. Swapping in real art later means changing this one
## scene (e.g. to a TextureRect) instead of every place that shows a color.

@onready var swatch: ColorRect = $Swatch
@onready var caption_label: Label = $CaptionLabel


func set_color(color: Color) -> void:
	swatch.color = color


func set_color_hex(hex_color: String) -> void:
	if hex_color == "":
		return
	set_color(Color(hex_color))


func set_caption(text: String) -> void:
	caption_label.text = text
