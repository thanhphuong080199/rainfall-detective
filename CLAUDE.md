# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Rainfall Detective is a Godot **4.7** 2D narrative detective game. The current state is a **Milestone 0 technical sandbox**: every character, location, dialogue line, and piece of evidence under `data/` is deliberately disposable placeholder content ("Character A", "Test Room", "Old Key") that exists only to prove the systems work — there is no story, no protagonist, and no real case yet. GDScript only; no plugins, no C#.

The governing philosophy: **this project builds systems, not story**. No script under `scripts/` should ever need to change just because content changes — real content should be addable purely as JSON under `data/`.

## Commands

Run the game:
```bash
godot --path .   # from repo root; or open project.godot in the editor and press F5
```
Main scene: `scenes/main/TitleScreen.tscn`.

Verify changes headlessly — do this (at least the content-validation step) before calling any change done:
```bash
# Full check: import, load every script/scene, boot the main scene, run both test scripts.
.claude/skills/godot-development/scripts/verify.sh \
  --script res://scenes/test/validate_content.gd \
  --script res://scenes/test/smoke_test.gd

# Fast path after only editing data/*.json:
.claude/skills/godot-development/scripts/verify.sh --skip-import --skip-load-all --skip-boot \
  --script res://scenes/test/validate_content.gd
```
Raw equivalents exist (`godot --headless --path . -s res://scenes/test/validate_content.gd` and `.../smoke_test.gd`) but **Godot's exit codes lie** — a `SCRIPT ERROR`, `push_error()`, or parse failure still exits 0, and a `-s` script that errors before calling `quit()` can hang indefinitely. `verify.sh` handles both (output-based pass/fail, per-step timeouts); prefer it over raw invocations. There is no separate lint/build step — import + boot + these two tests are the whole pipeline.

`validate_content.gd` is fast, content-only (checks broken references in `data/`, exits 1 on any error). `smoke_test.gd` is the authoritative end-to-end check: drives every autoload through the full demo flow (examine/talk/present/move, conditions, events, event chains, save/load) and asserts zero `ContentValidator` errors *and* warnings; it prints `ALL TESTS PASSED` and exits 0 on success.

## Architecture

`docs/architecture.md`, `docs/content-guide.md`, `docs/event-system.md`, `docs/case-system.md`, and `docs/localization.md` are the source of truth — read the relevant one before non-trivial work; what follows is only a map. Where they and generic conventions disagree, the docs win.

**The `.claude/skills/godot-development` project skill** (tracked in git, shared by everyone working on this repo) encodes this repo's Godot 4/GDScript conventions in full — typed GDScript, composition/signals/Resources, node lifecycle, scene ownership, when to add an autoload, avoiding NodePath coupling, resource loading, naming — plus the CLI verification workflow in detail. It auto-loads for any `.gd`/`.tscn`/`.tres`/`project.godot` work; read it and its `references/*.md` rather than re-deriving those rules.

### Autoloads (global systems, registered in `project.godot`)

| Autoload | Owns |
|---|---|
| `LocaleManager` (`scripts/core/locale_manager.gd`) | loads `localization/strings.csv` into `TranslationServer` and owns the active locale (`vi` default, `en` supported) plus its persistence. Registered first — no other autoload depends on it. |
| `GameState` (`scripts/core/game_state.gd`) | current location, visited locations, evidence, flags, freeform variables, and a generic `seen_interactions` set (topics/examine points seen, custom "this happened" markers). Story-agnostic. |
| `ContentDB` (`scripts/core/content_db.gd`) | loads every `*.json` under `data/` at startup and caches it; the **only** system that reads `data/` directly — everything else goes through its getters. Runs `ContentValidator` and prints its report on boot. |
| `DialogueManager` (`scripts/dialogue/dialogue_manager.gd`) | plays one dialogue tree at a time, node by node. Pure playback engine — no opinion on *why* a given tree was chosen. |
| `Investigation` (`scripts/investigation/investigation_manager.gd`) | decision layer for Examine/Talk/Present/Move: picks *which* dialogue tree plays for the current location + game state, then hands off to `DialogueManager`. |
| `EventManager` (`scripts/events/event_manager.gd`) | evaluates `data/events/*.json` against `GameState` and runs an event's effects the moment its conditions become true — reacting to state changes, not a player click. |
| `CaseManager` (`scripts/cases/case_manager.gd`) | orchestrates Case/Chapter progression (which chapter is current, when it completes and the next one activates, case completion). Holds no state of its own — reads/writes `GameState` only, and detects chapter completion by listening for a chapter's designated `completion_event` (an ordinary Event) to fire, not by re-evaluating conditions itself. |
| `SaveManager` (`scripts/save/save_manager.gd`) | reads/writes `user://save_game.json`; owns the save format/version. |

