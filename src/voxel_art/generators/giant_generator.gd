class_name GiantGenerator
extends RefCounted
## The walker of planet 03: a humanoid built from half-block voxels, about
## fourteen blocks tall, skin like weathered rock with moss on the shoulders
## and back. Same part names as the humanoid so the walk cycle code is shared.

const SCALE := 0.5


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var rock := VoxelArt.ramp(ctx, str(params.get("ramp", "rock")), [Color("#3a3a3a"), Color("#5c5c5a"), Color("#7e7e7a"), Color("#a0a09a")])
	var moss := VoxelArt.ramp(ctx, str(params.get("moss", "grass")), [Color("#3a5a2a"), Color("#56803a"), Color("#78a04e"), Color("#a0c070")])
	var rig := PartRig.new()
	var torso := VoxelModel.new(Vector3i(10, 12, 6), SCALE)
	var tr := torso.add_ramp(rock)
	var tm := torso.add_ramp(moss)
	torso.pivot = Vector3(5, 0, 3)
	torso.fill_box(Vector3i(0, 0, 0), Vector3i(9, 11, 5), tr + 2)
	# Hunched: wider shoulders, mossy back and shoulder tops.
	for z in 6:
		for x in 10:
			if rng.randf() < 0.55:
				torso.set_voxel(x, 11, z, tm + rng.randi_range(0, 2))
	for y in range(3, 12):
		for x in 10:
			if rng.randf() < 0.35:
				torso.set_voxel(x, y, 5, tm + rng.randi_range(0, 2))
	# Cracks.
	for i in 6:
		torso.set_voxel(rng.randi_range(0, 9), rng.randi_range(1, 10), 0, tr)
	rig.add_part("torso", torso, "", Vector3(0, 14 * SCALE, 0))

	var head := VoxelModel.new(Vector3i(6, 5, 6), SCALE)
	var hr := head.add_ramp(rock)
	var eye := head.add_color(Color(0.9, 0.85, 0.6))
	head.pivot = Vector3(3, 0, 3)
	head.fill_box(Vector3i(0, 0, 0), Vector3i(5, 4, 5), hr + 2)
	head.fill_box(Vector3i(1, 4, 1), Vector3i(4, 4, 4), head.add_ramp(moss) + 1)
	head.set_voxel(1, 2, 0, eye)
	head.set_voxel(4, 2, 0, eye)
	rig.add_part("head", head, "torso", Vector3(0, 12 * SCALE, -1 * SCALE))

	for side in [-1, 1]:
		var arm := VoxelModel.new(Vector3i(4, 14, 4), SCALE)
		var ar := arm.add_ramp(rock)
		arm.pivot = Vector3(2, 14, 2)
		arm.fill_box(Vector3i(0, 0, 0), Vector3i(3, 13, 3), ar + 2)
		arm.fill_box(Vector3i(0, 0, 0), Vector3i(3, 2, 3), ar + 1)   # knuckles
		rig.add_part("arm_l" if side < 0 else "arm_r", arm, "torso", Vector3(side * 7 * SCALE, 11 * SCALE, 0))
		var leg := VoxelModel.new(Vector3i(4, 14, 5), SCALE)
		var lr := leg.add_ramp(rock)
		leg.pivot = Vector3(2, 14, 2)
		leg.fill_box(Vector3i(0, 0, 0), Vector3i(3, 13, 3), lr + 2)
		leg.fill_box(Vector3i(0, 0, 0), Vector3i(3, 1, 4), lr + 1)   # foot, toes forward
		rig.add_part("leg_l" if side < 0 else "leg_r", leg, "torso", Vector3(side * 2.5 * SCALE, 0, 0))
	rig.height = (14 + 12 + 5) * SCALE
	rig.collision_box = AABB(Vector3(-2.5, 0, -1.5), Vector3(5, rig.height, 3))
	return rig
