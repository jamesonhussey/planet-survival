class_name LightRaySim
extends RefCounted
## Sunlight as a straight line (planet 01). From any cell a ray is marched
## toward the sun through the block grid; every block on the way multiplies
## the transmitted light by (1 - opacity). Opaque blocks stop it, glass and
## water only dim it. Anything with transmission above `burn_threshold` is
## burned. Flammable blocks that stay exposed catch fire and are consumed.
## Pure and deterministic; the hazard module decides when the sun is out.

var world: WorldData
var sun_dir: Vector3 = Vector3(0.3, 1.0, 0.2).normalized()   # from the cell toward the sun
var max_distance: int = 96
var burn_threshold: float = 0.35
## Blocks below this flammability scorch but are not consumed (dry grass
## survives; thatch, planks and leaves burn away).
var min_flammability: float = 0.6
var region_min: Vector3i = Vector3i(-(1 << 20), 0, -(1 << 20))
var region_max: Vector3i = Vector3i(1 << 20, 1 << 20, 1 << 20)
var _cache: Dictionary = {}       # Vector3i -> transmission for the current sun_dir
var _opacity_by_id: PackedFloat32Array = []
var _flammable_by_id: PackedFloat32Array = []
var burned_blocks: Array[Vector3i] = []   # blocks consumed by fire in the last tick
var tick_count: int = 0


func _init(world_data: WorldData) -> void:
	world = world_data
	_opacity_by_id.resize(maxi(1, world.props.size()))
	_flammable_by_id.resize(maxi(1, world.props.size()))
	for i in world.props.size():
		_opacity_by_id[i] = world.props[i].opacity if world.props[i].solid or world.props[i].fluid else 0.0
		_flammable_by_id[i] = world.props[i].flammability
	if world.props.is_empty():
		_opacity_by_id[0] = 0.0


func set_sun(dir: Vector3) -> void:
	var d := dir.normalized()
	if d.y <= 0.02:
		d.y = 0.02
		d = d.normalized()
	if d.distance_to(sun_dir) > 1e-4:
		sun_dir = d
		_cache.clear()


func set_region(min_corner: Vector3i, max_corner: Vector3i) -> void:
	region_min = min_corner
	region_max = max_corner


func invalidate() -> void:
	_cache.clear()


func _opacity(id: int) -> float:
	if id < 0 or id >= _opacity_by_id.size():
		return 1.0
	return _opacity_by_id[id]


## Fraction of sunlight reaching `cell` (0..1). The cell itself is not counted.
func transmission_at(cell: Vector3i) -> float:
	var cached: Variant = _cache.get(cell)
	if cached != null:
		return cached
	# Lambdas capture by value, so accumulate in an array (a reference).
	var acc := [1.0]
	var origin := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	VoxelRay.cast(origin, sun_dir, float(max_distance), func(c: Vector3i) -> bool:
		if c == cell:
			return false
		if c.y >= world.world_height:
			return true  # out the top: stop, fully lit from here
		var id := world.get_block(c)
		if id == 0:
			return false
		acc[0] = float(acc[0]) * (1.0 - _opacity(id))
		return float(acc[0]) <= 0.01  # stop once effectively dark
	)
	var t := float(acc[0])
	if t <= 0.01:
		t = 0.0
	_cache[cell] = t
	return t


func is_burning_at(cell: Vector3i) -> bool:
	return transmission_at(cell) >= burn_threshold


## Exposure of an entity: the brightest of its head and feet cells.
func exposure(feet: Vector3, height: float = 1.7) -> float:
	var base := Vector3i(feet.floor())
	var head := Vector3i(Vector3(feet.x, feet.y + height - 0.1, feet.z).floor())
	return maxf(transmission_at(base), transmission_at(head))


## Burn flammable surface blocks inside a box around `center` (radius in
## blocks). Returns the number of blocks consumed. `rate` is the probability
## per fully exposed, fully flammable block per tick; `rng` makes it
## deterministic in tests.
func tick(center: Vector3i, radius: int, rate: float, rng: RandomNumberGenerator) -> int:
	tick_count += 1
	burned_blocks.clear()
	var consumed := 0
	for z in range(center.z - radius, center.z + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			# Top-most non-air block in the column within +-16 of the centre.
			for y in range(mini(center.y + 16, world.world_height - 1), maxi(center.y - 16, 0) - 1, -1):
				var id := world.get_block(Vector3i(x, y, z))
				if id == 0:
					continue
				var f := _flammable_by_id[id] if id < _flammable_by_id.size() else 0.0
				if f >= min_flammability:
					var above := Vector3i(x, y + 1, z)
					var t := transmission_at(above)
					if t >= burn_threshold and rng.randf() < rate * f * t:
						world.set_block(Vector3i(x, y, z), 0)
						burned_blocks.append(Vector3i(x, y, z))
						_cache.clear()
						consumed += 1
				break
	return consumed
