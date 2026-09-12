class_name EffectRunner
extends RefCounted
## Stateless helper (like ConditionEvaluator) that executes this project's
## one, shared effect vocabulary: a small set of named ways to mutate
## GameState from a list of {"type": ..., ...} dictionaries.
##
## Dialogue node/choice "actions" and event "effects" (see
## docs/event-system.md) are the exact same shape, run through the exact
## same run() below — there is deliberately only one effect system in this
## project, not a dialogue one and a separate event one. Originally this was
## DialogueManager._run_actions(); it was pulled out here, unchanged in
## behavior, when the Milestone 1.5 event system needed to run the identical
## logic outside of dialogue playback. See docs/architecture.md, "Key
## Architecture Decisions", for why.
##
## To add a new effect type: add one more `match` case below AND to
## ContentValidator._validate_effects()'s structural check — nothing else
## needs to change, and both dialogue actions and event effects get it for
## free.

const KNOWN_TYPES := ["set_flag", "add_evidence", "remove_evidence", "mark_interaction_complete"]


static func run(effects) -> void:
	if typeof(effects) != TYPE_ARRAY:
		return
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		match effect.get("type", ""):
			"set_flag":
				GameState.set_flag(effect.get("flag", ""), effect.get("value", true))
			"add_evidence":
				GameState.add_evidence(effect.get("evidence_id", ""))
			"remove_evidence":
				GameState.remove_evidence(effect.get("evidence_id", ""))
			"mark_interaction_complete":
				GameState.mark_seen("custom:%s" % effect.get("id", ""))
			_:
				push_warning("EffectRunner: unknown effect type '%s'" % [effect.get("type", "")])


## One-line human-readable description of a single effect, for developer
## logging only (EventManager's "Effects:" lines) — never used to decide
## execution. Keep in sync with run() above.
static func describe(effect) -> String:
	if typeof(effect) != TYPE_DICTIONARY:
		return "(malformed effect: %s)" % [effect]
	match effect.get("type", ""):
		"set_flag":
			return "set %s = %s" % [effect.get("flag", ""), effect.get("value", true)]
		"add_evidence":
			return "add evidence %s" % effect.get("evidence_id", "")
		"remove_evidence":
			return "remove evidence %s" % effect.get("evidence_id", "")
		"mark_interaction_complete":
			return "mark interaction complete: %s" % effect.get("id", "")
		_:
			return "(unknown effect type: %s)" % effect.get("type", "")
