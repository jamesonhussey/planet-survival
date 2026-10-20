extends TestCase
## Planet 01/02 rules: sunlight lines, flood fill with sealed volumes, swarm
## pathing through leaky walls.

const AIR := 0
const STONE := 1
const THATCH := 2
const WATER := 3
const BRICK := 4
const GLASS := 5
const SAND := 6
const PLANKS := 7


func _props() -> Array[MaterialProps]:
	var out: Array[MaterialProps] = []
	out.append(MaterialProps.from_dict({"id": 0, "name": "air", "solid": false, "opacity": 0}))
	out.append(MaterialProps.from_dict({"id": 1, "name": "stone", "solid": true, "airtight": true, "waterproof": true, "opacity": 1.0, "strength": 7, "flammability": 0}))
	out.append(MaterialProps.from_dict({"id": 2, "name": "thatch", "solid": true, "airtight": false, "waterproof": false, "opacity": 0.85, "strength": 1, "flammability": 1.0}))
	out.append(MaterialProps.from_dict({"id": 3, "name": "water", "solid": false, "fluid": true, "opacity": 0.5, "waterproof": true}))
	out.append(MaterialProps.from_dict({"id": 4, "name": "brick", "solid": true, "airtight": true, "waterproof": true, "opacity": 1.0, "strength": 6}))
	out.append(MaterialProps.from_dict({"id": 5, "name": "glass", "solid": true, "airtight": true, "waterproof": true, "opacity": 0.1, "strength": 1}))
	out.append(MaterialProps.from_dict({"id": 6, "name": "sand", "solid": true, "airtight": false, "waterproof": false, "opacity": 1.0, "strength": 1}))
	out.append(MaterialProps.from_dict({"id": 7, "name": "planks", "solid": true, "airtight": false, "waterproof": false, "opacity": 1.0, "strength": 4, "flammability": 0.8}))
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
	return w


# ---------------- light ----------------

func test_light_transmission_through_materials() -> void:
	var w := _world()
	var sim := LightRaySim.new(w)
	sim.set_sun(Vector3(0, 1, 0))
	assert_near(sim.transmission_at(Vector3i(0, 4, 0)), 1.0, 0.001, "open sky")
	w.set_block(Vector3i(0, 10, 0), STONE, false)
	sim.invalidate()
	assert_near(sim.transmission_at(Vector3i(0, 4, 0)), 0.0, 0.001, "stone roof")
	w.set_block(Vector3i(0, 10, 0), GLASS, false)
	sim.invalidate()
	assert_near(sim.transmission_at(Vector3i(0, 4, 0)), 0.9, 0.001, "glass dims a little")
	w.set_block(Vector3i(0, 10, 0), WATER, false)
	w.set_block(Vector3i(0, 11, 0), WATER, false)
	sim.invalidate()
	assert_near(sim.transmission_at(Vector3i(0, 4, 0)), 0.25, 0.001, "two water layers quarter it")
	assert_false(sim.is_burning_at(Vector3i(0, 4, 0)), "below threshold under water")


func test_light_angled_shadow() -> void:
	var w := _world()
	var sim := LightRaySim.new(w)
	# Sun low in the +x direction: a wall at x=5 shades cells west of it.
	sim.set_sun(Vector3(1, 0.5, 0))
	for y in range(4, 12):
		w.set_block(Vector3i(5, y, 0), STONE, false)
	assert_near(sim.transmission_at(Vector3i(2, 4, 0)), 0.0, 0.001, "in the wall's shadow")
	assert_near(sim.transmission_at(Vector3i(8, 4, 0)), 1.0, 0.001, "sunny side")
	assert_gt(sim.exposure(Vector3(8.5, 4.0, 0.5)), 0.9)
	assert_near(sim.exposure(Vector3(2.5, 4.0, 0.5)), 0.0, 0.001)


