class_name ChunkMesher
extends RefCounted
## Builds mesh arrays for one chunk with face culling, per-vertex ambient
## occlusion and atlas UVs. Pure: takes block arrays in, returns arrays out,
## so it runs on WorkerThreadPool and in unit tests. Two surfaces: opaque and
## transparent (glass, leaves, fluids). Collision faces exclude fluids.

const CS := Chunk.SIZE

# Face order: +X, -X, +Y, -Y, +Z, -Z
const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
# Quad corners per face (counter-clockwise seen from outside).
const CORNERS := [
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0)],   # +X
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],   # -X
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],   # +Y
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],   # -Y
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)],   # +Z
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0)],   # -Z
]
# Directional shade per face (fake sun from above), multiplied into COLOR.
const FACE_SHADE := [0.80, 0.70, 1.0, 0.45, 0.75, 0.65]

var props: Array[MaterialProps]
var atlas: BlockTextureGen
var _uv_cache: Dictionary = {}  # material*3+face -> PackedVector2Array(4)


func _init(material_props: Array[MaterialProps], texture_atlas: BlockTextureGen) -> void:
	props = material_props
	atlas = texture_atlas
	# Precompute all UV quads so build() is read-only and safe on worker threads.
	for id in props.size():
		for face in 3:
			_uvs_for(id, face)


class Result:
	var cpos: Vector3i
	var opaque: Array = []        # Mesh.ARRAY_MAX arrays or empty
	var transparent: Array = []
	var collision: PackedVector3Array = PackedVector3Array()
	var face_count: int = 0

	func is_empty() -> bool:
		return face_count == 0


## Snapshot of a chunk and its six neighbours' block arrays (copy-on-write,
## so cheap) taken on the main thread before meshing off-thread.
class MeshInput:
	var cpos: Vector3i
	var blocks: PackedByteArray
	var neighbors: Array[PackedByteArray] = []  # same order as DIRS; empty array = unloaded/air

	static func from_world(world: WorldData, chunk: Chunk) -> MeshInput:
		var inp := MeshInput.new()
		inp.cpos = chunk.cpos
		inp.blocks = chunk.blocks.duplicate()
		for d in DIRS:
			var n := world.get_chunk(chunk.cpos + d)
			inp.neighbors.append(n.blocks.duplicate() if n != null else PackedByteArray())
		return inp


func build(inp: MeshInput) -> Result:
	var res := Result.new()
	res.cpos = inp.cpos
	var blocks := inp.blocks
	var origin := Vector3(inp.cpos * CS)

	var o_verts := PackedVector3Array()
	var o_norms := PackedVector3Array()
	var o_uvs := PackedVector2Array()
	var o_cols := PackedColorArray()
	var o_idx := PackedInt32Array()
	var t_verts := PackedVector3Array()
	var t_norms := PackedVector3Array()
	var t_uvs := PackedVector2Array()
	var t_cols := PackedColorArray()
	var t_idx := PackedInt32Array()
	var col_faces := PackedVector3Array()

	for y in CS:
		for z in CS:
			for x in CS:
				var id := blocks[(y * CS + z) * CS + x]
				if id == 0:
					continue
				var mp := props[id]
				for f in 6:
					var d: Vector3i = DIRS[f]
					var nid := _neighbor_id(inp, x + d.x, y + d.y, z + d.z)
					if not _face_visible(mp, nid):
						continue
					var face: int = 1
					if f == 2:
						face = 0
					elif f == 3:
						face = 2
					var uvs := _uvs_for(id, face)
					var shade: float = FACE_SHADE[f]
					var base := Vector3(x, y, z) + origin
					var corners: Array = CORNERS[f]
					var vbase: int
					if mp.transparent:
						vbase = t_verts.size()
					else:
						vbase = o_verts.size()
					var ao: Array[float] = [1.0, 1.0, 1.0, 1.0]
					if not mp.fluid:
						for ci in 4:
							ao[ci] = _vertex_ao(inp, x, y, z, f, corners[ci])
					var alpha := 1.0 - mp.emissive
					for ci in 4:
						var v: Vector3 = base + corners[ci]
						var c := Color(shade * ao[ci], shade * ao[ci], shade * ao[ci], alpha)
						if mp.transparent:
							t_verts.append(v)
							t_norms.append(Vector3(d))
							t_uvs.append(uvs[ci])
							t_cols.append(c)
						else:
							o_verts.append(v)
							o_norms.append(Vector3(d))
							o_uvs.append(uvs[ci])
							o_cols.append(c)
					# Flip the quad diagonal when AO is anisotropic to avoid banding.
					var flip := (ao[0] + ao[2]) < (ao[1] + ao[3])
					# Godot front faces are clockwise; CORNERS are listed counter-clockwise
					# from outside, so wind each triangle in reverse.
					var tri: Array[int]
					if flip:
						tri = [0, 3, 1, 1, 3, 2]
					else:
						tri = [0, 2, 1, 0, 3, 2]
					if mp.transparent:
						for t in tri:
							t_idx.append(vbase + t)
					else:
						for t in tri:
							o_idx.append(vbase + t)
					res.face_count += 1
					if mp.solid:
						for t in tri:
							col_faces.append(base + corners[t])
	if o_verts.size() > 0:
		res.opaque = _arrays(o_verts, o_norms, o_uvs, o_cols, o_idx)
	if t_verts.size() > 0:
		res.transparent = _arrays(t_verts, t_norms, t_uvs, t_cols, t_idx)
	res.collision = col_faces
	return res


