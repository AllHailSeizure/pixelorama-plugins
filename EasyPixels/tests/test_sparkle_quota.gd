extends SceneTree

const SparklePalette = preload("res://src/Extensions/EasySparkle/SparklePalette.gd")
const SparkleQuota = preload("res://src/Extensions/EasySparkle/SparkleQuota.gd")

# Region sizes covering one pixel through representative medium and large
# regions, plus a few small edge cases where low-share roles should round
# to zero.
const REGION_SIZES := [0, 1, 2, 3, 7, 20, 47, 100, 1000, 9999, 100000]

# Below this region size, low-share roles are expected to legitimately
# round to zero and BASE dominance isn't guaranteed (e.g. a 1-pixel region
# is entirely BASE, a 2-pixel region may split BASE/SOFT_HIGHLIGHT evenly).
const DOMINANCE_MIN_SIZE := 20


func _init() -> void:
	for region_size in REGION_SIZES:
		_test_sums_to_region_size(region_size)
		_test_non_negative(region_size)
		_test_deterministic(region_size)
		_test_within_one_pixel_of_exact_share(region_size)

	for region_size in REGION_SIZES:
		if region_size >= DOMINANCE_MIN_SIZE:
			_test_base_dominant(region_size)

	_test_zero_and_negative_region_size_all_zero()
	_test_one_pixel_region_is_base_only()
	_test_custom_profile_still_sums_exactly()

	print("EasySparkle quota checks passed")
	quit(0)


func _test_sums_to_region_size(region_size: int) -> void:
	var counts := SparkleQuota.build(region_size)
	var total := 0
	for role in SparklePalette.ROLE_ORDER:
		total += counts[role]
	_assert(
		total == region_size,
		"region_size=%d: counts should sum exactly to region size (got %d)" % [region_size, total]
	)


func _test_non_negative(region_size: int) -> void:
	var counts := SparkleQuota.build(region_size)
	for role in SparklePalette.ROLE_ORDER:
		_assert(
			counts[role] >= 0,
			"region_size=%d: role %s should never be negative (got %d)" % [region_size, role, counts[role]]
		)


func _test_deterministic(region_size: int) -> void:
	var first := SparkleQuota.build(region_size)
	var second := SparkleQuota.build(region_size)
	for role in SparklePalette.ROLE_ORDER:
		_assert(
			first[role] == second[role],
			"region_size=%d: role %s should be deterministic across calls" % [region_size, role]
		)


## Largest-remainder rounding guarantees each role's count stays within one
## pixel of its exact proportional share.
func _test_within_one_pixel_of_exact_share(region_size: int) -> void:
	var counts := SparkleQuota.build(region_size)
	for role in SparklePalette.ROLE_ORDER:
		var percent: float = SparkleQuota.DEFAULT_PROFILE[role]
		var exact := region_size * percent / 100.0
		var diff: float = abs(float(counts[role]) - exact)
		_assert(
			diff < 1.0 + 0.0005,
			(
				"region_size=%d: role %s count (%d) should stay within one pixel of its exact share (%f)"
				% [region_size, role, counts[role], exact]
			)
		)


func _test_base_dominant(region_size: int) -> void:
	var counts := SparkleQuota.build(region_size)
	var base_count: int = counts[SparklePalette.Role.BASE]
	for role in SparklePalette.ROLE_ORDER:
		if role == SparklePalette.Role.BASE:
			continue
		_assert(
			base_count > counts[role],
			(
				"region_size=%d: base (%d) should dominate role %s (%d)"
				% [region_size, base_count, role, counts[role]]
			)
		)


func _test_zero_and_negative_region_size_all_zero() -> void:
	for region_size in [0, -1, -100]:
		var counts := SparkleQuota.build(region_size)
		for role in SparklePalette.ROLE_ORDER:
			_assert(
				counts[role] == 0,
				"region_size=%d: every role should be zero, got %s for %s" % [region_size, counts[role], role]
			)


## A single pixel is too small to split -- it should go entirely to the
## dominant BASE role instead of forcing every color into the object.
func _test_one_pixel_region_is_base_only() -> void:
	var counts := SparkleQuota.build(1)
	_assert(counts[SparklePalette.Role.BASE] == 1, "1-pixel region should be entirely BASE")
	for role in SparklePalette.ROLE_ORDER:
		if role != SparklePalette.Role.BASE:
			_assert(counts[role] == 0, "1-pixel region: role %s should round to zero" % role)


## The quota logic is testable without modifying an image: it works purely
## off an int and a Dictionary profile, including a caller-supplied profile
## distinct from DEFAULT_PROFILE.
func _test_custom_profile_still_sums_exactly() -> void:
	var profile := {
		SparklePalette.Role.DEEP_SHADOW: 10.0,
		SparklePalette.Role.SHADOW: 10.0,
		SparklePalette.Role.BASE: 10.0,
		SparklePalette.Role.SOFT_HIGHLIGHT: 10.0,
		SparklePalette.Role.BRIGHT_HIGHLIGHT: 10.0,
		SparklePalette.Role.PEAK_SPARKLE: 50.0,
	}
	for region_size in [1, 13, 250]:
		var counts := SparkleQuota.build(region_size, profile)
		var total := 0
		for role in SparklePalette.ROLE_ORDER:
			total += counts[role]
		_assert(
			total == region_size,
			"custom profile, region_size=%d: counts should sum exactly (got %d)" % [region_size, total]
		)


func _assert(condition: bool, message: String) -> void:
	assert(condition, message)
