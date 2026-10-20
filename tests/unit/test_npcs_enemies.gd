extends TestCase
## Village structures produce NPC points; enemy/villager data is consistent.


func test_village_structures_and_npc_points() -> void:
	var ids := Data.material_ids
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var flat := func(_x: int, _z: int) -> int: return 40
	var camp := StructureGen.build("hilltop_camp", Vector3i(0, 40, 0), rng, ids, flat)
	assert_gt(camp.size(), 200, "camp has blocks")
	var fire := 0
	for p in camp:
		if camp[p] == Data.block_id("campfire"):
			fire += 1
	assert_eq(fire, 1, "one campfire in the camp")
	assert_eq(StructureGen.npc_points("hilltop_camp", Vector3i(0, 40, 0)).size(), 4)
	var village := StructureGen.build("stilt_village", Vector3i(0, 34, 0), rng, ids, flat)
	var highest := 0
	for p in village:
		highest = maxi(highest, (p as Vector3i).y)
	assert_true(highest >= 34 + 9, "stilt huts stand well above the ground (%d)" % highest)
	assert_eq(StructureGen.npc_points("stilt_village", Vector3i(0, 34, 0)).size(), 3)
	var pts := StructureGen.npc_points("farmhouse", Vector3i(0, 50, 0))
	assert_eq(pts.size(), 1)
	assert_lt(float(pts[0]["home"].y), 50.0, "cellar folk live below the floor")


func test_npc_and_enemy_data_consistent() -> void:
	var npcs: Dictionary = Data.load_json("res://data/npcs/villagers.json").get("kinds", {})
	assert_eq(npcs.size(), 3)
	for k in npcs:
		var cfg: Dictionary = npcs[k]
		for t in cfg.get("trades", []):
			assert_true(Data.items.has(str(t["give"]["id"])), "%s trade give %s" % [k, t["give"]["id"]])
			assert_true(Data.items.has(str(t["get"]["id"])), "%s trade get %s" % [k, t["get"]["id"]])
		for task in cfg.get("tasks", []):
			assert_true(Data.items.has(str(task["need"]["id"])), "%s task need" % k)
			assert_true(Data.items.has(str(task["reward"]["id"])), "%s task reward" % k)
	var enemies: Dictionary = Data.load_json("res://data/enemies.json").get("kinds", {})
	assert_eq(enemies.size(), 3)
	for k in enemies:
		var e: Dictionary = enemies[k]
		assert_true(VoxelArt.GENERATORS.has(str(e["generator"])), "%s generator exists" % k)
		var rig := VoxelArt.rig(str(e["generator"]), e.get("params", {}), 11)
		assert_not_null(rig)
		assert_gt(rig.height, 0.3)


func test_enemy_rules_gate_hunting() -> void:
	var e := Enemy.new()
	e.setup_enemy({"hunts_in": "gas", "speed": 3.0, "damage": 5.0, "sight": 20.0, "breathes": false})
	e.perceive([Vector3(5, 0, 0)], 0.0, 0.0, false)
	assert_true(e.has_target)
	e._brain(0.1)
	# No gas: it does not pursue (default wander brain instead) -> wander_dir may be zero or random, but it never attacks.
	var attacks := []
	e.attacked.connect(func(_p: Vector3, _a: float) -> void: attacks.append(1))
	e.perceive([Vector3(1.0, 0, 0)], 0.0, 0.0, false)
	for i in 30:
		e._brain(0.1)
	assert_eq(attacks.size(), 0, "a gasper in clean air does not hunt")
	e.perceive([Vector3(1.0, 0, 0)], 0.5, 0.0, false)
	for i in 30:
		e._brain(0.1)
	assert_gt(attacks.size(), 0, "in gas it attacks")
	var hound := Enemy.new()
	hound.setup_enemy({"hunts_in": "dark", "flee": "light", "speed": 4.0, "damage": 7.0, "sight": 20.0})
	hound.perceive([Vector3(1.0, 0, 0)], 0.0, 1.0, false)
	hound._brain(0.1)
	assert_true(hound.moving, "fleeing the light")
	assert_lt(hound.wander_dir.x, 0.0, "away from the target")
	e.free()
	hound.free()
