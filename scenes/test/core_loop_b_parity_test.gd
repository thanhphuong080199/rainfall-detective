extends SceneTree
## Milestone 1.17 — production B vs. debug Prototype B contract (see
## docs/core-loop-sandbox.md, "Production B is not debug Prototype B").
## Milestone 1.16 deliberately made production B a SINGLE-deduction commit
## (one authored round per unit, shared session, acquired pool, help-only
## policy) while the debug prototype keeps its batch of every round. This
## pins down what must stay IDENTICAL between them and what must stay
## DIFFERENT, over every real case (X/Y/Z) and EVERY complete clue set of
## every round — not just the authored answers:
##   * the same DeductionEvaluator category for the round's clue set, and the
##     same accept/reject outcome, in production and in the debug batch;
##   * incomplete drafts and repeated failed sets are refused without cost in
##     both;
##   * production commits only its configured deduction, and resolving one
##     production B unit never resolves a later one sharing the session;
##   * the debug batch is unchanged: all rounds at once, one invalid draft
##     commits nothing, failures still escalate its run result.
## Pure and autoload-free (the cases are read straight from JSON) — FAST and
## FULL.
##
##   godot --headless --path . -s res://scenes/test/core_loop_b_parity_test.gd

const CASE_PATHS := [
	"res://data/deductions/prototypes/proto_x_archive_ledger.json",
	"res://data/deductions/prototypes/proto_y_lab_sample.json",
	"res://data/deductions/prototypes/proto_z_customs_parcel.json",
]

var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	print("=== Core loop — production B vs debug Prototype B ===")
	for path in CASE_PATHS:
		var case_def: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		_test_every_candidate_classifies_identically(case_def)
		_test_uncounted_inputs_match(case_def)
		_test_production_commits_only_its_unit(case_def)
		_test_debug_batch_unchanged(case_def)
	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _rounds(case_def: Dictionary) -> Array:
	return case_def["prototype_b"]["rounds"]


func _pool(case_def: Dictionary) -> Array[String]:
	var pool: Array[String] = []
	pool.assign(case_def["prototype_b"]["evidence_pool"])
	return pool


## A production B unit exactly as CoreLoopUnit builds one.
func _production(case_def: Dictionary, round_id: String, session: DeductionSession = null, recorder: DeductionLabRecorder = null) -> PrototypeBController:
	var controller := PrototypeBController.new()
	var round_ids: Array[String] = [round_id]
	controller.start(case_def, recorder, {
		"session": session if session != null else DeductionSession.new(str(case_def["id"])), "round_ids": round_ids,
		"evidence_pool": _pool(case_def), "failures_escalate_run_result": false,
	})
	return controller


func _debug(case_def: Dictionary, recorder: DeductionLabRecorder = null) -> PrototypeBController:
	var controller := PrototypeBController.new()
	controller.start(case_def, recorder)
	return controller


func _fill(controller: PrototypeBController, draft: int, clues: Array) -> void:
	controller.select_draft(draft)
	for clue in controller.get_selected_evidence_ids():
		controller.remove_evidence(clue)
	for clue in clues:
		controller.select_evidence(str(clue))


func _combinations(pool: Array, size: int) -> Array:
	if size == 0:
		return [[]]
	var out: Array = []
	for i in pool.size():
		for rest in _combinations(pool.slice(i + 1), size - 1):
			out.append([pool[i]] + rest)
	return out


## The category the recorder captured for draft `draft` of the last rejected
## batch, or "accepted" — what each controller actually got from the evaluator.
func _recorded_category(recorder: DeductionLabRecorder, draft: int) -> String:
	var events: Array[Dictionary] = recorder.get_events()
	for i in range(events.size() - 1, -1, -1):
		match str(events[i].get("type", "")):
			"theory_batch_rejected":
				return str((events[i].get("payload", {}).get("draft_categories", []) as Array)[draft])
			"theory_batch_accepted":
				return "accepted"
	return ""


func _first_accepted_path(case_def: Dictionary, round_def: Dictionary) -> Array:
	for candidate in _combinations(_pool(case_def), int(round_def["slot_count"])):
		var category: String = str(DeductionEvaluator.classify_attempt(case_def, DeductionSession.new(str(case_def["id"])), str(round_def["target"]), str(round_def["relation"]), candidate).get("category", ""))
		if DeductionEvaluator.is_valid_category(category):
			return candidate
	return []


# ---------------------------------------------------------------------------

