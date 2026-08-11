extends Node

const SparkleColorTransform = preload(
	"res://src/Extensions/EasySparkle/SparkleColor.gd"
)

# Pixelorama tool interface (see src/Tools/BaseTool.gd)
var is_moving := false
var is_syncing := false
var kname: String
var tool_slot = null
var cursor_text := ""

var adjustment := 30.0

var _adjustment_spin: SpinBox
var _description: Label
var _source_swatch: ColorRect
var _result_swatch: ColorRect
var _canvas: Node2D
var _hover := Vector2i.ZERO

var _stroke_active := false
var _stroke_changed := false
var _last_point := Vector2i.ZERO
var _visited := {}
var _stroke_project = null
var _stroke_cels: Array[BaseCel] = []
var _undo_data := {}


func _ready() -> void:
	kname = name.replace(" ", "_").to_lower()
	if tool_slot != null:
		if tool_slot.name == "Left tool":
			$ColorRect.color = ExtensionsApi.general.get_global().left_tool_color
		else:
			$ColorRect.color = ExtensionsApi.general.get_global().right_tool_color

	var amount_label := Label.new()
	amount_label.text = "Lightness shift:"
	add_child(amount_label)

	_adjustment_spin = SpinBox.new()
	_adjustment_spin.min_value = -100
	_adjustment_spin.max_value = 100
	_adjustment_spin.step = 1
	_adjustment_spin.value = adjustment
	_adjustment_spin.suffix = "%"
	_adjustment_spin.allow_greater = false
	_adjustment_spin.allow_lesser = false
	_adjustment_spin.value_changed.connect(_on_adjustment_changed)
	add_child(_adjustment_spin)

	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_description)

	var preview_label := Label.new()
	preview_label.text = "Hovered color  ->  Result"
	add_child(preview_label)

	var swatch_row := HBoxContainer.new()
	swatch_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(swatch_row)
	_source_swatch = _make_swatch(swatch_row)
	_result_swatch = _make_swatch(swatch_row)

	var hint := Label.new()
	hint.text = "Click or drag over pixels to apply. Each pixel changes once per stroke."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_canvas = ExtensionsApi.general.get_canvas()
	load_config()
	_update_description()
	_update_preview()


func _make_swatch(parent: Control) -> ColorRect:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(0, 18)
	swatch.color = Color.TRANSPARENT
	panel.add_child(swatch)
	return swatch


func save_config() -> void:
	if tool_slot == null:
		return
	ExtensionsApi.general.get_config_file().set_value(tool_slot.kname, kname, get_config())


func load_config() -> void:
	if tool_slot == null:
		return
	var value = ExtensionsApi.general.get_config_file().get_value(tool_slot.kname, kname, {})
	set_config(value)
	update_config()


func get_config() -> Dictionary:
	return {"adjustment": adjustment}


func set_config(config: Dictionary) -> void:
	adjustment = clampf(float(config.get("adjustment", adjustment)), -100.0, 100.0)


func update_config() -> void:
	if _adjustment_spin != null:
		_adjustment_spin.value = adjustment
	_update_description()
	_update_preview()


func draw_start(pos: Vector2i) -> void:
	var project = ExtensionsApi.project.current_project
	if project == null:
		return
	var cel = ExtensionsApi.project.get_current_cel()
	if not cel is PixelCel:
		return
	var image: Image = cel.get_image()
	if image == null or not _in_bounds(image, pos):
		return

	_stroke_project = project
	_stroke_cels = [cel]
	_undo_data = {}
	project.serialize_cel_undo_data(_stroke_cels, _undo_data)
	_stroke_active = true
	_stroke_changed = false
	_visited.clear()
	_last_point = pos
	_transform_at(image, pos)


func draw_move(pos: Vector2i) -> void:
	if not _stroke_active:
		return
	var image := _stroke_image()
	if image == null:
		return
	for point in _line_points(_last_point, pos):
		_transform_at(image, point)
	_last_point = pos


func draw_end(pos: Vector2i) -> void:
	if not _stroke_active:
		return
	var image := _stroke_image()
	if image != null:
		for point in _line_points(_last_point, pos):
			_transform_at(image, point)
	_finish_stroke(image)


