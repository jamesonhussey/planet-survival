class_name ChunkGenerator
extends RefCounted
## Deterministic terrain generator: same seed + planet terrain config => the
## same chunk on every machine, so clients and saves only need edits.
## Thread-safe for reading after construction (FastNoiseLite is immutable
## here and the column cache is guarded by a mutex).

var seed: int = 0
var terrain: Dictionary = {}
var world_height: int = 128
var id_surface: int = 2
var id_subsurface: int = 1
var id_deep: int = 3
var id_shore: int = 5
var id_fluid: int = 10
var id_mossy: int = 14
var subsurface_depth: int = 3
var lake_level: int = 40
var shore_band: int = 2
var mossy_chance: float = 0.1

var _height_noise := FastNoiseLite.new()
var _lake_noise := FastNoiseLite.new()
var _column_cache: Dictionary = {}  # Vector2i (chunk xz) -> PackedInt32Array heights (256) + lake flags
var _lake_cache: Dictionary = {}
var _cache_mutex := Mutex.new()
const CACHE_LIMIT := 4096


func _init(world_seed: int, terrain_cfg: Dictionary, material_ids: Dictionary, height: int = 128) -> void:
	seed = world_seed
	terrain = terrain_cfg
	world_height = height
	id_surface = int(material_ids.get(str(terrain.get("surface", "grass")), 2))
	id_subsurface = int(material_ids.get(str(terrain.get("subsurface", "dirt")), 1))
	id_deep = int(material_ids.get(str(terrain.get("deep", "stone")), 3))
	id_shore = int(material_ids.get(str(terrain.get("shore", "clay")), 5))
	id_fluid = int(material_ids.get(str(terrain.get("lake_fluid", "co2_water")), 10))
	id_mossy = int(material_ids.get("mossy_stone", id_deep))
	subsurface_depth = int(terrain.get("subsurface_depth", 3))
	lake_level = int(terrain.get("lake_level", 40))
	shore_band = int(terrain.get("shore_band", 2))
	mossy_chance = float(terrain.get("mossy_chance", 0.1))

	_height_noise.seed = seed
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = float(terrain.get("frequency", 0.011))
	_height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_height_noise.fractal_octaves = int(terrain.get("octaves", 4))
	_height_noise.fractal_lacunarity = 2.0
	_height_noise.fractal_gain = 0.5

	_lake_noise.seed = seed + 7919
	_lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lake_noise.frequency = float(terrain.get("lake_noise_frequency", 0.004))
	_lake_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


## Lake "basin" factor 0..1 at a column: 0 = dry land, 1 = lake centre.
func basin_at(x: int, z: int) -> float:
	var n := _lake_noise.get_noise_2d(float(x), float(z))  # -1..1
	var t := float(terrain.get("lake_threshold", 0.18))
	return smoothstep(t, t + 0.22, n)


## Columns with basin below this are plain land (never filled with lake fluid).
const BASIN_MIN := 0.03


## Terrain surface height (y of the top solid block) at a column. Land never
## dips below lake level outside a basin, so lakes have no water cliffs.
func height_at(x: int, z: int) -> int:
	var base := float(terrain.get("base_height", 50))
	var amp := float(terrain.get("amplitude", 12))
	var h := base + amp * _height_noise.get_noise_2d(float(x), float(z))
	h = maxf(h, float(lake_level) + 1.0)
	var basin := basin_at(x, z)
	if basin > 0.0:
		# Lakes sit in smooth bowls below lake level.
		var bowl := float(lake_level) - 2.0 - 6.0 * basin
		h = lerpf(h, bowl, clampf(basin * 1.6, 0.0, 1.0))
	return clampi(int(floor(h)), 1, world_height - 2)


func is_lake_column(x: int, z: int) -> bool:
	return basin_at(x, z) > BASIN_MIN and height_at(x, z) < lake_level


## Deterministic per-cell hash in [0,1).
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
	# heights[0..255] then basin*1000 in [256..511]
	var data := PackedInt32Array()
	data.resize(Chunk.SIZE * Chunk.SIZE * 2)
	var ox := cx * Chunk.SIZE
	var oz := cz * Chunk.SIZE
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var i := z * Chunk.SIZE + x
			data[i] = height_at(ox + x, oz + z)
			data[256 + i] = int(basin_at(ox + x, oz + z) * 1000.0)
	_cache_mutex.lock()
	if _column_cache.size() > CACHE_LIMIT:
		_column_cache.clear()
	_column_cache[key] = data
	_cache_mutex.unlock()
	return data


func generate(cpos: Vector3i) -> Chunk:
	var c := Chunk.new(cpos)
	var col := _column_data(cpos.x, cpos.z)
	var oy := cpos.y * Chunk.SIZE
	# Fast path: chunk entirely above the highest surface (and above any lake) is air.
	var max_h := 0
	for i in Chunk.SIZE * Chunk.SIZE:
		max_h = maxi(max_h, col[i])
	if oy > maxi(max_h, lake_level):
		c.generated = true
		c.dirty = false
		return c
	var ox := cpos.x * Chunk.SIZE
	var oz := cpos.z * Chunk.SIZE
	var blocks := c.blocks
	var count := 0
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var ci := z * Chunk.SIZE + x
			var h := col[ci]
			var basin := col[256 + ci]
			var near_lake := basin > int(BASIN_MIN * 1000.0)
			var shore := near_lake and h >= lake_level - shore_band and h <= lake_level + shore_band
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
					if h < lake_level and near_lake:
						id = id_shore
					else:
						id = id_shore if shore else id_surface
				elif wy <= lake_level and h < lake_level and near_lake:
					id = id_fluid
				if id != 0:
					blocks[(y * Chunk.SIZE + z) * Chunk.SIZE + x] = id
					count += 1
	c.blocks = blocks
	c.solid_count = count
	c.generated = true
	c.dirty = count > 0
	return c
