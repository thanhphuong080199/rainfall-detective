extends Node
## Autoload: LocaleManager
##
## Loads res://localization/strings.csv into two real Godot Translation
## resources and registers them with TranslationServer, then owns which
## locale is active and persists the player's choice. Every other script
## calls the engine's own tr(key) (or, from a static context that has no
## Object instance, TranslationServer.translate(key)) — this script has no
## opinion on where a key is used, only on getting translations loaded and
## the active locale set before anything else needs to display text.
##
## Deliberately NOT wired through Godot's asset-import pipeline (a .csv set
## to "Import As: Translation" in the editor, producing .translation
## resources under .godot/imported/). That path needs an editor-generated
## .import sidecar this project has no editor session to produce, and the
## output resources aren't hand-inspectable — see docs/localization.md for
## the full comparison. Loading the CSV directly at runtime (FileAccess +
## get_csv_line(), which already handles quoted/escaped fields) is the same
## "plain text, parsed by our own code" approach ContentDB already uses for
## data/*.json — see docs/architecture.md's "Key Architecture Decisions" for
## why that pattern was chosen there, which applies identically here.
##
## No autoload above this one is required — it has zero dependencies — so it
## is registered FIRST in project.godot, guaranteeing TranslationServer is
## fully set up before ContentDB/ContentValidator (which checks translation
## completeness) or any scene runs its own _ready().

signal locale_changed(locale: String)

const STRINGS_PATH := "res://localization/strings.csv"
const SUPPORTED_LOCALES := ["vi", "en"]
const DEFAULT_LOCALE := "vi"
const FALLBACK_LOCALE := "en"

## Overridable for automated tests, so they never touch the real player's
## settings file — same reasoning as SaveManager.save_path.
var settings_path: String = "user://settings.cfg"

## Every key this project's content/UI can reference, for
## ContentValidator's translation-completeness check. Populated by
## _load_strings(); empty until _ready() (or reload_strings(), for tests)
## has run.
var _known_keys: Array[String] = []


func _ready() -> void:
	_load_strings()
	TranslationServer.set_locale(_load_persisted_locale())


## Re-parses localization/strings.csv and re-registers both Translation
## objects. Only needed by _ready() and by tests that want to reload after
## pointing settings_path elsewhere — content never changes this at runtime.
func reload_strings() -> void:
	_load_strings()


func get_known_keys() -> Array[String]:
	return _known_keys


func get_locale() -> String:
	return TranslationServer.get_locale()


## Ignores an unsupported locale code rather than setting it — the same
## "fail closed on bad input" stance ConditionEvaluator takes for an unknown
## condition key.
func set_locale(locale: String) -> void:
	if not SUPPORTED_LOCALES.has(locale):
		push_warning("LocaleManager.set_locale: unsupported locale '%s'" % locale)
		return
	if TranslationServer.get_locale() == locale:
		return
	TranslationServer.set_locale(locale)
	_save_persisted_locale(locale)
	locale_changed.emit(locale)


func _load_strings() -> void:
	_known_keys = []
	var file := FileAccess.open(STRINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("LocaleManager: could not open %s (error %s)" % [STRINGS_PATH, FileAccess.get_open_error()])
		return

	var header: PackedStringArray = file.get_csv_line()
	var locale_columns: Dictionary = {}  # locale code -> column index
	for i in header.size():
		var column: String = header[i]
		if column != "keys":
			locale_columns[column] = i

	var translations: Dictionary = {}  # locale code -> Translation
	for locale in locale_columns:
		var translation := Translation.new()
		translation.locale = locale
		translations[locale] = translation

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty() or (row.size() == 1 and row[0] == ""):
			continue  # trailing blank line
		var key: String = row[0]
		_known_keys.append(key)
		for locale in locale_columns:
			var column_index: int = locale_columns[locale]
			if column_index < row.size() and row[column_index] != "":
				(translations[locale] as Translation).add_message(key, row[column_index])

	for locale in translations:
		TranslationServer.add_translation(translations[locale])


func _load_persisted_locale() -> String:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return DEFAULT_LOCALE
	var locale: String = config.get_value("localization", "locale", DEFAULT_LOCALE)
	return locale if SUPPORTED_LOCALES.has(locale) else DEFAULT_LOCALE


func _save_persisted_locale(locale: String) -> void:
	var config := ConfigFile.new()
	config.load(settings_path)  # keep any other settings this file may hold later
	config.set_value("localization", "locale", locale)
	var error := config.save(settings_path)
	if error != OK:
		push_error("LocaleManager: could not save %s (error %s)" % [settings_path, error])
