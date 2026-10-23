extends RefCounted
## Base assertion helper for SLIME RUSH: EVOLUTION automated GDScript test suites.
##
## Deliberately NOT a global class (`class_name`): a registered global class is always
## packed by the exporter, which dragged the whole QA suite into the shipped .pck even
## though the preset excludes `tests/*`. Suites extend this by path instead.

var suite_name: String = "UnnamedSuite"
var assertions_passed: int = 0
var assertions_failed: int = 0
var failure_messages: Array[String] = []


func _init(p_name: String = "Suite") -> void:
	suite_name = p_name


func _pass() -> void:
	assertions_passed += 1


func _fail(msg: String) -> void:
	assertions_failed += 1
	var formatted := "[FAIL] %s: %s" % [suite_name, msg]
	failure_messages.append(formatted)
	printerr(formatted)


func assert_true(cond: bool, msg: String = "Expected true") -> void:
	if cond:
		_pass()
	else:
		_fail(msg)


func assert_false(cond: bool, msg: String = "Expected false") -> void:
	if not cond:
		_pass()
	else:
		_fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual == expected:
		_pass()
	else:
		_fail("%s (expected=%s, actual=%s)" % [msg if not msg.is_empty() else "Values not equal", str(expected), str(actual)])


func assert_gt(a: float, b: float, msg: String = "") -> void:
	if a > b:
		_pass()
	else:
		_fail("%s (expected %f > %f)" % [msg if not msg.is_empty() else "Expected greater", a, b])


func assert_gte(a: float, b: float, msg: String = "") -> void:
	if a >= b:
		_pass()
	else:
		_fail("%s (expected %f >= %f)" % [msg if not msg.is_empty() else "Expected >=", a, b])


func assert_lt(a: float, b: float, msg: String = "") -> void:
	if a < b:
		_pass()
	else:
		_fail("%s (expected %f < %f)" % [msg if not msg.is_empty() else "Expected less", a, b])


func assert_lte(a: float, b: float, msg: String = "") -> void:
	if a <= b:
		_pass()
	else:
		_fail("%s (expected %f <= %f)" % [msg if not msg.is_empty() else "Expected <=", a, b])


func assert_approx(a: float, b: float, tol: float = 0.01, msg: String = "") -> void:
	if absf(a - b) <= tol:
		_pass()
	else:
		_fail("%s (expected ~%f ± %f, got %f)" % [msg if not msg.is_empty() else "Approx mismatch", b, tol, a])
