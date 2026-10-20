class_name InventoryUI
extends CanvasLayer
## Tab screen: pockets, chest rig, backpack (and nested containers you open),
## quick slots, nearby pickups. Click an item to hold it, click a cell to
## put it there, R rotates while holding, right-click for actions, 1-6 while
## hovering assigns a quick slot, G drops. Built entirely in code and drawn
## at the internal resolution.

var kit: PlayerKit
var root: Control
var left: VBoxContainer
var right: VBoxContainer
var tooltip: Label
var tooltip_bg: ColorRect
var quick_row: HBoxContainer
var quick_boxes: Array[Button] = []
var context: PanelContainer
var context_box: VBoxContainer
var nearby_box: VBoxContainer
var weight_label: Label
var views: Array[GridView] = []
var open_containers: Array = []      # ItemInstance containers shown on the right

var held: ItemInstance = null
var held_rot: bool = false
var hover_item: ItemInstance = null
var hover_view: GridView = null
var hover_cell: Vector2i = Vector2i(-1, -1)
var is_open: bool = false
var nearby_provider: Callable = Callable()   # -> Array[ItemPickup]
var take_pickup: Callable = Callable()       # (pickup) -> void
var drop_item: Callable = Callable()         # (item) -> void
var open_health: Callable = Callable()       # (item) -> void

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
	dim.color = Color(0.03, 0.03, 0.05, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_background_input)
	root.add_child(dim)

	left = VBoxContainer.new()
	left.position = Vector2(6, 4)
	left.add_theme_constant_override("separation", 3)
	root.add_child(left)
	right = VBoxContainer.new()
	right.position = Vector2(300, 4)
	right.add_theme_constant_override("separation", 3)
	root.add_child(right)

	quick_row = HBoxContainer.new()
	quick_row.position = Vector2(6, 244)
	quick_row.add_theme_constant_override("separation", 2)
	root.add_child(quick_row)
	for i in Equipment.QUICK_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 20)
		b.text = str(i + 1)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_quick_pressed.bind(i))
		quick_row.add_child(b)
		quick_boxes.append(b)
	weight_label = Label.new()
	weight_label.position = Vector2(300, 250)
	root.add_child(weight_label)

	tooltip_bg = ColorRect.new()
	tooltip_bg.color = Color(0, 0, 0, 0.85)
	tooltip_bg.visible = false
	tooltip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tooltip_bg)
	tooltip = Label.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip.custom_minimum_size = Vector2(150, 0)
	tooltip_bg.add_child(tooltip)

	context = PanelContainer.new()
	context.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.1, 0.97)
	sb.border_color = Color(0.6, 0.6, 0.6)
	sb.set_border_width_all(1)
	context.add_theme_stylebox_override("panel", sb)
	context_box = VBoxContainer.new()
	context_box.add_theme_constant_override("separation", 0)
	context.add_child(context_box)
	root.add_child(context)
	kit.equipment.changed.connect(_refresh_quick)
	_rebuild()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	visible = true
	held = null
	_rebuild()


func close() -> void:
	is_open = false
	visible = false
	held = null
	context.visible = false
	closed.emit()


func _rebuild() -> void:
	for c in left.get_children():
		c.queue_free()
	for c in right.get_children():
		c.queue_free()
	views.clear()
	var eq := kit.equipment
	_section(left, "POCKETS")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	left.add_child(row)
	for g in eq.pockets:
		row.add_child(_view(g, ""))
	_container_section(left, "CHEST RIG", eq.rig, "rig")
	_container_section(left, "BACKPACK", eq.backpack, "backpack")
	for c in open_containers.duplicate():
		if not _still_in_kit(c):
			open_containers.erase(c)
	for c in open_containers:
		_container_section(right, c.display_name().to_upper(), c, "")
	_section(right, "NEARBY  (E takes)")
	nearby_box = VBoxContainer.new()
	right.add_child(nearby_box)
	_refresh_nearby()
	_refresh_quick()


func _still_in_kit(c: ItemInstance) -> bool:
	return kit.equipment.all_items().has(c)


func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.75, 0.85, 0.75)
	parent.add_child(l)


