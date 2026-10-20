class_name PlanetSelect
extends Node
## The orbit screen: a starfield, four slowly rotating pixel planets labelled
## 01-04, a mode picker and continue/new-run buttons. Built in code, drawn
## through the PS1 pipeline like everything else.

const PLANET_ORDER := ["01", "02", "03", "04"]
const PLANET_NAMES := {"01": "THE ECLIPSE PLANET", "02": "THE BEACH PLANET", "03": "THE GIANTS PLANET", "04": "THE CO2 LAKE PLANET"}
const PLANET_LINES := {
	"01": "A moon hides the sun. Until it doesn't.",
	"02": "Endless beach. The tide has teeth.",
	"03": "Something enormous walks here.",
	"04": "Lush. Green. Breathes out.",
}

var pipeline: PS1Pipeline
var view: SubViewport
var root: Control
var stars: Array = []          # [pos, brightness, speed]
var star_layer: Control
var planet_rects: Array[TextureRect] = []
var planet_images: Dictionary = {}
var labels: Array[Label] = []
var info_name: Label
var info_line: Label
var info_hint: Label
var mode_buttons: Array[Button] = []
var start_button: Button
var continue_button: Button
var selected_planet: int = 3
var selected_mode: String = "standard"
var phase: float = 0.0
var _render_accum: float = 0.0
var has_save: bool = false

signal start_requested(planet_id: String, mode_id: String)
signal continue_requested


func _ready() -> void:
	pipeline = PS1Pipeline.new()
	pipeline.name = "PS1"
	add_child(pipeline)
	view = pipeline.build(Data.render)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	view.add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = PixelFont.make_theme(1)
	layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	star_layer = Control.new()
	star_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	star_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_layer.draw.connect(_draw_stars)
	root.add_child(star_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 140:
		stars.append([Vector2(rng.randf() * 480.0, rng.randf() * 270.0), rng.randf_range(0.3, 1.0), rng.randf_range(0.5, 2.0)])

	var title := Label.new()
	title.theme = PixelFont.make_theme(2)
	title.text = "CHOOSE A PLANET"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 8
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	for i in PLANET_ORDER.size():
		var pid: String = PLANET_ORDER[i]
		var tr := TextureRect.new()
		tr.position = Vector2(34 + i * 110, 52)
		tr.size = Vector2(80, 80)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_planet_input.bind(i))
		root.add_child(tr)
		planet_rects.append(tr)
		var l := Label.new()
		l.text = pid
		l.theme = PixelFont.make_theme(2)
		l.position = tr.position + Vector2(26, 82)
		root.add_child(l)
		labels.append(l)
	_render_planets(0.0)

	info_name = Label.new()
	info_name.theme = PixelFont.make_theme(2)
	info_name.set_anchors_preset(Control.PRESET_TOP_WIDE)
	info_name.offset_top = 162
	info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(info_name)
	info_line = Label.new()
	info_line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	info_line.offset_top = 184
	info_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(info_line)
	info_hint = Label.new()
	info_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	info_hint.offset_top = 196
	info_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_hint.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(info_hint)

	var modes := HBoxContainer.new()
	modes.position = Vector2(96, 214)
	modes.add_theme_constant_override("separation", 4)
	root.add_child(modes)
	for m in Data.modes.values():
		var b := Button.new()
		b.text = "%s  %d days" % [str(m.get("name", m["id"])), int(m["days"])]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_mode.bind(str(m["id"])))
		modes.add_child(b)
		mode_buttons.append(b)
	var row := HBoxContainer.new()
	row.position = Vector2(150, 240)
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	start_button = Button.new()
	start_button.text = "LAND"
	start_button.theme = PixelFont.make_theme(2)
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.pressed.connect(func() -> void: start_requested.emit(PLANET_ORDER[selected_planet], selected_mode))
	row.add_child(start_button)
	continue_button = Button.new()
	continue_button.text = "CONTINUE"
	continue_button.theme = PixelFont.make_theme(2)
	continue_button.focus_mode = Control.FOCUS_NONE
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	row.add_child(continue_button)
	_select(3)
	_refresh_modes()


func set_save_available(available: bool, summary: String = "") -> void:
	has_save = available
	continue_button.visible = available
	info_hint.text = ("Save slot: %s" % summary) if available else info_hint.text


func _planet_available(pid: String) -> bool:
	return Data.planets.has(pid)


func _on_planet_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_select(i)


func _select(i: int) -> void:
	selected_planet = i
	var pid: String = PLANET_ORDER[i]
	var available := _planet_available(pid)
	info_name.text = PLANET_NAMES.get(pid, pid)
	info_line.text = PLANET_LINES.get(pid, "")
	info_hint.text = "" if available else "(not yet charted: comes in a later milestone)"
	start_button.disabled = not available
	for k in labels.size():
		labels[k].modulate = Color(1, 1, 0.6) if k == i else Color(0.75, 0.75, 0.75)
		planet_rects[k].modulate = Color.WHITE if (k == i or _planet_available(PLANET_ORDER[k])) else Color(0.55, 0.55, 0.55)


func _on_mode(id: String) -> void:
	selected_mode = id
	_refresh_modes()


func _refresh_modes() -> void:
	var ids := Data.modes.keys()
	for k in mode_buttons.size():
		mode_buttons[k].modulate = Color(1, 1, 0.6) if ids[k] == selected_mode else Color(0.8, 0.8, 0.8)


func _render_planets(ph: float) -> void:
	for i in PLANET_ORDER.size():
		var pid: String = PLANET_ORDER[i]
		var img := PlanetSprite.render(40, Data.palette(pid), pid, ph + i * 1.3, 100 + i)
		planet_rects[i].texture = ImageTexture.create_from_image(img)


func _draw_stars() -> void:
	var t := Time.get_ticks_msec() * 0.001
	for s in stars:
		var b: float = s[1] * (0.6 + 0.4 * sin(t * float(s[2]) + float(s[0].x)))
		star_layer.draw_rect(Rect2(s[0], Vector2(1, 1)), Color(b, b, b * 1.1))


func _process(delta: float) -> void:
	phase += delta * 0.12
	_render_accum += delta
	if _render_accum > 0.25:
		_render_accum = 0.0
		_render_planets(phase)
	star_layer.queue_redraw()
	if Input.is_action_just_pressed("ui_accept") and not start_button.disabled:
		start_requested.emit(PLANET_ORDER[selected_planet], selected_mode)
	for i in 4:
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			_select(i)