func test_light_burns_flammable_roofs() -> void:
	var w := _world()
	var sim := LightRaySim.new(w)
	sim.set_sun(Vector3(0, 1, 0))
	for x in range(0, 4):
		for z in range(0, 4):
			w.set_block(Vector3i(x, 8, z), THATCH, false)
			w.set_block(Vector3i(x + 10, 8, z), STONE, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var total := 0
	for i in 20:
		total += sim.tick(Vector3i(5, 8, 2), 12, 0.5, rng)
	assert_eq(total, 16, "all thatch burned away")
	assert_eq(w.get_block(Vector3i(0, 8, 0)), AIR)
	assert_eq(w.get_block(Vector3i(10, 8, 0)), STONE, "stone does not burn")


# ---------------- flood ----------------

func test_flood_fills_open_ground_not_sealed_rooms() -> void:
	var w := _world()
	# Sealed brick room 3x3 interior at (0..2, 4..6, 0..2) with brick roof; thatch room at x=10.
	for x in range(-1, 4):
		for z in range(-1, 4):
			for y in range(4, 9):
				var wall := x == -1 or x == 3 or z == -1 or z == 3 or y == 8
				w.set_block(Vector3i(x, y, z), BRICK if wall else AIR, false)
	for x in range(9, 14):
		for z in range(-1, 4):
			for y in range(4, 9):
				var wall := x == 9 or x == 13 or z == -1 or z == 3 or y == 8
				w.set_block(Vector3i(x, y, z), THATCH if wall else AIR, false)
	var f := FluidSim.new(w, 3.0, WATER)
	f.set_region(Vector3i(-20, 0, -20), Vector3i(20, 31, 20))
	f.level = 6.5
	f.tick()
	assert_true(f.is_wet(Vector3i(-10, 4, -10)), "open ground floods")
	assert_true(f.is_wet(Vector3i(-10, 6, -10)), "up to the level")
	assert_false(f.is_wet(Vector3i(-10, 7, -10)), "not above it")
	assert_false(f.is_wet(Vector3i(1, 5, 1)), "brick room stays dry")
	assert_true(f.is_wet(Vector3i(11, 5, 1)), "thatch room floods")
	assert_eq(f.submersion(Vector3(1.5, 4.0, 1.5)), 0)
	assert_eq(f.submersion(Vector3(-10.5, 4.0, -10.5)), 2, "head under water in the open")
	# Recede.
	f.level = 3.0
	f.tick()
	assert_false(f.is_wet(Vector3i(-10, 4, -10)), "water gone when the level drops")


func test_flood_wave_destroys_weak_blocks() -> void:
	var w := _world()
	w.set_block(Vector3i(0, 4, 0), SAND, false)
	w.set_block(Vector3i(2, 4, 0), BRICK, false)
	var f := FluidSim.new(w, 3.0, WATER)
	f.set_region(Vector3i(-10, 0, -10), Vector3i(10, 31, 10))
	f.wave_force = 3.0
	f.level = 5.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	f.tick(rng)
	assert_eq(w.get_block(Vector3i(0, 4, 0)), AIR, "sand washed away")
	assert_eq(w.get_block(Vector3i(2, 4, 0)), BRICK, "brick stands")
	assert_gt(f.destroyed.size(), 0)
	assert_gt(f.surface_cells().size(), 0)


# ---------------- swarm ----------------

func test_swarm_reaches_target_in_the_open() -> void:
	var w := _world()
	var s := SwarmSim.new(w)
	s.targets = [Vector3i(10, 4, 0)]
	s.rebuild_field()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	s.spawn(Vector3i(0, 4, 0), 5, rng)
	var bites := 0
	for i in 80:
		for b in s.tick(0.1, rng):
			bites += int(b[1])
	assert_gt(bites, 0, "roaches arrived and bit")
	assert_eq(s.agents[0].cell, Vector3i(10, 4, 0))


func test_swarm_blocked_by_airtight_but_leaks_through_thatch() -> void:
	var w := _world()
	# Brick box around target A, thatch box around target B.
	for x in range(-1, 2):
		for z in range(-1, 2):
			for y in range(4, 7):
				var wall := x != 0 or z != 0 or y == 6
				w.set_block(Vector3i(x, y, z), BRICK if wall else AIR, false)
				w.set_block(Vector3i(x + 12, y, z), THATCH if wall else AIR, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var sealed := SwarmSim.new(w)
	sealed.targets = [Vector3i(0, 4, 0)]
	sealed.rebuild_field()
	sealed.spawn(Vector3i(5, 4, 5), 4, rng)
	var bites := 0
	for i in 150:
		for b in sealed.tick(0.1, rng):
			bites += int(b[1])
	assert_eq(bites, 0, "sealed box keeps them out")
	var leaky := SwarmSim.new(w)
	leaky.targets = [Vector3i(12, 4, 0)]
	leaky.rebuild_field()
	leaky.spawn(Vector3i(5, 4, 5), 4, rng)
	bites = 0
	for i in 150:
		for b in leaky.tick(0.1, rng):
			bites += int(b[1])
	assert_gt(bites, 0, "thatch box leaks")
