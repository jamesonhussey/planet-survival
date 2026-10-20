class_name GasSim
extends RefCounted
## Heavy-gas simulation (planet 04's limnic eruptions). A sparse grid of
## concentrations over the block world. Rules the player can read:
##   * gas is heavier than air: it flows DOWN first, then spreads sideways to
##     lower concentrations, and only creeps upward when a cell is nearly full
##   * airtight blocks stop it; anything not airtight (thatch, leaves, gaps)
##     lets it through; fluids are not entered
##   * it dissipates slowly over time
##   * it only exists inside an active region around its source (open edges)
## Pure: operates on WorldData + MaterialProps only. Deterministic given the
## same world and tick order (double-buffered updates).

var world: WorldData
var cells: Dictionary = {}          # Vector3i -> float concentration 0..max
var sources: Array[Vector3i] = []   # cells that emit while `emitting`
var region_min: Vector3i = Vector3i(-(1 << 20), 0, -(1 << 20))
var region_max: Vector3i = Vector3i(1 << 20, 1 << 20, 1 << 20)
var emitting: bool = false
var intensity: float = 1.0

# Tunables (from planet hazard "sim" config).
var emit_per_tick: float = 0.08
var max_concentration: float = 1.0
var gravity_rate: float = 0.9
var lateral_rate: float = 0.8
var rise_rate: float = 0.03
var rise_threshold: float = 0.85
var decay_per_tick: float = 0.0025
var min_concentration: float = 0.005
var max_active_cells: int = 20000

var _passable_by_id: PackedByteArray = []
var total_mass: float = 0.0
var tick_count: int = 0

const LATERAL: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


func _init(world_data: WorldData, cfg: Dictionary = {}) -> void:
	world = world_data
	configure(cfg)
	_build_passable_table()


func configure(cfg: Dictionary) -> void:
	emit_per_tick = float(cfg.get("emit_per_tick", emit_per_tick))
	max_concentration = float(cfg.get("max_concentration", max_concentration))
	gravity_rate = float(cfg.get("gravity_rate", gravity_rate))
	lateral_rate = float(cfg.get("lateral_rate", lateral_rate))
	rise_rate = float(cfg.get("rise_rate", rise_rate))
	rise_threshold = float(cfg.get("rise_threshold", rise_threshold))
	decay_per_tick = float(cfg.get("decay_per_tick", decay_per_tick))
	min_concentration = float(cfg.get("min_concentration", min_concentration))
	max_active_cells = int(cfg.get("max_active_cells", max_active_cells))


func _build_passable_table() -> void:
	_passable_by_id.resize(maxi(1, world.props.size()))
	for i in world.props.size():
		var p := world.props[i]
		_passable_by_id[i] = 0 if (p.airtight or p.fluid) else 1
	if world.props.is_empty():
		_passable_by_id[0] = 1


func set_region(min_corner: Vector3i, max_corner: Vector3i) -> void:
	region_min = min_corner
	region_max = max_corner


func in_region(p: Vector3i) -> bool:
	return p.x >= region_min.x and p.x <= region_max.x and p.y >= region_min.y and p.y <= region_max.y and p.z >= region_min.z and p.z <= region_max.z


## Can gas occupy this cell? (inside region, in world bounds, not airtight, not fluid)
func passable(p: Vector3i) -> bool:
	if not in_region(p):
		return false
	if p.y < 0 or p.y >= world.world_height:
		return false
	var id := world.get_block(p)
	if id >= _passable_by_id.size():
		return false
	return _passable_by_id[id] == 1


func concentration_at(p: Vector3i) -> float:
	return float(cells.get(p, 0.0))


func clear() -> void:
	cells.clear()
	total_mass = 0.0


## Add gas directly (tests, scripted vents).
func add(p: Vector3i, amount: float) -> void:
	if not passable(p):
		return
	cells[p] = minf(max_concentration, concentration_at(p) + amount)


