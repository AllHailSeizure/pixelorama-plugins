extends RefCounted


## Moves OKHSL lightness toward white or black and rotates hue by a relative
## amount, while preserving saturation and alpha. +100 reaches white; -100
## reaches black. `hue_rotation` is measured in OKHSL hue units, where 1.0
## is one full turn; it wraps into [0, 1). The default keeps existing callers'
## hue-preserving behavior unchanged.
static func transform(source: Color, amount_percent: float, hue_rotation: float = 0.0) -> Color:
	var amount := clampf(amount_percent / 100.0, -1.0, 1.0)
	var lightness := source.ok_hsl_l
	if amount >= 0.0:
		lightness = lerpf(lightness, 1.0, amount)
	else:
		lightness = lerpf(lightness, 0.0, -amount)
	var hue := fposmod(source.ok_hsl_h + hue_rotation, 1.0)
	return Color.from_ok_hsl(hue, source.ok_hsl_s, lightness, source.a)
