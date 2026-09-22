# Test catalog — what's already covered, and what to add

As of Milestone 1.7, `scenes/test/` is several small, independent `-s`
scripts rather than one file — see `docs/testing.md` for the full
organization and rationale. `scenes/test/smoke_test.gd` remains one file
with one `_initialize()` that calls a sequence of `_test_*` functions, each
covering one system (some deliberately continue from the state the previous
one left, some deliberately reset first — the comments above each function
say which and why; preserve that when you add to it) — it is the
critical-path/integration fixture, not where a new Condition/Effect check
goes (see "Focused test files" below for those). This table maps system →
the function(s)/file(s) that already exercise it → the specific behaviors
pinned down → what a change to that system should add. Read the actual
function before adding to it — this table is a map, not a substitute for
reading the file itself.

This table (and the two canonical commands below) is reconciled against the
*actual* current verification runners — `CLAUDE.md` and `docs/testing.md`
own the authoritative FAST/FULL command lists; if this file and either of
those ever disagree, `CLAUDE.md`/`docs/testing.md` win and this file is
stale (fix it in the same change that touches either of them).

**FAST** (assumes `.godot/` already built):
```bash
.claude/skills/godot-development/scripts/verify.sh --skip-import --skip-load-all --skip-boot \
  --script res://scenes/test/validate_content.gd \
  --script res://scenes/test/conditions_test.gd \
  --script res://scenes/test/effects_test.gd \
  --script res://scenes/test/dependency_analysis_test.gd \
  --script res://scenes/test/deduction_evaluator_test.gd \
  --script res://scenes/test/timeline_evaluator_test.gd \
  --script res://scenes/test/deduction_validation_test.gd \
  --script res://scenes/test/deduction_cases_test.gd \
  --script res://scenes/test/deduction_lab_controller_test.gd \
  --script res://scenes/test/deduction_lab_presenter_test.gd \
  --script res://scenes/test/deduction_lab_recorder_test.gd \
  --script res://scenes/test/resolution_policy_test.gd \
  --script res://scenes/test/prototype_a_controller_test.gd \
  --script res://scenes/test/prototype_a_presenter_test.gd \
  --script res://scenes/test/prototype_a_content_test.gd \
  --script res://scenes/test/prototype_b_controller_test.gd \
  --script res://scenes/test/prototype_b_presenter_test.gd \
  --script res://scenes/test/prototype_b_content_test.gd \
  --script res://scenes/test/prototype_c_controller_test.gd \
  --script res://scenes/test/prototype_c_presenter_test.gd \
  --script res://scenes/test/prototype_c_content_test.gd
```

**FULL** (also what CI runs on every push/PR):
```bash
.claude/skills/godot-development/scripts/verify.sh \
  --script res://scenes/test/validate_content.gd \
  --script res://scenes/test/conditions_test.gd \
  --script res://scenes/test/effects_test.gd \
  --script res://scenes/test/events_test.gd \
  --script res://scenes/test/duplicate_execution_test.gd \
  --script res://scenes/test/save_load_regression_test.gd \
  --script res://scenes/test/negative_progression_test.gd \
  --script res://scenes/test/dependency_analysis_test.gd \
  --script res://scenes/test/deduction_evaluator_test.gd \
  --script res://scenes/test/timeline_evaluator_test.gd \
  --script res://scenes/test/deduction_validation_test.gd \
  --script res://scenes/test/deduction_cases_test.gd \
  --script res://scenes/test/deduction_lab_controller_test.gd \
  --script res://scenes/test/deduction_lab_presenter_test.gd \
  --script res://scenes/test/deduction_lab_recorder_test.gd \
  --script res://scenes/test/deduction_lab_scene_test.gd \
  --script res://scenes/test/resolution_policy_test.gd \
  --script res://scenes/test/prototype_a_controller_test.gd \
  --script res://scenes/test/prototype_a_presenter_test.gd \
  --script res://scenes/test/prototype_a_content_test.gd \
  --script res://scenes/test/prototype_a_scene_test.gd \
  --script res://scenes/test/prototype_b_controller_test.gd \
  --script res://scenes/test/prototype_b_presenter_test.gd \
  --script res://scenes/test/prototype_b_content_test.gd \
  --script res://scenes/test/prototype_b_scene_test.gd \
  --script res://scenes/test/prototype_c_controller_test.gd \
  --script res://scenes/test/prototype_c_presenter_test.gd \
  --script res://scenes/test/prototype_c_content_test.gd \
  --script res://scenes/test/prototype_c_scene_test.gd \
  --script res://scenes/test/smoke_test.gd
```

## Focused test files (add a new Condition/Effect/Event check here, not to smoke_test.gd)

A script marked **FAST + FULL** is pure/autoload-free (no real scene tree)
and costs a fraction of a second; one marked **FULL only** needs a real
scene tree (`Main.tscn` instantiated) and is deliberately excluded from the
FAST loop to keep routine iteration quick — see `docs/testing.md` for the
rationale behind the split itself.

