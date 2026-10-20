class_name CrabGenerator
extends RefCounted
## Planet 02's sand crab: wide low shell, two claws, eyes on stalks. 1/8 voxels.

const SCALE := 0.125


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var ramp := VoxelArt.ramp(ctx, str(params.get("ramp", "sand")), [Color("#b89a62"), Color("#d6b97e"), Color("#ecd59e"), Color("#fbeec4")])
	var k := rng.randf_range(0.9, 1.2)
	var rig := PartRig.new()
	var body := VoxelModel.new(Vector3i(int(12 * k) + 2, 6, int(9 * k) + 2), SCALE)
	var b0 := body.add_ramp(ramp)
	var dark := body.add_color(ramp[0].darkened(0.3))
	var cx := body.size.x * 0.5
	var cz := body.size.z * 0.5
	body.pivot = Vector3(cx, 0, cz)
	body.fill_ellipsoid(Vector3(cx, 2.5, cz), Vector3(6 * k, 2.4, 4.5 * k), b0 + 1)
	for i in 6:
		body.set_voxel(int(cx - 4 + i * 1.6), 4, int(cz), dark)
	# eye stalks
	body.set_voxel(int(cx + 4 * k), 5, int(cz - 2), dark)
	body.set_voxel(int(cx + 4 * k), 5, int(cz + 2), dark)
	rig.add_part("body", body, "", Vector3(0, 2 * SCALE, 0))
	for side in [-1, 1]:
		var claw := VoxelModel.new(Vector3i(6, 4, 4), SCALE)
		var c0 := claw.add_ramp(ramp)
		claw.pivot = Vector3(0, 2, 2)
		claw.fill_box(Vector3i(0, 1, 1), Vector3i(5, 2, 2), c0 + 2)
		claw.fill_box(Vector3i(4, 0, 0), Vector3i(5, 3, 3), c0 + 1)
		claw.fill_box(Vector3i(5, 1, 1), Vector3i(5, 2, 2), -1)
		rig.add_part("claw_l" if side < 0 else "claw_r", claw, "body", Vector3(5 * k * SCALE, 1 * SCALE, side * 3 * SCALE))
		for i in 3:
			var leg := VoxelModel.new(Vector3i(2, 4, 2), SCALE)
			var l0 := leg.add_ramp(ramp)
			leg.pivot = Vector3(1, 4, 1)
			leg.fill_box(Vector3i(0, 0, 0), Vector3i(1, 3, 1), l0)
			rig.add_part("leg_%s%d" % ["l" if side < 0 else "r", i], leg, "body", Vector3((-3 + i * 3) * SCALE, 1 * SCALE, side * (4.5 * k) * SCALE))
	rig.height = 0.9
	rig.collision_box = AABB(Vector3(-0.6, 0, -0.5), Vector3(1.2, 0.9, 1.0))
	return rig
