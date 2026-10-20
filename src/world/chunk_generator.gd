class_name ChunkGenerator
extends RefCounted
## Deterministic terrain generator: same seed + planet config => the same
## chunk on every machine, so clients and saves only need edits. Terrain
## types: "hills_lakes" (04), "farmland" (01), "beach" (02). Structures
## (farmhouses, barns) are stamped in from StructureGen deterministically.
## Thread-safe for reading after construction (caches are mutex-guarded).

var seed: int = 0
var terrain: Dictionary = {}
var terrain_type: String = "hills_lakes"
var world_height: int = 128
var id_surface: int = 2
var id_subsurface: int = 1
var id_deep: int = 3
var id_shore: int = 5
var id_fluid: int = 10
var id_mossy: int = 14
var id_patch: int = 20
var subsurface_depth: int = 3
var lake_level: int = 40
var shore_band: int = 2
var mossy_chance: float = 0.1
var material_ids: Dictionary = {}
var structures_cfg: Array = []

var _height_noise := FastNoiseLite.new()
var _lake_noise := FastNoiseLite.new()
var _aux_noise := FastNoiseLite.new()
var _column_cache: Dictionary = {}
var _structure_cache: Dictionary = {}   # cell key -> {"blocks": Dictionary, "rect": Rect2i}
var _cache_mutex := Mutex.new()
const CACHE_LIMIT := 4096
const BASIN_MIN := 0.03


func _init(world_seed: int, terrain_cfg: Dictionary, mat_ids: Dictionary, height: int = 128, structures: Array = []) -> void:
	seed = world_seed
	terrain = terrain_cfg
	terrain_type = str(terrain.get("type", "hills_lakes"))
	world_height = height
	material_ids = mat_ids
	structures_cfg = structures
	id_surface = int(mat_ids.get(str(terrain.get("surface", "grass")), 2))
	id_subsurface = int(mat_ids.get(str(terrain.get("subsurface", "dirt")), 1))
	id_deep = int(mat_ids.get(str(terrain.get("deep", "stone")), 3))
	id_shore = int(mat_ids.get(str(terrain.get("shore", "clay")), 5))
	id_fluid = int(mat_ids.get(str(terrain.get("lake_fluid", "co2_water")), 10))
	id_mossy = int(mat_ids.get("mossy_stone", id_deep))
	id_patch = int(mat_ids.get("dry_grass", id_surface))
	subsurface_depth = int(terrain.get("subsurface_depth", 3))
	lake_level = int(terrain.get("lake_level", 40))
	if terrain_type == "beach":
		lake_level = int(terrain.get("sea_level", 34))
	shore_band = int(terrain.get("shore_band", 2))
	mossy_chance = float(terrain.get("mossy_chance", 0.1))

	_height_noise.seed = seed
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = float(terrain.get("frequency", terrain.get("dune_frequency", 0.011)))
	_height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_height_noise.fractal_octaves = int(terrain.get("octaves", 4))
	_height_noise.fractal_lacunarity = 2.0
	_height_noise.fractal_gain = 0.5

	_lake_noise.seed = seed + 7919
	_lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lake_noise.frequency = float(terrain.get("lake_noise_frequency", terrain.get("fissure_frequency", terrain.get("pool_frequency", 0.004))))
	_lake_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

	_aux_noise.seed = seed + 104729
	_aux_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_aux_noise.frequency = float(terrain.get("grass_patch_frequency", 0.05))
	_aux_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


# ---------------- per-type height functions ----------------

## Lake "basin" factor 0..1 at a column (hills_lakes only).
func basin_at(x: int, z: int) -> float:
	if terrain_type != "hills_lakes":
		return 0.0
	var n := _lake_noise.get_noise_2d(float(x), float(z))
	var t := float(terrain.get("lake_threshold", 0.18))
	return smoothstep(t, t + 0.22, n)


func height_at(x: int, z: int) -> int:
	match terrain_type:
		"farmland":
			return _height_farmland(x, z)
		"beach":
			return _height_beach(x, z)
	return _height_hills(x, z)


func _height_hills(x: int, z: int) -> int:
	var base := float(terrain.get("base_height", 50))
	var amp := float(terrain.get("amplitude", 12))
	var h := base + amp * _height_noise.get_noise_2d(float(x), float(z))
	h = maxf(h, float(lake_level) + 1.0)
	var basin := basin_at(x, z)
	if basin > 0.0:
		var bowl := float(lake_level) - 2.0 - 6.0 * basin
		h = lerpf(h, bowl, clampf(basin * 1.6, 0.0, 1.0))
	return clampi(int(floor(h)), 1, world_height - 2)


func _height_farmland(x: int, z: int) -> int:
	var base := float(terrain.get("base_height", 48))
	var amp := float(terrain.get("amplitude", 3))
	var h := base + amp * _height_noise.get_noise_2d(float(x), float(z))
	if _lake_noise.get_noise_2d(float(x), float(z)) > float(terrain.get("fissure_threshold", 0.55)):
		h -= float(terrain.get("fissure_depth", 4))
	return clampi(int(floor(h)), 1, world_height - 2)


