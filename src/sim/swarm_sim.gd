class_name SwarmSim
extends RefCounted
## The roach swarm (planet 02). Agents live on the block grid and crawl
## along any surface (they climb). Each tick a breadth-first distance field
## is grown from the targets (warm bodies first, dry ground otherwise); every
## agent steps downhill on it. Agents pass through air freely and squeeze
## through *leaky* solids (not airtight) slowly; airtight blocks stop them,
## so only a sealed shelter keeps them out. Agents in a target's cell bite.
## Pure and deterministic.

class Agent:
	var cell: Vector3i
	var progress: float = 0.0     # 0..1 toward next cell
	var next: Vector3i
	var alive: bool = true
	var hunger: float = 1.0
	var variant: int = 0

var world: WorldData
var agents: Array[Agent] = []
var targets: Array[Vector3i] = []         # cells agents want (players, creatures)
var dry_cells: Dictionary = {}            # optional secondary targets (dry ground when flooding)
var wet_cells: Dictionary = {}            # cells agents avoid (water)
var speed: float = 3.0                    # cells per second in air
var squeeze_factor: float = 0.25          # speed multiplier through leaky solids
var bite_damage: float = 4.0
var bite_interval: float = 1.0
var max_agents: int = 300
var field_radius: int = 48
var max_field_cells: int = 60000
var _dist: Dictionary = {}                # Vector3i -> int distance to nearest target
var _airtight_by_id: PackedByteArray = []
var _solid_by_id: PackedByteArray = []
var bites: Array = []                     # [[target_cell, count]] produced last tick
var tick_count: int = 0

const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]


func _init(world_data: WorldData) -> void:
	world = world_data
	var n := maxi(1, world.props.size())
	_airtight_by_id.resize(n)
	_solid_by_id.resize(n)
	for i in world.props.size():
		_airtight_by_id[i] = 1 if world.props[i].airtight else 0
		_solid_by_id[i] = 1 if world.props[i].solid else 0


## Can an agent occupy this cell? Air (or any non-solid) and leaky solids.
func passable(p: Vector3i) -> bool:
	if p.y < 0 or p.y >= world.world_height:
		return false
	if wet_cells.has(p):
		return false
	var id := world.get_block(p)
	if id >= _solid_by_id.size():
		return false
	if _solid_by_id[id] == 0:
		return true
	return _airtight_by_id[id] == 0


func is_leaky_solid(p: Vector3i) -> bool:
	var id := world.get_block(p)
	return id < _solid_by_id.size() and _solid_by_id[id] == 1 and _airtight_by_id[id] == 0


## Agents crawl on surfaces: an air cell needs a solid neighbour (floor,
## wall or ceiling) to be walkable; leaky solids always count.
func walkable(p: Vector3i) -> bool:
	if not passable(p):
		return false
	if is_leaky_solid(p):
		return true
	for d in DIRS:
		var id := world.get_block(p + d)
		if id != 0 and id < _solid_by_id.size() and _solid_by_id[id] == 1:
			return true
	return false


func spawn(cell: Vector3i, count: int, rng: RandomNumberGenerator) -> int:
	var n := 0
	for i in count:
		if agents.size() >= max_agents:
			break
		var a := Agent.new()
		a.cell = cell
		a.next = cell
		a.variant = rng.randi_range(0, 2)
		agents.append(a)
		n += 1
	return n


func clear() -> void:
	agents.clear()
	_dist.clear()


func count_alive() -> int:
	var n := 0
	for a in agents:
		if a.alive:
			n += 1
	return n


## Rebuild the distance field from the targets (multi-source BFS).
func rebuild_field() -> void:
	_dist.clear()
	var queue: Array[Vector3i] = []
	for t in targets:
		for c in [t, t + Vector3i(0, 1, 0), t + Vector3i(0, -1, 0)]:
			if passable(c) and not _dist.has(c):
				_dist[c] = 0
				queue.append(c)
	if queue.is_empty():
		for c in dry_cells:
			if passable(c) and not _dist.has(c):
				_dist[c] = 0
				queue.append(c)
	var center := Vector3i.ZERO
	if not targets.is_empty():
		center = targets[0]
	var head := 0
	while head < queue.size() and _dist.size() < max_field_cells:
		var p := queue[head]
		head += 1
		var dp: int = _dist[p]
		for d in DIRS:
			var n := p + d
			if _dist.has(n) or not walkable(n):
				continue
			if absi(n.x - center.x) > field_radius or absi(n.z - center.z) > field_radius:
				continue
			# Leaky solids cost more to pass (chewing through).
			_dist[n] = dp + (4 if is_leaky_solid(n) else 1)
			queue.append(n)


## Advance every agent by `dt` seconds. Returns bites as [[cell, count]].
func tick(dt: float, rng: RandomNumberGenerator = null) -> Array:
	tick_count += 1
	bites.clear()
	var bites_at: Dictionary = {}
	for a in agents:
		if not a.alive:
			continue
		# Arrived at a target cell: bite instead of moving.
		if _dist.get(a.cell, 999999) == 0 and not targets.is_empty():
			a.hunger -= dt
			if a.hunger <= 0.0:
				a.hunger = bite_interval
				bites_at[a.cell] = int(bites_at.get(a.cell, 0)) + 1
			continue
		if a.next == a.cell or not passable(a.next):
			a.next = _best_step(a.cell, rng)
			a.progress = 0.0
			if a.next == a.cell:
				continue
		var rate := speed * (squeeze_factor if is_leaky_solid(a.next) else 1.0)
		a.progress += rate * dt
		if a.progress >= 1.0:
			a.cell = a.next
			a.progress = 0.0
	for c in bites_at:
		bites.append([c, bites_at[c]])
	return bites


func _best_step(from: Vector3i, rng: RandomNumberGenerator) -> Vector3i:
	var best := from
	var best_d: int = _dist.get(from, 999999)
	var options: Array[Vector3i] = []
	for d in DIRS:
		var n := from + d
		var nd: int = _dist.get(n, 999999)
		if nd < best_d:
			best_d = nd
			best = n
			options = [n]
		elif nd == best_d and nd < 999999 and n != from:
			options.append(n)
	if options.size() > 1 and rng != null:
		return options[rng.randi_range(0, options.size() - 1)]
	if best == from and rng != null:
		# No gradient: wander onto any walkable neighbour.
		var walk: Array[Vector3i] = []
		for d in DIRS:
			if walkable(from + d):
				walk.append(from + d)
		if not walk.is_empty():
			return walk[rng.randi_range(0, walk.size() - 1)]
	return best


## World-space positions (cell centres, interpolated) for rendering.
func positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for a in agents:
		if not a.alive:
			continue
		var p := Vector3(a.cell).lerp(Vector3(a.next), a.progress) + Vector3(0.5, 0.1, 0.5)
		out.append(p)
	return out


func kill_in_cell(cell: Vector3i, max_count: int) -> int:
	var n := 0
	for a in agents:
		if a.alive and a.cell == cell:
			a.alive = false
			n += 1
			if n >= max_count:
				break
	return n


func prune_dead() -> void:
	var keep: Array[Agent] = []
	for a in agents:
		if a.alive:
			keep.append(a)
	agents = keep
