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
effect vocabulary, automatic content validation, and developer tooling — see
"Content validation" and "Developer tools" below. None of this decides final
deduction/case-solving gameplay; see this doc's closing note and
`docs/content-guide.md` for what's still deliberately undecided.

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
| `GameState` | `scripts/core/game_state.gd` | current location, visited locations, evidence inventory, flags, freeform variables, and a generic `seen_interactions` set (which topics/examine points have been played before, plus arbitrary author-chosen "this happened" markers — see "Automatic 'seen' tracking" below). Story-agnostic — never references a specific character/location/item by name. |
| `ContentDB` | `scripts/core/content_db.gd` | loads every `*.json` under `data/` at startup and caches it, then runs `ContentValidator` and prints its report. The **only** system that reads `data/` directly — everything else goes through its getters (`get_character`, `get_evidence`, `get_location`, `get_dialogue`, `get_case`, plus `get_all_*`/`get_all_*_ids` bulk getters used by validation and dev tooling). |
| `DialogueManager` | `scripts/dialogue/dialogue_manager.gd` | plays one dialogue tree at a time, node by node. Pure playback engine — no UI code, no opinion on *why* a given tree was chosen. |
| `Investigation` | `scripts/investigation/investigation_manager.gd` | the "decision layer" for Examine / Talk / Present / Move: figures out *which* dialogue tree should play for the current location + game state, then hands off to `DialogueManager`. Also auto-marks topics/examine points "seen" in `GameState`, and exposes `explain_topic_lock`/`explain_destination_lock` for debug tooling. |
| `SaveManager` | `scripts/save/save_manager.gd` | reads/writes `user://save_game.json`. Owns the save-file format/version; `GameState` itself has no opinion on file format. |

Plus two stateless static helpers (`class_name`, not autoloads):

- **`ConditionEvaluator`** (`scripts/core/condition_evaluator.gd`) evaluates
  the small condition mini-language used throughout content JSON. Used by
  both `DialogueManager` (choice conditions) and `Investigation` (examine/
  topic/destination conditions).
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
and `mark_interaction_complete` — see `scripts/dialogue/dialogue_manager.gd`'s
`_run_actions` to add a new type.

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

`ConditionEvaluator.explain(condition)` walks the same shapes and returns a
flat `[{"description": String, "passed": bool}, ...]` for every leaf found
(recursing into `all`/`any`/`not`) — used only by debug tooling ("explain
locked content"), never by gameplay evaluation. See "Developer tools" below.

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

## UI scene tree

```
TitleScreen.tscn  (Godot "Main Scene" — New Game / Continue / Quit)
        │  New Game or Continue → change_scene_to_file
        ▼
Main.tscn  (pure orchestrator — scripts/ui/main.gd)
 ├─ InvestigationView.tscn   (base layer: location, Examine/Talk/Move)
 ├─ DialogueBox.tscn         (overlay, shown while DialogueManager.is_active)
 ├─ EvidenceInventory.tscn   (overlay: browse, or "select" mode for Present)
 └─ GameMenu.tscn            (overlay: Save / Load / New Game / Resume / Quit)
```

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

| Folder | Shape |
|---|---|
| `data/characters/*.json` | one character per file: `id`, `name`, `expressions` (name → placeholder color) |
| `data/evidence/*.json` | one item per file: `id`, `name`, `icon_color`, `short_description`, `detailed_description` |
| `data/locations/*.json` | one location per file: `background_color`, `npcs` (with `topics`/`present_responses`), `examine_points` (with `variants`), `destinations` |
| `data/dialogue/*.json` | **array** of dialogue trees per file (a file can group several related trees) |
| `data/cases/*.json` | one case per file: `start_location`, `initial_flags` — what "New Game" resets to |

Dropping a new `*.json` file into any of these folders is enough to register
it — nothing needs to be imported or listed elsewhere. IDs must be unique
within their category (characters vs. evidence vs. locations vs. dialogue
trees vs. cases are separate namespaces); `ContentDB` logs a warning if a
duplicate id silently overwrites an earlier one.

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
  no (or an unrecognized) `type`.
- **warnings** — a content smell that isn't broken yet: a `present_responses`
  list with no generic (no-`evidence_id`) fallback entry, an `examine_points`
  variant list with no unconditional fallback entry, a character with no
  `normal` expression, or a placeholder color string that isn't valid hex.

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

`DebugPanel` (`scenes/debug/DebugPanel.tscn` + `scripts/debug/debug_panel.gd`)
is an **F1-toggled** overlay, entirely self-contained — unlike `GameMenu`/
`EvidenceInventory` it's never wired up by `Main.gd`, because nothing else
needs to coordinate with it. It reads state through the exact same public
APIs normal gameplay UI uses (`GameState`/`ContentDB`/`Investigation` — no
back-door access) and shows: current location, visited locations, evidence
held, all flags, and — per location NPC and per destination — whether it's
`AVAILABLE` or `LOCKED`, with `Investigation.explain_topic_lock()`/
`explain_destination_lock()` listing exactly which sub-condition(s) are
still failing (Part E, "explain locked content"). Actions: toggle any flag,
add/remove any evidence id, jump to any location id (bypassing that
destination's `condition` — it's a teleport for testing, not a move), and
reset the sandbox to the current case's starting state.

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
DECISION: All game content (characters, evidence, locations, dialogue, cases)
is authored as plain JSON under data/, loaded/cached at runtime by ContentDB.
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
  spec; a slot-selection UI is out of scope here.
- **`res://` DirAccess iteration order is not guaranteed alphabetical.**
  Harmless today since every `data/*.json` file is self-contained, but worth
  knowing if you ever depend on load order.
- **`ContentValidator` checks references, not solvability.** It can't tell
  you a case is unwinnable because two mutually-exclusive flags are both
  required somewhere, or that a topic is unreachable because nothing ever
  sets the flag it depends on — see Part F of the brief this pass was built
  against: that's explicitly out of scope ("do NOT attempt to build a full
  theorem prover"). It only catches dangling references and a couple of
  cheap structural smells (missing fallback entries).

## Verification

Four layers, in order of how much they actually prove:

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
#    DialogueManager / Investigation / SaveManager through the full demo
#    flow (talk, examine + repeat, evidence, present x2 (specific +
#    generic), flag/`all`/`any`/`visited_location`/`examined`/
#    `interaction_complete`-gated topics, "explain locked content", topic
#    "seen" state, move both directions, save, reset, load — including that
#    the new seen_interactions state round-trips — then instantiates
#    Main.tscn + TitleScreen.tscn and checks they (DebugPanel included) wire
#    up without error. Also asserts ContentValidator found zero errors AND
#    zero warnings in the real sandbox content. Prints "ALL TESTS PASSED"
#    and exits 0 on success.
godot --headless --path . -s res://scenes/test/smoke_test.gd
```

`ContentValidator` was additionally verified to actually *catch* problems
(not just pass clean content vacuously) by temporarily editing
`data/dialogue/test_effects.json` to reference an unknown character,
unknown evidence id, and unknown node id, re-running step 3, confirming all
three were reported with the correct message and a nonzero exit code, then
reverting.
