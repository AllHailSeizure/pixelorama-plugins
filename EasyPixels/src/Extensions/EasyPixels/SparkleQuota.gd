extends RefCounted

## Converts the sparkle color distribution into exact integer pixel quotas
## per SparklePalette.Role, so the roles handed to a fill always sum to
## precisely the targeted region's pixel count -- never more, never fewer.
##
## This module only produces counts. It does not choose which pixels get
## which role and it never touches an image; SparkleRegion.gd supplies the
## region size this consumes, and a later step is responsible for mapping
## the counts onto actual pixel coordinates and applying SparklePalette
## colors to the canvas.

const SparklePalette = preload("res://src/Extensions/EasySparkle/SparklePalette.gd")

## Default sparkle distribution, expressed as percentages of the region
## that sum to exactly 100. This is the only profile exposed in v1 --
## editable distribution percentages are out of scope for this step.
const DEFAULT_PROFILE := {
	SparklePalette.Role.DEEP_SHADOW: 5.0,
	SparklePalette.Role.SHADOW: 13.0,
	SparklePalette.Role.BASE: 45.0,
	SparklePalette.Role.SOFT_HIGHLIGHT: 20.0,
	SparklePalette.Role.BRIGHT_HIGHLIGHT: 12.0,
	SparklePalette.Role.PEAK_SPARKLE: 5.0,
}


## Converts `region_size` pixels into per-role integer counts using `profile`
## (defaults to DEFAULT_PROFILE) via the largest-remainder method:
##
## 1. Every role first gets floor(region_size * percent / 100) -- its
##    guaranteed share, which rounds toward zero rather than away from it,
##    so small regions naturally let low-share roles round to zero instead
##    of forcing every color into the object.
## 2. Whatever pixels are left over after that (region_size minus the sum
##    of the floors) are handed out one at a time to the roles with the
##    largest fractional remainder -- the roles that lost the most to
##    flooring -- which keeps every role's final count within one pixel of
##    its exact proportional share.
## 3. Ties in fractional remainder are broken first by higher percentage
##    share (so BASE, the largest share, wins ties over smaller roles and
##    stays dominant) and finally by SparklePalette.ROLE_ORDER, so the
##    result is fully deterministic for a given region size and profile.
##
## Returns a Dictionary keyed by SparklePalette.Role with non-negative int
## values that always sum exactly to `region_size`. `region_size <= 0`
## returns every role at 0.
static func build(region_size: int, profile: Dictionary = DEFAULT_PROFILE) -> Dictionary:
	var counts := {}
	for role in SparklePalette.ROLE_ORDER:
		counts[role] = 0

	if region_size <= 0:
		return counts

	var remainders := {}
	var allocated := 0
	for role in SparklePalette.ROLE_ORDER:
		var percent: float = profile.get(role, 0.0)
		var exact := region_size * percent / 100.0
		var floor_count := int(floor(exact))
		counts[role] = floor_count
		remainders[role] = exact - float(floor_count)
		allocated += floor_count

	var remaining := region_size - allocated
	if remaining <= 0:
		return counts

	var order := _remainder_order(remainders, profile)
	var i := 0
	while remaining > 0 and i < order.size():
		var role = order[i]
		counts[role] += 1
		remaining -= 1
		i += 1

	# Defensive fallback: only reachable if `profile` doesn't sum to 100, in
	# which case flooring alone can leave more than one leftover pixel per
	# role. Keep cycling through the priority order until every pixel is
	# accounted for, so the sum invariant holds regardless of profile input.
	i = 0
	while remaining > 0:
		var role = order[i % order.size()]
		counts[role] += 1
		remaining -= 1
		i += 1

	return counts


## Sorts roles by descending fractional remainder (largest remainder gets
## the next leftover pixel first), breaking ties by descending percentage
## share and finally by SparklePalette.ROLE_ORDER position, for full
## determinism.
static func _remainder_order(remainders: Dictionary, profile: Dictionary) -> Array:
	var order := SparklePalette.ROLE_ORDER.duplicate()
	order.sort_custom(
		func(a, b):
			var ra: float = remainders[a]
			var rb: float = remainders[b]
			if not is_equal_approx(ra, rb):
				return ra > rb
			var pa: float = profile.get(a, 0.0)
			var pb: float = profile.get(b, 0.0)
			if not is_equal_approx(pa, pb):
				return pa > pb
			return SparklePalette.ROLE_ORDER.find(a) < SparklePalette.ROLE_ORDER.find(b)
	)
	return order
