class_name HumanoidGenerator
extends RefCounted
## A low-detail survivor figure at 1/8-block voxels for remote players and
## (later) NPCs: torso, head, two arms, two legs, each a pivoted part so a
## walk cycle is just rotations. Params: skin (ramp), cloth (hex), seed via rng.

const SCALE := 0.125


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var skin := VoxelArt.ramp(ctx, str(params.get("skin", "skin")), [Color("#4a3a3a"), Color("#7a5a52"), Color("#a88474"), Color("#d0ab96")])
	var cloth := Color.html(str(params.get("cloth", "#3a5a6a")))
	var cloth2 := cloth.darkened(0.3)
	var hair := Color.html(str(params.get("hair", "#2a1e14")))
	var hue_shift := rng.randf_range(-0.05, 0.05)
	cloth = Color.from_hsv(fmod(cloth.h + hue_shift + 1.0, 1.0), cloth.s, cloth.v)
	var rig := PartRig.new()

	var torso := VoxelModel.new(Vector3i(8, 10, 4), SCALE)
	var tc := torso.add_color(cloth)
	var tc2 := torso.add_color(cloth2)
	torso.pivot = Vector3(4, 0, 2)
	torso.fill_box(Vector3i(0, 0, 0), Vector3i(7, 9, 3), tc)
	torso.fill_box(Vector3i(0, 0, 0), Vector3i(7, 2, 3), tc2)   # belt
	torso.fill_box(Vector3i(3, 3, 0), Vector3i(4, 8, 0), tc2)   # zip
	rig.add_part("torso", torso, "", Vector3(0, 12 * SCALE, 0))

	var head := VoxelModel.new(Vector3i(6, 6, 6), SCALE)
	var hs := head.add_ramp(skin)
	var hh := head.add_color(hair)
	var eye := head.add_color(Color(0.05, 0.05, 0.05))
	head.pivot = Vector3(3, 0, 3)
	head.fill_box(Vector3i(0, 0, 0), Vector3i(5, 5, 5), hs + 2)
	head.fill_box(Vector3i(0, 4, 0), Vector3i(5, 5, 5), hh)
	head.fill_box(Vector3i(0, 2, 5), Vector3i(5, 3, 5), hh)      # hair back
	head.set_voxel(1, 2, 0, eye)
	head.set_voxel(4, 2, 0, eye)
	rig.add_part("head", head, "torso", Vector3(0, 10 * SCALE, 0))

	for side in [-1, 1]:
		var arm := VoxelModel.new(Vector3i(3, 10, 3), SCALE)
		var ac := arm.add_color(cloth)
		var asx := arm.add_ramp(skin)
		arm.pivot = Vector3(1.5, 10, 1.5)   # shoulder at top
		arm.fill_box(Vector3i(0, 3, 0), Vector3i(2, 9, 2), ac)
		arm.fill_box(Vector3i(0, 0, 0), Vector3i(2, 2, 2), asx + 2)  # hand
		rig.add_part("arm_l" if side < 0 else "arm_r", arm, "torso", Vector3(side * 5.5 * SCALE, 9 * SCALE, 0))
		var leg := VoxelModel.new(Vector3i(3, 12, 3), SCALE)
		var lc := leg.add_color(cloth2)
		var boot := leg.add_color(Color(0.15, 0.12, 0.1))
		leg.pivot = Vector3(1.5, 12, 1.5)   # hip at top
		leg.fill_box(Vector3i(0, 2, 0), Vector3i(2, 11, 2), lc)
		leg.fill_box(Vector3i(0, 0, 0), Vector3i(2, 1, 2), boot)
		rig.add_part("leg_l" if side < 0 else "leg_r", leg, "torso", Vector3(side * 2 * SCALE, 0, 0))
	rig.height = (12 + 10 + 6) * SCALE
	rig.collision_box = AABB(Vector3(-0.35, 0, -0.35), Vector3(0.7, rig.height, 0.7))
	return rig
