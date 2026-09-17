extends SceneTree
## Focused tests for PrototypeCPresenter (Milestone 1.13 — see
## docs/prototype-c.md; resolution policy since Milestone 1.14 — see
## docs/resolution-policy.md): the player view's exact allow-listed key
## structure, a content-level spoiler sweep against the real X/Y/Z
## prototype_c data (no domain id/structural role/raw constraint field ever
## reaches it), fact text gated on "opened", the disputed claim absent before
## acceptance and present (with a neutral verdict + supporting-fact form)
## after, the final explanation absent until the claim is resolved,
## progressive violation feedback (category, then one authored fact), the
## resolution status (localized, no raw ids), assistance and partner content
## gated by the policy, the claim feedback levels, and the localized
## completion summary. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_c_presenter_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]
const BASE_VIEW_KEYS := [
	"non_canon", "case_title", "case_description", "objective", "completed", "accepted",
	"events", "time_slots", "unplaced_count", "can_submit", "can_resubmit", "can_check", "facts", "hint",
	"resolution_status", "stats", "completion_text", "completion_lines",
]
const RESOLUTION_STATUS_KEYS := [
	"current_status_text", "run_result_text", "run_result_label", "standard_attempts_remaining", "standard_attempts_total", "assisted_attempts_remaining",
	"assisted_attempts_total", "can_submit", "assistance_required", "assistance_active", "partner_available",
	"resolved_by_partner", "hint_notice",
]
const RAW_IDS := [
	"independent", "guided", "assisted", "standard", "assistance_required", "partner_available", "resolved",
	"player", "partner", "fits", "impossible", "anchor", "order", "overlap", "travel", "category", "fact",
	"timeline_consistent", "timeline_inconsistent", "invalid_input", "fixed_time", "no_overlap", "travel_time", "before",
]

