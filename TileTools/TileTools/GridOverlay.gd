extends Node2D

var grid_size := Vector2i(20, 20)
var grid_color := Color(1.0, 1.0, 1.0, 0.15)


func _draw() -> void:
	var project: Variant = _get_current_project()
	if project == null:
		return
	var canvas_size: Vector2i = project.size
	for x in range(0, canvas_size.x + 1, grid_size.x):
		draw_line(Vector2(x, 0), Vector2(x, canvas_size.y), grid_color, 1.0)
	for y in range(0, canvas_size.y + 1, grid_size.y):
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), grid_color, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _get_current_project() -> Variant:
	var global: Variant = get_node_or_null("/root/Global")
	if global == null:
		return null
	return global.current_project