func _height_beach(x: int, z: int) -> int:
	var sea := float(lake_level)
	var coast := float(terrain.get("coast_z", 0))
	var h: float
	if float(z) < coast:
		h = sea - 2.0 - (coast - float(z)) * float(terrain.get("seabed_slope", 0.06))
	else:
		var rise := minf((float(z) - coast) * float(terrain.get("land_slope", 0.045)), float(terrain.get("max_rise", 14)))
		h = sea + 1.0 + rise + float(terrain.get("dune_amplitude", 2.5)) * _height_noise.get_noise_2d(float(x), float(z))
		# Tidal pools on the lower beach.
		if rise < 4.0 and _lake_noise.get_noise_2d(float(x), float(z)) > float(terrain.get("pool_threshold", 0.45)):
			h = sea - 1.0
	return clampi(int(floor(h)), 6, world_height - 2)


func is_lake_column(x: int, z: int) -> bool:
	match terrain_type:
		"farmland":
			return false
		"beach":
			return height_at(x, z) < lake_level
	return basin_at(x, z) > BASIN_MIN and height_at(x, z) < lake_level


## Surface block for a column (type-specific detail like grass patches).
func surface_id(x: int, z: int, h: int) -> int:
	match terrain_type:
		"farmland":
			if _aux_noise.get_noise_2d(float(x), float(z)) > float(terrain.get("grass_patch_threshold", 0.3)):
				return id_patch
			return id_surface
	return id_surface


func cell_hash(x: int, y: int, z: int) -> float:
	var h := int(x) * 374761393 + int(y) * 668265263 + int(z) * 2147483647 + seed * 97
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)


func _column_data(cx: int, cz: int) -> PackedInt32Array:
	var key := Vector2i(cx, cz)
	_cache_mutex.lock()
	var cached: Variant = _column_cache.get(key)
	_cache_mutex.unlock()
	if cached != null:
		return cached
	var data := PackedInt32Array()
	data.resize(Chunk.SIZE * Chunk.SIZE * 2)
	var ox := cx * Chunk.SIZE
	var oz := cz * Chunk.SIZE
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var i := z * Chunk.SIZE + x
			data[i] = height_at(ox + x, oz + z)
			var basin := 0
			match terrain_type:
				"hills_lakes":
					basin = int(basin_at(ox + x, oz + z) * 1000.0)
				"beach":
					basin = 1000 if data[i] < lake_level else 0
			data[256 + i] = basin
	_cache_mutex.lock()
	if _column_cache.size() > CACHE_LIMIT:
		_column_cache.clear()
	_column_cache[key] = data
	_cache_mutex.unlock()
	return data


# ---------------- structures ----------------

## Structures whose footprint may touch the chunk column, as block maps.
func _structures_for_chunk(cx: int, cz: int) -> Array:
	var out: Array = []
	if structures_cfg.is_empty():
		return out
	var min_x := cx * Chunk.SIZE
	var min_z := cz * Chunk.SIZE
	for s in structures_cfg:
		var cell := int(s.get("cell", 64))
		var kind := str(s.get("generator", ""))
		var fp := StructureGen.footprint(kind)
		# Structure cells overlapping [min_x - fp, min_x + 16] (a structure can
		# extend up to fp from its origin).
		var c0x := WorldData.floor_div(min_x - fp.x - 2, cell)
		var c1x := WorldData.floor_div(min_x + Chunk.SIZE + 1, cell)
		var c0z := WorldData.floor_div(min_z - fp.y - 2, cell)
		var c1z := WorldData.floor_div(min_z + Chunk.SIZE + 1, cell)
		for scz in range(c0z, c1z + 1):
			for scx in range(c0x, c1x + 1):
				var st := _structure_at(kind, s, scx, scz)
				if st.is_empty():
					continue
				var rect: Rect2i = st["rect"]
				if rect.position.x > min_x + Chunk.SIZE + 1 or rect.end.x < min_x - 1 or rect.position.y > min_z + Chunk.SIZE + 1 or rect.end.y < min_z - 1:
					continue
				out.append(st)
	return out


