extends SceneTree
## Milestone 1.16 — CoreLoopValidator negative fixtures (see
## docs/core-loop-sandbox.md, "Validation", and docs/testing.md). The real
## sandbox chapter must validate clean; each mutation below breaks exactly one
## rule of the chapter-run contract and must be reported as an ERROR — and a
## broken chapter injected into ContentDB must surface through the same
## ContentValidator report validate_content.gd turns into a non-zero exit.
## Milestone 1.17 adds the second sandbox (it must validate clean too, with
## no warnings) and one fixture per multi-chapter rule: sandbox selection
## metadata, documented alternate paths, acquisition producers that arrive
## too late, unreachable/debug-only/cross-chapter offer dependencies,
## cross-chapter completion and consequence ids, duplicate B targets, a
## deduction-case mismatch, and the two new warnings.
## Needs ContentDB (autoload) — validators are load()ed at runtime, never
## referenced by class name (docs/architecture.md, "Known limitations").
## FAST and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_validation_test.gd

const CHAPTER_ID := "sbx_chapter_01"
const CHAPTER_2 := "sby_chapter_01"

var content_db: Node
var validator: Variant
var content_validator: Variant
var base_producers: Dictionary = {}
var real_chapter: Dictionary = {}
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	content_db = get_root().get_node("ContentDB")
	validator = load("res://scripts/core_loop/core_loop_validator.gd")
	content_validator = load("res://scripts/core/content_validator.gd")
	var flags: Dictionary = {}
	var evidence: Dictionary = {}
	var interactions: Dictionary = {}
	content_validator._collect_effect_targets_everywhere(flags, evidence, interactions, false)
	base_producers = {"flags": flags, "evidence": evidence, "interactions": interactions}
	real_chapter = content_db.get_chapter(CHAPTER_ID).duplicate(true)

	print("=== Core loop validation — negative fixtures ===")
	_test_real_chapter_is_clean()
	_test_reference_errors()
	_test_route_errors()
	_test_resolution_path_errors()
	_test_dependency_cycle()
	_test_completion_errors()
	_test_markers_and_debug_routes()
	_test_evidence_alternatives()
	_test_errors_reach_content_validator()
	_test_single_new_game_entry()
	_test_second_chapter_is_clean()
	_test_sandbox_selection_rules()
	_test_documented_path_rules()
	_test_late_acquisition_producer()
	_test_unreachable_and_cross_chapter_offers()
	_test_cross_chapter_completion_and_ids()
	_test_duplicate_b_target_and_case_mismatch()
	_test_new_warnings()
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _errors_for(chapter: Dictionary, chapter_id: String = CHAPTER_ID, producers: Dictionary = base_producers) -> Array[String]:
	var errors: Array[String] = []
	validator.validate_chapter(chapter_id, chapter, producers, errors)
	return errors


## Applies `mutate` to a copy of the real chapter and asserts one reported
## error contains `expected`.
func _expect(label: String, mutate: Callable, expected: String, producers: Dictionary = base_producers) -> void:
	var chapter: Dictionary = real_chapter.duplicate(true)
	mutate.call(chapter["core_loop"])
	var errors: Array[String] = _errors_for(chapter, CHAPTER_ID, producers)
	_check(errors.any(func(message: String) -> bool: return message.contains(expected)), "%s: expected an error containing \"%s\", got %s" % [label, expected, errors])


func _unit(loop: Dictionary, unit_id: String) -> Dictionary:
	for unit in loop["units"]:
		if unit["id"] == unit_id:
			return unit
	return {}


# ---------------------------------------------------------------------------

func _test_real_chapter_is_clean() -> void:
	var errors: Array[String] = _errors_for(real_chapter)
	_check(errors.is_empty(), "the real sandbox chapter validates clean: %s" % [errors])


