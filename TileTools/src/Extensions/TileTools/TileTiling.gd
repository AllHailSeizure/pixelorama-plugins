extends Node

var _active := false
var _bounds: Rect2i


func activate(bounds: Rect2i) -> void:
	_active = true
	_bounds = bounds
	set_process(true)


func deactivate() -> void:
	_active = false
	set_process(false)


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if not _active:
		return
	_wrap_overflow_pixels()


func _wrap_overflow_pixels() -> void:
	var project = ExtensionsApi.project.current_project
	if project == null:
		return
	var cel = project.frames[project.current_frame].cels[project.current_layer]
	if cel == null:
		return
	var image: Image = cel.get_image()
	if image == null:
		return

	var changed := false
	var bx: int = _bounds.position.x
	var by: int = _bounds.position.y
	var bw: int = _bounds.size.x
	var bh: int = _bounds.size.y

	if bw <= 0 or bh <= 0:
		return

	# Right overflow -> wrap to left
	for x in range(bx + bw, mini(bx + bw + bw, image.get_width())):
		for y in range(by, mini(by + bh, image.get_height())):
			var color := image.get_pixel(x, y)
			if color.a > 0:
				var wrap_x := bx + ((x - bx) % bw)
				var existing := image.get_pixel(wrap_x, y)
				image.set_pixel(wrap_x, y, color if color.a >= existing.a else existing)
				image.set_pixel(x, y, Color.TRANSPARENT)
				changed = true

	# Left overflow -> wrap to right
	for x in range(maxi(bx - bw, 0), maxi(bx, 0)):
		for y in range(by, mini(by + bh, image.get_height())):
			var color := image.get_pixel(x, y)
			if color.a > 0:
				var wrap_x := bx + bw - ((bx - x - 1) % bw) - 1
				var existing := image.get_pixel(wrap_x, y)
				image.set_pixel(wrap_x, y, color if color.a >= existing.a else existing)
				image.set_pixel(x, y, Color.TRANSPARENT)
				changed = true

	# Bottom overflow -> wrap to top
	for y in range(by + bh, mini(by + bh + bh, image.get_height())):
		for x in range(bx, mini(bx + bw, image.get_width())):
			var color := image.get_pixel(x, y)
			if color.a > 0:
				var wrap_y := by + ((y - by) % bh)
				var existing := image.get_pixel(x, wrap_y)
				image.set_pixel(x, wrap_y, color if color.a >= existing.a else existing)
				image.set_pixel(x, y, Color.TRANSPARENT)
				changed = true

	# Top overflow -> wrap to bottom
	for y in range(maxi(by - bh, 0), maxi(by, 0)):
		for x in range(bx, mini(bx + bw, image.get_width())):
			var color := image.get_pixel(x, y)
			if color.a > 0:
				var wrap_y := by + bh - ((by - y - 1) % bh) - 1
				var existing := image.get_pixel(x, wrap_y)
				image.set_pixel(x, wrap_y, color if color.a >= existing.a else existing)
				image.set_pixel(x, y, Color.TRANSPARENT)
				changed = true

	if changed:
		cel.update_texture()
