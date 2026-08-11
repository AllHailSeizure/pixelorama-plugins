extends Node

var is_moving := false
var kname: String
var tool_slot = null
var cursor_text := ""

var grid_size := Vector2i(20, 20)
var _selected_cell := Vector2i(-1, -1)
var _hover_cell := Vector2i.ZERO
var _move_start_pos := Vector2i.ZERO
var _canvas: Node2D

var _width_spin: SpinBox
var _height_spin: SpinBox


func _ready() -> void:
	kname = name.replace(" ", "_").to_lower()
	if tool_slot != null:
		if tool_slot.name == "Left tool":
			$ColorRect.color = ExtensionsApi.general.get_global().left_tool_color
		else:
			$ColorRect.color = ExtensionsApi.general.get_global().right_tool_color

	var width_label := Label.new()
	width_label.text = "Grid Width (px):"
	add_child(width_label)
	_width_spin = SpinBox.new()
	_width_spin.min_value = 1
	_width_spin.max_value = 512
	_width_spin.value = grid_size.x
	_width_spin.suffix = "px"
	_width_spin.value_changed.connect(_on_width_changed)
	add_child(_width_spin)

	var height_label := Label.new()
	height_label.text = "Grid Height (px):"
	add_child(height_label)
	_height_spin = SpinBox.new()
	_height_spin.min_value = 1
	_height_spin.max_value = 512
	_height_spin.value = grid_size.y
	_height_spin.suffix = "px"
	_height_spin.value_changed.connect(_on_height_changed)
	add_child(_height_spin)

	_canvas = ExtensionsApi.general.get_canvas()
	load_config()
	_update_grid_overlay()


func _exit_tree() -> void:
	_remove_grid_overlay()


func save_config() -> void:
	if tool_slot == null:
		return
	var config := get_config()
	ExtensionsApi.general.get_config_file().set_value(tool_slot.kname, kname, config)


func load_config() -> void:
	if tool_slot == null:
		return
	var value = ExtensionsApi.general.get_config_file().get_value(tool_slot.kname, kname, {})
	set_config(value)
	update_config()


func get_config() -> Dictionary:
	return {"grid_width": grid_size.x, "grid_height": grid_size.y}


func set_config(config: Dictionary) -> void:
	grid_size.x = config.get("grid_width", grid_size.x)
	grid_size.y = config.get("grid_height", grid_size.y)


func update_config() -> void:
	if _width_spin:
		_width_spin.value = grid_size.x
	if _height_spin:
		_height_spin.value = grid_size.y


func pos_to_cell(pos: Vector2) -> Vector2i:
	var cell_x := int(pos.x) / grid_size.x
	var cell_y := int(pos.y) / grid_size.y
	if pos.x < 0:
		cell_x -= 1
	if pos.y < 0:
		cell_y -= 1
	return Vector2i(cell_x, cell_y)


func cell_to_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell * grid_size), Vector2(grid_size))


func snap_to_grid(pos: Vector2) -> Vector2i:
	var cell := pos_to_cell(pos)
	return cell * grid_size


func draw_start(pos: Vector2) -> void:
	var cell := pos_to_cell(pos)
	if cell == _selected_cell and _selected_cell != Vector2i(-1, -1):
		is_moving = true
		_move_start_pos = snap_to_grid(pos)
		return
	is_moving = false
	_selected_cell = cell
	# Directly reset selection map — API clear_selection can fail silently
	# and operation 0 is ADD (no REPLACE exists), so we must clear first
	var project = ExtensionsApi.project.current_project
	if project != null:
		project.selection_map.crop(project.size.x, project.size.y)
		project.selection_map.fill(Color(0, 0, 0, 0))
	var rect := cell_to_rect(cell)
	ExtensionsApi.selection.select_rect(rect, 0)


func draw_move(pos: Vector2) -> void:
	if not is_moving:
		return
	var snapped := snap_to_grid(pos)
	var delta := snapped - _move_start_pos
	if delta == Vector2i.ZERO:
		return
	ExtensionsApi.selection.move_selection(delta, true, false)
	_move_start_pos = snapped
	_selected_cell += Vector2i(delta.x / grid_size.x, delta.y / grid_size.y)


func draw_end(pos: Vector2) -> void:
	is_moving = false


func cursor_move(pos: Vector2) -> void:
	_hover_cell = pos_to_cell(pos)


func draw_indicator(left: bool) -> void:
	if _canvas == null:
		return
	var rect := cell_to_rect(_hover_cell)
	var global = ExtensionsApi.general.get_global()
	var color: Color = global.left_tool_color if left else global.right_tool_color
	color.a = 0.3
	_canvas.indicators.draw_rect(rect, color, false, 2.0)


func draw_preview() -> void:
	pass


func _update_grid_overlay() -> void:
	var main_nodes = ExtensionsApi.get_main_nodes("TileTools")
	if main_nodes.is_empty():
		return
	main_nodes[0].show_grid_overlay(grid_size)


func _remove_grid_overlay() -> void:
	var main_nodes = ExtensionsApi.get_main_nodes("TileTools")
	if main_nodes.is_empty():
		return
	main_nodes[0].hide_grid_overlay()


func _on_width_changed(value: float) -> void:
	grid_size.x = int(value)
	update_config()
	save_config()
	_update_grid_overlay()


func _on_height_changed(value: float) -> void:
	grid_size.y = int(value)
	update_config()
	save_config()
	_update_grid_overlay()
