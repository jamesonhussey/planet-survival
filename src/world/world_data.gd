class_name WorldData
extends RefCounted
## The block grid every system shares: terrain, building and hazard sims all
## read and write through here. Pure data (no nodes) so it runs headless and
## in unit tests. Chunks live in a dictionary keyed by chunk position and are
## generated lazily by `generator`, so the world streams and the horizontal
## bound is just a clamp (`world_size` 0 = unbounded, the door to infinite).

const CS := Chunk.SIZE

var world_size: int = 1024        # blocks per side in x/z, centred on origin; 0 = unbounded
var world_height: int = 128       # blocks; must be a multiple of 16
var chunks: Dictionary = {}       # Vector3i -> Chunk
var generator: ChunkGenerator = null
var props: Array[MaterialProps] = []   # indexed by block id
var _half: int = 512
var _cy_max: int = 7

## Emitted after a block actually changed. Listeners: mesher (remesh), sims.
signal block_changed(pos: Vector3i, old_id: int, new_id: int)


func _init(size: int = 1024, height: int = 128, material_props: Array[MaterialProps] = []) -> void:
	world_size = size
	world_height = maxi(16, (height / CS) * CS)
	_half = world_size / 2
	_cy_max = world_height / CS - 1
	props = material_props


static func floor_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


static func chunk_pos_of(p: Vector3i) -> Vector3i:
	return Vector3i(floor_div(p.x, CS), floor_div(p.y, CS), floor_div(p.z, CS))


static func local_of(p: Vector3i) -> Vector3i:
	return Vector3i(posmod(p.x, CS), posmod(p.y, CS), posmod(p.z, CS))


func in_bounds(p: Vector3i) -> bool:
	if p.y < 0 or p.y >= world_height:
		return false
	if world_size <= 0:
		return true
	return p.x >= -_half and p.x < _half and p.z >= -_half and p.z < _half


func chunk_in_bounds(cpos: Vector3i) -> bool:
	if cpos.y < 0 or cpos.y > _cy_max:
		return false
	if world_size <= 0:
		return true
	var half_c := floor_div(_half, CS)
	return cpos.x >= -half_c and cpos.x < half_c and cpos.z >= -half_c and cpos.z < half_c


func chunk_y_count() -> int:
	return _cy_max + 1


func get_chunk(cpos: Vector3i) -> Chunk:
	return chunks.get(cpos)


func is_loaded(cpos: Vector3i) -> bool:
	return chunks.has(cpos)


## Returns the chunk, generating it if needed and allowed. Null outside bounds
## or when there is no generator.
func get_or_generate_chunk(cpos: Vector3i) -> Chunk:
	var c: Chunk = chunks.get(cpos)
	if c != null:
		return c
	if not chunk_in_bounds(cpos) or generator == null:
		return null
	c = generator.generate(cpos)
	chunks[cpos] = c
	return c


## Insert a chunk produced elsewhere (e.g. on a worker thread). Returns false
## if one is already loaded there.
func insert_chunk(c: Chunk) -> bool:
	if chunks.has(c.cpos):
		return false
	chunks[c.cpos] = c
	return true


func unload_chunk(cpos: Vector3i) -> void:
	chunks.erase(cpos)


## Block id at a world position. Unloaded or out-of-bounds cells read as air,
## except below the floor which reads as stone-like "bedrock" (id 3 if that
## material exists) so nothing falls out of the world.
func get_block(p: Vector3i) -> int:
	if p.y < 0:
		return 3 if props.size() > 3 else 1
	if p.y >= world_height:
		return 0
	var c: Chunk = chunks.get(Vector3i(floor_div(p.x, CS), floor_div(p.y, CS), floor_div(p.z, CS)))
	if c == null:
		return 0
	return c.blocks[(posmod(p.y, CS) * CS + posmod(p.z, CS)) * CS + posmod(p.x, CS)]


## Sets a block in a loaded chunk. Returns true if something changed.
func set_block(p: Vector3i, id: int, mark_edited: bool = true) -> bool:
	if not in_bounds(p):
		return false
	var c: Chunk = chunks.get(chunk_pos_of(p))
	if c == null:
		return false
	var l := local_of(p)
	var old := c.get_local(l.x, l.y, l.z)
	if old == id:
		return false
	c.set_local(l.x, l.y, l.z, id)
	if mark_edited:
		c.edited = true
	block_changed.emit(p, old, id)
	return true


func block_props(p: Vector3i) -> MaterialProps:
	var id := get_block(p)
	if id < 0 or id >= props.size():
		return props[0] if props.size() > 0 else MaterialProps.new()
	return props[id]


func is_solid(p: Vector3i) -> bool:
	var id := get_block(p)
	if props.is_empty():
		return id != 0
	return props[id].solid if id < props.size() else false


## Highest non-air block y in a loaded column, or -1 if none loaded/solid.
func surface_y(x: int, z: int) -> int:
	for cy in range(_cy_max, -1, -1):
		var c: Chunk = chunks.get(Vector3i(floor_div(x, CS), cy, floor_div(z, CS)))
		if c == null or c.is_empty():
			continue
		var lx := posmod(x, CS)
		var lz := posmod(z, CS)
		for ly in range(CS - 1, -1, -1):
			var id := c.blocks[(ly * CS + lz) * CS + lx]
			if id != 0 and (props.is_empty() or props[id].solid):
				return cy * CS + ly
	return -1


## Chunks whose generated content was modified (what a save must persist).
func edited_chunks() -> Array[Chunk]:
	var out: Array[Chunk] = []
	for c in chunks.values():
		if c.edited:
			out.append(c)
	return out
