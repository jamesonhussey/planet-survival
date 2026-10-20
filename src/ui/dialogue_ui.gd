class_name DialogueUI
extends CanvasLayer
## Talking to a villager: their lines (greetings, warnings, lore), trades
## (give X, get Y, from your kit) and one task at a time per player. Tasks
## are tracked per player in `tasks` (persisted by the run).

var kit: PlayerKit
var root: Control
var name_label: Label
var text_label: Label
var buttons: VBoxContainer
var is_open: bool = false
var villager: Villager = null
var def: Dictionary = {}
var tasks: Dictionary = {}   # npc kind -> {"active": task id, "done": [ids]}
var _line_i: int = 0
var give_items: Callable = Callable()   # (id, count) -> void  (rewards into the kit or the ground)

signal closed


func setup(player_kit: PlayerKit) -> void:
	kit = player_kit
	layer = 6
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = PixelFont.make_theme(1)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.08, 0.1, 0.95)
	panel.position = Vector2(40, 40)
	panel.size = Vector2(400, 190)
	root.add_child(panel)
	name_label = Label.new()
	name_label.theme = PixelFont.make_theme(2)
	name_label.position = Vector2(50, 46)
	root.add_child(name_label)
	text_label = Label.new()
	text_label.position = Vector2(50, 74)
	text_label.size = Vector2(240, 150)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(text_label)
	buttons = VBoxContainer.new()
	buttons.position = Vector2(300, 74)
	buttons.add_theme_constant_override("separation", 2)
	root.add_child(buttons)


func open(v: Villager, npc_def: Dictionary) -> void:
	villager = v
	def = npc_def
	is_open = true
	visible = true
	name_label.text = v.display_name
	var greetings: Array = def.get("greetings", ["..."])
	_say(str(greetings[v.rng.randi_range(0, greetings.size() - 1)]))
	_menu()


func close() -> void:
	is_open = false
	visible = false
	villager = null
	closed.emit()


func _say(t: String) -> void:
	text_label.text = t


func _clear_buttons() -> void:
	for c in buttons.get_children():
		c.queue_free()


func _button(text: String, cb: Callable, enabled: bool = true) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.pressed.connect(cb)
	buttons.add_child(b)


func _menu() -> void:
	_clear_buttons()
	_button("What should I know?", func() -> void:
		var w: Array = def.get("warnings", [])
		if not w.is_empty():
			_say(str(w[_line_i % w.size()]))
			_line_i += 1)
	_button("Tell me about this place", func() -> void:
		var l: Array = def.get("lore", [])
		if not l.is_empty():
			_say(str(l[_line_i % l.size()]))
			_line_i += 1)
	_button("Trade", _trade_menu)
	_button("Work", _task_menu)
	_button("Leave", close)


func _trade_menu() -> void:
	_clear_buttons()
	_say("What do you have?")
	for t in def.get("trades", []):
		var give: Dictionary = t["give"]
		var get: Dictionary = t["get"]
		var have := kit.equipment.count_of(str(give["id"]))
		var label := "%d %s -> %d %s  (%d)" % [int(give["count"]), Data.item_def(str(give["id"])).get("name", give["id"]), int(get["count"]), Data.item_def(str(get["id"])).get("name", get["id"]), have]
		_button(label, func() -> void:
			if kit.equipment.count_of(str(give["id"])) < int(give["count"]):
				_say("You don't have that.")
				return
			kit.equipment.consume(str(give["id"]), int(give["count"]))
			if give_items.is_valid():
				give_items.call(str(get["id"]), int(get["count"]))
			_say("Done. Anything else?")
			_trade_menu(), have >= int(give["count"]))
	_button("Back", _menu)


func _task_state() -> Dictionary:
	var kind := villager.npc_kind
	if not tasks.has(kind):
		tasks[kind] = {"active": "", "done": []}
	return tasks[kind]


func _task_menu() -> void:
	_clear_buttons()
	var st := _task_state()
	var list: Array = def.get("tasks", [])
	var active := str(st.get("active", ""))
	if active != "":
		var task: Dictionary = {}
		for t in list:
			if str(t["id"]) == active:
				task = t
		if task.is_empty():
			st["active"] = ""
			_task_menu()
			return
		var need: Dictionary = task["need"]
		var have := kit.equipment.count_of(str(need["id"]))
		_say("%s  (%d/%d)" % [str(task["text"]), have, int(need["count"])])
		_button("Turn in", func() -> void:
			kit.equipment.consume(str(need["id"]), int(need["count"]))
			var reward: Dictionary = task["reward"]
			if give_items.is_valid():
				give_items.call(str(reward["id"]), int(reward["count"]))
			(st["done"] as Array).append(active)
			st["active"] = ""
			_say(str(task.get("done", "Thank you.")))
			_menu(), have >= int(need["count"]))
		_button("Back", _menu)
		return
	var next: Dictionary = {}
	for t in list:
		if not (st["done"] as Array).has(str(t["id"])):
			next = t
			break
	if next.is_empty():
		_say("Nothing more to do. You've done enough.")
	else:
		_say(str(next["text"]))
		_button("Accept", func() -> void:
			st["active"] = str(next["id"])
			_say("Good. Come back when you have it.")
			_menu())
	_button("Back", _menu)
