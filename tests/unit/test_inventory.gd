extends TestCase


func _def(id: String, w: int, h: int, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "name": id, "size": [w, h], "weight": 1.0}
	d.merge(extra, true)
	return d


func test_place_fit_and_overlap() -> void:
	var g := InventoryGrid.new(4, 3)
	var a := ItemInstance.new(_def("a", 2, 1))
	var b := ItemInstance.new(_def("b", 1, 1))
	assert_true(g.place(a, 0, 0))
	assert_false(g.can_place(b, 1, 0, false), "overlaps a")
	assert_true(g.can_place(b, 2, 0, false))
	assert_false(g.can_place(b, 4, 0, false), "out of bounds")
	assert_false(g.can_place(a, 3, 0, false), "2 wide at x=3 of 4 does not fit")
	assert_eq(g.item_at(1, 0), a)
	assert_eq(g.position_of(a), Vector2i(0, 0))
	assert_true(g.remove(a))
	assert_null(g.item_at(1, 0))
	assert_eq(g.free_cells(), 12)


func test_rotation() -> void:
	var g := InventoryGrid.new(2, 3)
	var tall := ItemInstance.new(_def("t", 1, 3))
	assert_false(g.can_place(tall, 0, 0, true), "rotated 3x1 does not fit in 2 wide")
	assert_true(g.place(tall, 0, 0, false))
	assert_eq(tall.size(), Vector2i(1, 3))
	var wide := ItemInstance.new(_def("w", 2, 1))
	assert_true(g.can_place(wide, 1, 0, true), "rotated to 1x2 fits beside")
	assert_true(g.place(wide, 1, 0, true))
	assert_true(wide.rotated)
	assert_eq(wide.size(), Vector2i(1, 2))
	var square := ItemInstance.new(_def("s", 1, 1))
	assert_false(square.can_rotate())


func test_auto_place_and_stacking() -> void:
	var g := InventoryGrid.new(2, 2)
	var s1 := ItemInstance.new(_def("dirt", 1, 1, {"stack": 10}), 8)
	var s2 := ItemInstance.new(_def("dirt", 1, 1, {"stack": 10}), 5)
	assert_true(g.auto_place(s1))
	assert_true(g.auto_place(s2))
	assert_eq(s1.count, 10, "merged up to max")
	assert_eq(s2.count, 3, "remainder placed")
	assert_eq(g.items.size(), 2)
	for i in 2:
		assert_true(g.auto_place(ItemInstance.new(_def("x%d" % i, 1, 1))))
	assert_false(g.auto_place(ItemInstance.new(_def("y", 1, 1))), "grid full")
	var big := ItemInstance.new(_def("big", 2, 1))
	var g2 := InventoryGrid.new(1, 2)
	assert_true(g2.auto_place(big), "auto place rotates to fit")
	assert_true(big.rotated)


func test_move_within_and_between_grids() -> void:
	var a := InventoryGrid.new(3, 1)
	var b := InventoryGrid.new(3, 1)
	var it := ItemInstance.new(_def("i", 2, 1))
	assert_true(a.place(it, 0, 0))
	assert_true(a.move(it, 1, 0, false), "can shift onto its own cells")
	assert_eq(a.position_of(it), Vector2i(1, 0))
	assert_true(b.move(it, 0, 0, false))
	assert_false(a.has(it))
	assert_true(b.has(it))
	assert_eq(it.parent_grid, b)


func test_nested_containers_and_weight() -> void:
	var backpack := ItemInstance.new(_def("pack", 3, 4, {"grids": [[4, 4]], "slot": "backpack", "weight": 0.8}))
	var pouch := ItemInstance.new(_def("pouch", 1, 2, {"grids": [[2, 2]], "weight": 0.15}))
	var rock := ItemInstance.new(_def("rock", 1, 1, {"weight": 2.0, "stack": 5}), 3)
	assert_true(backpack.grids[0].auto_place(pouch))
	assert_true(pouch.grids[0].auto_place(rock))
	assert_near(backpack.weight(), 0.8 + 0.15 + 6.0, 0.001)
	assert_eq(backpack.contents().size(), 2, "pouch and rock")
	# A container cannot go inside itself or inside its own contents.
	assert_false(backpack.grids[0].can_place(backpack, 0, 2, false), "self")
	assert_false(pouch.grids[0].can_place(backpack, 0, 0, false), "inside own contents")
	assert_false(pouch.grids[0].can_place(pouch, 0, 0, false), "pouch in pouch")


func test_equipment_flow() -> void:
	var eq := Equipment.new()
	var pack := ItemInstance.new(_def("pack", 3, 4, {"grids": [[4, 4]], "slot": "backpack"}))
	var rig := ItemInstance.new(_def("rig", 3, 3, {"grids": [[2, 2], [1, 2]], "slot": "rig"}))
	assert_true(eq.equip(pack))
	assert_true(eq.equip(rig))
	assert_false(eq.equip(ItemInstance.new(_def("pack2", 3, 4, {"grids": [[4, 4]], "slot": "backpack"}))), "slot taken")
	assert_eq(eq.all_grids().size(), 4 + 2 + 1)
	var meds := ItemInstance.new(_def("bandage", 1, 1, {"category": "medical", "med": "bandage"}))
	assert_true(eq.add_item(meds))
	assert_true(eq.rig.grids[0].has(meds), "rig preferred for small items")
	var dirt := ItemInstance.new(_def("dirt", 1, 1, {"stack": 32, "block": "dirt"}), 40)
	assert_true(eq.add_item(dirt), "40 dirt split across stacks")
	assert_eq(eq.count_of("dirt"), 40)
	assert_eq(eq.consume("dirt", 35), 35)
	assert_eq(eq.count_of("dirt"), 5)
	eq.set_quick(0, meds)
	assert_eq(eq.quick_item(0), meds)
	eq.remove_item(meds)
	assert_null(eq.quick_item(0), "quick slot cleared when item leaves")
	assert_gt(eq.total_weight(), 0.0)


func test_examine_and_split() -> void:
	var unknown := ItemInstance.new(_def("hemostat", 1, 1, {"known": false, "unknown_name": "Sealed packet"}))
	assert_eq(unknown.display_name(), "Sealed packet")
	unknown.examined = true
	assert_eq(unknown.display_name(), "hemostat")
	var stack := ItemInstance.new(_def("dirt", 1, 1, {"stack": 32}), 10)
	var half := stack.split(4)
	assert_eq(stack.count, 6)
	assert_eq(half.count, 4)
	assert_null(stack.split(6), "cannot split everything")
