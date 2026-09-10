extends Node
## Autoload: Investigation
##
## Coordinates the four investigation verbs (Examine / Talk / Present / Move)
## for whatever the current location is. This is the "decision layer" that
## figures out WHICH dialogue tree should play, given game state; the actual
## playback is always handed off to DialogueManager. UI scenes call the
## methods here and otherwise only listen to DialogueManager/GameState
## signals — they never touch ContentDB or condition logic directly.
##
## Also auto-tracks "seen" state for topics and examine points in
## GameState.seen_interactions (keys "topic:<npc_id>:<topic_id>" and
## "examine:<location_id>:<point_id>") every time one is played. This is
## unconditional and automatic — content never has to opt in with an action —
## so it stays true for every future case without extra authoring, the same
## way GameState.go_to_location() always records visited_locations. Two
## things read it: the {"examined": "..."} condition (for repeat-examine
## variants), and is_topic_seen() below (for a "(read)" indicator in the UI).

func get_current_location() -> Dictionary:
	return ContentDB.get_location(GameState.current_location)


func get_examine_points() -> Array:
	return get_current_location().get("examine_points", [])


func get_npcs() -> Array:
	return get_current_location().get("npcs", [])


func get_npc(npc_id: String) -> Dictionary:
	for npc in get_npcs():
		if npc.get("id", "") == npc_id:
			return npc
	return {}


## Every topic this NPC defines, unfiltered by condition — used by debug
## tooling to show locked topics alongside available ones. Gameplay code
## should use get_topics() instead.
func get_all_topics(npc_id: String) -> Array:
	return get_npc(npc_id).get("topics", [])


## Topics currently offerable for this NPC (already filtered by condition).
func get_topics(npc_id: String) -> Array:
	var topics: Array = []
	for topic in get_all_topics(npc_id):
		if ConditionEvaluator.evaluate(topic.get("condition")):
			topics.append(topic)
	return topics


## True once this NPC's topic has been talked about at least once. Purely
## informational (e.g. a "(read)" tag in the UI) — never gates availability.
func is_topic_seen(npc_id: String, topic_id: String) -> bool:
	return GameState.has_seen(_topic_seen_key(npc_id, topic_id))


## Every destination this location defines, unfiltered by condition — used
## by debug tooling to show locked destinations alongside available ones.
## Gameplay code should use get_available_destinations() instead.
func get_all_destinations() -> Array:
	return get_current_location().get("destinations", [])


## Destinations currently reachable from here (already filtered by condition).
func get_available_destinations() -> Array:
	var destinations: Array = []
	for destination in get_all_destinations():
		if ConditionEvaluator.evaluate(destination.get("condition")):
			destinations.append(destination)
	return destinations


## True once this location's examine point has been examined at least once.
## Backs the {"examined": "..."} condition and is available for UI/debug use
## the same way is_topic_seen() is.
func is_examine_point_seen(point_id: String) -> bool:
	return GameState.has_seen(_examine_seen_key(GameState.current_location, point_id))


## True when the player is allowed to start a new interaction. Every verb
## below refuses while a dialogue is playing: the UI already blocks the
## clicks, but a verb that ran anyway would mutate game state (mark a topic
## read, change location) behind a dialogue the player is still reading.
func _is_busy(verb: String) -> bool:
	if DialogueManager.is_active:
		push_warning("Investigation.%s: ignored while a dialogue is playing" % verb)
		return true
	return false


func examine(point_id: String) -> void:
	if _is_busy("examine"):
		return
	for point in get_examine_points():
		if point.get("id", "") == point_id:
			var variant: Dictionary = ConditionEvaluator.resolve_variants(point.get("variants", []))
			if variant.is_empty():
				push_warning("Investigation.examine: no matching variant for '%s'" % point_id)
				return
			# Only record the examine as having happened if its dialogue
			# really started — otherwise the point would count as examined
			# (and its evidence-granting "before" variant would be skipped
			# forever) without the player ever having seen it.
			if not DialogueManager.start(variant.get("dialogue_id", "")):
				return
			GameState.mark_seen(_examine_seen_key(GameState.current_location, point_id))
			return
	push_error("Investigation.examine: unknown examine point '%s' in '%s'" % [point_id, GameState.current_location])