func cancel_tool() -> void:
	if _stroke_active:
		_finish_stroke(_stroke_image())


func cursor_move(pos: Vector2i) -> void:
	_hover = pos
	_update_preview()


func draw_indicator(_left: bool) -> void:
	if _canvas == null:
		return
	var image := _current_image()
	if image == null or not _in_bounds(image, _hover):
		return
	var result := transform_color(image.get_pixelv(_hover), adjustment)
	var fill := result
	fill.a = maxf(fill.a, 0.65)
	_canvas.indicators.draw_rect(Rect2(Vector2(_hover), Vector2.ONE), fill, true)
	var outline := Color.WHITE if result.get_luminance() < 0.5 else Color.BLACK
	outline.a = 0.9
	_canvas.indicators.draw_rect(Rect2(Vector2(_hover), Vector2.ONE), outline, false, 0.5)


func draw_preview() -> void:
	pass


func transform_color(source: Color, amount_percent: float) -> Color:
	return SparkleColorTransform.transform(source, amount_percent)


func _on_adjustment_changed(value: float) -> void:
	adjustment = value
	_update_description()
	_update_preview()
	save_config()


func _update_description() -> void:
	if _description == null:
		return
	if adjustment > 0.0:
		_description.text = "Glint: move %.0f%% of the remaining distance toward white." % adjustment
	elif adjustment < 0.0:
		_description.text = "Shadow: move %.0f%% of the distance toward black." % -adjustment
	else:
		_description.text = "No lightness change."


func _update_preview() -> void:
	if _source_swatch == null or _result_swatch == null:
		return
	var image := _current_image()
	if image == null or not _in_bounds(image, _hover):
		_source_swatch.color = Color.TRANSPARENT
		_result_swatch.color = Color.TRANSPARENT
		return
	var source := image.get_pixelv(_hover)
	_source_swatch.color = source
	_result_swatch.color = transform_color(source, adjustment)


func _transform_at(image: Image, point: Vector2i) -> void:
	if not _in_bounds(image, point) or _visited.has(point):
		return
	_visited[point] = true
	var source := image.get_pixelv(point)
	if source.a <= 0.0:
		return
	var result := transform_color(source, adjustment)
	if result.is_equal_approx(source):
		return
	if image.has_method("set_pixelv_custom"):
		image.set_pixelv_custom(point, result)
	else:
		image.set_pixelv(point, result)
	_stroke_changed = true


func _finish_stroke(image: Image) -> void:
	if _stroke_changed and image != null and image.get("is_indexed"):
		image.convert_rgb_to_indexed()
	if _stroke_changed:
		_commit_undo()
	_clear_stroke()
	_update_preview()


func _commit_undo() -> void:
	var global = ExtensionsApi.general.get_global()
	global.canvas.update_selected_cels_textures(_stroke_project)
	var redo_data := {}
	_stroke_project.serialize_cel_undo_data(_stroke_cels, redo_data)
	_stroke_project.undo_redo.create_action("Easy Sparkle")
	_stroke_project.deserialize_cel_undo_data(redo_data, _undo_data)
	_stroke_project.undo_redo.add_do_method(
		global.undo_or_redo.bind(
			false, _stroke_project.current_frame, _stroke_project.current_layer
		)
	)
	_stroke_project.undo_redo.add_undo_method(
		global.undo_or_redo.bind(
			true, _stroke_project.current_frame, _stroke_project.current_layer
		)
	)
	_stroke_project.undo_redo.commit_action()


func _clear_stroke() -> void:
	_stroke_active = false
	_stroke_changed = false
	_visited.clear()
	_stroke_project = null
	_stroke_cels = []
	_undo_data = {}


func _stroke_image() -> Image:
	if _stroke_cels.is_empty():
		return null
	return _stroke_cels[0].get_image()


func _current_image() -> Image:
	var cel = ExtensionsApi.project.get_current_cel()
	if not cel is PixelCel:
		return null
	return cel.get_image()


func _in_bounds(image: Image, point: Vector2i) -> bool:
	return (
		point.x >= 0
		and point.y >= 0
		and point.x < image.get_width()
		and point.y < image.get_height()
	)


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
