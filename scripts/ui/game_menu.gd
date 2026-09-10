extends Control
## Save / Load / New Game / Resume / Quit-to-Title overlay.

signal closed()
signal quit_to_title_requested()

@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var new_game_button: Button = %NewGameButton
@onready var resume_button: Button = %ResumeButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	resume_button.pressed.connect(close)
	quit_button.pressed.connect(func(): quit_to_title_requested.emit())


func open() -> void:
	status_label.text = ""
	load_button.disabled = not SaveManager.has_save()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _on_save_pressed() -> void:
	if SaveManager.save_game():
		status_label.text = "Saved."
		load_button.disabled = false
	else:
		status_label.text = "Save failed — see console."


func _on_load_pressed() -> void:
	if SaveManager.load_game():
		status_label.text = "Loaded."
		close()
	else:
		status_label.text = "Load failed — see console."


func _on_new_game_pressed() -> void:
	SaveManager.new_game()
	status_label.text = "Started a new game."
	close()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
