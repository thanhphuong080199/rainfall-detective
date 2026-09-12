# Architecture — Narrative Investigation Sandbox

This document explains how the sandbox is built: the autoloads (global systems),
the scenes, how data flows between them, and the Godot-specific conventions in
play. It assumes you know software engineering but not necessarily Godot.

**Philosophy: this project builds systems, not story.** Every character name,
line of dialogue, location, and piece of evidence in `data/` is disposable
placeholder content that exists to prove the systems work. None of the code
described below should ever need to change just because the content does —
see `docs/content-guide.md` for how to add real content later.

This started as a Milestone 0 sandbox (data-driven content, a condition
mini-language, Examine/Talk/Present/Move) and has since been strengthened as
a content pipeline and investigation-framework foundation: more condition/
effect vocabulary, automatic content validation, developer tooling, an
automatic Event system (`docs/event-system.md`), and — as of Milestone 1.6 —
a Case/Chapter organization layer on top of all of it (`docs/case-system.md`)
and bilingual localization, Vietnamese default / English supported
(`docs/localization.md`) — see "Content validation", "Developer tools",
"Case / Chapter progression", and "Localization" below. None of this
decides final deduction/case-solving gameplay; see this doc's closing note
and `docs/content-guide.md` for what's still deliberately undecided.

## Godot conventions used here, briefly

If you're new to Godot, these four conventions explain almost everything about
how this project is wired together:

- **Autoloads (singletons).** A script registered under `[autoload]` in
  `project.godot` is instantiated once as a `Node` under `/root`, before any
  scene loads, and stays alive for the whole game. It's reachable from any
  script simply by its registered name (e.g. `GameState.set_flag(...)`) —
  no `get_node()` needed. This project uses five of them (below) as the
  "global systems" layer. This is Godot's standard answer to "where does
  shared game state/logic live" — the equivalent of a global service/store in
  a web app, except it's a real node in the scene tree.
- **`res://` vs `user://`.** `res://` is the project's own folder (read-only
  once exported/shipped — this is where `data/*.json` and every scene/script
  live). `user://` is a writable, per-OS app-data folder Godot maps for you
  (e.g. `~/Library/Application Support/Godot/app_userdata/<project>/` on
  macOS) — this is where `save_game.json` lives, never inside the project.
- **Signals.** Godot's pub/sub mechanism (a `signal` declaration, `.emit()`
  to fire, `.connect()` to listen). Used throughout instead of direct
  cross-scene references, so e.g. `DialogueBox` never needs to know
  `InvestigationView` exists — both just react to the same autoload signals.
- **Scene composition + unique names.** A `.tscn` file is a reusable node
  tree; `[node ... instance=ExtResource(...)]` embeds one scene inside
  another (e.g. `PlaceholderVisual.tscn` is embedded in five other scenes).
  A node marked "Access as Unique Name" (`unique_name_in_owner = true` in the
  `.tscn`) can be fetched from anywhere in that scene via `%NodeName` instead
  of a brittle full path like `$Box/Margin/HBox/PortraitVisual`.

## Autoloads (the global systems layer)

Registered in `project.godot` in this order — see `docs/architecture.md#decisions`
for why order barely matters here.

| Autoload | Script | Owns |
|---|---|---|
| `LocaleManager` | `scripts/core/locale_manager.gd` | loads `localization/strings.csv` into `TranslationServer` and owns the active locale (`vi` default, `en` supported) plus its persistence. Registered **first** — no other autoload depends on it, and everything else may need translated text the moment it starts rendering. See `docs/localization.md`. |
| `GameState` | `scripts/core/game_state.gd` | current location, visited locations, evidence inventory, flags, freeform variables, and a generic `seen_interactions` set (which topics/examine points have been played before, plus arbitrary author-chosen "this happened" markers — see "Automatic 'seen' tracking" below). Story-agnostic — never references a specific character/location/item by name. |
| `ContentDB` | `scripts/core/content_db.gd` | loads every `*.json` under `data/` at startup and caches it, then runs `ContentValidator` and prints its report. The **only** system that reads `data/` directly — everything else goes through its getters (`get_character`, `get_evidence`, `get_location`, `get_dialogue`, `get_case`, plus `get_all_*`/`get_all_*_ids` bulk getters used by validation and dev tooling). |
| `DialogueManager` | `scripts/dialogue/dialogue_manager.gd` | plays one dialogue tree at a time, node by node. Pure playback engine — no UI code, no opinion on *why* a given tree was chosen. |
| `Investigation` | `scripts/investigation/investigation_manager.gd` | the "decision layer" for Examine / Talk / Present / Move: figures out *which* dialogue tree should play for the current location + game state, then hands off to `DialogueManager`. Also auto-marks topics/examine points "seen" in `GameState`, and exposes `explain_topic_lock`/`explain_destination_lock` for debug tooling. |
| `EventManager` | `scripts/events/event_manager.gd` | evaluates `data/events/*.json` against `GameState` and runs an event's effects the moment its conditions become true — reacting to state changes instead of a player click. See `docs/event-system.md` for the full design. |
| `CaseManager` | `scripts/cases/case_manager.gd` | orchestrates Case/Chapter progression: starting a case, tracking the current chapter, and advancing to the next chapter once the current one's `completion_event` (an ordinary Event) fires. Holds no state of its own — reads/writes `GameState` only. See `docs/case-system.md`. |
| `SaveManager` | `scripts/save/save_manager.gd` | reads/writes `user://save_game.json`. Owns the save-file format/version; `GameState` itself has no opinion on file format. |

Plus three stateless static helpers (`class_name`, not autoloads):

- **`ConditionEvaluator`** (`scripts/core/condition_evaluator.gd`) evaluates
  the small condition mini-language used throughout content JSON. Used by
  `DialogueManager` (choice conditions), `Investigation` (examine/topic/
  destination/npc-presence conditions), and `EventManager` (event
  conditions).
