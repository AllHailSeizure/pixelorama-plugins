extends SceneTree

const SparklePalette = preload("res://src/Extensions/EasySparkle/SparklePalette.gd")
const SparkleQuota = preload("res://src/Extensions/EasySparkle/SparkleQuota.gd")
const SparkleRegion = preload("res://src/Extensions/EasySparkle/SparkleRegion.gd")
const SparkleFill = preload("res://src/Extensions/EasySparkle/SparkleFill.gd")

const BG := Color(1, 1, 1, 1)
const TARGET := Color(0.5, 0.2, 0.7, 1.0)


func _init() -> void:
	_test_applied_counts_match_quota()
	_test_pixels_outside_region_unchanged()
	_test_every_region_pixel_is_a_palette_color()
	_test_alpha_and_silhouette_unchanged()
	_test_deterministic_regardless_of_click_point()
	_test_highlights_favor_upper_left_shadows_favor_lower_right()
	_test_peak_sparkle_points_are_spaced_apart()
	_test_empty_region_is_a_no_op()
	_test_custom_profile_counts_match()
	_test_indexed_image_guarded_calls_do_not_crash()
	_test_default_seed_matches_explicit_seed_zero()
	_test_same_seed_reproduces_same_arrangement()
	_test_different_seed_changes_placement_but_not_quotas_or_palette()
	_test_shadow_boundary_is_interleaved()
	_test_reroll_regenerates_from_source_without_compounding()

	print("EasySparkle fill checks passed")
	quit(0)


## Builds a `size` x `size` opaque TARGET-colored square on a larger BG
## canvas, offset so the square never touches the canvas edge -- keeping a
## ring of untouched background pixels to assert against.
func _build_square_image(size: int, canvas_size: int = -1) -> Dictionary:
	if canvas_size < 0:
		canvas_size = size + 6
	var image := Image.create_empty(canvas_size, canvas_size, false, Image.FORMAT_RGBA8)
	image.fill(BG)
	var offset := Vector2i(3, 3)
	for y in size:
		for x in size:
			image.set_pixelv(offset + Vector2i(x, y), TARGET)
	return {"image": image, "offset": offset, "size": size}


func _test_applied_counts_match_quota() -> void:
	var built := _build_square_image(20)
	var image: Image = built["image"]
	var region := SparkleRegion.find_region(image, built["offset"])
	var expected := SparkleQuota.build(region["points"].size())

	var counts := SparkleFill.apply(image, region)

	for role in SparklePalette.ROLE_ORDER:
		_assert(
			counts[role] == expected[role],
			"role %s: applied count %d should match quota %d" % [role, counts[role], expected[role]]
		)
	var total := 0
	for role in SparklePalette.ROLE_ORDER:
		total += counts[role]
	_assert(total == region["points"].size(), "applied counts should sum to region size")


func _test_pixels_outside_region_unchanged() -> void:
	var built := _build_square_image(10)
	var image: Image = built["image"]
	var before := image.duplicate()
	var region := SparkleRegion.find_region(image, built["offset"])

	SparkleFill.apply(image, region)

	var region_set := {}
	for point: Vector2i in region["points"]:
		region_set[point] = true
	for y in image.get_height():
		for x in image.get_width():
			var point := Vector2i(x, y)
			if region_set.has(point):
				continue
			_assert(
				image.get_pixelv(point).is_equal_approx(before.get_pixelv(point)),
				"pixel %s outside the region should be unchanged" % point
			)


func _test_every_region_pixel_is_a_palette_color() -> void:
	var built := _build_square_image(12)
	var image: Image = built["image"]
	var region := SparkleRegion.find_region(image, built["offset"])
	var palette := SparklePalette.build(region["color"])
	var palette_colors: Array[Color] = []
	for role in SparklePalette.ROLE_ORDER:
		palette_colors.append(palette[role])

	SparkleFill.apply(image, region)

	for point: Vector2i in region["points"]:
		var color := image.get_pixelv(point)
		var matched := false
		for palette_color in palette_colors:
			if _colors_match(color, palette_color):
				matched = true
				break
		_assert(matched, "region pixel %s color %s should be one of the palette's six colors" % [point, color])


func _test_alpha_and_silhouette_unchanged() -> void:
	var built := _build_square_image(10)
	var image: Image = built["image"]
	var region := SparkleRegion.find_region(image, built["offset"])
	var source_alpha: float = region["color"].a

	SparkleFill.apply(image, region)

	for point: Vector2i in region["points"]:
		_assert(
			is_equal_approx(image.get_pixelv(point).a, source_alpha),
			"pixel %s alpha should be unchanged by the fill" % point
		)