static func _arrays(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, c: PackedColorArray, i: PackedInt32Array) -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = i
	return arr


func _face_visible(mp: MaterialProps, nid: int) -> bool:
	if nid == 0:
		return true
	var np := props[nid]
	if mp.transparent:
		# Transparent blocks only draw against air or a different transparent kind.
		return np.transparent and np.id != mp.id
	return np.transparent


func _uvs_for(id: int, face: int) -> PackedVector2Array:
	var key := id * 3 + face
	var cached: Variant = _uv_cache.get(key)
	if cached != null:
		return cached
	var r := atlas.uv_rect(id, face) if atlas != null else Rect2(0, 0, 1, 1)
	var uvs := PackedVector2Array([
		Vector2(r.position.x, r.end.y),
		Vector2(r.position.x, r.position.y),
		Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y),
	])
	_uv_cache[key] = uvs
	return uvs


## Block id at a chunk-local coordinate that may fall into a neighbour.
func _neighbor_id(inp: MeshInput, x: int, y: int, z: int) -> int:
	if x >= 0 and x < CS and y >= 0 and y < CS and z >= 0 and z < CS:
		return inp.blocks[(y * CS + z) * CS + x]
	var n: PackedByteArray
	if x >= CS:
		n = inp.neighbors[0]; x -= CS
	elif x < 0:
		n = inp.neighbors[1]; x += CS
	elif y >= CS:
		n = inp.neighbors[2]; y -= CS
	elif y < 0:
		n = inp.neighbors[3]; y += CS
	elif z >= CS:
		n = inp.neighbors[4]; z -= CS
	else:
		n = inp.neighbors[5]; z += CS
	if n.is_empty():
		# Unloaded neighbour: treat the world floor as solid, everything else as air.
		return 1 if (inp.cpos.y == 0 and y < 0) else 0
	# Diagonal neighbours (two coordinates out of range) are not available; clamp.
	x = clampi(x, 0, CS - 1); y = clampi(y, 0, CS - 1); z = clampi(z, 0, CS - 1)
	return n[(y * CS + z) * CS + x]


func _occludes(inp: MeshInput, x: int, y: int, z: int) -> bool:
	var id := _neighbor_id(inp, x, y, z)
	if id == 0:
		return false
	var p := props[id]
	return p.solid and not p.transparent


## Classic 3-sample ambient occlusion for a face corner.
func _vertex_ao(inp: MeshInput, x: int, y: int, z: int, f: int, corner: Vector3) -> float:
	var d: Vector3i = DIRS[f]
	# Position of the air cell in front of the face.
	var ax := x + d.x
	var ay := y + d.y
	var az := z + d.z
	# The two tangent axes for this face and the corner's sign along them.
	var s1: Vector3i
	var s2: Vector3i
	if d.x != 0:
		s1 = Vector3i(0, 1 if corner.y > 0.5 else -1, 0)
		s2 = Vector3i(0, 0, 1 if corner.z > 0.5 else -1)
	elif d.y != 0:
		s1 = Vector3i(1 if corner.x > 0.5 else -1, 0, 0)
		s2 = Vector3i(0, 0, 1 if corner.z > 0.5 else -1)
	else:
		s1 = Vector3i(1 if corner.x > 0.5 else -1, 0, 0)
		s2 = Vector3i(0, 1 if corner.y > 0.5 else -1, 0)
	var side1 := _occludes(inp, ax + s1.x, ay + s1.y, az + s1.z)
	var side2 := _occludes(inp, ax + s2.x, ay + s2.y, az + s2.z)
	var corner_b := _occludes(inp, ax + s1.x + s2.x, ay + s1.y + s2.y, az + s1.z + s2.z)
	var occ := 0
	if side1 and side2:
		occ = 3
	else:
		occ = int(side1) + int(side2) + int(corner_b)
	return 1.0 - 0.22 * float(occ)
