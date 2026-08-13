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
## Placement is driven by a single deterministic, purely coordinate-based
## score computed per pixel -- given the same region, quotas, and seed, the
## result is always the same, regardless of which pixel was clicked to find
## the region or what order its points were visited in. The score is the sum
## of three terms:
## - A direction score that favors a fixed upper-left light source: pixels
##   closer to the region's upper-left corner score higher, pixels closer
##   to the lower-right score lower. The direction score never depends on
##   the seed, so the v1 lighting direction is fixed regardless of reroll.
## - A small-block noise offset, sampled from a coarse grid over the region
##   so that neighboring pixels usually share the same value. It nudges a
##   whole patch at a time across a role boundary, which makes the contour
##   of a band wander instead of tracing a clean iso-line of the light ramp.
##   The noise is seeded: a given `seed` always produces the same noise
##   field for the same region, but a different seed reshuffles which blocks
##   read high, which is what lets a reroll (same region, same palette, same
##   quotas, new seed) produce a visibly different arrangement without
##   touching anything else.
## - An ordered 4x4 Bayer dither offset. Roles are filled by ranking pixels
##   and taking the top N, and the top N of a smooth ramp is necessarily a
##   contiguous band -- which is what made the fill read as flat diagonal
##   stripes. The dither offsets each pixel's score by an amount fixed by
##   its position within a 4x4 cell, so pixels near a boundary fall on
##   alternating sides of it in a checkerboard, the way a pixel artist would
##   dither the transition by hand. Because the offset is a pure function of
##   the coordinates, the ranking stays deterministic and the quotas stay
##   exact; only *which* pixels sit on each side of a boundary changes. The
##   Bayer origin is shifted by the seed, so a reroll rearranges the
##   interleaving too.
##
## Highlights (soft highlight, bright highlight, peak sparkle) are assigned
## starting from the rarest, most extreme role down, picked from the
## highest scoring pixels remaining; peak sparkle additionally prefers
## candidates spaced apart from ones already chosen, so sparkles read as
## distinct points rather than a single blob. Shadows (deep shadow, shadow)
## are then assigned from the lowest scoring pixels remaining, i.e. the side
## opposite the light. Highlights and shadows rank by the same score, so
## both ends of the ramp are dithered and both are seed-dependent -- a hard
## cut is the one thing shading should not have, and the shadow bands were
## the most obviously banded back when they ranked on direction alone. Every
## role's quota (SparkleQuota's contract) is met exactly; whatever pixels are
## left over are BASE.
##
## Because placement is a pure function of (points, color, quotas, seed),
## calling `apply` again for the same region with a new seed regenerates
## the arrangement from that original source data -- it does not read or
## build on whatever is currently painted on `image`, so a reroll never
## compounds on top of a previous fill or reroll.

const SparklePalette = preload("res://src/Extensions/EasySparkle/SparklePalette.gd")
const SparkleQuota = preload("res://src/Extensions/EasySparkle/SparkleQuota.gd")

const Role = SparklePalette.Role

# Every placement score is expressed in the units of the direction score,
# which runs from 1.0 at the lit corner to 0.0 at the unlit one. Keeping the
# perturbations below in those same units means their magnitudes can be
# compared directly against how wide a role's band is in score terms, which
# is the only number that matters when tuning them.
#
# How wide is a band? Over a square region the direction score is the sum of
# two linear ramps, so its distribution is triangular: the fraction of
# pixels scoring above a threshold t in the upper half is 2 * (1 - t)^2, and
# symmetrically below t in the lower half. Solving that for the default
# 5/13/45/20/12/5 profile puts every non-BASE band at roughly 0.13 to 0.16
# of the score range, and BASE at about 0.27.

# Peak-to-peak span of the ordered dither. Tuned to just under one band
# width (~0.14 above), which is the point of the exercise: a boundary at
# threshold t becomes a transition zone spanning t +/- _DITHER_AMPLITUDE / 2,
# so with an amplitude of one band the zones of two neighboring boundaries
# meet but do not overlap. Exactly the two roles that share a boundary
# interleave there; three or four never smear together. Raise it toward 0.2
# for a wider, softer dithered transition, lower it toward 0.05 for a
# tighter one that only frays the last pixel or two of each band.
const _DITHER_AMPLITUDE := 0.12

# Peak-to-peak span of the block noise, deliberately well under one band: it
# is there to make a band's contour wander, not to reshuffle which band a
# pixel belongs to. (It used to be worth an effective 0.43 of the score
# range on highlights, three whole bands, which is why highlight selection
# read as scatter rather than as shading.)
#
# It survives alongside the dither, rather than being replaced by it,
# because the two do different jobs. The dither is a fixed per-pixel pattern
# that frays an edge but leaves the edge exactly where the light ramp put
# it; the noise moves the edge itself, a patch at a time. It is also the
# only unbounded source of reroll variety -- seeding the dither can only
# shift a 4x4 matrix, which is 16 arrangements -- and, tuned this far below
# _DITHER_AMPLITUDE, it is what keeps PEAK_SPARKLE off a visible grid: the
# dither alone makes the top-ranked pixels land on the Bayer cell's own
# lattice, and spaced sparkles snapped to a 4-pixel lattice look machined.
const _NOISE_AMPLITUDE := 0.08