## The same connected region, discovered by clicking two different member
## pixels (so SparkleRegion's flood fill visits/returns points in a
## different order), must still produce byte-identical fill results.
func _test_deterministic_regardless_of_click_point() -> void:
	var built_a := _build_square_image(14)
	var built_b := _build_square_image(14)
	var image_a: Image = built_a["image"]
	var image_b: Image = built_b["image"]
	var offset: Vector2i = built_a["offset"]
	var size: int = built_a["size"]

	var region_a := SparkleRegion.find_region(image_a, offset)
	var region_b := SparkleRegion.find_region(image_b, offset + Vector2i(size - 1, size - 1))

	SparkleFill.apply(image_a, region_a)
	SparkleFill.apply(image_b, region_b)

	_assert(_images_equal(image_a, image_b), "fills from two different click points on the same region should match exactly")

	# Re-running on a fresh copy of the same region should also reproduce
	# the exact same result.
	var built_c := _build_square_image(14)
	var image_c: Image = built_c["image"]
	var region_c := SparkleRegion.find_region(image_c, offset)
	SparkleFill.apply(image_c, region_c)
	_assert(_images_equal(image_a, image_c), "repeated fills of the same region should be identical")


func _test_highlights_favor_upper_left_shadows_favor_lower_right() -> void:
	var built := _build_square_image(20)
	var image: Image = built["image"]
	var region := SparkleRegion.find_region(image, built["offset"])
	var palette := SparklePalette.build(region["color"])

	SparkleFill.apply(image, region)

	var highlight_colors: Array[Color] = [
		palette[SparklePalette.Role.SOFT_HIGHLIGHT],
		palette[SparklePalette.Role.BRIGHT_HIGHLIGHT],
		palette[SparklePalette.Role.PEAK_SPARKLE],
	]
	var shadow_colors: Array[Color] = [
		palette[SparklePalette.Role.DEEP_SHADOW],
		palette[SparklePalette.Role.SHADOW],
	]

	var highlight_sum := Vector2i.ZERO
	var highlight_count := 0
	var shadow_sum := Vector2i.ZERO
	var shadow_count := 0
	for point: Vector2i in region["points"]:
		var color := image.get_pixelv(point)
		if _color_in(color, highlight_colors):
			highlight_sum += point
			highlight_count += 1
		elif _color_in(color, shadow_colors):
			shadow_sum += point
			shadow_count += 1

	_assert(highlight_count > 0, "test region should be large enough to receive highlight pixels")
	_assert(shadow_count > 0, "test region should be large enough to receive shadow pixels")

	var highlight_avg := Vector2(highlight_sum) / float(highlight_count)
	var shadow_avg := Vector2(shadow_sum) / float(shadow_count)

	_assert(
		highlight_avg.x + highlight_avg.y < shadow_avg.x + shadow_avg.y,
		(
			"highlight pixels should sit closer to the upper-left than shadow pixels (highlight avg %s, shadow avg %s)"
			% [highlight_avg, shadow_avg]
		)
	)


func _test_peak_sparkle_points_are_spaced_apart() -> void:
	var built := _build_square_image(24)
	var image: Image = built["image"]
	var region := SparkleRegion.find_region(image, built["offset"])
	var palette := SparklePalette.build(region["color"])
	var peak_color: Color = palette[SparklePalette.Role.PEAK_SPARKLE]

	SparkleFill.apply(image, region)

	var peak_points: Array[Vector2i] = []
	for point: Vector2i in region["points"]:
		if _colors_match(image.get_pixelv(point), peak_color):
			peak_points.append(point)

	_assert(peak_points.size() > 1, "a 24x24 region should receive more than one peak sparkle pixel")

	for i in peak_points.size():
		for j in range(i + 1, peak_points.size()):
			var a := peak_points[i]
			var b := peak_points[j]
			var chebyshev := maxi(absi(a.x - b.x), absi(a.y - b.y))
			_assert(
				chebyshev >= SparkleFill.PEAK_SPARKLE_MIN_SPACING,
				"peak sparkle points %s and %s should be spaced at least %d apart (got %d)" % [a, b, SparkleFill.PEAK_SPARKLE_MIN_SPACING, chebyshev]
			)


func _test_empty_region_is_a_no_op() -> void:
	var built := _build_square_image(10)
	var image: Image = built["image"]
	var before := image.duplicate()

	var counts := SparkleFill.apply(image, {})
	for role in SparklePalette.ROLE_ORDER:
		_assert(counts[role] == 0, "empty region should produce all-zero counts")
	_assert(_images_equal(image, before), "empty region should leave the image untouched")

	var null_counts := SparkleFill.apply(null, {"color": TARGET, "points": [Vector2i.ZERO]})
	for role in SparklePalette.ROLE_ORDER:
		_assert(null_counts[role] == 0, "null image should produce all-zero counts")


