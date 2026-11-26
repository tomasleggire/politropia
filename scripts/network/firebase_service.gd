extends Node

## Firebase Authentication & Cloud Firestore Service (autoload `FirebaseService`).
##
## Manages:
## 1. Google Sign-In authentication flow & token refresh
## 2. Cloud Firestore read/write for Politropia save data & collectibles
## 3. Automatic synchronization between local disk and cloud storage

signal auth_state_changed(is_logged_in: bool)
signal sync_started
signal sync_completed(success: bool)
signal auth_error(message: String)

const AUTH_CACHE_PATH := "user://firebase_auth.json"
const GOOGLE_SERVICES_PATH := "res://google-services.json"

# Firebase Project Credentials (fallback if google-services.json is missing)
var project_id: String = "blank-2315c"
var api_key: String = "AIzaSyDryAZ1DJTrdev8Jset5pqTsWs0LUSzMCg"
var web_client_id: String = "1089739619010-p5b2veeb1iik6icu0m1v6apeud7ulo6j.apps.googleusercontent.com"

# Session State
var is_logged_in := false
var user_id := ""
var user_email := ""
var user_name := ""
var user_photo_url := ""
var _id_token := ""
var _refresh_token := ""
var _token_expires_at := 0

var _is_syncing := false
var _google_plugin: Object = null


func _ready() -> void:
	_load_google_services_config()
	_init_native_plugin.call_deferred()
	_restore_cached_session.call_deferred()


func _init_native_plugin() -> void:
	if Engine.has_singleton("GoogleSignIn"):
		_google_plugin = Engine.get_singleton("GoogleSignIn")
		if _google_plugin.has_signal("sign_in_completed") and not _google_plugin.is_connected("sign_in_completed", _on_google_plugin_completed):
			_google_plugin.connect("sign_in_completed", _on_google_plugin_completed)
		if _google_plugin.has_signal("sign_in_failed") and not _google_plugin.is_connected("sign_in_failed", _on_google_plugin_failed):
			_google_plugin.connect("sign_in_failed", _on_google_plugin_failed)


func _on_google_plugin_completed(id_token: String) -> void:
	if not id_token.is_empty():
		sign_in_with_google_id_token(id_token)
	else:
		auth_error.emit("Empty ID token returned")


func _on_google_plugin_failed(error_message: String) -> void:
	auth_error.emit(error_message)


## Triggers the native Android Google Sign-In prompt or falls back to anonymous sign-in on desktop/dev.
func prompt_google_sign_in() -> void:
	if _google_plugin != null:
		_google_plugin.call("signIn", web_client_id)
	else:
		push_warning("FirebaseService: GoogleSignIn native plugin not found (Android only). Conectando con cuenta Firebase en modo invitado...")
		sign_in_anonymously()


## Clears cached credentials and prompts the Google account selector.
func switch_google_account() -> void:
	_clear_cached_session()
	const AVATAR_CACHE := "user://avatar_cache.png"
	if FileAccess.file_exists(AVATAR_CACHE):
		DirAccess.remove_absolute(AVATAR_CACHE)
	if _google_plugin != null:
		_google_plugin.call("switchAccount", web_client_id)
	else:
		push_warning("FirebaseService: GoogleSignIn native plugin not found (Android only). Conectando con cuenta Firebase en modo invitado...")
		sign_in_anonymously()


## Sign in to Firebase Authentication anonymously (works on all platforms without native plugins).
func sign_in_anonymously() -> void:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % api_key
	var payload := { "returnSecureToken": true }
	var headers := ["Content-Type: application/json"]

	var response := await _send_http_request(url, HTTPClient.METHOD_POST, headers, JSON.stringify(payload))
	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var err_text := body.get_string_from_utf8()
		push_error("FirebaseService: anonymous login error (%d): %s" % [response_code, err_text])
		auth_error.emit("Error de autenticación: " + str(response_code))
		return

	if not _process_auth_response_body(body, "invitado@politropia.local", "INVITADO"):
		auth_error.emit("No se pudo procesar la respuesta de autenticación")


