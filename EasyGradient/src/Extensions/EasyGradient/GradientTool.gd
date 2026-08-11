extends Node

# Pixelorama tool interface (see src/Tools/BaseTool.gd)
var is_moving := false
var is_syncing := false
var kname: String
var tool_slot = null
var cursor_text := ""

var _point_a := Vector2i.ZERO
var _point_b := Vector2i.ZERO
var _has_a := false
var _has_b := false
var _color_a := Color.TRANSPARENT
var _color_b := Color.TRANSPARENT
var _hover := Vector2i.ZERO
var _canvas: Node2D

var _swatch_a: ColorRect
var _swatch_b: ColorRect
var _status: Label
var _generate_button: Button


func _ready() -> void:
	kname = name.replace(" ", "_").to_lower()
	if tool_slot != null:
		if tool_slot.name == "Left tool":
			$ColorRect.color = ExtensionsApi.general.get_global().left_tool_color
		else:
			$ColorRect.color = ExtensionsApi.general.get_global().right_tool_color

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	var swatch_row := HBoxContainer.new()
	swatch_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(swatch_row)
	_swatch_a = _make_swatch(swatch_row)
	_swatch_b = _make_swatch(swatch_row)

	_generate_button = Button.new()
	_generate_button.text = "Generate Gradient (Enter)"
	_generate_button.pressed.connect(_on_generate_pressed)
	add_child(_generate_button)

	var clear_button := Button.new()
	clear_button.text = "Clear Points"
	clear_button.pressed.connect(_on_clear_pressed)
	add_child(clear_button)

	_canvas = ExtensionsApi.general.get_canvas()
	_update_ui()


## Enter generates, so the gradient can be placed without leaving the canvas.
## Only reached when nothing else consumed the key (e.g. a focused text field),
## and only while this tool is the selected one — the node exists no longer.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	if not (_has_a and _has_b):
		return
	_on_generate_pressed()
	# Stops the other tool slot's instance from generating a second time.
	get_viewport().set_input_as_handled()


func _make_swatch(parent: Control) -> ColorRect:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(0, 16)
	swatch.color = Color.TRANSPARENT
	panel.add_child(swatch)
	return swatch


# Points are per-session; there is nothing worth persisting between runs.
func save_config() -> void:
	pass


func load_config() -> void:
	pass


func get_config() -> Dictionary:
	return {}


func set_config(_config: Dictionary) -> void:
	pass


func update_config() -> void:
	pass


func draw_start(pos: Vector2i) -> void:
	if not _has_a or _has_b:
		# First click, or a fresh pair after the previous one was completed.
		_point_a = pos
		_has_a = true
		_has_b = false
	else:
		_point_b = pos
		_has_b = true
	_sample_colors()
	_update_ui()


func draw_move(_pos: Vector2i) -> void:
	pass


func draw_end(_pos: Vector2i) -> void:
	pass


func cancel_tool() -> void:
	_on_clear_pressed()


func cursor_move(pos: Vector2i) -> void:
	_hover = pos


func draw_indicator(left: bool) -> void:
	if _canvas == null:
		return
	var global = ExtensionsApi.general.get_global()
	var color: Color = global.left_tool_color if left else global.right_tool_color

	# Preview the line that would be generated: A -> B once both are set,
	# otherwise A -> cursor, so the second point can be aimed.
	if _has_a:
		var end_point := _point_b if _has_b else _hover
		var preview := color
		preview.a = 0.35
		for point in _line_points(_point_a, end_point):
			_canvas.indicators.draw_rect(Rect2(Vector2(point), Vector2.ONE), preview, true)

	var marker := color
	marker.a = 0.9
	if _has_a:
		_canvas.indicators.draw_rect(Rect2(Vector2(_point_a), Vector2.ONE), marker, false, 0.5)
	if _has_b:
		_canvas.indicators.draw_rect(Rect2(Vector2(_point_b), Vector2.ONE), marker, false, 0.5)


