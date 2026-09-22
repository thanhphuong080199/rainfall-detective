extends Control
## The investigation HUD of a core-loop chapter (Milestone 1.16 — see
## docs/core-loop-sandbox.md, "UI"): the current objective, the one mechanic
## the chapter offers right now (or a safe, spoiler-free "keep investigating"
## line while it is still locked), and short notices — new evidence filed,
## a refused action, a checkpoint that could not be written. Never says WHAT
## is missing. The root ignores the mouse so the investigation underneath
## keeps receiving clicks; only the panel itself is interactive.

signal unit_requested(unit_id: String)
signal menu_requested()

var _runtime: ChapterRuntime
var _is_interactive: bool = true
## The current notice as [translation key, argument key or ""], so it
## re-renders in the new language after a locale switch.
var _notice: Array[String] = ["", ""]

@onready var panel: PanelContainer = %Panel
@onready var objective_label: Label = %ObjectiveLabel
@onready var notice_label: Label = %NoticeLabel
@onready var unit_hint_label: Label = %UnitHintLabel
@onready var open_unit_button: Button = %OpenUnitButton
@onready var menu_button: Button = %MenuButton


func _ready() -> void:
	visible = false
	open_unit_button.pressed.connect(func() -> void: unit_requested.emit(_runtime.get_current_unit_id()))
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	GameState.evidence_added.connect(_on_evidence_added)
	LocaleManager.locale_changed.connect(func(_locale: String) -> void: _render_notice(); refresh())


func setup(runtime: ChapterRuntime) -> void:
	_runtime = runtime
	_runtime.state_changed.connect(refresh)
	_runtime.checkpoint_failed.connect(func() -> void: show_notice("UI_CORE_LOOP_SAVE_FAILED"))
	GameState.flag_changed.connect(func(_flag: String, _value: bool) -> void: refresh())
	GameState.interaction_seen.connect(func(_key: String) -> void: refresh())


## Mirrors InvestigationView.set_interactive(): no mechanic can be opened
## while a dialogue is on screen — and (Milestone 1.17 visual QA) the HUD is
## hidden meanwhile: the dialogue box's translucent panel covers the same
## screen area, so both texts were drawn on top of each other. The pending
## notice (e.g. the evidence just filed) shows again when the dialogue ends.
func set_interactive(is_interactive: bool) -> void:
	_is_interactive = is_interactive
	refresh()


## `key` is a translation key; `argument_key`, when given, is translated and
## substituted into it (e.g. the name of the evidence just filed).
func show_notice(key: String, argument_key: String = "") -> void:
	_notice = [key, argument_key]
	_render_notice()


func _render_notice() -> void:
	var text: String = ""
	if _notice[0] != "":
		text = tr(_notice[0]) % tr(_notice[1]) if _notice[1] != "" else tr(_notice[0])
	notice_label.text = text
	notice_label.visible = text != ""


func refresh() -> void:
	if _runtime == null:
		return
	var view: Dictionary = CoreLoopPresenter.build_hud(_runtime)
	visible = view.get("visible", false) and not _runtime.is_briefing() and not _runtime.is_completed() and _is_interactive
	if not visible:
		return
	var error: String = view.get("error", "")
	objective_label.text = error if error != "" else tr("UI_CORE_LOOP_OBJECTIVE") % view.get("objective", "")
	menu_button.visible = error != ""
	menu_button.text = tr("UI_CORE_LOOP_MENU")
	var available: bool = view.get("unit_available", false)
	open_unit_button.visible = error == "" and available
	open_unit_button.text = tr("UI_CORE_LOOP_OPEN_UNIT") % view.get("unit_title", "")
	open_unit_button.disabled = not _is_interactive
	unit_hint_label.text = view.get("unit_hint", "") if error == "" and not available else ""
	notice_label.visible = notice_label.text != ""


func _on_evidence_added(evidence_id: String) -> void:
	if _runtime == null or not _runtime.is_active():
		return
	show_notice("UI_CORE_LOOP_NEW_EVIDENCE", str(ContentDB.get_evidence(evidence_id).get("name", "")))
