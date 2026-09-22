extends Control
## Entry point (Main Scene). New Game starts the case content marks as the
## New Game entry (SaveManager.get_new_game_case_id() — Milestone 1.16: the
## non-canon core-loop sandbox chapter); Continue is only enabled for a save
## SaveManager fully validates as resumable — a present-but-unreadable file
## disables it and says so, safely, without ever loading part of it.
## Replacing an existing, resumable save with a New Game is confirmed first.
##
## Milestone 1.17 (docs/core-loop-sandbox.md, "Sandbox selection"): in DEBUG
## builds only, a Technical Sandbox selector lists every non-canon case whose
## JSON declares "sandbox_selection" (SaveManager.get_sandbox_entries() — no
## case id is named here). Picking one only changes WHICH case the ordinary
## New Game route starts; everything after that — confirmation over a
## resumable save, SaveManager.new_game(), the gameplay scene — is the same
## path a release build takes. With one entry or fewer it collapses. Continue
## never asks: it resumes whatever the save holds (the panel names it).
## Release builds never show the panel and always start the default.

## Whether the debug-only sandbox selector may appear. Defaults to the build
## type; tests set it before the node enters the tree to check both builds.
var sandbox_selector_enabled: bool = OS.is_debug_build()

var _selected_case_id: String = ""
var _sandbox_entries: Array[Dictionary] = []

@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel
@onready var language_label: Label = %LanguageLabel
@onready var vi_button: Button = %ViButton
@onready var en_button: Button = %EnButton
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog
@onready var sandbox_panel: VBoxContainer = %SandboxPanel
@onready var sandbox_header: Label = %SandboxHeader
@onready var sandbox_list: VBoxContainer = %SandboxList
@onready var sandbox_summary: Label = %SandboxSummary
@onready var saved_run_label: Label = %SavedRunLabel


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(func(): get_tree().quit())
	vi_button.pressed.connect(func(): LocaleManager.set_locale("vi"))
	en_button.pressed.connect(func(): LocaleManager.set_locale("en"))
	confirm_dialog.confirmed.connect(_start_new_game)
	LocaleManager.locale_changed.connect(func(_locale): _apply_labels())
	_selected_case_id = SaveManager.get_new_game_case_id()
	_build_sandbox_selector()
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
	confirm_dialog.get_ok_button().text = tr("UI_CORE_LOOP_CONFIRM")
	confirm_dialog.get_cancel_button().text = tr("UI_CORE_LOOP_CANCEL")
	var resumable: bool = SaveManager.has_resumable_save()
	continue_button.disabled = not resumable
	status_label.text = tr("UI_TITLE_SAVE_UNREADABLE") if SaveManager.has_save() and not resumable else ""
	_apply_sandbox_labels()


## Builds one toggle button per selectable sandbox (by list position, never
## by id). Shown only in debug builds with more than one choice.
func _build_sandbox_selector() -> void:
	_sandbox_entries = []
	if sandbox_selector_enabled:
		_sandbox_entries = SaveManager.get_sandbox_entries()
	UiUtil.clear_children(sandbox_list)
	sandbox_panel.visible = _sandbox_entries.size() > 1
	if not sandbox_panel.visible:
		return
	var group := ButtonGroup.new()
	for i in _sandbox_entries.size():
		var button := Button.new()
		button.name = "Sandbox_%d" % i
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var case_id: String = str(_sandbox_entries[i].get("case_id", ""))
		button.pressed.connect(func() -> void: _select_sandbox(case_id))
		sandbox_list.add_child(button)


func _select_sandbox(case_id: String) -> void:
	_selected_case_id = case_id
	_apply_sandbox_labels()


func _apply_sandbox_labels() -> void:
	var selected: Dictionary = {}
	for i in _sandbox_entries.size():
		var entry: Dictionary = _sandbox_entries[i]
		var button: Button = sandbox_list.get_node_or_null("Sandbox_%d" % i) as Button
		if button != null:
			var chosen: bool = entry.get("case_id", "") == _selected_case_id
			# The pressed style alone is too subtle to tell which one New Game
			# will start — the same ●/○ markers the final-claim choices use.
			button.text = ("● " if chosen else "○ ") + tr(str(entry.get("name", "")))
			button.set_pressed_no_signal(chosen)
		if entry.get("case_id", "") == _selected_case_id:
			selected = entry
	confirm_dialog.dialog_text = tr("UI_TITLE_CONFIRM_NEW_GAME")
	if not sandbox_panel.visible:
		return
	sandbox_header.text = tr("UI_TITLE_SANDBOX_HEADER")
	sandbox_summary.text = tr(str(selected.get("description", ""))) if not selected.is_empty() else ""
	var saved_case: String = SaveManager.get_saved_case_id()
	var saved_name: String = str(ContentDB.get_case(saved_case).get("display_name", "")) if saved_case != "" else ""
	saved_run_label.text = tr("UI_TITLE_SANDBOX_SAVED") % tr(saved_name) if saved_name != "" else ""
	saved_run_label.visible = saved_run_label.text != ""
	if not selected.is_empty():
		confirm_dialog.dialog_text = tr("UI_TITLE_CONFIRM_NEW_SANDBOX") % tr(str(selected.get("name", "")))


func _on_new_game_pressed() -> void:
	if SaveManager.has_resumable_save():
		confirm_dialog.popup_centered()
		return
	_start_new_game()


func _start_new_game() -> void:
	SaveManager.preserve_unreadable_save()
	SaveManager.new_game(_selected_case_id)
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_continue_pressed() -> void:
	if SaveManager.load_game():
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	else:
		status_label.text = tr("UI_COULD_NOT_LOAD_SAVE")
		continue_button.disabled = true
