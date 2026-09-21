extends Control
## Save / Load / New Game / Resume / Quit-to-Title overlay.

signal closed()
signal quit_to_title_requested()
## Milestone 1.16: the player confirmed "New Game" — Main.gd decides what that
## means (a core-loop chapter restarts through its runtime; any other case
## starts over), so this menu no longer calls SaveManager.new_game() itself.
signal new_game_requested()

@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var new_game_button: Button = %NewGameButton
@onready var resume_button: Button = %ResumeButton
@onready var quit_button: Button = %QuitButton
@onready var language_label: Label = %LanguageLabel
@onready var vi_button: Button = %ViButton
@onready var en_button: Button = %EnButton
@onready var status_label: Label = %StatusLabel
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	resume_button.pressed.connect(close)
	quit_button.pressed.connect(func(): quit_to_title_requested.emit())
	vi_button.pressed.connect(func(): LocaleManager.set_locale("vi"))
	en_button.pressed.connect(func(): LocaleManager.set_locale("en"))
	confirm_dialog.confirmed.connect(_on_new_game_confirmed)
	LocaleManager.locale_changed.connect(func(_locale): _apply_static_labels())
	_apply_static_labels()


## Every label here is either a static .tscn string or this menu's own
## Save/Load result — none of it comes from content, so this is the whole
## translation surface for this scene. Re-run on locale_changed since the
## toggle that fires it lives on this same screen (see docs/localization.md
## for why Control text properties don't retranslate themselves).
func _apply_static_labels() -> void:
	%TitleLabel.text = tr("UI_MENU_TITLE")
	save_button.text = tr("UI_SAVE")
	load_button.text = tr("UI_LOAD")
	new_game_button.text = tr("UI_NEW_GAME")
	resume_button.text = tr("UI_RESUME")
	quit_button.text = tr("UI_QUIT_TO_TITLE")
	language_label.text = tr("UI_LANGUAGE_LABEL")
	var current_locale: String = LocaleManager.get_locale()
	vi_button.set_pressed_no_signal(current_locale == "vi")
	en_button.set_pressed_no_signal(current_locale == "en")
	vi_button.disabled = current_locale == "vi"
	en_button.disabled = current_locale == "en"
	confirm_dialog.dialog_text = tr("UI_MENU_CONFIRM_NEW_GAME")
	confirm_dialog.get_ok_button().text = tr("UI_CORE_LOOP_CONFIRM")
	confirm_dialog.get_cancel_button().text = tr("UI_CORE_LOOP_CANCEL")


func open() -> void:
	status_label.text = ""
	load_button.disabled = not SaveManager.has_resumable_save()
	_apply_static_labels()
	visible = true
	resume_button.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _on_save_pressed() -> void:
	if SaveManager.save_game():
		status_label.text = tr("UI_SAVED")
		load_button.disabled = false
	else:
		status_label.text = tr("UI_SAVE_FAILED")


func _on_load_pressed() -> void:
	if SaveManager.load_game():
		status_label.text = tr("UI_LOADED")
		close()
	else:
		status_label.text = tr("UI_LOAD_FAILED")


## Starting over replaces the current progress, so it is confirmed first.
func _on_new_game_pressed() -> void:
	confirm_dialog.popup_centered()


func _on_new_game_confirmed() -> void:
	new_game_requested.emit()
	status_label.text = tr("UI_STARTED_NEW_GAME")
	close()


func _input(event: InputEvent) -> void:
	if visible and not confirm_dialog.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
