extends SceneTree
## Minimal headless unit test runner.
##   tools/godot.sh --headless --path . -s res://tests/run_tests.gd -- [--filter=substr]
## Discovers res://tests/unit/test_*.gd, instantiates each (must extend
## TestCase), runs every test_* method and exits 1 if anything failed.

const UNIT_DIR := "res://tests/unit"

var _started := false
var _finished := false


func _process(_delta: float) -> bool:
	# A runtime error inside _initialize aborts it before quit() runs, which
	# would leave the process hanging. Returning true here ends the main loop.
	if _started and not _finished:
		printerr("test runner aborted by a script error (see above)")
		quit(1)
		return true
	return false


func _initialize() -> void:
	_started = true
	# Autoloads exist but Game.boot() never ran: load the data files once so
	# tests can use Data.materials / Data.make_item().
	if root.has_node("Data"):
		var data: Node = root.get_node("Data")
		if not data.get("loaded"):
			data.call("load_all")
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
	var files := _discover(UNIT_DIR)
	files.sort()
	var total := 0
	var failed := 0
	var failures: PackedStringArray = []
	var started := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failures.append("%s: failed to load/compile" % path)
			failed += 1
			continue
		var case: Variant = script.new()
		if not (case is TestCase):
			failures.append("%s: does not extend TestCase" % path)
			failed += 1
			continue
		for m in case.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (name.contains(filter) or path.contains(filter)):
				continue
			total += 1
			case._failures.clear()
			case._current = "%s::%s" % [path.get_file(), name]
			case.before_each()
			case.call(name)
			case.after_each()
			if case._failures.size() > 0:
				failed += 1
				for f in case._failures:
					failures.append(f)
				print("  FAIL %s" % case._current)
			else:
				print("  ok   %s" % case._current)
	var ms := Time.get_ticks_msec() - started
	print("")
	if failures.size() > 0:
		print("Failures:")
		for f in failures:
			print("  - %s" % f)
	print("%d tests, %d failed, %d files, %d ms" % [total, failed, files.size(), ms])
	_finished = true
	quit(1 if failed > 0 or total == 0 else 0)


func _discover(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if not f.begins_with("."):
				out.append_array(_discover(dir_path.path_join(f)))
		elif f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	return out
