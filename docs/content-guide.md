# Content Guide

How to add game content without touching any script in `scripts/`. Every
recipe below is "add a JSON file" or "add a JSON object to an existing file."
Restart the game (or re-run `scenes/test/smoke_test.gd`) to pick up changes —
`ContentDB` loads everything once at startup.

Read `docs/architecture.md` first if you haven't — it explains *why* the
schema looks like this. This doc is the *how*.

General rules that apply everywhere below:

- Every id (`character_a`, `test_key`, `examine_desk_before`, ...) must be
  unique **within its own category** (characters / evidence / locations /
  dialogue trees / cases are separate namespaces). If you duplicate one, the
  **later**-loaded entry wins — and load order isn't guaranteed, so which one
  that is isn't either. The content validator reports duplicates as errors
  and names both files, so just run it.
- You can put content in **subfolders** (`data/dialogue/case_01/*.json`) and
  it will be picked up. Folder layout is for your benefit only; ids stay in
  one flat namespace per category regardless of where the file lives.
- Anywhere you see `"condition"`, it's optional — omit it and that thing is
  always available. See "Conditions reference" below.
- Dialogue ids, evidence ids, character ids, and location ids are all
  referenced from other JSON by plain string — a typo won't necessarily be
  caught at the exact spot you made it. Run the **content validator** after
  editing anything under `data/` — see "Validating content" below — it
  catches almost all of these before you ever have to click around to find
  them.

## 1. Add a character (and its expressions)

Create `data/characters/<id>.json`:

```json
{
  "id": "character_c",
  "name": "Character C",
  "expressions": {
    "normal": "#6B5B95",
    "happy": "#88B04B",
    "angry": "#C94C4C",
    "surprised": "#F7CAC9"
  }
}
```

Each key under `expressions` is an expression name (used as the `expression`
field in dialogue nodes); the value is a placeholder color shown as that
character's portrait. `"normal"` is used as the fallback if a dialogue node
requests an expression the character doesn't have, so always include it.
Add or rename expressions freely — nothing else needs to know about them in
advance.

**To add just a new expression to an existing character**, add one key to
its `expressions` object. That's the whole change.

## 2. Add a location

Create `data/locations/<id>.json`:

```json
{
  "id": "test_attic",
  "name": "Test Attic",
  "background_color": "#4A3F5E",
  "npcs": [],
  "examine_points": [],
  "destinations": [
    { "location_id": "test_hallway", "label": "Back to the Hallway" }
  ]
}
```

`npcs`, `examine_points`, and `destinations` can start empty — see the
sections below for what goes in each. To make this location reachable, add a
matching `destinations` entry to *another* location that points to it (e.g.
add `{ "location_id": "test_attic", "label": "Go to the Attic" }` to
`test_hallway.json`'s `destinations`). Movement is one-directional per
entry — a round trip needs an entry on both sides, as `test_room.json`/
`test_hallway.json` already do.

## 3. Add a dialogue tree

Dialogue trees live in `data/dialogue/*.json`. Each file holds an **array**
of trees — group them however makes sense (by character, by location, by
whatever); `ContentDB` merges every file in the folder into one id→tree map.

```json
{
  "id": "character_a_about_window",
  "start": "n1",
  "nodes": {
    "n1": {
      "speaker": "character_a",
      "expression": "normal",
      "text": "The window? I never open it.",
      "next": null
    }
  }
}
```

- `speaker`: a character id, or `""` for narration (no portrait/name shown —
  used for examine-point flavor text, e.g. `examine_desk_before`).
- `expression`: one of that character's expression keys (ignored if
  `speaker` is `""`).
- `next`: another node id in this same tree's `nodes`, or `null`/omitted to
  end the dialogue.
- `actions` (optional list, runs when the node is entered): see below.

**Branching with choices** — replace `next` with `choices`:

```json
"n1": {
  "speaker": "character_a",
  "expression": "normal",
  "text": "Can I help you?",
  "choices": [
    { "text": "Ask about the desk.", "condition": { "flag": "desk_examined", "equals": false }, "next": "n2" },
    { "text": "Nothing, thanks.", "next": null }
  ]
}
```

