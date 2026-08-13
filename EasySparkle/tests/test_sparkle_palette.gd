extends SceneTree

const SparklePalette = preload("res://src/Extensions/EasySparkle/SparklePalette.gd")

const EPSILON := 0.0005


func _init() -> void:
	# Representative warm, cool, neutral, dark, and light colors, plus the
	# edge cases the acceptance criteria call out explicitly: near-black,
	# near-white, low-saturation, and partially transparent.
	var cases := {
		"warm": Color.from_ok_hsl(0.08, 0.65, 0.55, 1.0),
		"cool": Color.from_ok_hsl(0.62, 0.60, 0.45, 1.0),
		"neutral_gray": Color.from_ok_hsl(0.0, 0.0, 0.5, 1.0),
		"dark": Color.from_ok_hsl(0.35, 0.50, 0.15, 1.0),
		"light": Color.from_ok_hsl(0.90, 0.50, 0.85, 1.0),
		"near_black": Color.from_ok_hsl(0.5, 0.8, 0.01, 1.0),
		"near_white": Color.from_ok_hsl(0.2, 0.8, 0.99, 1.0),
		"low_saturation": Color.from_ok_hsl(0.45, 0.03, 0.5, 1.0),
		"partially_transparent": Color.from_ok_hsl(0.62, 0.70, 0.40, 0.35),
		"fully_transparent": Color.from_ok_hsl(0.62, 0.70, 0.40, 0.0),
	}

	for case_name in cases.keys():
		var source: Color = cases[case_name]
		var palette := SparklePalette.build(source)
		_assert_has_all_roles(palette, case_name)
		_assert_base_identical(palette, source, case_name)
		_assert_alpha_preserved(palette, source, case_name)
		_assert_saturation_preserved(palette, source, case_name)
		_assert_in_gamut(palette, case_name)
		_assert_stable_lightness_order(palette, case_name)

	_test_hue_rotates_in_opposite_directions()
	_test_hue_rotation_wraps_at_both_ends()

	print("EasySparkle palette derivation checks passed")
	quit(0)


func _assert_has_all_roles(palette: Dictionary, case_name: String) -> void:
	for role in SparklePalette.ROLE_ORDER:
		_assert(palette.has(role), "%s: palette missing role %s" % [case_name, role])
	_assert(
		palette.size() == SparklePalette.ROLE_ORDER.size(),
		"%s: palette should contain exactly the six defined roles" % case_name
	)


func _assert_base_identical(palette: Dictionary, source: Color, case_name: String) -> void:
	var base: Color = palette[SparklePalette.Role.BASE]
	_assert(base == source, "%s: base role should be identical to the sampled color" % case_name)


func _assert_alpha_preserved(palette: Dictionary, source: Color, case_name: String) -> void:
	for role in SparklePalette.ROLE_ORDER:
		var result: Color = palette[role]
		_assert(
			is_equal_approx(result.a, source.a),
			"%s: role %s should preserve source alpha (got %f, expected %f)" % [case_name, role, result.a, source.a]
		)


func _assert_in_gamut(palette: Dictionary, case_name: String) -> void:
	for role in SparklePalette.ROLE_ORDER:
		var result: Color = palette[role]
		for component in [result.r, result.g, result.b, result.a]:
			_assert(
				component >= -EPSILON and component <= 1.0 + EPSILON,
				"%s: role %s produced an out-of-gamut component (%f)" % [case_name, role, component]
			)


## Lightness must be non-decreasing across ROLE_ORDER (deep shadow ... peak
## sparkle) for every input, including degenerate cases where several roles
## saturate to the same black/white value.
func _assert_stable_lightness_order(palette: Dictionary, case_name: String) -> void:
	var previous_lightness := -1.0
	for role in SparklePalette.ROLE_ORDER:
		var result: Color = palette[role]
		var lightness := result.ok_hsl_l
		_assert(
			lightness >= previous_lightness - EPSILON,
			(
				"%s: role %s (l=%f) should not be darker than the previous role (l=%f)"
				% [case_name, role, lightness, previous_lightness]
			)
		)
		previous_lightness = lightness


func _test_hue_rotates_in_opposite_directions() -> void:
	var source := Color.from_ok_hsl(0.40, 0.65, 0.50, 0.75)
	var palette := SparklePalette.build(source)

	for role in [SparklePalette.Role.DEEP_SHADOW, SparklePalette.Role.SHADOW]:
		var result: Color = palette[role]
		_assert(
			_signed_hue_delta(result.ok_hsl_h, source.ok_hsl_h) > 0.0,
			"shadow role %s should rotate hue in the coolward direction" % role
		)


func _assert_saturation_preserved(palette: Dictionary, source: Color, case_name: String) -> void:
	for role in SparklePalette.ROLE_ORDER:
		var result: Color = palette[role]
		_assert(
			absf(result.ok_hsl_s - source.ok_hsl_s) <= EPSILON,
			(
				"%s: role %s should preserve source saturation (got %f, expected %f)"
				% [case_name, role, result.ok_hsl_s, source.ok_hsl_s]
			)
		)
	for role in [
		SparklePalette.Role.SOFT_HIGHLIGHT,
		SparklePalette.Role.BRIGHT_HIGHLIGHT,
		SparklePalette.Role.PEAK_SPARKLE,
	]:
		var result: Color = palette[role]
		_assert(
			_signed_hue_delta(result.ok_hsl_h, source.ok_hsl_h) < 0.0,
			"highlight role %s should rotate hue in the warmward direction" % role
		)


func _test_hue_rotation_wraps_at_both_ends() -> void:
	var near_zero := Color.from_ok_hsl(0.01, 0.65, 0.50, 1.0)
	var zero_palette := SparklePalette.build(near_zero)
	var warm_highlight: Color = zero_palette[SparklePalette.Role.PEAK_SPARKLE]
	_assert(
		warm_highlight.ok_hsl_h > 0.9 and warm_highlight.ok_hsl_h < 1.0,
		"negative highlight rotation should wrap a near-zero hue into the top of [0, 1)"
	)
	_assert(
		_signed_hue_delta(warm_highlight.ok_hsl_h, near_zero.ok_hsl_h) < 0.0,
		"wrapped highlight hue should retain its warmward signed direction"
	)

	var near_one := Color.from_ok_hsl(0.99, 0.65, 0.50, 1.0)
	var one_palette := SparklePalette.build(near_one)
	var cool_shadow: Color = one_palette[SparklePalette.Role.DEEP_SHADOW]
	_assert(
		cool_shadow.ok_hsl_h >= 0.0 and cool_shadow.ok_hsl_h < 0.1,
		"positive shadow rotation should wrap a near-one hue into the bottom of [0, 1)"
	)
	_assert(
		_signed_hue_delta(cool_shadow.ok_hsl_h, near_one.ok_hsl_h) > 0.0,
		"wrapped shadow hue should retain its coolward signed direction"
	)


func _signed_hue_delta(hue: float, source_hue: float) -> float:
	return fposmod(hue - source_hue + 0.5, 1.0) - 0.5


func _assert(condition: bool, message: String) -> void:
	assert(condition, message)
