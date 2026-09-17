extends SceneTree
## Focused tests for PrototypeBPresenter (Milestone 1.12 — see
## docs/prototype-b.md; draft/batch model since Milestone 1.14 — see
## docs/resolution-policy.md): the player view's exact allow-listed key
## structure, a content-level spoiler sweep against the real X/Y/Z
## prototype_b data (no domain id/structural role/veracity/relation/target
## ever reaches it), both questions visible as unverified drafts with no
## per-draft or per-clue correctness, the deductions appearing ONLY after an
## accepted theory, evidence text gated on "opened", hint progression via the
## real base API, the resolution status (localized, no raw ids), assistance
## and partner content gated by the policy, the non-oracular feedback levels,
## and the localized completion summary. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_b_presenter_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]
const VIEW_KEYS := [
	"non_canon", "case_title", "case_description", "completed", "theory_accepted", "drafts", "active_draft_handle",
	"question", "slot_count", "slots", "can_commit", "known_failed_theory", "evidence", "hint", "resolution_status",
	"stats", "completion_text", "completion_lines",
]
const RESOLUTION_STATUS_KEYS := [
	"current_status_text", "run_result_text", "run_result_label", "standard_attempts_remaining", "standard_attempts_total", "assisted_attempts_remaining",
	"assisted_attempts_total", "can_submit", "assistance_required", "assistance_active", "partner_available",
	"resolved_by_partner", "hint_notice",
]
const RAW_IDS := [
	"independent", "guided", "assisted", "standard", "assistance_required", "partner_available", "resolved",
	"player", "partner", "theory_accepted", "theory_rejected", "coarse", "incomplete_drafts", "duplicate_failed_theory",
	"valid_support", "irrelevant_evidence", "insufficient_evidence", "compatible_not_proof", "invalid_input", "supports",
]

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

	presenter = load("res://scripts/deduction/prototype_b_presenter.gd")
	controller_script = load("res://scripts/deduction/prototype_b_controller.gd")
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeBPresenter — focused tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		_check(not case_def.is_empty(), "%s should load through ContentDB" % case_id)
		_test_player_view_shape(case_def)
		_test_player_view_spoiler_safety(case_def)
		_test_drafts_never_reveal_correctness(case_def)
		_test_feedback_levels_assistance_and_partner_gating(case_def)

	_test_resolved_claims_absent_before_accepted_present_after()
	_test_evidence_text_gated_on_opened()
	_test_hint_follows_active_draft()
	_test_uncounted_feedback_mapping()
	_test_resolution_status_localized()
	_test_completion_lines_localized()

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


func _fill_draft(controller, index: int, ids: Array) -> void:
	controller.select_draft(index)
	for existing in controller.get_selected_evidence_ids():
		controller.remove_evidence(existing)
	for evidence_id in ids:
		controller.select_evidence(evidence_id)


func _proof(case_def: Dictionary, round_index: int) -> Array:
	var round_def: Dictionary = case_def.get("prototype_b", {}).get("rounds", [])[round_index]
	for proof_set in evaluator.find_claim(case_def, str(round_def.get("target", ""))).get("proof_sets", []):
		if proof_set.get("relation") == round_def.get("relation") and (proof_set.get("requires", []) as Array).size() == int(round_def.get("slot_count", 0)):
			return proof_set.get("requires", [])
	return []


## Five distinct evidence combinations for question 2 that the real evaluator
## does NOT accept — generated from the pool, never hand-picked.
func _wrong_second_drafts(case_def: Dictionary, controller) -> Array:
	var round_def: Dictionary = case_def.get("prototype_b", {}).get("rounds", [])[1]
	var pool: Array = controller.get_evidence_pool_ids()
	var slot_count: int = int(round_def.get("slot_count", 0))
	var out: Array = []
	var probe = load("res://scripts/deduction/deduction_session.gd").new(str(case_def.get("id", "")))
	for a in pool.size():
		for b in range(a + 1, pool.size()):
			for c in range(b + 1, pool.size()):
				var combo: Array = [pool[a], pool[b], pool[c]].slice(0, slot_count)
				var category: String = evaluator.classify_attempt(case_def, probe, str(round_def.get("target", "")), str(round_def.get("relation", "")), combo).get("category", "")
				if not evaluator.is_valid_category(category) and not out.any(func(existing): return existing == combo):
					out.append(combo)
				if out.size() == 5:
					return out
	return out


