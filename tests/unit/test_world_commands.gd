extends TestCase


func _props() -> Array[MaterialProps]:
	var out: Array[MaterialProps] = []
	out.append(MaterialProps.from_dict({"id": 0, "name": "air", "solid": false}))
	out.append(MaterialProps.from_dict({"id": 1, "name": "stone", "solid": true}))
	out.append(MaterialProps.from_dict({"id": 2, "name": "water", "solid": false, "fluid": true}))
	return out


func _setup() -> Array:
	var w := WorldData.new(64, 32, _props())
	w.insert_chunk(Chunk.new(Vector3i(0, 0, 0)))
	var cmds := WorldCommands.new()
	cmds.setup(w)
	var s := Session.new()
	s.setup(cmds)
	return [w, cmds, s]


func test_dig_and_place_roundtrip() -> void:
	var parts := _setup()
	var w: WorldData = parts[0]
	var cmds: WorldCommands = parts[1]
	var s: Session = parts[2]
	w.set_block(Vector3i(3, 3, 3), 1, false)
	var rejected := []
	cmds.command_rejected.connect(func(_p: int, _c: Dictionary, r: String) -> void: rejected.append(r))
	s.submit({"type": "dig", "pos": Vector3i(3, 3, 3), "from": Vector3(3.5, 5.0, 3.5)})
	assert_eq(w.get_block(Vector3i(3, 3, 3)), 0, "dug")
	s.submit({"type": "place", "pos": Vector3i(3, 3, 3), "block": 1, "from": Vector3(3.5, 5.0, 3.5)})
	assert_eq(w.get_block(Vector3i(3, 3, 3)), 1, "placed")
	assert_eq(rejected.size(), 0, str(rejected))
	cmds.free()
	s.free()


func test_rejections() -> void:
	var parts := _setup()
	var w: WorldData = parts[0]
	var cmds: WorldCommands = parts[1]
	var s: Session = parts[2]
	w.set_block(Vector3i(3, 3, 3), 1, false)
	w.set_block(Vector3i(4, 0, 4), 1, false)
	var rejected := []
	cmds.command_rejected.connect(func(_p: int, _c: Dictionary, r: String) -> void: rejected.append(r))
	s.submit({"type": "dig", "pos": Vector3i(3, 3, 3), "from": Vector3(30.0, 5.0, 3.5)})
	assert_eq(rejected.back(), "out of reach")
	s.submit({"type": "dig", "pos": Vector3i(4, 0, 4), "from": Vector3(4.5, 2.0, 4.5)})
	assert_eq(rejected.back(), "bedrock")
	s.submit({"type": "place", "pos": Vector3i(3, 3, 3), "block": 1, "from": Vector3(3.5, 5.0, 3.5)})
	assert_eq(rejected.back(), "occupied")
	s.submit({"type": "place", "pos": Vector3i(5, 5, 5), "block": 99, "from": Vector3(5.5, 7.0, 5.5)})
	assert_eq(rejected.back(), "invalid block")
	s.submit({"type": "place", "pos": Vector3i(5, 5, 5), "block": 1, "from": Vector3(5.5, 7.0, 5.5), "blocked_by_body": true})
	assert_eq(rejected.back(), "player in the way")
	s.submit({"type": "dig", "pos": Vector3i(6, 6, 6), "from": Vector3(6.5, 8.0, 6.5)})
	assert_eq(rejected.back(), "nothing to dig")
	assert_eq(w.get_block(Vector3i(3, 3, 3)), 1, "unchanged")
	cmds.free()
	s.free()


func test_voxel_ray_hits_first_solid() -> void:
	var w := WorldData.new(64, 32, _props())
	w.insert_chunk(Chunk.new(Vector3i(0, 0, 0)))
	w.set_block(Vector3i(5, 2, 5), 1, false)
	var hit := VoxelRay.cast(Vector3(5.5, 2.5, 0.5), Vector3(0, 0, 1), 10.0, func(c: Vector3i) -> bool: return w.is_solid(c))
	assert_true(hit.hit)
	assert_eq(hit.pos, Vector3i(5, 2, 5))
	assert_eq(hit.prev, Vector3i(5, 2, 4))
	assert_eq(hit.normal, Vector3i(0, 0, -1))
	assert_near(hit.distance, 4.5, 0.01)
	var miss := VoxelRay.cast(Vector3(5.5, 2.5, 0.5), Vector3(0, 0, 1), 3.0, func(c: Vector3i) -> bool: return w.is_solid(c))
	assert_false(miss.hit)
	# Diagonal ray from above lands on the top face.
	var diag := VoxelRay.cast(Vector3(5.5, 6.0, 5.5), Vector3(0.01, -1, 0.01), 10.0, func(c: Vector3i) -> bool: return w.is_solid(c))
	assert_true(diag.hit)
	assert_eq(diag.normal, Vector3i(0, 1, 0))


func test_kit_drops_and_consumption() -> void:
	# Uses the real Data autoload (materials + items) through WorldData props.
	var w := WorldData.new(64, 32, Data.materials)
	w.insert_chunk(Chunk.new(Vector3i(0, 0, 0)))
	w.set_block(Vector3i(3, 3, 3), Data.block_id("stone"), false)
	var cmds := WorldCommands.new()
	cmds.setup(w)
	var kit := PlayerKit.new(1)
	kit.equipment.equip(Data.make_item("backpack_small"))
	cmds.kit_lookup = func(_peer: int) -> PlayerKit: return kit
	var s := Session.new()
	s.setup(cmds)
	var rejected := []
	cmds.command_rejected.connect(func(_p: int, _c: Dictionary, r: String) -> void: rejected.append(r))
	s.submit({"type": "dig", "pos": Vector3i(3, 3, 3), "from": Vector3(3.5, 5.0, 3.5)})
	assert_eq(kit.equipment.count_of("cobble"), 1, "digging stone yields cobble")
	s.submit({"type": "place", "pos": Vector3i(3, 3, 3), "block": Data.block_id("brick"), "from": Vector3(3.5, 5.0, 3.5)})
	assert_eq(rejected.back(), "no brick left")
	s.submit({"type": "place", "pos": Vector3i(3, 3, 3), "block": Data.block_id("stone"), "from": Vector3(3.5, 5.0, 3.5)})
	assert_eq(w.get_block(Vector3i(3, 3, 3)), Data.block_id("stone"), "placed stone from cobble")
	assert_eq(kit.equipment.count_of("cobble"), 0, "cobble consumed")
	# Overflow: fill the pack, dig again, drop must overflow into the world.
	var overflow := []
	cmds.item_overflow.connect(func(_p: int, _pos: Vector3i, it: ItemInstance) -> void: overflow.append(it))
	while kit.equipment.add_item(Data.make_item("log")):
		pass
	for g in kit.equipment.pockets:
		g.auto_place(Data.make_item("bandage"))
	s.submit({"type": "dig", "pos": Vector3i(3, 3, 3), "from": Vector3(3.5, 5.0, 3.5)})
	assert_eq(overflow.size(), 1, "drop overflowed")
	cmds.free()
	s.free()