Plus stateless `class_name` static helpers (not autoloads): `ConditionEvaluator` (the condition mini-language), `EffectRunner` (the effect vocabulary), `ContentValidator` (cross-checks everything `ContentDB` loaded for broken references).

### Content is data, not code

Everything under `data/` (`characters/`, `evidence/`, `locations/`, `dialogue/`, `chapters/`, `cases/`, `events/`) is plain JSON, loaded once by `ContentDB`; runtime lookups return plain `Dictionary`, never typed wrapper classes. IDs are unique **within their own category** regardless of which file/subfolder they live in (subfolders are scanned automatically and exist purely for human organization); a duplicate id is a `ContentValidator` error, since load order across files isn't guaranteed. Adding real content should never require touching `scripts/` — `docs/content-guide.md` has the recipe for each content type.

### The condition/effect core, reused everywhere

- **Conditions** (`ConditionEvaluator.evaluate()`): a fixed mini-language — `flag`, `has_evidence`, `visited_location`, `examined`, `interaction_complete`, `all`/`any`/`not` — used identically for dialogue choices, talk topics, destinations, examine-point variants, NPC presence, and events. A condition object holds exactly **one** check; anything not on that whitelist (a typo'd key) evaluates to `false` (fails closed) and is a `ContentValidator` error, never a silent unlock.
- **Effects** (`EffectRunner.run()`): `set_flag`, `add_evidence`, `remove_evidence`, `mark_interaction_complete` — the one vocabulary for both a dialogue node/choice's `actions` and an event's `effects`.
- Deliberately **no** `unlock_topic`/`unlock_location` effect and **no** dedicated "character location" mechanism exist — both are just `set_flag` plus a `condition` on the gated thing (a character "moves" via two `npcs` entries in two different location files with complementary conditions). Read `docs/architecture.md`'s "Key Architecture Decisions" before proposing a parallel mechanism for either.
- Dialogue trees have exactly two node kinds (line; line-with-choices) — no silent "branch" node. Which tree plays at all is resolved one level up, by `Investigation`, via ordered `variants` lists in location JSON.
- Events (`data/events/*.json`) add zero new condition/effect vocabulary; they're `ConditionEvaluator` + `EffectRunner` evaluated automatically off `GameState` signals instead of a player click, with a bounded fixed-point loop for event chains. See `docs/event-system.md`.
- Cases (`data/cases/*.json`) may organize themselves into Chapters (`data/chapters/<case_id>/*.json`). A Chapter adds zero new condition/effect vocabulary either: its `completion_event` is the id of an ordinary Event, so `CaseManager` never evaluates a condition itself — it only reacts to `EventManager.event_triggered`. A case with no chapters (`case_00_sandbox`) is unaffected. See `docs/case-system.md`.
- Every `name`/`label`/`text`/`display_name`/`description` field in `data/` is a **translation key** resolved through Godot's `TranslationServer`/`tr()` (`vi` default, `en` supported), not literal text — see `docs/localization.md`. `ContentDB`/`Investigation`/`DialogueManager`/`EventManager`/`CaseManager` are all unaware this exists; only the UI layer calls `tr()`.

### UI wiring

`Main.gd` (`scripts/ui/main.gd`) is the **only** place `InvestigationView`, `DialogueBox`, `EvidenceInventory`, `GameMenu`, and `DebugPanel` (F1, debug builds only) are wired together — none of them reference each other directly, only autoload signals and scene-local signals `Main.gd` relays. Two load-bearing guards: `Investigation` refuses Examine/Talk/Present/Move while `DialogueManager.is_active`, and `InvestigationView` re-applies its interactive/disabled state after every re-render (freshly built buttons default to enabled). Both must hold for a click mid-dialogue to be a no-op.
