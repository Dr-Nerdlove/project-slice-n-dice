class_name TuningStore
extends RefCounted
## Persists the tunable config values to user://.

const PATH := "user://tuning.json"


static func load_into(cfg: Config) -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		cfg.from_dict(parsed)


static func save(cfg: Config) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(cfg.to_dict(), "\t"))
