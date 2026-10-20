class_name HelpScreen
extends CanvasLayer
## F1: controls and how the game is read. The only place the game explains
## itself in words; nothing on this screen tells you how to beat a planet.

var root: Control
var is_open: bool = false

signal closed

const TEXT := """CONTROLS
WASD move   Space jump   Shift sprint   Ctrl crouch
LMB dig / strike   RMB place the selected block
1-6 or wheel: quick slots   Q use the selected item
E take, harvest, drink, talk, start a vigil
Tab inventory   H body   C craft   F torch   Esc pause
Inventory: click to pick up / put down, R rotate, right-click
for options, 1-6 to assign a slot, G drop

THE RULES
Every planet has one physical rule. Nothing will spell it out.
Watch the sky, the water, the animals and the people who live
there. Materials behave by their properties (air-tight, water-
proof, strength, how they burn), not by name. Hazards always
announce themselves before they arrive.

TOGETHER
A dead friend can come back: a cairn of stone, their tag, and
a fire kept through one full night."""


func setup() -> void:
	layer = 6
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = PixelFont.make_theme(1)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var title := Label.new()
	title.theme = PixelFont.make_theme(2)
	title.text = "HELP"
	title.position = Vector2(24, 4)
	root.add_child(title)
	var top := Label.new()
	top.text = "F1 closes    debug: F3 info  F5 hazard  F6 x20  F7 fly"
	top.position = Vector2(110, 10)
	top.modulate = Color(0.75, 0.75, 0.75)
	root.add_child(top)
	var body := Label.new()
	body.text = TEXT
	body.position = Vector2(24, 24)
	body.size = Vector2(432, 230)
	body.autowrap_mode = TextServer.AUTOWRAP_OFF
	root.add_child(body)


func open() -> void:
	is_open = true
	visible = true


func close() -> void:
	is_open = false
	visible = false
	closed.emit()