Each choice can have its own `condition` (hidden entirely if false — see
`character_a_greeting` in `data/dialogue/character_a.json` for the full
working example), its own `actions`, and its own `next`.

**Actions** (used on a node, or on a choice — same shape either way; these
are this project's **effect system**):

```json
"actions": [
  { "type": "set_flag", "flag": "met_character_c", "value": true },
  { "type": "add_evidence", "evidence_id": "test_key" },
  { "type": "remove_evidence", "evidence_id": "test_key" },
  { "type": "mark_interaction_complete", "id": "met_character_c" }
]
```

- `set_flag` — sets `flag` to `value` (`true`/`false`). This is also the
  general-purpose "unlock" mechanism: there's no separate `unlock_topic`/
  `unlock_location` action — set a flag here, and reference it in a
  `condition` on whatever topic/destination/choice should become available
  (see `character_a_present_key` unlocking `about_key` and the
  `test_hallway` destination in `data/dialogue/character_a.json` /
  `data/locations/test_room.json`).
- `add_evidence` — adds `evidence_id` to the player's inventory (no-op if
  already held).
- `remove_evidence` — removes `evidence_id` from the inventory (no-op if not
  held). For evidence that gets consumed or replaced by something else.
- `mark_interaction_complete` — records that a one-off milestone with this
  `id` has happened, for later use with an `{"interaction_complete": "id"}`
  condition (see "Conditions reference" below). Use this for a "this
  happened" marker that isn't really an on/off flag and isn't tied to one
  specific topic/examine point — those two get simpler tracking
  automatically, for free (see "Talk topics" and "Examine points" below).

To add a new action type, add one more `match` case in
`DialogueManager._run_actions()` (`scripts/dialogue/dialogue_manager.gd`) —
nothing else needs to change. `ContentValidator` will flag any action with
an unrecognized `type` as a warning, and `add_evidence`/`remove_evidence`
referencing an unknown evidence id as an error.

**There's no "branch" node for silently jumping based on state with no line
shown.** If you want different dialogue depending on game state without the
player picking anything (like "the desk looks different once you've already
searched it"), that's a **variant list** on the examine point or NPC entry
in the *location* JSON, not something inside the dialogue tree — see
sections 5 and 7 below.

## 4. Add an evidence item

Create `data/evidence/<id>.json`:

```json
{
  "id": "test_ledger",
  "name": "Torn Ledger",
  "icon_color": "#7A6F5D",
  "short_description": "A page torn from a ledger.",
  "detailed_description": "A single page, torn out. The handwriting is cramped and hard to read, but a few numbers stand out."
}
```

Both descriptions are shown in the inventory's detail panel:
`short_description` as a one-line subtitle under the name,
`detailed_description` as the body below it. Write the short one as a glance
("A page torn from a ledger.") and the long one as what the player learns by
actually studying it.

An evidence item only shows up in the inventory once the player has actually
received it — see the next section for how.

## 5. Add an examine interaction

Add an entry to a location's `examine_points` array
(`data/locations/<id>.json`):

```json
"examine_points": [
  {
    "id": "trapdoor",
    "label": "Examine the Trapdoor",
    "variants": [
      { "condition": { "has_evidence": "test_key" }, "dialogue_id": "examine_trapdoor_unlocked" },
      { "dialogue_id": "examine_trapdoor_locked" }
    ]
  }
]
```

`variants` is checked top-to-bottom; the first entry whose `condition`
passes (or that has no `condition` at all) is what plays. Put your
"default"/fallback variant last, with no `condition` — exactly like
`examine_desk_before`/`examine_desk_after` in `test_room.json`. A single-variant
examine point (no before/after difference) just needs one entry with no
`condition`.

Whichever `dialogue_id` is chosen is played exactly like any other dialogue
tree — that's where you'd `add_evidence` or `set_flag` (see section 3).

**A "first look vs. later look" examine point that grants no evidence**
doesn't need a flag at all — every examine point is automatically tracked as
"examined" the moment it's played, so `{"examined": "point_id"}` just works:

```json
"examine_points": [
  {
    "id": "mirror",
    "label": "Examine the Mirror",
    "variants": [
      { "condition": { "examined": "mirror" }, "dialogue_id": "examine_mirror_after" },
      { "dialogue_id": "examine_mirror_before" }
    ]
  }
]
```

See `mirror` in `data/locations/test_hallway.json` for the full working
example. `{"examined": "..."}` always means "this location's own examine
point" — see "Conditions reference" below.

## 6. Add a talk topic

Add an entry to an NPC's `topics` array, inside that location's `npcs` list:

```json
"npcs": [
  {
    "id": "character_a",
    "topics": [
      { "id": "about_window", "label": "Ask about the window", "dialogue_id": "character_a_about_window", "condition": { "flag": "met_character_c" } }
    ],
    "present_responses": []
  }
]
```

Omit `condition` for a topic that's always available (like `greeting` in the
existing content). A topic with a false condition simply doesn't appear in
the Talk list — no separate "locked" state to manage.

