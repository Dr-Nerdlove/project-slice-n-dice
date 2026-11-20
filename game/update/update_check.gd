class_name UpdateCheck
extends RefCounted
## Pure logic of the "newer version" notice: version maths and reading the answer of GitHub's
## "latest release" API. No nodes, no network; main.gd does the request. Never trusts the answer:
## garbage, oversized data or a download link outside the releases repository means "no update".

const API_URL := "https://api.github.com/repos/Dr-Nerdlove/project-slice-n-dice/releases/latest"
## A download link is accepted only below this address (the releases of this repository).
const DOWNLOAD_PREFIX := "https://github.com/Dr-Nerdlove/project-slice-n-dice/releases/download/"
const MAX_BODY_BYTES := 262144
const MAX_URL_LENGTH := 512


## "0.3.1", "v0.3.1", "0.3.0-dev+abc" -> [0, 3, 1]; anything else -> [] (exactly three numbers needed).
## A suffix after "-" or "+" is ignored, so a dev build counts as its base version.
static func parse_version(text: String) -> Array[int]:
	var out: Array[int] = []
	var s := text.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	var cut := s.length()
	for sep in ["-", "+"]:
		var at := s.find(sep)
		if at != -1:
			cut = mini(cut, at)
	s = s.substr(0, cut)
	var parts := s.split(".")
	if parts.size() != 3:
		return out
	for p in parts:
		if p.is_empty() or p.length() > 6 or not p.is_valid_int() or p.begins_with("-") or p.begins_with("+"):
			return [] as Array[int]
		out.append(p.to_int())
	return out


## True when `candidate` is a valid version higher than the valid version `current`.
static func is_newer(candidate: String, current: String) -> bool:
	var a := parse_version(candidate)
	var b := parse_version(current)
	if a.is_empty() or b.is_empty():
		return false
	for i in 3:
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


## "MAJOR*10000 + MINOR*100 + PATCH", the Android version code (see tools/set-version.sh); -1 if invalid.
static func version_code(text: String) -> int:
	var v := parse_version(text)
	if v.is_empty():
		return -1
	return v[0] * 10000 + v[1] * 100 + v[2]


static func is_allowed_url(url: String) -> bool:
	if url.length() > MAX_URL_LENGTH or not url.begins_with(DOWNLOAD_PREFIX):
		return false
	var rest := url.substr(DOWNLOAD_PREFIX.length())
	if rest.is_empty() or rest.contains("..") or rest.contains("\\") or rest.contains("@"):
		return false
	for i in rest.length():
		var c := rest.unicode_at(i)
		if c <= 32 or c >= 127:
			return false
	return true


## Reads the API answer. Returns {"version": "0.3.1", "url": "<apk link>"} if it describes a release newer than
## `current` with an allowed .apk link, otherwise {}.
static func parse_release(body: PackedByteArray, current: String) -> Dictionary:
	if body.is_empty() or body.size() > MAX_BODY_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {}
	var data: Variant = json.data
	if not data is Dictionary:
		return {}
	var rel: Dictionary = data
	if rel.get("draft", false) == true or rel.get("prerelease", false) == true:
		return {}
	var tag: Variant = rel.get("tag_name")
	if not tag is String or not is_newer(tag, current):
		return {}
	var assets: Variant = rel.get("assets")
	if not assets is Array:
		return {}
	for a: Variant in assets:
		if not a is Dictionary:
			continue
		var name: Variant = (a as Dictionary).get("name")
		var url: Variant = (a as Dictionary).get("browser_download_url")
		if name is String and url is String and (name as String).to_lower().ends_with(".apk") and is_allowed_url(url):
			var v := parse_version(tag)
			return {"version": "%d.%d.%d" % [v[0], v[1], v[2]], "url": url}
	return {}


## The version the running game reports (project setting, set from the release tag by tools/set-version.sh).
static func running_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
