extends SceneTree
## Milestone 1.16 — CoreLoopValidator negative fixtures (see
## docs/core-loop-sandbox.md, "Validation", and docs/testing.md). The real
## sandbox chapter must validate clean; each mutation below breaks exactly one
## rule of the chapter-run contract and must be reported as an ERROR — and a
## broken chapter injected into ContentDB must surface through the same
## ContentValidator report validate_content.gd turns into a non-zero exit.
## Needs ContentDB (autoload) — validators are load()ed at runtime, never
## referenced by class name (docs/architecture.md, "Known limitations").
## FAST and FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_validation_test.gd

const CHAPTER_ID := "sbx_chapter_01"

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
