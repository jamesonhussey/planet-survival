class_name RoachGenerator
extends RefCounted
## A hand-sized roach at 1/16-block voxels: body, head, six legs, antennae.
## One part (rendered by the swarm MultiMesh). Params: ramp (shell colours),
## size multiplier via rng.

const SCALE := 1.0 / 16.0


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var ramp := VoxelArt.ramp(ctx, str(params.get("ramp", "roach")), [Color("#2a1a10"), Color("#4e2e18"), Color("#7a4a26"), Color("#a86c3a")])
	var k := rng.randf_range(0.9, 1.3)
	var L := int(10 * k)
	var Wd := int(5 * k) + 1
	var m := VoxelModel.new(Vector3i(L + 6, 5, Wd + 6), SCALE)
	var c0 := m.add_ramp(ramp)
	var cx := (L + 6) * 0.5
	var cz := (Wd + 6) * 0.5
	m.pivot = Vector3(cx, 0, cz)
	var seed := rng.randi()
	var pick := func(x: int, y: int, z: int) -> int:
		var n := TreeGenerator._hash3(x, y, z, seed)
		return c0 + (1 if y < 2 else (2 if n < 0.75 else 3))
	m.fill_ellipsoid(Vector3(cx, 1.5, cz), Vector3(L * 0.5, 1.6, Wd * 0.5), c0 + 2, pick)
	# Head
	m.fill_ellipsoid(Vector3(cx + L * 0.5 + 0.5, 1.4, cz), Vector3(1.4, 1.2, 1.4), c0)
	# Legs: three per side
	for i in 3:
		var lx := int(cx - L * 0.3 + i * L * 0.3)
		for side in [-1, 1]:
			var z0 := int(cz + side * (Wd * 0.5))
			m.set_voxel(lx, 1, z0 + side, c0 + 1)
			m.set_voxel(lx, 0, z0 + side * 2, c0 + 1)
	# Antennae
	for side in [-1, 1]:
		for s in 3:
			m.set_voxel(int(cx + L * 0.5 + 2 + s), 2 + (1 if s > 0 else 0), int(cz + side * (1 + s)), c0)
	var rig := PartRig.new()
	rig.add_part("roach", m)
	rig.height = 0.3
	rig.collision_box = AABB()
	return rig
