class_name GasperGenerator
extends RefCounted
## Planet 04's lurker: a tall, hunched grey figure with long arms, a small
## head and pale eyes. 1/8-block voxels; parts for arms/legs so it lopes.

const SCALE := 0.125


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var ramp := VoxelArt.ramp(ctx, str(params.get("ramp", "stone")), [Color("#3a4a3a"), Color("#5a6e58"), Color("#7e8e7a"), Color("#a2b09a")])
	var rig := PartRig.new()
	var torso := VoxelModel.new(Vector3i(8, 14, 5), SCALE)
	var t0 := torso.add_ramp(ramp)
	torso.pivot = Vector3(4, 0, 2.5)
	var seed := rng.randi()
	var pick := func(x: int, y: int, z: int) -> int:
		return t0 + (0 if TreeGenerator._hash3(x, y, z, seed) < 0.3 else 1)
	torso.fill_ellipsoid(Vector3(4, 7, 2.5), Vector3(3.6, 7.0, 2.4), t0 + 1, pick)
	rig.add_part("torso", torso, "", Vector3(0, 14 * SCALE, 0))
	var head := VoxelModel.new(Vector3i(5, 5, 5), SCALE)
	var h0 := head.add_ramp(ramp)
	var eye := head.add_color(Color(0.85, 0.95, 0.7))
	head.pivot = Vector3(2.5, 0, 2.5)
	head.fill_ellipsoid(Vector3(2.5, 2.5, 2.5), Vector3(2.2, 2.4, 2.2), h0)
	head.set_voxel(1, 2, 0, eye)
	head.set_voxel(3, 2, 0, eye)
	rig.add_part("head", head, "torso", Vector3(0, 13 * SCALE, 1.5 * SCALE), true)
	for side in [-1, 1]:
		var arm := VoxelModel.new(Vector3i(2, 16, 2), SCALE)
		var a0 := arm.add_ramp(ramp)
		arm.pivot = Vector3(1, 16, 1)
		arm.fill_box(Vector3i(0, 0, 0), Vector3i(1, 15, 1), a0 + (1 if side > 0 else 0))
		rig.add_part("arm_l" if side < 0 else "arm_r", arm, "torso", Vector3(side * 4.5 * SCALE, 12 * SCALE, 0))
		var leg := VoxelModel.new(Vector3i(3, 14, 3), SCALE)
		var l0 := leg.add_ramp(ramp)
		leg.pivot = Vector3(1.5, 14, 1.5)
		leg.fill_box(Vector3i(0, 0, 0), Vector3i(2, 13, 2), l0)
		rig.add_part("leg_l" if side < 0 else "leg_r", leg, "torso", Vector3(side * 2 * SCALE, 0, 0))
	rig.height = (14 + 14 + 5) * SCALE
	rig.collision_box = AABB(Vector3(-0.4, 0, -0.4), Vector3(0.8, rig.height, 0.8))
	return rig
