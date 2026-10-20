class_name HUD
extends CanvasLayer
## In-game HUD built from code, drawn inside the low-res viewport so it shares
## the pixel grid: clock/day, oxygen + HP bars, quick slots, crosshair, aim
## text, action progress, toasts, hazard warning banner, debug overlay (F3)
## and the end-of-run overlay.

var theme_small: Theme
var theme_big: Theme
var root: Control
var clock_label: Label
var oxygen_fill: ColorRect
var hp_fill: ColorRect
var quick_row: HBoxContainer
var quick_boxes: Array[Control] = []
var quick_labels: Array[Label] = []
var oxygen_bar: ColorRect
var oxygen_label: Label
var toast_box: VBoxContainer
var debug_label: Label
var end_overlay: Control
var end_title: Label
var end_body: Label
var crosshair: Control
var aim_label: Label
var action_bg: ColorRect
var action_fill: ColorRect
var action_label: Label
var status_label: Label
var hunger_fill: ColorRect
var thirst_fill: ColorRect
var temp_fill: ColorRect
var stamina_fill: ColorRect
var temp_label: Label

var _toasts: Array = []  # [label, time_left]
var debug_provider: Callable = Callable()


func _ready() -> void:
	layer = 5
	theme_small = PixelFont.make_theme(1)
	theme_big = PixelFont.make_theme(2)
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_small
	add_child(root)

	clock_label = _label(root, Vector2(6, 4), "Day 1  08:00")
	status_label = _label(root, Vector2(6, 16), "")
	status_label.modulate = Color(1.0, 0.8, 0.6)

	oxygen_bar = _bar(root, Vector2(6, 246), Color(0.25, 0.75, 0.95))
	oxygen_fill = oxygen_bar.get_child(0)
	var hp_bar := _bar(root, Vector2(6, 256), Color(0.85, 0.25, 0.25))
	hp_fill = hp_bar.get_child(0)
	oxygen_label = _label(root, Vector2(80, 244), "O2")
	_label(root, Vector2(80, 254), "HP")
	# Survival needs: right side, stacked.
	var x0 := 390.0
	hunger_fill = _bar(root, Vector2(x0, 190), Color(0.85, 0.6, 0.2)).get_child(0)
	thirst_fill = _bar(root, Vector2(x0, 200), Color(0.3, 0.55, 0.95)).get_child(0)
	temp_fill = _bar(root, Vector2(x0, 210), Color(0.9, 0.9, 0.9)).get_child(0)
	stamina_fill = _bar(root, Vector2(x0, 220), Color(0.5, 0.85, 0.4)).get_child(0)
	for pair in [[190, "FOOD"], [200, "WATER"], [210, "TEMP"], [220, "STAM"]]:
		var l := _label(root, Vector2(x0 - 34, float(pair[0]) - 2.0), str(pair[1]))
		l.modulate = Color(0.8, 0.8, 0.8)
	temp_label = _label(root, Vector2(x0 + 72, 208), "37")

	quick_row = HBoxContainer.new()
	quick_row.position = Vector2(112, 246)
	quick_row.add_theme_constant_override("separation", 2)
	quick_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(quick_row)
	for i in Equipment.QUICK_SLOTS:
		var box := ColorRect.new()
		box.color = Color(0, 0, 0, 0.55)
		box.custom_minimum_size = Vector2(56, 18)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var num := Label.new()
		num.text = str(i + 1)
		num.position = Vector2(2, 0)
		num.modulate = Color(0.7, 0.7, 0.7)
		box.add_child(num)
		var l := Label.new()
		l.position = Vector2(10, 4)
		l.clip_text = true
		l.size = Vector2(46, 12)
		box.add_child(l)
		quick_row.add_child(box)
		quick_boxes.append(box)
		quick_labels.append(l)

	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_box.offset_left = -200
	toast_box.offset_right = 200
	toast_box.offset_top = -110
	toast_box.offset_bottom = -50
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)

	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	for r in [Rect2(-3, 0, 7, 1), Rect2(0, -3, 1, 7)]:
		var cr := ColorRect.new()
		cr.color = Color(1, 1, 1, 0.85)
		cr.position = r.position
		cr.size = r.size
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(cr)
	aim_label = _label(root, Vector2(0, 0), "")
	aim_label.set_anchors_preset(Control.PRESET_CENTER)
	aim_label.offset_left = 8
	aim_label.offset_top = 6
	aim_label.modulate = Color(1, 1, 1, 0.8)

	action_bg = ColorRect.new()
	action_bg.color = Color(0, 0, 0, 0.6)
	action_bg.set_anchors_preset(Control.PRESET_CENTER)
	action_bg.offset_left = -50
	action_bg.offset_right = 50
	action_bg.offset_top = 20
	action_bg.offset_bottom = 26
	action_bg.visible = false
	action_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(action_bg)
	action_fill = ColorRect.new()
	action_fill.color = Color(0.9, 0.9, 0.6)
	action_fill.position = Vector2(1, 1)
	action_fill.size = Vector2(0, 4)
	action_bg.add_child(action_fill)
	action_label = Label.new()
	action_label.position = Vector2(0, -12)
	action_label.size = Vector2(100, 10)
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_bg.add_child(action_label)

	debug_label = _label(root, Vector2(6, 28), "")
	debug_label.visible = false
	debug_label.modulate = Color(0.8, 1.0, 0.8)

	end_overlay = Control.new()
	end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_overlay.visible = false
	end_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_overlay.add_child(dim)
	end_title = Label.new()
	end_title.theme = theme_big
	end_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	end_title.offset_top = 90
	end_title.offset_left = -200
	end_title.offset_right = 200
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_overlay.add_child(end_title)
	end_body = Label.new()
	end_body.set_anchors_preset(Control.PRESET_CENTER_TOP)
	end_body.offset_top = 130
	end_body.offset_left = -200
	end_body.offset_right = 200
	end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_overlay.add_child(end_body)
	root.add_child(end_overlay)

	EventBus.toast.connect(show_toast)
	EventBus.vitals_changed.connect(_on_vitals)
	EventBus.hazard_phase_changed.connect(_on_hazard_phase)
	EventBus.run_ended.connect(_on_run_ended)


