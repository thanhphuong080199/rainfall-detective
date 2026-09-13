# Prototype Deduction Cases X / Y / Z — audit (Milestone 1.9, hardened in 1.9.1)

> **NON-CANON.** These three mysteries are disposable playtest material for
> comparing Prototype A (statement contradiction), B (claim/clue connection)
> and C (timeline reconstruction). None of their people, places or events
> belongs to the game's story or world. Every file says so in
> `metadata.canon: false` / `metadata.note`. Do not reuse them in real content.

Files: `data/deductions/prototypes/proto_x_archive_ledger.json`,
`proto_y_lab_sample.json`, `proto_z_customs_parcel.json`. Text lives in
`localization/strings.csv` under `DED_PROTO_X_*`, `DED_PROTO_Y_*` and
`DED_PROTO_Z_*`. The data contract is in `docs/deduction-system.md`.

This document is written so the reasoning can be audited **without reading
any code**. `DeductionValidator` machine-checks what it can: reachability,
depth, references, timeline consistency, and identical structure.
`deduction_cases_test.gd` checks that the authored proof can't be completed
without the exclusive-control evidence. Whether each inference is *rational*
is a human judgment, which is what this page, its proof obligations and its
"Human audit checklist" are for.

## 0. What Milestone 1.9.1 changed, and why

| Defect confirmed in the 1.9 audit | Fix |
|---|---|
| The conclusion {D2 "had opportunity and access", D3 "staged"} was only a *best explanation*. Someone else could still have used the credential or staged the scene. | D2 is now `candidate_exclusive_control`: D1 + custody + a zone-closure record, under a stated credential rule (no copies, no remote use). The old D2 survives as the true but insufficient `candidate_had_opportunity`, which the conclusion never accepts. |
| The custody record became available only after D1 was committed (`unlock_requires`). A private thought created evidence. | No evidence is gated. D1 only makes the record's relevance apparent. |
| The staging clues differed in kind (X glass-fall direction, Y screw reachability, Z wire bend), with each rule buried inside the contradiction item. | One reasoning pattern: a sign, a separate illustrated reference stating the same rule ("…bends away from the side the force came from"), and a part bent toward the outside. So the opening was forced from inside. |
| The alternate alibis were weaker than the primary ones (X: posting time only; Z: send time only), and the primary alibis placed a card or ticket, not the person. | Primary alibis are identity-checked (gate camera / desk camera / photo ID). Alternate photos show the owner next to an in-frame clock. |
| The staging signs didn't rule out someone entering through the opening after it was forced. | Each sign states that nothing crossed the opening afterwards (undisturbed sill dust / hatch dust / no prints across the gap). |
| Roles presupposed guilt (`culprit_had_access`, `culprit_custody_denial`, `culprit_intrusion_claim`). | Renamed `candidate_exclusive_control`, `candidate_custody_denial`, `candidate_staging_claim`. The template is now `credential_misuse_v2`. |
| "Maximum depth 2" was ambiguous once a conclusion sat on top of D2. | One definition: `docs/deduction-system.md`, "Inference depth". |

## 0.1 What Milestone 1.10 audited and closed (the "already inside" gap)

Milestone 1.10 (Deduction Lab Shell) re-audited the exclusive-control
argument for a remaining loophole: R3's evidence said "nobody else *enters or
leaves*" during a monitored window, which is consistent with a third party
having already been inside the zone *before* the window started (never
seen "entering or leaving" because they were simply already there) — the
same person could then have handed the credential to, or otherwise been
present alongside, the candidate without the camera log ever contradicting
that. The conclusion silently assumed the zone was empty at the start, which
R3's text never actually stated.

**Fix:** `custody_continuity`'s evidence text (`e_wing_camera` /
`e_corridor_camera` / `e_cage_camera`) now explicitly states that the
last-seen check *itself* (the same 19:30/20:30/06:00 check R4 already
anchors to) finds the zone empty of people, immediately before the camera's
monitored window begins — not merely that nobody was seen crossing the
entrance afterwards. This is a **text-only** change (localization/strings.csv
only): no new evidence item, no new claim, no depth or structural-signature
change, since `DeductionValidator.structural_signature()` never hashes
evidence `text`. The fact is independently available from the start (this
evidence has no `unlock_requires`, in any of the three cases, both before
and after this change) — it is not unlocked by the conclusion it helps
prove.