func _test_every_candidate_classifies_identically(case_def: Dictionary) -> void:
	var case_id: String = str(case_def["id"])
	var rounds: Array = _rounds(case_def)
	var seen_categories: Dictionary = {}
	var mismatches: Array[String] = []
	var accepted_count := 0
	var total := 0
	for r in rounds.size():
		var round_def: Dictionary = rounds[r]
		var other: int = 1 - r
		var other_path: Array = _first_accepted_path(case_def, rounds[other])
		for candidate in _combinations(_pool(case_def), int(round_def["slot_count"])):
			total += 1
			var expected: String = str(DeductionEvaluator.classify_attempt(case_def, DeductionSession.new(case_id), str(round_def["target"]), str(round_def["relation"]), candidate).get("category", ""))
			var valid: bool = DeductionEvaluator.is_valid_category(expected)
			seen_categories[expected] = true
			var production_recorder := DeductionLabRecorder.new()
			production_recorder.start(case_id, "clue_connection")
			var production := _production(case_def, str(round_def["id"]), null, production_recorder)
			_fill(production, 0, candidate)
			var production_result: Dictionary = production.commit_theory()
			var debug_recorder := DeductionLabRecorder.new()
			debug_recorder.start(case_id, "clue_connection")
			var debug := _debug(case_def, debug_recorder)
			_fill(debug, r, candidate)
			_fill(debug, other, other_path)
			var debug_result: Dictionary = debug.commit_theory()
			var production_category: String = _recorded_category(production_recorder, 0)
			var debug_category: String = _recorded_category(debug_recorder, r)
			if valid:
				accepted_count += 1
			var agrees: bool = production_result.get("accepted", false) == valid and debug_result.get("accepted", false) == valid \
				and production_result.get("counted", false) and debug_result.get("counted", false) \
				and (production_category == ("accepted" if valid else expected)) and (debug_category == ("accepted" if valid else expected))
			if not agrees:
				mismatches.append("%s %s: evaluator %s, production %s/%s, debug %s/%s" % [round_def["id"], candidate, expected, production_result.get("accepted"), production_category, debug_result.get("accepted"), debug_category])
	_check(mismatches.is_empty(), "%s: all %d complete clue sets get the same evaluator category and outcome in production B and the debug batch: %s" % [case_id, total, mismatches.slice(0, 3)])
	_check(accepted_count == 3, "%s: exactly the three authored accepted proof sets are accepted by both (primary + alternate D1, D3): %d" % [case_id, accepted_count])
	# A formal B commit always carries a FULL slot set, so the evaluator's
	# "insufficient_evidence" (a strict subset of a proof) never reaches it —
	# that input is an incomplete draft, refused uncounted in both (see
	# _test_uncounted_inputs_match). The relevant-but-not-proof and irrelevant
	# categories must both have been compared.
	_check(seen_categories.has(DeductionEvaluator.COMPATIBLE_NOT_PROOF) and seen_categories.has(DeductionEvaluator.IRRELEVANT_EVIDENCE), "%s: relevant-but-insufficient and irrelevant sets were both exercised: %s" % [case_id, seen_categories.keys()])
	_check(not seen_categories.has(DeductionEvaluator.INSUFFICIENT_EVIDENCE), "%s: no complete slot set is ever 'insufficient' — that input only exists as an incomplete draft" % case_id)


func _test_uncounted_inputs_match(case_def: Dictionary) -> void:
	var case_id: String = str(case_def["id"])
	var round_def: Dictionary = _rounds(case_def)[0]
	var accepted: Array = _first_accepted_path(case_def, round_def)
	var wrong: Array = []
	for clue in _pool(case_def):
		if not accepted.has(clue) and wrong.size() < 3:
			wrong.append(clue)
	var production := _production(case_def, str(round_def["id"]))
	var debug := _debug(case_def)
	for pair in [[production, 0], [debug, 0]]:
		var controller: PrototypeBController = pair[0]
		_fill(controller, 0, wrong.slice(0, 2))
		var incomplete: Dictionary = controller.commit_theory()
		_check(incomplete.get("counted", true) == false and controller.get_policy().get_current_unit_failures() == 0, "%s: an incomplete draft is refused without cost in %s B" % [case_id, "production" if controller == production else "debug"])
	_fill(production, 0, wrong)
	production.commit_theory()
	var reordered: Array = wrong.duplicate()
	reordered.reverse()
	_fill(production, 0, reordered)
	var duplicate: Dictionary = production.commit_theory()
	_check(duplicate.get("reason", "") == PrototypeBController.REASON_DUPLICATE_THEORY and production.get_policy().get_current_unit_failures() == 1, "%s: production B blocks the same failed clue set (any order) without cost" % case_id)
	_check(PrototypeBPresenter.build_feedback(case_def, production, duplicate).get("explanation", "") == TranslationServer.translate("UI_PROTOTYPE_B_FEEDBACK_DUPLICATE_SINGLE"), "%s: production B's duplicate notice is worded for one question" % case_id)
	_fill(debug, 0, wrong)
	_fill(debug, 1, _first_accepted_path(case_def, _rounds(case_def)[1]))
	debug.commit_theory()
	_fill(debug, 0, reordered)
	var debug_duplicate: Dictionary = debug.commit_theory()
	_check(debug_duplicate.get("reason", "") == PrototypeBController.REASON_DUPLICATE_THEORY and debug.get_policy().get_current_unit_failures() == 1, "%s: the debug batch blocks the same failed theory the same way" % case_id)


