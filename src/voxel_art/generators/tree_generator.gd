class_name TreeGenerator
extends RefCounted
## Seeded tree: leaning trunk, a few branches, a canopy of overlapping leaf
## blobs with colour noise. 1/4-block voxels (trees are big). Params:
##   height: [min, max] blocks   canopy: [min, max] radius in blocks
##   ramp: leaf palette ramp name   bark: bark ramp name

const SCALE := 0.25


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var h_range: Array = params.get("height", [6, 10])
	var c_range: Array = params.get("canopy", [2.2, 3.4])
	var height_blocks := rng.randf_range(float(h_range[0]), float(h_range[1]))
	var canopy_blocks := rng.randf_range(float(c_range[0]), float(c_range[1]))
	var vpb := int(round(1.0 / SCALE))   # voxels per block
	var H := int(height_blocks * vpb)
	var R := int(canopy_blocks * vpb)
	var W := R * 2 + 6
	var m := VoxelModel.new(Vector3i(W, H + R + 2, W), SCALE)
	var leaf_ramp := VoxelArt.ramp(ctx, str(params.get("ramp", "leaf")), [Color("#1f4a2a"), Color("#2f6e3a"), Color("#4f9a4a"), Color("#8fd19a")])
	var bark_ramp := VoxelArt.ramp(ctx, str(params.get("bark", "bark")), [Color("#2a1e14"), Color("#4a3522"), Color("#6a4f34"), Color("#8a6a48")])
	var leaf0 := m.add_ramp(leaf_ramp)
	var bark0 := m.add_ramp(bark_ramp)
	var cx := W * 0.5
	var cz := W * 0.5
	m.pivot = Vector3(cx, 0, cz)

	# Trunk: slight lean, tapering.
	var lean := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6)) * vpb / float(maxi(H, 1))
	var trunk_top := int(H * 0.72)
	for y in trunk_top + 1:
		var t := float(y) / float(maxi(trunk_top, 1))
		var half := lerpf(0.55 * vpb, 0.28 * vpb, t)
		var shade := bark0 + (1 if (y / 3) % 2 == 0 else 2)
		m.fill_column(cx + lean.x * y, cz + lean.y * y, y, y, half, shade)
	# Roots
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		m.fill_column(cx + cos(a) * 0.7 * vpb, cz + sin(a) * 0.7 * vpb, 0, int(0.35 * vpb), 0.3 * vpb, bark0)
	# Branches
	var branches := rng.randi_range(2, 4)
	var tips: Array[Vector3] = []
	for i in branches:
		var a := rng.randf() * TAU
		var y0 := int(lerpf(H * 0.45, H * 0.7, rng.randf()))
		var len := rng.randf_range(0.8, 1.6) * vpb * (canopy_blocks * 0.5)
		var steps := int(len)
		for s in steps:
			var f := float(s) / float(maxi(steps, 1))
			var px := cx + lean.x * y0 + cos(a) * f * len
			var pz := cz + lean.y * y0 + sin(a) * f * len
			var py := y0 + int(f * len * 0.6)
			m.fill_column(px, pz, py, py, 0.25 * vpb, bark0 + 1)
			if s == steps - 1:
				tips.append(Vector3(px, py, pz))
	# Canopy: blobs at trunk top and branch tips, colour by height + noise.
	var top := Vector3(cx + lean.x * trunk_top, trunk_top + R * 0.35, cz + lean.y * trunk_top)
	var pick := func(x: int, y: int, z: int) -> int:
		var n := _hash3(x, y, z, rng.seed)
		var t := clampf(float(y - trunk_top) / float(maxi(R * 2, 1)) + (n - 0.5) * 0.5, 0.0, 0.999)
		var i := int(t * 3.0)
		if n < 0.08:
			i = mini(i + 1, 3)
		return leaf0 + i
	m.fill_ellipsoid(top, Vector3(R, R * 0.8, R), leaf0, pick)
	for tip in tips:
		m.fill_ellipsoid(tip + Vector3(0, R * 0.3, 0), Vector3(R * 0.55, R * 0.45, R * 0.55), leaf0, pick)
	for i in rng.randi_range(2, 4):
		var off := Vector3(rng.randf_range(-R, R), rng.randf_range(-R * 0.3, R * 0.5), rng.randf_range(-R, R)) * 0.7
		m.fill_ellipsoid(top + off, Vector3(R * 0.6, R * 0.5, R * 0.6), leaf0, pick)
	# Holes for silhouette interest
	for i in rng.randi_range(3, 6):
		var off := Vector3(rng.randf_range(-R, R), rng.randf_range(-R * 0.4, R * 0.6), rng.randf_range(-R, R))
		var c := top + off
		var rr := rng.randf_range(0.8, 1.6)
		for y in range(int(c.y - rr), int(c.y + rr) + 1):
			for z in range(int(c.z - rr), int(c.z + rr) + 1):
				for x in range(int(c.x - rr), int(c.x + rr) + 1):
					if Vector3(x, y, z).distance_to(c) <= rr and m.get_voxel(x, y, z) - 1 >= leaf0 and m.get_voxel(x, y, z) - 1 < leaf0 + 4:
						m.clear_voxel(x, y, z)

	var rig := PartRig.new()
	rig.add_part("tree", m)
	rig.height = (H + R) * SCALE
	rig.collision_box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, trunk_top * SCALE, 0.6))
	return rig


static func _hash3(x: int, y: int, z: int, seed: int) -> float:
	var h := x * 374761393 + y * 668265263 + z * 2147483647 + seed * 97
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
