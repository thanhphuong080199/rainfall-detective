extends SceneTree
## Focused tests for DeductionLabPresenter (Milestone 1.10 — see
## docs/deduction-lab.md): the Player Preview spoiler-boundary contract,
## checked structurally (exact allow-listed keys, recursively) and by content
## (no real domain id/veracity/proof-set/structural-role value ever reaches
## the "view" the presenter returns), against the real X/Y/Z prototype cases
## loaded through ContentDB — plus the evidence-gating case the fixture
## covers that the real cases don't (Milestone 1.9.1 removed all
## unlock_requires from X/Y/Z). Run with:
##   godot --headless --path . -s res://scenes/test/deduction_lab_presenter_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]

var content_db: Node
var presenter: Variant
var evaluator: Variant
var session_script: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame

	presenter = load("res://scripts/deduction/deduction_lab_presenter.gd")
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	session_script = load("res://scripts/deduction/deduction_session.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== DeductionLabPresenter — focused tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		_check(not case_def.is_empty(), "%s should load through ContentDB" % case_id)
		_test_player_view_shape(case_def)
		_test_player_view_spoiler_safety(case_def)
		_test_player_view_claim_visibility_gating(case_def)
		_test_player_view_hint_progression(case_def)
		_test_author_view_is_unfiltered(case_def)
	_test_player_view_hides_gated_evidence()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_session(case_id: String):
	return session_script.new(case_id)


## Every domain id anywhere in `case_def` (suspects, questions, evidence,
## claims, proof sets, timeline events/constraints) — the exact vocabulary a
## spoiler-safe view must never contain.
func _all_domain_ids(case_def: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for section in ["suspects", "questions", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			ids.append(str(entry.get("id", "")))
	for claim in case_def.get("claims", []):
		for proof_set in claim.get("proof_sets", []):
			ids.append(str(proof_set.get("id", "")))
	var timeline: Dictionary = case_def.get("timeline", {})
	for event in timeline.get("events", []):
		ids.append(str(event.get("id", "")))
	for constraint in timeline.get("constraints", []):
		ids.append(str(constraint.get("id", "")))
	return ids


func _all_structural_roles(case_def: Dictionary) -> Array[String]:
	var roles: Array[String] = []
	for section in ["suspects", "questions", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			var role: String = str(entry.get("structural_role", ""))
			if role != "" and not roles.has(role):
				roles.append(role)
	return roles


func _all_veracity_values(case_def: Dictionary) -> Array[String]:
	var values: Array[String] = []
	for claim in case_def.get("claims", []):
		var veracity: String = str(claim.get("veracity", ""))
		if veracity != "" and not values.has(veracity):
			values.append(veracity)
	return values


## Every key that appears anywhere in `value`, recursively — used to prove
## the STRUCTURE itself never carries a banned field name, not just that its
## current values happen not to look like ids.
func _collect_all_keys(value: Variant, out: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary):
			out[str(key)] = true
			_collect_all_keys((value as Dictionary)[key], out)
	elif typeof(value) == TYPE_ARRAY:
		for entry in (value as Array):
			_collect_all_keys(entry, out)


func _assert_keys_exactly(dict: Dictionary, allowed: Array, context: String) -> void:
	var actual: Array = dict.keys()
	actual.sort()
	var expected: Array = allowed.duplicate()
	expected.sort()
	_check(actual == expected, "%s should have exactly the keys %s, got %s" % [context, expected, actual])


func _test_player_view_shape(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var result: Dictionary = presenter.build_player_view(case_def, _new_session(case_id))
	var view: Dictionary = result.get("view", {})
	_assert_keys_exactly(view, ["non_canon", "case_title", "case_description", "solved", "questions_resolved", "questions_total", "suspects", "questions", "evidence", "claims", "hints", "timeline"], "%s: player view" % case_id)
	_check(view.get("non_canon") == true, "%s: the Player Preview must surface the non-canon status" % case_id)
	for suspect in view.get("suspects", []):
		_assert_keys_exactly(suspect, ["handle", "name"], "%s: player suspect entry" % case_id)
	for question in view.get("questions", []):
		_assert_keys_exactly(question, ["handle", "text", "required", "resolved"], "%s: player question entry" % case_id)
	for evidence in view.get("evidence", []):
		_assert_keys_exactly(evidence, ["handle", "name", "opened", "text", "tags", "time"], "%s: player evidence entry" % case_id)
	for claim in view.get("claims", []):
		var allowed: Array = ["handle", "kind", "text", "status"]
		if claim.get("kind") == "statement":
			allowed.append("speaker")
		_assert_keys_exactly(claim, allowed, "%s: player claim entry" % case_id)
	for hint in view.get("hints", []):
		_assert_keys_exactly(hint, ["handle", "question_handle", "levels_revealed", "total_levels", "can_reveal_more"], "%s: player hint entry" % case_id)
	for event in view.get("timeline", []):
		_assert_keys_exactly(event, ["handle", "label", "known_time"], "%s: player timeline entry" % case_id)


## Content-level sweep: after a realistic amount of play (D1 proven, one
## evidence opened, one hint revealed, but NOT solved), no domain id, no
## structural role, and no raw veracity value the case defines may appear
## anywhere in the serialized view — and no key name banned by the milestone
## brief may appear anywhere in its structure either.
func _test_player_view_spoiler_safety(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session = _new_session(case_id)
	var misused_id: String = _role_id(case_def, "claims", "credential_misused")
	var use_record_id: String = _role_id(case_def, "evidence", "credential_use_record")
	var alibi_id: String = _role_id(case_def, "evidence", "owner_alibi_primary")
	var travel_id: String = _role_id(case_def, "evidence", "travel_fact")
	evaluator.commit_attempt(case_def, session, misused_id, "supports", [use_record_id, alibi_id, travel_id])
	session.mark_evidence_opened(use_record_id)
	evaluator.request_hint(case_def, session, _role_id(case_def, "claims", "candidate_exclusive_control"))

	var result: Dictionary = presenter.build_player_view(case_def, session)
	var view: Dictionary = result.get("view", {})
	var serialized: String = JSON.stringify(view)

	for domain_id in _all_domain_ids(case_def):
		_check(not serialized.contains(domain_id), "%s: player view must never contain the raw domain id \"%s\"" % [case_id, domain_id])
	for role in _all_structural_roles(case_def):
		_check(not serialized.contains(role), "%s: player view must never contain the structural role \"%s\"" % [case_id, role])
	for veracity in _all_veracity_values(case_def):
		# "true"/"false" are also legitimate substrings of unrelated JSON
		# (e.g. booleans) so only the case's more specific values are checked.
		if veracity == "true" or veracity == "false":
			continue
		_check(not serialized.contains(veracity), "%s: player view must never contain the raw veracity value \"%s\"" % [case_id, veracity])
	for domain_id in result.get("handle_map", {}).values():
		_check(not serialized.contains(str(domain_id)), "%s: player view must never contain a handle_map target id (\"%s\")" % [case_id, domain_id])

	var all_keys: Dictionary = {}
	_collect_all_keys(view, all_keys)
	for banned_key in ["id", "veracity", "proof_sets", "compatible", "structural_role", "resolved_by", "unlock_requires", "ground_truth", "depth", "source", "certainty", "misleading", "speaker_id", "lie_motive"]:
		_check(not all_keys.has(banned_key), '%s: player view must never carry a "%s" field anywhere in its structure' % [case_id, banned_key])

	_check(not serialized.contains(str(case_def.get("ground_truth", {}).get("culprit", "IMPOSSIBLE"))), "%s: the culprit id must never appear in the player view" % case_id)


## The conclusion's text (and every unresolved deduction's text) must be
## absent before it is proven, and appear only once the session resolves it —
## proven by literally counting visible claims before/after, not just by
## re-checking ids.
func _test_player_view_claim_visibility_gating(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session = _new_session(case_id)
	var statement_and_hypothesis_count := 0
	for claim in case_def.get("claims", []):
		if claim.get("kind") == "statement" or claim.get("kind") == "hypothesis":
			statement_and_hypothesis_count += 1

	var fresh_view: Dictionary = presenter.build_player_view(case_def, session).get("view", {})
	_check((fresh_view.get("claims", []) as Array).size() == statement_and_hypothesis_count, "%s: a fresh session should show only statements/hypotheses (%d), never an unresolved deduction or conclusion" % [case_id, statement_and_hypothesis_count])

	var conclusion_key: String = evaluator.find_claim(case_def, str(case_def.get("ground_truth", {}).get("conclusion", ""))).get("text", "")
	var conclusion_text: String = String(TranslationServer.translate(conclusion_key))
	_check(not JSON.stringify(fresh_view).contains(conclusion_text), "%s: the conclusion's translated text must not appear before it is proven" % case_id)

	var misused_id: String = _role_id(case_def, "claims", "credential_misused")
	evaluator.commit_attempt(case_def, session, misused_id, "supports", [_role_id(case_def, "evidence", "credential_use_record"), _role_id(case_def, "evidence", "owner_alibi_primary"), _role_id(case_def, "evidence", "travel_fact")])
	var after_d1_view: Dictionary = presenter.build_player_view(case_def, session).get("view", {})
	_check((after_d1_view.get("claims", []) as Array).size() == statement_and_hypothesis_count + 1, "%s: proving D1 should reveal exactly one more claim (D1 itself)" % case_id)


func _test_player_view_hint_progression(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session = _new_session(case_id)
	var target_id: String = _role_id(case_def, "claims", "credential_misused")
	var question_id: String = _role_id(case_def, "questions", "owner_involvement")

	var result: Dictionary = presenter.build_player_view(case_def, session)
	var question_handle: String = _handle_for(result.get("handle_map", {}), question_id)
	_check(question_handle != "", "%s: the owner_involvement question should have a handle" % case_id)
	var hint_entry: Dictionary = _find_hint_by_question_handle(result.get("view", {}), question_handle)
	_check(not hint_entry.is_empty(), "%s: a hint entry should exist for the owner_involvement question" % case_id)
	_check((hint_entry.get("levels_revealed", []) as Array).is_empty(), "%s: no hint level should be revealed yet" % case_id)
	_check(hint_entry.get("can_reveal_more") == true, "%s: more hint levels should be available" % case_id)

	evaluator.request_hint(case_def, session, target_id)
	var result2: Dictionary = presenter.build_player_view(case_def, session)
	var hint_entry2: Dictionary = _find_hint_by_question_handle(result2.get("view", {}), question_handle)
	_check((hint_entry2.get("levels_revealed", []) as Array).size() == 1, "%s: requesting one hint should reveal exactly one level in the player view" % case_id)


func _test_author_view_is_unfiltered(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var session = _new_session(case_id)
	var errors: Array[String] = ["some error"]
	var warnings: Array[String] = ["some warning"]
	var author_view: Dictionary = presenter.build_author_view(case_def, session, errors, warnings)
	_check(author_view.get("case_id") == case_id, "%s: author view should carry the real case id" % case_id)
	_check((author_view.get("suspects", []) as Array).size() == (case_def.get("suspects", []) as Array).size(), "%s: author view should list every suspect" % case_id)
	for suspect in author_view.get("suspects", []):
		_check(str(suspect.get("id", "")) != "", "%s: author suspect entries must carry the real id" % case_id)
	_check(author_view.get("ground_truth", {}).get("culprit") == case_def.get("ground_truth", {}).get("culprit"), "%s: author view must expose ground truth" % case_id)
	_check(author_view.get("session") == session.to_dict(), "%s: author view should embed the session's own to_dict()" % case_id)
	_check(author_view.get("validation_errors") == errors, "%s: author view should pass validation errors through unchanged" % case_id)
	_check(author_view.get("validation_warnings") == warnings, "%s: author view should pass validation warnings through unchanged" % case_id)


## The real X/Y/Z cases have zero gated evidence (Milestone 1.9.1); the
## fixture still has one (e_followup, gated behind ded_misused) so the
## "locked evidence must be entirely absent" rule stays covered.
func _test_player_view_hides_gated_evidence() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var session = _new_session("fx_case")

	var before: Dictionary = presenter.build_player_view(case_def, session)
	_check(not (before.get("handle_map", {}) as Dictionary).values().has("e_followup"), "gated evidence must be entirely absent before its unlock deduction is proven")
	var before_count: int = (before.get("view", {}).get("evidence", []) as Array).size()

	evaluator.commit_attempt(case_def, session, "ded_misused", "supports", ["e_log", "e_away", "e_travel"])
	var after: Dictionary = presenter.build_player_view(case_def, session)
	_check((after.get("handle_map", {}) as Dictionary).values().has("e_followup"), "previously gated evidence should appear once its unlock deduction is proven")
	_check((after.get("view", {}).get("evidence", []) as Array).size() == before_count + 1, "exactly one more evidence item should become visible")


# ---------------------------------------------------------------------------
# Local helpers

func _role_id(case_def: Dictionary, section: String, role: String) -> String:
	for entry in case_def.get(section, []):
		if entry.get("structural_role", "") == role:
			return entry.get("id", "")
	_failures.append('%s has no %s with structural_role "%s"' % [case_def.get("id", ""), section, role])
	return ""


func _handle_for(handle_map: Dictionary, domain_id: String) -> String:
	for handle in handle_map:
		if handle_map[handle] == domain_id:
			return handle
	return ""


func _find_hint_by_question_handle(view: Dictionary, question_handle: String) -> Dictionary:
	for hint in view.get("hints", []):
		if hint.get("question_handle", "") == question_handle:
			return hint
	return {}
