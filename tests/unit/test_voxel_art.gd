extends TestCase


func test_single_voxel_is_six_quads() -> void:
	var m := VoxelModel.new(Vector3i(4, 4, 4), 0.125)
	var c := m.add_color(Color.RED)
	m.set_voxel(1, 1, 1, c)
	var q := VoxelMesher.build_arrays(m)
	assert_eq(q.quad_count, 6)
	assert_eq(q.verts.size(), 24)
	assert_eq(q.idx.size(), 36)
	# Scaled to metres.
	var mn := Vector3(INF, INF, INF)
	for v in q.verts:
		mn = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
	assert_near(mn.x, 0.125)


func test_greedy_merges_same_colour() -> void:
	var m := VoxelModel.new(Vector3i(8, 8, 8), 0.125)
	var c := m.add_color(Color.GREEN)
	m.fill_box(Vector3i(0, 0, 0), Vector3i(7, 7, 7), c)
	var q := VoxelMesher.build_arrays(m)
	assert_eq(q.quad_count, 6, "solid same-colour cube merges to 6 quads")
	var d := m.add_color(Color.BLUE)
	m.set_voxel(0, 0, 0, d)
	var q2 := VoxelMesher.build_arrays(m)
	assert_gt(q2.quad_count, 6, "a different colour voxel splits faces")


func test_two_colours_adjacent() -> void:
	var m := VoxelModel.new(Vector3i(4, 4, 4), 0.125)
	var a := m.add_color(Color.RED)
	var b := m.add_color(Color.BLUE)
	m.set_voxel(1, 1, 1, a)
	m.set_voxel(2, 1, 1, b)
	assert_eq(VoxelMesher.build_arrays(m).quad_count, 10)


func test_hollow_box_has_inner_faces() -> void:
	var m := VoxelModel.new(Vector3i(6, 6, 6), 0.125)
	var c := m.add_color(Color.WHITE)
	m.fill_box(Vector3i(0, 0, 0), Vector3i(5, 5, 5), c)
	m.fill_box(Vector3i(1, 1, 1), Vector3i(4, 4, 4), -1)  # -1 + 1 = 0 clears
	assert_eq(VoxelMesher.build_arrays(m).quad_count, 12)


func test_generators_are_deterministic_and_non_empty() -> void:
	for gen in ["tree", "lantern", "grazer"]:
		VoxelArt.clear_cache()
		var a := VoxelArt.rig(gen, {}, 99)
		VoxelArt.clear_cache()
		var b := VoxelArt.rig(gen, {}, 99)
		VoxelArt.clear_cache()
		var c := VoxelArt.rig(gen, {}, 100)
		assert_not_null(a, gen)
		assert_true(a.parts.size() > 0, "%s has parts" % gen)
		assert_eq(a.parts[0].model.voxels, b.parts[0].model.voxels, "%s same seed same voxels" % gen)
		assert_ne(a.parts[0].model.voxels, c.parts[0].model.voxels, "%s different seed differs" % gen)
		for p in a.parts:
			assert_true(p.mesh != null and p.mesh.get_surface_count() > 0, "%s part %s baked" % [gen, p.name])
		assert_gt(a.height, 0.0, "%s height" % gen)


func test_grazer_has_animatable_legs() -> void:
	var r := VoxelArt.rig("grazer", {}, 5)
	for n in ["body", "head", "leg_fl", "leg_fr", "leg_bl", "leg_br", "tail"]:
		assert_not_null(r.get_part(n), n)
	var root := r.instantiate(null)
	var nodes := PartRig.part_nodes(root)
	assert_eq(nodes.size(), 7)
	assert_true((nodes["leg_fl"] as Node3D).get_parent() == nodes["body"], "legs parented to body")
	root.free()


func test_cache_returns_same_rig() -> void:
	VoxelArt.clear_cache()
	var a := VoxelArt.rig("lantern", {"rust": 0.5}, 3)
	var b := VoxelArt.rig("lantern", {"rust": 0.5}, 3)
	assert_true(a == b, "cached instance reused")
	assert_false(VoxelArt.rig("lantern", {"rust": 0.6}, 3) == a, "different params => different rig")
