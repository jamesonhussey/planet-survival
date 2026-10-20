extends TestCase
## Sanity test proving the runner discovers files and reports assertions.


func test_assertions_work() -> void:
	assert_eq(1 + 1, 2)
	assert_true(true)
	assert_near(0.1 + 0.2, 0.3, 1e-6)