- **`EffectRunner`** (`scripts/core/effect_runner.gd`) runs this project's
  one effect vocabulary (`set_flag`, `add_evidence`, `remove_evidence`,
  `mark_interaction_complete`) from a list of `{"type": ..., ...}`
  dictionaries. Used by `DialogueManager` (a node/choice's `"actions"`) and
  `EventManager` (an event's `"effects"`) — see `docs/event-system.md`,
  "Reusing Conditions and Effects", for why this was pulled out of
  `DialogueManager` rather than duplicated.
- **`ContentValidator`** (`scripts/core/content_validator.gd`) cross-checks
  everything `ContentDB` loaded for broken references. See "Content
  validation" below.

### Why Investigation is separate from DialogueManager

They're genuinely different concerns: `DialogueManager` only knows how to
play *a* tree once told which one; `Investigation` is the thing that decides
*which* tree, by combining the current location's data with live game state.
Merging them would mean `DialogueManager` needs to know about locations, NPCs,
and evidence — coupling the reusable playback engine to investigation-game
specifics.

## Dialogue: two node kinds, no "branch" node

A dialogue tree (see `docs/content-guide.md` for the full JSON shape) is a
`nodes` dictionary plus a `start` node id. Every node is one of:

- **line** — `{speaker, expression, text, actions?, next?}`. Shows one line,
  runs any `actions` (see below), then either ends (`next` absent/null) or
  moves to another node.
- **line with choices** — same, but `choices: [{text, condition?, actions?, next?}, ...]`
  instead of `next`. Choices are filtered by `condition` before being shown;
  picking one runs its `actions` then moves to its `next`.

`actions` (a list, run in order when a node is entered, or when a choice is
picked) is this project's **effect system** (Part B2 in the original brief
uses that word; the JSON key stays `actions` because it's already the clear,
correct word for "things that happen" — renaming it would have been pure
churn). Currently supports `set_flag`, `add_evidence`, `remove_evidence`,
and `mark_interaction_complete`, executed by `EffectRunner.run()`
(`scripts/core/effect_runner.gd`) — see "Events" below for why that's a
standalone helper rather than a private `DialogueManager` method. Add a new
type there (one more `match` case), and `ContentValidator._validate_effects()`
to keep it validated.

**There is deliberately no third "branch" node type** for silently jumping
based on state with no line shown. That kind of branching — "which dialogue
plays at all" — is resolved one level up, by `Investigation`, via ordered
**variant lists** in the location JSON:

```json
"variants": [
  { "condition": { "has_evidence": "test_key" }, "dialogue_id": "examine_desk_after" },
  { "dialogue_id": "examine_desk_before" }
]
```

`ConditionEvaluator.resolve_variants()` returns the first entry whose
`condition` passes (a missing `condition` always passes, so it's a natural
fallback when listed last). This is used for examine-point variants. NPC
`present_responses` use a related but distinct lookup — see
`Investigation._resolve_present_response()` — because it matches against
*which evidence was just handed over*, not against global game state, so it
can't reuse the condition language.

Keeping this as the only branching mechanism means every dialogue tree is
always a simple linear-with-choices "scene" once started — one engine, not
two.

## The condition mini-language

`ConditionEvaluator.evaluate()` (`scripts/core/condition_evaluator.gd`) accepts:

| Shape | Meaning |
|---|---|
| `null` / absent | always true |
| `{"flag": "x"}` | `GameState.get_flag("x") == true` |
| `{"flag": "x", "equals": false}` | `GameState.get_flag("x") == false` |
| `{"has_evidence": "id"}` | `GameState.has_evidence("id")` |
| `{"visited_location": "id"}` | that location has been entered at least once |
| `{"examined": "id"}` | the **current location's own** examine point with this id has been examined before (see "Automatic 'seen' tracking" below) |
| `{"interaction_complete": "id"}` | a `mark_interaction_complete` effect with this id has fired |
| `{"all": [cond, cond, ...]}` | every sub-condition is true |
| `{"any": [cond, cond, ...]}` | at least one sub-condition is true |
| `{"not": cond}` | the sub-condition is false |

This is deliberately a fixed set of named leaf checks against `GameState`,
not a general-purpose expression language — see "Key Architecture Decisions"
below for why `unlock_topic`/`unlock_location` aren't a separate mechanism on
top of this.

**Anything not on that list evaluates to `false`.** A mistyped key
(`{"has_evidnce": ...}`) is the single most likely authoring mistake in this
format, and the two ways to handle it are not symmetric: content that stays
locked is a bug you notice the moment you playtest, whereas content that
silently unlocks itself at the start of the case is a bug you notice weeks
later, if at all. `ConditionEvaluator.KEYS` is the whitelist, and
`ContentValidator` reads that same constant to reject unknown keys outright,
so in practice the runtime fallback should never be reached. If you add a new
leaf shape, add it to `LEAF_KEYS` in the same commit.

**One condition object holds exactly one check.** `evaluate()` tests the
shapes in a fixed order (that order *is* `KEYS`: composites first, then
leaves) and returns on the first match, so `{"flag": "a", "has_evidence":
"b"}` quietly drops the `has_evidence` half rather than meaning "and". The
validator rejects any object carrying more than one key from `KEYS`, and
names the one that would actually have won — walking `KEYS` rather than the
object's own key order, since JSON key order has nothing to do with
precedence. To require two things, write `{"all": [...]}`.

`ConditionEvaluator.explain(condition)` returns
`[{"description": String, "passed": bool}, ...]` for debug tooling ("explain
locked content"), never for gameplay evaluation. A top-level `all` is
flattened into one entry per part (each one genuinely is required);
everything else — `any` included — stays a **single** entry whose description
spells the whole group out (`ANY of: (has evidence "test_key" OR has evidence
"test_note")`). That grouping matters: flattening an `any` too would make the
debug panel list both alternatives as "missing" when the player only needs
one of them, which is actively misleading in the one feature whose entire job
is explaining why something is locked. See "Developer tools" below.

## Automatic "seen" tracking

`GameState.seen_interactions` is a generic set of namespaced string keys —
`mark_seen(key)` (returns `true` the first time) and `has_seen(key)` are the
whole API. Nothing in content JSON writes to it directly; three things build
keys into it:

- `Investigation.examine(point_id)` marks `"examine:<location_id>:<point_id>"`
  after the examine's dialogue starts. Backs the `{"examined": "..."}`
  condition, so a **flavor-only** examine point (grants no evidence) can
  still show different text on a repeat look, without inventing a flag for
  it — see `mirror` in `data/locations/test_hallway.json`.
- `Investigation.talk(npc_id, topic_id)` marks `"topic:<npc_id>:<topic_id>"`.
  This is the "completed/read" state Part B3 asks for — `is_topic_seen()`
  drives the `(read)` tag `InvestigationView` shows next to a topic that's
  already been talked about. It's automatic (unlike a flag) specifically so
  content authors never have to remember to wire it up per topic.
- The `mark_interaction_complete` effect marks `"custom:<author-chosen id>"`
  — for milestones that aren't tied to one specific topic/examine point (see
  `character_b_greeting`'s `met_character_b` in `data/dialogue/character_b.json`,
  consumed by `character_a`'s `about_character_b` topic).

`visited_locations` (pre-existing, unrelated to `seen_interactions`) stays a
separate, simpler array — it only ever needed "was this location entered,"
recorded by `GameState.go_to_location()` itself, and merging it into the
newer namespaced set wouldn't have added anything.

## Events

`EventManager` reacts to `GameState` changes: `data/events/*.json` content
defines a `condition` (the same mini-language above) plus `effects` (the
same vocabulary dialogue actions use, via `EffectRunner`), and the moment a
not-yet-triggered event's condition becomes true, its effects run
automatically — no player click required. This is what lets a case express
"talking to X plus holding Y causes Z to happen" as content instead of
bespoke GDScript. Full design — trigger policies, event chains, character
presence via NPC-entry conditions, debugging, save/load, validation — is in
`docs/event-system.md`; only the parts relevant elsewhere in this document
are summarized here:

- Events add **zero** new condition or effect vocabulary — they're built
  entirely on `ConditionEvaluator` and `EffectRunner`, the same two helpers
  everything else in this section uses.
- A character's location is now dynamic, via the same "flag + condition"
  pattern the "no `unlock_topic`" decision below already established for
  everything else — see the matching decision entry below, and
  `docs/event-system.md`'s "Character presence."
- No per-frame polling: evaluation runs off the same `GameState` signals
  `InvestigationView`/`DebugPanel` already listen to.

## Case / Chapter progression

`CaseManager` (Milestone 1.6) organizes a case's content into an ordered
sequence of **Chapters** — "the currently active phase" — without adding any
new condition/effect/evaluation machinery. Full design — chapter fields, why
completion is modeled as an ordinary Event rather than a second evaluator,
runtime state, scoping, namespacing, save/load, developer tools, and
validation — is in `docs/case-system.md`; only the parts relevant elsewhere
in this document are summarized here:

- A **Case** (`data/cases/*.json`) optionally declares `chapters` (an
  ordered list of chapter ids) and `starting_chapter`. A case that omits
  both, like `case_00_sandbox`, is a **flat case** — entirely unaffected by
  any of this, which is how Milestone 0-1.5 backward compatibility is
  proven rather than assumed.
- A **Chapter** (`data/chapters/<case_id>/*.json`, its own `ContentDB`
  category) has optional `entry_effects` (run once via `EffectRunner` when
  it becomes current), an optional `completion_event` (an id in
  `data/events/*.json` — its `conditions`/`effects` *are* the chapter's
  completion conditions/effects), and an optional `next_chapter`.
- `CaseManager` holds no persisted state of its own: "current case/chapter"
  lives in `GameState.variables`, and "chapter/case completed" reuses the
  same `seen_interactions` "has this happened" set a `"once"` event's
  triggered state already uses (see "Automatic 'seen' tracking" above) — so
  save/load round-trips case progression with zero save-format changes.
- `CaseManager` never calls `ConditionEvaluator` itself — it only listens to
  `EventManager.event_triggered` and checks whether the event that fired is
  the current chapter's `completion_event`. This is deliberate: it reuses
  `EventManager`'s already-correct reentrant evaluation loop instead of
  building a second one. See `docs/case-system.md`, "Why chapter completion
  is an Event, not a second evaluator."
- Content that should only be reachable during one chapter (chapter-scoped
  content/events) uses the same `set_flag` + `condition` idiom as every
  other "unlock" in this project (see "Key Architecture Decisions" below): a
  chapter's own `entry_effects` sets a scope flag, and scoped content
  requires it.

## Localization

Every player-facing string — content (`data/*.json`) and static UI chrome —
is a **translation key**, not literal text, resolved through Godot's real
`TranslationServer`/`tr()` (a `name`/`label`/`text`/`display_name`/
`description` field that used to hold "Old Key" now holds
`EVID_TEST_KEY_NAME`). Full design — why the CSV is loaded at runtime
instead of through Godot's asset-import pipeline, the key-naming convention,
why UI code calls `tr()` explicitly instead of relying on `Control`
auto-translation, which screens react live to a language switch, and
content validation — is in `docs/localization.md`; only what's relevant
elsewhere in this document is summarized here:

- `LocaleManager` (registered first in `[autoload]`) loads
  `localization/strings.csv` into `TranslationServer` and owns the active
  locale (`vi` default) plus its persistence (`user://settings.cfg`, a
  `ConfigFile` — a player preference, kept separate from
  `user://save_game.json` the same way "`res://` vs `user://`" above
  already separates content from state).
- No new condition/effect vocabulary, and no second "translated content"
  system alongside `ContentDB` — `ContentDB`/`Investigation`/
  `DialogueManager`/`EventManager`/`CaseManager` are completely unaware
  translation keys exist; they still just pass `Dictionary` values around
  exactly as before. Only the UI layer (where a string is actually assigned
  to a `Label`/`Button`) calls `tr()`.
- `GameMenu` has the player-facing VI/EN toggle. `InvestigationView` (the
  screen left visible, dimmed, behind `GameMenu`) and `DebugPanel` also
  react live to a locale change; every other screen simply renders fresh
  text the next time it opens, since none of them can be on screen at the
  same moment the toggle is reachable — see `docs/localization.md` for why.

## UI scene tree

```
TitleScreen.tscn  (Godot "Main Scene" — New Game / Continue / Quit)
        │  New Game or Continue → change_scene_to_file
        ▼
Main.tscn  (pure orchestrator — scripts/ui/main.gd)
 ├─ InvestigationView.tscn   (base layer: location, Examine/Talk/Move)
 ├─ DialogueBox.tscn         (overlay, shown while DialogueManager.is_active)
 ├─ EvidenceInventory.tscn   (overlay: browse, or "select" mode for Present)
 ├─ GameMenu.tscn            (overlay: Save / Load / New Game / Resume / Quit)
 └─ DebugPanel.tscn          (overlay, debug builds only — see "Developer tools")
```

Child order is also draw/input order: later children draw on top, and `_input`
is delivered in reverse tree order, so `DebugPanel` (last) gets first refusal
on **Esc** and `InvestigationView` (first) gets it last. All three overlays
use `_input` for Esc, deliberately, so that "topmost overlay closes first"
holds.

`Main.gd` is the **only** place that wires these four scenes to each other —
none of them hold a reference to any of the others. They talk exclusively
through:

1. **Autoload signals** every UI scene listens to directly (`GameState.flag_changed`,
   `DialogueManager.dialogue_started`, etc.) — this is how, for example,
   `InvestigationView` knows to re-render its action list after a flag
   changes, without anyone telling it to.
2. **Scene-local signals** for things that are genuinely about this UI, not
   game state — e.g. `InvestigationView.present_requested(npc_id)` fires
   when the player picks "Present Evidence" for an NPC; `Main.gd` catches it
   and calls `evidence_inventory.open("select")`, then later routes
   `EvidenceInventory.evidence_chosen_for_present(evidence_id)` into
   `Investigation.present(evidence_id, npc_id)`. Neither scene knows the
   other exists.

`Main.gd` also disables `InvestigationView` (via `set_interactive(false)`)
for the duration of every dialogue, so a click landing mid-typewriter can't
kick off a second, overlapping action.

Two non-obvious rules make that guarantee actually hold, and both are easy to
break by accident:

- **`InvestigationView` re-applies its interactive state after every
  re-render.** Its action buttons are created at runtime, and dialogue
  actions routinely change game state mid-dialogue (`add_evidence`,
  `set_flag`), which re-renders the list. Freshly created `Button`s default
  to `disabled = false`, so a render that forgot to re-apply the flag handed
  the player a live action list while a dialogue was still on screen. The
  state lives in `_is_interactive` and every `_render_*` ends with
  `_apply_interactive()`.
- **`Investigation` refuses all four verbs while `DialogueManager.is_active`**
  (`_is_busy()`), and `DialogueManager.start()` returns a `bool` that
  `examine()`/`talk()` must check before marking anything seen. The UI guard
  above is a convenience; this one is the correctness guarantee. Without it,
  a rejected examine still marked its point as examined — so its
  evidence-granting "first look" variant was skipped forever, with no error
  anywhere. Never call `GameState.mark_seen()` next to a `start()` you
  haven't checked.

### Reusable UI building blocks

- **`PlaceholderVisual.tscn`** (`scripts/ui/placeholder_visual.gd`) — a
  `ColorRect` + `Label`, used for every portrait, background, and evidence
  icon. `set_color_hex("#RRGGBB")` + `set_caption(text)` is the entire API.
  Swapping in real art later means changing this one scene (e.g. to a
  `TextureRect` that prefers a real texture path and falls back to the
  color), not every call site.
- **`EvidenceSlot.tscn`** (`scripts/evidence/evidence_slot.gd`) — one
  clickable grid entry in `EvidenceInventory`, itself built from a `Button` +
  one `PlaceholderVisual`.
- **`UiUtil.clear_children(parent)`** (`scripts/ui/ui_util.gd`) — the one
  correct way to rebuild a runtime-built list here. Every UI in this project
  clears and repopulates a container (action list, dialogue choices, evidence
  grid, debug report), and the obvious `for child in get_children():
  child.queue_free()` is a trap: `queue_free()` only schedules deletion for
  the end of the frame, so nodes added straight afterwards coexist with the
  "deleted" ones — still visible, still laid out, still connected. In
  `DialogueBox` that meant a stale choice button bound to its old index could
  still be clicked, resolving against a different set of choices.
  `clear_children()` does `remove_child()` (synchronous) then `queue_free()`.

### The `EvidenceInventory` mouse_filter chain, for anyone editing DialogueBox

`DialogueBox`'s "click anywhere to advance" relies on Godot's `mouse_filter`
propagation, which is easy to get subtly wrong (see `docs/architecture.md#decisions`
for how these values were actually confirmed rather than guessed). The rule
that matters: `Label` defaults to `IGNORE` (clicks fall through it), Panels/
Buttons/ColorRects default to `STOP` (clicks are absorbed right there), and
Containers (`VBoxContainer` etc.) default to `PASS` (seen here *and* passed
further behind). `DialogueBox`'s root is `STOP` with its own `_gui_input()`;
its inner `Box` panel is explicitly overridden to `PASS` so a click on the
box's background still reaches the root instead of being silently eaten by
the panel. A choice `Button` still wins over both, since it's checked first
(children are hit-tested before their parents).

## Content / data structure

Everything under `data/` is plain JSON, loaded once at startup by `ContentDB`
(see `_load_json_dir()`), and is the **only** thing that varies between a
placeholder sandbox and a real case — no script in `scripts/` should ever
need to change to add content. Full schemas and how-tos are in
`docs/content-guide.md`; summary:

Every `name`/`label`/`text`/`display_name`/`description` field below holds a
**translation key** resolved through `TranslationServer`, not literal text —
see `docs/localization.md`.

| Folder | Shape |
|---|---|
| `data/characters/*.json` | one character per file: `id`, `name`, `expressions` (name → placeholder color) |
| `data/evidence/*.json` | one item per file: `id`, `name`, `icon_color`, `short_description`, `detailed_description` |
| `data/locations/*.json` | one location per file: `background_color`, `npcs` (with an optional presence `condition`, `topics`/`present_responses`), `examine_points` (with `variants`), `destinations` |
| `data/dialogue/*.json` | **array** of dialogue trees per file (a file can group several related trees) |
| `data/chapters/<case_id>/*.json` | one chapter per file: `id`, `display_name`, `entry_effects`, `completion_event`, `next_chapter` — see `docs/case-system.md` |
| `data/cases/*.json` | one case per file: `start_location`, `initial_flags` — what "New Game" resets to; optionally `chapters` + `starting_chapter` — see `docs/case-system.md` |
| `data/events/*.json` | **array** of events per file: `id`, `conditions`, `trigger_policy`, `effects` — see `docs/event-system.md` |

Dropping a new `*.json` file into any of these folders is enough to register
it — nothing needs to be imported or listed elsewhere. **Subfolders are
scanned too**, so a case can keep its files together
(`data/dialogue/case_01/*.json`) without any change to how content is looked
up; folder layout is purely for humans.

IDs must be unique within their category (characters vs. evidence vs.
locations vs. dialogue trees vs. cases are separate namespaces), regardless
of which folder or file they live in. A duplicate means the **later**-loaded
entry replaces the earlier one — and since `res://` directory iteration order
isn't guaranteed, which one "wins" isn't either. `ContentDB` records every
collision it sees (`get_duplicate_id_issues()`) and `ContentValidator`
reports them as errors, naming both files.

## Content validation

`ContentValidator` (`scripts/core/content_validator.gd`) cross-checks every
reference inside the content `ContentDB` already loaded — the kind of typo a
human or an AI coding agent hand-editing JSON is likely to make. It is
**not** a JSON schema validator (malformed JSON already fails loudly in
`ContentDB._load_json_file()`) and it does not attempt to prove a case is
completable (see "Known limitations" and Part F of the original brief for
why that's explicitly out of scope).

It checks two severities:

- **errors** — a broken reference that will misbehave at runtime: an NPC
  that isn't a known character, a topic/examine variant/present-response
  pointing at a dialogue id that doesn't exist, a dialogue node's `next`/
  choice `next` pointing at a node id that doesn't exist, a `speaker`/
  `expression` that doesn't exist, a `has_evidence`/`visited_location`/
  `examined` condition referencing an id that doesn't exist, a destination
  or case `start_location` pointing at an unknown location, an `add_evidence`
  /`remove_evidence` action referencing unknown evidence, or an action with
  no (or an unrecognized) `type` — and the same for an event's `effects` and
  an npc entry's presence `condition` (see `docs/event-system.md`). Also: a condition using an **unknown key**
  (checked against `ConditionEvaluator.KEYS`, so a typo is caught at
  validation time instead of silently locking content), an `all`/`any` that
  isn't a non-empty array, a **duplicate id** — either across content files
  within one category, or repeated inside a single location's `npcs` /
  `topics` / `examine_points` / `destinations` list, where every lookup is
  first-match-wins so the second entry is unreachable — an entry missing its
  id entirely, a condition object stacking more than one check (see "The
  condition mini-language" above), and a `set_flag` action value or case
  `initial_flags` value that isn't a boolean (`GameState.get_flag()` is typed
  `-> bool`).
- **warnings** — a content smell that isn't broken yet: a `present_responses`
  list with no generic (no-`evidence_id`) fallback entry, an NPC with no
  `present_responses` at all (presenting evidence to them produces no
  dialogue and no feedback whatsoever — a silent dead end), an
  `examine_points` variant list with no unconditional fallback entry, a
  character with no `normal` expression, a placeholder color string that
  isn't valid hex, a **dialogue node nothing can reach** (the validator
  walks each tree from its `start` through every `next` and choice `next`;
  an orphan is nearly always a typo in some other node's `next`, and the
  dialogue still "works" — it just silently skips content you wrote), or
  (Milestone 1.7) a **dependency-reachability smell**: a condition requiring
  a flag/evidence id/interaction-complete id that no Effect anywhere in
  loaded content is capable of ever producing — see `docs/testing.md`,
  "Progression dependency validation", for the full design and its
  deliberate limits (it is not a reachability *proof*, the same stance as
  everywhere else in this section).

It runs automatically every boot (`ContentDB._ready()` calls
`ContentValidator.validate()` then `.report()`, prefixing every line with
`[ContentValidator]`), and is also runnable standalone for a scriptable exit
code:

```bash
godot --headless --path . -s res://scenes/test/validate_content.gd
```

exits `1` if there are any errors, `0` otherwise (warnings don't fail the
build). See `docs/content-guide.md`, "Validating content", for the authoring
workflow this is meant to support.

**Why `validate_content.gd` reaches `ContentValidator` through
`ContentDB.get_last_validation_result()` instead of calling
`ContentValidator.validate()` directly** — a real Godot compile-order bug,
found while building this: a `class_name` script that itself references an
autoload by bare name (`ContentValidator` references `ContentDB`), when
called directly from a custom `-s` entry script, gets force-compiled during
that entry script's own restricted early compile pass — before autoload
identifiers are registered — and fails with `Identifier not found:
ContentDB`. Worse, GDScript caches that failed compile, so `ContentValidator`
then stays broken for the rest of the process, including inside `ContentDB`'s
own normal `_ready()` call to it. Routing through the autoload's own method
(the same `get_root().get_node("ContentDB")` pattern `smoke_test.gd` already
uses for every autoload) sidesteps it entirely. See "Known limitations"
below — this is an addition to the `-s` entry-point quirk already documented
there.

## Developer tools

`DebugPanel` (`scenes/debug/DebugPanel.tscn` + `scripts/debug/debug_panel.gd`),
the **Case Debugger**, is an **F1-toggled** overlay, entirely self-contained —
unlike `GameMenu`/`EvidenceInventory` it's never wired up by `Main.gd`,
because nothing else needs to coordinate with it. As of Milestone 1.8 it's a
tabbed panel (State / Evidence / Location / NPCs / Events / Case & Chapter /
Inspector / Log) above a live-refreshing Case/Chapter/Location header — full
design, the Condition Inspector, "known producers" lookup, and exactly which
actions are normal-pipeline mutations vs. explicit debug overrides are in
`docs/case-debugger.md`; only what's relevant elsewhere in this document is
summarized here. It reads state through the exact same public APIs normal
gameplay UI uses (`GameState`/`ContentDB`/`Investigation`/`EventManager`/
`CaseManager` — no back-door access), built on the same
`ConditionEvaluator.explain()`/`explain_tree()` (Part E, "explain locked
content") every "why is this locked" panel uses — an `any` is reported as a
single grouped line in the flat breakdowns (never as several
separately-"missing" alternatives, see "The condition mini-language" above),
while the Inspector tab's nested tree view shows an `any`'s branches in full.

Jump (location) and Reset Case both call `DialogueManager.stop()` first. They
are the only path in the game that can change location or reset the case
while a dialogue is on screen — `Investigation` refuses to, and the Menu
button is disabled mid-dialogue — and letting that dialogue keep running
would fire the rest of its actions into state it was never written against.
`stop()` exists for exactly this and has no gameplay caller.

**Isolated from normal gameplay, and inert in a release build almost for
free**: `_ready()` checks `OS.is_debug_build()` first and returns
immediately (no signal connections, no input handling) if it's false —
which an exported release build already sets to false automatically, so
there's nothing to strip by hand later. The node stays in `Main.tscn`'s tree
either way; in a release build it's just a hidden `Control` that never does
anything.

## Key Architecture Decisions {#decisions}

```
DECISION: There is no "unlock_topic"/"unlock_location" effect. Unlocking a
topic or destination is just: an effect (usually set_flag, or the automatic
"seen"/"interaction_complete" tracking) changes GameState, and that topic's
or destination's own `condition` re-evaluates true. "Unlock the hallway" in
the brief's example flow is what set_flag("hallway_unlocked", true) plus a
condition consuming that flag already does — see present_responses in
test_room.json / the about_key topic and test_hallway destination that
consume it.

WHY: set_flag + condition is already a fully generic "make content available
later" mechanism — any topic, destination, or dialogue choice can be gated
on any flag, evidence, visited-location, examined, or interaction-complete
condition, in any combination. A parallel unlock_topic/unlock_location
effect that also flips availability would do the identical job through a
second code path, for no new capability — genuinely the opposite of "keep
effects generic," since it would special-case per content type what the
existing mechanism already handles uniformly.

ALTERNATIVES: A registry of "unlocked topic/location ids" that unlock_topic/
unlock_location effects write to and a matching {"topic_unlocked": "..."}/
{"location_unlocked": "..."} condition reads — functionally identical to
set_flag + {"flag": "..."}, just with different names and a second bookkeeping
structure alongside `flags` in GameState to keep in sync.

IMPACT: Content authors always reach for set_flag (or the automatic seen/
interaction_complete tracking) plus a `condition` to gate anything — one
mechanism, not "set_flag for some things, unlock_X for others." Revisitable
later if a future case needs unlock semantics set_flag genuinely can't
express (none has come up through Milestone 0 or this pass).
```

```
DECISION: A character's presence in a location is dynamic via the exact same
mechanism as the decision above: an optional `condition` on each npc entry
in location JSON, filtered by Investigation.get_npcs(). There is no
add_character_to_location/remove_character_from_location effect and no
GameState field tracking "where is character X" — an event "moves" a
character by setting one flag that two locations' npc entries both
reference with complementary conditions.

WHY: This is literally the same shape as "no unlock_topic/unlock_location"
above, applied to a third kind of content-gated availability (npcs, after
topics/destinations). A dedicated character-location mechanism would need
its own GameState storage (a second source of truth for "where is this
character" alongside the location JSON that still has to define that
character's topics/present_responses wherever they end up anyway — an event
effect can't invent those), plus two new effect types, for a capability
set_flag + condition already provides uniformly.

ALTERNATIVES: add_character_to_location/remove_character_from_location
effects backed by a GameState.character_location_overrides map, with
Investigation.get_npcs() merging a location's static npcs list against that
map. Considered and rejected — see docs/event-system.md, "Character
presence," for the fuller comparison (the destination location still needs
its own static npc entry for topics/present_responses either way, so the
override map doesn't actually remove any authoring work — it just adds a
second bookkeeping structure next to the JSON that already has to exist).

IMPACT: Moving a character is entirely a content/condition concern — no new
GameState field, no new effect type, and Investigation.get_npcs()'s filter
is the one place that decides presence, the same way get_topics()/
get_available_destinations() already decide topic/destination availability.
The tradeoff: nothing enforces that a character's presence conditions across
different locations are mutually exclusive — see docs/event-system.md,
"Known limitations."
```

```
DECISION: All game content (characters, evidence, locations, dialogue, cases,
events) is authored as plain JSON under data/, loaded/cached at runtime by
ContentDB.
Runtime lookups return plain Dictionary, not typed Resource/wrapper classes.

WHY: Needs to be easy for a human or an AI coding agent to hand-edit
reliably later, and to fail loudly (a JSON parse error with file+line) rather
than silently, when it's wrong.

ALTERNATIVES: Godot .tres Resource files — native Inspector editing, typed
fields — but the text-resource format (load_steps counts, ext_resource ids)
is fragile to hand-edit and a common source of silent breakage. Typed
RefCounted wrapper classes around the parsed data — safer key access, but
pure boilerplate at this scale.

IMPACT: No Inspector-driven content authoring. Every optional field is read
via dict.get(key, default), never dict[key], and raw content access is
funneled through ContentDB's getters / small domain helpers (Investigation's
_resolve_present_response, etc.) rather than repeated key-chains, to contain
the blast radius of a typo'd key. Revisitable later — wrapping the returned
dictionaries in typed accessor classes wouldn't require changing the JSON
format itself.
```

```
DECISION: Placeholder visuals (portraits, backgrounds, evidence icons) are
ColorRect + Label (PlaceholderVisual.tscn), colored via a hex string in JSON,
not image files.

WHY: Zero art pipeline, zero binary assets, zero missing-file risk, while
still making expression-switching visually obvious (each expression is a
different color) and evidence icons visually distinct.

ALTERNATIVES: Procedurally generated ImageTexture placeholders (more "real"
but pointless extra code for something that has to be replaced anyway);
actual placeholder PNGs (needs an image-generation step / dependency, and
`assets/` staying genuinely empty is more honest about Milestone 0's scope).

IMPACT: assets/backgrounds, assets/characters, assets/evidence, assets/ui
exist (with .gitkeep) but are empty until real art exists. Swapping in real
art later means changing PlaceholderVisual.tscn/.gd (e.g. to a TextureRect
that prefers a real texture path and falls back to the color), not every
place that currently calls set_color_hex().
```

```
DECISION: Dialogue trees have exactly two node kinds (line; line-with-choices)
and no internal "branch" node. Which dialogue tree plays at all (e.g.
examine-desk-before-key vs. after) is resolved by Investigation via an
ordered "variants" list in the location JSON, not inside the dialogue tree.

WHY: Avoids building two parallel branching systems (a conversation engine
and a separate examine/present engine); keeps every dialogue tree a simple
linear-with-choices "scene" regardless of where it's triggered from.

ALTERNATIVES: A dedicated branch/conditional-start node type inside dialogue
trees, evaluated on entry before showing anything.

IMPACT: Simpler schema, fewer node kinds to document and to get wrong by
hand. Verified sufficient for every case in the Milestone 0 demo flow
(scenes/test/smoke_test.gd exercises both the examine-variant and
present-response-variant paths). Extendable later — letting `next` optionally
be a variant list — without a redesign, if a future case needs a silent
mid-tree branch that isn't player-facing.
```

## Known limitations

- **`ContentDB`'s JSON loading won't survive an export as-is.** It globs
  `res://data/**/*.json` with `DirAccess` at runtime, which works from the
  editor/source (all Milestone 0 needs). Godot only auto-bundles recognized
  *resource* types into an exported `.pck`; exporting a real build later will
  need `data/*` added to the export preset's "non-resource files/folders"
  filter (Project → Export → Resources tab), or the JSON simply won't be
  there at runtime. No export preset exists yet in this milestone, so this
  is a note for later, not a bug now.
- **A Godot quirk this project works around**: a script run as the direct
  entry point via `godot -s some_script.gd` (as `scenes/test/smoke_test.gd`
  is) does **not** get the usual compile-time autoload name resolution every
  *other* script in the project gets — referencing `GameState` by bare name
  in such a script fails to compile with `Identifier not found`, even though
  the exact same reference works everywhere else. `smoke_test.gd` works
  around this with `get_root().get_node("GameState")` instead. This is
  specific to being the `-s` entry-point script; it does not affect
  `game_state.gd`, `dialogue_manager.gd`, or any other script in this
  project, which are all loaded the normal way and reference each other by
  bare autoload name without issue.
- **`godot --headless --check-only -s <file>.gd`, run per-script, is not a
  trustworthy way to lint this codebase.** It produces a false-positive
  `Identifier not found: <Autoload>` for any script that references another
  autoload by name (a known engine issue, godotengine/godot#80319) — which
  is most scripts here, by design. Trust the full boot
  (`godot --headless --path . --quit-after N`, grep output for `ERROR`) and
  `scenes/test/smoke_test.gd` instead.
- **The `-s` entry-point quirk above is bigger than just the entry script
  itself — it can silently break an unrelated autoload for the rest of the
  process.** Discovered while building `ContentValidator`: a `class_name`
  script that references an autoload by bare name, if a custom `-s` entry
  script statically calls into it (e.g. `ContentValidator.validate()`
  written directly in the entry script), forces that `class_name` script to
  compile during the entry script's own restricted early pass — before
  autoload identifiers exist — and fails with `Identifier not found`.
  GDScript then **caches that failed compile**, so the class stays broken
  for the rest of that process, including for completely normal callers
  later (`ContentDB._ready()`'s own call to `ContentValidator`, which works
  fine in every other context, failed too in this repro). Fix: reach such a
  class only through an autoload's own method
  (`ContentDB.get_last_validation_result()`), via `get_root().get_node()`,
  never by the class's bare name, from inside a custom `-s` script — see
  `scenes/test/validate_content.gd`'s comment for the full repro. Worth
  remembering before adding a second `-s` tooling script that reaches for
  `ConditionEvaluator` or `ContentValidator` directly.
- **UI click-routing is verified by value-inspection, not a simulated
  click.** `smoke_test.gd` instantiates `Main.tscn` and asserts the
  `mouse_filter` values on `DialogueBox`, `EvidenceInventory`, and
  `GameMenu` are what the click-handling design requires (see the
  mouse_filter section above), rather than injecting a real
  `InputEventMouseButton` and checking the outcome. This is because a
  headless CLI agent has no way to *see* the result of a real click to
  confirm it visually. The gameplay/state logic (examine, talk, present,
  move, flags, evidence, save/load) is exercised for real, end to end, via
  direct autoload calls — only the pixel-click routing layer relies on
  reasoning + value assertions instead. `DebugPanel` is checked the same
  way (instantiated, `open()`/`close()` toggled, visibility asserted) — no
  screenshot tooling was available in the environment this was built in to
  visually confirm its layout renders correctly; a human should eyeball it
  (F1 in a running build) before relying on it heavily.
- **Single save slot.** `user://save_game.json` — matches the Milestone 0
  spec; a slot-selection UI is out of scope here. `SaveManager.save_path` is
  a variable rather than a constant so automated tests can point at a
  throwaway file (`smoke_test.gd` does, so running the tests never destroys a
  game in progress); gameplay never changes it.
- **Save `variables` round-trip through JSON, so numbers come back as
  floats.** `flags` are sanitized on load (non-booleans are rejected and
  reported), but `variables` are free-form by design and are restored as-is.
  If a future case stores an integer counter there, compare it as a number,
  not with `is` / strict typing.
- **`ContentValidator` does not detect unreferenced content.** A dialogue
  tree that nothing points at (like `test_effects_remove_evidence`, which
  exists purely for the smoke test) is legitimate, so orphans are not
  reported. If a case's dialogue never plays, the validator will not tell
  you.
- **`res://` DirAccess iteration order is not guaranteed alphabetical**, and
  subfolders are walked in whatever order they come back in. Harmless as long
  as every content id is unique (which `ContentValidator` now enforces), but
  it does mean you can never rely on one content file "overriding" another.
- **`ContentValidator` checks references, not solvability.** It can't tell
  you a case is unwinnable because two mutually-exclusive flags are both
  required somewhere, or that a topic is unreachable because nothing ever
  sets the flag it depends on — see Part F of the brief this pass was built
  against: that's explicitly out of scope ("do NOT attempt to build a full
  theorem prover"). It only catches dangling references and a couple of
  cheap structural smells (missing fallback entries).

## Verification

See `docs/testing.md` for the full test organization (Milestone 1.7 split
`smoke_test.gd`'s condition-language checks and added several independent
focused/regression test scripts alongside it — `scenes/test/*_test.gd`), the
FAST/FULL commands, and CI. What follows describes the four raw verification
layers those scripts are built on, in order of how much they actually prove:

```bash
# 1. Force import, surface scene/resource reference errors.
godot --headless --import --path .

# 2. Boot the real project for a few seconds, catch runtime errors in the
#    normal TitleScreen -> autoloads boot path. --quit-after does not set a
#    nonzero exit code for script errors, so grep the output instead of $?.
#    This also runs ContentValidator and prints its report.
godot --headless --path . --quit-after 60

# 3. Content validation as a scriptable pass/fail, independent of the full
#    smoke test — useful as a fast check after only editing data/*.json.
#    Exits 1 if ContentValidator found any errors, 0 otherwise.
godot --headless --path . -s res://scenes/test/validate_content.gd

# 4. The authoritative end-to-end check: drives GameState / ContentDB /
#    DialogueManager / Investigation / EventManager / CaseManager /
#    SaveManager / LocaleManager through the full demo flow (talk, examine + repeat,
#    evidence, present x2 (specific + generic), flag/`all`/`any`/
#    `visited_location`/`examined`/`interaction_complete`-gated topics,
#    "explain locked content", topic "seen" state, move both directions, an
#    event chain that moves a character and unlocks new content, a
#    repeatable event, manual event trigger, save, reset, load — including
#    that the new seen_interactions state (event-triggered state included)
#    round-trips and a triggered "once" event does not refire — then the
#    Test Case end to end (CaseManager.start_case, both chapters completing
#    in order with chapter-scoped content and a save/load round trip mid-
#    chapter, case completion, developer tools, and that a flat case like
#    case_00_sandbox is unaffected) — then bilingual localization (both
#    locales resolve correctly, an unsupported locale is rejected, the
#    persisted preference round-trips, an already-visible InvestigationView
#    re-renders live on a locale switch, and ContentValidator catches a
#    translation missing from a locale) — then instantiates Main.tscn +
#    TitleScreen.tscn and checks they (DebugPanel included) wire up without
#    error. Also asserts ContentValidator found zero errors AND zero
#    warnings in the real sandbox content. Prints "ALL TESTS PASSED" and
#    exits 0 on success.
godot --headless --path . -s res://scenes/test/smoke_test.gd
```

Beyond the demo flow, `smoke_test.gd` also pins down the behaviours that are
easy to regress silently: that a mistyped condition key fails **closed**,
that `explain()` keeps an `any` as one grouped line, that a verb rejected
mid-dialogue (examine/talk/present/move) mutates **no** state, that
re-rendering the action list while a dialogue is playing does not re-enable
its buttons, and that rebuilding a button list leaves no stale children
behind.

See `README.md` for how to run the game itself and for the full control
reference.

`ContentValidator` was additionally verified to actually *catch* problems
(not just pass clean content vacuously) by temporarily editing
`data/dialogue/test_effects.json` to reference an unknown character,
unknown evidence id, and unknown node id, re-running step 3, confirming all
three were reported with the correct message and a nonzero exit code, then
reverting.
