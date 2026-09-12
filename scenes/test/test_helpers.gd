class_name TestHelpers
extends RefCounted
## Small, shared boilerplate for this project's independent headless test
## scripts (see docs/testing.md and .claude/skills/godot-testing) — NOT a
## parallel gameplay API, just the handful of things every focused test
## script under scenes/test/ would otherwise repeat: pointing SaveManager/
## LocaleManager at throwaway user:// files so a test can never touch a real
## player's save or settings (every copy of this project — including a git
## worktree — shares one real user:// folder, see docs/architecture.md's
## "Known limitations"), and printing the same pass/fail verdict block
## smoke_test.gd already established.
##
## Deliberately a plain RefCounted static toolbox, not an autoload: it holds
## no state of its own (the caller's own _failures array is passed in), and
## it never references another autoload by bare name — so, unlike
## ContentValidator/ConditionEvaluator, it's safe to reference directly by
## class name (TestHelpers.foo(...)) from a custom -s entry script without
## tripping the compile-order trap documented in docs/architecture.md ("A
## Godot quirk this project works around").


## Points SaveManager at a throwaway user:// file unique to `test_name`, and
## deletes any file left over from a previous run of the same test. Every
## test script that calls SaveManager.save_game()/load_game() must call this
## first.
static func isolate_save(save_manager: Node, test_name: String) -> void:
	save_manager.save_path = "user://%s_save.json" % test_name
	save_manager.delete_save()


## Points LocaleManager at a throwaway user:// settings file unique to
## `test_name`. Only needed by a test that calls LocaleManager.set_locale().
static func isolate_locale(locale_manager: Node, test_name: String) -> void:
	locale_manager.settings_path = "user://%s_settings.cfg" % test_name


## The "--- N passed, M failed ---" / "ALL TESTS PASSED" verdict block every
## test script in this project prints before quitting — returns the exit
## code to pass straight to SceneTree.quit().
static func finish(failures: Array[String], pass_count: int) -> int:
	print("--- %d passed, %d failed ---" % [pass_count, failures.size()])
	if failures.is_empty():
		print("ALL TESTS PASSED")
		return 0
	for failure in failures:
		print("FAIL: ", failure)
	return 1
