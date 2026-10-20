class_name FluidSim
extends RefCounted
## Rising water (planet 02). One global `level`: every open cell below it
## that is connected to the outside becomes wet. Waterproof blocks hold water
## back; porous blocks (sand, gravel, thatch, planks) let it through but are
## not themselves "wet" cells. Enclosed waterproof volumes stay dry. At the
## flood front the wave applies `wave_force` against block `strength` and
## destroys what is weaker. Pure and deterministic.

var world: WorldData
var level: float = 0.0              # water surface height (world y)
var base_level: float = 0.0         # calm sea level
var wet: Dictionary = {}            # Vector3i -> true (open cells under water)
var region_min: Vector3i
var region_max: Vector3i
var wave_force: float = 0.0         # destructive force at the front (0 = calm)
var destroyed: Array[Vector3i] = [] # blocks destroyed in the last tick
var max_cells: int = 70000
var _solid_by_id: PackedByteArray = []
var _waterproof_by_id: PackedByteArray = []
var _strength_by_id: PackedFloat32Array = []
var _fluid_id: int = 10
var tick_count: int = 0


func _init(world_data: WorldData, sea_level: float, fluid_block: int = 10) -> void:
	world = world_data
	base_level = sea_level
	level = sea_level
	_fluid_id = fluid_block
	var n := maxi(1, world.props.size())
	_solid_by_id.resize(n)
	_waterproof_by_id.resize(n)
	_strength_by_id.resize(n)
	for i in world.props.size():
		var p := world.props[i]
		_solid_by_id[i] = 1 if p.solid else 0
		_waterproof_by_id[i] = 1 if p.waterproof else 0
		_strength_by_id[i] = p.strength
	region_min = Vector3i(-(1 << 20), 0, -(1 << 20))
	region_max = Vector3i(1 << 20, 1 << 20, 1 << 20)


func set_region(min_corner: Vector3i, max_corner: Vector3i) -> void:
	region_min = min_corner
	region_max = max_corner


func in_region(p: Vector3i) -> bool:
	return p.x >= region_min.x and p.x <= region_max.x and p.y >= region_min.y and p.y <= region_max.y and p.z >= region_min.z and p.z <= region_max.z


## Can water pass this cell? Open cells and porous (non-waterproof) solids.
func passable(p: Vector3i) -> bool:
	if not in_region(p) or p.y < 0 or p.y >= world.world_height:
		return false
	var id := world.get_block(p)
	if id >= _solid_by_id.size():
		return false
	if _solid_by_id[id] == 0:
		return true
	return _waterproof_by_id[id] == 0


func is_open(p: Vector3i) -> bool:
	var id := world.get_block(p)
	return id < _solid_by_id.size() and _solid_by_id[id] == 0


func is_wet(p: Vector3i) -> bool:
	return wet.has(p)


## Recompute the wet set for the current level by flood-filling from the
## region's edges (the sea comes from outside). Then apply wave damage to
## blocks touching newly wet cells.
func tick(rng: RandomNumberGenerator = null) -> void:
	tick_count += 1
	destroyed.clear()
	var top := int(floor(level))
	var previous := wet
	wet = {}
	if top < region_min.y:
		return
	var queue: Array[Vector3i] = []
	var seen: Dictionary = {}
	# Seeds: every passable cell on the region boundary at or below the level,
	# and (so the sea surface exists even far from edges) open cells at the
	# surface row that see the sky.
	var y_hi := mini(top, region_max.y)
	for y in range(region_min.y, y_hi + 1):
		for x in range(region_min.x, region_max.x + 1):
			for z in [region_min.z, region_max.z]:
				var p := Vector3i(x, y, z)
				if passable(p) and not seen.has(p):
					seen[p] = true
					queue.append(p)
		for z in range(region_min.z + 1, region_max.z):
			for x in [region_min.x, region_max.x]:
				var p := Vector3i(x, y, z)
				if passable(p) and not seen.has(p):
					seen[p] = true
					queue.append(p)
	var head := 0
	while head < queue.size() and seen.size() < max_cells:
		var p := queue[head]
		head += 1
		if is_open(p):
			wet[p] = true
		for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0), Vector3i(0, 1, 0)]:
			var n: Vector3i = p + d
			if n.y > top or seen.has(n) or not passable(n):
				continue
			seen[n] = true
			queue.append(n)
	# Wave damage where water arrived this tick.
	if wave_force > 0.0:
		for p in wet:
			if previous.has(p):
				continue
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
				var n: Vector3i = p + d
				var id := world.get_block(n)
				if id == 0 or id >= _solid_by_id.size() or _solid_by_id[id] == 0:
					continue
				var s := _strength_by_id[id]
				if s < wave_force:
					var chance := clampf((wave_force - s) / maxf(wave_force, 0.01), 0.0, 1.0)
					var roll := rng.randf() if rng != null else 0.5
					if roll < chance:
						world.set_block(n, 0)
						destroyed.append(n)


## Highest wet cell an entity occupies (for swimming/drowning): 0 = dry,
## 1 = feet in water, 2 = head under water.
func submersion(feet: Vector3, height: float = 1.7) -> int:
	var base := Vector3i(feet.floor())
	var head := Vector3i(Vector3(feet.x, feet.y + height - 0.1, feet.z).floor())
	if wet.has(head):
		return 2
	if wet.has(base) or feet.y < level and wet.has(Vector3i(base.x, base.y + 1, base.z)):
		return 1
	return 0


## Water surface cells for rendering: wet cells with no wet cell above.
func surface_cells(limit: int = 30000) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for p in wet:
		if not wet.has(p + Vector3i(0, 1, 0)):
			out.append(p)
			if out.size() >= limit:
				break
	return out
