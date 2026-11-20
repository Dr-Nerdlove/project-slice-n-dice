extends SceneTree
## Tests of the update notice (headless): version maths, reading the release answer, the banner and its
## wiring in main.gd, and one real HTTP round trip against a tiny local server. Run through tests/run.sh.

var fails := 0
## Moves the localhost ports (and the user:// file) so several test runs can go on at once (tests/run.sh).
var PORT_OFFSET := int(OS.get_environment("TEST_PORT_OFFSET"))


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  [" + info + "]" if info != "" else ""))
	if not ok:
		fails += 1


const GOOD_URL := "https://github.com/Dr-Nerdlove/project-slice-n-dice/releases/download/v0.3.1/slice-n-dice-v0.3.1.apk"


func release(tag: String, assets: Array, extra := {}) -> PackedByteArray:
	var d := {"tag_name": tag, "assets": assets}
	d.merge(extra, true)
	return JSON.stringify(d).to_utf8_buffer()


func apk(url := GOOD_URL, name := "slice-n-dice-v0.3.1.apk") -> Dictionary:
	return {"name": name, "browser_download_url": url}


func _initialize() -> void:
	_logic_tests()
	_source_tests()
	await _wiring_tests()
	await _http_tests()
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


func _logic_tests() -> void:
	check("update: version parses with and without v", UpdateCheck.parse_version("0.3.1") == [0, 3, 1] and UpdateCheck.parse_version("v1.20.3") == [1, 20, 3])
	check("update: a dev suffix is ignored", UpdateCheck.parse_version("0.3.0-dev+abc1234") == [0, 3, 0])
	var bad := true
	for t in ["", "v", "1", "1.2", "1.2.3.4", "a.b.c", "1.2.x", "1..3", "-1.2.3", "1.-2.3", "1.2.3456789", " ", "1.2.3 4"]:
		if not UpdateCheck.parse_version(t).is_empty():
			bad = false
			print("   accepted: ", t)
	check("update: malformed versions are rejected", bad)
	check("update: 0.10.0 is newer than 0.9.0 (numbers, not text)", UpdateCheck.is_newer("0.10.0", "0.9.0") and not UpdateCheck.is_newer("0.9.0", "0.10.0"))
	check("update: major, minor and patch each count", UpdateCheck.is_newer("1.0.0", "0.99.99") and UpdateCheck.is_newer("0.4.0", "0.3.9") and UpdateCheck.is_newer("0.3.1", "0.3.0"))
	check("update: the same version is not newer", not UpdateCheck.is_newer("0.3.0", "0.3.0") and not UpdateCheck.is_newer("v0.3.0", "0.3.0-dev+x"))
	check("update: an older version is not newer", not UpdateCheck.is_newer("0.2.1", "0.3.0"))
	check("update: garbage is never newer", not UpdateCheck.is_newer("junk", "0.3.0") and not UpdateCheck.is_newer("9.9.9", "junk"))
	check("update: version code", UpdateCheck.version_code("0.3.0") == 300 and UpdateCheck.version_code("1.2.3") == 10203 and UpdateCheck.version_code("x") == -1)

	var ok := UpdateCheck.parse_release(release("v0.3.1", [apk()]), "0.3.0")
	check("update: a newer release gives version and link", ok.get("version", "") == "0.3.1" and ok.get("url", "") == GOOD_URL, str(ok))
	check("update: the same release gives nothing", UpdateCheck.parse_release(release("v0.3.0", [apk()]), "0.3.0").is_empty())
	check("update: an older release gives nothing", UpdateCheck.parse_release(release("v0.2.9", [apk()]), "0.3.0").is_empty())
	check("update: the first .apk asset is taken", UpdateCheck.parse_release(release("v0.3.1", [{"name": "notes.txt", "browser_download_url": GOOD_URL.replace(".apk", ".txt")}, apk()]), "0.3.0").get("url", "") == GOOD_URL)
	check("update: a release without an apk gives nothing", UpdateCheck.parse_release(release("v0.3.1", [{"name": "notes.txt", "browser_download_url": GOOD_URL}]), "0.3.0").is_empty())
	check("update: draft and pre-release are ignored", UpdateCheck.parse_release(release("v0.3.1", [apk()], {"draft": true}), "0.3.0").is_empty() and UpdateCheck.parse_release(release("v0.3.1", [apk()], {"prerelease": true}), "0.3.0").is_empty())
	var evil := [
		"http://github.com/Dr-Nerdlove/project-slice-n-dice/releases/download/v0.3.1/a.apk",
		"https://evil.example/Dr-Nerdlove/project-slice-n-dice/releases/download/v0.3.1/a.apk",
		"https://github.com.evil.example/Dr-Nerdlove/project-slice-n-dice/releases/download/v0.3.1/a.apk",
		"https://github.com/Dr-Nerdlove/other-repo/releases/download/v0.3.1/a.apk",
		"https://github.com/Dr-Nerdlove/project-slice-n-dice/releases/download/../../../../evil/a.apk",
		"https://github.com/Dr-Nerdlove/project-slice-n-dice/releases/download/v1/a.apk x",
		"https://github.com/Dr-Nerdlove/project-slice-n-dice/releases/download/@evil.example/a.apk",
		"https://github.com/Dr-Nerdlove/project-slice-n-dice/releases/download/",
		"https://github.com/Dr-Nerdlove/project-slice-n-dice/releases/download/" + "a".repeat(600),
		"https://github.com/Joni9993/slice-n-dice-releases/releases/download/v0.3.1/a.apk",  # the former releases repository
		"file:///sdcard/a.apk", "javascript:alert(1)", "",
	]
	var all_refused := true
	for u: String in evil:
		if not UpdateCheck.parse_release(release("v0.3.1", [apk(u)]), "0.3.0").is_empty():
			all_refused = false
			print("   accepted: ", u)
	check("update: download links outside the releases repository are refused", all_refused)
	check("update: a refused link is skipped, a later good one is used", UpdateCheck.parse_release(release("v0.3.1", [apk("https://evil.example/a.apk"), apk()]), "0.3.0").get("url", "") == GOOD_URL)

	var garbage_ok := true
	var garbage: Array = [
		PackedByteArray(), "not json".to_utf8_buffer(), "[1,2,3]".to_utf8_buffer(), "null".to_utf8_buffer(), "42".to_utf8_buffer(),
		"{".to_utf8_buffer(), '{"tag_name": 5}'.to_utf8_buffer(), '{"tag_name": "v9.9.9"}'.to_utf8_buffer(),
		'{"tag_name": "v9.9.9", "assets": 7}'.to_utf8_buffer(), '{"tag_name": "v9.9.9", "assets": [1, "x", null, {"name": 3}]}'.to_utf8_buffer(),
		'{"tag_name": "v9.9.9", "assets": [{"name": "a.apk", "browser_download_url": 5}]}'.to_utf8_buffer(),
	]
	for g: PackedByteArray in garbage:
		if not UpdateCheck.parse_release(g, "0.3.0").is_empty():
			garbage_ok = false
	check("update: garbage in the answer gives nothing and does not crash", garbage_ok)
	var big := release("v0.3.1", [apk()], {"body": "x".repeat(UpdateCheck.MAX_BODY_BYTES)})
	check("update: an oversized answer is refused", big.size() > UpdateCheck.MAX_BODY_BYTES and UpdateCheck.parse_release(big, "0.3.0").is_empty())
	check("update: the same answer without the padding is accepted", not UpdateCheck.parse_release(release("v0.3.1", [apk()]), "0.3.0").is_empty())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _source_tests() -> void:
	var presets := _read(ProjectSettings.globalize_path("res://export_presets.cfg"))
	var rx := RegEx.new()
	rx.compile('(?m)^version/name="([^"]*)"')
	var m := rx.search(presets)
	var name_in_presets := m.get_string(1) if m != null else ""
	var running := UpdateCheck.running_version()
	check("update: the game knows its version", not UpdateCheck.parse_version(running).is_empty(), running)
	check("update: export preset name matches the game's version", name_in_presets == running.split("-")[0].split("+")[0], "%s vs %s" % [name_in_presets, running])
	rx.compile("(?m)^version/code=(\\d+)")
	m = rx.search(presets)
	check("update: export preset code is MAJOR*10000+MINOR*100+PATCH", m != null and m.get_string(1).to_int() == UpdateCheck.version_code(running))
	check("name: the app is called Spinback Rumble", ProjectSettings.get_setting("application/config/name") == "Spinback Rumble" and presets.contains('package/name="Spinback Rumble"'))
	check("name: the package id is unchanged (a new id would be a separate app and lose the testers' data)", presets.contains('package/unique_name="io.slicendice.prototype"'))
	check("name: Android back does not quit on its own (main.gd handles it)", ProjectSettings.get_setting("application/config/quit_on_go_back") == false)
	var src := _read("res://main.gd")
	var server_at := src.find('has("--server")')
	var timer_at := src.find("create_timer(UPDATE_CHECK_DELAY)")
	check("update: main.gd returns in server mode before it schedules the check", server_at != -1 and timer_at > server_at and src.substr(server_at, timer_at - server_at).contains("\t\treturn\n"))
	check("update: main.gd does not check in headless runs", src.contains('DisplayServer.get_name() != "headless"'))


