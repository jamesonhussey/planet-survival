extends TestCase


func test_ritual_needs_a_fire_through_a_night() -> void:
	var r := Ritual.new(Vector3i(0, 50, 0), 2, 1.5)
	# Daytime: nothing accumulates.
	assert_false(r.tick(0.1, false, true, true))
	assert_near(r.progress(), 0.0)
	# Night without fire: paused.
	assert_false(r.tick(0.2, true, false, true))
	assert_near(r.progress(), 0.0)
	# Night with fire: 0.4 day of night = one full night.
	assert_false(r.tick(0.2, true, true, true))
	assert_near(r.progress(), 0.5, 0.01)
	assert_true(r.tick(0.2, true, true, true))
	assert_true(r.complete)


func test_ritual_fails_if_cairn_destroyed_and_scales_with_revives() -> void:
	var r := Ritual.new(Vector3i.ZERO, 3, 0.0)
	r.tick(0.1, true, true, false)
	assert_true(r.failed)
	assert_eq(r.fail_reason, "the cairn was destroyed")
	var second := Ritual.new(Vector3i.ZERO, 3, 0.0, 1)
	assert_near(second.night_needed, 1.25)


func test_humanoid_rig() -> void:
	var rig := VoxelArt.rig("humanoid", {}, 77)
	for n in ["torso", "head", "arm_l", "arm_r", "leg_l", "leg_r"]:
		assert_not_null(rig.get_part(n), n)
	assert_gt(rig.height, 1.5)


func test_gas_packing_round_trip() -> void:
	var cells := {Vector3i(-12, 40, 300): 0.5, Vector3i(5, 41, -7): 1.0, Vector3i(900, 3, 900): 0.2}
	var packed := Replicator.pack_gas(cells, [Vector3(0, 40, 0)], 64.0)
	var back := Replicator.unpack_gas(packed)
	assert_eq(back.size(), 1, "cells beyond the radius are culled")
	assert_false(back.has(Vector3i(-12, 40, 300)))
	assert_near(back[Vector3i(5, 41, -7)], 1.0, 0.01)
	var all := Replicator.unpack_gas(Replicator.pack_gas(cells, [], 0.0))
	assert_eq(all.size(), 3, "no centers = everything")
	assert_near(all[Vector3i(-12, 40, 300)], 0.5, 0.01)