func tick() -> void:
	tick_count += 1
	# 1. Emission.
	if emitting and cells.size() < max_active_cells:
		var e := emit_per_tick * intensity
		for s in sources:
			if passable(s):
				cells[s] = minf(max_concentration, float(cells.get(s, 0.0)) + e)
	if cells.is_empty():
		total_mass = 0.0
		return
	# 2. Flow (double buffered: read `cells`, accumulate into `delta`).
	var delta: Dictionary = {}
	var keys := cells.keys()
	for p in keys:
		var v: float = cells[p]
		if v <= 0.0:
			continue
		var remaining := v
		# Down first.
		var below: Vector3i = p + Vector3i(0, -1, 0)
		if passable(below):
			var room := max_concentration - float(cells.get(below, 0.0))
			var amt := minf(v * gravity_rate, maxf(room, 0.0))
			if amt > 0.0:
				delta[below] = float(delta.get(below, 0.0)) + amt
				delta[p] = float(delta.get(p, 0.0)) - amt
				remaining -= amt
		elif below.y >= 0 and in_region(below) == false:
			# Falling out of the region: gas is lost.
			delta[p] = float(delta.get(p, 0.0)) - v * gravity_rate
			remaining -= v * gravity_rate
		if remaining <= 0.0:
			continue
		# Sideways toward lower concentration.
		var share := remaining * lateral_rate * 0.25
		for d in LATERAL:
			var n: Vector3i = p + d
			if not in_region(n):
				delta[p] = float(delta.get(p, 0.0)) - share  # open edge
				continue
			if not passable(n):
				continue
			var nv := float(cells.get(n, 0.0))
			var diff := remaining - nv
			if diff > 0.0:
				var amt2 := minf(share, diff * 0.5)
				delta[n] = float(delta.get(n, 0.0)) + amt2
				delta[p] = float(delta.get(p, 0.0)) - amt2
		# Creep upward only when nearly full (pool rising).
		if remaining >= rise_threshold * max_concentration:
			var above: Vector3i = p + Vector3i(0, 1, 0)
			if passable(above):
				var av := float(cells.get(above, 0.0))
				if av < remaining:
					var amt3 := (remaining - av) * rise_rate
					delta[above] = float(delta.get(above, 0.0)) + amt3
					delta[p] = float(delta.get(p, 0.0)) - amt3
	# 3. Apply + decay + prune.
	for p in delta:
		cells[p] = float(cells.get(p, 0.0)) + float(delta[p])
	var mass := 0.0
	var dead: Array = []
	for p in cells:
		var v: float = float(cells[p]) - decay_per_tick
		if v < min_concentration:
			dead.append(p)
		else:
			if v > max_concentration:
				v = max_concentration
			cells[p] = v
			mass += v
	for p in dead:
		cells.erase(p)
	total_mass = mass


## Highest concentration in the column of cells an entity occupies
## (feet..head). Used for breathing checks.
func exposure(feet: Vector3, height: float = 1.7) -> float:
	var base := Vector3i(feet.floor())
	var worst := 0.0
	var n := maxi(1, int(ceil(height)))
	for i in n:
		worst = maxf(worst, concentration_at(base + Vector3i(0, i, 0)))
	return worst


## Finds lake-surface source cells inside a region: air cells directly above
## a fluid block. `fluid_id` is the lake material id.
func collect_sources_from_fluid(fluid_id: int, min_corner: Vector3i, max_corner: Vector3i, max_sources: int = 4096) -> int:
	sources.clear()
	for z in range(min_corner.z, max_corner.z + 1):
		for x in range(min_corner.x, max_corner.x + 1):
			for y in range(max_corner.y, min_corner.y - 1, -1):
				var id := world.get_block(Vector3i(x, y, z))
				if id == fluid_id:
					var above := Vector3i(x, y + 1, z)
					if world.get_block(above) == 0:
						sources.append(above)
					break
			if sources.size() >= max_sources:
				return sources.size()
	return sources.size()
