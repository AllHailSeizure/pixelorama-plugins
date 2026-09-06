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
		_assert_in_gamut(palette, case_name)
		_assert_stable_lightness_order(palette, case_name)

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


func _assert(condition: bool, message: String) -> void:
	assert(condition, message)
