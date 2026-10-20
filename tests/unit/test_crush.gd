extends TestCase
## Planet 03 rule: a footfall presses weak blocks, spares strong ones, and a
## strong roof is shelter.

const AIR := 0
const STONE := 1
const DIRT := 2
const PLANKS := 3


func _props() -> Array[MaterialProps]:
	var out: Array[MaterialProps] = []
	out.append(MaterialProps.from_dict({"id": 0, "name": "air", "solid": false}))
	out.append(MaterialProps.from_dict({"id": 1, "name": "stone", "solid": true, "strength": 7}))
	out.append(MaterialProps.from_dict({"id": 2, "name": "dirt", "solid": true, "strength": 2}))
	out.append(MaterialProps.from_dict({"id": 3, "name": "planks", "solid": true, "strength": 4}))
	return out


func _world() -> WorldData:
	var w := WorldData.new(64, 32, _props())
	for cx in range(-2, 2):
		for cz in range(-2, 2):
			for cy in 2:
				w.insert_chunk(Chunk.new(Vector3i(cx, cy, cz)))
	for x in range(-32, 32):
		for z in range(-32, 32):
			for y in 4:
				w.set_block(Vector3i(x, y, z), STONE, false)
			for y in range(4, 8):
				w.set_block(Vector3i(x, y, z), DIRT, false)
	return w


func test_footfall_presses_weak_blocks_only() -> void:
	var w := _world()
	var sim := CrushSim.new(w)
	# A plank hut and a stone hut on the surface, both under the foot.
	for y in range(8, 11):
		w.set_block(Vector3i(0, y, 0), PLANKS, false)
		w.set_block(Vector3i(1, y, 0), STONE, false)
	var n := sim.footfall(0, 0, 2.0, 5.0, 2)
	assert_gt(n, 10, "dirt and planks pressed (%d)" % n)
	assert_eq(w.get_block(Vector3i(0, 10, 0)), AIR, "top plank crushed")
	assert_eq(w.get_block(Vector3i(0, 9, 0)), AIR, "second plank crushed (depth 2)")
	assert_eq(w.get_block(Vector3i(0, 8, 0)), PLANKS, "depth limit spares the third")
	assert_eq(w.get_block(Vector3i(1, 10, 0)), STONE, "stone holds")
	assert_eq(w.surface_y(3, 3), 7, "outside the foot nothing happens")
	assert_eq(w.surface_y(-1, 1), 5, "bare dirt inside the foot pressed two deep")
	# Deterministic: the same footfall on the same world does the same thing.
	var w2 := _world()
	for y in range(8, 11):
		w2.set_block(Vector3i(0, y, 0), PLANKS, false)
		w2.set_block(Vector3i(1, y, 0), STONE, false)
	assert_eq(CrushSim.new(w2).footfall(0, 0, 2.0, 5.0, 2), n)


func test_strong_roof_is_shelter() -> void:
	var w := _world()
	var sim := CrushSim.new(w)
	var feet := Vector3(0.5, 8.0, 0.5)
	assert_true(sim.crushed(feet, 0, 0, 2.0, 5.0), "in the open under the foot: crushed")
	assert_false(sim.crushed(Vector3(6.5, 8.0, 0.5), 0, 0, 2.0, 5.0), "beside the foot: fine")
	w.set_block(Vector3i(0, 11, 0), PLANKS, false)
	assert_true(sim.crushed(feet, 0, 0, 2.0, 5.0), "a plank roof is not shelter")
	w.set_block(Vector3i(0, 11, 0), STONE, false)
	assert_false(sim.crushed(feet, 0, 0, 2.0, 5.0), "a stone roof is")
	assert_true(sim.crushed(feet, 0, 0, 2.0, 8.0), "unless the foot is heavier than the stone")


func test_tremor_and_path() -> void:
	assert_near(CrushSim.tremor(0.0, 70.0), 1.0)
	assert_near(CrushSim.tremor(70.0, 70.0), 0.0)
	assert_gt(CrushSim.tremor(10.0, 70.0), CrushSim.tremor(40.0, 70.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var path := CrushSim.plan_path(Vector2(100, 100), 18.0, 150.0, 90.0, rng)
	var s: Vector2 = path["start"]
	var e: Vector2 = path["end"]
	var c: Vector2 = path["closest"]
	assert_near(c.distance_to(Vector2(100, 100)), 18.0, 1e-3, "passes at the asked distance")
	assert_near(s.distance_to(e), 240.0, 1e-3)
	# The closest point of the segment to the focus is `closest`.
	var dir := (e - s).normalized()
	var t := (Vector2(100, 100) - s).dot(dir)
	assert_near((s + dir * t).distance_to(c), 0.0, 1e-3)
	assert_true(t > 0.0 and t < 240.0, "focus is beside the segment, not past an end")
