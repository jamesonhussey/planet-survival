class_name ItemInstance
extends RefCounted
## One concrete item in the world or an inventory. `def` is the entry from
## data/items.json. Containers own one or more InventoryGrids (nesting).
## Pure: no nodes, so inventories run in unit tests and on the server.

static var _next_uid: int = 1

var uid: int
var def: Dictionary
var id: String
var count: int = 1
var rotated: bool = false
var examined: bool = false
var uses_left: int = 0
var hp_pool: float = 0.0
var durability: float = 1.0
var freshness_hours: float = -1.0   # food: game hours until spoiled (-1 = not started)
var data: Dictionary = {}            # free-form per-instance data (e.g. tag owner)
var grids: Array = []            # Array[InventoryGrid] for containers
## Grid this item sits in (weak back-reference; the grid owns the item).
var parent_grid: InventoryGrid:
	get:
		return _parent_ref.get_ref() if _parent_ref != null else null
	set(v):
		_parent_ref = weakref(v) if v != null else null
var _parent_ref: WeakRef = null


func _init(item_def: Dictionary = {}, amount: int = 1) -> void:
	uid = _next_uid
	_next_uid += 1
	def = item_def
	id = str(def.get("id", "unknown"))
	count = maxi(1, amount)
	uses_left = int(def.get("uses", 0))
	hp_pool = float(def.get("hp_pool", 0.0))
	examined = bool(def.get("known", true))
	for g in def.get("grids", []):
		var grid := InventoryGrid.new(int(g[0]), int(g[1]))
		grid.owner_item = self
		grids.append(grid)


func is_container() -> bool:
	return not grids.is_empty()


func base_size() -> Vector2i:
	var s: Array = def.get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


## Footprint in cells after rotation.
func size() -> Vector2i:
	var s := base_size()
	return Vector2i(s.y, s.x) if rotated else s


func can_rotate() -> bool:
	var s := base_size()
	return s.x != s.y


func max_stack() -> int:
	return maxi(1, int(def.get("stack", 1)))


func stackable_with(other: ItemInstance) -> bool:
	return other != null and other != self and other.id == id and max_stack() > 1 and other.count < other.max_stack()


func category() -> String:
	return str(def.get("category", "misc"))


func is_block() -> bool:
	return def.has("block")


func block_name() -> String:
	return str(def.get("block", ""))


## Own weight (times stack) plus everything inside.
func weight() -> float:
	var w := float(def.get("weight", 0.1)) * count
	for g in grids:
		w += g.weight()
	return w


func display_name() -> String:
	if examined and data.has("owner_name"):
		return "%s (%s)" % [str(def.get("name", id.capitalize())), str(data["owner_name"])]
	if examined:
		return str(def.get("name", id.capitalize()))
	return str(def.get("unknown_name", "Unknown item"))


func description() -> String:
	if not examined:
		return "Examine to identify."
	return str(def.get("desc", ""))


func examine_time() -> float:
	return float(def.get("examine_time", 1.5))


## Split `n` off this stack into a new instance (returns null if impossible).
func split(n: int) -> ItemInstance:
	if n <= 0 or n >= count:
		return null
	count -= n
	var other := ItemInstance.new(def, n)
	other.examined = examined
	return other


## Everything nested inside this item, depth-first.
func contents(recursive: bool = true) -> Array:
	var out: Array = []
	for g in grids:
		for it in g.items:
			out.append(it)
			if recursive:
				out.append_array(it.contents(true))
	return out


func to_dict() -> Dictionary:
	var d := {"id": id, "uid": uid, "count": count, "rotated": rotated, "examined": examined, "uses_left": uses_left, "hp_pool": hp_pool, "durability": durability, "freshness_hours": freshness_hours, "data": data.duplicate()}
	if is_container():
		var gs: Array = []
		for g in grids:
			gs.append(g.to_dict())
		d["grids"] = gs
	return d
