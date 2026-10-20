extends TestCase
## Data files must load without validation errors and expose stable ids.


func _new_registry() -> Node:
	var script: GDScript = load("res://src/data/data_registry.gd")
	return script.new() as Node


func test_materials_load_and_validate() -> void:
	var reg: Node = _new_registry()
	reg.load_all()
	assert_eq(reg.errors.size(), 0, "validation errors: %s" % ", ".join(reg.errors))
	assert_eq(reg.block(0).name, "air")
	assert_true(reg.block_id("stone") > 0, "stone id")
	assert_true(reg.block(reg.block_id("brick")).airtight, "brick airtight")
	assert_false(reg.block(reg.block_id("thatch")).airtight, "thatch leaks")
	assert_true(reg.block(reg.block_id("glass")).opacity < 0.5, "glass passes light")
	assert_true(reg.planets.has("04"), "planet 04 present")
	assert_eq(int(reg.mode("short")["days"]), 30)
	reg.free()


func test_unknown_block_is_air() -> void:
	var reg: Node = _new_registry()
	reg.load_all()
	assert_eq(reg.block(9999).id, 0)
	assert_eq(reg.block(-1).id, 0)
	reg.free()
