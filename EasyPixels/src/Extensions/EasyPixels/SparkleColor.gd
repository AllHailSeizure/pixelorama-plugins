extends RefCounted


## Moves OKHSL lightness toward white or black while preserving hue, saturation,
## and alpha. +100 reaches white; -100 reaches black.
static func transform(source: Color, amount_percent: float) -> Color:
	var amount := clampf(amount_percent / 100.0, -1.0, 1.0)
	var lightness := source.ok_hsl_l
	if amount >= 0.0:
		lightness = lerpf(lightness, 1.0, amount)
	else:
		lightness = lerpf(lightness, 0.0, -amount)
	return Color.from_ok_hsl(source.ok_hsl_h, source.ok_hsl_s, lightness, source.a)
