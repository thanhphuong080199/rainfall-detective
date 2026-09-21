extends Control
## The chapter briefing (Milestone 1.16 — see docs/core-loop-sandbox.md,
## "UI"): localized title, text and first objective, a language switch, and
## the two ways out — begin (ChapterRuntime.acknowledge_briefing(), via Main)
## or back to the main menu. Carries no deduction data at all. Shown again on
## Continue until acknowledged, because the run's phase — not this screen —
## says whether the briefing is done.

signal continue_requested()
signal menu_requested()

var _runtime: ChapterRuntime

@onready var title_label: Label = %TitleLabel
@onready var non_canon_label: Label = %NonCanonLabel
@onready var text_label: Label = %TextLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var language_label: Label = %LanguageLabel
@onready var vi_button: Button = %ViButton
@onready var en_button: Button = %EnButton
@onready var menu_button: Button = %MenuButton
@onready var continue_button: Button = %ContinueButton


func _ready() -> void:
	visible = false
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	vi_button.pressed.connect(func() -> void: LocaleManager.set_locale("vi"))
	en_button.pressed.connect(func() -> void: LocaleManager.set_locale("en"))
	LocaleManager.locale_changed.connect(func(_locale: String) -> void: _refresh_if_visible())


func setup(runtime: ChapterRuntime) -> void:
	_runtime = runtime


func open() -> void:
	visible = true
	refresh()
	continue_button.grab_focus()


func close() -> void:
	visible = false


func _refresh_if_visible() -> void:
	if visible:
		refresh()


func refresh() -> void:
	var view: Dictionary = CoreLoopPresenter.build_briefing(_runtime)
	title_label.text = view.get("title", "")
	non_canon_label.text = tr("UI_CORE_LOOP_NON_CANON") if view.get("non_canon", false) else ""
	non_canon_label.visible = non_canon_label.text != ""
	text_label.text = view.get("text", "")
	objective_label.text = tr("UI_CORE_LOOP_OBJECTIVE") % view.get("objective", "")
	language_label.text = tr("UI_LANGUAGE_LABEL")
	menu_button.text = tr("UI_CORE_LOOP_MENU")
	continue_button.text = tr("UI_CORE_LOOP_BRIEFING_CONTINUE")
	var locale: String = LocaleManager.get_locale()
	vi_button.disabled = locale == "vi"
	en_button.disabled = locale == "en"