func _test_reference_errors() -> void:
	_expect("unknown deduction case", func(loop: Dictionary) -> void: loop["deduction_case"] = "proto_nope", "is not a known deduction case")
	_expect("unknown inventory evidence link", func(loop: Dictionary) -> void: loop["evidence_links"]["sbx_nope"] = "e_door_log", "references unknown evidence")
	_expect("unknown deduction evidence link", func(loop: Dictionary) -> void: loop["evidence_links"]["sbx_door_log"] = "e_nope", "is not evidence of deduction case")
	_expect("two links to one target", func(loop: Dictionary) -> void: loop["evidence_links"]["sbx_route_note"] = "e_door_log", "maps both")
	_expect("debug-only mechanic", func(loop: Dictionary) -> void: _unit(loop, "b1_badge")["mechanic"] = "deduction_lab", "is not a production mechanic")
	_expect("unknown B round", func(loop: Dictionary) -> void: _unit(loop, "b1_badge")["round"] = "round_9", "is not a prototype_b round")
	_expect("unknown A round", func(loop: Dictionary) -> void: _unit(loop, "a1_denial")["rounds"] = ["round_9"], "is unknown or repeated")
	_expect("unit without a resolved consequence", func(loop: Dictionary) -> void: (_unit(loop, "b2_staging")["consequences"] as Dictionary).erase("resolved"), 'must declare a "resolved" consequence')
	_expect("consequence for an impossible outcome", func(loop: Dictionary) -> void: _unit(loop, "b1_badge")["consequences"]["timeline_accepted"] = {"id": "x", "effects": []}, "never produces")
	_expect("duplicate consequence id", func(loop: Dictionary) -> void: _unit(loop, "b2_staging")["consequences"]["resolved"]["id"] = "sbx_b1_resolved", "duplicate id")
	_expect("phase with an unknown unit", func(loop: Dictionary) -> void: loop["phases"][1]["unit"] = "zz", "references unknown or invalid unit")


func _test_route_errors() -> void:
	_expect("briefing not first", func(loop: Dictionary) -> void: loop["phases"].push_back(loop["phases"].pop_front()), "briefing but not the first phase")
	_expect("final claim before the timeline", func(loop: Dictionary) -> void:
		var phases: Array = loop["phases"]
		var timeline: Dictionary = phases[4]
		phases[4] = phases[5]
		phases[5] = timeline, "can never come before the timeline")
	_expect("unit never fully resolved", func(loop: Dictionary) -> void: loop["phases"].pop_back(), "never fully resolved")
	_expect("unit phases not contiguous", func(loop: Dictionary) -> void:
		loop["phases"].insert(5, {"id": "detour", "unit": "b1_badge", "completes_on": "resolved", "objective": "CL_SBX_OBJECTIVE_TIMELINE"}), "contiguous")


func _test_resolution_path_errors() -> void:
	_expect("offered without the required evidence", func(loop: Dictionary) -> void:
		_unit(loop, "b1_badge")["offer_condition"] = {"all": [{"has_evidence": "sbx_route_note"}, {"has_evidence": "sbx_tram_tap"}]}, "covers no accepted proof path")
	_expect("an any-branch that leaves the unit unsolvable", func(loop: Dictionary) -> void:
		_unit(loop, "b2_staging")["offer_condition"] = {"any": [{"all": [{"has_evidence": "sbx_forced_window"}, {"has_evidence": "sbx_latch_guide"}, {"has_evidence": "sbx_window_latch"}]}, {"has_evidence": "sbx_forced_window"}]}, "covers no accepted proof path")
	_expect("A offered without its refuting evidence", func(loop: Dictionary) -> void:
		_unit(loop, "a1_denial")["offer_condition"] = {"interaction_complete": "sbx_oren_pressed"}, "covers no accepted proof path")
	var no_latch: Dictionary = base_producers.duplicate(true)
	(no_latch["evidence"] as Dictionary).erase("sbx_window_latch")
	_expect("required evidence nothing grants", func(_loop: Dictionary) -> void: pass, "the player can acquire", no_latch)
	_expect("required evidence never linked", func(loop: Dictionary) -> void: (loop["evidence_links"] as Dictionary).erase("sbx_lost_property_sheet"), "the player can acquire")


func _test_dependency_cycle() -> void:
	_expect("offered only by its own consequence", func(loop: Dictionary) -> void:
		_unit(loop, "a1_denial")["offer_condition"] = {"all": [{"flag": "sbx_window_inspection_unlocked"}, {"has_evidence": "sbx_lost_property_sheet"}]}, "dependency cycle")
	_expect("offered only by a later consequence", func(loop: Dictionary) -> void:
		_unit(loop, "b1_badge")["offer_condition"] = {"all": [{"flag": "sbx_timeline_unlocked"}, {"has_evidence": "sbx_door_log"}, {"has_evidence": "sbx_route_note"}, {"has_evidence": "sbx_tram_tap"}]}, "dependency cycle")


func _test_completion_errors() -> void:
	_expect("final consequence never completes the chapter", func(loop: Dictionary) -> void:
		_unit(loop, "c1_timeline")["consequences"]["resolved"]["effects"] = [], "the chapter can never complete")
	_expect("chapter completes before the final phase", func(loop: Dictionary) -> void:
		_unit(loop, "b1_badge")["consequences"]["resolved"]["effects"].append({"type": "set_flag", "flag": "sbx_final_claim_accepted", "value": true}), "before the final phase")
	var chapter: Dictionary = real_chapter.duplicate(true)
	chapter["completion_event"] = ""
	_check(_errors_for(chapter).any(func(message: String) -> bool: return message.contains("needs a chapter completion_event")), "a core-loop chapter without a completion_event is rejected")


