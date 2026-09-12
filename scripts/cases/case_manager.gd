extends Node
## Autoload: CaseManager
##
## Orchestration layer for Case/Chapter progression (Milestone 1.6). Sits one
## level above Investigation/EventManager, the way docs/case-system.md's
## diagram describes: Case -> Chapter -> (content + Events) ->
## Conditions/Effects -> GameState. This script owns NO persisted state of
## its own — "current case", "current chapter", and "which chapters/cases
## have completed" all live in GameState (the `case_id`/`current_chapter`
## variables, and the existing seen_interactions "has this happened" set a
## "once" event's triggered state already uses) — so save/load round-trips
## case progression for free, with zero save-format changes.
##
## A Chapter's completion is deliberately modelled as an ordinary Event (see
## data/events/*.json / docs/event-system.md), not as a second condition-
## evaluation loop: CaseManager only listens to EventManager.event_triggered
## and checks whether the event that just fired is the CURRENT chapter's
## declared completion_event. See docs/case-system.md, "Why chapter
## completion is an Event, not a second evaluator", for why the obvious
## alternative (a Chapter carrying its own completion_conditions, evaluated
## by CaseManager listening to GameState directly) was rejected: it would
## duplicate EventManager's reentrant fixed-point evaluation loop for no new
## capability.
##
## A case with no "chapters"/"starting_chapter" fields (e.g. the Milestone
## 0-1.5 sandbox, case_00_sandbox) is a "flat" case: start_case() still
## works, current_chapter simply stays "", and every method below is a safe
## no-op — chapters are opt-in per case, not a required structure.

signal chapter_activated(chapter_id: String)
signal chapter_completed(chapter_id: String)
signal case_completed(case_id: String)


func _ready() -> void:
	EventManager.event_triggered.connect(_on_event_triggered)


## Canonical entry point to start (or restart) any case, chapter-based or
## flat — this is what SaveManager.new_game() and the debug panel's "reset"
## call, so a future real case uses the exact same path the Test Case does
## (see docs/case-system.md, "Case initialization" — nothing here or in
## SaveManager hardcodes "test_case").
func start_case(case_id: String) -> void:
	GameState.start_new_game(case_id)
	var case_data: Dictionary = ContentDB.get_case(case_id)
	var starting_chapter: String = case_data.get("starting_chapter", "")
	if starting_chapter == "":
		return  # Flat case (no chapter structure) — nothing further to do.
	_activate_chapter(starting_chapter)


func get_current_case_id() -> String:
	return GameState.get_var("case_id", "")


func get_current_chapter_id() -> String:
	return GameState.get_var("current_chapter", "")


func is_chapter_complete(chapter_id: String) -> bool:
	return GameState.has_seen(_chapter_complete_key(chapter_id))


func is_case_complete(case_id: String) -> bool:
	return GameState.has_seen(_case_complete_key(case_id))


## Every chapter id of `case_id` that has completed, in the case's own
## declared order — for debug tooling ("completed chapters" listing).
func get_completed_chapters(case_id: String) -> Array[String]:
	var completed: Array[String] = []
	for chapter_id in ContentDB.get_case(case_id).get("chapters", []):
		if is_chapter_complete(String(chapter_id)):
			completed.append(String(chapter_id))
	return completed


## Debug-only: why (if at all) `chapter_id` has not completed yet. Delegates
## entirely to EventManager.explain_event() when the chapter has a
## completion_event (see class doc) — CaseManager has no condition-
## evaluation logic of its own to duplicate. Returns {"has_completion_event":
## bool, "triggered": bool, "conditions_satisfied": bool, "conditions":
## Array[Dictionary]}. See DebugPanel, the only caller.
func explain_chapter_completion(chapter_id: String) -> Dictionary:
	var chapter: Dictionary = ContentDB.get_chapter(chapter_id)
	var completion_event: String = chapter.get("completion_event", "")
	if completion_event == "":
		return {"has_completion_event": false, "triggered": is_chapter_complete(chapter_id), "conditions_satisfied": false, "conditions": []}
	var info: Dictionary = EventManager.explain_event(completion_event)
	info["has_completion_event"] = true
	return info


# ---------------------------------------------------------------------------
# Developer tools — mirror DebugPanel's existing "bypass conditions, reuse
# the real pipeline" philosophy (see docs/architecture.md, "Developer tools").

## Teleports current_chapter straight to `chapter_id` and runs its
## entry_effects, bypassing whatever the previous chapter's completion would
## normally require — a teleport for testing, exactly like DebugPanel's
## location jump bypasses a destination's condition. Returns false for an
## unknown chapter id.
func jump_to_chapter(chapter_id: String) -> bool:
	if ContentDB.get_chapter(chapter_id).is_empty():
		return false
	_activate_chapter(chapter_id)
	return true


## Forces the current chapter's completion_event through
## EventManager.force_trigger() — the exact same pipeline a real completion
## uses (this script's own _on_event_triggered() handles the rest from
## there), per the project's rule that a developer shortcut reuses normal
## progression APIs instead of duplicating them. Returns false when there is
## no current chapter, or it has no completion_event to force.
func force_complete_current_chapter() -> bool:
	var chapter: Dictionary = ContentDB.get_chapter(get_current_chapter_id())
	var completion_event: String = chapter.get("completion_event", "")
	if completion_event == "":
		return false
	return EventManager.force_trigger(completion_event)


## Restarts whatever case is currently active from scratch (same as starting
## it fresh) — the primary developer/testing affordance this milestone asks
## for (see docs/case-system.md, "Case reset"). A no-op if no case is active.
func reset_case() -> void:
	var case_id: String = get_current_case_id()
	if case_id != "":
		start_case(case_id)


# ---------------------------------------------------------------------------

func _on_event_triggered(event_id: String) -> void:
	var chapter_id: String = get_current_chapter_id()
	if chapter_id == "":
		return
	var chapter: Dictionary = ContentDB.get_chapter(chapter_id)
	if chapter.get("completion_event", "") != event_id:
		return
	_complete_chapter(chapter_id, chapter)


func _complete_chapter(chapter_id: String, chapter: Dictionary) -> void:
	if is_chapter_complete(chapter_id):
		return  # Defensive: EventManager's own "once" gating should already prevent a second call.
	GameState.mark_seen(_chapter_complete_key(chapter_id))
	print("[CaseManager] Chapter completed: %s" % chapter_id)
	chapter_completed.emit(chapter_id)

	var next_chapter: String = chapter.get("next_chapter", "")
	if next_chapter == "":
		_complete_case(get_current_case_id())
	else:
		_activate_chapter(next_chapter)


func _complete_case(case_id: String) -> void:
	if case_id == "" or is_case_complete(case_id):
		return
	GameState.mark_seen(_case_complete_key(case_id))
	print("[CaseManager] Case completed: %s" % case_id)
	case_completed.emit(case_id)


func _activate_chapter(chapter_id: String) -> void:
	GameState.set_var("current_chapter", chapter_id)
	print("[CaseManager] Chapter activated: %s" % chapter_id)
	var chapter: Dictionary = ContentDB.get_chapter(chapter_id)
	EffectRunner.run(chapter.get("entry_effects", []))
	chapter_activated.emit(chapter_id)


func _chapter_complete_key(chapter_id: String) -> String:
	return "chapter_complete:%s" % chapter_id


func _case_complete_key(case_id: String) -> String:
	return "case_complete:%s" % case_id
