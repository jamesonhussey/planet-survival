class_name InventoryGrid
extends RefCounted
## Tarkov-style cell grid. Items occupy w x h cells (rotation swaps them).
## Pure logic: fits/place/remove/auto_place/move, nested through
## ItemInstance.grids. `owner_item` is the container item holding this grid
## (null for built-in pockets).

var width: int
var height: int
var items: Array = []                 # Array[ItemInstance]
var _pos: Dictionary = {}             # uid -> Vector2i
var _cells: PackedInt32Array          # uid at cell or 0
## Back-reference to the container item holding this grid (weak: the item
## owns the grid, so a strong reference would be a RefCounted cycle).
var owner_item: ItemInstance:
	get:
		return _owner_ref.get_ref() if _owner_ref != null else null
	set(v):
		_owner_ref = weakref(v) if v != null else null
var _owner_ref: WeakRef = null
var name: String = ""

signal changed


func _init(w: int = 1, h: int = 1) -> void:
	width = maxi(1, w)
	height = maxi(1, h)
	_cells = PackedInt32Array()
	_cells.resize(width * height)


func cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return _cells[y * width + x]


func item_at(x: int, y: int) -> ItemInstance:
	var uid := cell(x, y)
	if uid <= 0:
		return null
	return _by_uid(uid)


func _by_uid(uid: int) -> ItemInstance:
	for it in items:
		if it.uid == uid:
			return it
	return null


func position_of(item: ItemInstance) -> Vector2i:
	return _pos.get(item.uid, Vector2i(-1, -1))


func has(item: ItemInstance) -> bool:
	return _pos.has(item.uid)


## Would `item` fit at (x,y) with the given rotation? `ignore` lets a move
## test ignore the item's own current cells.
func can_place(item: ItemInstance, x: int, y: int, rotated: bool, ignore: ItemInstance = null) -> bool:
	if item == null:
		return false
	# A container can never go inside itself or its own contents.
	if owner_item != null and (owner_item == item or _is_ancestor(item, owner_item)):
		return false
	var s := item.base_size()
	if rotated:
		s = Vector2i(s.y, s.x)
	if x < 0 or y < 0 or x + s.x > width or y + s.y > height:
		return false
	var ignore_uid := ignore.uid if ignore != null else -1
	for yy in range(y, y + s.y):
		for xx in range(x, x + s.x):
			var c := _cells[yy * width + xx]
			if c != 0 and c != ignore_uid:
				return false
	return true


static func _is_ancestor(candidate: ItemInstance, of: ItemInstance) -> bool:
	# true if `candidate` contains `of` somewhere inside
	var g: InventoryGrid = of.parent_grid
	var guard := 0
	while g != null and guard < 64:
		guard += 1
		if g.owner_item == candidate:
			return true
		g = g.owner_item.parent_grid if g.owner_item != null else null
	return false


func place(item: ItemInstance, x: int, y: int, rotated: bool = false) -> bool:
	if not can_place(item, x, y, rotated):
		return false
	if item.parent_grid != null:
		item.parent_grid.remove(item)
	item.rotated = rotated if item.can_rotate() else false
	var s := item.size()
	for yy in range(y, y + s.y):
		for xx in range(x, x + s.x):
			_cells[yy * width + xx] = item.uid
	items.append(item)
	_pos[item.uid] = Vector2i(x, y)
	item.parent_grid = self
	changed.emit()
	return true


func remove(item: ItemInstance) -> bool:
	if not _pos.has(item.uid):
		return false
	for i in _cells.size():
		if _cells[i] == item.uid:
			_cells[i] = 0
	items.erase(item)
	_pos.erase(item.uid)
	item.parent_grid = null
	changed.emit()
	return true


## First free spot (tries unrotated then rotated). Returns {x, y, rotated} or {}.
func find_slot(item: ItemInstance) -> Dictionary:
	for rot in ([false, true] if item.can_rotate() else [false]):
		for y in height:
			for x in width:
				if can_place(item, x, y, rot):
					return {"x": x, "y": y, "rotated": rot}
	return {}


## Merge into existing stacks first, then place the remainder. Returns true
## if the whole item ended up in this grid (possibly merged away).
func auto_place(item: ItemInstance) -> bool:
	if item.max_stack() > 1:
		for other: ItemInstance in items:
			if item.stackable_with(other):
				var room: int = other.max_stack() - other.count
				var moved := mini(room, item.count)
				other.count += moved
				item.count -= moved
				if item.count <= 0:
					if item.parent_grid != null:
						item.parent_grid.remove(item)
					changed.emit()
					return true
	var slot := find_slot(item)
	if slot.is_empty():
		return false
	return place(item, int(slot["x"]), int(slot["y"]), bool(slot["rotated"]))


## Move an item already in some grid to (x,y) here, rotating if asked.
func move(item: ItemInstance, x: int, y: int, rotated: bool) -> bool:
	var from := item.parent_grid
	var ignore := item if from == self else null
	if not can_place(item, x, y, rotated, ignore):
		return false
	if from != null:
		from.remove(item)
	return place(item, x, y, rotated)


func weight() -> float:
	var w := 0.0
	for it in items:
		w += it.weight()
	return w


func free_cells() -> int:
	var n := 0
	for c in _cells:
		if c == 0:
			n += 1
	return n


func all_items(recursive: bool = true) -> Array:
	var out: Array = []
	for it in items:
		out.append(it)
		if recursive:
			out.append_array(it.contents(true))
	return out


func to_dict() -> Dictionary:
	var list: Array = []
	for it: ItemInstance in items:
		var d: Dictionary = it.to_dict()
		var p: Vector2i = position_of(it)
		d["x"] = p.x
		d["y"] = p.y
		list.append(d)
	return {"w": width, "h": height, "items": list}
