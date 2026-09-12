# Localization

How this project shows text in more than one language, why it's built the
way it is, and how to add or edit translated text. Read `docs/architecture.md`
first — this doc assumes you know the autoload layer and the "content is
data" philosophy already.

**Supported locales: Vietnamese (`vi`, default) and English (`en`).**
Every player-facing string — content-driven (character names, dialogue,
evidence, location/topic/examine/destination labels, case/chapter display
names) and static UI chrome (menu/button labels, status messages) — goes
through this system. There is exactly one mechanism for both kinds of text,
not a content-side one and a UI-side one.

## What problem this solves

Every piece of player-facing text in this project used to be a literal
string baked directly into `data/*.json` or a `.tscn`/`.gd` file, in
English only. Supporting a second language means every one of those strings
needs a Vietnamese counterpart, and switching between them needs to happen
at runtime, from a language the player chooses — not something a rebuild or
a different exported `.pck` decides.

## Architecture: Godot's own TranslationServer, not a parallel system

This project uses Godot's real, built-in localization primitives —
`Translation` resources, `TranslationServer`, and `tr()` — exactly as the
engine intends, not a custom "translate this dictionary" helper living
beside them. Content JSON fields that used to hold literal text now hold a
**translation key** (a stable, author-chosen id like `UI_SAVE` or
`CHAR_CHARACTER_A_NAME`); the actual English/Vietnamese strings live in one
place, `localization/strings.csv`, and are resolved through `tr(key)` (or,
from a `static func` with no `self`, `TranslationServer.translate(key)` —
see "Where a key is resolved" below) wherever text is actually displayed.

```
data/*.json text field
        │  now holds a translation key, e.g. "UI_SAVE"
        ▼
localization/strings.csv
        │  LocaleManager loads this into two Translation objects at boot
        ▼
TranslationServer  (locale = "vi" by default, "en" the fallback)
        │
tr(key)  /  TranslationServer.translate(key)
        │  called at the one point each key is actually displayed
        ▼
   the Label/Button text the player sees
```

## Why the CSV is loaded at runtime, not through the editor's import pipeline

Godot's normal workflow for a translation CSV is to set its import type to
"Translation" in the editor, which the editor represents as a `.csv.import`
sidecar it generates for you, producing `.translation` resource files
Godot's asset pipeline then loads automatically via
`[internationalization] locale/translations` in `project.godot`.

```
DECISION: localization/strings.csv is parsed at runtime by LocaleManager
(FileAccess + get_csv_line(), registering Translation objects directly with
TranslationServer.add_translation()), not imported through Godot's asset
pipeline as a "csv_translation" resource.

WHY IT IS NEEDED NOW: This project needs its translated strings loaded and
the correct locale active before any scene renders a single character of
text, and needs that to work identically whether the project was ever
opened in the Godot editor or not (this whole codebase is built and
verified headlessly).

ALTERNATIVES: Hand-write a `.csv.import` sidecar with importer=
"csv_translation" to make Godot's import step generate .translation
resources automatically, the way the editor would if someone set the CSV's
"Import As" dropdown to "Translation".

WHY THIS OPTION WAS CHOSEN: A hand-crafted .import sidecar for a
multi-output importer (one .translation file per locale column) has no
documented, stable text format to copy without actually running the
editor's Import dock once and inspecting what it writes — this project has
had no editor session to produce or verify that against. The resulting
.translation files are also not text — they're compiled resources, not
something a human or an AI agent can diff or hand-edit to catch a mistake.
Loading the CSV directly at runtime is the exact same "plain text, parsed
by our own code, human/AI-editable, fails loudly" reasoning
docs/architecture.md's "Key Architecture Decisions" already gives for
choosing hand-parsed JSON over `.tres` for all narrative content — applied
here to translations instead of narrative content.

IMPACT: localization/strings.csv is committed as plain text and diffs
cleanly like everything else under data/. No `[internationalization]
locale/translations` entry exists in project.godot; LocaleManager is solely
responsible for getting TranslationServer populated, and it is registered
FIRST in the autoload list (see "LocaleManager" below) so that happens
before ContentDB/ContentValidator or any scene need it. Revisitable later:
if this project ever gains a real editor-authoring workflow, the CSV is
already shaped exactly as Godot's own importer expects (a "keys" column
plus one column per locale), so switching to the import-pipeline path then
would need no reshaping of the data itself.
```

