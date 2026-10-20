class_name GridView
extends Control
## Draws one InventoryGrid as cells and item tiles and reports clicks/hover
## in grid coordinates. All drawing is immediate-mode (_draw) so it stays
## crisp at the low internal resolution.

const CATEGORY_COLORS := {
	"block": Color(0.55, 0.45, 0.3), "material": Color(0.45, 0.55, 0.3), "medical": Color(0.75, 0.3, 0.3),
	"container": Color(0.35, 0.4, 0.55), "gear": Color(0.4, 0.55, 0.6), "food": Color(0.7, 0.6, 0.25), "misc": Color(0.45, 0.45, 0.45),
}

var grid: InventoryGrid
var cell: int = 17
var title: String = ""
var hover_cell: Vector2i = Vector2i(-1, -1)
var highlight: Rect2i = Rect2i()        # cells a held item would cover
var highlight_ok: bool = true
var ghost_item: ItemInstance = null     # item currently held (drawn faded)
var font: Font
var font_size: int = 9

signal cell_clicked(view: GridView, x: int, y: int, button: int)
signal hovered(view: GridView, item: ItemInstance, x: int, y: int)
signal unhovered(view: GridView)


func setup(g: InventoryGrid, label: String, cell_px: int = 17) -> void:
	grid = g
	title = label
	cell = cell_px
	font = PixelFont.get_font(1)
	font_size = PixelFont.cell_size(1).y
	custom_minimum_size = Vector2(g.width * cell + 2, g.height * cell + 2 + (10 if title != "" else 0))
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not g.changed.is_connected(queue_redraw):
		g.changed.connect(queue_redraw)


func _grid_origin() -> Vector2:
	return Vector2(1, 1 + (10 if title != "" else 0))


func cell_at(local: Vector2) -> Vector2i:
	var o := _grid_origin()
	var p := (local - o) / float(cell)
	var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
	if c.x < 0 or c.y < 0 or c.x >= grid.width or c.y >= grid.height:
		return Vector2i(-1, -1)
	return c


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := cell_at((event as InputEventMouseMotion).position)
		if c != hover_cell:
			hover_cell = c
			if c.x >= 0:
				hovered.emit(self, grid.item_at(c.x, c.y), c.x, c.y)
			else:
				unhovered.emit(self)
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		var c := cell_at(mb.position)
		if c.x >= 0:
			cell_clicked.emit(self, c.x, c.y, mb.button_index)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_cell = Vector2i(-1, -1)
		unhovered.emit(self)
		queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	var o := _grid_origin()
	if title != "":
		draw_string(font, Vector2(1, 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.8, 0.8, 0.8))
	# Cells
	for y in grid.height:
		for x in grid.width:
			var r := Rect2(o + Vector2(x * cell, y * cell), Vector2(cell, cell))
			draw_rect(r, Color(0, 0, 0, 0.55))
			draw_rect(r, Color(0.35, 0.35, 0.35, 0.8), false, 1.0)
	# Items
	for it: ItemInstance in grid.items:
		var p := grid.position_of(it)
		var s := it.size()
		var r := Rect2(o + Vector2(p.x * cell, p.y * cell) + Vector2(1, 1), Vector2(s.x * cell, s.y * cell) - Vector2(2, 2))
		var col: Color = CATEGORY_COLORS.get(it.category(), CATEGORY_COLORS["misc"])
		if not it.examined:
			col = col.darkened(0.35)
		if it == ghost_item:
			col.a = 0.35
		draw_rect(r, col)
		draw_rect(r, col.lightened(0.3), false, 1.0)
		var label := _short_name(it)
		draw_string(font, r.position + Vector2(1, 8), label, HORIZONTAL_ALIGNMENT_LEFT, int(r.size.x) - 1, font_size, Color.WHITE)
		if it.count > 1:
			var cnt := str(it.count)
			draw_string(font, r.position + Vector2(r.size.x - cnt.length() * 6 - 1, r.size.y - 1), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 0.6))
		elif it.def.has("uses") or it.hp_pool > 0.0:
			var u := str(it.uses_left) if it.def.has("uses") else str(int(it.hp_pool))
			draw_string(font, r.position + Vector2(r.size.x - u.length() * 6 - 1, r.size.y - 1), u, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 1, 0.7))
	# Highlight for a held item
	if highlight.size.x > 0:
		var hr := Rect2(o + Vector2(highlight.position) * cell, Vector2(highlight.size) * cell)
		draw_rect(hr, Color(0.3, 1.0, 0.3, 0.35) if highlight_ok else Color(1.0, 0.3, 0.3, 0.4))
	elif hover_cell.x >= 0:
		var hr := Rect2(o + Vector2(hover_cell) * cell, Vector2(cell, cell))
		draw_rect(hr, Color(1, 1, 1, 0.12))


static func _short_name(it: ItemInstance) -> String:
	if not it.examined:
		return "?"
	var n := str(it.def.get("short", ""))
	if n != "":
		return n
	var name := it.display_name()
	var w := it.size().x
	var max_chars := maxi(1, w * 2)
	if name.length() <= max_chars:
		return name
	var words := name.split(" ")
	if words.size() > 1:
		var abbr := ""
		for wd in words:
			abbr += wd.substr(0, 1)
		return abbr.to_upper()
	return name.substr(0, max_chars)
