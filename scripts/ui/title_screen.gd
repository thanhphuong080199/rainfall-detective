extends Control
## Entry point (Main Scene). New Game always starts case_00_sandbox fresh;
## Continue is only enabled when a save file already exists on disk.

@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	%TitleLabel.text = tr("UI_TITLE_SCREEN_TITLE")
	%SubtitleLabel.text = tr("UI_TITLE_SCREEN_SUBTITLE")
	new_game_button.text = tr("UI_NEW_GAME")
	continue_button.text = tr("UI_CONTINUE")
	quit_button.text = tr("UI_QUIT")
	continue_button.disabled = not SaveManager.has_save()
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(func(): get_tree().quit())


func _on_new_game_pressed() -> void:
	SaveManager.new_game()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_continue_pressed() -> void:
	if SaveManager.load_game():
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	else:
		status_label.text = tr("UI_COULD_NOT_LOAD_SAVE")
