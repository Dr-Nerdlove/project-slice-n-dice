class_name NetStore
extends RefCounted
## Remembers things about the player's online use (in user://, never in the repository): the server address typed,
## the install's random identity token (lets the server give a dropped player the same place back) and the last
## Play game joined (host and port; kept while a match runs, so "Rejoin" works after an app restart).

## Where the address is kept (tests point this somewhere else).
static var path := "user://online.json"


static func _read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _write(d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


static func load_address() -> String:
	var v: Variant = _read().get("address")
	return v if v is String else ""


static func save_address(address: String) -> void:
	var d := _read()
	d["address"] = address
	_write(d)


## The saved token, or "" when none was created yet.
static func load_token() -> String:
	var v: Variant = _read().get("token")
	return v if NetProto.valid_token(v) else ""


## The install's identity token (32 hex characters). Created on first use and kept; "" only if nothing can be saved.
static func token() -> String:
	var d := _read()
	if NetProto.valid_token(d.get("token")):
		return d["token"]
	var t := Crypto.new().generate_random_bytes(16).hex_encode()
	d["token"] = t
	_write(d)
	return t


## The last Play game joined: {"host": String, "port": int}, or {} when there is none.
static func load_last_game() -> Dictionary:
	var v: Variant = _read().get("last_game")
	if v is Dictionary and (v as Dictionary).get("host") is String and (v as Dictionary).get("port") is float:
		var port := int((v as Dictionary)["port"])
		if port >= 1 and port <= 65535 and ((v as Dictionary)["host"] as String) != "":
			return {"host": (v as Dictionary)["host"], "port": port}
	return {}


static func save_last_game(host: String, port: int) -> void:
	var d := _read()
	d["last_game"] = {"host": host, "port": port}
	_write(d)


static func clear_last_game() -> void:
	var d := _read()
	if d.has("last_game"):
		d.erase("last_game")
		_write(d)


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
