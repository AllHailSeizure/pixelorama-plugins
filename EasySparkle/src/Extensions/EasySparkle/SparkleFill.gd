extends RefCounted

## Applies a spatially structured sparkle fill to a connected region on
## `image`. This is where the three earlier EasySparkle pieces come
## together and pixels actually get painted:
## - SparkleRegion.find_region supplies *which* pixels the fill may touch.
## - SparklePalette.build supplies the six colors available.
## - SparkleQuota.build supplies exactly how many pixels each color gets.
##
## This module decides *where*, inside the region, each quota's pixels
## land, then writes the resulting colors onto `image`.
##
## Placement is driven by two deterministic, purely coordinate-based scores
## computed per pixel -- no RNG, no clock, nothing that could differ between
## two calls on the same region, regardless of which pixel was clicked to
## find it:
## - A direction score that favors a fixed upper-left light source: pixels
##   closer to the region's upper-left corner score higher, pixels closer
##   to the lower-right score lower.
## - A small-block noise score, sampled from a coarse grid over the region
##   so that neighboring pixels usually share the same noise value. This
##   keeps highlight selection from spreading out as fine, evenly scattered
##   noise -- instead it clumps into small patches -- while remaining fully
##   determined by pixel coordinates alone.
##
## Highlights (soft highlight, bright highlight, peak sparkle) are assigned
## starting from the rarest, most extreme role down, picked from the
## highest direction+noise scoring pixels remaining; peak sparkle
## additionally prefers candidates spaced apart from ones already chosen,
## so sparkles read as distinct points rather than a single blob. Shadows
## (deep shadow, shadow) are assigned from the lowest pure-direction-scoring
## pixels remaining, i.e. the side opposite the light -- shading reads best
## as a coherent falloff, so no noise is mixed in for shadows. Every role's
## quota (SparkleQuota's contract) is met exactly; whatever pixels are left
## over are BASE.

const SparklePalette = preload("res://src/Extensions/EasySparkle/SparklePalette.gd")
const SparkleQuota = preload("res://src/Extensions/EasySparkle/SparkleQuota.gd")

const Role = SparklePalette.Role

# Weight given to the fixed light direction vs. block noise when ranking
# highlight candidates.
const _DIRECTION_WEIGHT := 0.7
const _NOISE_WEIGHT := 1.0 - _DIRECTION_WEIGHT

# Block size (in pixels) that shares a single noise value, so highlight
# selection clumps into small patches instead of scattering per-pixel.
const _NOISE_BLOCK_SIZE := 2

# Minimum Chebyshev distance PEAK_SPARKLE prefers between its own points,
# so sparkles read as separate, rare points of light rather than one
# cluster. Public because it is a meaningful, testable contract.
const PEAK_SPARKLE_MIN_SPACING := 3

# Highlights are assigned rarest/most-extreme first so peak sparkle gets
# first pick of the strongest-scoring pixels. Shadows are assigned
# deepest-first for the same reason on the opposite side.
const _HIGHLIGHT_ORDER: Array[Role] = [Role.PEAK_SPARKLE, Role.BRIGHT_HIGHLIGHT, Role.SOFT_HIGHLIGHT]
const _SHADOW_ORDER: Array[Role] = [Role.DEEP_SHADOW, Role.SHADOW]


## Applies the sparkle fill described by `region` (as returned by
## SparkleRegion.find_region) to `image`, sizing roles with `profile`
## (defaults to SparkleQuota.DEFAULT_PROFILE).
##
## Writes colors directly onto `image`: every region pixel is recolored,
## nothing outside the region is touched, and every written color carries
## the same alpha the region already had (SparklePalette never changes
## alpha), so the silhouette and alpha channel are unchanged. Indexed
## images are remapped afterward the same way EasyGradient's fill does.
##
## Returns a Dictionary keyed by SparklePalette.Role with the number of
## pixels actually painted that role -- always identical to
## SparkleQuota.build(region["points"].size(), profile) -- so callers can
## verify the fill did exactly what the quota promised.
##
## A null image or an empty/missing region is a no-op that returns
## all-zero counts.
static func apply(image: Image, region: Dictionary, profile: Dictionary = SparkleQuota.DEFAULT_PROFILE) -> Dictionary:
	var counts := _zero_counts()
	if image == null or region.is_empty():
		return counts

	var points: Array[Vector2i] = region["points"]
	if points.is_empty():
		return counts

	var source: Color = region["color"]
	var palette := SparklePalette.build(source)
	var quotas := SparkleQuota.build(points.size(), profile)
	var assignment := _assign_roles(points, quotas)

	for point in points:
		var role = assignment[point]
		counts[role] += 1
		var color: Color = palette[role]
		if image.has_method("set_pixelv_custom"):
			image.set_pixelv_custom(point, color)
		else:
			image.set_pixelv(point, color)

	# Indexed images store palette indices; remap the RGB we just wrote.
	if image.get("is_indexed"):
		image.convert_rgb_to_indexed()

	return counts


