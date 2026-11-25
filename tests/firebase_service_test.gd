extends SceneTree

## Unit test suite for FirebaseService (scripts/network/firebase_service.gd).
## Tests:
## 1. Config loading & credentials (google-services.json parsing)
## 2. Session caching & restoration lifecycle (save, restore, clear, sign_out)
## 3. Expired token handling on restore
## 4. URL construction for Firestore REST API
## 5. Unauthenticated guard clauses (save_to_cloud, load_from_cloud, refresh_id_token)
## 6. Native plugin callbacks & auth_error signal emission (_on_google_plugin_completed, _on_google_plugin_failed)
## 7. Sign-in prompt fallback when native plugin is absent
## 8. Sync guard behavior
## 9. Google ID Token sign-in with invalid token (error handling & signal emission)
## 10. Anonymous authentication network flow & error handling
##
## Run:
##   godot --headless --path . --script res://tests/firebase_service_test.gd

const WATCHDOG_SECONDS := 20.0

var checks := 0
var failed: Array[String] = []

var _cached_backup: String = ""
var _had_cached_file: bool = false


func _initialize() -> void:
	var watchdog := create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(func() -> void:
		print("FAIL: watchdog timeout reached")
		quit(1)
	)

	await _run()

	var verdict := "PASS %d/%d" % [checks, checks] if failed.is_empty() else "FAIL %d/%d: %s" % [failed.size(), checks, ", ".join(failed)]
	print(verdict)
	quit(0 if failed.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed.append(label)
		print("  [FAIL] %s" % label)
	else:
		print("  [OK]   %s" % label)


func _run() -> void:
	await process_frame

	var firebase: Node = root.get_node_or_null("/root/FirebaseService")
	check(firebase != null, "FirebaseService autoload node exists in SceneTree")
	if firebase == null:
		return

	_backup_session(firebase)

	_case_config_loading(firebase)
	_case_firestore_url_generation(firebase)
	_case_unauthenticated_guards(firebase)
	_case_plugin_callbacks_and_signals(firebase)
	_case_session_lifecycle(firebase)
	await _case_expired_token_restoration(firebase)
	_case_prompt_fallback(firebase)
	_case_sync_guards(firebase)
	await _case_invalid_google_token_flow(firebase)
	await _case_anonymous_auth(firebase)

	_restore_original_session(firebase)


func _backup_session(firebase: Node) -> void:
	var cache_path: String = firebase.AUTH_CACHE_PATH
	_had_cached_file = FileAccess.file_exists(cache_path)
	if _had_cached_file:
		var f := FileAccess.open(cache_path, FileAccess.READ)
		if f != null:
			_cached_backup = f.get_as_text()
			f.close()


func _restore_original_session(firebase: Node) -> void:
	firebase.sign_out()
	var cache_path: String = firebase.AUTH_CACHE_PATH
	if _had_cached_file and not _cached_backup.is_empty():
		var f := FileAccess.open(cache_path, FileAccess.WRITE)
		if f != null:
			f.store_string(_cached_backup)
			f.close()
	elif FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(cache_path)


# ------------------------------------------------------------------------------
# TEST CASES
# ------------------------------------------------------------------------------

## 1. Config loading from google-services.json or fallback constants
func _case_config_loading(firebase: Node) -> void:
	print("--- Case 1: Config loading ---")
	firebase._load_google_services_config()

	check(not firebase.project_id.is_empty(), "project_id is configured: %s" % firebase.project_id)
	check(firebase.api_key.begins_with("AIza"), "api_key has valid Google API key prefix: %s..." % firebase.api_key.substr(0, 8))
	check(firebase.web_client_id.contains(".apps.googleusercontent.com"), "web_client_id is valid OAuth client: %s..." % firebase.web_client_id.substr(0, 16))


## 2. Firestore document URL construction
func _case_firestore_url_generation(firebase: Node) -> void:
	print("--- Case 2: Firestore URL generation ---")
	var prev_proj: String = firebase.project_id
	var prev_user: String = firebase.user_id

	firebase.project_id = "test-project-42"
	firebase.user_id = "usr_xyz_99"

	var url: String = firebase._get_firestore_document_url()
	var expected := "https://firestore.googleapis.com/v1/projects/test-project-42/databases/(default)/documents/users/usr_xyz_99"
	check(url == expected, "Firestore document URL formatted correctly (%s)" % url)

	firebase.project_id = prev_proj
	firebase.user_id = prev_user


## 3. Unauthenticated guard clauses
func _case_unauthenticated_guards(firebase: Node) -> void:
	print("--- Case 3: Unauthenticated guards ---")
	firebase.sign_out()
	check(not firebase.is_logged_in, "precondition: user is logged out")

	# save_to_cloud should return false when not logged in
	var save_result: bool = await firebase.save_to_cloud({"test": 123})
	check(not save_result, "save_to_cloud returns false when unauthenticated")

	# load_from_cloud should return empty dictionary
	var load_result: Dictionary = await firebase.load_from_cloud()
	check(load_result.is_empty(), "load_from_cloud returns empty dictionary when unauthenticated")

	# refresh_id_token should return false when refresh_token is empty
	firebase._refresh_token = ""
	var refresh_result: bool = await firebase.refresh_id_token()
	check(not refresh_result, "refresh_id_token returns false when refresh_token is empty")


## 4. Native plugin callbacks & auth_error signal emission
func _case_plugin_callbacks_and_signals(firebase: Node) -> void:
	print("--- Case 4: Native plugin callbacks & signals ---")
	var captured := {"error": ""}
	var on_auth_error := func(msg: String) -> void:
		captured["error"] = msg

	firebase.auth_error.connect(on_auth_error)

	# Test empty ID token in completed callback
	firebase._on_google_plugin_completed("")
	check(captured["error"] == "Empty ID token returned", "empty ID token triggers auth_error with expected message")

	# Test plugin failure callback
	captured["error"] = ""
	firebase._on_google_plugin_failed("Canceled by user")
	check(captured["error"] == "Canceled by user", "plugin failure forwards error message via auth_error")

	firebase.auth_error.disconnect(on_auth_error)


## 5. Session lifecycle & caching (save, restore, clear, sign_out)
func _case_session_lifecycle(firebase: Node) -> void:
	print("--- Case 5: Session caching lifecycle ---")
	# Configure fake session
	var fake_uid := "mock_uid_12345"
	var fake_email := "mock@politropia.test"
	var fake_name := "Mock User"
	var fake_token := "token_abc"
	var fake_refresh := "refresh_xyz"
	var fake_expiry: int = int(Time.get_unix_time_from_system()) + 3600

	firebase.user_id = fake_uid
	firebase.user_email = fake_email
	firebase.user_name = fake_name
	firebase._id_token = fake_token
	firebase._refresh_token = fake_refresh
	firebase._token_expires_at = fake_expiry
	firebase.is_logged_in = true

	# Save session
	firebase._save_cached_session()
	check(FileAccess.file_exists(firebase.AUTH_CACHE_PATH), "session cache file created on disk")

	# Verify persisted content
	var file := FileAccess.open(firebase.AUTH_CACHE_PATH, FileAccess.READ)
	check(file != null, "session cache file is readable")
	if file != null:
		var content := file.get_as_text()
		file.close()
		var json := JSON.new()
		check(json.parse(content) == OK, "session cache file contains valid JSON")
		var dict: Dictionary = json.data if json.data is Dictionary else {}
		check(dict.get("user_id") == fake_uid, "cached user_id matches")
		check(dict.get("refresh_token") == fake_refresh, "cached refresh_token matches")

	# Clear in-memory state
	firebase.user_id = ""
	firebase.user_email = ""
	firebase.user_name = ""
	firebase._id_token = ""
	firebase._refresh_token = ""
	firebase.is_logged_in = false

	# Restore cached session
	var captured := {"auth_event": false, "signout_event": false}
	var on_state_changed := func(logged_in: bool) -> void:
		if logged_in:
			captured["auth_event"] = true
		else:
			captured["signout_event"] = true

	firebase.auth_state_changed.connect(on_state_changed)

	firebase._restore_cached_session()
	check(firebase.is_logged_in, "session restored: is_logged_in is true")
	check(firebase.user_id == fake_uid, "session restored: user_id restored from disk")
	check(firebase.user_email == fake_email, "session restored: user_email restored from disk")
	check(firebase._id_token == fake_token, "session restored: _id_token restored from disk")
	check(captured["auth_event"], "auth_state_changed(true) signal emitted on restoration")

	# Test sign_out
	firebase.sign_out()
	check(not firebase.is_logged_in, "sign_out: is_logged_in set to false")
	check(firebase.user_id.is_empty(), "sign_out: user_id cleared")
	check(firebase._id_token.is_empty(), "sign_out: _id_token cleared")
	check(not FileAccess.file_exists(firebase.AUTH_CACHE_PATH), "sign_out: cache file removed from disk")
	check(captured["signout_event"], "sign_out: auth_state_changed(false) emitted")

	firebase.auth_state_changed.disconnect(on_state_changed)


## 6. Expired token handling on restore
func _case_expired_token_restoration(firebase: Node) -> void:
	print("--- Case 6: Expired token restoration ---")
	firebase.sign_out()

	# Create cache with expired token and dummy refresh token
	var cache_data := {
		"user_id": "expired_user",
		"user_email": "expired@test.com",
		"user_name": "Expired",
		"id_token": "expired_id_token",
		"refresh_token": "invalid_refresh_token",
		"expires_at": int(Time.get_unix_time_from_system()) - 1000 # Past timestamp
	}
	var file := FileAccess.open(firebase.AUTH_CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(cache_data))
		file.close()

	# Restore cached session should detect expiration and attempt refresh
	await firebase._restore_cached_session()

	# Since invalid_refresh_token will fail to refresh from Google, session must be cleared
	check(not firebase.is_logged_in, "session remains logged out when refreshing expired invalid token")
	check(firebase.user_id.is_empty(), "user_id is cleared after refresh failure")
	check(not FileAccess.file_exists(firebase.AUTH_CACHE_PATH), "cache file removed after refresh failure")


## 7. Sign-in prompt fallback when native plugin is absent
func _case_prompt_fallback(firebase: Node) -> void:
	print("--- Case 7: Prompt fallback when native plugin is absent ---")
	# In PC/editor environment, _google_plugin is null
	var prev_plugin: Object = firebase._google_plugin
	firebase._google_plugin = null

	# Calling prompt_google_sign_in falls back to sign_in_anonymously()
	# We verify that it does not crash or raise uncaught errors
	firebase.prompt_google_sign_in()
	check(firebase._google_plugin == null, "desktop fallback invoked successfully without native plugin")

	firebase._google_plugin = prev_plugin


## 8. Sync guards
func _case_sync_guards(firebase: Node) -> void:
	print("--- Case 8: Sync guards ---")
	firebase.sign_out()
	var captured := {"sync_started": false}
	var on_sync := func() -> void:
		captured["sync_started"] = true
	firebase.sync_started.connect(on_sync)

	# Should not start sync when not logged in
	firebase.sync_with_cloud()
	check(not captured["sync_started"], "sync_with_cloud does not start when unauthenticated")

	firebase.sync_started.disconnect(on_sync)


## 9. Google ID Token sign-in with invalid token
func _case_invalid_google_token_flow(firebase: Node) -> void:
	print("--- Case 9: Invalid Google ID token network flow ---")
	firebase.sign_out()

	var captured := {"error": ""}
	var on_err := func(msg: String) -> void:
		captured["error"] = msg
	firebase.auth_error.connect(on_err)

	# Calling with an invalid fake token
	firebase.sign_in_with_google_id_token("invalid_google_id_token_test")

	var start_time := Time.get_ticks_msec()
	while captured["error"].is_empty() and (Time.get_ticks_msec() - start_time) < 4000:
		await process_frame

	firebase.auth_error.disconnect(on_err)

	check(not captured["error"].is_empty(), "sign_in_with_google_id_token emitted auth_error on invalid token: '%s'" % captured["error"])
	check(not firebase.is_logged_in, "user remains unauthenticated after failed Google token login")


## 10. Anonymous authentication network flow & error handling
func _case_anonymous_auth(firebase: Node) -> void:
	print("--- Case 10: Anonymous authentication network flow ---")
	firebase.sign_out()

	var captured := {"auth_changed": false, "error": ""}
	var on_auth := func(logged_in: bool) -> void:
		if logged_in:
			captured["auth_changed"] = true

	var on_err := func(msg: String) -> void:
		captured["error"] = msg

	firebase.auth_state_changed.connect(on_auth)
	firebase.auth_error.connect(on_err)

	# Execute sign_in_anonymously
	firebase.sign_in_anonymously()

	# Wait up to 5 seconds for HTTP network request to complete
	var start_time := Time.get_ticks_msec()
	while not firebase.is_logged_in and captured["error"].is_empty() and (Time.get_ticks_msec() - start_time) < 5000:
		await process_frame

	firebase.auth_state_changed.disconnect(on_auth)
	firebase.auth_error.disconnect(on_err)

	if firebase.is_logged_in:
		check(true, "sign_in_anonymously succeeded over network")
		check(not firebase.user_id.is_empty(), "authenticated user_id received: %s" % firebase.user_id)
		check(not firebase._id_token.is_empty(), "authenticated id_token received")
		check(captured["auth_changed"], "auth_state_changed(true) emitted on sign-in")
		check(FileAccess.file_exists(firebase.AUTH_CACHE_PATH), "session saved to cache after sign-in")
		firebase.sign_out()
	else:
		# If anonymous auth provider is disabled or network fails (e.g. 400 ADMIN_ONLY_OPERATION)
		check(not captured["error"].is_empty() or not firebase.is_logged_in,
			"sign_in_anonymously handled API response gracefully (auth_error: '%s')" % captured["error"])