func _container_section(parent: Control, text: String, holder: ItemInstance, slot: String) -> void:
	var header := HBoxContainer.new()
	parent.add_child(header)
	var l := Label.new()
	l.text = text if holder == null else "%s: %s" % [text, holder.display_name()]
	l.modulate = Color(0.75, 0.85, 0.75)
	header.add_child(l)
	if holder == null:
		var hint := Label.new()
		hint.text = "  (right-click a %s to equip)" % ("rig" if slot == "rig" else "pack")
		hint.modulate = Color(0.5, 0.5, 0.5)
		parent.add_child(hint)
		return
	if slot != "":
		var b := Button.new()
		b.text = "take off"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_unequip.bind(slot))
		header.add_child(b)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 3)
	flow.add_theme_constant_override("v_separation", 3)
	parent.add_child(flow)
	for g in holder.grids:
		flow.add_child(_view(g, ""))


func _view(g: InventoryGrid, title: String) -> GridView:
	var v := GridView.new()
	v.setup(g, title)
	v.cell_clicked.connect(_on_cell_clicked)
	v.hovered.connect(_on_hovered)
	v.unhovered.connect(_on_unhovered)
	views.append(v)
	return v


func _unequip(slot: String) -> void:
	var it := kit.equipment.unequip(slot)
	if it != null and not kit.equipment.add_item(it):
		if drop_item.is_valid():
			drop_item.call(it)
			EventBus.toast.emit("%s dropped (no room)" % it.display_name(), 2.0)
	_rebuild()


# ---- interaction ----

func _on_hovered(view: GridView, item: ItemInstance, x: int, y: int) -> void:
	hover_view = view
	hover_cell = Vector2i(x, y)
	hover_item = item
	_update_highlight()
	_update_tooltip(view, item)


func _on_unhovered(view: GridView) -> void:
	if hover_view == view:
		hover_view = null
		hover_item = null
		hover_cell = Vector2i(-1, -1)
		view.highlight = Rect2i()
		view.queue_redraw()
		tooltip_bg.visible = false


func _update_highlight() -> void:
	for v in views:
		v.highlight = Rect2i()
		v.ghost_item = held
		v.queue_redraw()
	if held != null and hover_view != null and hover_cell.x >= 0:
		var s := held.base_size()
		if held_rot:
			s = Vector2i(s.y, s.x)
		var ignore := held if hover_view.grid == held.parent_grid else null
		hover_view.highlight = Rect2i(hover_cell, s)
		hover_view.highlight_ok = hover_view.grid.can_place(held, hover_cell.x, hover_cell.y, held_rot, ignore)
		hover_view.queue_redraw()


func _update_tooltip(view: GridView, item: ItemInstance) -> void:
	if item == null or held != null:
		tooltip_bg.visible = false
		return
	var lines: PackedStringArray = [item.display_name()]
	var s := item.base_size()
	lines.append("%dx%d  %.2f kg%s" % [s.x, s.y, item.weight(), ("  x%d" % item.count) if item.count > 1 else ""])
	if item.examined:
		if item.def.has("uses"):
			lines.append("uses: %d" % item.uses_left)
		if item.hp_pool > 0.0:
			lines.append("pool: %d" % int(item.hp_pool))
		if item.def.has("filter_seconds") and item.id == "breather":
			lines.append("filter: %ds" % int(kit.filter_seconds if kit.breather == item else float(item.def["filter_seconds"])))
		var d := item.description()
		if d != "":
			lines.append(d)
	else:
		lines.append("Right-click > Examine")
	tooltip.text = "\n".join(lines)
	tooltip_bg.visible = true
	var pos := view.global_position + Vector2(hover_cell) * view.cell + Vector2(view.cell + 4, 0)
	if pos.x > 320:
		pos.x = view.global_position.x - 160
	tooltip_bg.position = pos
	tooltip_bg.size = Vector2(156, 14 * lines.size() + 8)
	tooltip.position = Vector2(3, 2)
	tooltip.size = Vector2(150, 0)


func _on_cell_clicked(view: GridView, x: int, y: int, button: int) -> void:
	context.visible = false
	var item := view.grid.item_at(x, y)
	if button == MOUSE_BUTTON_LEFT:
		if held == null:
			if item != null:
				held = item
				held_rot = item.rotated
				tooltip_bg.visible = false
				_update_highlight()
			return
		# Place the held item here (or swap stacks / merge).
		var target := view.grid
		if item != null and item != held and held.stackable_with(item):
			var moved := mini(item.max_stack() - item.count, held.count)
			item.count += moved
			held.count -= moved
			if held.count <= 0:
				kit.equipment.remove_item(held)
			held = null
			_rebuild()
			return
		var ignore := held if target == held.parent_grid else null
		if target.can_place(held, x, y, held_rot, ignore):
			target.move(held, x, y, held_rot)
			held = null
			_rebuild()
		else:
			EventBus.toast.emit("Doesn't fit", 0.8)
	elif button == MOUSE_BUTTON_RIGHT:
		held = null
		_update_highlight()
		if item != null:
			_show_context(item, view.global_position + Vector2(x * view.cell + 6, y * view.cell + 6))


