extends Control
## Gameplay root. Pure orchestrator: wires the child UI scenes together via
## signals and holds zero story/game logic of its own. Also enforces that
## InvestigationView can't be interacted with while a dialogue is playing,
## so a click mid-typewriter can't kick off a second, overlapping action.
##
## Milestone 1.16 (docs/core-loop-sandbox.md): also owns the ONE
## ChapterRuntime of this gameplay scene (not an autoload — its durable truth
## lives in GameState.chapter_run, so the scene can come and go) and routes
## between the core-loop screens from the runtime's state: the briefing while
## the run is in its briefing phase, the mechanic that was open when the game
## was saved, the Result screen once the chapter is complete, otherwise the
## investigation with its HUD. No screen decides progression; each one asks
## the runtime, and this script only chooses what is visible. For a case
## without a core-loop chapter the runtime stays inactive and everything
## below behaves exactly as before.

@onready var investigation_view: Control = %InvestigationView
@onready var core_loop_hud: Control = %CoreLoopHud
@onready var dialogue_box: Control = %DialogueBox
@onready var evidence_inventory: Control = %EvidenceInventory
@onready var case_file: Control = %CaseFile
@onready var mechanic_screen: Control = %MechanicScreen
@onready var briefing_screen: Control = %BriefingScreen
@onready var result_screen: Control = %ResultScreen
@onready var game_menu: Control = %GameMenu

var _present_target_npc_id: String = ""
var _runtime: ChapterRuntime


func _ready() -> void:
	investigation_view.evidence_button_pressed.connect(_on_evidence_button_pressed)
	investigation_view.menu_button_pressed.connect(game_menu.open)
	investigation_view.present_requested.connect(_on_present_requested)

	evidence_inventory.evidence_chosen_for_present.connect(_on_evidence_chosen_for_present)

	game_menu.quit_to_title_requested.connect(_on_quit_to_title)
	game_menu.new_game_requested.connect(_on_new_game_requested)

	DialogueManager.dialogue_started.connect(func(_dialogue_id): _set_investigation_interactive(false))
	DialogueManager.dialogue_ended.connect(func(): _set_investigation_interactive(true))

	_runtime = ChapterRuntime.new()
	for screen in [core_loop_hud, case_file, mechanic_screen, briefing_screen, result_screen]:
		screen.setup(_runtime)
	_runtime.run_replaced.connect(_show_current_screen)
	_runtime.chapter_completed.connect(_on_chapter_completed)
	core_loop_hud.unit_requested.connect(_on_unit_requested)
	core_loop_hud.menu_requested.connect(_on_quit_to_title)
	case_file.unit_requested.connect(_on_unit_requested)
	case_file.closed.connect(_focus_investigation)
	mechanic_screen.closed.connect(_show_current_screen)
	briefing_screen.continue_requested.connect(_on_briefing_continue)
	briefing_screen.menu_requested.connect(_on_quit_to_title)
	result_screen.restart_requested.connect(func() -> void: _runtime.restart_chapter())
	result_screen.menu_requested.connect(_on_quit_to_title)
	_runtime.reload_from_game_state()


func _exit_tree() -> void:
	if _runtime != null:
		_runtime.flush("scene_exit")
		_runtime.detach()


## Closing the window is a safe quit too (1.15B §13.2 "on safe quit").
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _runtime != null:
		_runtime.flush("quit")


## The runtime this scene owns — read-only access for tests and tooling.
func get_runtime() -> ChapterRuntime:
	return _runtime


func _set_investigation_interactive(is_interactive: bool) -> void:
	investigation_view.set_interactive(is_interactive)
	core_loop_hud.set_interactive(is_interactive)


## Picks the one screen the run's durable state calls for. Called whenever the
## run is (re)built — New Game, Continue, Load, Restart — and whenever a
## mechanic closes.
func _show_current_screen() -> void:
	var active: bool = _runtime.is_active()
	investigation_view.set_evidence_button_label_key("UI_CORE_LOOP_CASE_FILE_BUTTON" if active else "UI_EVIDENCE_BUTTON")
	briefing_screen.close()
	result_screen.close()
	if not active:
		case_file.close()
		mechanic_screen.visible = false
		core_loop_hud.refresh()
		return
	core_loop_hud.refresh()
	if _runtime.has_error():
		mechanic_screen.visible = false
		return
	if _runtime.is_briefing():
		case_file.close()
		briefing_screen.open()
		return
	if _runtime.is_completed():
		case_file.close()
		mechanic_screen.visible = false
		result_screen.open()
		return
	var open_unit: String = _runtime.get_open_unit_id()
	if open_unit != "" and open_unit == _runtime.get_current_unit_id():
		if mechanic_screen.get_unit_id() != open_unit:
			mechanic_screen.open(open_unit)
		return
	_focus_investigation()


## The final commit completes the chapter while its mechanic screen is still
## showing the verdict's feedback — the Result screen waits for that screen's
## Continue (mechanic_screen.closed), so the explanation is never skipped.
func _on_chapter_completed() -> void:
	if not mechanic_screen.visible:
		_show_current_screen()


func _on_briefing_continue() -> void:
	_runtime.acknowledge_briefing()
	_show_current_screen()


func _on_unit_requested(unit_id: String) -> void:
	var result: Dictionary = _runtime.open_unit(unit_id)
	if result.get("ok", false) != true:
		core_loop_hud.show_notice(CoreLoopPresenter.refusal_key(str(result.get("reason", ""))))
		return
	case_file.close()
	mechanic_screen.open(unit_id)


func _on_evidence_button_pressed() -> void:
	if _runtime.is_active():
		case_file.open()
	else:
		evidence_inventory.open("browse")


func _focus_investigation() -> void:
	investigation_view.grab_default_focus()


func _on_present_requested(npc_id: String) -> void:
	_present_target_npc_id = npc_id
	evidence_inventory.open("select")


func _on_evidence_chosen_for_present(evidence_id: String) -> void:
	Investigation.present(evidence_id, _present_target_npc_id)


## A core-loop chapter restarts through the runtime (so the outgoing run is
## recorded as restarted/abandoned); any other case simply starts over.
func _on_new_game_requested() -> void:
	if _runtime.is_active():
		_runtime.restart_chapter()
		return
	var case_id: String = CaseManager.get_current_case_id()
	SaveManager.new_game(case_id if case_id != "" else SaveManager.get_new_game_case_id())


func _on_quit_to_title() -> void:
	_runtime.flush("quit_to_title")
	get_tree().change_scene_to_file("res://scenes/main/TitleScreen.tscn")
