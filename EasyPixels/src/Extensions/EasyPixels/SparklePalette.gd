extends RefCounted

## Derives the six-role perceptual sparkle palette used by a sparkle fill
## from a single sampled source color.
##
## Every non-base role is produced by running the source color through
## SparkleColorTransform.transform (see SparkleColor.gd) at a fixed signed
## percentage. That formula lerps OKHSL lightness toward white (positive) or
## black (negative) while preserving hue, saturation, and alpha, and it
## saturates at the endpoints instead of overshooting -- so for any input,
## including near-black, near-white, low-saturation, and partially
## transparent colors, increasing the shift amount never decreases
## lightness and decreasing it never increases lightness. Fixing the six
## roles at strictly increasing amounts therefore guarantees the roles keep
## a stable, non-decreasing perceptual lightness order, even in degenerate
## cases where several roles saturate to the same value.

const SparkleColorTransform = preload("res://src/Extensions/EasySparkle/SparkleColor.gd")

## Role identifiers, already declared in ascending perceptual-lightness order.
enum Role {
	DEEP_SHADOW,
	SHADOW,
	BASE,
	SOFT_HIGHLIGHT,
	BRIGHT_HIGHLIGHT,
	PEAK_SPARKLE,
}

## Roles in stable ascending lightness order. Iterate this (rather than the
## Dictionary returned by build()) when order matters, e.g. for UI display.
const ROLE_ORDER: Array[Role] = [
	Role.DEEP_SHADOW,
	Role.SHADOW,
	Role.BASE,
	Role.SOFT_HIGHLIGHT,
	Role.BRIGHT_HIGHLIGHT,
	Role.PEAK_SPARKLE,
]

## Signed lightness-shift percent applied per role, fed straight into
## SparkleColorTransform.transform. 0 keeps the base role identical to the
## source color; negative/positive move toward black/white respectively.
## Values are strictly increasing across ROLE_ORDER, which is what
## guarantees the resulting roles never invert their lightness order.
const ROLE_AMOUNTS := {
	Role.DEEP_SHADOW: -60.0,
	Role.SHADOW: -30.0,
	Role.BASE: 0.0,
	Role.SOFT_HIGHLIGHT: 25.0,
	Role.BRIGHT_HIGHLIGHT: 55.0,
	Role.PEAK_SPARKLE: 85.0,
}

const ROLE_NAMES := {
	Role.DEEP_SHADOW: "Deep shadow",
	Role.SHADOW: "Shadow",
	Role.BASE: "Base",
	Role.SOFT_HIGHLIGHT: "Soft highlight",
	Role.BRIGHT_HIGHLIGHT: "Bright highlight",
	Role.PEAK_SPARKLE: "Peak sparkle",
}


## Builds the six-role palette for `source`. Returns a Dictionary keyed by
## Role with Color values.
##
## The BASE role is always exactly `source` -- component for component,
## including alpha -- rather than a round trip through the OKHSL transform,
## so it is guaranteed identical to the sampled color rather than merely
## close to it.
##
## Every other role preserves `source`'s alpha exactly (the underlying
## transform never touches alpha) and is clamped into the valid 0..1 color
## range as a defensive measure, since callers should never receive an
## out-of-gamut color regardless of how extreme `source` is.
static func build(source: Color) -> Dictionary:
	var palette := {}
	for role in ROLE_ORDER:
		if role == Role.BASE:
			palette[role] = source
		else:
			var amount: float = ROLE_AMOUNTS[role]
			palette[role] = SparkleColorTransform.transform(source, amount).clamp()
	return palette


## Human-readable label for a role, for tool-option previews.
static func role_name(role: Role) -> String:
	return ROLE_NAMES.get(role, "")
