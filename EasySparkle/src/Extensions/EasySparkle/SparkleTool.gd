extends Node

const SparklePalette = preload(
	"res://src/Extensions/EasySparkle/SparklePalette.gd"
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

var _region_label: Label
var _canvas: Node2D
var _hover := Vector2i.ZERO

# One labeled swatch per SparklePalette role, in SparklePalette.ROLE_ORDER.
var _palette_swatches: Array[ColorRect] = []

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

	var preview_label := Label.new()
	preview_label.text = "Sparkle palette preview (hovered pixel)"
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(preview_label)

	var palette_row := HBoxContainer.new()
	palette_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(palette_row)
	for role in SparklePalette.ROLE_ORDER:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		palette_row.add_child(column)
		_palette_swatches.append(_make_swatch(column))
		var caption := Label.new()
		caption.text = SparklePalette.role_name(role)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)

	_region_label = Label.new()
	_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_region_label)

	var hint := Label.new()
	hint.text = "Click a non-transparent pixel to target its connected, exact-color region."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_canvas = ExtensionsApi.general.get_canvas()
	load_config()
	_update_palette_preview()
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
	# The palette is derived on the fly from SparklePalette; there is
	# currently nothing about it that needs to be persisted per tool slot.
	return {}


func set_config(_config: Dictionary) -> void:
	pass


func update_config() -> void:
	_update_palette_preview()


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
	_update_palette_preview()


func draw_indicator(left: bool) -> void:
	if _canvas == null:
		return

	if _has_region:
		var global = ExtensionsApi.general.get_global()
		var region_color: Color = global.left_tool_color if left else global.right_tool_color
		region_color.a = 0.35
		for point in _region_points:
			_canvas.indicators.draw_rect(Rect2(Vector2(point), Vector2.ONE), region_color, true)


func draw_preview() -> void:
	pass


## Refreshes the tool-options palette preview swatches from the pixel
## currently under the cursor. Every role in SparklePalette.ROLE_ORDER gets
## its own swatch, so the full six-role palette is always visible together,
## not just whichever role a user happens to pick. This never reads or
## writes anything but the swatch colors themselves -- no image is touched.
func _update_palette_preview() -> void:
	if _palette_swatches.is_empty():
		return
	var image := _current_image()
	var valid := image != null and _in_bounds(image, _hover)
	if not valid:
		for swatch in _palette_swatches:
			swatch.color = Color.TRANSPARENT
		return
	var source := image.get_pixelv(_hover)
	var palette := SparklePalette.build(source)
	for i in SparklePalette.ROLE_ORDER.size():
		var role = SparklePalette.ROLE_ORDER[i]
		_palette_swatches[i].color = palette[role]


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
