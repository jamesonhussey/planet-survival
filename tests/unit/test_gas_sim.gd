extends TestCase
## The heavy-gas rules: falls, pools, blocked by airtight, leaks through
## non-airtight, decays, stays in its region.

const AIR := 0
const STONE := 1
const THATCH := 2
const WATER := 3
const BRICK := 4


func _props() -> Array[MaterialProps]:
	var out: Array[MaterialProps] = []
	out.append(MaterialProps.from_dict({"id": 0, "name": "air", "solid": false, "airtight": false}))
	out.append(MaterialProps.from_dict({"id": 1, "name": "stone", "solid": true, "airtight": true}))
	out.append(MaterialProps.from_dict({"id": 2, "name": "thatch", "solid": true, "airtight": false}))
	out.append(MaterialProps.from_dict({"id": 3, "name": "water", "solid": false, "fluid": true, "airtight": false}))
	out.append(MaterialProps.from_dict({"id": 4, "name": "brick", "solid": true, "airtight": true}))
	return out


## 32x32x32 world (two chunks per axis) with a stone floor at y=0..3.
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
	return w


func _sim(w: WorldData) -> GasSim:
	var g := GasSim.new(w, {"decay_per_tick": 0.0, "emit_per_tick": 0.2})
	g.set_region(Vector3i(-30, 0, -30), Vector3i(30, 31, 30))
	return g


func test_gas_falls_and_pools_in_pit() -> void:
	var w := _world()
	# Dig a 1x1 pit 3 deep at (5,*,5).
	for y in range(1, 4):
		w.set_block(Vector3i(5, y, 5), AIR, false)
	var g := _sim(w)
	g.add(Vector3i(5, 8, 5), 1.0)
	for i in 12:
		g.tick()
	assert_gt(g.concentration_at(Vector3i(5, 1, 5)), g.concentration_at(Vector3i(5, 8, 5)), "pit bottom holds more than release point")
	assert_gt(g.concentration_at(Vector3i(5, 1, 5)), 0.3, "pit bottom accumulated")


func test_airtight_wall_blocks_but_thatch_leaks() -> void:
	var w := _world()
	# Two walls across x = 0 (brick) and x = 10 (thatch), 6 high, full z width.
	for z in range(-32, 32):
		for y in range(4, 10):
			w.set_block(Vector3i(0, y, z), BRICK, false)
			w.set_block(Vector3i(10, y, z), THATCH, false)
	var g := _sim(w)
	g.sources = [Vector3i(5, 4, 0), Vector3i(5, 4, 1), Vector3i(5, 4, -1)]
	g.emitting = true
	for i in 60:
		g.tick()
	var behind_brick := 0.0
	var behind_thatch := 0.0
	for z in range(-3, 4):
		behind_brick = maxf(behind_brick, g.concentration_at(Vector3i(-1, 4, z)))
		behind_thatch = maxf(behind_thatch, g.concentration_at(Vector3i(11, 4, z)))
	assert_eq(behind_brick, 0.0, "brick is airtight")
	assert_gt(behind_thatch, 0.0, "thatch leaks")
	assert_gt(g.concentration_at(Vector3i(1, 4, 0)), 0.05, "gas reaches and piles up against the airtight wall")


func test_sealed_room_stays_clean_until_opened() -> void:
	var w := _world()
	# 3x3 interior room with brick walls, floor is the stone ground, brick roof.
	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in range(4, 8):
				var wall := absi(x) == 2 or absi(z) == 2 or y == 7
				w.set_block(Vector3i(x, y, z), BRICK if wall else AIR, false)
	var g := _sim(w)
	g.sources = [Vector3i(6, 4, 0)]
	g.emitting = true
	for i in 80:
		g.tick()
	assert_eq(g.concentration_at(Vector3i(0, 4, 0)), 0.0, "sealed room is clean")
	# Knock a hole in the wall: gas gets in.
	w.set_block(Vector3i(2, 4, 0), AIR, false)
	for i in 40:
		g.tick()
	assert_gt(g.concentration_at(Vector3i(0, 4, 0)), 0.0, "opened room fills")


func test_high_ground_is_safer() -> void:
	var w := _world()
	# A 6-high stone pillar at (-8,*,-8); gas released on the ground nearby.
	for y in range(4, 10):
		w.set_block(Vector3i(-8, y, -8), STONE, false)
	var g := _sim(w)
	g.sources = [Vector3i(-5, 4, -8)]
	g.emitting = true
	for i in 60:
		g.tick()
	assert_gt(g.concentration_at(Vector3i(-7, 4, -8)), g.concentration_at(Vector3i(-8, 10, -8)) + 0.05, "ground level worse than pillar top")


func test_decay_clears_everything() -> void:
	var w := _world()
	var g := GasSim.new(w, {"decay_per_tick": 0.05})
	g.set_region(Vector3i(-30, 0, -30), Vector3i(30, 31, 30))
	g.add(Vector3i(0, 4, 0), 1.0)
	g.add(Vector3i(1, 4, 0), 1.0)
	assert_gt(g.cells.size(), 0.0)
	for i in 60:
		g.tick()
	assert_eq(g.cells.size(), 0, "all cells pruned after decay")
	assert_near(g.total_mass, 0.0)


func test_region_boundary_is_an_open_edge() -> void:
	var w := _world()
	var g := _sim(w)
	g.set_region(Vector3i(-2, 0, -2), Vector3i(2, 31, 2))
	g.add(Vector3i(0, 4, 0), 1.0)
	for i in 30:
		g.tick()
	for p in g.cells:
		assert_true(g.in_region(p), "cell %s outside region" % str(p))
	assert_false(g.passable(Vector3i(3, 4, 0)))


func test_exposure_reads_body_column() -> void:
	var w := _world()
	var g := _sim(w)
	g.add(Vector3i(0, 5, 0), 0.6)
	assert_near(g.exposure(Vector3(0.5, 4.0, 0.5)), 0.6)
	assert_near(g.exposure(Vector3(0.5, 7.0, 0.5)), 0.0)


func test_collect_sources_from_lake() -> void:
	var w := _world()
	for x in range(2, 6):
		for z in range(2, 6):
			w.set_block(Vector3i(x, 3, z), WATER, false)
	var g := _sim(w)
	var n := g.collect_sources_from_fluid(WATER, Vector3i(0, 0, 0), Vector3i(8, 10, 8))
	assert_eq(n, 16)
	assert_true(g.sources.has(Vector3i(2, 4, 2)))
