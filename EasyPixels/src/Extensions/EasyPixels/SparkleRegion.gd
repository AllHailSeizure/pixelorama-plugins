extends RefCounted

## Finds the connected, exact-color region on `image` that contains `start`.
##
## Connectivity is orthogonal only (no diagonal) — the same rule a standard
## bucket fill uses. Two pixels that only touch corner-to-corner are treated
## as separate regions even when their colors match exactly, so "diagonal
## contact" alone never joins two areas.
##
## A pixel only belongs to the region if its color (including alpha) is
## exactly equal to the color at `start`. There is no tolerance.
##
## Returns an empty dictionary — no region — when:
## - `image` is null
## - `start` is outside the image bounds
## - the pixel at `start` is fully transparent (alpha <= 0)
##
## Otherwise returns {"color": Color, "points": Array[Vector2i]} where
## `points` lists every pixel in the region, including `start`.
##
## This function only reads `image`; it never writes to it.
static func find_region(image: Image, start: Vector2i) -> Dictionary:
	if image == null or not _in_bounds(image, start):
		return {}

	var target := image.get_pixelv(start)
	if target.a <= 0.0:
		return {}

	var width := image.get_width()
	var height := image.get_height()
	var visited := {start: true}
	var points: Array[Vector2i] = []
	var stack: Array[Vector2i] = [start]

	while not stack.is_empty():
		var point: Vector2i = stack.pop_back()
		points.append(point)
		for neighbor in _orthogonal_neighbors(point):
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= width or neighbor.y >= height:
				continue
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if image.get_pixelv(neighbor) == target:
				stack.append(neighbor)

	return {"color": target, "points": points}


static func _orthogonal_neighbors(point: Vector2i) -> Array[Vector2i]:
	return [
		point + Vector2i.UP,
		point + Vector2i.DOWN,
		point + Vector2i.LEFT,
		point + Vector2i.RIGHT,
	]


static func _in_bounds(image: Image, point: Vector2i) -> bool:
	return (
		point.x >= 0
		and point.y >= 0
		and point.x < image.get_width()
		and point.y < image.get_height()
	)
