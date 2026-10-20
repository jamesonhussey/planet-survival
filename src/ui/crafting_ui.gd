class_name CraftingUI
extends CanvasLayer
## C screen: recipes from data/recipes.json, craftable ones first, with the
## inputs you have / need and the station requirement. Click to craft (a
## timed action on the kit).

var kit: PlayerKit
var recipes: Array = []
var stations_provider: Callable = Callable()   # -> Array[String]
var root: Control
var list_box: VBoxContainer
var detail: Label
var is_open: bool = false
var selected: Dictionary = {}
var status: Label

signal closed


func setup(player_kit: PlayerKit, recipe_list: Array) -> void:
	kit = player_kit
	recipes = recipe_list
	layer = 6
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = PixelFont.make_theme(1)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var title := Label.new()
	title.text = "CRAFTING"
	title.position = Vector2(8, 4)
	title.theme = PixelFont.make_theme(2)
	root.add_child(title)
	status = Label.new()
	status.position = Vector2(160, 10)
	status.modulate = Color(0.75, 0.85, 0.75)
	root.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 34)
	scroll.size = Vector2(230, 226)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 1)
	list_box.custom_minimum_size = Vector2(220, 0)
	scroll.add_child(list_box)
	detail = Label.new()
	detail.position = Vector2(250, 34)
	detail.size = Vector2(222, 220)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(detail)
	kit.equipment.changed.connect(func() -> void:
		if is_open:
			_refresh())
	kit.action_finished.connect(func(_k: String, _r: Dictionary) -> void:
		if is_open:
			_refresh())


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	visible = true
	_refresh()


func close() -> void:
	is_open = false
	visible = false
	closed.emit()


func _stations() -> Array:
	return stations_provider.call() if stations_provider.is_valid() else []


func _refresh() -> void:
	for c in list_box.get_children():
		c.queue_free()
	var stations := _stations()
	status.text = ("near: " + ", ".join(stations)) if not stations.is_empty() else "no station nearby (campfire unlocks cooking and firing)"
	for r in Crafting.sorted_recipes(recipes, kit.equipment, stations):
		var plan := Crafting.can_craft(r, kit.equipment, stations)
		var b := Button.new()
		var outs: PackedStringArray = []
		for o in r.get("out", []):
			outs.append("%s x%d" % [Data.item_def(str(o["id"])).get("name", o["id"]), int(o.get("count", 1))])
		b.text = ("  " if plan["ok"] else "x ") + ", ".join(outs)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		if not plan["ok"]:
			b.modulate = Color(0.6, 0.6, 0.6)
		b.pressed.connect(_on_pick.bind(r))
		list_box.add_child(b)
	_update_detail()


func _on_pick(r: Dictionary) -> void:
	if selected == r and not kit.busy():
		var plan := kit.start_craft(r, _stations())
		if plan["ok"]:
			EventBus.toast.emit("Crafting %s..." % str(r.get("name", r.get("id", ""))), 1.5)
	selected = r
	_update_detail()


func _update_detail() -> void:
	if selected.is_empty():
		detail.text = "Pick a recipe. Click it again to craft."
		return
	var lines: PackedStringArray = [str(selected.get("name", selected.get("id", ""))).to_upper(), ""]
	lines.append(str(selected.get("desc", "")))
	lines.append("")
	lines.append("Needs:")
	for inp in selected.get("in", []):
		var id := str(inp["id"])
		var have := kit.equipment.count_of(id)
		var need := int(inp.get("count", 1))
		lines.append("  %s %d/%d" % [Data.item_def(id).get("name", id), have, need])
	var station := str(selected.get("station", ""))
	if station != "":
		lines.append("  station: %s %s" % [station, "(here)" if _stations().has(station) else "(none nearby)"])
	lines.append("  time: %.0fs" % float(selected.get("time", 2.0)))
	lines.append("")
	var plan := Crafting.can_craft(selected, kit.equipment, _stations())
	if kit.busy():
		lines.append("...%s %d%%" % [kit.action["kind"], int(kit.action_progress() * 100)])
	elif plan["ok"]:
		lines.append("Click again to craft.")
	else:
		lines.append(str(plan["reason"]))
	detail.text = "\n".join(lines)


func _process(_delta: float) -> void:
	if is_open and kit.busy() and Engine.get_process_frames() % 10 == 0:
		_update_detail()
