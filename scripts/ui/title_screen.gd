extends Control
## Entry point (Main Scene). New Game starts the case content marks as the
## New Game entry (SaveManager.get_new_game_case_id() — Milestone 1.16: the
## non-canon core-loop sandbox chapter); Continue is only enabled for a save
## SaveManager fully validates as resumable — a present-but-unreadable file
## disables it and says so, safely, without ever loading part of it.
## Replacing an existing, resumable save with a New Game is confirmed first.

@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel
@onready var language_label: Label = %LanguageLabel
@onready var vi_button: Button = %ViButton
@onready var en_button: Button = %EnButton
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(func(): get_tree().quit())
	vi_button.pressed.connect(func(): LocaleManager.set_locale("vi"))
	en_button.pressed.connect(func(): LocaleManager.set_locale("en"))
	confirm_dialog.confirmed.connect(_start_new_game)
	LocaleManager.locale_changed.connect(func(_locale): _apply_labels())
	_apply_labels()
	if continue_button.disabled:
		new_game_button.grab_focus()
	else:
		continue_button.grab_focus()


func _apply_labels() -> void:
	%TitleLabel.text = tr("UI_TITLE_SCREEN_TITLE")
	%SubtitleLabel.text = tr("UI_TITLE_SCREEN_SUBTITLE")
	new_game_button.text = tr("UI_NEW_GAME")
	continue_button.text = tr("UI_CONTINUE")
	quit_button.text = tr("UI_QUIT")
	language_label.text = tr("UI_LANGUAGE_LABEL")
	var locale: String = LocaleManager.get_locale()
	vi_button.disabled = locale == "vi"
	en_button.disabled = locale == "en"
	confirm_dialog.dialog_text = tr("UI_TITLE_CONFIRM_NEW_GAME")
	confirm_dialog.get_ok_button().text = tr("UI_CORE_LOOP_CONFIRM")
	confirm_dialog.get_cancel_button().text = tr("UI_CORE_LOOP_CANCEL")
	var resumable: bool = SaveManager.has_resumable_save()
	continue_button.disabled = not resumable
	status_label.text = tr("UI_TITLE_SAVE_UNREADABLE") if SaveManager.has_save() and not resumable else ""


func _on_new_game_pressed() -> void:
	if SaveManager.has_resumable_save():
		confirm_dialog.popup_centered()
		return
	_start_new_game()


func _start_new_game() -> void:
	SaveManager.preserve_unreadable_save()
	SaveManager.new_game(SaveManager.get_new_game_case_id())
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_continue_pressed() -> void:
	if SaveManager.load_game():
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	else:
		status_label.text = tr("UI_COULD_NOT_LOAD_SAVE")
		continue_button.disabled = true
