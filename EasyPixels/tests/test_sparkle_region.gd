extends SceneTree

const SparkleRegion = preload("res://src/Extensions/EasySparkle/SparkleRegion.gd")

const BG := Color(1, 1, 1, 1)
const RED := Color(1, 0, 0, 1)
const GREEN := Color(0, 1, 0, 1)
const BLUE := Color(0, 0, 1, 1)
const TRANSPARENT_RED := Color(1, 0, 0, 0)


func _init() -> void:
	var image := _build_test_image()

	_test_connected_region_and_edges(image)
	_test_disconnected_same_color_excluded(image)
	_test_diagonal_contact_does_not_connect(image)
	_test_single_pixel_and_enclosed_region(image)
	_test_transparent_click_returns_no_region(image)
	_test_out_of_bounds_click_returns_no_region(image)
	_test_null_image_returns_no_region()
	_test_region_discovery_does_not_modify_image(image)

	print("EasySparkle region detection checks passed")
	quit(0)


## 7x7 canvas. Coordinates below are (x, y).
##   Region A (red, touches top+left edges, connected): (0,0) (1,0) (0,1)
##   Disconnected red, far corner:                      (6,6)
##   Red pixel only diagonally touching region A:        (2,1)
##   Enclosed 2-pixel green region (no edge contact):    (4,3) (4,4)
##   Enclosed single-pixel blue region:                  (2,4)
##   Fully transparent pixel (same RGB as red):           (5,5)
## Everywhere else is opaque white background.
func _build_test_image() -> Image:
	var image := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
	image.fill(BG)
	image.set_pixelv(Vector2i(0, 0), RED)
	image.set_pixelv(Vector2i(1, 0), RED)
	image.set_pixelv(Vector2i(0, 1), RED)
	image.set_pixelv(Vector2i(6, 6), RED)
	image.set_pixelv(Vector2i(2, 1), RED)
	image.set_pixelv(Vector2i(4, 3), GREEN)
	image.set_pixelv(Vector2i(4, 4), GREEN)
	image.set_pixelv(Vector2i(2, 4), BLUE)
	image.set_pixelv(Vector2i(5, 5), TRANSPARENT_RED)
	return image


func _test_connected_region_and_edges(image: Image) -> void:
	var result := SparkleRegion.find_region(image, Vector2i(0, 0))
	_assert(not result.is_empty(), "edge-touching click should find a region")
	_assert(result["color"].is_equal_approx(RED), "region color should match the clicked pixel")
	_assert_points_equal(
		result["points"],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		"region A should contain exactly its three connected pixels"
	)

	# Clicking any member pixel of the same region should yield the same set.
	var from_member := SparkleRegion.find_region(image, Vector2i(1, 0))
	_assert_points_equal(
		from_member["points"],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		"region lookup should be consistent regardless of which member pixel was clicked"
	)


func _test_disconnected_same_color_excluded(image: Image) -> void:
	var result := SparkleRegion.find_region(image, Vector2i(0, 0))
	for point: Vector2i in result["points"]:
		_assert(point != Vector2i(6, 6), "disconnected same-color pixel must be excluded from region A")

	var far_result := SparkleRegion.find_region(image, Vector2i(6, 6))
	_assert_points_equal(
		far_result["points"],
		[Vector2i(6, 6)],
		"the disconnected red pixel should form its own single-pixel region"
	)


func _test_diagonal_contact_does_not_connect(image: Image) -> void:
	var result := SparkleRegion.find_region(image, Vector2i(2, 1))
	_assert_points_equal(
		result["points"],
		[Vector2i(2, 1)],
		"a pixel that only touches another same-color pixel diagonally must not be merged into it"
	)
	var region_a := SparkleRegion.find_region(image, Vector2i(0, 0))
	for point: Vector2i in region_a["points"]:
		_assert(point != Vector2i(2, 1), "region A must not absorb a diagonally-touching pixel")


func _test_single_pixel_and_enclosed_region(image: Image) -> void:
	var blue := SparkleRegion.find_region(image, Vector2i(2, 4))
	_assert_points_equal(
		blue["points"], [Vector2i(2, 4)], "an enclosed single pixel should form a region of exactly one pixel"
	)

	var green := SparkleRegion.find_region(image, Vector2i(4, 3))
	_assert_points_equal(
		green["points"],
		[Vector2i(4, 3), Vector2i(4, 4)],
		"an enclosed multi-pixel region should be found in full without leaking into its surroundings"
	)


func _test_transparent_click_returns_no_region(image: Image) -> void:
	var result := SparkleRegion.find_region(image, Vector2i(5, 5))
	_assert(result.is_empty(), "clicking a fully transparent pixel should not produce a region")


func _test_out_of_bounds_click_returns_no_region(image: Image) -> void:
	_assert(
		SparkleRegion.find_region(image, Vector2i(-1, 0)).is_empty(),
		"a negative out-of-bounds click should not produce a region"
	)
	_assert(
		SparkleRegion.find_region(image, Vector2i(100, 100)).is_empty(),
		"a positive out-of-bounds click should not produce a region"
	)


func _test_null_image_returns_no_region() -> void:
	_assert(SparkleRegion.find_region(null, Vector2i.ZERO).is_empty(), "a null image should not produce a region")


func _test_region_discovery_does_not_modify_image(image: Image) -> void:
	var before := image.duplicate()
	SparkleRegion.find_region(image, Vector2i(0, 0))
	SparkleRegion.find_region(image, Vector2i(4, 3))
	SparkleRegion.find_region(image, Vector2i(5, 5))
	_assert(_images_equal(before, image), "region discovery must never write to the image")


func _images_equal(a: Image, b: Image) -> bool:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return false
	for y in a.get_height():
		for x in a.get_width():
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true


func _assert_points_equal(actual: Array, expected: Array, message: String) -> void:
	var actual_set := {}
	for point in actual:
		actual_set[point] = true
	var expected_set := {}
	for point in expected:
		expected_set[point] = true
	_assert(actual.size() == expected.size(), "%s (size mismatch: got %d, expected %d)" % [message, actual.size(), expected.size()])
	for point in expected_set.keys():
		_assert(actual_set.has(point), "%s (missing point %s)" % [message, point])
	for point in actual_set.keys():
		_assert(expected_set.has(point), "%s (unexpected point %s)" % [message, point])


func _assert(condition: bool, message: String) -> void:
	assert(condition, message)