## `localization/strings.csv`

One header row (`keys,en,vi`) plus one row per translation key. Every field
is quoted (standard CSV, handles embedded commas/quotes — Godot's
`FileAccess.get_csv_line()` parses this correctly, the same call
`LocaleManager._load_strings()` uses to read it):

```csv
"keys","en","vi"
"UI_SAVE","Save","Lưu"
"CHAR_CHARACTER_A_NAME","Character A","Nhân Vật A"
```

Key naming convention (not structurally enforced, the same "convention, not
infrastructure" stance `docs/case-system.md` takes for case/chapter id
namespacing):

| Prefix | For |
|---|---|
| `UI_` | Static UI chrome — button/menu labels, section headers, status messages, hint text. Named after what the string *is* (`UI_SAVE`, `UI_BACK`), not where it appears. |
| `CHAR_<id>_NAME` | A character's `name` field. |
| `EVID_<id>_NAME` / `_SHORT` / `_DETAIL` | An evidence item's `name` / `short_description` / `detailed_description`. |
| `LOC_<id>_NAME` | A location's `name` field. |
| `LOC_<location_id>_TOPIC_<npc_id>_<topic_id>_LABEL` | A talk topic's `label`. |
| `LOC_<location_id>_EXAMINE_<point_id>_LABEL` | An examine point's `label`. |
| `LOC_<location_id>_DEST_<target_location_id>_LABEL` | A destination's `label`. |
| `DLG_<dialogue_id>_<node_id>_TEXT` | A dialogue node's `text`. |
| `DLG_<dialogue_id>_<node_id>_CHOICE<n>_TEXT` | Choice `n`'s `text` on that node (1-indexed). |
| `CASE_<id>_NAME` / `_DESC` | A case's `display_name` (or legacy `title`) / `description`. |
| `CHAPTER_<id>_NAME` | A chapter's `display_name`. |

Every key referenced from `data/` must have both an `en` and a `vi` entry —
`ContentValidator` enforces this (see "Content validation" below).

## `LocaleManager`

New autoload (`scripts/core/locale_manager.gd`), registered **first** in
`project.godot`'s `[autoload]` list — it has no dependency on any other
autoload, and everything else may need text translated the moment it starts
rendering. Owns exactly two things:

- **Loading**: parses `localization/strings.csv` into two `Translation`
  resources (one per locale column) and registers both with
  `TranslationServer.add_translation()`.
- **The active locale**: `set_locale(locale)` (rejects anything not in
  `SUPPORTED_LOCALES`, the same "fail closed on bad input" stance
  `ConditionEvaluator` takes for an unknown condition key), `get_locale()`,
  and a `locale_changed(locale)` signal. The chosen locale is persisted to
  `user://settings.cfg` via `ConfigFile` — a **player preference**, kept
  separate from `user://save_game.json` (case/game state) exactly the way
  `docs/architecture.md`'s Godot-conventions section already distinguishes
  "settings" from "save games." `DEFAULT_LOCALE = "vi"`: a fresh install
  with no settings file yet boots in Vietnamese, per this project's
  requirement.

`LocaleManager` has no opinion on *where* a key is used — it doesn't know
about `ContentDB`, `DialogueManager`, or any UI scene. Every consumer calls
the engine's own `tr()`/`TranslationServer.translate()` directly.

## Where a key is resolved: explicit `tr()`, not Control auto-translation

