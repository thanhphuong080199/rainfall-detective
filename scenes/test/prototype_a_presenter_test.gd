extends SceneTree
## Focused tests for PrototypeAPresenter (Milestone 1.11 — see
## docs/prototype-a.md): the player view's exact allow-listed key structure,
## a content-level spoiler sweep against the real X/Y/Z prototype_a data
## (no domain id/structural role/veracity/required-optional-before-resolution
## ever reaches it), round-scoping (no future-round text), evidence text
## gated on "opened", hint progression, and the feedback-category mapping for
## every evaluator outcome. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_a_presenter_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]

var content_db: Node
var presenter: Variant
var controller_script: Variant
var evaluator: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame

	presenter = load("res://scripts/deduction/prototype_a_presenter.gd")
	controller_script = load("res://scripts/deduction/prototype_a_controller.gd")
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeAPresenter — focused tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		_check(not case_def.is_empty(), "%s should load through ContentDB" % case_id)
		_test_player_view_shape(case_def)
		_test_player_view_spoiler_safety(case_def)
		_test_round_scoping_hides_future_round(case_def)
		# Milestone 1.14 — resolution policy (docs/resolution-policy.md).
		_test_resolution_status_visible_and_localized(case_def)
		_test_assistance_absent_until_acknowledged(case_def)
		_test_partner_content_hidden_until_used(case_def)
		_test_run_result_does_not_leak_into_fresh_round(case_def)

	_test_outcome_hidden_before_resolution_revealed_after()
	_test_evidence_text_gated_on_opened()
	_test_hint_progression_in_view()
	_test_feedback_mapping_all_categories()
	_test_feedback_resolution_mapping()
	_test_completion_lines_localized()
	_test_stats_are_numeric_only()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_controller(case_def: Dictionary):
	var controller = controller_script.new()
	controller.start(case_def)
	return controller


