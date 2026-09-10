class_name UiUtil
extends RefCounted
## Tiny UI toolbox. Not an autoload and deliberately holds no game state —
## just the couple of Godot idioms that are easy to get subtly wrong and are
## needed in more than one UI script.

## Removes every child of `parent` and frees it.
##
## The obvious version of this — `for child in parent.get_children():
## child.queue_free()` — is a trap: queue_free() only schedules deletion for
## the END of the current frame, so any node added immediately afterwards
## coexists with the "deleted" ones for the rest of the frame. They stay
## visible, stay laid out by the container, and stay connected to their
## signals, so a fast second click can still hit a stale button (e.g. an old
## dialogue choice still bound to its old index). remove_child() takes them
## out of the tree synchronously; queue_free() then reclaims the memory.
static func clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