var content_db: Node
var presenter: Variant
var controller_script: Variant
var evaluator: Variant
var timeline: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame

	presenter = load("res://scripts/deduction/prototype_c_presenter.gd")
	controller_script = load("res://scripts/deduction/prototype_c_controller.gd")
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	timeline = load("res://scripts/deduction/timeline_evaluator.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeCPresenter — focused tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		_check(not case_def.is_empty(), "%s should load through ContentDB" % case_id)
		_test_player_view_shape(case_def)
		_test_player_view_spoiler_safety_before_acceptance(case_def)
		_test_accepted_view_spoiler_safety(case_def)
		_test_progressive_feedback_assistance_and_partner(case_def)

	_test_claim_absent_before_accepted_present_after()
	_test_resolution_absent_until_claim_resolved()
	_test_fact_text_gated_on_opened()
	_test_hint_progression_in_view()
	_test_violation_feedback_mapping()
	_test_claim_feedback_mapping()
	_test_resolution_status_localized()
	_test_completion_lines_localized()
	_test_presenter_never_reads_constraint_type_or_required()

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


func _all_domain_ids(case_def: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for section in ["suspects", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			ids.append(str(entry.get("id", "")))
	for event in case_def.get("timeline", {}).get("events", []):
		ids.append(str(event.get("id", "")))
	for constraint in case_def.get("timeline", {}).get("constraints", []):
		ids.append(str(constraint.get("id", "")))
	return ids


func _all_structural_roles(case_def: Dictionary) -> Array[String]:
	var roles: Array[String] = []
	for section in ["suspects", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			var role: String = str(entry.get("structural_role", ""))
			if role != "" and not roles.has(role):
				roles.append(role)
	for event in case_def.get("timeline", {}).get("events", []):
		var role: String = str(event.get("structural_role", ""))
		if role != "" and not roles.has(role):
			roles.append(role)
	return roles


func _collect_all_keys(value: Variant, out: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary):
			out[str(key)] = true
			_collect_all_keys((value as Dictionary)[key], out)
	elif typeof(value) == TYPE_ARRAY:
		for entry in (value as Array):
			_collect_all_keys(entry, out)


func _collect_string_values(value: Variant, out: Array) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary):
			_collect_string_values((value as Dictionary)[key], out)
	elif typeof(value) == TYPE_ARRAY:
		for entry in (value as Array):
			_collect_string_values(entry, out)
	elif typeof(value) == TYPE_STRING:
		out.append(value)


func _assert_keys_exactly(dict: Dictionary, allowed: Array, context: String) -> void:
	var actual: Array = dict.keys()
	actual.sort()
	var expected: Array = allowed.duplicate()
	expected.sort()
	_check(actual == expected, "%s should have exactly the keys %s, got %s" % [context, expected, actual])


func _place_all_at(controller, slot: String) -> void:
	for event_id in controller.get_all_event_ids():
		if not controller.is_fixed(event_id):
			controller.place_event(event_id, slot)


func _place_solution(case_def: Dictionary, controller) -> void:
	var solution: Dictionary = case_def.get("ground_truth", {}).get("solution_timeline", {})
	for event_id in controller.get_all_event_ids():
		if not controller.is_fixed(event_id):
			controller.place_event(event_id, str(solution.get(event_id, "")))


func _fact_text(case_def: Dictionary, constraint_id: String) -> String:
	return String(TranslationServer.translate(str(case_def.get("prototype_c", {}).get("visible_constraint_facts", {}).get(constraint_id, ""))))


func _test_player_view_shape(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_assert_keys_exactly(view, BASE_VIEW_KEYS, "%s: player view before acceptance" % case_id)
	_assert_keys_exactly(view.get("resolution_status", {}), RESOLUTION_STATUS_KEYS, "%s: resolution status" % case_id)
	_check(view.get("non_canon") == true and view.get("completed") == false and view.get("accepted") == false, "%s: a fresh non-canon run" % case_id)
	_check(view.get("completion_text") == "" and (view.get("completion_lines", []) as Array).is_empty(), "%s: no completion content before completion" % case_id)
	_check((view.get("events", []) as Array).size() == 7, "%s: all seven timeline events are surfaced" % case_id)
	for event in view.get("events", []):
		_assert_keys_exactly(event, ["handle", "label", "duration_minutes", "fixed", "placement", "selected"], "%s: event entry" % case_id)
	for fact in view.get("facts", []):
		_assert_keys_exactly(fact, ["handle", "opened", "text"], "%s: fact entry" % case_id)
	_assert_keys_exactly(view.get("hint", {}), ["levels_revealed", "total_levels", "can_reveal_more"], "%s: hint entry" % case_id)
	_assert_keys_exactly(view.get("stats", {}), ["elapsed_ms", "submissions", "failed", "moves", "facts_opened", "hints_used", "claim_attempts", "assistance_used", "partner_resolutions"], "%s: stats" % case_id)
	for key in view.get("stats", {}):
		_check(typeof(view["stats"][key]) == TYPE_INT, "%s: stats.%s must be numeric" % [case_id, key])


func _test_player_view_spoiler_safety_before_acceptance(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	controller.open_fact(controller.get_fact_ids()[0])
	_place_all_at(controller, controller.get_time_slots()[0])
	controller.submit_timeline()
	controller.reveal_next_hint()
	var result: Dictionary = presenter.build_player_view(case_def, controller)
	_check(result.get("view", {}).get("accepted", true) == false, "%s: sanity — dumping every event on one slot is rejected" % case_id)
	_sweep_spoiler_safety(case_def, result, case_id)


func _test_accepted_view_spoiler_safety(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	_place_solution(case_def, controller)
	_check(controller.submit_timeline().get("accepted", false) == true, "%s: the authored solution should be accepted" % case_id)
	var result: Dictionary = presenter.build_player_view(case_def, controller)
	var claim: Dictionary = result.get("view", {}).get("claim", {})
	_check(not claim.is_empty(), "%s: the accepted view includes the claim" % case_id)
	_assert_keys_exactly(claim, ["handle", "statement_text", "fits_selected", "impossible_selected", "justification_options", "can_submit"], "%s: claim block" % case_id)
	_check((claim.get("justification_options", []) as Array).size() == controller.get_fact_ids().size(), "%s: every visible fact is offered as a possible justification" % case_id)
	for option in claim.get("justification_options", []):
		_assert_keys_exactly(option, ["handle", "text", "selected"], "%s: justification option" % case_id)
		_check(String(option.get("text", "")) != "", "%s: every option shows its fact text" % case_id)
	_check(claim.get("fits_selected") == false and claim.get("impossible_selected") == false and claim.get("can_submit") == false, "%s: the claim form starts neutral and not submittable" % case_id)
	_sweep_spoiler_safety(case_def, result, case_id)


func _sweep_spoiler_safety(case_def: Dictionary, result: Dictionary, case_id: String) -> void:
	var view: Dictionary = result.get("view", {})
	var serialized: String = JSON.stringify(view)
	for domain_id in _all_domain_ids(case_def):
		_check(not serialized.contains(domain_id), "%s: player view must never contain the raw domain id \"%s\"" % [case_id, domain_id])
	for role in _all_structural_roles(case_def):
		_check(not serialized.contains(role), "%s: player view must never contain the structural role \"%s\"" % [case_id, role])
	var all_keys: Dictionary = {}
	_collect_all_keys(view, all_keys)
	for banned_key in ["id", "veracity", "proof_sets", "compatible", "structural_role", "type", "required", "unlock_requires", "ground_truth", "source", "certainty", "misleading", "solution_timeline", "constraint_ref", "supporting_constraint_refs", "correct", "verdict_correct", "justification_valid", "constraint_id"]:
		_check(not all_keys.has(banned_key), '%s: player view must never carry a "%s" field anywhere in its structure' % [case_id, banned_key])
	var values: Array = []
	_collect_string_values(view, values)
	for raw_id in RAW_IDS:
		_check(not values.has(raw_id), "%s: the player view must never carry the raw id \"%s\" as a value" % [case_id, raw_id])


func _test_progressive_feedback_assistance_and_partner(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var slots: Array = controller.get_time_slots()
	var fact_texts: Array = controller.get_fact_ids().map(func(id): return _fact_text(case_def, id))
	var category_texts: Array = ["UI_PROTOTYPE_C_CATEGORY_ANCHOR", "UI_PROTOTYPE_C_CATEGORY_WINDOW", "UI_PROTOTYPE_C_CATEGORY_ORDER", "UI_PROTOTYPE_C_CATEGORY_OVERLAP", "UI_PROTOTYPE_C_CATEGORY_TRAVEL"].map(func(key): return String(TranslationServer.translate(key)))
	var ladder_4: String = String(TranslationServer.translate(str(case_def.get("prototype_c", {}).get("hint_ladder", [])[3])))

	var feedbacks: Array = []
	for i in 3:
		_place_all_at(controller, slots[i])
		feedbacks.append(presenter.build_violation_feedback(case_def, controller, controller.submit_timeline()))
		var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
		_check(not view.has("assistance") and not JSON.stringify(view).contains(ladder_4), "%s: no assistance content after %d failure(s)" % [case_id, i + 1])

	_check((feedbacks[0].get("violations", []) as Array).is_empty(), "%s: the first failure lists no fact at all" % case_id)
	_check(category_texts.any(func(text): return String(feedbacks[0].get("message", "")).contains(text)), "%s: the first failure names a broad category, got \"%s\"" % [case_id, feedbacks[0].get("message")])
	_check(not fact_texts.any(func(text): return String(feedbacks[0].get("message", "")).contains(text)), "%s: the first failure's message must not quote a fact" % case_id)
	var second_violations: Array = feedbacks[1].get("violations", [])
	_check(second_violations.size() == 1, "%s: the second failure lists exactly one fact, got %s" % [case_id, second_violations])
	if second_violations.size() == 1:
		_check(fact_texts.has(second_violations[0].get("text")), "%s: the listed fact is the authored sentence verbatim — no computed correct time" % case_id)
		_check(not (second_violations[0].get("event_handles", []) as Array).is_empty(), "%s: the fact's involved events are identified for highlighting" % case_id)
	_check(String(feedbacks[2].get("resolution_notice", "")).contains(String(TranslationServer.translate("UI_RESOLUTION_NOTICE_ASSISTANCE_REQUIRED"))), "%s: the third failure requires assistance" % case_id)

	controller.accept_assistance()
	var assisted: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	var assistance: Dictionary = assisted.get("assistance", {})
	_assert_keys_exactly(assistance, ["headline", "text", "relationship", "event_handles"], "%s: timeline assistance" % case_id)
	_check(assistance.get("text") == ladder_4 and String(assistance.get("relationship", "")) != "" and not (assistance.get("event_handles", []) as Array).is_empty(), "%s: assistance names a critical relationship and reuses the ladder's level-4 text" % case_id)
	var solution: Dictionary = case_def.get("ground_truth", {}).get("solution_timeline", {})
	for event_id in solution:
		if not controller.is_fixed(event_id):
			_check(not String(assistance.get("relationship", "")).contains(str(solution[event_id])), "%s: assistance must never state a correct time" % case_id)

	var partner_headline: String = String(TranslationServer.translate("UI_PROTOTYPE_C_PARTNER_TIMELINE_NOTE"))
	var last: Dictionary = {}
	for i in range(3, 5):
		_place_all_at(controller, slots[i])
		last = presenter.build_violation_feedback(case_def, controller, controller.submit_timeline())
	_check(last.get("partner") == false and String(last.get("message", "")) != partner_headline, "%s: the partner timeline stays hidden while merely offered" % case_id)
	var partner: Dictionary = presenter.build_violation_feedback(case_def, controller, controller.resolve_with_partner())
	_check(partner.get("accepted") == true and partner.get("partner") == true and partner.get("message") == partner_headline, "%s: the partner timeline is clearly labeled" % case_id)
	_check(not (partner.get("violations", []) as Array).is_empty(), "%s: the partner explains which established facts now hold" % case_id)
	_check(timeline.evaluate(case_def, controller.get_placements()).get("category") == timeline.CONSISTENT, "%s: the partner timeline passes the real evaluator" % case_id)
	_check(presenter.build_player_view(case_def, controller).get("view", {}).has("claim") and not presenter.build_player_view(case_def, controller).get("view", {}).has("assistance"), "%s: the claim unit starts without carried-over assistance" % case_id)


func _test_claim_absent_before_accepted_present_after() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not before.has("claim") and not JSON.stringify(before).contains("st_lie"), "the claim key is ENTIRELY ABSENT before acceptance")
	controller.place_event("t_a", "09:00")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(after.has("claim") and String(after.get("claim", {}).get("statement_text", "")) != "", "the claim appears once the timeline is accepted")
	_check(after.get("claim_phase") == true and after.get("claim_resolved") == false, "the claim phase is open")
	controller.select_claim_answer(true)
	controller.select_claim_justification("c_b_window")
	var selected: Dictionary = presenter.build_player_view(case_def, controller)
	var claim: Dictionary = selected.get("view", {}).get("claim", {})
	_check(claim.get("impossible_selected") == true and claim.get("can_submit") == true, "the selected verdict and a chosen fact enable Submit Verdict")
	var chosen: Array = claim.get("justification_options", []).filter(func(o): return o.get("selected"))
	_check(chosen.size() == 1 and selected.get("handle_map", {}).get(chosen[0].get("handle")) == "c_b_window", "exactly the chosen fact is marked selected — nothing marks it correct")


func _test_resolution_absent_until_claim_resolved() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	controller.place_event("t_a", "09:00")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()
	controller.answer_claim(false, "c_b_window")
	_check(not presenter.build_player_view(case_def, controller).get("view", {}).has("resolution"), "a wrong claim answer must not reveal the resolution")
	controller.answer_claim(true, "c_b_after_fixed")
	var resolved: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_assert_keys_exactly(resolved.get("resolution", {}), ["explanation", "justification", "partner_note"], "resolution block")
	_check(String(resolved.get("resolution", {}).get("explanation", "")).contains("10:10"), "the explanation interpolates the player's OWN accepted time")
	_check(String(resolved.get("resolution", {}).get("justification", "")) != "" and resolved.get("resolution", {}).get("partner_note") == "", "the player's justification is shown; no partner note for a player solution")


func _test_fact_text_gated_on_opened() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	for fact in presenter.build_player_view(case_def, controller).get("view", {}).get("facts", []):
		_check(fact.get("opened") == false and fact.get("text") == "", "an unopened fact shows no text")
	controller.open_fact(controller.get_fact_ids()[0])
	var opened: Array = presenter.build_player_view(case_def, controller).get("view", {}).get("facts", []).filter(func(f): return f.get("opened"))
	_check(opened.size() == 1 and opened[0].get("text") != "", "exactly one opened fact shows its text")


func _test_hint_progression_in_view() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((before.get("hint", {}).get("levels_revealed", []) as Array).is_empty() and before.get("hint", {}).get("can_reveal_more") == true, "no hint revealed yet")
	controller.reveal_next_hint()
	_check((presenter.build_player_view(case_def, controller).get("view", {}).get("hint", {}).get("levels_revealed", []) as Array).size() == 1, "one reveal shows one level")


func _test_violation_feedback_mapping() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	controller.place_event("t_a", "10:10")
	controller.place_event("t_b", "10:10")
	var first: Dictionary = presenter.build_violation_feedback(case_def, controller, controller.submit_timeline())
	_assert_keys_exactly(first, ["accepted", "blocked_duplicate", "invalid", "partner", "violations", "message", "resolution_notice"], "violation feedback")
	_check(first.get("accepted") == false and first.get("invalid") == false and (first.get("violations", []) as Array).is_empty(), "the first rejection lists no fact")
	_check(first.get("message") == String(TranslationServer.translate("UI_PROTOTYPE_C_FEEDBACK_CATEGORY")) % String(TranslationServer.translate("UI_PROTOTYPE_C_CATEGORY_WINDOW")), "the first rejection names only the window category, got \"%s\"" % first.get("message"))
	_check(String(first.get("resolution_notice", "")).contains("2/3"), "the first rejection reports the remaining checks")

	controller.place_event("t_a", "10:25")
	var second: Dictionary = presenter.build_violation_feedback(case_def, controller, controller.submit_timeline())
	_check((second.get("violations", []) as Array).size() == 1 and second.get("message") == String(TranslationServer.translate("UI_PROTOTYPE_C_FEEDBACK_FACT")), "the second rejection lists exactly one fact")
	for violation in second.get("violations", []):
		_assert_keys_exactly(violation, ["text", "event_handles"], "violation entry")

	var invalid_result: Dictionary = {"category": timeline.INVALID_INPUT, "reason": "incomplete_selection", "violated_required": [], "violated_optional": [], "accepted": false, "blocked_duplicate": false}
	var invalid: Dictionary = presenter.build_violation_feedback(case_def, controller, invalid_result)
	_check(invalid.get("invalid") == true and invalid.get("message") == String(TranslationServer.translate("UI_PROTOTYPE_C_FEEDBACK_INVALID")), "an incomplete board gets the non-spoiling 'place every event' message")
	var locked: Dictionary = presenter.build_violation_feedback(case_def, controller, {"category": timeline.INVALID_INPUT, "reason": "submission_locked"})
	_check(locked.get("message") == String(TranslationServer.translate("UI_RESOLUTION_SUBMISSION_LOCKED")), "a locked check explains the lock")

	var accepted = _new_controller(case_def)
	accepted.place_event("t_a", "09:00")
	accepted.place_event("t_b", "10:10")
	var accepted_feedback: Dictionary = presenter.build_violation_feedback(case_def, accepted, accepted.submit_timeline())
	_check(accepted_feedback.get("accepted") == true and (accepted_feedback.get("violations", []) as Array).is_empty(), "an accepted timeline lists no violations")


func _test_claim_feedback_mapping() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	controller.place_event("t_a", "09:00")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()
	var missing: Dictionary = presenter.build_claim_feedback(case_def, controller, controller.answer_claim(true))
	_check(missing.get("guidance") == String(TranslationServer.translate("UI_PROTOTYPE_C_CLAIM_NEEDS_JUSTIFICATION")) and missing.get("resolution_notice") == "", "a verdict with no fact asks for the justification, at no cost")
	var first: Dictionary = presenter.build_claim_feedback(case_def, controller, controller.answer_claim(true, "c_a_window"))
	_check(first.get("correct") == false and first.get("guidance") == String(TranslationServer.translate("UI_PROTOTYPE_C_CLAIM_WRONG_FEEDBACK")), "the first wrong claim gets the generic nudge")
	var duplicate: Dictionary = presenter.build_claim_feedback(case_def, controller, controller.answer_claim(true, "c_a_window"))
	_check(duplicate.get("guidance") == String(TranslationServer.translate("UI_PROTOTYPE_C_CLAIM_DUPLICATE")), "a duplicate claim is refused at no cost")
	var second: Dictionary = presenter.build_claim_feedback(case_def, controller, controller.answer_claim(false, "c_b_window"))
	_check(second.get("guidance") == String(TranslationServer.translate("UI_PROTOTYPE_C_CLAIM_WRONG_VERDICT")), "a later wrong verdict says the verdict is off")
	var third: Dictionary = presenter.build_claim_feedback(case_def, controller, controller.answer_claim(false, "c_a_window"))
	_check(String(third.get("resolution_notice", "")).contains(String(TranslationServer.translate("UI_RESOLUTION_NOTICE_ASSISTANCE_REQUIRED"))), "the third wrong claim requires assistance")
	var other = _new_controller(case_def)
	other.place_event("t_a", "09:00")
	other.place_event("t_b", "10:10")
	other.submit_timeline()
	other.answer_claim(false, "c_a_window")
	var justification_off: Dictionary = presenter.build_claim_feedback(case_def, other, other.answer_claim(true, "c_a_window"))
	_check(justification_off.get("guidance") == String(TranslationServer.translate("UI_PROTOTYPE_C_CLAIM_WRONG_JUSTIFICATION")), "a later right verdict with an unrelated fact says the fact doesn't settle it")
	var right: Dictionary = presenter.build_claim_feedback(case_def, other, other.answer_claim(true, "c_b_window"))
	_check(right.get("correct") == true and right.get("guidance") == "", "a correct claim carries no guidance (the explanation is shown separately)")


func _test_resolution_status_localized() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	TranslationServer.set_locale("en")
	var en_status: Dictionary = presenter.build_player_view(case_def, controller).get("view", {}).get("resolution_status", {})
	TranslationServer.set_locale("vi")
	var vi_status: Dictionary = presenter.build_player_view(case_def, controller).get("view", {}).get("resolution_status", {})
	var en: String = String(en_status.get("current_status_text", ""))
	var vi: String = String(vi_status.get("current_status_text", ""))
	_check(en.contains("3/3") and not en.contains("Independent") and vi.contains("3/3") and vi != en, "the current-unit status is shown in words, never the run result, and translated: \"%s\" / \"%s\"" % [en, vi])
	_check(String(en_status.get("run_result_text", "")).contains("Independent"), "the EN run-result line separately says Independent, got \"%s\"" % en_status.get("run_result_text"))


func _test_completion_lines_localized() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	controller.place_event("t_a", "09:00")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()
	controller.answer_claim(true, "c_b_window")
	controller.acknowledge_claim()
	TranslationServer.set_locale("en")
	var en_lines: Array = presenter.build_player_view(case_def, controller).get("view", {}).get("completion_lines", [])
	TranslationServer.set_locale("vi")
	var vi_lines: Array = presenter.build_player_view(case_def, controller).get("view", {}).get("completion_lines", [])
	_check(en_lines.size() == 12, "the completion summary shows 7 shared lines + 5 timeline/claim lines, got %s" % [en_lines])
	_check(en_lines.has("Formal commits: 2") and en_lines.has("Resolution tier: Independent") and en_lines.has("Partner resolution used: No"), "the EN summary counts both formal commits and reports the tier, got %s" % [en_lines])
	_check(vi_lines.size() == en_lines.size() and vi_lines != en_lines, "the VI summary is translated")


## Structural guarantee, cheaper and more precise than a text sweep (the
## narrative content itself uses ordinary words like "window"): the presenter
## must never read a constraint's own "type" or "required" field at all —
## every fact it shows comes from the AUTHORED visible_constraint_facts
## translation key, never from inspecting the constraint's shape.
func _test_presenter_never_reads_constraint_type_or_required() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/deduction/prototype_c_presenter.gd")
	for forbidden in ['.get("type"', '.get("required"', '.get("earliest"', '.get("latest"', '.get("min_gap_minutes"', '.get("ground_truth"', '.get("supporting_constraint_refs"']:
		_check(not source.contains(forbidden), "prototype_c_presenter.gd must never read %s — facts come only from authored translation keys" % forbidden)
