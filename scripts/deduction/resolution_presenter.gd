class_name ResolutionPresenter
extends RefCounted
## Localized, spoiler-free text for ResolutionPolicy state (Milestone 1.14 —
## see docs/resolution-policy.md; hardened in Milestone 1.14.1), shared by
## PrototypeAPresenter/PrototypeBPresenter/PrototypeCPresenter so the three
## prototypes describe the current unit, the run result, remaining attempts,
## assistance and completion summaries with ONE vocabulary.
## Stateless static helpers, no autoloads.
##
## Never emits a raw run-result/phase id: every value a view carries is
## either a translated string, a number, or a boolean. Carries no puzzle
## content at all — which statement, clue, time or fact assistance points at
## is each prototype presenter's own, separately gated, decision.
##
## Milestone 1.14.1: build_status() reports the CURRENT unit's own state
## ("current_status_text") and the RUN-WIDE result ("run_result_text")
## as two separate strings, never one merged line — a fresh unit must never
## read as "Assisted" merely because an earlier unit used help. When the
## current unit is itself still PHASE_STANDARD (no local failures, no active
## assistance) but the run result is already above Independent, the run
## result line explicitly says it was reached in an earlier challenge, so the
## two lines never appear to contradict each other.

const TIER_LABEL_KEYS := {
	ResolutionPolicy.TIER_INDEPENDENT: "UI_RESOLUTION_TIER_INDEPENDENT",
	ResolutionPolicy.TIER_GUIDED: "UI_RESOLUTION_TIER_GUIDED",
	ResolutionPolicy.TIER_ASSISTED: "UI_RESOLUTION_TIER_ASSISTED",
}
## "%d/%d formal commits before assistance" — Prototype A passes its own
## credibility wording instead.
const DEFAULT_ATTEMPTS_KEY := "UI_RESOLUTION_STATUS_ATTEMPTS"
const HINT_NOTICE_KEY := "UI_RESOLUTION_HINT_NOTICE"
const RUN_RESULT_KEY := "UI_RESOLUTION_RUN_RESULT"
const RUN_RESULT_FROM_EARLIER_KEY := "UI_RESOLUTION_RUN_RESULT_FROM_EARLIER"


static func tier_label(run_resolution_result: String) -> String:
	return _t(TIER_LABEL_KEYS.get(run_resolution_result, ""))


## The allow-listed status block every prototype view carries under
## "resolution_status". `attempts_key` is a two-%d format key for the
## standard-phase budget line. Returns the CURRENT unit's state
## ("current_status_text") and the RUN-WIDE result ("run_result_text",
## "run_result_label") as two separate fields — see class doc above.
static func build_status(policy: ResolutionPolicy, attempts_key: String = DEFAULT_ATTEMPTS_KEY) -> Dictionary:
	if policy == null:
		return {}
	var remaining: int = policy.get_standard_attempts_remaining()
	var assisted_remaining: int = policy.get_assisted_attempts_remaining()
	var current_status_text: String
	match policy.get_current_unit_phase():
		ResolutionPolicy.PHASE_STANDARD:
			current_status_text = _t(attempts_key) % [remaining, ResolutionPolicy.STANDARD_FAILURE_LIMIT]
		ResolutionPolicy.PHASE_ASSISTANCE_REQUIRED:
			current_status_text = _t("UI_RESOLUTION_STATUS_ASSISTANCE_REQUIRED")
		ResolutionPolicy.PHASE_ASSISTED:
			current_status_text = _t("UI_RESOLUTION_STATUS_ASSISTED_ATTEMPTS") % [assisted_remaining, ResolutionPolicy.ASSISTED_FAILURE_LIMIT]
		ResolutionPolicy.PHASE_PARTNER_AVAILABLE:
			current_status_text = _t("UI_RESOLUTION_STATUS_PARTNER_AVAILABLE")
		ResolutionPolicy.PHASE_RESOLVED:
			var resolved_key: String = "UI_RESOLUTION_STATUS_RESOLVED_PARTNER" if policy.get_unit_resolved_by() == ResolutionPolicy.RESOLVED_BY_PARTNER else "UI_RESOLUTION_STATUS_RESOLVED"
			current_status_text = _t(resolved_key)
		_:
			current_status_text = ""
	var label: String = tier_label(policy.get_run_resolution_result())
	## The current unit is still a clean slate (no local failure, no active
	## assistance) but the run result is already elevated — say so was
	## "reached in an earlier challenge" so this unit is never misread as
	## itself Assisted/Guided.
	var result_from_earlier_unit: bool = policy.get_current_unit_phase() == ResolutionPolicy.PHASE_STANDARD \
		and policy.get_run_resolution_result() != ResolutionPolicy.TIER_INDEPENDENT
	var run_result_text: String = _t(RUN_RESULT_FROM_EARLIER_KEY if result_from_earlier_unit else RUN_RESULT_KEY) % label
	return {
		"current_status_text": current_status_text,
		"run_result_text": run_result_text,
		"run_result_label": label,
		"standard_attempts_remaining": remaining,
		"standard_attempts_total": ResolutionPolicy.STANDARD_FAILURE_LIMIT,
		"assisted_attempts_remaining": assisted_remaining,
		"assisted_attempts_total": ResolutionPolicy.ASSISTED_FAILURE_LIMIT,
		"can_submit": policy.can_submit(),
		"assistance_required": policy.requires_assistance(),
		"assistance_active": policy.is_unit_assistance_accepted(),
		"partner_available": policy.can_use_partner_resolution(),
		"resolved_by_partner": policy.get_unit_resolved_by() == ResolutionPolicy.RESOLVED_BY_PARTNER,
		"hint_notice": _t(HINT_NOTICE_KEY),
	}


