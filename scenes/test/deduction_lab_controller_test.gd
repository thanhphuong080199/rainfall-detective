extends SceneTree
## Focused tests for DeductionLabController (Milestone 1.10 — see
## docs/deduction-lab.md): session ownership, isolation between cases, the
## switch/reset confirmation flow, and that mode toggling never mutates the
## session. Pure/autoload-free — hand-built fixtures, no ContentDB needed. Run
## with: godot --headless --path . -s res://scenes/test/deduction_lab_controller_test.gd

var controller_script: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	# Loaded via load() rather than referenced by class_name, matching every
	# other deduction test in this project — see deduction_cases_test.gd's own
	# header comment for why (-s entry-script compile-order caution).
	controller_script = load("res://scripts/deduction/deduction_lab_controller.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== DeductionLabController — focused tests ===")
	_test_start_case()
	_test_malformed_case_def_is_rejected()
	_test_has_progress_definition()
	_test_switch_without_progress_is_immediate()
	_test_switch_with_progress_requires_confirmation()
	_test_cancel_preserves_session_exactly()
	_test_confirm_creates_isolated_session()
	_test_state_never_leaks_between_cases()
	_test_reset_session_in_place()
	_test_mode_toggle_never_mutates_session()
	_test_snapshot_restore_round_trip()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _case_x() -> Dictionary:
	return fixtures.base_case()


func _case_y() -> Dictionary:
	var case_def: Dictionary = fixtures.base_case()
	case_def["id"] = "fx_case_y"
	return case_def


func _new_controller():
	return controller_script.new()


func _test_start_case() -> void:
	var controller = _new_controller()
	_check(controller.get_session() == null, "a fresh controller should have no session")
	_check(controller.start_case(_case_x()), "start_case should succeed for a well-formed case_def")
	_check(controller.get_case_id() == "fx_case", "get_case_id should report the started case's id")
	_check(controller.get_session() != null, "start_case should create a session")
	_check(controller.get_session().case_id == "fx_case", "the created session should carry the case's id")


func _test_malformed_case_def_is_rejected() -> void:
	var controller = _new_controller()
	_check(controller.start_case(_case_x()), "sanity — starting a valid case first should succeed")
	var existing_session = controller.get_session()
	_check(not controller.start_case({}), "start_case should reject an empty dictionary")
	_check(not controller.start_case({"display_name": "no id here"}), "start_case should reject a case_def with no id")
	_check(controller.get_session() == existing_session, "a rejected start_case must not replace the existing session")


func _test_has_progress_definition() -> void:
	var controller = _new_controller()
	controller.start_case(_case_x())
	_check(not controller.has_progress(), "a freshly started session should have no progress")

	var evidence_only = _new_controller()
	evidence_only.start_case(_case_x())
	evidence_only.get_session().mark_evidence_opened("e_log")
	_check(evidence_only.has_progress(), "opening one piece of evidence should count as progress")

	var hint_only = _new_controller()
	hint_only.start_case(_case_x())
	hint_only.get_session().advance_hint("ded_misused", 1)
	_check(hint_only.has_progress(), "revealing one hint level should count as progress")

	var attempt_only = _new_controller()
	attempt_only.start_case(_case_x())
	attempt_only.get_session().record_attempt("ded_misused", "supports", "irrelevant_evidence")
	_check(attempt_only.has_progress(), "a single logged attempt (even a failed one) should count as progress")

	var resolved_only = _new_controller()
	resolved_only.start_case(_case_x())
	resolved_only.get_session().resolve_claim("ded_misused", "supported", true)
	_check(resolved_only.has_progress(), "a resolved claim should count as progress")


func _test_switch_without_progress_is_immediate() -> void:
	var controller = _new_controller()
	_check(controller.request_case_switch(_case_x()) == "switched", "the very first case selection should switch immediately (nothing to lose)")
	var first_session = controller.get_session()
	_check(controller.request_case_switch(_case_y()) == "switched", "switching from a session with no progress should also be immediate")
	_check(controller.get_case_id() == "fx_case_y", "the immediate switch should actually change the active case")
	_check(controller.get_session() != first_session, "the immediate switch should create a brand new session object")
	_check(not controller.has_pending_switch(), "an immediate switch should leave nothing pending")


func _test_switch_with_progress_requires_confirmation() -> void:
	var controller = _new_controller()
	controller.start_case(_case_x())
	controller.get_session().mark_evidence_opened("e_log")
	var session_before = controller.get_session()

	_check(controller.request_case_switch(_case_y()) == "pending_confirmation", "switching away from meaningful progress should require confirmation")
	_check(controller.has_pending_switch(), "a deferred switch should be marked pending")
	_check(controller.get_pending_case_id() == "fx_case_y", "the pending switch should remember which case was requested")
	_check(controller.get_session() == session_before, "the current session must be untouched while a switch is only pending")
	_check(controller.get_case_id() == "fx_case", "the active case must not change until the switch is confirmed")

	_check(controller.request_case_switch({}) == "invalid", "requesting a switch to a malformed case_def should be rejected")
	_check(controller.get_session() == session_before, "a rejected switch request must not touch the current session")