func _test_custom_profile_counts_match() -> void:
	var built := _build_square_image(15)
	var image: Image = built["image"]
	var region := SparkleRegion.find_region(image, built["offset"])
	var profile := {
		SparklePalette.Role.DEEP_SHADOW: 10.0,
		SparklePalette.Role.SHADOW: 10.0,
		SparklePalette.Role.BASE: 10.0,
		SparklePalette.Role.SOFT_HIGHLIGHT: 10.0,
		SparklePalette.Role.BRIGHT_HIGHLIGHT: 10.0,
		SparklePalette.Role.PEAK_SPARKLE: 50.0,
	}
	var expected := SparkleQuota.build(region["points"].size(), profile)

	var counts := SparkleFill.apply(image, region, profile)

	for role in SparklePalette.ROLE_ORDER:
		_assert(
			counts[role] == expected[role],
			"custom profile role %s: applied %d should match quota %d" % [role, counts[role], expected[role]]
		)


## Stock Godot's Image has neither `is_indexed` nor `set_pixelv_custom` --
## those only exist on Pixelorama's own Image subclass at runtime. This
## just proves the guarded calls (image.has_method(...) / image.get(...))
## don't crash against a plain Image, matching the same guard pattern
## EasyGradient's fill already relies on.
func _test_indexed_image_guarded_calls_do_not_crash() -> void:
	var built := _build_square_image(6)
	var image: Image = built["image"]
	var region := SparkleRegion.find_region(image, built["offset"])
	var counts := SparkleFill.apply(image, region)
	var total := 0
	for role in SparklePalette.ROLE_ORDER:
		total += counts[role]
	_assert(total == region["points"].size(), "fill should complete normally when indexed-image hooks are absent")


## Seed 0 (the default) must reproduce the exact placement SparkleFill
## produced before seeds existed -- calling apply() with no seed argument
## and calling it with an explicit seed of 0 must be indistinguishable.
func _test_default_seed_matches_explicit_seed_zero() -> void:
	var built_default := _build_square_image(16)
	var image_default: Image = built_default["image"]
	var region_default := SparkleRegion.find_region(image_default, built_default["offset"])
	SparkleFill.apply(image_default, region_default)

	var built_zero := _build_square_image(16)
	var image_zero: Image = built_zero["image"]
	var region_zero := SparkleRegion.find_region(image_zero, built_zero["offset"])
	SparkleFill.apply(image_zero, region_zero, SparkleQuota.DEFAULT_PROFILE, 0)

	_assert(_images_equal(image_default, image_zero), "omitting the seed should be identical to passing seed 0")


## A "visible seed reproduces the same arrangement for identical source data
## and settings": the same region, profile, and seed applied to two fresh
## copies of the same source image must land on byte-identical results.
func _test_same_seed_reproduces_same_arrangement() -> void:
	var built_a := _build_square_image(18)
	var image_a: Image = built_a["image"]
	var region_a := SparkleRegion.find_region(image_a, built_a["offset"])
	SparkleFill.apply(image_a, region_a, SparkleQuota.DEFAULT_PROFILE, 12345)

	var built_b := _build_square_image(18)
	var image_b: Image = built_b["image"]
	var region_b := SparkleRegion.find_region(image_b, built_b["offset"])
	SparkleFill.apply(image_b, region_b, SparkleQuota.DEFAULT_PROFILE, 12345)

	_assert(_images_equal(image_a, image_b), "the same seed on the same source region should reproduce the same arrangement")


## Rerolling must change *where* colors land while leaving the palette,
## quotas, target region, and overall lighting direction untouched. Both
## highlight and shadow boundaries are seed-driven now.
func _test_different_seed_changes_placement_but_not_quotas_or_palette() -> void:
	var built_a := _build_square_image(18)
	var image_a: Image = built_a["image"]
	var region_a := SparkleRegion.find_region(image_a, built_a["offset"])
	var counts_a := SparkleFill.apply(image_a, region_a, SparkleQuota.DEFAULT_PROFILE, 1)

	var built_b := _build_square_image(18)
	var image_b: Image = built_b["image"]
	var region_b := SparkleRegion.find_region(image_b, built_b["offset"])
	var counts_b := SparkleFill.apply(image_b, region_b, SparkleQuota.DEFAULT_PROFILE, 2)

	_assert(not _images_equal(image_a, image_b), "different seeds should visibly change role placement")

	for role in SparklePalette.ROLE_ORDER:
		_assert(
			counts_a[role] == counts_b[role],
			"role %s quota should be identical across seeds (got %d vs %d)" % [role, counts_a[role], counts_b[role]]
		)

	var palette_a := SparklePalette.build(region_a["color"])
	var palette_b := SparklePalette.build(region_b["color"])
	for role in SparklePalette.ROLE_ORDER:
		_assert(
			_colors_match(palette_a[role], palette_b[role]),
			"palette color for role %s should be unaffected by the seed" % role
		)

	_assert(region_a["points"].size() == region_b["points"].size(), "target region should be unaffected by the seed")