See `docs/deduction-lab.md` for the regression test
(`deduction_cases_test.gd`'s `_test_zone_verified_empty_before_window()`)
that asserts, for all three cases and both locales, that this fact is
present in the evidence text.

## 0.2 What Milestone 1.11 (Prototype A) added

`candidate_staging_claim` (`st_oren_break_in` / `st_priya_vent_entry` /
`st_felix_fence_entry`) gained a second, **alternate**, single-evidence
`refutes` proof set — `staging_sign` alone (`e_forced_window` /
`e_open_hatch` / `e_cut_fence`) — added identically, by role, to all three
cases. This does not touch D1/D2/D3 or the conclusion: `candidate_staging_
claim` is a terminal statement, never an input to another proof. Its
`compatible: [staging_sign]` entry was removed, since that evidence is now a
full proof-set requirement rather than merely consistent-but-insufficient.

The original two-evidence proof set (`physical_rule_or_reference` +
`staging_contradiction`, the taught-rule + bent-direction pair) is
unchanged and remains the primary path — Prototype A's UI can't reach it (it
only ever submits one evidence item per attempt), so it stays a dormant,
harmless alternate for Author Inspector or any future multi-clue prototype.
The new alternate is independently sound: R4's own text already establishes
that the forced-opening debris lies on top of prints that were already
there, which alone proves the opening was forced from inside, after someone
had already reached the target — without needing the physical bend-
direction rule. See `docs/prototype-a.md` for the full Prototype A design
and `deduction_cases_test.gd`'s existing `_test_staging_rule_is_taught()`
for the older two-evidence path.

## 1. The shared proof graph (`structural_template: credential_misuse_v2`)

### Before (Milestone 1.9)

```
use_record + alibi (primary | alternate) + travel_fact ──► D1 credential_misused
D1 ══ unlock_requires ══► credential_custody               ← a thought made the record appear
D1 + credential_custody ──► D2 culprit_had_access          ← "had opportunity and access"
staged_intrusion_sign + staging_contradiction ──► D3 intrusion_staged
D2 + D3 ──► final_conclusion                               ← best explanation only
```

### After (Milestone 1.9.1)

```
 credential_use_record ──┐
 owner_alibi_primary ────┼─supports─► D1 credential_misused            (depth 1)
 travel_fact ────────────┘   alternate: owner_alibi_alternate instead of the primary alibi (depth 1)

 credential_custody ─────────supports─► candidate_had_opportunity      (depth 1, true, NOT proof of the act)

 D1 ─────────────────────┐
 credential_custody ─────┼─supports─► D2 candidate_exclusive_control   (depth 2)
 custody_continuity ─────┘

 staging_sign ───────────────┐
 physical_rule_or_reference ─┼─supports─► D3 staging_deduction         (depth 1)
 staging_contradiction ──────┘

 D2 + D3 ──supports──► final_conclusion   (synthesis layer: reports depth 3, exempt from the limit)
```

Terminal claims:

```
 D1 ─rules_out─► hypothesis_owner              red_herring_explanation + D2 ─rules_out─► hypothesis_bystander
 D3 ─rules_out─► hypothesis_outsider           red_herring + red_herring_explanation ─explains─► red_herring_explained
 credential_custody ─refutes─► candidate_custody_denial
 physical_rule_or_reference + staging_contradiction ─refutes─► candidate_staging_claim
 staging_sign ─refutes─► candidate_staging_claim  (Milestone 1.11 alternate — single evidence, see "0.2" above)
 red_herring_explanation ─refutes─► bystander_innocent_lie
 owner_alibi_primary ─supports─► owner_alibi_statement
 credential_custody ─supports─► owner_incomplete_statement
```

### 1.1 Case rules every case states in its own evidence

"Under the case rules" means under these six stated facts. The player must
apply them, but never needs to know them in advance.

| Rule | Role that states it | Content |
|---|---|---|
| **R1 credential** | `credential_use_record` | The credential works only when physically presented at the reader or seal. It can't be copied or operated remotely. The use location is inside a named zone. |
| **R2 custody** | `credential_custody` | The credential was signed out to the candidate before the use time T and returned after it. |
| **R3 zone closure** | `custody_continuity` | A check at the target's last-seen time confirms the zone is empty of people. From that moment, a camera covers the zone's only entrance: the candidate enters before T and leaves after T with the credential item, and nobody else enters or leaves before the candidate does. |
| **R4 last seen + no later crossing** | `staging_sign` | The target was intact at that check. Debris from the forced opening lies on top of fresh prints leading to the target. Nothing crossed the opening afterwards. |
| **R5 taught physical rule** | `physical_rule_or_reference` | An illustrated reference: the part bends away from the side the force came from. |
| **R6 travel + identity** | `travel_fact`, `owner_alibi_primary`, `owner_alibi_alternate` | The minimum trip time between the owner's location and the scene. The owner herself or himself is identity-verified, with a timestamp, within minutes of T. |

### 1.2 The proof, step by step (role form)

1. **D1 — credential misuse.** The credential was physically at the reader at
   T (`credential_use_record`, R1). The owner was verifiably somewhere else
   within minutes of T, and the trip takes longer than that gap (R6). So
   someone other than the owner presented the credential at T.
2. **D2 — exclusive control.** From D1, a non-owner physically presented the
   credential inside the zone at T (R1). R3's check finds the zone empty of
   people at the last-seen time, and from then on only the candidate crosses
   the entrance — so the candidate was the only person inside at any point
   up to T, including anyone who might otherwise have already been inside
   before the check. Cloning and remote use are excluded by R1. A handover to
   anyone else is excluded by R3, because the recipient would have had to be
   inside the zone, and nobody was, before or during the candidate's time
   there. R2 documents how the candidate had the credential. So **only the
   candidate could have presented it**.
3. **D3 — staging.** The opening was forced after someone had already walked
   to the target, and nothing crossed it afterwards (R4). The bent part
   points outward, and the reference says it bends away from the force (R5).
   So it was forced **from inside**, and it was never an entry.
4. **Conclusion.** Between the last check and discovery, the target could be
   reached only through the zone entrance, where only the candidate passed
   (R3), or through the forced opening, which was not an entry (D3). The
   credential use was the candidate's (D2). So the candidate performed the
   act, and the only person inside, the candidate, forced the opening to fake
   an outside entry.

### 1.3 Proof obligations (role form)

| Plausible alternative actor | Why still possible before D2/D3 | Eliminated by | Why that is sufficient |
|---|---|---|---|
| The **credential owner** (`apparent_suspect`) | the use record names their credential | D1 (R6 + R1), and R3 as well | identity-verified elsewhere, too far to travel, and the credential must be physically present |
| The **bystander** | on site, carrying a sealed container, lied about times | R3 (inside D2); the container is explained by `red_herring_explanation` | they never entered the zone |
| **Other people on site** (guard, contractor, whoever did the last check) | present near the time | R3 + R4 | the target was intact at the check, and nobody but the candidate entered the zone afterwards |
| Someone **already inside the zone** before the last-seen check (never seen "entering or leaving" the monitored window at all) | a camera that only reports entries/exits during a window can't rule out someone who was there before the window started | R3 (the check itself, not just the camera log) | the check confirms the zone held nobody at that moment, before the camera window even begins — so there is no "already inside" gap for the camera log to fail to cover |
| An **outsider through the forced opening** | the `staging_sign`, backed by `candidate_staging_claim` | D3 (R4 + R5) | forced from inside, after the walk to the target, with nothing crossing it afterwards |
| Someone with a **copied credential or remote access** | a log records a credential, not a face | R1 | the credential can't be copied or used remotely |
| Someone the candidate **handed the credential to** (inside the zone, before or during the candidate's own time there) | custody alone doesn't exclude a handover | R3 | the recipient had to be inside the zone at some point, and R3 shows nobody but the candidate ever was |
| The candidate **merely had the opportunity** | `candidate_had_opportunity` is true | the conclusion doesn't accept it | the conclusion requires D2, not opportunity |

**Jointly sufficient.** Every route to the target is covered: the zone
entrance (R3) and the forced opening (D3). The credential use is pinned to
one person (D2). Nothing in the conclusion depends on a lie, a motive,
suspicious behaviour, or staging whose author is unknown.

**What each prerequisite contributes, and what happens without it.** Checked
by `deduction_cases_test.gd` for each case:

| Removed | Effect |
|---|---|
| `custody_continuity` | the conclusion becomes unprovable. Custody alone is opportunity. |
| `credential_custody` | the conclusion becomes unprovable. There's no documented link between the candidate and this credential, and no "how access was obtained". |
| `physical_rule_or_reference` | the conclusion becomes unprovable. The staging contradiction is uninterpretable without the taught rule. |
| D2's proof (with opportunity + staging still proven) | the conclusion becomes unprovable |
| both owner alibis | the conclusion becomes unprovable (D1 fails) |
| only the alternate alibi, or the red herring | still provable. They are not load-bearing. |

**Honest redundancy note.** R3 alone also excludes the owner from the zone.
D1 stays a premise of D2 so the owner's innocence is shown by independent,
identity-checked records, not only by the candidate's camera log. R2 isn't
needed to *exclude* other actors, but it ties the camera's credential item to
the owner's credential and supplies the conclusion's "how access was
obtained".

### 1.4 Inference depth

D1 = 1, `candidate_had_opportunity` = 1, D2 = 2, D3 = 1. The conclusion is
the synthesis layer (it reports 3) and is exempt. Both D1 proof paths are
depth 1. The deepest intermediate deduction is exactly at the documented
maximum of 2. See `docs/deduction-system.md`, "Inference depth".

### 1.5 Evidence availability

No evidence in X, Y or Z has `unlock_requires`. The custody record and the
continuity camera log are available from the start. D1 changes what the
player understands about them, not whether they exist. Committing D1 unlocks
D1 as an input and nothing else.

A future investigation-action system could stage this causally: D1 resolved,
then a lead ("who signed out the owner's things?") becomes meaningful, then
the player asks the front desk, and *that action* reveals the sheet. It is
not built. Until it is, required evidence stays independently discoverable,
and the validator warns about the old pattern.

### 1.6 Staging puzzles — one reasoning pattern

1. An observed sign (`staging_sign`) apparently shows outside entry.
2. A separate illustrated reference (`physical_rule_or_reference`) states
   the rule in the same words in all three cases: "*…bends away from the
   side the force came from.*"
3. A plain observation (`staging_contradiction`) says the part is bent
   **outward**, naming the outside place.
4. Comparing 2 and 3 shows the force came from inside (`staging_deduction`).
   The sign adds that it happened after someone walked to the target, and
   that nothing crossed the opening afterwards.

| Case | `staging_sign` | `physical_rule_or_reference` (taught rule) | `staging_contradiction` | Outside is… |
|---|---|---|---|---|
| X | `e_forced_window`: window forced; frame dust on fresh footprints; sill dust undisturbed | `e_latch_guide`: a forced latch bends away from the side the force came from | `e_window_latch`: latch bent outward | the courtyard |
| Y | `e_open_hatch`: vent hatch forced; hatch dust on fresh scuffs; dust in the opening undisturbed | `e_hatch_diagram`: forced retaining tabs bend away from the side the force came from | `e_hatch_tabs`: tabs bent outward | the duct |
| Z | `e_cut_fence`: fence cut; clippings on fresh boot prints; no prints across the gap | `e_fence_sheet`: cut wire ends bend away from the side the force came from | `e_wire_ends`: wire ends bent outward | the street |

No outside knowledge is needed. The rule is stated; the player only applies
it. Text-length parity is measured in section 5.

### 1.7 Properties every case shares

- 3 suspects, 11 evidence items, 14 claims:
  - 5 statements;
  - 3 hypotheses;
  - 1 explanation;
  - 4 deductions: 3 required, plus the opportunity-only distractor;
  - 1 conclusion.
- Proof-set cardinality: D1 3 (both paths), opportunity 1, D2 3, D3 3,
  conclusion 2.
- One **alternate proof path** (D1), proving the same proposition at the
  same strength and depth.
- One **truthful but misleading red herring**, later explained.
- One **innocent lie**, unrelated to the act.
- One **incomplete** true statement, which is supported and can't be refuted.
- Two **deceptive** statements from the candidate. Neither is ever an input
  to the conclusion.
- **Three live hypotheses** mid-case (owner, bystander, outsider).
- **Four required questions** and **four hint ladders**. No level 4 reveals
  the conclusion.
- A seven-event timeline with **two fixed anchors** and **eleven
  constraints**, one of them optional.

### Mid-case hypothesis space

After D1 and before D2/D3, three hypotheses stay live:
- **the candidate**: signed the credential out, which is only opportunity so
  far;
- **the bystander**: carried a sealed container and lied;
- **an outsider**: the forced opening, backed by the candidate's claim.

None of them is eliminated by a single observation.

### Structural-role mapping

| Role | Case X — Archive Ledger | Case Y — Lab Sample | Case Z — Customs Parcel |
|---|---|---|---|
| **Suspects** | | | |
| `apparent_suspect` (credential owner) | `sus_mara` Mara Voss, archivist | `sus_teodor` Teodor Lind, technician | `sus_nadia` Nadia Okafor, customs inspector |
| `actual_culprit` (ground truth only) | `sus_oren` Oren Tal, visiting researcher | `sus_priya` Priya Anand, postdoc | `sus_felix` Felix Moreau, freight agent |
| `bystander` | `sus_ilse` Ilse Brandt, front-desk clerk | `sus_bruno` Bruno Keller, night cleaner | `sus_gus` Gus Hale, forklift driver |
| Credential / zone | staff badge on a cardigan / stacks wing | key card in a lab coat / cold-store corridor | handheld seal scanner / parcel cage area |
| **Evidence** | | | |
| `credential_use_record` | `e_door_log` | `e_cold_room_log` | `e_seal_registry` |
| `owner_alibi_primary` | `e_tram_tap` | `e_gym_scan` | `e_ferry_gate` |
| `owner_alibi_alternate` | `e_harbor_photo` | `e_class_photo` | `e_ferry_photo` |
| `travel_fact` | `e_route_note` (25 min) | `e_shuttle_note` (20 min) | `e_port_map_note` (30 min) |
| `credential_custody` | `e_lost_property_sheet` | `e_coat_rack_sheet` | `e_locker_log` |
| `custody_continuity` | `e_wing_camera` | `e_corridor_camera` | `e_cage_camera` |
| `staging_sign` | `e_forced_window` | `e_open_hatch` | `e_cut_fence` |
| `physical_rule_or_reference` | `e_latch_guide` | `e_hatch_diagram` | `e_fence_sheet` |
| `staging_contradiction` | `e_window_latch` | `e_hatch_tabs` | `e_wire_ends` |
| `red_herring` (misleading) | `e_back_door_sighting` | `e_loading_bay_footage` | `e_yard_sighting` |
| `red_herring_explanation` | `e_shredding_log` | `e_waste_manifest` | `e_pallet_manifest` |
| **Claims** | | | |
| `owner_alibi_statement` (true) | `st_mara_went_to_harbor` | `st_teodor_went_to_gym` | `st_nadia_took_ferry` |
| `owner_incomplete_statement` | `st_mara_badge_on_cardigan` | `st_teodor_card_in_coat` | `st_nadia_scanner_on_dock` |
| `candidate_custody_denial` (deceptive) | `st_oren_never_touched` | `st_priya_never_borrowed` | `st_felix_never_handled` |
| `candidate_staging_claim` (deceptive) | `st_oren_break_in` | `st_priya_vent_entry` | `st_felix_fence_entry` |
| `bystander_innocent_lie` (deceptive, unrelated) | `st_ilse_left_early` | `st_bruno_left_early` | `st_gus_not_in_yard` |
| `hypothesis_owner` (false) | `hyp_mara` | `hyp_teodor` | `hyp_nadia` |
| `hypothesis_bystander` (false) | `hyp_ilse` | `hyp_bruno` | `hyp_gus` |
| `hypothesis_outsider` (false) | `hyp_outsider` | `hyp_outsider` | `hyp_outsider` |
| `red_herring_explained` | `exp_shredding_box` | `exp_waste_bin` | `exp_empty_crates` |
| `credential_misused` (D1) | `ded_badge_misused` | `ded_card_misused` | `ded_scanner_misused` |
| `candidate_had_opportunity` (distractor) | `ded_oren_signed_out_badge` | `ded_priya_borrowed_card` | `ded_felix_took_scanner` |
| `candidate_exclusive_control` (D2) | `ded_only_oren_had_badge` | `ded_only_priya_had_card` | `ded_only_felix_had_scanner` |
| `staging_deduction` (D3) | `ded_break_in_staged` | `ded_hatch_staged` | `ded_fence_staged` |
| `final_conclusion` | `concl_x` | `concl_y` | `concl_z` |
| **Questions** | `q_owner`, `q_access` (`exclusive_control`), `q_staging`, `q_culprit` | same ids | same ids |
| **Timeline events** | | | |
| `owner_departure` (claimed) | `tl_mara_leaves` | `tl_teodor_leaves` | `tl_nadia_leaves` |
| `custody_start` | `tl_cardigan_taken` | `tl_coat_borrowed` | `tl_scanner_taken` |
| `owner_alibi_anchor` (fixed) | `tl_mara_tram_tap` 20:04 | `tl_gym_checkin` 21:09 | `tl_ferry_boarding` 06:38 |
| `credential_use_anchor` (fixed) | `tl_badge_used` 20:06 | `tl_card_used` 21:12 | `tl_seal_applied` 06:42 |
| `staging_act` | `tl_window_forced` | `tl_hatch_forced` | `tl_fence_cut` |
| `bystander_errand` (3 min) | `tl_shredding_pickup` | `tl_bin_out` | `tl_pallet_moved` |
| `custody_end` | `tl_cardigan_returned` | `tl_coat_returned` | `tl_scanner_returned` |

`DeductionValidator.validate_structural_equivalence()` rejects any
divergence, including each proof set's depth. `deduction_cases_test.gd` also
spells out the role topology and depths claim by claim.

### Proof sets (role form — the same in all three cases)

| Claim role | Relation | Requires |
|---|---|---|
| `credential_misused` | supports | `credential_use_record` + `owner_alibi_primary` + `travel_fact` **(primary)** |
| `credential_misused` | supports | `credential_use_record` + `owner_alibi_alternate` + `travel_fact` **(alternate)** |
| `candidate_had_opportunity` | supports | `credential_custody` |
| `candidate_exclusive_control` | supports | D1 + `credential_custody` + `custody_continuity` (compatible, not proof: `credential_use_record`, `candidate_had_opportunity`) |
| `staging_deduction` | supports | `staging_sign` + `physical_rule_or_reference` + `staging_contradiction` |
| `final_conclusion` | supports | D2 + D3 (compatible, not proof: D1, `candidate_had_opportunity`) |
| `owner_alibi_statement` | supports | `owner_alibi_primary` |
| `owner_incomplete_statement` | supports | `credential_custody` |
| `candidate_custody_denial` | refutes | `credential_custody` |
| `candidate_staging_claim` | refutes | `physical_rule_or_reference` + `staging_contradiction` **(primary)** |
| `candidate_staging_claim` | refutes | `staging_sign` **(alternate, single-evidence — Milestone 1.11, see "0.2")** |
| `bystander_innocent_lie` | refutes | `red_herring_explanation` |
| `red_herring_explained` | explains | `red_herring` + `red_herring_explanation` |
| `hypothesis_owner` | rules_out | D1 (compatible, not proof: `credential_use_record`) |
| `hypothesis_bystander` | rules_out | `red_herring_explanation` + D2 (compatible, not proof: `red_herring`) |
| `hypothesis_outsider` | rules_out | D3 (compatible, not proof: `staging_sign`) |

Questions: `q_owner` is resolved by D1 supported **or** `hypothesis_owner`
refuted; `q_access` by D2; `q_staging` by D3; `q_culprit` by the conclusion.

### Timeline constraints (role form)

| Constraint | Type | Events | Required | Source role | Meaning |
|---|---|---|---|---|---|
| use time | `fixed_time` | `credential_use_anchor` | yes | `credential_use_record` | anchor 1 |
| alibi time | `fixed_time` | `owner_alibi_anchor` | yes | `owner_alibi_primary` | anchor 2 |
| owner leaves | `window` | `owner_departure` | yes | `owner_alibi_statement` | what the (truthful) owner said, ± a few minutes |
| owner travel | `travel_time` | `owner_departure` ↔ `owner_alibi_anchor` | yes | `travel_fact` | the owner can't be in both places faster than the trip |
| custody start | `window` | `custody_start` | yes | `credential_custody` | handwritten log time ± 2–3 min |
| custody end | `window` | `custody_end` | yes | `credential_custody` | handwritten log time ± 2–3 min, no earlier than leaving the zone |
| staging after entry | `before` (gap 1) | `credential_use_anchor` → `staging_act` | yes | `staging_sign` | debris lies **on top of** the fresh prints |
| staging heard | `window` | `staging_act` | yes | `red_herring` | the witness heard it "a few minutes after" the hour mark; the window lies inside the candidate's time in the zone |
| not during errand | `no_overlap` | `staging_act` ↔ `bystander_errand` | yes | `red_herring` | the witness was watching the bystander then, and heard nothing |
| errand time | `window` | `bystander_errand` | yes | `red_herring_explanation` | contractor's log time ± 2 min |
| bystander's claim | `window` | `bystander_errand` | **no** | `bystander_innocent_lie` | where the errand would be if the lie were true; the true timeline violates it |

Several placements are valid in every case. The owner's departure and the
staging act each have slack: staging can fall before *or* after the errand,
as long as they don't overlap.

### Hint ladders (role form)

| Target | L1 restate question | L2 compare categories | L3 evidence group | L4 reveal intermediate deduction |
|---|---|---|---|---|
| D1 `credential_misused` | `q_owner` | time, location, distance | use record, primary alibi, travel fact | D1 |
| D2 `candidate_exclusive_control` | `q_access` | possession, location, time | custody, continuity | D1 (the prerequisite) |
| D3 `staging_deduction` | `q_staging` | scene, physics | sign, reference, contradiction | D3 |
| `final_conclusion` | `q_culprit` | possession, scene | continuity, contradiction | D2 |

No level ever reveals the final conclusion. A level 4 is information only;
it does not commit the deduction for the player.
---

## 2. Case X — The Archive Ledger (`proto_x_archive_ledger`)

A confidential ledger vanished from Stack Room 3 of the city archive.

### Objective sequence

| Time | What actually happened |
|---|---|
| 19:30 | Closing check: the ledger is on its shelf. From now on, the stacks-wing entrance camera sees nobody but Oren. |
| 19:35 | Mara leaves for dinner at Harbor, forgetting her grey cardigan (staff badge clipped on) on her chair. Ilse logs it into lost property. |
| 19:48 | Oren tells Ilse he will return the cardigan to Mara and signs it out. |
| 19:51 | Oren walks into the stacks wing wearing the cardigan. |
| 20:04 | Mara taps out at Harbor Station; the gate camera shows her. |
| 20:05 | Mara's friend photographs her at Harbor Grill; the harbor clock reads 20:05. |
| 20:06 | Oren holds Mara's badge to the Stack Room 3 reader and takes the ledger. |
| 20:08 | Oren forces the window from inside. Its latch bends outward, toward the courtyard. Dust from the frame falls onto his own footprints. |
| 20:10–20:13 | Ilse, working unlogged overtime, hands the shredding box to the contractor at the back door while the guard watches. |
| 20:13 | Oren walks out of the stacks wing, still wearing the cardigan. |
| 20:14 | Oren hands the cardigan back in to lost property. |

**Culprit and method:** Oren signed the badge-bearing cardigan out of lost
property under the pretext of returning it, used the badge to open Stack
Room 3, took the ledger, and forced the window from inside to fake an
outside break-in.

### Case rules (as stated in the evidence)

| Rule | Stated in | Concrete form |
|---|---|---|
| R1 credential | `e_door_log` | Badges work only when held to the reader, can't be copied, and doors can't be opened remotely. Stack Room 3 is inside the stacks wing. |
| R2 custody | `e_lost_property_sheet` | Cardigan with M. Voss's badge signed out by O. Tal at 19:48, handed back by O. Tal at 20:14. |
| R3 zone closure | `e_wing_camera` | The 19:30 closing check finds the wing empty and locks it. The camera covers the wing's only entrance from then on. Oren in at 19:51, out at 20:13, wearing the cardigan. Nobody else in or out 19:30–20:30. |
| R4 last seen | `e_forced_window` | Shelf full at the 19:30 closing check. Frame dust lies on top of fresh footprints leading to the shelf, and the sill dust is undisturbed, so nobody climbed through afterwards. |
| R5 taught rule | `e_latch_guide` | When a latched window is forced open, its latch bends away from the side the force came from. |
| R6 travel + identity | `e_route_note`, `e_tram_tap`, `e_harbor_photo` | The trip takes ≥ 25 min. The gate camera shows Mara herself; the photo's harbor clock reads 20:05. |

### Suspects' actual activity

- **Mara (apparent suspect):** innocent. She left at 19:35 and was at
  Harbor from 20:04 on. Her badge was on the cardigan she forgot.
- **Oren (culprit):** held the cardigan 19:48–20:14 and was alone in the
  stacks wing 19:51–20:13. He used the badge at 20:06 and forced the window
  at 20:08. Afterwards he denied touching Mara's things and blamed an
  intruder.
- **Ilse (bystander):** innocent. She wrote the lost-property sheet and
  stayed past her shift to finish shredding (box out ~20:10). She never
  entered the stacks wing. She lied that she left at 19:45 to hide the
  unlogged overtime.

### Statements

| Id | Speaker | Says | Veracity | Shown by |
|---|---|---|---|---|
| `st_mara_went_to_harbor` | Mara | left ~19:30, went straight to Harbor | **true** | supports: `e_tram_tap` |
| `st_mara_badge_on_cardigan` | Mara | badge was clipped to her cardigan | **incomplete**: true, but omits that she left the cardigan behind. It is supported, never refuted. | supports: `e_lost_property_sheet` |
| `st_oren_never_touched` | Oren | never had anything of Mara's | **deceptive** | refutes: `e_lost_property_sheet` |
| `st_oren_break_in` | Oren | someone forced the window from the courtyard | **deceptive** | refutes: `e_latch_guide` + `e_window_latch`. The forced window alone is merely compatible. |
| `st_ilse_left_early` | Ilse | locked up and left at 19:45 | **deceptive, innocent** (hides overtime, unrelated to the theft) | refutes: `e_shredding_log` |

### Evidence — observation vs intended interpretation

| Id | Observation (what it says) | Intended use | Premature interpretation to avoid |
|---|---|---|---|
| `e_door_log` | Mara's badge opened Stack Room 3 (in the stacks wing) at 20:06; badges must be held to the reader, can't be copied, no remote opening | *the badge* was physically at the door at 20:06 | "Mara entered at 20:06" |
| `e_tram_tap` | Mara's card tapped out at Harbor Station at 20:04; gate camera shows Mara | Mara herself was at Harbor at 20:04 | — |
| `e_harbor_photo` | friend's photo of Mara at Harbor Grill, harbor clock reads 20:05 | independent proof Mara was at Harbor at 20:05 | — |
| `e_route_note` | fastest Harbor↔archive trip is 25 min, even by taxi | the **taught** fact that makes the alibi decisive | — |
| `e_lost_property_sheet` (available from the start) | 19:48 cardigan with M. Voss badge taken by O. Tal; 20:14 handed back by O. Tal | the badge was signed out to Oren 19:48–20:14 | "Oren used it". Holding is only opportunity. |
| `e_wing_camera` (available from the start) | the wing's only entrance: Oren in 19:51 and out 20:13 wearing the cardigan; nobody else in or out 19:30–20:30 | nobody but Oren could be at the Stack Room door at 20:06 | "Oren is guilty". It shows presence, not the act; it needs R1 and D1. |
| `e_forced_window` | window forced open; shelf (full at 19:30) empty; frame dust on top of fresh footprints to the shelf; sill dust undisturbed | the window was forced after someone had already walked to the shelf, and nobody came through it afterwards | "a burglar came in through the window" |
| `e_latch_guide` | illustrated guide: a forced latch bends away from the side the force came from | the taught physical rule | — |
| `e_window_latch` | the latch is bent outward, toward the courtyard | applied with the guide: the force came from inside | — |
| `e_back_door_sighting` (**red herring**) | guard: ~20:10 Ilse carried a sealed box out; heard the window crack a few minutes after eight, not while watching her | truthful; misleading because the box *looks* like the ledger leaving | "Ilse smuggled the ledger out" |
| `e_shredding_log` | ~20:10 one sealed box of shredded paper handed over by I. Brandt | the box was shredding; Ilse was still there at 20:10 | — |

### Deductions and conclusion

- **D1 `ded_badge_misused`** (depth 1): "Someone other than Mara used Mara's
  badge at 20:06."
  - `ps_misused_tram` {`e_door_log`, `e_tram_tap`, `e_route_note`}
  - **alternate** `ps_misused_photo` {`e_door_log`, `e_harbor_photo`, `e_route_note`}

  Both proof sets place Mara herself, identity-checked and timestamped,
  25 minutes away within two minutes of the use. They prove the same
  proposition at the same strength.
- **`ded_oren_signed_out_badge`** (depth 1, true, **not sufficient**): "Oren
  signed Mara's badge out of lost property before it was used and handed it
  back afterwards." {`e_lost_property_sheet`}. This is the opportunity-only
  claim. The conclusion lists it as *compatible* and never accepts it as
  proof.
- **D2 `ded_only_oren_had_badge`** (depth 2): "Only Oren could have
  presented Mara's badge at 20:06: it was signed out to him, he was the only
  person in the stacks wing, and a badge can't be copied or used remotely."
  {D1, `e_lost_property_sheet`, `e_wing_camera`}
- **D3 `ded_break_in_staged`** (depth 1): "The window was forced from inside
  the room, after someone had already walked to the shelf, to fake a
  break-in." {`e_forced_window`, `e_latch_guide`, `e_window_latch`}
- **Conclusion `concl_x`** (synthesis layer): "Oren used Mara's badge,
  clipped to the cardigan he had signed out of lost property, to enter
  Stack Room 3 and take the ledger, then forced the window from inside to
  make it look like an outside break-in." {D2, D3}

### Proof obligation — Case X

| Plausible alternative actor | Why still possible before D2/D3 | Eliminated by | Why that is sufficient |
|---|---|---|---|
| **Mara** used her own badge | the door log names her badge | D1 (R6 + R1) | she was identity-verified at Harbor at 20:04/20:05, the trip takes ≥ 25 min, and the badge must be physically present |
| **Ilse** took the ledger (box) | on site; seen carrying a sealed box; lied about leaving | R3 inside D2 | she never entered the stacks wing, so she could reach neither the door nor the shelf. The box is separately explained by `e_shredding_log`. |
| **Night guard**, **shredding contractor** | on site near 20:10 | R3 inside D2 | nobody but Oren entered the wing 19:30–20:30 |
| **Whoever did the 19:30 closing check** | last person known at the shelf | R4 + R3 | the shelf was still full at the check; nobody but Oren entered the wing afterwards |
| **Someone already inside the wing** before 19:30 (never recorded "entering or leaving") | the camera log alone only proves nobody crossed the entrance 19:30–20:30 | R3 (the check itself) | the 19:30 closing check finds the wing empty of people before the camera's window even starts, closing the gap a pure entry/exit log would leave |
| **An outside thief** through the window | forced window; Oren says so | D3 (R5) | the window was forced from inside, after someone had walked to the shelf, so it was not an entry |
| **Someone with a copied badge or a remote opening** | the log records a badge, not a face | R1 | badges can't be copied and doors can't be opened remotely |
| **Someone Oren handed the badge to** | custody alone doesn't exclude a handover | R3 | whoever used it had to be at the door inside the wing, and nobody else was in the wing |
| **Oren merely "had the opportunity"** | `ded_oren_signed_out_badge` is true | not accepted as proof | the conclusion requires D2, which adds zone closure (R3) and D1 |

**Why the final prerequisites jointly leave no alternative.** Between the
19:30 check and discovery, the shelf could be reached only two ways:
- through the wing entrance, where R3 shows only Oren passed;
- through the forced window, which D3 shows was forced from inside after
  the walk to the shelf, with nobody crossing the undisturbed sill
  afterwards.

The badge use at 20:06 was Oren's (D2). The one person inside the room is
therefore also the one who forced the window from inside. Remove
`e_wing_camera`, `e_lost_property_sheet` or `e_latch_guide`, and the authored
conclusion becomes unprovable. `deduction_cases_test.gd` checks this for each
case.

**Out of scope, deliberately:** an accomplice receiving the ledger after
Oren left the wing, and where the ledger went. The questions are who took
it, how access was obtained, and how the act was concealed.

### Hypotheses

| Hypothesis | Plausible because | Eliminated by |
|---|---|---|
| `hyp_mara` | the door log names her badge | rules_out {D1} |
| `hyp_ilse` | box at 20:10; lied about leaving | rules_out {`e_shredding_log`, D2} |
| `hyp_outsider` | forced window; Oren says so | rules_out {D3} |

**Red herring:** `e_back_door_sighting`, explained by `exp_shredding_box`.
**Innocent lie:** `st_ilse_left_early`, refuted by `e_shredding_log`. Its
motive (unlogged overtime) has nothing to do with the theft, and no proof
uses it as evidence of guilt.

### Timeline

| Constraint | Concrete form |
|---|---|
| `c_badge_time` | `tl_badge_used` = 20:06 (`e_door_log`) |
| `c_tram_time` | `tl_mara_tram_tap` = 20:04 (`e_tram_tap`) |
| `c_mara_leaves_claimed` | `tl_mara_leaves` in 19:25–19:45 (`st_mara_went_to_harbor`) |
| `c_mara_travel` | `tl_mara_leaves` ↔ `tl_mara_tram_tap` ≥ 25 min (`e_route_note`), which forces leaving ≤ 19:39 |
| `c_cardigan_taken_window` | `tl_cardigan_taken` in 19:45–19:50 |
| `c_cardigan_returned_window` | `tl_cardigan_returned` in 20:13–20:16 (no earlier than Oren leaving the wing) |
| `c_window_after_entry` | `tl_badge_used` + 1 min ≤ `tl_window_forced` |
| `c_window_heard` | `tl_window_forced` in 20:07–20:13 (within Oren's time in the wing) |
| `c_window_not_during_errand` | `tl_window_forced` doesn't overlap `tl_shredding_pickup` (3 min) |
| `c_shredding_window` | `tl_shredding_pickup` in 20:08–20:12 |
| `c_ilse_claimed_departure` (**optional**) | `tl_shredding_pickup` in 19:30–19:45; the truth violates it |

Authored solution: leaves 19:35 · cardigan taken 19:48 · tram 20:04 · badge
20:06 · window 20:08 · shredding 20:10 · returned 20:14. Also valid, for
example: leaves 19:30, or window 20:12 with shredding at 20:08.

### Hint ladders

| Target | L1 | L2 | L3 | L4 |
|---|---|---|---|---|
| `ded_badge_misused` | "Where was Mara when her badge opened the door?" | times, places, travel time | door log + travel-card record + transit map note | "Someone other than Mara used her badge at 20:06." |
| `ded_only_oren_had_badge` | "Whose hands could it have been in at 20:06, and nobody else's?" | possession, location, time | lost-property sheet + stacks-wing camera log | reveals D1 (the prerequisite) |
| `ded_break_in_staged` | "What does the forced window tell you?" | scene; the repair guide on forced latches | forced window + window-repair guide + bent latch | "Forced from inside to fake a break-in." |
| `concl_x` | "Who took it, and how was it hidden?" | who alone could use the means of entry + what was staged | stacks-wing camera log + bent latch | "Only Oren could have presented Mara's badge at 20:06." (D2, intermediate) |

### Audit notes

- The lost-property sheet is written by the bystander. The identity
  elimination does not rest on it alone: the neutral wing camera (R3) places
  Oren, and only Oren, in the wing with the badge-bearing cardigan.
- The camera cannot see the badge's owner name. R2 is what ties the
  cardigan's badge to Mara, and it is also the "how access was obtained"
  part of the conclusion.
- Wing camera and shelf check both start at 19:30. A checker who stayed
  hidden past 20:30 would have to leave through the camera-covered entrance
  and would be recorded.

---

## 3. Case Y — The Swapped Sample (`proto_y_lab_sample`)

A sample vial in a research lab's cold room was relabelled and swapped
overnight. The structure is identical to X (section 2), so only the
case-specific parts are listed.

### Objective sequence

| Time | What actually happened |
|---|---|
| 20:30 | Stock check: the sample is in its rack. From now on, the cold-store corridor camera sees nobody but Priya. |
| 20:45 | Teodor leaves for spin class at Riverside, leaving his lab coat (key card in the pocket) on the laundry rack. |
| 20:55 | Priya borrows the coat from Bruno's laundry rack, saying she will pass it on to Teodor. |
| 20:59 | Priya walks into the cold-store corridor wearing the coat. |
| 21:09 | Teodor checks in at Riverside Gym; the desk camera shows him. |
| 21:10 | The instructor photographs Teodor on bike 7; the studio clock reads 21:10. |
| 21:12 | Priya holds Teodor's card to the cold-room reader, then swaps and relabels the sample. |
| 21:14 | Priya forces the vent hatch from inside. Its retaining tabs bend outward, into the duct. Hatch dust falls onto her scuffs. |
| 21:18–21:21 | Bruno, back from a long unauthorized break, wheels the scheduled glassware-waste bin out of the loading bay. |
| 21:20 | Priya walks out of the corridor. |
| 21:25 | Priya returns the coat. |

### Case rules

| Rule | Stated in | Concrete form |
|---|---|---|
| R1 credential | `e_cold_room_log` | cards must be held to the reader, can't be copied, no remote opening; the cold room is off the cold-store corridor |
| R2 custody | `e_coat_rack_sheet` | coat with T. Lind's key card borrowed by P. Anand at 20:55, returned at 21:25 |
| R3 zone closure | `e_corridor_camera` | the 20:30 stock check finds the corridor empty and locks it; the corridor's only entrance from then on: Priya in 20:59, out 21:20, wearing a lab coat; nobody else in or out 20:30–21:40 |
| R4 last seen | `e_open_hatch` | sample checked at 20:30; hatch dust on fresh scuffs leading to the rack; dust inside the opening undisturbed |
| R5 taught rule | `e_hatch_diagram` | forced retaining tabs bend away from the side the force came from |
| R6 travel + identity | `e_shuttle_note`, `e_gym_scan`, `e_class_photo` | ≥ 20 min; desk camera shows Teodor; studio clock reads 21:10 |

### Statements

| Id | Speaker | Veracity | Shown by |
|---|---|---|---|
| `st_teodor_went_to_gym` | Teodor | **true** | supports: `e_gym_scan` |
| `st_teodor_card_in_coat` | Teodor | **incomplete** (omits that the coat stayed behind) | supports: `e_coat_rack_sheet` |
| `st_priya_never_borrowed` | Priya | **deceptive** | refutes: `e_coat_rack_sheet` |
| `st_priya_vent_entry` | Priya ("someone forced the hatch from the duct") | **deceptive** | refutes: `e_hatch_diagram` + `e_hatch_tabs` (compatible: `e_open_hatch`) |
| `st_bruno_left_early` | Bruno | **deceptive, innocent** (hides a break) | refutes: `e_waste_manifest` |

### Deductions and conclusion

- **D1 `ded_card_misused`**: `ps_misused_gym_scan` {`e_cold_room_log`, `e_gym_scan`, `e_shuttle_note`}; **alternate** `ps_misused_class_photo` {`e_cold_room_log`, `e_class_photo`, `e_shuttle_note`}.
- **`ded_priya_borrowed_card`** (opportunity only): {`e_coat_rack_sheet`}.
- **D2 `ded_only_priya_had_card`**: {D1, `e_coat_rack_sheet`, `e_corridor_camera`}.
- **D3 `ded_hatch_staged`**: {`e_open_hatch`, `e_hatch_diagram`, `e_hatch_tabs`}.
- **Conclusion `concl_y`**: {D2, D3}. Priya used the card from the coat she borrowed to enter the cold room and swap the sample, then forced the hatch from inside.

### Proof obligation — Case Y

| Alternative actor | Why possible before D2/D3 | Eliminated by |
|---|---|---|
| Teodor | the lock log names his card | D1 (identity-checked gym check-in / photo at 21:09–21:10, ≥ 20 min trip, R1) |
| Bruno | wheeled a sealed bin out; lied about leaving | R3 (never entered the corridor); the bin is explained by `e_waste_manifest` |
| The 20:30 stock checker; other night staff | on site | R4 + R3 |
| Someone already inside the corridor before 20:30 (never recorded "entering or leaving") | the camera log alone only proves nobody crossed the entrance 20:30–21:40 | R3 (the check itself) | the 20:30 stock check finds the corridor empty of people before the camera's window even starts |
| An outsider through the vent | forced hatch; Priya says so | D3 (tabs bent into the duct, R5; dust in the opening undisturbed) |
| Copied card / remote opening | the log records a card | R1 |
| Someone Priya handed the card to | custody alone doesn't exclude it | R3 |
| Priya "merely had the opportunity" | `ded_priya_borrowed_card` is true | not accepted; the conclusion requires D2 |

### Timeline

Fixed: `tl_card_used` 21:12, `tl_gym_checkin` 21:09.

Required windows:
- `tl_teodor_leaves` 20:40–20:55, plus a 20-minute travel constraint, so in
  practice ≤ 20:49;
- `tl_coat_borrowed` 20:52–20:58;
- `tl_coat_returned` 21:22–21:28;
- `tl_hatch_forced` 21:13–21:19, at least 1 minute after the card use, and
  not overlapping `tl_bin_out` (3 min);
- `tl_bin_out` 21:16–21:20.

Optional: `tl_bin_out` 20:35–20:45, from Bruno's lie; the truth violates it.

Authored solution: 20:45 · 20:55 · 21:09 · 21:12 · 21:14 · 21:18 · 21:25.

Hint ladders have the same shape as X: D1 (lock log + gym check-in + shuttle
timetable), D2 (laundry sheet + corridor camera log, revealing D1), D3
(forced hatch + maintenance diagram + bent tabs), and the conclusion
(corridor camera log + bent tabs, revealing D2).

---

## 4. Case Z — The Switched Parcel (`proto_z_customs_parcel`)

A sealed parcel at the customs depot was switched just before dispatch.

### Objective sequence

| Time | What actually happened |
|---|---|
| 06:00 | Cage check: parcel 118 is in the cage. From now on, the cage-area gate camera sees nobody but Felix. |
| 06:02 | Nadia leaves for the early ferry, leaving her seal scanner on the charging dock. |
| 06:20 | Felix takes the scanner, telling Gus he will bring it to her; Gus logs it. |
| 06:23 | Felix walks through the cage area's only gate with the scanner clipped to his belt. The area is fenced floor to roof. |
| 06:38 | Nadia's ticket is scanned boarding at North Pier; staff check her photo ID. |
| 06:41 | Nadia photographs herself on the ferry deck; the deck clock reads 06:41. |
| 06:42 | Felix switches parcel 118 and re-seals it with Nadia's scanner. |
| 06:44 | Felix cuts the rear fence from inside. The wire ends bend outward, toward the street. Clippings fall onto his boot prints. |
| 06:47–06:50 | Gus, whose forklift licence has lapsed, moves a covered pallet of returned empty crates from the dock beside the cage area. |
| 06:51 | Felix walks out through the gate. |
| 06:55 | Felix returns the scanner. |

### Case rules

| Rule | Stated in | Concrete form |
|---|---|---|
| R1 credential | `e_seal_registry` | the scanner must be held against the seal, can't be copied or operated remotely; parcel 118 is in the cage area |
| R2 custody | `e_locker_log` | N. Okafor's scanner taken by F. Moreau at 06:20, returned at 06:55 |
| R3 zone closure | `e_cage_camera` | the 06:00 cage check finds the area empty and locks it; the area's only gate (fenced floor to roof) from then on: Felix in 06:23, out 06:51, scanner on his belt; nobody else in or out 06:00–07:10 |
| R4 last seen | `e_cut_fence` | parcel checked at 06:00; clippings on fresh boot prints leading to the parcel; no prints cross the gap |
| R5 taught rule | `e_fence_sheet` | cut wire ends bend away from the side the force came from |
| R6 travel + identity | `e_port_map_note`, `e_ferry_gate`, `e_ferry_photo` | ≥ 30 min; photo ID checked at boarding; the deck clock reads 06:41 |

### Statements

| Id | Speaker | Veracity | Shown by |
|---|---|---|---|
| `st_nadia_took_ferry` | Nadia | **true** | supports: `e_ferry_gate` |
| `st_nadia_scanner_on_dock` | Nadia | **incomplete** (omits that anyone could take it from the dock) | supports: `e_locker_log` |
| `st_felix_never_handled` | Felix | **deceptive** | refutes: `e_locker_log` |
| `st_felix_fence_entry` | Felix | **deceptive** | refutes: `e_fence_sheet` + `e_wire_ends` (compatible: `e_cut_fence`) |
| `st_gus_not_in_yard` | Gus | **deceptive, innocent** (hides the lapsed licence) | refutes: `e_pallet_manifest` |

### Deductions and conclusion

- **D1 `ded_scanner_misused`**: `ps_misused_ferry_gate` {`e_seal_registry`, `e_ferry_gate`, `e_port_map_note`}; **alternate** `ps_misused_ferry_photo` {`e_seal_registry`, `e_ferry_photo`, `e_port_map_note`}.
- **`ded_felix_took_scanner`** (opportunity only): {`e_locker_log`}.
- **D2 `ded_only_felix_had_scanner`**: {D1, `e_locker_log`, `e_cage_camera`}.
- **D3 `ded_fence_staged`**: {`e_cut_fence`, `e_fence_sheet`, `e_wire_ends`}.
- **Conclusion `concl_z`**: {D2, D3}. Felix used Nadia's scanner, taken on the promise of bringing it to her, to re-seal the switched parcel, then cut the fence from inside.

### Proof obligation — Case Z

| Alternative actor | Why possible before D2/D3 | Eliminated by |
|---|---|---|
| Nadia | the seal registry names her scanner | D1 (ID-checked boarding / photo at 06:38–06:41, ≥ 30 min trip, R1) |
| Gus | drove a covered pallet from beside the cage; lied about the yard | R3 (never entered the cage area); the pallet is explained by `e_pallet_manifest` |
| The 06:00 cage checker; the yard guard | on site | R4 + R3 |
| Someone already inside the cage area before 06:00 (never recorded "entering or leaving") | the camera log alone only proves nobody crossed the gate 06:00–07:10 | R3 (the check itself) | the 06:00 cage check finds the area empty of people before the camera's window even starts |
| Outside thieves through the fence | cut fence; Felix says so | D3 (ends bent toward the street, R5; no prints across the gap) |
| Copied scanner / remote sealing | the registry records a scanner | R1 |
| Someone Felix handed the scanner to | custody alone doesn't exclude it | R3 |
| Felix "merely had the opportunity" | `ded_felix_took_scanner` is true | not accepted; the conclusion requires D2 |

### Timeline

Fixed: `tl_seal_applied` 06:42, `tl_ferry_boarding` 06:38.

Required windows:
- `tl_nadia_leaves` 05:55–06:10, plus a 30-minute travel constraint, so in
  practice ≤ 06:08;
- `tl_scanner_taken` 06:18–06:22;
- `tl_scanner_returned` 06:52–06:58;
- `tl_fence_cut` 06:43–06:49, at least 1 minute after sealing, and not
  overlapping `tl_pallet_moved` (3 min);
- `tl_pallet_moved` 06:45–06:49.

Optional: `tl_pallet_moved` 06:00–06:30, from Gus's lie; the truth violates
it.

Authored solution: 06:02 · 06:20 · 06:38 · 06:42 · 06:44 · 06:47 · 06:55.

Hint ladders have the same shape as X: D1 (seal registry + ferry gate + port
map), D2 (locker log + cage-area camera log, revealing D1), D3 (cut fence +
safety sheet + bent wire ends), and the conclusion (cage-area camera log +
bent wire ends, revealing D2).

---

## 5. Parity measurements and known equivalence caveats

### Measured parity

English word counts come from a whitespace split over
`localization/strings.csv`. Recount after any wording change.

| Measure | X | Y | Z |
|---|---|---|---|
| All case text (every key) | 929 | 950 | 961 |
| Evidence observation text | 294 | 298 | 317 |
| Staging: sign / rule / contradiction | 43 / 21 / 9 | 47 / 22 / 10 | 45 / 21 / 10 |
| Use record / custody / continuity | 34 / 30 / 49 | 34 / 29 / 44 | 36 / 30 / 58 |
| Primary alibi / alternate alibi / travel fact | 20 / 21 / 15 | 22 / 20 / 16 | 22 / 22 / 16 |
| Observations required by the staging deduction | 3 | 3 | 3 |
| Depth: D1 / staging / D2 / conclusion (synthesis) | 1 / 1 / 2 / 3 | same | same |
| Visibility of the staging rule | own illustrated reference item; identical rule wording | same | same |
| Distractors bearing on staging | 0 — since Milestone 1.11 the sign alone (`staging_sign`) is a valid alternate single-evidence refutation of `candidate_staging_claim`, not merely compatible with it (see "0.2") | same | same |
| Distractors bearing on the conclusion | 2 compatible (D1, opportunity-only) | same | same |
| Proof-set cardinality: D1 / opportunity / D2 / D3 / conclusion | 3 / 1 / 3 / 3 / 2 | same | same |

### Known equivalence caveats

The proof graphs are identical, but the surfaces are not perfectly equal.
Record these caveats alongside the results rather than pretending they don't
exist:

- **Z's continuity log is the longest item** (58 words, versus 49 and 44). An
  open yard needs the extra "fenced floor to roof" clause that a wing or
  corridor doesn't.
- **Milestone 1.10's zone-verified-empty clause** ("the N:NN [closing check
  wording] finds the [zone] empty and locks it") added exactly 11 words to
  each case's continuity evidence, uniformly — the existing gap above (X 38 →
  49, Y 33 → 44, Z 47 → 58) is preserved, not widened.
- **Object familiarity still differs slightly.** All three rules are stated
  in identical words and the player only applies them. Still, a window latch
  (X) is a more everyday object than a vent hatch's retaining tabs (Y) or
  cut chain-link (Z). Compare staging-hint usage per case.
- **Times differ** (evening / evening / dawn), and so do the travel-time
  numbers (25 / 20 / 30 min). The required arithmetic is equally simple in
  all three.
- **Relabelling** a sample (Y) is conceptually slightly further from
  "theft" than taking a ledger (X) or switching a parcel (Z).
- **The custody record is written by the bystander** in every case. No
  elimination rests on it alone (R3 does that work), but a sceptical player
  may distrust it. This is equally true in all three.
- **Zone windows start at the target's last check** (19:30 / 20:30 / 06:00).
  Where exactly the checker went is not modelled; this is identical in all
  three.
- **An accomplice receiving the object after the act** is out of scope in
  all three. The questions are who performed the act, how access was
  obtained, and how the act was concealed.
- Names and roles were chosen to avoid obvious gender or occupation cues
  pointing at the culprit, but no bias review has been done. Treat this as
  unverified.
- The Vietnamese text was written alongside the English but has not had a
  native-speaker review for clarity or equal length.

## 6. Human audit checklist

`DeductionValidator` can't judge these questions. Answer them for every case
that shares a template, and again after any wording change.

| # | Question | How to check | X / Y / Z (Milestone 1.9.1) |
|---|---|---|---|
| 1 | **Does the final proof eliminate alternatives?** | For every plausible actor in the proof-obligation tables, name the stated rule or deduction that removes them. Look for any route to the target that neither zone closure (R3) nor the staging deduction (D3) covers. Specifically check whether R3 rules out someone who was already inside the zone before the monitored window started, not just someone who entered/left during it. | Yes (sections 1.3, 2, 3, 4). Since Milestone 1.10, R3's evidence text states the last-seen check itself finds the zone empty of people, closing the "already inside" gap a pure entry/exit log would leave (section 0.1). Accomplices after the act are declared out of scope. |
| 2 | **Is every required physical rule taught?** | Every inference that needs a physical or specialist fact must find that fact stated in some evidence text, never "everyone knows…". | Yes: `travel_fact`, `physical_rule_or_reference`, and R1 in the use record. |
| 3 | **Does any thought magically create evidence?** | Nothing a deduction or conclusion requires has `unlock_requires` (the validator warns). Read the objective sequence for records that only "appear" after a realization. | No gating in any case. |
| 4 | **Is observation separated from interpretation?** | Evidence text says only what a record, camera or inspection shows. Interpretations appear only in deductions. Check each "premature interpretation" column. | Yes (section 2's evidence table; Y and Z use the same roles). |
| 5 | **Is any lie incorrectly treated as guilt?** | No proof set requires a refuted statement (they can't be inputs). The innocent lie's motive is unrelated. The conclusion's grounds contain no statement. | Yes, none. Tested: a refuted denial is `unselectable_item`. |
| 6 | **Are alternate proof paths equally strong?** | An alternate must prove the same proposition, from evidence of the same certainty and identity strength, at the same depth. | Yes. An identity-checked record and an owner photo with an in-frame clock: both `fixed`, both depth 1. |
| 7 | Is every red herring true and explained later? | `misleading` items are true observations used by an `explains` proof set. | Yes |
| 8 | Is the incomplete statement never treated as false? | `veracity: incomplete`: supported, with no refuting proof set. | Yes (tested) |
| 9 | Is the staging reasoning pattern identical across the template? | The same four roles, the same rule sentence, and the same "bent outward, toward/into <outside place>" phrasing. | Yes (section 1.6) |
| 10 | Is the text length roughly equal per role? | Recount (section 5) and investigate any role that differs by more than about 25%. | Z's continuity log is the outlier (caveat noted). |