Godot Controls have an `auto_translate_mode` that, in principle, should
re-translate a node's `text` automatically when `TranslationServer`'s locale
changes. This project does **not** rely on that. A headless probe (`Button`
with `text` assigned a registered key, then `TranslationServer.set_locale()`
called and a frame awaited) showed the `text` **property**, when read back
from script, still holds the original, untranslated string — there's no way
to headlessly confirm whether the actual on-screen *rendering* differs, and
this project has no screenshot tooling (see `docs/architecture.md`'s "Known
limitations"). Shipping unverified behavior for the primary UI text of every
screen was not an acceptable trade for a few dozen `tr()` calls.

So: **every place text is actually assigned to a Label/Button, an explicit
`tr(key)` call resolves it**, and any screen that can plausibly still be
visible while the player changes language (currently only `GameMenu` itself
and the `InvestigationView` dimmed behind it — see "Which screens react to
`locale_changed`" below) re-runs its own render/label-setting function when
`LocaleManager.locale_changed` fires. This is fully headlessly verifiable —
`scenes/test/smoke_test.gd`'s `_test_localization()` asserts the *exact*
displayed string on an already-instantiated `InvestigationView` both before
and after a live locale switch, not just that a key exists.

A `class_name` `static func` with no `self` (`ContentValidator`) can't call
`tr()` (an `Object` instance method) — it uses
`TranslationServer.translate(key)` instead, the same underlying lookup.

### Which screens react to `locale_changed`

| Screen | Reacts to `locale_changed`? | Why |
|---|---|---|
| `InvestigationView` | Yes — re-runs `_render_current()` | Stays visible (dimmed) behind `GameMenu`, where the language toggle lives. |
| `GameMenu` | Yes — re-runs its own static-label setup | Owns the toggle; must reflect the new language immediately, including which button now shows as the current selection. |
| `DebugPanel` | Yes — re-runs `_refresh_if_visible()` | Cheap, keeps the dev-only content-name displays (e.g. `LOCATION`, `EVIDENCE`) current; consistent with its other refresh triggers. |
| `DialogueBox`, `EvidenceInventory` | No | Both can only be open while `GameMenu` cannot (a running dialogue disables the Menu button; `EvidenceInventory`'s full-rect `STOP` mouse filter blocks the click that would open it) — see `Investigation._is_busy()` / `Main.gd`'s dialogue-disables-`InvestigationView` wiring in `docs/architecture.md`. They always render fresh text for whatever locale is active the next time they open. |
| `TitleScreen` | No | Never visible while the toggle (in `GameMenu`, reachable only from inside a running game) could fire — a fresh `_ready()` after "Quit to Title" already picks up the current locale. |

## Content validation

`ContentValidator._validate_translatable(key, context, errors)` (called
from character/evidence/location/topic/examine/destination/dialogue-node/
dialogue-choice/case/chapter validation, wherever that content type has a
field documented above as translatable) checks the key **directly against
each locale's own `Translation` object** —
`TranslationServer.get_translation_object(locale).get_message(key)` — never
through `tr()`/`TranslationServer.translate()`, which would silently
succeed via the configured fallback locale (`locale/fallback="en"` in
`project.godot`) and hide a missing Vietnamese line behind whatever English
happens to say. A key missing from either locale is reported as an error,
the same severity as any other broken reference — the default locale is
Vietnamese, so a missing `vi` message is not a cosmetic gap, it's content
that silently ships in the wrong language.

## Adding a new translated string

1. Pick a key following the convention above (or a new `UI_` one for
   static chrome).
2. Add a row to `localization/strings.csv` with both an `en` and a `vi`
   value.
3. Use that key as the field's value in `data/*.json` (content) — or call
   `tr("YOUR_KEY")` directly at the one point in a `.gd` script where a
   static string is displayed.
4. Run content validation — a key missing from either locale is now a
   validator error, not a silent gap.

## Known limitations

- **No locale beyond `vi`/`en` today.** `LocaleManager.SUPPORTED_LOCALES`
  is a two-entry constant; adding a third locale means adding a CSV column,
  a `SUPPORTED_LOCALES` entry, and a corresponding `GameMenu` toggle
  button — not a redesign, but not automatic either (deliberately not
  over-built for a need that doesn't exist yet).
- **No visual confirmation that on-screen rendering matches `tr()`'s
  return value.** Every check in `_test_localization()` reads a Control's
  `.text` property back from script, which is what this project's own
  probe proved reflects an explicit `tr()`/direct assignment correctly —
  but, as with every other headless UI check in this codebase (see
  `docs/architecture.md`'s "UI click-routing is verified by
  value-inspection, not a simulated click"), nothing here proves pixels on
  screen actually show the right glyphs (font coverage for Vietnamese
  diacritics, text overflow in a narrow button, etc.). A human should run
  the game (`godot --path .`) and eyeball both languages, especially any
  screen with fixed-width buttons.
- **`user://settings.cfg` is a single unversioned file.** No migration
  path exists if its shape ever changes; acceptable at this project's
  current scale (one key: `localization/locale`) the same way
  `SaveManager`'s single save slot is (see `docs/architecture.md`'s "Known
  limitations").