func _test_production_commits_only_its_unit(case_def: Dictionary) -> void:
	var case_id: String = str(case_def["id"])
	var rounds: Array = _rounds(case_def)
	var shared := DeductionSession.new(case_id)
	# Two production B units of one run, sharing its session — in either order.
	for order in [[0, 1], [1, 0]]:
		shared = DeductionSession.new(case_id)
		var first := _production(case_def, str(rounds[order[0]]["id"]), shared)
		var later := _production(case_def, str(rounds[order[1]]["id"]), shared)
		_check(first.get_draft_count() == 1 and later.get_draft_count() == 1, "%s: a production B unit asks exactly one question" % case_id)
		_fill(first, 0, _first_accepted_path(case_def, rounds[order[0]]))
		_check(first.commit_theory().get("accepted", false), "%s: the first unit resolves with its authored path" % case_id)
		_check(shared.is_supported(str(rounds[order[0]]["target"])) and not shared.is_supported(str(rounds[order[1]]["target"])), "%s: committing it resolves ONLY its own deduction (order %s)" % [case_id, order])
		_check(not later.is_theory_accepted(), "%s: the later B unit is not resolved by the earlier one's commit (order %s)" % [case_id, order])
		_fill(later, 0, _first_accepted_path(case_def, rounds[order[0]]))
		_check(not later.commit_theory().get("accepted", true), "%s: the earlier unit's answer is rejected by the later unit's own question" % case_id)
		_fill(later, 0, _first_accepted_path(case_def, rounds[order[1]]))
		var accepted: Dictionary = later.commit_theory()
		_check(accepted.get("accepted", false) and shared.is_supported(str(rounds[order[1]]["target"])), "%s: the later unit resolves only through its own commit" % case_id)
		_check(PrototypeBPresenter.build_feedback(case_def, later, accepted).get("headline", "") == TranslationServer.translate("UI_PROTOTYPE_B_FEEDBACK_SUCCESS_HEADLINE_SINGLE"), "%s: production B's success feedback speaks of ONE connection, never the batch's \"both\"" % case_id)


func _test_debug_batch_unchanged(case_def: Dictionary) -> void:
	var case_id: String = str(case_def["id"])
	var rounds: Array = _rounds(case_def)
	var debug := _debug(case_def)
	_check(debug.get_draft_count() == rounds.size() and debug.get_policy().failures_escalate_run_result(), "%s: debug Prototype B still drafts every round and keeps failure-escalating semantics" % case_id)
	_fill(debug, 0, _first_accepted_path(case_def, rounds[0]))
	var wrong: Array = _first_accepted_path(case_def, rounds[0])
	_fill(debug, 1, wrong)
	_check(not debug.commit_theory().get("accepted", true) and debug.get_session().get_resolved_claims().is_empty(), "%s: one invalid draft commits NEITHER deduction in the debug batch" % case_id)
	_fill(debug, 1, _first_accepted_path(case_def, rounds[1]))
	var batch: Dictionary = debug.commit_theory()
	_check(batch.get("accepted", false) and debug.get_session().is_supported(str(rounds[0]["target"])) and debug.get_session().is_supported(str(rounds[1]["target"])), "%s: a fully valid debug theory commits every round at once" % case_id)
	_check(PrototypeBPresenter.build_feedback(case_def, debug, batch).get("headline", "") == TranslationServer.translate("UI_PROTOTYPE_B_FEEDBACK_SUCCESS_HEADLINE"), "%s: the debug batch keeps its \"both connections\" wording" % case_id)
