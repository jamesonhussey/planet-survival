class_name ChunkStreamer
extends Node3D
## Keeps chunks loaded and meshed around focus points (players). Generation
## and meshing run on WorkerThreadPool; results are applied on the main
## thread. Generation runs one chunk further out than meshing so every meshed
## chunk has all its neighbours. Server and clients both run one of these
## (clients get edits replicated into the same WorldData).

var world: WorldData
var mesher: ChunkMesher
var opaque_material: Material
var transparent_material: Material
var load_radius: int = 5            # chunks (horizontal) that get meshed
var unload_margin: int = 3
var max_inflight: int = 24
var max_apply_per_frame: int = 10
var focus_points: Array[Vector3] = []
var enabled: bool = true
var verbose: bool = false
var _shutting_down: bool = false

var _nodes: Dictionary = {}          # cpos -> MeshInstance3D
var _bodies: Dictionary = {}         # cpos -> StaticBody3D
var _pending_gen: Dictionary = {}    # cpos -> task id
var _pending_mesh: Dictionary = {}   # cpos -> task id
var _results_mutex := Mutex.new()
var _gen_results: Array = []         # Chunk
var _mesh_results: Array = []        # ChunkMesher.Result
var _frame: int = 0
var _wanted: Array[Vector3i] = []    # sorted by distance, recomputed periodically
var _last_focus_chunk := Vector3i(1 << 20, 0, 0)

signal chunk_meshed(cpos: Vector3i)


func setup(world_data: WorldData, chunk_mesher: ChunkMesher, opaque: Material, transparent: Material) -> void:
	world = world_data
	mesher = chunk_mesher
	opaque_material = opaque
	transparent_material = transparent
	world.block_changed.connect(_on_block_changed)


func set_focus(points: Array[Vector3]) -> void:
	focus_points = points


## Synchronously generate + mesh a small area so the player has ground to
## stand on before the first frame.
func preload_around(pos: Vector3, radius: int) -> void:
	var cc := WorldData.chunk_pos_of(Vector3i(pos.floor()))
	var gen_r := radius + 1
	for dz in range(-gen_r, gen_r + 1):
		for dx in range(-gen_r, gen_r + 1):
			for cy in world.chunk_y_count():
				world.get_or_generate_chunk(Vector3i(cc.x + dx, cy, cc.z + dz))
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			for cy in world.chunk_y_count():
				var cpos := Vector3i(cc.x + dx, cy, cc.z + dz)
				var c := world.get_chunk(cpos)
				if c != null and c.dirty and not c.is_empty():
					_apply_mesh(mesher.build(ChunkMesher.MeshInput.from_world(world, c)))
					c.dirty = false


func _exit_tree() -> void:
	# Worker jobs capture `self`; wait for every in-flight task before the
	# node is freed so no job touches a dead object.
	_shutting_down = true
	for tid in _pending_gen.values():
		WorkerThreadPool.wait_for_task_completion(tid)
	for tid in _pending_mesh.values():
		WorkerThreadPool.wait_for_task_completion(tid)
	_pending_gen.clear()
	_pending_mesh.clear()


func _process(_delta: float) -> void:
	if not enabled or world == null or _shutting_down:
		return
	_frame += 1
	var t0 := Time.get_ticks_usec()
	_collect_results()
	if verbose and _frame % 20 == 0:
		print("[streamer] frame %d: %d loaded, %d meshed, %d gen + %d mesh in flight, collect %d us" % [_frame, world.chunks.size(), _nodes.size(), _pending_gen.size(), _pending_mesh.size(), Time.get_ticks_usec() - t0])
	if focus_points.is_empty():
		return
	var fc := WorldData.chunk_pos_of(Vector3i(focus_points[0].floor()))
	if fc != _last_focus_chunk or _frame % 30 == 0:
		_last_focus_chunk = fc
		_recompute_wanted(fc)
		_unload_far(fc)
	_schedule()


func _recompute_wanted(fc: Vector3i) -> void:
	_wanted.clear()
	var r := load_radius + 1
	var cols: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			cols.append(Vector2i(dx, dz))
	cols.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())
	for c in cols:
		for cy in world.chunk_y_count():
			var cpos := Vector3i(fc.x + c.x, cy, fc.z + c.y)
			if world.chunk_in_bounds(cpos):
				_wanted.append(cpos)


func _unload_far(fc: Vector3i) -> void:
	var limit := load_radius + 1 + unload_margin
	var to_remove: Array[Vector3i] = []
	for cpos in world.chunks.keys():
		if absi(cpos.x - fc.x) > limit or absi(cpos.z - fc.z) > limit:
			to_remove.append(cpos)
	for cpos in to_remove:
		if _pending_gen.has(cpos) or _pending_mesh.has(cpos):
			continue
		_free_node(cpos)
		world.unload_chunk(cpos)
		EventBus.chunk_unloaded.emit(cpos)


func _schedule() -> void:
	var inflight := _pending_gen.size() + _pending_mesh.size()
	if inflight >= max_inflight:
		return
	var mesh_r := load_radius
	var fc := _last_focus_chunk
	for cpos in _wanted:
		if inflight >= max_inflight:
			break
		var c := world.get_chunk(cpos)
		if c == null:
			if not _pending_gen.has(cpos):
				_pending_gen[cpos] = WorkerThreadPool.add_task(_gen_job.bind(cpos), true, "gen %s" % str(cpos))
				inflight += 1
			continue
		if not c.dirty or c.is_empty() or _pending_mesh.has(cpos):
			continue
		if absi(cpos.x - fc.x) > mesh_r or absi(cpos.z - fc.z) > mesh_r:
			continue
		if not _neighbors_ready(cpos):
			continue
		var inp := ChunkMesher.MeshInput.from_world(world, c)
		c.dirty = false
		_pending_mesh[cpos] = WorkerThreadPool.add_task(_mesh_job.bind(inp), true, "mesh %s" % str(cpos))
		inflight += 1


