extends SceneTree
## Focused, independent tests for ConditionEvaluator — the condition
## mini-language shared by dialogue choices, topics, destinations, examine
## variants, npc presence, and events (see docs/architecture.md's "The
## condition mini-language"). Run with:
##   godot --headless --path . -s res://scenes/test/conditions_test.gd
##
## Deliberately its own small file (moved out of the old monolithic
## smoke_test.gd, see Milestone 1.7): adding a new leaf condition shape only
## needs a new _check(...) here, not an edit to the project's one big
## end-to-end test. Each check below is a small, deterministic setup ->
## evaluate() call -> assert, independent of any dialogue/investigation flow.
##
## ConditionEvaluator itself references GameState by bare autoload name, so —
## like every other class_name script with that property in this project —
## it's load()ed here rather than referenced by bare class name, sidestepping
## the -s entry-point compile-order trap (see docs/architecture.md, "A Godot
## quirk this project works around").

var game_state: Node
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	game_state = get_root().get_node("GameState")
	await process_frame

	print("=== ConditionEvaluator — focused tests ===")
	_test_leaf_shapes()
	_test_composite_shapes()
	_test_fail_closed_shapes()
	_test_explain()
	_test_explain_tree()
	_test_validator_precedence_rejection()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


## Every leaf shape ConditionEvaluator.KEYS lists, both directions (true and
## false) where the shape has two directions to test — see docs/architecture.md,
## "The condition mini-language" table.
func _test_leaf_shapes() -> void:
	game_state.start_new_game("case_00_sandbox")
	var evaluator = load("res://scripts/core/condition_evaluator.gd")

	_check(evaluator.evaluate(null), "a null condition should always pass")

	# flag / equals
	_check(not evaluator.evaluate({"flag": "hallway_unlocked"}), "an unset flag should evaluate false")
	_check(evaluator.evaluate({"flag": "hallway_unlocked", "equals": false}), "equals:false should pass while the flag is unset")
	game_state.set_flag("hallway_unlocked", true)
	_check(evaluator.evaluate({"flag": "hallway_unlocked"}), "a flag set true should evaluate true")
	_check(not evaluator.evaluate({"flag": "hallway_unlocked", "equals": false}), "equals:false should fail once the flag is true")

	# has_evidence
	_check(not evaluator.evaluate({"has_evidence": "test_key"}), "has_evidence should be false before the item is held")
	game_state.add_evidence("test_key")
	_check(evaluator.evaluate({"has_evidence": "test_key"}), "has_evidence should be true once the item is held")

	# visited_location
	_check(not evaluator.evaluate({"visited_location": "test_hallway"}), "visited_location should be false before that location is entered")
	game_state.go_to_location("test_hallway")
	_check(evaluator.evaluate({"visited_location": "test_hallway"}), "visited_location should be true once that location has been entered")

	# examined — always relative to GameState.current_location (now test_hallway)
	_check(not evaluator.evaluate({"examined": "mirror"}), "examined should be false before that point has been examined")
	game_state.mark_seen("examine:test_hallway:mirror")
	_check(evaluator.evaluate({"examined": "mirror"}), "examined should be true once that point has been marked seen for the current location")

	# interaction_complete
	_check(not evaluator.evaluate({"interaction_complete": "some_milestone"}), "interaction_complete should be false before that id has fired")
	game_state.mark_seen("custom:some_milestone")
	_check(evaluator.evaluate({"interaction_complete": "some_milestone"}), "interaction_complete should be true once that id has been marked complete")


