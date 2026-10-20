extends TestCase


func test_clean_air_keeps_oxygen_full() -> void:
	var v := Vitals.new()
	v.configure({"oxygen_seconds": 10, "suffocation_dps": 5, "gas_threshold": 0.2})
	for i in 100:
		v.breathe(0.1, 0.1)
	assert_near(v.oxygen, 1.0)
	assert_eq(v.hp, 100.0)
	assert_true(v.alive)


func test_gas_drains_then_damages_then_kills() -> void:
	var v := Vitals.new()
	v.configure({"oxygen_seconds": 10, "suffocation_dps": 5, "gas_threshold": 0.2})
	var t := 0.0
	while v.oxygen > 0.0 and t < 100.0:
		v.breathe(0.2, 0.1)
		t += 0.1
	assert_true(t <= 10.5, "at threshold concentration lungs empty in ~oxygen_seconds (%.1f)" % t)
	assert_eq(v.hp, 100.0, "no damage until oxygen is gone")
	v.breathe(0.2, 1.0)
	assert_near(v.hp, 95.0, 0.01)
	for i in 30:
		v.breathe(0.2, 1.0)
	assert_false(v.alive)
	assert_eq(v.last_damage_cause, "suffocation")


func test_thick_gas_is_faster() -> void:
	var a := Vitals.new()
	var b := Vitals.new()
	for i in 50:
		a.breathe(0.25, 0.1)
		b.breathe(1.0, 0.1)
	assert_lt(b.oxygen, a.oxygen)


func test_recovery_after_escape() -> void:
	var v := Vitals.new()
	v.configure({"oxygen_seconds": 10, "oxygen_recover_seconds": 2})
	for i in 50:
		v.breathe(0.5, 0.1)
	assert_lt(v.oxygen, 1.0)
	for i in 30:
		v.breathe(0.0, 0.1)
	assert_near(v.oxygen, 1.0)
	assert_false(v.suffocating)


func test_hazard_director_curves() -> void:
	assert_near(HazardDirector.curve({"base": 2.0, "per_day": -0.02, "min": 0.5}, 0.0, 1.0), 2.0)
	assert_near(HazardDirector.curve({"base": 2.0, "per_day": -0.02, "min": 0.5}, 100.0, 1.0), 0.5)
	assert_near(HazardDirector.curve({"base": 1.0, "per_day": 0.03, "max": 3.0}, 100.0, 1.0), 3.0)
	assert_near(HazardDirector.curve(1.5, 50.0, 1.0), 1.5)
	assert_near(HazardDirector.curve(null, 50.0, 7.0), 7.0)
