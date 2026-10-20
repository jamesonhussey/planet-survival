extends Node
## Autoload "SteamBridge": the one place that talks to Steam. Wraps the
## GodotSteam GDExtension (`Steam` singleton) when it is present and does
## nothing harmful when it is not, so dev builds never need Steam running.
##   - achievements: data/achievements.json, unlocked through
##     EventBus.achievement(id); also remembered locally in user://achievements.json
##   - cloud saves: `cloud_write/cloud_read` mirror a save file to Steam Remote
##     Storage (Steam Auto-Cloud also works with the user:// path; see docs/RELEASE.md)
##   - lobbies: `create_lobby/join_lobby` are stubs until SteamMultiplayerPeer
##     is wired to Net (ENet stays the dev transport)

var steam: Object = null           # the GodotSteam singleton, or null
var app_id: int = 480              # Spacewar test app until a real id exists
var defs: Dictionary = {}          # id -> achievement def
var unlocked: Dictionary = {}      # id -> true (local mirror)
var _run_planet: String = ""
var _run_mode: String = ""
var _nights: int = 0

signal unlocked_achievement(id: String, def: Dictionary)


func _ready() -> void:
	var j: Dictionary = Data.load_json("res://data/achievements.json")
	for a in j.get("achievements", []):
		defs[str(a["id"])] = a
	_load_local()
	if Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")
		var r: Variant = steam.call("steamInitEx", app_id, true)
		if r is Dictionary and int((r as Dictionary).get("status", 1)) != 0:
			push_warning("[steam] init failed: %s" % str(r))
			steam = null
		else:
			print("[steam] initialised (app %d)" % app_id)
			steam.call("requestCurrentStats")
	else:
		print("[steam] GodotSteam not present; achievements stay local")
	EventBus.achievement.connect(unlock)
	EventBus.run_started.connect(func(p: String, m: String) -> void:
		_run_planet = p
		_run_mode = m
		_nights = 0)
	EventBus.day_changed.connect(func(day: int) -> void:
		if day >= 2 and _run_planet != "":
			unlock("night_%s" % _run_planet)
		if day >= 8:
			unlock("week"))
	EventBus.run_ended.connect(func(won: bool, _day: int) -> void:
		if won and _run_planet != "":
			unlock("win_%s" % _run_planet)
			if _run_mode == "long_haul":
				unlock("long_haul"))


func _process(_dt: float) -> void:
	if steam != null:
		steam.call("run_callbacks")


func available() -> bool:
	return steam != null


func unlock(id: String) -> void:
	if not defs.has(id) or unlocked.has(id):
		return
	unlocked[id] = true
	_save_local()
	if steam != null:
		steam.call("setAchievement", id)
		steam.call("storeStats")
	var d: Dictionary = defs[id]
	EventBus.toast.emit("Achievement: %s" % str(d.get("name", id)), 3.0)
	unlocked_achievement.emit(id, d)


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


# ---- cloud ----

func cloud_write(name: String, bytes: PackedByteArray) -> bool:
	if steam == null:
		return false
	return bool(steam.call("fileWrite", name, bytes))


func cloud_read(name: String) -> PackedByteArray:
	if steam == null or not bool(steam.call("fileExists", name)):
		return PackedByteArray()
	var r: Variant = steam.call("fileRead", name, int(steam.call("getFileSize", name)))
	if r is Dictionary:
		return (r as Dictionary).get("buf", PackedByteArray())
	return PackedByteArray()


# ---- lobbies (M7 scaffold; transport lands with SteamMultiplayerPeer) ----

func create_lobby(max_players: int = 8) -> void:
	if steam != null:
		steam.call("createLobby", 1, max_players)   # 1 = friends only


func join_lobby(lobby_id: int) -> void:
	if steam != null:
		steam.call("joinLobby", lobby_id)


# ---- local mirror ----

func _load_local() -> void:
	var f := FileAccess.open("user://achievements.json", FileAccess.READ)
	if f == null:
		return
	var v: Variant = JSON.parse_string(f.get_as_text())
	if v is Dictionary:
		for k in (v as Dictionary).get("unlocked", []):
			unlocked[str(k)] = true


func _save_local() -> void:
	var f := FileAccess.open("user://achievements.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"unlocked": unlocked.keys()}))
