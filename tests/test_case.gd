class_name TestCase
extends RefCounted
## Base class for unit tests. Subclass in tests/unit/test_*.gd and add
## methods named test_*. Assertions are non-fatal: a test keeps running and
## every failure is reported with the method name.

var _failures: PackedStringArray = []
var _current: String = ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		fail("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	if actual == unexpected:
		fail("%s expected something other than %s" % [msg, str(unexpected)])


func assert_near(actual: float, expected: float, eps: float = 1e-4, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("%s expected %f within %f, got %f" % [msg, expected, eps, actual])


func assert_gt(a: float, b: float, msg: String = "") -> void:
	if not (a > b):
		fail("%s expected %s > %s" % [msg, str(a), str(b)])


func assert_lt(a: float, b: float, msg: String = "") -> void:
	if not (a < b):
		fail("%s expected %s < %s" % [msg, str(a), str(b)])


func assert_null(v: Variant, msg: String = "expected null") -> void:
	if v != null:
		fail(msg)


func assert_not_null(v: Variant, msg: String = "expected non-null") -> void:
	if v == null:
		fail(msg)