func _test_composite_shapes() -> void:
	game_state.start_new_game("case_00_sandbox")
	var evaluator = load("res://scripts/core/condition_evaluator.gd")

	# all — an empty list is vacuously true at the evaluate() level (no
	# sub-condition is false); ContentValidator separately rejects an empty
	# "all" as authored content (see dependency_analysis_test.gd / the
	# existing _validate_condition coverage), so this is not a contradiction.
	_check(evaluator.evaluate({"all": []}), "an empty \"all\" list is vacuously true at the evaluate() level")
	_check(not evaluator.evaluate({"all": [{"has_evidence": "test_key"}, {"has_evidence": "test_note"}]}), "\"all\" should fail while either sub-condition is false")
	game_state.add_evidence("test_key")
	game_state.add_evidence("test_note")
	_check(evaluator.evaluate({"all": [{"has_evidence": "test_key"}, {"has_evidence": "test_note"}]}), "\"all\" should pass once every sub-condition is true")

	# any
	game_state.start_new_game("case_00_sandbox")
	_check(not evaluator.evaluate({"any": [{"has_evidence": "test_key"}, {"has_evidence": "test_note"}]}), "\"any\" should fail while every sub-condition is false")
	game_state.add_evidence("test_note")
	_check(evaluator.evaluate({"any": [{"has_evidence": "test_key"}, {"has_evidence": "test_note"}]}), "\"any\" should pass once at least one sub-condition is true")

	# not
	_check(evaluator.evaluate({"not": {"flag": "hallway_unlocked"}}), "\"not\" should pass while the inner condition is false")
	game_state.set_flag("hallway_unlocked", true)
	_check(not evaluator.evaluate({"not": {"flag": "hallway_unlocked"}}), "\"not\" should fail once the inner condition becomes true")


## The condition mini-language's edge cases, which content authors hit far
## more often than the happy path: a mistyped key must NOT silently unlock
## content (fail closed), never leak past a typed getter, etc.
func _test_fail_closed_shapes() -> void:
	game_state.start_new_game("case_00_sandbox")
	var evaluator = load("res://scripts/core/condition_evaluator.gd")

	_check(not evaluator.evaluate({"has_evidnce": "test_key"}), "a mistyped condition key should fail CLOSED, not unlock content")
	_check(not evaluator.evaluate({}), "an empty condition object should fail closed")
	_check(not evaluator.evaluate("has_evidence:test_key"), "a non-object condition should fail closed")
	_check(not evaluator.evaluate({"all": "not-an-array"}), "a non-array \"all\" should fail closed")
	_check(not evaluator.evaluate({"any": "not-an-array"}), "a non-array \"any\" should fail closed")
	_check(evaluator.evaluate({"flag": "hallway_unlocked", "equals": false}), "\"equals\" should still be a recognized modifier, not an unknown key")

	# Non-boolean flags must never reach get_flag()'s bool return type.
	game_state.flags["not_a_bool"] = "yes"
	_check(not game_state.get_flag("not_a_bool"), "a non-boolean flag should be reported and treated as the default")
	game_state.flags.erase("not_a_bool")

	# A flag explicitly set to false must still be recorded, so the debug
	# panel can list it and a save can round-trip it.
	game_state.set_flag("explicitly_false", false)
	_check(game_state.flags.has("explicitly_false"), "setting a flag to false should still record it")

	# Two checks in one object: evaluate() honours whichever comes first in
	# its own fixed precedence order (KEYS) and silently drops the rest.
	game_state.add_evidence("test_key")
	_check(
		not evaluator.evaluate({"has_evidence": "test_key", "flag": "definitely_not_set"}),
		"evaluate() resolves \"flag\" before \"has_evidence\" and drops the rest"
	)


## explain(): a top-level "all" is flattened (each part really is required),
## an "any" stays one grouped line — see docs/architecture.md's
## "The condition mini-language".
func _test_explain() -> void:
	var evaluator = load("res://scripts/core/condition_evaluator.gd")
	var all_lines: Array = evaluator.explain({"all": [{"has_evidence": "test_key"}, {"has_evidence": "test_badge"}]})
	_check(all_lines.size() == 2, "explain() should list each part of an \"all\" separately")
	var any_lines: Array = evaluator.explain({"any": [{"has_evidence": "test_key"}, {"has_evidence": "test_note"}]})
	_check(any_lines.size() == 1, "explain() should keep an \"any\" as a single entry rather than listing both halves as missing")
	_check(
		String(any_lines[0].get("description", "")).contains(" OR "),
		"an \"any\" explanation should spell out the alternatives"
	)