func _label(parent: Control, pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, pos: Vector2, color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.position = pos
	bg.size = Vector2(70, 7)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(1, 1)
	fill.size = Vector2(68, 5)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	parent.add_child(bg)
	return bg


func set_clock_text(t: String) -> void:
	clock_label.text = t


## items: Array of ItemInstance or null per quick slot.
func set_quick_slots(items: Array, index: int) -> void:
	for i in quick_boxes.size():
		var it: ItemInstance = items[i] if i < items.size() else null
		var text := ""
		if it != null:
			text = GridView._short_name(it)
			if it.count > 1:
				text += " %d" % it.count
			elif it.def.has("uses"):
				text += " (%d)" % it.uses_left
		quick_labels[i].text = text
		quick_boxes[i].color = Color(0.9, 0.85, 0.5, 0.45) if i == index else Color(0, 0, 0, 0.55)


func set_aim_text(t: String) -> void:
	aim_label.text = t


func set_status(t: String) -> void:
	status_label.text = t


func show_toast(text: String, seconds: float = 3.0) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(l)
	_toasts.append([l, seconds])
	while _toasts.size() > 4:
		var old: Array = _toasts.pop_front()
		(old[0] as Label).queue_free()


func _on_vitals(v: Dictionary) -> void:
	oxygen_fill.size.x = 68.0 * clampf(float(v.get("oxygen", 1.0)), 0.0, 1.0)
	hp_fill.size.x = 68.0 * clampf(float(v.get("hp", 100.0)) / maxf(float(v.get("max_hp", 100.0)), 1.0), 0.0, 1.0)
	oxygen_fill.color = Color(0.95, 0.3, 0.2) if bool(v.get("suffocating", false)) else Color(0.25, 0.75, 0.95)
	# The air meter only appears when the air is not fine.
	var show_o2 := float(v.get("oxygen", 1.0)) < 0.999 or bool(v.get("suffocating", false))
	oxygen_bar.visible = show_o2
	oxygen_label.visible = show_o2
	hunger_fill.size.x = 68.0 * clampf(float(v.get("hunger", 1.0)), 0.0, 1.0)
	thirst_fill.size.x = 68.0 * clampf(float(v.get("thirst", 1.0)), 0.0, 1.0)
	stamina_fill.size.x = 68.0 * clampf(float(v.get("stamina", 1.0)), 0.0, 1.0)
	var t := float(v.get("temperature", 37.0))
	temp_fill.size.x = 68.0 * clampf((t - 30.0) / 12.0, 0.0, 1.0)
	temp_fill.color = Color(0.4, 0.6, 1.0) if bool(v.get("cold", false)) else (Color(1.0, 0.45, 0.2) if bool(v.get("hot", false)) else Color(0.9, 0.9, 0.9))
	temp_label.text = "%.0f" % t
	var kind := str(v.get("action_kind", ""))
	action_bg.visible = kind != ""
	if kind != "":
		action_fill.size.x = 98.0 * clampf(float(v.get("action_progress", 0.0)), 0.0, 1.0)
		action_label.text = kind
	var bits: PackedStringArray = []
	if bool(v.get("overweight", false)):
		bits.append("OVERWEIGHT")
	if float(v.get("pain", 0.0)) >= 2.0:
		bits.append("PAIN")
	if bool(v.get("bleeding", false)):
		bits.append("BLEEDING")
	if bool(v.get("fracture", false)):
		bits.append("FRACTURE")
	if bool(v.get("breather", false)):
		bits.append("MASK %ds" % int(v.get("filter", 0.0)))
	if bool(v.get("starving", false)):
		bits.append("STARVING")
	if bool(v.get("dehydrated", false)):
		bits.append("DEHYDRATED")
	if bool(v.get("cold", false)):
		bits.append("COLD")
	if bool(v.get("hot", false)):
		bits.append("OVERHEATING")
	if bool(v.get("poisoned", false)):
		bits.append("POISONED")
	if bool(v.get("burning", false)):
		bits.append("BURNING")
	if int(v.get("swim", 0)) == 2:
		bits.append("DROWNING")
	elif int(v.get("swim", 0)) == 1:
		bits.append("SWIMMING")
	if bool(v.get("bitten", false)):
		bits.append("ROACHES")
	status_label.text = "  ".join(bits)


## No banners: the world itself is the warning (sounds, sky, animals, tremors).
func _on_hazard_phase(_id: String, _phase: int, _intensity: float) -> void:
	pass


func _on_run_ended(won: bool, day: int) -> void:
	end_overlay.visible = true
	end_title.text = "YOU MADE IT" if won else "YOU DIED"
	end_body.text = ("Survived %d days.  Esc returns to orbit." % day) if won else ("Day %d.  R: try again   Esc: back to orbit" % day)


func set_death_cause(cause: String) -> void:
	if cause != "":
		end_body.text = "Cause: %s.  %s" % [cause.replace("_", " "), end_body.text]


func set_debug_visible(v: bool) -> void:
	debug_label.visible = v


func _process(delta: float) -> void:
	for i in range(_toasts.size() - 1, -1, -1):
		_toasts[i][1] -= delta
		var l: Label = _toasts[i][0]
		if _toasts[i][1] <= 0.0:
			l.queue_free()
			_toasts.remove_at(i)
		elif _toasts[i][1] < 0.6:
			l.modulate.a = _toasts[i][1] / 0.6
	if debug_label.visible and debug_provider.is_valid():
		debug_label.text = str(debug_provider.call())
