class_name CrushSim
extends RefCounted
## Planet 03: something enormous walks here. A footfall presses a disc of
## ground: every block in it whose `strength` is below the foot's force is
## destroyed from the top down (up to `max_depth` blocks) and anything standing
## in the disc without a strong block over its head is crushed. Pure: reads
## material properties only, so stone, brick and cairns hold, planks and
## thatch do not, and a stone roof is shelter whatever it is called.

var world: WorldData
var _strength_by_id: PackedFloat32Array = []
var _solid_by_id: PackedByteArray = []
var destroyed: Array[Vector3i] = []   # blocks removed by the last footfall
var footfalls: int = 0


func _init(world_data: WorldData) -> void:
	world = world_data
	var n := maxi(1, world.props.size())
	_strength_by_id.resize(n)
	_solid_by_id.resize(n)
	for i in world.props.size():
		_strength_by_id[i] = world.props[i].strength
		_solid_by_id[i] = 1 if world.props[i].solid else 0


func strength(id: int) -> float:
	if id <= 0 or id >= _strength_by_id.size():
		return 0.0
	return _strength_by_id[id]


func is_solid(id: int) -> bool:
	if id <= 0 or id >= _solid_by_id.size():
		return false
	return _solid_by_id[id] == 1


## A foot lands centred on column (cx, cz). Returns the number of blocks
## destroyed; `destroyed` lists them. Deterministic given the world state, so
## clients replay the same footfalls.
func footfall(cx: int, cz: int, radius: float, force: float, max_depth: int = 2) -> int:
	destroyed.clear()
	footfalls += 1
	var r := int(ceil(radius))
	var r2 := radius * radius
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if float(dx * dx + dz * dz) > r2:
				continue
			var x := cx + dx
			var z := cz + dz
			var y := world.surface_y(x, z)
			if y < 1:
				continue
			var removed := 0
			while removed < max_depth and y >= 1:
				var id := world.get_block(Vector3i(x, y, z))
				if not is_solid(id):
					break
				if strength(id) >= force:
					break
				world.set_block(Vector3i(x, y, z), 0)
				destroyed.append(Vector3i(x, y, z))
				removed += 1
				y -= 1
	return destroyed.size()


## Would something standing at `feet` (height `height`) be crushed by a foot of
## `radius` at (cx, cz) with `force`? Not if a solid block at least as strong
## as the foot sits above its head within `look_up` blocks: a roof of rock is
## shelter, a roof of planks is not.
func crushed(feet: Vector3, cx: int, cz: int, radius: float, force: float, height: float = 1.8, look_up: int = 8) -> bool:
	var d := Vector2(feet.x - (cx + 0.5), feet.z - (cz + 0.5)).length()
	if d > radius + 0.4:
		return false
	var top := int(floor(feet.y + height))
	for y in range(top, top + look_up + 1):
		var id := world.get_block(Vector3i(int(floor(feet.x)), y, int(floor(feet.z))))
		if is_solid(id) and strength(id) >= force:
			return false
	return true


## Felt tremor 0..1 at `distance` from a footfall.
static func tremor(distance: float, tremor_range: float) -> float:
	if tremor_range <= 0.0:
		return 0.0
	var t := clampf(1.0 - distance / tremor_range, 0.0, 1.0)
	return t * t


## A straight walk that passes `pass_distance` beside `focus`: starts
## `before` metres before the closest point and ends `after` metres past it.
## Returns {"start": Vector2, "end": Vector2, "closest": Vector2}.
static func plan_path(focus: Vector2, pass_distance: float, before: float, after: float, rng: RandomNumberGenerator) -> Dictionary:
	var a := rng.randf() * TAU
	var dir := Vector2(cos(a), sin(a))
	var side := Vector2(-dir.y, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	var closest := focus + side * pass_distance
	return {"start": closest - dir * before, "end": closest + dir * after, "closest": closest}
