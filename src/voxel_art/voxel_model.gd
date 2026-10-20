class_name VoxelModel
extends RefCounted
## A dense micro-voxel grid: each cell holds a palette index + 1 (0 = empty).
## `scale` is metres per voxel (1/8 block by default). Generators sculpt
## into this with the helper fills, then VoxelMesher turns it into a mesh.

var size: Vector3i
var voxels: PackedByteArray
var palette: PackedColorArray = PackedColorArray()
var scale: float = 0.125
## Point (in voxel units) that sits at the model's local origin when meshed.
var pivot: Vector3 = Vector3.ZERO


func _init(sz: Vector3i = Vector3i(8, 8, 8), voxel_scale: float = 0.125) -> void:
	size = Vector3i(maxi(1, sz.x), maxi(1, sz.y), maxi(1, sz.z))
	scale = voxel_scale
	voxels = PackedByteArray()
	voxels.resize(size.x * size.y * size.z)


func index(x: int, y: int, z: int) -> int:
	return (y * size.z + z) * size.x + x


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z


func get_voxel(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return 0
	return voxels[(y * size.z + z) * size.x + x]


## `color_index` is an index into `palette`; stored as index + 1.
func set_voxel(x: int, y: int, z: int, color_index: int) -> void:
	if in_bounds(x, y, z):
		voxels[(y * size.z + z) * size.x + x] = color_index + 1


func clear_voxel(x: int, y: int, z: int) -> void:
	if in_bounds(x, y, z):
		voxels[(y * size.z + z) * size.x + x] = 0


func add_color(c: Color) -> int:
	palette.append(c)
	return palette.size() - 1


func add_ramp(colors: Array[Color]) -> int:
	var first := palette.size()
	for c in colors:
		palette.append(c)
	return first


func fill_box(min_c: Vector3i, max_c: Vector3i, color_index: int) -> void:
	for y in range(maxi(min_c.y, 0), mini(max_c.y, size.y - 1) + 1):
		for z in range(maxi(min_c.z, 0), mini(max_c.z, size.z - 1) + 1):
			for x in range(maxi(min_c.x, 0), mini(max_c.x, size.x - 1) + 1):
				voxels[(y * size.z + z) * size.x + x] = color_index + 1


## Ellipsoid fill. `pick` optionally maps (x,y,z) -> color index for texture.
func fill_ellipsoid(center: Vector3, radii: Vector3, color_index: int, pick: Callable = Callable()) -> void:
	var r := Vector3(maxf(radii.x, 0.01), maxf(radii.y, 0.01), maxf(radii.z, 0.01))
	var min_c := Vector3i((center - r).floor())
	var max_c := Vector3i((center + r).ceil())
	for y in range(maxi(min_c.y, 0), mini(max_c.y, size.y - 1) + 1):
		for z in range(maxi(min_c.z, 0), mini(max_c.z, size.z - 1) + 1):
			for x in range(maxi(min_c.x, 0), mini(max_c.x, size.x - 1) + 1):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - center) / r
				if d.length_squared() <= 1.0:
					var ci := color_index
					if pick.is_valid():
						ci = int(pick.call(x, y, z))
					voxels[(y * size.z + z) * size.x + x] = ci + 1


func fill_sphere(center: Vector3, radius: float, color_index: int, pick: Callable = Callable()) -> void:
	fill_ellipsoid(center, Vector3(radius, radius, radius), color_index, pick)


## Vertical column (trunks, posts) from y0 to y1 with the given half width.
func fill_column(cx: float, cz: float, y0: int, y1: int, half: float, color_index: int) -> void:
	for y in range(maxi(y0, 0), mini(y1, size.y - 1) + 1):
		for z in range(int(floor(cz - half)), int(ceil(cz + half)) + 1):
			for x in range(int(floor(cx - half)), int(ceil(cx + half)) + 1):
				if in_bounds(x, y, z) and Vector2(x + 0.5 - cx, z + 0.5 - cz).length() <= half + 0.01:
					voxels[(y * size.z + z) * size.x + x] = color_index + 1


func count() -> int:
	var n := 0
	for v in voxels:
		if v != 0:
			n += 1
	return n


func is_empty() -> bool:
	return count() == 0


## Bounding box (in voxel units) of filled cells, or an empty AABB.
func bounds() -> AABB:
	var min_c := Vector3i(size)
	var max_c := Vector3i(-1, -1, -1)
	for y in size.y:
		for z in size.z:
			for x in size.x:
				if voxels[(y * size.z + z) * size.x + x] != 0:
					min_c = Vector3i(mini(min_c.x, x), mini(min_c.y, y), mini(min_c.z, z))
					max_c = Vector3i(maxi(max_c.x, x), maxi(max_c.y, y), maxi(max_c.z, z))
	if max_c.x < 0:
		return AABB()
	return AABB(Vector3(min_c), Vector3(max_c - min_c + Vector3i.ONE))


func color_at(x: int, y: int, z: int) -> Color:
	var v := get_voxel(x, y, z)
	if v == 0 or v - 1 >= palette.size():
		return Color.MAGENTA
	return palette[v - 1]
