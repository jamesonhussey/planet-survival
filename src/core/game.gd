extends Node
## Game flow autoload ("Game"). State machine: BOOT -> PLANET_SELECT -> RUN -> END.
## Parses command line user args (after "--"):
##   --smoke              boot headless, run --frames frames, quit (CI)
##   --screenshot         like --smoke but saves screenshots/ before quitting
##   --planet=04          planet id to start on directly (skips planet select)
##   --menu               force the planet select screen (screenshots)
##   --mode=short         game mode id (default standard)
##   --frames=240         frame budget for --smoke/--screenshot
##   --seed=12345         world seed
##   --continue           load the save slot if one exists
##   --host[=port]        host a co-op game (with --planet/--mode/--seed)
##   --join=ip[:port]     join a co-op game
##   --name=Name          player name shown to others

enum State { BOOT, PLANET_SELECT, RUN, END }

var state: State = State.BOOT
var args: Dictionary = {}
var root_node: Node = null
var run_root: Node = null
var select_root: Node = null
var smoke_frames_left: int = -1
var screenshot_mode: bool = false


func boot(root: Node) -> void:
	root_node = root
	args = _parse_args(OS.get_cmdline_user_args())
	InputSetup.install()
	Data.load_all()
	var smoke: bool = args.has("smoke") or args.has("screenshot")
	screenshot_mode = args.has("screenshot")
	if smoke:
		smoke_frames_left = int(args.get("frames", "240"))
	if args.has("fps"):
		Engine.max_fps = int(args["fps"])
	if args.has("name"):
		Net.my_name = str(args["name"])
	Net.joined.connect(_on_net_joined)
	Net.join_failed.connect(func(reason: String) -> void:
		EventBus.toast.emit("Join failed: %s" % reason, 4.0)
		show_planet_select())
	Net.disconnected_from_host.connect(func() -> void:
		EventBus.toast.emit("Disconnected from host.", 4.0)
		show_planet_select())
	if args.has("join"):
		var parts := str(args["join"]).split(":")
		var port := int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT
		join_game(parts[0], port)
		return
	if args.has("host"):
		var port := int(args["host"]) if str(args["host"]) != "1" else Net.DEFAULT_PORT
		host_game(str(args.get("planet", "04")), str(args.get("mode", "standard")), int(args.get("seed", "1337")), port)
		return
	if args.has("continue") and SaveSystem.exists():
		load_save()
		return
	var planet_id: String = str(args.get("planet", ""))
	if planet_id == "" and smoke and not args.has("menu"):
		planet_id = "04"
	if planet_id != "":
		start_run(planet_id, str(args.get("mode", "standard")), int(args.get("seed", "1337")))
	else:
		show_planet_select()


func show_planet_select() -> void:
	state = State.PLANET_SELECT
	_clear_run()
	_clear_select()
	var SelectScene := load("res://src/ui/planet_select.gd") as GDScript
	select_root = SelectScene.new()
	select_root.name = "PlanetSelect"
	root_node.add_child(select_root)
	select_root.set_save_available(SaveSystem.exists(), SaveSystem.summary())
	select_root.start_requested.connect(func(planet_id: String, mode_id: String) -> void:
		SaveSystem.delete()
		start_run(planet_id, mode_id, randi() % 1000000))
	select_root.continue_requested.connect(load_save)
	select_root.host_requested.connect(func(planet_id: String, mode_id: String) -> void:
		SaveSystem.delete()
		host_game(planet_id, mode_id, randi() % 1000000))
	select_root.join_requested.connect(func(address: String) -> void:
		var parts := address.split(":")
		join_game(parts[0], int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT))


func host_game(planet_id: String, mode_id: String, seed: int, port: int = Net.DEFAULT_PORT) -> void:
	var err := Net.host({"planet_id": planet_id, "mode_id": mode_id, "seed": seed}, port)
	if err != OK:
		EventBus.toast.emit(Net.last_error, 4.0)
		return
	start_run(planet_id, mode_id, seed)


var connecting_root: Node = null


func join_game(address: String, port: int) -> void:
	_clear_run()
	_clear_select()
	var err := Net.join(address, port)
	if err != OK:
		EventBus.toast.emit(Net.last_error, 4.0)
		show_planet_select()
		return
	state = State.PLANET_SELECT
	connecting_root = CanvasLayer.new()
	var l := Label.new()
	l.theme = PixelFont.make_theme(2)
	l.text = "CONNECTING TO %s:%d ..." % [address, port]
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(300, 320)
	connecting_root.add_child(l)
	root_node.add_child(connecting_root)


func _on_net_joined(config: Dictionary) -> void:
	if connecting_root != null:
		connecting_root.queue_free()
		connecting_root = null
	start_run(str(config.get("planet_id", "04")), str(config.get("mode_id", "standard")), int(config.get("seed", 1337)))


func load_save() -> void:
	var meta := SaveSystem.read_meta()
	if meta.is_empty():
		show_planet_select()
		return
	start_run(str(meta.get("planet_id", "04")), str(meta.get("mode_id", "standard")), int(meta.get("seed", 1337)), meta)


func start_run(planet_id: String, mode_id: String, seed: int, save_data: Dictionary = {}) -> void:
	_clear_run()
	_clear_select()
	state = State.RUN
	var RunScene := load("res://src/core/run.gd") as GDScript
	run_root = RunScene.new()
	run_root.name = "Run"
	run_root.set("planet_id", planet_id)
	run_root.set("mode_id", mode_id)
	run_root.set("world_seed", seed)
	run_root.set("save_data", save_data)
	root_node.add_child(run_root)
	EventBus.run_started.emit(planet_id, mode_id)
	# Smoke budgets count frames *inside* the run (connecting/menus excluded).
	if smoke_frames_left >= 0:
		smoke_frames_left = int(args.get("frames", "240"))
	if Net.is_online() and not Net.is_server():
		Net.ready_in_run.rpc_id(1)


func end_run(won: bool, day: int) -> void:
	state = State.END
	# Permadeath (and a finished run) consumes the save slot.
	SaveSystem.delete()
	EventBus.run_ended.emit(won, day)


func return_to_orbit() -> void:
	Net.leave()
	show_planet_select()


func _clear_run() -> void:
	if run_root != null and is_instance_valid(run_root):
		run_root.queue_free()
	run_root = null


func _clear_select() -> void:
	if select_root != null and is_instance_valid(select_root):
		select_root.queue_free()
	select_root = null


func _process(_delta: float) -> void:
	if smoke_frames_left < 0:
		return
	smoke_frames_left -= 1
	if smoke_frames_left == 0:
		if screenshot_mode:
			_save_screenshot()
		print("[smoke] finished OK (state=%s)" % State.keys()[state])
		_clear_run()
		_clear_select()
		get_tree().quit(0)


func _save_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_warning("screenshot: no image (headless?)")
		return
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	if not FileAccess.file_exists("res://screenshots/.gdignore"):
		var f := FileAccess.open("res://screenshots/.gdignore", FileAccess.WRITE)
		if f != null:
			f.close()
	var path := "res://screenshots/%s_%s.png" % [str(args.get("planet", "04")), Time.get_datetime_string_from_system().replace(":", "-")]
	var err := img.save_png(path)
	print("[screenshot] %s (%s)" % [path, error_string(err)])


static func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--"):
			var body := a.trim_prefix("--")
			var eq := body.find("=")
			if eq >= 0:
				out[body.substr(0, eq)] = body.substr(eq + 1)
			else:
				out[body] = "1"
	return out