## The old shadow ranking used only the smooth direction score. Along every
## row and column that made DEEP_SHADOW and SHADOW monotonic: one role could
## meet the other at a clean line, but could never cross it and cross back.
## Ordered dithering should produce repeated local A-B-A alternations along
## that same boundary, proving the roles genuinely interdigitate instead of
## merely sharing a slightly crooked edge.
func _test_shadow_boundary_is_interleaved() -> void:
	var built := _build_square_image(48)
	var image: Image = built["image"]
	var offset: Vector2i = built["offset"]
	var size: int = built["size"]
	var region := SparkleRegion.find_region(image, offset)
	var palette := SparklePalette.build(region["color"])

	SparkleFill.apply(image, region, SparkleQuota.DEFAULT_PROFILE, 37)

	var deep_shadow: Color = palette[SparklePalette.Role.DEEP_SHADOW]
	var shadow: Color = palette[SparklePalette.Role.SHADOW]
	var alternations := 0
	for y in range(offset.y, offset.y + size):
		for x in range(offset.x + 1, offset.x + size - 1):
			if _is_role_alternation(
				image.get_pixel(x - 1, y), image.get_pixel(x, y), image.get_pixel(x + 1, y),
				deep_shadow, shadow
			):
				alternations += 1
	for x in range(offset.x, offset.x + size):
		for y in range(offset.y + 1, offset.y + size - 1):
			if _is_role_alternation(
				image.get_pixel(x, y - 1), image.get_pixel(x, y), image.get_pixel(x, y + 1),
				deep_shadow, shadow
			):
				alternations += 1

	_assert(
		alternations >= 4,
		"deep-shadow/shadow boundary should interleave repeatedly (found %d local alternations)" % alternations
	)


## A reroll is defined as calling apply() again for the same source region
## with a new seed -- it must regenerate the arrangement purely from the
## original source data, not transform/compound on top of the previous
## fill already painted on the image. Rerolling on an already-filled image
## must match a single fresh fill made directly with the reroll's seed.
func _test_reroll_regenerates_from_source_without_compounding() -> void:
	var built := _build_square_image(16)
	var image: Image = built["image"]
	var region := SparkleRegion.find_region(image, built["offset"])

	SparkleFill.apply(image, region, SparkleQuota.DEFAULT_PROFILE, 7)  # initial fill
	SparkleFill.apply(image, region, SparkleQuota.DEFAULT_PROFILE, 42)  # reroll, same region dict

	var built_fresh := _build_square_image(16)
	var image_fresh: Image = built_fresh["image"]
	var region_fresh := SparkleRegion.find_region(image_fresh, built_fresh["offset"])
	SparkleFill.apply(image_fresh, region_fresh, SparkleQuota.DEFAULT_PROFILE, 42)  # straight to seed 42

	_assert(
		_images_equal(image, image_fresh),
		"rerolling an already-filled region should match a fresh fill with the reroll's seed, not compound with the prior fill"
	)


func _color_in(color: Color, palette: Array[Color]) -> bool:
	for candidate in palette:
		if _colors_match(color, candidate):
			return true
	return false


func _is_role_alternation(a: Color, b: Color, c: Color, role_a: Color, role_b: Color) -> bool:
	return (
		(_colors_match(a, role_a) and _colors_match(b, role_b) and _colors_match(c, role_a))
		or (_colors_match(a, role_b) and _colors_match(b, role_a) and _colors_match(c, role_b))
	)


## Pixels are stored 8-bit-per-channel on the image, so a color read back
## from the image can differ from the float value it was written from by
## up to 1/255 per channel. Compare with a tolerance that accounts for
## that quantization instead of is_equal_approx's much tighter default.
func _colors_match(a: Color, b: Color, tolerance: float = 0.006) -> bool:
	return (
		absf(a.r - b.r) <= tolerance
		and absf(a.g - b.g) <= tolerance
		and absf(a.b - b.b) <= tolerance
		and absf(a.a - b.a) <= tolerance
	)


func _images_equal(a: Image, b: Image) -> bool:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return false
	for y in a.get_height():
		for x in a.get_width():
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true


func _assert(condition: bool, message: String) -> void:
	assert(condition, message)