## Reads project_id, api_key, and client_id from google-services.json.
func _load_google_services_config() -> void:
	var data := _read_json_file(GOOGLE_SERVICES_PATH)
	if data.is_empty():
		return

	var project_info: Dictionary = data.get("project_info", {})
	if project_info.has("project_id"):
		project_id = str(project_info["project_id"])

	var clients: Array = data.get("client", [])
	if not clients.is_empty() and clients[0] is Dictionary:
		var client_dict: Dictionary = clients[0]
		var api_keys: Array = client_dict.get("api_key", [])
		if not api_keys.is_empty() and api_keys[0] is Dictionary:
			api_key = str(api_keys[0].get("current_key", api_key))

		var oauth_clients: Array = client_dict.get("oauth_client", [])
		for oauth: Variant in oauth_clients:
			if oauth is Dictionary and oauth.get("client_type") == 3:
				web_client_id = str(oauth.get("client_id", web_client_id))


## Restores user session from cached tokens on game startup.
func _restore_cached_session() -> void:
	var data := _read_json_file(AUTH_CACHE_PATH)
	if data.is_empty():
		return

	_refresh_token = str(data.get("refresh_token", ""))
	user_id = str(data.get("user_id", ""))
	user_email = str(data.get("user_email", ""))
	user_name = str(data.get("user_name", ""))
	user_photo_url = str(data.get("user_photo_url", ""))
	_id_token = str(data.get("id_token", ""))
	_token_expires_at = int(data.get("expires_at", 0))

	if _refresh_token.is_empty():
		return

	if not await _ensure_valid_token(60):
		return

	is_logged_in = true
	auth_state_changed.emit(true)
	sync_with_cloud()


func _save_cached_session() -> void:
	var file := FileAccess.open(AUTH_CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return

	var data := {
		"user_id": user_id,
		"user_email": user_email,
		"user_name": user_name,
		"user_photo_url": user_photo_url,
		"id_token": _id_token,
		"refresh_token": _refresh_token,
		"expires_at": _token_expires_at
	}
	file.store_string(JSON.stringify(data))
	file.close()


func _clear_cached_session() -> void:
	if FileAccess.file_exists(AUTH_CACHE_PATH):
		DirAccess.remove_absolute(AUTH_CACHE_PATH)
	is_logged_in = false
	user_id = ""
	user_email = ""
	user_name = ""
	user_photo_url = ""
	_id_token = ""
	_refresh_token = ""
	_token_expires_at = 0
	auth_state_changed.emit(false)


## Sign in to Firebase Authentication using a Google ID Token (from Android plugin or OAuth).
func sign_in_with_google_id_token(google_id_token: String) -> void:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=%s" % api_key
	var payload := {
		"postBody": "id_token=%s&providerId=google.com" % google_id_token,
		"requestUri": "http://localhost",
		"returnIdpCredential": true,
		"returnSecureToken": true
	}
	var headers := ["Content-Type: application/json"]

	var response := await _send_http_request(url, HTTPClient.METHOD_POST, headers, JSON.stringify(payload))
	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var err_text := body.get_string_from_utf8()
		push_error("FirebaseService: login error (%d): %s" % [response_code, err_text])
		auth_error.emit("Google Sign-In failed: " + str(response_code))
		return

	if not _process_auth_response_body(body):
		auth_error.emit("Could not parse auth response")


## Renews Firebase ID token using stored refresh token.
func refresh_id_token() -> bool:
	if _refresh_token.is_empty():
		_clear_cached_session()
		return false

	var url := "https://securetoken.googleapis.com/v1/token?key=%s" % api_key
	var body_string := "grant_type=refresh_token&refresh_token=%s" % _refresh_token
	var headers := ["Content-Type: application/x-www-form-urlencoded"]

	var response := await _send_http_request(url, HTTPClient.METHOD_POST, headers, body_string)
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		_clear_cached_session()
		return false

	var json := JSON.new()
	var body: PackedByteArray = response[3]
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		_clear_cached_session()
		return false

	var data: Dictionary = json.data
	_id_token = str(data.get("id_token", ""))
	_refresh_token = str(data.get("refresh_token", _refresh_token))
	user_id = str(data.get("user_id", user_id))
	var expires_in: int = int(data.get("expires_in", "3600"))
	_token_expires_at = int(Time.get_unix_time_from_system()) + expires_in

	is_logged_in = true
	_save_cached_session()
	auth_state_changed.emit(true)
	return true


func sign_out() -> void:
	_clear_cached_session()


# ---------------------------------------------------------
# FIRESTORE CLOUD STORAGE & SYNC
# ---------------------------------------------------------

func _get_firestore_document_url() -> String:
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/users/%s" % [project_id, user_id]


## Saves local progress data to Cloud Firestore.
func save_to_cloud(save_data: Dictionary) -> bool:
	if not is_logged_in or not await _ensure_valid_token(30):
		return false

	var now := int(Time.get_unix_time_from_system())
	var url := _get_firestore_document_url()
	var json_payload := JSON.stringify(save_data)
	var timestamp_val: int = int(save_data.get("timestamp", now))

	var firestore_body := {
		"fields": {
			"save_data": { "stringValue": json_payload },
			"timestamp": { "integerValue": str(timestamp_val) },
			"updated_at": { "integerValue": str(now) }
		}
	}
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _id_token
	]

	var response := await _send_http_request(url, HTTPClient.METHOD_PATCH, headers, JSON.stringify(firestore_body))
	var code: int = response[1]
	if code == 200:
		return true

	push_warning("FirebaseService: save_to_cloud returned code %d" % code)
	return false