**"Completed/read" state is automatic** — you don't write anything for this.
The first time the player picks a topic, `Investigation` marks it seen, and
`InvestigationView` appends `(read)` to its label next time it's shown. This
is purely informational and isn't exposed as a `condition` shape on its own
(it's a UI nicety, not a gameplay gate). **If you actually want to gate
other content on "this topic was talked about"**, add a
`mark_interaction_complete` action to that topic's own dialogue tree with an
id you choose, then reference that id with `{"interaction_complete": "..."}`
elsewhere — see `character_b_greeting`'s `met_character_b` action, consumed
by `character_a`'s `about_character_b` topic, for the working example.

## 7. Add an evidence-presentation response

Add an entry to an NPC's `present_responses` array:

```json
"present_responses": [
  { "evidence_id": "test_ledger", "dialogue_id": "character_a_present_ledger" },
  { "dialogue_id": "character_a_present_generic" }
]
```

This is matched differently from `variants` above: the first entry whose
`evidence_id` matches what the player is holding up wins; if nothing
matches, the first entry with **no** `evidence_id` field at all is used as
the generic fallback. **Always include a generic fallback entry** (as both
`character_a` and `character_b` do) — if you don't, presenting unrelated
evidence to that NPC does nothing and logs a warning instead of showing any
response.

## 8. Add a case

A case is what "New Game" resets to. Create `data/cases/<id>.json`:

```json
{
  "id": "case_01_example",
  "title": "Example Case",
  "start_location": "test_room",
  "initial_flags": {
    "hallway_unlocked": false
  }
}
```

List every flag the case's content uses in `initial_flags`, even set to
`false` — `GameState.get_flag()` would default to `false` anyway if it were
missing, but listing them here makes the file self-documenting about what
flags exist. `SaveManager.new_game("case_01_example")` (or edit the default
argument in `scripts/save/save_manager.gd` / the call in
`scripts/ui/title_screen.gd`) switches which case "New Game" boots into.

## Conditions reference

Used identically for choice `condition`, topic `condition`, destination
`condition`, and variant `condition`:

| Shape | Meaning |
|---|---|
| *(omitted / `null`)* | always available |
| `{ "flag": "some_flag" }` | true once `set_flag("some_flag", true)` has run |
| `{ "flag": "some_flag", "equals": false }` | true until that flag is set |
| `{ "has_evidence": "some_id" }` | true once that evidence has been obtained |
| `{ "visited_location": "some_location_id" }` | true once that location has been entered at least once |
| `{ "examined": "some_point_id" }` | true once **this location's own** examine point with that id has been examined (see section 5) |
| `{ "interaction_complete": "some_id" }` | true once a `mark_interaction_complete` action with that id has run (see section 3) |
| `{ "all": [ <condition>, <condition>, ... ] }` | true once every sub-condition is true |
| `{ "any": [ <condition>, <condition>, ... ] }` | true once at least one sub-condition is true |
| `{ "not": <condition> }` | true when the sub-condition is false |

This is a fixed set of named checks, not a general expression language —
there's no way to write arbitrary boolean logic beyond nesting `all`/`any`/
`not`. That's intentional; see `docs/architecture.md`'s "Key Architecture
Decisions" if you're wondering why there's no `unlock_topic`/`unlock_location`
action to go with these instead of just `set_flag` + a `flag` condition.

**Any key not in that table means the condition is `false`.** So a typo like
`{ "has_evidnce": "test_key" }` locks the thing you attached it to, rather
than quietly leaving it unlocked from the start of the case. The validator
catches this for you (`uses unknown key "..."`), which is the real reason to
run it after editing conditions — this is by far the easiest mistake to make
in this format and the hardest to spot by playing.

The only extra key allowed is `"equals"`, and only alongside `"flag"`.

**One condition object = one check.** This does *not* mean "and":

```json
{ "flag": "door_open", "has_evidence": "old_key" }
```

Only the `flag` half is ever evaluated — the other is silently dropped. The
validator rejects this and tells you which one would have won. Write it as:

```json
{ "all": [ { "flag": "door_open" }, { "has_evidence": "old_key" } ] }
```

Working examples in the sandbox content:
- `character_b.json`'s `clue` topic — `all` (requires two different
  evidence items to both be held).
