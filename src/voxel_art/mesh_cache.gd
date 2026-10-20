class_name VoxelArt
extends RefCounted
## Registry of generators + cache of baked rigs. A rig is keyed by
## (generator, params, seed) so hundreds of props share a handful of meshes.
##   VoxelArt.rig("tree", {"height": [6, 11]}, seed) -> PartRig (baked)

const GENERATORS := {
	"tree": "res://src/voxel_art/generators/tree_generator.gd",
	"lantern": "res://src/voxel_art/generators/lantern_generator.gd",
	"grazer": "res://src/voxel_art/generators/grazer_generator.gd",
	"berry_bush": "res://src/voxel_art/generators/berry_bush_generator.gd",
	"humanoid": "res://src/voxel_art/generators/humanoid_generator.gd",
	"palm": "res://src/voxel_art/generators/palm_generator.gd",
	"dead_tree": "res://src/voxel_art/generators/dead_tree_generator.gd",
	"shell_cluster": "res://src/voxel_art/generators/shell_cluster_generator.gd",
	"roach": "res://src/voxel_art/generators/roach_generator.gd",
	"gasper": "res://src/voxel_art/generators/gasper_generator.gd",
	"crab": "res://src/voxel_art/generators/crab_generator.gd",
}

static var _cache: Dictionary = {}
static var _scripts: Dictionary = {}
static var stats_built: int = 0
static var stats_ms: int = 0


static func cache_key(generator: String, params: Dictionary, seed: int) -> String:
	return "%s|%s|%d" % [generator, JSON.stringify(params), seed]


static func rig(generator: String, params: Dictionary, seed: int, palette_id: String = "04") -> PartRig:
	var key := cache_key(generator, params, seed)
	var cached: PartRig = _cache.get(key)
	if cached != null:
		return cached
	var script: GDScript = _scripts.get(generator)
	if script == null:
		var path: String = GENERATORS.get(generator, "")
		if path == "":
			push_error("[voxel_art] unknown generator '%s'" % generator)
			return null
		script = load(path)
		_scripts[generator] = script
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ctx := {"palette_id": palette_id}
	var r: PartRig = script.generate(params, rng, ctx)
	r.id = key
	r.bake()
	_cache[key] = r
	stats_built += 1
	stats_ms += Time.get_ticks_msec() - t0
	return r


## Deterministic variant seed for a prop at a world cell.
static func variant_seed(base_seed: int, generator: String, variants: int, x: int, z: int) -> int:
	var h := x * 73856093 ^ z * 19349663 ^ base_seed * 83492791 ^ generator.hash()
	h = h & 0x7FFFFFFF
	return base_seed * 1000 + generator.hash() % 1000 + (h % maxi(1, variants))


static func clear_cache() -> void:
	_cache.clear()


## Helper for generators: ramp colours from the planet palette, with a
## fallback so unit tests run without the Data autoload.
static func ramp(ctx: Dictionary, name: String, fallback: Array[Color]) -> Array[Color]:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("Data"):
		var data: Node = tree.root.get_node("Data")
		if data.get("loaded"):
			var r: Array[Color] = data.palette_ramp(str(ctx.get("palette_id", "04")), name)
			if not r.is_empty() and r[0] != Color.MAGENTA:
				return r
	return fallback