func _wiring_tests() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check("update: no banner and no request at the start", not main.main_menu.update_banner.visible and main._update_http == null)
	check("update: the menu shows the running version", main.menu._version_label.text == "Version " + UpdateCheck.running_version() and not main.menu._update_btn.visible)
	main.offer_update({})
	check("update: nothing newer shows nothing", not main.main_menu.update_banner.visible and not main.menu._update_btn.visible)
	var info := UpdateCheck.parse_release(release("v0.3.1", [apk()]), "0.3.0")
	main.offer_update(info)
	check("update: a newer version shows the banner with the text", main.main_menu.update_banner.visible and main.main_menu._banner_label.text == "New version 0.3.1 available", main.main_menu._banner_label.text)
	check("update: the menu shows the new version and the button", main.menu._update_btn.visible and main.menu._version_label.text.contains("0.3.1"))
	await process_frame
	await process_frame
	await process_frame
	var banner_rect: Rect2 = main.main_menu.update_banner.get_global_rect()
	check("update: the banner sits inside the screen", banner_rect.size.x > 100.0 and banner_rect.size.y > 20.0 and Rect2(Vector2.ZERO, main.get_viewport().get_visible_rect().size).encloses(banner_rect), str(banner_rect))
	check("update: the banner is a main menu thing: it is not in the game HUD and only the pause button blocks touches there", main.main_menu.visible and main.router.exclude_rects == [main.hud.gear_rect()])
	check("update: Settings shows the update button and the new version", main.main_menu.settings_update_btn.visible and main.main_menu.settings_version_label.text.contains("0.3.1"))
	var menu_signals := [0]
	main.menu.update_requested.connect(func() -> void: menu_signals[0] += 1)
	var opened := []
	main.open_url = func(u: String) -> void: opened.append(u)
	main.menu._update_btn.pressed.emit()
	check("update: the menu button reaches main", menu_signals[0] == 1)
	check("update: the menu button opens the download link", opened == [GOOD_URL], str(opened))
	main.main_menu.update_requested.emit()
	check("update: the banner button opens the download link", opened == [GOOD_URL, GOOD_URL])
	main._update["url"] = "https://evil.example/a.apk"
	main._download_update()
	check("update: a link outside the releases repository is never opened", opened.size() == 2)
	main._update["url"] = GOOD_URL
	main.main_menu.update_banner.find_children("*", "Button", true, false).back().pressed.emit()
	check("update: Later hides the banner", not main.main_menu.update_banner.visible)
	await process_frame
	check("update: Later is remembered for the session", main._update_dismissed)
	main.offer_update(info)
	check("update: Later stays for the session, the menu button stays", not main.main_menu.update_banner.visible and main.menu._update_btn.visible)
	main.queue_free()
	await process_frame

	var main2: Node = load("res://main.tscn").instantiate()
	root.add_child(main2)
	await process_frame
	main2.offer_update(UpdateCheck.parse_release(release("v0.3.0", [apk()]), UpdateCheck.running_version()))
	check("update: the same version shows nothing", not main2.main_menu.update_banner.visible)
	main2.queue_free()
	await process_frame