## Every domain id anywhere in `case_def` (suspects, evidence, claims, proof
## sets) — the exact vocabulary a spoiler-safe view must never contain.
func _all_domain_ids(case_def: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for section in ["suspects", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			ids.append(str(entry.get("id", "")))
	for claim in case_def.get("claims", []):
		for proof_set in claim.get("proof_sets", []):
			ids.append(str(proof_set.get("id", "")))
	return ids


func _all_structural_roles(case_def: Dictionary) -> Array[String]:
	var roles: Array[String] = []
	for section in ["suspects", "evidence", "claims"]:
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
	var controller = _new_controller(case_def)
	var result: Dictionary = presenter.build_player_view(case_def, controller)
	var view: Dictionary = result.get("view", {})
	_assert_keys_exactly(view, [
		"non_canon", "case_title", "case_description", "suspects", "round_index", "round_count", "completed",
		"current_statement_handle", "statements", "evidence", "selected_evidence_handle", "hint", "resolution_status",
		"stats", "completion_text", "completion_lines",
	], "%s: player view" % case_id)
	_assert_keys_exactly(view.get("resolution_status", {}), RESOLUTION_STATUS_KEYS, "%s: resolution status" % case_id)
	_check((view.get("completion_lines", []) as Array).is_empty(), "%s: completion_lines must be empty before completion" % case_id)
	_check(view.get("non_canon") == true, "%s: the player view must surface the non-canon status" % case_id)
	_check(view.get("completed") == false, "%s: a fresh run must not be completed" % case_id)
	_check(view.get("completion_text") == "", "%s: completion_text must be empty before the prototype completes" % case_id)
	for suspect in view.get("suspects", []):
		_assert_keys_exactly(suspect, ["handle", "name"], "%s: player suspect entry" % case_id)
	for statement in view.get("statements", []):
		_assert_keys_exactly(statement, ["handle", "text", "speaker", "resolved", "outcome"], "%s: player statement entry" % case_id)
	for evidence in view.get("evidence", []):
		_assert_keys_exactly(evidence, ["handle", "name", "opened", "text", "selected"], "%s: player evidence entry" % case_id)
	if not (view.get("hint", {}) as Dictionary).is_empty():
		_assert_keys_exactly(view.get("hint", {}), ["handle", "levels_revealed", "total_levels", "can_reveal_more"], "%s: player hint entry" % case_id)
	_assert_keys_exactly(view.get("stats", {}), ["elapsed_ms", "submissions", "incorrect", "optional_found", "hints_used", "assistance_used", "partner_resolutions"], "%s: player stats" % case_id)


## Content-level sweep after realistic play (one wrong attempt, one correct
## required refutation, one hint revealed, one evidence opened) — no domain
## id, structural role, or raw veracity value may appear anywhere in the
## serialized view, and no banned key name may appear anywhere in its
## structure.
func _test_player_view_spoiler_safety(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var pool: Array = controller.get_evidence_pool_ids()
	controller.open_evidence(pool[0])
	controller.select_evidence(pool[1])
	controller.present_evidence()  # almost certainly wrong; that's fine, it's still real play
	var required_id: String = str((case_def.get("prototype_a", {}).get("rounds", [])[0] as Dictionary).get("required_refutations", [])[0])
	controller.reveal_next_hint(required_id)

	var result: Dictionary = presenter.build_player_view(case_def, controller)
	var view: Dictionary = result.get("view", {})
	var serialized: String = JSON.stringify(view)

	for domain_id in _all_domain_ids(case_def):
		_check(not serialized.contains(domain_id), "%s: player view must never contain the raw domain id \"%s\"" % [case_id, domain_id])
	for role in _all_structural_roles(case_def):
		_check(not serialized.contains(role), "%s: player view must never contain the structural role \"%s\"" % [case_id, role])
	for veracity in _all_veracity_values(case_def):
		if veracity == "true" or veracity == "false":
			continue
		_check(not serialized.contains(veracity), "%s: player view must never contain the raw veracity value \"%s\"" % [case_id, veracity])
	for domain_id in result.get("handle_map", {}).values():
		_check(not serialized.contains(str(domain_id)), "%s: player view must never contain a handle_map target id (\"%s\")" % [case_id, domain_id])

	var all_keys: Dictionary = {}
	_collect_all_keys(view, all_keys)
	for banned_key in ["id", "veracity", "proof_sets", "compatible", "structural_role", "required_refutations", "optional_refutations", "unlock_requires", "ground_truth", "source", "certainty", "misleading", "lie_motive", "speaker_id"]:
		_check(not all_keys.has(banned_key), '%s: player view must never carry a "%s" field anywhere in its structure' % [case_id, banned_key])

	_check(not serialized.contains(str(case_def.get("ground_truth", {}).get("culprit", "IMPOSSIBLE"))), "%s: the culprit id must never appear in the Prototype A player view" % case_id)


## Only the CURRENT round's statements ever appear — round 2's content must
## be completely absent while round 1 is active.
func _test_round_scoping_hides_future_round(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var round2_statement_id: String = str((case_def.get("prototype_a", {}).get("rounds", [])[1] as Dictionary).get("statements", [])[0])
	var round2_claim: Dictionary = evaluator.find_claim(case_def, round2_statement_id)
	var round2_text: String = String(TranslationServer.translate(round2_claim.get("text", "")))

	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((view.get("statements", []) as Array).size() == (case_def.get("prototype_a", {}).get("rounds", [])[0] as Dictionary).get("statements", []).size(), "%s: only round 1's statements should be visible initially" % case_id)
	_check(round2_text != "" and not JSON.stringify(view).contains(round2_text), "%s: round 2's statement text must not leak while round 1 is active" % case_id)


func _test_outcome_hidden_before_resolution_revealed_after() -> void:
	var controller = _new_controller(fixtures.prototype_a_case())
	controller.next_statement()  # st_required1
	var before: Dictionary = presenter.build_player_view(fixtures.prototype_a_case(), controller).get("view", {})
	var before_statement: Dictionary = _find_by_handle_field(before.get("statements", []), "handle", before.get("current_statement_handle", ""))
	_check(before_statement.get("resolved") == false and before_statement.get("outcome") == "", "the required/optional classification must be invisible before resolution")

	controller.select_evidence("e_b")
	controller.present_evidence()
	var after: Dictionary = presenter.build_player_view(fixtures.prototype_a_case(), controller).get("view", {})
	var after_statement: Dictionary = _find_by_handle_field(after.get("statements", []), "handle", after.get("current_statement_handle", ""))
	_check(after_statement.get("resolved") == true and after_statement.get("outcome") == "required", "the outcome should reveal \"required\" only once the session has actually resolved it")


func _test_evidence_text_gated_on_opened() -> void:
	var case_def: Dictionary = fixtures.prototype_a_case()
	var controller = _new_controller(case_def)
	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	for evidence in view.get("evidence", []):
		_check(evidence.get("opened") == false and evidence.get("text") == "", "unopened evidence must show no text yet")

	controller.open_evidence("e_a")
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	var opened_count := 0
	for evidence in after.get("evidence", []):
		if evidence.get("opened", false):
			opened_count += 1
			_check(evidence.get("text", "") != "", "an opened evidence item must show its text")
	_check(opened_count == 1, "exactly one evidence item should be opened")


func _test_hint_progression_in_view() -> void:
	var case_def: Dictionary = fixtures.prototype_a_case()
	var controller = _new_controller(case_def)
	controller.next_statement()  # st_required1, which HAS a ladder
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not (before.get("hint", {}) as Dictionary).is_empty(), "a required refutation's hint entry should be present")
	_check((before.get("hint", {}).get("levels_revealed", []) as Array).is_empty(), "no hint level should be revealed yet")
	_check(before.get("hint", {}).get("can_reveal_more") == true, "more levels should be available")

	controller.reveal_next_hint("st_required1")
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((after.get("hint", {}).get("levels_revealed", []) as Array).size() == 1, "revealing one hint should show exactly one level")

	controller.previous_statement()  # st_true, which has NO ladder
	var no_ladder_view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((no_ladder_view.get("hint", {}) as Dictionary).is_empty(), "a statement with no hint ladder must show an empty hint entry")


func _test_feedback_mapping_all_categories() -> void:
	var case_def: Dictionary = fixtures.prototype_a_case()
	var required_feedback: Dictionary = presenter.build_feedback(case_def, {"category": "valid_refutation", "claim_id": "st_required1", "outcome": "required"})
	_check(required_feedback.get("success") == true and required_feedback.get("optional") == false, "a required refutation should map to success, not optional")
	_check(required_feedback.get("explanation") != "" and required_feedback.get("witness_response") != "", "a required refutation should surface the round's authored explanation and witness response")

	var optional_feedback: Dictionary = presenter.build_feedback(case_def, {"category": "valid_refutation", "claim_id": "st_optional", "outcome": "optional"})
	_check(optional_feedback.get("success") == true and optional_feedback.get("optional") == true, "an optional refutation should map to success AND optional")
	_check(optional_feedback.get("explanation") != "", "an optional refutation should also surface its authored explanation")

	for entry in [
		["irrelevant_evidence", "UI_PROTOTYPE_A_FEEDBACK_IRRELEVANT"],
		["insufficient_evidence", "UI_PROTOTYPE_A_FEEDBACK_INSUFFICIENT"],
		["compatible_not_proof", "UI_PROTOTYPE_A_FEEDBACK_COMPATIBLE"],
		["invalid_input", "UI_PROTOTYPE_A_FEEDBACK_INVALID"],
	]:
		var feedback: Dictionary = presenter.build_feedback(case_def, {"category": entry[0], "claim_id": "st_required1", "outcome": "unsuccessful"})
		_check(feedback.get("success") == false, "%s must never be reported as success" % entry[0])
		_check(feedback.get("explanation") == String(TranslationServer.translate(entry[1])), "%s should map to the generic %s message, got \"%s\"" % [entry[0], entry[1], feedback.get("explanation")])
		_check(feedback.get("witness_response") == "", "%s must never surface a witness response" % entry[0])


func _test_stats_are_numeric_only() -> void:
	var controller = _new_controller(fixtures.prototype_a_case())
	controller.select_statement(1)
	controller.select_evidence("e_noise")
	controller.present_evidence()
	var stats: Dictionary = controller.get_stats()
	for key in stats:
		_check(typeof(stats[key]) == TYPE_INT or typeof(stats[key]) == TYPE_FLOAT, "stats.%s must be numeric, never text that could leak content" % key)


func _find_by_handle_field(entries: Array, field: String, value: String) -> Dictionary:
	for entry in entries:
		if entry.get(field, "") == value:
			return entry
	return {}


# ---------------------------------------------------------------------------
# Milestone 1.14 — resolution policy

const RESOLUTION_STATUS_KEYS := [
	"current_status_text", "run_result_text", "run_result_label", "standard_attempts_remaining", "standard_attempts_total", "assisted_attempts_remaining",
	"assisted_attempts_total", "can_submit", "assistance_required", "assistance_active", "partner_available",
	"resolved_by_partner", "hint_notice",
]
## Internal ids that must never reach a player view as a raw string value.
const RAW_POLICY_IDS := [
	"independent", "guided", "assisted", "standard", "assistance_required", "partner_available", "resolved",
	"player", "partner", "failed_commit", "successful_commit", "submission_locked", "duplicate_failed_attempt",
	"valid_refutation", "irrelevant_evidence", "insufficient_evidence", "compatible_not_proof", "invalid_input",
]


func _collect_string_values(value: Variant, out: Array) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary):
			_collect_string_values((value as Dictionary)[key], out)
	elif typeof(value) == TYPE_ARRAY:
		for entry in (value as Array):
			_collect_string_values(entry, out)
	elif typeof(value) == TYPE_STRING:
		out.append(value)


## The round-1 required statement's index plus every pool item that does NOT
## refute it — five distinct, genuinely failing presentations for real X/Y/Z.
func _round_1_failure_plan(case_def: Dictionary, controller) -> Dictionary:
	var pa_round: Dictionary = case_def.get("prototype_a", {}).get("rounds", [])[0]
	var required_id: String = str(pa_round.get("required_refutations", [])[0])
	var accepted: Array = []
	for proof_set in evaluator.find_claim(case_def, required_id).get("proof_sets", []):
		if proof_set.get("relation") == "refutes":
			accepted.append_array(proof_set.get("requires", []))
	var wrong: Array = controller.get_evidence_pool_ids().filter(func(id): return not accepted.has(id))
	return {"statement_index": (pa_round.get("statements", []) as Array).find(required_id), "required_id": required_id, "accepted": accepted, "wrong": wrong}


func _present(controller, statement_index: int, evidence_id: String) -> Dictionary:
	controller.select_statement(statement_index)
	controller.select_evidence(evidence_id)
	return controller.present_evidence()


func _test_resolution_status_visible_and_localized(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	TranslationServer.set_locale("en")
	var en_status: Dictionary = presenter.build_player_view(case_def, controller).get("view", {}).get("resolution_status", {})
	TranslationServer.set_locale("vi")
	var vi_status: Dictionary = presenter.build_player_view(case_def, controller).get("view", {}).get("resolution_status", {})
	_check(String(en_status.get("current_status_text", "")).contains("Credibility: 3/3") and not String(en_status.get("current_status_text", "")).contains("Independent"), "%s: the EN current-unit status should read credibility 3/3 and never mention the run result, got \"%s\"" % [case_id, en_status.get("current_status_text")])
	_check(String(en_status.get("run_result_text", "")).contains("Independent"), "%s: the EN run-result line should separately say Independent, got \"%s\"" % [case_id, en_status.get("run_result_text")])
	_check(String(vi_status.get("current_status_text", "")).contains("3/3") and vi_status.get("current_status_text") != en_status.get("current_status_text"), "%s: the VI status should be translated, got \"%s\"" % [case_id, vi_status.get("current_status_text")])
	_check(vi_status.get("run_result_text") != en_status.get("run_result_text"), "%s: the VI run-result line should be translated too" % case_id)
	_check(en_status.get("can_submit") == true and en_status.get("assistance_required") == false and en_status.get("partner_available") == false, "%s: a fresh status should allow presenting with nothing pending" % case_id)

	var plan: Dictionary = _round_1_failure_plan(case_def, controller)
	_present(controller, plan["statement_index"], plan["wrong"][0])
	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(view.get("resolution_status", {}).get("standard_attempts_remaining") == 2, "%s: one failure should show 2 credibility remaining" % case_id)
	var values: Array = []
	_collect_string_values(view, values)
	for raw_id in RAW_POLICY_IDS:
		_check(not values.has(raw_id), "%s: the player view must never carry the raw id \"%s\" as a value" % [case_id, raw_id])


## Before assistance is ACKNOWLEDGED, nothing that narrows the answer may
## reach the view: no assistance key, no focus statement, no category hint
## (the ladder's level-2 text), no correct evidence. After acknowledgement the
## block names the statement and category but never an accepted evidence item.
func _test_assistance_absent_until_acknowledged(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var plan: Dictionary = _round_1_failure_plan(case_def, controller)
	var ladder: Array = case_def.get("prototype_a", {}).get("rounds", [])[0].get("hint_ladders", {}).get(plan["required_id"], [])
	var category_hint: String = String(TranslationServer.translate(str(ladder[1])))
	var accepted_names: Array = plan["accepted"].map(func(id): return String(TranslationServer.translate(str(evaluator.find_evidence(case_def, id).get("name", "")))))

	for i in 3:
		var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
		_check(not before.has("assistance"), "%s: no assistance key after %d failure(s)" % [case_id, i])
		_check(not JSON.stringify(before).contains(category_hint), "%s: the assistance category hint must not leak after %d failure(s)" % [case_id, i])
		_present(controller, plan["statement_index"], plan["wrong"][i])

	var pending: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(pending.get("resolution_status", {}).get("assistance_required") == true, "%s: sanity — three failures require assistance" % case_id)
	_check(not pending.has("assistance") and not JSON.stringify(pending).contains(category_hint), "%s: assistance content must stay absent while assistance is merely offered" % case_id)

	controller.accept_assistance()
	var result: Dictionary = presenter.build_player_view(case_def, controller)
	var view: Dictionary = result.get("view", {})
	_check(view.has("assistance"), "%s: the assistance key must appear once acknowledged" % case_id)
	var assistance: Dictionary = view.get("assistance", {})
	_assert_keys_exactly(assistance, ["headline", "statement_handle", "focus", "category_hint"], "%s: assistance block" % case_id)
	_check(result.get("handle_map", {}).get(assistance.get("statement_handle", "")) == plan["required_id"], "%s: assistance should focus the unresolved required statement" % case_id)
	_check(assistance.get("category_hint") == category_hint, "%s: the category hint should reuse the authored ladder's level-2 text" % case_id)
	for name in accepted_names:
		_check(name != "" and not JSON.stringify(assistance).contains(name), "%s: assistance must never name the accepted evidence \"%s\"" % [case_id, name])
	_check(view.get("resolution_status", {}).get("assistance_active") == true and view.get("resolution_status", {}).get("can_submit") == true, "%s: acknowledged assistance should re-enable presenting" % case_id)


func _test_partner_content_hidden_until_used(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var plan: Dictionary = _round_1_failure_plan(case_def, controller)
	var partner_headline: String = String(TranslationServer.translate("UI_RESOLUTION_PARTNER_HEADLINE"))
	for i in 3:
		_present(controller, plan["statement_index"], plan["wrong"][i])
	controller.accept_assistance()
	var fifth: Dictionary = {}
	for i in range(3, 5):
		fifth = _present(controller, plan["statement_index"], plan["wrong"][i])
	var fifth_feedback: Dictionary = presenter.build_feedback(case_def, fifth)
	_check(fifth_feedback.get("partner") == false and fifth_feedback.get("partner_note") == "" and fifth_feedback.get("headline") != partner_headline, "%s: the partner solution must stay hidden while partner resolution is merely offered" % case_id)
	_check(String(fifth_feedback.get("resolution_notice", "")) == String(TranslationServer.translate("UI_RESOLUTION_NOTICE_PARTNER_AVAILABLE")), "%s: the fifth failure should explain that partner resolution is available" % case_id)
	var offered: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(offered.get("resolution_status", {}).get("partner_available") == true and offered.get("resolution_status", {}).get("can_submit") == false, "%s: the view should offer partner resolution with blind presenting closed" % case_id)

	var partner: Dictionary = controller.resolve_with_partner()
	var feedback: Dictionary = presenter.build_feedback(case_def, partner)
	_check(feedback.get("success") == true and feedback.get("partner") == true and feedback.get("headline") == partner_headline, "%s: partner resolution should be clearly labeled" % case_id)
	var evidence_name: String = String(TranslationServer.translate(str(evaluator.find_evidence(case_def, str(partner.get("evidence_id", ""))).get("name", ""))))
	_check(evidence_name != "" and String(feedback.get("partner_note", "")).contains(evidence_name), "%s: the partner note should name the evidence the partner presented" % case_id)
	_check(feedback.get("explanation") != "", "%s: partner resolution must still explain what contradicted the statement" % case_id)


## Milestone 1.14.1 (docs/resolution-policy.md, "Local unit state vs. run
## result"): a round resolved in Assisted Mode — even via partner resolution —
## must never leak into the NEXT round's own presentation. Round 2 must start
## with a completely fresh local budget and no assistance content, while the
## run result stays Assisted, reported on its own separate, explicitly-worded
## line — never merged into round 2's own status text.
func _test_run_result_does_not_leak_into_fresh_round(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	TranslationServer.set_locale("en")
	var controller = _new_controller(case_def)
	var plan: Dictionary = _round_1_failure_plan(case_def, controller)
	for i in 3:
		_present(controller, plan["statement_index"], plan["wrong"][i])
	controller.accept_assistance()
	for i in range(3, 5):
		_present(controller, plan["statement_index"], plan["wrong"][i])
	var partner: Dictionary = controller.resolve_with_partner()
	_check(partner.get("partner", false) == true, "%s: sanity — partner resolution should finish round 1" % case_id)
	controller.acknowledge_feedback()
	_check(controller.get_round_index() == 1, "%s: sanity — round 2 should now be active" % case_id)

	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	var status: Dictionary = view.get("resolution_status", {})
	_check(String(status.get("current_status_text", "")) == "Credibility: 3/3", "%s: round 2 must start with a completely fresh local budget, got \"%s\"" % [case_id, status.get("current_status_text")])
	_check(status.get("assistance_active") == false and status.get("assistance_required") == false and status.get("can_submit") == true and status.get("partner_available") == false, "%s: round 2 must not inherit round 1's active assistance, locked submission or offered partner resolution" % case_id)
	_check(not view.has("assistance"), "%s: round 2 must not carry any assistance content until its OWN third failure" % case_id)
	_check(String(status.get("run_result_text", "")).contains("Assisted") and String(status.get("run_result_text", "")).to_lower().contains("earlier"), "%s: the run result must still read Assisted, explicitly noting it was reached in an earlier challenge, got \"%s\"" % [case_id, status.get("run_result_text")])


func _test_feedback_resolution_mapping() -> void:
	var case_def: Dictionary = fixtures.prototype_a_case()
	var controller = _new_controller(case_def)
	var first: Dictionary = _present(controller, 1, "e_noise")
	var first_feedback: Dictionary = presenter.build_feedback(case_def, first)
	_check(first_feedback.get("rebuttal") != "", "a counted failure should produce a rebuttal")
	_check(String(first_feedback.get("resolution_notice", "")).contains("2/3"), "a counted failure's notice should report the remaining credibility, got \"%s\"" % first_feedback.get("resolution_notice"))
	_check(String(first_feedback.get("resolution_notice", "")).contains(String(TranslationServer.translate("UI_RESOLUTION_TIER_GUIDED"))), "a failure that changes the tier should say so explicitly")
	_check(first_feedback.get("witness_response") == "" and first_feedback.get("partner_note") == "", "a failure must never surface authored witness/partner text")

	var duplicate_feedback: Dictionary = presenter.build_feedback(case_def, _present(controller, 1, "e_noise"))
	_check(duplicate_feedback.get("explanation") == String(TranslationServer.translate("UI_PROTOTYPE_A_FEEDBACK_DUPLICATE")), "a duplicate presentation should explain that nothing was spent")
	_check(duplicate_feedback.get("rebuttal") == "" and duplicate_feedback.get("resolution_notice") == "", "a duplicate costs nothing, so it gets no rebuttal and no credibility notice")

	_present(controller, 1, "e_a")
	var third_feedback: Dictionary = presenter.build_feedback(case_def, _present(controller, 1, "e_c"))
	_check(String(third_feedback.get("resolution_notice", "")).contains(String(TranslationServer.translate("UI_RESOLUTION_NOTICE_ASSISTANCE_REQUIRED"))), "the third failure's notice should require assistance")
	var locked_feedback: Dictionary = presenter.build_feedback(case_def, _present(controller, 1, "e_b"))
	_check(locked_feedback.get("explanation") == String(TranslationServer.translate("UI_RESOLUTION_SUBMISSION_LOCKED")) and locked_feedback.get("success") == false, "a locked presentation should explain the lock, even with the right evidence")


func _test_completion_lines_localized() -> void:
	var case_def: Dictionary = fixtures.prototype_a_case()
	var controller = _new_controller(case_def)
	_present(controller, 1, "e_b")
	controller.acknowledge_feedback()
	_present(controller, 1, "e_c")
	controller.acknowledge_feedback()
	TranslationServer.set_locale("en")
	var en_view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	TranslationServer.set_locale("vi")
	var vi_view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	var en_lines: Array = en_view.get("completion_lines", [])
	var vi_lines: Array = vi_view.get("completion_lines", [])
	_check(en_lines.size() == 8, "the completion summary should show 7 shared resolution lines + optional contradictions, got %s" % [en_lines])
	_check(en_lines.has("Resolution tier: Independent") and en_lines.has("Partner resolution used: No") and en_lines.has("Assistance used: No"), "the EN summary should report tier/assistance/partner in words, got %s" % [en_lines])
	_check(en_lines.has("Formal commits: 2") and en_lines.has("Failed formal commits: 0"), "the EN summary should report formal commits, got %s" % [en_lines])
	_check(vi_lines.size() == en_lines.size() and vi_lines != en_lines, "the VI summary should be fully translated")