func _test_player_view_shape(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_assert_keys_exactly(view, VIEW_KEYS, "%s: player view" % case_id)
	_check(view.get("non_canon") == true and view.get("completed") == false and view.get("theory_accepted") == false, "%s: a fresh non-canon run" % case_id)
	_check(not view.has("resolved_claims") and not view.has("assistance"), "%s: resolved_claims/assistance must be entirely absent on a fresh run" % case_id)
	_check((view.get("drafts", []) as Array).size() == 2, "%s: both investigation questions must be available as drafts" % case_id)
	for draft in view.get("drafts", []):
		_assert_keys_exactly(draft, ["handle", "number", "question", "slot_count", "filled_count", "complete", "saved", "active"], "%s: draft entry" % case_id)
		_check(String(draft.get("question", "")) != "", "%s: every draft shows its question text" % case_id)
	for slot in view.get("slots", []):
		_assert_keys_exactly(slot, ["index", "filled", "evidence_handle"], "%s: slot entry" % case_id)
	for evidence in view.get("evidence", []):
		_assert_keys_exactly(evidence, ["handle", "name", "opened", "text", "selected"], "%s: evidence entry" % case_id)
	if not (view.get("hint", {}) as Dictionary).is_empty():
		_assert_keys_exactly(view.get("hint", {}), ["handle", "levels_revealed", "total_levels", "can_reveal_more"], "%s: hint entry" % case_id)
	_assert_keys_exactly(view.get("resolution_status", {}), RESOLUTION_STATUS_KEYS, "%s: resolution status" % case_id)
	_assert_keys_exactly(view.get("stats", {}), ["elapsed_ms", "attempts", "failed", "opened", "replacements", "drafts_saved", "hints_used", "assistance_used", "partner_resolutions"], "%s: stats" % case_id)
	for key in view.get("stats", {}):
		_check(typeof(view["stats"][key]) == TYPE_INT, "%s: stats.%s must be numeric" % [case_id, key])


## Realistic play (one wrong theory, one hint, one opened item, both drafts
## filled) — no domain id, structural role, target deduction text or raw id
## may appear anywhere in the serialized view.
func _test_player_view_spoiler_safety(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var pool: Array = controller.get_evidence_pool_ids()
	controller.open_evidence(pool[0])
	_fill_draft(controller, 0, [pool[0], pool[1], pool[2]])
	_fill_draft(controller, 1, _wrong_second_drafts(case_def, controller)[0])
	controller.commit_theory()
	controller.reveal_next_hint()

	var result: Dictionary = presenter.build_player_view(case_def, controller)
	var view: Dictionary = result.get("view", {})
	var serialized: String = JSON.stringify(view)
	for domain_id in _all_domain_ids(case_def):
		_check(not serialized.contains(domain_id), "%s: player view must never contain the raw domain id \"%s\"" % [case_id, domain_id])
	for role in _all_structural_roles(case_def):
		_check(not serialized.contains(role), "%s: player view must never contain the structural role \"%s\"" % [case_id, role])
	for round_def in case_def.get("prototype_b", {}).get("rounds", []):
		var target_text: String = String(TranslationServer.translate(str(evaluator.find_claim(case_def, str(round_def.get("target", ""))).get("text", ""))))
		_check(target_text != "" and not serialized.contains(target_text), "%s: an unaccepted theory must never reveal a target deduction's text" % case_id)
	var all_keys: Dictionary = {}
	_collect_all_keys(view, all_keys)
	for banned_key in ["id", "veracity", "proof_sets", "compatible", "structural_role", "target", "relation", "unlock_requires", "ground_truth", "source", "certainty", "misleading", "category", "affected_draft_index", "correct", "valid"]:
		_check(not all_keys.has(banned_key), '%s: player view must never carry a "%s" field anywhere in its structure' % [case_id, banned_key])
	var values: Array = []
	_collect_string_values(view, values)
	for raw_id in RAW_IDS:
		_check(not values.has(raw_id), "%s: the player view must never carry the raw id \"%s\" as a value" % [case_id, raw_id])


## Filling question 1 with its REAL proof vs. a wrong trio of the same size
## must produce indistinguishable draft metadata — the view reports "filled"
## and "saved", never correctness.
func _test_drafts_never_reveal_correctness(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var correct = _new_controller(case_def)
	_fill_draft(correct, 0, _proof(case_def, 0))
	var wrong = _new_controller(case_def)
	var pool: Array = wrong.get_evidence_pool_ids()
	var wrong_trio: Array = pool.filter(func(id): return not _proof(case_def, 0).has(id)).slice(0, int(_proof(case_def, 0).size()))
	_fill_draft(wrong, 0, wrong_trio)
	var correct_view: Dictionary = presenter.build_player_view(case_def, correct).get("view", {})
	var wrong_view: Dictionary = presenter.build_player_view(case_def, wrong).get("view", {})
	_check(correct_view.get("drafts") == wrong_view.get("drafts"), "%s: a correct and a wrong draft must look identical in the drafts list" % case_id)
	_check(correct_view.get("can_commit") == wrong_view.get("can_commit") and correct_view.get("resolution_status") == wrong_view.get("resolution_status"), "%s: correctness must never leak through commit availability or status" % case_id)
	var correct_slots: Array = correct_view.get("slots", []).map(func(s): return s.get("filled"))
	var wrong_slots: Array = wrong_view.get("slots", []).map(func(s): return s.get("filled"))
	_check(correct_slots == wrong_slots, "%s: slot entries must never mark a clue as correct" % case_id)


func _test_feedback_levels_assistance_and_partner_gating(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var rounds: Array = case_def.get("prototype_b", {}).get("rounds", [])
	var q1: String = String(TranslationServer.translate(str(rounds[0].get("question", ""))))
	var q2: String = String(TranslationServer.translate(str(rounds[1].get("question", ""))))
	var rejected_text: String = String(TranslationServer.translate("UI_PROTOTYPE_B_FEEDBACK_THEORY_REJECTED"))
	var wrong: Array = _wrong_second_drafts(case_def, controller)
	_check(wrong.size() == 5, "%s: sanity — five distinct wrong drafts for question 2" % case_id)
	var d3_names: Array = _proof(case_def, 1).map(func(id): return String(TranslationServer.translate(str(evaluator.find_evidence(case_def, id).get("name", "")))))
	var ladder: Array = []
	for hint_ladder in case_def.get("hints", []):
		if hint_ladder.get("target") == rounds[1].get("target"):
			ladder = hint_ladder.get("levels", [])
	var category_hint: String = String(TranslationServer.translate(str(ladder[1].get("text", ""))))
	var evidence_group_hint: String = String(TranslationServer.translate(str(ladder[2].get("text", ""))))

	_fill_draft(controller, 0, _proof(case_def, 0))
	var feedbacks: Array = []
	for i in 3:
		_fill_draft(controller, 1, wrong[i])
		var feedback: Dictionary = presenter.build_feedback(case_def, controller, controller.commit_theory())
		feedbacks.append(feedback)
		var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
		_check(not view.has("assistance") and not JSON.stringify(view).contains(category_hint), "%s: no assistance content after %d failure(s)" % [case_id, i + 1])
		for name in d3_names:
			_check(not JSON.stringify(feedback).contains(name), "%s: failure %d feedback must never name a needed clue (\"%s\")" % [case_id, i + 1, name])
		_check(feedback.get("deduction_text") == "" and feedback.get("success") == false, "%s: failure %d reveals no deduction" % [case_id, i + 1])

	_check(feedbacks[0].get("explanation") == rejected_text, "%s: the first failure must be the generic rejection only, got \"%s\"" % [case_id, feedbacks[0].get("explanation")])
	_check(not String(feedbacks[0].get("explanation")).contains(q1) and not String(feedbacks[0].get("explanation")).contains(q2), "%s: the first failure must not identify a question" % case_id)
	_check(String(feedbacks[1].get("explanation")).contains(q2) and not String(feedbacks[1].get("explanation")).contains(q1), "%s: the second failure names only the affected question" % case_id)
	_check(String(feedbacks[2].get("resolution_notice")).contains(String(TranslationServer.translate("UI_RESOLUTION_NOTICE_ASSISTANCE_REQUIRED"))), "%s: the third failure requires assistance" % case_id)

	controller.accept_assistance()
	var assisted: Dictionary = presenter.build_player_view(case_def, controller)
	var assistance: Dictionary = assisted.get("view", {}).get("assistance", {})
	_assert_keys_exactly(assistance, ["headline", "draft_handle", "focus", "category_hint"], "%s: assistance block" % case_id)
	_check(assisted.get("handle_map", {}).get(assistance.get("draft_handle", "")) == "1", "%s: assistance points at the invalid question's draft" % case_id)
	_check(String(assistance.get("focus", "")).contains(q2) and assistance.get("category_hint") == category_hint, "%s: assistance names the question and reuses the ladder's category level" % case_id)
	_check(not JSON.stringify(assistance).contains(evidence_group_hint), "%s: assistance must never reveal the ladder's evidence-group level" % case_id)
	for name in d3_names:
		_check(not JSON.stringify(assistance).contains(name), "%s: assistance must never name a needed clue (\"%s\")" % [case_id, name])

	var partner_headline: String = String(TranslationServer.translate("UI_RESOLUTION_PARTNER_HEADLINE"))
	var last: Dictionary = {}
	for i in range(3, 5):
		_fill_draft(controller, 1, wrong[i])
		last = presenter.build_feedback(case_def, controller, controller.commit_theory())
	_check(last.get("partner") == false and last.get("partner_note") == "" and last.get("headline") != partner_headline, "%s: the partner solution stays hidden while merely offered" % case_id)
	var partner: Dictionary = presenter.build_feedback(case_def, controller, controller.resolve_with_partner())
	_check(partner.get("success") == true and partner.get("partner") == true and partner.get("headline") == partner_headline, "%s: partner resolution is clearly labeled" % case_id)
	for name in d3_names:
		_check(String(partner.get("partner_note", "")).contains(name), "%s: the partner note explains the connection it made (\"%s\")" % [case_id, name])
	_check(String(partner.get("deduction_text", "")) != "" and String(partner.get("explanation", "")) != "", "%s: partner resolution still explains both deductions" % case_id)
	_check(presenter.build_player_view(case_def, controller).get("view", {}).has("resolved_claims"), "%s: the deductions appear once the partner resolves the theory" % case_id)


func _test_resolved_claims_absent_before_accepted_present_after() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	_fill_draft(controller, 0, ["e_a", "e_b", "e_c"])
	_fill_draft(controller, 1, ["e_d", "e_e"])
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not before.has("resolved_claims") and not JSON.stringify(before).contains("first deduction"), "complete-but-uncommitted drafts reveal no deduction")
	controller.commit_theory()
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((after.get("resolved_claims", []) as Array).size() == 2, "both deductions appear once the theory is accepted")
	_check(JSON.stringify(after).contains("first deduction") and JSON.stringify(after).contains("second deduction"), "the resolved claims carry their own text")


func _test_evidence_text_gated_on_opened() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	for evidence in presenter.build_player_view(case_def, controller).get("view", {}).get("evidence", []):
		_check(evidence.get("opened") == false and evidence.get("text") == "", "unopened evidence shows no text")
	controller.open_evidence("e_a")
	var opened: Array = presenter.build_player_view(case_def, controller).get("view", {}).get("evidence", []).filter(func(e): return e.get("opened"))
	_check(opened.size() == 1 and opened[0].get("text") != "", "exactly one opened item shows its text")


func _test_hint_follows_active_draft() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	controller.reveal_next_hint()
	var first: Dictionary = presenter.build_player_view(case_def, controller)
	_check((first.get("view", {}).get("hint", {}).get("levels_revealed", []) as Array).size() == 1, "the active draft's revealed hint shows")
	_check(first.get("handle_map", {}).get(first.get("view", {}).get("hint", {}).get("handle", "")) == "ded_first", "the hint handle resolves to the active draft's target")
	controller.select_draft(1)
	var second: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((second.get("hint", {}).get("levels_revealed", []) as Array).is_empty(), "switching drafts shows that question's own (unrevealed) ladder")


func _test_uncounted_feedback_mapping() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	var incomplete: Dictionary = presenter.build_feedback(case_def, controller, controller.commit_theory())
	_check(incomplete.get("explanation") == String(TranslationServer.translate("UI_PROTOTYPE_B_FEEDBACK_INVALID")) and incomplete.get("resolution_notice") == "", "an incomplete theory explains what's missing and costs nothing")
	_fill_draft(controller, 0, ["e_a", "e_b", "e_c"])
	_fill_draft(controller, 1, ["e_d", "e_noise"])
	controller.commit_theory()
	var duplicate: Dictionary = presenter.build_feedback(case_def, controller, controller.commit_theory())
	_check(duplicate.get("explanation") == String(TranslationServer.translate("UI_PROTOTYPE_B_FEEDBACK_DUPLICATE")) and duplicate.get("resolution_notice") == "", "a duplicate theory is refused at no cost")
	var locked_controller = _new_controller(case_def)
	_fill_draft(locked_controller, 0, ["e_a", "e_b", "e_c"])
	for pair in [["e_d", "e_noise"], ["e_e", "e_noise"], ["e_a", "e_d"]]:
		_fill_draft(locked_controller, 1, pair)
		locked_controller.commit_theory()
	_fill_draft(locked_controller, 1, ["e_d", "e_e"])
	var locked: Dictionary = presenter.build_feedback(case_def, locked_controller, locked_controller.commit_theory())
	_check(locked.get("explanation") == String(TranslationServer.translate("UI_RESOLUTION_SUBMISSION_LOCKED")) and locked.get("success") == false, "a locked commit explains the lock, even for a correct theory")


func _test_resolution_status_localized() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	TranslationServer.set_locale("en")
	var en_status: Dictionary = presenter.build_player_view(case_def, controller).get("view", {}).get("resolution_status", {})
	TranslationServer.set_locale("vi")
	var vi_status: Dictionary = presenter.build_player_view(case_def, controller).get("view", {}).get("resolution_status", {})
	var en: String = String(en_status.get("current_status_text", ""))
	var vi: String = String(vi_status.get("current_status_text", ""))
	_check(en.contains("3/3") and not en.contains("Independent"), "the EN current-unit status shows the commit budget in words and never the run result, got \"%s\"" % en)
	_check(String(en_status.get("run_result_text", "")).contains("Independent"), "the EN run-result line separately says Independent, got \"%s\"" % en_status.get("run_result_text"))
	_check(vi.contains("3/3") and vi != en, "the VI status is translated, got \"%s\"" % vi)


func _test_completion_lines_localized() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	_fill_draft(controller, 0, ["e_a", "e_b", "e_c"])
	_fill_draft(controller, 1, ["e_d", "e_e"])
	controller.commit_theory()
	controller.acknowledge_result()
	TranslationServer.set_locale("en")
	var en_lines: Array = presenter.build_player_view(case_def, controller).get("view", {}).get("completion_lines", [])
	TranslationServer.set_locale("vi")
	var vi_lines: Array = presenter.build_player_view(case_def, controller).get("view", {}).get("completion_lines", [])
	_check(en_lines.size() == 10, "the completion summary shows 7 shared lines + clues opened, replacements, drafts saved, got %s" % [en_lines])
	_check(en_lines.has("Resolution tier: Independent") and en_lines.has("Formal commits: 1") and en_lines.has("Partner resolution used: No"), "the EN summary reports resolution in words, got %s" % [en_lines])
	_check(vi_lines.size() == en_lines.size() and vi_lines != en_lines, "the VI summary is translated")
