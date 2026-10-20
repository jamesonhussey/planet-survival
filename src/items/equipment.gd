class_name Equipment
extends RefCounted
## What a player carries: four 1x1 pockets (built in), an optional chest rig
## and backpack (container items with their own grids), and quick slots that
## reference items anywhere in the kit. Pure logic.

const POCKETS := 4
const QUICK_SLOTS := 6

var pockets: Array = []           # Array[InventoryGrid] 1x1 each
var rig: ItemInstance = null
var backpack: ItemInstance = null
var quick: Array = []             # uid per slot (0 = empty)

signal changed


func _init() -> void:
	for i in POCKETS:
		var g := InventoryGrid.new(1, 1)
		g.name = "Pocket %d" % (i + 1)
		g.changed.connect(_on_grid_changed)
		pockets.append(g)
	quick.resize(QUICK_SLOTS)
	quick.fill(0)


func equip(item: ItemInstance) -> bool:
	var slot := str(item.def.get("slot", ""))
	if slot == "backpack":
		if backpack != null:
			return false
		backpack = item
	elif slot == "rig":
		if rig != null:
			return false
		rig = item
	else:
		return false
	if item.parent_grid != null:
		item.parent_grid.remove(item)
	for g in item.grids:
		if not g.changed.is_connected(_on_grid_changed):
			g.changed.connect(_on_grid_changed)
	changed.emit()
	return true


func unequip(slot: String) -> ItemInstance:
	var it: ItemInstance = null
	if slot == "backpack":
		it = backpack
		backpack = null
	elif slot == "rig":
		it = rig
		rig = null
	if it != null:
		changed.emit()
	return it


func _on_grid_changed() -> void:
	changed.emit()


## Every grid the player can reach, outermost first: pockets, rig, backpack,
## then nested containers.
func all_grids() -> Array:
	var out: Array = []
	out.append_array(pockets)
	for holder in [rig, backpack]:
		if holder != null:
			out.append_array(holder.grids)
	var nested: Array = []
	for g in out:
		for it in g.items:
			if it.is_container():
				nested.append_array(_grids_of(it))
	out.append_array(nested)
	return out


static func _grids_of(it: ItemInstance) -> Array:
	var out: Array = []
	out.append_array(it.grids)
	for g in it.grids:
		for inner in g.items:
			if inner.is_container():
				out.append_array(_grids_of(inner))
	return out


func all_items() -> Array:
	var out: Array = []
	for g in all_grids():
		out.append_array(g.items)
	return out


## Put an item anywhere it fits (merging stacks first). Prefers rig, then
## pockets, then backpack so quick things stay reachable.
func add_item(item: ItemInstance) -> bool:
	var order: Array = []
	if rig != null:
		order.append_array(rig.grids)
	order.append_array(pockets)
	if backpack != null:
		order.append_array(backpack.grids)
	for g in all_grids():
		if not order.has(g):
			order.append(g)
	# Stack merge pass across everything first.
	if item.max_stack() > 1:
		for g in order:
			for other in g.items:
				if item.stackable_with(other):
					var moved := mini(other.max_stack() - other.count, item.count)
					other.count += moved
					item.count -= moved
					if item.count <= 0:
						changed.emit()
						return true
	for g in order:
		if g.auto_place(item):
			changed.emit()
			return true
	return false


func count_of(def_id: String) -> int:
	var n := 0
	for it in all_items():
		if it.id == def_id:
			n += it.count
	return n


## Remove `n` of an item id, emptying stacks as needed. Returns removed count.
func consume(def_id: String, n: int) -> int:
	var left := n
	for it in all_items():
		if left <= 0:
			break
		if it.id != def_id:
			continue
		var take := mini(it.count, left)
		it.count -= take
		left -= take
		if it.count <= 0:
			_forget_quick(it.uid)
			it.parent_grid.remove(it)
	if left != n:
		changed.emit()
	return n - left


func remove_item(item: ItemInstance) -> void:
	_forget_quick(item.uid)
	if item.parent_grid != null:
		item.parent_grid.remove(item)
	changed.emit()


func find_by_uid(uid: int) -> ItemInstance:
	if uid <= 0:
		return null
	for it in all_items():
		if it.uid == uid:
			return it
	return null


func find_first(pred: Callable) -> ItemInstance:
	for it in all_items():
		if pred.call(it):
			return it
	return null


func total_weight() -> float:
	var w := 0.0
	for g in pockets:
		w += g.weight()
	for holder in [rig, backpack]:
		if holder != null:
			w += holder.weight()
	return w


func set_quick(slot: int, item: ItemInstance) -> void:
	if slot < 0 or slot >= QUICK_SLOTS:
		return
	if item != null:
		for i in QUICK_SLOTS:
			if quick[i] == item.uid:
				quick[i] = 0
	quick[slot] = item.uid if item != null else 0
	changed.emit()


func quick_item(slot: int) -> ItemInstance:
	if slot < 0 or slot >= QUICK_SLOTS:
		return null
	var it := find_by_uid(int(quick[slot]))
	if it == null and quick[slot] != 0:
		quick[slot] = 0
	return it


func _forget_quick(uid: int) -> void:
	for i in QUICK_SLOTS:
		if quick[i] == uid:
			quick[i] = 0


## Auto-fill empty quick slots with blocks and meds in a sensible order.
func auto_assign_quick() -> void:
	var candidates: Array = []
	for it in all_items():
		if it.is_block() or it.category() == "medical" or it.category() == "food" or it.category() == "gear":
			candidates.append(it)
	for it in candidates:
		if quick.has(it.uid):
			continue
		for i in QUICK_SLOTS:
			if quick[i] == 0:
				quick[i] = it.uid
				break
	changed.emit()