func draw_preview() -> void:
	pass


func _on_clear_pressed() -> void:
	_has_a = false
	_has_b = false
	_color_a = Color.TRANSPARENT
	_color_b = Color.TRANSPARENT
	_update_ui()


func _on_generate_pressed() -> void:
	if not (_has_a and _has_b):
		return
	var project = ExtensionsApi.project.current_project
	if project == null:
		return
	var cel = ExtensionsApi.project.get_current_cel()
	if not cel is PixelCel:
		return
	var image: Image = cel.get_image()
	if image == null:
		return

	var points := _line_points(_point_a, _point_b)
	if points.size() < 2:
		return

	# Re-sample at generate time so edits made after picking are picked up.
	var start_color := _sample(image, _point_a)
	var end_color := _sample(image, _point_b)

	var cels: Array[BaseCel] = [cel]
	var undo_data := {}
	project.serialize_cel_undo_data(cels, undo_data)

	var last := points.size() - 1
	for i in points.size():
		var point: Vector2i = points[i]
		if not _in_bounds(image, point):
			continue
		var color := start_color.lerp(end_color, float(i) / float(last))
		if image.has_method("set_pixelv_custom"):
			image.set_pixelv_custom(point, color)
		else:
			image.set_pixelv(point, color)
	# Indexed images store palette indices; remap the RGB we just wrote.
	if image.get("is_indexed"):
		image.convert_rgb_to_indexed()

	_commit_undo(project, cels, undo_data)
	_sample_colors()
	_update_ui()


func _commit_undo(project, cels: Array[BaseCel], undo_data: Dictionary) -> void:
	var global = ExtensionsApi.general.get_global()
	global.canvas.update_selected_cels_textures(project)
	var redo_data := {}
	project.serialize_cel_undo_data(cels, redo_data)
	project.undo_redo.create_action("Gradient Line")
	project.deserialize_cel_undo_data(redo_data, undo_data)
	project.undo_redo.add_do_method(global.undo_or_redo.bind(false, project.current_frame, project.current_layer))
	project.undo_redo.add_undo_method(global.undo_or_redo.bind(true, project.current_frame, project.current_layer))
	project.undo_redo.commit_action()


func _sample_colors() -> void:
	var image := _current_image()
	if image == null:
		return
	if _has_a:
		_color_a = _sample(image, _point_a)
	if _has_b:
		_color_b = _sample(image, _point_b)


func _current_image() -> Image:
	var cel = ExtensionsApi.project.get_current_cel()
	if not cel is PixelCel:
		return null
	return cel.get_image()


func _sample(image: Image, point: Vector2i) -> Color:
	if not _in_bounds(image, point):
		return Color.TRANSPARENT
	return image.get_pixelv(point)


func _in_bounds(image: Image, point: Vector2i) -> bool:
	return (
		point.x >= 0
		and point.y >= 0
		and point.x < image.get_width()
		and point.y < image.get_height()
	)


## Bresenham's line algorithm — the same pixel path the Line tool walks.
func _line_points(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx + dy
	var x := from.x
	var y := from.y
	while true:
		points.append(Vector2i(x, y))
		if x == to.x and y == to.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return points


func _update_ui() -> void:
	if _status == null:
		return
	if not _has_a:
		_status.text = "Click a pixel to set the start point."
	elif not _has_b:
		_status.text = "Start %s. Click a second pixel." % _format_point(_point_a)
	else:
		var length := _line_points(_point_a, _point_b).size()
		_status.text = "%s -> %s (%d px)" % [_format_point(_point_a), _format_point(_point_b), length]
	_swatch_a.color = _color_a
	_swatch_b.color = _color_b
	if _generate_button != null:
		_generate_button.disabled = not (_has_a and _has_b)


func _format_point(point: Vector2i) -> String:
	return "(%d, %d)" % [point.x, point.y]