func _neighbors_ready(cpos: Vector3i) -> bool:
	for d in ChunkMesher.DIRS:
		var n := cpos + d
		if world.chunk_in_bounds(n) and not world.is_loaded(n):
			return false
	return true


func _gen_job(cpos: Vector3i) -> void:
	var c := world.generator.generate(cpos)
	if _shutting_down:
		return
	_results_mutex.lock()
	_gen_results.append(c)
	_results_mutex.unlock()


func _mesh_job(inp: ChunkMesher.MeshInput) -> void:
	var r := mesher.build(inp)
	if _shutting_down:
		return
	_results_mutex.lock()
	_mesh_results.append(r)
	_results_mutex.unlock()


func _collect_results() -> void:
	_results_mutex.lock()
	var gens := _gen_results
	var meshes := _mesh_results
	_gen_results = []
	_mesh_results = []
	_results_mutex.unlock()
	for c in gens:
		var tid: int = _pending_gen.get(c.cpos, -1)
		if tid >= 0:
			WorkerThreadPool.wait_for_task_completion(tid)
			_pending_gen.erase(c.cpos)
		if world.insert_chunk(c):
			for d in ChunkMesher.DIRS:
				var n := world.get_chunk(c.cpos + d)
				if n != null:
					n.dirty = true
			EventBus.chunk_loaded.emit(c.cpos)
	var applied := 0
	for r in meshes:
		var tid: int = _pending_mesh.get(r.cpos, -1)
		if tid >= 0:
			WorkerThreadPool.wait_for_task_completion(tid)
			_pending_mesh.erase(r.cpos)
		if world.is_loaded(r.cpos):
			_apply_mesh(r)
			applied += 1
		if applied >= max_apply_per_frame:
			# Put the rest back for next frame.
			var idx := meshes.find(r)
			_results_mutex.lock()
			for k in range(idx + 1, meshes.size()):
				_mesh_results.append(meshes[k])
			_results_mutex.unlock()
			break


func _apply_mesh(r: ChunkMesher.Result) -> void:
	if r.is_empty():
		_free_node(r.cpos)
		return
	var mi: MeshInstance3D = _nodes.get(r.cpos)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "chunk_%d_%d_%d" % [r.cpos.x, r.cpos.y, r.cpos.z]
		add_child(mi)
		_nodes[r.cpos] = mi
	var mesh := ArrayMesh.new()
	if not r.opaque.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.opaque)
		mesh.surface_set_material(mesh.get_surface_count() - 1, opaque_material)
	if not r.transparent.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.transparent)
		mesh.surface_set_material(mesh.get_surface_count() - 1, transparent_material)
	mi.mesh = mesh
	var body: StaticBody3D = _bodies.get(r.cpos)
	if r.collision.size() > 0:
		if body == null:
			body = StaticBody3D.new()
			body.name = "body"
			body.collision_layer = 1
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.name = "shape"
			body.add_child(cs)
			mi.add_child(body)
			_bodies[r.cpos] = body
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(r.collision)
		(body.get_node("shape") as CollisionShape3D).shape = shape
	elif body != null:
		body.queue_free()
		_bodies.erase(r.cpos)
	chunk_meshed.emit(r.cpos)


func _free_node(cpos: Vector3i) -> void:
	var mi: MeshInstance3D = _nodes.get(cpos)
	if mi != null:
		mi.queue_free()
		_nodes.erase(cpos)
	_bodies.erase(cpos)


func _on_block_changed(pos: Vector3i, _old: int, _new: int) -> void:
	# Mark the chunk and any neighbour sharing a face dirty for remeshing.
	var cpos := WorldData.chunk_pos_of(pos)
	var l := WorldData.local_of(pos)
	var c := world.get_chunk(cpos)
	if c != null:
		c.dirty = true
	var touch: Array[Vector3i] = []
	if l.x == 0: touch.append(cpos + Vector3i(-1, 0, 0))
	if l.x == Chunk.SIZE - 1: touch.append(cpos + Vector3i(1, 0, 0))
	if l.y == 0: touch.append(cpos + Vector3i(0, -1, 0))
	if l.y == Chunk.SIZE - 1: touch.append(cpos + Vector3i(0, 1, 0))
	if l.z == 0: touch.append(cpos + Vector3i(0, 0, -1))
	if l.z == Chunk.SIZE - 1: touch.append(cpos + Vector3i(0, 0, 1))
	for n in touch:
		var nc := world.get_chunk(n)
		if nc != null:
			nc.dirty = true


## Immediately remesh a chunk on the main thread (used after player edits so
## the hole appears this frame rather than after a worker round trip).
func remesh_now(cpos: Vector3i) -> void:
	var c := world.get_chunk(cpos)
	if c == null:
		return
	if _pending_mesh.has(cpos):
		return
	_apply_mesh(mesher.build(ChunkMesher.MeshInput.from_world(world, c)))
	c.dirty = false


func loaded_count() -> int:
	return world.chunks.size()


func meshed_count() -> int:
	return _nodes.size()
