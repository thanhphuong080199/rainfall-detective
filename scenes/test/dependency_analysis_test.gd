extends SceneTree
## Tests for ContentValidator's dependency-reachability WARNINGs (Milestone
## 1.7, section 19) — cheap static checks for "a condition requires flag/
## evidence/interaction X, but nothing in loaded content can ever produce
## it." See content_validator.gd's own "Dependency reachability" section
## for exactly what this does and does not attempt to prove. Run with:
##   godot --headless --path . -s res://scenes/test/dependency_analysis_test.gd
##
## _collect_condition_requirements() and _collect_effect_targets() are pure
## functions (no ContentDB access), so they're unit-tested directly here with
## hand-built dictionaries — the same "call the validator function directly"
## pattern smoke_test.gd already established for _validate_condition() and
## _validate_dialogue_reachability(). The real sandbox content is checked
## separately, end to end, via ContentDB's own cached validation result.

var content_db: Node
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame

	print("=== ContentValidator dependency-reachability tests ===")
	_test_collect_condition_requirements()
	_test_collect_effect_targets()
	_test_real_sandbox_content_has_no_dependency_warnings()
	_test_end_to_end_unreachable_flag_is_reported()
	_test_find_producers()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _test_collect_condition_requirements() -> void:
	var validator = load("res://scripts/core/content_validator.gd")

	var flags: Dictionary = {}
	var evidence: Dictionary = {}
	var interactions: Dictionary = {}
	validator._collect_condition_requirements({"flag": "some_flag"}, flags, evidence, interactions)
	_check(flags.has("some_flag"), "a top-level {\"flag\": ...} (equals defaulting to true) should be collected as a requirement")

	flags = {}
	validator._collect_condition_requirements({"flag": "some_flag", "equals": false}, flags, evidence, interactions)
	_check(not flags.has("some_flag"), "an equals:false flag requirement should NOT be collected — it's satisfied by the default unset state")

	flags = {}
	evidence = {}
	validator._collect_condition_requirements(
		{"all": [{"flag": "a"}, {"has_evidence": "b"}]}, flags, evidence, interactions
	)
	_check(flags.has("a") and evidence.has("b"), "requirements nested inside a top-level \"all\" should be collected")

	flags = {}
	validator._collect_condition_requirements({"any": [{"flag": "a"}, {"flag": "b"}]}, flags, evidence, interactions)
	_check(flags.is_empty(), "requirements nested inside an \"any\" should NOT be collected — the other alternative may be reachable")

	flags = {}
	validator._collect_condition_requirements({"not": {"flag": "a"}}, flags, evidence, interactions)
	_check(flags.is_empty(), "requirements nested inside a \"not\" should NOT be collected")

	interactions = {}
	validator._collect_condition_requirements({"interaction_complete": "some_id"}, {}, {}, interactions)
	_check(interactions.has("some_id"), "a top-level interaction_complete requirement should be collected")


func _test_collect_effect_targets() -> void:
	var validator = load("res://scripts/core/content_validator.gd")

	var flags: Dictionary = {}
	var evidence: Dictionary = {}
	var interactions: Dictionary = {}
	validator._collect_effect_targets([{"type": "set_flag", "flag": "a", "value": true}], flags, evidence, interactions)
	_check(flags.has("a"), "set_flag ... value:true should be collected as capable of satisfying {\"flag\": \"a\"}")

	flags = {}
	validator._collect_effect_targets([{"type": "set_flag", "flag": "a", "value": false}], flags, evidence, interactions)
	_check(not flags.has("a"), "set_flag ... value:false must NOT be collected as capable of satisfying {\"flag\": \"a\"}")

	flags = {}
	validator._collect_effect_targets([{"type": "set_flag", "flag": "a"}], flags, evidence, interactions)
	_check(flags.has("a"), "set_flag with no explicit value defaults to true, per EffectRunner")

	evidence = {}
	validator._collect_effect_targets([{"type": "add_evidence", "evidence_id": "test_key"}], {}, evidence, {})
	_check(evidence.has("test_key"), "add_evidence should be collected as capable of satisfying has_evidence")

	interactions = {}
	validator._collect_effect_targets([{"type": "mark_interaction_complete", "id": "some_id"}], {}, {}, interactions)
	_check(interactions.has("some_id"), "mark_interaction_complete should be collected as capable of satisfying interaction_complete")


