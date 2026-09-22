# Core-loop chapter template

A complete, valid, **non-canon** core-loop chapter over the dummy mystery
`proto_z_customs_parcel` — the one deduction case no sandbox uses. Copy it to
start a new chapter; read `docs/core-loop-authoring.md` for the why of every
field.

This folder is **not** loaded by the game: ContentDB only reads `data/`, and
`docs/templates/.gdignore` keeps Godot from importing `strings.csv` as a
translation. `scenes/test/core_loop_template_test.gd` injects it at runtime
and proves it validates clean and plays to completion (primary route,
documented alternate B path, alternate timeline) through the unchanged
runtime.

## What it demonstrates

| Contract piece | Where |
|---|---|
| Non-canon metadata | `case_tpl_parcel.json` `metadata.canon: false`; chapter `core_loop.canon: false` |
| Selectable sandbox | `case_tpl_parcel.json` `"sandbox_selection": {"order": 3}` (no `new_game_entry`) |
| Briefing / result | `core_loop.briefing`, `core_loop.result` |
| Evidence links | `core_loop.evidence_links` (nine items, one optional) |
| Phases | briefing → investigation_1 → confrontation → investigation_2 → timeline → final_claim |
| B unit | `b1_scanner` (round_1, two documented paths), `b2_fence` (round_2) |
| A unit | `a1_felix` (round_1, one required contradiction) |
| C unit | `c1_timeline` (timeline, then final claim; `timeline_accepted` with `"effects": []`) |
| Offer conditions | `has_evidence` / `any` / `interaction_complete` / `flag` |
| Consequences | each unit's `consequences` (`set_flag` unlocks read by the next phase) |
| Locked-then-available interaction | Felix's `confront` topic (flag), the yard destination (flag), `wire_ends` (examined-gated) |
| Optional interaction | the `yard_camera` examine point (a linked red herring no answer needs) |
| Localization keys | `strings.csv` (CASE_/CHAPTER_/CL_/LOC_/DLG_/EVID_TPL_…) |
| Completion event | `tpl_chapter_01_complete` ← the final consequence's flag |

## Using it

1. Copy `data/*` into the project's `data/` (same sub-folders) and append
   the rows of `strings.csv` (without its header) to
   `localization/strings.csv` — CRLF line endings, every field quoted.
2. Rename every `tpl_` / `TPL_` id and key to your chapter's prefix; give
   `sandbox_selection.order` an unused number (1 and 2 are taken).
3. Point `deduction_case` and the `evidence_links` values at your deduction
   case; pick its `prototype_b` / `prototype_a` rounds; update
   `documented_paths`.
4. Replace the placeholder text (keep EN and VI).
5. Validate, simulate and inspect (`docs/core-loop-authoring.md` §8–10).

## Save / resume

Nothing to author: the runtime checkpoints the run at every durable step,
Continue resumes this chapter directly, and a save whose chapter definition
no longer matches (renamed units/consequences) is rejected whole rather than
half-loaded.
