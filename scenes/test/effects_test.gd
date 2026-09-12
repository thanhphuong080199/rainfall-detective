extends SceneTree
## Focused, independent tests for EffectRunner — the effect vocabulary shared
## by dialogue node/choice "actions" and event "effects" (see
## docs/architecture.md, "Reusing Conditions and Effects"). Run with:
##   godot --headless --path . -s res://scenes/test/effects_test.gd
##
## Before Milestone 1.7, EffectRunner had no dedicated test — it was only
## ever exercised as a side effect of the narrative progression walkthrough
## in smoke_test.gd (see .claude/skills/godot-testing/references/test-catalog.md).
## Each check here is a small, deterministic setup -> EffectRunner.run() call
## -> assertion against resulting GameState, per docs/godot-testing's
## "assert resulting Game State rather than private method calls."

var game_state: Node
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	game_state = get_root().get_node("GameState")
	await process_frame

	print("=== EffectRunner — focused tests ===")
	_test_set_flag()
	_test_add_evidence()
	_test_remove_evidence()
	_test_mark_interaction_complete()
	_test_unknown_effect_type_is_a_safe_noop()
	_test_effect_list_idempotent_on_repeat_run()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _fresh_state() -> void:
	game_state.start_new_game("case_00_sandbox")


func _test_set_flag() -> void:
	_fresh_state()
	var effect_runner = load("res://scripts/core/effect_runner.gd")

	# A lambda captures a local by VALUE, not by reference (see
	# .claude/skills/godot-development/references/cli-verification.md) — a
	# single-element Array is the mutable cell that works around this.
	var change_count: Array[int] = [0]
	var on_flag_changed := func(_name, _value): change_count[0] += 1
	game_state.flag_changed.connect(on_flag_changed)

	effect_runner.run([{"type": "set_flag", "flag": "effect_test_flag", "value": true}])
	_check(game_state.get_flag("effect_test_flag"), "set_flag effect should set the named flag to the given value")
	_check(change_count[0] == 1, "set_flag should emit flag_changed exactly once for a real change")

	# Running the identical effect again (the flag already holds that value)
	# must not re-emit flag_changed — UI refreshes and EventManager
	# re-evaluation both hang off that signal, so a spurious emission would
	# mean unrelated re-evaluation work on every no-op re-run.
	effect_runner.run([{"type": "set_flag", "flag": "effect_test_flag", "value": true}])
	_check(change_count[0] == 1, "re-running set_flag with the same value must not re-emit flag_changed")

	effect_runner.run([{"type": "set_flag", "flag": "effect_test_flag", "value": false}])
	_check(not game_state.get_flag("effect_test_flag"), "set_flag should be able to flip a flag back to false")
	_check(change_count[0] == 2, "flipping the flag to a genuinely new value should emit flag_changed again")

	game_state.flag_changed.disconnect(on_flag_changed)


func _test_add_evidence() -> void:
	_fresh_state()
	var effect_runner = load("res://scripts/core/effect_runner.gd")

	var added_count: Array[int] = [0]
	var on_evidence_added := func(_id): added_count[0] += 1
	game_state.evidence_added.connect(on_evidence_added)

	effect_runner.run([{"type": "add_evidence", "evidence_id": "test_key"}])
	_check(game_state.has_evidence("test_key"), "add_evidence effect should grant the named evidence")
	_check(game_state.evidence_inventory.count("test_key") == 1, "add_evidence should grant exactly one copy")
	_check(added_count[0] == 1, "add_evidence should emit evidence_added exactly once for a real grant")

	# Idempotency: already holding the item must be a safe no-op, not a
	# second copy and not a second signal emission.
	effect_runner.run([{"type": "add_evidence", "evidence_id": "test_key"}])
	_check(game_state.evidence_inventory.count("test_key") == 1, "add_evidence must not duplicate an already-held item")
	_check(added_count[0] == 1, "re-adding an already-held item must not re-emit evidence_added")

	game_state.evidence_added.disconnect(on_evidence_added)


