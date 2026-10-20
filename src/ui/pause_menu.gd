class_name PauseMenu
extends CanvasLayer
## Esc menu: resume, save and return to orbit, quit. Built in code.

var root: Control
var is_open: bool = false
var info: Label

signal resume_requested
signal save_quit_requested
signal quit_requested


func _ready() -> void:
	layer = 7
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = PixelFont.make_theme(1)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var title := Label.new()
	title.theme = PixelFont.make_theme(2)
	title.text = "PAUSED"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 60
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	info = Label.new()
	info.set_anchors_preset(Control.PRESET_TOP_WIDE)
	info.offset_top = 90
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.modulate = Color(0.75, 0.75, 0.75)
	root.add_child(info)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -70
	box.offset_right = 70
	box.offset_top = -10
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	for pair in [["Resume", resume_requested], ["Save and return to orbit", save_quit_requested], ["Quit to desktop", quit_requested]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		var sig: Signal = pair[1]
		b.pressed.connect(func() -> void: sig.emit())
		box.add_child(b)


func open(text: String = "") -> void:
	is_open = true
	visible = true
	info.text = text


func close() -> void:
	is_open = false
	visible = false
