extends Control
## The chapter's narrative Result screen (Milestone 1.16 — see
## docs/core-loop-sandbox.md, "UI"). Tells what was established, in order,
## with partner help mentioned in words where it happened — and nothing else:
## no score, rank, time, attempt count or Independent/Guided/Assisted badge
## (1.15B locks that; the run help result stays in the save and the
## recording). Offers a restart (a genuinely fresh run, confirmed first) or
## the main menu, plus the local evaluation-log export, whose failure is only
## reported.

signal restart_requested()
signal menu_requested()

var _runtime: ChapterRuntime

@onready var title_label: Label = %TitleLabel
@onready var non_canon_label: Label = %NonCanonLabel
@onready var text_label: Label = %TextLabel
@onready var findings_list: VBoxContainer = %FindingsList
@onready var status_label: Label = %StatusLabel
@onready var export_button: Button = %ExportButton
@onready var menu_button: Button = %MenuButton
@onready var restart_button: Button = %RestartButton
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	export_button.pressed.connect(_on_export_pressed)
	confirm_dialog.confirmed.connect(func() -> void: restart_requested.emit())
	LocaleManager.locale_changed.connect(func(_locale: String) -> void: _refresh_if_visible())


func setup(runtime: ChapterRuntime) -> void:
	_runtime = runtime


func open() -> void:
	visible = true
	status_label.text = ""
	refresh()
	menu_button.grab_focus()


func close() -> void:
	visible = false


func _refresh_if_visible() -> void:
	if visible:
		refresh()


func refresh() -> void:
	var view: Dictionary = CoreLoopPresenter.build_result(_runtime)
	title_label.text = view.get("title", "")
	non_canon_label.text = tr("UI_CORE_LOOP_NON_CANON") if view.get("non_canon", false) else ""
	non_canon_label.visible = non_canon_label.text != ""
	text_label.text = view.get("text", "")
	UiUtil.clear_children(findings_list)
	for line in view.get("findings", []):
		var label := Label.new()
		label.text = "• %s" % line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		findings_list.add_child(label)
	export_button.text = tr("UI_CORE_LOOP_EXPORT")
	menu_button.text = tr("UI_CORE_LOOP_MENU")
	restart_button.text = tr("UI_CORE_LOOP_RESTART")
	confirm_dialog.dialog_text = tr("UI_CORE_LOOP_CONFIRM_RESTART")
	confirm_dialog.get_ok_button().text = tr("UI_CORE_LOOP_CONFIRM")
	confirm_dialog.get_cancel_button().text = tr("UI_CORE_LOOP_CANCEL")


func _on_restart_pressed() -> void:
	confirm_dialog.popup_centered()


func _on_export_pressed() -> void:
	var result: Dictionary = _runtime.export_recording()
	status_label.text = tr("UI_CORE_LOOP_EXPORTED") % result.get("path", "") if result.get("success", false) else tr("UI_CORE_LOOP_EXPORT_FAILED")