| File | FAST/FULL | Covers |
|---|---|---|
| `conditions_test.gd` | FAST + FULL | Every `ConditionEvaluator` leaf/composite shape, both directions where meaningful, plus the fail-closed edge cases and the validator's stacked-check precedence rejection. Add a new leaf shape's test here. |
| `effects_test.gd` | FAST + FULL | Every `EffectRunner` effect type: resulting `GameState`, signal-emission-only-on-real-change, idempotency on repeat run, and a safe no-op for an unknown type. Add a new effect type's test here. |
| `events_test.gd` | FULL only | Negative trigger (missing condition piece), positive trigger, a "once" event's fire count under repeated reevaluation, an isolated event-chain regression, a chapter-scoped topic not leaking into an unrelated case, and `debug_reset_trigger()`'s state transitions (Milestone 1.8). |
| `duplicate_execution_test.gd` | FULL only | Regression coverage specifically for accidental double-firing: an event under redundant reevaluation, a real chapter completion (and the next chapter's activation) under redundant reevaluation, case completion likewise. |
| `save_load_regression_test.gd` | FULL only | An exact round trip of every persisted field, a triggered "once" event surviving save/reset/load without refiring, and a mid-chapter-2 save/load that doesn't re-run entry/completion effects. Isolated `user://` save file. |
| `negative_progression_test.gd` | FULL only | The paths where a bug could let a player skip required progression: event without required evidence, chapter with partial completion conditions, locked destination, wrong evidence presented. |
| `dependency_analysis_test.gd` | FAST + FULL | `ContentValidator`'s dependency-reachability WARNING checks — both the pure collector functions in isolation and an end-to-end check that real sandbox content produces zero *unexpected* dependency warnings — plus (Milestone 1.8) `find_flag_producers`/`find_evidence_producers`/`find_interaction_producers` against real content, and the pure `_effect_produces_*` predicates in isolation. |
| `deduction_evaluator_test.gd` | FAST + FULL | Milestone 1.9 — `DeductionEvaluator`/`DeductionSession` against `deduction_fixtures.gd`: every result category, order independence, alternate proofs, duplicate rejection, locked inputs, unlock-only-on-commit, conclusion locking, hint ladders, deterministic reset, JSON round trip. Add a new result category / API behaviour here. |
| `timeline_evaluator_test.gd` | FAST + FULL | Milestone 1.9 — every `TimelineEvaluator` constraint type on both sides of its boundary, multiple valid timelines, optional violations, invalid input. Add a new constraint type here. |
| `deduction_validation_test.gd` | FAST + FULL | Milestone 1.9/1.9.1 — one negative fixture per `DeductionValidator` rule, the intermediate-depth definition (evidence → D1 → D2 → conclusion passes, a third intermediate layer fails), conclusion/kind-change graph soundness, the deduction-gated-evidence warning, plus zero deduction errors/warnings in real content. Milestone 1.12 adds the Prototype B validation rules (target must be a `deduction`, must not double as a Prototype A target, proof cardinality must match `slot_count`, no proper subset may resolve the target). Add a new deduction validation rule's negative fixture here. Milestone 1.14 adds `_test_prototype_c_supporting_constraint_refs()` — negative copies of real X for a missing/duplicated/self-referencing/hidden/unrelated/insufficient/incomplete `supporting_constraint_refs` list. |
| `deduction_cases_test.gd` | FAST + FULL | Milestone 1.9/1.9.1 — the three prototype cases (X/Y/Z) end to end in structural-role terms: primary + alternate path, conclusion locking, final-proof sufficiency (opportunity/staging/lies never resolve; removing exclusive-control evidence makes the conclusion unprovable), alternative-actor elimination, independent evidence availability, taught staging rule, statements/hypotheses/red herring, role topology + depth, timelines, identical structural signatures. Milestone 1.10 adds the "zone verified empty before the monitored window" regression (`_test_zone_verified_empty_before_window`, see `docs/deduction-prototype-cases.md` §0.1). Its `_test_staging_rule_is_taught()` neighbors are what Milestone 1.12's `prototype_b_content_test.gd` leans on to justify Prototype B's D3 round using `slot_count: 3`, not the milestone brief's illustrative 2 (see that row below). |
| `deduction_lab_controller_test.gd` | FAST + FULL | Milestone 1.10 — `DeductionLabController`: session ownership, isolation between cases (a fresh session on every start_case, even re-starting the same id), the has_progress()-gated switch/reset confirmation flow (immediate when nothing to lose, deferred + cancel-preserves-exactly + confirm-creates-isolated-session otherwise), mode toggle never mutating the session, snapshot/restore. |
| `deduction_lab_presenter_test.gd` | FAST + FULL | Milestone 1.10 — `DeductionLabPresenter`: the Player Preview's exact allow-listed keys at every nesting level (structural), a content sweep against the real X/Y/Z cases proving no domain id/structural role/veracity value ever reaches it, claim-visibility gating (unresolved deduction/conclusion absent, appears the instant it's proven), hint-level-revealed progression, the fixture's gated-evidence case (X/Y/Z have none since 1.9.1), and that the Author Inspector view stays unfiltered (real ids, ground truth, proof sets). |
| `deduction_lab_recorder_test.gd` | FAST + FULL | Milestone 1.10 — `DeductionLabRecorder`: off by default, Start/Stop/Clear, strictly-increasing sequence numbers and non-decreasing elapsed_ms via an injected fake clock, session-signal wiring with idempotent double-connect protection, `author_debug` vs. `player_preview` source tagging, the exported schema's exact fields, stable serialization, safe filename generation (including a path-traversal attempt), and export-failure handling — throwaway `user://` directory cleaned up before/after. Reused completely unmodified by both Prototype A (`"statement_contradiction"`) and Prototype B (`"clue_connection"`) — see the two rows below. Prototype C (`"timeline_reconstruction"`) reuses it the same way, and Milestone 1.14's resolution events are recorded by the controllers through the same public `record()`. Milestone 1.14.1 adds `event_schema_version` (2) to the exported dict's expected top-level fields and a dedicated contract test that drives a real `PrototypeAController` failure through a recorder and asserts the exported event vocabulary actually matches the declared version — the renamed `run_resolution_result_changed` type and `run_resolution_result_before`/`after` payload keys present, the retired v1 `resolution_tier_changed`/`tier_before`/`tier_after` absent (`docs/deduction-lab.md`, "Recorder schema"). |
| `deduction_lab_scene_test.gd` | FULL only | Milestone 1.10 — instantiates `Main.tscn`: DebugPanel integration (new tab, button wiring), F1 hide/show session preservation, Player/Author mode instantiation (every Author-only debug action button and every recorder control clicked once through the real UI), malformed/empty case-selection safety, bilingual coverage of the non-canon badge and the Overview tab's rendered text. Does **not** cover the "Launch Prototype A/B/C" buttons themselves — that launch wiring is exercised by `prototype_a_scene_test.gd`/`prototype_b_scene_test.gd`/`prototype_c_scene_test.gd` below, against the same `DeductionLab.tscn` instance. Milestone 1.14.1 adds `_test_prototype_overlay_hides_lab_content()`: opening any Prototype overlay hides `%CenterPanel`/`%DimBackground` (not merely dims them), releases keyboard focus a Lab control held, confirms the overlay's `mouse_filter` blocks every click from reaching underneath, launching a second prototype closes the first and keeps the Lab hidden, F1 hide/show never restores the Lab's content while a prototype is still open, and returning restores the Lab's content and session (selected case) exactly. |
| `resolution_policy_test.gd` | FAST + FULL | Milestone 1.14 — `ResolutionPolicy` (`docs/resolution-policy.md`) alone, no content: Independent start; one/two failures → Guided; third failure → `assistance_required` + Assisted; blocked commits while locked; assistance acknowledgement; two assisted failures → `partner_available`; partner resolution never counted as a player commit; valid non-resolving commits never a penalty; hint levels 1–2/3–4; one-way run results across units with run-wide failure counting (a new unit's own phase/failures always reset, the run result never does); `begin_next_unit()` refused on an unresolved unit; transition-event order (local vs. run-wide, see below); result snapshots; a source check that no prototype controller redefines the limits; strict JSON round-trip `load_dict()` (rejecting an unknown `run_resolution_result`/`current_unit_phase`, a backward-inconsistent one, etc.); determinism. Milestone 1.14.1 renamed the accessors under test from `get_tier()`/`get_phase()` to `get_run_resolution_result()`/`get_current_unit_phase()` (and `get_failure_count()`→`get_current_unit_failures()`, `get_remaining_standard_attempts()`→`get_standard_attempts_remaining()`) for explicit naming — see `docs/resolution-policy.md`, "Local unit state vs. run result" — and the transition-event test now expects `run_resolution_result_changed` (never the retired `resolution_tier_changed`). Add a new policy rule's test here — a mechanic's use of the policy belongs in that prototype's own controller test. |
| `prototype_a_controller_test.gd` | FAST + FULL | Milestone 1.11 — `PrototypeAController` (`docs/prototype-a.md`): fresh session per run, isolation from a `DeductionLabController`'s own session, statement/evidence navigation, one-evidence-only enforcement, required/optional/wrong-attempt classification through the real `DeductionEvaluator`, idempotent resubmission, round/prototype completion via `acknowledge_feedback()`, hints (Prototype-A-owned data, not the base contract's), stats/abandonment, and a structural check that no `DeductionSession` mutator is ever called directly. Uses `deduction_fixtures.gd`'s `prototype_a_case()`. Milestone 1.14 adds the resolution policy: credibility consumed only by genuinely evaluated failures (the optional lie, an alternate refutation — fixture `e_alt` — duplicates and locked presentations cost nothing), assistance after three failures (targeting the statement, never the evidence), assisted success, partner resolution through `commit_attempt()`, hint tier changes, completion `resolution` payload and `prototype_restarted`. |
| `prototype_a_presenter_test.gd` | FAST + FULL | Milestone 1.11 — `PrototypeAPresenter`: the player view's exact allow-listed keys, a spoiler sweep against real X/Y/Z content, round-scoping (no future-round text), evidence text gated on opened, hint progression, and `build_feedback()`'s mapping for every evaluator category. Milestone 1.14 adds `resolution_status` keys and localization, no raw policy ids as values, assistance absent until acknowledged (then naming the statement and the level-2 category hint, never an accepted evidence name) on real X/Y/Z, partner content hidden until used, rebuttal/duplicate/locked/notice mapping, and the 8-line localized completion summary. Milestone 1.14.1 renames the `resolution_status` allow-list (`status_text`/`tier_label`/`attempts_remaining`/`attempts_total` → `current_status_text`/`run_result_text`/`run_result_label`/`standard_attempts_remaining`/`standard_attempts_total`) and adds `_test_run_result_does_not_leak_into_fresh_round()` on real X/Y/Z: after round 1 finishes Assisted via partner resolution, round 2's `current_status_text` reads a completely fresh "Credibility: 3/3" (never mentioning the run result), the view carries no `assistance` key, and `run_result_text` explicitly reads "…reached during an earlier challenge" while still saying Assisted. |
| `prototype_a_content_test.gd` | FAST + FULL | Milestone 1.11 — X/Y/Z walked once in structural-role terms: true/incomplete/required×2/optional statement-role coverage, each target solvable with one evidence item actually in the pool, every pool item available from the start, true/incomplete statements never refutable, translations resolve, and the Prototype A structural-signature shape matches across all three cases. |
| `prototype_a_scene_test.gd` | FULL only | Milestone 1.11 — launching from the Lab (with/without an active Lab case), reading/selecting evidence and presenting it through real buttons, wrong/correct/optional feedback, hint reveal, round transition and completion, restart/return confirmation (cancelling preserves the run exactly), recorder controls and the exported schema/event vocabulary, F1 hide/show session preservation, bilingual coverage. Milestone 1.12 adds `_test_continue_button_stays_reachable_with_long_feedback()` — the Continue-button layout regression: structural proof Continue lives in `%Footer`, outside the scrolling `%BodyScroll`, plus behavioral proof it stays visible/keyboard-focused with real-then-synthetic-long feedback text in both locales (see `docs/prototype-a.md`, "Layout", for why this is checked structurally/behaviorally rather than by real pixel geometry). Milestone 1.14 adds credibility → assistance → partner resolution through real buttons (text status, no answer revealed, Present disabled while locked, `[Partner focus]` marker), the Assisted completion summary, attempts surviving a locale switch/F1/cancelled restart, a recorded restart, and the resolution actions living in the fixed footer. Milestone 1.14.1 splits every tier-in-status assertion into the current round's own `%ResolutionStatusLabel` (never mentions the run result) and the separate `%RunResultLabel` (always the run-wide result, with the "reached in an earlier challenge" wording once part 2 starts fresh while the run stays Assisted — the milestone's core regression), extends `_test_resolution_actions_live_in_fixed_footer()` to also prove `%PresentButton`/`%HintButton` live in `%Footer`'s `%ActionRow` rather than the scrolling body, and checks the exported recording's `event_schema_version` (2) plus the presence of `run_resolution_result_changed`/absence of the retired `resolution_tier_changed`. |
| `prototype_b_controller_test.gd` | FAST + FULL | Milestone 1.12 — `PrototypeBController` (`docs/prototype-b.md`): fresh session per run, isolation from a `DeductionLabController`'s *and* a `PrototypeAController`'s own sessions, clue placement/removal/replacement, exact slot-capacity enforcement (including that different rounds may declare different `slot_count`s, read from content, never hardcoded), duplicate prevention, order-independence, classification through the real `DeductionEvaluator`, idempotent resubmission, round/prototype completion, hints via the **real base hint API** (not a private copy, unlike Prototype A), stats/abandonment, and a structural check that no `DeductionSession` mutator is ever called directly. Uses its own fixture, `deduction_fixtures.gd`'s `prototype_b_case()` (two rounds with deliberately *different* slot counts). **Rewritten in Milestone 1.14** for the draft/batch model: two independent unverified drafts, editing/saving/switching never evaluating, Commit Theory requiring every draft, one correct + one incorrect draft committing neither (and carrying no per-draft/per-clue detail), the second failure naming only an affected question, identical failed theories blocked, primary/alternate (fixture `e_f`) paths, both deductions committed through `commit_attempt()`, assistance targeting an invalid draft without inserting clues, partner batch resolution keeping valid drafts, telemetry and restart. |
| `prototype_b_presenter_test.gd` | FAST + FULL | Milestone 1.12 — `PrototypeBPresenter`: the player view's exact allow-listed keys, a spoiler sweep against real X/Y/Z content (no domain id/structural role/target/relation ever reaches it), round-scoping (a future round's question/target text is absent), `resolved_claim` absent before success and populated only after, hint progression, and `build_feedback()`'s mapping for every evaluator category. **Rewritten in Milestone 1.14**: draft entries that never reveal correctness (a correct and a wrong draft render identically), `resolved_claims` absent until the theory is accepted, generated wrong drafts driving coarse → guided → assistance feedback on real X/Y/Z with no clue names, assistance using the base ladder's category level only, partner notes, uncounted-reason mapping, localized status and the 10-line summary. Milestone 1.14.1 renames the `resolution_status` allow-list the same way as `prototype_a_presenter_test.gd`'s (see that row) and asserts the current-unit status never mentions the run result while the separate run-result line does. |
| `prototype_b_content_test.gd` | FAST + FULL | Milestone 1.12 — X/Y/Z walked once in structural-role terms: exactly two rounds targeting D1 and D3; D1's primary AND alternate 3-item paths both solve with `slot_count: 3`; D3 requires all 3 authored clues (no 2-of-3 subset resolves it — the audited reason round 2 uses 3 slots, not the milestone brief's illustrative 2, backed directly by `deduction_cases_test.gd`'s pre-existing insufficiency assertions); no proper subset of either accepted proof resolves its target; every accepted proof item is available from the start and pool-listed; translations resolve; the Prototype B structural-signature shape matches across all three cases; and the Prototype A/B separation audit — Prototype A's own single accepted clue does not, alone, solve Prototype B's D3 target — machine-checked against real content. |
| `prototype_b_scene_test.gd` | FULL only | Milestone 1.12 — launching from the Lab (with/without an active Lab case, and that launching Prototype B hides rather than resets Prototype A if it was open, and vice versa), reading/placing/removing/replacing evidence through real buttons, Connect disabled until every slot is filled, wrong-connection feedback with the board preserved, D1's primary AND alternate paths, D3 needing all three clues, hint reveal, round transition and completion, restart/return confirmation, recorder controls and the exported event vocabulary/schema (including normalized `evidence_ids`), F1 hide/show session preservation, all three cases solving round 1, bilingual coverage, and its own copy of the Milestone 1.12 Continue-button layout regression (same rationale as `prototype_a_scene_test.gd`'s). **Rewritten in Milestone 1.14**: draft tabs retaining content, Save Draft costing nothing, Commit Theory disabled until both drafts are complete, a mixed batch revealing and unlocking nothing with progressive feedback, both D1 paths completing, assistance and partner resolution via the footer, the Assisted summary, restart recording, attempts preserved across F1 and locale switches, all three cases, and the long-feedback layout regression. Milestone 1.14.1 splits tier assertions into `%ResolutionStatusLabel` (current draft/commit state only)/`%RunResultLabel` (run-wide result), extends the layout regression test to prove `%CommitTheoryButton` lives in `%Footer`'s `%ActionRow` rather than the scrolling body, checks `event_schema_version` (2), and asserts the retired v1 event vocabulary (`round_started`/`connection_submitted`/`connection_result`/`round_completed`/`resolution_tier_changed`) never appears in a real export. |
| `prototype_c_controller_test.gd` | FAST + FULL | Milestone 1.13 — `PrototypeCController` (`docs/prototype-c.md`): fresh interaction state per run, isolation from a `DeductionLabController`'s/`PrototypeAController`'s/`PrototypeBController`'s own state, fixed events locked against every mutator, select/place/move/remove (including two events legally sharing a slot), incomplete-board submission gating, invalid-timeline rejection with retained placements, identical-resubmission blocking until a move, acceptance via the real `TimelineEvaluator` (not exact-solution equality, proven with two different accepted placements), an optional constraint never blocking acceptance, hints (Prototype-C-owned, a single flat ladder), the final claim check (wrong "Fits" preserves state and allows retry; correct "Impossible" resolves it), idempotent `acknowledge_claim()`, stats/abandonment, and a structural check that `DeductionSession` is never referenced — the one prototype controller with no session at all. Uses its own fixture, `deduction_fixtures.gd`'s `prototype_c_case()`. Milestone 1.14 adds: moves never consuming commits, any previously failed placement blocked, category-then-fact feedback, assistance naming the critical PAIR without moving events, a partner timeline applied only when `TimelineEvaluator` accepts it (authored, else enumerated; never an unaccepted placement), the claim needing a verdict + supporting fact (every supporting fact accepted, unrelated facts and "Fits" rejected, the timeline untouched), claim feedback levels/duplicates, claim assistance/partner resolution, telemetry and restart. The fixture gained a second ruling-out fact (`c_b_after_fixed`). |
| `prototype_c_presenter_test.gd` | FAST + FULL | Milestone 1.13 — `PrototypeCPresenter`: the player view's exact allow-listed keys (18 before acceptance since Milestone 1.14); a spoiler sweep against real X/Y/Z content both before AND after acceptance (no domain id/structural role/raw constraint field ever reaches it); the claim key's entire absence before acceptance and presence after; the resolution key's entire absence until the claim is correctly resolved (with the player's own interpolated time); fact text gated on opened; hint progression; and the violation/claim feedback mappings for every outcome. Milestone 1.14 adds the neutral verdict + justification form, progressive feedback on real X/Y/Z (no fact on the first rejection, one verbatim fact on the second), assistance gating (level-4 text, a relationship, no times), the labeled partner timeline, claim feedback levels, localized status and the 12-line summary. Milestone 1.14.1 renames the `resolution_status` allow-list the same way as `prototype_a_presenter_test.gd`'s (see that row). |
| `prototype_c_content_test.gd` | FAST + FULL | Milestone 1.13 — X/Y/Z walked once in structural terms: 7 events/2 fixed/5 movable; the authored solution offered and passing; every required constraint has a translated fact and every optional one doesn't; the universal-contradiction proof (every one of `DeductionValidator.enumerate_accepted_prototype_c_timelines()`'s ~8 accepted placements per case fails the disputed claim's constraint) — the one heavy, bounded check deliberately kept out of the always-on `DeductionValidator` for performance (~0.5s/case through the real evaluator, so ~1.5s for this file alone — the slowest of the pure deduction tests, an audited trade-off, see `docs/prototype-c.md`); an alternate valid timeline distinct from the authored one; an optional violation never blocking acceptance; a deliberately wrong placement rejected; translations resolve; and the Prototype C structural-signature shape matches across all three cases. Milestone 1.14 adds that `supporting_constraint_refs` equals `DeductionValidator.prototype_c_facts_ruling_out_claim()` and holds in every accepted timeline, and that the real controller accepts "Impossible" with exactly those facts and nothing else. |
| `prototype_c_scene_test.gd` | FULL only | Milestone 1.13 — launching from the Lab (with/without an active Lab case, and that launching Prototype C hides, never resets, Prototype A AND Prototype B if either was open), fixed events rendered locked with no buttons, select/place/move/remove through real buttons, Check disabled until complete then invalid-then-corrected with retained placements and visible violation feedback, an alternate valid timeline also accepted, fact inspection, hint reveal, the final claim phase (wrong then correct, with the interpolated time visible in the rendered label), completion with the 12-line resolution summary (Milestone 1.14), restart/return confirmation (cancelling preserves the run exactly), recorder controls and the exported schema/event vocabulary (including the normalized placement map), F1 hide/show session preservation, all three cases accepting their own authored solution, bilingual coverage, and the Milestone 1.12 long-feedback layout regression applied to this scene too. Milestone 1.14 adds category-only first feedback, the claim form (verdict alone disabled, unrelated fact rejected, supporting fact accepted), timeline AND claim assistance/partner resolution through the footer with `[conflict]` markers, the 12-line Assisted summary, restart recording, and attempts preserved across F1 and locale switches. Milestone 1.14.1 proves the claim unit — a fresh resolution unit right after the timeline finished Assisted — starts with a full budget on `%ResolutionStatusLabel` and never itself reads "Assisted", while the separate `%RunResultLabel` reads the "reached in an earlier challenge" wording; extends the layout regression to prove `%CheckButton` (in `%Footer`'s `%ActionRow`) and `%ClaimSubmitButton` (directly in `%Footer`) both live outside the scrolling body; and checks `event_schema_version` (2) plus the absence of the retired `resolution_tier_changed`. |
| `deduction_fixtures.gd` | n/a — fixture | Not a test — hand-built deduction case fixtures used by the tests above: `base_case()` (the deduction-foundation fixture, Milestone 1.9), `prototype_a_case()` (Milestone 1.11), `prototype_b_case()` (Milestone 1.12, two rounds with different slot counts), `prototype_c_case()` (Milestone 1.13, one fixed and two movable timeline events with a disjoint optional claim constraint). Never reaches `ContentDB`, so a fixture can be as deliberately broken as a negative test needs. Milestone 1.14: `prototype_a_case()` gained an alternate single-evidence refutation (`e_alt`), `prototype_b_case()` an alternate 3-item path (`e_f`), `prototype_c_case()` a second ruling-out fact (`c_b_after_fixed`) plus `supporting_constraint_refs`. |
| `test_helpers.gd` | n/a — helper | Not a test — shared `isolate_save`/`isolate_locale`/`finish` boilerplate every file above uses. |

## `ContentValidator` / `ContentDB` — `_test_content_loaded`

Asserts every content category loaded at least the expected count, and —
this is the important one — that `content_db.get_last_validation_result()`
reports **zero errors and zero unexpected warnings** against the real
sandbox content (`KNOWN_ACCEPTED_WARNINGS` names the one documented
exception — `test_repeatable_pulse`'s deliberately test-only `pulse_flag`
dependency, see `docs/testing.md`). Any new content shape or new placeholder
content must keep that true, and a *second* unexpected warning still fails
this check.

Add a check here when: you add a new content *category* (new top-level
`data/` folder) or a new bulk getter on `ContentDB` that other tooling will
rely on (`get_all_*_ids`).

## `ConditionEvaluator` — `conditions_test.gd`

Pins down the properties that matter more than the happy path:

- `evaluate(null)` → true; an unknown key, an empty object, a non-Dictionary,
  and a non-array `all` all fail **closed** (never silently unlock).
- `"equals"` is a recognized modifier alongside `"flag"`, not an unknown key.
- `explain()` flattens a top-level `all` into one entry per part, but keeps
  an `any` as a single grouped entry (spelling out the alternatives with
  " OR ") — this is a debug-UI correctness property, not just a data check
  (`docs/architecture.md`, "The condition mini-language").
- A condition object stacking two checks (`{"flag": ..., "has_evidence": ...}`)
  is rejected by the validator, and the error names the check that would
  actually have won (`ConditionEvaluator.KEYS` order:
  `["all", "any", "not", "flag", "has_evidence", "visited_location",
  "examined", "interaction_complete"]` — see `COMPOSITE_KEYS`/`LEAF_KEYS` in
  `condition_evaluator.gd`), not just "this is invalid."
- Non-boolean flags never leak past `get_flag()`'s typed return; setting a
  flag to `false` still records it (so the debug panel and a save both show
  it).

Add a check here when: you add a new leaf shape (also update `LEAF_KEYS` +
`ContentValidator` + `docs/content-guide.md`'s conditions table in the same
change — this is a schema change, see the SKILL.md "Regression surface"
section), or change `evaluate()`'s precedence/failure behavior at all. This
file is independent of `smoke_test.gd` — it's the one place a new leaf
shape's test goes (see `docs/testing.md`).

`_test_explain_tree()` (Milestone 1.8) covers `explain_tree()` — the nested
ALL/ANY/NOT breakdown built for the Case Debugger's Condition Inspector
(`docs/case-debugger.md`). It's additive to `explain()`'s own flattening/
grouping behavior above, not a replacement — a new leaf shape's `evaluate()`
test still only needs `_test_leaf_shapes()`; only touch `_test_explain_tree()`
if you change what a tree *node* looks like (its `passed`/`children` shape).

## `EffectRunner` — `effects_test.gd`

Direct `EffectRunner.run(...)` calls against a fresh `GameState`, asserting
the resulting state (never a private method call): each effect type's happy
path, that a signal (`flag_changed`/`evidence_added`/`evidence_removed`/
`interaction_seen`) only fires for a REAL change (not a no-op re-run), that
`add_evidence`/`remove_evidence` are idempotent, that an unrecognized effect
`type` is a safe no-op (no state mutated), and that a whole effects list is
safe to run more than once with the same net result (chapters re-run
`entry_effects` on `jump_to_chapter`). `_test_progression_flow` and
`_test_event_system` in `smoke_test.gd` still exercise effects as
*consequences* of real content (e.g. presenting the key sets
`hallway_unlocked`) — that integration-level coverage is complementary, not
redundant with this file's isolated unit-level checks.

Add a check here when: you add a new effect `type` (also update
`ContentValidator._validate_effects()` and `docs/content-guide.md`'s actions
list — schema change) or change idempotency (does running it twice still
no-op correctly, like `add_evidence` on an already-held item). This file is
independent of `smoke_test.gd` — it's the one place a new effect type's test
goes (see `docs/testing.md`).

## `DialogueManager` / `Investigation` — `_test_progression_flow`, `_test_interaction_guards`

`_test_progression_flow` is the fullest single test in the file — it's the
"critical path" for `case_00_sandbox`: talk (before/after a flag flips a
choice's availability) → examine (grants evidence, sets a flag) → repeat
examine (variant resolves to "after," no duplicate evidence) → a second
examine point → present (specific match unlocks a topic + a destination) →
present (generic fallback) → move both directions → another examine (an
`examined`-gated flavor variant with **no** evidence, proving that condition
doesn't need a flag) → present to a second NPC → an `all`-gated topic
(needs two evidence items) → an `interaction_complete`-gated topic. When
`case_00_sandbox`'s content changes shape, or a new representative sandbox
case replaces it, this is the function whose flow needs re-deriving — walk
the location/dialogue JSON the same way this function does, verb by verb,
rather than guessing a new path.

`_test_interaction_guards` is the correctness guarantee behind the UI
convenience in `InvestigationView`: a verb (examine/talk/move) rejected
because `DialogueManager.is_active` must mutate **no** state at all — not
mark anything seen, not grant evidence, not change location. Also covers
`DialogueManager.stop()` as the escape hatch and an unknown dialogue id
failing `start()` cleanly.

Add a check here when: you add a new verb, change variant/present_response
resolution order, or change what counts as "busy" (`Investigation._is_busy()`).

## `EventManager` — `_test_event_system`

Continues directly from `_test_progression_flow`'s end state (test_room,
character_a present, holding `test_key`/`test_badge`, `hallway_unlocked`
true) specifically to prove events fire off state real gameplay actions
built up, not just hand-set flags. Covers, in order:

- an event with two conditions (`interaction_complete` + `has_evidence`)
  firing exactly when the second one becomes true from a real Talk action;
- an **event chain**: a second event whose only condition is a flag the
  first event's effect just set, firing in the same evaluation pass with no
  further player action;
- character presence changing as a pure consequence of the flag flip (no
  new code — the NPC's own presence `condition` in a second location's JSON
  now passes);
- new content becoming available off the same flag (an examine variant);
- a `"once"` event **not** refiring on an unrelated later state change;
- `EventManager.force_trigger()` succeeding for a known id (bypassing
  conditions) and failing cleanly for an unknown one;
- `"repeatable"`: fires on a false→true transition, does **not** refire
  while the condition stays true through an unrelated change, and fires
  again on the next false→true transition.

Add a check here when: you add an event, change `trigger_policy` semantics,
or touch the fixed-point evaluation loop (`_evaluate_all()` /
`MAX_EVALUATION_CYCLES`) — at minimum re-verify one existing chain still
resolves in one pass and the cycle cap still logs instead of hanging.

`events_test.gd` (independent, resets per `_test_*`) adds: negative trigger
(has_evidence still missing → no fire), positive trigger, an isolated event
chain proven to fire both events in one pass, a chapter-scoped topic
confirmed absent from an unrelated flat case, and a "once" event's fire
count checked against ten unrelated reevaluation passes.
`duplicate_execution_test.gd` extends that last check to chapter/case
completion specifically (a real completion, then redundant reevaluation,
asserting `chapter_completed`/`case_completed`/`chapter_activated` signal
counts stay put) — add a check there instead of here for a new "does this
fire more than once" regression.

## `CaseManager` — `_test_case_system`, `_test_case_debug_tools`

Deliberately calls `case_manager.start_case("test_case")` to reset state
first — it must not depend on whatever `_test_save_load` left behind. Covers
the full two-chapter Test Case: starting chapter activation, a completion
explanation reporting unsatisfied conditions with a breakdown, a **save/load
round trip mid-chapter** (chapter not falsely marked complete after
loading), completing chapter 1 via its real `completion_event` → automatic
activation of chapter 2 (`entry_effects` running, a chapter-scoped topic
becoming reachable only now), a **second** save/load round trip mid-chapter-2
(chapter 1 not un-completed, `chapter_completed` not re-firing), completing
chapter 2 → case completion (`case_completed` firing, `get_completed_chapters`
listing both) — then confirms a flat case (`case_00_sandbox`) is entirely
unaffected (`get_current_chapter_id()` stays `""`,
`force_complete_current_chapter()` fails gracefully).

`_test_case_debug_tools` covers `jump_to_chapter` (teleport — runs
`entry_effects`, does **not** mark the skipped chapter complete),
`force_complete_current_chapter` (forces the real `completion_event` through
`EventManager.force_trigger()`, so it still actually completes the chapter
and cascades to case completion), and `reset_case`.

Add a check here when: you add a chapter/case, change how completion is
detected, or change what `entry_effects`/`next_chapter` do on transition —
the two things to specifically re-verify are "entry effects run exactly
once per real transition" and "a completed chapter doesn't re-fire
`chapter_completed` after a load."

## `SaveManager` / `GameState` persistence — `_test_save_load` (+ the round trips inside `_test_case_system`)

Captures location/evidence/flags/`seen_interactions` before saving, resets
via `start_new_game`, loads, and asserts every captured value came back —
including that a triggered `"once"` event's state survived and did **not**
refire just because reload re-evaluates every event against the restored
(still-satisfying) state. This is the test that actually proves
`is_event_triggered()` wins over "conditions still true" after a load.

Add a check here when: you add anything that needs new persisted state —
first check whether it actually needs a new field (see SKILL.md's "Save/load"
section) before assuming it does.

`save_load_regression_test.gd` (independent, own throwaway save file) is the
dedicated persistence suite: an exact round trip of every persisted field,
the "once" event / no-refire guarantee above repeated in isolation, and a
mid-chapter-2 save/load specifically checked to NOT re-emit
`chapter_activated`/`chapter_completed` for anything the save already
reflects (see `docs/case-system.md`'s "no `entry_effects` re-run" on load).
Prefer adding a new persistence regression check there — it doesn't require
replaying the rest of the narrative walkthrough first.

## `LocaleManager` — `_test_localization`

Confirms the CSV actually loaded into real `Translation` objects (not just
"a dictionary somewhere"), that a static UI key and a content-driven key
both resolve correctly in both locales, that an unsupported locale is
rejected (fails closed, mirroring `ConditionEvaluator`'s stance), that the
preference persists to a `ConfigFile`, that an **already-instantiated**
`InvestigationView` re-renders correctly on a live locale switch (not just a
freshly-opened one), and that `ContentValidator._validate_translatable`
reports a key missing from either locale.

Add a check here when: you add a new translatable field type, a new locale,
or a new screen that should react live to `locale_changed`.

## `DebugPanel` (Case Debugger) / scene wiring — `_test_scene_instantiation`

Not a simulated click (headless has no way to see a rendered click's
result) — instantiates `Main.tscn`/`TitleScreen.tscn` and asserts the
`mouse_filter` values the click-routing design requires, that a runtime
list rebuild (`UiUtil.clear_children`) leaves no stale nodes, and that
re-rendering the action list while `set_interactive(false)` never leaves a
button enabled. `DebugPanel` itself is instantiated and `open()`/`close()`
toggled with `visible` asserted — never visually confirmed to render
correctly (see `docs/architecture.md`'s "Known limitations" — a human should
press F1 in a running build after any DebugPanel change). The Case
Debugger's own underlying logic (Milestone 1.8) — `explain_tree()`, the
`find_*_producers()` lookups, `debug_reset_trigger()` — is unit tested where
it lives (`conditions_test.gd`, `dependency_analysis_test.gd`,
`events_test.gd` respectively, per the rows above), not here; this test stays
scoped to scene instantiation and click-routing plumbing, per
`docs/case-debugger.md`'s own "no pixel-perfect UI tests" stance.

Add a check here when: you change an overlay's `mouse_filter` chain, add a
new overlay `Main.gd` wires up, or change `DebugPanel`'s node structure in a
way that could break instantiation (a renamed unique name, a removed
`ConfirmationDialog`, etc.). A new tab's *data* (what it displays, what
action it performs) belongs in the underlying system's own focused test file
instead — see `docs/case-debugger.md`, "Automated test coverage".


## Core loop sandbox (Milestone 1.16) — `core_loop_*_test.gd`

Source of truth: `docs/core-loop-sandbox.md`; test layout: `docs/testing.md`,
"Core loop tests". Shared helpers + the sandbox's ids:
`core_loop_test_support.gd` (`CoreLoopTestSupport` — `play_until(runtime,
"briefing"|"b1"|"a1"|"b2"|"timeline"|"claim")`, `gather_*`, `solve_*`).

- `core_loop_mechanics_test.gd` (pure) — controller production context
  (shared session, round scope, acquired pool, help-only policy), snapshot
  round trips/rejection, debug defaults unchanged. Add here: a new context key
  or snapshot field on a prototype controller.
- `core_loop_validation_test.gd` — one fixture per `CoreLoopValidator` rule,
  plus errors reaching `ContentValidator`. Add here: any new chapter-contract
  rule (mutate the real chapter, expect one error substring).
- `core_loop_runtime_test.gd` — the full route through `ChapterRuntime` with
  both sides of every lock, consequence idempotency/attribution, duplicates,
  help/partner, restart isolation, recorder + summary. Add here: new runtime
  behavior (commands, phases, consequences).
- `core_loop_save_test.gd` — save at each checkpoint -> NEW runtime -> load,
  nothing replayed; exact mid-mechanic resume; migration; corrupt and
  half-applied snapshots rejected whole. Add here: anything newly persisted.
- `core_loop_scene_test.gd` (FULL only) — real screens and visible buttons
  from the title screen to the Result screen, Continue at several
  checkpoints, VI/EN, footer layout, visible-text leak scan. Add here: a new
  screen, control or routing rule.

Traps already hit: never type a variable as `ChapterRuntime`/`CoreLoopPresenter`
in a `-s` script (they reference autoloads — the compile-order trap poisons
the class for the whole process; use `RefCounted` and `load()`); compare
snapshots after a JSON round trip on BOTH sides (`1 != 1.0` in Dictionary
equality); press buttons only through a visibility check (a hidden button's
`pressed` signal still fires and masks routing bugs).