func talk(npc_id: String, topic_id: String) -> void:
	if _is_busy("talk"):
		return
	for topic in get_topics(npc_id):
		if topic.get("id", "") == topic_id:
			if not DialogueManager.start(topic.get("dialogue_id", "")):
				return
			GameState.mark_seen(_topic_seen_key(npc_id, topic_id))
			return
	push_error("Investigation.talk: topic '%s' is not currently available for '%s'" % [topic_id, npc_id])


func _topic_seen_key(npc_id: String, topic_id: String) -> String:
	return "topic:%s:%s" % [npc_id, topic_id]


## Must match the key shape ConditionEvaluator's {"examined": "..."} check
## builds independently (it can't call this helper — it lives in a
## different, non-autoload static class).
func _examine_seen_key(location_id: String, point_id: String) -> String:
	return "examine:%s:%s" % [location_id, point_id]


func present(evidence_id: String, npc_id: String) -> void:
	if _is_busy("present"):
		return
	var npc: Dictionary = get_npc(npc_id)
	if npc.is_empty():
		push_error("Investigation.present: unknown NPC '%s' in '%s'" % [npc_id, GameState.current_location])
		return
	var response: Dictionary = _resolve_present_response(npc.get("present_responses", []), evidence_id)
	if response.is_empty():
		push_warning("Investigation.present: '%s' has no present-response for '%s' (add a generic fallback entry)" % [npc_id, evidence_id])
		return
	DialogueManager.start(response.get("dialogue_id", ""))


func move_to(location_id: String) -> void:
	if _is_busy("move_to"):
		return
	for destination in get_available_destinations():
		if destination.get("location_id", "") == location_id:
			GameState.go_to_location(location_id)
			return
	push_error("Investigation.move_to: '%s' is not reachable from '%s'" % [location_id, GameState.current_location])


## Debug-only: why (if at all) a given topic is currently locked. Returns
## {"locked": bool, "conditions": Array[Dictionary]} where each condition
## entry is {"description": String, "passed": bool} (see
## ConditionEvaluator.explain()). Never used by normal gameplay — see
## scripts/debug/debug_panel.gd, the only caller.
func explain_topic_lock(npc_id: String, topic_id: String) -> Dictionary:
	for topic in get_all_topics(npc_id):
		if topic.get("id", "") == topic_id:
			var condition = topic.get("condition")
			return {"locked": not ConditionEvaluator.evaluate(condition), "conditions": ConditionEvaluator.explain(condition)}
	return {"locked": true, "conditions": []}


## Debug-only: same as explain_topic_lock(), for a destination of the
## current location.
func explain_destination_lock(location_id: String) -> Dictionary:
	for destination in get_all_destinations():
		if destination.get("location_id", "") == location_id:
			var condition = destination.get("condition")
			return {"locked": not ConditionEvaluator.evaluate(condition), "conditions": ConditionEvaluator.explain(condition)}
	return {"locked": true, "conditions": []}


## Picks the present-response whose evidence_id matches exactly, or the
## first entry with no evidence_id (the generic fallback) otherwise. This is
## a different lookup than ConditionEvaluator.resolve_variants(): it matches
## against the specific evidence the player is holding up right now, not
## against global game state, so it can't reuse the condition mini-language.
func _resolve_present_response(present_responses: Array, evidence_id: String) -> Dictionary:
	var generic: Dictionary = {}
	for response in present_responses:
		if typeof(response) != TYPE_DICTIONARY:
			continue
		var response_evidence_id: String = response.get("evidence_id", "")
		if response_evidence_id == evidence_id:
			return response
		if response_evidence_id == "" and generic.is_empty():
			generic = response
	return generic
