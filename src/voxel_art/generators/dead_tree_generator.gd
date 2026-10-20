class_name DeadTreeGenerator
extends RefCounted
## A bare, twisted dead tree at 1/4-block voxels (planet 01). Params:
## height [min,max] blocks, ramp (dead wood colours).

const SCALE := 0.25


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var h_range: Array = params.get("height", [4, 8])
	var H := int(rng.randf_range(float(h_range[0]), float(h_range[1])) * 4)
	var W := 22
	var m := VoxelModel.new(Vector3i(W, H + 10, W), SCALE)
	var wood := VoxelArt.ramp(ctx, str(params.get("ramp", "dead")), [Color("#2a2420"), Color("#4a403a"), Color("#6a5e56"), Color("#8a7e76")])
	var w0 := m.add_ramp(wood)
	var cx := W * 0.5
	var cz := W * 0.5
	m.pivot = Vector3(cx, 0, cz)
	var lean := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8)) / float(maxi(H, 1))
	for y in H + 1:
		var t := float(y) / float(H)
		m.fill_column(cx + lean.x * y * 2.0, cz + lean.y * y * 2.0, y, y, lerpf(2.0, 0.8, t), w0 + (1 if y % 4 < 2 else 0))
	# Branches: crooked segments climbing outward.
	for i in rng.randi_range(3, 6):
		var y0 := int(lerpf(H * 0.4, H * 0.95, rng.randf()))
		var a := rng.randf() * TAU
		var p := Vector3(cx + lean.x * y0 * 2.0, y0, cz + lean.y * y0 * 2.0)
		var dir := Vector3(cos(a), 0.7, sin(a)).normalized()
		for s in rng.randi_range(5, 10):
			p += dir
			dir = (dir + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.4, 0.4))).normalized()
			m.set_voxel(int(p.x), int(p.y), int(p.z), w0 + 2)
			if s < 3:
				m.set_voxel(int(p.x) + 1, int(p.y), int(p.z), w0 + 1)
	var rig := PartRig.new()
	rig.add_part("tree", m)
	rig.height = H * SCALE
	rig.collision_box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, H * SCALE, 0.6))
	return rig