- `test_room.json`'s `about_evidence` topic — `any` (requires just one of
  two evidence items).
- `test_room.json`'s `about_hallway_trip` topic — `visited_location`.
- `test_hallway.json`'s `mirror` examine point — `examined`.
- `test_room.json`'s `about_character_b` topic — `interaction_complete`.

## Validating content

After adding or editing anything under `data/`, run:

```bash
godot --headless --path . -s res://scenes/test/validate_content.gd
```

It exits `1` (and prints one `[ContentValidator] ERROR: ...` line per
problem). Errors it catches:

- Anything referencing an id that doesn't exist — a typo'd dialogue /
  evidence / character / location id, a dialogue `next` pointing at a node
  that isn't there, a `has_evidence` / `visited_location` / `examined`
  condition naming something that doesn't exist, an unknown `expression` for
  a speaker, and so on.
- A condition using an **unknown key** (see "Conditions reference" above), or
  an `all` / `any` that isn't a non-empty array.
- A **duplicate id** — either two content files declaring the same id, or the
  same id repeated inside one location's `npcs`, `topics`, `examine_points`
  or `destinations` list. (Lookups take the first match, so the second copy
  would simply never be reachable.) An entry with no id at all is reported
  the same way.
- A `set_flag` action `value`, or a case `initial_flags` value, that isn't
  `true` or `false`.
- A condition object holding more than one check (see "Conditions reference"
  above) — only one of them would ever be evaluated.

And warnings (which do **not** fail the run) for easy-to-forget structural
gaps: a `present_responses` list with no generic fallback entry, an NPC with
no `present_responses` at all (presenting anything to them does nothing
whatsoever — no dialogue, no feedback), an `examine_points` variant list with
no unconditional fallback entry, a character missing its `normal`
expression, or a dialogue node nothing can reach (usually a typo in another
node's `next` — the dialogue still plays, it just skips the node you wrote). This same check also runs automatically every time
the game boots (look for `[ContentValidator]` in the console output) — the
standalone script above just gives it a scriptable exit code without
booting the full game. See `docs/architecture.md`, "Content validation",
for exactly what it checks and why it's built the way it is.

It is **not** a substitute for actually playing through new content — it
only catches broken references, not "this topic is unreachable because
nothing ever sets the flag it needs" or similar design-level gaps.

## Developer tools

Press **F1** in a running debug build to open a developer overlay showing
the current location, evidence held, every flag, visited locations, and —
per NPC topic and per destination — whether it's available or locked, with
the specific missing condition(s) listed if it's locked. From there you can
toggle any flag, add/remove any evidence id, jump straight to any location
id (skipping that destination's `condition` — useful for reaching content
deep in a case without replaying everything to unlock it), or reset the
sandbox back to the case's starting state. **Esc** closes it. When a topic is
locked behind an `any`, the panel shows the alternatives as one grouped line
(`ANY of: (... OR ...)`) rather than listing each as separately missing — you
only need one of them. It's gone entirely in an
exported release build (`OS.is_debug_build()` is false there) — nothing to
remember to strip out later. See `docs/architecture.md`, "Developer tools".