# Block size (in pixels) that shares a single noise value, so the noise
# clumps into small patches instead of scattering per-pixel.
const _NOISE_BLOCK_SIZE := 2

# Classic 4x4 ordered (Bayer) dither matrix, row-major, holding each cell's
# rank in 0..15. Its defining property is that the ranks are spread as
# evenly as possible over the cell, so thresholding it produces the regular
# checkerboard-like patterns pixel art uses for gradients, rather than the
# clumps a random field would give.
const _BAYER_SIZE := 4
const _BAYER_MATRIX: Array[int] = [
	0, 8, 2, 10,
	12, 4, 14, 6,
	3, 11, 1, 9,
	15, 7, 13, 5,
]

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
## `seed` drives the noise field and the dither origin (see the class doc):
## the same region, profile, and seed always produce the same arrangement,
## while a different seed reshuffles placement at both ends of the ramp --
## this is what a "reroll" is, at this layer. Defaults to 0, so callers that
## don't care about rerolling get a stable arrangement.
##
## Returns a Dictionary keyed by SparklePalette.Role with the number of
## pixels actually painted that role -- always identical to
## SparkleQuota.build(region["points"].size(), profile) -- so callers can
## verify the fill did exactly what the quota promised.
##
## A null image or an empty/missing region is a no-op that returns
## all-zero counts.
static func apply(image: Image, region: Dictionary, profile: Dictionary = SparkleQuota.DEFAULT_PROFILE, seed: int = 0) -> Dictionary:
	var counts := _zero_counts()
	if image == null or region.is_empty():
		return counts

	var points: Array[Vector2i] = region["points"]
	if points.is_empty():
		return counts

	var source: Color = region["color"]
	var palette := SparklePalette.build(source)
	var quotas := SparkleQuota.build(points.size(), profile)
	var assignment := _assign_roles(points, quotas, seed)

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
## by `quotas`, deterministically from pixel coordinates and `seed` alone --
## the same `points` set and `seed` always produce the same mapping
## regardless of the points' order; a different `seed` reshuffles placement
## at both ends of the ramp (BASE still follows from whatever is left over).
static func _assign_roles(points: Array[Vector2i], quotas: Dictionary, seed: int = 0) -> Dictionary:
	var assignment := {}
	var bounds := _bounds(points)

	var scores := {}
	for point in points:
		scores[point] = _placement_score(point, bounds, seed)

	var remaining: Array[Vector2i] = points.duplicate()

	for role in _HIGHLIGHT_ORDER:
		var quota: int = quotas.get(role, 0)
		if quota <= 0:
			continue
		remaining.sort_custom(
			func(a, b): return _compare(scores[a], scores[b], a, b, true)
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
			func(a, b): return _compare(scores[a], scores[b], a, b, false)
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


## Ranks a pixel along the lit -> unlit ramp: the light direction, wandered
## by the block noise and then dithered. Highlights take the top of this
## ranking and shadows the bottom, so a single score describes the whole
## ramp. Purely a function of the pixel's coordinates, the region's bounds,
## and `seed`, which is what keeps the fill deterministic and the quotas
## exact no matter how the perturbations are tuned.
static func _placement_score(point: Vector2i, bounds: Dictionary, seed: int) -> float:
	return (
		_direction_score(point, bounds)
		+ (_noise_score(point, seed) - 0.5) * _NOISE_AMPLITUDE
		+ _dither_offset(point, seed) * _DITHER_AMPLITUDE
	)


## The pixel's 4x4 Bayer rank, remapped to roughly [-0.5, +0.5] so it can be
## scaled by a peak-to-peak amplitude and added to a score without shifting
## the score's average. `seed` shifts the matrix origin -- independently on
## each axis, so that consecutive seeds don't just slide the same pattern
## along the diagonal -- which rearranges the interleaving on a reroll while
## keeping the ordered-dither structure intact.
static func _dither_offset(point: Vector2i, seed: int = 0) -> float:
	var x := posmod(point.x + seed, _BAYER_SIZE)
	var y := posmod(point.y + seed / _BAYER_SIZE, _BAYER_SIZE)
	var rank: int = _BAYER_MATRIX[y * _BAYER_SIZE + x]
	var cells := _BAYER_SIZE * _BAYER_SIZE
	return (float(rank) + 0.5) / float(cells) - 0.5


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
## _NOISE_BLOCK_SIZE square so nearby pixels usually share a value. Mixing
## `seed` into the hash reshuffles which blocks read high without changing
## the block structure itself.
static func _noise_score(point: Vector2i, seed: int = 0) -> float:
	var block_x := point.x / _NOISE_BLOCK_SIZE
	var block_y := point.y / _NOISE_BLOCK_SIZE
	return float(_hash2(block_x, block_y, seed) % 1000) / 999.0


static func _hash2(x: int, y: int, seed: int = 0) -> int:
	var h := x * 374761393 + y * 668265263 + seed * 2246822519
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