func _show_context(item: ItemInstance, at: Vector2) -> void:
	for c in context_box.get_children():
		c.queue_free()
	var actions: Array = []
	if not item.examined:
		actions.append(["Examine", func() -> void: kit.start_examine(item)])
	if item.category() == "medical" and item.examined:
		actions.append(["Use...", func() -> void:
			if open_health.is_valid():
				open_health.call(item)])
	if item.id == "breather":
		actions.append(["Toggle mask", func() -> void: kit.toggle_breather()])
	if item.def.has("slot"):
		var slot := str(item.def["slot"])
		if (slot == "rig" and kit.equipment.rig == null) or (slot == "backpack" and kit.equipment.backpack == null):
			actions.append(["Equip", func() -> void:
				kit.equipment.equip(item)
				_rebuild()])
	if item.is_container() and not open_containers.has(item) and item != kit.equipment.rig and item != kit.equipment.backpack:
		actions.append(["Open", func() -> void:
			open_containers.append(item)
			_rebuild()])
	if open_containers.has(item):
		actions.append(["Close", func() -> void:
			open_containers.erase(item)
			_rebuild()])
	if item.count > 1:
		actions.append(["Split half", func() -> void:
			var half := item.split(item.count / 2)
			if half != null and not kit.equipment.add_item(half):
				item.count += half.count
				EventBus.toast.emit("No room to split", 1.0)
			_rebuild()])
	actions.append(["Drop", func() -> void:
		kit.equipment.remove_item(item)
		if drop_item.is_valid():
			drop_item.call(item)
		_rebuild()])
	for a in actions:
		var b := Button.new()
		b.text = a[0]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var cb: Callable = a[1]
		b.pressed.connect(func() -> void:
			context.visible = false
			cb.call())
		context_box.add_child(b)
	context.position = at
	context.visible = true
	context.reset_size()
	if context.position.x + 90 > 480:
		context.position.x = 480 - 90


func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		context.visible = false
		if held != null and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			held = null
			_update_highlight()


func _on_quick_pressed(slot: int) -> void:
	if held != null:
		kit.equipment.set_quick(slot, held)
		held = null
		_update_highlight()
	elif hover_item != null:
		kit.equipment.set_quick(slot, hover_item)
	else:
		kit.equipment.set_quick(slot, null)
	_refresh_quick()


func _refresh_quick() -> void:
	for i in quick_boxes.size():
		var it := kit.equipment.quick_item(i)
		quick_boxes[i].text = "%d %s" % [i + 1, GridView._short_name(it) if it != null else "-"]
	if weight_label != null:
		var p := kit.penalties()
		weight_label.text = "weight %.1f kg%s" % [p["weight"], "  OVERWEIGHT" if bool(p["overweight"]) else ""]
	for v in views:
		v.queue_redraw()


func _refresh_nearby() -> void:
	if nearby_box == null:
		return
	for c in nearby_box.get_children():
		c.queue_free()
	if not nearby_provider.is_valid():
		return
	var list: Array = nearby_provider.call()
	if list.is_empty():
		var l := Label.new()
		l.text = "nothing here"
		l.modulate = Color(0.5, 0.5, 0.5)
		nearby_box.add_child(l)
		return
	for pk in list:
		var b := Button.new()
		b.text = "take %s%s" % [pk.item.display_name(), (" x%d" % pk.item.count) if pk.item.count > 1 else ""]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			if take_pickup.is_valid():
				take_pickup.call(pk)
			_rebuild())
		nearby_box.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("rotate_item") and held != null and held.can_rotate():
		held_rot = not held_rot
		_update_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item") and (held != null or hover_item != null):
		var it := held if held != null else hover_item
		held = null
		kit.equipment.remove_item(it)
		if drop_item.is_valid():
			drop_item.call(it)
		_rebuild()
		get_viewport().set_input_as_handled()
	else:
		for i in Equipment.QUICK_SLOTS:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				var it := held if held != null else hover_item
				if it != null:
					kit.equipment.set_quick(i, it)
					_refresh_quick()
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open and Engine.get_process_frames() % 30 == 0:
		_refresh_nearby()