func _test_markers_and_debug_routes() -> void:
	_expect("canon chapter over a non-canon deduction case", func(loop: Dictionary) -> void: loop["canon"] = true, "sandbox content must declare")
	_expect("missing canon marker", func(loop: Dictionary) -> void: loop.erase("canon"), 'must declare "canon"')
	_expect("debug scene referenced by content", func(loop: Dictionary) -> void: loop["briefing"]["text"] = "res://scenes/debug/DeductionLab.tscn", "may not name scenes or scripts")
	var orphan: Dictionary = real_chapter.duplicate(true)
	_check(_errors_for(orphan, "sbx_chapter_orphan").any(func(message: String) -> bool: return message.contains("must belong to exactly one case")), "a core-loop chapter no case lists is rejected")


func _test_evidence_alternatives() -> void:
	var alternatives: Array = validator.evidence_alternatives({"all": [{"has_evidence": "a"}, {"any": [{"has_evidence": "b"}, {"has_evidence": "c"}]}, {"flag": "f"}]})
	_check(alternatives.size() == 2 and alternatives[0].has("a") and alternatives[0].has("b") and alternatives[1].has("c"), "all/any expand into guaranteed evidence sets: %s" % [alternatives])
	_check(validator.evidence_alternatives({"not": {"has_evidence": "a"}}) == [{}], "'not' guarantees nothing")
	var wide: Array = []
	for i in 8:
		wide.append({"any": [{"has_evidence": "x%d" % i}, {"has_evidence": "y%d" % i}]})
	_check(validator.evidence_alternatives({"all": wide}).is_empty(), "an expansion past the cap is reported, never half-checked")


func _test_errors_reach_content_validator() -> void:
	var chapters: Dictionary = content_db.get_all_chapters()
	var broken: Dictionary = real_chapter.duplicate(true)
	broken["core_loop"]["deduction_case"] = "proto_nope"
	chapters[CHAPTER_ID] = broken
	var result: Dictionary = content_validator.validate()
	chapters[CHAPTER_ID] = real_chapter.duplicate(true)
	_check((result.get("errors", []) as Array).any(func(message: String) -> bool: return message.contains("is not a known deduction case")), "a broken core_loop reaches the ContentValidator report (validate_content.gd exits non-zero on it)")
	broken = real_chapter.duplicate(true)
	broken["core_loop"]["phases"][1]["objective"] = "CL_SBX_NO_SUCH_KEY"
	chapters[CHAPTER_ID] = broken
	result = content_validator.validate()
	chapters[CHAPTER_ID] = real_chapter.duplicate(true)
	_check((result.get("errors", []) as Array).any(func(message: String) -> bool: return message.contains("CL_SBX_NO_SUCH_KEY") and message.contains("translation")), "a missing VI/EN key in a core_loop is a validation error")
	broken = real_chapter.duplicate(true)
	_unit(broken["core_loop"], "b1_badge")["offer_condition"] = {"has_evidnce": "sbx_door_log"}
	chapters[CHAPTER_ID] = broken
	result = content_validator.validate()
	chapters[CHAPTER_ID] = real_chapter.duplicate(true)
	_check((result.get("errors", []) as Array).any(func(message: String) -> bool: return message.contains("offer_condition") and message.contains("has_evidnce")), "a typo'd offer_condition key fails closed at validation time")
	_check((content_validator.validate().get("errors", []) as Array).is_empty(), "restoring the real chapter restores a clean report")


func _test_single_new_game_entry() -> void:
	var cases: Dictionary = content_db.get_all_cases()
	var duplicate: Dictionary = (cases["case_sbx_archive"] as Dictionary).duplicate(true)
	duplicate["id"] = "case_sbx_second"
	duplicate["chapters"] = []
	duplicate.erase("starting_chapter")
	cases["case_sbx_second"] = duplicate
	var result: Dictionary = content_validator.validate()
	cases.erase("case_sbx_second")
	_check((result.get("errors", []) as Array).any(func(message: String) -> bool: return message.contains("More than one case declares")), "two New Game entry cases are rejected")


# ---------------------------------------------------------------------------
# Milestone 1.17 — multi-chapter rules

func _chapter(chapter_id: String) -> Dictionary:
	return content_db.get_chapter(chapter_id).duplicate(true)