## One real request over HTTP to a tiny local server: the answer is read, the request carries a User-Agent
## and nothing that identifies the user.
func _http_tests() -> void:
	var srv := TCPServer.new()
	var port := 0
	for p in range(24700 + PORT_OFFSET, 24740 + PORT_OFFSET):
		if srv.listen(p, "127.0.0.1") == OK:
			port = p
			break
	check("update: local test server started", port != 0)
	if port == 0:
		return
	var seen := {"request": ""}
	for case in [["a newer release", release("v9.0.0", [apk()]), true, "200 OK"], ["garbage", "<html>nope</html>".to_utf8_buffer(), false, "200 OK"], ["an error status with a valid body", release("v9.0.0", [apk()]), false, "404 Not Found"]]:
		var main: Node = load("res://main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		seen["request"] = ""
		main.update_url = "http://127.0.0.1:%d/latest" % port
		main._start_update_check()
		check("update: the request has a timeout and a size limit", main._update_http.timeout > 0.0 and main._update_http.body_size_limit == UpdateCheck.MAX_BODY_BYTES)
		var conn: StreamPeerTCP = null
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 5000:
			if conn == null and srv.is_connection_available():
				conn = srv.take_connection()
			if conn != null:
				conn.poll()
				if conn.get_available_bytes() > 0:
					seen["request"] = conn.get_utf8_string(conn.get_available_bytes())
					var body: PackedByteArray = case[1]
					conn.put_data(("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [case[3], body.size()]).to_utf8_buffer())
					conn.put_data(body)
					break
			await process_frame
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 5000 and main._update_http != null and is_instance_valid(main._update_http) and not main._update_http.is_queued_for_deletion():
			await process_frame
		check("update: the request reached the server (%s)" % case[0], seen["request"].begins_with("GET /latest"))
		var shown: bool = main.main_menu.update_banner.visible
		check("update: HTTP round trip (%s) -> banner %s" % [case[0], case[2]], shown == case[2], seen["request"].split("\r\n")[0])
		if case[2]:
			var req: String = seen["request"].to_lower()
			check("update: the request has a User-Agent and no cookies or ids", req.contains("user-agent: slice-n-dice") and not req.contains("cookie") and not req.contains("authorization") and not req.contains("x-"), req.split("\r\n")[0])
		if conn != null:
			conn.disconnect_from_host()
		main.queue_free()
		await process_frame
	srv.stop()