func _structure_at(kind: String, cfg: Dictionary, scx: int, scz: int) -> Dictionary:
	var key := "%s|%d|%d" % [kind, scx, scz]
	_cache_mutex.lock()
	var cached: Variant = _structure_cache.get(key)
	_cache_mutex.unlock()
	if cached != null:
		return cached
	var cell := int(cfg.get("cell", 64))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, kind, scx, scz])
	var result: Dictionary = {}
	if rng.randf() < float(cfg.get("chance", 0.5)):
		var fp := StructureGen.footprint(kind)
		var margin := 3
		var ox := scx * cell + margin + rng.randi_range(0, maxi(0, cell - fp.x - 2 * margin))
		var oz := scz * cell + margin + rng.randi_range(0, maxi(0, cell - fp.y - 2 * margin))
		var prefer := str(cfg.get("prefer", ""))
		if prefer == "high":
			var best_h := -1
			for i in 10:
				var tx := scx * cell + margin + rng.randi_range(0, maxi(0, cell - fp.x - 2 * margin))
				var tz := scz * cell + margin + rng.randi_range(0, maxi(0, cell - fp.y - 2 * margin))
				var th := height_at(tx + fp.x / 2, tz + fp.y / 2)
				if th > best_h and not is_lake_column(tx + fp.x / 2, tz + fp.y / 2):
					best_h = th
					ox = tx
					oz = tz
		elif prefer == "coast":
			var coast := int(terrain.get("coast_z", 0))
			oz = coast + 6 + rng.randi_range(0, 18)
		# Floor height: the median-ish terrain height under the footprint.
		var hs: Array[int] = []
		for z in range(0, fp.y, 2):
			for x in range(0, fp.x, 2):
				hs.append(height_at(ox + x, oz + z))
		hs.sort()
		var base_y := hs[hs.size() / 2]
		if not is_lake_column(ox + fp.x / 2, oz + fp.y / 2):
			var blocks := StructureGen.build(kind, Vector3i(ox, base_y, oz), rng, material_ids, height_at)
			result = {"blocks": blocks, "rect": Rect2i(ox - 1, oz - 1, fp.x + 2, fp.y + 2), "kind": kind, "key": key,
				"npcs": StructureGen.npc_points(kind, Vector3i(ox, base_y, oz)) if cfg.has("npcs") else [], "npc_kind": str(cfg.get("npcs", ""))}
	_cache_mutex.lock()
	if _structure_cache.size() > 512:
		_structure_cache.clear()
	_structure_cache[key] = result
	_cache_mutex.unlock()
	return result


## True if a structure footprint covers this column (props keep out).
func is_structure_column(x: int, z: int) -> bool:
	for st in _structures_for_chunk(WorldData.floor_div(x, Chunk.SIZE), WorldData.floor_div(z, Chunk.SIZE)):
		if (st["rect"] as Rect2i).has_point(Vector2i(x, z)):
			return true
	return false


# ---------------- chunk fill ----------------

func generate(cpos: Vector3i) -> Chunk:
	var c := Chunk.new(cpos)
	var col := _column_data(cpos.x, cpos.z)
	var oy := cpos.y * Chunk.SIZE
	var ox := cpos.x * Chunk.SIZE
	var oz := cpos.z * Chunk.SIZE
	var structs := _structures_for_chunk(cpos.x, cpos.z)
	# Fast path: chunk entirely above the highest surface, any lake and any structure.
	var max_h := 0
	for i in Chunk.SIZE * Chunk.SIZE:
		max_h = maxi(max_h, col[i])
	if oy > maxi(max_h, lake_level) + 12 and structs.is_empty():
		c.generated = true
		c.dirty = false
		return c
	var blocks := c.blocks
	var count := 0
	var has_water := terrain_type != "farmland"
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var ci := z * Chunk.SIZE + x
			var h := col[ci]
			var basin := col[256 + ci]
			var near_lake := basin > int(BASIN_MIN * 1000.0)
			var shore := terrain_type == "hills_lakes" and near_lake and h >= lake_level - shore_band and h <= lake_level + shore_band
			var top_id := surface_id(ox + x, oz + z, h)
			for y in Chunk.SIZE:
				var wy := oy + y
				var id := 0
				if wy == 0:
					id = id_deep
				elif wy < h - subsurface_depth:
					id = id_deep
					if mossy_chance > 0.0 and wy > h - subsurface_depth - 3 and cell_hash(ox + x, wy, oz + z) < mossy_chance:
						id = id_mossy
				elif wy < h:
					id = id_shore if shore else id_subsurface
				elif wy == h:
					if has_water and h < lake_level and near_lake:
						id = id_shore
					else:
						id = id_shore if shore else top_id
				elif has_water and wy <= lake_level and h < lake_level and near_lake:
					id = id_fluid
				if id != 0:
					blocks[(y * Chunk.SIZE + z) * Chunk.SIZE + x] = id
					count += 1
	# Stamp structures.
	for st in structs:
		var bl: Dictionary = st["blocks"]
		for p in bl:
			var wp: Vector3i = p
			var lx := wp.x - ox
			var ly := wp.y - oy
			var lz := wp.z - oz
			if lx < 0 or ly < 0 or lz < 0 or lx >= Chunk.SIZE or ly >= Chunk.SIZE or lz >= Chunk.SIZE:
				continue
			var idx := (ly * Chunk.SIZE + lz) * Chunk.SIZE + lx
			var old := blocks[idx]
			var nid: int = bl[p]
			if old == 0 and nid != 0:
				count += 1
			elif old != 0 and nid == 0:
				count -= 1
			blocks[idx] = nid
	c.blocks = blocks
	c.solid_count = count
	c.generated = true
	c.dirty = count > 0
	return c


## Structures touching a chunk column (for NPC spawning), each with key,
## kind, rect, npcs and npc_kind.
func structures_near_chunk(cx: int, cz: int) -> Array:
	return _structures_for_chunk(cx, cz)
