extends TestCase


func test_head_or_thorax_zero_is_death() -> void:
	var b := BodyHealth.new()
	b.damage("left_leg", 70.0)
	assert_true(b.alive, "limb loss is not death")
	assert_true(b.is_blacked("left_leg"))
	b.damage("head", 35.0)
	assert_false(b.alive)
	var c := BodyHealth.new()
	c.damage("thorax", 85.0, "cut")
	assert_false(c.alive)
	assert_eq(c.death_cause, "cut")


func test_blacked_limb_spreads_damage() -> void:
	var b := BodyHealth.new()
	b.damage("right_arm", 60.0)
	assert_true(b.is_blacked("right_arm"))
	var before := b.total_hp()
	b.damage("right_arm", 10.0)
	assert_eq(b.hp["right_arm"], 0.0, "blacked part takes no more")
	assert_near(before - b.total_hp(), 10.0 * BodyHealth.BLACKOUT_SPREAD, 0.01, "70% spread to the rest")
	# Overflow when a limb blacks out also spreads.
	var c := BodyHealth.new()
	c.damage("left_leg", 85.0)  # 20 overflow
	assert_near(c.total_max() - c.total_hp(), 65.0 + 20.0 * BodyHealth.BLACKOUT_SPREAD, 0.01)


func test_bleeds_tick_and_bandage_stops_light_only() -> void:
	var b := BodyHealth.new()
	b.add_effect("light_bleed", "left_arm")
	b.add_effect("heavy_bleed", "stomach")
	var before := b.total_hp()
	b.tick(10.0)
	assert_near(before - b.total_hp(), 0.5 * 10.0 + 1.6 * 10.0, 0.01)
	var bandage := {"med": "bandage", "treats": ["light_bleed"], "use_time": 2.0}
	assert_false(b.med_plan(bandage, "stomach", 3, 0.0)["ok"], "bandage cannot stop a heavy bleed")
	var r := b.apply_med(bandage, "left_arm", 3, 0.0)
	assert_true(r["ok"])
	assert_false(b.has_effect("light_bleed", "left_arm"))
	assert_true(b.has_effect("heavy_bleed", "stomach"))
	var tq := {"med": "tourniquet", "treats": ["heavy_bleed", "light_bleed"]}
	assert_false(b.med_plan(tq, "stomach", 1, 0.0)["ok"], "tourniquet is limbs only")
	var hemo := {"med": "hemostat", "treats": ["heavy_bleed", "light_bleed"]}
	assert_true(b.apply_med(hemo, "stomach", 2, 0.0)["ok"])
	assert_false(b.has_effect("heavy_bleed"))


func test_medkit_pool_and_surgery() -> void:
	var b := BodyHealth.new()
	b.damage("thorax", 40.0)
	var kit := {"med": "medkit", "treats": ["light_bleed"], "heal_per_use": 30.0}
	var r := b.apply_med(kit, "thorax", 0, 50.0)
	assert_near(r["healed"], 30.0)
	assert_near(r["pool_consumed"], 30.0)
	assert_near(b.hp["thorax"], 75.0)
	r = b.apply_med(kit, "thorax", 0, 20.0)
	assert_near(r["healed"], 10.0, 0.01, "limited by remaining missing hp")
	assert_false(b.med_plan(kit, "thorax", 0, 0.0)["ok"], "empty kit")
	b.damage("left_leg", 100.0)
	assert_false(b.med_plan(kit, "left_leg", 0, 100.0)["ok"], "medkit cannot fix a destroyed limb")
	var surg := {"med": "surgical", "max_hp_penalty": 0.2, "restore_hp": 1.0, "use_time": 16.0}
	assert_false(b.med_plan(surg, "thorax", 2, 0.0)["ok"], "no surgery on thorax")
	var s := b.apply_med(surg, "left_leg", 2, 0.0)
	assert_true(s["ok"])
	assert_near(b.max_hp["left_leg"], 52.0)
	assert_near(b.hp["left_leg"], 1.0)
	assert_false(b.is_blacked("left_leg"))


func test_penalties_and_pain() -> void:
	var b := BodyHealth.new()
	assert_near(b.penalties()["move_speed"], 1.0)
	b.damage("left_leg", 65.0, "blunt")
	var p := b.penalties()
	assert_lt(p["move_speed"], 0.6)
	assert_gt(b.pain(), 0.0)
	var pk := {"med": "painkiller", "duration": 60.0}
	assert_true(b.apply_med(pk, "thorax", 4, 0.0)["ok"])
	assert_near(b.pain(), 0.0, 0.001, "painkillers suppress pain")
	b.tick(61.0)
	assert_gt(b.pain(), 0.0, "pain returns when they wear off")
	var c := BodyHealth.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	c.damage("right_arm", 30.0, "blunt", rng)
	assert_true(c.has_effect("fracture", "right_arm"), "heavy blunt hit fractures")
	assert_lt(c.penalties()["carry"], 1.0)
	var splint := {"med": "splint", "treats": ["fracture"]}
	assert_true(c.apply_med(splint, "right_arm", 1, 0.0)["ok"])
	assert_false(c.has_effect("fracture"))


func test_damage_all_and_burn() -> void:
	var b := BodyHealth.new()
	b.damage_all(10.0, "suffocation")
	assert_near(b.hp["head"], 32.0)
	assert_near(b.hp["thorax"], 78.0)
	b.damage("right_arm", 5.0, "burn")
	assert_true(b.has_effect("burn", "right_arm"))
	b.tick(31.0)
	assert_false(b.has_effect("burn"), "burns expire")
	assert_lt(b.hp["right_arm"], 55.0, "burn did damage over time")
