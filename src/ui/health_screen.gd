class_name HealthScreen
extends CanvasLayer
## H screen: body silhouette with per-part HP, status letters, pain and
## penalties, and the medical items in your kit. Pick a med, click a part.

const PART_RECTS := {
	"head": Rect2(26, 6, 20, 18),
	"thorax": Rect2(20, 26, 32, 28),
	"stomach": Rect2(22, 56, 28, 16),
	"left_arm": Rect2(2, 28, 14, 42),
	"right_arm": Rect2(56, 28, 14, 42),
	"left_leg": Rect2(20, 74, 14, 48),
	"right_leg": Rect2(38, 74, 14, 48),
}
const PART_NAMES := {"head": "Head", "thorax": "Thorax", "stomach": "Stomach", "left_arm": "L. Arm", "right_arm": "R. Arm", "left_leg": "L. Leg", "right_leg": "R. Leg"}
const EFFECT_LETTERS := {"light_bleed": "b", "heavy_bleed": "B", "fracture": "F", "burn": "S", "pain": "P", "painkillers": "+", "suffocation": "O", "dehydration": "D", "poison": "X"}

var kit: PlayerKit
var root: Control
var body_view: Control
var info: Label
var med_box: VBoxContainer
var selected_med: ItemInstance = null
var hover_part: String = ""
var is_open: bool = false
var status: Label

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
	root.add_child(dim)
	var title := Label.new()
	title.text = "HEALTH"
	title.position = Vector2(8, 4)
	title.theme = PixelFont.make_theme(2)
	root.add_child(title)

	body_view = Control.new()
	body_view.position = Vector2(30, 40)
	body_view.size = Vector2(72, 126)
	body_view.mouse_filter = Control.MOUSE_FILTER_STOP
	body_view.draw.connect(_draw_body)
	body_view.gui_input.connect(_on_body_input)
	root.add_child(body_view)

	info = Label.new()
	info.position = Vector2(120, 40)
	info.size = Vector2(170, 200)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)

	var med_title := Label.new()
	med_title.text = "MEDICAL  (pick one, click a part)"
	med_title.position = Vector2(300, 40)
	med_title.modulate = Color(0.75, 0.85, 0.75)
	root.add_child(med_title)
	med_box = VBoxContainer.new()
	med_box.position = Vector2(300, 54)
	med_box.add_theme_constant_override("separation", 1)
	root.add_child(med_box)

	status = Label.new()
	status.position = Vector2(8, 252)
	root.add_child(status)
	kit.equipment.changed.connect(_refresh)
	kit.body.part_changed.connect(_on_body_changed.unbind(3))
	kit.body.effect_added.connect(_on_body_changed.unbind(2))
	kit.body.effect_removed.connect(_on_body_changed.unbind(2))
	kit.action_finished.connect(_on_body_changed.unbind(2))


func _on_body_changed() -> void:
	if is_open:
		_update_info()
		body_view.queue_redraw()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open(with_med: ItemInstance = null) -> void:
	is_open = true
	visible = true
	selected_med = with_med
	_refresh()


func close() -> void:
	is_open = false
	visible = false
	closed.emit()


func _refresh() -> void:
	if not is_open:
		return
	for c in med_box.get_children():
		c.queue_free()
	var meds: Array = []
	for it in kit.equipment.all_items():
		if it.category() == "medical":
			meds.append(it)
	if meds.is_empty():
		var l := Label.new()
		l.text = "no medical items"
		l.modulate = Color(0.5, 0.5, 0.5)
		med_box.add_child(l)
	for it: ItemInstance in meds:
		var b := Button.new()
		var extra := ""
		if it.def.has("uses"):
			extra = " (%d)" % it.uses_left
		elif it.hp_pool > 0.0:
			extra = " (%d)" % int(it.hp_pool)
		b.text = ("> " if it == selected_med else "  ") + it.display_name() + extra
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			if not it.examined:
				kit.start_examine(it)
				EventBus.toast.emit("Examining...", 1.0)
				return
			selected_med = it
			_refresh())
		med_box.add_child(b)
	_update_info()
	body_view.queue_redraw()


func _update_info() -> void:
	var b := kit.body
	var lines: PackedStringArray = []
	lines.append("Total %d / %d" % [int(b.total_hp()), int(b.total_max())])
	var p := kit.penalties()
	lines.append("Pain %.1f   Move x%.2f   Carry x%.2f" % [p["pain"], p["move_speed"], p["carry"]])
	lines.append("Weight %.1f kg" % p["weight"])
	lines.append("")
	for part in BodyHealth.PARTS:
		var fx := ""
		for e in b.effects_on(part):
			fx += EFFECT_LETTERS.get(e["type"], "?")
		lines.append("%-8s %3d/%3d  %s%s" % [PART_NAMES[part], int(b.hp[part]), int(b.max_hp[part]), fx, "  DESTROYED" if b.is_blacked(part) else ""])
	lines.append("")
	lines.append("b light bleed  B heavy bleed  F fracture")
	lines.append("S burn  P pain  + painkillers  O suffocating")
	if selected_med != null:
		lines.append("")
		lines.append("Selected: %s. Click a body part." % selected_med.display_name())
	if kit.busy():
		lines.append("...%s %d%%" % [kit.action["kind"], int(kit.action_progress() * 100)])
	info.text = "\n".join(lines)


func _draw_body() -> void:
	var b := kit.body
	var font := PixelFont.get_font(1)
	for part in BodyHealth.PARTS:
		var r: Rect2 = PART_RECTS[part]
		var frac := float(b.hp[part]) / maxf(float(b.max_hp[part]), 1.0)
		var col: Color
		if b.is_blacked(part):
			col = Color(0.1, 0.1, 0.1)
		else:
			col = Color(0.85, 0.25, 0.2).lerp(Color(0.3, 0.75, 0.35), frac)
		body_view.draw_rect(r, col)
		var border := Color.WHITE if part == hover_part else Color(0, 0, 0, 0.8)
		body_view.draw_rect(r, border, false, 1.0)
		# hp as a filled bar inside the part
		var bar := Rect2(r.position + Vector2(1, r.size.y - 3), Vector2((r.size.x - 2) * frac, 2))
		body_view.draw_rect(bar, Color(1, 1, 1, 0.7))
		var letters := ""
		for e in b.effects_on(part):
			letters += EFFECT_LETTERS.get(e["type"], "?")
		if letters != "":
			body_view.draw_string(font, r.position + Vector2(2, 9), letters, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.9, 0.5))


func _part_at(p: Vector2) -> String:
	for part in BodyHealth.PARTS:
		if (PART_RECTS[part] as Rect2).has_point(p):
			return part
	return ""


func _on_body_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hp := _part_at((event as InputEventMouseMotion).position)
		if hp != hover_part:
			hover_part = hp
			body_view.queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var part := _part_at((event as InputEventMouseButton).position)
		if part == "":
			return
		if selected_med == null:
			EventBus.toast.emit("Pick a medical item first", 1.2)
			return
		var plan := kit.start_med(selected_med, part)
		if plan["ok"]:
			EventBus.toast.emit("Using %s on %s (%.0fs)" % [selected_med.display_name(), PART_NAMES[part], plan["use_time"]], 2.0)
		else:
			EventBus.toast.emit(str(plan["reason"]), 1.5)
		_refresh()


func _process(_delta: float) -> void:
	if is_open and kit.busy() and Engine.get_process_frames() % 10 == 0:
		_update_info()