## The feedback line describing a counted formal commit's consequence: the
## remaining budget, whether assistance is now required or partner resolution
## is now offered, and — explicitly, never silently — a run-result change.
## "" for an action that counted nothing.
static func build_commit_notice(snapshot: Dictionary, attempts_key: String = DEFAULT_ATTEMPTS_KEY) -> String:
	if snapshot.get("counted", false) != true:
		return ""
	var lines: Array[String] = []
	if snapshot.get("reason", "") == ResolutionPolicy.REASON_FAILED_COMMIT:
		match str(snapshot.get("current_unit_phase_after", "")):
			ResolutionPolicy.PHASE_STANDARD:
				lines.append(_t(attempts_key) % [int(snapshot.get("standard_attempts_remaining", 0)), ResolutionPolicy.STANDARD_FAILURE_LIMIT])
			ResolutionPolicy.PHASE_ASSISTANCE_REQUIRED:
				lines.append(_t("UI_RESOLUTION_NOTICE_ASSISTANCE_REQUIRED"))
			ResolutionPolicy.PHASE_ASSISTED:
				lines.append(_t("UI_RESOLUTION_STATUS_ASSISTED_ATTEMPTS") % [int(snapshot.get("assisted_attempts_remaining", 0)), ResolutionPolicy.ASSISTED_FAILURE_LIMIT])
			ResolutionPolicy.PHASE_PARTNER_AVAILABLE:
				lines.append(_t("UI_RESOLUTION_NOTICE_PARTNER_AVAILABLE"))
	lines.append_array(_run_result_change_lines(snapshot))
	return "\n".join(PackedStringArray(lines))


## Just the explicit "this run is now Guided/Assisted" line, for a hint or an
## assistance acknowledgement — "" when the run result did not change.
static func build_run_result_notice(snapshot: Dictionary) -> String:
	return "\n".join(PackedStringArray(_run_result_change_lines(snapshot)))


## Localized completion-summary lines shared by every prototype, in a fixed
## order, followed by `extra_lines` (each prototype's own mechanic statistics).
static func build_completion_lines(policy: ResolutionPolicy, elapsed_ms: int, hints_used: int, extra_lines: Array[String] = []) -> Array[String]:
	var lines: Array[String] = []
	if policy == null:
		return lines
	var total_seconds: int = int(float(elapsed_ms) / 1000.0)
	lines.append(_t("UI_RESOLUTION_STATS_TIME") % ("%d:%02d" % [total_seconds / 60, total_seconds % 60]))
	lines.append(_t("UI_RESOLUTION_STATS_FORMAL_COMMITS") % policy.get_formal_commit_count())
	lines.append(_t("UI_RESOLUTION_STATS_FAILED_COMMITS") % policy.get_failed_commit_count())
	lines.append(_t("UI_RESOLUTION_STATS_HINTS") % hints_used)
	lines.append(_t("UI_RESOLUTION_STATS_ASSISTANCE") % _yes_no(policy.get_assistance_count() > 0))
	lines.append(_t("UI_RESOLUTION_STATS_TIER") % tier_label(policy.get_run_resolution_result()))
	lines.append(_t("UI_RESOLUTION_STATS_PARTNER") % _yes_no(policy.get_partner_resolution_count() > 0))
	lines.append_array(extra_lines)
	return lines


static func _run_result_change_lines(snapshot: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if snapshot.get("counted", false) == true and snapshot.get("run_resolution_result_changed", false) == true:
		lines.append(_t("UI_RESOLUTION_NOTICE_TIER_CHANGED") % tier_label(str(snapshot.get("run_resolution_result_after", ""))))
	return lines


static func _yes_no(value: bool) -> String:
	return _t("UI_RESOLUTION_YES" if value else "UI_RESOLUTION_NO")


static func _t(key: Variant) -> String:
	if typeof(key) != TYPE_STRING or key == "":
		return ""
	return String(TranslationServer.translate(key))
