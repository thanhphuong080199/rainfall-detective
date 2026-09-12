extends Node
## Autoload: EventManager
##
## Reactive layer over GameState: evaluates a fixed list of content-authored
## "events" (data/events/*.json) and runs an event's effects the moment its
## conditions become true. See docs/event-system.md for the full design and
## docs/content-guide.md for how to author one.
##
## Deliberately reuses the exact building blocks investigation content
## already uses instead of inventing a second condition/effect language:
## ConditionEvaluator.evaluate() decides whether an event is ready, and
## EffectRunner.run() (the same executor DialogueManager uses for a node's
## "actions") runs its "effects". An event is really just a condition that,
## instead of gating one piece of UI, gates a burst of effects evaluated
## automatically instead of on a player click.
##
## No per-frame polling: evaluation is driven entirely by the same GameState
## signals investigation UI already listens to (flag_changed, evidence_added/
## removed, location_changed, interaction_seen) — see _request_evaluation().

signal event_triggered(event_id: String)

## Safety valve for event chains (one event's effects satisfying another
## event's conditions — see docs/event-system.md, "Event chains"):
## _evaluate_all() re-scans every event in a fixed-point loop until nothing
## new fires, capped here so a content bug that makes two events perpetually
## re-satisfy each other's conditions fails loudly (a push_warning) instead
## of hanging.
const MAX_EVALUATION_CYCLES := 20

## In-memory only, per event id: whether a "repeatable" event's conditions
## were satisfied the last time it was evaluated. This is how a repeatable
## event fires on a false->true transition instead of on every evaluation
## while it happens to stay true. Deliberately NOT persisted — see
## docs/event-system.md, "Known limitations", for exactly what that means.
var _repeatable_was_satisfied: Dictionary = {}

var _is_evaluating: bool = false
var _needs_reevaluation: bool = false


func _ready() -> void:
	GameState.flag_changed.connect(func(_flag_name, _value): _request_evaluation())
	GameState.evidence_added.connect(func(_evidence_id): _request_evaluation())
	GameState.evidence_removed.connect(func(_evidence_id): _request_evaluation())
	GameState.location_changed.connect(func(_location_id): _request_evaluation())
	GameState.interaction_seen.connect(func(_key): _request_evaluation())


func is_event_triggered(event_id: String) -> bool:
	return GameState.has_seen(_event_key(event_id))


## Debug-only: {"triggered": bool, "conditions_satisfied": bool,
## "conditions": Array[Dictionary]} — see DebugPanel's EVENTS section, the
## only caller.
func explain_event(event_id: String) -> Dictionary:
	var event: Dictionary = ContentDB.get_event(event_id)
	var conditions = event.get("conditions")
	return {
		"triggered": is_event_triggered(event_id),
		"conditions_satisfied": ConditionEvaluator.evaluate(conditions),
		"conditions": ConditionEvaluator.explain(conditions),
	}


## Developer-only: runs event_id's effects right now, through the exact same
## _fire() every automatic trigger uses — bypassing its conditions AND its
## trigger_policy (a "once" event forced this way still marks itself
## triggered, so a later automatic evaluation won't also fire it; a
## "repeatable" event forced this way doesn't touch the automatic
## false->true edge tracking, so it doesn't interfere with the next real
## transition either). Returns false for an unknown event id. See
## DebugPanel, the only caller.
func force_trigger(event_id: String) -> bool:
	var event: Dictionary = ContentDB.get_event(event_id)
	if event.is_empty():
		push_warning("EventManager.force_trigger: unknown event '%s'" % event_id)
		return false
	print("[EventManager] Manually triggered: %s" % event_id)
	_fire(event_id, event)
	return true


func _request_evaluation() -> void:
	if ContentDB.get_all_event_ids().is_empty():
		return
	if _is_evaluating:
		_needs_reevaluation = true
		return
	_evaluate_all()


## Fixed-point re-scan: runs every event whose conditions are newly
## satisfied, and if that changed anything, scans again — this is what lets
## one event's effects trigger another in the same pass (see
## docs/event-system.md, "Event chains") without recursing through
## _request_evaluation(): a re-entrant call made from inside an effect just
## sets _needs_reevaluation and returns, so effects that mutate GameState
## from inside this loop can't blow the call stack or double-run a pass
## that's already in progress. For this sandbox's event count, re-scanning
## the whole list is simpler and clearer than maintaining a dirty queue, and
## plenty fast — see docs/event-system.md, "Event evaluation".
func _evaluate_all() -> void:
	_is_evaluating = true
	print("[EventManager] Evaluating events after state change.")
	var cycles := 0
	var any_fired := true
	while any_fired and cycles < MAX_EVALUATION_CYCLES:
		any_fired = false
		cycles += 1
		for event_id in ContentDB.get_all_event_ids():
			if _try_trigger(event_id):
				any_fired = true
	if cycles >= MAX_EVALUATION_CYCLES:
		push_warning("[EventManager] stopped after %d evaluation cycles — check content for two events that keep re-satisfying each other's conditions" % MAX_EVALUATION_CYCLES)
	_is_evaluating = false
	if _needs_reevaluation:
		_needs_reevaluation = false
		_evaluate_all()


func _try_trigger(event_id: String) -> bool:
	var event: Dictionary = ContentDB.get_event(event_id)
	var satisfied: bool = ConditionEvaluator.evaluate(event.get("conditions"))
	var policy: String = event.get("trigger_policy", "once")

	if policy == "repeatable":
		var was_satisfied: bool = _repeatable_was_satisfied.get(event_id, false)
		var is_first_evaluation: bool = not _repeatable_was_satisfied.has(event_id)
		_repeatable_was_satisfied[event_id] = satisfied
		# Fires only on a false->true transition: never on the evaluation
		# that first observes an event (which would misfire the instant a
		# save loads into a state where it's already satisfied — see
		# docs/event-system.md, "Known limitations") and never again while
		# it stays satisfied.
		if not satisfied or was_satisfied or is_first_evaluation:
			return false
	else:
		if policy != "once":
			push_warning("EventManager: event '%s' has unknown trigger_policy '%s' — treating it as 'once'" % [event_id, policy])
		if not satisfied or is_event_triggered(event_id):
			return false

	_fire(event_id, event)
	return true


func _fire(event_id: String, event: Dictionary) -> void:
	GameState.mark_seen(_event_key(event_id))
	var effects: Array = event.get("effects", [])
	print("[EventManager] Triggered: %s" % event_id)
	if not effects.is_empty():
		print("[EventManager] Effects:")
		for effect in effects:
			print("[EventManager]   - %s" % EffectRunner.describe(effect))
	EffectRunner.run(effects)
	event_triggered.emit(event_id)


func _event_key(event_id: String) -> String:
	return "event:%s" % event_id