## Loads user save data from Cloud Firestore. Returns empty dictionary if not found.
func load_from_cloud() -> Dictionary:
	if not is_logged_in or not await _ensure_valid_token(30):
		return {}

	var url := _get_firestore_document_url()
	var headers := ["Authorization: Bearer %s" % _id_token]

	var response := await _send_http_request(url, HTTPClient.METHOD_GET, headers)
	if response[1] != 200:
		return {}

	var body: PackedByteArray = response[3]
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {}

	var doc: Dictionary = json.data
	var fields: Dictionary = doc.get("fields", {})
	if not fields.has("save_data"):
		return {}

	var save_string: String = fields["save_data"].get("stringValue", "")
	if save_string.is_empty():
		return {}

	var save_json := JSON.new()
	if save_json.parse(save_string) != OK or not save_json.data is Dictionary:
		return {}

	return save_json.data as Dictionary


## Checks whether a save dictionary has meaningful player progression
## (checkpoints, collectibles, unlocked abilities, defeated bosses, etc.)
## rather than being a default or empty new game payload.
func has_save_progress(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	var cp: Dictionary = data.get("checkpoint", {}) if data.get("checkpoint", {}) is Dictionary else {}
	if not str(cp.get("active_id", "")).is_empty() or not (cp.get("activated_ids", []) as Array).is_empty():
		return true

	var col: Dictionary = data.get("collectibles", {}) if data.get("collectibles", {}) is Dictionary else {}
	if not (col.get("collected", []) as Array).is_empty():
		return true

	var ab: Dictionary = data.get("abilities", {}) if data.get("abilities", {}) is Dictionary else {}
	if not (ab.get("abilities", []) as Array).is_empty():
		return true

	var bo: Dictionary = data.get("bosses", {}) if data.get("bosses", {}) is Dictionary else {}
	if not (bo.get("bosses", {}) as Dictionary).is_empty():
		return true

	var fg: Dictionary = data.get("fragments", {}) if data.get("fragments", {}) is Dictionary else {}
	if not (fg.get("levels", {}) as Dictionary).is_empty():
		return true

	var sc: Dictionary = data.get("secrets", {}) if data.get("secrets", {}) is Dictionary else {}
	if not (sc.get("rewards", []) as Array).is_empty() or not (sc.get("walls", []) as Array).is_empty():
		return true

	var bq: Dictionary = data.get("blind_quest", {}) if data.get("blind_quest", {}) is Dictionary else {}
	if bool(bq.get("accepted", false)) or bool(bq.get("completed", false)):
		return true

	return false


## Full bidirectional synchronization:
## 1. Merges collectibles (never lost).
## 2. Compares progress content: progress is never overwritten by an empty new game.
## 3. Compares local timestamp vs remote timestamp when both have progress.
## 4. Keeps latest state and updates both local disk and cloud.
func sync_with_cloud() -> void:
	if not is_logged_in or _is_syncing:
		return

	_is_syncing = true
	sync_started.emit()

	var remote_data: Dictionary = await load_from_cloud()
	var local_exists := (SaveManager != null and SaveManager.has_save()) or (SaveService != null and SaveService.has_save())
	if local_exists and SaveManager != null and not FileAccess.file_exists(SaveManager.SAVE_PATH):
		SaveManager.save_game()

	# Ensure in-memory state is loaded from disk if local save exists
	if local_exists and SaveManager != null:
		SaveManager.load_game()

	var local_data: Dictionary = SaveManager.get_disk_save_data() if (SaveManager != null and local_exists) else {}

	var remote_has_prog := has_save_progress(remote_data)
	var local_has_prog := has_save_progress(local_data)

	if remote_data.is_empty():
		# Cloud is empty; if we have local progress, upload it
		if local_exists:
			await save_to_cloud(SaveManager.get_save_data())
		_is_syncing = false
		sync_completed.emit(true)
		return

	if not local_exists or local_data.is_empty():
		# Local is empty, but cloud has data; apply cloud save
		SaveManager.apply_save_data(remote_data, true)
		_is_syncing = false
		sync_completed.emit(true)
		return

	# Merge collectibles from remote into local state
	var remote_collectibles: Variant = remote_data.get("collectibles", {})
	if remote_collectibles is Dictionary:
		var remote_collected_ids: Variant = remote_collectibles.get("collected", [])
		if remote_collected_ids is Array and not (remote_collected_ids as Array).is_empty():
			SaveManager.merge_collectibles(remote_collected_ids as Array)

	var remote_ts: int = int(remote_data.get("timestamp", 0))
	var local_ts: int = int(local_data.get("timestamp", 0))

	var apply_remote := (remote_has_prog and not local_has_prog) or (remote_has_prog == local_has_prog and remote_ts > local_ts)
	if apply_remote:
		SaveManager.apply_save_data(remote_data, true)
	else:
		await save_to_cloud(SaveManager.get_save_data())

	_is_syncing = false
	sync_completed.emit(true)


# ---------------------------------------------------------
# PRIVATE HELPERS
# ---------------------------------------------------------

func _send_http_request(url: String, method: HTTPClient.Method, headers: PackedStringArray = [], body: String = "") -> Array:
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return [err, 0, PackedStringArray(), PackedByteArray()]
	var response: Array = await http.request_completed
	http.queue_free()
	return response


func _process_auth_response_body(body: PackedByteArray, default_email: String = "", default_name: String = "") -> bool:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return false

	var data: Dictionary = json.data
	_id_token = str(data.get("idToken", ""))
	_refresh_token = str(data.get("refreshToken", ""))
	user_id = str(data.get("localId", ""))
	user_email = str(data.get("email", default_email))
	user_name = str(data.get("displayName", default_name))
	user_photo_url = str(data.get("photoUrl", ""))
	var expires_in: int = int(data.get("expiresIn", "3600"))
	_token_expires_at = int(Time.get_unix_time_from_system()) + expires_in

	is_logged_in = true
	_save_cached_session()
	auth_state_changed.emit(true)
	sync_with_cloud()
	return true


func _ensure_valid_token(margin_seconds: int = 30) -> bool:
	var now := int(Time.get_unix_time_from_system())
	if now >= _token_expires_at - margin_seconds:
		return await refresh_id_token()
	return true


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) == OK and json.data is Dictionary:
		return json.data as Dictionary
	return {}
