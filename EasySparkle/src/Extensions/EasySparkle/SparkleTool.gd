extends Node

const SparkleColorTransform = preload(
	"res://src/Extensions/EasySparkle/SparkleColor.gd"
)
const SparkleRegionFinder = preload(
	"res://src/Extensions/EasySparkle/SparkleRegion.gd"
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
var _region_label: Label
var _canvas: Node2D
var _hover := Vector2i.ZERO

# The region targeted by the most recent click. Detection is read-only —
# nothing here ever writes to the image. Recoloring the region is out of
# scope for this tool revision and lands in a later change.
var _region_points: Array[Vector2i] = []
var _region_color := Color.TRANSPARENT
var _has_region := false


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

	_region_label = Label.new()
	_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_region_label)

	var hint := Label.new()
	hint.text = "Click a non-transparent pixel to target its connected, exact-color region."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_canvas = ExtensionsApi.general.get_canvas()
	load_config()
	_update_description()
	_update_preview()
	_update_region_status()


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


## A click targets the connected, exact-color region under the cursor and
## previews it. Nothing about this is destructive: unsupported cels,
## transparent pixels, and out-of-bounds clicks simply clear the preview.
func draw_start(pos: Vector2i) -> void:
	var project = ExtensionsApi.project.current_project
	if project == null:
		_clear_region()
		return
	var cel = ExtensionsApi.project.get_current_cel()
	if not cel is PixelCel:
		_clear_region()
		return
	var image: Image = cel.get_image()
	var result := SparkleRegionFinder.find_region(image, pos)
	if result.is_empty():
		_clear_region()
		return
	_region_points = result["points"]
	_region_color = result["color"]
	_has_region = true
	_update_region_status()


func draw_move(_pos: Vector2i) -> void:
	pass


func draw_end(_pos: Vector2i) -> void:
	pass


func cancel_tool() -> void:
	_clear_region()


func cursor_move(pos: Vector2i) -> void:
	_hover = pos
	_update_preview()


func draw_indicator(left: bool) -> void:
	if _canvas == null:
		return

	if _has_region:
		var global = ExtensionsApi.general.get_global()
		var region_color: Color = global.left_tool_color if left else global.right_tool_color
		region_color.a = 0.35
		for point in _region_points:
			_canvas.indicators.draw_rect(Rect2(Vector2(point), Vector2.ONE), region_color, true)

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


func _update_region_status() -> void:
	if _region_label == null:
		return
	if _has_region:
		var count := _region_points.size()
		_region_label.text = "Region: %d pixel%s selected." % [count, "" if count == 1 else "s"]
	else:
		_region_label.text = "No region selected."


func _clear_region() -> void:
	_region_points = []
	_region_color = Color.TRANSPARENT
	_has_region = false
	_update_region_status()


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