## Like _expect(), on any chapter; returns [errors, warnings].
func _run_rules(chapter_id: String, mutate: Callable, producers: Dictionary = base_producers) -> Array:
	var chapter: Dictionary = _chapter(chapter_id)
	mutate.call(chapter)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	validator.validate_chapter(chapter_id, chapter, producers, errors, warnings)
	return [errors, warnings]


func _expect_rule(label: String, chapter_id: String, mutate: Callable, expected: String, producers: Dictionary = base_producers, as_warning: bool = false) -> void:
	var found: Array = _run_rules(chapter_id, mutate, producers)
	var pool: Array = found[1] if as_warning else found[0]
	_check(pool.any(func(message: String) -> bool: return message.contains(expected)), "%s: expected %s containing \"%s\", got errors %s / warnings %s" % [label, "a WARNING" if as_warning else "an ERROR", expected, found[0], found[1]])


func _without_evidence_producer(evidence_id: String) -> Dictionary:
	var producers: Dictionary = base_producers.duplicate(true)
	(producers["evidence"] as Dictionary).erase(evidence_id)
	return producers


func _test_second_chapter_is_clean() -> void:
	var found: Array = _run_rules(CHAPTER_2, func(_chapter: Dictionary) -> void: pass)
	_check((found[0] as Array).is_empty() and (found[1] as Array).is_empty(), "the second sandbox chapter validates with no errors and no warnings: %s %s" % [found[0], found[1]])
	var first: Array = _run_rules(CHAPTER_ID, func(_chapter: Dictionary) -> void: pass)
	_check((first[1] as Array).is_empty(), "the first sandbox raises none of the new warnings: %s" % [first[1]])


func _test_sandbox_selection_rules() -> void:
	var cases: Dictionary = content_db.get_all_cases()
	var mutations: Array = [
		["duplicate selection order", func() -> void: cases["case_sby_lab"]["sandbox_selection"]["order"] = 1, "order 1 is already used"],
		["malformed selection order", func() -> void: cases["case_sby_lab"]["sandbox_selection"] = {"order": "first"}, 'whole-number "order"'],
		["canon case offered in the selector", func() -> void: cases["case_sby_lab"]["metadata"]["canon"] = true, "is only for non-canon sandbox content"],
		["selectable sandbox without a description", func() -> void: (cases["case_sby_lab"] as Dictionary).erase("description"), 'needs a "description"'],
		["selection pointing at a missing/non-core-loop chapter", func() -> void: cases["case_sby_lab"]["starting_chapter"] = "test_case_chapter_01", "is not a core-loop chapter"],
		["selection pointing at a chapter that does not exist", func() -> void: cases["case_sby_lab"]["starting_chapter"] = "sby_nope", "is not a core-loop chapter"],
		["selectable sandboxes but no release default", func() -> void: (cases["case_sbx_archive"] as Dictionary).erase("new_game_entry"), 'no case declares "new_game_entry": true'],
	]
	for mutation in mutations:
		var snapshot: Dictionary = cases.duplicate(true)
		(mutation[1] as Callable).call()
		var result: Dictionary = content_validator.validate()
		for case_id in snapshot:
			cases[case_id] = snapshot[case_id]
		_check((result.get("errors", []) as Array).any(func(message: String) -> bool: return message.contains(mutation[2])), "%s: expected a validation error containing \"%s\", got %s" % [mutation[0], mutation[2], result.get("errors", [])])
	var chapters: Dictionary = content_db.get_all_chapters()
	var original: Dictionary = (chapters[CHAPTER_2] as Dictionary).duplicate(true)
	chapters[CHAPTER_2]["core_loop"]["canon"] = true
	var canon_result: Dictionary = content_validator.validate()
	chapters[CHAPTER_2] = original
	_check((canon_result.get("errors", []) as Array).any(func(message: String) -> bool: return message.contains('is not marked "canon": false')), "a selectable sandbox whose chapter is marked canon is rejected")
	_check((content_validator.validate().get("errors", []) as Array).is_empty(), "restoring the selection metadata restores a clean report")


func _test_documented_path_rules() -> void:
	_expect_rule("documented path that is not an accepted proof path", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "b1_badge")["documented_paths"][1] = ["sbx_door_log", "sbx_back_door_sighting", "sbx_route_note"], "is not an authored accepted proof path")
	_expect_rule("documented alternate path that cannot be reached", CHAPTER_ID, func(_chapter: Dictionary) -> void: pass, "documented path 2 is not reachable", _without_evidence_producer("sbx_harbor_photo"))
	_expect_rule("documented path naming unlinked evidence", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "b1_badge")["documented_paths"][0] = ["sbx_door_log", "test_key", "sbx_route_note"], "which evidence_links does not link")
	_expect_rule("documented paths on a non-B unit", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "a1_denial")["documented_paths"] = [["sbx_lost_property_sheet"]], "only supported on clue_connection units")