func _test_remove_evidence() -> void:
	_fresh_state()
	var effect_runner = load("res://scripts/core/effect_runner.gd")

	var removed_count: Array[int] = [0]
	var on_evidence_removed := func(_id): removed_count[0] += 1
	game_state.evidence_removed.connect(on_evidence_removed)

	# Removing evidence that was never held must be a safe no-op — for
	# evidence that gets consumed along more than one narrative path, only
	# one of which the player may have actually taken.
	effect_runner.run([{"type": "remove_evidence", "evidence_id": "test_note"}])
	_check(not game_state.has_evidence("test_note"), "removing evidence never held should remain absent")
	_check(removed_count[0] == 0, "removing evidence never held must not emit evidence_removed")

	game_state.add_evidence("test_note")
	effect_runner.run([{"type": "remove_evidence", "evidence_id": "test_note"}])
	_check(not game_state.has_evidence("test_note"), "remove_evidence should remove evidence that was actually held")
	_check(removed_count[0] == 1, "remove_evidence should emit evidence_removed exactly once for a real removal")

	# Removing it again (already gone) must not re-emit.
	effect_runner.run([{"type": "remove_evidence", "evidence_id": "test_note"}])
	_check(removed_count[0] == 1, "removing already-absent evidence a second time must not re-emit evidence_removed")

	game_state.evidence_removed.disconnect(on_evidence_removed)


func _test_mark_interaction_complete() -> void:
	_fresh_state()
	var effect_runner = load("res://scripts/core/effect_runner.gd")

	var seen_count: Array[int] = [0]
	var on_interaction_seen := func(_key): seen_count[0] += 1
	game_state.interaction_seen.connect(on_interaction_seen)

	_check(not game_state.has_seen("custom:effect_test_milestone"), "the milestone should not be marked before the effect runs")
	effect_runner.run([{"type": "mark_interaction_complete", "id": "effect_test_milestone"}])
	_check(game_state.has_seen("custom:effect_test_milestone"), "mark_interaction_complete should record the milestone under the 'custom:' namespace")
	_check(seen_count[0] == 1, "mark_interaction_complete should emit interaction_seen exactly once for a new milestone")

	# One-off milestones are exactly that — running the same effect again
	# (e.g. a chapter re-entered via jump_to_chapter, or a dialogue node
	# replayed) must not re-fire interaction_seen a second time.
	effect_runner.run([{"type": "mark_interaction_complete", "id": "effect_test_milestone"}])
	_check(seen_count[0] == 1, "re-running mark_interaction_complete for an already-seen id must not re-emit interaction_seen")

	game_state.interaction_seen.disconnect(on_interaction_seen)


## An effect with an unrecognized "type" is only a ContentValidator WARNING
## (see docs/event-system.md's "Content validation" / content_validator.gd's
## _validate_effects), so EffectRunner itself must degrade safely: no crash,
## no state mutated, regardless of whatever unrelated fields the malformed
## entry happens to carry.
func _test_unknown_effect_type_is_a_safe_noop() -> void:
	_fresh_state()
	var effect_runner = load("res://scripts/core/effect_runner.gd")
	var flags_before: Dictionary = game_state.flags.duplicate()
	var evidence_before: Array = game_state.evidence_inventory.duplicate()

	effect_runner.run([{"type": "teleport_player", "flag": "hallway_unlocked", "evidence_id": "test_key"}])

	_check(game_state.flags == flags_before, "an unknown effect type must not mutate flags")
	_check(game_state.evidence_inventory == evidence_before, "an unknown effect type must not mutate evidence")


## Effects are re-run wholesale on chapter re-entry (jump_to_chapter) and
## potentially replayed dialogue nodes — a list of effects must be safe to
## execute more than once with the exact same net result (see
## docs/godot-testing's "safe during reevaluation").
func _test_effect_list_idempotent_on_repeat_run() -> void:
	_fresh_state()
	var effect_runner = load("res://scripts/core/effect_runner.gd")
	var effects := [
		{"type": "set_flag", "flag": "chapter_scope_active", "value": true},
		{"type": "add_evidence", "evidence_id": "test_badge"},
		{"type": "mark_interaction_complete", "id": "entered_chapter"},
	]

	effect_runner.run(effects)
	effect_runner.run(effects)
	effect_runner.run(effects)

	_check(game_state.get_flag("chapter_scope_active"), "repeated set_flag should still leave the flag true")
	_check(game_state.evidence_inventory.count("test_badge") == 1, "repeated add_evidence should still leave exactly one copy")
	_check(game_state.has_seen("custom:entered_chapter"), "repeated mark_interaction_complete should still be recorded")
