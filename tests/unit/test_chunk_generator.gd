extends TestCase

const IDS := {"air": 0, "dirt": 1, "grass": 2, "stone": 3, "clay": 5, "co2_water": 10, "mossy_stone": 14}
const TERRAIN := {
	"base_height": 50, "amplitude": 12, "frequency": 0.011, "octaves": 4,
	"lake_level": 40, "lake_noise_frequency": 0.004, "lake_threshold": 0.18,
	"lake_fluid": "co2_water", "surface": "grass", "subsurface": "dirt", "subsurface_depth": 3,
	"deep": "stone", "shore": "clay", "shore_band": 2, "mossy_chance": 0.12,
}


func test_deterministic() -> void:
	var a := ChunkGenerator.new(42, TERRAIN, IDS, 128)
	var b := ChunkGenerator.new(42, TERRAIN, IDS, 128)
	var ca := a.generate(Vector3i(3, 2, -4))
	var cb := b.generate(Vector3i(3, 2, -4))
	assert_eq(ca.blocks, cb.blocks, "same seed => identical chunk")
	var c := ChunkGenerator.new(43, TERRAIN, IDS, 128)
	assert_ne(c.generate(Vector3i(3, 2, -4)).blocks, ca.blocks, "different seed => different chunk")


func test_column_structure() -> void:
	var g := ChunkGenerator.new(7, TERRAIN, IDS, 128)
	var w := WorldData.new(1024, 128)
	w.generator = g
	var h := g.height_at(10, 10)
	assert_true(h > 1 and h < 126, "height in range")
	for cy in 8:
		w.get_or_generate_chunk(Vector3i(0, cy, 0))
	assert_eq(w.get_block(Vector3i(10, 0, 10)), IDS["stone"], "floor is stone")
	var top := w.get_block(Vector3i(10, h, 10))
	assert_true(top != 0, "surface block solid")
	assert_eq(w.get_block(Vector3i(10, h + 1, 10)) in [0, IDS["co2_water"]], true, "above surface is air or lake")
	var below := w.get_block(Vector3i(10, h - 1, 10))
	assert_true(below == IDS["dirt"] or below == IDS["clay"], "subsurface is dirt/clay, got %d" % below)


func test_lakes_exist_and_hold_fluid() -> void:
	var g := ChunkGenerator.new(7, TERRAIN, IDS, 128)
	var found := false
	var checked := 0
	for z in range(-256, 256, 8):
		for x in range(-256, 256, 8):
			if g.is_lake_column(x, z):
				found = true
				var h := g.height_at(x, z)
				assert_true(h < g.lake_level, "lake floor below lake level")
				var w := WorldData.new(1024, 128)
				w.generator = g
				for cy in 8:
					w.get_or_generate_chunk(WorldData.chunk_pos_of(Vector3i(x, cy * 16, z)))
				assert_eq(w.get_block(Vector3i(x, g.lake_level, z)), IDS["co2_water"], "fluid at lake level")
				assert_eq(w.get_block(Vector3i(x, g.lake_level + 1, z)), 0, "air above lake")
				checked += 1
				if checked >= 3:
					return
	assert_true(found, "at least one lake column within 512x512")
