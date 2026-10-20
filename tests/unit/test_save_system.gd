extends TestCase
## Save round trip: meta JSON + compressed edited chunks.


func test_round_trip() -> void:
	var props: Array[MaterialProps] = Data.materials
	var w := WorldData.new(64, 32, props)
	w.insert_chunk(Chunk.new(Vector3i(0, 0, 0)))
	w.insert_chunk(Chunk.new(Vector3i(-1, 1, -1)))
	w.set_block(Vector3i(3, 3, 3), Data.block_id("brick"))
	w.set_block(Vector3i(-5, 20, -7), Data.block_id("glass"))
	var meta := {"planet_id": "04", "mode_id": "short", "seed": 99, "clock": {"day": 3, "day_fraction": 0.4}}
	assert_eq(SaveSystem.write(meta, w), OK)
	assert_true(SaveSystem.exists())
	assert_eq(SaveSystem.summary(), "planet 04, day 3")
	var back := SaveSystem.read_meta()
	assert_eq(int(back["seed"]), 99)
	var chunks := SaveSystem.read_chunks()
	assert_eq(chunks.size(), 2)
	assert_true(chunks.has(Vector3i(-1, 1, -1)), "negative chunk coordinates survive")
	# Apply to a fresh world the way the run does.
	var w2 := WorldData.new(64, 32, props)
	w2.saved_chunks = chunks
	w2.insert_chunk(Chunk.new(Vector3i(0, 0, 0)))
	w2.insert_chunk(Chunk.new(Vector3i(-1, 1, -1)))
	assert_eq(w2.get_block(Vector3i(3, 3, 3)), Data.block_id("brick"))
	assert_eq(w2.get_block(Vector3i(-5, 20, -7)), Data.block_id("glass"))
	assert_true(w2.get_chunk(Vector3i(0, 0, 0)).edited)
	SaveSystem.delete()
	assert_false(SaveSystem.exists())
