class_name NetStore
extends RefCounted
## Remembers the server address the player typed (in user://, never in the repository).

## Where the address is kept (tests point this somewhere else).
static var path := "user://online.json"


static func load_address() -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).get("address") is String:
		return (parsed as Dictionary)["address"]
	return ""


static func save_address(address: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"address": address}))


## "host" or "host:port" -> {"host", "port"}; an empty host means the text is not usable.
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges()
	var port := NetProto.DEFAULT_PORT
	var host := t
	var colon := t.rfind(":")
	if colon >= 0 and t.count(":") == 1:
		host = t.substr(0, colon)
		var ps := t.substr(colon + 1)
		if not ps.is_valid_int() or int(ps) < 1 or int(ps) > 65535:
			return {"host": "", "port": port}
		port = int(ps)
	if host.length() > 253 or host.contains(" "):
		host = ""
	return {"host": host, "port": port}
