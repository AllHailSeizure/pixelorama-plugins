extends SceneTree

const SparkleColorTransform = preload(
	"res://src/Extensions/EasySparkle/SparkleColor.gd"
)


func _init() -> void:
	var source := Color.from_ok_hsl(0.62, 0.70, 0.40, 0.50)
	var glint := SparkleColorTransform.transform(source, 30.0)
	var shadow := SparkleColorTransform.transform(source, -15.0)

	_assert_close(glint.ok_hsl_l, 0.58, "+30 should move 30% toward white")
	_assert_close(shadow.ok_hsl_l, 0.34, "-15 should move 15% toward black")
	_assert_close(glint.ok_hsl_h, source.ok_hsl_h, "glint hue should be preserved")
	_assert_close(shadow.ok_hsl_s, source.ok_hsl_s, "shadow saturation should be preserved")
	_assert_close(glint.a, source.a, "alpha should be preserved")
	_assert_close(SparkleColorTransform.transform(source, 100).ok_hsl_l, 1.0, "+100 should be white")
	_assert_close(SparkleColorTransform.transform(source, -100).ok_hsl_l, 0.0, "-100 should be black")
	assert(SparkleColorTransform.transform(source, 0).is_equal_approx(source), "0 should not change color")

	print("EasySparkle color formula checks passed")
	quit(0)


func _assert_close(actual: float, expected: float, message: String) -> void:
	assert(is_equal_approx(actual, expected), "%s: got %f, expected %f" % [message, actual, expected])
