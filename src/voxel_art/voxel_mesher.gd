class_name VoxelMesher
extends RefCounted
## Greedy meshing for micro-voxel models: adjacent same-colour faces merge
## into one quad, so a 16x16x16 block of one colour is 6 quads, not 1536.
## Output is a single-surface ArrayMesh with vertex colours; the voxel
## shader does the rest. Pure and deterministic.

# Mild per-face shade so flat-lit models still read as 3D.
const FACE_SHADE := {Vector3i(0, 1, 0): 1.0, Vector3i(0, -1, 0): 0.62, Vector3i(1, 0, 0): 0.86, Vector3i(-1, 0, 0): 0.78, Vector3i(0, 0, 1): 0.9, Vector3i(0, 0, -1): 0.72}


class Quads:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var quad_count: int = 0


static func build_arrays(m: VoxelModel) -> Quads:
	var q := Quads.new()
	var dims := [m.size.x, m.size.y, m.size.z]
	for d in 3:
		var u := (d + 1) % 3
		var v := (d + 2) % 3
		var x := [0, 0, 0]
		var du := [0, 0, 0]
		var dv := [0, 0, 0]
		var mask := PackedInt32Array()
		mask.resize(dims[u] * dims[v])
		x[d] = -1
		while x[d] < dims[d]:
			# Build mask for the slice between x[d] and x[d]+1.
			var n := 0
			for xv in dims[v]:
				x[v] = xv
				for xu in dims[u]:
					x[u] = xu
					var a := m.get_voxel(x[0], x[1], x[2]) if x[d] >= 0 else 0
					var xb := [x[0], x[1], x[2]]
					xb[d] += 1
					var b := m.get_voxel(xb[0], xb[1], xb[2]) if x[d] < dims[d] - 1 else 0
					if (a != 0) == (b != 0):
						mask[n] = 0
					elif a != 0:
						mask[n] = a          # face points +d
					else:
						mask[n] = -b         # face points -d
					n += 1
			x[d] += 1
			# Greedy merge.
			n = 0
			for j in dims[v]:
				var i := 0
				while i < dims[u]:
					var c := mask[n]
					if c == 0:
						i += 1
						n += 1
						continue
					var w := 1
					while i + w < dims[u] and mask[n + w] == c:
						w += 1
					var h := 1
					var done := false
					while j + h < dims[v] and not done:
						for k in w:
							if mask[n + k + h * dims[u]] != c:
								done = true
								break
						if not done:
							h += 1
					x[u] = i
					x[v] = j
					du = [0, 0, 0]
					dv = [0, 0, 0]
					du[u] = w
					dv[v] = h
					var ci := absi(c) - 1
					var col := m.palette[ci] if ci < m.palette.size() else Color.MAGENTA
					var normal := Vector3i.ZERO
					normal[d] = 1 if c > 0 else -1
					_emit_quad(q, m, x, du, dv, normal, col)
					for l in h:
						for k in w:
							mask[n + k + l * dims[u]] = 0
					i += w
					n += w
	return q


static func _emit_quad(q: Quads, m: VoxelModel, x: Array, du: Array, dv: Array, normal: Vector3i, col: Color) -> void:
	var s := m.scale
	var o := (Vector3(x[0], x[1], x[2]) - m.pivot) * s
	var a := o
	var b := o + Vector3(du[0], du[1], du[2]) * s
	var c := o + Vector3(du[0] + dv[0], du[1] + dv[1], du[2] + dv[2]) * s
	var dd := o + Vector3(dv[0], dv[1], dv[2]) * s
	var shade: float = FACE_SHADE.get(normal, 1.0)
	var vc := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
	var base := q.verts.size()
	for p in [a, b, c, dd]:
		q.verts.append(p)
		q.norms.append(Vector3(normal))
		q.cols.append(vc)
	# Godot front faces are clockwise.
	if normal.x + normal.y + normal.z > 0:
		for t in [0, 2, 1, 0, 3, 2]:
			q.idx.append(base + t)
	else:
		for t in [0, 1, 2, 0, 2, 3]:
			q.idx.append(base + t)
	q.quad_count += 1


static func build_mesh(m: VoxelModel, material: Material = null) -> ArrayMesh:
	var q := build_arrays(m)
	var mesh := ArrayMesh.new()
	if q.verts.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = q.verts
	arr[Mesh.ARRAY_NORMAL] = q.norms
	arr[Mesh.ARRAY_COLOR] = q.cols
	arr[Mesh.ARRAY_INDEX] = q.idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh
