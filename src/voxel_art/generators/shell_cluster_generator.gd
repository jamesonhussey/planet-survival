class_name ShellClusterGenerator
extends RefCounted
## A few shells half-buried in the sand (planet 02 food), 1/8-block voxels.

const SCALE := 0.125


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var W := 10
	var m := VoxelModel.new(Vector3i(W, 4, W), SCALE)
	var stone := VoxelArt.ramp(ctx, str(params.get("ramp", "stone")), [Color("#8a8a80"), Color("#a8a8a0"), Color("#c8c8c0"), Color("#e0e0d8")])
	var s0 := m.add_ramp(stone)
	var pink := m.add_color(Color("#d8a0a0"))
	m.pivot = Vector3(W * 0.5, 0, W * 0.5)
	for i in rng.randi_range(3, 6):
		var c := Vector3(rng.randf_range(1.5, W - 1.5), 0.5, rng.randf_range(1.5, W - 1.5))
		var r := rng.randf_range(0.9, 1.6)
		m.fill_ellipsoid(c, Vector3(r, r * 0.6, r * 0.8), s0 + rng.randi_range(1, 3))
		if rng.randf() < 0.4:
			m.set_voxel(int(c.x), 1, int(c.z), pink)
	var rig := PartRig.new()
	rig.add_part("shells", m)
	rig.height = 0.3
	rig.collision_box = AABB()
	return rig