func _test_cancel_preserves_session_exactly() -> void:
	var controller = _new_controller()
	controller.start_case(_case_x())
	var session = controller.get_session()
	session.mark_evidence_opened("e_log")
	session.record_attempt("ded_misused", "supports", "irrelevant_evidence")
	var before: Dictionary = session.to_dict()

	_check(controller.request_case_switch(_case_y()) == "pending_confirmation", "sanity — this switch should be deferred")
	_check(controller.cancel_case_switch(), "cancel_case_switch should succeed while a switch is pending")
	_check(not controller.has_pending_switch(), "cancelling should clear the pending switch")
	_check(controller.get_session() == session, "cancelling must preserve session OBJECT IDENTITY, not just equal content")
	_check(session.to_dict() == before, "cancelling must leave the session's content byte-for-byte (structurally) unchanged")
	_check(not controller.cancel_case_switch(), "cancelling with nothing pending should report false")


func _test_confirm_creates_isolated_session() -> void:
	var controller = _new_controller()
	controller.start_case(_case_x())
	var old_session = controller.get_session()
	old_session.mark_evidence_opened("e_log")
	old_session.resolve_claim("ded_misused", "supported", true)

	controller.request_case_switch(_case_y())
	_check(controller.confirm_case_switch(), "confirm_case_switch should succeed while a switch is pending")
	_check(not controller.has_pending_switch(), "confirming should clear the pending switch")
	_check(controller.get_case_id() == "fx_case_y", "confirming should activate the requested case")
	var new_session = controller.get_session()
	_check(new_session != old_session, "confirming should create a NEW session object, never reuse the old one")
	_check(new_session.get_resolved_claims().is_empty(), "the new session must start with none of the old case's resolved claims")
	_check(new_session.get_opened_evidence_ids().is_empty(), "the new session must start with none of the old case's opened evidence")
	_check(not controller.confirm_case_switch(), "confirming with nothing pending should report false")


func _test_state_never_leaks_between_cases() -> void:
	var controller = _new_controller()
	controller.start_case(_case_x())
	controller.get_session().mark_evidence_opened("e_log")
	controller.get_session().advance_hint("ded_misused", 2)

	controller.start_case(_case_y())
	_check(controller.get_session().get_opened_evidence_ids().is_empty(), "starting a different case must not carry over opened evidence")
	_check(controller.get_session().get_hint_levels().is_empty(), "starting a different case must not carry over hint levels")

	controller.start_case(_case_x())
	_check(controller.get_session().get_opened_evidence_ids().is_empty(), "re-starting the SAME case id must also create a fresh, isolated session")


func _test_reset_session_in_place() -> void:
	var controller = _new_controller()
	_check(not controller.reset_session(), "reset_session before any case has started should report false")
	controller.start_case(_case_x())
	var session = controller.get_session()
	session.mark_evidence_opened("e_log")
	session.resolve_claim("ded_misused", "supported", true)
	_check(controller.has_progress(), "sanity — there should be progress before reset")

	_check(controller.reset_session(), "reset_session should succeed with an active session")
	_check(controller.get_session() == session, "reset_session must reset IN PLACE — same object identity")
	_check(not controller.has_progress(), "reset_session should clear all progress")
	_check(controller.get_case_id() == "fx_case", "reset_session must not change which case is active")


func _test_mode_toggle_never_mutates_session() -> void:
	var controller = _new_controller()
	controller.start_case(_case_x())
	controller.get_session().mark_evidence_opened("e_log")
	var before: Dictionary = controller.get_session().to_dict()

	_check(controller.get_mode() == controller_script.MODE_PLAYER, "the default mode should be Player Preview")
	_check(controller.set_mode(controller_script.MODE_AUTHOR), "switching to Author mode should succeed")
	_check(controller.get_mode() == controller_script.MODE_AUTHOR, "get_mode should reflect the switch")
	_check(controller.get_session().to_dict() == before, "switching mode must not mutate the session at all")
	_check(controller.set_mode(controller_script.MODE_PLAYER), "switching back to Player mode should succeed")
	_check(not controller.set_mode("not_a_real_mode"), "an unknown mode string should be rejected")
	_check(controller.get_mode() == controller_script.MODE_PLAYER, "a rejected mode change should leave the mode unchanged")


func _test_snapshot_restore_round_trip() -> void:
	var controller = _new_controller()
	controller.start_case(_case_x())
	var session = controller.get_session()
	session.mark_evidence_opened("e_log")
	session.resolve_claim("ded_misused", "supported", true)
	controller.set_mode(controller_script.MODE_AUTHOR)
	var snapshot: Dictionary = controller.snapshot()

	var restored = _new_controller()
	_check(restored.restore(snapshot, _case_x()), "restore should succeed for a snapshot just taken")
	_check(restored.get_case_id() == "fx_case", "restore should recover the case id")
	_check(restored.get_mode() == controller_script.MODE_AUTHOR, "restore should recover the mode")
	_check(restored.get_session().to_dict() == session.to_dict(), "restore should recover the session's full progress")
	_check(not restored.restore({}), "restore should reject a dictionary with no case_id")
	_check(not restored.restore({"case_id": "fx_case", "session": "not_a_dictionary"}), "restore should reject a malformed session payload")
