extends TestCase


func _props() -> Array[MaterialProps]:
	var out: Array[MaterialProps] = []
	out.append(MaterialProps.from_dict({"id": 0, "name": "air", "solid": false, "opacity": 0}))
	out.append(MaterialProps.from_dict({"id": 1, "name": "dirt", "solid": true, "airtight": true}))
	out.append(MaterialProps.from_dict({"id": 2, "name": "grass", "solid": true}))
	out.append(MaterialProps.from_dict({"id": 3, "name": "stone", "solid": true}))
	return out


func test_floor_div_and_chunk_pos() -> void:
	assert_eq(WorldData.floor_div(17, 16), 1)
	assert_eq(WorldData.floor_div(-1, 16), -1)
	assert_eq(WorldData.floor_div(-16, 16), -1)
	assert_eq(WorldData.floor_div(-17, 16), -2)
	assert_eq(WorldData.chunk_pos_of(Vector3i(-1, 20, 31)), Vector3i(-1, 1, 1))
	assert_eq(WorldData.local_of(Vector3i(-1, 20, 31)), Vector3i(15, 4, 15))


func test_set_get_block_roundtrip() -> void:
	var w := WorldData.new(64, 32, _props())
	var c := Chunk.new(Vector3i(-1, 0, 0))
	assert_true(w.insert_chunk(c))
	assert_false(w.insert_chunk(c), "double insert refused")
	var changed := []
	w.block_changed.connect(func(p: Vector3i, o: int, n: int) -> void: changed.append([p, o, n]))
	assert_true(w.set_block(Vector3i(-3, 5, 7), 3))
	assert_eq(w.get_block(Vector3i(-3, 5, 7)), 3)
	assert_false(w.set_block(Vector3i(-3, 5, 7), 3), "no change -> false")
	assert_eq(changed.size(), 1)
	assert_true(c.edited)
	assert_eq(c.solid_count, 1)
	assert_true(w.set_block(Vector3i(-3, 5, 7), 0))
	assert_eq(c.solid_count, 0)


func test_bounds_and_unloaded_reads() -> void:
	var w := WorldData.new(64, 32, _props())
	assert_true(w.in_bounds(Vector3i(31, 0, -32)))
	assert_false(w.in_bounds(Vector3i(32, 0, 0)))
	assert_false(w.in_bounds(Vector3i(0, 32, 0)))
	assert_false(w.set_block(Vector3i(0, 0, 0), 1), "unloaded chunk cannot be written")
	assert_eq(w.get_block(Vector3i(0, 0, 0)), 0, "unloaded reads as air")
	assert_eq(w.get_block(Vector3i(0, -1, 0)), 3, "below floor reads as bedrock")
	var unbounded := WorldData.new(0, 32, _props())
	assert_true(unbounded.in_bounds(Vector3i(100000, 3, -99999)))
	assert_true(unbounded.chunk_in_bounds(Vector3i(5000, 1, 5000)))


func test_surface_y() -> void:
	var w := WorldData.new(64, 32, _props())
	w.insert_chunk(Chunk.new(Vector3i(0, 0, 0)))
	w.insert_chunk(Chunk.new(Vector3i(0, 1, 0)))
	for y in 20:
		w.set_block(Vector3i(4, y, 4), 1 if y < 19 else 2)
	assert_eq(w.surface_y(4, 4), 19)
	assert_eq(w.surface_y(5, 4), -1)
	assert_eq(w.edited_chunks().size(), 2)
