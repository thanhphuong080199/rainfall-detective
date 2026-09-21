class_name CoreLoopTestSupport
extends RefCounted
## Shared driving helpers for the Milestone 1.16 core-loop tests
## (core_loop_runtime_test.gd, core_loop_save_test.gd,
## core_loop_scene_test.gd) — see docs/testing.md. NOT a parallel gameplay
## API: every step goes through the same production entry points a player's
## clicks reach (Investigation's verbs, DialogueManager, ChapterRuntime), just
## without the widgets. The sandbox content's ids live HERE, in test code,
## never in scripts/.
##
## Like TestHelpers, it references no autoload by bare name (they are passed
## in), so a custom -s entry script can use it directly.

const CASE_ID := "case_sbx_archive"
const CHAPTER_ID := "sbx_chapter_01"
const B1 := "b1_badge"
const A1 := "a1_denial"
const B2 := "b2_staging"
const C1 := "c1_timeline"
## The prototype_b/prototype_a/prototype_c solutions of proto_x_archive_ledger.
const B1_PATH := ["e_door_log", "e_tram_tap", "e_route_note"]
const B1_ALTERNATE_PATH := ["e_door_log", "e_harbor_photo", "e_route_note"]
const B2_PATH := ["e_forced_window", "e_latch_guide", "e_window_latch"]
const A1_STATEMENT_INDEX := 2
const A1_EVIDENCE := "e_lost_property_sheet"
const C1_TIMELINE := {
	"tl_mara_leaves": "19:35", "tl_cardigan_taken": "19:48", "tl_window_forced": "20:08",
	"tl_shredding_pickup": "20:10", "tl_cardigan_returned": "20:14",
}
const C1_CLAIM_SUPPORT := "c_shredding_window"

var game_state: Node
var investigation: Node
var dialogue_manager: Node
var save_manager: Node
var case_manager: Node


func _init(tree: SceneTree) -> void:
	game_state = tree.get_root().get_node("GameState")
	investigation = tree.get_root().get_node("Investigation")
	dialogue_manager = tree.get_root().get_node("DialogueManager")
	save_manager = tree.get_root().get_node("SaveManager")
	case_manager = tree.get_root().get_node("CaseManager")


## A ChapterRuntime with a deterministic run id sequence and recorder clock.
## Loaded at runtime (never referenced by class name) — the -s compile-order
## trap, docs/architecture.md "Known limitations".
func new_runtime(prefix: String = "run") -> RefCounted:
	var counter: Array[int] = [0]
	var id_fn := func() -> String:
		counter[0] += 1
		return "%s-%d" % [prefix, counter[0]]
	var clock: Array[int] = [0]
	var clock_fn := func() -> int:
		clock[0] += 10
		return clock[0]
	var recorder: RefCounted = load("res://scripts/core_loop/chapter_run_recorder.gd").new(clock_fn, func() -> String: return "rec-%s" % prefix)
	return load("res://scripts/core_loop/chapter_runtime.gd").new(id_fn, recorder)


func start_new_game(runtime: RefCounted) -> void:
	save_manager.new_game(CASE_ID)
	runtime.reload_from_game_state()


func drain_dialogue() -> void:
	var guard := 0
	while dialogue_manager.is_active and guard < 50:
		dialogue_manager.advance()
		guard += 1


func go_to(location_id: String) -> void:
	if game_state.current_location == location_id:
		return
	if location_id != "sbx_archive_lobby" and game_state.current_location != "sbx_archive_lobby":
		investigation.move_to("sbx_archive_lobby")
	investigation.move_to(location_id)


func examine(location_id: String, point_id: String) -> void:
	go_to(location_id)
	investigation.examine(point_id)
	drain_dialogue()


func talk(location_id: String, npc_id: String, topic_id: String) -> void:
	go_to(location_id)
	investigation.talk(npc_id, topic_id)
	drain_dialogue()


## Required evidence for B1 through the normal investigation verbs.
func gather_b1_evidence() -> void:
	examine("sbx_archive_lobby", "transit_map")
	talk("sbx_archive_lobby", "sbx_mara", "evening")
	examine("sbx_stacks_wing", "door_terminal")


func unlock_a1() -> void:
	talk("sbx_stacks_wing", "sbx_oren", "badge")
	examine("sbx_archive_lobby", "front_desk_log")


func gather_b2_evidence() -> void:
	examine("sbx_stacks_wing", "forced_window")
	examine("sbx_stacks_wing", "window_latch")
	examine("sbx_maintenance_office", "repair_shelf")


func fill_b(runtime: RefCounted, unit_id: String, path: Array) -> void:
	for evidence_id in path:
		runtime.perform(unit_id, "select_evidence", [evidence_id])


func clear_b(runtime: RefCounted, unit_id: String) -> void:
	var unit: RefCounted = runtime.get_unit(unit_id)
	for evidence_id in unit.controller.get_selected_evidence_ids():
		runtime.perform(unit_id, "remove_evidence", [evidence_id])


func solve_b(runtime: RefCounted, unit_id: String, path: Array) -> Dictionary:
	runtime.open_unit(unit_id)
	clear_b(runtime, unit_id)
	fill_b(runtime, unit_id, path)
	var result: Dictionary = runtime.perform(unit_id, "commit_theory")
	runtime.dismiss_feedback(unit_id)
	runtime.close_unit()
	return result


func solve_a(runtime: RefCounted) -> Dictionary:
	runtime.open_unit(A1)
	runtime.perform(A1, "select_statement", [A1_STATEMENT_INDEX])
	runtime.perform(A1, "select_evidence", [A1_EVIDENCE])
	var result: Dictionary = runtime.perform(A1, "present_evidence")
	runtime.dismiss_feedback(A1)
	runtime.close_unit()
	return result


func place_timeline(runtime: RefCounted, placements: Dictionary) -> void:
	for event_id in placements:
		runtime.perform(C1, "place_event", [event_id, placements[event_id]])


func solve_timeline(runtime: RefCounted) -> Dictionary:
	runtime.open_unit(C1)
	place_timeline(runtime, C1_TIMELINE)
	var result: Dictionary = runtime.perform(C1, "submit_timeline")
	runtime.dismiss_feedback(C1)
	return result


func solve_claim(runtime: RefCounted) -> Dictionary:
	runtime.open_unit(C1)
	runtime.perform(C1, "select_claim_answer", [true])
	runtime.perform(C1, "select_claim_justification", [C1_CLAIM_SUPPORT])
	var result: Dictionary = runtime.perform(C1, "submit_claim")
	runtime.dismiss_feedback(C1)
	return result


## Drives a fresh run all the way to `stop_after` ("briefing", "b1", "a1",
## "b2", "timeline", "claim") through the player path.
func play_until(runtime: RefCounted, stop_after: String) -> void:
	start_new_game(runtime)
	if stop_after == "new":
		return
	runtime.acknowledge_briefing()
	if stop_after == "briefing":
		return
	gather_b1_evidence()
	solve_b(runtime, B1, B1_PATH)
	if stop_after == "b1":
		return
	unlock_a1()
	solve_a(runtime)
	if stop_after == "a1":
		return
	gather_b2_evidence()
	solve_b(runtime, B2, B2_PATH)
	if stop_after == "b2":
		return
	solve_timeline(runtime)
	if stop_after == "timeline":
		return
	solve_claim(runtime)


func event_types(runtime: RefCounted) -> Array[String]:
	var types: Array[String] = []
	for event in runtime.get_recorder().get_events():
		types.append(str(event.get("type", "")))
	return types