## The real sandbox content (case_00_sandbox + test_case, and every shared
## location/dialogue/event they use) must produce zero UNEXPECTED dependency
## warnings — every flag/evidence/interaction it requires genuinely has a
## producing Effect somewhere in the same content, confirmed by manually
## tracing every condition in data/ during this milestone's implementation.
## The one known exception (see smoke_test.gd's KNOWN_ACCEPTED_WARNINGS,
## which this list must match) is test_repeatable_pulse's "pulse_flag" —
## deliberately test-scaffolding-only content, not a real gap. A NEW warning
## appearing here means either a real content gap was introduced, or the
## check itself needs refining — never silence it by weakening the check.
func _test_real_sandbox_content_has_no_dependency_warnings() -> void:
	var result: Dictionary = content_db.get_last_validation_result()
	var unexpected_dependency_warnings: Array = []
	for warning in result.get("warnings", []):
		var text: String = String(warning)
		if text.begins_with("Dependency check:") and not text.contains("pulse_flag"):
			unexpected_dependency_warnings.append(warning)
	_check(unexpected_dependency_warnings.is_empty(), "real sandbox content should produce zero unexpected dependency-reachability warnings: %s" % [unexpected_dependency_warnings])


## End-to-end proof the check actually catches a real gap (mirroring
## docs/architecture.md's own precedent for verifying ContentValidator
## "actually catches problems, not just passes clean content vacuously") —
## composed entirely from the two pure collector functions already unit-
## tested above, without mutating ContentDB's real loaded singleton state.
func _test_end_to_end_unreachable_flag_is_reported() -> void:
	var validator = load("res://scripts/core/content_validator.gd")
	var warnings: Array[String] = []

	var settable_flags: Dictionary = {}
	validator._collect_effect_targets([{"type": "set_flag", "flag": "other_flag", "value": true}], settable_flags, {}, {})

	var required_flags: Dictionary = {}
	validator._collect_condition_requirements({"flag": "totally_unreachable_flag"}, required_flags, {}, {})

	for flag_name in required_flags:
		if not settable_flags.has(flag_name):
			warnings.append('Dependency check: a condition requires flag "%s" to be true, but no Effect anywhere in loaded content ever sets it' % flag_name)

	_check(warnings.size() == 1, "a flag required but never set by any collected effect should produce exactly one warning")
	_check(warnings[0].contains("totally_unreachable_flag"), "the warning should name the specific unreachable flag")


## find_flag_producers/find_evidence_producers/find_interaction_producers
## (Milestone 1.8, Case Debugger's Inspector tab): unlike the collectors
## above (which only answer "does some producer exist," for the WARNING
## check), these name WHICH content produces something and WHERE — checked
## here against the real loaded sandbox content, since (unlike the pure
## collector functions above) they read ContentDB directly.
func _test_find_producers() -> void:
	var validator = load("res://scripts/core/content_validator.gd")

	var flag_producers: Array = validator.find_flag_producers("character_a_moved")
	_check(flag_producers.size() >= 1, "character_a_moved should have at least one known producer in real content")
	var flag_sources: Array = []
	for entry in flag_producers:
		flag_sources.append(String(entry.get("source", "")))
	_check(
		flag_sources.any(func(source): return source.contains("character_a_moves_to_hallway")),
		"the known producer of character_a_moved should point at the event that actually sets it (character_a_moves_to_hallway)"
	)

	_check(validator.find_flag_producers("totally_unreachable_flag_xyz").is_empty(), "a flag nothing sets should have zero known producers")

	var evidence_producers: Array = validator.find_evidence_producers("test_key")
	_check(evidence_producers.size() >= 1, "test_key should have at least one known producer in real content")
	_check(
		String(evidence_producers[0].get("source", "")).contains("examine_desk_before"),
		"the known producer of test_key should point at the dialogue tree that actually grants it (examine_desk_before)"
	)
	_check(validator.find_evidence_producers("no_such_evidence_xyz").is_empty(), "evidence nothing grants should have zero known producers")

	var interaction_producers: Array = validator.find_interaction_producers("character_a_ready_to_move")
	_check(interaction_producers.size() >= 1, "character_a_ready_to_move should have at least one known producer in real content")
	_check(validator.find_interaction_producers("no_such_interaction_xyz").is_empty(), "an interaction_complete id nothing marks should have zero known producers")

	# The underlying predicate find_flag_producers is built on: a
	# set_flag ... value:false must never count as a producer of {"flag": x}
	# becoming true — same "equals:true only" rule the WARNING check already
	# enforces. Tested directly against the real (pure) predicate rather than
	# depending on real sandbox content happening to contain a value:false
	# setter to filter out.
	_check(validator._effect_produces_flag({"type": "set_flag", "flag": "x", "value": true}, "x"), "a set_flag ... value:true effect should be recognized as producing that flag")
	_check(not validator._effect_produces_flag({"type": "set_flag", "flag": "x", "value": false}, "x"), "a set_flag ... value:false effect must NOT be recognized as producing that flag")
	_check(validator._effect_produces_flag({"type": "set_flag", "flag": "x"}, "x"), "set_flag with no explicit value defaults to true, per EffectRunner")
	_check(not validator._effect_produces_flag({"type": "set_flag", "flag": "y", "value": true}, "x"), "a set_flag for a different flag must not match")
