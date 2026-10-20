class_name VoxelRay
extends RefCounted
## Grid ray marching (Amanatides & Woo DDA). Used by the player's interactor
## and by the light-ray hazard later. Pure.


class Hit:
	var hit: bool = false
	var pos: Vector3i          # the solid cell hit
	var prev: Vector3i         # the empty cell before it (where to place)
	var normal: Vector3i
	var distance: float = 0.0


## Casts from `origin` along `dir` up to `max_dist`, stopping at the first
## cell for which `is_solid.call(Vector3i) -> bool` is true.
static func cast(origin: Vector3, dir: Vector3, max_dist: float, is_solid: Callable) -> Hit:
	var h := Hit.new()
	if dir.length_squared() < 1e-12:
		return h
	dir = dir.normalized()
	var cell := Vector3i(origin.floor())
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_delta := Vector3(
		INF if dir.x == 0.0 else absf(1.0 / dir.x),
		INF if dir.y == 0.0 else absf(1.0 / dir.y),
		INF if dir.z == 0.0 else absf(1.0 / dir.z))
	var t_max := Vector3(
		_first_boundary(origin.x, dir.x, cell.x),
		_first_boundary(origin.y, dir.y, cell.y),
		_first_boundary(origin.z, dir.z, cell.z))
	var prev := cell
	var normal := Vector3i.ZERO
	var t := 0.0
	for _i in 512:
		if is_solid.call(cell):
			h.hit = true
			h.pos = cell
			h.prev = prev
			h.normal = normal
			h.distance = t
			return h
		prev = cell
		if t_max.x < t_max.y and t_max.x < t_max.z:
			t = t_max.x
			t_max.x += t_delta.x
			cell.x += step.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			t = t_max.y
			t_max.y += t_delta.y
			cell.y += step.y
			normal = Vector3i(0, -step.y, 0)
		else:
			t = t_max.z
			t_max.z += t_delta.z
			cell.z += step.z
			normal = Vector3i(0, 0, -step.z)
		if t > max_dist:
			break
	return h


static func _first_boundary(o: float, d: float, c: int) -> float:
	if d > 0.0:
		return (float(c) + 1.0 - o) / d
	elif d < 0.0:
		return (o - float(c)) / -d
	return INF
