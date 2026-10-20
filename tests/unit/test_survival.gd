extends TestCase


func test_hunger_and_thirst_drain_then_damage() -> void:
	var v := Vitals.new()
	v.configure({"hunger_hours": 10, "thirst_hours": 5})
	v.metabolize(5 * 3600.0)
	assert_near(v.hunger, 0.5, 0.01)
	assert_near(v.thirst, 0.0, 0.01)
	assert_true(v.dehydrated)
	assert_false(v.starving)
	var hp_before := v.hp
	v.metabolize(10.0)
	assert_lt(v.hp, hp_before, "dehydration hurts")
	assert_eq(v.last_damage_cause, "dehydration")
	v.consume({"thirst": 0.3})
	assert_near(v.thirst, 0.3, 0.001)
	v.metabolize(1.0)
	assert_false(v.dehydrated)


func test_temperature_follows_environment() -> void:
	var v := Vitals.new()
	v.configure({"comfort_temp": 20})
	for i in 60:
		v.metabolize(60.0, {"ambient": 0.0})
	assert_lt(v.temperature, 35.0, "freezing night drops core temperature")
	assert_true(v.cold)
	var hp := v.hp
	v.metabolize(60.0, {"ambient": 0.0})
	assert_lt(v.hp, hp, "hypothermia damage")
	for i in 60:
		v.metabolize(60.0, {"ambient": 0.0, "heat_source": 1.0})
	assert_gt(v.temperature, 36.0, "a fire warms you back up")
	var open_air := Vitals.new()
	var sheltered := Vitals.new()
	for i in 30:
		open_air.metabolize(60.0, {"ambient": 0.0})
		sheltered.metabolize(60.0, {"ambient": 0.0, "sheltered": true})
	assert_gt(sheltered.temperature, open_air.temperature, "shelter helps versus the open")


func test_stamina() -> void:
	var v := Vitals.new()
	for i in 20:
		v.exert(0.5, true)
	assert_lt(v.stamina, 0.1)
	assert_false(v.can_sprint())
	for i in 20:
		v.exert(0.5, false)
	assert_true(v.can_sprint())
	assert_lt(v.speed_factor(), 1.01)


func test_crafting_resolution() -> void:
	var eq := Equipment.new()
	eq.equip(Data.make_item("backpack_small"))
	var planks := Data.item_def("planks")
	assert_false(planks.is_empty())
	var recipe := {"id": "planks_from_log", "in": [{"id": "log", "count": 1}], "out": [{"id": "planks", "count": 4}], "station": "", "time": 2.0}
	assert_false(Crafting.can_craft(recipe, eq, [])["ok"], "no log yet")
	eq.add_item(Data.make_item("log"))
	assert_true(Crafting.can_craft(recipe, eq, [])["ok"])
	var r := Crafting.craft(recipe, eq, Data)
	assert_eq(eq.count_of("log"), 0)
	assert_eq(eq.count_of("planks"), 4)
	assert_eq(r["overflow"].size(), 0)
	var fire_recipe := {"id": "cooked_meat", "in": [{"id": "meat_raw", "count": 1}], "out": [{"id": "meat_cooked", "count": 1}], "station": "campfire", "time": 4.0}
	eq.add_item(Data.make_item("meat_raw"))
	assert_false(Crafting.can_craft(fire_recipe, eq, [])["ok"], "needs a campfire")
	assert_true(Crafting.can_craft(fire_recipe, eq, ["campfire"])["ok"])


func test_recipe_data_is_consistent() -> void:
	var doc := Data.load_json("res://data/recipes.json")
	var recipes: Array = doc.get("recipes", [])
	assert_gt(recipes.size(), 5)
	for r in recipes:
		for inp in r.get("in", []):
			assert_true(Data.items.has(str(inp["id"])), "recipe %s input %s exists" % [r["id"], inp["id"]])
		for outp in r.get("out", []):
			assert_true(Data.items.has(str(outp["id"])), "recipe %s output %s exists" % [r["id"], outp["id"]])
	assert_true(Data.block("campfire".to_int() if false else Data.block_id("campfire")).heat > 0.0, "campfire is a heat source")
	assert_eq(Data.block(Data.block_id("campfire")).station, "campfire")
