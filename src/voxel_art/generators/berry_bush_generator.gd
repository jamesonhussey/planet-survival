class_name BerryBushGenerator
extends RefCounted
## A low bush at 1/8-block voxels with a few bright berries. Params:
##   ramp: leaf palette ramp   berry: hex colour

const SCALE := 0.125


static func generate(params: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> PartRig:
	var leaf := VoxelArt.ramp(ctx, str(params.get("ramp", "leaf")), [Color("#1f4a2a"), Color("#2f6e3a"), Color("#4f9a4a"), Color("#8fd19a")])
	var berry := Color.html(str(params.get("berry", "#c43a6e")))
	var W := 12
	var H := 9
	var m := VoxelModel.new(Vector3i(W, H, W), SCALE)
	var l0 := m.add_ramp(leaf)
	var b0 := m.add_color(berry)
	var b1 := m.add_color(berry.lightened(0.3))
	m.pivot = Vector3(W * 0.5, 0, W * 0.5)
	var seed := rng.randi()
	var pick := func(x: int, y: int, z: int) -> int:
		var n := TreeGenerator._hash3(x, y, z, seed)
		return l0 + (0 if y < 2 else (1 if n < 0.45 else 2))
	for i in rng.randi_range(3, 5):
		var c := Vector3(W * 0.5 + rng.randf_range(-2.5, 2.5), rng.randf_range(2.5, 4.5), W * 0.5 + rng.randf_range(-2.5, 2.5))
		m.fill_ellipsoid(c, Vector3(rng.randf_range(2.5, 4.0), rng.randf_range(2.0, 3.5), rng.randf_range(2.5, 4.0)), l0, pick)
	# stems
	m.fill_column(W * 0.5, W * 0.5, 0, 2, 0.6, l0)
	# berries on the outside
	for i in rng.randi_range(6, 12):
		var x := rng.randi_range(1, W - 2)
		var y := rng.randi_range(3, H - 2)
		var z := rng.randi_range(1, W - 2)
		if m.get_voxel(x, y, z) != 0 and (m.get_voxel(x, y + 1, z) == 0 or m.get_voxel(x + 1, y, z) == 0 or m.get_voxel(x - 1, y, z) == 0 or m.get_voxel(x, y, z + 1) == 0 or m.get_voxel(x, y, z - 1) == 0):
			m.set_voxel(x, y, z, b0 if rng.randf() < 0.7 else b1)
	var rig := PartRig.new()
	rig.add_part("bush", m)
	rig.height = H * SCALE
	rig.collision_box = AABB()
	return rig
