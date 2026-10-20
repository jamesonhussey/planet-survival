extends Node
## Game flow autoload ("Game"). State machine: BOOT -> PLANET_SELECT -> RUN -> END.
## Parses command line user args (after "--"):
##   --smoke              boot headless, run --frames frames, quit (CI)
##   --screenshot         like --smoke but saves screenshots/ before quitting
##   --planet=04          planet id to start on directly (skips planet select)
##   --mode=short         game mode id (default from data/modes.json)
##   --frames=240         frame budget for --smoke/--screenshot
##   --seed=12345         world seed

enum State { BOOT, PLANET_SELECT, RUN, END }

var state: State = State.BOOT
var args: Dictionary = {}
var root_node: Node = null
var run_root: Node = null
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
	var planet_id: String = str(args.get("planet", ""))
	if planet_id == "" and smoke:
		planet_id = "04"
	if planet_id != "":
		start_run(planet_id, str(args.get("mode", "standard")), int(args.get("seed", "1337")))
	else:
		show_planet_select()


func show_planet_select() -> void:
	state = State.PLANET_SELECT
	_clear_run()
	# Milestone 3 builds the starfield select screen. Until then, start on 04.
	start_run("04", "standard", 1337)


func start_run(planet_id: String, mode_id: String, seed: int) -> void:
	_clear_run()
	state = State.RUN
	var RunScene := load("res://src/core/run.gd") as GDScript
	run_root = RunScene.new()
	run_root.name = "Run"
	run_root.set("planet_id", planet_id)
	run_root.set("mode_id", mode_id)
	run_root.set("world_seed", seed)
	root_node.add_child(run_root)
	EventBus.run_started.emit(planet_id, mode_id)


func end_run(won: bool, day: int) -> void:
	state = State.END
	EventBus.run_ended.emit(won, day)


func _clear_run() -> void:
	if run_root != null and is_instance_valid(run_root):
		run_root.queue_free()
	run_root = null


func _process(_delta: float) -> void:
	if smoke_frames_left < 0:
		return
	smoke_frames_left -= 1
	if smoke_frames_left == 0:
		if screenshot_mode:
			_save_screenshot()
		print("[smoke] finished OK (state=%s)" % State.keys()[state])
		get_tree().quit(0)


func _save_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_warning("screenshot: no image (headless?)")
		return
	DirAccess.make_dir_recursive_absolute("res://screenshots")
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