## Maps every point in `points` to exactly the SparklePalette.Role dictated
## by `quotas`, deterministically from pixel coordinates alone -- the same
## `points` set always produces the same mapping regardless of its order.
static func _assign_roles(points: Array[Vector2i], quotas: Dictionary) -> Dictionary:
	var assignment := {}
	var bounds := _bounds(points)

	var highlight_scores := {}
	var shadow_scores := {}
	for point in points:
		var direction := _direction_score(point, bounds)
		highlight_scores[point] = direction * _DIRECTION_WEIGHT + _noise_score(point) * _NOISE_WEIGHT
		shadow_scores[point] = direction

	var remaining: Array[Vector2i] = points.duplicate()

	for role in _HIGHLIGHT_ORDER:
		var quota: int = quotas.get(role, 0)
		if quota <= 0:
			continue
		remaining.sort_custom(
			func(a, b): return _compare(highlight_scores[a], highlight_scores[b], a, b, true)
		)
		var chosen: Array[Vector2i]
		if role == Role.PEAK_SPARKLE:
			chosen = _take_spaced(remaining, quota, PEAK_SPARKLE_MIN_SPACING)
		else:
			chosen = remaining.slice(0, mini(quota, remaining.size()))
		for point in chosen:
			assignment[point] = role
		remaining = _subtract(remaining, chosen)

	for role in _SHADOW_ORDER:
		var quota: int = quotas.get(role, 0)
		if quota <= 0:
			continue
		remaining.sort_custom(
			func(a, b): return _compare(shadow_scores[a], shadow_scores[b], a, b, false)
		)
		var chosen: Array[Vector2i] = remaining.slice(0, mini(quota, remaining.size()))
		for point in chosen:
			assignment[point] = role
		remaining = _subtract(remaining, chosen)

	for point in remaining:
		assignment[point] = Role.BASE

	return assignment


## Greedily takes up to `quota` points from `sorted_candidates` (already
## ranked best-first), preferring ones at least `min_spacing` (Chebyshev)
## away from every point already chosen. If spacing can't be honored for
## every pick -- not enough room in a small or narrow region -- the
## remaining slots are filled from the best-ranked leftovers regardless of
## spacing, so the quota is always met exactly.
static func _take_spaced(
	sorted_candidates: Array[Vector2i], quota: int, min_spacing: int
) -> Array[Vector2i]:
	var chosen: Array[Vector2i] = []
	for point in sorted_candidates:
		if chosen.size() >= quota:
			break
		var far_enough := true
		for existing in chosen:
			if maxi(absi(existing.x - point.x), absi(existing.y - point.y)) < min_spacing:
				far_enough = false
				break
		if far_enough:
			chosen.append(point)

	if chosen.size() < quota:
		var chosen_set := {}
		for point in chosen:
			chosen_set[point] = true
		for point in sorted_candidates:
			if chosen.size() >= quota:
				break
			if not chosen_set.has(point):
				chosen.append(point)

	return chosen


static func _subtract(source: Array[Vector2i], remove: Array[Vector2i]) -> Array[Vector2i]:
	var remove_set := {}
	for point in remove:
		remove_set[point] = true
	var result: Array[Vector2i] = []
	for point in source:
		if not remove_set.has(point):
			result.append(point)
	return result


## Sorts descending when `descending` is true, ascending otherwise, tying
## deterministically by (y, x) so results never depend on input order.
static func _compare(score_a: float, score_b: float, a: Vector2i, b: Vector2i, descending: bool) -> bool:
	if not is_equal_approx(score_a, score_b):
		return score_a > score_b if descending else score_a < score_b
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## 1.0 at the region's upper-left corner, 0.0 at its lower-right corner,
## blending linearly in between. A single-pixel-wide or -tall region falls
## back to a width/height of 1 so the score stays well-defined.
static func _direction_score(point: Vector2i, bounds: Dictionary) -> float:
	var width: float = maxf(float(bounds["max_x"] - bounds["min_x"]), 1.0)
	var height: float = maxf(float(bounds["max_y"] - bounds["min_y"]), 1.0)
	var x_score: float = (bounds["max_x"] - point.x) / width
	var y_score: float = (bounds["max_y"] - point.y) / height
	return (x_score + y_score) / 2.0


## Deterministic pseudo-noise in [0, 1), constant across each
## _NOISE_BLOCK_SIZE square so nearby pixels usually share a value.
static func _noise_score(point: Vector2i) -> float:
	var block_x := point.x / _NOISE_BLOCK_SIZE
	var block_y := point.y / _NOISE_BLOCK_SIZE
	return float(_hash2(block_x, block_y) % 1000) / 999.0


static func _hash2(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


static func _bounds(points: Array[Vector2i]) -> Dictionary:
	var min_x := points[0].x
	var max_x := points[0].x
	var min_y := points[0].y
	var max_y := points[0].y
	for point in points:
		min_x = mini(min_x, point.x)
		max_x = maxi(max_x, point.x)
		min_y = mini(min_y, point.y)
		max_y = maxi(max_y, point.y)
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}


static func _zero_counts() -> Dictionary:
	var counts := {}
	for role in SparklePalette.ROLE_ORDER:
		counts[role] = 0
	return counts