## explain_tree() (Milestone 1.8, Case Debugger's Condition Inspector):
## additive to explain() above — verifies the nested tree shape without
## touching explain()'s own flattening/grouping behavior, which stays exactly
## as tested by _test_explain() above.
func _test_explain_tree() -> void:
	game_state.start_new_game("case_00_sandbox")
	var evaluator = load("res://scripts/core/condition_evaluator.gd")

	var null_tree: Dictionary = evaluator.explain_tree(null)
	_check(null_tree.get("passed", false) == true, "a null condition's tree should report passed:true")
	_check((null_tree.get("children", [1]) as Array).is_empty(), "a null condition's tree should have no children")

	_check(not evaluator.explain_tree({"has_evidence": "test_key"}).get("passed", true), "a leaf's tree node should reflect evaluate()'s actual result")
	_check((evaluator.explain_tree({"has_evidence": "test_key"}).get("children", [1]) as Array).is_empty(), "a leaf should have no children")
	game_state.add_evidence("test_key")
	_check(evaluator.explain_tree({"has_evidence": "test_key"}).get("passed", false), "re-evaluating the same leaf after state changes should reflect the new result")

	game_state.start_new_game("case_00_sandbox")
	var all_tree: Dictionary = evaluator.explain_tree({"all": [{"has_evidence": "test_key"}, {"flag": "hallway_unlocked"}]})
	_check(all_tree.get("description", "") == "ALL", "a top-level \"all\" tree node should be labeled ALL")
	_check(not all_tree.get("passed", true), "the ALL node should fail while any child is false")
	_check((all_tree.get("children", []) as Array).size() == 2, "the ALL node should keep one child per sub-condition, unlike explain()'s flattening")

	var any_tree: Dictionary = evaluator.explain_tree({"any": [{"has_evidence": "test_key"}, {"flag": "hallway_unlocked"}]})
	_check(any_tree.get("description", "") == "ANY", "a top-level \"any\" tree node should be labeled ANY")
	_check((any_tree.get("children", []) as Array).size() == 2, "the ANY node should keep both alternatives as children, unlike explain()'s single grouped line")
	game_state.set_flag("hallway_unlocked", true)
	_check(evaluator.explain_tree({"any": [{"has_evidence": "test_key"}, {"flag": "hallway_unlocked"}]}).get("passed", false), "the ANY node should pass once one child passes")

	var not_tree: Dictionary = evaluator.explain_tree({"not": {"flag": "hallway_unlocked"}})
	_check(not_tree.get("description", "") == "NOT", "a \"not\" tree node should be labeled NOT")
	_check(not not_tree.get("passed", true), "NOT should invert its single (currently true) child")
	_check((not_tree.get("children", []) as Array).size() == 1, "NOT should carry exactly one child")

	# Nesting: an ALL containing an ANY should keep the ANY as a genuine
	# sub-tree, not flatten or summarize it — the entire point of this
	# inspector vs. explain().
	var nested: Dictionary = evaluator.explain_tree({
		"all": [{"any": [{"flag": "hallway_unlocked"}, {"flag": "never_set"}]}, {"has_evidence": "test_key"}],
	})
	var nested_children: Array = nested.get("children", [])
	_check(nested_children[0].get("description", "") == "ANY", "a nested composite should keep its own kind, not be flattened into the parent")


## ContentValidator is the thing that actually prevents the "one condition
## object, two checks" trap from ever reaching evaluate() at runtime — these
## checks belong here (not effects_test.gd/dependency_analysis_test.gd)
## because they're really about ConditionEvaluator's own precedence contract.
func _test_validator_precedence_rejection() -> void:
	var validator = load("res://scripts/core/content_validator.gd")

	var stacked_errors: Array[String] = []
	validator._validate_condition({"has_evidence": "test_key", "flag": "x"}, "probe", stacked_errors)
	_check(stacked_errors.size() == 1, "stacking two checks in one condition should be a validation error")
	_check(
		String(stacked_errors[0] if not stacked_errors.is_empty() else "").contains('only check "flag"'),
		"the error should name the check that would actually win, not the first key in the object"
	)

	var composite_errors: Array[String] = []
	validator._validate_condition({"all": [{"flag": "a"}], "has_evidence": "test_key"}, "probe", composite_errors)
	_check(not composite_errors.is_empty(), "mixing a composite and a leaf check in one object should also be rejected")

	var unreachable_warnings: Array[String] = []
	validator._validate_dialogue_reachability("probe", {
		"start": "n1",
		"nodes": {"n1": {"next": "n2"}, "n2": {}, "orphan": {}},
	}, unreachable_warnings)
	_check(unreachable_warnings.size() == 1, "an unreachable dialogue node should be reported once")
	_check(
		String(unreachable_warnings[0] if not unreachable_warnings.is_empty() else "").contains("orphan"),
		"the unreachable-node warning should name the orphaned node"
	)
