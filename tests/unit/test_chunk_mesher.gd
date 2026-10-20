extends TestCase


func _props() -> Array[MaterialProps]:
	var out: Array[MaterialProps] = []
	out.append(MaterialProps.from_dict({"id": 0, "name": "air", "solid": false, "opacity": 0}))
	out.append(MaterialProps.from_dict({"id": 1, "name": "stone", "solid": true}))
	out.append(MaterialProps.from_dict({"id": 2, "name": "glass", "solid": true, "transparent": true, "opacity": 0.1}))
	out.append(MaterialProps.from_dict({"id": 3, "name": "water", "solid": false, "fluid": true, "transparent": true}))
	return out


func _input_from(c: Chunk) -> ChunkMesher.MeshInput:
	var inp := ChunkMesher.MeshInput.new()
	inp.cpos = c.cpos
	inp.blocks = c.blocks.duplicate()
	for i in 6:
		inp.neighbors.append(PackedByteArray())
	return inp


func test_single_block_has_six_faces() -> void:
	var m := ChunkMesher.new(_props(), null)
	var c := Chunk.new(Vector3i(0, 1, 0))
	c.set_local(5, 5, 5, 1)
	var r := m.build(_input_from(c))
	assert_eq(r.face_count, 6)
	assert_eq((r.opaque[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 24)
	assert_eq((r.opaque[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 36)
	assert_eq(r.collision.size(), 36, "collision triangles for a solid block")
	assert_true(r.transparent.is_empty())
	# Vertices are in world space (chunk y=1 => +16).
	var v: PackedVector3Array = r.opaque[Mesh.ARRAY_VERTEX]
	assert_true(v[0].y >= 21.0 and v[0].y <= 22.0, "world-space offset applied")


func test_adjacent_blocks_cull_shared_face() -> void:
	var m := ChunkMesher.new(_props(), null)
	var c := Chunk.new()
	c.set_local(5, 5, 5, 1)
	c.set_local(6, 5, 5, 1)
	assert_eq(m.build(_input_from(c)).face_count, 10)


func test_buried_chunk_has_no_faces() -> void:
	var m := ChunkMesher.new(_props(), null)
	var c := Chunk.new()
	c.blocks.fill(1)
	c.recount()
	var inp := _input_from(c)
	for i in 6:
		var n := PackedByteArray()
		n.resize(Chunk.VOLUME)
		n.fill(1)
		inp.neighbors[i] = n
	assert_eq(m.build(inp).face_count, 0)


func test_transparent_rules() -> void:
	var m := ChunkMesher.new(_props(), null)
	var c := Chunk.new()
	c.set_local(5, 5, 5, 1)   # stone
	c.set_local(6, 5, 5, 2)   # glass next to it
	var r := m.build(_input_from(c))
	# stone: 6 faces (its face toward glass is visible); glass: 5 faces (not toward stone)
	assert_eq(r.face_count, 11)
	assert_false(r.transparent.is_empty())
	# water is not solid: no collision faces, but it still renders
	var w := Chunk.new()
	w.set_local(1, 1, 1, 3)
	var rw := m.build(_input_from(w))
	assert_eq(rw.face_count, 6)
	assert_eq(rw.collision.size(), 0)
	# two water blocks side by side do not draw the face between them
	w.set_local(2, 1, 1, 3)
	assert_eq(m.build(_input_from(w)).face_count, 10)


func test_ambient_occlusion_darkens_inner_corner() -> void:
	var m := ChunkMesher.new(_props(), null)
	var c := Chunk.new()
	# Floor slab with a wall: the floor vertex touching the wall gets darker.
	for x in range(2, 6):
		for z in range(2, 6):
			c.set_local(x, 2, z, 1)
	c.set_local(2, 3, 3, 1)
	var r := m.build(_input_from(c))
	var cols: PackedColorArray = r.opaque[Mesh.ARRAY_COLOR]
	var mn := 1.0
	var mx := 0.0
	for col in cols:
		mn = minf(mn, col.r)
		mx = maxf(mx, col.r)
	assert_lt(mn, mx, "AO produced varying vertex brightness")
