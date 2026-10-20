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
var warning_label: Label
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

var _toasts: Array = []  # [label, time_left]
var debug_provider: Callable = Callable()
var _warning_phase: int = 0
var _warning_time: float = 0.0


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

	var oxygen_bar := _bar(root, Vector2(6, 246), Color(0.25, 0.75, 0.95))
	oxygen_fill = oxygen_bar.get_child(0)
	var hp_bar := _bar(root, Vector2(6, 256), Color(0.85, 0.25, 0.25))
	hp_fill = hp_bar.get_child(0)
	_label(root, Vector2(80, 244), "O2")
	_label(root, Vector2(80, 254), "HP")

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

	warning_label = _label(root, Vector2(0, 30), "")
	warning_label.theme = theme_big
	warning_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.offset_top = 28
	warning_label.offset_bottom = 60
	warning_label.modulate = Color(1.0, 0.85, 0.3)

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
	status_label.text = "  ".join(bits)


func _on_hazard_phase(_id: String, phase: int, _intensity: float) -> void:
	_warning_phase = phase
	_warning_time = 0.0
	match phase:
		HazardModule.Phase.WARNING: warning_label.text = "SOMETHING IS WRONG"
		HazardModule.Phase.ACTIVE: warning_label.text = "GET TO HIGH GROUND"
		HazardModule.Phase.RECOVERY: warning_label.text = "THE AIR IS CLEARING"
		_: warning_label.text = ""


func _on_run_ended(won: bool, day: int) -> void:
	end_overlay.visible = true
	end_title.text = "YOU MADE IT" if won else "YOU DIED"
	end_body.text = ("Survived %d days." % day) if won else ("Day %d. Press R to try again." % day)
	warning_label.text = ""


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
	if _warning_phase == HazardModule.Phase.WARNING or _warning_phase == HazardModule.Phase.ACTIVE:
		_warning_time += delta
		warning_label.visible = fmod(_warning_time, 1.0) < 0.7
	else:
		warning_label.visible = true
	if debug_label.visible and debug_provider.is_valid():
		debug_label.text = str(debug_provider.call())