func _test_late_acquisition_producer() -> void:
	# The route note is granted ONLY by B1's own consequence: it arrives after
	# B1 needs it.
	_expect_rule("acquisition producer after the evidence is required", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "b1_badge")["consequences"]["resolved"]["effects"].append({"type": "add_evidence", "evidence_id": "sbx_route_note"}), "arrives after the unit requires it", _without_evidence_producer("sbx_route_note"))
	# ...while evidence an EARLIER phase's consequence grants is acquirable.
	var found: Array = _run_rules(CHAPTER_2, func(_chapter: Dictionary) -> void: pass, _without_evidence_producer("sby_shuttle_note"))
	_check(not (found[0] as Array).any(func(message: String) -> bool: return message.contains("b2_keycard")), "evidence only an earlier phase's consequence grants counts as acquirable for a later unit: %s" % [found[0]])


func _test_unreachable_and_cross_chapter_offers() -> void:
	_expect_rule("unit offered on a flag nothing produces", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "b2_staging")["offer_condition"]["all"].append({"flag": "sbx_debug_only_flag"}), 'phase "investigation_2" is unreachable')
	_expect_rule("...reported as needing a debug override", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "b2_staging")["offer_condition"]["all"].append({"interaction_complete": "sbx_never_marked"}), "only a debug override could")
	_expect_rule("offer depending on ANOTHER chapter's consequence", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "a1_denial")["offer_condition"]["all"].append({"flag": "sby_staging_proven"}), 'only chapter "sby_chapter_01"\'s consequence produces')


func _test_cross_chapter_completion_and_ids() -> void:
	_expect_rule("two chapters sharing one completion event", CHAPTER_ID, func(chapter: Dictionary) -> void: chapter["completion_event"] = "sby_chapter_01_complete", 'shares completion_event "sby_chapter_01_complete"')
	var events: Dictionary = content_db.get_all_events()
	events["fixture_cross_complete"] = {"id": "fixture_cross_complete", "conditions": {"flag": "sby_timeline_unlocked"}, "trigger_policy": "once", "effects": [{"type": "mark_interaction_complete", "id": "fixture_done"}]}
	_expect_rule("completion requirement another chapter's consequence produces", CHAPTER_ID, func(chapter: Dictionary) -> void:
		chapter["completion_event"] = "fixture_cross_complete"
		_unit(chapter["core_loop"], "c1_timeline")["consequences"]["resolved"]["effects"] = [{"type": "set_flag", "flag": "sby_timeline_unlocked", "value": true}], "one chapter's completion must never satisfy another's")
	events.erase("fixture_cross_complete")
	_expect_rule("consequence id shared with another chapter", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "b1_badge")["consequences"]["resolved"]["id"] = "sby_b1_resolved", 'is also used by chapter "sby_chapter_01"')


func _test_duplicate_b_target_and_case_mismatch() -> void:
	_expect_rule("two B units asking the same deduction", CHAPTER_ID, func(chapter: Dictionary) -> void: _unit(chapter["core_loop"], "b2_staging")["round"] = "round_1", 'both ask for deduction "ded_badge_misused"')
	_expect_rule("evidence linked to another deduction case", CHAPTER_2, func(chapter: Dictionary) -> void: chapter["core_loop"]["evidence_links"]["sby_open_hatch"] = "e_door_log", 'which is not evidence of deduction case "proto_y_lab_sample"')


func _test_new_warnings() -> void:
	_expect_rule("linked evidence nothing can grant", CHAPTER_ID, func(_chapter: Dictionary) -> void: pass, 'links evidence "sbx_shredding_log", but nothing can ever grant it', _without_evidence_producer("sbx_shredding_log"), true)
	_expect_rule("a unit-ending consequence that unlocks nothing", CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "b1_badge")["consequences"]["resolved"]["effects"] = [{"type": "set_flag", "flag": "sbx_nobody_reads_this", "value": true}], "unlocks nothing any condition reads", base_producers, true)
	var found: Array = _run_rules(CHAPTER_ID, func(chapter: Dictionary) -> void:
		_unit(chapter["core_loop"], "b1_badge")["consequences"]["resolved"]["effects"] = [{"type": "set_flag", "flag": "sbx_nobody_reads_this", "value": true}])
	_check(not (found[0] as Array).any(func(message: String) -> bool: return message.contains("unlocks nothing")), "an unused consequence is a WARNING, never an error")
